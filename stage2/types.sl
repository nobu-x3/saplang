import arena;
import ast;
import diag;
import sys;
import token;

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
    diag::DiagBuf*  diag;       // nullable; layout/cycle errors reported here when set
}

export fn void typer_init(TypeInterner* it, arena::Arena* a, diag::DiagBuf* d, u64 initial_cap) {
    u64 bytes = initial_cap * sizeof(TypeBucket);
    it.buckets = {(TypeBucket*)arena::alloc(a, bytes), initial_cap};
    sys::memset(it.buckets.ptr, 0, bytes);
    it.count = 0;
    it.cap   = initial_cap;
    it.arena = a;
    it.diag  = d;
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

export fn Type* reintern_from(TypeInterner* dst, Type* foreign) {
    if(foreign == null) { return null; }
    switch(foreign.kind) {
        case TypeKind::Primitive:    { return foreign; }
        case TypeKind::ComptimeType: { return foreign; }
        case TypeKind::Pointer: {
            Type* p = reintern_from(dst, foreign.data.pointee);
            bool is_const = ((u8)foreign.flags & (u8)LayoutFlags::Const) != 0;
            return intern_pointer(dst, p, is_const);
        }
        case TypeKind::Array: {
            Type* e = reintern_from(dst, foreign.data.array.elem);
            return intern_array(dst, e, foreign.data.array.count);
        }
        case TypeKind::Slice: {
            Type* e = reintern_from(dst, foreign.data.slice_elem);
            return intern_slice(dst, e);
        }
        case TypeKind::FnPtr: {
            Type* r = reintern_from(dst, foreign.data.fn_ptr.ret);
            Type*[] ps = reintern_params(dst, foreign.data.fn_ptr.params);
            return intern_fn_ptr(dst, r, ps, foreign.data.fn_ptr.is_variadic);
        }
        case TypeKind::Struct: {
            Type* t = intern_struct(dst, foreign.data.struct_decl);
            propagate_opaque(t, foreign);
            return t;
        }
        case TypeKind::Union: {
            Type* t = intern_union(dst, foreign.data.union_decl);
            propagate_opaque(t, foreign);
            return t;
        }
        case TypeKind::Enum: {
            Type* t = intern_enum(dst, foreign.data.enum_decl);
            propagate_opaque(t, foreign);
            return t;
        }
        else { return null; }
    }
    return null;
}

fn void propagate_opaque(Type* interned, Type* foreign) {
    if(((u8)foreign.flags & (u8)LayoutFlags::Opaque) != 0) {
        interned.flags = (LayoutFlags)((u8)interned.flags | (u8)LayoutFlags::Opaque);
    }
}

// sizeof/alignof
export fn u32 size_of(TypeInterner* it, Type* type) {
    if(((u8)type.flags & (u8)LayoutFlags::Opaque) != 0) {
        if(it.diag != null) {
            diag::report(it.diag, it.arena, decl_src_pos(type), "cannot take size of opaque type");
        }
        return 0;
    }
    if(((u8)type.flags & (u8)LayoutFlags::Computed) != 0) {
        return type.size;
    }
    compute_layout(it, type);
    return type.size;
}

export fn u32 align_of(TypeInterner* it, Type* type) {
    if(((u8)type.flags & (u8)LayoutFlags::Opaque) != 0) {
        if(it.diag != null) {
            diag::report(it.diag, it.arena, decl_src_pos(type), "cannot take alignment of opaque type");
        }
        return 0;
    }
    if(((u8)type.flags & (u8)LayoutFlags::Computed) != 0) {
        return type.align;
    }
    compute_layout(it, type);
    return type.align;
}

fn void compute_layout(TypeInterner* it, Type* type) {
    if(((u8)type.flags & (u8)LayoutFlags::Computed) != 0) { return; }
    if(((u8)type.flags & (u8)LayoutFlags::InProgress) != 0) {
        if(it.diag != null) {
            diag::report(it.diag, it.arena, decl_src_pos(type),
                         "type has infinite size (cycle through non-pointer fields)");
        }
        return;
    }
    type.flags = (LayoutFlags)((u8)type.flags | (u8)LayoutFlags::InProgress);

    u32 size = 0;
    u32 align = 1;
    switch(type.kind) {
        case TypeKind::Primitive: {
            size  = type.size;
            align = type.align;
        }
        case TypeKind::Pointer: { size = 8;  align = 8; }
        case TypeKind::FnPtr:   { size = 8;  align = 8; }
        case TypeKind::Slice:   { size = 16; align = 8; }
        case TypeKind::Array: {
            Type* elem = type.data.array.elem;
            if(layout_field(it, elem)) {
                size  = elem.size * (u32)type.data.array.count;
                align = elem.align;
            }
        }
        case TypeKind::Struct: {
            ast::StructDeclNode* decl = (ast::StructDeclNode*)type.data.struct_decl;
            Layout* new_layout = (Layout*)arena::alloc(it.arena, sizeof(Layout));
            u32* offsets = (u32*)arena::alloc(it.arena, decl.fields.len * sizeof(u32));
            new_layout.offsets = {offsets, decl.fields.len};
            u32 cursor = 0;
            u32 max_align = 1;
            for(u64 i = 0; i < decl.fields.len; i += 1) {
                Type* field_type = reintern_from(it, (Type*)decl.fields[i].resolved_type);
                if(!layout_field(it, field_type)) {
                    offsets[i] = cursor;
                    continue;
                }
                u32 field_align = field_type.align;
                u32 field_size  = field_type.size;
                cursor = (u32)arena::align_up((u64)cursor, (u64)field_align);
                offsets[i] = cursor;
                cursor += field_size;
                if(field_align > max_align) { max_align = field_align; }
            }
            size  = (u32)arena::align_up((u64)cursor, (u64)max_align);
            align = max_align;
            type.layout = new_layout;
        }
        case TypeKind::Union: {
            ast::UnionDeclNode* decl = (ast::UnionDeclNode*)type.data.union_decl;
            Layout* new_layout = (Layout*)arena::alloc(it.arena, sizeof(Layout));
            u32* offsets = (u32*)arena::alloc(it.arena, decl.fields.len * sizeof(u32));
            sys::memset(offsets, 0, decl.fields.len * sizeof(u32));
            new_layout.offsets = {offsets, decl.fields.len};
            u32 max_size  = 0;
            u32 max_align = 1;
            for(u64 i = 0; i < decl.fields.len; i += 1) {
                Type* field_type = reintern_from(it, (Type*)decl.fields[i].resolved_type);
                if(!layout_field(it, field_type)) { continue; }
                u32 field_align = field_type.align;
                u32 field_size  = field_type.size;
                if(field_size  > max_size)  { max_size  = field_size; }
                if(field_align > max_align) { max_align = field_align; }
            }
            size  = (u32)arena::align_up((u64)max_size, (u64)max_align);
            align = max_align;
            type.layout = new_layout;
        }
        case TypeKind::Enum: {
            Type* base = reintern_from(it, enum_base_type(type));
            if(layout_field(it, base)) {
                size  = base.size;
                align = base.align;
            }
        }
        case TypeKind::ComptimeType: {
            if(it.diag != null) {
                diag::report(it.diag, it.arena, 0, "Type has no runtime size");
            }
            size  = 0;
            align = 0;
        }
        else { }
    }

    type.size  = size;
    type.align = align;
    type.flags = (LayoutFlags)(((u8)type.flags | (u8)LayoutFlags::Computed) & ~(u8)LayoutFlags::InProgress);
}

fn bool layout_field(TypeInterner* it, Type* field_type) {
    if(field_type == null) { return false; }
    if(((u8)field_type.flags & (u8)LayoutFlags::Opaque) != 0) {
        if(it.diag != null) {
            diag::report(it.diag, it.arena, decl_src_pos(field_type),
                         "cannot take size of opaque type");
        }
        return false;
    }
    compute_layout(it, field_type);
    return true;
}

fn u32 decl_src_pos(Type* t) {
    if(t.kind == TypeKind::Struct) { return ((ast::StructDeclNode*)t.data.struct_decl).h.src_pos; }
    if(t.kind == TypeKind::Union)  { return ((ast::UnionDeclNode*) t.data.union_decl ).h.src_pos; }
    if(t.kind == TypeKind::Enum)   { return ((ast::EnumDeclNode*)  t.data.enum_decl  ).h.src_pos; }
    return 0;
}

fn Type*[] reintern_params(TypeInterner* dst, Type*[] src) {
    u64 bytes = src.len * sizeof(Type*);
    Type** mem = (Type**)arena::alloc(dst.arena, bytes);
    for(u64 i = 0; i < src.len; i += 1) {
        mem[i] = reintern_from(dst, src[i]);
    }
    return {mem, src.len};
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

PrimitiveTable PRIM;
bool prim_table_inited = false;

fn void ensure_prim_init() {
    if(prim_table_inited) { return; }
    build_primitive_table();
}

fn void build_primitive_table() {
    sys::memset(&PRIM, 0, sizeof(PrimitiveTable));
    init_prim(&PRIM.i8_,   PrimitiveKind::I8,   1, 1);
    init_prim(&PRIM.i16_,  PrimitiveKind::I16,  2, 2);
    init_prim(&PRIM.i32_,  PrimitiveKind::I32,  4, 4);
    init_prim(&PRIM.i64_,  PrimitiveKind::I64,  8, 8);
    init_prim(&PRIM.u8_,   PrimitiveKind::U8,   1, 1);
    init_prim(&PRIM.u16_,  PrimitiveKind::U16,  2, 2);
    init_prim(&PRIM.u32_,  PrimitiveKind::U32,  4, 4);
    init_prim(&PRIM.u64_,  PrimitiveKind::U64,  8, 8);
    init_prim(&PRIM.f32_,  PrimitiveKind::F32,  4, 4);
    init_prim(&PRIM.f64_,  PrimitiveKind::F64,  8, 8);
    init_prim(&PRIM.bool_, PrimitiveKind::BOOL, 1, 1);
    init_prim(&PRIM.void_, PrimitiveKind::VOID, 0, 1);

    PRIM.type_.kind  = TypeKind::ComptimeType;
    PRIM.type_.flags = LayoutFlags::Computed;

    PRIM.null_ptr.kind  = TypeKind::Pointer;
    PRIM.null_ptr.size  = 8;
    PRIM.null_ptr.align = 8;
    PRIM.null_ptr.flags = LayoutFlags::Computed;
    PRIM.null_ptr.data.pointee = &PRIM.void_;

    prim_table_inited = true;
}

fn void init_prim(Type* t, PrimitiveKind p, u32 size, u32 align) {
    t.kind  = TypeKind::Primitive;
    t.prim  = p;
    t.size  = size;
    t.align = align;
    t.flags = LayoutFlags::Computed;
}

export fn Type* prim_i8 ()    { ensure_prim_init(); return &PRIM.i8_;   }
export fn Type* prim_i16()    { ensure_prim_init(); return &PRIM.i16_;  }
export fn Type* prim_i32()    { ensure_prim_init(); return &PRIM.i32_;  }
export fn Type* prim_i64()    { ensure_prim_init(); return &PRIM.i64_;  }
export fn Type* prim_u8 ()    { ensure_prim_init(); return &PRIM.u8_;   }
export fn Type* prim_u16()    { ensure_prim_init(); return &PRIM.u16_;  }
export fn Type* prim_u32()    { ensure_prim_init(); return &PRIM.u32_;  }
export fn Type* prim_u64()    { ensure_prim_init(); return &PRIM.u64_;  }
export fn Type* prim_f32()    { ensure_prim_init(); return &PRIM.f32_;  }
export fn Type* prim_f64()    { ensure_prim_init(); return &PRIM.f64_;  }
export fn Type* prim_bool()   { ensure_prim_init(); return &PRIM.bool_; }
export fn Type* prim_void()   { ensure_prim_init(); return &PRIM.void_; }
export fn Type* prim_type()   { ensure_prim_init(); return &PRIM.type_; }
export fn Type* prim_null_ptr() { ensure_prim_init(); return &PRIM.null_ptr; }

export fn Type* primitive(PrimitiveKind kind) {
    switch(kind) {
        case PrimitiveKind::I8:   { return prim_i8();  }
        case PrimitiveKind::I16:  { return prim_i16(); }
        case PrimitiveKind::I32:  { return prim_i32(); }
        case PrimitiveKind::I64:  { return prim_i64(); }
        case PrimitiveKind::U8:   { return prim_u8();  }
        case PrimitiveKind::U16:  { return prim_u16(); }
        case PrimitiveKind::U32:  { return prim_u32(); }
        case PrimitiveKind::U64:  { return prim_u64(); }
        case PrimitiveKind::F32:  { return prim_f32(); }
        case PrimitiveKind::F64:  { return prim_f64(); }
        case PrimitiveKind::BOOL: { return prim_bool();}
        case PrimitiveKind::VOID: { return prim_void();}
        else { return null; }
    }
    return null;
}

export fn PrimitiveKind get_primitive_kind_from_token(token::TokenKind k) {
    switch(k) {
        case token::TokenKind::I8:   { return PrimitiveKind::I8;   }
        case token::TokenKind::I16:  { return PrimitiveKind::I16;  }
        case token::TokenKind::I32:  { return PrimitiveKind::I32;  }
        case token::TokenKind::I64:  { return PrimitiveKind::I64;  }
        case token::TokenKind::U8:   { return PrimitiveKind::U8;   }
        case token::TokenKind::U16:  { return PrimitiveKind::U16;  }
        case token::TokenKind::U32:  { return PrimitiveKind::U32;  }
        case token::TokenKind::U64:  { return PrimitiveKind::U64;  }
        case token::TokenKind::F32:  { return PrimitiveKind::F32;  }
        case token::TokenKind::F64:  { return PrimitiveKind::F64;  }
        case token::TokenKind::BOOL: { return PrimitiveKind::BOOL; }
        case token::TokenKind::VOID: { return PrimitiveKind::VOID; }
        else { return PrimitiveKind::NONE; }
    }
    return PrimitiveKind::NONE;
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
