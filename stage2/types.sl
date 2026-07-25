import arena;
import ast;
import diag;
import mutex;
import symbol;
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
    Ty* elem;
    u64   count;
}

export struct FnPtrInfo {
    Ty*   ret;
    Ty*[] params;
    bool    is_variadic;
}

export union TypeData {
    Ty*       pointee;        // TypeKind::Pointer
    ArrayInfo   array;          // TypeKind::Array
    Ty*       slice_elem;     // TypeKind::Slice
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

export struct Ty {
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
    Ty i8_;  Ty i16_; Ty i32_; Ty i64_;
    Ty u8_;  Ty u16_; Ty u32_; Ty u64_;
    Ty f32_; Ty f64_;
    Ty bool_;
    Ty void_;
    Ty type_;
    Ty null_ptr;
}

export struct TypeBucket {
    u32   hash;                 // 0 = empty slot
    Ty* type;
}

export struct TypeInterner {
    TypeBucket[]    buckets;
    u64             count;
    u64             cap;        // power of 2
    arena::Arena*   arena;
    mutex::Mutex    lock;       // guards intern + lazy layout computation
}

// Process-global; reached only through acquire()/release() or the self-locking wrappers.
TypeInterner GLOBAL_TYPER;

export fn void typer_init(arena::Arena* a, u64 initial_cap) {
    u64 bytes = initial_cap * sizeof(TypeBucket);
    GLOBAL_TYPER.buckets = {(TypeBucket*)arena::alloc(a, bytes), initial_cap};
    sys::memset(GLOBAL_TYPER.buckets.ptr, 0, bytes);
    GLOBAL_TYPER.count = 0;
    GLOBAL_TYPER.cap   = initial_cap;
    GLOBAL_TYPER.arena = a;
    mutex::create(&GLOBAL_TYPER.lock);
}

export fn TypeInterner* acquire() {
    mutex::lock(&GLOBAL_TYPER.lock);
    return &GLOBAL_TYPER;
}

export fn void release() {
    mutex::unlock(&GLOBAL_TYPER.lock);
}

export fn Ty* intern_pointer(Ty* pointee, bool is_const) {
    TypeInterner* it = types::acquire();
    Ty* t = _intern_pointer(it, pointee, is_const);
    types::release();
    return t;
}

fn Ty* _intern_pointer(TypeInterner* it, Ty* pointee, bool is_const) {
    u32 hash = hash_pointer(pointee, is_const);
    u64 mask = it.cap - 1;
    u64 idx = (u64)hash & mask;
    while(it.buckets[idx].hash != 0) {
        Ty* cur = it.buckets[idx].type;
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
    Ty* type = (Ty*)arena::alloc(it.arena, sizeof(Ty));
    sys::memset(type, 0, sizeof(Ty));
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

export fn Ty* intern_array(Ty* elem, u64 count) {
    TypeInterner* it = types::acquire();
    Ty* t = _intern_array(it, elem, count);
    types::release();
    return t;
}

fn Ty* _intern_array(TypeInterner* it, Ty* elem, u64 count) {
    u32 hash = hash_array(elem, count);
    u64 mask = it.cap - 1;
    u64 idx = (u64)hash & mask;
    while(it.buckets[idx].hash != 0) {
        Ty* cur = it.buckets[idx].type;
        if(it.buckets[idx].hash == hash
                && cur.kind == TypeKind::Array
                && cur.data.array.count == count
                && cur.data.array.elem == elem) {
            return cur;
        }
        idx = (idx + 1) & mask;
    }
    Ty* type = (Ty*)arena::alloc(it.arena, sizeof(Ty));
    sys::memset(type, 0, sizeof(Ty));
    type.kind = TypeKind::Array;
    type.data.array.elem = elem;
    type.data.array.count = count;
    return install(it, hash, type);
}

export fn Ty* intern_slice(Ty* elem) {
    TypeInterner* it = types::acquire();
    Ty* t = _intern_slice(it, elem);
    types::release();
    return t;
}

fn Ty* _intern_slice(TypeInterner* it, Ty* elem) {
    u32 hash = hash_slice(elem);
    u64 mask = it.cap - 1;
    u64 idx = (u64)hash & mask;
    while(it.buckets[idx].hash != 0) {
        Ty* cur = it.buckets[idx].type;
        if(it.buckets[idx].hash == hash
                && cur.kind == TypeKind::Slice
                && cur.data.slice_elem == elem) {
            return cur;
        }
        idx = (idx + 1) & mask;
    }
    Ty* type = (Ty*)arena::alloc(it.arena, sizeof(Ty));
    sys::memset(type, 0, sizeof(Ty));
    type.kind = TypeKind::Slice;
    type.size = 16;
    type.align = 8;
    type.flags = LayoutFlags::Computed;
    type.data.slice_elem = elem;
    return install(it, hash, type);
}

export fn Ty* intern_fn_ptr(Ty* ret, Ty*[] params, bool variadic) {
    TypeInterner* it = types::acquire();
    Ty* t = _intern_fn_ptr(it, ret, params, variadic);
    types::release();
    return t;
}

fn Ty* _intern_fn_ptr(TypeInterner* it, Ty* ret, Ty*[] params, bool variadic) {
    u32 hash = hash_fn_ptr(ret, params, variadic);
    u64 mask = it.cap - 1;
    u64 idx = (u64)hash & mask;
    while(it.buckets[idx].hash != 0) {
        Ty* cur = it.buckets[idx].type;
        if(it.buckets[idx].hash == hash
                && cur.kind == TypeKind::FnPtr
                && cur.data.fn_ptr.ret == ret
                && cur.data.fn_ptr.is_variadic == variadic
                && fn_params_equal(cur.data.fn_ptr.params, params)) {
            return cur;
        }
        idx = (idx + 1) & mask;
    }
    Ty* type = (Ty*)arena::alloc(it.arena, sizeof(Ty));
    sys::memset(type, 0, sizeof(Ty));
    type.kind = TypeKind::FnPtr;
    type.size = 8;
    type.align = 8;
    type.flags = LayoutFlags::Computed;
    type.data.fn_ptr.is_variadic = variadic;
    type.data.fn_ptr.ret = ret;
    type.data.fn_ptr.params = copy_type_slice(it.arena, params);
    return install(it, hash, type);
}

export fn Ty* intern_struct(void* decl) {    // ast::StructDeclNode*
    TypeInterner* it = types::acquire();
    Ty* t = _intern_struct(it, decl);
    types::release();
    return t;
}

fn Ty* _intern_struct(TypeInterner* it, void* decl) {
    u32 hash = hash_decl(decl, 0x10000005);
    u64 mask = it.cap - 1;
    u64 idx  = (u64)hash & mask;
    while (it.buckets[idx].hash != 0) {
        Ty* cur = it.buckets[idx].type;
        if (it.buckets[idx].hash == hash
                && cur.kind == TypeKind::Struct
                && cur.data.struct_decl == decl) {
            return cur;
        }
        idx = (idx + 1) & mask;
    }
    Ty* t = (Ty*)arena::alloc(it.arena, sizeof(Ty));
    sys::memset(t, 0, sizeof(Ty));
    t.kind = TypeKind::Struct;
    t.data.struct_decl = decl;
    return install(it, hash, t);
}

export fn Ty* intern_union(void* decl) {    // ast::UnionDeclNode*
    TypeInterner* it = types::acquire();
    Ty* t = _intern_union(it, decl);
    types::release();
    return t;
}

fn Ty* _intern_union(TypeInterner* it, void* decl) {
    u32 hash = hash_decl(decl, 0x10000006);
    u64 mask = it.cap - 1;
    u64 idx  = (u64)hash & mask;
    while (it.buckets[idx].hash != 0) {
        Ty* cur = it.buckets[idx].type;
        if (it.buckets[idx].hash == hash
                && cur.kind == TypeKind::Union
                && cur.data.union_decl == decl) {
            return cur;
        }
        idx = (idx + 1) & mask;
    }
    Ty* t = (Ty*)arena::alloc(it.arena, sizeof(Ty));
    sys::memset(t, 0, sizeof(Ty));
    t.kind = TypeKind::Union;
    t.data.union_decl = decl;
    return install(it, hash, t);
}

export fn Ty* intern_enum(void* decl) {    // ast::EnumDeclNode*
    TypeInterner* it = types::acquire();
    Ty* t = _intern_enum(it, decl);
    types::release();
    return t;
}

fn Ty* _intern_enum(TypeInterner* it, void* decl) {
    u32 hash = hash_decl(decl, 0x10000007);
    if(hash == 0) { hash = 1; }
    u64 mask = it.cap - 1;
    u64 idx  = (u64)hash & mask;
    while (it.buckets[idx].hash != 0) {
        Ty* cur = it.buckets[idx].type;
        if (it.buckets[idx].hash == hash
                && cur.kind == TypeKind::Enum
                && cur.data.enum_decl == decl) {
            return cur;
        }
        idx = (idx + 1) & mask;
    }
    Ty* t = (Ty*)arena::alloc(it.arena, sizeof(Ty));
    sys::memset(t, 0, sizeof(Ty));
    t.kind = TypeKind::Enum;
    t.data.enum_decl = decl;
    return install(it, hash, t);
}

// sizeof/alignof — diag is nullable; layout/cycle errors report there when set.
export fn u32 size_of(diag::DiagBuf* diag, Ty* type) {
    if(((u8)type.flags & (u8)LayoutFlags::Opaque) != 0) {
        if(diag != null) {
            diag::report(diag, GLOBAL_TYPER.arena, decl_src_pos(type), "cannot take size of opaque type");
        }
        return 0;
    }
    if(((u8)type.flags & (u8)LayoutFlags::Computed) != 0) {
        return type.size;
    }
    TypeInterner* it = types::acquire();
    compute_layout(it, diag, type);
    types::release();
    return type.size;
}

export fn u32 align_of(diag::DiagBuf* diag, Ty* type) {
    if(((u8)type.flags & (u8)LayoutFlags::Opaque) != 0) {
        if(diag != null) {
            diag::report(diag, GLOBAL_TYPER.arena, decl_src_pos(type), "cannot take alignment of opaque type");
        }
        return 0;
    }
    if(((u8)type.flags & (u8)LayoutFlags::Computed) != 0) {
        return type.align;
    }
    TypeInterner* it = types::acquire();
    compute_layout(it, diag, type);
    types::release();
    return type.align;
}

fn void compute_layout(TypeInterner* it, diag::DiagBuf* diag, Ty* type) {
    if(((u8)type.flags & (u8)LayoutFlags::Computed) != 0) { return; }
    if(((u8)type.flags & (u8)LayoutFlags::InProgress) != 0) {
        if(diag != null) {
            diag::report(diag, it.arena, decl_src_pos(type),
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
            Ty* elem = type.data.array.elem;
            if(layout_field(it, diag, elem)) {
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
                Ty* field_type = (Ty*)decl.fields[i].resolved_type;
                if(!layout_field(it, diag, field_type)) {
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
                Ty* field_type = (Ty*)decl.fields[i].resolved_type;
                if(!layout_field(it, diag, field_type)) { continue; }
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
            Ty* base = enum_base_type(type);
            if(layout_field(it, diag, base)) {
                size  = base.size;
                align = base.align;
            }
        }
        case TypeKind::ComptimeType: {
            if(diag != null) {
                diag::report(diag, it.arena, 0, "Type has no runtime size");
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

fn bool layout_field(TypeInterner* it, diag::DiagBuf* diag, Ty* field_type) {
    if(field_type == null) { return false; }
    if(((u8)field_type.flags & (u8)LayoutFlags::Opaque) != 0) {
        if(diag != null) {
            diag::report(diag, it.arena, decl_src_pos(field_type),
                         "cannot take size of opaque type");
        }
        return false;
    }
    compute_layout(it, diag, field_type);
    return true;
}

fn u32 decl_src_pos(Ty* t) {
    if(t.kind == TypeKind::Struct) { return ((ast::StructDeclNode*)t.data.struct_decl).h.src_pos; }
    if(t.kind == TypeKind::Union)  { return ((ast::UnionDeclNode*) t.data.union_decl ).h.src_pos; }
    if(t.kind == TypeKind::Enum)   { return ((ast::EnumDeclNode*)  t.data.enum_decl  ).h.src_pos; }
    return 0;
}

// Conversions
export fn bool is_convertible(Ty* src, Ty* dst) {
    if (src == dst) { return true; }
    // array -> pointer: decays to an element pointer (matching element, or void* which any pointer converts to)
    if (is_array(src) && is_ptr(dst)) {
        Ty* a_elem = src.data.array.elem;
        Ty* p_pee  = dst.data.pointee;
        return a_elem == p_pee || is_void(p_pee);
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
    // null -> any pointer, slice, or function pointer
    if (src == prim_null_ptr() && (is_ptr(dst) || is_slice(dst) || is_fnptr(dst))) { return true; }
    return false;
}

export fn bool is_convertible_in_cond(Ty* src) {
    if (is_bool(src)) { return true; }
    if (is_int(src))  { return true; }       // zero / non-zero
    if (is_ptr(src) || is_slice(src) || is_fnptr(src)) { return true; }  // null / non-null
    return false;
}

export fn bool int_lit_fits(u64 value, bool is_negative, Ty* dst) {
    if (!is_int(dst)) { return false; }
    if (is_negative && is_unsigned_int(dst)) { return false; }
    u64 dst_max = int_max(dst);
    u64 dst_min_abs = int_min_abs(dst);    // for signed; 0 for unsigned
    if (is_negative) { return value <= dst_min_abs; }
    return value <= dst_max;
}

export fn bool is_castable(Ty* src, Ty* dst) {
    if (src == null || dst == null) { return false; }
    if (((u8)src.flags & (u8)LayoutFlags::Opaque) != 0) { return false; }
    if (((u8)dst.flags & (u8)LayoutFlags::Opaque) != 0) { return false; }
    if (is_convertible(src, dst))                  { return true; }
    // An enum casts through its base integer type: int↔enum, enum↔enum, enum↔float (C treats enums as ints).
    Ty* s = src; if (src.kind == TypeKind::Enum) { s = enum_base_type(src); }
    Ty* d = dst; if (dst.kind == TypeKind::Enum) { d = enum_base_type(dst); }
    if (is_bool(s) && (is_int(d) || is_float(d) || is_bool(d))) { return true; }   // C treats bool as 0/1
    if ((is_int(s) || is_float(s)) && is_bool(d))  { return true; }
    if (is_int(s)          && is_int(d))           { return true; }
    if (is_int(s)          && is_float(d))         { return true; }
    if (is_float(s)        && is_int(d))           { return true; }
    if (is_float(s)        && is_float(d))         { return true; }
    if (is_ptr(s)          && is_ptr_sized_int(d)) { return true; }
    if (is_ptr_sized_int(s) && is_ptr(d))          { return true; }
    return false;
}

fn bool is_ptr_sized_int(Ty* t) {
    if (!is_int(t)) { return false; }
    return t.prim == PrimitiveKind::I64 || t.prim == PrimitiveKind::U64;
}

fn i32 int_rank(Ty* t) {
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
export fn bool is_int(Ty* t) {
    return t.kind == TypeKind::Primitive
    && t.prim >= PrimitiveKind::I8 && t.prim <= PrimitiveKind::U64;
}

export fn bool is_signed_int(Ty* t) {
    return t.kind == TypeKind::Primitive
    && t.prim >= PrimitiveKind::I8 && t.prim <= PrimitiveKind::I64;
}

export fn bool is_unsigned_int(Ty* t) {
    return t.kind == TypeKind::Primitive
    && t.prim >= PrimitiveKind::U8 && t.prim <= PrimitiveKind::U64;
}

export fn bool is_float(Ty* t) {
    return t.kind == TypeKind::Primitive
    && t.prim >= PrimitiveKind::F32 && t.prim <= PrimitiveKind::F64;
}

export fn bool is_bool(Ty* t) {
    return t.kind == TypeKind::Primitive
    && t.prim == PrimitiveKind::BOOL;
}

export fn bool is_void(Ty* t) {
    return t.kind == TypeKind::Primitive
    && t.prim == PrimitiveKind::VOID;
}

export fn bool is_slice(Ty* t) {
    return t.kind == TypeKind::Slice;
}

export fn bool is_array(Ty* t) {
    return t.kind == TypeKind::Array;
}

export fn bool is_ptr(Ty* t) {
    return t.kind == TypeKind::Pointer;
}

export fn bool is_fnptr(Ty* t) {
    return t.kind == TypeKind::FnPtr;
}

export fn bool is_named(Ty* t) {
    return t.kind == TypeKind::Struct || t.kind == TypeKind::Union || t.kind == TypeKind::Enum;
}

export fn bool is_comptime_type(Ty* t) {
    return t.kind == TypeKind::ComptimeType;
}

export fn Ty* enum_base_type(Ty* type) {
    if(type.kind != TypeKind::Enum) { return null; }
    ast::EnumDeclNode* decl = (ast::EnumDeclNode*)type.data.enum_decl;
    if(decl == null) { return null; }
    if(decl.base_type == null) { return prim_i32(); }   // an omitted base type defaults to i32
    return (Ty*)decl.base_type.h.ty;
}

// A struct's field types in declaration order; lets a backend build the LLVM struct body without importing ast.
export fn Ty*[] struct_field_types(Ty* type, arena::Arena* a) {
    ast::StructDeclNode* decl = (ast::StructDeclNode*)type.data.struct_decl;
    Ty** out = (Ty**)arena::alloc(a, (decl.fields.len + 1) * sizeof(Ty*));
    for(u64 i = 0; i < decl.fields.len; i += 1) { out[i] = (Ty*)decl.fields[i].resolved_type; }
    Ty*[] result = {out, decl.fields.len};
    return result;
}

// Field accessors over a struct or union, letting a backend build DWARF composite types without importing ast.
fn ast::FieldDecl* field_at(Ty* type, u64 index) {
    if(type.kind == TypeKind::Struct) { return &((ast::StructDeclNode*)type.data.struct_decl).fields[index]; }
    return &((ast::UnionDeclNode*)type.data.union_decl).fields[index];
}

export fn u64 field_count(Ty* type) {
    if(type.kind == TypeKind::Struct) { return ((ast::StructDeclNode*)type.data.struct_decl).fields.len; }
    if(type.kind == TypeKind::Union)  { return ((ast::UnionDeclNode*)type.data.union_decl).fields.len; }
    return 0;
}

export fn Ty* field_type(Ty* type, u64 index) { return (Ty*)field_at(type, index).resolved_type; }

export fn symbol::Symbol* field_name_sym(Ty* type, u64 index) { return field_at(type, index).name; }

export fn u32 field_offset(Ty* type, u64 index) {
    if(((u8)type.flags & (u8)LayoutFlags::Computed) == 0) { size_of(null, type); }
    if(type.layout == null) { return 0; }
    return type.layout.offsets[index];
}

export fn symbol::Symbol* type_name_sym(Ty* type) {
    if(type.kind == TypeKind::Struct) { return ((ast::StructDeclNode*)type.data.struct_decl).qualified_name; }
    if(type.kind == TypeKind::Union)  { return ((ast::UnionDeclNode*)type.data.union_decl).qualified_name; }
    return null;
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

fn void init_prim(Ty* t, PrimitiveKind p, u32 size, u32 align) {
    t.kind  = TypeKind::Primitive;
    t.prim  = p;
    t.size  = size;
    t.align = align;
    t.flags = LayoutFlags::Computed;
}

export fn Ty* prim_i8 ()    { ensure_prim_init(); return &PRIM.i8_;   }
export fn Ty* prim_i16()    { ensure_prim_init(); return &PRIM.i16_;  }
export fn Ty* prim_i32()    { ensure_prim_init(); return &PRIM.i32_;  }
export fn Ty* prim_i64()    { ensure_prim_init(); return &PRIM.i64_;  }
export fn Ty* prim_u8 ()    { ensure_prim_init(); return &PRIM.u8_;   }
export fn Ty* prim_u16()    { ensure_prim_init(); return &PRIM.u16_;  }
export fn Ty* prim_u32()    { ensure_prim_init(); return &PRIM.u32_;  }
export fn Ty* prim_u64()    { ensure_prim_init(); return &PRIM.u64_;  }
export fn Ty* prim_f32()    { ensure_prim_init(); return &PRIM.f32_;  }
export fn Ty* prim_f64()    { ensure_prim_init(); return &PRIM.f64_;  }
export fn Ty* prim_bool()   { ensure_prim_init(); return &PRIM.bool_; }
export fn Ty* prim_void()   { ensure_prim_init(); return &PRIM.void_; }
export fn Ty* prim_type()   { ensure_prim_init(); return &PRIM.type_; }
export fn Ty* prim_null_ptr() { ensure_prim_init(); return &PRIM.null_ptr; }

export fn Ty* primitive(PrimitiveKind kind) {
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

export fn u64 int_max(Ty* t) {
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

export fn u64 int_min_abs(Ty* t) {
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

fn Ty* install(TypeInterner* it, u32 hash, Ty* t) {
    if ((it.count + 1) * 10 > it.cap * 7) { typer_grow(it); }
    u64 mask = it.cap - 1;
    u64 idx  = (u64)hash & mask;
    while (it.buckets[idx].hash != 0) { idx = (idx + 1) & mask; }
    it.buckets[idx].hash = hash;
    it.buckets[idx].type = t;
    it.count += 1;
    return t;
}

fn bool fn_params_equal(Ty*[] a, Ty*[] b) {
    if (a.len != b.len) { return false; }
    for (u64 i = 0; i < a.len; i += 1) {
        if (a[i] != b[i]) { return false; }
    }
    return true;
}

fn Ty*[] copy_type_slice(arena::Arena* a, Ty*[] src) {
    u64 bytes = src.len * sizeof(Ty*);
    Ty** mem = (Ty**)arena::alloc(a, bytes);
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

fn u32 hash_array(Ty* elem, u64 count) {
    u32 h = hash_ptr(elem) ^ 0x10000002;
    h ^= (u32)((count * 0x9E3779B97F4A7C15) >> 32);
    if (h == 0) { h = 1; }
    return h;
}

fn u32 hash_slice(Ty* elem) {
    u32 h = hash_ptr(elem) ^ 0x10000003;
    if (h == 0) { h = 1; }
    return h;
}

fn u32 hash_fn_ptr(Ty* ret, Ty*[] params, bool is_variadic) {
    u32 h = hash_ptr(ret) ^ 0x10000004;
    for (u64 i = 0; i < params.len; i += 1) {
        h = h * 31 + hash_ptr(params[i]);
    }
    h ^= (u32)params.len;
    if (is_variadic) { h ^= 0x80000000; }
    if (h == 0) { h = 1; }
    return h;
}

fn u32 hash_pointer(Ty* pointee, bool is_const) {
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
