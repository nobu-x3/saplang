import testing;
import compiler;
import link_paths;
import module;
import interner;
import types;
import symbol;
import token;
import diag;
import codegen;
import sapir;
import sapir_print;
import io;
import arena;
import sys;

fn arena::Arena* sub_arena(arena::Arena* a) {
    arena::Arena* sub = (arena::Arena*)arena::alloc(a, sizeof(arena::Arena));
    sys::memset(sub, 0, sizeof(arena::Arena));
    sub.default_page_size = 1048576;
    return sub;
}

fn void boot(arena::Arena* a) {
    interner::init(sub_arena(a), 64);
    types::typer_init(sub_arena(a), 64);
    token::load_keywords();
}

fn module::Module* mk_source_module(arena::Arena* a, u8[] name, u8[] src) {
    module::Module* m = (module::Module*)arena::alloc(a, sizeof(module::Module));
    sys::memset(m, 0, sizeof(module::Module));
    m.arena = sub_arena(a);
    m.source = src;
    m.name = interner::intern(name);
    return m;
}

fn void wire_imports(arena::Arena* a, module::Module* m, module::Module* dep) {
    module::Module** imps = (module::Module**)arena::alloc(a, sizeof(module::Module*));
    imps[0] = dep;
    m.imports = {imps, 1};
}

fn i32 cross_module_generic_call(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* b = mk_source_module(a, "b", "export fn T id(comptime Type T, T x) { return x; }");
    module::Module* av = mk_source_module(a, "a", "import b;\nexport fn i32 use() { return b::id(5); }");
    wire_imports(a, av, b);
    compiler::add_module(c, av);
    compiler::add_module(c, b);
    i32 rc = compiler::run_frontend(c);
    if(!testing::expect_eq(rc, 0, msg)) { return -1; }
    if(!testing::expect_eq(c.error_count, (i64)0, msg)) { return -2; }
    if(!testing::expect_eq(av.instantiated_fns.len, (u64)1, msg)) { return -3; }
    return 0;
}

// A generic in `b` whose body uses b's own private type resolves that type against b (its defining module),
// not the caller `a`, when monomorphized — the clone re-check uses the defining module's scope.
// A type constructor is interned process-wide, so the same instantiation is one type in both modules.
fn i32 cross_module_generic_type_identity(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* b = mk_source_module(a, "b", "fn Type Box(comptime Type T) { return struct { T value; }; }\nexport alias BoxI32 = Box(i32);\nexport fn i32 unwrap(BoxI32 x) { return x.value; }");
    module::Module* av = mk_source_module(a, "a", "import b;\nfn Type Box(comptime Type T) { return struct { T value; }; }\nexport fn i32 use() { b::BoxI32 mine; mine.value = 7; return b::unwrap(mine); }");
    wire_imports(a, av, b);
    compiler::add_module(c, av);
    compiler::add_module(c, b);
    i32 rc = compiler::run_frontend(c);
    if(!testing::expect_eq(rc, 0, msg)) { return -1; }
    if(!testing::expect_eq(c.error_count, (i64)0, msg)) { return -2; }
    return 0;
}

fn i32 cross_module_generic_uses_home_type(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* b = mk_source_module(a, "b", "struct Helper { i32 v; }\nexport fn T wrap(comptime Type T, T x) { Helper h; return x; }");
    module::Module* av = mk_source_module(a, "a", "import b;\nexport fn i32 use() { return b::wrap(5); }");
    wire_imports(a, av, b);
    compiler::add_module(c, av);
    compiler::add_module(c, b);
    i32 rc = compiler::run_frontend(c);
    if(!testing::expect_eq(rc, 0, msg)) { return -1; }
    if(!testing::expect_eq(c.error_count, (i64)0, msg)) { return -2; }
    if(!testing::expect_eq(av.instantiated_fns.len, (u64)1, msg)) { return -3; }
    return 0;
}

