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
    return testing::run();
}
