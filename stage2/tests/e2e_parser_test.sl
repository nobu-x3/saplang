import testing;
import test_util;
import module;
import arena;

fn i32 ok_parses(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { i32 x = 1; return x; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 err_missing_semicolon(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { i32 x = 1 return x; }");
    if(!testing::expect_ge(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "expected ';', got 'return'", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)30, m)) { return -3; }
    return 0;
}

fn i32 err_bad_expr(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { return 1 +; }");
    if(!testing::expect_ge(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "expected identifier, got ';'", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)30, m)) { return -3; }
    return 0;
}

fn i32 err_unclosed_block(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { return 0;");
    if(!testing::expect_ge(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "expected '}', got end of file", m)) { return -2; }
    return 0;
}

fn i32 err_param_no_name(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f(i32) { return 0; }");
    if(!testing::expect_ge(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "expected identifier, got ')'", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)19, m)) { return -3; }
    return 0;
}

fn i32 main() {
    testing::init();
    u8[] suite = "E2E Parser Tests";
    testing::add(suite, "ok_parses",             &ok_parses);
    testing::add(suite, "err_missing_semicolon", &err_missing_semicolon);
    testing::add(suite, "err_bad_expr",          &err_bad_expr);
    testing::add(suite, "err_unclosed_block",    &err_unclosed_block);
    testing::add(suite, "err_param_no_name",     &err_param_no_name);
    return testing::run();
}
