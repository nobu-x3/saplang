import testing;
import types;
import ast;
import arena;
import diag;
import token;
import sys;

// Locked snapshot reads of the global typer's bookkeeping.
fn u64 typer_count() { types::TypeInterner* it = types::acquire(); u64 count = it.count; types::release(); return count; }
fn u64 typer_cap()   { types::TypeInterner* it = types::acquire(); u64 cap = it.cap; types::release(); return cap; }

fn diag::DiagBuf* fresh_diag(arena::Arena* a) {
    diag::DiagBuf* d = (diag::DiagBuf*)arena::alloc(a, sizeof(diag::DiagBuf));
    sys::memset(d, 0, sizeof(diag::DiagBuf));
    return d;
}

fn types::Ty* fake_prim(arena::Arena* a, types::PrimitiveKind p, u32 size, u32 align) {
    types::Ty* t = (types::Ty*)arena::alloc(a, sizeof(types::Ty));
    sys::memset(t, 0, sizeof(types::Ty));
    t.kind = types::TypeKind::Primitive;
    t.prim = p;
    t.size = size;
    t.align = align;
    t.flags = types::LayoutFlags::Computed;
    return t;
}

fn types::Ty* fake_i8 (arena::Arena* a)  { return fake_prim(a, types::PrimitiveKind::I8,   1, 1); }
fn types::Ty* fake_i16(arena::Arena* a)  { return fake_prim(a, types::PrimitiveKind::I16,  2, 2); }
fn types::Ty* fake_i32(arena::Arena* a)  { return fake_prim(a, types::PrimitiveKind::I32,  4, 4); }
fn types::Ty* fake_i64(arena::Arena* a)  { return fake_prim(a, types::PrimitiveKind::I64,  8, 8); }
fn types::Ty* fake_u8(arena::Arena* a)   { return fake_prim(a, types::PrimitiveKind::U8,   1, 1); }
fn types::Ty* fake_u16(arena::Arena* a)  { return fake_prim(a, types::PrimitiveKind::U16,  2, 2); }
fn types::Ty* fake_u32(arena::Arena* a)  { return fake_prim(a, types::PrimitiveKind::U32,  4, 4); }
fn types::Ty* fake_u64(arena::Arena* a)  { return fake_prim(a, types::PrimitiveKind::U64,  8, 8); }
fn types::Ty* fake_f32(arena::Arena* a)  { return fake_prim(a, types::PrimitiveKind::F32,  4, 4); }
fn types::Ty* fake_f64(arena::Arena* a)  { return fake_prim(a, types::PrimitiveKind::F64,  8, 8); }
fn types::Ty* fake_bool(arena::Arena* a) { return fake_prim(a, types::PrimitiveKind::BOOL, 1, 1); }
fn types::Ty* fake_void(arena::Arena* a) { return fake_prim(a, types::PrimitiveKind::VOID, 0, 1); }
fn types::Ty* fake_none_prim(arena::Arena* a) { return fake_prim(a, types::PrimitiveKind::NONE, 0, 1); }

fn types::Ty* fake_comptime(arena::Arena* a) {
    types::Ty* t = (types::Ty*)arena::alloc(a, sizeof(types::Ty));
    sys::memset(t, 0, sizeof(types::Ty));
    t.kind = types::TypeKind::ComptimeType;
    return t;
}

fn ast::EnumDeclNode* fake_enum_decl(arena::Arena* a, types::Ty* base) {
    ast::AstNode* base_ast = (ast::AstNode*)arena::alloc(a, sizeof(ast::AstNode));
    sys::memset(base_ast, 0, sizeof(ast::AstNode));
    base_ast.h.ty = (void*)base;
    ast::EnumDeclNode* decl = (ast::EnumDeclNode*)arena::alloc(a, sizeof(ast::EnumDeclNode));
    sys::memset(decl, 0, sizeof(ast::EnumDeclNode));
    decl.base_type = base_ast;
    return decl;
}

fn ast::EnumDeclNode* fake_enum_decl_null_base(arena::Arena* a) {
    ast::EnumDeclNode* decl = (ast::EnumDeclNode*)arena::alloc(a, sizeof(ast::EnumDeclNode));
    sys::memset(decl, 0, sizeof(ast::EnumDeclNode));
    return decl;
}

fn types::Ty* fake_enum_with_base(arena::Arena* a, types::Ty* base) {
    return types::intern_enum((void*)fake_enum_decl(a, base));
}

fn ast::StructDeclNode* fake_struct_decl(arena::Arena* a, types::Ty*[] fts) {
    ast::StructDeclNode* d = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    sys::memset(d, 0, sizeof(ast::StructDeclNode));
    if(fts.len > 0) {
        ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, fts.len * sizeof(ast::FieldDecl));
        sys::memset(fields, 0, fts.len * sizeof(ast::FieldDecl));
        for(u64 i = 0; i < fts.len; i += 1) {
            fields[i].resolved_type = (void*)fts[i];
        }
        d.fields = {fields, fts.len};
    } else {
        d.fields = {null, 0};
    }
    return d;
}

fn ast::UnionDeclNode* fake_union_decl(arena::Arena* a, types::Ty*[] fts) {
    ast::UnionDeclNode* d = (ast::UnionDeclNode*)arena::alloc(a, sizeof(ast::UnionDeclNode));
    sys::memset(d, 0, sizeof(ast::UnionDeclNode));
    if(fts.len > 0) {
        ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, fts.len * sizeof(ast::FieldDecl));
        sys::memset(fields, 0, fts.len * sizeof(ast::FieldDecl));
        for(u64 i = 0; i < fts.len; i += 1) {
            fields[i].resolved_type = (void*)fts[i];
        }
        d.fields = {fields, fts.len};
    } else {
        d.fields = {null, 0};
    }
    return d;
}

fn types::Ty* fake_struct_typed(arena::Arena* a, types::Ty*[] fts) {
    return types::intern_struct((void*)fake_struct_decl(a, fts));
}

fn types::Ty* fake_union_typed(arena::Arena* a, types::Ty*[] fts) {
    return types::intern_union((void*)fake_union_decl(a, fts));
}

fn void* fake_decl(arena::Arena* a) { return arena::alloc(a, 8); }

fn types::Ty*[] mk_params0() { types::Ty*[] p; p.ptr = null; p.len = 0; return p; }

fn types::Ty*[] mk_params1(arena::Arena* a, types::Ty* p0) {
    types::Ty** mem = (types::Ty**)arena::alloc(a, sizeof(types::Ty*));
    mem[0] = p0;
    types::Ty*[] p; p.ptr = mem; p.len = 1; return p;
}

fn types::Ty*[] mk_params2(arena::Arena* a, types::Ty* p0, types::Ty* p1) {
    types::Ty** mem = (types::Ty**)arena::alloc(a, sizeof(types::Ty*) * 2);
    mem[0] = p0; mem[1] = p1;
    types::Ty*[] p; p.ptr = mem; p.len = 2; return p;
}

fn types::Ty*[] mk_params3(arena::Arena* a, types::Ty* p0, types::Ty* p1, types::Ty* p2) {
    types::Ty** mem = (types::Ty**)arena::alloc(a, sizeof(types::Ty*) * 3);
    mem[0] = p0; mem[1] = p1; mem[2] = p2;
    types::Ty*[] p; p.ptr = mem; p.len = 3; return p;
}

fn bool has_flag(types::Ty* t, types::LayoutFlags f) {
    return ((u8)(t.flags & f)) != 0;
}

// ===== typer_init =====

fn i32 typer_init_zeroes_count(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::TypeInterner* it = types::acquire();
    u64 count = it.count;
    types::release();
    if(!testing::expect_eq(count, (u64)0, m)) { return -1; }
    return 0;
}

fn i32 typer_init_cap_matches(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::TypeInterner* it = types::acquire();
    u64 cap = it.cap;
    u64 buckets_len = it.buckets.len;
    types::release();
    if(!testing::expect_eq(cap, (u64)16, m)) { return -1; }
    if(!testing::expect_eq(buckets_len, (u64)16, m)) { return -2; }
    return 0;
}

fn i32 typer_init_arena_bound(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::TypeInterner* it = types::acquire();
    void* arena = (void*)it.arena;
    types::release();
    if(!testing::expect_eq(arena, (void*)a, m)) { return -1; }
    return 0;
}

fn i32 typer_init_buckets_empty(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::TypeInterner* it = types::acquire();
    bool all_zero = true;
    for(u64 i = 0; i < it.buckets.len; i += 1) {
        if(it.buckets[i].hash != 0) { all_zero = false; }
    }
    types::release();
    if(!testing::expect_true(all_zero, m)) { return -1; }
    return 0;
}

// ===== intern_pointer =====

fn i32 pointer_identity(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* pointee = fake_i32(a);
    types::Ty* p1 = types::intern_pointer(pointee, false);
    types::Ty* p2 = types::intern_pointer(pointee, false);
    if(!testing::expect_eq((void*)p1, (void*)p2, m)) { return -1; }
    return 0;
}

fn i32 pointer_distinct_pointees(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* a32 = fake_i32(a);
    types::Ty* b64 = fake_i64(a);
    types::Ty* p1 = types::intern_pointer(a32, false);
    types::Ty* p2 = types::intern_pointer(b64, false);
    if(!testing::expect_ne((void*)p1, (void*)p2, m)) { return -1; }
    return 0;
}

fn i32 pointer_const_distinguishes(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* pointee = fake_i32(a);
    types::Ty* p1 = types::intern_pointer(pointee, false);
    types::Ty* p2 = types::intern_pointer(pointee, true);
    if(!testing::expect_ne((void*)p1, (void*)p2, m)) { return -1; }
    if(!testing::expect_eq(has_flag(p1, types::LayoutFlags::Const), false, m)) { return -2; }
    if(!testing::expect_eq(has_flag(p2, types::LayoutFlags::Const), true,  m)) { return -3; }
    return 0;
}

fn i32 pointer_eager_layout(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* p = types::intern_pointer(fake_i32(a), false);
    if(!testing::expect_eq((u64)p.size,  (u64)8, m)) { return -1; }
    if(!testing::expect_eq((u64)p.align, (u64)8, m)) { return -2; }
    if(!testing::expect_eq(has_flag(p, types::LayoutFlags::Computed), true, m)) { return -3; }
    return 0;
}

fn i32 pointer_kind_and_data(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* pointee = fake_i32(a);
    types::Ty* p = types::intern_pointer(pointee, false);
    if(!testing::expect_eq((u64)p.kind, (u64)types::TypeKind::Pointer, m)) { return -1; }
    if(!testing::expect_eq((void*)p.data.pointee, (void*)pointee, m)) { return -2; }
    return 0;
}

fn i32 pointer_count_increments(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::intern_pointer(fake_i32(a), false);
    if(!testing::expect_eq(typer_count(), (u64)1, m)) { return -1; }
    types::intern_pointer(fake_i32(a), false);
    if(!testing::expect_eq(typer_count(), (u64)2, m)) { return -2; }
    return 0;
}

fn i32 pointer_to_pointer(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* base = fake_i32(a);
    types::Ty* p1 = types::intern_pointer(base, false);
    types::Ty* p2 = types::intern_pointer(p1,   false);
    if(!testing::expect_ne((void*)p1, (void*)p2, m)) { return -1; }
    if(!testing::expect_eq((void*)p2.data.pointee, (void*)p1, m)) { return -2; }
    types::Ty* p2b = types::intern_pointer(p1, false);
    if(!testing::expect_eq((void*)p2, (void*)p2b, m)) { return -3; }
    return 0;
}

// ===== intern_array =====

fn i32 array_identity(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_i32(a);
    types::Ty* a1 = types::intern_array(elem, 10);
    types::Ty* a2 = types::intern_array(elem, 10);
    if(!testing::expect_eq((void*)a1, (void*)a2, m)) { return -1; }
    return 0;
}

fn i32 array_distinct_counts(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_i32(a);
    types::Ty* a1 = types::intern_array(elem, 10);
    types::Ty* a2 = types::intern_array(elem, 11);
    if(!testing::expect_ne((void*)a1, (void*)a2, m)) { return -1; }
    return 0;
}

fn i32 array_distinct_elems(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* a1 = types::intern_array(fake_i32(a), 10);
    types::Ty* a2 = types::intern_array(fake_i64(a), 10);
    if(!testing::expect_ne((void*)a1, (void*)a2, m)) { return -1; }
    return 0;
}

fn i32 array_zero_count_ok(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_i32(a);
    types::Ty* a1 = types::intern_array(elem, 0);
    types::Ty* a2 = types::intern_array(elem, 0);
    if(!testing::expect_eq((void*)a1, (void*)a2, m)) { return -1; }
    if(!testing::expect_eq(a1.data.array.count, (u64)0, m)) { return -2; }
    return 0;
}

fn i32 array_lazy_layout(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* arr = types::intern_array(fake_i32(a), 5);
    if(!testing::expect_eq(has_flag(arr, types::LayoutFlags::Computed), false, m)) { return -1; }
    return 0;
}

fn i32 array_kind_and_data(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_i32(a);
    types::Ty* arr  = types::intern_array(elem, 7);
    if(!testing::expect_eq((u64)arr.kind, (u64)types::TypeKind::Array, m)) { return -1; }
    if(!testing::expect_eq((void*)arr.data.array.elem, (void*)elem, m)) { return -2; }
    if(!testing::expect_eq(arr.data.array.count, (u64)7, m)) { return -3; }
    return 0;
}

fn i32 array_of_pointer_combo(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* ptr = types::intern_pointer(fake_i32(a), false);
    types::Ty* arr = types::intern_array(ptr, 4);
    if(!testing::expect_eq((void*)arr.data.array.elem, (void*)ptr, m)) { return -1; }
    types::Ty* arr2 = types::intern_array(ptr, 4);
    if(!testing::expect_eq((void*)arr, (void*)arr2, m)) { return -2; }
    return 0;
}

// ===== intern_slice =====

fn i32 slice_identity(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_i32(a);
    types::Ty* s1 = types::intern_slice(elem);
    types::Ty* s2 = types::intern_slice(elem);
    if(!testing::expect_eq((void*)s1, (void*)s2, m)) { return -1; }
    return 0;
}

fn i32 slice_distinct_elems(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s1 = types::intern_slice(fake_i32(a));
    types::Ty* s2 = types::intern_slice(fake_i64(a));
    if(!testing::expect_ne((void*)s1, (void*)s2, m)) { return -1; }
    return 0;
}

fn i32 slice_eager_layout(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = types::intern_slice(fake_i32(a));
    if(!testing::expect_eq((u64)s.size,  (u64)16, m)) { return -1; }
    if(!testing::expect_eq((u64)s.align, (u64)8,  m)) { return -2; }
    if(!testing::expect_eq(has_flag(s, types::LayoutFlags::Computed), true, m)) { return -3; }
    return 0;
}

fn i32 slice_kind_and_data(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_i32(a);
    types::Ty* s = types::intern_slice(elem);
    if(!testing::expect_eq((u64)s.kind, (u64)types::TypeKind::Slice, m)) { return -1; }
    if(!testing::expect_eq((void*)s.data.slice_elem, (void*)elem, m)) { return -2; }
    return 0;
}

fn i32 slice_of_composite_combo(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* arr = types::intern_array(fake_u8(a), 64);
    types::Ty* s1 = types::intern_slice(arr);
    types::Ty* s2 = types::intern_slice(arr);
    if(!testing::expect_eq((void*)s1, (void*)s2, m)) { return -1; }
    if(!testing::expect_eq((void*)s1.data.slice_elem, (void*)arr, m)) { return -2; }
    return 0;
}

// ===== intern_fn_ptr =====

fn i32 fnptr_identity(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* ret = fake_i32(a);
    types::Ty*[] p = mk_params2(a, fake_i32(a), fake_f64(a));
    types::Ty* f1 = types::intern_fn_ptr(ret, p, false);
    types::Ty* f2 = types::intern_fn_ptr(ret, p, false);
    if(!testing::expect_eq((void*)f1, (void*)f2, m)) { return -1; }
    return 0;
}

fn i32 fnptr_distinct_return(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* p32 = fake_i32(a);
    types::Ty*[] p = mk_params1(a, p32);
    types::Ty* f1 = types::intern_fn_ptr(fake_i32(a), p, false);
    types::Ty* f2 = types::intern_fn_ptr(fake_i64(a), p, false);
    if(!testing::expect_ne((void*)f1, (void*)f2, m)) { return -1; }
    return 0;
}

fn i32 fnptr_distinct_variadic(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* ret = fake_void(a);
    types::Ty*[] p = mk_params1(a, fake_u8(a));
    types::Ty* f1 = types::intern_fn_ptr(ret, p, false);
    types::Ty* f2 = types::intern_fn_ptr(ret, p, true);
    if(!testing::expect_ne((void*)f1, (void*)f2, m)) { return -1; }
    return 0;
}

fn i32 fnptr_distinct_param_types(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* ret = fake_void(a);
    types::Ty*[] p1 = mk_params1(a, fake_i32(a));
    types::Ty*[] p2 = mk_params1(a, fake_i64(a));
    types::Ty* f1 = types::intern_fn_ptr(ret, p1, false);
    types::Ty* f2 = types::intern_fn_ptr(ret, p2, false);
    if(!testing::expect_ne((void*)f1, (void*)f2, m)) { return -1; }
    return 0;
}

fn i32 fnptr_distinct_param_order(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* ret = fake_void(a);
    types::Ty* x = fake_i32(a);
    types::Ty* y = fake_f64(a);
    types::Ty* f1 = types::intern_fn_ptr(ret, mk_params2(a, x, y), false);
    types::Ty* f2 = types::intern_fn_ptr(ret, mk_params2(a, y, x), false);
    if(!testing::expect_ne((void*)f1, (void*)f2, m)) { return -1; }
    return 0;
}

fn i32 fnptr_distinct_arity(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* ret = fake_void(a);
    types::Ty* x = fake_i32(a);
    types::Ty* f1 = types::intern_fn_ptr(ret, mk_params1(a, x), false);
    types::Ty* f2 = types::intern_fn_ptr(ret, mk_params2(a, x, x), false);
    if(!testing::expect_ne((void*)f1, (void*)f2, m)) { return -1; }
    return 0;
}

fn i32 fnptr_empty_params(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* ret = fake_i32(a);
    types::Ty* f1 = types::intern_fn_ptr(ret, mk_params0(), false);
    types::Ty* f2 = types::intern_fn_ptr(ret, mk_params0(), false);
    if(!testing::expect_eq((void*)f1, (void*)f2, m)) { return -1; }
    if(!testing::expect_eq(f1.data.fn_ptr.params.len, (u64)0, m)) { return -2; }
    return 0;
}

fn i32 fnptr_many_params(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* ret = fake_void(a);
    types::Ty* x = fake_i32(a);
    u64 n = 12;
    types::Ty** mem = (types::Ty**)arena::alloc(a, n * sizeof(types::Ty*));
    for(u64 i = 0; i < n; i += 1) { mem[i] = x; }
    types::Ty*[] params; params.ptr = mem; params.len = n;
    types::Ty* f1 = types::intern_fn_ptr(ret, params, false);
    types::Ty* f2 = types::intern_fn_ptr(ret, params, false);
    if(!testing::expect_eq((void*)f1, (void*)f2, m)) { return -1; }
    if(!testing::expect_eq(f1.data.fn_ptr.params.len, n, m)) { return -2; }
    return 0;
}

fn i32 fnptr_eager_layout(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* f = types::intern_fn_ptr(fake_void(a), mk_params0(), false);
    if(!testing::expect_eq((u64)f.size,  (u64)8, m)) { return -1; }
    if(!testing::expect_eq((u64)f.align, (u64)8, m)) { return -2; }
    if(!testing::expect_eq(has_flag(f, types::LayoutFlags::Computed), true, m)) { return -3; }
    return 0;
}

fn i32 fnptr_composite_params_combo(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* arr  = types::intern_array(fake_i32(a), 8);
    types::Ty* ptr  = types::intern_pointer(fake_bool(a), true);
    types::Ty* slc  = types::intern_slice(fake_u8(a));
    types::Ty*[] p  = mk_params3(a, arr, ptr, slc);
    types::Ty* f1 = types::intern_fn_ptr(slc, p, false);
    types::Ty* f2 = types::intern_fn_ptr(slc, mk_params3(a, arr, ptr, slc), false);
    if(!testing::expect_eq((void*)f1, (void*)f2, m)) { return -1; }
    return 0;
}

// ===== intern_struct / intern_union / intern_enum =====

fn i32 struct_identity_by_decl(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    void* d = fake_decl(a);
    types::Ty* s1 = types::intern_struct(d);
    types::Ty* s2 = types::intern_struct(d);
    if(!testing::expect_eq((void*)s1, (void*)s2, m)) { return -1; }
    if(!testing::expect_eq((u64)s1.kind, (u64)types::TypeKind::Struct, m)) { return -2; }
    if(!testing::expect_eq((void*)s1.data.struct_decl, d, m)) { return -3; }
    return 0;
}

fn i32 struct_distinct_decls(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    void* d1 = fake_decl(a);
    void* d2 = fake_decl(a);
    types::Ty* s1 = types::intern_struct(d1);
    types::Ty* s2 = types::intern_struct(d2);
    if(!testing::expect_ne((void*)s1, (void*)s2, m)) { return -1; }
    return 0;
}

fn i32 struct_lazy_layout(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = types::intern_struct(fake_decl(a));
    if(!testing::expect_eq(has_flag(s, types::LayoutFlags::Computed), false, m)) { return -1; }
    return 0;
}

fn i32 union_identity_and_kind(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    void* d = fake_decl(a);
    types::Ty* u1 = types::intern_union(d);
    types::Ty* u2 = types::intern_union(d);
    if(!testing::expect_eq((void*)u1, (void*)u2, m)) { return -1; }
    if(!testing::expect_eq((u64)u1.kind, (u64)types::TypeKind::Union, m)) { return -2; }
    if(!testing::expect_eq((void*)u1.data.union_decl, d, m)) { return -3; }
    return 0;
}

fn i32 enum_identity_and_kind(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    void* d = fake_decl(a);
    types::Ty* e1 = types::intern_enum(d);
    types::Ty* e2 = types::intern_enum(d);
    if(!testing::expect_eq((void*)e1, (void*)e2, m)) { return -1; }
    if(!testing::expect_eq((u64)e1.kind, (u64)types::TypeKind::Enum, m)) { return -2; }
    if(!testing::expect_eq((void*)e1.data.enum_decl, d, m)) { return -3; }
    return 0;
}

// ===== cross-kind isolation =====

fn i32 pointer_vs_slice_same_elem(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_i32(a);
    types::Ty* p = types::intern_pointer(elem, false);
    types::Ty* s = types::intern_slice(elem);
    if(!testing::expect_ne((void*)p, (void*)s, m)) { return -1; }
    return 0;
}

fn i32 array_vs_slice_same_elem(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_i32(a);
    types::Ty* arr = types::intern_array(elem, 8);
    types::Ty* slc = types::intern_slice(elem);
    if(!testing::expect_ne((void*)arr, (void*)slc, m)) { return -1; }
    return 0;
}

