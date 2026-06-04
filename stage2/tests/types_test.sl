import testing;
import types;
import arena;
import sys;

fn void setup(types::TypeInterner* it, arena::Arena* a, u64 cap) {
    types::typer_init(it, a, cap);
}

fn types::Type* fake_prim(arena::Arena* a, types::PrimitiveKind p, u32 size, u32 align) {
    types::Type* t = (types::Type*)arena::alloc(a, sizeof(types::Type));
    sys::memset(t, 0, sizeof(types::Type));
    t.kind = types::TypeKind::Primitive;
    t.prim = p;
    t.size = size;
    t.align = align;
    t.flags = types::LayoutFlags::Computed;
    return t;
}

fn types::Type* fake_i32(arena::Arena* a)  { return fake_prim(a, types::PrimitiveKind::I32,  4, 4); }
fn types::Type* fake_i64(arena::Arena* a)  { return fake_prim(a, types::PrimitiveKind::I64,  8, 8); }
fn types::Type* fake_f64(arena::Arena* a)  { return fake_prim(a, types::PrimitiveKind::F64,  8, 8); }
fn types::Type* fake_bool(arena::Arena* a) { return fake_prim(a, types::PrimitiveKind::BOOL, 1, 1); }
fn types::Type* fake_u8(arena::Arena* a)   { return fake_prim(a, types::PrimitiveKind::U8,   1, 1); }
fn types::Type* fake_void(arena::Arena* a) { return fake_prim(a, types::PrimitiveKind::VOID, 0, 1); }

fn void* fake_decl(arena::Arena* a) { return arena::alloc(a, 8); }

fn types::Type*[] mk_params0() { types::Type*[] p; p.ptr = null; p.len = 0; return p; }

fn types::Type*[] mk_params1(arena::Arena* a, types::Type* p0) {
    types::Type** mem = (types::Type**)arena::alloc(a, sizeof(types::Type*));
    mem[0] = p0;
    types::Type*[] p; p.ptr = mem; p.len = 1; return p;
}

fn types::Type*[] mk_params2(arena::Arena* a, types::Type* p0, types::Type* p1) {
    types::Type** mem = (types::Type**)arena::alloc(a, sizeof(types::Type*) * 2);
    mem[0] = p0; mem[1] = p1;
    types::Type*[] p; p.ptr = mem; p.len = 2; return p;
}

fn types::Type*[] mk_params3(arena::Arena* a, types::Type* p0, types::Type* p1, types::Type* p2) {
    types::Type** mem = (types::Type**)arena::alloc(a, sizeof(types::Type*) * 3);
    mem[0] = p0; mem[1] = p1; mem[2] = p2;
    types::Type*[] p; p.ptr = mem; p.len = 3; return p;
}

fn bool has_flag(types::Type* t, types::LayoutFlags f) {
    return ((u8)(t.flags & f)) != 0;
}

// ===== typer_init =====

fn i32 typer_init_zeroes_count(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    if(!testing::expect_eq(it.count, (u64)0, m)) { return -1; }
    return 0;
}

fn i32 typer_init_cap_matches(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    if(!testing::expect_eq(it.cap, (u64)16, m)) { return -1; }
    if(!testing::expect_eq(it.buckets.len, (u64)16, m)) { return -2; }
    return 0;
}

fn i32 typer_init_arena_bound(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    if(!testing::expect_eq((void*)it.arena, (void*)a, m)) { return -1; }
    return 0;
}

fn i32 typer_init_buckets_empty(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    for(u64 i = 0; i < it.buckets.len; i += 1) {
        if(!testing::expect_eq(it.buckets[i].hash, (u32)0, m)) { return -1; }
    }
    return 0;
}

// ===== intern_pointer =====

