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

fn i32 ok_int_literal_adapts(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn u64 f(u8[] s) { u64 total = 0; for(u64 i = 0; i < s.len; i += 1) { if((i & 1) == 0) { total += 3; } } return total; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_small_int_literal_adapts(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i16 f(i16 a) { i16 b = a + 1; b -= 2; return b + -3; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_float_literal_adapts(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn f32 f(f32 p) { f32 q = p * 2.0; return q + -1.5; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 err_binop_mixed_sign(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f(u64 a, i32 b) { return (i32)(a + b); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "operator is not defined for u64 and i32", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)47, m)) { return -3; }
    return 0;
}

fn i32 err_compound_assign_narrows(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f(i16 x, i32 big) { x += big; return (i32)x; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "expected i16, found i32", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)39, m)) { return -3; }
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

// CFG runs over both the monomorphized clone (from instantiated_fns) and the generic template itself.
fn i32 ok_cfg_covers_generic(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn T id(comptime Type T, T x) { return x; }\nexport fn i32 f() { return id(5); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    if(!testing::expect_eq(mod.instantiated_fns.len, (u64)1, m)) { return -2; }
    if(!testing::expect_not_null(mod.instantiated_fns[0].cfg, m)) { return -3; }
    ast::BlockNode* root = (ast::BlockNode*)mod.root_node;
    if(!testing::expect_not_null(((ast::FnDeclNode*)root.stmts[0]).cfg, m)) { return -4; }
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

fn i32 err_duplicate_param(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn i32 g(i32 x, i32 x) { return x; }\nexport fn i32 f() { return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "duplicate declaration of x", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)16, m)) { return -3; }
    return 0;
}

fn i32 err_local_shadows_param(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f(i32 a) { i32 a = 2; return a; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "duplicate declaration of a", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)25, m)) { return -3; }
    return 0;
}

// A nested block still gets its own scope, so it may legally shadow a parameter.
fn i32 ok_nested_block_shadows_param(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f(i32 a) { { i32 a = 2; return a; } }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
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

fn i32 ok_enum_default_base(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "enum E { A, B }\ncomprun { if(sizeof(E) != (u64)4) { comperror(\"enum default base is not i32-sized\"); } }\nexport fn i32 f() { i32 c = E::B; return c + (i32)E::A; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_slice(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn u64 f() { i32[3] arr; i32[] s = arr[0..2]; return s.len; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_ptr_slice_bounded(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn u64 f(i32* p) { i32[] s = p[0..4]; return s.len; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 err_ptr_slice_open_hi(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn u64 f(i32* p) { i32[] s = p[0..]; return s.len; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "slicing a pointer requires an upper bound", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)37, m)) { return -3; }
    return 0;
}

fn i32 ok_switch(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { i32 x = 1; switch(x) { case 1: { return 1; } else { return 0; } } }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 err_switch_disc_not_scalar(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "struct P { i32 x; }\nexport fn i32 f(P p) { switch(p) { else { return 0; } } return 1; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "switch value must be an integer or enum, found main::P", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)50, m)) { return -3; }
    return 0;
}

fn i32 err_duplicate_case_label(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f(i32 x) { switch(x) { case 1: { return 1; } case 1: { return 2; } else { return 0; } } }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "duplicate case label", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)64, m)) { return -3; }
    return 0;
}

// Duplicate detection spans multi-label arms (`case 2:` here repeats a value from the first arm) but not distinct values.
fn i32 err_duplicate_case_across_arms(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f(i32 x) { switch(x) { case 1: case 2: { return 1; } case 2: { return 2; } else { return 0; } } }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "duplicate case label", m)) { return -2; }
    return 0;
}

fn i32 ok_switch_distinct_multilabel(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f(i32 x) { switch(x) { case 1: case 2: { return 1; } case 3: { return 3; } else { return 0; } } }");
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

fn i32 err_lit_wrong_target(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f(i32* p) { p = 5; return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "expected i32*, found i32", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)30, m)) { return -3; }
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

