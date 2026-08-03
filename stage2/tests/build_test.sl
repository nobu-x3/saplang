import testing;
import test_util;
import builder;
import arena;
import mem;
import list;
import sys;

test_util::Counting g_counting;

// Build owns no arena — only an Allocator — so the whole step graph can be built on a caller's allocator.
fn i32 graph_allocates_through_caller_allocator(arena::Arena* a, const u8[]m) {
    sys::memset(&g_counting, 0, sizeof(test_util::Counting));
    g_counting.inner = arena::allocator(a);

    builder::Build* b = builder::new_build(a);
    b.allocator = test_util::counting_allocator(&g_counting);
    b.install_step = builder::step(b, "install", "install");
    u64 before = g_counting.allocs;

    builder::CompileStep* exe = builder::add_executable(b, "app", "main.sl");
    builder::add_import_path(exe, "std");
    builder::install_artifact(b, exe);

    if(!testing::expect_true(g_counting.allocs > before, m)) { return -1; }
    if(!testing::expect_eq(builder::artifact_path(b, exe), "sap-out/bin/app", m)) { return -2; }
    return 0;
}

// Graph shape: install_artifact hangs the compile step off install; a run step depends on the
// same compile step; a named top step depends on the run step. First-field aliasing means
// &exe.step is the CompileStep address.
fn i32 graph_structure(arena::Arena* a, const u8[]m) {
    builder::Build* b = builder::new_build(a);
    b.compiler_path = "saplangc";
    b.install_step = builder::step(b, "install", "install");

    builder::CompileStep* exe = builder::add_executable(b, "app", "src/main.sl");
    builder::add_import_path(exe, "std");
    builder::link_lib(exe, "m");
    builder::install_artifact(b, exe);

    if(!testing::expect_true(exe.installed, m)) { return -1; }
    if(!testing::expect_eq(b.install_step.deps.len, (u64)1, m)) { return -2; }
    if(!testing::expect_eq((void*)b.install_step.deps.ptr[0], (void*)&exe.step, m)) { return -3; }

    builder::RunStep* r = builder::add_run_artifact(b, exe);
    if(!testing::expect_eq(r.step.deps.len, (u64)1, m)) { return -4; }
    if(!testing::expect_eq((void*)r.step.deps.ptr[0], (void*)&exe.step, m)) { return -5; }

    builder::Step* run_step = builder::step(b, "run", "run it");
    builder::depend_on(run_step, &r.step);
    if(!testing::expect_eq(run_step.deps.len, (u64)1, m)) { return -6; }

    if(!testing::expect_not_null((void*)builder::resolve_step(b, "run"), m)) { return -7; }
    if(!testing::expect_null((void*)builder::resolve_step(b, "nope"), m)) { return -8; }
    return 0;
}

// Installed artifacts resolve under sap-out/bin/; run-only ones under .sap-cache/.
fn i32 artifact_paths(arena::Arena* a, const u8[]m) {
    builder::Build* b = builder::new_build(a);
    b.install_step = builder::step(b, "install", "x");

    builder::CompileStep* inst = builder::add_executable(b, "app", "main.sl");
    builder::install_artifact(b, inst);
    if(!testing::expect_eq(builder::artifact_path(b, inst), "sap-out/bin/app", m)) { return -1; }

    builder::CompileStep* tmp = builder::add_executable(b, "tool", "tool.sl");
    if(!testing::expect_eq(builder::artifact_path(b, tmp), ".sap-cache/tool", m)) { return -2; }
    return 0;
}

// The assembled saplangc invocation, exercised with every flag class at once.
fn i32 command_string(arena::Arena* a, const u8[]m) {
    builder::Build* b = builder::new_build(a);
    b.compiler_path = "saplangc";
    b.install_step = builder::step(b, "install", "x");

    builder::CompileStep* exe = builder::add_executable(b, "app", "main.sl");
    builder::add_import_path(exe, "std");
    builder::add_import_path(exe, "vendor");
    builder::link_lib(exe, "LLVM-19");
    builder::link_lib_dir(exe, "/opt/lib");
    builder::Target t;
    t.name = "linux";
    builder::set_target(exe, t);
    builder::set_optimize(exe, builder::Optimize::Release);
    builder::install_artifact(b, exe);

    u8[] cmd = builder::compile_command_string(b, exe);
    const u8[] want = "saplangc main.sl -o sap-out/bin/app -i std;vendor -l LLVM-19 -L /opt/lib -target linux -config Release";
    if(!testing::expect_eq(cmd, want, m)) { return -1; }
    return 0;
}

// A run-only artifact with no imports/libs and a default (Debug) optimize.
fn i32 command_string_minimal(arena::Arena* a, const u8[]m) {
    builder::Build* b = builder::new_build(a);
    b.compiler_path = "saplangc";

    builder::CompileStep* exe = builder::add_executable(b, "t", "t.sl");
    u8[] cmd = builder::compile_command_string(b, exe);
    const u8[] want = "saplangc t.sl -o .sap-cache/t -config Debug";
    if(!testing::expect_eq(cmd, want, m)) { return -1; }
    return 0;
}

