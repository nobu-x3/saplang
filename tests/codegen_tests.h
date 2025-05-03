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
							   "  %__some_func_a = alloca i32, align 4\n"
							   "  store i32 %0, ptr %__some_func_a, align 4\n"
							   "  %__some_func_b = alloca i32, align 4\n"
							   "  store i32 %1, ptr %__some_func_b, align 4\n"
							   "}\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
}

void test_BuiltinGlobalVarNoInit_codegen(void) {
	{
		CODEGEN_TEST_SETUP_SINGLE("i32 i;");
		const char *expected = "; ModuleID = 'test'\n"
							   "source_filename = \"test\"\n\n"
							   "@i = global i32 0\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
	{
		CODEGEN_TEST_SETUP_SINGLE("f32 i;");
		const char *expected = "; ModuleID = 'test'\n"
							   "source_filename = \"test\"\n\n"
							   "@i = global bfloat 0xR0000\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
	{
		CODEGEN_TEST_SETUP_SINGLE("bool i;");
		const char *expected = "; ModuleID = 'test'\n"
							   "source_filename = \"test\"\n\n"
							   "@i = global i1 false\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
}

void test_BuiltinGlobalVar_codegen(void) {
	{
		CODEGEN_TEST_SETUP_SINGLE("i32 i = 1;");
		const char *expected = "; ModuleID = 'test'\n"
							   "source_filename = \"test\"\n\n"
							   "@i = global i32 1\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
	{
		CODEGEN_TEST_SETUP_SINGLE("f32 i = 1.0;");
		const char *expected = "; ModuleID = 'test'\n"
							   "source_filename = \"test\"\n\n"
							   "@i = global bfloat 0xR3F80\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
	{
		CODEGEN_TEST_SETUP_SINGLE("bool i = true;");
		const char *expected = "; ModuleID = 'test'\n"
							   "source_filename = \"test\"\n\n"
							   "@i = global i1 true\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
}

void test_BuiltinGlobalConst_codegen(void) {
	{
		CODEGEN_TEST_SETUP_SINGLE("const i32 i = 1;");
		const char *expected = "; ModuleID = 'test'\n"
							   "source_filename = \"test\"\n\n"
							   "@i = constant i32 1\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
	{
		CODEGEN_TEST_SETUP_SINGLE("const f32 i = 1.0;");
		const char *expected = "; ModuleID = 'test'\n"
							   "source_filename = \"test\"\n\n"
							   "@i = constant bfloat 0xR3F80\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
	{
		CODEGEN_TEST_SETUP_SINGLE("const bool i = true;");
		const char *expected = "; ModuleID = 'test'\n"
							   "source_filename = \"test\"\n\n"
							   "@i = constant i1 true\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
}

void test_StructDecl_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("struct TestStruct { i32 first; f32 second; } TestStruct str; ");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%TestStruct = type { i32, bfloat }\n\n"
						   "@str = global %TestStruct zeroinitializer\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_GlobalStructDeclInit_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("struct TestStruct { i32 first; f32 second; i64 third; } TestStruct str = {.second = 3.22, 1337}; ");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%TestStruct = type { i32, bfloat, i64 }\n\n"
						   "@str = global %TestStruct { i32 0, bfloat 0xR404E, i64 1337 }\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_ConstGlobalStructDeclInit_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("struct TestStruct { i32 first; f32 second; i64 third; } const TestStruct str = {.second = 3.22, 1337}; ");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%TestStruct = type { i32, bfloat, i64 }\n\n"
						   "@str = constant %TestStruct { i32 0, bfloat 0xR404E, i64 1337 }\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_LocalVarDeclNoInit_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void some_func() { i32 i; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define void @some_func() {\n"
						   "entry:\n"
						   "  %__some_func_i = alloca i32, align 4\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_LocalVarDeclWithInit_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void some_func() { i32 i = 3; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define void @some_func() {\n"
						   "entry:\n"
						   "  %__some_func_i = alloca i32, align 4\n"
						   "  store i32 3, ptr %__some_func_i, align 4\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}
