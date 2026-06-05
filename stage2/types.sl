import arena;
import ast;
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

// Conversions

export fn bool is_convertible(Type* src, Type* dst) {
    if (src == dst) { return true; }
    // array -> pointer (matching depth + element)
    if (is_array(src) && is_ptr(dst)) {
        Type* a_elem = src.data.array.elem;
        Type* p_pee  = dst.data.pointee;
        return a_elem == p_pee;
    }
    // array -> slice
    if (is_array(src) && is_slice(dst)) {
        return src.data.array.elem == dst.data.slice_elem;
    }
    // enum -> base
    if (src.kind == TypeKind::Enum && enum_base_type(src) == dst) { return true; }
    // integer widening, same signedness
    if (is_int(src) && is_int(dst)) {
        bool same_sign = is_signed_int(src) == is_signed_int(dst);
        return same_sign && int_rank(src) <= int_rank(dst);
    }
    // float widening
    if (is_float(src) && is_float(dst)) {
        if (src.prim == PrimitiveKind::F32 && dst.prim == PrimitiveKind::F64) { return true; }
        return false;
    }
    // pointer -> pointer (any pointee)
    if (is_ptr(src) && is_ptr(dst)) { return true; }
    // null -> any pointer or slice
    if (src == prim_null_ptr() && (is_ptr(dst) || is_slice(dst))) { return true; }
    return false;
}

export fn bool is_convertible_in_cond(Type* src) {
    if (is_bool(src)) { return true; }
    if (is_int(src))  { return true; }       // zero / non-zero
    if (is_ptr(src) || is_slice(src)) { return true; }  // null / non-null
    return false;
}

export fn bool int_lit_fits(u64 value, bool is_negative, Type* dst) {
    if (!is_int(dst)) { return false; }
    if (is_negative && is_unsigned_int(dst)) { return false; }
    u64 dst_max = int_max(dst);
    u64 dst_min_abs = int_min_abs(dst);    // for signed; 0 for unsigned
    if (is_negative) { return value <= dst_min_abs; }
    return value <= dst_max;
}

fn i32 int_rank(Type* t) {
    if(!is_int(t)) { return -1; }
    switch(t.prim) {
        case PrimitiveKind::I8:
        case PrimitiveKind::U8: { return 1; }
        case PrimitiveKind::I16:
        case PrimitiveKind::U16: { return 2; }
        case PrimitiveKind::I32:
        case PrimitiveKind::U32: { return 3; }
        case PrimitiveKind::I64:
        case PrimitiveKind::U64: { return 4; }
        else { return -1; }
    }
    return -1;
}

// Helpers
export fn bool is_int(Type* t) {
    return t.kind == TypeKind::Primitive
    && t.prim >= PrimitiveKind::I8 && t.prim <= PrimitiveKind::U64;
}

export fn bool is_signed_int(Type* t) {
    return t.kind == TypeKind::Primitive
    && t.prim >= PrimitiveKind::I8 && t.prim <= PrimitiveKind::I64;
}

export fn bool is_unsigned_int(Type* t) {
    return t.kind == TypeKind::Primitive
    && t.prim >= PrimitiveKind::U8 && t.prim <= PrimitiveKind::U64;
}

export fn bool is_float(Type* t) {
    return t.kind == TypeKind::Primitive
    && t.prim >= PrimitiveKind::F32 && t.prim <= PrimitiveKind::F64;
}

export fn bool is_bool(Type* t) {
    return t.kind == TypeKind::Primitive
    && t.prim == PrimitiveKind::BOOL;
}

export fn bool is_void(Type* t) {
    return t.kind == TypeKind::Primitive
    && t.prim == PrimitiveKind::VOID;
}

export fn bool is_slice(Type* t) {
    return t.kind == TypeKind::Slice;
}

export fn bool is_array(Type* t) {
    return t.kind == TypeKind::Array;
}

export fn bool is_ptr(Type* t) {
    return t.kind == TypeKind::Pointer;
}

export fn bool is_named(Type* t) {
    return t.kind == TypeKind::Struct || t.kind == TypeKind::Union || t.kind == TypeKind::Enum;
}

export fn bool is_comptime_type(Type* t) {
    return t.kind == TypeKind::ComptimeType;
}

export fn Type* enum_base_type(Type* type) {
    if(type.kind != TypeKind::Enum) { return null; }
    ast::EnumDeclNode* decl = (ast::EnumDeclNode*)type.data.enum_decl;
    if(decl == null || decl.base_type == null) { return null; }
    return (Type*)decl.base_type.h.ty;
}

Type NULL_PTR_STORAGE;

export fn Type* prim_null_ptr() {
    NULL_PTR_STORAGE.kind = TypeKind::Pointer;
    NULL_PTR_STORAGE.size = 8;
    NULL_PTR_STORAGE.align = 8;
    NULL_PTR_STORAGE.flags = LayoutFlags::Computed;
    return &NULL_PTR_STORAGE;
}

export fn u64 int_max(Type* t) {
    if(!is_int(t)) { return 0; }
    switch(t.prim) {
        case PrimitiveKind::I8:  { return 127; }
        case PrimitiveKind::I16: { return 32767; }
        case PrimitiveKind::I32: { return 2147483647; }
        case PrimitiveKind::I64: { return 9223372036854775807; }
        case PrimitiveKind::U8:  { return 255; }
        case PrimitiveKind::U16: { return 65535; }
        case PrimitiveKind::U32: { return 4294967295; }
        case PrimitiveKind::U64: { return 18446744073709551615; }
        else { return 0; }
    }
    return 0;
}

export fn u64 int_min_abs(Type* t) {
    if(!is_signed_int(t)) { return 0; }
    switch(t.prim) {
        case PrimitiveKind::I8:  { return 128; }
        case PrimitiveKind::I16: { return 32768; }
        case PrimitiveKind::I32: { return 2147483648; }
        case PrimitiveKind::I64: { return 9223372036854775808; }
        else { return 0; }
    }
    return 0;
}

// PRIVATE FUNCTIONS

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
