import arena;
import sys;

export enum TypeKind : u8 {
    Primitive,
        Pointer,
        Array,
        Slice,
        FnPtr,
        Struct,
        Union,
        Enum,
        ComptimeType,
}

export enum PrimitiveKind : u8 {
    NONE = 0,
         I8, I16, I32, I64,
         U8, U16, U32, U64,
         F32, F64,
         BOOL,
         VOID,
}

export struct ArrayInfo {
    Type* elem;
    u64   count;
}

export struct FnPtrInfo {
    Type*   ret;
    Type*[] params;
    bool    is_variadic;
}

export union TypeData {
    Type*       pointee;        // TypeKind::Pointer
    ArrayInfo   array;          // TypeKind::Array
    Type*       slice_elem;     // TypeKind::Slice
    FnPtrInfo   fn_ptr;         // TypeKind::FnPtr
    void*       struct_decl;    // ast::StructDeclNode*; void* breaks the types<->ast cycle
    void*       union_decl;     // ast::UnionDeclNode*
    void*       enum_decl;      // ast::EnumDeclNode*
}

export enum LayoutFlags : u8 {
    None = 0,
         Computed = 1,
         InProgress = 2,             // cycle detection
         Const = 4,
         Opaque = 8,                 // extern { opaque struct X; } — layout unknown
}

export struct Type {
    TypeKind        kind;
    PrimitiveKind   prim;       // NONE if not primitive
    LayoutFlags     flags;
    u32             size;       // cached bytes; valid only if LayoutFlags::Computed
    u32             align;      // cached; valid only if LayoutFlags::Computed
    Layout*         layout;     // struct/union field offsets; null until computed
    TypeData        data;
}

export struct Layout {
    u32[] offsets;              // one entry per field, in declaration order
}

export struct PrimitiveTable {
    Type i8_;  Type i16_; Type i32_; Type i64_;
    Type u8_;  Type u16_; Type u32_; Type u64_;
    Type f32_; Type f64_;
    Type bool_;
    Type void_;
    Type type_;
    Type null_ptr;
}

export struct TypeBucket {
    u32   hash;                 // 0 = empty slot
    Type* type;
}

export struct TypeInterner {
    TypeBucket[]    buckets;
    u64             count;
    u64             cap;        // power of 2
    arena::Arena*   arena;
}

export fn void typer_init(TypeInterner* it, arena::Arena* a, u64 initial_cap) {
    u64 bytes = initial_cap * sizeof(TypeBucket);
    it.buckets = {(TypeBucket*)arena::alloc(a, bytes), initial_cap};
    sys::memset(it.buckets.ptr, 0, bytes);
    it.count = 0;
    it.cap   = initial_cap;
    it.arena = a;
}

export fn Type* intern_pointer(TypeInterner* it, Type* pointee, bool is_const) {
    u32 hash = hash_pointer(pointee, is_const);
    u64 mask = it.cap - 1;
    u64 idx = (u64)hash & mask;
    while(it.buckets[idx].hash != 0) {
        Type* cur = it.buckets[idx].type;
        bool cur_const = ((u8)cur.flags & (u8)LayoutFlags::Const) != 0;
        bool const_match = is_const == cur_const;
        if(it.buckets[idx].hash == hash
                && const_match
                && cur.kind == TypeKind::Pointer
                && cur.data.pointee == pointee) {
            return cur;
        }
        idx = (idx + 1) & mask;
    }
    Type* type = (Type*)arena::alloc(it.arena, sizeof(Type));
    sys::memset(type, 0, sizeof(Type));
    type.kind = TypeKind::Pointer;
    type.size = 8;
    type.align = 8;
    type.flags = LayoutFlags::Computed;
    if(is_const) {
        type.flags = (LayoutFlags)((u8)type.flags | (u8)LayoutFlags::Const);
    }
    type.data.pointee = pointee;
    return install(it, hash, type);
}