fn i32 pointer_identity(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* pointee = fake_i32(a);
    types::Type* p1 = types::intern_pointer(&it, pointee, false);
    types::Type* p2 = types::intern_pointer(&it, pointee, false);
    if(!testing::expect_eq((void*)p1, (void*)p2, m)) { return -1; }
    return 0;
}

fn i32 pointer_distinct_pointees(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* a32 = fake_i32(a);
    types::Type* b64 = fake_i64(a);
    types::Type* p1 = types::intern_pointer(&it, a32, false);
    types::Type* p2 = types::intern_pointer(&it, b64, false);
    if(!testing::expect_ne((void*)p1, (void*)p2, m)) { return -1; }
    return 0;
}

fn i32 pointer_const_distinguishes(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* pointee = fake_i32(a);
    types::Type* p1 = types::intern_pointer(&it, pointee, false);
    types::Type* p2 = types::intern_pointer(&it, pointee, true);
    if(!testing::expect_ne((void*)p1, (void*)p2, m)) { return -1; }
    if(!testing::expect_eq(has_flag(p1, types::LayoutFlags::Const), false, m)) { return -2; }
    if(!testing::expect_eq(has_flag(p2, types::LayoutFlags::Const), true,  m)) { return -3; }
    return 0;
}

fn i32 pointer_eager_layout(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* p = types::intern_pointer(&it, fake_i32(a), false);
    if(!testing::expect_eq((u64)p.size,  (u64)8, m)) { return -1; }
    if(!testing::expect_eq((u64)p.align, (u64)8, m)) { return -2; }
    if(!testing::expect_eq(has_flag(p, types::LayoutFlags::Computed), true, m)) { return -3; }
    return 0;
}

fn i32 pointer_kind_and_data(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* pointee = fake_i32(a);
    types::Type* p = types::intern_pointer(&it, pointee, false);
    if(!testing::expect_eq((u64)p.kind, (u64)types::TypeKind::Pointer, m)) { return -1; }
    if(!testing::expect_eq((void*)p.data.pointee, (void*)pointee, m)) { return -2; }
    return 0;
}

fn i32 pointer_count_increments(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::intern_pointer(&it, fake_i32(a), false);
    if(!testing::expect_eq(it.count, (u64)1, m)) { return -1; }
    types::intern_pointer(&it, fake_i32(a), false);
    if(!testing::expect_eq(it.count, (u64)2, m)) { return -2; }
    return 0;
}

fn i32 pointer_to_pointer(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* base = fake_i32(a);
    types::Type* p1 = types::intern_pointer(&it, base, false);
    types::Type* p2 = types::intern_pointer(&it, p1,   false);
    if(!testing::expect_ne((void*)p1, (void*)p2, m)) { return -1; }
    if(!testing::expect_eq((void*)p2.data.pointee, (void*)p1, m)) { return -2; }
    types::Type* p2b = types::intern_pointer(&it, p1, false);
    if(!testing::expect_eq((void*)p2, (void*)p2b, m)) { return -3; }
    return 0;
}

// ===== intern_array =====

fn i32 array_identity(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* elem = fake_i32(a);
    types::Type* a1 = types::intern_array(&it, elem, 10);
    types::Type* a2 = types::intern_array(&it, elem, 10);
    if(!testing::expect_eq((void*)a1, (void*)a2, m)) { return -1; }
    return 0;
}

fn i32 array_distinct_counts(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* elem = fake_i32(a);
    types::Type* a1 = types::intern_array(&it, elem, 10);
    types::Type* a2 = types::intern_array(&it, elem, 11);
    if(!testing::expect_ne((void*)a1, (void*)a2, m)) { return -1; }
    return 0;
}

fn i32 array_distinct_elems(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* a1 = types::intern_array(&it, fake_i32(a), 10);
    types::Type* a2 = types::intern_array(&it, fake_i64(a), 10);
    if(!testing::expect_ne((void*)a1, (void*)a2, m)) { return -1; }
    return 0;
}

