#pragma once

#include "util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <unity.h>
#include <driver.h>

#define MODULE_TEST_SETUP(path) \


void test(const char* path, char* output_path) {
    CompileOptions opts = {0};
    char input_file_path[256] = "";
    sprintf(input_file_path, "%s/main.sl", path);
    opts.input_file_path = input_file_path;
    opts.no_cleanup = 0;
    opts.threads = 1;
    opts.output_file_path = output_path;
    driver_set_compiler_options(opts);
    TEST_ASSERT_EQUAL_INT(driver_run(), RESULT_SUCCESS);
    char cmd [128] = "";
    sprintf(cmd, "./%s", output_path);
    TEST_ASSERT_EQUAL_INT(system(cmd), 0);
}

// Run the driver on a module fixture that we expect to fail compilation
// at the dependency-graph stage. The cycle-detection diagnostic goes to
// stderr; redirect it to /dev/null for the duration of the test so it
// doesn't pollute the unity output.
static void test_expect_driver_failure(const char *path, char *output_path) {
    CompileOptions opts = {0};
    char input_file_path[256] = "";
    sprintf(input_file_path, "%s/main.sl", path);
    opts.input_file_path = input_file_path;
    opts.no_cleanup = 0;
    opts.threads = 1;
    opts.output_file_path = output_path;
    driver_set_compiler_options(opts);

    int saved_stderr = dup(fileno(stderr));
    FILE *devnull = freopen("/dev/null", "w", stderr);
    (void)devnull;

    CompilerResult res = driver_run();

    fflush(stderr);
    dup2(saved_stderr, fileno(stderr));
    close(saved_stderr);

    TEST_ASSERT_EQUAL_INT(RESULT_FAILURE, res);
}

void test_ImportTest_modules(void) {
    test("module_tests/import_test", "import_test");
}

// End-to-end exercise of the `null` literal: typed-pointer init,
// equality / inequality, truthy / falsy branches, reassignment,
// returning from a pointer-returning fn, designated and positional
// struct-field init. The fixture's main() returns 0 only if every
// check holds, so a regression shows up as a non-zero exit code.
void test_NullTest_modules(void) {
    test("module_tests/null_test", "null_test");
}

// Mutual import: main imports a, a imports b, b imports a. Driver
// should refuse to build the dependency graph rather than spinning or
// silently short-circuiting.
void test_ImportCycle_modules(void) {
    test_expect_driver_failure("module_tests/cycle_test", "cycle_test");
}

void test_SwitchTest_modules(void) {
    test("module_tests/switch_test", "switch_test");
}

// End-to-end exercise of slices: T[] declarations, array→slice decay at
// var-init and call sites, .len on both arrays and slices, indexed read
// and write, slice literals (positional and designated), sub-slicing,
// and the zero slice from null. main() returns 0 only if every check
// holds.
void test_SliceTest_modules(void) {
    test("module_tests/slice_test", "slice_test");
}

static void test_DebugInfoBasic_modules(void) {
    CompileOptions opts = {0};
    char input_file_path[256] = "";
    sprintf(input_file_path, "%s/main.sl", "module_tests/debug_info_basic");
    opts.input_file_path = input_file_path;
    opts.no_cleanup = 1;
    opts.gen_debug = 1;
    opts.threads = 1;
    opts.output_file_path = "debug_info_basic";
    driver_set_compiler_options(opts);
    TEST_ASSERT_EQUAL_INT(driver_run(), RESULT_SUCCESS);
    TEST_ASSERT_EQUAL_INT(system("./debug_info_basic"), 0);

    FILE *dump = popen("llvm-dwarfdump --debug-info .tmp/tmp-main.o", "r");
    TEST_ASSERT_NOT_NULL(dump);
    char buf[8192] = {0};
    size_t n = fread(buf, 1, sizeof(buf) - 1, dump);
    pclose(dump);
    TEST_ASSERT_GREATER_THAN(0, n);
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_TAG_compile_unit"), "expected DW_TAG_compile_unit in dwarfdump output");
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_TAG_subprogram"), "expected DW_TAG_subprogram in dwarfdump output");
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_AT_linkage_name\t(\"main\")"), "expected main subprogram with linkage_name in dwarfdump output");

    int rc = system("llvm-dwarfdump --verify .tmp/tmp-main.o > /dev/null 2>&1");
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, rc, "llvm-dwarfdump --verify reported errors on the emitted object");
}