fn i32 struct_union_enum_same_decl(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    void* d = fake_decl(a);
    types::Ty* s = types::intern_struct(d);
    types::Ty* u = types::intern_union(d);
    types::Ty* e = types::intern_enum(d);
    if(!testing::expect_ne((void*)s, (void*)u, m)) { return -1; }
    if(!testing::expect_ne((void*)u, (void*)e, m)) { return -2; }
    if(!testing::expect_ne((void*)s, (void*)e, m)) { return -3; }
    return 0;
}

// ===== growth + probing =====

fn i32 small_cap_forces_probing(arena::Arena* a, u8[] m) {
    types::typer_init(a, 2);
    types::Ty* p1 = types::intern_pointer(fake_i32(a),  false);
    types::Ty* p2 = types::intern_pointer(fake_i64(a),  false);
    types::Ty* p3 = types::intern_pointer(fake_f64(a),  false);
    types::Ty* p4 = types::intern_pointer(fake_bool(a), false);
    if(!testing::expect_ne((void*)p1, (void*)p2, m)) { return -1; }
    if(!testing::expect_ne((void*)p2, (void*)p3, m)) { return -2; }
    if(!testing::expect_ne((void*)p3, (void*)p4, m)) { return -3; }
    if(!testing::expect_ge(typer_cap(), (u64)4, m)) { return -4; }
    return 0;
}

fn i32 growth_preserves_identity(arena::Arena* a, u8[] m) {
    types::typer_init(a, 4);
    types::Ty* anchor_a = fake_i32(a);
    types::Ty* anchor_b = fake_i64(a);
    types::Ty* p_a_early = types::intern_pointer(anchor_a, false);
    types::Ty* p_b_early = types::intern_pointer(anchor_b, true);
    for(u64 i = 0; i < 32; i += 1) {
        types::Ty* extra = fake_prim(a, types::PrimitiveKind::I32, 4, 4);
        types::intern_pointer(extra, false);
    }
    types::Ty* p_a_late = types::intern_pointer(anchor_a, false);
    types::Ty* p_b_late = types::intern_pointer(anchor_b, true);
    if(!testing::expect_eq((void*)p_a_early, (void*)p_a_late, m)) { return -1; }
    if(!testing::expect_eq((void*)p_b_early, (void*)p_b_late, m)) { return -2; }
    return 0;
}

fn i32 growth_doubles_cap(arena::Arena* a, u8[] m) {
    types::typer_init(a, 4);
    u64 start_cap = typer_cap();
    for(u64 i = 0; i < 32; i += 1) {
        types::Ty* extra = fake_prim(a, types::PrimitiveKind::I32, 4, 4);
        types::intern_pointer(extra, false);
    }
    if(!testing::expect_gt(typer_cap(), start_cap, m)) { return -1; }
    if(!testing::expect_eq(typer_cap() & (typer_cap() - 1), (u64)0, m)) { return -2; }
    return 0;
}

fn i32 count_tracks_distinct_inserts(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_i32(a);
    types::intern_pointer(elem, false);
    types::intern_pointer(elem, false);
    types::intern_pointer(elem, true);
    types::intern_array(elem, 4);
    types::intern_array(elem, 4);
    types::intern_slice(elem);
    if(!testing::expect_eq(typer_count(), (u64)4, m)) { return -1; }
    return 0;
}

fn i32 growth_preserves_all_kinds(arena::Arena* a, u8[] m) {
    types::typer_init(a, 4);
    types::Ty* elem   = fake_i32(a);
    types::Ty* void_t = fake_void(a);
    void* sd = fake_decl(a);
    void* ud = fake_decl(a);
    void* ed = fake_decl(a);
    types::Ty* anchor_ptr = types::intern_pointer(elem, true);
    types::Ty* anchor_arr = types::intern_array  (elem, 5);
    types::Ty* anchor_slc = types::intern_slice  (elem);
    types::Ty* anchor_fn  = types::intern_fn_ptr (void_t, mk_params1(a, elem), false);
    types::Ty* anchor_st  = types::intern_struct (sd);
    types::Ty* anchor_un  = types::intern_union  (ud);
    types::Ty* anchor_en  = types::intern_enum   (ed);
    for(u64 i = 0; i < 40; i += 1) {
        types::intern_pointer(fake_prim(a, types::PrimitiveKind::I32, 4, 4), false);
    }
    if(!testing::expect_eq((void*)anchor_ptr, (void*)types::intern_pointer(elem, true), m)) { return -1; }
    if(!testing::expect_eq((void*)anchor_arr, (void*)types::intern_array  (elem, 5),    m)) { return -2; }
    if(!testing::expect_eq((void*)anchor_slc, (void*)types::intern_slice  (elem),       m)) { return -3; }
    if(!testing::expect_eq((void*)anchor_fn,  (void*)types::intern_fn_ptr (void_t, mk_params1(a, elem), false), m)) { return -4; }
    if(!testing::expect_eq((void*)anchor_st,  (void*)types::intern_struct (sd), m)) { return -5; }
    if(!testing::expect_eq((void*)anchor_un,  (void*)types::intern_union  (ud), m)) { return -6; }
    if(!testing::expect_eq((void*)anchor_en,  (void*)types::intern_enum   (ed), m)) { return -7; }
    return 0;
}

fn i32 growth_multiple_doublings(arena::Arena* a, u8[] m) {
    types::typer_init(a, 2);
    types::Ty* anchor_elem = fake_i32(a);
    types::Ty* anchor = types::intern_pointer(anchor_elem, false);
    u64 start_cap = typer_cap();
    for(u64 i = 0; i < 64; i += 1) {
        types::intern_pointer(fake_prim(a, types::PrimitiveKind::I32, 4, 4), false);
    }
    if(!testing::expect_ge(typer_cap(), start_cap * (u64)8, m)) { return -1; }
    types::Ty* anchor_late = types::intern_pointer(anchor_elem, false);
    if(!testing::expect_eq((void*)anchor, (void*)anchor_late, m)) { return -2; }
    return 0;
}

fn i32 fnptr_params_owned_after_intern(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* ret = fake_void(a);
    types::Ty* p0  = fake_i32(a);
    types::Ty* p1  = fake_f64(a);
    types::Ty*[] params = mk_params2(a, p0, p1);
    types::Ty* f1 = types::intern_fn_ptr(ret, params, false);
    params[0] = fake_bool(a);
    params[1] = fake_u8(a);
    types::Ty* f2 = types::intern_fn_ptr(ret, mk_params2(a, p0, p1), false);
    if(!testing::expect_eq((void*)f1, (void*)f2, m)) { return -1; }
    return 0;
}

fn i32 count_survives_grow(arena::Arena* a, u8[] m) {
    types::typer_init(a, 4);
    u64 n = 50;
    for(u64 i = 0; i < n; i += 1) {
        types::intern_pointer(fake_prim(a, types::PrimitiveKind::I32, 4, 4), false);
    }
    if(!testing::expect_eq(typer_count(), n, m)) { return -1; }
    if(!testing::expect_gt(typer_cap(), (u64)4, m)) { return -2; }
    return 0;
}


// ===== predicate helpers (is_int, is_signed_int, ...) =====

fn i32 is_int_exhaustive(arena::Arena* a, u8[] m) {
    types::typer_init(a, 32);
    if(!testing::expect_eq(types::is_int(fake_i8(a)),   true,  m)) { return -1; }
    if(!testing::expect_eq(types::is_int(fake_i16(a)),  true,  m)) { return -2; }
    if(!testing::expect_eq(types::is_int(fake_i32(a)),  true,  m)) { return -3; }
    if(!testing::expect_eq(types::is_int(fake_i64(a)),  true,  m)) { return -4; }
    if(!testing::expect_eq(types::is_int(fake_u8(a)),   true,  m)) { return -5; }
    if(!testing::expect_eq(types::is_int(fake_u16(a)),  true,  m)) { return -6; }
    if(!testing::expect_eq(types::is_int(fake_u32(a)),  true,  m)) { return -7; }
    if(!testing::expect_eq(types::is_int(fake_u64(a)),  true,  m)) { return -8; }
    if(!testing::expect_eq(types::is_int(fake_f32(a)),  false, m)) { return -9; }
    if(!testing::expect_eq(types::is_int(fake_f64(a)),  false, m)) { return -10; }
    if(!testing::expect_eq(types::is_int(fake_bool(a)), false, m)) { return -11; }
    if(!testing::expect_eq(types::is_int(fake_void(a)), false, m)) { return -12; }
    if(!testing::expect_eq(types::is_int(fake_none_prim(a)),    false, m)) { return -13; }
    if(!testing::expect_eq(types::is_int(types::intern_pointer(fake_i32(a), false)), false, m)) { return -14; }
    if(!testing::expect_eq(types::is_int(types::intern_array(fake_i32(a), 4)),       false, m)) { return -15; }
    if(!testing::expect_eq(types::is_int(types::intern_slice(fake_i32(a))),          false, m)) { return -16; }
    if(!testing::expect_eq(types::is_int(types::intern_fn_ptr(fake_void(a), mk_params0(), false)), false, m)) { return -17; }
    if(!testing::expect_eq(types::is_int(types::intern_struct(fake_decl(a))), false, m)) { return -18; }
    if(!testing::expect_eq(types::is_int(types::intern_union(fake_decl(a))),  false, m)) { return -19; }
    if(!testing::expect_eq(types::is_int(types::intern_enum(fake_decl(a))),   false, m)) { return -20; }
    if(!testing::expect_eq(types::is_int(fake_comptime(a)), false, m)) { return -21; }
    return 0;
}

fn i32 is_signed_int_exhaustive(arena::Arena* a, u8[] m) {
    types::typer_init(a, 32);
    if(!testing::expect_eq(types::is_signed_int(fake_i8(a)),   true,  m)) { return -1; }
    if(!testing::expect_eq(types::is_signed_int(fake_i16(a)),  true,  m)) { return -2; }
    if(!testing::expect_eq(types::is_signed_int(fake_i32(a)),  true,  m)) { return -3; }
    if(!testing::expect_eq(types::is_signed_int(fake_i64(a)),  true,  m)) { return -4; }
    if(!testing::expect_eq(types::is_signed_int(fake_u8(a)),   false, m)) { return -5; }
    if(!testing::expect_eq(types::is_signed_int(fake_u16(a)),  false, m)) { return -6; }
    if(!testing::expect_eq(types::is_signed_int(fake_u32(a)),  false, m)) { return -7; }
    if(!testing::expect_eq(types::is_signed_int(fake_u64(a)),  false, m)) { return -8; }
    if(!testing::expect_eq(types::is_signed_int(fake_f32(a)),  false, m)) { return -9; }
    if(!testing::expect_eq(types::is_signed_int(fake_bool(a)), false, m)) { return -10; }
    if(!testing::expect_eq(types::is_signed_int(fake_void(a)), false, m)) { return -11; }
    if(!testing::expect_eq(types::is_signed_int(types::intern_pointer(fake_i32(a), false)), false, m)) { return -12; }
    if(!testing::expect_eq(types::is_signed_int(types::intern_struct(fake_decl(a))),        false, m)) { return -13; }
    return 0;
}

fn i32 is_unsigned_int_exhaustive(arena::Arena* a, u8[] m) {
    types::typer_init(a, 32);
    if(!testing::expect_eq(types::is_unsigned_int(fake_u8(a)),   true,  m)) { return -1; }
    if(!testing::expect_eq(types::is_unsigned_int(fake_u16(a)),  true,  m)) { return -2; }
    if(!testing::expect_eq(types::is_unsigned_int(fake_u32(a)),  true,  m)) { return -3; }
    if(!testing::expect_eq(types::is_unsigned_int(fake_u64(a)),  true,  m)) { return -4; }
    if(!testing::expect_eq(types::is_unsigned_int(fake_i8(a)),   false, m)) { return -5; }
    if(!testing::expect_eq(types::is_unsigned_int(fake_i16(a)),  false, m)) { return -6; }
    if(!testing::expect_eq(types::is_unsigned_int(fake_i32(a)),  false, m)) { return -7; }
    if(!testing::expect_eq(types::is_unsigned_int(fake_i64(a)),  false, m)) { return -8; }
    if(!testing::expect_eq(types::is_unsigned_int(fake_f32(a)),  false, m)) { return -9; }
    if(!testing::expect_eq(types::is_unsigned_int(fake_bool(a)), false, m)) { return -10; }
    if(!testing::expect_eq(types::is_unsigned_int(fake_void(a)), false, m)) { return -11; }
    if(!testing::expect_eq(types::is_unsigned_int(types::intern_slice(fake_u8(a))),   false, m)) { return -12; }
    if(!testing::expect_eq(types::is_unsigned_int(types::intern_enum(fake_decl(a))), false, m)) { return -13; }
    return 0;
}

fn i32 is_float_exhaustive(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    if(!testing::expect_eq(types::is_float(fake_f32(a)),  true,  m)) { return -1; }
    if(!testing::expect_eq(types::is_float(fake_f64(a)),  true,  m)) { return -2; }
    if(!testing::expect_eq(types::is_float(fake_i32(a)),  false, m)) { return -3; }
    if(!testing::expect_eq(types::is_float(fake_u32(a)),  false, m)) { return -4; }
    if(!testing::expect_eq(types::is_float(fake_bool(a)), false, m)) { return -5; }
    if(!testing::expect_eq(types::is_float(fake_void(a)), false, m)) { return -6; }
    if(!testing::expect_eq(types::is_float(types::intern_pointer(fake_f32(a), false)), false, m)) { return -7; }
    if(!testing::expect_eq(types::is_float(fake_comptime(a)), false, m)) { return -8; }
    return 0;
}

fn i32 is_bool_exhaustive(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    if(!testing::expect_eq(types::is_bool(fake_bool(a)), true,  m)) { return -1; }
    if(!testing::expect_eq(types::is_bool(fake_i8(a)),   false, m)) { return -2; }
    if(!testing::expect_eq(types::is_bool(fake_u8(a)),   false, m)) { return -3; }
    if(!testing::expect_eq(types::is_bool(fake_f32(a)),  false, m)) { return -4; }
    if(!testing::expect_eq(types::is_bool(fake_void(a)), false, m)) { return -5; }
    if(!testing::expect_eq(types::is_bool(types::intern_pointer(fake_bool(a), false)), false, m)) { return -6; }
    if(!testing::expect_eq(types::is_bool(types::intern_struct(fake_decl(a))), false, m)) { return -7; }
    return 0;
}

fn i32 is_void_exhaustive(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    if(!testing::expect_eq(types::is_void(fake_void(a)), true,  m)) { return -1; }
    if(!testing::expect_eq(types::is_void(fake_i8(a)),   false, m)) { return -2; }
    if(!testing::expect_eq(types::is_void(fake_bool(a)), false, m)) { return -3; }
    if(!testing::expect_eq(types::is_void(fake_f64(a)),  false, m)) { return -4; }
    if(!testing::expect_eq(types::is_void(types::intern_pointer(fake_void(a), false)), false, m)) { return -5; }
    return 0;
}

fn i32 is_slice_exhaustive(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    if(!testing::expect_eq(types::is_slice(types::intern_slice(fake_i32(a))), true,  m)) { return -1; }
    if(!testing::expect_eq(types::is_slice(types::intern_array(fake_i32(a), 4)),       false, m)) { return -2; }
    if(!testing::expect_eq(types::is_slice(types::intern_pointer(fake_i32(a), false)), false, m)) { return -3; }
    if(!testing::expect_eq(types::is_slice(fake_i32(a)),  false, m)) { return -4; }
    if(!testing::expect_eq(types::is_slice(fake_bool(a)), false, m)) { return -5; }
    if(!testing::expect_eq(types::is_slice(types::intern_struct(fake_decl(a))), false, m)) { return -6; }
    return 0;
}

fn i32 is_array_exhaustive(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    if(!testing::expect_eq(types::is_array(types::intern_array(fake_i32(a), 4)),        true,  m)) { return -1; }
    if(!testing::expect_eq(types::is_array(types::intern_array(fake_i32(a), 0)),        true,  m)) { return -2; }
    if(!testing::expect_eq(types::is_array(types::intern_slice(fake_i32(a))),           false, m)) { return -3; }
    if(!testing::expect_eq(types::is_array(types::intern_pointer(fake_i32(a), false)),  false, m)) { return -4; }
    if(!testing::expect_eq(types::is_array(fake_i32(a)),  false, m)) { return -5; }
    if(!testing::expect_eq(types::is_array(fake_void(a)), false, m)) { return -6; }
    if(!testing::expect_eq(types::is_array(types::intern_union(fake_decl(a))), false, m)) { return -7; }
    return 0;
}

fn i32 is_ptr_exhaustive(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    if(!testing::expect_eq(types::is_ptr(types::intern_pointer(fake_i32(a), false)), true,  m)) { return -1; }
    if(!testing::expect_eq(types::is_ptr(types::intern_pointer(fake_i32(a), true)),  true,  m)) { return -2; }
    if(!testing::expect_eq(types::is_ptr(types::intern_fn_ptr(fake_void(a), mk_params0(), false)), false, m)) { return -3; }
    if(!testing::expect_eq(types::is_ptr(types::intern_slice(fake_i32(a))),          false, m)) { return -4; }
    if(!testing::expect_eq(types::is_ptr(types::intern_array(fake_i32(a), 4)),       false, m)) { return -5; }
    if(!testing::expect_eq(types::is_ptr(fake_i32(a)),  false, m)) { return -6; }
    if(!testing::expect_eq(types::is_ptr(fake_void(a)), false, m)) { return -7; }
    if(!testing::expect_eq(types::is_ptr(types::intern_enum(fake_decl(a))), false, m)) { return -8; }
    return 0;
}

fn i32 is_named_exhaustive(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    if(!testing::expect_eq(types::is_named(types::intern_struct(fake_decl(a))), true,  m)) { return -1; }
    if(!testing::expect_eq(types::is_named(types::intern_union(fake_decl(a))),  true,  m)) { return -2; }
    if(!testing::expect_eq(types::is_named(types::intern_enum(fake_decl(a))),   true,  m)) { return -3; }
    if(!testing::expect_eq(types::is_named(fake_i32(a)),  false, m)) { return -4; }
    if(!testing::expect_eq(types::is_named(fake_bool(a)), false, m)) { return -5; }
    if(!testing::expect_eq(types::is_named(fake_void(a)), false, m)) { return -6; }
    if(!testing::expect_eq(types::is_named(types::intern_pointer(fake_i32(a), false)), false, m)) { return -7; }
    if(!testing::expect_eq(types::is_named(types::intern_array(fake_i32(a), 4)),       false, m)) { return -8; }
    if(!testing::expect_eq(types::is_named(types::intern_slice(fake_i32(a))),          false, m)) { return -9; }
    if(!testing::expect_eq(types::is_named(types::intern_fn_ptr(fake_void(a), mk_params0(), false)), false, m)) { return -10; }
    if(!testing::expect_eq(types::is_named(fake_comptime(a)), false, m)) { return -11; }
    return 0;
}

fn i32 is_comptime_type_exhaustive(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    if(!testing::expect_eq(types::is_comptime_type(fake_comptime(a)), true,  m)) { return -1; }
    if(!testing::expect_eq(types::is_comptime_type(fake_i32(a)),      false, m)) { return -2; }
    if(!testing::expect_eq(types::is_comptime_type(fake_void(a)),     false, m)) { return -3; }
    if(!testing::expect_eq(types::is_comptime_type(types::intern_pointer(fake_i32(a), false)), false, m)) { return -4; }
    if(!testing::expect_eq(types::is_comptime_type(types::intern_struct(fake_decl(a))),        false, m)) { return -5; }
    if(!testing::expect_eq(types::is_comptime_type(types::intern_enum(fake_decl(a))),          false, m)) { return -6; }
    return 0;
}

fn i32 predicates_NONE_primitive_falses(arena::Arena* a, u8[] m) {
    types::Ty* t = fake_none_prim(a);
    if(!testing::expect_eq(types::is_int(t),          false, m)) { return -1; }
    if(!testing::expect_eq(types::is_signed_int(t),   false, m)) { return -2; }
    if(!testing::expect_eq(types::is_unsigned_int(t), false, m)) { return -3; }
    if(!testing::expect_eq(types::is_float(t),        false, m)) { return -4; }
    if(!testing::expect_eq(types::is_bool(t),         false, m)) { return -5; }
    if(!testing::expect_eq(types::is_void(t),         false, m)) { return -6; }
    if(!testing::expect_eq(types::is_ptr(t),          false, m)) { return -7; }
    if(!testing::expect_eq(types::is_slice(t),        false, m)) { return -8; }
    if(!testing::expect_eq(types::is_array(t),        false, m)) { return -9; }
    if(!testing::expect_eq(types::is_named(t),        false, m)) { return -10; }
    if(!testing::expect_eq(types::is_comptime_type(t),false, m)) { return -11; }
    return 0;
}

// ===== enum_base_type =====

fn i32 enum_base_type_non_enum_returns_null(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    if(!testing::expect_eq((void*)types::enum_base_type(fake_i32(a)),  null, m)) { return -1; }
    if(!testing::expect_eq((void*)types::enum_base_type(fake_void(a)), null, m)) { return -2; }
    if(!testing::expect_eq((void*)types::enum_base_type(fake_bool(a)), null, m)) { return -3; }
    if(!testing::expect_eq((void*)types::enum_base_type(types::intern_pointer(fake_i32(a), false)), null, m)) { return -4; }
    if(!testing::expect_eq((void*)types::enum_base_type(types::intern_array(fake_i32(a), 4)),       null, m)) { return -5; }
    if(!testing::expect_eq((void*)types::enum_base_type(types::intern_slice(fake_i32(a))),          null, m)) { return -6; }
    if(!testing::expect_eq((void*)types::enum_base_type(types::intern_fn_ptr(fake_void(a), mk_params0(), false)), null, m)) { return -7; }
    if(!testing::expect_eq((void*)types::enum_base_type(types::intern_struct(fake_decl(a))), null, m)) { return -8; }
    if(!testing::expect_eq((void*)types::enum_base_type(types::intern_union(fake_decl(a))),  null, m)) { return -9; }
    if(!testing::expect_eq((void*)types::enum_base_type(fake_comptime(a)), null, m)) { return -10; }
    return 0;
}

fn i32 enum_base_type_returns_set_base_i32(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* base = fake_i32(a);
    types::Ty* e = fake_enum_with_base(a, base);
    if(!testing::expect_eq((void*)types::enum_base_type(e), (void*)base, m)) { return -1; }
    return 0;
}

fn i32 enum_base_type_returns_set_base_u8(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* base = fake_u8(a);
    types::Ty* e = fake_enum_with_base(a, base);
    if(!testing::expect_eq((void*)types::enum_base_type(e), (void*)base, m)) { return -1; }
    return 0;
}

fn i32 enum_base_type_stable_across_calls(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* base = fake_i64(a);
    types::Ty* e = fake_enum_with_base(a, base);
    if(!testing::expect_eq((void*)types::enum_base_type(e), (void*)types::enum_base_type(e), m)) { return -1; }
    if(!testing::expect_eq((void*)types::enum_base_type(e), (void*)base, m)) { return -2; }
    return 0;
}

