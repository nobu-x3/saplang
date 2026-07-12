import testing;
import test_util;
import module;
import arena;
import ast;
import interner;

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

fn i32 ok_generic_infer_pointer(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn T deref(comptime Type T, T* p) { return *p; }\nexport fn i32 f() { i32 x = 5; return deref(&x); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_generic_infer_slice(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn T first(comptime Type T, T[] s) { return s[0]; }\nexport fn i32 f() { i32[3] arr; return first(arr[0..2]); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_generic_explicit(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn T id(comptime Type T, T x) { return x; }\nexport fn i32 f() { return id(i32, 5); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

// Explicit T=i32, but the runtime arg is a float literal — mismatches the resolved param type.
fn i32 err_generic_explicit_arg_mismatch(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn T id(comptime Type T, T x) { return x; }\nexport fn i32 f() { return id(i32, 1.5); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "expected i32, found f64", m)) { return -2; }
    return 0;
}

// A type keyword at a runtime position (missing runtime arg) is diagnosed, not silently accepted.
fn i32 err_generic_type_at_runtime(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn T id(comptime Type T, T x) { return x; }\nexport fn i32 f() { return id(i32); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "type argument passed to a runtime parameter", m)) { return -2; }
    return 0;
}

// A user-defined type works as an explicit type argument (resolved as a type name).
fn i32 ok_generic_user_type_explicit(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "struct P { i32 v; }\nfn T id(comptime Type T, T x) { return x; }\nexport fn i32 f() { P p; id(P, p); return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

// A value where the comptime Type param expects a type is diagnosed.
fn i32 err_generic_value_as_type_arg(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn T id(comptime Type T, T x) { return x; }\nexport fn i32 f() { i32 y = 3; id(5, y); return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "expected a type argument for the comptime parameter", m)) { return -2; }
    return 0;
}

fn i32 ok_typeof_sizeof(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn u64 f() { i32 x = 5; return sizeof(typeof(x)); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_typeof_var_type(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { i32 x = 5; typeof(x) y = 3; return y; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

// typeof(x) resolves to x's concrete type — assigning it to a different type mismatches.
fn i32 err_typeof_resolves_operand_type(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { i32 x = 5; typeof(x) y = 3; f64 z = y; return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "expected f64, found i32", m)) { return -2; }
    return 0;
}

fn i32 ok_comprun_local(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { i32 x = 2 + 3; } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 err_comprun_comperror(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { comperror(\"boom\"); } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "boom", m)) { return -2; }
    return 0;
}

fn i32 warn_comprun_compwarning(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { compwarning(\"careful\"); } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    if(!testing::expect_eq(test_util::warning_count(mod), (u64)1, m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "careful", m)) { return -3; }
    return 0;
}

// A comptime local drives control flow inside the comprun; the taken branch fires comperror.
fn i32 err_comprun_var_driven(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { i32 x = 5; if(x > 3) { comperror(\"big\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "big", m)) { return -2; }
    return 0;
}

fn i32 ok_comprun_var_no_error(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { i32 x = 1; if(x > 3) { comperror(\"big\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

// A while loop runs to completion at comptime, then the post-condition fires comperror.
fn i32 err_comprun_while(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { i32 i = 0; while(i < 3) { i = i + 1; } if(i == 3) { comperror(\"looped\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "looped", m)) { return -2; }
    return 0;
}

fn i32 err_comprun_toplevel(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun { comperror(\"toplvl\"); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "toplvl", m)) { return -2; }
    return 0;
}

fn i32 ok_generic_negative_value(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn i32 make(comptime Type T, comptime i32 N, T x) { return 0; }\nexport fn i32 f() { return make(i32, -3, 5); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

// A generic function cannot be overloaded (with a generic or a concrete same-name function).
fn i32 err_overload_generic(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn T id(comptime Type T, T x) { return x; }\nfn i32 id(i32 a) { return a; }\nexport fn i32 f() { return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "generic functions cannot be overloaded", m)) { return -2; }
    return 0;
}

fn i32 ok_generic_infer_fnptr(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn i32 use(comptime Type T, fn* T(T) f) { return 0; }\nexport fn i32 main() { fn* i32(i32) g; return use(g); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_generic_explicit_value(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn i32 make(comptime Type T, comptime i32 N, T x) { return 0; }\nexport fn i32 f() { return make(i32, 3, 5); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

// A comptime value argument must be an integer literal (const-eval is literal-only).
fn i32 err_generic_value_arg_nonliteral(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn i32 make(comptime Type T, comptime i32 N, T x) { return 0; }\nexport fn i32 f() { i32 k = 3; return make(i32, k, 5); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "comptime value argument must be an integer literal", m)) { return -2; }
    return 0;
}

fn i32 ok_generic_two_type_params(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn i32 pair(comptime Type A, comptime Type B, A a, B b) { return 0; }\nexport fn i32 f() { return pair(1, 2.0); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

// The same var bound to two different types (i32 then f64) is a conflict, so inference fails.
fn i32 err_generic_conflicting_infer(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn i32 same(comptime Type T, T a, T b) { return 0; }\nexport fn i32 f() { return same(1, 2.0); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "cannot infer comptime arguments for same", m)) { return -2; }
    return 0;
}

// A recursive type-param generic must terminate at compile time (clone cached before re-checking).
fn i32 ok_generic_recursive(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn T rec(comptime Type T, T x) { return rec(x); }\nexport fn i32 f() { return rec(5); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

// A non-pointer arg where the pattern is T* can't unify, so inference fails.
fn i32 err_generic_infer_mismatch(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn T deref(comptime Type T, T* p) { return *p; }\nexport fn i32 f() { i32 x = 5; return deref(x); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "cannot infer comptime arguments for deref", m)) { return -2; }
    return 0;
}

// Two different type args → two distinct instances with distinct, correctly-mangled names.
fn i32 ok_generic_two_instances(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn T id(comptime Type T, T x) { return x; }\nexport fn i32 f() { i32 p = id(i32, 5); f64 q = id(f64, 1.5); return p; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    if(!testing::expect_eq(mod.instantiated_fns.len, (u64)2, m)) { return -2; }
    if(!testing::expect_ne((void*)mod.instantiated_fns[0].name, (void*)mod.instantiated_fns[1].name, m)) { return -3; }
    if(!testing::expect_substr(interner::symbol_str(mod.instantiated_fns[0].name), "i32", m)) { return -4; }
    if(!testing::expect_substr(interner::symbol_str(mod.instantiated_fns[1].name), "f64", m)) { return -5; }
    return 0;
}

// Distinct comptime value args produce distinct instances (the value is part of the key + mangled name).
fn i32 ok_generic_value_distinct_instances(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn i32 make(comptime Type T, comptime i32 N, T x) { return 0; }\nexport fn i32 f() { i32 p = make(i32, 3, 5); i32 q = make(i32, 4, 6); return p + q; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    if(!testing::expect_eq(mod.instantiated_fns.len, (u64)2, m)) { return -2; }
    if(!testing::expect_ne((void*)mod.instantiated_fns[0].name, (void*)mod.instantiated_fns[1].name, m)) { return -3; }
    return 0;
}

// The same type arg reuses one cached instance.
fn i32 ok_generic_cached_instance(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn T id(comptime Type T, T x) { return x; }\nexport fn i32 f() { i32 p = id(i32, 5); i32 q = id(i32, 6); return p + q; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    if(!testing::expect_eq(mod.instantiated_fns.len, (u64)1, m)) { return -2; }
    return 0;
}

// A call in a body links to its instance (CallNode.resolved_fn), whose name carries the type arg.
fn i32 ok_generic_call_resolves_to_instance(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn T id(comptime Type T, T x) { return x; }\nexport fn i32 f() { i32 p = id(i32, 5); return p; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    ast::BlockNode* root = (ast::BlockNode*)mod.root_node;
    ast::FnDeclNode* fdecl = (ast::FnDeclNode*)root.stmts[1];
    ast::BlockNode* body = (ast::BlockNode*)fdecl.body;
    ast::VarDeclNode* vd = (ast::VarDeclNode*)body.stmts[0];
    ast::CallNode* call = (ast::CallNode*)vd.init;
    if(!testing::expect_not_null(call.resolved_fn, m)) { return -2; }
    ast::FnDeclNode* clone = (ast::FnDeclNode*)call.resolved_fn;
    if(!testing::expect_substr(interner::symbol_str(clone.name), "i32", m)) { return -3; }
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
    testing::add(suite, "ok_generic_infer_pointer",  &ok_generic_infer_pointer);
    testing::add(suite, "ok_generic_infer_slice",    &ok_generic_infer_slice);
    testing::add(suite, "ok_generic_explicit",      &ok_generic_explicit);
    testing::add(suite, "err_generic_explicit_arg_mismatch", &err_generic_explicit_arg_mismatch);
    testing::add(suite, "ok_generic_two_instances", &ok_generic_two_instances);
    testing::add(suite, "ok_generic_value_distinct_instances", &ok_generic_value_distinct_instances);
    testing::add(suite, "ok_generic_cached_instance", &ok_generic_cached_instance);
    testing::add(suite, "ok_generic_call_resolves_to_instance", &ok_generic_call_resolves_to_instance);
    testing::add(suite, "ok_typeof_sizeof",         &ok_typeof_sizeof);
    testing::add(suite, "ok_typeof_var_type",       &ok_typeof_var_type);
    testing::add(suite, "err_typeof_resolves_operand_type", &err_typeof_resolves_operand_type);
    testing::add(suite, "ok_comprun_local",          &ok_comprun_local);
    testing::add(suite, "err_comprun_comperror",     &err_comprun_comperror);
    testing::add(suite, "warn_comprun_compwarning",  &warn_comprun_compwarning);
    testing::add(suite, "err_comprun_var_driven",    &err_comprun_var_driven);
    testing::add(suite, "ok_comprun_var_no_error",   &ok_comprun_var_no_error);
    testing::add(suite, "err_comprun_while",         &err_comprun_while);
    testing::add(suite, "err_comprun_toplevel",      &err_comprun_toplevel);
    testing::add(suite, "ok_generic_negative_value", &ok_generic_negative_value);
    testing::add(suite, "err_overload_generic",     &err_overload_generic);
    testing::add(suite, "ok_generic_infer_fnptr",   &ok_generic_infer_fnptr);
    testing::add(suite, "ok_generic_explicit_value", &ok_generic_explicit_value);
    testing::add(suite, "err_generic_value_arg_nonliteral", &err_generic_value_arg_nonliteral);
    testing::add(suite, "err_generic_type_at_runtime", &err_generic_type_at_runtime);
    testing::add(suite, "ok_generic_user_type_explicit", &ok_generic_user_type_explicit);
    testing::add(suite, "err_generic_value_as_type_arg", &err_generic_value_as_type_arg);
    testing::add(suite, "ok_generic_two_type_params", &ok_generic_two_type_params);
    testing::add(suite, "err_generic_conflicting_infer", &err_generic_conflicting_infer);
    testing::add(suite, "ok_generic_recursive",     &ok_generic_recursive);
    testing::add(suite, "err_generic_infer_mismatch", &err_generic_infer_mismatch);
    return testing::run();
}