static void test_DebugInfoTypes_modules(void) {
    CompileOptions opts = {0};
    char input_file_path[256] = "";
    sprintf(input_file_path, "%s/main.sl", "module_tests/debug_info_types");
    opts.input_file_path = input_file_path;
    opts.no_cleanup = 1;
    opts.gen_debug = 1;
    opts.threads = 1;
    opts.output_file_path = "debug_info_types";
    driver_set_compiler_options(opts);
    TEST_ASSERT_EQUAL_INT(driver_run(), RESULT_SUCCESS);
    TEST_ASSERT_EQUAL_INT(system("./debug_info_types"), 0);

    FILE *dump = popen("llvm-dwarfdump --debug-info .tmp/tmp-main.o", "r");
    TEST_ASSERT_NOT_NULL(dump);
    char buf[32768] = {0};
    size_t n = fread(buf, 1, sizeof(buf) - 1, dump);
    pclose(dump);
    TEST_ASSERT_GREATER_THAN(0, n);
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_AT_linkage_name\t(\"main\")"), "expected main subprogram");
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "(\"__main_add__i32_i32\")"), "expected add subprogram with mangled signature");
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "DW_TAG_base_type"), "expected DW_TAG_base_type for primitives");
    TEST_ASSERT_NOT_NULL_MESSAGE(strstr(buf, "(\"i32\")"), "expected i32 basic type");

    int rc = system("llvm-dwarfdump --verify .tmp/tmp-main.o > /dev/null 2>&1");
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, rc, "llvm-dwarfdump --verify reported errors on the Phase 2 fixture");
}

static void test_DebugInfoLines_modules(void) {
    CompileOptions opts = {0};
    char input_file_path[256] = "";
    sprintf(input_file_path, "%s/main.sl", "module_tests/debug_info_lines");
    opts.input_file_path = input_file_path;
    opts.no_cleanup = 1;
    opts.gen_debug = 1;
    opts.threads = 1;
    opts.output_file_path = "debug_info_lines";
    driver_set_compiler_options(opts);
    TEST_ASSERT_EQUAL_INT(driver_run(), RESULT_SUCCESS);
    TEST_ASSERT_EQUAL_INT(system("./debug_info_lines"), 0);

    FILE *dump = popen("llvm-dwarfdump --debug-line .tmp/tmp-main.o", "r");
    TEST_ASSERT_NOT_NULL(dump);
    char buf[16384] = {0};
    size_t n = fread(buf, 1, sizeof(buf) - 1, dump);
    pclose(dump);
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

    int rc = system("llvm-dwarfdump --verify .tmp/tmp-main.o > /dev/null 2>&1");
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, rc, "llvm-dwarfdump --verify reported errors on the Phase 3 fixture");
}
static void test_DebugInfoLocals_modules(void) {
    CompileOptions opts = {0};
    char input_file_path[256] = "";
    sprintf(input_file_path, "%s/main.sl", "module_tests/debug_info_locals");
    opts.input_file_path = input_file_path;
    opts.no_cleanup = 1;
    opts.gen_debug = 1;
    opts.threads = 1;
    opts.output_file_path = "debug_info_locals";
    driver_set_compiler_options(opts);
    TEST_ASSERT_EQUAL_INT(driver_run(), RESULT_SUCCESS);
    TEST_ASSERT_EQUAL_INT(system("./debug_info_locals"), 0);

    FILE *info = popen("llvm-dwarfdump --debug-info .tmp/tmp-main.o", "r");
    TEST_ASSERT_NOT_NULL(info);
    char buf[32768] = {0};
    size_t n = fread(buf, 1, sizeof(buf) - 1, info);
    pclose(info);
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

    int rc = system("llvm-dwarfdump --verify .tmp/tmp-main.o > /dev/null 2>&1");
    TEST_ASSERT_EQUAL_INT_MESSAGE(0, rc, "llvm-dwarfdump --verify reported errors on the Phase 4 fixture");
}