fn i32 array_zero_count_ok(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* elem = fake_i32(a);
    types::Type* a1 = types::intern_array(&it, elem, 0);
    types::Type* a2 = types::intern_array(&it, elem, 0);
    if(!testing::expect_eq((void*)a1, (void*)a2, m)) { return -1; }
    if(!testing::expect_eq(a1.data.array.count, (u64)0, m)) { return -2; }
    return 0;
}

fn i32 array_lazy_layout(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* arr = types::intern_array(&it, fake_i32(a), 5);
    if(!testing::expect_eq(has_flag(arr, types::LayoutFlags::Computed), false, m)) { return -1; }
    return 0;
}

fn i32 array_kind_and_data(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* elem = fake_i32(a);
    types::Type* arr  = types::intern_array(&it, elem, 7);
    if(!testing::expect_eq((u64)arr.kind, (u64)types::TypeKind::Array, m)) { return -1; }
    if(!testing::expect_eq((void*)arr.data.array.elem, (void*)elem, m)) { return -2; }
    if(!testing::expect_eq(arr.data.array.count, (u64)7, m)) { return -3; }
    return 0;
}

fn i32 array_of_pointer_combo(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* ptr = types::intern_pointer(&it, fake_i32(a), false);
    types::Type* arr = types::intern_array(&it, ptr, 4);
    if(!testing::expect_eq((void*)arr.data.array.elem, (void*)ptr, m)) { return -1; }
    types::Type* arr2 = types::intern_array(&it, ptr, 4);
    if(!testing::expect_eq((void*)arr, (void*)arr2, m)) { return -2; }
    return 0;
}

// ===== intern_slice =====

fn i32 slice_identity(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* elem = fake_i32(a);
    types::Type* s1 = types::intern_slice(&it, elem);
    types::Type* s2 = types::intern_slice(&it, elem);
    if(!testing::expect_eq((void*)s1, (void*)s2, m)) { return -1; }
    return 0;
}

fn i32 slice_distinct_elems(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* s1 = types::intern_slice(&it, fake_i32(a));
    types::Type* s2 = types::intern_slice(&it, fake_i64(a));
    if(!testing::expect_ne((void*)s1, (void*)s2, m)) { return -1; }
    return 0;
}

fn i32 slice_eager_layout(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* s = types::intern_slice(&it, fake_i32(a));
    if(!testing::expect_eq((u64)s.size,  (u64)16, m)) { return -1; }
    if(!testing::expect_eq((u64)s.align, (u64)8,  m)) { return -2; }
    if(!testing::expect_eq(has_flag(s, types::LayoutFlags::Computed), true, m)) { return -3; }
    return 0;
}

fn i32 slice_kind_and_data(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* elem = fake_i32(a);
    types::Type* s = types::intern_slice(&it, elem);
    if(!testing::expect_eq((u64)s.kind, (u64)types::TypeKind::Slice, m)) { return -1; }
    if(!testing::expect_eq((void*)s.data.slice_elem, (void*)elem, m)) { return -2; }
    return 0;
}

fn i32 slice_of_composite_combo(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* arr = types::intern_array(&it, fake_u8(a), 64);
    types::Type* s1 = types::intern_slice(&it, arr);
    types::Type* s2 = types::intern_slice(&it, arr);
    if(!testing::expect_eq((void*)s1, (void*)s2, m)) { return -1; }
    if(!testing::expect_eq((void*)s1.data.slice_elem, (void*)arr, m)) { return -2; }
    return 0;
}

// ===== intern_fn_ptr =====

fn i32 fnptr_identity(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* ret = fake_i32(a);
    types::Type*[] p = mk_params2(a, fake_i32(a), fake_f64(a));
    types::Type* f1 = types::intern_fn_ptr(&it, ret, p, false);
    types::Type* f2 = types::intern_fn_ptr(&it, ret, p, false);
    if(!testing::expect_eq((void*)f1, (void*)f2, m)) { return -1; }
    return 0;
}

