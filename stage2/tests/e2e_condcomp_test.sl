import testing;
import test_util;
import module;
import list;
import arena;

// Every positive case puts an undefined name in the untaken branch: if it survived, error_count would catch it.

fn module::Module* with_defines(arena::Arena* a, u8[] src, module::Define[] defines) {
    module::BuildInfo build = test_util::host_build();
    build.defines = defines;
    return test_util::frontend_build(a, src, build);
}

fn i32 ok_top_level_fn(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun if (build::os == \"linux\") { fn i32 impl() { return 7; } }\nelse { fn i32 impl() { return missing_api(); } }\ncomprun { if(impl() != 7) { comperror(\"wrong branch\"); } }\nexport fn i32 f() { return impl(); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_else_taken(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun if (build::os == \"windows\") { fn i32 impl() { return missing_api(); } }\nelse { fn i32 impl() { return 3; } }\ncomprun { if(impl() != 3) { comperror(\"wrong branch\"); } }\nexport fn i32 f() { return impl(); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_no_else_condition_false(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun if (build::os == \"windows\") { fn i32 impl() { return missing_api(); } }\nexport fn i32 f() { return 1; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_else_if_chain(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun if (build::config == \"Release\") { const i32 K = 1; }\nelse if (build::config == \"Debug\") { const i32 K = 2; }\nelse { const i32 K = missing_api(); }\ncomprun { if(K != 2) { comperror(\"wrong arm\"); } }\nexport fn i32 f() { return K; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_arch_and_not_equal(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun if (build::arch == \"x86_64\" && build::os != \"windows\") { const i32 K = 4; }\nelse { const i32 K = missing_api(); }\ncomprun { if(K != 4) { comperror(\"bad\"); } }\nexport fn i32 f() { return K; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_or_and_negation(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun if (!build::defined(\"tracing\") && (build::os == \"plan9\" || build::arch == \"x86_64\")) { const i32 K = 5; }\nelse { const i32 K = missing_api(); }\ncomprun { if(K != 5) { comperror(\"bad\"); } }\nexport fn i32 f() { return K; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_defined_flag(arena::Arena* a, u8[] m) {
    list::List(module::Define) defines;
    defines.ptr = null; defines.len = 0; defines.cap = 0;
    module::Define tracing;
    tracing.name = "tracing";
    tracing.value = {null, 0};
    list::push(&defines, a, tracing);
    module::Module* mod = with_defines(a, "comprun if (build::defined(\"tracing\")) { const i32 K = 8; }\nelse { const i32 K = missing_api(); }\ncomprun { if(K != 8) { comperror(\"bad\"); } }\nexport fn i32 f() { return K; }", {defines.ptr, defines.len});
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_define_value(arena::Arena* a, u8[] m) {
    list::List(module::Define) defines;
    defines.ptr = null; defines.len = 0; defines.cap = 0;
    module::Define level;
    level.name = "level";
    level.value = "high";
    list::push(&defines, a, level);
    module::Module* mod = with_defines(a, "comprun if (build::define(\"level\") == \"high\") { const i32 K = 9; }\nelse { const i32 K = missing_api(); }\ncomprun { if(K != 9) { comperror(\"bad\"); } }\nexport fn i32 f() { return K; }", {defines.ptr, defines.len});
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

// A bare -Dname and an undefined name both read as the empty value.
fn i32 ok_define_value_absent(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun if (build::define(\"level\") == \"\") { const i32 K = 6; }\nelse { const i32 K = missing_api(); }\ncomprun { if(K != 6) { comperror(\"bad\"); } }\nexport fn i32 f() { return K; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_nested_top_level(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun if (build::os == \"linux\") {\n  comprun if (build::config == \"Debug\") { const i32 K = 11; }\n  else { const i32 K = missing_api(); }\n}\nelse { const i32 K = missing_api(); }\ncomprun { if(K != 11) { comperror(\"bad\"); } }\nexport fn i32 f() { return K; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_struct_alias_and_global(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun if (build::os == \"linux\") {\n  struct Handle { i32 fd; }\n  alias Native = Handle;\n  const i32 INVALID = -1;\n}\nelse {\n  struct Handle { Missing h; }\n  alias Native = Missing;\n  const i32 INVALID = missing_api();\n}\nexport fn i32 f() { Native h = {2}; if(h.fd == INVALID) { return 0; } return h.fd; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_generic_fn_in_branch(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun if (build::os == \"linux\") { fn T pick(comptime Type T, T x, T y) { return x; } }\nelse { fn T pick(comptime Type T, T x, T y) { return missing_api(); } }\nexport fn i32 f() { return pick(1, 2) + (i32)pick((i64)3, (i64)4); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_extern_block_in_branch(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun if (build::os == \"linux\") { extern \"c\" { fn i32 close(i32 fd); } }\nelse { extern \"c\" { fn Missing CloseHandle(Missing h); } }\nexport fn i32 f() { return close(1); }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_stmt_level(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() {\n  i32 total = 1;\n  comprun if (build::os == \"linux\") { total = total + 2; }\n  else { total = missing_api(); }\n  return total;\n}");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

// A branch is spliced into the enclosing block, so the names it declares stay visible after it.
fn i32 ok_stmt_decl_escapes_branch(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() {\n  comprun if (build::os == \"linux\") { i32 fd = 3; }\n  else { i32 fd = missing_api(); }\n  return fd;\n}");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_stmt_in_loop_with_defer(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "fn void release(i32 h) { }\nexport fn i32 f() {\n  i32 total = 0;\n  for(i32 i = 0; i < 3; i += 1) {\n    defer release(i);\n    comprun if (build::config == \"Debug\") { total = total + i; }\n    else { total = missing_api(); }\n  }\n  return total;\n}");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_stmt_in_switch_case(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f(i32 v) {\n  switch(v) {\n  case 1: {\n    comprun if (build::os == \"linux\") { return 10; }\n    else { return missing_api(); }\n  }\n  else { return 0; }\n  }\n}");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_branch_wraps_struct_literal_and_slice(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "struct P { i32 x; i32 y; }\nexport fn i32 f() {\n  i32[4] xs = [1, 2, 3, 4];\n  comprun if (build::arch == \"x86_64\") {\n    P p = {5, 6};\n    i32[] tail = xs[1..3];\n    return p.x + (i32)tail.len;\n  }\n  else { return missing_api(); }\n}");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 err_unknown_build_field(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() {\n  comprun if (build::platform == \"linux\") { return 1; }\n  return 0;\n}");
    if(!testing::expect_ge(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "comprun if condition must use build::os, build::arch, build::config, build::define(\"name\"), or build::defined(\"name\")", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)41, m)) { return -3; }
    return 0;
}

fn i32 err_non_build_condition(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "const i32 K = 1;\nexport fn i32 f() {\n  comprun if (K == 1) { return 1; }\n  return 0;\n}");
    if(!testing::expect_ge(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "comprun if condition must use build::os, build::arch, build::config, build::define(\"name\"), or build::defined(\"name\")", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)51, m)) { return -3; }
    return 0;
}

fn i32 err_non_string_operand(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() {\n  comprun if (build::os == 3) { return 1; }\n  return 0;\n}");
    if(!testing::expect_ge(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "comprun if condition must use build::os, build::arch, build::config, build::define(\"name\"), or build::defined(\"name\")", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)47, m)) { return -3; }
    return 0;
}

fn i32 err_defined_without_string(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() {\n  comprun if (build::defined(tracing)) { return 1; }\n  return 0;\n}");
    if(!testing::expect_ge(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "comprun if condition must use build::os, build::arch, build::config, build::define(\"name\"), or build::defined(\"name\")", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)49, m)) { return -3; }
    return 0;
}

// A compinsert fragment is parsed as its own module, so it has to inherit the build info.
fn i32 ok_compinsert_emits_comp_if(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun { compinsert(\"comprun if (build::os == \\\"linux\\\") { const i32 K = 12; } else { const i32 K = missing_api(); }\"); }\nexport fn i32 f() { return K; }");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 ok_compinsert_stmt_emits_comp_if(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() {\n  i32 total = 1;\n  compinsert(\"comprun if (build::config == \\\"Debug\\\") { total = total + 5; } else { total = missing_api(); }\");\n  return total;\n}");
    if(!testing::expect_eq(test_util::error_count(mod), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 err_build_in_comprun_block(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() {\n  comprun { if (build::os == \"linux\") { comperror(\"x\"); } }\n  return 0;\n}");
    if(!testing::expect_ge(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "`build::` is only available in a `comprun if` condition", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)36, m)) { return -3; }
    return 0;
}

fn i32 err_build_in_runtime_expr(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() { return (i32)build::os.len; }");
    if(!testing::expect_ge(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "`build::` is only available in a `comprun if` condition", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)32, m)) { return -3; }
    return 0;
}

// A branch that failed to open is not a block, so it must not be spliced.
fn i32 err_braceless_branch_stmt(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export fn i32 f() {\n  comprun if (build::os == \"linux\") return 1;\n  return 0;\n}");
    if(!testing::expect_ge(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "expected '{', got 'return'", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)56, m)) { return -3; }
    return 0;
}

fn i32 err_braceless_branch_top_level(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "comprun if (build::os == \"linux\") const i32 K = 1;\nexport fn i32 f() { return 0; }");
    if(!testing::expect_ge(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "expected '{', got 'const'", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)34, m)) { return -3; }
    return 0;
}

fn i32 err_exported_comp_if(arena::Arena* a, u8[] m) {
    module::Module* mod = test_util::frontend(a, "export comprun if (build::os == \"linux\") { const i32 K = 1; }");
    if(!testing::expect_ge(test_util::error_count(mod), (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mod.diag.entries[0].msg, "`export` is not valid on `comprun` (it does not declare a named symbol)", m)) { return -2; }
    if(!testing::expect_eq(mod.diag.entries[0].src_pos, (u32)7, m)) { return -3; }
    return 0;
}

fn i32 main() {
    testing::init();
    u8[] suite = "E2E Conditional Compilation Tests";
    testing::add(suite, "ok_top_level_fn",                     &ok_top_level_fn);
    testing::add(suite, "ok_else_taken",                       &ok_else_taken);
    testing::add(suite, "ok_no_else_condition_false",          &ok_no_else_condition_false);
    testing::add(suite, "ok_else_if_chain",                    &ok_else_if_chain);
    testing::add(suite, "ok_arch_and_not_equal",               &ok_arch_and_not_equal);
    testing::add(suite, "ok_or_and_negation",                  &ok_or_and_negation);
    testing::add(suite, "ok_defined_flag",                     &ok_defined_flag);
    testing::add(suite, "ok_define_value",                     &ok_define_value);
    testing::add(suite, "ok_define_value_absent",              &ok_define_value_absent);
    testing::add(suite, "ok_nested_top_level",                 &ok_nested_top_level);
    testing::add(suite, "ok_struct_alias_and_global",          &ok_struct_alias_and_global);
    testing::add(suite, "ok_generic_fn_in_branch",             &ok_generic_fn_in_branch);
    testing::add(suite, "ok_extern_block_in_branch",           &ok_extern_block_in_branch);
    testing::add(suite, "ok_stmt_level",                       &ok_stmt_level);
    testing::add(suite, "ok_stmt_decl_escapes_branch",         &ok_stmt_decl_escapes_branch);
    testing::add(suite, "ok_stmt_in_loop_with_defer",          &ok_stmt_in_loop_with_defer);
    testing::add(suite, "ok_stmt_in_switch_case",              &ok_stmt_in_switch_case);
    testing::add(suite, "ok_branch_wraps_struct_literal_and_slice", &ok_branch_wraps_struct_literal_and_slice);
    testing::add(suite, "err_unknown_build_field",             &err_unknown_build_field);
    testing::add(suite, "err_non_build_condition",             &err_non_build_condition);
    testing::add(suite, "err_non_string_operand",              &err_non_string_operand);
    testing::add(suite, "err_defined_without_string",          &err_defined_without_string);
    testing::add(suite, "ok_compinsert_emits_comp_if",         &ok_compinsert_emits_comp_if);
    testing::add(suite, "ok_compinsert_stmt_emits_comp_if",    &ok_compinsert_stmt_emits_comp_if);
    testing::add(suite, "err_build_in_comprun_block",          &err_build_in_comprun_block);
    testing::add(suite, "err_build_in_runtime_expr",           &err_build_in_runtime_expr);
    testing::add(suite, "err_braceless_branch_stmt",           &err_braceless_branch_stmt);
    testing::add(suite, "err_braceless_branch_top_level",      &err_braceless_branch_top_level);
    testing::add(suite, "err_exported_comp_if",                &err_exported_comp_if);
    return testing::run();
}
