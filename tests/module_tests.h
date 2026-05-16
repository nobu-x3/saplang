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
    // Pin import resolution to the fixture dir; the default "." path
    // searches recursively by basename and would happily resolve a
    // sibling fixture's `main.sl` when multiple module tests share the
    // build/bin tree.
    (void)da_init(opts.import_paths, 1);
    (void)da_push(opts.import_paths, strdup(path));
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