fn i32 enum_base_type_distinct_decls_distinct_bases(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* base_a = fake_i32(a);
    types::Ty* base_b = fake_u16(a);
    types::Ty* ea = fake_enum_with_base(a, base_a);
    types::Ty* eb = fake_enum_with_base(a, base_b);
    if(!testing::expect_eq((void*)types::enum_base_type(ea), (void*)base_a, m)) { return -1; }
    if(!testing::expect_eq((void*)types::enum_base_type(eb), (void*)base_b, m)) { return -2; }
    if(!testing::expect_ne((void*)types::enum_base_type(ea), (void*)types::enum_base_type(eb), m)) { return -3; }
    return 0;
}

fn i32 enum_base_type_null_base_defaults_i32(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* e = types::intern_enum((void*)fake_enum_decl_null_base(a));
    if(!testing::expect_eq((void*)types::enum_base_type(e), (void*)types::prim_i32(), m)) { return -1; }
    return 0;
}

// ===== int_max =====

fn i32 int_max_per_signed_primitive(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::int_max(fake_i8(a)),  (u64)127,                  m)) { return -1; }
    if(!testing::expect_eq(types::int_max(fake_i16(a)), (u64)32767,                m)) { return -2; }
    if(!testing::expect_eq(types::int_max(fake_i32(a)), (u64)2147483647,           m)) { return -3; }
    if(!testing::expect_eq(types::int_max(fake_i64(a)), (u64)9223372036854775807,  m)) { return -4; }
    return 0;
}

fn i32 int_max_per_unsigned_primitive(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::int_max(fake_u8(a)),  (u64)255,                   m)) { return -1; }
    if(!testing::expect_eq(types::int_max(fake_u16(a)), (u64)65535,                 m)) { return -2; }
    if(!testing::expect_eq(types::int_max(fake_u32(a)), (u64)4294967295,            m)) { return -3; }
    if(!testing::expect_eq(types::int_max(fake_u64(a)), (u64)18446744073709551615,  m)) { return -4; }
    return 0;
}

fn i32 int_max_non_int_returns_zero(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    if(!testing::expect_eq(types::int_max(fake_f32(a)),  (u64)0, m)) { return -1; }
    if(!testing::expect_eq(types::int_max(fake_f64(a)),  (u64)0, m)) { return -2; }
    if(!testing::expect_eq(types::int_max(fake_bool(a)), (u64)0, m)) { return -3; }
    if(!testing::expect_eq(types::int_max(fake_void(a)), (u64)0, m)) { return -4; }
    if(!testing::expect_eq(types::int_max(fake_none_prim(a)), (u64)0, m)) { return -5; }
    if(!testing::expect_eq(types::int_max(types::intern_pointer(fake_i32(a), false)), (u64)0, m)) { return -6; }
    if(!testing::expect_eq(types::int_max(types::intern_array(fake_i32(a), 4)),       (u64)0, m)) { return -7; }
    if(!testing::expect_eq(types::int_max(types::intern_slice(fake_i32(a))),          (u64)0, m)) { return -8; }
    if(!testing::expect_eq(types::int_max(types::intern_struct(fake_decl(a))),        (u64)0, m)) { return -9; }
    if(!testing::expect_eq(types::int_max(fake_comptime(a)), (u64)0, m)) { return -10; }
    return 0;
}

// ===== int_min_abs =====

fn i32 int_min_abs_per_signed_primitive(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::int_min_abs(fake_i8(a)),  (u64)128,                   m)) { return -1; }
    if(!testing::expect_eq(types::int_min_abs(fake_i16(a)), (u64)32768,                 m)) { return -2; }
    if(!testing::expect_eq(types::int_min_abs(fake_i32(a)), (u64)2147483648,            m)) { return -3; }
    if(!testing::expect_eq(types::int_min_abs(fake_i64(a)), (u64)9223372036854775808,   m)) { return -4; }
    return 0;
}

fn i32 int_min_abs_unsigned_returns_zero(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::int_min_abs(fake_u8(a)),  (u64)0, m)) { return -1; }
    if(!testing::expect_eq(types::int_min_abs(fake_u16(a)), (u64)0, m)) { return -2; }
    if(!testing::expect_eq(types::int_min_abs(fake_u32(a)), (u64)0, m)) { return -3; }
    if(!testing::expect_eq(types::int_min_abs(fake_u64(a)), (u64)0, m)) { return -4; }
    return 0;
}

fn i32 int_min_abs_non_int_returns_zero(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    if(!testing::expect_eq(types::int_min_abs(fake_f32(a)),  (u64)0, m)) { return -1; }
    if(!testing::expect_eq(types::int_min_abs(fake_bool(a)), (u64)0, m)) { return -2; }
    if(!testing::expect_eq(types::int_min_abs(fake_void(a)), (u64)0, m)) { return -3; }
    if(!testing::expect_eq(types::int_min_abs(types::intern_pointer(fake_i32(a), false)), (u64)0, m)) { return -4; }
    if(!testing::expect_eq(types::int_min_abs(types::intern_struct(fake_decl(a))),        (u64)0, m)) { return -5; }
    if(!testing::expect_eq(types::int_min_abs(fake_comptime(a)), (u64)0, m)) { return -6; }
    return 0;
}

// ===== int_lit_fits =====

fn i32 int_lit_fits_non_int_dst_false(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    if(!testing::expect_eq(types::int_lit_fits((u64)0, false, fake_f32(a)),  false, m)) { return -1; }
    if(!testing::expect_eq(types::int_lit_fits((u64)0, false, fake_f64(a)),  false, m)) { return -2; }
    if(!testing::expect_eq(types::int_lit_fits((u64)0, false, fake_bool(a)), false, m)) { return -3; }
    if(!testing::expect_eq(types::int_lit_fits((u64)0, false, fake_void(a)), false, m)) { return -4; }
    if(!testing::expect_eq(types::int_lit_fits((u64)0, false, types::intern_pointer(fake_i32(a), false)), false, m)) { return -5; }
    if(!testing::expect_eq(types::int_lit_fits((u64)0, false, types::intern_struct(fake_decl(a))), false, m)) { return -6; }
    if(!testing::expect_eq(types::int_lit_fits((u64)0, false, fake_comptime(a)), false, m)) { return -7; }
    return 0;
}

fn i32 int_lit_fits_negative_to_unsigned_false(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::int_lit_fits((u64)1,  true, fake_u8(a)),  false, m)) { return -1; }
    if(!testing::expect_eq(types::int_lit_fits((u64)1,  true, fake_u16(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::int_lit_fits((u64)1,  true, fake_u32(a)), false, m)) { return -3; }
    if(!testing::expect_eq(types::int_lit_fits((u64)1,  true, fake_u64(a)), false, m)) { return -4; }
    if(!testing::expect_eq(types::int_lit_fits((u64)0,  true, fake_u8(a)),  false, m)) { return -5; }
    return 0;
}

fn i32 int_lit_fits_zero_to_each_int(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::int_lit_fits((u64)0, false, fake_i8(a)),  true, m)) { return -1; }
    if(!testing::expect_eq(types::int_lit_fits((u64)0, false, fake_i16(a)), true, m)) { return -2; }
    if(!testing::expect_eq(types::int_lit_fits((u64)0, false, fake_i32(a)), true, m)) { return -3; }
    if(!testing::expect_eq(types::int_lit_fits((u64)0, false, fake_i64(a)), true, m)) { return -4; }
    if(!testing::expect_eq(types::int_lit_fits((u64)0, false, fake_u8(a)),  true, m)) { return -5; }
    if(!testing::expect_eq(types::int_lit_fits((u64)0, false, fake_u16(a)), true, m)) { return -6; }
    if(!testing::expect_eq(types::int_lit_fits((u64)0, false, fake_u32(a)), true, m)) { return -7; }
    if(!testing::expect_eq(types::int_lit_fits((u64)0, false, fake_u64(a)), true, m)) { return -8; }
    return 0;
}

fn i32 int_lit_fits_i8_boundaries(arena::Arena* a, u8[] m) {
    types::Ty* t = fake_i8(a);
    if(!testing::expect_eq(types::int_lit_fits((u64)127, false, t), true,  m)) { return -1; }
    if(!testing::expect_eq(types::int_lit_fits((u64)128, false, t), false, m)) { return -2; }
    if(!testing::expect_eq(types::int_lit_fits((u64)128, true,  t), true,  m)) { return -3; }
    if(!testing::expect_eq(types::int_lit_fits((u64)129, true,  t), false, m)) { return -4; }
    if(!testing::expect_eq(types::int_lit_fits((u64)1,   true,  t), true,  m)) { return -5; }
    return 0;
}

fn i32 int_lit_fits_u8_boundaries(arena::Arena* a, u8[] m) {
    types::Ty* t = fake_u8(a);
    if(!testing::expect_eq(types::int_lit_fits((u64)255, false, t), true,  m)) { return -1; }
    if(!testing::expect_eq(types::int_lit_fits((u64)256, false, t), false, m)) { return -2; }
    return 0;
}

fn i32 int_lit_fits_i16_boundaries(arena::Arena* a, u8[] m) {
    types::Ty* t = fake_i16(a);
    if(!testing::expect_eq(types::int_lit_fits((u64)32767, false, t), true,  m)) { return -1; }
    if(!testing::expect_eq(types::int_lit_fits((u64)32768, false, t), false, m)) { return -2; }
    if(!testing::expect_eq(types::int_lit_fits((u64)32768, true,  t), true,  m)) { return -3; }
    if(!testing::expect_eq(types::int_lit_fits((u64)32769, true,  t), false, m)) { return -4; }
    return 0;
}

fn i32 int_lit_fits_u16_boundaries(arena::Arena* a, u8[] m) {
    types::Ty* t = fake_u16(a);
    if(!testing::expect_eq(types::int_lit_fits((u64)65535, false, t), true,  m)) { return -1; }
    if(!testing::expect_eq(types::int_lit_fits((u64)65536, false, t), false, m)) { return -2; }
    return 0;
}

fn i32 int_lit_fits_i32_boundaries(arena::Arena* a, u8[] m) {
    types::Ty* t = fake_i32(a);
    if(!testing::expect_eq(types::int_lit_fits((u64)2147483647, false, t), true,  m)) { return -1; }
    if(!testing::expect_eq(types::int_lit_fits((u64)2147483648, false, t), false, m)) { return -2; }
    if(!testing::expect_eq(types::int_lit_fits((u64)2147483648, true,  t), true,  m)) { return -3; }
    if(!testing::expect_eq(types::int_lit_fits((u64)2147483649, true,  t), false, m)) { return -4; }
    return 0;
}

fn i32 int_lit_fits_u32_boundaries(arena::Arena* a, u8[] m) {
    types::Ty* t = fake_u32(a);
    if(!testing::expect_eq(types::int_lit_fits((u64)4294967295, false, t), true,  m)) { return -1; }
    if(!testing::expect_eq(types::int_lit_fits((u64)4294967296, false, t), false, m)) { return -2; }
    return 0;
}

fn i32 int_lit_fits_i64_boundaries(arena::Arena* a, u8[] m) {
    types::Ty* t = fake_i64(a);
    if(!testing::expect_eq(types::int_lit_fits((u64)9223372036854775807, false, t), true,  m)) { return -1; }
    if(!testing::expect_eq(types::int_lit_fits((u64)9223372036854775808, false, t), false, m)) { return -2; }
    if(!testing::expect_eq(types::int_lit_fits((u64)9223372036854775808, true,  t), true,  m)) { return -3; }
    if(!testing::expect_eq(types::int_lit_fits((u64)9223372036854775809, true,  t), false, m)) { return -4; }
    return 0;
}

fn i32 int_lit_fits_u64_max(arena::Arena* a, u8[] m) {
    types::Ty* u64t = fake_u64(a);
    if(!testing::expect_eq(types::int_lit_fits((u64)18446744073709551615, false, u64t), true, m)) { return -1; }
    if(!testing::expect_eq(types::int_lit_fits((u64)0, false, u64t),                    true, m)) { return -2; }
    return 0;
}

fn i32 int_lit_fits_cross_size_u8_vs_i8(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::int_lit_fits((u64)200, false, fake_u8(a)), true,  m)) { return -1; }
    if(!testing::expect_eq(types::int_lit_fits((u64)200, false, fake_i8(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::int_lit_fits((u64)200, false, fake_i16(a)), true, m)) { return -3; }
    return 0;
}

fn i32 int_lit_fits_value_fits_wider(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::int_lit_fits((u64)100000, false, fake_u32(a)), true, m)) { return -1; }
    if(!testing::expect_eq(types::int_lit_fits((u64)100000, false, fake_u16(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::int_lit_fits((u64)100000, false, fake_i32(a)), true, m)) { return -3; }
    if(!testing::expect_eq(types::int_lit_fits((u64)100000, false, fake_i16(a)), false, m)) { return -4; }
    return 0;
}

// ===== is_convertible_in_cond =====

fn i32 cond_bool_true(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_convertible_in_cond(fake_bool(a)), true, m)) { return -1; }
    return 0;
}

fn i32 cond_all_ints_true(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_convertible_in_cond(fake_i8(a)),  true, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible_in_cond(fake_i16(a)), true, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible_in_cond(fake_i32(a)), true, m)) { return -3; }
    if(!testing::expect_eq(types::is_convertible_in_cond(fake_i64(a)), true, m)) { return -4; }
    if(!testing::expect_eq(types::is_convertible_in_cond(fake_u8(a)),  true, m)) { return -5; }
    if(!testing::expect_eq(types::is_convertible_in_cond(fake_u16(a)), true, m)) { return -6; }
    if(!testing::expect_eq(types::is_convertible_in_cond(fake_u32(a)), true, m)) { return -7; }
    if(!testing::expect_eq(types::is_convertible_in_cond(fake_u64(a)), true, m)) { return -8; }
    return 0;
}

fn i32 cond_floats_false(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_convertible_in_cond(fake_f32(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible_in_cond(fake_f64(a)), false, m)) { return -2; }
    return 0;
}

fn i32 cond_pointer_true(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    if(!testing::expect_eq(types::is_convertible_in_cond(types::intern_pointer(fake_i32(a), false)), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible_in_cond(types::intern_pointer(fake_void(a), false)), true, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible_in_cond(types::intern_pointer(fake_i32(a), true)),  true, m)) { return -3; }
    return 0;
}

fn i32 cond_slice_true(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    if(!testing::expect_eq(types::is_convertible_in_cond(types::intern_slice(fake_i32(a))), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible_in_cond(types::intern_slice(fake_u8(a))),  true, m)) { return -2; }
    return 0;
}

fn i32 cond_array_false(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    if(!testing::expect_eq(types::is_convertible_in_cond(types::intern_array(fake_i32(a), 4)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible_in_cond(types::intern_array(fake_bool(a), 0)), false, m)) { return -2; }
    return 0;
}

fn i32 cond_fnptr_false(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    if(!testing::expect_eq(types::is_convertible_in_cond(types::intern_fn_ptr(fake_void(a), mk_params0(), false)), false, m)) { return -1; }
    return 0;
}

fn i32 cond_struct_union_enum_false(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    if(!testing::expect_eq(types::is_convertible_in_cond(types::intern_struct(fake_decl(a))), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible_in_cond(types::intern_union(fake_decl(a))),  false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible_in_cond(types::intern_enum(fake_decl(a))),   false, m)) { return -3; }
    return 0;
}

fn i32 cond_void_false(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_convertible_in_cond(fake_void(a)), false, m)) { return -1; }
    return 0;
}

fn i32 cond_comptime_false(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_convertible_in_cond(fake_comptime(a)), false, m)) { return -1; }
    return 0;
}

// ===== is_convertible — Rule 1 (identity) =====

fn i32 convert_identity_primitive(arena::Arena* a, u8[] m) {
    types::Ty* ti = fake_i32(a);
    if(!testing::expect_eq(types::is_convertible(ti, ti), true, m)) { return -1; }
    types::Ty* bl = fake_bool(a);
    if(!testing::expect_eq(types::is_convertible(bl, bl), true, m)) { return -2; }
    types::Ty* vd = fake_void(a);
    if(!testing::expect_eq(types::is_convertible(vd, vd), true, m)) { return -3; }
    types::Ty* tf = fake_f32(a);
    if(!testing::expect_eq(types::is_convertible(tf, tf), true, m)) { return -4; }
    return 0;
}

fn i32 convert_identity_pointer(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* p = types::intern_pointer(fake_i32(a), false);
    if(!testing::expect_eq(types::is_convertible(p, p), true, m)) { return -1; }
    return 0;
}

fn i32 convert_identity_slice(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = types::intern_slice(fake_i32(a));
    if(!testing::expect_eq(types::is_convertible(s, s), true, m)) { return -1; }
    return 0;
}

fn i32 convert_identity_array(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* arr = types::intern_array(fake_i32(a), 8);
    if(!testing::expect_eq(types::is_convertible(arr, arr), true, m)) { return -1; }
    return 0;
}

fn i32 convert_identity_fnptr(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* fp = types::intern_fn_ptr(fake_void(a), mk_params0(), false);
    if(!testing::expect_eq(types::is_convertible(fp, fp), true, m)) { return -1; }
    return 0;
}

fn i32 convert_identity_struct_union_enum(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = types::intern_struct(fake_decl(a));
    types::Ty* u = types::intern_union(fake_decl(a));
    types::Ty* e = types::intern_enum(fake_decl(a));
    if(!testing::expect_eq(types::is_convertible(s, s), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(u, u), true, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(e, e), true, m)) { return -3; }
    return 0;
}

fn i32 convert_identity_null_ptr(arena::Arena* a, u8[] m) {
    types::Ty* n = types::prim_null_ptr();
    if(!testing::expect_eq(types::is_convertible(n, n), true, m)) { return -1; }
    return 0;
}

// ===== is_convertible — Rule 2 (array → pointer) =====

fn i32 convert_array_to_pointer_matching_elem(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_i32(a);
    types::Ty* arr = types::intern_array(elem, 10);
    types::Ty* ptr = types::intern_pointer(elem, false);
    if(!testing::expect_eq(types::is_convertible(arr, ptr), true, m)) { return -1; }
    return 0;
}

fn i32 convert_array_to_pointer_mismatched_elem(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* arr = types::intern_array(fake_i32(a), 10);
    types::Ty* ptr = types::intern_pointer(fake_i64(a), false);
    if(!testing::expect_eq(types::is_convertible(arr, ptr), false, m)) { return -1; }
    return 0;
}

fn i32 convert_array_to_pointer_zero_count(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_i32(a);
    types::Ty* arr = types::intern_array(elem, 0);
    types::Ty* ptr = types::intern_pointer(elem, false);
    if(!testing::expect_eq(types::is_convertible(arr, ptr), true, m)) { return -1; }
    return 0;
}

fn i32 convert_array_to_pointer_count_irrelevant(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_u8(a);
    types::Ty* ptr = types::intern_pointer(elem, false);
    if(!testing::expect_eq(types::is_convertible(types::intern_array(elem, 1),    ptr), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(types::intern_array(elem, 64),   ptr), true, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(types::intern_array(elem, 9999), ptr), true, m)) { return -3; }
    return 0;
}

fn i32 convert_nested_array_to_pointer_inner(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_i32(a);
    types::Ty* inner = types::intern_array(elem, 5);
    types::Ty* outer = types::intern_array(inner, 4);
    types::Ty* p_inner = types::intern_pointer(inner, false);
    types::Ty* p_elem  = types::intern_pointer(elem,  false);
    if(!testing::expect_eq(types::is_convertible(outer, p_inner), true,  m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(outer, p_elem),  false, m)) { return -2; }
    return 0;
}

// ===== is_convertible — Rule 3 (array → slice) =====

fn i32 convert_array_to_slice_matching_elem(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_i32(a);
    types::Ty* arr = types::intern_array(elem, 10);
    types::Ty* slc = types::intern_slice(elem);
    if(!testing::expect_eq(types::is_convertible(arr, slc), true, m)) { return -1; }
    return 0;
}

fn i32 convert_array_to_slice_mismatched_elem(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* arr = types::intern_array(fake_i32(a), 10);
    types::Ty* slc = types::intern_slice(fake_i64(a));
    if(!testing::expect_eq(types::is_convertible(arr, slc), false, m)) { return -1; }
    return 0;
}

fn i32 convert_array_to_slice_struct_elem(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* sd = types::intern_struct(fake_decl(a));
    types::Ty* arr = types::intern_array(sd, 4);
    types::Ty* slc = types::intern_slice(sd);
    if(!testing::expect_eq(types::is_convertible(arr, slc), true, m)) { return -1; }
    types::Ty* sd2 = types::intern_struct(fake_decl(a));
    types::Ty* slc2 = types::intern_slice(sd2);
    if(!testing::expect_eq(types::is_convertible(arr, slc2), false, m)) { return -2; }
    return 0;
}

fn i32 convert_slice_to_array_fails(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_i32(a);
    types::Ty* arr = types::intern_array(elem, 10);
    types::Ty* slc = types::intern_slice(elem);
    if(!testing::expect_eq(types::is_convertible(slc, arr), false, m)) { return -1; }
    return 0;
}

// ===== is_convertible — Rule 5 (enum → base) =====

fn i32 convert_enum_to_base_matching(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* base = fake_i32(a);
    types::Ty* e = fake_enum_with_base(a, base);
    if(!testing::expect_eq(types::is_convertible(e, base), true, m)) { return -1; }
    return 0;
}

fn i32 convert_enum_to_base_mismatched(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* base = fake_i32(a);
    types::Ty* e = fake_enum_with_base(a, base);
    if(!testing::expect_eq(types::is_convertible(e, fake_i64(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(e, fake_u32(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(e, fake_i8(a)),  false, m)) { return -3; }
    return 0;
}

fn i32 convert_enum_to_base_unsigned(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* base = fake_u8(a);
    types::Ty* e = fake_enum_with_base(a, base);
    if(!testing::expect_eq(types::is_convertible(e, base), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(e, fake_u8(a)), false, m)) { return -2; }
    return 0;
}

fn i32 convert_base_to_enum_fails(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* base = fake_i32(a);
    types::Ty* e = fake_enum_with_base(a, base);
    if(!testing::expect_eq(types::is_convertible(base, e), false, m)) { return -1; }
    return 0;
}

// ===== is_convertible — Rule 6 (integer widening, same sign) =====

fn i32 convert_int_widen_signed(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_convertible(fake_i8(a),  fake_i16(a)), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(fake_i8(a),  fake_i32(a)), true, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(fake_i8(a),  fake_i64(a)), true, m)) { return -3; }
    if(!testing::expect_eq(types::is_convertible(fake_i16(a), fake_i32(a)), true, m)) { return -4; }
    if(!testing::expect_eq(types::is_convertible(fake_i16(a), fake_i64(a)), true, m)) { return -5; }
    if(!testing::expect_eq(types::is_convertible(fake_i32(a), fake_i64(a)), true, m)) { return -6; }
    return 0;
}

fn i32 convert_int_widen_unsigned(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_convertible(fake_u8(a),  fake_u16(a)), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(fake_u8(a),  fake_u32(a)), true, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(fake_u8(a),  fake_u64(a)), true, m)) { return -3; }
    if(!testing::expect_eq(types::is_convertible(fake_u16(a), fake_u32(a)), true, m)) { return -4; }
    if(!testing::expect_eq(types::is_convertible(fake_u16(a), fake_u64(a)), true, m)) { return -5; }
    if(!testing::expect_eq(types::is_convertible(fake_u32(a), fake_u64(a)), true, m)) { return -6; }
    return 0;
}