fn i32 fnptr_distinct_return(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* p32 = fake_i32(a);
    types::Type*[] p = mk_params1(a, p32);
    types::Type* f1 = types::intern_fn_ptr(&it, fake_i32(a), p, false);
    types::Type* f2 = types::intern_fn_ptr(&it, fake_i64(a), p, false);
    if(!testing::expect_ne((void*)f1, (void*)f2, m)) { return -1; }
    return 0;
}

fn i32 fnptr_distinct_variadic(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* ret = fake_void(a);
    types::Type*[] p = mk_params1(a, fake_u8(a));
    types::Type* f1 = types::intern_fn_ptr(&it, ret, p, false);
    types::Type* f2 = types::intern_fn_ptr(&it, ret, p, true);
    if(!testing::expect_ne((void*)f1, (void*)f2, m)) { return -1; }
    return 0;
}

fn i32 fnptr_distinct_param_types(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* ret = fake_void(a);
    types::Type*[] p1 = mk_params1(a, fake_i32(a));
    types::Type*[] p2 = mk_params1(a, fake_i64(a));
    types::Type* f1 = types::intern_fn_ptr(&it, ret, p1, false);
    types::Type* f2 = types::intern_fn_ptr(&it, ret, p2, false);
    if(!testing::expect_ne((void*)f1, (void*)f2, m)) { return -1; }
    return 0;
}

fn i32 fnptr_distinct_param_order(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* ret = fake_void(a);
    types::Type* x = fake_i32(a);
    types::Type* y = fake_f64(a);
    types::Type* f1 = types::intern_fn_ptr(&it, ret, mk_params2(a, x, y), false);
    types::Type* f2 = types::intern_fn_ptr(&it, ret, mk_params2(a, y, x), false);
    if(!testing::expect_ne((void*)f1, (void*)f2, m)) { return -1; }
    return 0;
}

fn i32 fnptr_distinct_arity(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* ret = fake_void(a);
    types::Type* x = fake_i32(a);
    types::Type* f1 = types::intern_fn_ptr(&it, ret, mk_params1(a, x), false);
    types::Type* f2 = types::intern_fn_ptr(&it, ret, mk_params2(a, x, x), false);
    if(!testing::expect_ne((void*)f1, (void*)f2, m)) { return -1; }
    return 0;
}

fn i32 fnptr_empty_params(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* ret = fake_i32(a);
    types::Type* f1 = types::intern_fn_ptr(&it, ret, mk_params0(), false);
    types::Type* f2 = types::intern_fn_ptr(&it, ret, mk_params0(), false);
    if(!testing::expect_eq((void*)f1, (void*)f2, m)) { return -1; }
    if(!testing::expect_eq(f1.data.fn_ptr.params.len, (u64)0, m)) { return -2; }
    return 0;
}

fn i32 fnptr_many_params(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* ret = fake_void(a);
    types::Type* x = fake_i32(a);
    u64 n = 12;
    types::Type** mem = (types::Type**)arena::alloc(a, n * sizeof(types::Type*));
    for(u64 i = 0; i < n; i += 1) { mem[i] = x; }
    types::Type*[] params; params.ptr = mem; params.len = n;
    types::Type* f1 = types::intern_fn_ptr(&it, ret, params, false);
    types::Type* f2 = types::intern_fn_ptr(&it, ret, params, false);
    if(!testing::expect_eq((void*)f1, (void*)f2, m)) { return -1; }
    if(!testing::expect_eq(f1.data.fn_ptr.params.len, n, m)) { return -2; }
    return 0;
}

fn i32 fnptr_eager_layout(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* f = types::intern_fn_ptr(&it, fake_void(a), mk_params0(), false);
    if(!testing::expect_eq((u64)f.size,  (u64)8, m)) { return -1; }
    if(!testing::expect_eq((u64)f.align, (u64)8, m)) { return -2; }
    if(!testing::expect_eq(has_flag(f, types::LayoutFlags::Computed), true, m)) { return -3; }
    return 0;
}

