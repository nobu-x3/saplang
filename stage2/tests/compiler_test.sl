import testing;
import compiler;
import module;
import interner;
import types;
import symbol;
import token;
import diag;
import io;
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

fn i32 generic_template_frontend(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    compiler::add_module(c, mk_source_module(a, "main", "fn T id(comptime Type T, T x) { return x; }\nexport fn i32 main() { return 0; }"));
    i32 rc = compiler::run_frontend(c);
    if(!testing::expect_eq(rc, 0, msg)) { return -1; }
    if(!testing::expect_eq(c.error_count, (i64)0, msg)) { return -2; }
    return 0;
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

fn i32 cross_module_overload(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* b = mk_source_module(a, "b", "export fn i32 pick(i32 x) { return x; }\nexport fn i32 pick(f32 x) { return 0; }");
    module::Module* av = mk_source_module(a, "a", "import b;\nexport fn i32 use() { return b::pick(7); }");
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

fn void write_file(u8[] path, u8[] content) {
    io::File f = io::open(path, "w");
    io::write_string(&f, content);
    io::close(&f);
}

fn i32 discover_multi(arena::Arena* a, u8[] msg) {
    boot(a);
    write_file("/tmp/sdhelp.sl", "export fn i32 foo() { return 5; }");
    write_file("/tmp/sdmain.sl", "import sdhelp;\nexport fn i32 use() { return sdhelp::foo(); }");
    compiler::Compiler* c = compiler::new(a);
    compiler::add_source(c, "/tmp/sdmain.sl");
    compiler::add_import_path(c, "/tmp");
    compiler::discover(c);
    i32 result = 0;
    if(!testing::expect_eq(c.modules.len, (u64)2, msg)) { result = -1; }
    else if(!testing::expect_eq((void*)c.modules[0].name, (void*)interner::intern("sdmain"), msg)) { result = -2; }
    else if(!testing::expect_eq(c.modules[0].imports.len, (u64)1, msg)) { result = -3; }
    else if(!testing::expect_eq((void*)c.modules[0].imports[0].name, (void*)interner::intern("sdhelp"), msg)) { result = -4; }
    io::unlink("/tmp/sdhelp.sl");
    io::unlink("/tmp/sdmain.sl");
    return result;
}

fn i32 discover_transitive(arena::Arena* a, u8[] msg) {
    boot(a);
    write_file("/tmp/sdb.sl", "export fn i32 b() { return 1; }");
    write_file("/tmp/sda.sl", "import sdb;\nexport fn i32 a() { return sdb::b(); }");
    write_file("/tmp/sdmain3.sl", "import sda;\nexport fn i32 main() { return sda::a(); }");
    compiler::Compiler* c = compiler::new(a);
    compiler::add_source(c, "/tmp/sdmain3.sl");
    compiler::add_import_path(c, "/tmp");
    compiler::discover(c);
    i32 result = 0;
    if(!testing::expect_eq(c.modules.len, (u64)3, msg)) { result = -1; }
    else if(!testing::expect_eq(compiler::run_frontend(c), 0, msg)) { result = -2; }
    io::unlink("/tmp/sdb.sl");
    io::unlink("/tmp/sda.sl");
    io::unlink("/tmp/sdmain3.sl");
    return result;
}

fn i32 discover_dedups_shared_import(arena::Arena* a, u8[] msg) {
    boot(a);
    write_file("/tmp/sdb2.sl", "export fn i32 b() { return 1; }");
    write_file("/tmp/sda2.sl", "import sdb2;\nexport fn i32 a() { return sdb2::b(); }");
    write_file("/tmp/sdmain4.sl", "import sda2;\nimport sdb2;\nexport fn i32 main() { return sda2::a() + sdb2::b(); }");
    compiler::Compiler* c = compiler::new(a);
    compiler::add_source(c, "/tmp/sdmain4.sl");
    compiler::add_import_path(c, "/tmp");
    compiler::discover(c);
    i32 result = 0;
    if(!testing::expect_eq(c.modules.len, (u64)3, msg)) { result = -1; }
    io::unlink("/tmp/sdb2.sl");
    io::unlink("/tmp/sda2.sl");
    io::unlink("/tmp/sdmain4.sl");
    return result;
}

fn i32 discover_missing_reports(arena::Arena* a, u8[] msg) {
    boot(a);
    write_file("/tmp/sdmain5.sl", "import sdnope;\nexport fn i32 main() { return 0; }");
    compiler::Compiler* c = compiler::new(a);
    compiler::add_source(c, "/tmp/sdmain5.sl");
    compiler::add_import_path(c, "/tmp");
    compiler::discover(c);
    i32 result = 0;
    if(!testing::expect_eq(c.modules.len, (u64)1, msg)) { result = -1; }
    else if(!testing::expect_ge(c.modules[0].diag.entries.len, 1, msg)) { result = -2; }
    else if(!testing::expect_eq(c.modules[0].diag.entries[0].msg, "module not found", msg)) { result = -3; }
    io::unlink("/tmp/sdmain5.sl");
    return result;
}

fn i32 discover_single_no_imports(arena::Arena* a, u8[] msg) {
    boot(a);
    write_file("/tmp/sdsingle.sl", "export fn i32 main() { return 0; }");
    compiler::Compiler* c = compiler::new(a);
    compiler::add_source(c, "/tmp/sdsingle.sl");
    compiler::add_import_path(c, "/tmp");
    compiler::discover(c);
    i32 result = 0;
    if(!testing::expect_eq(c.modules.len, (u64)1, msg)) { result = -1; }
    else if(!testing::expect_eq(c.modules[0].imports.len, (u64)0, msg)) { result = -2; }
    io::unlink("/tmp/sdsingle.sl");
    return result;
}

fn i32 discover_missing_entry_reports(arena::Arena* a, u8[] msg) {
    boot(a);
    io::unlink("/tmp/sd_nonexistent_xyz.sl");
    compiler::Compiler* c = compiler::new(a);
    compiler::add_source(c, "/tmp/sd_nonexistent_xyz.sl");
    compiler::discover(c);
    i32 result = 0;
    if(!testing::expect_eq(c.modules.len, (u64)1, msg)) { result = -1; }
    else if(!testing::expect_ge(c.modules[0].diag.entries.len, 1, msg)) { result = -2; }
    else if(!testing::expect_eq(c.modules[0].diag.entries[0].msg, "cannot read source file", msg)) { result = -3; }
    return result;
}

fn i32 discover_conditional_compilation(arena::Arena* a, u8[] msg) {
    boot(a);
    write_file("/tmp/sdcc.sl", "export fn i32 x() { return 1; }");
    write_file("/tmp/sdcc.linux.sl", "export fn i32 x() { return 2; }");
    write_file("/tmp/sdmain6.sl", "import sdcc;\nexport fn i32 main() { return sdcc::x(); }");
    compiler::Compiler* c = compiler::new(a);
    compiler::add_source(c, "/tmp/sdmain6.sl");
    compiler::add_import_path(c, "/tmp");
    compiler::set_target(c, "linux");
    compiler::discover(c);
    i32 result = 0;
    if(!testing::expect_eq(c.modules.len, (u64)2, msg)) { result = -1; }
    else if(!testing::expect_eq(c.modules[1].source, "export fn i32 x() { return 2; }", msg)) { result = -2; }
    io::unlink("/tmp/sdcc.sl");
    io::unlink("/tmp/sdcc.linux.sl");
    io::unlink("/tmp/sdmain6.sl");
    return result;
}

fn i32 discover_target_fallback(arena::Arena* a, u8[] msg) {
    boot(a);
    io::unlink("/tmp/sdfb.linux.sl");
    write_file("/tmp/sdfb.sl", "export fn i32 y() { return 7; }");
    write_file("/tmp/sdmain7.sl", "import sdfb;\nexport fn i32 main() { return sdfb::y(); }");
    compiler::Compiler* c = compiler::new(a);
    compiler::add_source(c, "/tmp/sdmain7.sl");
    compiler::add_import_path(c, "/tmp");
    compiler::set_target(c, "linux");
    compiler::discover(c);
    i32 result = 0;
    if(!testing::expect_eq(c.modules.len, (u64)2, msg)) { result = -1; }
    else if(!testing::expect_eq(compiler::run_frontend(c), 0, msg)) { result = -2; }
    io::unlink("/tmp/sdfb.sl");
    io::unlink("/tmp/sdmain7.sl");
    return result;
}

fn i32 multithreaded_frontend(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    compiler::set_multithreaded(c, true);
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

fn i32 multithreaded_circular_stress(arena::Arena* a, u8[] msg) {
    boot(a);
    for(u64 iter = 0; iter < 20; iter += 1) {
        compiler::Compiler* c = compiler::new(a);
        compiler::set_multithreaded(c, true);
        module::Module* av = mk_source_module(a, "a", "import b;\nexport fn i32 fa() { return b::fb(); }");
        module::Module* b = mk_source_module(a, "b", "import a;\nexport fn i32 fb() { return a::fa(); }");
        wire_imports(a, av, b);
        wire_imports(a, b, av);
        compiler::add_module(c, av);
        compiler::add_module(c, b);
        if(!testing::expect_eq(compiler::run_frontend(c), 0, msg)) { return -1; }
        if(!testing::expect_eq(c.error_count, (i64)0, msg)) { return -2; }
    }
    return 0;
}

fn i32 multithreaded_error_bails(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    compiler::set_multithreaded(c, true);
    compiler::add_module(c, mk_source_module(a, "main", "export fn i32 main() { return undefined_thing; }"));
    i32 rc = compiler::run_frontend(c);
    if(!testing::expect_eq(rc, 1, msg)) { return -1; }
    if(!testing::expect_true(c.error_count > 0, msg)) { return -2; }
    return 0;
}

fn i32 run_file_ok(arena::Arena* a, u8[] msg) {
    boot(a);
    write_file("/tmp/sdrun_helper.sl", "export fn i32 foo() { return 5; }");
    write_file("/tmp/sdrun_main.sl", "import sdrun_helper;\nexport fn i32 main() { return sdrun_helper::foo(); }");
    compiler::Compiler* c = compiler::new(a);
    compiler::add_source(c, "/tmp/sdrun_main.sl");
    compiler::add_import_path(c, "/tmp");
    i32 rc = compiler::run(c);
    i32 result = 0;
    if(!testing::expect_eq(rc, 0, msg)) { result = -1; }
    io::unlink("/tmp/sdrun_helper.sl");
    io::unlink("/tmp/sdrun_main.sl");
    return result;
}

fn i32 run_file_missing_import(arena::Arena* a, u8[] msg) {
    boot(a);
    write_file("/tmp/sdrun_bad.sl", "import sdrun_nope;\nexport fn i32 main() { return 0; }");
    compiler::Compiler* c = compiler::new(a);
    compiler::add_source(c, "/tmp/sdrun_bad.sl");
    compiler::add_import_path(c, "/tmp");
    i32 rc = compiler::run(c);
    i32 result = 0;
    if(!testing::expect_eq(rc, 1, msg)) { result = -1; }
    io::unlink("/tmp/sdrun_bad.sl");
    return result;
}

fn i32 run_file_sema_error(arena::Arena* a, u8[] msg) {
    boot(a);
    write_file("/tmp/sdrun_se.sl", "export fn i32 main() { return undefined_thing; }");
    compiler::Compiler* c = compiler::new(a);
    compiler::add_source(c, "/tmp/sdrun_se.sl");
    compiler::add_import_path(c, "/tmp");
    i32 rc = compiler::run(c);
    i32 result = 0;
    if(!testing::expect_eq(rc, 1, msg)) { result = -1; }
    io::unlink("/tmp/sdrun_se.sl");
    return result;
}

fn i32 no_double_scan(arena::Arena* a, u8[] msg) {
    boot(a);
    write_file("/tmp/sdds_helper.sl", "export fn i32 foo() { return 5; }");
    write_file("/tmp/sdds_main.sl", "import sdds_helper;\nexport fn i32 main() { return sdds_helper::foo(); }");
    compiler::Compiler* c = compiler::new(a);
    compiler::add_source(c, "/tmp/sdds_main.sl");
    compiler::add_import_path(c, "/tmp");
    compiler::discover(c);
    u64 tokens_after_discover = c.modules[0].tokens.len;
    compiler::run_frontend(c);
    i32 result = 0;
    if(!testing::expect_true(tokens_after_discover > 0, msg)) { result = -1; }
    else if(!testing::expect_eq(c.modules[0].tokens.len, tokens_after_discover, msg)) { result = -2; }
    io::unlink("/tmp/sdds_helper.sl");
    io::unlink("/tmp/sdds_main.sl");
    return result;
}

fn u8[][] mk_args(arena::Arena* a, u64 count) {
    u8[][] args = {null, 0};
    args.len = count;
    args.ptr = arena::alloc(a, count * sizeof(u8[]));
    return args;
}

fn i32 argv_full(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    u8[][] args = mk_args(a, 6);
    args[0] = "main.sl";
    args[1] = "-i";
    args[2] = "/tmp;/usr/lib";
    args[3] = "-target";
    args[4] = "linux";
    args[5] = "-mt";
    if(!testing::expect_true(compiler::parse_argv(c, args), msg)) { return -1; }
    if(!testing::expect_eq(c.entry_sources.len, (u64)1, msg)) { return -2; }
    if(!testing::expect_eq(c.entry_sources[0], "main.sl", msg)) { return -3; }
    if(!testing::expect_eq(c.import_paths.len, (u64)2, msg)) { return -4; }
    if(!testing::expect_eq(c.import_paths[0], "/tmp", msg)) { return -5; }
    if(!testing::expect_eq(c.import_paths[1], "/usr/lib", msg)) { return -6; }
    if(!testing::expect_eq(c.target, "linux", msg)) { return -7; }
    if(!testing::expect_true(c.is_multithreaded, msg)) { return -8; }
    return 0;
}

fn i32 argv_unknown_fails(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    u8[][] args = mk_args(a, 1);
    args[0] = "--nonsense";
    if(!testing::expect_true(!compiler::parse_argv(c, args), msg)) { return -1; }
    return 0;
}

fn i32 argv_dangling_flag_fails(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    u8[][] args = mk_args(a, 1);
    args[0] = "-i";
    if(!testing::expect_true(!compiler::parse_argv(c, args), msg)) { return -1; }
    return 0;
}

fn i32 main() {
    testing::init();

    u8[] fe = "Compiler Frontend Tests";
    testing::add(fe, "single_module_ok",       &single_module_ok);
    testing::add(fe, "generic_template_frontend", &generic_template_frontend);
    testing::add(fe, "cross_module_ok",        &cross_module_ok);
    testing::add(fe, "cross_module_overload",  &cross_module_overload);
    testing::add(fe, "circular_imports_ok",    &circular_imports_ok);
    testing::add(fe, "sema_error_bails",       &sema_error_bails);
    testing::add(fe, "cross_module_missing_export_errors", &cross_module_missing_export_errors);
    testing::add(fe, "parse_error_bails",      &parse_error_bails);
    testing::add(fe, "drain_warning_not_counted", &drain_warning_not_counted);
    testing::add(fe, "add_module_grows",       &add_module_grows);
    testing::add(fe, "multithreaded_frontend", &multithreaded_frontend);
    testing::add(fe, "multithreaded_circular_stress", &multithreaded_circular_stress);
    testing::add(fe, "multithreaded_error_bails", &multithreaded_error_bails);

    u8[] dv = "Compiler Discovery Tests";
    testing::add(dv, "discover_multi",              &discover_multi);
    testing::add(dv, "discover_transitive",         &discover_transitive);
    testing::add(dv, "discover_dedups_shared_import", &discover_dedups_shared_import);
    testing::add(dv, "discover_missing_reports",    &discover_missing_reports);
    testing::add(dv, "discover_single_no_imports",  &discover_single_no_imports);
    testing::add(dv, "discover_missing_entry_reports", &discover_missing_entry_reports);
    testing::add(dv, "discover_conditional_compilation", &discover_conditional_compilation);
    testing::add(dv, "discover_target_fallback",     &discover_target_fallback);

    u8[] rn = "Compiler Run Tests";
    testing::add(rn, "run_file_ok",             &run_file_ok);
    testing::add(rn, "run_file_missing_import", &run_file_missing_import);
    testing::add(rn, "run_file_sema_error",     &run_file_sema_error);
    testing::add(rn, "no_double_scan",          &no_double_scan);

    u8[] av = "Compiler Argv Tests";
    testing::add(av, "argv_full",               &argv_full);
    testing::add(av, "argv_unknown_fails",      &argv_unknown_fails);
    testing::add(av, "argv_dangling_flag_fails", &argv_dangling_flag_fails);

    return testing::run();
}