fn i32 convert_int_same_rank_same_sign(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_convertible(fake_i32(a), fake_i32(a)), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(fake_u8(a),  fake_u8(a)),  true, m)) { return -2; }
    return 0;
}

fn i32 convert_int_narrow_signed_fails(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_convertible(fake_i64(a), fake_i32(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(fake_i32(a), fake_i16(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(fake_i16(a), fake_i8(a)),  false, m)) { return -3; }
    if(!testing::expect_eq(types::is_convertible(fake_i64(a), fake_i8(a)),  false, m)) { return -4; }
    return 0;
}

fn i32 convert_int_narrow_unsigned_fails(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_convertible(fake_u64(a), fake_u32(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(fake_u32(a), fake_u16(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(fake_u16(a), fake_u8(a)),  false, m)) { return -3; }
    if(!testing::expect_eq(types::is_convertible(fake_u64(a), fake_u8(a)),  false, m)) { return -4; }
    return 0;
}

fn i32 convert_int_cross_sign_same_rank_fails(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_convertible(fake_i8(a),  fake_u8(a)),  false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(fake_u8(a),  fake_i8(a)),  false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(fake_i32(a), fake_u32(a)), false, m)) { return -3; }
    if(!testing::expect_eq(types::is_convertible(fake_u32(a), fake_i32(a)), false, m)) { return -4; }
    if(!testing::expect_eq(types::is_convertible(fake_i64(a), fake_u64(a)), false, m)) { return -5; }
    return 0;
}

fn i32 convert_int_cross_sign_widen_fails(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_convertible(fake_i8(a),  fake_u32(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(fake_u8(a),  fake_i64(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(fake_i32(a), fake_u64(a)), false, m)) { return -3; }
    if(!testing::expect_eq(types::is_convertible(fake_u32(a), fake_i64(a)), false, m)) { return -4; }
    return 0;
}

// ===== is_convertible — Rule 7 (float widening) =====

fn i32 convert_float_f32_to_f64(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_convertible(fake_f32(a), fake_f64(a)), true, m)) { return -1; }
    return 0;
}

fn i32 convert_float_f64_to_f32_fails(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_convertible(fake_f64(a), fake_f32(a)), false, m)) { return -1; }
    return 0;
}

fn i32 convert_float_identity_via_pointer(arena::Arena* a, u8[] m) {
    types::Ty* f = fake_f32(a);
    if(!testing::expect_eq(types::is_convertible(f, f), true, m)) { return -1; }
    types::Ty* g = fake_f64(a);
    if(!testing::expect_eq(types::is_convertible(g, g), true, m)) { return -2; }
    return 0;
}

// ===== is_convertible — Rule 8 (pointer → pointer, any pointee) =====

fn i32 convert_ptr_to_ptr_distinct_pointees(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* p_i32  = types::intern_pointer(fake_i32(a), false);
    types::Ty* p_i64  = types::intern_pointer(fake_i64(a), false);
    types::Ty* p_bool = types::intern_pointer(fake_bool(a), false);
    if(!testing::expect_eq(types::is_convertible(p_i32, p_i64),  true, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(p_i32, p_bool), true, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(p_i64, p_i32),  true, m)) { return -3; }
    return 0;
}

fn i32 convert_void_ptr_to_typed_ptr(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* p_void = types::intern_pointer(fake_void(a), false);
    types::Ty* p_i32  = types::intern_pointer(fake_i32(a),  false);
    if(!testing::expect_eq(types::is_convertible(p_void, p_i32), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(p_i32, p_void), true, m)) { return -2; }
    return 0;
}

fn i32 convert_ptr_to_ptr_through_const_qual(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_i32(a);
    types::Ty* p     = types::intern_pointer(elem, false);
    types::Ty* p_c   = types::intern_pointer(elem, true);
    if(!testing::expect_eq(types::is_convertible(p,   p_c), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(p_c, p),   true, m)) { return -2; }
    return 0;
}

fn i32 convert_ptr_to_slice_fails(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_i32(a);
    types::Ty* p = types::intern_pointer(elem, false);
    types::Ty* s = types::intern_slice(elem);
    if(!testing::expect_eq(types::is_convertible(p, s), false, m)) { return -1; }
    return 0;
}

fn i32 convert_ptr_to_named_struct_ptr(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* sd = types::intern_struct(fake_decl(a));
    types::Ty* p_s   = types::intern_pointer(sd, false);
    types::Ty* p_i32 = types::intern_pointer(fake_i32(a), false);
    if(!testing::expect_eq(types::is_convertible(p_s,   p_i32), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(p_i32, p_s),   true, m)) { return -2; }
    return 0;
}

fn i32 convert_ptr_to_non_ptr_fails(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* p = types::intern_pointer(fake_i32(a), false);
    if(!testing::expect_eq(types::is_convertible(p, fake_i32(a)),  false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(p, fake_bool(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(p, types::intern_array(fake_i32(a), 4)), false, m)) { return -3; }
    if(!testing::expect_eq(types::is_convertible(p, types::intern_struct(fake_decl(a))),  false, m)) { return -4; }
    return 0;
}

// ===== is_convertible — Rule 9 (null → pointer or slice) =====

fn i32 convert_null_to_pointer(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* n = types::prim_null_ptr();
    if(!testing::expect_eq(types::is_convertible(n, types::intern_pointer(fake_i32(a),  false)), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(n, types::intern_pointer(fake_void(a), false)), true, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(n, types::intern_pointer(fake_bool(a), true)),  true, m)) { return -3; }
    types::Ty* sd = types::intern_struct(fake_decl(a));
    if(!testing::expect_eq(types::is_convertible(n, types::intern_pointer(sd, false)), true, m)) { return -4; }
    return 0;
}

fn i32 convert_null_to_slice(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* n = types::prim_null_ptr();
    if(!testing::expect_eq(types::is_convertible(n, types::intern_slice(fake_i32(a))), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(n, types::intern_slice(fake_u8(a))),  true, m)) { return -2; }
    return 0;
}

fn i32 convert_null_to_int_fails(arena::Arena* a, u8[] m) {
    types::Ty* n = types::prim_null_ptr();
    if(!testing::expect_eq(types::is_convertible(n, fake_i32(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(n, fake_u8(a)),  false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(n, fake_i64(a)), false, m)) { return -3; }
    return 0;
}

fn i32 convert_null_to_array_fails(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* n = types::prim_null_ptr();
    if(!testing::expect_eq(types::is_convertible(n, types::intern_array(fake_i32(a), 4)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(n, types::intern_array(fake_u8(a),  0)), false, m)) { return -2; }
    return 0;
}

fn i32 convert_null_to_struct_union_enum_fails(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* n = types::prim_null_ptr();
    if(!testing::expect_eq(types::is_convertible(n, types::intern_struct(fake_decl(a))), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(n, types::intern_union(fake_decl(a))),  false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(n, types::intern_enum(fake_decl(a))),   false, m)) { return -3; }
    return 0;
}

fn i32 convert_null_to_bool_or_float_fails(arena::Arena* a, u8[] m) {
    types::Ty* n = types::prim_null_ptr();
    if(!testing::expect_eq(types::is_convertible(n, fake_bool(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(n, fake_f32(a)),  false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(n, fake_f64(a)),  false, m)) { return -3; }
    if(!testing::expect_eq(types::is_convertible(n, fake_void(a)), false, m)) { return -4; }
    return 0;
}

fn i32 prim_null_ptr_is_stable(arena::Arena* a, u8[] m) {
    types::Ty* n1 = types::prim_null_ptr();
    types::Ty* n2 = types::prim_null_ptr();
    if(!testing::expect_eq((void*)n1, (void*)n2, m)) { return -1; }
    return 0;
}

// ===== is_convertible — cross-kind rejections =====

fn i32 convert_int_to_float_fails(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_convertible(fake_i32(a), fake_f32(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(fake_i32(a), fake_f64(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(fake_u64(a), fake_f64(a)), false, m)) { return -3; }
    return 0;
}

fn i32 convert_float_to_int_fails(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_convertible(fake_f32(a), fake_i32(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(fake_f64(a), fake_i64(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(fake_f64(a), fake_u32(a)), false, m)) { return -3; }
    return 0;
}

fn i32 convert_bool_to_int_or_int_to_bool_fails(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_convertible(fake_bool(a), fake_i32(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(fake_i32(a), fake_bool(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(fake_bool(a), fake_u8(a)),  false, m)) { return -3; }
    if(!testing::expect_eq(types::is_convertible(fake_u8(a),  fake_bool(a)), false, m)) { return -4; }
    return 0;
}

fn i32 convert_int_to_pointer_fails(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* p = types::intern_pointer(fake_i32(a), false);
    if(!testing::expect_eq(types::is_convertible(fake_i32(a), p), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(fake_u64(a), p), false, m)) { return -2; }
    return 0;
}

fn i32 convert_slice_to_pointer_fails(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_i32(a);
    types::Ty* s = types::intern_slice(elem);
    types::Ty* p = types::intern_pointer(elem, false);
    if(!testing::expect_eq(types::is_convertible(s, p), false, m)) { return -1; }
    return 0;
}

fn i32 convert_struct_to_struct_distinct_decls_fails(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s1 = types::intern_struct(fake_decl(a));
    types::Ty* s2 = types::intern_struct(fake_decl(a));
    if(!testing::expect_eq(types::is_convertible(s1, s2), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(s2, s1), false, m)) { return -2; }
    return 0;
}

fn i32 convert_void_to_anything_fails(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* v = fake_void(a);
    if(!testing::expect_eq(types::is_convertible(v, fake_i32(a)),  false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(v, fake_bool(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(v, fake_f32(a)),  false, m)) { return -3; }
    if(!testing::expect_eq(types::is_convertible(v, types::intern_pointer(fake_i32(a), false)), false, m)) { return -4; }
    return 0;
}

fn i32 convert_pointer_to_int_fails(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* p = types::intern_pointer(fake_i32(a), false);
    if(!testing::expect_eq(types::is_convertible(p, fake_i32(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(p, fake_u64(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(p, fake_i8(a)),  false, m)) { return -3; }
    return 0;
}

fn i32 convert_null_to_fnptr_fails(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* n = types::prim_null_ptr();
    types::Ty* fp = types::intern_fn_ptr(fake_void(a), mk_params0(), false);
    if(!testing::expect_eq(types::is_convertible(n, fp), false, m)) { return -1; }
    return 0;
}

fn i32 convert_enum_to_other_enum_same_base_fails(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* base = fake_i32(a);
    types::Ty* e1 = fake_enum_with_base(a, base);
    types::Ty* e2 = fake_enum_with_base(a, base);
    if(!testing::expect_eq(types::is_convertible(e1, e2), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(e2, e1), false, m)) { return -2; }
    return 0;
}

fn i32 convert_array_to_different_array_fails(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* a1 = types::intern_array(fake_i32(a), 4);
    types::Ty* a2 = types::intern_array(fake_i32(a), 8);
    types::Ty* a3 = types::intern_array(fake_i64(a), 4);
    if(!testing::expect_eq(types::is_convertible(a1, a2), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(a1, a3), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(a2, a3), false, m)) { return -3; }
    return 0;
}

fn i32 convert_slice_to_different_slice_fails(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s1 = types::intern_slice(fake_i32(a));
    types::Ty* s2 = types::intern_slice(fake_i64(a));
    types::Ty* s3 = types::intern_slice(fake_u8(a));
    if(!testing::expect_eq(types::is_convertible(s1, s2), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(s1, s3), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(s2, s3), false, m)) { return -3; }
    return 0;
}

fn i32 convert_fnptr_to_different_fnptr_fails(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* f1 = types::intern_fn_ptr(fake_void(a), mk_params0(), false);
    types::Ty* f2 = types::intern_fn_ptr(fake_i32(a),  mk_params0(), false);
    types::Ty* f3 = types::intern_fn_ptr(fake_void(a), mk_params1(a, fake_i32(a)), false);
    types::Ty* f4 = types::intern_fn_ptr(fake_void(a), mk_params0(), true);
    if(!testing::expect_eq(types::is_convertible(f1, f2), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(f1, f3), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(f1, f4), false, m)) { return -3; }
    return 0;
}

fn i32 convert_ptr_to_ptr_all_pointee_kinds(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* p_prim   = types::intern_pointer(fake_i32(a), false);
    types::Ty* p_arr    = types::intern_pointer(types::intern_array(fake_i32(a), 4), false);
    types::Ty* p_slc    = types::intern_pointer(types::intern_slice(fake_i32(a)),   false);
    types::Ty* p_fn     = types::intern_pointer(types::intern_fn_ptr(fake_void(a), mk_params0(), false), false);
    types::Ty* p_struct = types::intern_pointer(types::intern_struct(fake_decl(a)), false);
    types::Ty* p_union  = types::intern_pointer(types::intern_union(fake_decl(a)),  false);
    types::Ty* p_enum   = types::intern_pointer(types::intern_enum(fake_decl(a)),   false);
    types::Ty* p_ptr    = types::intern_pointer(p_prim, false);
    if(!testing::expect_eq(types::is_convertible(p_prim,   p_arr),    true, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(p_arr,    p_slc),    true, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(p_slc,    p_fn),     true, m)) { return -3; }
    if(!testing::expect_eq(types::is_convertible(p_fn,     p_struct), true, m)) { return -4; }
    if(!testing::expect_eq(types::is_convertible(p_struct, p_union),  true, m)) { return -5; }
    if(!testing::expect_eq(types::is_convertible(p_union,  p_enum),   true, m)) { return -6; }
    if(!testing::expect_eq(types::is_convertible(p_enum,   p_ptr),    true, m)) { return -7; }
    if(!testing::expect_eq(types::is_convertible(p_ptr,    p_prim),   true, m)) { return -8; }
    return 0;
}

fn i32 convert_array_of_pointer_to_slice_of_pointer(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* pe   = types::intern_pointer(fake_i32(a), false);
    types::Ty* arr  = types::intern_array(pe, 6);
    types::Ty* slc  = types::intern_slice(pe);
    types::Ty* ptr  = types::intern_pointer(pe, false);
    if(!testing::expect_eq(types::is_convertible(arr, slc), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(arr, ptr), true, m)) { return -2; }
    return 0;
}

fn i32 convert_array_of_struct_to_pointer_of_struct(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* sd  = types::intern_struct(fake_decl(a));
    types::Ty* arr = types::intern_array(sd, 3);
    types::Ty* slc = types::intern_slice(sd);
    types::Ty* p   = types::intern_pointer(sd, false);
    if(!testing::expect_eq(types::is_convertible(arr, p),   true, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(arr, slc), true, m)) { return -2; }
    return 0;
}

fn i32 convert_comptime_to_comptime_identity(arena::Arena* a, u8[] m) {
    types::Ty* c = fake_comptime(a);
    if(!testing::expect_eq(types::is_convertible(c, c), true, m)) { return -1; }
    return 0;
}

fn i32 convert_comptime_to_other_fails(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* c1 = fake_comptime(a);
    types::Ty* c2 = fake_comptime(a);
    if(!testing::expect_eq(types::is_convertible(c1, c2), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(c1, fake_i32(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(fake_i32(a), c1), false, m)) { return -3; }
    if(!testing::expect_eq(types::is_convertible(c1, types::intern_pointer(fake_i32(a), false)), false, m)) { return -4; }
    return 0;
}

fn i32 cond_none_primitive_false(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_convertible_in_cond(fake_none_prim(a)), false, m)) { return -1; }
    return 0;
}

fn i32 convert_struct_to_non_struct_fails(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* sd = types::intern_struct(fake_decl(a));
    if(!testing::expect_eq(types::is_convertible(sd, fake_i32(a)),  false, m)) { return -1; }
    if(!testing::expect_eq(types::is_convertible(sd, fake_bool(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_convertible(sd, fake_f64(a)),  false, m)) { return -3; }
    if(!testing::expect_eq(types::is_convertible(sd, types::intern_pointer(fake_i32(a), false)), false, m)) { return -4; }
    if(!testing::expect_eq(types::is_convertible(sd, types::intern_array(fake_i32(a), 4)),       false, m)) { return -5; }
    if(!testing::expect_eq(types::is_convertible(sd, types::intern_slice(fake_i32(a))),          false, m)) { return -6; }
    return 0;
}

fn i32 prim_null_ptr_kind_is_pointer(arena::Arena* a, u8[] m) {
    types::Ty* n = types::prim_null_ptr();
    if(!testing::expect_eq((u64)n.kind, (u64)types::TypeKind::Pointer, m)) { return -1; }
    if(!testing::expect_eq(types::is_ptr(n), true, m)) { return -2; }
    return 0;
}

// ===== size_of / align_of — primitives =====

fn i32 layout_primitives_exhaustive(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    if(!testing::expect_eq(types::size_of(null, fake_i8(a)),   (u32)1, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, fake_i8(a)),   (u32)1, m)) { return -2; }
    if(!testing::expect_eq(types::size_of(null, fake_i16(a)),  (u32)2, m)) { return -3; }
    if(!testing::expect_eq(types::align_of(null, fake_i16(a)),  (u32)2, m)) { return -4; }
    if(!testing::expect_eq(types::size_of(null, fake_i32(a)),  (u32)4, m)) { return -5; }
    if(!testing::expect_eq(types::align_of(null, fake_i32(a)),  (u32)4, m)) { return -6; }
    if(!testing::expect_eq(types::size_of(null, fake_i64(a)),  (u32)8, m)) { return -7; }
    if(!testing::expect_eq(types::align_of(null, fake_i64(a)),  (u32)8, m)) { return -8; }
    if(!testing::expect_eq(types::size_of(null, fake_u8(a)),   (u32)1, m)) { return -9; }
    if(!testing::expect_eq(types::size_of(null, fake_u16(a)),  (u32)2, m)) { return -10; }
    if(!testing::expect_eq(types::size_of(null, fake_u32(a)),  (u32)4, m)) { return -11; }
    if(!testing::expect_eq(types::size_of(null, fake_u64(a)),  (u32)8, m)) { return -12; }
    if(!testing::expect_eq(types::size_of(null, fake_f32(a)),  (u32)4, m)) { return -13; }
    if(!testing::expect_eq(types::size_of(null, fake_f64(a)),  (u32)8, m)) { return -14; }
    if(!testing::expect_eq(types::size_of(null, fake_bool(a)), (u32)1, m)) { return -15; }
    if(!testing::expect_eq(types::size_of(null, fake_void(a)), (u32)0, m)) { return -16; }
    return 0;
}

// ===== size_of / align_of — pointer / slice / fnptr =====

fn i32 layout_pointer_always_8_8(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* p1 = types::intern_pointer(fake_i8(a),  false);
    types::Ty* p2 = types::intern_pointer(fake_i64(a), false);
    types::Ty* p3 = types::intern_pointer(fake_void(a), false);
    types::Ty* p4 = types::intern_pointer(p1, false);
    types::Ty* p5 = types::intern_pointer(types::intern_struct(fake_decl(a)), false);
    if(!testing::expect_eq(types::size_of(null, p1), (u32)8, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, p1), (u32)8, m)) { return -2; }
    if(!testing::expect_eq(types::size_of(null, p2), (u32)8, m)) { return -3; }
    if(!testing::expect_eq(types::size_of(null, p3), (u32)8, m)) { return -4; }
    if(!testing::expect_eq(types::size_of(null, p4), (u32)8, m)) { return -5; }
    if(!testing::expect_eq(types::size_of(null, p5), (u32)8, m)) { return -6; }
    return 0;
}

fn i32 layout_const_pointer_is_8_8(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* p = types::intern_pointer(fake_i32(a), true);
    if(!testing::expect_eq(types::size_of(null, p), (u32)8, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, p), (u32)8, m)) { return -2; }
    return 0;
}

fn i32 layout_slice_always_16_8(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s1 = types::intern_slice(fake_i8(a));
    types::Ty* s2 = types::intern_slice(fake_i64(a));
    types::Ty* s3 = types::intern_slice(types::intern_pointer(fake_i32(a), false));
    if(!testing::expect_eq(types::size_of(null, s1), (u32)16, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, s1), (u32)8,  m)) { return -2; }
    if(!testing::expect_eq(types::size_of(null, s2), (u32)16, m)) { return -3; }
    if(!testing::expect_eq(types::size_of(null, s3), (u32)16, m)) { return -4; }
    return 0;
}

fn i32 layout_fnptr_always_8_8(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* f1 = types::intern_fn_ptr(fake_void(a), mk_params0(), false);
    types::Ty* f2 = types::intern_fn_ptr(fake_i32(a),  mk_params2(a, fake_i32(a), fake_f64(a)), false);
    types::Ty* f3 = types::intern_fn_ptr(fake_void(a), mk_params1(a, fake_u8(a)), true);
    if(!testing::expect_eq(types::size_of(null, f1), (u32)8, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, f1), (u32)8, m)) { return -2; }
    if(!testing::expect_eq(types::size_of(null, f2), (u32)8, m)) { return -3; }
    if(!testing::expect_eq(types::size_of(null, f3), (u32)8, m)) { return -4; }
    return 0;
}

// ===== size_of / align_of — arrays =====

fn i32 layout_array_primitive_elem(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* a_i8  = types::intern_array(fake_i8(a),  4);
    types::Ty* a_i32 = types::intern_array(fake_i32(a), 4);
    types::Ty* a_i64 = types::intern_array(fake_i64(a), 3);
    types::Ty* a_u64 = types::intern_array(fake_u64(a), 2);
    if(!testing::expect_eq(types::size_of(null, a_i8),  (u32)4,  m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, a_i8),  (u32)1,  m)) { return -2; }
    if(!testing::expect_eq(types::size_of(null, a_i32), (u32)16, m)) { return -3; }
    if(!testing::expect_eq(types::align_of(null, a_i32), (u32)4,  m)) { return -4; }
    if(!testing::expect_eq(types::size_of(null, a_i64), (u32)24, m)) { return -5; }
    if(!testing::expect_eq(types::align_of(null, a_i64), (u32)8,  m)) { return -6; }
    if(!testing::expect_eq(types::size_of(null, a_u64), (u32)16, m)) { return -7; }
    return 0;
}

fn i32 layout_array_zero_count(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* arr = types::intern_array(fake_i32(a), 0);
    if(!testing::expect_eq(types::size_of(null, arr), (u32)0, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, arr), (u32)4, m)) { return -2; }
    return 0;
}

fn i32 layout_array_single(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* arr = types::intern_array(fake_i32(a), 1);
    if(!testing::expect_eq(types::size_of(null, arr), (u32)4, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, arr), (u32)4, m)) { return -2; }
    return 0;
}

fn i32 layout_array_large_count(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* arr = types::intern_array(fake_i8(a), 1000);
    if(!testing::expect_eq(types::size_of(null, arr), (u32)1000, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, arr), (u32)1, m)) { return -2; }
    return 0;
}

fn i32 layout_nested_array(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* inner = types::intern_array(fake_i32(a), 2);
    types::Ty* outer = types::intern_array(inner, 3);
    if(!testing::expect_eq(types::size_of(null, outer), (u32)24, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, outer), (u32)4,  m)) { return -2; }
    return 0;
}

fn i32 layout_array_of_pointer(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* ptr = types::intern_pointer(fake_i32(a), false);
    types::Ty* arr = types::intern_array(ptr, 5);
    if(!testing::expect_eq(types::size_of(null, arr), (u32)40, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, arr), (u32)8,  m)) { return -2; }
    return 0;
}

fn i32 layout_array_of_slice(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* slc = types::intern_slice(fake_i32(a));
    types::Ty* arr = types::intern_array(slc, 2);
    if(!testing::expect_eq(types::size_of(null, arr), (u32)32, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, arr), (u32)8,  m)) { return -2; }
    return 0;
}

fn i32 layout_array_of_struct(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params2(a, fake_i8(a), fake_i32(a)));
    types::Ty* arr = types::intern_array(s, 3);
    if(!testing::expect_eq(types::size_of(null, arr), (u32)24, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, arr), (u32)4,  m)) { return -2; }
    return 0;
}

// ===== size_of / align_of — structs =====

fn i32 layout_empty_struct(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params0());
    if(!testing::expect_eq(types::size_of(null, s), (u32)0, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, s), (u32)1, m)) { return -2; }
    return 0;
}

fn i32 layout_struct_one_i8(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params1(a, fake_i8(a)));
    if(!testing::expect_eq(types::size_of(null, s), (u32)1, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, s), (u32)1, m)) { return -2; }
    return 0;
}

fn i32 layout_struct_one_i32(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params1(a, fake_i32(a)));
    if(!testing::expect_eq(types::size_of(null, s), (u32)4, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, s), (u32)4, m)) { return -2; }
    return 0;
}

fn i32 layout_struct_i8_i32(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params2(a, fake_i8(a), fake_i32(a)));
    if(!testing::expect_eq(types::size_of(null, s), (u32)8, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, s), (u32)4, m)) { return -2; }
    return 0;
}