fn i32 fnptr_composite_params_combo(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* arr  = types::intern_array(&it, fake_i32(a), 8);
    types::Type* ptr  = types::intern_pointer(&it, fake_bool(a), true);
    types::Type* slc  = types::intern_slice(&it, fake_u8(a));
    types::Type*[] p  = mk_params3(a, arr, ptr, slc);
    types::Type* f1 = types::intern_fn_ptr(&it, slc, p, false);
    types::Type* f2 = types::intern_fn_ptr(&it, slc, mk_params3(a, arr, ptr, slc), false);
    if(!testing::expect_eq((void*)f1, (void*)f2, m)) { return -1; }
    return 0;
}

// ===== intern_struct / intern_union / intern_enum =====

fn i32 struct_identity_by_decl(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    void* d = fake_decl(a);
    types::Type* s1 = types::intern_struct(&it, d);
    types::Type* s2 = types::intern_struct(&it, d);
    if(!testing::expect_eq((void*)s1, (void*)s2, m)) { return -1; }
    if(!testing::expect_eq((u64)s1.kind, (u64)types::TypeKind::Struct, m)) { return -2; }
    if(!testing::expect_eq((void*)s1.data.struct_decl, d, m)) { return -3; }
    return 0;
}

fn i32 struct_distinct_decls(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    void* d1 = fake_decl(a);
    void* d2 = fake_decl(a);
    types::Type* s1 = types::intern_struct(&it, d1);
    types::Type* s2 = types::intern_struct(&it, d2);
    if(!testing::expect_ne((void*)s1, (void*)s2, m)) { return -1; }
    return 0;
}

fn i32 struct_lazy_layout(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* s = types::intern_struct(&it, fake_decl(a));
    if(!testing::expect_eq(has_flag(s, types::LayoutFlags::Computed), false, m)) { return -1; }
    return 0;
}

fn i32 union_identity_and_kind(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    void* d = fake_decl(a);
    types::Type* u1 = types::intern_union(&it, d);
    types::Type* u2 = types::intern_union(&it, d);
    if(!testing::expect_eq((void*)u1, (void*)u2, m)) { return -1; }
    if(!testing::expect_eq((u64)u1.kind, (u64)types::TypeKind::Union, m)) { return -2; }
    if(!testing::expect_eq((void*)u1.data.union_decl, d, m)) { return -3; }
    return 0;
}

fn i32 enum_identity_and_kind(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    void* d = fake_decl(a);
    types::Type* e1 = types::intern_enum(&it, d);
    types::Type* e2 = types::intern_enum(&it, d);
    if(!testing::expect_eq((void*)e1, (void*)e2, m)) { return -1; }
    if(!testing::expect_eq((u64)e1.kind, (u64)types::TypeKind::Enum, m)) { return -2; }
    if(!testing::expect_eq((void*)e1.data.enum_decl, d, m)) { return -3; }
    return 0;
}

// ===== cross-kind isolation =====

fn i32 pointer_vs_slice_same_elem(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* elem = fake_i32(a);
    types::Type* p = types::intern_pointer(&it, elem, false);
    types::Type* s = types::intern_slice(&it, elem);
    if(!testing::expect_ne((void*)p, (void*)s, m)) { return -1; }
    return 0;
}

fn i32 array_vs_slice_same_elem(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* elem = fake_i32(a);
    types::Type* arr = types::intern_array(&it, elem, 8);
    types::Type* slc = types::intern_slice(&it, elem);
    if(!testing::expect_ne((void*)arr, (void*)slc, m)) { return -1; }
    return 0;
}