export fn Type* intern_array(TypeInterner* it, Type* elem, u64 count) {
    u32 hash = hash_array(elem, count);
    u64 mask = it.cap - 1;
    u64 idx = (u64)hash & mask;
    while(it.buckets[idx].hash != 0) {
        Type* cur = it.buckets[idx].type;
        if(it.buckets[idx].hash == hash
                && cur.kind == TypeKind::Array
                && cur.data.array.count == count
                && cur.data.array.elem == elem) {
            return cur;
        }
        idx = (idx + 1) & mask;
    }
    Type* type = (Type*)arena::alloc(it.arena, sizeof(Type));
    sys::memset(type, 0, sizeof(Type));
    type.kind = TypeKind::Array;
    type.data.array.elem = elem;
    type.data.array.count = count;
    return install(it, hash, type);
}

export fn Type* intern_slice(TypeInterner* it, Type* elem) {
    u32 hash = hash_slice(elem);
    u64 mask = it.cap - 1;
    u64 idx = (u64)hash & mask;
    while(it.buckets[idx].hash != 0) {
        Type* cur = it.buckets[idx].type;
        if(it.buckets[idx].hash == hash
                && cur.kind == TypeKind::Slice
                && cur.data.slice_elem == elem) {
            return cur;
        }
        idx = (idx + 1) & mask;
    }
    Type* type = (Type*)arena::alloc(it.arena, sizeof(Type));
    sys::memset(type, 0, sizeof(Type));
    type.kind = TypeKind::Slice;
    type.size = 16;
    type.align = 8;
    type.flags = LayoutFlags::Computed;
    type.data.slice_elem = elem;
    return install(it, hash, type);
}

export fn Type* intern_fn_ptr(TypeInterner* it, Type* ret, Type*[] params, bool variadic) {
    u32 hash = hash_fn_ptr(ret, params, variadic);
    u64 mask = it.cap - 1;
    u64 idx = (u64)hash & mask;
    while(it.buckets[idx].hash != 0) {
        Type* cur = it.buckets[idx].type;
        if(it.buckets[idx].hash == hash
                && cur.kind == TypeKind::FnPtr
                && cur.data.fn_ptr.ret == ret
                && cur.data.fn_ptr.is_variadic == variadic
                && fn_params_equal(cur.data.fn_ptr.params, params)) {
            return cur;
        }
        idx = (idx + 1) & mask;
    }
    Type* type = (Type*)arena::alloc(it.arena, sizeof(Type));
    sys::memset(type, 0, sizeof(Type));
    type.kind = TypeKind::FnPtr;
    type.size = 8;
    type.align = 8;
    type.flags = LayoutFlags::Computed;
    type.data.fn_ptr.is_variadic = variadic;
    type.data.fn_ptr.ret = ret;
    type.data.fn_ptr.params = copy_type_slice(it.arena, params);
    return install(it, hash, type);
}

export fn Type* intern_struct(TypeInterner* it, void* decl) {    // ast::StructDeclNode*
    u32 hash = hash_decl(decl, 0x10000005);
    u64 mask = it.cap - 1;
    u64 idx  = (u64)hash & mask;
    while (it.buckets[idx].hash != 0) {
        Type* cur = it.buckets[idx].type;
        if (it.buckets[idx].hash == hash
                && cur.kind == TypeKind::Struct
                && cur.data.struct_decl == decl) {
            return cur;
        }
        idx = (idx + 1) & mask;
    }
    Type* t = (Type*)arena::alloc(it.arena, sizeof(Type));
    sys::memset(t, 0, sizeof(Type));
    t.kind = TypeKind::Struct;
    t.data.struct_decl = decl;
    return install(it, hash, t);
}

export fn Type* intern_union(TypeInterner* it, void* decl) {    // ast::UnionDeclNode*
    u32 hash = hash_decl(decl, 0x10000006);
    u64 mask = it.cap - 1;
    u64 idx  = (u64)hash & mask;
    while (it.buckets[idx].hash != 0) {
        Type* cur = it.buckets[idx].type;
        if (it.buckets[idx].hash == hash
                && cur.kind == TypeKind::Union
                && cur.data.union_decl == decl) {
            return cur;
        }
        idx = (idx + 1) & mask;
    }
    Type* t = (Type*)arena::alloc(it.arena, sizeof(Type));
    sys::memset(t, 0, sizeof(Type));
    t.kind = TypeKind::Union;
    t.data.union_decl = decl;
    return install(it, hash, t);
}

