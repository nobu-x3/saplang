#pragma once
#include "test_util.h"
#include <codegen.h>
#include <parser.h>
#include <sema.h>
#include <types.h>
#include <unity.h>
#include <util.h>

#define CODEGEN_TEST_SETUP_SINGLE(input_string)                                                                                                                                                                                                \
	const char *input = input_string;                                                                                                                                                                                                          \
	const char *path = "parser_tests.sl";                                                                                                                                                                                                      \
	Scanner scanner;                                                                                                                                                                                                                           \
	scanner_init_from_string(&scanner, path, input);                                                                                                                                                                                           \
	Parser parser;                                                                                                                                                                                                                             \
	FILE *old_stdout = capture_error_begin();                                                                                                                                                                                                  \
	parser_init(&parser, scanner, NULL);                                                                                                                                                                                                       \
	Module *module = parse_input(&parser);                                                                                                                                                                                                     \
	for (ASTNode *node = module->ast; node != NULL; node = node->next) {                                                                                                                                                                       \
		analyze_ast(module->symbol_table, node, 0, "");                                                                                                                                                                                        \
	}                                                                                                                                                                                                                                          \
	CodegenInitContext cg_init_ctx = {"test", "test", ".", 0};                                                                                                                                                                                 \
	CodegenLLVM cg_ctx = codegen_init(&cg_init_ctx);                                                                                                                                                                                           \
	codegen_run(&cg_ctx, module->ast, module->symbol_table);                                                                                                                                                                                   \
	char *output = codegen_output_str(&cg_ctx);                                                                                                                                                                                                \
	codegen_deinit(&cg_ctx);                                                                                                                                                                                                                   \
	char *error = capture_error_end(old_stdout);

void test_FunctionDecl_codegen(void) {
	{
		CODEGEN_TEST_SETUP_SINGLE("fn void some_func() {}");
		const char *expected = "; ModuleID = 'test'\n"
							   "source_filename = \"test\"\n\n"
							   "define void @some_func() {\n"
							   "entry:\n"
							   "}\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
	{
		CODEGEN_TEST_SETUP_SINGLE("fn i32 some_func() {}");
		const char *expected = "; ModuleID = 'test'\n"
							   "source_filename = \"test\"\n\n"
							   "define i32 @some_func() {\n"
							   "entry:\n"
							   "}\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
	{
		CODEGEN_TEST_SETUP_SINGLE("fn i32 some_func(i32 a, i32 b) {}");
		const char *expected = "; ModuleID = 'test'\n"
							   "source_filename = \"test\"\n\n"
							   "define i32 @some_func(i32 %0, i32 %1) {\n"
							   "entry:\n"
							   "}\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
}
