#pragma once

#include "platform.h"
#include "util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unity.h>
#include <driver.h>

#if !defined(_WIN32)
#include <sys/wait.h>
#endif

#define MODULE_TEST_SETUP(path) \


// Platform executable name for a base (adds .exe on Windows).
static const char *exe_name(const char *base, char *buf, size_t n) {
#if defined(_WIN32)
    snprintf(buf, n, "%s.exe", base);
#else
    snprintf(buf, n, "%s", base);
#endif
    return buf;
}

// Run a program built into the cwd by base name. cmd.exe won't find a bare
// name in the current directory, so a `.\` prefix is required on Windows.
static int run_built(const char *base) {
    char cmd[200] = "";
#if defined(_WIN32)
    snprintf(cmd, sizeof(cmd), ".\\%s.exe", base);
#else
    snprintf(cmd, sizeof(cmd), "./%s", base);
#endif
    return system(cmd);
}

// Decode the exit code from a system() return value. On POSIX, `system`
// returns wait-style encoded status — exit code is in the high byte.
static int decode_exit(int status) {
#if defined(_WIN32)
    return status;
#else
    if (WIFEXITED(status))
        return WEXITSTATUS(status);
    return -1;
#endif
}

// Compile a fixture with an explicit target, run it, return its exit code.
static int build_and_get_exit_with_target(const char *path, const char *base, const char *target) {
    CompileOptions opts = {0};
    char input_file_path[256] = "";
    sprintf(input_file_path, "%s/main.sl", path);
    opts.input_file_path = strdup(input_file_path);
    opts.no_cleanup = 0;
    opts.threads = 1;
    opts.target = strdup(target);
    char out_name[160] = "";
    opts.output_file_path = strdup(exe_name(base, out_name, sizeof(out_name)));
    driver_set_compiler_options(opts);
    TEST_ASSERT_EQUAL_INT(driver_run(), RESULT_SUCCESS);
    return decode_exit(run_built(base));
}

// Compile a debug-info fixture (gen_debug, no cleanup) and run it.
static void build_and_run_debug(const char *path, const char *base) {
    CompileOptions opts = {0};
    char input_file_path[256] = "";
    sprintf(input_file_path, "%s/main.sl", path);
    opts.input_file_path = strdup(input_file_path);
    opts.no_cleanup = 1;
    opts.gen_debug = 1;
    opts.threads = 1;
    char ob[160] = "";
    opts.output_file_path = strdup(exe_name(base, ob, sizeof(ob)));
    driver_set_compiler_options(opts);
    TEST_ASSERT_EQUAL_INT(driver_run(), RESULT_SUCCESS);
    TEST_ASSERT_EQUAL_INT(run_built(base), 0);
}

void test(const char* path, char* output_path) {
    CompileOptions opts = {0};
    char input_file_path[256] = "";
    sprintf(input_file_path, "%s/main.sl", path);
    opts.input_file_path = strdup(input_file_path);
    opts.no_cleanup = 0;
    opts.threads = 1;
    char out_name[160] = "";
    opts.output_file_path = strdup(exe_name(output_path, out_name, sizeof(out_name)));
    driver_set_compiler_options(opts);
    TEST_ASSERT_EQUAL_INT(driver_run(), RESULT_SUCCESS);
    TEST_ASSERT_EQUAL_INT(run_built(output_path), 0);
}

// Run the driver on a module fixture that we expect to fail compilation
// at the dependency-graph stage. The cycle-detection diagnostic goes to
// stderr; redirect it to /dev/null for the duration of the test so it
// doesn't pollute the unity output.
static void test_expect_driver_failure(const char *path, char *output_path) {
    CompileOptions opts = {0};
    char input_file_path[256] = "";
    sprintf(input_file_path, "%s/main.sl", path);
    opts.input_file_path = strdup(input_file_path);
    opts.no_cleanup = 0;
    opts.threads = 1;
    opts.output_file_path = strdup(output_path);
    driver_set_compiler_options(opts);

    int saved_stderr = SL_DUP(SL_FILENO(stderr));
    FILE *devnull = freopen(SL_DEVNULL, "w", stderr);
    (void)devnull;

    CompilerResult res = driver_run();

    fflush(stderr);
    SL_DUP2(saved_stderr, SL_FILENO(stderr));
    SL_CLOSE(saved_stderr);

    TEST_ASSERT_EQUAL_INT(RESULT_FAILURE, res);
}

void test_ImportTest_modules(void) {
    test("module_tests/import_test", "import_test");
}