// A comprun in module `a` calls `b::dbl(5)` at comptime; the callee is body-checked on demand in module b.
// Positive: condition is false, so no comperror — proves the cross-module call evaluated without error.
fn i32 cross_module_comptime_call_ok(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* b = mk_source_module(a, "b", "export fn i32 dbl(i32 n) { return n * 2; }");
    module::Module* av = mk_source_module(a, "a", "import b;\nexport fn i32 use() { comprun { if(b::dbl(5) == 999) { comperror(\"nope\"); } } return 0; }");
    wire_imports(a, av, b);
    compiler::add_module(c, av);
    compiler::add_module(c, b);
    i32 rc = compiler::run_frontend(c);
    if(!testing::expect_eq(rc, 0, msg)) { return -1; }
    if(!testing::expect_eq(c.error_count, (i64)0, msg)) { return -2; }
    return 0;
}

// Negative: condition is true (b::dbl(5) == 10), so the comperror fires — pins the returned comptime value.
fn i32 cross_module_comptime_call_err(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* b = mk_source_module(a, "b", "export fn i32 dbl(i32 n) { return n * 2; }");
    module::Module* av = mk_source_module(a, "a", "import b;\nexport fn i32 use() { comprun { if(b::dbl(5) == 10) { comperror(\"hit\"); } } return 0; }");
    wire_imports(a, av, b);
    compiler::add_module(c, av);
    compiler::add_module(c, b);
    i32 rc = compiler::run_frontend(c);
    if(!testing::expect_eq(rc, 1, msg)) { return -1; }
    if(!testing::expect_eq(c.error_count, (i64)1, msg)) { return -2; }
    return 0;
}

// A comprun in module `a` reads a const exported by module `b` at comptime.
fn i32 cross_module_const_read_ok(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* b = mk_source_module(a, "b", "export const i32 K = 9;");
    module::Module* av = mk_source_module(a, "a", "import b;\nexport fn i32 use() { comprun { if(b::K == 999) { comperror(\"nope\"); } } return 0; }");
    wire_imports(a, av, b);
    compiler::add_module(c, av);
    compiler::add_module(c, b);
    i32 rc = compiler::run_frontend(c);
    if(!testing::expect_eq(rc, 0, msg)) { return -1; }
    if(!testing::expect_eq(c.error_count, (i64)0, msg)) { return -2; }
    return 0;
}

fn i32 cross_module_const_read_err(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* b = mk_source_module(a, "b", "export const i32 K = 9;");
    module::Module* av = mk_source_module(a, "a", "import b;\nexport fn i32 use() { comprun { if(b::K == 9) { comperror(\"k9\"); } } return 0; }");
    wire_imports(a, av, b);
    compiler::add_module(c, av);
    compiler::add_module(c, b);
    i32 rc = compiler::run_frontend(c);
    if(!testing::expect_eq(rc, 1, msg)) { return -1; }
    if(!testing::expect_eq(c.error_count, (i64)1, msg)) { return -2; }
    return 0;
}