export fn Type* intern_enum(TypeInterner* it, void* decl) {    // ast::EnumDeclNode*
    u32 hash = hash_decl(decl, 0x10000007);
    if(hash == 0) { hash = 1; }
    u64 mask = it.cap - 1;
    u64 idx  = (u64)hash & mask;
    while (it.buckets[idx].hash != 0) {
        Type* cur = it.buckets[idx].type;
        if (it.buckets[idx].hash == hash
                && cur.kind == TypeKind::Enum
                && cur.data.enum_decl == decl) {
            return cur;
        }
        idx = (idx + 1) & mask;
    }
    Type* t = (Type*)arena::alloc(it.arena, sizeof(Type));
    sys::memset(t, 0, sizeof(Type));
    t.kind = TypeKind::Enum;
    t.data.enum_decl = decl;
    return install(it, hash, t);
}

fn Type* install(TypeInterner* it, u32 hash, Type* t) {
    if ((it.count + 1) * 10 > it.cap * 7) { typer_grow(it); }
    u64 mask = it.cap - 1;
    u64 idx  = (u64)hash & mask;
    while (it.buckets[idx].hash != 0) { idx = (idx + 1) & mask; }
    it.buckets[idx].hash = hash;
    it.buckets[idx].type = t;
    it.count += 1;
    return t;
}

fn bool fn_params_equal(Type*[] a, Type*[] b) {
    if (a.len != b.len) { return false; }
    for (u64 i = 0; i < a.len; i += 1) {
        if (a[i] != b[i]) { return false; }
    }
    return true;
}

fn Type*[] copy_type_slice(arena::Arena* a, Type*[] src) {
    u64 bytes = src.len * sizeof(Type*);
    Type** mem = (Type**)arena::alloc(a, bytes);
    sys::memcpy(mem, src.ptr, bytes);
    return {mem, src.len};
}

fn void typer_grow(TypeInterner* it) {
    TypeBucket[] old = it.buckets;
    u64 new_cap = it.cap * 2;
    u64 bytes   = new_cap * sizeof(TypeBucket);
    it.buckets = {(TypeBucket*)arena::alloc(it.arena, bytes), new_cap};
    sys::memset(it.buckets.ptr, 0, bytes);
    it.cap   = new_cap;
    it.count = 0;
    u64 mask = new_cap - 1;
    for (u64 i = 0; i < old.len; i += 1) {
        if (old[i].hash == 0) { continue; }
        u64 idx = (u64)old[i].hash & mask;
        while (it.buckets[idx].hash != 0) { idx = (idx + 1) & mask; }
        it.buckets[idx] = old[i];
        it.count += 1;
    }
}

fn u32 hash_ptr(void* p) {
    u64 m = (u64)p * 0x9E3779B97F4A7C15;
    return (u32)(m >> 32);
}

fn u32 hash_array(Type* elem, u64 count) {
    u32 h = hash_ptr(elem) ^ 0x10000002;
    h ^= (u32)((count * 0x9E3779B97F4A7C15) >> 32);
    if (h == 0) { h = 1; }
    return h;
}

fn u32 hash_slice(Type* elem) {
    u32 h = hash_ptr(elem) ^ 0x10000003;
    if (h == 0) { h = 1; }
    return h;
}

fn u32 hash_fn_ptr(Type* ret, Type*[] params, bool is_variadic) {
    u32 h = hash_ptr(ret) ^ 0x10000004;
    for (u64 i = 0; i < params.len; i += 1) {
        h = h * 31 + hash_ptr(params[i]);
    }
    h ^= (u32)params.len;
    if (is_variadic) { h ^= 0x80000000; }
    if (h == 0) { h = 1; }
    return h;
}

fn u32 hash_pointer(Type* pointee, bool is_const) {
    u32 h = hash_ptr(pointee) ^ 0x10000001;
    if (is_const) { h ^= 0xC0000000; }
    if (h == 0) { h = 1; }
    return h;
}

fn u32 hash_decl(void* decl, u32 disc) {
    u32 h = hash_ptr(decl) ^ disc;
    if (h == 0) { h = 1; }
    return h;
}
