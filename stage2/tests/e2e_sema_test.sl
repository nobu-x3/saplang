import testing;
import test_util;
import module;
import arena;

fn i32 ok_arithmetic(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { i32 x = 1 + 2; return x; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_struct_field(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "struct P { i32 x; i32 y; }\nexport fn i32 f() { P p; p.x = 3; return p.x; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_fn_call(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn i32 g(i32 a) { return a; }\nexport fn i32 f() { return g(3); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_control_flow(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { i32 s = 0; for(i32 i = 0; i < 3; i = i + 1) { s = s + i; } return s; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_generic_template(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn T id(comptime Type T, T x) { return x; }\nexport fn i32 f() { return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 err_undefined_ident(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { return zzz; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "undefined identifier zzz", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)27, m)) { return -3; }
    return 0;
}

fn i32 err_unknown_type(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { Nope n; return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "unknown type Nope", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)20, m)) { return -3; }
    return 0;
}

fn i32 err_return_type_mismatch(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { return true; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "expected i32, found bool", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)27, m)) { return -3; }
    return 0;
}

fn i32 ok_enum(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "enum Color : i32 { Red, Green, Blue }\nexport fn i32 f() { return (i32)Color::Green; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_union(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "union U { i32 i; f32 fl; }\nexport fn i32 f() { U u; u.i = 3; return u.i; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_slice(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn u64 f() { i32[3] arr; i32[] s = arr[0..2]; return s.len; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_switch(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { i32 x = 1; switch(x) { case 1: { return 1; } else { return 0; } } }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_defer(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { i32 x = 0; defer { x = 1; } return x; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_overload(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn i32 g(i32 a) { return a; }\nfn i32 g(f32 a) { return 0; }\nexport fn i32 f() { return g(3); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 err_no_matching_overload(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn i32 g(i32 a) { return a; }\nfn i32 g(f32 a) { return 0; }\nstruct P { i32 x; }\nexport fn i32 f() { P p; return g(p); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "no matching overload for g", m)) { return -2; }
    return 0;
}

// Overloads resolve by parameter types, so a differing return type is rejected.
fn i32 err_overload_return_mismatch(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn i32 g(i32 a) { return a; }\nfn f32 g(f32 a) { return a; }\nexport fn i32 f() { return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "overloads of g must have the same return type", m)) { return -2; }
    return 0;
}

fn i32 ok_cast(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { f32 x = 1.5; return (i32)x; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_neg_float_lit(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn f32 f() { f32 x = -1.5; return x; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_pointer(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { i32 x = 5; i32* p = &x; return *p; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 err_lit_overflow(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { i8 x = 300; return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "literal 300 does not fit in i8", m)) { return -2; }
    return 0;
}

fn i32 err_missing_return(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    return 0;
}

fn i32 err_break_outside_loop(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { break; return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    return 0;
}

fn i32 err_unknown_field(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "struct P { i32 x; }\nexport fn i32 f() { P p; return p.zzz; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    return 0;
}

fn i32 ok_alias(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "alias I = i32;\nexport fn I f() { I x = 3; return x; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_anon_struct(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "alias Pair = struct { i32 x; i32 y; };\nexport fn i32 f() { Pair p; p.x = 1; return p.x; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

// Anonymous structs are only allowed on an alias RHS, not as a variable type.
fn i32 err_anon_struct_local(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { struct { i32 x; } s; return 0; }");
    if(!testing::expect_ge(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "anonymous struct types are only allowed on the right-hand side of an `alias` declaration; use a named struct or wrap this in `alias`", m)) { return -2; }
    return 0;
}

fn i32 ok_sizeof(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn u64 f() { return sizeof(i32); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_alignof(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn u64 f() { return alignof(i32); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_char_lit(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn u8 f() { u8 c = 'A'; return c; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_array_index(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { i32[3] arr; arr[0] = 7; return arr[0]; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_while(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { i32 i = 0; while(i < 3) { i = i + 1; } return i; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_const_global(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "const i32 X = 5;\nexport fn i32 f() { return X; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_nested_field(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "struct Inner { i32 v; }\nstruct Outer { Inner inner; }\nexport fn i32 f() { Outer o; o.inner.v = 4; return o.inner.v; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_fn_ptr(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn i32 g(i32 a) { return a; }\nexport fn i32 f() { fn* i32(i32) p = g; return p(5); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_extern_block(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "extern \"c\" { fn i32 puts(u8* s); }\nexport fn i32 f() { return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_enum_explicit(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "enum E : i32 { A = 1, B = 5 }\nexport fn i32 f() { return (i32)E::B; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_multi_case(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { i32 x = 1; switch(x) { case 1: case 2: { return 1; } else { return 0; } } }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_string_lit(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn u8* f() { u8* s = \"hi\"; return s; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_slice_ptr(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { i32[3] arr; i32[] s = arr[0..2]; i32* p = s.ptr; return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_comprun_empty(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_widen_conversion(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { i8 a = 5; i32 b = a; return b; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_if_else_return(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { i32 x = 1; if(x > 0) { return 1; } else { return 0; } }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 warn_unreachable_code(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { return 0; i32 y = 1; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    if(!testing::expect_ge(test_util::warning_count(mod), (u64)1, m)) { return -2; }
    return 0;
}

fn i32 ok_generic_call_infer(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn T id(comptime Type T, T x) { return x; }\nexport fn i32 f() { return id(5); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

// Inferring T=f64 from the arg makes the call f64-typed, so it mismatches the i32 return — proving
// the inferred return type flows through (not defaulted to the enclosing type).
fn i32 err_generic_call_return_type(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn T id(comptime Type T, T x) { return x; }\nexport fn i32 f() { return id(1.5); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "expected i32, found f64", m)) { return -2; }
    return 0;
}

fn i32 main() {
    testing::init();
    u8[] suite = "E2E Sema Tests";
    testing::add(suite, "ok_arithmetic",            &ok_arithmetic);
    testing::add(suite, "ok_struct_field",          &ok_struct_field);
    testing::add(suite, "ok_fn_call",               &ok_fn_call);
    testing::add(suite, "ok_control_flow",          &ok_control_flow);
    testing::add(suite, "ok_generic_template",      &ok_generic_template);
    testing::add(suite, "err_undefined_ident",      &err_undefined_ident);
    testing::add(suite, "err_unknown_type",         &err_unknown_type);
    testing::add(suite, "err_return_type_mismatch", &err_return_type_mismatch);
    testing::add(suite, "ok_enum",                  &ok_enum);
    testing::add(suite, "ok_union",                 &ok_union);
    testing::add(suite, "ok_slice",                 &ok_slice);
    testing::add(suite, "ok_switch",                &ok_switch);
    testing::add(suite, "ok_defer",                 &ok_defer);
    testing::add(suite, "ok_overload",              &ok_overload);
    testing::add(suite, "err_no_matching_overload", &err_no_matching_overload);
    testing::add(suite, "err_overload_return_mismatch", &err_overload_return_mismatch);
    testing::add(suite, "ok_cast",                  &ok_cast);
    testing::add(suite, "ok_neg_float_lit",         &ok_neg_float_lit);
    testing::add(suite, "ok_pointer",               &ok_pointer);
    testing::add(suite, "err_lit_overflow",         &err_lit_overflow);
    testing::add(suite, "err_missing_return",       &err_missing_return);
    testing::add(suite, "err_break_outside_loop",   &err_break_outside_loop);
    testing::add(suite, "err_unknown_field",        &err_unknown_field);
    testing::add(suite, "ok_alias",                 &ok_alias);
    testing::add(suite, "ok_anon_struct",           &ok_anon_struct);
    testing::add(suite, "err_anon_struct_local",    &err_anon_struct_local);
    testing::add(suite, "ok_sizeof",                &ok_sizeof);
    testing::add(suite, "ok_alignof",               &ok_alignof);
    testing::add(suite, "ok_char_lit",              &ok_char_lit);
    testing::add(suite, "ok_array_index",           &ok_array_index);
    testing::add(suite, "ok_while",                 &ok_while);
    testing::add(suite, "ok_const_global",          &ok_const_global);
    testing::add(suite, "ok_nested_field",          &ok_nested_field);
    testing::add(suite, "ok_fn_ptr",                &ok_fn_ptr);
    testing::add(suite, "ok_extern_block",          &ok_extern_block);
    testing::add(suite, "ok_enum_explicit",         &ok_enum_explicit);
    testing::add(suite, "ok_multi_case",            &ok_multi_case);
    testing::add(suite, "ok_string_lit",            &ok_string_lit);
    testing::add(suite, "ok_slice_ptr",             &ok_slice_ptr);
    testing::add(suite, "ok_comprun_empty",         &ok_comprun_empty);
    testing::add(suite, "ok_widen_conversion",      &ok_widen_conversion);
    testing::add(suite, "ok_if_else_return",        &ok_if_else_return);
    testing::add(suite, "warn_unreachable_code",    &warn_unreachable_code);
    testing::add(suite, "ok_generic_call_infer",    &ok_generic_call_infer);
    testing::add(suite, "err_generic_call_return_type", &err_generic_call_return_type);
    return testing::run();
}