fn i32 struct_union_enum_same_decl(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    void* d = fake_decl(a);
    types::Type* s = types::intern_struct(&it, d);
    types::Type* u = types::intern_union(&it, d);
    types::Type* e = types::intern_enum(&it, d);
    if(!testing::expect_ne((void*)s, (void*)u, m)) { return -1; }
    if(!testing::expect_ne((void*)u, (void*)e, m)) { return -2; }
    if(!testing::expect_ne((void*)s, (void*)e, m)) { return -3; }
    return 0;
}

// ===== growth + probing =====

fn i32 small_cap_forces_probing(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 2);
    types::Type* p1 = types::intern_pointer(&it, fake_i32(a),  false);
    types::Type* p2 = types::intern_pointer(&it, fake_i64(a),  false);
    types::Type* p3 = types::intern_pointer(&it, fake_f64(a),  false);
    types::Type* p4 = types::intern_pointer(&it, fake_bool(a), false);
    if(!testing::expect_ne((void*)p1, (void*)p2, m)) { return -1; }
    if(!testing::expect_ne((void*)p2, (void*)p3, m)) { return -2; }
    if(!testing::expect_ne((void*)p3, (void*)p4, m)) { return -3; }
    if(!testing::expect_ge(it.cap, (u64)4, m)) { return -4; }
    return 0;
}

fn i32 growth_preserves_identity(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 4);
    types::Type* anchor_a = fake_i32(a);
    types::Type* anchor_b = fake_i64(a);
    types::Type* p_a_early = types::intern_pointer(&it, anchor_a, false);
    types::Type* p_b_early = types::intern_pointer(&it, anchor_b, true);
    for(u64 i = 0; i < 32; i += 1) {
        types::Type* extra = fake_prim(a, types::PrimitiveKind::I32, 4, 4);
        types::intern_pointer(&it, extra, false);
    }
    types::Type* p_a_late = types::intern_pointer(&it, anchor_a, false);
    types::Type* p_b_late = types::intern_pointer(&it, anchor_b, true);
    if(!testing::expect_eq((void*)p_a_early, (void*)p_a_late, m)) { return -1; }
    if(!testing::expect_eq((void*)p_b_early, (void*)p_b_late, m)) { return -2; }
    return 0;
}

fn i32 growth_doubles_cap(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 4);
    u64 start_cap = it.cap;
    for(u64 i = 0; i < 32; i += 1) {
        types::Type* extra = fake_prim(a, types::PrimitiveKind::I32, 4, 4);
        types::intern_pointer(&it, extra, false);
    }
    if(!testing::expect_gt(it.cap, start_cap, m)) { return -1; }
    if(!testing::expect_eq(it.cap & (it.cap - 1), (u64)0, m)) { return -2; }
    return 0;
}

fn i32 count_tracks_distinct_inserts(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* elem = fake_i32(a);
    types::intern_pointer(&it, elem, false);
    types::intern_pointer(&it, elem, false);
    types::intern_pointer(&it, elem, true);
    types::intern_array(&it, elem, 4);
    types::intern_array(&it, elem, 4);
    types::intern_slice(&it, elem);
    if(!testing::expect_eq(it.count, (u64)4, m)) { return -1; }
    return 0;
}