fn i32 layout_struct_i32_i8(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params2(a, fake_i32(a), fake_i8(a)));
    if(!testing::expect_eq(types::size_of(null, s), (u32)8, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, s), (u32)4, m)) { return -2; }
    return 0;
}

fn i32 layout_struct_i8_i8_i32(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params3(a, fake_i8(a), fake_i8(a), fake_i32(a)));
    if(!testing::expect_eq(types::size_of(null, s), (u32)8, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, s), (u32)4, m)) { return -2; }
    return 0;
}

fn i32 layout_struct_i8_i64(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params2(a, fake_i8(a), fake_i64(a)));
    if(!testing::expect_eq(types::size_of(null, s), (u32)16, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, s), (u32)8,  m)) { return -2; }
    return 0;
}

fn i32 layout_struct_ptr_i8(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* ptr = types::intern_pointer(fake_i32(a), false);
    types::Ty* s = fake_struct_typed(a, mk_params2(a, ptr, fake_i8(a)));
    if(!testing::expect_eq(types::size_of(null, s), (u32)16, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, s), (u32)8,  m)) { return -2; }
    return 0;
}

fn i32 layout_struct_array_field(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* arr = types::intern_array(fake_i8(a), 3);
    types::Ty* s = fake_struct_typed(a, mk_params2(a, arr, fake_i32(a)));
    if(!testing::expect_eq(types::size_of(null, s), (u32)8, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, s), (u32)4, m)) { return -2; }
    return 0;
}

fn i32 layout_struct_slice_field(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* slc = types::intern_slice(fake_u8(a));
    types::Ty* s = fake_struct_typed(a, mk_params2(a, slc, fake_i32(a)));
    if(!testing::expect_eq(types::size_of(null, s), (u32)24, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, s), (u32)8,  m)) { return -2; }
    return 0;
}

fn i32 layout_struct_three_i32(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params3(a, fake_i32(a), fake_i32(a), fake_i32(a)));
    if(!testing::expect_eq(types::size_of(null, s), (u32)12, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, s), (u32)4,  m)) { return -2; }
    return 0;
}

fn i32 layout_struct_nested(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* inner = fake_struct_typed(a, mk_params2(a, fake_i8(a), fake_i32(a)));
    types::Ty* outer = fake_struct_typed(a, mk_params2(a, inner, fake_i8(a)));
    if(!testing::expect_eq(types::size_of(null, outer), (u32)12, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, outer), (u32)4,  m)) { return -2; }
    return 0;
}

fn i32 layout_struct_with_fnptr(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* fp = types::intern_fn_ptr(fake_void(a), mk_params0(), false);
    types::Ty* s = fake_struct_typed(a, mk_params2(a, fp, fake_i8(a)));
    if(!testing::expect_eq(types::size_of(null, s), (u32)16, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, s), (u32)8,  m)) { return -2; }
    return 0;
}

// ===== struct offsets =====

fn i32 layout_struct_offsets_dense_i32(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params3(a, fake_i32(a), fake_i32(a), fake_i32(a)));
    types::size_of(null, s);
    if(!testing::expect_ne((void*)s.layout, null, m)) { return -1; }
    if(!testing::expect_eq(s.layout.offsets[0], (u32)0, m)) { return -2; }
    if(!testing::expect_eq(s.layout.offsets[1], (u32)4, m)) { return -3; }
    if(!testing::expect_eq(s.layout.offsets[2], (u32)8, m)) { return -4; }
    return 0;
}

fn i32 layout_struct_offsets_i8_i32(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params2(a, fake_i8(a), fake_i32(a)));
    types::size_of(null, s);
    if(!testing::expect_eq(s.layout.offsets[0], (u32)0, m)) { return -1; }
    if(!testing::expect_eq(s.layout.offsets[1], (u32)4, m)) { return -2; }
    return 0;
}

fn i32 layout_struct_offsets_i32_i8(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params2(a, fake_i32(a), fake_i8(a)));
    types::size_of(null, s);
    if(!testing::expect_eq(s.layout.offsets[0], (u32)0, m)) { return -1; }
    if(!testing::expect_eq(s.layout.offsets[1], (u32)4, m)) { return -2; }
    return 0;
}

fn i32 layout_struct_offsets_i8_i8_i32(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params3(a, fake_i8(a), fake_i8(a), fake_i32(a)));
    types::size_of(null, s);
    if(!testing::expect_eq(s.layout.offsets[0], (u32)0, m)) { return -1; }
    if(!testing::expect_eq(s.layout.offsets[1], (u32)1, m)) { return -2; }
    if(!testing::expect_eq(s.layout.offsets[2], (u32)4, m)) { return -3; }
    return 0;
}

fn i32 layout_struct_offsets_i8_i64(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params2(a, fake_i8(a), fake_i64(a)));
    types::size_of(null, s);
    if(!testing::expect_eq(s.layout.offsets[0], (u32)0, m)) { return -1; }
    if(!testing::expect_eq(s.layout.offsets[1], (u32)8, m)) { return -2; }
    return 0;
}

fn i32 layout_struct_offsets_single_field(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params1(a, fake_i32(a)));
    types::size_of(null, s);
    if(!testing::expect_eq(s.layout.offsets[0], (u32)0, m)) { return -1; }
    return 0;
}

// ===== size_of / align_of — unions =====

fn i32 layout_empty_union(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* u = fake_union_typed(a, mk_params0());
    if(!testing::expect_eq(types::size_of(null, u), (u32)0, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, u), (u32)1, m)) { return -2; }
    return 0;
}

fn i32 layout_union_one_i8(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* u = fake_union_typed(a, mk_params1(a, fake_i8(a)));
    if(!testing::expect_eq(types::size_of(null, u), (u32)1, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, u), (u32)1, m)) { return -2; }
    return 0;
}

fn i32 layout_union_i8_i32(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* u = fake_union_typed(a, mk_params2(a, fake_i8(a), fake_i32(a)));
    if(!testing::expect_eq(types::size_of(null, u), (u32)4, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, u), (u32)4, m)) { return -2; }
    return 0;
}

fn i32 layout_union_i64_i8(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* u = fake_union_typed(a, mk_params2(a, fake_i64(a), fake_i8(a)));
    if(!testing::expect_eq(types::size_of(null, u), (u32)8, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, u), (u32)8, m)) { return -2; }
    return 0;
}

fn i32 layout_union_i8_i64(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* u = fake_union_typed(a, mk_params2(a, fake_i8(a), fake_i64(a)));
    if(!testing::expect_eq(types::size_of(null, u), (u32)8, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, u), (u32)8, m)) { return -2; }
    return 0;
}

fn i32 layout_union_with_slice(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* slc = types::intern_slice(fake_i32(a));
    types::Ty* u = fake_union_typed(a, mk_params2(a, slc, fake_i32(a)));
    if(!testing::expect_eq(types::size_of(null, u), (u32)16, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, u), (u32)8,  m)) { return -2; }
    return 0;
}

fn i32 layout_union_with_pointer(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* ptr = types::intern_pointer(fake_i32(a), false);
    types::Ty* u = fake_union_typed(a, mk_params2(a, ptr, fake_i32(a)));
    if(!testing::expect_eq(types::size_of(null, u), (u32)8, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, u), (u32)8, m)) { return -2; }
    return 0;
}

fn i32 layout_union_offsets_all_zero(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* u = fake_union_typed(a, mk_params3(a, fake_i8(a), fake_i32(a), fake_i64(a)));
    types::size_of(null, u);
    if(!testing::expect_ne((void*)u.layout, null, m)) { return -1; }
    if(!testing::expect_eq(u.layout.offsets[0], (u32)0, m)) { return -2; }
    if(!testing::expect_eq(u.layout.offsets[1], (u32)0, m)) { return -3; }
    if(!testing::expect_eq(u.layout.offsets[2], (u32)0, m)) { return -4; }
    return 0;
}

// ===== size_of / align_of — enums =====

fn i32 layout_enum_i32_base(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* e = fake_enum_with_base(a, fake_i32(a));
    if(!testing::expect_eq(types::size_of(null, e), (u32)4, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, e), (u32)4, m)) { return -2; }
    return 0;
}

fn i32 layout_enum_i8_base(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* e = fake_enum_with_base(a, fake_i8(a));
    if(!testing::expect_eq(types::size_of(null, e), (u32)1, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, e), (u32)1, m)) { return -2; }
    return 0;
}

fn i32 layout_enum_u64_base(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* e = fake_enum_with_base(a, fake_u64(a));
    if(!testing::expect_eq(types::size_of(null, e), (u32)8, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, e), (u32)8, m)) { return -2; }
    return 0;
}

fn i32 layout_enum_null_base_defaults_i32(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* e = types::intern_enum((void*)fake_enum_decl_null_base(a));
    if(!testing::expect_eq(types::size_of(null, e), (u32)4, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, e), (u32)4, m)) { return -2; }
    return 0;
}

// ===== ComptimeType =====

fn i32 layout_comptime_zero(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* c = fake_comptime(a);
    if(!testing::expect_eq(types::size_of(null, c), (u32)0, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, c), (u32)0, m)) { return -2; }
    return 0;
}

// ===== layout flag / cache behavior =====

fn i32 layout_struct_sets_computed_flag(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params1(a, fake_i32(a)));
    if(!testing::expect_eq(has_flag(s, types::LayoutFlags::Computed), false, m)) { return -1; }
    types::size_of(null, s);
    if(!testing::expect_eq(has_flag(s, types::LayoutFlags::Computed), true, m)) { return -2; }
    return 0;
}

fn i32 layout_caching_returns_same(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params2(a, fake_i8(a), fake_i32(a)));
    u32 sz1 = types::size_of(null, s);
    u32 sz2 = types::size_of(null, s);
    u32 al1 = types::align_of(null, s);
    u32 al2 = types::align_of(null, s);
    if(!testing::expect_eq(sz1, sz2, m)) { return -1; }
    if(!testing::expect_eq(al1, al2, m)) { return -2; }
    if(!testing::expect_eq(sz1, (u32)8, m)) { return -3; }
    return 0;
}

fn i32 layout_array_sets_computed_flag(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* arr = types::intern_array(fake_i32(a), 4);
    if(!testing::expect_eq(has_flag(arr, types::LayoutFlags::Computed), false, m)) { return -1; }
    types::size_of(null, arr);
    if(!testing::expect_eq(has_flag(arr, types::LayoutFlags::Computed), true, m)) { return -2; }
    return 0;
}

fn i32 layout_struct_sets_layout_pointer(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params1(a, fake_i32(a)));
    if(!testing::expect_eq((void*)s.layout, null, m)) { return -1; }
    types::size_of(null, s);
    if(!testing::expect_ne((void*)s.layout, null, m)) { return -2; }
    if(!testing::expect_eq(s.layout.offsets.len, (u64)1, m)) { return -3; }
    return 0;
}

fn i32 layout_union_sets_layout_pointer(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* u = fake_union_typed(a, mk_params2(a, fake_i8(a), fake_i64(a)));
    if(!testing::expect_eq((void*)u.layout, null, m)) { return -1; }
    types::size_of(null, u);
    if(!testing::expect_ne((void*)u.layout, null, m)) { return -2; }
    if(!testing::expect_eq(u.layout.offsets.len, (u64)2, m)) { return -3; }
    return 0;
}

fn i32 layout_array_layout_stays_null(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* arr = types::intern_array(fake_i32(a), 4);
    types::size_of(null, arr);
    if(!testing::expect_eq((void*)arr.layout, null, m)) { return -1; }
    return 0;
}

fn i32 layout_pointer_layout_stays_null(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* p = types::intern_pointer(fake_i32(a), false);
    types::size_of(null, p);
    if(!testing::expect_eq((void*)p.layout, null, m)) { return -1; }
    return 0;
}

// ===== cycle detection =====

fn i32 cycle_self_struct_non_pointer_returns_zero(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    ast::StructDeclNode* decl = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    sys::memset(decl, 0, sizeof(ast::StructDeclNode));
    ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, sizeof(ast::FieldDecl));
    sys::memset(fields, 0, sizeof(ast::FieldDecl));
    decl.fields = {fields, 1};
    types::Ty* s = types::intern_struct((void*)decl);
    fields[0].resolved_type = (void*)s;
    u32 sz = types::size_of(null, s);
    if(!testing::expect_eq(sz, (u32)0, m)) { return -1; }
    return 0;
}

fn i32 cycle_self_struct_pointer_field_returns_eight(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    ast::StructDeclNode* decl = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    sys::memset(decl, 0, sizeof(ast::StructDeclNode));
    ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, sizeof(ast::FieldDecl));
    sys::memset(fields, 0, sizeof(ast::FieldDecl));
    decl.fields = {fields, 1};
    types::Ty* s = types::intern_struct((void*)decl);
    types::Ty* ps = types::intern_pointer(s, false);
    fields[0].resolved_type = (void*)ps;
    u32 sz = types::size_of(null, s);
    if(!testing::expect_eq(sz, (u32)8, m)) { return -1; }
    return 0;
}

fn i32 cycle_mutual_struct_pointer_fields_both_eight(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    ast::StructDeclNode* d_a = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    ast::StructDeclNode* d_b = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    sys::memset(d_a, 0, sizeof(ast::StructDeclNode));
    sys::memset(d_b, 0, sizeof(ast::StructDeclNode));
    ast::FieldDecl* f_a = (ast::FieldDecl*)arena::alloc(a, sizeof(ast::FieldDecl));
    ast::FieldDecl* f_b = (ast::FieldDecl*)arena::alloc(a, sizeof(ast::FieldDecl));
    sys::memset(f_a, 0, sizeof(ast::FieldDecl));
    sys::memset(f_b, 0, sizeof(ast::FieldDecl));
    d_a.fields = {f_a, 1};
    d_b.fields = {f_b, 1};
    types::Ty* ta = types::intern_struct((void*)d_a);
    types::Ty* tb = types::intern_struct((void*)d_b);
    f_a[0].resolved_type = (void*)types::intern_pointer(tb, false);
    f_b[0].resolved_type = (void*)types::intern_pointer(ta, false);
    if(!testing::expect_eq(types::size_of(null, ta), (u32)8, m)) { return -1; }
    if(!testing::expect_eq(types::size_of(null, tb), (u32)8, m)) { return -2; }
    return 0;
}




// ===== cross-module layout consistency =====

// ===== Opaque preservation + size_of/align_of error =====

fn types::Ty* fake_opaque_struct(arena::Arena* a) {
    types::Ty* t = types::intern_struct(fake_decl(a));
    t.flags = (types::LayoutFlags)((u8)t.flags | (u8)types::LayoutFlags::Opaque);
    return t;
}

fn types::Ty* fake_opaque_union(arena::Arena* a) {
    types::Ty* t = types::intern_union(fake_decl(a));
    t.flags = (types::LayoutFlags)((u8)t.flags | (u8)types::LayoutFlags::Opaque);
    return t;
}

fn i32 opaque_struct_size_of_reports_diag(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    types::Ty* s = fake_opaque_struct(a);
    u32 sz = types::size_of(d, s);
    if(!testing::expect_eq(sz, (u32)0, m)) { return -1; }
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -2; }
    if(!testing::expect_eq(d.entries[0].is_warning, false, m)) { return -3; }
    return 0;
}

fn i32 opaque_struct_align_of_reports_diag(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    types::Ty* s = fake_opaque_struct(a);
    u32 al = types::align_of(d, s);
    if(!testing::expect_eq(al, (u32)0, m)) { return -1; }
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -2; }
    return 0;
}

fn i32 opaque_size_of_reports_every_call(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    types::Ty* s = fake_opaque_struct(a);
    types::size_of(d, s);
    types::size_of(d, s);
    types::size_of(d, s);
    if(!testing::expect_eq(d.entries.len, (u64)3, m)) { return -1; }
    return 0;
}

fn i32 opaque_does_not_set_layout(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_opaque_struct(a);
    types::size_of(null, s);
    if(!testing::expect_eq((void*)s.layout, null, m)) { return -1; }
    if(!testing::expect_eq(has_flag(s, types::LayoutFlags::Computed), false, m)) { return -2; }
    return 0;
}

fn i32 opaque_union_size_reports_diag(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    types::Ty* u = fake_opaque_union(a);
    u32 sz = types::size_of(d, u);
    if(!testing::expect_eq(sz, (u32)0, m)) { return -1; }
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -2; }
    return 0;
}

fn i32 opaque_with_null_diag_no_crash(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_opaque_struct(a);
    if(!testing::expect_eq(types::size_of(null, s), (u32)0, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, s), (u32)0, m)) { return -2; }
    return 0;
}

// ===== ComptimeType / cycle — diag reporting =====

fn i32 comptime_size_of_reports_diag(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    types::Ty* c = fake_comptime(a);
    types::size_of(d, c);
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -1; }
    if(!testing::expect_eq(d.entries[0].is_warning, false, m)) { return -2; }
    return 0;
}

fn i32 comptime_with_null_diag_no_crash(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* c = fake_comptime(a);
    if(!testing::expect_eq(types::size_of(null, c), (u32)0, m)) { return -1; }
    return 0;
}

fn i32 cycle_self_struct_reports_diag(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    ast::StructDeclNode* decl = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    sys::memset(decl, 0, sizeof(ast::StructDeclNode));
    ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, sizeof(ast::FieldDecl));
    sys::memset(fields, 0, sizeof(ast::FieldDecl));
    decl.fields = {fields, 1};
    types::Ty* s = types::intern_struct((void*)decl);
    fields[0].resolved_type = (void*)s;
    types::size_of(d, s);
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -1; }
    if(!testing::expect_eq(d.entries[0].is_warning, false, m)) { return -2; }
    return 0;
}

fn i32 cycle_mutual_struct_non_pointer_both_zero(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    ast::StructDeclNode* d_a = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    ast::StructDeclNode* d_b = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    sys::memset(d_a, 0, sizeof(ast::StructDeclNode));
    sys::memset(d_b, 0, sizeof(ast::StructDeclNode));
    ast::FieldDecl* f_a = (ast::FieldDecl*)arena::alloc(a, sizeof(ast::FieldDecl));
    ast::FieldDecl* f_b = (ast::FieldDecl*)arena::alloc(a, sizeof(ast::FieldDecl));
    sys::memset(f_a, 0, sizeof(ast::FieldDecl));
    sys::memset(f_b, 0, sizeof(ast::FieldDecl));
    d_a.fields = {f_a, 1};
    d_b.fields = {f_b, 1};
    types::Ty* ta = types::intern_struct((void*)d_a);
    types::Ty* tb = types::intern_struct((void*)d_b);
    f_a[0].resolved_type = (void*)tb;
    f_b[0].resolved_type = (void*)ta;
    if(!testing::expect_eq(types::size_of(null, ta), (u32)0, m)) { return -1; }
    if(!testing::expect_eq(types::size_of(null, tb), (u32)0, m)) { return -2; }
    return 0;
}

// ===== null resolved_type guard =====

fn i32 layout_struct_null_field_skipped(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    ast::StructDeclNode* decl = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    sys::memset(decl, 0, sizeof(ast::StructDeclNode));
    ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, 2 * sizeof(ast::FieldDecl));
    sys::memset(fields, 0, 2 * sizeof(ast::FieldDecl));
    fields[1].resolved_type = (void*)fake_i32(a);
    decl.fields = {fields, 2};
    types::Ty* s = types::intern_struct((void*)decl);
    if(!testing::expect_eq(types::size_of(null, s), (u32)4, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, s), (u32)4, m)) { return -2; }
    return 0;
}

fn i32 layout_union_null_field_skipped(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    ast::UnionDeclNode* decl = (ast::UnionDeclNode*)arena::alloc(a, sizeof(ast::UnionDeclNode));
    sys::memset(decl, 0, sizeof(ast::UnionDeclNode));
    ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, 2 * sizeof(ast::FieldDecl));
    sys::memset(fields, 0, 2 * sizeof(ast::FieldDecl));
    fields[1].resolved_type = (void*)fake_i64(a);
    decl.fields = {fields, 2};
    types::Ty* u = types::intern_union((void*)decl);
    if(!testing::expect_eq(types::size_of(null, u), (u32)8, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, u), (u32)8, m)) { return -2; }
    return 0;
}

fn i32 layout_empty_struct_has_layout(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params0());
    types::size_of(null, s);
    if(!testing::expect_ne((void*)s.layout, null, m)) { return -1; }
    if(!testing::expect_eq(s.layout.offsets.len, (u64)0, m)) { return -2; }
    return 0;
}

fn i32 layout_struct_with_bool(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params2(a, fake_bool(a), fake_i32(a)));
    if(!testing::expect_eq(types::size_of(null, s), (u32)8, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, s), (u32)4, m)) { return -2; }
    if(!testing::expect_eq(s.layout.offsets[0], (u32)0, m)) { return -3; }
    if(!testing::expect_eq(s.layout.offsets[1], (u32)4, m)) { return -4; }
    return 0;
}

fn i32 layout_struct_with_float(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = fake_struct_typed(a, mk_params2(a, fake_i32(a), fake_f64(a)));
    if(!testing::expect_eq(types::size_of(null, s), (u32)16, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, s), (u32)8,  m)) { return -2; }
    if(!testing::expect_eq(s.layout.offsets[0], (u32)0, m)) { return -3; }
    if(!testing::expect_eq(s.layout.offsets[1], (u32)8, m)) { return -4; }
    return 0;
}