// -D overrides resolve through the standard/option accessors; bare -Dflag reads as true.
fn i32 options(arena::Arena* a, const u8[]m) {
    builder::Build* b = builder::new_build(a);
    builder::define(b, "optimize", "Release", true);
    builder::define(b, "verbose", "", false);
    builder::define(b, "name", "sap", true);

    builder::Optimize opt = builder::standard_optimize_options(b);
    if(!testing::expect_eq((i32)opt, (i32)builder::Optimize::Release, m)) { return -1; }
    if(!testing::expect_true(builder::option_bool(b, "verbose", "d"), m)) { return -2; }
    if(!testing::expect_true(!builder::option_bool(b, "missing", "d"), m)) { return -3; }
    if(!testing::expect_eq(builder::option_string(b, "name", "d"), "sap", m)) { return -4; }

    builder::Target tg = builder::standard_target_options(b);
    if(!testing::expect_eq(tg.name.len, (u64)0, m)) { return -5; }
    return 0;
}

// An explicit -Dtarget flows into standard_target_options and out into the command.
fn i32 target_option(arena::Arena* a, const u8[]m) {
    builder::Build* b = builder::new_build(a);
    b.compiler_path = "saplangc";
    builder::define(b, "target", "windows", true);
    builder::Target tg = builder::standard_target_options(b);

    builder::CompileStep* exe = builder::add_executable(b, "app", "main.sl");
    builder::set_target(exe, tg);
    u8[] cmd = builder::compile_command_string(b, exe);
    const u8[] want = "saplangc main.sl -o .sap-cache/app -target windows -config Debug";
    if(!testing::expect_eq(cmd, want, m)) { return -1; }
    return 0;
}

// Options other than optimize/target reach the source as compiler defines; the command string also keys the rebuild stamp.
fn i32 defines_forwarded(arena::Arena* a, const u8[]m) {
    builder::Build* b = builder::new_build(a);
    b.compiler_path = "saplangc";
    builder::define(b, "optimize", "Release", true);
    builder::define(b, "tracing", "", false);
    builder::define(b, "level", "high", true);
    builder::standard_optimize_options(b);

    builder::CompileStep* exe = builder::add_executable(b, "app", "main.sl");
    u8[] cmd = builder::compile_command_string(b, exe);
    const u8[] want = "saplangc main.sl -o .sap-cache/app -config Release -Dtracing -Dlevel=high";
    if(!testing::expect_eq(cmd, want, m)) { return -1; }
    return 0;
}

// A -flag that is not -D and not build-owned rides along to every compile, after the defines.
fn i32 compiler_flags_forwarded(arena::Arena* a, const u8[]m) {
    builder::Build* b = builder::new_build(a);
    b.compiler_path = "saplangc";
    builder::define(b, "tracing", "", false);
    list::push(&b.compiler_flags, b.allocator, "-show-timings");
    list::push(&b.compiler_flags, b.allocator, "-mt");

    builder::CompileStep* exe = builder::add_executable(b, "app", "main.sl");
    u8[] cmd = builder::compile_command_string(b, exe);
    const u8[] want = "saplangc main.sl -o .sap-cache/app -config Debug -Dtracing -show-timings -mt";
    if(!testing::expect_eq(cmd, want, m)) { return -1; }
    return 0;
}

// The parallel scheduler gathers every reachable compile once; a step shared by install and run
// is not double-counted.
fn i32 gather_compiles(arena::Arena* a, const u8[]m) {
    builder::Build* b = builder::new_build(a);
    b.install_step = builder::step(b, "install", "x");

    builder::CompileStep* e1 = builder::add_executable(b, "a", "a.sl");
    builder::CompileStep* e2 = builder::add_executable(b, "b", "b.sl");
    builder::install_artifact(b, e1);
    builder::install_artifact(b, e2);

    builder::RunStep* r = builder::add_run_artifact(b, e1);
    builder::Step* run_step = builder::step(b, "run", "run");
    builder::depend_on(run_step, &r.step);

    list::List(builder::CompileStep*) compiles;
    compiles.ptr = null; compiles.len = 0; compiles.cap = 0;
    builder::collect_compiles(b.install_step, &compiles, arena::allocator(a));
    builder::collect_compiles(run_step, &compiles, arena::allocator(a));

    if(!testing::expect_eq(compiles.len, (u64)2, m)) { return -1; }
    return 0;
}

fn i32 main() {
    testing::init();
    const u8[] suite = "Build System Tests";
    testing::add(suite, "graph_allocates_through_caller_allocator", &graph_allocates_through_caller_allocator);
    testing::add(suite, "graph_structure", &graph_structure);
    testing::add(suite, "artifact_paths", &artifact_paths);
    testing::add(suite, "command_string", &command_string);
    testing::add(suite, "command_string_minimal", &command_string_minimal);
    testing::add(suite, "options", &options);
    testing::add(suite, "target_option", &target_option);
    testing::add(suite, "defines_forwarded", &defines_forwarded);
    testing::add(suite, "compiler_flags_forwarded", &compiler_flags_forwarded);
    testing::add(suite, "gather_compiles", &gather_compiles);
    return testing::run();
}