fn i32 growth_preserves_all_kinds(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 4);
    types::Type* elem   = fake_i32(a);
    types::Type* void_t = fake_void(a);
    void* sd = fake_decl(a);
    void* ud = fake_decl(a);
    void* ed = fake_decl(a);
    types::Type* anchor_ptr = types::intern_pointer(&it, elem, true);
    types::Type* anchor_arr = types::intern_array  (&it, elem, 5);
    types::Type* anchor_slc = types::intern_slice  (&it, elem);
    types::Type* anchor_fn  = types::intern_fn_ptr (&it, void_t, mk_params1(a, elem), false);
    types::Type* anchor_st  = types::intern_struct (&it, sd);
    types::Type* anchor_un  = types::intern_union  (&it, ud);
    types::Type* anchor_en  = types::intern_enum   (&it, ed);
    for(u64 i = 0; i < 40; i += 1) {
        types::intern_pointer(&it, fake_prim(a, types::PrimitiveKind::I32, 4, 4), false);
    }
    if(!testing::expect_eq((void*)anchor_ptr, (void*)types::intern_pointer(&it, elem, true), m)) { return -1; }
    if(!testing::expect_eq((void*)anchor_arr, (void*)types::intern_array  (&it, elem, 5),    m)) { return -2; }
    if(!testing::expect_eq((void*)anchor_slc, (void*)types::intern_slice  (&it, elem),       m)) { return -3; }
    if(!testing::expect_eq((void*)anchor_fn,  (void*)types::intern_fn_ptr (&it, void_t, mk_params1(a, elem), false), m)) { return -4; }
    if(!testing::expect_eq((void*)anchor_st,  (void*)types::intern_struct (&it, sd), m)) { return -5; }
    if(!testing::expect_eq((void*)anchor_un,  (void*)types::intern_union  (&it, ud), m)) { return -6; }
    if(!testing::expect_eq((void*)anchor_en,  (void*)types::intern_enum   (&it, ed), m)) { return -7; }
    return 0;
}

fn i32 growth_multiple_doublings(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 2);
    types::Type* anchor_elem = fake_i32(a);
    types::Type* anchor = types::intern_pointer(&it, anchor_elem, false);
    u64 start_cap = it.cap;
    for(u64 i = 0; i < 64; i += 1) {
        types::intern_pointer(&it, fake_prim(a, types::PrimitiveKind::I32, 4, 4), false);
    }
    if(!testing::expect_ge(it.cap, start_cap * (u64)8, m)) { return -1; }
    types::Type* anchor_late = types::intern_pointer(&it, anchor_elem, false);
    if(!testing::expect_eq((void*)anchor, (void*)anchor_late, m)) { return -2; }
    return 0;
}

fn i32 fnptr_params_owned_after_intern(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 16);
    types::Type* ret = fake_void(a);
    types::Type* p0  = fake_i32(a);
    types::Type* p1  = fake_f64(a);
    types::Type*[] params = mk_params2(a, p0, p1);
    types::Type* f1 = types::intern_fn_ptr(&it, ret, params, false);
    params[0] = fake_bool(a);
    params[1] = fake_u8(a);
    types::Type* f2 = types::intern_fn_ptr(&it, ret, mk_params2(a, p0, p1), false);
    if(!testing::expect_eq((void*)f1, (void*)f2, m)) { return -1; }
    return 0;
}

fn i32 count_survives_grow(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup(&it, a, 4);
    u64 n = 50;
    for(u64 i = 0; i < n; i += 1) {
        types::intern_pointer(&it, fake_prim(a, types::PrimitiveKind::I32, 4, 4), false);
    }
    if(!testing::expect_eq(it.count, n, m)) { return -1; }
    if(!testing::expect_gt(it.cap, (u64)4, m)) { return -2; }
    return 0;
}

fn i32 cross_interner_independence(arena::Arena* a, u8[] m) {
    types::TypeInterner it1; setup(&it1, a, 16);
    types::TypeInterner it2; setup(&it2, a, 16);
    types::Type* elem = fake_i32(a);
    types::Type* p1 = types::intern_pointer(&it1, elem, false);
    types::Type* p2 = types::intern_pointer(&it2, elem, false);
    if(!testing::expect_ne((void*)p1, (void*)p2, m)) { return -1; }
    if(!testing::expect_eq((void*)p1, (void*)types::intern_pointer(&it1, elem, false), m)) { return -2; }
    if(!testing::expect_eq((void*)p2, (void*)types::intern_pointer(&it2, elem, false), m)) { return -3; }
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
    testing::add(suite, "cross_interner_independence",     &cross_interner_independence);

    return testing::run();
}
