#pragma once

#include "util.h"
#include <stdlib.h>
#include <string.h>
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

void test_ImportTest_modules(void) {
    test("module_tests/import_test", "import_test");
}