fn i32 ok_sizeof_value(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun { i32 x; if(sizeof(x) != (u64)4) { comperror(\"bad\"); } }\nexport fn u64 f(i64 v) { return sizeof(v); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 err_compcode_unsupported(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { i32 x = compcode { i32 y = 1; }; return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "compcode is not yet supported", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)28, m)) { return -3; }
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

fn i32 ok_index_any_int(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f(i32[8] arr, i32 lo, u8 j) { i32[] s = arr[lo..lo + 4]; return arr[j] + s[j]; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 err_index_not_int(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f(i32[4] arr, bool b) { return arr[b]; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "index must be an integer type, found bool", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)49, m)) { return -3; }
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

fn i32 ok_addr_of_fn(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn i32 g(i32 a) { return a; }\nexport fn i32 f() { fn* i32(i32) p = &g; return p(5); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_addr_of_fn_arg(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn void job() { } fn void run(fn* void() cb) { cb(); }\nexport fn i32 f() { run(&job); return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 err_addr_of_non_lvalue(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { return &5; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "cannot take the address of a non-lvalue", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)28, m)) { return -3; }
    return 0;
}

fn i32 ok_extern_block(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "extern \"c\" { fn i32 puts(u8* s); }\nexport fn i32 f() { return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_extern_fn_call(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "extern \"c\" { fn i32 puts(const i8* s); }\nexport fn i32 f() { return puts(\"hi\"); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_extern_struct_ptr(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "extern \"c\" { struct FILE { i8 _; }; fn FILE* fopen(const i8* p, const i8* mode); fn i32 fclose(FILE* s); }\nexport fn i32 f() { FILE* h = fopen(\"a\", \"r\"); return fclose(h); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_extern_union(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "extern \"c\" { union U { i32 i; f32 fl; }; }\nexport fn i32 f(U* u) { return u.i; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_extern_variadic(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "extern \"c\" { fn i32 printf(const i8* fmt, ...); }\nexport fn i32 f() { return printf(\"%d\", 42); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 err_extern_call_arity(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "extern \"c\" { fn i32 puts(const i8* s); }\nexport fn i32 f() { return puts(); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "call expects 1 arguments but got 0", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)72, m)) { return -3; }
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

fn i32 ok_comptime_and_shortcircuit(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn bool boom() { comperror(\"rhs ran\"); return true; }\ncomprun { if(false && boom()) { } }\nexport fn i32 f() { return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_comptime_or_shortcircuit(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn bool boom() { comperror(\"rhs ran\"); return true; }\ncomprun { if(true || boom()) { } }\nexport fn i32 f() { return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

// Logical operators accept truthy operands (bool/int/ptr/slice), like `if` and `!`.
fn i32 ok_logical_pointer_operands(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f(i32* p1, i32* p2) { if(p1 && p2) { return 1; } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_logical_mixed_truthy_operands(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f(i32 n, u8[] s) { if(n || s) { return 1; } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

// An enum acts as its base int in arithmetic/bitwise: enum on either side, with or without a literal.
fn i32 ok_enum_arithmetic(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "enum C : i32 { R, G, B } export fn i32 f(C c, i32 n) { return c - 1 + n * c + 2 * c; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_enum_bitwise(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "enum F : u8 { A = 1, B = 2 } export fn u8 f() { u8 x = F::A | F::B; u8 y = F::A & 3; return x + y; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

// Unary bitwise-not / negate on an enum act on its base int, like binary ops.
fn i32 ok_enum_unary(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "enum F : u8 { A = 1 } enum C : i32 { R, G, B } export fn i32 f(C c) { u8 x = ~F::A; return (i32)x + (-c); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

// Comparisons stay strict: an enum compared to a bare int still needs an explicit cast.
fn i32 err_enum_eq_int_strict(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "enum C : i32 { R, G, B } export fn bool f(C c) { return c == 1; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "operator is not defined for main::C and i32", m)) { return -2; }
    return 0;
}

// A non-truthy operand (float) in a logical op is still rejected.
fn i32 err_logical_float_operand(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f(f32 x, bool b) { if(x && b) { return 1; } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "operator is not defined for f32 and bool", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_and_evaluates_rhs(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn bool boom() { comperror(\"rhs ran\"); return true; }\ncomprun { if(true && boom()) { } }\nexport fn i32 f() { return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "rhs ran", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_div_by_zero(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun { i32 z = 0; i32 y = 1 / z; }\nexport fn i32 f() { return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "division by zero at comptime", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)31, m)) { return -3; }
    return 0;
}

fn i32 err_comptime_shift_range(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun { i32 s = 99; i32 y = 1 << s; }\nexport fn i32 f() { return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "shift amount out of range at comptime", m)) { return -2; }
    return 0;
}

// {1, .c = 3, 2}: the trailing positional fills b (the next positional slot), not c.
fn i32 ok_comptime_struct_lit_mixed(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "struct P { i32 a; i32 b; i32 c; }\ncomprun { P p = {1, .c = 3, 2}; if(p.a != 1) { comperror(\"a\"); } if(p.b != 2) { comperror(\"b\"); } if(p.c != 3) { comperror(\"c\"); } }\nexport fn i32 f() { return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_comptime_cast_wraps(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun { i32 big = 300; u8 a = (u8)big; if((i64)a != 44) { comperror(\"wrap\"); } i32 n = 0 - 1; u8 b = (u8)n; if((i64)b != 255) { comperror(\"neg\"); } }\nexport fn i32 f() { return 0; }");
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

// comprun calls a function defined later in the module; on-demand resolution + eval run it at comptime.
fn i32 err_comprun_calls_fn(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { if(dbl(5) == 10) { comperror(\"ten\"); } } return 0; } fn i32 dbl(i32 n) { return n * 2; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "ten", m)) { return -2; }
    return 0;
}

// A const global is a comptime value: usable as an array dimension.
fn i32 ok_const_global_array_dim(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "const i32 N = 4; export fn i32 f() { i32[N] arr; return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_const_array_size_folds(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "const u64 N = 3;\ncomprun { if(sizeof(u8[N * 2]) != (u64)6) { comperror(\"wrong array size\"); } }\nexport fn i32 f() { u8[N] buf; buf[0] = 1; return (i32)buf[0]; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 err_array_size_not_const(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f(i32 n) { i32[n] arr; return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "array size must be a compile-time constant", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)29, m)) { return -3; }
    return 0;
}

// A const global's initializer is folded at comptime and drives a comprun condition.
fn i32 err_const_global_in_comprun(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "const i32 G = 7; export fn i32 f() { comprun { if(G == 7) { comperror(\"seven\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "seven", m)) { return -2; }
    return 0;
}

// A const initializer that references another const folds correctly at comptime (idents in the init are resolved).
fn i32 err_const_chain_in_comprun(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "const i32 A = 5; const i32 B = A + 1; export fn i32 f() { comprun { if(B == 6) { comperror(\"six\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "six", m)) { return -2; }
    return 0;
}

// Top-level const initializers are type-checked in the body pass.
fn i32 err_bad_const_init(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "const i32 BAD = \"str\"; export fn i32 f() { return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "expected i32, found u8*", m)) { return -2; }
    return 0;
}

// A mutable global is not a comptime value — its runtime value isn't fixed.
fn i32 err_mutable_global_at_comptime(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "i32 G = 7; export fn i32 f() { comprun { if(G == 7) { comperror(\"x\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "identifier is not a comptime value", m)) { return -2; }
    return 0;
}

// compinsert's argument may be a comprun local; sema resolves it so eval_compinsert can read the bytes.
fn i32 ok_compinsert_from_local(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun { u8[] code = \"fn i32 gen() { return 7; }\"; compinsert(code); }\nexport fn i32 f() { return gen(); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

// compinsert generates a top-level fn; a later comprun resolves and calls it, proving it was registered + body-checked.
fn i32 err_compinsert_generated_fn_callable(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun { compinsert(\"fn i32 gen() { return 42; }\"); }\nexport fn i32 f() { comprun { if(gen() == 42) { comperror(\"ok42\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "ok42", m)) { return -2; }
    return 0;
}

// A const chooses which function body compinsert emits — the in-source conditional-compilation pattern.
fn i32 err_compinsert_conditional(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "const i32 P = 1; comprun { if(P == 1) { compinsert(\"fn i32 impl() { return 100; }\"); } else { compinsert(\"fn i32 impl() { return 200; }\"); } }\nexport fn i32 f() { comprun { if(impl() == 100) { comperror(\"picked\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "picked", m)) { return -2; }
    return 0;
}

// In-function compinsert splices generated statements into the body; the generated `return` satisfies return-path analysis.
fn i32 ok_compinsert_in_function(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { compinsert(\"i32 x = 40; return x + 2;\"); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

// The spliced statements are fully sema-checked in the enclosing block.
fn i32 err_compinsert_in_function_typecheck(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { compinsert(\"return nope;\"); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "undefined identifier nope", m)) { return -2; }
    return 0;
}

// Generated code with no return leaves the function without a return path — caught by CFG on the spliced body.
fn i32 err_compinsert_in_function_no_return(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { compinsert(\"i32 x = 1;\"); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "function may exit without a return statement", m)) { return -2; }
    return 0;
}

// compinsert generates a const; a later comprun reads it (registered + init-checked).
fn i32 err_compinsert_generates_const(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun { compinsert(\"const i32 GEN = 42;\"); }\nexport fn i32 f() { comprun { if(GEN == 42) { comperror(\"gen42\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "gen42", m)) { return -2; }
    return 0;
}

// compinsert generates a struct type that a runtime function then uses.
fn i32 ok_compinsert_generates_struct(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun { compinsert(\"struct Pt { i32 x; i32 y; }\"); }\nexport fn i32 f() { Pt p; p.x = 5; return p.x; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 err_compinsert_rejects_import(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun { compinsert(\"import foo;\"); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "compinsert can only generate fn / struct / union / enum / const / alias declarations", m)) { return -2; }
    return 0;
}

// A sema error in generated code gets a virtual src_pos (past real source) that maps back to the compinsert call.
fn i32 err_compinsert_position_registry(arena::Arena* a, u8[] m) {
    u8[] src = "comprun { compinsert(\"fn i32 g() { return nope; }\"); }\nexport fn i32 f() { return 0; }";
    module::Module* mod = test_util::frontend(a, src);
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    u32 pos = mod.diag.entries[0].src_pos;
    if(!testing::expect_true(pos >= (u32)src.len, m)) { return -2; }
    if(!testing::expect_true(module::find_inserted_source(mod, pos) != null, m)) { return -3; }
    return 0;
}

// A string literal inside generated code must resolve against the module pool (offsets remapped on splice).
fn i32 err_compinsert_string_literal(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun { compinsert(\"fn u8[] msg() { return \\\"hello\\\"; }\"); }\nexport fn i32 f() { comprun { comperror(msg()); } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "hello", m)) { return -2; }
    return 0;
}

fn i32 err_compinsert_rejects_export(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun { compinsert(\"export fn i32 g() { return 1; }\"); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "compinsert-generated declarations may not be `export`", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_typeinfo_size(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "struct P { i32 x; i32 y; } export fn i32 f() { comprun { if(type_info(P).size == (u64)8) { comperror(\"sz8\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "sz8", m)) { return -2; }
    return 0;
}

// type_info(T).fields is a FieldInfo[]; each carries name / ty / offset.
fn i32 err_comptime_typeinfo_fields(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "struct P { i32 a; i32 b; } export fn i32 f() { comprun { if(type_info(P).fields[1].offset == (u64)4) { comperror(\"off4\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "off4", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_typeinfo_field_name(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "struct P { i32 xx; i32 yy; } export fn i32 f() { comprun { u8[] n0 = type_info(P).fields[0].name; if(n0[0] == (u8)120) { comperror(\"nx\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "nx", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_bytes_len(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { u8[] s = \"abc\"; if(s.len == (u64)3) { comperror(\"len3\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "len3", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_bytes_index(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { u8[] s = \"abc\"; u8 c = s[0]; if(c == (u8)97) { comperror(\"s97\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "s97", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_undefined(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { i32 x = undefined; x = 5; if(x == 5) { comperror(\"undef5\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "undef5", m)) { return -2; }
    return 0;
}

// A function assigned to a fn-pointer local is a comptime value; calling through it dispatches to the function.
fn i32 err_comptime_fnptr_call(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn i32 dbl(i32 n) { return n * 2; } export fn i32 f() { comprun { fn* i32(i32) p = dbl; if(p(21) == 42) { comperror(\"fp42\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "fp42", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_array_mutate(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { i32[3] a = [1, 2, 3]; a[0] = 9; if(a[0] == 9) { comperror(\"a0is9\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "a0is9", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_struct_mutate(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "struct P { i32 x; i32 y; } export fn i32 f() { comprun { P p = { .x = 1, .y = 2 }; p.x = 7; if(p.x == 7) { comperror(\"x7\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "x7", m)) { return -2; }
    return 0;
}

// An enum value expression referencing a sibling member folds at comptime.
fn i32 err_comptime_enum_chain(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "enum E : i32 { A = 5, B = A + 1 } export fn i32 f() { comprun { if((i32)E::B == 6) { comperror(\"b6\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "b6", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_cast(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { if((i32)3.9 == 3) { comperror(\"trunc3\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "trunc3", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_enum_member(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "enum E : i32 { A, B, C } export fn i32 f() { comprun { if((i32)E::C == 2) { comperror(\"c2\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "c2", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_enum_switch(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "enum Color : i32 { Red, Green, Blue } export fn i32 f() { comprun { Color c = Color::Green; switch(c) { case Color::Green: { comperror(\"green\"); } else { comperror(\"other\"); } } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "green", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_struct_member(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "struct P { i32 x; i32 y; } export fn i32 f() { comprun { P p = { .x = 3, .y = 7 }; if(p.y == 7) { comperror(\"y7\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "y7", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_array_index(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { i32[3] a = [10, 20, 30]; u64 i = 2; if(a[i] == 30) { comperror(\"idx30\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "idx30", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_defer(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { i32 x = 0; defer { x = 9; } if(x == 0) { comperror(\"beforedefr\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "beforedefr", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_break(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { i32 i = 0; while(i < 10) { if(i == 2) { break; } i = i + 1; } if(i == 2) { comperror(\"broke2\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "broke2", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_continue(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { i32 sum = 0; for(i32 i = 0; i < 5; i = i + 1) { if(i == 2) { continue; } sum = sum + i; } if(sum == 8) { comperror(\"skip2\"); } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "skip2", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_switch_case(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { i32 x = 2; switch(x) { case 1: case 2: { comperror(\"oneortwo\"); } else { comperror(\"def\"); } } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "oneortwo", m)) { return -2; }
    return 0;
}

fn i32 err_comptime_switch_default(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { comprun { i32 x = 9; switch(x) { case 2: { comperror(\"case2\"); } else { comperror(\"def\"); } } } return 0; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "def", m)) { return -2; }
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
    testing::add(suite, "ok_cfg_covers_generic",    &ok_cfg_covers_generic);
    testing::add(suite, "err_undefined_ident",      &err_undefined_ident);
    testing::add(suite, "err_unknown_type",         &err_unknown_type);
    testing::add(suite, "err_duplicate_param",      &err_duplicate_param);
    testing::add(suite, "err_local_shadows_param",  &err_local_shadows_param);
    testing::add(suite, "ok_nested_block_shadows_param", &ok_nested_block_shadows_param);
    testing::add(suite, "err_return_type_mismatch", &err_return_type_mismatch);
    testing::add(suite, "ok_int_literal_adapts",    &ok_int_literal_adapts);
    testing::add(suite, "ok_small_int_literal_adapts", &ok_small_int_literal_adapts);
    testing::add(suite, "ok_float_literal_adapts",  &ok_float_literal_adapts);
    testing::add(suite, "err_binop_mixed_sign",     &err_binop_mixed_sign);
    testing::add(suite, "err_compound_assign_narrows", &err_compound_assign_narrows);
    testing::add(suite, "ok_enum",                  &ok_enum);
    testing::add(suite, "ok_enum_default_base",     &ok_enum_default_base);
    testing::add(suite, "ok_union",                 &ok_union);
    testing::add(suite, "ok_slice",                 &ok_slice);
    testing::add(suite, "ok_ptr_slice_bounded",     &ok_ptr_slice_bounded);
    testing::add(suite, "err_ptr_slice_open_hi",    &err_ptr_slice_open_hi);
    testing::add(suite, "ok_switch",                &ok_switch);
    testing::add(suite, "err_switch_disc_not_scalar", &err_switch_disc_not_scalar);
    testing::add(suite, "err_duplicate_case_label",  &err_duplicate_case_label);
    testing::add(suite, "err_duplicate_case_across_arms", &err_duplicate_case_across_arms);
    testing::add(suite, "ok_switch_distinct_multilabel", &ok_switch_distinct_multilabel);
    testing::add(suite, "ok_defer",                 &ok_defer);
    testing::add(suite, "ok_overload",              &ok_overload);
    testing::add(suite, "err_no_matching_overload", &err_no_matching_overload);
    testing::add(suite, "err_overload_return_mismatch", &err_overload_return_mismatch);
    testing::add(suite, "ok_cast",                  &ok_cast);
    testing::add(suite, "ok_neg_float_lit",         &ok_neg_float_lit);
    testing::add(suite, "ok_pointer",               &ok_pointer);
    testing::add(suite, "err_lit_overflow",         &err_lit_overflow);
    testing::add(suite, "err_lit_wrong_target",     &err_lit_wrong_target);
    testing::add(suite, "err_missing_return",       &err_missing_return);
    testing::add(suite, "err_break_outside_loop",   &err_break_outside_loop);
    testing::add(suite, "err_unknown_field",        &err_unknown_field);
    testing::add(suite, "ok_alias",                 &ok_alias);
    testing::add(suite, "ok_anon_struct",           &ok_anon_struct);
    testing::add(suite, "err_anon_struct_local",    &err_anon_struct_local);
    testing::add(suite, "ok_sizeof",                &ok_sizeof);
    testing::add(suite, "ok_sizeof_value",          &ok_sizeof_value);
    testing::add(suite, "err_compcode_unsupported", &err_compcode_unsupported);
    testing::add(suite, "ok_alignof",               &ok_alignof);
    testing::add(suite, "ok_char_lit",              &ok_char_lit);
    testing::add(suite, "ok_array_index",           &ok_array_index);
    testing::add(suite, "ok_index_any_int",         &ok_index_any_int);
    testing::add(suite, "err_index_not_int",        &err_index_not_int);
    testing::add(suite, "ok_while",                 &ok_while);
    testing::add(suite, "ok_const_global",          &ok_const_global);
    testing::add(suite, "ok_nested_field",          &ok_nested_field);
    testing::add(suite, "ok_fn_ptr",                &ok_fn_ptr);
    testing::add(suite, "ok_addr_of_fn",            &ok_addr_of_fn);
    testing::add(suite, "ok_addr_of_fn_arg",        &ok_addr_of_fn_arg);
    testing::add(suite, "err_addr_of_non_lvalue",   &err_addr_of_non_lvalue);
    testing::add(suite, "ok_extern_block",          &ok_extern_block);
    testing::add(suite, "ok_extern_fn_call",        &ok_extern_fn_call);
    testing::add(suite, "ok_extern_struct_ptr",     &ok_extern_struct_ptr);
    testing::add(suite, "ok_extern_union",          &ok_extern_union);
    testing::add(suite, "ok_extern_variadic",       &ok_extern_variadic);
    testing::add(suite, "err_extern_call_arity",    &err_extern_call_arity);
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
    testing::add(suite, "ok_comptime_and_shortcircuit", &ok_comptime_and_shortcircuit);
    testing::add(suite, "ok_comptime_or_shortcircuit",  &ok_comptime_or_shortcircuit);
    testing::add(suite, "ok_logical_pointer_operands",  &ok_logical_pointer_operands);
    testing::add(suite, "ok_logical_mixed_truthy_operands", &ok_logical_mixed_truthy_operands);
    testing::add(suite, "ok_enum_arithmetic",           &ok_enum_arithmetic);
    testing::add(suite, "ok_enum_bitwise",              &ok_enum_bitwise);
    testing::add(suite, "ok_enum_unary",                &ok_enum_unary);
    testing::add(suite, "err_enum_eq_int_strict",       &err_enum_eq_int_strict);
    testing::add(suite, "err_logical_float_operand",    &err_logical_float_operand);
    testing::add(suite, "err_comptime_and_evaluates_rhs", &err_comptime_and_evaluates_rhs);
    testing::add(suite, "err_comptime_div_by_zero",     &err_comptime_div_by_zero);
    testing::add(suite, "err_comptime_shift_range",     &err_comptime_shift_range);
    testing::add(suite, "ok_comptime_struct_lit_mixed", &ok_comptime_struct_lit_mixed);
    testing::add(suite, "ok_comptime_cast_wraps",       &ok_comptime_cast_wraps);
    testing::add(suite, "err_comprun_comperror",     &err_comprun_comperror);
    testing::add(suite, "warn_comprun_compwarning",  &warn_comprun_compwarning);
    testing::add(suite, "err_comprun_var_driven",    &err_comprun_var_driven);
    testing::add(suite, "ok_comprun_var_no_error",   &ok_comprun_var_no_error);
    testing::add(suite, "err_comprun_while",         &err_comprun_while);
    testing::add(suite, "err_comprun_calls_fn",      &err_comprun_calls_fn);
    testing::add(suite, "ok_const_global_array_dim", &ok_const_global_array_dim);
    testing::add(suite, "ok_const_array_size_folds", &ok_const_array_size_folds);
    testing::add(suite, "err_array_size_not_const", &err_array_size_not_const);
    testing::add(suite, "err_const_global_in_comprun", &err_const_global_in_comprun);
    testing::add(suite, "err_const_chain_in_comprun", &err_const_chain_in_comprun);
    testing::add(suite, "err_bad_const_init",        &err_bad_const_init);
    testing::add(suite, "err_mutable_global_at_comptime", &err_mutable_global_at_comptime);
    testing::add(suite, "ok_compinsert_from_local",   &ok_compinsert_from_local);
    testing::add(suite, "err_compinsert_generated_fn_callable", &err_compinsert_generated_fn_callable);
    testing::add(suite, "err_compinsert_conditional", &err_compinsert_conditional);
    testing::add(suite, "ok_compinsert_in_function",  &ok_compinsert_in_function);
    testing::add(suite, "err_compinsert_in_function_typecheck", &err_compinsert_in_function_typecheck);
    testing::add(suite, "err_compinsert_in_function_no_return", &err_compinsert_in_function_no_return);
    testing::add(suite, "err_compinsert_generates_const", &err_compinsert_generates_const);
    testing::add(suite, "ok_compinsert_generates_struct", &ok_compinsert_generates_struct);
    testing::add(suite, "err_compinsert_rejects_import", &err_compinsert_rejects_import);
    testing::add(suite, "err_compinsert_position_registry", &err_compinsert_position_registry);
    testing::add(suite, "err_compinsert_string_literal", &err_compinsert_string_literal);
    testing::add(suite, "err_compinsert_rejects_export", &err_compinsert_rejects_export);
    testing::add(suite, "err_comptime_typeinfo_size", &err_comptime_typeinfo_size);
    testing::add(suite, "err_comptime_typeinfo_fields", &err_comptime_typeinfo_fields);
    testing::add(suite, "err_comptime_typeinfo_field_name", &err_comptime_typeinfo_field_name);
    testing::add(suite, "err_comptime_bytes_len",     &err_comptime_bytes_len);
    testing::add(suite, "err_comptime_bytes_index",   &err_comptime_bytes_index);
    testing::add(suite, "err_comptime_undefined",     &err_comptime_undefined);
    testing::add(suite, "err_comptime_fnptr_call",    &err_comptime_fnptr_call);
    testing::add(suite, "err_comptime_array_mutate",  &err_comptime_array_mutate);
    testing::add(suite, "err_comptime_struct_mutate", &err_comptime_struct_mutate);
    testing::add(suite, "err_comptime_enum_chain",    &err_comptime_enum_chain);
    testing::add(suite, "err_comptime_cast",         &err_comptime_cast);
    testing::add(suite, "err_comptime_enum_member",  &err_comptime_enum_member);
    testing::add(suite, "err_comptime_enum_switch",  &err_comptime_enum_switch);
    testing::add(suite, "err_comptime_struct_member", &err_comptime_struct_member);
    testing::add(suite, "err_comptime_array_index",  &err_comptime_array_index);
    testing::add(suite, "err_comptime_defer",        &err_comptime_defer);
    testing::add(suite, "err_comptime_break",        &err_comptime_break);
    testing::add(suite, "err_comptime_continue",     &err_comptime_continue);
    testing::add(suite, "err_comptime_switch_case",  &err_comptime_switch_case);
    testing::add(suite, "err_comptime_switch_default", &err_comptime_switch_default);
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
