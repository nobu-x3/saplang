import testing;
import types;
import types_print;
import ast;
import arena;
import interner;
import io;
import symbol;
import sys;

fn void setup_typer(types::TypeInterner* it, arena::Arena* a, u64 cap) {
    types::typer_init(it, a, null, cap);
}

fn void setup_interner(interner::Interner* it, arena::Arena* a, u64 bucket_count) {
    u64 nbytes = bucket_count * sizeof(symbol::Symbol*);
    void* raw = arena::alloc(a, nbytes);
    sys::memset(raw, 0, nbytes);
    it.slab_arena = a;
    it.slab = {null, 0};
    it.slab_cap = 0;
    it.buckets = {(symbol::Symbol**)raw, bucket_count};
    it.entry_count = 0;
}

fn types::Type* fake_prim(arena::Arena* a, types::PrimitiveKind p) {
    types::Type* t = (types::Type*)arena::alloc(a, sizeof(types::Type));
    sys::memset(t, 0, sizeof(types::Type));
    t.kind = types::TypeKind::Primitive;
    t.prim = p;
    t.flags = types::LayoutFlags::Computed;
    return t;
}

fn types::Type* fake_i8 (arena::Arena* a) { return fake_prim(a, types::PrimitiveKind::I8);   }
fn types::Type* fake_i16(arena::Arena* a) { return fake_prim(a, types::PrimitiveKind::I16);  }
fn types::Type* fake_i32(arena::Arena* a) { return fake_prim(a, types::PrimitiveKind::I32);  }
fn types::Type* fake_i64(arena::Arena* a) { return fake_prim(a, types::PrimitiveKind::I64);  }
fn types::Type* fake_u8 (arena::Arena* a) { return fake_prim(a, types::PrimitiveKind::U8);   }
fn types::Type* fake_u16(arena::Arena* a) { return fake_prim(a, types::PrimitiveKind::U16);  }
fn types::Type* fake_u32(arena::Arena* a) { return fake_prim(a, types::PrimitiveKind::U32);  }
fn types::Type* fake_u64(arena::Arena* a) { return fake_prim(a, types::PrimitiveKind::U64);  }
fn types::Type* fake_f32(arena::Arena* a) { return fake_prim(a, types::PrimitiveKind::F32);  }
fn types::Type* fake_f64(arena::Arena* a) { return fake_prim(a, types::PrimitiveKind::F64);  }
fn types::Type* fake_bool(arena::Arena* a){ return fake_prim(a, types::PrimitiveKind::BOOL); }
fn types::Type* fake_void(arena::Arena* a){ return fake_prim(a, types::PrimitiveKind::VOID); }

fn types::Type* fake_comptime(arena::Arena* a) {
    types::Type* t = (types::Type*)arena::alloc(a, sizeof(types::Type));
    sys::memset(t, 0, sizeof(types::Type));
    t.kind = types::TypeKind::ComptimeType;
    return t;
}

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

fn ast::StructDeclNode* fake_struct_decl_named(arena::Arena* a, symbol::Symbol* name) {
    ast::StructDeclNode* d = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    sys::memset(d, 0, sizeof(ast::StructDeclNode));
    d.name = name;
    return d;
}

fn ast::UnionDeclNode* fake_union_decl_named(arena::Arena* a, symbol::Symbol* name) {
    ast::UnionDeclNode* d = (ast::UnionDeclNode*)arena::alloc(a, sizeof(ast::UnionDeclNode));
    sys::memset(d, 0, sizeof(ast::UnionDeclNode));
    d.name = name;
    return d;
}

fn ast::EnumDeclNode* fake_enum_decl_named(arena::Arena* a, symbol::Symbol* name) {
    ast::EnumDeclNode* d = (ast::EnumDeclNode*)arena::alloc(a, sizeof(ast::EnumDeclNode));
    sys::memset(d, 0, sizeof(ast::EnumDeclNode));
    d.name = name;
    return d;
}

fn u8[] do_print(arena::Arena* a, types::Type* t) {
    return types_print::print_to_arena(t, null, a);
}

fn u8[] do_print_named(arena::Arena* a, types::Type* t, interner::Interner* names) {
    return types_print::print_to_arena(t, names, a);
}

// ===== primitives =====

fn i32 print_signed_ints(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(do_print(a, fake_i8(a)),  "i8",  m)) { return -1; }
    if(!testing::expect_eq(do_print(a, fake_i16(a)), "i16", m)) { return -2; }
    if(!testing::expect_eq(do_print(a, fake_i32(a)), "i32", m)) { return -3; }
    if(!testing::expect_eq(do_print(a, fake_i64(a)), "i64", m)) { return -4; }
    return 0;
}