fn i32 layout_struct_offsets_with_slice(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* slc = types::intern_slice(fake_i32(a));
    types::Ty* s = fake_struct_typed(a, mk_params2(a, slc, fake_i32(a)));
    types::size_of(null, s);
    if(!testing::expect_eq(s.layout.offsets[0], (u32)0,  m)) { return -1; }
    if(!testing::expect_eq(s.layout.offsets[1], (u32)16, m)) { return -2; }
    return 0;
}

fn i32 layout_struct_offsets_with_pointer(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* ptr = types::intern_pointer(fake_i32(a), false);
    types::Ty* s = fake_struct_typed(a, mk_params3(a, fake_i8(a), ptr, fake_i32(a)));
    types::size_of(null, s);
    if(!testing::expect_eq(s.layout.offsets[0], (u32)0,  m)) { return -1; }
    if(!testing::expect_eq(s.layout.offsets[1], (u32)8,  m)) { return -2; }
    if(!testing::expect_eq(s.layout.offsets[2], (u32)16, m)) { return -3; }
    return 0;
}

fn i32 layout_struct_offsets_with_nested_struct(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* inner = fake_struct_typed(a, mk_params2(a, fake_i8(a), fake_i32(a)));
    types::Ty* outer = fake_struct_typed(a, mk_params2(a, fake_i32(a), inner));
    types::size_of(null, outer);
    if(!testing::expect_eq(outer.layout.offsets[0], (u32)0, m)) { return -1; }
    if(!testing::expect_eq(outer.layout.offsets[1], (u32)4, m)) { return -2; }
    return 0;
}

fn i32 layout_array_of_fnptr(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* fp  = types::intern_fn_ptr(fake_void(a), mk_params0(), false);
    types::Ty* arr = types::intern_array(fp, 4);
    if(!testing::expect_eq(types::size_of(null, arr), (u32)32, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, arr), (u32)8,  m)) { return -2; }
    return 0;
}

fn i32 layout_array_of_union(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* u   = fake_union_typed(a, mk_params2(a, fake_i64(a), fake_i8(a)));
    types::Ty* arr = types::intern_array(u, 3);
    if(!testing::expect_eq(types::size_of(null, arr), (u32)24, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, arr), (u32)8,  m)) { return -2; }
    return 0;
}

fn i32 layout_array_of_enum(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* e   = fake_enum_with_base(a, fake_i32(a));
    types::Ty* arr = types::intern_array(e, 5);
    if(!testing::expect_eq(types::size_of(null, arr), (u32)20, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, arr), (u32)4,  m)) { return -2; }
    return 0;
}

fn i32 layout_pointer_to_fnptr(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* fp = types::intern_fn_ptr(fake_void(a), mk_params0(), false);
    types::Ty* p  = types::intern_pointer(fp, false);
    if(!testing::expect_eq(types::size_of(null, p), (u32)8, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, p), (u32)8, m)) { return -2; }
    return 0;
}

fn i32 layout_pointer_to_enum(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* e = fake_enum_with_base(a, fake_i64(a));
    types::Ty* p = types::intern_pointer(e, false);
    if(!testing::expect_eq(types::size_of(null, p), (u32)8, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, p), (u32)8, m)) { return -2; }
    return 0;
}

fn i32 layout_enum_caches_after_first(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* e = fake_enum_with_base(a, fake_i32(a));
    if(!testing::expect_eq(has_flag(e, types::LayoutFlags::Computed), false, m)) { return -1; }
    types::size_of(null, e);
    if(!testing::expect_eq(has_flag(e, types::LayoutFlags::Computed), true, m)) { return -2; }
    u32 a2 = types::align_of(null, e);
    if(!testing::expect_eq(a2, (u32)4, m)) { return -3; }
    return 0;
}

fn i32 layout_slice_layout_stays_null(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = types::intern_slice(fake_i32(a));
    types::size_of(null, s);
    if(!testing::expect_eq((void*)s.layout, null, m)) { return -1; }
    return 0;
}

fn i32 layout_fnptr_layout_stays_null(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* f = types::intern_fn_ptr(fake_void(a), mk_params0(), false);
    types::size_of(null, f);
    if(!testing::expect_eq((void*)f.layout, null, m)) { return -1; }
    return 0;
}

fn i32 layout_enum_layout_stays_null(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* e = fake_enum_with_base(a, fake_i32(a));
    types::size_of(null, e);
    if(!testing::expect_eq((void*)e.layout, null, m)) { return -1; }
    return 0;
}

fn i32 layout_3d_array(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* a1 = types::intern_array(fake_i32(a), 2);
    types::Ty* a2 = types::intern_array(a1, 3);
    types::Ty* a3 = types::intern_array(a2, 4);
    if(!testing::expect_eq(types::size_of(null, a3), (u32)96, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, a3), (u32)4,  m)) { return -2; }
    return 0;
}

fn i32 layout_slice_of_struct(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s   = fake_struct_typed(a, mk_params2(a, fake_i8(a), fake_i32(a)));
    types::Ty* slc = types::intern_slice(s);
    if(!testing::expect_eq(types::size_of(null, slc), (u32)16, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, slc), (u32)8,  m)) { return -2; }
    return 0;
}

fn i32 layout_slice_of_array(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* arr = types::intern_array(fake_i32(a), 5);
    types::Ty* slc = types::intern_slice(arr);
    if(!testing::expect_eq(types::size_of(null, slc), (u32)16, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, slc), (u32)8,  m)) { return -2; }
    return 0;
}

fn i32 layout_pointer_to_opaque_no_diag(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    types::Ty* s = fake_opaque_struct(a);
    types::Ty* p = types::intern_pointer(s, false);
    if(!testing::expect_eq(types::size_of(d, p), (u32)8, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(d, p), (u32)8, m)) { return -2; }
    if(!testing::expect_eq(d.entries.len, (u64)0, m)) { return -3; }
    return 0;
}

fn i32 layout_array_of_pointer_to_opaque_no_diag(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    types::Ty* s   = fake_opaque_struct(a);
    types::Ty* p   = types::intern_pointer(s, false);
    types::Ty* arr = types::intern_array(p, 4);
    if(!testing::expect_eq(types::size_of(d, arr), (u32)32, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(d, arr), (u32)8,  m)) { return -2; }
    if(!testing::expect_eq(d.entries.len, (u64)0, m)) { return -3; }
    return 0;
}

fn i32 cycle_struct_through_array_field(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    ast::StructDeclNode* decl = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    sys::memset(decl, 0, sizeof(ast::StructDeclNode));
    ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, sizeof(ast::FieldDecl));
    sys::memset(fields, 0, sizeof(ast::FieldDecl));
    decl.fields = {fields, 1};
    types::Ty* s   = types::intern_struct((void*)decl);
    types::Ty* arr = types::intern_array(s, 3);
    fields[0].resolved_type = (void*)arr;
    if(!testing::expect_eq(types::size_of(null, s), (u32)0, m)) { return -1; }
    return 0;
}

fn i32 cycle_union_through_value(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    ast::UnionDeclNode* decl = (ast::UnionDeclNode*)arena::alloc(a, sizeof(ast::UnionDeclNode));
    sys::memset(decl, 0, sizeof(ast::UnionDeclNode));
    ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, sizeof(ast::FieldDecl));
    sys::memset(fields, 0, sizeof(ast::FieldDecl));
    decl.fields = {fields, 1};
    types::Ty* u = types::intern_union((void*)decl);
    fields[0].resolved_type = (void*)u;
    if(!testing::expect_eq(types::size_of(null, u), (u32)0, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(null, u), (u32)1, m)) { return -2; }
    return 0;
}

fn i32 cycle_union_reports_diag(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    ast::UnionDeclNode* decl = (ast::UnionDeclNode*)arena::alloc(a, sizeof(ast::UnionDeclNode));
    sys::memset(decl, 0, sizeof(ast::UnionDeclNode));
    ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, sizeof(ast::FieldDecl));
    sys::memset(fields, 0, sizeof(ast::FieldDecl));
    decl.fields = {fields, 1};
    types::Ty* u = types::intern_union((void*)decl);
    fields[0].resolved_type = (void*)u;
    types::size_of(d, u);
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -1; }
    return 0;
}

fn i32 cycle_diag_src_pos_matches_decl(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    ast::StructDeclNode* decl = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    sys::memset(decl, 0, sizeof(ast::StructDeclNode));
    decl.h.src_pos = 4242;
    ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, sizeof(ast::FieldDecl));
    sys::memset(fields, 0, sizeof(ast::FieldDecl));
    decl.fields = {fields, 1};
    types::Ty* s = types::intern_struct((void*)decl);
    fields[0].resolved_type = (void*)s;
    types::size_of(d, s);
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -1; }
    if(!testing::expect_eq(d.entries[0].src_pos, (u32)4242, m)) { return -2; }
    return 0;
}

fn i32 comptime_diag_msg_content(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    types::size_of(d, fake_comptime(a));
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -1; }
    u8[] expected = "Type has no runtime size";
    if(!testing::expect_eq(d.entries[0].msg, expected, m)) { return -2; }
    return 0;
}

fn i32 cycle_diag_msg_content(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    ast::StructDeclNode* decl = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    sys::memset(decl, 0, sizeof(ast::StructDeclNode));
    ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, sizeof(ast::FieldDecl));
    sys::memset(fields, 0, sizeof(ast::FieldDecl));
    decl.fields = {fields, 1};
    types::Ty* s = types::intern_struct((void*)decl);
    fields[0].resolved_type = (void*)s;
    types::size_of(d, s);
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -1; }
    u8[] expected = "type has infinite size (cycle through non-pointer fields)";
    if(!testing::expect_eq(d.entries[0].msg, expected, m)) { return -2; }
    return 0;
}

fn i32 opaque_diag_msg_content(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    types::Ty* s = fake_opaque_struct(a);
    types::size_of(d, s);
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -1; }
    u8[] expected = "cannot take size of opaque type";
    if(!testing::expect_eq(d.entries[0].msg, expected, m)) { return -2; }
    return 0;
}

fn i32 union_lazy_layout(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* u = types::intern_union(fake_decl(a));
    if(!testing::expect_eq(has_flag(u, types::LayoutFlags::Computed), false, m)) { return -1; }
    return 0;
}

fn i32 enum_lazy_layout(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* e = types::intern_enum(fake_decl(a));
    if(!testing::expect_eq(has_flag(e, types::LayoutFlags::Computed), false, m)) { return -1; }
    return 0;
}

fn i32 layout_struct_multiple_opaque_fields_reports_each(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    types::Ty* opaque_a = fake_opaque_struct(a);
    types::Ty* opaque_b = fake_opaque_struct(a);
    types::Ty* s = fake_struct_typed(a, mk_params2(a, opaque_a, opaque_b));
    u32 size = types::size_of(d, s);
    if(!testing::expect_eq(size, (u32)0, m)) { return -1; }
    if(!testing::expect_eq(d.entries.len, (u64)2, m)) { return -2; }
    return 0;
}

fn i32 cycle_struct_with_valid_field(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    ast::StructDeclNode* decl = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    sys::memset(decl, 0, sizeof(ast::StructDeclNode));
    ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, 2 * sizeof(ast::FieldDecl));
    sys::memset(fields, 0, 2 * sizeof(ast::FieldDecl));
    decl.fields = {fields, 2};
    types::Ty* s = types::intern_struct((void*)decl);
    fields[0].resolved_type = (void*)s;
    fields[1].resolved_type = (void*)fake_i32(a);
    if(!testing::expect_eq(types::size_of(d, s), (u32)4, m)) { return -1; }
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -2; }
    return 0;
}

fn i32 cycle_self_struct_align_of_reports_and_returns_one(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    ast::StructDeclNode* decl = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    sys::memset(decl, 0, sizeof(ast::StructDeclNode));
    ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, sizeof(ast::FieldDecl));
    sys::memset(fields, 0, sizeof(ast::FieldDecl));
    decl.fields = {fields, 1};
    types::Ty* s = types::intern_struct((void*)decl);
    fields[0].resolved_type = (void*)s;
    if(!testing::expect_eq(types::align_of(d, s), (u32)1, m)) { return -1; }
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -2; }
    return 0;
}

fn i32 layout_union_with_opaque_field(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    types::Ty* opaque_s = fake_opaque_struct(a);
    types::Ty* u = fake_union_typed(a, mk_params1(a, opaque_s));
    if(!testing::expect_eq(types::size_of(d, u), (u32)0, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(d, u), (u32)1, m)) { return -2; }
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -3; }
    return 0;
}

fn i32 layout_struct_with_comptime_field_reports_diag(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    types::Ty* c = fake_comptime(a);
    types::Ty* s = fake_struct_typed(a, mk_params2(a, c, fake_i32(a)));
    u32 size = types::size_of(d, s);
    if(!testing::expect_eq(size, (u32)4, m)) { return -1; }
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -2; }
    return 0;
}

fn i32 layout_union_with_comptime_field_reports_diag(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    types::Ty* c = fake_comptime(a);
    types::Ty* u = fake_union_typed(a, mk_params2(a, c, fake_i32(a)));
    u32 size = types::size_of(d, u);
    if(!testing::expect_eq(size, (u32)4, m)) { return -1; }
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -2; }
    return 0;
}

fn i32 layout_array_of_comptime_reports_diag(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    types::Ty* c   = fake_comptime(a);
    types::Ty* arr = types::intern_array(c, 3);
    types::size_of(d, arr);
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -1; }
    return 0;
}

fn i32 layout_array_of_opaque_reports_diag(arena::Arena* a, u8[] m) {
    diag::DiagBuf* d = fresh_diag(a);
    types::typer_init(a, 16);
    types::Ty* op  = fake_opaque_struct(a);
    types::Ty* arr = types::intern_array(op, 3);
    if(!testing::expect_eq(types::size_of(d, arr), (u32)0, m)) { return -1; }
    if(!testing::expect_eq(types::align_of(d, arr), (u32)1, m)) { return -2; }
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -3; }
    return 0;
}

// ===== PrimitiveTable + accessors =====

fn bool check_prim_fields(types::Ty* t, types::PrimitiveKind p, u32 size, u32 align, u8[] m) {
    if(!testing::expect_eq((u64)t.kind, (u64)types::TypeKind::Primitive, m)) { return false; }
    if(!testing::expect_eq((u64)t.prim, (u64)p, m)) { return false; }
    if(!testing::expect_eq(t.size,  size,  m)) { return false; }
    if(!testing::expect_eq(t.align, align, m)) { return false; }
    if(!testing::expect_eq(has_flag(t, types::LayoutFlags::Computed), true, m)) { return false; }
    return true;
}

fn i32 prim_signed_ints_have_correct_fields(arena::Arena* a, u8[] m) {
    if(!check_prim_fields(types::prim_i8 (), types::PrimitiveKind::I8,  1, 1, m)) { return -1; }
    if(!check_prim_fields(types::prim_i16(), types::PrimitiveKind::I16, 2, 2, m)) { return -2; }
    if(!check_prim_fields(types::prim_i32(), types::PrimitiveKind::I32, 4, 4, m)) { return -3; }
    if(!check_prim_fields(types::prim_i64(), types::PrimitiveKind::I64, 8, 8, m)) { return -4; }
    return 0;
}

fn i32 prim_unsigned_ints_have_correct_fields(arena::Arena* a, u8[] m) {
    if(!check_prim_fields(types::prim_u8 (), types::PrimitiveKind::U8,  1, 1, m)) { return -1; }
    if(!check_prim_fields(types::prim_u16(), types::PrimitiveKind::U16, 2, 2, m)) { return -2; }
    if(!check_prim_fields(types::prim_u32(), types::PrimitiveKind::U32, 4, 4, m)) { return -3; }
    if(!check_prim_fields(types::prim_u64(), types::PrimitiveKind::U64, 8, 8, m)) { return -4; }
    return 0;
}

fn i32 prim_floats_have_correct_fields(arena::Arena* a, u8[] m) {
    if(!check_prim_fields(types::prim_f32(), types::PrimitiveKind::F32, 4, 4, m)) { return -1; }
    if(!check_prim_fields(types::prim_f64(), types::PrimitiveKind::F64, 8, 8, m)) { return -2; }
    return 0;
}

fn i32 prim_bool_has_correct_fields(arena::Arena* a, u8[] m) {
    if(!check_prim_fields(types::prim_bool(), types::PrimitiveKind::BOOL, 1, 1, m)) { return -1; }
    return 0;
}

fn i32 prim_void_has_correct_fields(arena::Arena* a, u8[] m) {
    if(!check_prim_fields(types::prim_void(), types::PrimitiveKind::VOID, 0, 1, m)) { return -1; }
    return 0;
}

fn i32 prim_type_has_correct_fields(arena::Arena* a, u8[] m) {
    types::Ty* t = types::prim_type();
    if(!testing::expect_eq((u64)t.kind, (u64)types::TypeKind::ComptimeType, m)) { return -1; }
    if(!testing::expect_eq((u64)t.prim, (u64)types::PrimitiveKind::NONE,    m)) { return -2; }
    if(!testing::expect_eq(has_flag(t, types::LayoutFlags::Computed), true, m)) { return -3; }
    return 0;
}

fn i32 prim_null_ptr_has_correct_fields(arena::Arena* a, u8[] m) {
    types::Ty* t = types::prim_null_ptr();
    if(!testing::expect_eq((u64)t.kind, (u64)types::TypeKind::Pointer,   m)) { return -1; }
    if(!testing::expect_eq((u64)t.prim, (u64)types::PrimitiveKind::NONE, m)) { return -2; }
    if(!testing::expect_eq(t.size,  (u32)8, m)) { return -3; }
    if(!testing::expect_eq(t.align, (u32)8, m)) { return -4; }
    if(!testing::expect_eq(has_flag(t, types::LayoutFlags::Computed), true, m)) { return -5; }
    return 0;
}

fn i32 prim_null_ptr_pointee_is_void(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq((void*)types::prim_null_ptr().data.pointee, (void*)types::prim_void(), m)) { return -1; }
    return 0;
}

fn i32 prim_accessors_are_stable_across_calls(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq((void*)types::prim_i8(),       (void*)types::prim_i8(),       m)) { return -1;  }
    if(!testing::expect_eq((void*)types::prim_i32(),      (void*)types::prim_i32(),      m)) { return -2;  }
    if(!testing::expect_eq((void*)types::prim_u64(),      (void*)types::prim_u64(),      m)) { return -3;  }
    if(!testing::expect_eq((void*)types::prim_f64(),      (void*)types::prim_f64(),      m)) { return -4;  }
    if(!testing::expect_eq((void*)types::prim_bool(),     (void*)types::prim_bool(),     m)) { return -5;  }
    if(!testing::expect_eq((void*)types::prim_void(),     (void*)types::prim_void(),     m)) { return -6;  }
    if(!testing::expect_eq((void*)types::prim_type(),     (void*)types::prim_type(),     m)) { return -7;  }
    if(!testing::expect_eq((void*)types::prim_null_ptr(), (void*)types::prim_null_ptr(), m)) { return -8;  }
    return 0;
}

fn i32 prim_accessors_are_distinct(arena::Arena* a, u8[] m) {
    if(!testing::expect_ne((void*)types::prim_i32(),  (void*)types::prim_i64(), m)) { return -1; }
    if(!testing::expect_ne((void*)types::prim_i32(),  (void*)types::prim_u32(), m)) { return -2; }
    if(!testing::expect_ne((void*)types::prim_i8(),   (void*)types::prim_u8(),  m)) { return -3; }
    if(!testing::expect_ne((void*)types::prim_f32(),  (void*)types::prim_f64(), m)) { return -4; }
    if(!testing::expect_ne((void*)types::prim_bool(), (void*)types::prim_u8(),  m)) { return -5; }
    if(!testing::expect_ne((void*)types::prim_void(), (void*)types::prim_bool(),m)) { return -6; }
    if(!testing::expect_ne((void*)types::prim_type(), (void*)types::prim_void(),m)) { return -7; }
    if(!testing::expect_ne((void*)types::prim_null_ptr(), (void*)types::prim_void(), m)) { return -8; }
    return 0;
}

fn i32 primitive_dispatch_matches_accessors(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq((void*)types::primitive(types::PrimitiveKind::I8),   (void*)types::prim_i8(),   m)) { return -1;  }
    if(!testing::expect_eq((void*)types::primitive(types::PrimitiveKind::I16),  (void*)types::prim_i16(),  m)) { return -2;  }
    if(!testing::expect_eq((void*)types::primitive(types::PrimitiveKind::I32),  (void*)types::prim_i32(),  m)) { return -3;  }
    if(!testing::expect_eq((void*)types::primitive(types::PrimitiveKind::I64),  (void*)types::prim_i64(),  m)) { return -4;  }
    if(!testing::expect_eq((void*)types::primitive(types::PrimitiveKind::U8),   (void*)types::prim_u8(),   m)) { return -5;  }
    if(!testing::expect_eq((void*)types::primitive(types::PrimitiveKind::U16),  (void*)types::prim_u16(),  m)) { return -6;  }
    if(!testing::expect_eq((void*)types::primitive(types::PrimitiveKind::U32),  (void*)types::prim_u32(),  m)) { return -7;  }
    if(!testing::expect_eq((void*)types::primitive(types::PrimitiveKind::U64),  (void*)types::prim_u64(),  m)) { return -8;  }
    if(!testing::expect_eq((void*)types::primitive(types::PrimitiveKind::F32),  (void*)types::prim_f32(),  m)) { return -9;  }
    if(!testing::expect_eq((void*)types::primitive(types::PrimitiveKind::F64),  (void*)types::prim_f64(),  m)) { return -10; }
    if(!testing::expect_eq((void*)types::primitive(types::PrimitiveKind::BOOL), (void*)types::prim_bool(), m)) { return -11; }
    if(!testing::expect_eq((void*)types::primitive(types::PrimitiveKind::VOID), (void*)types::prim_void(), m)) { return -12; }
    return 0;
}

fn i32 primitive_none_returns_null(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq((void*)types::primitive(types::PrimitiveKind::NONE), null, m)) { return -1; }
    return 0;
}

