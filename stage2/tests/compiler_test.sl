import testing;
import compiler;
import module;
import interner;
import types;
import symbol;
import token;
import diag;
import arena;
import sys;

fn void boot(arena::Arena* a) {
    interner::init(a, 64);
    types::typer_init(a, 64);
    token::load_keywords();
}

fn module::Module* mk_source_module(arena::Arena* a, u8[] name, u8[] src) {
    module::Module* m = (module::Module*)arena::alloc(a, sizeof(module::Module));
    sys::memset(m, 0, sizeof(module::Module));
    m.arena = a;
    m.source = src;
    m.name = interner::intern(name);
    return m;
}

fn void wire_imports(arena::Arena* a, module::Module* m, module::Module* dep) {
    module::Module** imps = (module::Module**)arena::alloc(a, sizeof(module::Module*));
    imps[0] = dep;
    m.imports = {imps, 1};
}

fn i32 single_module_ok(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    compiler::add_module(c, mk_source_module(a, "main", "export fn i32 main() { return 0; }"));
    i32 rc = compiler::run_frontend(c);
    if(!testing::expect_eq(rc, 0, msg)) { return -1; }
    if(!testing::expect_eq(c.error_count, (i64)0, msg)) { return -2; }
    return 0;
}

fn i32 cross_module_ok(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* b = mk_source_module(a, "b", "export fn i32 foo() { return 5; }");
    module::Module* av = mk_source_module(a, "a", "import b;\nexport fn i32 use() { return b::foo(); }");
    wire_imports(a, av, b);
    compiler::add_module(c, av);
    compiler::add_module(c, b);
    i32 rc = compiler::run_frontend(c);
    if(!testing::expect_eq(rc, 0, msg)) { return -1; }
    if(!testing::expect_eq(c.error_count, (i64)0, msg)) { return -2; }
    return 0;
}

fn i32 circular_imports_ok(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* av = mk_source_module(a, "a", "import b;\nexport fn i32 fa() { return b::fb(); }");
    module::Module* b = mk_source_module(a, "b", "import a;\nexport fn i32 fb() { return a::fa(); }");
    wire_imports(a, av, b);
    wire_imports(a, b, av);
    compiler::add_module(c, av);
    compiler::add_module(c, b);
    i32 rc = compiler::run_frontend(c);
    if(!testing::expect_eq(rc, 0, msg)) { return -1; }
    if(!testing::expect_eq(c.error_count, (i64)0, msg)) { return -2; }
    return 0;
}

fn i32 sema_error_bails(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    compiler::add_module(c, mk_source_module(a, "main", "export fn i32 main() { return undefined_thing; }"));
    i32 rc = compiler::run_frontend(c);
    if(!testing::expect_eq(rc, 1, msg)) { return -1; }
    if(!testing::expect_true(c.error_count > 0, msg)) { return -2; }
    return 0;
}

fn i32 cross_module_missing_export_errors(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* b = mk_source_module(a, "b", "fn i32 hidden() { return 5; }");
    module::Module* av = mk_source_module(a, "a", "import b;\nexport fn i32 use() { return b::hidden(); }");
    wire_imports(a, av, b);
    compiler::add_module(c, av);
    compiler::add_module(c, b);
    i32 rc = compiler::run_frontend(c);
    if(!testing::expect_eq(rc, 1, msg)) { return -1; }
    if(!testing::expect_true(c.error_count > 0, msg)) { return -2; }
    return 0;
}

fn i32 parse_error_bails(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    compiler::add_module(c, mk_source_module(a, "main", "export fn i32 main() { return 1 + }"));
    i32 rc = compiler::run_frontend(c);
    if(!testing::expect_eq(rc, 1, msg)) { return -1; }
    if(!testing::expect_true(c.error_count > 0, msg)) { return -2; }
    return 0;
}

fn i32 drain_warning_not_counted(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* m = mk_source_module(a, "main", "");
    compiler::add_module(c, m);
    diag::report_warning(&m.diag, a, 0, "just a warning");
    compiler::drain_diagnostics(c);
    if(!testing::expect_eq(c.error_count, (i64)0, msg)) { return -1; }
    diag::report(&m.diag, a, 0, "an error");
    compiler::drain_diagnostics(c);
    if(!testing::expect_eq(c.error_count, (i64)1, msg)) { return -2; }
    return 0;
}

fn i32 add_module_grows(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    for(u64 i = 0; i < 10; i += 1) {
        compiler::add_module(c, mk_source_module(a, "m", "export fn i32 f() { return 0; }"));
    }
    if(!testing::expect_eq(c.modules.len, (u64)10, msg)) { return -1; }
    i32 rc = compiler::run_frontend(c);
    if(!testing::expect_eq(rc, 0, msg)) { return -2; }
    return 0;
}

fn i32 main() {
    testing::init();

    u8[] fe = "Compiler Frontend Tests";
    testing::add(fe, "single_module_ok",       &single_module_ok);
    testing::add(fe, "cross_module_ok",        &cross_module_ok);
    testing::add(fe, "circular_imports_ok",    &circular_imports_ok);
    testing::add(fe, "sema_error_bails",       &sema_error_bails);
    testing::add(fe, "cross_module_missing_export_errors", &cross_module_missing_export_errors);
    testing::add(fe, "parse_error_bails",      &parse_error_bails);
    testing::add(fe, "drain_warning_not_counted", &drain_warning_not_counted);
    testing::add(fe, "add_module_grows",       &add_module_grows);

    return testing::run();
}