fn i32 print_unsigned_ints(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(do_print(a, fake_u8(a)),  "u8",  m)) { return -1; }
    if(!testing::expect_eq(do_print(a, fake_u16(a)), "u16", m)) { return -2; }
    if(!testing::expect_eq(do_print(a, fake_u32(a)), "u32", m)) { return -3; }
    if(!testing::expect_eq(do_print(a, fake_u64(a)), "u64", m)) { return -4; }
    return 0;
}

fn i32 print_floats(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(do_print(a, fake_f32(a)), "f32", m)) { return -1; }
    if(!testing::expect_eq(do_print(a, fake_f64(a)), "f64", m)) { return -2; }
    return 0;
}

fn i32 print_bool(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(do_print(a, fake_bool(a)), "bool", m)) { return -1; }
    return 0;
}

fn i32 print_void(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(do_print(a, fake_void(a)), "void", m)) { return -1; }
    return 0;
}

fn i32 print_comptime_type(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(do_print(a, fake_comptime(a)), "Type", m)) { return -1; }
    return 0;
}

fn i32 print_canonical_prims(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(do_print(a, types::prim_i32()),  "i32",  m)) { return -1; }
    if(!testing::expect_eq(do_print(a, types::prim_u8()),   "u8",   m)) { return -2; }
    if(!testing::expect_eq(do_print(a, types::prim_bool()), "bool", m)) { return -3; }
    if(!testing::expect_eq(do_print(a, types::prim_type()), "Type", m)) { return -4; }
    return 0;
}

// ===== pointer =====

fn i32 print_pointer_to_primitive(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* p = types::intern_pointer(&it, fake_i32(a), false);
    if(!testing::expect_eq(do_print(a, p), "i32*", m)) { return -1; }
    return 0;
}

fn i32 print_pointer_to_pointer(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* p1 = types::intern_pointer(&it, fake_i32(a), false);
    types::Type* p2 = types::intern_pointer(&it, p1, false);
    if(!testing::expect_eq(do_print(a, p2), "i32**", m)) { return -1; }
    return 0;
}

fn i32 print_const_pointer(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* p = types::intern_pointer(&it, fake_i32(a), true);
    if(!testing::expect_eq(do_print(a, p), "const i32*", m)) { return -1; }
    return 0;
}

fn i32 print_pointer_to_void(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* p = types::intern_pointer(&it, fake_void(a), false);
    if(!testing::expect_eq(do_print(a, p), "void*", m)) { return -1; }
    return 0;
}

fn i32 print_canonical_null_ptr(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(do_print(a, types::prim_null_ptr()), "void*", m)) { return -1; }
    return 0;
}

// ===== array =====

fn i32 print_array_various(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* a4   = types::intern_array(&it, fake_i32(a), 4);
    types::Type* u100 = types::intern_array(&it, fake_u8(a),  100);
    if(!testing::expect_eq(do_print(a, a4),   "i32[4]",  m)) { return -1; }
    if(!testing::expect_eq(do_print(a, u100), "u8[100]", m)) { return -2; }
    return 0;
}

fn i32 print_array_zero_count(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* arr = types::intern_array(&it, fake_i32(a), 0);
    if(!testing::expect_eq(do_print(a, arr), "i32[0]", m)) { return -1; }
    return 0;
}

fn i32 print_nested_array(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* inner = types::intern_array(&it, fake_i32(a), 3);
    types::Type* outer = types::intern_array(&it, inner, 2);
    if(!testing::expect_eq(do_print(a, outer), "i32[3][2]", m)) { return -1; }
    return 0;
}

fn i32 print_array_of_pointer(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* p   = types::intern_pointer(&it, fake_i32(a), false);
    types::Type* arr = types::intern_array(&it, p, 4);
    if(!testing::expect_eq(do_print(a, arr), "i32*[4]", m)) { return -1; }
    return 0;
}

// ===== slice =====

fn i32 print_slice_of_primitive(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* s = types::intern_slice(&it, fake_i32(a));
    if(!testing::expect_eq(do_print(a, s), "i32[]", m)) { return -1; }
    return 0;
}

fn i32 print_slice_of_slice(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* inner = types::intern_slice(&it, fake_u8(a));
    types::Type* outer = types::intern_slice(&it, inner);
    if(!testing::expect_eq(do_print(a, outer), "u8[][]", m)) { return -1; }
    return 0;
}

fn i32 print_pointer_to_slice(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* s = types::intern_slice(&it, fake_i32(a));
    types::Type* p = types::intern_pointer(&it, s, false);
    if(!testing::expect_eq(do_print(a, p), "i32[]*", m)) { return -1; }
    return 0;
}

// ===== fnptr =====