fn i32 get_primitive_kind_from_token_maps_all(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq((u64)types::get_primitive_kind_from_token(token::TokenKind::I8),   (u64)types::PrimitiveKind::I8,   m)) { return -1;  }
    if(!testing::expect_eq((u64)types::get_primitive_kind_from_token(token::TokenKind::I16),  (u64)types::PrimitiveKind::I16,  m)) { return -2;  }
    if(!testing::expect_eq((u64)types::get_primitive_kind_from_token(token::TokenKind::I32),  (u64)types::PrimitiveKind::I32,  m)) { return -3;  }
    if(!testing::expect_eq((u64)types::get_primitive_kind_from_token(token::TokenKind::I64),  (u64)types::PrimitiveKind::I64,  m)) { return -4;  }
    if(!testing::expect_eq((u64)types::get_primitive_kind_from_token(token::TokenKind::U8),   (u64)types::PrimitiveKind::U8,   m)) { return -5;  }
    if(!testing::expect_eq((u64)types::get_primitive_kind_from_token(token::TokenKind::U16),  (u64)types::PrimitiveKind::U16,  m)) { return -6;  }
    if(!testing::expect_eq((u64)types::get_primitive_kind_from_token(token::TokenKind::U32),  (u64)types::PrimitiveKind::U32,  m)) { return -7;  }
    if(!testing::expect_eq((u64)types::get_primitive_kind_from_token(token::TokenKind::U64),  (u64)types::PrimitiveKind::U64,  m)) { return -8;  }
    if(!testing::expect_eq((u64)types::get_primitive_kind_from_token(token::TokenKind::F32),  (u64)types::PrimitiveKind::F32,  m)) { return -9;  }
    if(!testing::expect_eq((u64)types::get_primitive_kind_from_token(token::TokenKind::F64),  (u64)types::PrimitiveKind::F64,  m)) { return -10; }
    if(!testing::expect_eq((u64)types::get_primitive_kind_from_token(token::TokenKind::BOOL), (u64)types::PrimitiveKind::BOOL, m)) { return -11; }
    if(!testing::expect_eq((u64)types::get_primitive_kind_from_token(token::TokenKind::VOID), (u64)types::PrimitiveKind::VOID, m)) { return -12; }
    return 0;
}

fn i32 get_primitive_kind_from_token_type_is_none(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq((u64)types::get_primitive_kind_from_token(token::TokenKind::TYPE), (u64)types::PrimitiveKind::NONE, m)) { return -1; }
    return 0;
}

fn i32 get_primitive_kind_from_token_non_primitive_is_none(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq((u64)types::get_primitive_kind_from_token(token::TokenKind::Ident),  (u64)types::PrimitiveKind::NONE, m)) { return -1; }
    if(!testing::expect_eq((u64)types::get_primitive_kind_from_token(token::TokenKind::Plus),   (u64)types::PrimitiveKind::NONE, m)) { return -2; }
    if(!testing::expect_eq((u64)types::get_primitive_kind_from_token(token::TokenKind::STRUCT), (u64)types::PrimitiveKind::NONE, m)) { return -3; }
    if(!testing::expect_eq((u64)types::get_primitive_kind_from_token(token::TokenKind::EOF),    (u64)types::PrimitiveKind::NONE, m)) { return -4; }
    return 0;
}

fn i32 castable_identity_primitive(arena::Arena* a, u8[] m) {
    types::Ty* t = fake_i32(a);
    if(!testing::expect_eq(types::is_castable(t, t), true, m)) { return -1; }
    types::Ty* b = fake_bool(a);
    if(!testing::expect_eq(types::is_castable(b, b), true, m)) { return -2; }
    types::Ty* v = fake_void(a);
    if(!testing::expect_eq(types::is_castable(v, v), true, m)) { return -3; }
    return 0;
}

fn i32 castable_int_to_int_all_combos(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_castable(fake_i8(a),  fake_i64(a)), true, m)) { return -1;  }
    if(!testing::expect_eq(types::is_castable(fake_i64(a), fake_i8(a)),  true, m)) { return -2;  }
    if(!testing::expect_eq(types::is_castable(fake_i32(a), fake_u32(a)), true, m)) { return -3;  }
    if(!testing::expect_eq(types::is_castable(fake_u32(a), fake_i32(a)), true, m)) { return -4;  }
    if(!testing::expect_eq(types::is_castable(fake_u8(a),  fake_i64(a)), true, m)) { return -5;  }
    if(!testing::expect_eq(types::is_castable(fake_i32(a), fake_u64(a)), true, m)) { return -6;  }
    if(!testing::expect_eq(types::is_castable(fake_u64(a), fake_i8(a)),  true, m)) { return -7;  }
    if(!testing::expect_eq(types::is_castable(fake_u16(a), fake_u16(a)), true, m)) { return -8;  }
    if(!testing::expect_eq(types::is_castable(fake_i16(a), fake_u32(a)), true, m)) { return -9;  }
    if(!testing::expect_eq(types::is_castable(fake_u32(a), fake_u16(a)), true, m)) { return -10; }
    return 0;
}

fn i32 castable_int_to_float(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_castable(fake_i8(a),  fake_f32(a)), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(fake_i32(a), fake_f64(a)), true, m)) { return -2; }
    if(!testing::expect_eq(types::is_castable(fake_u64(a), fake_f32(a)), true, m)) { return -3; }
    if(!testing::expect_eq(types::is_castable(fake_u8(a),  fake_f64(a)), true, m)) { return -4; }
    return 0;
}

fn i32 castable_float_to_int(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_castable(fake_f32(a), fake_i8(a)),  true, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(fake_f64(a), fake_i32(a)), true, m)) { return -2; }
    if(!testing::expect_eq(types::is_castable(fake_f32(a), fake_u64(a)), true, m)) { return -3; }
    if(!testing::expect_eq(types::is_castable(fake_f64(a), fake_u16(a)), true, m)) { return -4; }
    return 0;
}

fn i32 castable_float_to_float(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_castable(fake_f32(a), fake_f64(a)), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(fake_f64(a), fake_f32(a)), true, m)) { return -2; }
    types::Ty* f = fake_f32(a);
    if(!testing::expect_eq(types::is_castable(f, f), true, m)) { return -3; }
    return 0;
}

fn i32 castable_ptr_to_ptr_various(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* p_i32  = types::intern_pointer(fake_i32(a), false);
    types::Ty* p_void = types::intern_pointer(fake_void(a), false);
    types::Ty* p_struct = types::intern_pointer(types::intern_struct(fake_decl(a)), false);
    if(!testing::expect_eq(types::is_castable(p_i32,    p_void),   true, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(p_void,   p_struct), true, m)) { return -2; }
    if(!testing::expect_eq(types::is_castable(p_struct, p_i32),    true, m)) { return -3; }
    return 0;
}

fn i32 castable_ptr_to_ptr_sized_int(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* p = types::intern_pointer(fake_i32(a), false);
    if(!testing::expect_eq(types::is_castable(p, fake_i64(a)), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(p, fake_u64(a)), true, m)) { return -2; }
    return 0;
}

fn i32 castable_ptr_sized_int_to_ptr(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* p = types::intern_pointer(fake_i32(a), false);
    if(!testing::expect_eq(types::is_castable(fake_i64(a), p), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(fake_u64(a), p), true, m)) { return -2; }
    return 0;
}