fn i32 generic_call_frontend(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    compiler::add_module(c, mk_source_module(a, "main", "fn T id(comptime Type T, T x) { return x; }\nexport fn i32 main() { return id(5); }"));
    i32 rc = compiler::run_frontend(c);
    if(!testing::expect_eq(rc, 0, msg)) { return -1; }
    if(!testing::expect_eq(c.error_count, (i64)0, msg)) { return -2; }
    return 0;
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
    else if(!testing::expect_eq((void*)c.modules.ptr[0].name, (void*)interner::intern("sdmain"), msg)) { result = -2; }
    else if(!testing::expect_eq(c.modules.ptr[0].imports.len, (u64)1, msg)) { result = -3; }
    else if(!testing::expect_eq((void*)c.modules.ptr[0].imports[0].name, (void*)interner::intern("sdhelp"), msg)) { result = -4; }
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

fn i32 discover_sets_path_and_line_col(arena::Arena* a, u8[] msg) {
    boot(a);
    write_file("/tmp/sdpos.sl", "export fn i32 f() {\n    return 0;\n}");
    compiler::Compiler* c = compiler::new(a);
    compiler::add_source(c, "/tmp/sdpos.sl");
    compiler::discover(c);
    module::Module* m = c.modules.ptr[0];
    i32 result = 0;
    if(!testing::expect_eq(m.path, "/tmp/sdpos.sl", msg)) { result = -1; }
    u32 line = 0;
    u32 col = 0;
    module::line_col(m, 0, &line, &col);
    if(result == 0 && !testing::expect_eq(line, (u32)1, msg)) { result = -2; }
    if(result == 0 && !testing::expect_eq(col, (u32)1, msg)) { result = -3; }
    module::line_col(m, 24, &line, &col);
    if(result == 0 && !testing::expect_eq(line, (u32)2, msg)) { result = -4; }
    if(result == 0 && !testing::expect_eq(col, (u32)5, msg)) { result = -5; }
    io::unlink("/tmp/sdpos.sl");
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
    else if(!testing::expect_ge(c.modules.ptr[0].diag.entries.len, 1, msg)) { result = -2; }
    else if(!testing::expect_eq(c.modules.ptr[0].diag.entries[0].msg, "module not found", msg)) { result = -3; }
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
    else if(!testing::expect_eq(c.modules.ptr[0].imports.len, (u64)0, msg)) { result = -2; }
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
    else if(!testing::expect_ge(c.modules.ptr[0].diag.entries.len, 1, msg)) { result = -2; }
    else if(!testing::expect_eq(c.modules.ptr[0].diag.entries[0].msg, "cannot read source file", msg)) { result = -3; }
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
    else if(!testing::expect_eq(c.modules.ptr[1].source, "export fn i32 x() { return 2; }", msg)) { result = -2; }
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
    u64 tokens_after_discover = c.modules.ptr[0].tokens.len;
    compiler::run_frontend(c);
    i32 result = 0;
    if(!testing::expect_true(tokens_after_discover > 0, msg)) { result = -1; }
    else if(!testing::expect_eq(c.modules.ptr[0].tokens.len, tokens_after_discover, msg)) { result = -2; }
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
    if(!testing::expect_eq(c.entry_sources.ptr[0], "main.sl", msg)) { return -3; }
    if(!testing::expect_eq(c.import_paths.len, (u64)2, msg)) { return -4; }
    if(!testing::expect_eq(c.import_paths.ptr[0], "/tmp", msg)) { return -5; }
    if(!testing::expect_eq(c.import_paths.ptr[1], "/usr/lib", msg)) { return -6; }
    if(!testing::expect_eq(c.target, "linux", msg)) { return -7; }
    if(!testing::expect_true(c.is_multithreaded, msg)) { return -8; }
    return 0;
}

fn i32 argv_compile_only(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    u8[][] args = mk_args(a, 2);
    args[0] = "main.sl";
    args[1] = "-c";
    if(!testing::expect_true(compiler::parse_argv(c, args), msg)) { return -1; }
    if(!testing::expect_true(c.compile_only, msg)) { return -2; }
    return 0;
}

fn i32 argv_dump_flags(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    u8[][] args = mk_args(a, 5);
    args[0] = "main.sl";
    args[1] = "-token-dump";
    args[2] = "-ast-dump";
    args[3] = "-llvm-dump";
    args[4] = "-show-timings";
    if(!testing::expect_true(compiler::parse_argv(c, args), msg)) { return -1; }
    if(!testing::expect_true(c.token_dump, msg)) { return -2; }
    if(!testing::expect_true(c.ast_dump, msg)) { return -3; }
    if(!testing::expect_true(c.llvm_dump, msg)) { return -4; }
    if(!testing::expect_true(c.show_timings, msg)) { return -5; }
    // token/ast dumps stop before codegen; llvm-dump needs the backend to have run.
    if(!testing::expect_true(compiler::stops_before_backend(c), msg)) { return -6; }
    return 0;
}

fn i32 argv_link_config(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    u8[][] args = mk_args(a, 3);
    args[0] = "main.sl";
    args[1] = "-link-config";
    args[2] = "paths.cfg";
    if(!testing::expect_true(compiler::parse_argv(c, args), msg)) { return -1; }
    if(!testing::expect_eq(c.link_config, "paths.cfg", msg)) { return -2; }
    return 0;
}

// key=value lines override probed paths; comments and unknown keys are ignored.
fn i32 link_config_override(arena::Arena* a, u8[] msg) {
    io::File f = io::open("lp_test.cfg", "w");
    if(!testing::expect_true(f.fp != null, msg)) { return -1; }
    io::write_string(&f, "# comment
crt_start=/tmp/custom/Scrt1.o
unknown_key=ignored
lib_dir=/tmp/custom
");
    io::close(&f);

    link_paths::LinkPaths paths = link_paths::resolve(a);
    if(!testing::expect_true(link_paths::apply_override(&paths, a, "lp_test.cfg"), msg)) { return -2; }
    if(!testing::expect_eq(cstr_slice((u8*)paths.crt_start), "/tmp/custom/Scrt1.o", msg)) { return -3; }
    if(!testing::expect_eq(cstr_slice((u8*)paths.lib_dir), "-L/tmp/custom", msg)) { return -4; }
    io::unlink("lp_test.cfg");

    if(!testing::expect_true(!link_paths::apply_override(&paths, a, "no_such_file.cfg"), msg)) { return -5; }
    return 0;
}

fn u8[] cstr_slice(u8* raw) {
    u64 len = 0;
    while(raw[len] != 0) { len += 1; }
    u8[] out = {raw, len};
    return out;
}

fn i32 argv_comptime_limits(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    u8[][] args = mk_args(a, 5);
    args[0] = "main.sl";
    args[1] = "-comptime-depth";
    args[2] = "64";
    args[3] = "-comptime-iterations";
    args[4] = "5000";
    if(!testing::expect_true(compiler::parse_argv(c, args), msg)) { return -1; }
    if(!testing::expect_eq((u64)c.comptime_depth, (u64)64, msg)) { return -2; }
    if(!testing::expect_eq(c.comptime_iterations, (u64)5000, msg)) { return -3; }
    return 0;
}

fn i32 argv_lib_dirs_and_libs(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    u8[][] args = mk_args(a, 5);
    args[0] = "main.sl";
    args[1] = "-L";
    args[2] = "/opt/lib";
    args[3] = "-l";
    args[4] = "foo";
    if(!testing::expect_true(compiler::parse_argv(c, args), msg)) { return -1; }
    if(!testing::expect_eq(c.lib_dirs.len, (u64)1, msg)) { return -2; }
    if(!testing::expect_eq(c.lib_dirs.ptr[0], "/opt/lib", msg)) { return -3; }
    if(!testing::expect_eq(c.extern_libs.len, (u64)1, msg)) { return -4; }
    if(!testing::expect_eq(c.extern_libs.ptr[0], "foo", msg)) { return -5; }
    return 0;
}

fn i32 argv_dangling_L_fails(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    u8[][] args = mk_args(a, 1);
    args[0] = "-L";
    if(!testing::expect_true(!compiler::parse_argv(c, args), msg)) { return -1; }
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

// E2E: run the real driver pipeline (discover-less, in-memory) through lowering and pin the sapir.
fn i32 e2e_lower_single_fn(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* m = mk_source_module(a, "prog", "fn i32 add(i32 x, i32 y) { return x + y; }");
    compiler::add_module(c, m);
    if(!testing::expect_eq(compiler::run_frontend(c), 0, msg)) { return -1; }
    if(!testing::expect_ne((void*)m.sapir, null, msg)) { return -2; }

    u8[] got = sapir_print::print_module_to_arena((sapir::SapirModule*)m.sapir, a);
    io::OutBuf want;
    io::outbuf_init(&want, a, 512);
    io::outbuf_write(&want, "module prog\n\n");
    io::outbuf_write(&want, "fn __prog_add(i32, i32) -> i32 {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = param.i32 0\n");
    io::outbuf_write(&want, "    %1 = param.i32 1\n");
    io::outbuf_write(&want, "    %2 = add.i32 %0, %1\n");
    io::outbuf_write(&want, "    ret %2\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b2:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -3; }
    return 0;
}

// Each module lowers independently and mangles with its own module name.
fn i32 e2e_lower_multi_module(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* dep = mk_source_module(a, "b", "export fn i32 helper() { return 7; }");
    module::Module* app = mk_source_module(a, "a", "import b;\nexport fn i32 use() { return 0; }");
    wire_imports(a, app, dep);
    compiler::add_module(c, app);
    compiler::add_module(c, dep);
    if(!testing::expect_eq(compiler::run_frontend(c), 0, msg)) { return -1; }
    if(!testing::expect_ne((void*)app.sapir, null, msg)) { return -2; }
    if(!testing::expect_ne((void*)dep.sapir, null, msg)) { return -3; }

    u8[] got = sapir_print::print_module_to_arena((sapir::SapirModule*)dep.sapir, a);
    io::OutBuf want;
    io::outbuf_init(&want, a, 512);
    io::outbuf_write(&want, "module b\n\n");
    io::outbuf_write(&want, "fn __b_helper() -> i32 {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = const.i32 7\n");
    io::outbuf_write(&want, "    ret %0\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b2:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -4; }
    return 0;
}

// E2E: a call into an imported module resolves to a Foreign decl mangled off the callee's home module.
fn i32 e2e_lower_cross_module_call(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* dep = mk_source_module(a, "b", "export fn i32 helper() { return 7; }");
    module::Module* app = mk_source_module(a, "a", "import b;\nexport fn i32 use() { return b::helper(); }");
    wire_imports(a, app, dep);
    compiler::add_module(c, app);
    compiler::add_module(c, dep);
    if(!testing::expect_eq(compiler::run_frontend(c), 0, msg)) { return -1; }
    if(!testing::expect_ne((void*)app.sapir, null, msg)) { return -2; }

    u8[] got = sapir_print::print_module_to_arena((sapir::SapirModule*)app.sapir, a);
    io::OutBuf want;
    io::outbuf_init(&want, a, 512);
    io::outbuf_write(&want, "module a\n\n");
    io::outbuf_write(&want, "fn __a_use() -> i32 {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = call.i32 __b_helper()\n");
    io::outbuf_write(&want, "    ret %0\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b2:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -3; }
    return 0;
}

// E2E: source -> codegen -> ld.lld link -> run the produced executable, checking its exit code.
fn i32 e2e_compile_link_run(arena::Arena* a, u8[] msg) {
    boot(a);
    arena::Arena* ca = sub_arena(a);
    compiler::Compiler* c = compiler::new(ca);
    module::Module* m = mk_source_module(ca, "e2eprog", "fn i32 triple(i32 x) { return x * 3; } fn i32 main() { return triple(14); }");
    compiler::add_module(c, m);
    if(!testing::expect_eq(compiler::run_frontend(c), 0, msg)) { return -1; }
    c.output_path = "e2e_out_prog";
    if(!testing::expect_eq(compiler::run_backend(c), 0, msg)) { return -2; }
    if(!testing::expect_eq((u64)compiler::run_executable(ca, "./e2e_out_prog"), (u64)42, msg)) { return -3; }
    return 0;
}

// E2E: a -L dir reaches the linker (build_link_argv emits -L<path>) and the program still links + runs.
fn i32 e2e_lib_dir_flag(arena::Arena* a, u8[] msg) {
    boot(a);
    arena::Arena* ca = sub_arena(a);
    compiler::Compiler* c = compiler::new(ca);
    module::Module* m = mk_source_module(ca, "ldprog", "fn i32 main() { return 42; }");
    compiler::add_module(c, m);
    if(!testing::expect_eq(compiler::run_frontend(c), 0, msg)) { return -1; }
    compiler::add_lib_dir(c, "/usr/lib");
    c.output_path = "e2e_libdir_prog";
    if(!testing::expect_eq(compiler::run_backend(c), 0, msg)) { return -2; }
    if(!testing::expect_eq((u64)compiler::run_executable(ca, "./e2e_libdir_prog"), (u64)42, msg)) { return -3; }
    return 0;
}

// E2E: a -config Release build runs the -O2 pipeline and still produces a correct executable.
fn i32 e2e_release_build(arena::Arena* a, u8[] msg) {
    boot(a);
    arena::Arena* ca = sub_arena(a);
    compiler::Compiler* c = compiler::new(ca);
    module::Module* m = mk_source_module(ca, "relprog", "fn i32 sq(i32 x) { return x * x; } fn i32 main() { i32 s = 0; for(i32 i = 0; i < 7; i = i + 1) { s = s + i; } return s + sq(3) + 12; }");
    compiler::add_module(c, m);
    if(!testing::expect_eq(compiler::run_frontend(c), 0, msg)) { return -1; }
    c.config = codegen::BuildConfig::Release;
    c.output_path = "e2e_release_prog";
    if(!testing::expect_eq(compiler::run_backend(c), 0, msg)) { return -2; }
    if(!testing::expect_eq((u64)compiler::run_executable(ca, "./e2e_release_prog"), (u64)42, msg)) { return -3; }
    return 0;
}

// E2E: a -config AddressSanitizer build instruments, links the asan runtime, and a clean program still runs.
fn i32 e2e_asan_build(arena::Arena* a, u8[] msg) {
    boot(a);
    arena::Arena* ca = sub_arena(a);
    compiler::Compiler* c = compiler::new(ca);
    module::Module* m = mk_source_module(ca, "asanprog", "fn i32 main() { i32 x = 40; i32* p = &x; *p = 42; return x; }");
    compiler::add_module(c, m);
    if(!testing::expect_eq(compiler::run_frontend(c), 0, msg)) { return -1; }
    c.config = codegen::BuildConfig::AddressSanitizer;
    c.output_path = "e2e_asan_prog";
    if(!testing::expect_eq(compiler::run_backend(c), 0, msg)) { return -2; }
    if(!testing::expect_eq((u64)compiler::run_executable(ca, "./e2e_asan_prog"), (u64)42, msg)) { return -3; }
    return 0;
}

// E2E: two modules with a cross-module call -> two object files -> ld.lld -> run.
fn i32 e2e_link_multi_module(arena::Arena* a, u8[] msg) {
    boot(a);
    arena::Arena* ca = sub_arena(a);
    compiler::Compiler* c = compiler::new(ca);
    module::Module* dep = mk_source_module(ca, "dep", "export fn i32 tripled(i32 x) { return x * 3; }");
    module::Module* app = mk_source_module(ca, "appmod", "import dep;\nfn i32 main() { return dep::tripled(14); }");
    wire_imports(ca, app, dep);
    compiler::add_module(c, app);
    compiler::add_module(c, dep);
    if(!testing::expect_eq(compiler::run_frontend(c), 0, msg)) { return -1; }
    c.output_path = "e2e_multi_prog";
    if(!testing::expect_eq(compiler::run_backend(c), 0, msg)) { return -2; }
    if(!testing::expect_eq((u64)compiler::run_executable(ca, "./e2e_multi_prog"), (u64)42, msg)) { return -3; }
    return 0;
}

// E2E: an unresolved extern makes ld.lld fail; the backend surfaces a non-zero result rather than a bad binary.
fn i32 e2e_link_failure_reported(arena::Arena* a, u8[] msg) {
    boot(a);
    arena::Arena* ca = sub_arena(a);
    compiler::Compiler* c = compiler::new(ca);
    module::Module* m = mk_source_module(ca, "badprog", "extern { fn i32 undefined_ext_symbol_xyz(); } fn i32 main() { return undefined_ext_symbol_xyz(); }");
    compiler::add_module(c, m);
    if(!testing::expect_eq(compiler::run_frontend(c), 0, msg)) { return -1; }
    c.output_path = "e2e_bad_prog";
    if(!testing::expect_ne(compiler::run_backend(c), 0, msg)) { return -2; }
    return 0;
}

// A generic template is skipped by lowering (only monomorphized clones are emitted).
fn i32 e2e_generic_template_skipped(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* m = mk_source_module(a, "g", "export fn T id(comptime Type T, T x) { return x; }");
    compiler::add_module(c, m);
    if(!testing::expect_eq(compiler::run_frontend(c), 0, msg)) { return -1; }
    if(!testing::expect_ne((void*)m.sapir, null, msg)) { return -2; }
    sapir::SapirModule* sm = (sapir::SapirModule*)m.sapir;
    if(!testing::expect_eq(sm.fns.len, (u64)0, msg)) { return -3; }
    return 0;
}

// E2E: control flow lowered through the real driver produces the expected phi'd sapir.
fn i32 e2e_lower_control_flow(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* m = mk_source_module(a, "prog", "fn i32 f(bool c) { i32 x = 0; if(c) { x = 1; } else { x = 2; } return x; }");
    compiler::add_module(c, m);
    if(!testing::expect_eq(compiler::run_frontend(c), 0, msg)) { return -1; }
    if(!testing::expect_ne((void*)m.sapir, null, msg)) { return -2; }

    u8[] got = sapir_print::print_module_to_arena((sapir::SapirModule*)m.sapir, a);
    io::OutBuf want;
    io::outbuf_init(&want, a, 512);
    io::outbuf_write(&want, "module prog\n\n");
    io::outbuf_write(&want, "fn __prog_f(bool) -> i32 {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = param.bool 0\n");
    io::outbuf_write(&want, "    %1 = const.i32 0\n");
    io::outbuf_write(&want, "    condbr %0, b2, b3\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b2:  ; preds: b0\n");
    io::outbuf_write(&want, "    %4 = const.i32 1\n");
    io::outbuf_write(&want, "    br b4\n");
    io::outbuf_write(&want, "b3:  ; preds: b0\n");
    io::outbuf_write(&want, "    %6 = const.i32 2\n");
    io::outbuf_write(&want, "    br b4\n");
    io::outbuf_write(&want, "b4:  ; preds: b2, b3\n");
    io::outbuf_write(&want, "    %8 = phi.i32 [b2: %4, b3: %6]\n");
    io::outbuf_write(&want, "    ret %8\n");
    io::outbuf_write(&want, "b5:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -3; }
    return 0;
}

// A while loop lowered through the driver leaves a well-formed sapir module.
fn i32 e2e_lower_loop(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* m = mk_source_module(a, "prog", "fn i32 f(i32 n) { i32 i = 0; while(i < n) { i = i + 1; } return i; }");
    compiler::add_module(c, m);
    if(!testing::expect_eq(compiler::run_frontend(c), 0, msg)) { return -1; }
    if(!testing::expect_ne((void*)m.sapir, null, msg)) { return -2; }
    sapir::SapirModule* sm = (sapir::SapirModule*)m.sapir;
    if(!testing::expect_eq(sm.fns.len, (u64)1, msg)) { return -3; }
    return 0;
}

// The driver fails (rc != 0, error counted) on a not-yet-supported global reference.
// E2E: a const global reads back through a GlobalAddr/Load, and the global itself is emitted, via the driver.
fn i32 e2e_lower_global_ref(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* m = mk_source_module(a, "prog", "const i32 LIMIT = 10; fn i32 f() { return LIMIT; }");
    compiler::add_module(c, m);
    if(!testing::expect_eq(compiler::run_frontend(c), 0, msg)) { return -1; }
    if(!testing::expect_ne((void*)m.sapir, null, msg)) { return -2; }

    u8[] got = sapir_print::print_module_to_arena((sapir::SapirModule*)m.sapir, a);
    io::OutBuf want;
    io::outbuf_init(&want, a, 512);
    io::outbuf_write(&want, "module prog\n\n");
    io::outbuf_write(&want, "global __prog_LIMIT: i32 const = 10\n\n");
    io::outbuf_write(&want, "fn __prog_f() -> i32 {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = globaladdr.__prog_LIMIT\n");
    io::outbuf_write(&want, "    %1 = load.i32 %0\n");
    io::outbuf_write(&want, "    ret %1\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b2:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -3; }
    return 0;
}

// E2E: a struct-through-pointer store lowers to alloca-free FieldAddr/Store through the driver.
fn i32 e2e_lower_struct(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    module::Module* m = mk_source_module(a, "prog", "struct P { i32 x; } fn void f(P* p) { p.x = 8; }");
    compiler::add_module(c, m);
    if(!testing::expect_eq(compiler::run_frontend(c), 0, msg)) { return -1; }
    if(!testing::expect_ne((void*)m.sapir, null, msg)) { return -2; }

    u8[] got = sapir_print::print_module_to_arena((sapir::SapirModule*)m.sapir, a);
    io::OutBuf want;
    io::outbuf_init(&want, a, 512);
    io::outbuf_write(&want, "module prog\n\n");
    io::outbuf_write(&want, "fn __prog_f(prog::P*) -> void {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = param.prog::P* 0\n");
    io::outbuf_write(&want, "    %1 = fieldaddr %0, 0\n");
    io::outbuf_write(&want, "    %2 = const.i32 8\n");
    io::outbuf_write(&want, "    store %1, %2\n");
    io::outbuf_write(&want, "    ret\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -3; }
    return 0;
}

fn i32 argv_sapir_dump(arena::Arena* a, u8[] msg) {
    boot(a);
    compiler::Compiler* c = compiler::new(a);
    u8[][] args = mk_args(a, 2);
    args[0] = "main.sl";
    args[1] = "-sapir-dump";
    if(!testing::expect_true(compiler::parse_argv(c, args), msg)) { return -1; }
    if(!testing::expect_true(c.sapir_dump, msg)) { return -2; }
    return 0;
}

fn i32 main() {
    testing::init();

    u8[] fe = "Compiler Frontend Tests";
    testing::add(fe, "single_module_ok",       &single_module_ok);
    testing::add(fe, "generic_template_frontend", &generic_template_frontend);
    testing::add(fe, "generic_call_frontend",    &generic_call_frontend);
    testing::add(fe, "cross_module_generic_call", &cross_module_generic_call);
    testing::add(fe, "cross_module_generic_type_identity", &cross_module_generic_type_identity);
    testing::add(fe, "cross_module_generic_uses_home_type", &cross_module_generic_uses_home_type);
    testing::add(fe, "cross_module_comptime_call_ok",  &cross_module_comptime_call_ok);
    testing::add(fe, "cross_module_comptime_call_err", &cross_module_comptime_call_err);
    testing::add(fe, "cross_module_const_read_ok",  &cross_module_const_read_ok);
    testing::add(fe, "cross_module_const_read_err", &cross_module_const_read_err);
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
    testing::add(dv, "discover_sets_path_and_line_col", &discover_sets_path_and_line_col);
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
    testing::add(av, "argv_compile_only",       &argv_compile_only);
    testing::add(av, "argv_dump_flags",         &argv_dump_flags);
    testing::add(av, "argv_link_config",        &argv_link_config);
    testing::add(av, "link_config_override",    &link_config_override);
    testing::add(av, "argv_comptime_limits",    &argv_comptime_limits);
    testing::add(av, "argv_lib_dirs_and_libs",  &argv_lib_dirs_and_libs);
    testing::add(av, "argv_dangling_L_fails",   &argv_dangling_L_fails);
    testing::add(av, "argv_unknown_fails",      &argv_unknown_fails);
    testing::add(av, "argv_dangling_flag_fails", &argv_dangling_flag_fails);
    testing::add(av, "argv_sapir_dump",         &argv_sapir_dump);

    u8[] e2e = "Compiler E2E Lower Tests";
    testing::add(e2e, "e2e_lower_single_fn",         &e2e_lower_single_fn);
    testing::add(e2e, "e2e_lower_multi_module",      &e2e_lower_multi_module);
    testing::add(e2e, "e2e_lower_cross_module_call", &e2e_lower_cross_module_call);
    testing::add(e2e, "e2e_compile_link_run",        &e2e_compile_link_run);
    testing::add(e2e, "e2e_lib_dir_flag",            &e2e_lib_dir_flag);
    testing::add(e2e, "e2e_release_build",           &e2e_release_build);
    testing::add(e2e, "e2e_asan_build",              &e2e_asan_build);
    testing::add(e2e, "e2e_link_multi_module",       &e2e_link_multi_module);
    testing::add(e2e, "e2e_link_failure_reported",   &e2e_link_failure_reported);
    testing::add(e2e, "e2e_generic_template_skipped", &e2e_generic_template_skipped);
    testing::add(e2e, "e2e_lower_control_flow",      &e2e_lower_control_flow);
    testing::add(e2e, "e2e_lower_loop",              &e2e_lower_loop);
    testing::add(e2e, "e2e_lower_global_ref",       &e2e_lower_global_ref);
    testing::add(e2e, "e2e_lower_struct",            &e2e_lower_struct);

    return testing::run();
}