// `-target=linux` picks threads.linux.sl over threads.sl.
void test_TargetSelect_Linux_modules(void) {
    int code = build_and_get_exit_with_target("module_tests/target_select", "target_select_linux", "linux");
    TEST_ASSERT_EQUAL_INT(22, code);
}

// `-target=windows` picks threads.windows.sl.
void test_TargetSelect_Windows_modules(void) {
    int code = build_and_get_exit_with_target("module_tests/target_select", "target_select_windows", "windows");
    TEST_ASSERT_EQUAL_INT(33, code);
}

// `-target=macos` has no matching .macos.sl variant; falls back to threads.sl.
void test_TargetSelect_FallbackToCommon_modules(void) {
    int code = build_and_get_exit_with_target("module_tests/target_select", "target_select_fallback", "macos");
    TEST_ASSERT_EQUAL_INT(11, code);
}

// E2E `null` literal: init, eq/ne, truthy/falsy, reassign, fn return, field init.
void test_NullTest_modules(void) {
    test("module_tests/null_test", "null_test");
}

// Mutual import — driver must refuse to build, not spin.
void test_ImportCycle_modules(void) {
    test_expect_driver_failure("module_tests/cycle_test", "cycle_test");
}

void test_MissingExport_modules(void) {
    test_expect_driver_failure("module_tests/missing_export", "missing_export");
}

void test_ParserErrorTypeKeywordVar_modules(void) {
    test_expect_driver_failure("module_tests/parser_error_type_keyword_var", "parser_error_type_keyword_var");
}

void test_ParserErrorInFnBody_modules(void) {
    test_expect_driver_failure("module_tests/parser_error_in_fn_body", "parser_error_in_fn_body");
}

void test_SwitchTest_modules(void) {
    test("module_tests/switch_test", "switch_test");
}

// E2E slices: decl, decay, .len, index r/w, slice literals, sub-slice, null→zero.
void test_SliceTest_modules(void) {
    test("module_tests/slice_test", "slice_test");
}

void test_SliceLenChain_modules(void) {
    test("module_tests/slice_len_chain", "slice_len_chain");
}

void test_CrossModuleStructField_modules(void) {
    test("module_tests/cross_module_struct_field", "cross_module_struct_field");
}

void test_CrossModuleGlobalVar_modules(void) {
    test("module_tests/cross_module_global_var", "cross_module_global_var");
}

void test_CrossModuleConstGlobal_modules(void) {
    test("module_tests/cross_module_const_global", "cross_module_const_global");
}

void test_CrossModuleConstSlice_modules(void) {
    test("module_tests/cross_module_const_slice", "cross_module_const_slice");
}

void test_CrossModuleUnionField_modules(void) {
    test("module_tests/cross_module_union_field", "cross_module_union_field");
}

void test_CrossModuleEnumValue_modules(void) {
    test("module_tests/cross_module_enum_value", "cross_module_enum_value");
}

void test_CrossModuleTransitiveType_modules(void) {
    test("module_tests/cross_module_transitive_type", "cross_module_transitive_type");
}

void test_EnumCastAndChars_modules(void) {
    test("module_tests/enum_cast_and_chars", "enum_cast_and_chars");
}

void test_StructSliceTable_modules(void) {
    test("module_tests/struct_slice_table", "struct_slice_table");
}

static void test_DebugInfoBasic_modules(void) {
    build_and_run_debug("module_tests/debug_info_basic", "debug_info_basic");

    FILE *dump = SL_POPEN("llvm-dwarfdump --debug-info .tmp/tmp-main.o", "r");
    TEST_ASSERT_NOT_NULL(dump);
    char buf[8192] = {0};
    size_t n = fread(buf, 1, sizeof(buf) - 1, dump);
    SL_PCLOSE(dump);
    TEST_ASSERT_GREATER_THAN(0, n);
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_TAG_compile_unit"), "expected DW_TAG_compile_unit in dwarfdump output");
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_TAG_subprogram"), "expected DW_TAG_subprogram in dwarfdump output");
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_AT_linkage_name\t(\"main\")"), "expected main subprogram with linkage_name in dwarfdump output");

    int rc = system("llvm-dwarfdump --verify .tmp/tmp-main.o > " SL_DEVNULL " 2>&1");
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, rc, "llvm-dwarfdump --verify reported errors on the emitted object");
}