fn i32 print_fnptr_void_empty(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* fp = types::intern_fn_ptr(&it, fake_void(a), mk_params0(), false);
    if(!testing::expect_eq(do_print(a, fp), "fn* void()", m)) { return -1; }
    return 0;
}

fn i32 print_fnptr_with_return(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* fp = types::intern_fn_ptr(&it, fake_i32(a), mk_params0(), false);
    if(!testing::expect_eq(do_print(a, fp), "fn* i32()", m)) { return -1; }
    return 0;
}

fn i32 print_fnptr_with_one_param(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* fp = types::intern_fn_ptr(&it, fake_void(a), mk_params1(a, fake_i32(a)), false);
    if(!testing::expect_eq(do_print(a, fp), "fn* void(i32)", m)) { return -1; }
    return 0;
}

fn i32 print_fnptr_with_two_params(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* fp = types::intern_fn_ptr(&it, fake_i32(a), mk_params2(a, fake_i32(a), fake_f64(a)), false);
    if(!testing::expect_eq(do_print(a, fp), "fn* i32(i32, f64)", m)) { return -1; }
    return 0;
}

fn i32 print_fnptr_variadic_only(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* fp = types::intern_fn_ptr(&it, fake_void(a), mk_params0(), true);
    if(!testing::expect_eq(do_print(a, fp), "fn* void(...)", m)) { return -1; }
    return 0;
}

fn i32 print_fnptr_variadic_with_params(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* fp = types::intern_fn_ptr(&it, fake_void(a), mk_params1(a, fake_i32(a)), true);
    if(!testing::expect_eq(do_print(a, fp), "fn* void(i32, ...)", m)) { return -1; }
    return 0;
}

fn i32 print_fnptr_with_composite_params(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* p   = types::intern_pointer(&it, fake_i32(a), false);
    types::Type* slc = types::intern_slice(&it, fake_u8(a));
    types::Type* fp  = types::intern_fn_ptr(&it, fake_void(a), mk_params2(a, p, slc), false);
    if(!testing::expect_eq(do_print(a, fp), "fn* void(i32*, u8[])", m)) { return -1; }
    return 0;
}

fn i32 print_pointer_to_fnptr(arena::Arena* a, u8[] m) {
    types::TypeInterner it; setup_typer(&it, a, 16);
    types::Type* fp = types::intern_fn_ptr(&it, fake_void(a), mk_params0(), false);
    types::Type* p  = types::intern_pointer(&it, fp, false);
    if(!testing::expect_eq(do_print(a, p), "fn* void()*", m)) { return -1; }
    return 0;
}

// ===== struct / union / enum =====

fn i32 print_struct_with_name(arena::Arena* a, u8[] m) {
    types::TypeInterner ty; setup_typer(&ty, a, 16);
    interner::Interner names; setup_interner(&names, a, 16);
    symbol::Symbol* nm = interner::intern(&names, "Foo");
    types::Type* s = types::intern_struct(&ty, (void*)fake_struct_decl_named(a, nm));
    if(!testing::expect_eq(do_print_named(a, s, &names), "Foo", m)) { return -1; }
    return 0;
}

fn i32 print_union_with_name(arena::Arena* a, u8[] m) {
    types::TypeInterner ty; setup_typer(&ty, a, 16);
    interner::Interner names; setup_interner(&names, a, 16);
    symbol::Symbol* nm = interner::intern(&names, "Variant");
    types::Type* u = types::intern_union(&ty, (void*)fake_union_decl_named(a, nm));
    if(!testing::expect_eq(do_print_named(a, u, &names), "Variant", m)) { return -1; }
    return 0;
}

fn i32 print_enum_with_name(arena::Arena* a, u8[] m) {
    types::TypeInterner ty; setup_typer(&ty, a, 16);
    interner::Interner names; setup_interner(&names, a, 16);
    symbol::Symbol* nm = interner::intern(&names, "Color");
    types::Type* e = types::intern_enum(&ty, (void*)fake_enum_decl_named(a, nm));
    if(!testing::expect_eq(do_print_named(a, e, &names), "Color", m)) { return -1; }
    return 0;
}

fn i32 print_struct_with_null_name_says_anon(arena::Arena* a, u8[] m) {
    types::TypeInterner ty; setup_typer(&ty, a, 16);
    interner::Interner names; setup_interner(&names, a, 16);
    types::Type* s = types::intern_struct(&ty, (void*)fake_struct_decl_named(a, null));
    if(!testing::expect_eq(do_print_named(a, s, &names), "<anon>", m)) { return -1; }
    return 0;
}