fn i32 castable_ptr_to_smaller_int_rejected(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* p = types::intern_pointer(fake_i32(a), false);
    if(!testing::expect_eq(types::is_castable(p, fake_i32(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(p, fake_i16(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_castable(p, fake_i8(a)),  false, m)) { return -3; }
    if(!testing::expect_eq(types::is_castable(p, fake_u32(a)), false, m)) { return -4; }
    if(!testing::expect_eq(types::is_castable(p, fake_u16(a)), false, m)) { return -5; }
    if(!testing::expect_eq(types::is_castable(p, fake_u8(a)),  false, m)) { return -6; }
    return 0;
}

fn i32 castable_smaller_int_to_ptr_rejected(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* p = types::intern_pointer(fake_i32(a), false);
    if(!testing::expect_eq(types::is_castable(fake_i32(a), p), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(fake_i16(a), p), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_castable(fake_i8(a),  p), false, m)) { return -3; }
    if(!testing::expect_eq(types::is_castable(fake_u32(a), p), false, m)) { return -4; }
    return 0;
}

fn i32 castable_inherits_is_convertible(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* elem = fake_i32(a);
    types::Ty* arr  = types::intern_array(elem, 5);
    types::Ty* ptr  = types::intern_pointer(elem, false);
    types::Ty* slc  = types::intern_slice(elem);
    if(!testing::expect_eq(types::is_castable(arr, ptr), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(arr, slc), true, m)) { return -2; }
    types::Ty* e = fake_enum_with_base(a, elem);
    if(!testing::expect_eq(types::is_castable(e, elem), true, m)) { return -3; }
    types::Ty* nullp = types::prim_null_ptr();
    if(!testing::expect_eq(types::is_castable(nullp, ptr), true, m)) { return -4; }
    if(!testing::expect_eq(types::is_castable(nullp, slc), true, m)) { return -5; }
    if(!testing::expect_eq(types::is_castable(fake_i8(a), fake_i32(a)), true, m)) { return -6; }
    if(!testing::expect_eq(types::is_castable(fake_f32(a), fake_f64(a)), true, m)) { return -7; }
    return 0;
}

fn i32 castable_opaque_src_rejected(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* op = fake_opaque_struct(a);
    if(!testing::expect_eq(types::is_castable(op, fake_i32(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(op, op),          false, m)) { return -2; }
    if(!testing::expect_eq(types::is_castable(op, types::intern_pointer(fake_i32(a), false)), false, m)) { return -3; }
    return 0;
}

fn i32 castable_opaque_dst_rejected(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* op = fake_opaque_struct(a);
    if(!testing::expect_eq(types::is_castable(fake_i32(a), op), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(types::intern_struct(fake_decl(a)), op), false, m)) { return -2; }
    return 0;
}

fn i32 castable_pointer_to_opaque_allowed(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* op   = fake_opaque_struct(a);
    types::Ty* p_op = types::intern_pointer(op, false);
    types::Ty* p_i32 = types::intern_pointer(fake_i32(a), false);
    if(!testing::expect_eq(types::is_castable(p_op,  p_i32), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(p_i32, p_op),  true, m)) { return -2; }
    return 0;
}

fn i32 castable_int_to_bool_rejected(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_castable(fake_i32(a), fake_bool(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(fake_u8(a),  fake_bool(a)), false, m)) { return -2; }
    return 0;
}

fn i32 castable_bool_to_int_rejected(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_castable(fake_bool(a), fake_i32(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(fake_bool(a), fake_u8(a)),  false, m)) { return -2; }
    return 0;
}

fn i32 castable_bool_float_rejected(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_castable(fake_bool(a), fake_f32(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(fake_f64(a),  fake_bool(a)), false, m)) { return -2; }
    return 0;
}

fn i32 castable_identity_composite(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* arr = types::intern_array(fake_i32(a), 4);
    types::Ty* slc = types::intern_slice(fake_i32(a));
    types::Ty* ptr = types::intern_pointer(fake_i32(a), false);
    types::Ty* fp  = types::intern_fn_ptr(fake_void(a), mk_params0(), false);
    types::Ty* s   = types::intern_struct(fake_decl(a));
    types::Ty* u   = types::intern_union(fake_decl(a));
    types::Ty* e   = types::intern_enum(fake_decl(a));
    if(!testing::expect_eq(types::is_castable(arr, arr), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(slc, slc), true, m)) { return -2; }
    if(!testing::expect_eq(types::is_castable(ptr, ptr), true, m)) { return -3; }
    if(!testing::expect_eq(types::is_castable(fp,  fp),  true, m)) { return -4; }
    if(!testing::expect_eq(types::is_castable(s,   s),   true, m)) { return -5; }
    if(!testing::expect_eq(types::is_castable(u,   u),   true, m)) { return -6; }
    if(!testing::expect_eq(types::is_castable(e,   e),   true, m)) { return -7; }
    return 0;
}

fn i32 castable_fnptr_to_int_rejected(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* fp = types::intern_fn_ptr(fake_void(a), mk_params0(), false);
    if(!testing::expect_eq(types::is_castable(fp, fake_i64(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(fp, fake_u64(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_castable(fp, fake_i32(a)), false, m)) { return -3; }
    if(!testing::expect_eq(types::is_castable(fake_i64(a), fp), false, m)) { return -4; }
    if(!testing::expect_eq(types::is_castable(fake_u64(a), fp), false, m)) { return -5; }
    if(!testing::expect_eq(types::is_castable(fake_i32(a), fp), false, m)) { return -6; }
    return 0;
}

fn i32 castable_enum_to_other_enum_rejected(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* base = fake_i32(a);
    types::Ty* e1 = fake_enum_with_base(a, base);
    types::Ty* e2 = fake_enum_with_base(a, base);
    if(!testing::expect_eq(types::is_castable(e1, e2), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(e2, e1), false, m)) { return -2; }
    return 0;
}

fn i32 castable_void_rejected(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_castable(fake_void(a), fake_i32(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(fake_i32(a), fake_void(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_castable(fake_void(a), fake_bool(a)), false, m)) { return -3; }
    return 0;
}

fn i32 castable_struct_rejected(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s1 = types::intern_struct(fake_decl(a));
    types::Ty* s2 = types::intern_struct(fake_decl(a));
    if(!testing::expect_eq(types::is_castable(s1, s2), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(s1, fake_i32(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_castable(fake_i32(a), s1), false, m)) { return -3; }
    return 0;
}

fn i32 castable_comptime_rejected(arena::Arena* a, u8[] m) {
    types::Ty* c = fake_comptime(a);
    if(!testing::expect_eq(types::is_castable(c, fake_i32(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(fake_i32(a), c), false, m)) { return -2; }
    return 0;
}

fn i32 castable_fnptr_ptr_rejected(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* fp = types::intern_fn_ptr(fake_void(a), mk_params0(), false);
    types::Ty* p  = types::intern_pointer(fake_i32(a), false);
    if(!testing::expect_eq(types::is_castable(fp, p), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(p, fp), false, m)) { return -2; }
    return 0;
}

fn i32 castable_slice_ptr_rejected(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* s = types::intern_slice(fake_i32(a));
    types::Ty* p = types::intern_pointer(fake_i32(a), false);
    if(!testing::expect_eq(types::is_castable(s, p), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(p, s), false, m)) { return -2; }
    return 0;
}

fn i32 castable_enum_to_non_base_rejected(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* e = fake_enum_with_base(a, fake_i32(a));
    if(!testing::expect_eq(types::is_castable(e, fake_i64(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(e, fake_u32(a)), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_castable(e, fake_f32(a)), false, m)) { return -3; }
    return 0;
}

fn i32 castable_null_args_return_false(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_castable(null, fake_i32(a)), false, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(fake_i32(a), null), false, m)) { return -2; }
    if(!testing::expect_eq(types::is_castable(null, null),        false, m)) { return -3; }
    return 0;
}

fn i32 castable_pointer_const_qualifier_irrelevant(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Ty* p     = types::intern_pointer(fake_i32(a), false);
    types::Ty* p_c   = types::intern_pointer(fake_i32(a), true);
    if(!testing::expect_eq(types::is_castable(p, p_c), true, m)) { return -1; }
    if(!testing::expect_eq(types::is_castable(p_c, p), true, m)) { return -2; }
    return 0;
}

fn i32 canonical_prims_pass_predicates(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(types::is_int(types::prim_i32()),          true,  m)) { return -1;  }
    if(!testing::expect_eq(types::is_signed_int(types::prim_i8()),    true,  m)) { return -2;  }
    if(!testing::expect_eq(types::is_unsigned_int(types::prim_u64()), true,  m)) { return -3;  }
    if(!testing::expect_eq(types::is_float(types::prim_f64()),        true,  m)) { return -4;  }
    if(!testing::expect_eq(types::is_bool(types::prim_bool()),        true,  m)) { return -5;  }
    if(!testing::expect_eq(types::is_void(types::prim_void()),        true,  m)) { return -6;  }
    if(!testing::expect_eq(types::is_comptime_type(types::prim_type()), true, m)) { return -7;  }
    if(!testing::expect_eq(types::is_ptr(types::prim_null_ptr()),     true,  m)) { return -8;  }
    if(!testing::expect_eq(types::is_int(types::prim_f32()),          false, m)) { return -9;  }
    if(!testing::expect_eq(types::is_signed_int(types::prim_u8()),    false, m)) { return -10; }
    return 0;
}

// ===== entry point =====

fn i32 main() {
    testing::init();
    u8[] suite = "TypeInterner Tests";

    testing::add(suite, "typer_init_zeroes_count",  &typer_init_zeroes_count);
    testing::add(suite, "typer_init_cap_matches",   &typer_init_cap_matches);
    testing::add(suite, "typer_init_arena_bound",   &typer_init_arena_bound);
    testing::add(suite, "typer_init_buckets_empty", &typer_init_buckets_empty);

    testing::add(suite, "pointer_identity",            &pointer_identity);
    testing::add(suite, "pointer_distinct_pointees",   &pointer_distinct_pointees);
    testing::add(suite, "pointer_const_distinguishes", &pointer_const_distinguishes);
    testing::add(suite, "pointer_eager_layout",        &pointer_eager_layout);
    testing::add(suite, "pointer_kind_and_data",       &pointer_kind_and_data);
    testing::add(suite, "pointer_count_increments",    &pointer_count_increments);
    testing::add(suite, "pointer_to_pointer",          &pointer_to_pointer);

    testing::add(suite, "array_identity",         &array_identity);
    testing::add(suite, "array_distinct_counts",  &array_distinct_counts);
    testing::add(suite, "array_distinct_elems",   &array_distinct_elems);
    testing::add(suite, "array_zero_count_ok",    &array_zero_count_ok);
    testing::add(suite, "array_lazy_layout",      &array_lazy_layout);
    testing::add(suite, "array_kind_and_data",    &array_kind_and_data);
    testing::add(suite, "array_of_pointer_combo", &array_of_pointer_combo);

    testing::add(suite, "slice_identity",             &slice_identity);
    testing::add(suite, "slice_distinct_elems",       &slice_distinct_elems);
    testing::add(suite, "slice_eager_layout",         &slice_eager_layout);
    testing::add(suite, "slice_kind_and_data",        &slice_kind_and_data);
    testing::add(suite, "slice_of_composite_combo",   &slice_of_composite_combo);

    testing::add(suite, "fnptr_identity",                &fnptr_identity);
    testing::add(suite, "fnptr_distinct_return",         &fnptr_distinct_return);
    testing::add(suite, "fnptr_distinct_variadic",       &fnptr_distinct_variadic);
    testing::add(suite, "fnptr_distinct_param_types",    &fnptr_distinct_param_types);
    testing::add(suite, "fnptr_distinct_param_order",    &fnptr_distinct_param_order);
    testing::add(suite, "fnptr_distinct_arity",          &fnptr_distinct_arity);
    testing::add(suite, "fnptr_empty_params",            &fnptr_empty_params);
    testing::add(suite, "fnptr_many_params",             &fnptr_many_params);
    testing::add(suite, "fnptr_eager_layout",            &fnptr_eager_layout);
    testing::add(suite, "fnptr_composite_params_combo",  &fnptr_composite_params_combo);

    testing::add(suite, "struct_identity_by_decl",  &struct_identity_by_decl);
    testing::add(suite, "struct_distinct_decls",    &struct_distinct_decls);
    testing::add(suite, "struct_lazy_layout",       &struct_lazy_layout);
    testing::add(suite, "union_identity_and_kind",  &union_identity_and_kind);
    testing::add(suite, "enum_identity_and_kind",   &enum_identity_and_kind);

    testing::add(suite, "pointer_vs_slice_same_elem",  &pointer_vs_slice_same_elem);
    testing::add(suite, "array_vs_slice_same_elem",    &array_vs_slice_same_elem);
    testing::add(suite, "struct_union_enum_same_decl", &struct_union_enum_same_decl);

    testing::add(suite, "small_cap_forces_probing",     &small_cap_forces_probing);
    testing::add(suite, "growth_preserves_identity",    &growth_preserves_identity);
    testing::add(suite, "growth_doubles_cap",           &growth_doubles_cap);
    testing::add(suite, "count_tracks_distinct_inserts",  &count_tracks_distinct_inserts);
    testing::add(suite, "growth_preserves_all_kinds",     &growth_preserves_all_kinds);
    testing::add(suite, "growth_multiple_doublings",      &growth_multiple_doublings);
    testing::add(suite, "fnptr_params_owned_after_intern", &fnptr_params_owned_after_intern);
    testing::add(suite, "count_survives_grow",             &count_survives_grow);

    u8[] helpers = "Type Helpers Tests";

    testing::add(helpers, "is_int_exhaustive",          &is_int_exhaustive);
    testing::add(helpers, "is_signed_int_exhaustive",   &is_signed_int_exhaustive);
    testing::add(helpers, "is_unsigned_int_exhaustive", &is_unsigned_int_exhaustive);
    testing::add(helpers, "is_float_exhaustive",        &is_float_exhaustive);
    testing::add(helpers, "is_bool_exhaustive",         &is_bool_exhaustive);
    testing::add(helpers, "is_void_exhaustive",         &is_void_exhaustive);
    testing::add(helpers, "is_slice_exhaustive",        &is_slice_exhaustive);
    testing::add(helpers, "is_array_exhaustive",        &is_array_exhaustive);
    testing::add(helpers, "is_ptr_exhaustive",          &is_ptr_exhaustive);
    testing::add(helpers, "is_named_exhaustive",        &is_named_exhaustive);
    testing::add(helpers, "is_comptime_type_exhaustive", &is_comptime_type_exhaustive);
    testing::add(helpers, "predicates_NONE_primitive_falses", &predicates_NONE_primitive_falses);

    testing::add(helpers, "enum_base_type_non_enum_returns_null",     &enum_base_type_non_enum_returns_null);
    testing::add(helpers, "enum_base_type_returns_set_base_i32",      &enum_base_type_returns_set_base_i32);
    testing::add(helpers, "enum_base_type_returns_set_base_u8",       &enum_base_type_returns_set_base_u8);
    testing::add(helpers, "enum_base_type_stable_across_calls",       &enum_base_type_stable_across_calls);
    testing::add(helpers, "enum_base_type_distinct_decls_distinct_bases", &enum_base_type_distinct_decls_distinct_bases);
    testing::add(helpers, "enum_base_type_null_base_defaults_i32",    &enum_base_type_null_base_defaults_i32);

    testing::add(helpers, "int_max_per_signed_primitive",     &int_max_per_signed_primitive);
    testing::add(helpers, "int_max_per_unsigned_primitive",   &int_max_per_unsigned_primitive);
    testing::add(helpers, "int_max_non_int_returns_zero",     &int_max_non_int_returns_zero);

    testing::add(helpers, "int_min_abs_per_signed_primitive", &int_min_abs_per_signed_primitive);
    testing::add(helpers, "int_min_abs_unsigned_returns_zero", &int_min_abs_unsigned_returns_zero);
    testing::add(helpers, "int_min_abs_non_int_returns_zero", &int_min_abs_non_int_returns_zero);

    testing::add(helpers, "int_lit_fits_non_int_dst_false",        &int_lit_fits_non_int_dst_false);
    testing::add(helpers, "int_lit_fits_negative_to_unsigned_false", &int_lit_fits_negative_to_unsigned_false);
    testing::add(helpers, "int_lit_fits_zero_to_each_int",         &int_lit_fits_zero_to_each_int);
    testing::add(helpers, "int_lit_fits_i8_boundaries",            &int_lit_fits_i8_boundaries);
    testing::add(helpers, "int_lit_fits_u8_boundaries",            &int_lit_fits_u8_boundaries);
    testing::add(helpers, "int_lit_fits_i16_boundaries",           &int_lit_fits_i16_boundaries);
    testing::add(helpers, "int_lit_fits_u16_boundaries",           &int_lit_fits_u16_boundaries);
    testing::add(helpers, "int_lit_fits_i32_boundaries",           &int_lit_fits_i32_boundaries);
    testing::add(helpers, "int_lit_fits_u32_boundaries",           &int_lit_fits_u32_boundaries);
    testing::add(helpers, "int_lit_fits_i64_boundaries",           &int_lit_fits_i64_boundaries);
    testing::add(helpers, "int_lit_fits_u64_max",                  &int_lit_fits_u64_max);
    testing::add(helpers, "int_lit_fits_cross_size_u8_vs_i8",      &int_lit_fits_cross_size_u8_vs_i8);
    testing::add(helpers, "int_lit_fits_value_fits_wider",         &int_lit_fits_value_fits_wider);

    u8[] cond_s = "is_convertible_in_cond Tests";

    testing::add(cond_s, "cond_bool_true",              &cond_bool_true);
    testing::add(cond_s, "cond_all_ints_true",          &cond_all_ints_true);
    testing::add(cond_s, "cond_floats_false",           &cond_floats_false);
    testing::add(cond_s, "cond_pointer_true",           &cond_pointer_true);
    testing::add(cond_s, "cond_slice_true",             &cond_slice_true);
    testing::add(cond_s, "cond_array_false",            &cond_array_false);
    testing::add(cond_s, "cond_fnptr_false",            &cond_fnptr_false);
    testing::add(cond_s, "cond_struct_union_enum_false", &cond_struct_union_enum_false);
    testing::add(cond_s, "cond_void_false",             &cond_void_false);
    testing::add(cond_s, "cond_comptime_false",         &cond_comptime_false);
    testing::add(cond_s, "cond_none_primitive_false",   &cond_none_primitive_false);

    u8[] conv = "is_convertible Tests";

    testing::add(conv, "convert_identity_primitive",          &convert_identity_primitive);
    testing::add(conv, "convert_identity_pointer",            &convert_identity_pointer);
    testing::add(conv, "convert_identity_slice",              &convert_identity_slice);
    testing::add(conv, "convert_identity_array",              &convert_identity_array);
    testing::add(conv, "convert_identity_fnptr",              &convert_identity_fnptr);
    testing::add(conv, "convert_identity_struct_union_enum",  &convert_identity_struct_union_enum);
    testing::add(conv, "convert_identity_null_ptr",           &convert_identity_null_ptr);

    testing::add(conv, "convert_array_to_pointer_matching_elem",    &convert_array_to_pointer_matching_elem);
    testing::add(conv, "convert_array_to_pointer_mismatched_elem",  &convert_array_to_pointer_mismatched_elem);
    testing::add(conv, "convert_array_to_pointer_zero_count",       &convert_array_to_pointer_zero_count);
    testing::add(conv, "convert_array_to_pointer_count_irrelevant", &convert_array_to_pointer_count_irrelevant);
    testing::add(conv, "convert_nested_array_to_pointer_inner",     &convert_nested_array_to_pointer_inner);

    testing::add(conv, "convert_array_to_slice_matching_elem",   &convert_array_to_slice_matching_elem);
    testing::add(conv, "convert_array_to_slice_mismatched_elem", &convert_array_to_slice_mismatched_elem);
    testing::add(conv, "convert_array_to_slice_struct_elem",     &convert_array_to_slice_struct_elem);
    testing::add(conv, "convert_slice_to_array_fails",           &convert_slice_to_array_fails);

    testing::add(conv, "convert_enum_to_base_matching",            &convert_enum_to_base_matching);
    testing::add(conv, "convert_enum_to_base_mismatched",          &convert_enum_to_base_mismatched);
    testing::add(conv, "convert_enum_to_base_unsigned",            &convert_enum_to_base_unsigned);
    testing::add(conv, "convert_base_to_enum_fails",               &convert_base_to_enum_fails);
    testing::add(conv, "convert_enum_to_other_enum_same_base_fails", &convert_enum_to_other_enum_same_base_fails);

    testing::add(conv, "convert_int_widen_signed",                &convert_int_widen_signed);
    testing::add(conv, "convert_int_widen_unsigned",              &convert_int_widen_unsigned);
    testing::add(conv, "convert_int_same_rank_same_sign",         &convert_int_same_rank_same_sign);
    testing::add(conv, "convert_int_narrow_signed_fails",         &convert_int_narrow_signed_fails);
    testing::add(conv, "convert_int_narrow_unsigned_fails",       &convert_int_narrow_unsigned_fails);
    testing::add(conv, "convert_int_cross_sign_same_rank_fails",  &convert_int_cross_sign_same_rank_fails);
    testing::add(conv, "convert_int_cross_sign_widen_fails",      &convert_int_cross_sign_widen_fails);

    testing::add(conv, "convert_float_f32_to_f64",          &convert_float_f32_to_f64);
    testing::add(conv, "convert_float_f64_to_f32_fails",    &convert_float_f64_to_f32_fails);
    testing::add(conv, "convert_float_identity_via_pointer", &convert_float_identity_via_pointer);

    testing::add(conv, "convert_ptr_to_ptr_distinct_pointees",   &convert_ptr_to_ptr_distinct_pointees);
    testing::add(conv, "convert_void_ptr_to_typed_ptr",          &convert_void_ptr_to_typed_ptr);
    testing::add(conv, "convert_ptr_to_ptr_through_const_qual",  &convert_ptr_to_ptr_through_const_qual);
    testing::add(conv, "convert_ptr_to_slice_fails",             &convert_ptr_to_slice_fails);
    testing::add(conv, "convert_ptr_to_named_struct_ptr",        &convert_ptr_to_named_struct_ptr);
    testing::add(conv, "convert_ptr_to_non_ptr_fails",           &convert_ptr_to_non_ptr_fails);
    testing::add(conv, "convert_ptr_to_ptr_all_pointee_kinds",   &convert_ptr_to_ptr_all_pointee_kinds);

    testing::add(conv, "convert_null_to_pointer",                &convert_null_to_pointer);
    testing::add(conv, "convert_null_to_slice",                  &convert_null_to_slice);
    testing::add(conv, "convert_null_to_int_fails",              &convert_null_to_int_fails);
    testing::add(conv, "convert_null_to_array_fails",            &convert_null_to_array_fails);
    testing::add(conv, "convert_null_to_struct_union_enum_fails", &convert_null_to_struct_union_enum_fails);
    testing::add(conv, "convert_null_to_bool_or_float_fails",    &convert_null_to_bool_or_float_fails);
    testing::add(conv, "convert_null_to_fnptr_fails",            &convert_null_to_fnptr_fails);
    testing::add(conv, "prim_null_ptr_is_stable",                &prim_null_ptr_is_stable);
    testing::add(conv, "prim_null_ptr_kind_is_pointer",          &prim_null_ptr_kind_is_pointer);

    testing::add(conv, "convert_int_to_float_fails",                  &convert_int_to_float_fails);
    testing::add(conv, "convert_float_to_int_fails",                  &convert_float_to_int_fails);
    testing::add(conv, "convert_bool_to_int_or_int_to_bool_fails",    &convert_bool_to_int_or_int_to_bool_fails);
    testing::add(conv, "convert_int_to_pointer_fails",                &convert_int_to_pointer_fails);
    testing::add(conv, "convert_slice_to_pointer_fails",              &convert_slice_to_pointer_fails);
    testing::add(conv, "convert_struct_to_struct_distinct_decls_fails", &convert_struct_to_struct_distinct_decls_fails);
    testing::add(conv, "convert_void_to_anything_fails",              &convert_void_to_anything_fails);
    testing::add(conv, "convert_pointer_to_int_fails",                &convert_pointer_to_int_fails);
    testing::add(conv, "convert_struct_to_non_struct_fails",          &convert_struct_to_non_struct_fails);
    testing::add(conv, "convert_array_to_different_array_fails",      &convert_array_to_different_array_fails);
    testing::add(conv, "convert_slice_to_different_slice_fails",      &convert_slice_to_different_slice_fails);
    testing::add(conv, "convert_fnptr_to_different_fnptr_fails",      &convert_fnptr_to_different_fnptr_fails);

    testing::add(conv, "convert_array_of_pointer_to_slice_of_pointer", &convert_array_of_pointer_to_slice_of_pointer);
    testing::add(conv, "convert_array_of_struct_to_pointer_of_struct", &convert_array_of_struct_to_pointer_of_struct);
    testing::add(conv, "convert_comptime_to_comptime_identity",        &convert_comptime_to_comptime_identity);
    testing::add(conv, "convert_comptime_to_other_fails",              &convert_comptime_to_other_fails);

    testing::add(suite, "union_lazy_layout", &union_lazy_layout);
    testing::add(suite, "enum_lazy_layout",  &enum_lazy_layout);

    u8[] layout = "Layout Tests";

    testing::add(layout, "layout_primitives_exhaustive",         &layout_primitives_exhaustive);
    testing::add(layout, "layout_pointer_always_8_8",            &layout_pointer_always_8_8);
    testing::add(layout, "layout_const_pointer_is_8_8",          &layout_const_pointer_is_8_8);
    testing::add(layout, "layout_slice_always_16_8",             &layout_slice_always_16_8);
    testing::add(layout, "layout_fnptr_always_8_8",              &layout_fnptr_always_8_8);

    testing::add(layout, "layout_array_primitive_elem", &layout_array_primitive_elem);
    testing::add(layout, "layout_array_zero_count",     &layout_array_zero_count);
    testing::add(layout, "layout_array_single",         &layout_array_single);
    testing::add(layout, "layout_array_large_count",    &layout_array_large_count);
    testing::add(layout, "layout_nested_array",         &layout_nested_array);
    testing::add(layout, "layout_array_of_pointer",     &layout_array_of_pointer);
    testing::add(layout, "layout_array_of_slice",       &layout_array_of_slice);
    testing::add(layout, "layout_array_of_struct",      &layout_array_of_struct);
    testing::add(layout, "layout_array_of_fnptr",       &layout_array_of_fnptr);
    testing::add(layout, "layout_array_of_union",       &layout_array_of_union);
    testing::add(layout, "layout_array_of_enum",        &layout_array_of_enum);
    testing::add(layout, "layout_3d_array",             &layout_3d_array);

    testing::add(layout, "layout_slice_of_struct", &layout_slice_of_struct);
    testing::add(layout, "layout_slice_of_array",  &layout_slice_of_array);

    testing::add(layout, "layout_pointer_to_fnptr", &layout_pointer_to_fnptr);
    testing::add(layout, "layout_pointer_to_enum",  &layout_pointer_to_enum);

    testing::add(layout, "layout_empty_struct",         &layout_empty_struct);
    testing::add(layout, "layout_struct_one_i8",        &layout_struct_one_i8);
    testing::add(layout, "layout_struct_one_i32",       &layout_struct_one_i32);
    testing::add(layout, "layout_struct_i8_i32",        &layout_struct_i8_i32);
    testing::add(layout, "layout_struct_i32_i8",        &layout_struct_i32_i8);
    testing::add(layout, "layout_struct_i8_i8_i32",     &layout_struct_i8_i8_i32);
    testing::add(layout, "layout_struct_i8_i64",        &layout_struct_i8_i64);
    testing::add(layout, "layout_struct_ptr_i8",        &layout_struct_ptr_i8);
    testing::add(layout, "layout_struct_array_field",   &layout_struct_array_field);
    testing::add(layout, "layout_struct_slice_field",   &layout_struct_slice_field);
    testing::add(layout, "layout_struct_three_i32",     &layout_struct_three_i32);
    testing::add(layout, "layout_struct_nested",        &layout_struct_nested);
    testing::add(layout, "layout_struct_with_fnptr",    &layout_struct_with_fnptr);
    testing::add(layout, "layout_struct_with_bool",     &layout_struct_with_bool);
    testing::add(layout, "layout_struct_with_float",    &layout_struct_with_float);
    testing::add(layout, "layout_empty_struct_has_layout", &layout_empty_struct_has_layout);

    testing::add(layout, "layout_struct_offsets_dense_i32",        &layout_struct_offsets_dense_i32);
    testing::add(layout, "layout_struct_offsets_i8_i32",           &layout_struct_offsets_i8_i32);
    testing::add(layout, "layout_struct_offsets_i32_i8",           &layout_struct_offsets_i32_i8);
    testing::add(layout, "layout_struct_offsets_i8_i8_i32",        &layout_struct_offsets_i8_i8_i32);
    testing::add(layout, "layout_struct_offsets_i8_i64",           &layout_struct_offsets_i8_i64);
    testing::add(layout, "layout_struct_offsets_single_field",     &layout_struct_offsets_single_field);
    testing::add(layout, "layout_struct_offsets_with_slice",       &layout_struct_offsets_with_slice);
    testing::add(layout, "layout_struct_offsets_with_pointer",     &layout_struct_offsets_with_pointer);
    testing::add(layout, "layout_struct_offsets_with_nested_struct", &layout_struct_offsets_with_nested_struct);

    testing::add(layout, "layout_empty_union",            &layout_empty_union);
    testing::add(layout, "layout_union_one_i8",           &layout_union_one_i8);
    testing::add(layout, "layout_union_i8_i32",           &layout_union_i8_i32);
    testing::add(layout, "layout_union_i64_i8",           &layout_union_i64_i8);
    testing::add(layout, "layout_union_i8_i64",           &layout_union_i8_i64);
    testing::add(layout, "layout_union_with_slice",       &layout_union_with_slice);
    testing::add(layout, "layout_union_with_pointer",     &layout_union_with_pointer);
    testing::add(layout, "layout_union_offsets_all_zero", &layout_union_offsets_all_zero);

    testing::add(layout, "layout_enum_i32_base",         &layout_enum_i32_base);
    testing::add(layout, "layout_enum_i8_base",          &layout_enum_i8_base);
    testing::add(layout, "layout_enum_u64_base",         &layout_enum_u64_base);
    testing::add(layout, "layout_enum_null_base_defaults_i32",   &layout_enum_null_base_defaults_i32);
    testing::add(layout, "layout_enum_caches_after_first", &layout_enum_caches_after_first);

    testing::add(layout, "layout_comptime_zero", &layout_comptime_zero);

    testing::add(layout, "layout_struct_sets_computed_flag", &layout_struct_sets_computed_flag);
    testing::add(layout, "layout_caching_returns_same",      &layout_caching_returns_same);
    testing::add(layout, "layout_array_sets_computed_flag",  &layout_array_sets_computed_flag);
    testing::add(layout, "layout_struct_sets_layout_pointer", &layout_struct_sets_layout_pointer);
    testing::add(layout, "layout_union_sets_layout_pointer",  &layout_union_sets_layout_pointer);
    testing::add(layout, "layout_array_layout_stays_null",   &layout_array_layout_stays_null);
    testing::add(layout, "layout_pointer_layout_stays_null", &layout_pointer_layout_stays_null);
    testing::add(layout, "layout_slice_layout_stays_null",   &layout_slice_layout_stays_null);
    testing::add(layout, "layout_fnptr_layout_stays_null",   &layout_fnptr_layout_stays_null);
    testing::add(layout, "layout_enum_layout_stays_null",    &layout_enum_layout_stays_null);

    testing::add(layout, "layout_struct_null_field_skipped", &layout_struct_null_field_skipped);
    testing::add(layout, "layout_union_null_field_skipped",  &layout_union_null_field_skipped);

    u8[] cyc = "Cycle Detection Tests";

    testing::add(cyc, "cycle_self_struct_non_pointer_returns_zero",   &cycle_self_struct_non_pointer_returns_zero);
    testing::add(cyc, "cycle_self_struct_pointer_field_returns_eight", &cycle_self_struct_pointer_field_returns_eight);
    testing::add(cyc, "cycle_mutual_struct_pointer_fields_both_eight", &cycle_mutual_struct_pointer_fields_both_eight);
    testing::add(cyc, "cycle_mutual_struct_non_pointer_both_zero",     &cycle_mutual_struct_non_pointer_both_zero);
    testing::add(cyc, "cycle_struct_through_array_field",              &cycle_struct_through_array_field);
    testing::add(cyc, "cycle_union_through_value",                     &cycle_union_through_value);








    u8[] op = "Opaque + Diag Tests";

    testing::add(op, "opaque_struct_size_of_reports_diag",   &opaque_struct_size_of_reports_diag);
    testing::add(op, "opaque_struct_align_of_reports_diag",  &opaque_struct_align_of_reports_diag);
    testing::add(op, "opaque_size_of_reports_every_call",    &opaque_size_of_reports_every_call);
    testing::add(op, "opaque_does_not_set_layout",           &opaque_does_not_set_layout);
    testing::add(op, "opaque_union_size_reports_diag",       &opaque_union_size_reports_diag);
    testing::add(op, "opaque_with_null_diag_no_crash",       &opaque_with_null_diag_no_crash);
    testing::add(op, "opaque_diag_msg_content",              &opaque_diag_msg_content);
    testing::add(op, "layout_pointer_to_opaque_no_diag",     &layout_pointer_to_opaque_no_diag);
    testing::add(op, "layout_array_of_pointer_to_opaque_no_diag", &layout_array_of_pointer_to_opaque_no_diag);

    testing::add(op, "comptime_size_of_reports_diag",        &comptime_size_of_reports_diag);
    testing::add(op, "comptime_with_null_diag_no_crash",     &comptime_with_null_diag_no_crash);
    testing::add(op, "comptime_diag_msg_content",            &comptime_diag_msg_content);
    testing::add(op, "cycle_self_struct_reports_diag",       &cycle_self_struct_reports_diag);
    testing::add(op, "cycle_union_reports_diag",             &cycle_union_reports_diag);
    testing::add(op, "cycle_diag_src_pos_matches_decl",      &cycle_diag_src_pos_matches_decl);
    testing::add(op, "cycle_diag_msg_content",               &cycle_diag_msg_content);


    testing::add(layout, "layout_struct_multiple_opaque_fields_reports_each", &layout_struct_multiple_opaque_fields_reports_each);
    testing::add(layout, "layout_union_with_opaque_field",                    &layout_union_with_opaque_field);
    testing::add(layout, "layout_struct_with_comptime_field_reports_diag",    &layout_struct_with_comptime_field_reports_diag);
    testing::add(layout, "layout_union_with_comptime_field_reports_diag",     &layout_union_with_comptime_field_reports_diag);
    testing::add(layout, "layout_array_of_comptime_reports_diag",             &layout_array_of_comptime_reports_diag);
    testing::add(layout, "layout_array_of_opaque_reports_diag",               &layout_array_of_opaque_reports_diag);


    testing::add(cyc, "cycle_struct_with_valid_field",                   &cycle_struct_with_valid_field);
    testing::add(cyc, "cycle_self_struct_align_of_reports_and_returns_one", &cycle_self_struct_align_of_reports_and_returns_one);

    u8[] pr = "PrimitiveTable Tests";

    testing::add(pr, "prim_signed_ints_have_correct_fields",   &prim_signed_ints_have_correct_fields);
    testing::add(pr, "prim_unsigned_ints_have_correct_fields", &prim_unsigned_ints_have_correct_fields);
    testing::add(pr, "prim_floats_have_correct_fields",        &prim_floats_have_correct_fields);
    testing::add(pr, "prim_bool_has_correct_fields",           &prim_bool_has_correct_fields);
    testing::add(pr, "prim_void_has_correct_fields",           &prim_void_has_correct_fields);
    testing::add(pr, "prim_type_has_correct_fields",           &prim_type_has_correct_fields);
    testing::add(pr, "prim_null_ptr_has_correct_fields",       &prim_null_ptr_has_correct_fields);
    testing::add(pr, "prim_null_ptr_pointee_is_void",          &prim_null_ptr_pointee_is_void);
    testing::add(pr, "prim_accessors_are_stable_across_calls", &prim_accessors_are_stable_across_calls);
    testing::add(pr, "prim_accessors_are_distinct",            &prim_accessors_are_distinct);
    testing::add(pr, "primitive_dispatch_matches_accessors",   &primitive_dispatch_matches_accessors);
    testing::add(pr, "primitive_none_returns_null",            &primitive_none_returns_null);
    testing::add(pr, "get_primitive_kind_from_token_maps_all", &get_primitive_kind_from_token_maps_all);
    testing::add(pr, "get_primitive_kind_from_token_type_is_none", &get_primitive_kind_from_token_type_is_none);
    testing::add(pr, "get_primitive_kind_from_token_non_primitive_is_none", &get_primitive_kind_from_token_non_primitive_is_none);
    testing::add(pr, "canonical_prims_pass_predicates",        &canonical_prims_pass_predicates);

    u8[] cast = "is_castable Tests";

    testing::add(cast, "castable_identity_primitive",            &castable_identity_primitive);
    testing::add(cast, "castable_int_to_int_all_combos",         &castable_int_to_int_all_combos);
    testing::add(cast, "castable_int_to_float",                  &castable_int_to_float);
    testing::add(cast, "castable_float_to_int",                  &castable_float_to_int);
    testing::add(cast, "castable_float_to_float",                &castable_float_to_float);
    testing::add(cast, "castable_ptr_to_ptr_various",            &castable_ptr_to_ptr_various);
    testing::add(cast, "castable_ptr_to_ptr_sized_int",          &castable_ptr_to_ptr_sized_int);
    testing::add(cast, "castable_ptr_sized_int_to_ptr",          &castable_ptr_sized_int_to_ptr);
    testing::add(cast, "castable_ptr_to_smaller_int_rejected",   &castable_ptr_to_smaller_int_rejected);
    testing::add(cast, "castable_smaller_int_to_ptr_rejected",   &castable_smaller_int_to_ptr_rejected);
    testing::add(cast, "castable_inherits_is_convertible",       &castable_inherits_is_convertible);
    testing::add(cast, "castable_opaque_src_rejected",           &castable_opaque_src_rejected);
    testing::add(cast, "castable_opaque_dst_rejected",           &castable_opaque_dst_rejected);
    testing::add(cast, "castable_pointer_to_opaque_allowed",     &castable_pointer_to_opaque_allowed);
    testing::add(cast, "castable_int_to_bool_rejected",          &castable_int_to_bool_rejected);
    testing::add(cast, "castable_bool_to_int_rejected",          &castable_bool_to_int_rejected);
    testing::add(cast, "castable_bool_float_rejected",           &castable_bool_float_rejected);
    testing::add(cast, "castable_void_rejected",                 &castable_void_rejected);
    testing::add(cast, "castable_struct_rejected",               &castable_struct_rejected);
    testing::add(cast, "castable_comptime_rejected",             &castable_comptime_rejected);
    testing::add(cast, "castable_fnptr_ptr_rejected",            &castable_fnptr_ptr_rejected);
    testing::add(cast, "castable_slice_ptr_rejected",            &castable_slice_ptr_rejected);
    testing::add(cast, "castable_enum_to_non_base_rejected",     &castable_enum_to_non_base_rejected);
    testing::add(cast, "castable_null_args_return_false",        &castable_null_args_return_false);
    testing::add(cast, "castable_pointer_const_qualifier_irrelevant", &castable_pointer_const_qualifier_irrelevant);
    testing::add(cast, "castable_identity_composite",            &castable_identity_composite);
    testing::add(cast, "castable_fnptr_to_int_rejected",         &castable_fnptr_to_int_rejected);
    testing::add(cast, "castable_enum_to_other_enum_rejected",   &castable_enum_to_other_enum_rejected);

    return testing::run();
}