static void test_DebugInfoTypes_modules(void) {
    build_and_run_debug("module_tests/debug_info_types", "debug_info_types");

    FILE *dump = SL_POPEN("llvm-dwarfdump --debug-info .tmp/tmp-main.o", "r");
    TEST_ASSERT_NOT_NULL(dump);
    char buf[32768] = {0};
    size_t n = fread(buf, 1, sizeof(buf) - 1, dump);
    SL_PCLOSE(dump);
    TEST_ASSERT_GREATER_THAN(0, n);
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_AT_linkage_name\t(\"main\")"), "expected main subprogram");
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "(\"__main_add__i32_i32\")"), "expected add subprogram with mangled signature");
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_TAG_base_type"), "expected DW_TAG_base_type for primitives");
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "(\"i32\")"), "expected i32 basic type");

    int rc = system("llvm-dwarfdump --verify .tmp/tmp-main.o > " SL_DEVNULL " 2>&1");
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, rc, "llvm-dwarfdump --verify reported errors on the Phase 2 fixture");
}

static void test_DebugInfoLines_modules(void) {
    build_and_run_debug("module_tests/debug_info_lines", "debug_info_lines");

    FILE *dump = SL_POPEN("llvm-dwarfdump --debug-line .tmp/tmp-main.o", "r");
    TEST_ASSERT_NOT_NULL(dump);
    char buf[16384] = {0};
    size_t n = fread(buf, 1, sizeof(buf) - 1, dump);
    SL_PCLOSE(dump);
    TEST_ASSERT_GREATER_THAN(0, n);
    // The line program prologue must reference main.sl, and several
    // statements (we want is_stmt markers on at least a handful of
    // distinct rows) should make it through.
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "main.sl"), "expected main.sl referenced in line table prologue");
    int is_stmt_rows = 0;
    for (char *p = buf; (p = strstr(p, "is_stmt")) != NULL; ++p, ++is_stmt_rows) {}
    // Includes the standard_opcode_lengths header row, so >= 4 means at
    // least 3 real line-program rows carry is_stmt.
    TEST_ASSERT_GREATER_THAN_MESSAGE(3, is_stmt_rows, "expected multiple is_stmt rows in line table");

    int rc = system("llvm-dwarfdump --verify .tmp/tmp-main.o > " SL_DEVNULL " 2>&1");
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, rc, "llvm-dwarfdump --verify reported errors on the Phase 3 fixture");
}
static void test_DebugInfoGlobals_modules(void) {
    build_and_run_debug("module_tests/debug_info_globals", "debug_info_globals");

    FILE *info = SL_POPEN("llvm-dwarfdump --debug-info .tmp/tmp-main.o", "r");
    TEST_ASSERT_NOT_NULL(info);
    char buf[32768] = {0};
    size_t n = fread(buf, 1, sizeof(buf) - 1, info);
    SL_PCLOSE(info);
    TEST_ASSERT_GREATER_THAN(0, n);

    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_TAG_variable"), "expected DW_TAG_variable entries for globals");
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_AT_name\t(\"g_count\")"), "expected primitive global g_count");
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_AT_name\t(\"g_outer\")"), "expected struct global g_outer");
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_AT_name\t(\"Outer\")"), "expected Outer struct DI");
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_AT_name\t(\"Inner\")"), "expected nested Inner struct DI");

    int rc = system("llvm-dwarfdump --verify .tmp/tmp-main.o > " SL_DEVNULL " 2>&1");
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, rc, "llvm-dwarfdump --verify reported errors on the globals fixture");
}

static void test_DebugInfoLocals_modules(void) {
    build_and_run_debug("module_tests/debug_info_locals", "debug_info_locals");

    FILE *info = SL_POPEN("llvm-dwarfdump --debug-info .tmp/tmp-main.o", "r");
    TEST_ASSERT_NOT_NULL(info);
    char buf[32768] = {0};
    size_t n = fread(buf, 1, sizeof(buf) - 1, info);
    SL_PCLOSE(info);
    TEST_ASSERT_GREATER_THAN(0, n);

    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_TAG_formal_parameter"), "expected DW_TAG_formal_parameter for params");
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_TAG_variable"), "expected DW_TAG_variable for locals");
    // Display names should be the source-level identifiers, not the mangled ones.
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_AT_name\t(\"a\")"), "expected param `a` by display name");
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_AT_name\t(\"prod\")"), "expected local `prod` by display name");
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_AT_name\t(\"p\")"), "expected local `p` of struct type by display name");
    // The Point struct should now surface because `p` anchors it.
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_TAG_structure_type"), "expected DW_TAG_structure_type for Point (anchored via local)");
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_AT_name\t(\"Point\")"), "expected Point struct named");

    int rc = system("llvm-dwarfdump --verify .tmp/tmp-main.o > " SL_DEVNULL " 2>&1");
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, rc, "llvm-dwarfdump --verify reported errors on the Phase 4 fixture");
}