fn i32 print_struct_with_null_interner_says_anon(arena::Arena* a, u8[] m) {
    types::TypeInterner ty; setup_typer(&ty, a, 16);
    interner::Interner names; setup_interner(&names, a, 16);
    symbol::Symbol* nm = interner::intern(&names, "Foo");
    types::Type* s = types::intern_struct(&ty, (void*)fake_struct_decl_named(a, nm));
    if(!testing::expect_eq(do_print(a, s), "<anon>", m)) { return -1; }
    return 0;
}

fn i32 print_pointer_to_struct(arena::Arena* a, u8[] m) {
    types::TypeInterner ty; setup_typer(&ty, a, 16);
    interner::Interner names; setup_interner(&names, a, 16);
    symbol::Symbol* nm = interner::intern(&names, "Node");
    types::Type* s = types::intern_struct(&ty, (void*)fake_struct_decl_named(a, nm));
    types::Type* p = types::intern_pointer(&ty, s, false);
    if(!testing::expect_eq(do_print_named(a, p, &names), "Node*", m)) { return -1; }
    return 0;
}

fn i32 print_array_of_struct(arena::Arena* a, u8[] m) {
    types::TypeInterner ty; setup_typer(&ty, a, 16);
    interner::Interner names; setup_interner(&names, a, 16);
    symbol::Symbol* nm = interner::intern(&names, "Item");
    types::Type* s   = types::intern_struct(&ty, (void*)fake_struct_decl_named(a, nm));
    types::Type* arr = types::intern_array(&ty, s, 4);
    if(!testing::expect_eq(do_print_named(a, arr, &names), "Item[4]", m)) { return -1; }
    return 0;
}

// ===== null type =====

fn i32 print_null_type(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq(do_print(a, null), "<null>", m)) { return -1; }
    return 0;
}

// ===== entry point =====

fn i32 main() {
    testing::init();
    u8[] suite = "types_print Tests";

    testing::add(suite, "print_signed_ints",                       &print_signed_ints);
    testing::add(suite, "print_unsigned_ints",                     &print_unsigned_ints);
    testing::add(suite, "print_floats",                            &print_floats);
    testing::add(suite, "print_bool",                              &print_bool);
    testing::add(suite, "print_void",                              &print_void);
    testing::add(suite, "print_comptime_type",                     &print_comptime_type);
    testing::add(suite, "print_canonical_prims",                   &print_canonical_prims);

    testing::add(suite, "print_pointer_to_primitive",              &print_pointer_to_primitive);
    testing::add(suite, "print_pointer_to_pointer",                &print_pointer_to_pointer);
    testing::add(suite, "print_const_pointer",                     &print_const_pointer);
    testing::add(suite, "print_pointer_to_void",                   &print_pointer_to_void);
    testing::add(suite, "print_canonical_null_ptr",                &print_canonical_null_ptr);

    testing::add(suite, "print_array_various",                     &print_array_various);
    testing::add(suite, "print_array_zero_count",                  &print_array_zero_count);
    testing::add(suite, "print_nested_array",                      &print_nested_array);
    testing::add(suite, "print_array_of_pointer",                  &print_array_of_pointer);

    testing::add(suite, "print_slice_of_primitive",                &print_slice_of_primitive);
    testing::add(suite, "print_slice_of_slice",                    &print_slice_of_slice);
    testing::add(suite, "print_pointer_to_slice",                  &print_pointer_to_slice);

    testing::add(suite, "print_fnptr_void_empty",                  &print_fnptr_void_empty);
    testing::add(suite, "print_fnptr_with_return",                 &print_fnptr_with_return);
    testing::add(suite, "print_fnptr_with_one_param",              &print_fnptr_with_one_param);
    testing::add(suite, "print_fnptr_with_two_params",             &print_fnptr_with_two_params);
    testing::add(suite, "print_fnptr_variadic_only",               &print_fnptr_variadic_only);
    testing::add(suite, "print_fnptr_variadic_with_params",        &print_fnptr_variadic_with_params);
    testing::add(suite, "print_fnptr_with_composite_params",       &print_fnptr_with_composite_params);
    testing::add(suite, "print_pointer_to_fnptr",                  &print_pointer_to_fnptr);

    testing::add(suite, "print_struct_with_name",                  &print_struct_with_name);
    testing::add(suite, "print_union_with_name",                   &print_union_with_name);
    testing::add(suite, "print_enum_with_name",                    &print_enum_with_name);
    testing::add(suite, "print_struct_with_null_name_says_anon",   &print_struct_with_null_name_says_anon);
    testing::add(suite, "print_struct_with_null_interner_says_anon", &print_struct_with_null_interner_says_anon);
    testing::add(suite, "print_pointer_to_struct",                 &print_pointer_to_struct);
    testing::add(suite, "print_array_of_struct",                   &print_array_of_struct);

    testing::add(suite, "print_null_type",                         &print_null_type);

    return testing::run();
}
