#pragma once
#include "test_util.h"
#include <codegen.h>
#include <parser.h>
#include <sema.h>
#include <string.h>
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
	if (!module || module->has_errors)                                                                                                                                                                                                         \
		UnityFail("Parsing failed", 0);                                                                                                                                                                                                        \
	int success = 1;                                                                                                                                                                                                                           \
	symbol_table_set_type_info(module->symbol_table);                                                                                                                                                                                          \
	for (ASTNode *node = module->ast; node != NULL; node = node->next) {                                                                                                                                                                       \
		success &= analyze_ast(module->symbol_table, node, 0, "") == RESULT_SUCCESS;                                                                                                                                                           \
		success &= resolve_types(module->symbol_table, node, 1) == RESULT_SUCCESS;                                                                                                                                                             \
	}                                                                                                                                                                                                                                          \
	if (!success)                                                                                                                                                                                                                              \
		UnityFail("Sema failed", 0);                                                                                                                                                                                                           \
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
							   "define void @__main_some_func() {\n"
							   "entry:\n"
							   "  ret void\n"
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
							   "define i32 @__main_some_func() {\n"
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
							   "define i32 @__main_some_func__i32_i32(i32 %0, i32 %1) {\n"
							   "entry:\n"
							   "  %__main_some_func__i32_i32_a = alloca i32, align 4\n"
							   "  store i32 %0, ptr %__main_some_func__i32_i32_a, align 4\n"
							   "  %__main_some_func__i32_i32_b = alloca i32, align 4\n"
							   "  store i32 %1, ptr %__main_some_func__i32_i32_b, align 4\n"
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
							   "@__main_i = global i32 0\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
	{
		CODEGEN_TEST_SETUP_SINGLE("f32 i;");
		const char *expected = "; ModuleID = 'test'\n"
							   "source_filename = \"test\"\n\n"
							   "@__main_i = global float 0.000000e+00\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
	{
		CODEGEN_TEST_SETUP_SINGLE("bool i;");
		const char *expected = "; ModuleID = 'test'\n"
							   "source_filename = \"test\"\n\n"
							   "@__main_i = global i1 false\n";
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
							   "@__main_i = global i32 1\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
	{
		CODEGEN_TEST_SETUP_SINGLE("f32 i = 1.0;");
		const char *expected = "; ModuleID = 'test'\n"
							   "source_filename = \"test\"\n\n"
							   "@__main_i = global float 1.000000e+00\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
	{
		CODEGEN_TEST_SETUP_SINGLE("bool i = true;");
		const char *expected = "; ModuleID = 'test'\n"
							   "source_filename = \"test\"\n\n"
							   "@__main_i = global i1 true\n";
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
							   "@__main_i = constant i32 1\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
	{
		CODEGEN_TEST_SETUP_SINGLE("const f32 i = 1.0;");
		const char *expected = "; ModuleID = 'test'\n"
							   "source_filename = \"test\"\n\n"
							   "@__main_i = constant float 1.000000e+00\n";
		const char *expected_error = "";
		TEST_ASSERT_EQUAL_STRING(expected, output);
		TEST_ASSERT_EQUAL_STRING(expected_error, error);
		free(error);
	}
	{
		CODEGEN_TEST_SETUP_SINGLE("const bool i = true;");
		const char *expected = "; ModuleID = 'test'\n"
							   "source_filename = \"test\"\n\n"
							   "@__main_i = constant i1 true\n";
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
						   "%__main_TestStruct = type { i32, float }\n\n"
						   "@__main_str = global %__main_TestStruct zeroinitializer\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_GlobalStructDeclInit_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("struct TestStruct { i32 first; f32 second; i64 third; } TestStruct str = {.second = 3.22, 1337}; ");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%__main_TestStruct = type { i32, float, i64 }\n\n"
						   "@__main_str = global %__main_TestStruct { i32 0, float 0x4009C28F60000000, i64 1337 }\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_ConstGlobalStructDeclInit_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("struct TestStruct { i32 first; f32 second; i64 third; } const TestStruct str = {.second = 3.22, 1337}; ");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%__main_TestStruct = type { i32, float, i64 }\n\n"
						   "@__main_str = constant %__main_TestStruct { i32 0, float 0x4009C28F60000000, i64 1337 }\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_LocalVarDeclNoInit_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void some_func() { i32 i; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define void @__main_some_func() {\n"
						   "entry:\n"
						   "  %__main_some_func_i = alloca i32, align 4\n"
						   "  ret void\n"
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
						   "define void @__main_some_func() {\n"
						   "entry:\n"
						   "  %__main_some_func_i = alloca i32, align 4\n"
						   "  store i32 3, ptr %__main_some_func_i, align 4\n"
						   "  ret void\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_LocalVarDeclWithInitOfIdent_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void some_func() { i32 a; i32 i = a; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define void @__main_some_func() {\n"
						   "entry:\n"
						   "  %__main_some_func_a = alloca i32, align 4\n"
						   "  %__main_some_func_i = alloca i32, align 4\n"
						   "  %0 = load i32, ptr %__main_some_func_a, align 4\n"
						   "  store i32 %0, ptr %__main_some_func_i, align 4\n"
						   "  ret void\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_LocalVarReassignmentToLiteral_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void some_func() { i32 i; i = 3; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define void @__main_some_func() {\n"
						   "entry:\n"
						   "  %__main_some_func_i = alloca i32, align 4\n"
						   "  store i32 3, ptr %__main_some_func_i, align 4\n"
						   "  ret void\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_LocalVarReassignmentToLocalVar_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void some_func() { i32 i; i32 a; i = a; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define void @__main_some_func() {\n"
						   "entry:\n"
						   "  %__main_some_func_i = alloca i32, align 4\n"
						   "  %__main_some_func_a = alloca i32, align 4\n"
						   "  %0 = load i32, ptr %__main_some_func_a, align 4\n"
						   "  store i32 %0, ptr %__main_some_func_i, align 4\n"
						   "  ret void\n"
						   "}\n";
	;
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_LocalVarReassignmentToGlobalVar_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("i32 a; fn i32 main() { i32 i; i = a; return i; }")
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "@__main_a = global i32 0\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_i = alloca i32, align 4\n"
						   "  %0 = load i32, ptr @__main_a, align 4\n"
						   "  store i32 %0, ptr %__main_main_i, align 4\n"
						   "  %1 = load i32, ptr %__main_main_i, align 4\n"
						   "  ret i32 %1\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_GlobalVarReassignmentToLiteral_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("i32 a; fn void some_func() { a = 3; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "@__main_a = global i32 0\n\n"
						   "define void @__main_some_func() {\n"
						   "entry:\n"
						   "  store i32 3, ptr @__main_a, align 4\n"
						   "  ret void\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_GlobalVarReassignmentToGlobal_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("i32 a; i32 i; fn void some_func() { i = a; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "@__main_a = global i32 0\n"
						   "@__main_i = global i32 0\n\n"
						   "define void @__main_some_func() {\n"
						   "entry:\n"
						   "  %0 = load i32, ptr @__main_a, align 4\n"
						   "  store i32 %0, ptr @__main_i, align 4\n"
						   "  ret void\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_GlobalVarReassignmentToLocal_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("i32 i; fn void some_func() { i32 a; i = a; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "@__main_i = global i32 0\n\n"
						   "define void @__main_some_func() {\n"
						   "entry:\n"
						   "  %__main_some_func_a = alloca i32, align 4\n"
						   "  %0 = load i32, ptr %__main_some_func_a, align 4\n"
						   "  store i32 %0, ptr @__main_i, align 4\n"
						   "  ret void\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_LocalStructLiteralInit_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("struct TestStruct { i32 first; f32 second; } fn void foo() { TestStruct str = {3, 4.0}; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%__main_TestStruct = type { i32, float }\n\n"
						   "define void @__main_foo() {\n"
						   "entry:\n"
						   "  %__main_foo_str = alloca %__main_TestStruct, align 8\n"
						   "  %gep_0__main_foo_str = getelementptr inbounds %__main_TestStruct, ptr %__main_foo_str, i32 0, i32 0\n"
						   "  store i32 3, ptr %gep_0__main_foo_str, align 4\n"
						   "  %gep_1__main_foo_str = getelementptr inbounds %__main_TestStruct, ptr %__main_foo_str, i32 0, i32 1\n"
						   "  store float 4.000000e+00, ptr %gep_1__main_foo_str, align 4\n"
						   "  ret void\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_LocalStructLiteralEmptyInit_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("struct TestStruct { i32 first; f32 second; } fn void foo() { TestStruct str = {}; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%__main_TestStruct = type { i32, float }\n\n"
						   "define void @__main_foo() {\n"
						   "entry:\n"
						   "  %__main_foo_str = alloca %__main_TestStruct, align 8\n"
						   "  %gep_0__main_foo_str = getelementptr inbounds %__main_TestStruct, ptr %__main_foo_str, i32 0, i32 0\n"
						   "  store i32 0, ptr %gep_0__main_foo_str, align 4\n"
						   "  %gep_1__main_foo_str = getelementptr inbounds %__main_TestStruct, ptr %__main_foo_str, i32 0, i32 1\n"
						   "  store float 0.000000e+00, ptr %gep_1__main_foo_str, align 4\n"
						   "  ret void\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_LocalStructLiteralReinitialization_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("struct TestStruct { i32 first; f32 second; } fn void foo() { TestStruct str = {1, 1.0}; str = {}; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%__main_TestStruct = type { i32, float }\n\n"
						   "define void @__main_foo() {\n"
						   "entry:\n"
						   "  %__main_foo_str = alloca %__main_TestStruct, align 8\n"
						   "  %gep_0__main_foo_str = getelementptr inbounds %__main_TestStruct, ptr %__main_foo_str, i32 0, i32 0\n"
						   "  store i32 1, ptr %gep_0__main_foo_str, align 4\n"
						   "  %gep_1__main_foo_str = getelementptr inbounds %__main_TestStruct, ptr %__main_foo_str, i32 0, i32 1\n"
						   "  store float 1.000000e+00, ptr %gep_1__main_foo_str, align 4\n"
						   "  %gep_0__main_foo_str1 = getelementptr inbounds %__main_TestStruct, ptr %__main_foo_str, i32 0, i32 0\n"
						   "  store i32 0, ptr %gep_0__main_foo_str1, align 4\n"
						   "  %gep_1__main_foo_str2 = getelementptr inbounds %__main_TestStruct, ptr %__main_foo_str, i32 0, i32 1\n"
						   "  store float 0.000000e+00, ptr %gep_1__main_foo_str2, align 4\n"
						   "  ret void\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_BasicMemberAccessAssignment_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("struct TestStruct { i32 first; f32 second; } fn void foo() { TestStruct str; str.first = 1; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%__main_TestStruct = type { i32, float }\n\n"
						   "define void @__main_foo() {\n"
						   "entry:\n"
						   "  %__main_foo_str = alloca %__main_TestStruct, align 8\n"
						   "  %first = getelementptr inbounds %__main_TestStruct, ptr %__main_foo_str, i32 0, i32 0\n"
						   "  store i32 1, ptr %first, align 4\n"
						   "  ret void\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_NestedMemberAccessAssignment_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("struct TestStruct { i32 first; f32 second; } struct TestStruct2 { TestStruct nest; } fn void foo() { TestStruct2 str; str.nest.first = 1; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%__main_TestStruct2 = type { %__main_TestStruct }\n"
						   "%__main_TestStruct = type { i32, float }\n"
						   "\n"
						   "define void @__main_foo() {\n"
						   "entry:\n"
						   "  %__main_foo_str = alloca %__main_TestStruct2, align 8\n"
						   "  %nest = getelementptr inbounds %__main_TestStruct2, ptr %__main_foo_str, i32 0, i32 0\n"
						   "  %first = getelementptr inbounds %__main_TestStruct, ptr %nest, i32 0, i32 0\n"
						   "  store i32 1, ptr %first, align 4\n"
						   "  ret void\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_MemberAccessAssignmentToMemberAccess_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("struct TestStr { i32 first; } fn i32 main() { TestStr a = {8}; TestStr b; b.first = a.first; return b.first; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%__main_TestStr = type { i32 }\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca %__main_TestStr, align 8\n"
						   "  %gep_0__main_main_a = getelementptr inbounds %__main_TestStr, ptr %__main_main_a, i32 0, i32 0\n"
						   "  store i32 8, ptr %gep_0__main_main_a, align 4\n"
						   "  %__main_main_b = alloca %__main_TestStr, align 8\n"
						   "  %first = getelementptr inbounds %__main_TestStr, ptr %__main_main_b, i32 0, i32 0\n"
						   "  %first1 = getelementptr inbounds %__main_TestStr, ptr %__main_main_a, i32 0, i32 0\n"
						   "  %0 = load i32, ptr %first1, align 4\n"
						   "  store i32 %0, ptr %first, align 4\n"
						   "  %first2 = getelementptr inbounds %__main_TestStr, ptr %__main_main_b, i32 0, i32 0\n"
						   "  %1 = load i32, ptr %first2, align 4\n"
						   "  ret i32 %1\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_BasicReturn_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { return 1; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  ret i32 1\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_ExprIdentReturn_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32 a = 8; return a; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca i32, align 4\n"
						   "  store i32 8, ptr %__main_main_a, align 4\n"
						   "  %0 = load i32, ptr %__main_main_a, align 4\n"
						   "  ret i32 %0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_MemberAccessReturn_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("struct TestStr { i32 first; } fn i32 main() { TestStr a = {8}; return a.first; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%__main_TestStr = type { i32 }\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca %__main_TestStr, align 8\n"
						   "  %gep_0__main_main_a = getelementptr inbounds %__main_TestStr, ptr %__main_main_a, i32 0, i32 0\n"
						   "  store i32 8, ptr %gep_0__main_main_a, align 4\n"
						   "  %first = getelementptr inbounds %__main_TestStr, ptr %__main_main_a, i32 0, i32 0\n"
						   "  %0 = load i32, ptr %first, align 4\n"
						   "  ret i32 %0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_NestedStructInit_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("struct TestStr { i32 first; } struct TestStr2 { TestStr nest; } fn i32 main() { TestStr2 str = {{8}}; return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%__main_TestStr2 = type { %__main_TestStr }\n"
						   "%__main_TestStr = type { i32 }\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_str = alloca %__main_TestStr2, align 8\n"
						   "  %tmp_inner_str = alloca %__main_TestStr, align 8\n"
						   "  %gep_0 = getelementptr inbounds %__main_TestStr, ptr %tmp_inner_str, i32 0, i32 0\n"
						   "  store i32 8, ptr %gep_0, align 4\n"
						   "  %inner_struct_val = load %__main_TestStr, ptr %tmp_inner_str, align 4\n"
						   "  %gep_0__main_main_str = getelementptr inbounds %__main_TestStr2, ptr %__main_main_str, i32 0, i32 0\n"
						   "  store %__main_TestStr %inner_struct_val, ptr %gep_0__main_main_str, align 4\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_MemberAccessNestedReturn_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("struct TestStr { i32 first; } struct TestStr2 { TestStr nest; } fn i32 main() { TestStr2 a = {{8}}; return a.nest.first; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%__main_TestStr2 = type { %__main_TestStr }\n"
						   "%__main_TestStr = type { i32 }\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca %__main_TestStr2, align 8\n"
						   "  %tmp_inner_str = alloca %__main_TestStr, align 8\n"
						   "  %gep_0 = getelementptr inbounds %__main_TestStr, ptr %tmp_inner_str, i32 0, i32 0\n"
						   "  store i32 8, ptr %gep_0, align 4\n"
						   "  %inner_struct_val = load %__main_TestStr, ptr %tmp_inner_str, align 4\n"
						   "  %gep_0__main_main_a = getelementptr inbounds %__main_TestStr2, ptr %__main_main_a, i32 0, i32 0\n"
						   "  store %__main_TestStr %inner_struct_val, ptr %gep_0__main_main_a, align 4\n"
						   "  %nest = getelementptr inbounds %__main_TestStr2, ptr %__main_main_a, i32 0, i32 0\n"
						   "  %first = getelementptr inbounds %__main_TestStr, ptr %nest, i32 0, i32 0\n"
						   "  %0 = load i32, ptr %first, align 4\n"
						   "  ret i32 %0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_UnaryNeg_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32 a = 5; i32 b = -a; return b; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca i32, align 4\n"
						   "  store i32 5, ptr %__main_main_a, align 4\n"
						   "  %__main_main_b = alloca i32, align 4\n"
						   "  %0 = load i32, ptr %__main_main_a, align 4\n"
						   "  %negtmp = sub i32 0, %0\n"
						   "  store i32 %negtmp, ptr %__main_main_b, align 4\n"
						   "  %1 = load i32, ptr %__main_main_b, align 4\n"
						   "  ret i32 %1\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_UnaryLogicalNot_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn bool main() { bool f = true; bool g = !f; return g; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i1 @main() {\n"
						   "entry:\n"
						   "  %__main_main_f = alloca i1, align 1\n"
						   "  store i1 true, ptr %__main_main_f, align 1\n"
						   "  %__main_main_g = alloca i1, align 1\n"
						   "  %0 = load i1, ptr %__main_main_f, align 1\n"
						   "  %nottmp = xor i1 %0, true\n"
						   "  store i1 %nottmp, ptr %__main_main_g, align 1\n"
						   "  %1 = load i1, ptr %__main_main_g, align 1\n"
						   "  ret i1 %1\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_UnaryAddressOf_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32 v = 42; i32* p = &v; return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_v = alloca i32, align 4\n"
						   "  store i32 42, ptr %__main_main_v, align 4\n"
						   "  %__main_main_p = alloca ptr, align 8\n"
						   "  store ptr %__main_main_v, ptr %__main_main_p, align 8\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_UnaryDeref_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32 v = 7; i32* p = &v; i32 u = *p; return u; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_v = alloca i32, align 4\n"
						   "  store i32 7, ptr %__main_main_v, align 4\n"
						   "  %__main_main_p = alloca ptr, align 8\n"
						   "  store ptr %__main_main_v, ptr %__main_main_p, align 8\n"
						   "  %__main_main_u = alloca i32, align 4\n"
						   "  %0 = load ptr, ptr %__main_main_p, align 8\n"
						   "  %deref = load i32, ptr %0, align 4\n"
						   "  store i32 %deref, ptr %__main_main_u, align 4\n"
						   "  %1 = load i32, ptr %__main_main_u, align 4\n"
						   "  ret i32 %1\n"
						   "}\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING("", error);
	free(error);
}

void test_UnaryBitwiseNot_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32 x = 0; i32 y = ~x; return y; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_x = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_x, align 4\n"
						   "  %__main_main_y = alloca i32, align 4\n"
						   "  %0 = load i32, ptr %__main_main_x, align 4\n"
						   "  %lnot = xor i32 %0, -1\n"
						   "  store i32 %lnot, ptr %__main_main_y, align 4\n"
						   "  %1 = load i32, ptr %__main_main_y, align 4\n"
						   "  ret i32 %1\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_Add_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32 x = 0; i32 y = 1; y = y + x; y = y + 1; y = 1 + y; return y; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_x = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_x, align 4\n"
						   "  %__main_main_y = alloca i32, align 4\n"
						   "  store i32 1, ptr %__main_main_y, align 4\n"
						   "  %0 = load i32, ptr %__main_main_y, align 4\n"
						   "  %1 = load i32, ptr %__main_main_x, align 4\n"
						   "  %add = add i32 %0, %1\n"
						   "  store i32 %add, ptr %__main_main_y, align 4\n"
						   "  %2 = load i32, ptr %__main_main_y, align 4\n"
						   "  %add1 = add i32 %2, 1\n"
						   "  store i32 %add1, ptr %__main_main_y, align 4\n"
						   "  %3 = load i32, ptr %__main_main_y, align 4\n"
						   "  %add2 = add i32 1, %3\n"
						   "  store i32 %add2, ptr %__main_main_y, align 4\n"
						   "  %4 = load i32, ptr %__main_main_y, align 4\n"
						   "  ret i32 %4\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_Sub_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32 x = 0; i32 y = 1; y = y - x; y = y - 1; y = 1 - y; return y; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_x = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_x, align 4\n"
						   "  %__main_main_y = alloca i32, align 4\n"
						   "  store i32 1, ptr %__main_main_y, align 4\n"
						   "  %0 = load i32, ptr %__main_main_y, align 4\n"
						   "  %1 = load i32, ptr %__main_main_x, align 4\n"
						   "  %sub = sub i32 %0, %1\n"
						   "  store i32 %sub, ptr %__main_main_y, align 4\n"
						   "  %2 = load i32, ptr %__main_main_y, align 4\n"
						   "  %sub1 = sub i32 %2, 1\n"
						   "  store i32 %sub1, ptr %__main_main_y, align 4\n"
						   "  %3 = load i32, ptr %__main_main_y, align 4\n"
						   "  %sub2 = sub i32 1, %3\n"
						   "  store i32 %sub2, ptr %__main_main_y, align 4\n"
						   "  %4 = load i32, ptr %__main_main_y, align 4\n"
						   "  ret i32 %4\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_Div_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn f32 foo() { f32 x = 4.0; f32 y = 2.0; y = x / y; y = y / 1.0; y = 1.0 / y; return y; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define float @__main_foo() {\n"
						   "entry:\n"
						   "  %__main_foo_x = alloca float, align 4\n"
						   "  store float 4.000000e+00, ptr %__main_foo_x, align 4\n"
						   "  %__main_foo_y = alloca float, align 4\n"
						   "  store float 2.000000e+00, ptr %__main_foo_y, align 4\n"
						   "  %0 = load float, ptr %__main_foo_x, align 4\n"
						   "  %1 = load float, ptr %__main_foo_y, align 4\n"
						   "  %div = fdiv float %0, %1\n"
						   "  store float %div, ptr %__main_foo_y, align 4\n"
						   "  %2 = load float, ptr %__main_foo_y, align 4\n"
						   "  %div1 = fdiv float %2, 1.000000e+00\n"
						   "  store float %div1, ptr %__main_foo_y, align 4\n"
						   "  %3 = load float, ptr %__main_foo_y, align 4\n"
						   "  %div2 = fdiv float 1.000000e+00, %3\n"
						   "  store float %div2, ptr %__main_foo_y, align 4\n"
						   "  %4 = load float, ptr %__main_foo_y, align 4\n"
						   "  ret float %4\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_Mul_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32 x = 4; i32 y = 2; y = x * y; y = y * 1; y = 1 * y; return y; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_x = alloca i32, align 4\n"
						   "  store i32 4, ptr %__main_main_x, align 4\n"
						   "  %__main_main_y = alloca i32, align 4\n"
						   "  store i32 2, ptr %__main_main_y, align 4\n"
						   "  %0 = load i32, ptr %__main_main_x, align 4\n"
						   "  %1 = load i32, ptr %__main_main_y, align 4\n"
						   "  %mul = mul i32 %0, %1\n"
						   "  store i32 %mul, ptr %__main_main_y, align 4\n"
						   "  %2 = load i32, ptr %__main_main_y, align 4\n"
						   "  %mul1 = mul i32 %2, 1\n"
						   "  store i32 %mul1, ptr %__main_main_y, align 4\n"
						   "  %3 = load i32, ptr %__main_main_y, align 4\n"
						   "  %mul2 = mul i32 1, %3\n"
						   "  store i32 %mul2, ptr %__main_main_y, align 4\n"
						   "  %4 = load i32, ptr %__main_main_y, align 4\n"
						   "  ret i32 %4\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_Mod_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32 x = 4; i32 y = 2; y = x % y; y = y % 1; return y; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_x = alloca i32, align 4\n"
						   "  store i32 4, ptr %__main_main_x, align 4\n"
						   "  %__main_main_y = alloca i32, align 4\n"
						   "  store i32 2, ptr %__main_main_y, align 4\n"
						   "  %0 = load i32, ptr %__main_main_x, align 4\n"
						   "  %1 = load i32, ptr %__main_main_y, align 4\n"
						   "  %rem = srem i32 %0, %1\n"
						   "  store i32 %rem, ptr %__main_main_y, align 4\n"
						   "  %2 = load i32, ptr %__main_main_y, align 4\n"
						   "  %rem1 = srem i32 %2, 1\n"
						   "  store i32 %rem1, ptr %__main_main_y, align 4\n"
						   "  %3 = load i32, ptr %__main_main_y, align 4\n"
						   "  ret i32 %3\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_SelfAdd_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32 x = 1; i32 y = 1; y += x; y += 1; y += y; return y; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_x = alloca i32, align 4\n"
						   "  store i32 1, ptr %__main_main_x, align 4\n"
						   "  %__main_main_y = alloca i32, align 4\n"
						   "  store i32 1, ptr %__main_main_y, align 4\n"
						   "  %0 = load i32, ptr %__main_main_y, align 4\n"
						   "  %1 = load i32, ptr %__main_main_x, align 4\n"
						   "  %add = add i32 %0, %1\n"
						   "  store i32 %add, ptr %__main_main_y, align 4\n"
						   "  %2 = load i32, ptr %__main_main_y, align 4\n"
						   "  %add1 = add i32 %2, 1\n"
						   "  store i32 %add1, ptr %__main_main_y, align 4\n"
						   "  %3 = load i32, ptr %__main_main_y, align 4\n"
						   "  %4 = load i32, ptr %__main_main_y, align 4\n"
						   "  %add2 = add i32 %3, %4\n"
						   "  store i32 %add2, ptr %__main_main_y, align 4\n"
						   "  %5 = load i32, ptr %__main_main_y, align 4\n"
						   "  ret i32 %5\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_SelfSub_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32 x = 1; i32 y = 10; y -= x; y -= 1; y -= y; return y; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_x = alloca i32, align 4\n"
						   "  store i32 1, ptr %__main_main_x, align 4\n"
						   "  %__main_main_y = alloca i32, align 4\n"
						   "  store i32 10, ptr %__main_main_y, align 4\n"
						   "  %0 = load i32, ptr %__main_main_y, align 4\n"
						   "  %1 = load i32, ptr %__main_main_x, align 4\n"
						   "  %sub = sub i32 %0, %1\n"
						   "  store i32 %sub, ptr %__main_main_y, align 4\n"
						   "  %2 = load i32, ptr %__main_main_y, align 4\n"
						   "  %sub1 = sub i32 %2, 1\n"
						   "  store i32 %sub1, ptr %__main_main_y, align 4\n"
						   "  %3 = load i32, ptr %__main_main_y, align 4\n"
						   "  %4 = load i32, ptr %__main_main_y, align 4\n"
						   "  %sub2 = sub i32 %3, %4\n"
						   "  store i32 %sub2, ptr %__main_main_y, align 4\n"
						   "  %5 = load i32, ptr %__main_main_y, align 4\n"
						   "  ret i32 %5\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_SelfMul_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32 x = 2; i32 y = 10; y *= x; y *= 1; y *= y; return y; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_x = alloca i32, align 4\n"
						   "  store i32 2, ptr %__main_main_x, align 4\n"
						   "  %__main_main_y = alloca i32, align 4\n"
						   "  store i32 10, ptr %__main_main_y, align 4\n"
						   "  %0 = load i32, ptr %__main_main_y, align 4\n"
						   "  %1 = load i32, ptr %__main_main_x, align 4\n"
						   "  %mul = mul i32 %0, %1\n"
						   "  store i32 %mul, ptr %__main_main_y, align 4\n"
						   "  %2 = load i32, ptr %__main_main_y, align 4\n"
						   "  %mul1 = mul i32 %2, 1\n"
						   "  store i32 %mul1, ptr %__main_main_y, align 4\n"
						   "  %3 = load i32, ptr %__main_main_y, align 4\n"
						   "  %4 = load i32, ptr %__main_main_y, align 4\n"
						   "  %mul2 = mul i32 %3, %4\n"
						   "  store i32 %mul2, ptr %__main_main_y, align 4\n"
						   "  %5 = load i32, ptr %__main_main_y, align 4\n"
						   "  ret i32 %5\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_SelfDiv_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32 x = 2; i32 y = 10; y /= x; y /= 1; y /= y; return y; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_x = alloca i32, align 4\n"
						   "  store i32 2, ptr %__main_main_x, align 4\n"
						   "  %__main_main_y = alloca i32, align 4\n"
						   "  store i32 10, ptr %__main_main_y, align 4\n"
						   "  %0 = load i32, ptr %__main_main_y, align 4\n"
						   "  %1 = load i32, ptr %__main_main_x, align 4\n"
						   "  %div = sdiv i32 %0, %1\n"
						   "  store i32 %div, ptr %__main_main_y, align 4\n"
						   "  %2 = load i32, ptr %__main_main_y, align 4\n"
						   "  %div1 = sdiv i32 %2, 1\n"
						   "  store i32 %div1, ptr %__main_main_y, align 4\n"
						   "  %3 = load i32, ptr %__main_main_y, align 4\n"
						   "  %4 = load i32, ptr %__main_main_y, align 4\n"
						   "  %div2 = sdiv i32 %3, %4\n"
						   "  store i32 %div2, ptr %__main_main_y, align 4\n"
						   "  %5 = load i32, ptr %__main_main_y, align 4\n"
						   "  ret i32 %5\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_CharList_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void main() { u8 lit = 'a'; lit = 'b'; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define void @main() {\n"
						   "entry:\n"
						   "  %__main_main_lit = alloca i8, align 1\n"
						   "  store i8 97, ptr %__main_main_lit, align 1\n"
						   "  store i8 98, ptr %__main_main_lit, align 1\n"
						   "  ret void\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

// A slice variable allocas a two-field struct `{ ptr, i64 }`. With no
// initializer, no store is emitted — matches the existing default-init
// behavior for other aggregate locals.
void test_SliceVarDeclNoInit_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void foo() { i32[] s; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "alloca { ptr, i64 }"));
	TEST_ASSERT_EQUAL_STRING("", error);
	free(error);
}

// Initialising a slice from a fixed-size array materialises the fat
// pointer in-place: an `insertvalue` for the data pointer (the array
// alloca) and another for the length. The store then commits the whole
// { ptr, i64 } aggregate.
void test_SliceVarDeclFromArray_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void foo() { i32[3] arr = [1, 2, 3]; i32[] s = arr; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "alloca [3 x i32]"));
	TEST_ASSERT_NOT_NULL(strstr(output, "alloca { ptr, i64 }"));
	TEST_ASSERT_NOT_NULL(strstr(output, "insertvalue { ptr, i64 } undef, ptr %__main_foo_arr, 0"));
	TEST_ASSERT_NOT_NULL(strstr(output, "i64 3, 1"));
	TEST_ASSERT_NOT_NULL(strstr(output, "store { ptr, i64 }"));
	TEST_ASSERT_EQUAL_STRING("", error);
	free(error);
}

// Calling `take(arr)` with a fixed-size array against a slice parameter
// emits the same materialisation at the call site and passes the
// { ptr, i64 } value as the argument.
void test_SlicePassArrayAsArg_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void take(i32[] s) {} fn void foo() { i32[3] arr = [1, 2, 3]; take(arr); }");
	TEST_ASSERT_NOT_NULL(strstr(output, "define void @\"__main_take__i32[]\"({ ptr, i64 } %0)"));
	TEST_ASSERT_NOT_NULL(strstr(output, "insertvalue { ptr, i64 } undef, ptr %__main_foo_arr, 0"));
	TEST_ASSERT_NOT_NULL(strstr(output, "i64 3, 1"));
	TEST_ASSERT_NOT_NULL(strstr(output, "call void @\"__main_take__i32[]\"({ ptr, i64 }"));
	TEST_ASSERT_EQUAL_STRING("", error);
	free(error);
}

// `null → slice` produces a zero slice: null data pointer, zero length.
// Same shape as the array case, just with a null constant.
// `null` typed as a slice should produce the zero slice. LLVM
// constant-folds the two `insertvalue`s into a `zeroinitializer` for
// the { ptr, i64 } aggregate, which is semantically the same.
void test_SliceFromNull_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void foo() { i32[] s = null; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "alloca { ptr, i64 }"));
	TEST_ASSERT_NOT_NULL(strstr(output, "store { ptr, i64 } zeroinitializer"));
	TEST_ASSERT_EQUAL_STRING("", error);
	free(error);
}

// A slice literal lowers to the same `insertvalue` shape used for
// array→slice decay: ptr into field 0, len into field 1. The store lands
// on the slice's alloca.
void test_SliceLiteralPositional_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void foo(i32* p) { i32[] s = {p, 4}; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "alloca { ptr, i64 }"));
	TEST_ASSERT_NOT_NULL(strstr(output, "insertvalue { ptr, i64 } undef, ptr"));
	TEST_ASSERT_NOT_NULL(strstr(output, "i64 4, 1"));
	TEST_ASSERT_NOT_NULL(strstr(output, "store { ptr, i64 }"));
	TEST_ASSERT_EQUAL_STRING("", error);
	free(error);
}

// Designated form lowers identically — the field name only selects which
// expression goes into which slot. The IR shape is the same.
void test_SliceLiteralDesignated_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void foo(i32* p) { i32[] s = {.len = 7, .ptr = p}; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "insertvalue { ptr, i64 } undef, ptr"));
	TEST_ASSERT_NOT_NULL(strstr(output, "i64 7, 1"));
	TEST_ASSERT_EQUAL_STRING("", error);
	free(error);
}

// End-to-end: build a slice from raw ptr + len, then read `.len` from it.
// Verifies the constructed slice is structurally usable.
void test_SliceLiteralLengthIsReadable_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn u64 foo(i32* p) { i32[] s = {p, 9}; return s.len; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "i64 9, 1"));
	TEST_ASSERT_NOT_NULL(strstr(output, "getelementptr inbounds { ptr, i64 }"));
	TEST_ASSERT_NOT_NULL(strstr(output, "load i64"));
	TEST_ASSERT_EQUAL_STRING("", error);
	free(error);
}

// Sub-slicing an array bases the new data pointer at `&arr[lo]` and
// sets length to `hi - lo`. The output ptr is a GEP from the array
// alloca, and the length subtraction shows up explicitly.
void test_SliceRangeFromArray_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void foo() { i32[5] arr = [1,2,3,4,5]; i32[] s = arr[1..4]; }");
	// Compile-time bounds (4 - 1) constant-fold to 3, so no explicit
	// `sub` shows up — verify the constant length and the offset GEP.
	TEST_ASSERT_NOT_NULL(strstr(output, "getelementptr inbounds [5 x i32]"));
	TEST_ASSERT_NOT_NULL(strstr(output, "getelementptr inbounds i32, ptr %range.arr.base, i64 1"));
	TEST_ASSERT_NOT_NULL(strstr(output, "insertvalue { ptr, i64 } %range.slice.ptr, i64 3, 1"));
	TEST_ASSERT_EQUAL_STRING("", error);
	free(error);
}

// Sub-slicing a slice loads the source slice's data pointer first, then
// GEPs by lo. Constant bounds fold the length to a literal i64.
void test_SliceRangeFromSlice_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32[] foo(i32[] s) { return s[1..3]; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "getelementptr inbounds { ptr, i64 }"));
	TEST_ASSERT_NOT_NULL(strstr(output, "load ptr"));
	TEST_ASSERT_NOT_NULL(strstr(output, "getelementptr inbounds i32"));
	TEST_ASSERT_NOT_NULL(strstr(output, "i64 2, 1"));
	TEST_ASSERT_EQUAL_STRING("", error);
	free(error);
}

// Slice indexing is a single-index GEP into the loaded data pointer,
// distinct from the two-index `[0, i]` pattern arrays use. Reads emit
// `getelementptr inbounds i32, ptr ...` and a load of the element type.
void test_SliceIndexRead_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 foo(i32[] s) { return s[2]; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "getelementptr inbounds { ptr, i64 }"));
	TEST_ASSERT_NOT_NULL(strstr(output, "load ptr"));
	TEST_ASSERT_NOT_NULL(strstr(output, "getelementptr inbounds i32, ptr"));
	TEST_ASSERT_NOT_NULL(strstr(output, "load i32, ptr"));
	TEST_ASSERT_EQUAL_STRING("", error);
	free(error);
}

// Indexed slice writes use the same GEP shape as reads; the store lands
// on the element pointer, not on the slice header.
void test_SliceIndexWrite_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void foo(i32[] s) { s[1] = 42; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "getelementptr inbounds i32, ptr"));
	TEST_ASSERT_NOT_NULL(strstr(output, "store i32 42, ptr"));
	TEST_ASSERT_EQUAL_STRING("", error);
	free(error);
}

// `arr.len` for a fixed-size array folds to a compile-time `i64`
// constant — no load, no GEP, just the literal length.
void test_ArrayDotLen_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn u64 foo() { i32[5] a = [1,2,3,4,5]; return a.len; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "ret i64 5"));
	TEST_ASSERT_EQUAL_STRING("", error);
	free(error);
}

// `s.len` reads field 1 of the slice header. That's a struct-GEP + load
// — exactly the same shape as struct-field reads elsewhere.
void test_SliceDotLen_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn u64 foo(i32[] s) { return s.len; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "getelementptr inbounds { ptr, i64 }"));
	TEST_ASSERT_NOT_NULL(strstr(output, "i32 0, i32 1"));
	TEST_ASSERT_NOT_NULL(strstr(output, "load i64"));
	TEST_ASSERT_EQUAL_STRING("", error);
	free(error);
}

// End-to-end: decay an array into a slice, then read `.len` from the
// slice — the length should still be the array's original size.
void test_SliceDotLenAfterDecay_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn u64 foo() { i32[3] arr = [1,2,3]; i32[] s = arr; return s.len; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "insertvalue { ptr, i64 } %slice.ptr, i64 3, 1"));
	TEST_ASSERT_NOT_NULL(strstr(output, "getelementptr inbounds { ptr, i64 }"));
	TEST_ASSERT_EQUAL_STRING("", error);
	free(error);
}

void test_LocalArrayLiteralInit_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void foo() { u8[3] lit = [1, 2, 3]; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define void @__main_foo() {\n"
						   "entry:\n"
						   "  %__main_foo_lit = alloca [3 x i8], align 1\n"
						   "  %arrayinit.begin = getelementptr inbounds [3 x i8], ptr %__main_foo_lit, i64 0, i64 0\n"
						   "  store i8 1, ptr %arrayinit.begin, align 1\n"
						   "  %arrayinit.element = getelementptr inbounds i8, ptr %arrayinit.begin, i64 1\n"
						   "  store i8 2, ptr %arrayinit.element, align 1\n"
						   "  %arrayinit.element1 = getelementptr inbounds i8, ptr %arrayinit.element, i64 1\n"
						   "  store i8 3, ptr %arrayinit.element1, align 1\n"
						   "  ret void\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_LocalArrayLiteralInitWithVar_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void foo() { u8 a = 0; u8[3] lit = [a, 2, 3]; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define void @__main_foo() {\n"
						   "entry:\n"
						   "  %__main_foo_a = alloca i8, align 1\n"
						   "  store i8 0, ptr %__main_foo_a, align 1\n"
						   "  %__main_foo_lit = alloca [3 x i8], align 1\n"
						   "  %arrayinit.begin = getelementptr inbounds [3 x i8], ptr %__main_foo_lit, i64 0, i64 0\n"
						   "  %0 = load i8, ptr %__main_foo_a, align 1\n"
						   "  store i8 %0, ptr %arrayinit.begin, align 1\n"
						   "  %arrayinit.element = getelementptr inbounds i8, ptr %arrayinit.begin, i64 1\n"
						   "  store i8 2, ptr %arrayinit.element, align 1\n"
						   "  %arrayinit.element1 = getelementptr inbounds i8, ptr %arrayinit.element, i64 1\n"
						   "  store i8 3, ptr %arrayinit.element1, align 1\n"
						   "  ret void\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_LocalArrayLiteralNested_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void foo() { u8[3][2] lit = [[1, 2], [3, 4], [5, 6]]; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define void @__main_foo() {\n"
						   "entry:\n"
						   "  %__main_foo_lit = alloca [3 x [2 x i8]], align 1\n"
						   "  %arrayinit.begin = getelementptr inbounds [3 x [2 x i8]], ptr %__main_foo_lit, i64 0, i64 0\n"
						   "  %arrayinit.begin1 = getelementptr inbounds [2 x i8], ptr %arrayinit.begin, i64 0, i64 0\n"
						   "  store i8 1, ptr %arrayinit.begin1, align 1\n"
						   "  %arrayinit.element = getelementptr inbounds i8, ptr %arrayinit.begin1, i64 1\n"
						   "  store i8 2, ptr %arrayinit.element, align 1\n"
						   "  %arrayinit.element2 = getelementptr inbounds [2 x i8], ptr %arrayinit.begin, i64 1\n"
						   "  %arrayinit.begin3 = getelementptr inbounds [2 x i8], ptr %arrayinit.element2, i64 0, i64 0\n"
						   "  store i8 3, ptr %arrayinit.begin3, align 1\n"
						   "  %arrayinit.element4 = getelementptr inbounds i8, ptr %arrayinit.begin3, i64 1\n"
						   "  store i8 4, ptr %arrayinit.element4, align 1\n"
						   "  %arrayinit.element5 = getelementptr inbounds [2 x i8], ptr %arrayinit.element2, i64 1\n"
						   "  %arrayinit.begin6 = getelementptr inbounds [2 x i8], ptr %arrayinit.element5, i64 0, i64 0\n"
						   "  store i8 5, ptr %arrayinit.begin6, align 1\n"
						   "  %arrayinit.element7 = getelementptr inbounds i8, ptr %arrayinit.begin6, i64 1\n"
						   "  store i8 6, ptr %arrayinit.element7, align 1\n"
						   "  ret void\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_ArrayElementAccess_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32[3] lit = [1, 2, 3]; return lit[0]; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_lit = alloca [3 x i32], align 4\n"
						   "  %arrayinit.begin = getelementptr inbounds [3 x i32], ptr %__main_main_lit, i64 0, i64 0\n"
						   "  store i32 1, ptr %arrayinit.begin, align 4\n"
						   "  %arrayinit.element = getelementptr inbounds i32, ptr %arrayinit.begin, i64 1\n"
						   "  store i32 2, ptr %arrayinit.element, align 4\n"
						   "  %arrayinit.element1 = getelementptr inbounds i32, ptr %arrayinit.element, i64 1\n"
						   "  store i32 3, ptr %arrayinit.element1, align 4\n"
						   "  %arrgep = getelementptr inbounds [3 x i32], ptr %__main_main_lit, i64 0, i64 0\n"
						   "  %arrload = load i32, ptr %arrgep, align 4\n"
						   "  ret i32 %arrload\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_ArrayElementAccessFromVarIndex_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32 a = 0; i32[3] lit = [1, 2, 3]; return lit[a]; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_a, align 4\n"
						   "  %__main_main_lit = alloca [3 x i32], align 4\n"
						   "  %arrayinit.begin = getelementptr inbounds [3 x i32], ptr %__main_main_lit, i64 0, i64 0\n"
						   "  store i32 1, ptr %arrayinit.begin, align 4\n"
						   "  %arrayinit.element = getelementptr inbounds i32, ptr %arrayinit.begin, i64 1\n"
						   "  store i32 2, ptr %arrayinit.element, align 4\n"
						   "  %arrayinit.element1 = getelementptr inbounds i32, ptr %arrayinit.element, i64 1\n"
						   "  store i32 3, ptr %arrayinit.element1, align 4\n"
						   "  %0 = load i32, ptr %__main_main_a, align 4\n"
						   "  %idx64 = sext i32 %0 to i64\n"
						   "  %arrgep = getelementptr inbounds [3 x i32], ptr %__main_main_lit, i64 0, i64 %idx64\n"
						   "  %arrload = load i32, ptr %arrgep, align 4\n"
						   "  ret i32 %arrload\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_NestedArrayAccess_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32[3][2] lit = [[1, 2], [3, 4], [5, 6]]; return lit[0][1]; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_lit = alloca [3 x [2 x i32]], align 4\n"
						   "  %arrayinit.begin = getelementptr inbounds [3 x [2 x i32]], ptr %__main_main_lit, i64 0, i64 0\n"
						   "  %arrayinit.begin1 = getelementptr inbounds [2 x i32], ptr %arrayinit.begin, i64 0, i64 0\n"
						   "  store i32 1, ptr %arrayinit.begin1, align 4\n"
						   "  %arrayinit.element = getelementptr inbounds i32, ptr %arrayinit.begin1, i64 1\n"
						   "  store i32 2, ptr %arrayinit.element, align 4\n"
						   "  %arrayinit.element2 = getelementptr inbounds [2 x i32], ptr %arrayinit.begin, i64 1\n"
						   "  %arrayinit.begin3 = getelementptr inbounds [2 x i32], ptr %arrayinit.element2, i64 0, i64 0\n"
						   "  store i32 3, ptr %arrayinit.begin3, align 4\n"
						   "  %arrayinit.element4 = getelementptr inbounds i32, ptr %arrayinit.begin3, i64 1\n"
						   "  store i32 4, ptr %arrayinit.element4, align 4\n"
						   "  %arrayinit.element5 = getelementptr inbounds [2 x i32], ptr %arrayinit.element2, i64 1\n"
						   "  %arrayinit.begin6 = getelementptr inbounds [2 x i32], ptr %arrayinit.element5, i64 0, i64 0\n"
						   "  store i32 5, ptr %arrayinit.begin6, align 4\n"
						   "  %arrayinit.element7 = getelementptr inbounds i32, ptr %arrayinit.begin6, i64 1\n"
						   "  store i32 6, ptr %arrayinit.element7, align 4\n"
						   "  %arrgep = getelementptr inbounds [3 x [2 x i32]], ptr %__main_main_lit, i64 0, i64 0\n"
						   "  %arrgep8 = getelementptr inbounds [2 x i32], ptr %arrgep, i64 0, i64 1\n"
						   "  %arrload = load i32, ptr %arrgep8, align 4\n"
						   "  ret i32 %arrload\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_VoidFnCallNoParams_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void foo() {} fn i32 main() { foo(); return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define void @__main_foo() {\n"
						   "entry:\n"
						   "  ret void\n"
						   "}\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  call void @__main_foo()\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_VoidFnCallWithParams_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void foo(i32 a, i32 b) {} fn i32 main() { i32 a = 0; i32 b = 0; foo(a, b); return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define void @__main_foo__i32_i32(i32 %0, i32 %1) {\n"
						   "entry:\n"
						   "  %__main_foo__i32_i32_a = alloca i32, align 4\n"
						   "  store i32 %0, ptr %__main_foo__i32_i32_a, align 4\n"
						   "  %__main_foo__i32_i32_b = alloca i32, align 4\n"
						   "  store i32 %1, ptr %__main_foo__i32_i32_b, align 4\n"
						   "  ret void\n"
						   "}\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_a, align 4\n"
						   "  %__main_main_b = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_b, align 4\n"
						   "  %0 = load i32, ptr %__main_main_a, align 4\n"
						   "  %1 = load i32, ptr %__main_main_b, align 4\n"
						   "  call void @__main_foo__i32_i32(i32 %0, i32 %1)\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_NonVoidFnCallWithParams_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 foo(i32 a, i32 b) { return 5; } fn i32 main() { i32 a = 0; i32 b = 0; a = foo(a, b); return foo(a, b); }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @__main_foo__i32_i32(i32 %0, i32 %1) {\n"
						   "entry:\n"
						   "  %__main_foo__i32_i32_a = alloca i32, align 4\n"
						   "  store i32 %0, ptr %__main_foo__i32_i32_a, align 4\n"
						   "  %__main_foo__i32_i32_b = alloca i32, align 4\n"
						   "  store i32 %1, ptr %__main_foo__i32_i32_b, align 4\n"
						   "  ret i32 5\n"
						   "}\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_a, align 4\n"
						   "  %__main_main_b = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_b, align 4\n"
						   "  %0 = load i32, ptr %__main_main_a, align 4\n"
						   "  %1 = load i32, ptr %__main_main_b, align 4\n"
						   "  %calltmp = call i32 @__main_foo__i32_i32(i32 %0, i32 %1)\n"
						   "  store i32 %calltmp, ptr %__main_main_a, align 4\n"
						   "  %2 = load i32, ptr %__main_main_a, align 4\n"
						   "  %3 = load i32, ptr %__main_main_b, align 4\n"
						   "  %calltmp1 = call i32 @__main_foo__i32_i32(i32 %2, i32 %3)\n"
						   "  ret i32 %calltmp1\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_EnumVar_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("enum EnumType { First, Second = 234, Third, EVEN = Second } fn i32 main() { EnumType a = EnumType::Second; return a; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca i32, align 4\n"
						   "  store i32 234, ptr %__main_main_a, align 4\n"
						   "  %0 = load i32, ptr %__main_main_a, align 4\n"
						   "  ret i32 %0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_EnumValueReturn_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("enum EnumType { First, Second = 234, Third, EVEN = Second } fn i32 main() { return EnumType::Second; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  ret i32 234\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_ExternBlockFn_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("extern { fn void printf(const u8* str, ...); }"
							  "fn i32 main() { printf(\"hello world\"); return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "@.str = constant [12 x i8] c\"hello world\\00\", align 1\n\n"
						   "declare void @printf(ptr)\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  call void @printf(ptr @.str)\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_ExternBlockFnVa_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("extern { fn void printf(const u8* str, ...); }"
							  "fn i32 main() { i32 a = 1; printf(\"hello world %d\", a); return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "@.str = constant [15 x i8] c\"hello world %d\\00\", align 1\n\n"
						   "declare void @printf(ptr)\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca i32, align 4\n"
						   "  store i32 1, ptr %__main_main_a, align 4\n"
						   "  %0 = load i32, ptr %__main_main_a, align 4\n"
						   "  call void @printf(ptr @.str, i32 %0)\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_ForLoopConstComp_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("extern { fn void printf(const u8* str, ...); }"
							  "fn i32 main() { for(i32 i = 0; i < 10; i +=1 ){ printf(\"hello world %d\", i); } return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "@.str = constant [15 x i8] c\"hello world %d\\00\", align 1\n\n"
						   "declare void @printf(ptr)\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_i = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_i, align 4\n"
						   "  br label %forcond\n"
						   "\n"
						   "forcond:                                          ; preds = %forstep, %entry\n"
						   "  %0 = load i32, ptr %__main_main_i, align 4\n"
						   "  %cmplt = icmp slt i32 %0, 10\n"
						   "  br i1 %cmplt, label %forbody, label %forend\n"
						   "\n"
						   "forbody:                                          ; preds = %forcond\n"
						   "  %1 = load i32, ptr %__main_main_i, align 4\n"
						   "  call void @printf(ptr @.str, i32 %1)\n"
						   "  br label %forstep\n"
						   "\n"
						   "forstep:                                          ; preds = %forbody\n"
						   "  %2 = load i32, ptr %__main_main_i, align 4\n"
						   "  %add = add i32 %2, 1\n"
						   "  store i32 %add, ptr %__main_main_i, align 4\n"
						   "  br label %forcond\n"
						   "\n"
						   "forend:                                           ; preds = %forcond\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_ForLoopVarComp_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("extern { fn void printf(const u8* str, ...); }"
							  "fn i32 main() { i32 a = 10; for(i32 i = 0; i < a; i +=1 ){ printf(\"hello world %d\", i); } return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "@.str = constant [15 x i8] c\"hello world %d\\00\", align 1\n\n"
						   "declare void @printf(ptr)\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca i32, align 4\n"
						   "  store i32 10, ptr %__main_main_a, align 4\n"
						   "  %__main_main_i = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_i, align 4\n"
						   "  br label %forcond\n"
						   "\n"
						   "forcond:                                          ; preds = %forstep, %entry\n"
						   "  %0 = load i32, ptr %__main_main_i, align 4\n"
						   "  %1 = load i32, ptr %__main_main_a, align 4\n"
						   "  %cmplt = icmp slt i32 %0, %1\n"
						   "  br i1 %cmplt, label %forbody, label %forend\n"
						   "\n"
						   "forbody:                                          ; preds = %forcond\n"
						   "  %2 = load i32, ptr %__main_main_i, align 4\n"
						   "  call void @printf(ptr @.str, i32 %2)\n"
						   "  br label %forstep\n"
						   "\n"
						   "forstep:                                          ; preds = %forbody\n"
						   "  %3 = load i32, ptr %__main_main_i, align 4\n"
						   "  %add = add i32 %3, 1\n"
						   "  store i32 %add, ptr %__main_main_i, align 4\n"
						   "  br label %forcond\n"
						   "\n"
						   "forend:                                           ; preds = %forcond\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_WhileLoopBasicComp_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("extern { fn void printf(const u8* str, ...); }"
							  "fn i32 main() { i32 a = 0; while(a < 10){ printf(\"hello world %d\", a); a += 1; } return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "@.str = constant [15 x i8] c\"hello world %d\\00\", align 1\n\n"
						   "declare void @printf(ptr)\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_a, align 4\n"
						   "  br label %whilecond\n\nwhilecond:                                        ; preds = %whilebody, %entry\n"
						   "  %0 = load i32, ptr %__main_main_a, align 4\n"
						   "  %cmplt = icmp slt i32 %0, 10\n"
						   "  br i1 %cmplt, label %whilebody, label %whileend\n"
						   "\n"
						   "whilebody:                                        ; preds = %whilecond\n"
						   "  %1 = load i32, ptr %__main_main_a, align 4\n"
						   "  call void @printf(ptr @.str, i32 %1)\n"
						   "  %2 = load i32, ptr %__main_main_a, align 4\n"
						   "  %add = add i32 %2, 1\n"
						   "  store i32 %add, ptr %__main_main_a, align 4\n"
						   "  br label %whilecond\n"
						   "\n"
						   "whileend:                                         ; preds = %whilecond\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_WhileLoopVarComp_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("extern { fn void printf(const u8* str, ...); }"
							  "fn i32 main() { i32 a = 0; i32 b = 10; while(a < b){ printf(\"hello world %d\", a); a += 1; } return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "@.str = constant [15 x i8] c\"hello world %d\\00\", align 1\n\n"
						   "declare void @printf(ptr)\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_a, align 4\n"
						   "  %__main_main_b = alloca i32, align 4\n"
						   "  store i32 10, ptr %__main_main_b, align 4\n"
						   "  br label %whilecond\n"
						   "\n"
						   "whilecond:                                        ; preds = %whilebody, %entry\n"
						   "  %0 = load i32, ptr %__main_main_a, align 4\n"
						   "  %1 = load i32, ptr %__main_main_b, align 4\n"
						   "  %cmplt = icmp slt i32 %0, %1\n"
						   "  br i1 %cmplt, label %whilebody, label %whileend\n"
						   "\n"
						   "whilebody:                                        ; preds = %whilecond\n"
						   "  %2 = load i32, ptr %__main_main_a, align 4\n"
						   "  call void @printf(ptr @.str, i32 %2)\n"
						   "  %3 = load i32, ptr %__main_main_a, align 4\n"
						   "  %add = add i32 %3, 1\n"
						   "  store i32 %add, ptr %__main_main_a, align 4\n"
						   "  br label %whilecond\n"
						   "\n"
						   "whileend:                                         ; preds = %whilecond\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_IfStmtBasic_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("extern { fn void printf(const u8* str, ...); }"
							  "fn i32 main() { i32 a = 0; if(a){ printf(\"hello world %d\", a); } return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "@.str = constant [15 x i8] c\"hello world %d\\00\", align 1\n\n"
						   "declare void @printf(ptr)\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_a, align 4\n"
						   "  %0 = load i32, ptr %__main_main_a, align 4\n"
						   "  %tobool = icmp ne i32 %0, 0\n"
						   "  br i1 %tobool, label %then, label %ifcont\n"
						   "\n"
						   "then:                                             ; preds = %entry\n"
						   "  %1 = load i32, ptr %__main_main_a, align 4\n"
						   "  call void @printf(ptr @.str, i32 %1)\n"
						   "  br label %ifcont\n"
						   "\n"
						   "ifcont:                                           ; preds = %then, %entry\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_IfStmtInWhileLoop_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("extern { fn void printf(const u8* str, ...); }"
							  "fn i32 main() { i32 a = 0; while(a < 10) { if(a % 2 == 0){ printf(\"hello world %d\", a); } a += 1; } return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "@.str = constant [15 x i8] c\"hello world %d\\00\", align 1\n\n"
						   "declare void @printf(ptr)\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_a, align 4\n"
						   "  br label %whilecond\n"
						   "\n"
						   "whilecond:                                        ; preds = %ifcont, %entry\n"
						   "  %0 = load i32, ptr %__main_main_a, align 4\n"
						   "  %cmplt = icmp slt i32 %0, 10\n"
						   "  br i1 %cmplt, label %whilebody, label %whileend\n"
						   "\n"
						   "whilebody:                                        ; preds = %whilecond\n"
						   "  %1 = load i32, ptr %__main_main_a, align 4\n"
						   "  %rem = srem i32 %1, 2\n"
						   "  %2 = icmp eq i32 %rem, 0\n"
						   "  br i1 %2, label %then, label %ifcont\n"
						   "\n"
						   "whileend:                                         ; preds = %whilecond\n"
						   "  ret i32 0\n"
						   "\n"
						   "then:                                             ; preds = %whilebody\n"
						   "  %3 = load i32, ptr %__main_main_a, align 4\n"
						   "  call void @printf(ptr @.str, i32 %3)\n"
						   "  br label %ifcont\n"
						   "\n"
						   "ifcont:                                           ; preds = %then, %whilebody\n"
						   "  %4 = load i32, ptr %__main_main_a, align 4\n"
						   "  %add = add i32 %4, 1\n"
						   "  store i32 %add, ptr %__main_main_a, align 4\n"
						   "  br label %whilecond\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_IfElseStmtInWhileLoop_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("extern { fn void printf(const u8* str, ...); }"
							  "fn i32 main() { i32 a = 0; while(a < 10) { if(a % 2 == 0){ printf(\"hello world %d\", a); } else { printf(\"\n\"); } a += 1; } a = 50; return a; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "@.str = constant [15 x i8] c\"hello world %d\\00\", align 1\n"
						   "@.str.1 = constant [2 x i8] c\"\\0A\\00\", align 1\n\n"
						   "declare void @printf(ptr)\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_a, align 4\n"
						   "  br label %whilecond\n"
						   "\n"
						   "whilecond:                                        ; preds = %ifcont, %entry\n"
						   "  %0 = load i32, ptr %__main_main_a, align 4\n"
						   "  %cmplt = icmp slt i32 %0, 10\n"
						   "  br i1 %cmplt, label %whilebody, label %whileend\n"
						   "\n"
						   "whilebody:                                        ; preds = %whilecond\n"
						   "  %1 = load i32, ptr %__main_main_a, align 4\n"
						   "  %rem = srem i32 %1, 2\n"
						   "  %2 = icmp eq i32 %rem, 0\n"
						   "  br i1 %2, label %then, label %else\n"
						   "\n"
						   "whileend:                                         ; preds = %whilecond\n"
						   "  store i32 50, ptr %__main_main_a, align 4\n"
						   "  %3 = load i32, ptr %__main_main_a, align 4\n"
						   "  ret i32 %3\n"
						   "\n"
						   "then:                                             ; preds = %whilebody\n"
						   "  %4 = load i32, ptr %__main_main_a, align 4\n"
						   "  call void @printf(ptr @.str, i32 %4)\n"
						   "  br label %ifcont\n"
						   "\n"
						   "else:                                             ; preds = %whilebody\n"
						   "  call void @printf(ptr @.str.1)\n"
						   "  br label %ifcont\n"
						   "\n"
						   "ifcont:                                           ; preds = %else, %then\n"
						   "  %5 = load i32, ptr %__main_main_a, align 4\n"
						   "  %add = add i32 %5, 1\n"
						   "  store i32 %add, ptr %__main_main_a, align 4\n"
						   "  br label %whilecond\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_ExplicitCastIntToIntType_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32 a = 0; i64 b = (i64)a; i8 c = (i8)a; return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_a, align 4\n"
						   "  %__main_main_b = alloca i64, align 8\n"
						   "  %0 = load i32, ptr %__main_main_a, align 4\n"
						   "  %casttmp = sext i32 %0 to i64\n"
						   "  store i64 %casttmp, ptr %__main_main_b, align 8\n"
						   "  %__main_main_c = alloca i8, align 1\n"
						   "  %1 = load i32, ptr %__main_main_a, align 4\n"
						   "  %casttmp1 = trunc i32 %1 to i8\n"
						   "  store i8 %casttmp1, ptr %__main_main_c, align 1\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_ExplicitCastFloatToFloatType_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { f32 a = 0.0; f64 b = (f64)a; f32 c = (f32)b; return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca float, align 4\n"
						   "  store float 0.000000e+00, ptr %__main_main_a, align 4\n"
						   "  %__main_main_b = alloca double, align 8\n"
						   "  %0 = load float, ptr %__main_main_a, align 4\n"
						   "  %fpext = fpext float %0 to double\n"
						   "  store double %fpext, ptr %__main_main_b, align 8\n"
						   "  %__main_main_c = alloca float, align 4\n"
						   "  %1 = load double, ptr %__main_main_b, align 8\n"
						   "  %fptrunc = fptrunc double %1 to float\n"
						   "  store float %fptrunc, ptr %__main_main_c, align 4\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_ExplicitCastFloatToIntType_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { f32 a = 0.0; i64 b = (i64)a; f64 c = (f64)b; return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca float, align 4\n"
						   "  store float 0.000000e+00, ptr %__main_main_a, align 4\n"
						   "  %__main_main_b = alloca i64, align 8\n"
						   "  %0 = load float, ptr %__main_main_a, align 4\n"
						   "  %fptosi = fptosi float %0 to i64\n"
						   "  store i64 %fptosi, ptr %__main_main_b, align 8\n"
						   "  %__main_main_c = alloca double, align 8\n"
						   "  %1 = load i64, ptr %__main_main_b, align 4\n"
						   "  %sitofp = sitofp i64 %1 to double\n"
						   "  store double %sitofp, ptr %__main_main_c, align 8\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_ExplicitCastPtrToIntType_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i64 a = 0; i64* b = &a; i64 c = (i64)b; i32* d = (i32*)c; return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca i64, align 8\n"
						   "  store i64 0, ptr %__main_main_a, align 8\n"
						   "  %__main_main_b = alloca ptr, align 8\n"
						   "  store ptr %__main_main_a, ptr %__main_main_b, align 8\n"
						   "  %__main_main_c = alloca i64, align 8\n"
						   "  %0 = load ptr, ptr %__main_main_b, align 8\n"
						   "  %inttoptr = ptrtoint ptr %0 to i64\n"
						   "  store i64 %inttoptr, ptr %__main_main_c, align 8\n"
						   "  %__main_main_d = alloca ptr, align 8\n"
						   "  %1 = load i64, ptr %__main_main_c, align 4\n"
						   "  %ptrtoint = inttoptr i64 %1 to ptr\n"
						   "  store ptr %ptrtoint, ptr %__main_main_d, align 8\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_ExplicitCastPtrToPtr_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("struct TestStruct1 { i32 a; } struct TestStruct2 { f64 b; }"
							  "fn i32 main() { TestStruct1* ts1; TestStruct2* ts2 = (TestStruct1*)ts1; return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_ts1 = alloca ptr, align 8\n"
						   "  %__main_main_ts2 = alloca ptr, align 8\n"
						   "  %0 = load ptr, ptr %__main_main_ts1, align 8\n"
						   "  store ptr %0, ptr %__main_main_ts2, align 8\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_ExplicitCastPtrToPtrWithAddressOf_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("struct TestStruct1 { i32 a; } struct TestStruct2 { f64 b; }"
							  "fn i32 main() { TestStruct1 ts1; TestStruct2* ts2 = (TestStruct1*)&ts1; return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%__main_TestStruct1 = type { i32 }\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_ts1 = alloca %__main_TestStruct1, align 8\n"
						   "  %__main_main_ts2 = alloca ptr, align 8\n"
						   "  store ptr %__main_main_ts1, ptr %__main_main_ts2, align 8\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_WhileLoopContinueBreak_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("extern { fn void printf(const u8* str, ...); }"
							  "fn i32 main() {"
							  " i32 a = 0;"
							  " while(a < 10) {"
							  " 	if(a % 2 == 0) {"
							  "			printf(\"even\n\"); a += 1; continue;"
							  "		}"
							  "		if(a >= 7){"
							  "			printf(\"more than 7\n\"); break;"
							  "		}"
							  "		printf(\"odd\n\"); a += 1;"
							  "	}"
							  "return 0;"
							  "}");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "@.str = constant [6 x i8] c\"even\\0A\\00\", align 1\n"
						   "@.str.1 = constant [13 x i8] c\"more than 7\\0A\\00\", align 1\n"
						   "@.str.2 = constant [5 x i8] c\"odd\\0A\\00\", align 1\n\n"
						   "declare void @printf(ptr)\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_a, align 4\n"
						   "  br label %whilecond\n"
						   "\n"
						   "whilecond:                                        ; preds = %ifcont2, %then, %entry\n"
						   "  %0 = load i32, ptr %__main_main_a, align 4\n"
						   "  %cmplt = icmp slt i32 %0, 10\n  br i1 %cmplt, label %whilebody, label %whileend\n"
						   "\n"
						   "whilebody:                                        ; preds = %whilecond\n"
						   "  %1 = load i32, ptr %__main_main_a, align 4\n"
						   "  %rem = srem i32 %1, 2\n"
						   "  %2 = icmp eq i32 %rem, 0\n"
						   "  br i1 %2, label %then, label %ifcont\n"
						   "\n"
						   "whileend:                                         ; preds = %then1, %whilecond\n"
						   "  ret i32 0\n"
						   "\n"
						   "then:                                             ; preds = %whilebody\n"
						   "  call void @printf(ptr @.str)\n"
						   "  %3 = load i32, ptr %__main_main_a, align 4\n"
						   "  %add = add i32 %3, 1\n"
						   "  store i32 %add, ptr %__main_main_a, align 4\n"
						   "  br label %whilecond\n"
						   "\n"
						   "ifcont:                                           ; preds = %whilebody\n"
						   "  %4 = load i32, ptr %__main_main_a, align 4\n"
						   "  %cmpge = icmp sge i32 %4, 7\n"
						   "  br i1 %cmpge, label %then1, label %ifcont2\n"
						   "\n"
						   "then1:                                            ; preds = %ifcont\n"
						   "  call void @printf(ptr @.str.1)\n"
						   "  br label %whileend\n"
						   "\n"
						   "ifcont2:                                          ; preds = %ifcont\n"
						   "  call void @printf(ptr @.str.2)\n"
						   "  %5 = load i32, ptr %__main_main_a, align 4\n"
						   "  %add3 = add i32 %5, 1\n"
						   "  store i32 %add3, ptr %__main_main_a, align 4\n"
						   "  br label %whilecond\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_ForLoopContinueBreak_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("extern { fn void printf(const u8* str, ...); }"
							  "fn i32 main() {"
							  " for(i32 a = 0; a < 10; a += 1) {"
							  " 	if(a % 2 == 0) {"
							  "			printf(\"even\n\"); continue;"
							  "		}"
							  "		if(a >= 7){"
							  "			printf(\"more than 7\n\"); break;"
							  "		}"
							  "		printf(\"odd\n\");"
							  "	}"
							  "return 0;"
							  "}");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "@.str = constant [6 x i8] c\"even\\0A\\00\", align 1\n"
						   "@.str.1 = constant [13 x i8] c\"more than 7\\0A\\00\", align 1\n"
						   "@.str.2 = constant [5 x i8] c\"odd\\0A\\00\", align 1\n\n"
						   "declare void @printf(ptr)\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_a, align 4\n"
						   "  br label %forcond\n"
						   "\n"
						   "forcond:                                          ; preds = %forstep, %entry\n"
						   "  %0 = load i32, ptr %__main_main_a, align 4\n"
						   "  %cmplt = icmp slt i32 %0, 10\n"
						   "  br i1 %cmplt, label %forbody, label %forend\n"
						   "\n"
						   "forbody:                                          ; preds = %forcond\n"
						   "  %1 = load i32, ptr %__main_main_a, align 4\n"
						   "  %rem = srem i32 %1, 2\n"
						   "  %2 = icmp eq i32 %rem, 0\n"
						   "  br i1 %2, label %then, label %ifcont\n"
						   "\n"
						   "forstep:                                          ; preds = %ifcont2, %then\n"
						   "  %3 = load i32, ptr %__main_main_a, align 4\n"
						   "  %add = add i32 %3, 1\n"
						   "  store i32 %add, ptr %__main_main_a, align 4\n"
						   "  br label %forcond\n"
						   "\n"
						   "forend:                                           ; preds = %then1, %forcond\n"
						   "  ret i32 0\n"
						   "\n"
						   "then:                                             ; preds = %forbody\n"
						   "  call void @printf(ptr @.str)\n"
						   "  br label %forstep\n"
						   "\n"
						   "ifcont:                                           ; preds = %forbody\n"
						   "  %4 = load i32, ptr %__main_main_a, align 4\n"
						   "  %cmpge = icmp sge i32 %4, 7\n"
						   "  br i1 %cmpge, label %then1, label %ifcont2\n"
						   "\n"
						   "then1:                                            ; preds = %ifcont\n"
						   "  call void @printf(ptr @.str.1)\n"
						   "  br label %forend\n"
						   "\n"
						   "ifcont2:                                          ; preds = %ifcont\n"
						   "  call void @printf(ptr @.str.2)\n"
						   "  br label %forstep\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_UnionDecl_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("union TestUnion { i32 a; i64 b; } "
							  "fn i32 main() { TestUnion ts; return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%union.__main_TestUnion = type { i64 }\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_ts = alloca %union.__main_TestUnion, align 8\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_UnionMemberAccess_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("union TestUnion { i32 a; i64 b; } "
							  "fn i32 main() { TestUnion ts; ts.a = 50; return ts.a; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%union.__main_TestUnion = type { i64 }\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_ts = alloca %union.__main_TestUnion, align 8\n"
						   "  store i32 50, ptr %__main_main_ts, align 4\n"
						   "  %0 = load i32, ptr %__main_main_ts, align 4\n"
						   "  ret i32 %0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_NestedIfs_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32 a = 0; if(a) { i32 b = 1; if(b) { return 2; } } return 1;}");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_main_a, align 4\n"
						   "  %0 = load i32, ptr %__main_main_a, align 4\n"
						   "  %tobool = icmp ne i32 %0, 0\n"
						   "  br i1 %tobool, label %then, label %ifcont\n"
						   "\n"
						   "then:                                             ; preds = %entry\n"
						   "  %__main_main_b = alloca i32, align 4\n"
						   "  store i32 1, ptr %__main_main_b, align 4\n"
						   "  %1 = load i32, ptr %__main_main_b, align 4\n"
						   "  %tobool1 = icmp ne i32 %1, 0\n"
						   "  br i1 %tobool1, label %then2, label %ifcont\n"
						   "\n"
						   "ifcont:                                           ; preds = %then, %entry\n"
						   "  ret i32 1\n"
						   "\n"
						   "then2:                                            ; preds = %then\n"
						   "  ret i32 2\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_NullLiteralVarInit_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void foo() { i32* p = null; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define void @__main_foo() {\n"
						   "entry:\n"
						   "  %__main_foo_p = alloca ptr, align 8\n"
						   "  store ptr null, ptr %__main_foo_p, align 8\n"
						   "  ret void\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_NullLiteralReturn_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32* foo() { return null; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define ptr @__main_foo() {\n"
						   "entry:\n"
						   "  ret ptr null\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_NullLiteralCompareEq_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32* p = null; if (p == null) { return 1; } return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_p = alloca ptr, align 8\n"
						   "  store ptr null, ptr %__main_main_p, align 8\n"
						   "  %0 = load ptr, ptr %__main_main_p, align 8\n"
						   "  %1 = icmp eq ptr %0, null\n"
						   "  br i1 %1, label %then, label %ifcont\n"
						   "\n"
						   "then:                                             ; preds = %entry\n"
						   "  ret i32 1\n"
						   "\n"
						   "ifcont:                                           ; preds = %entry\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_PointerTruthyIfStillEmits_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { i32* p = null; if (p) { return 1; } return 0; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_main_p = alloca ptr, align 8\n"
						   "  store ptr null, ptr %__main_main_p, align 8\n"
						   "  %0 = load ptr, ptr %__main_main_p, align 8\n"
						   "  %tobool = icmp ne ptr %0, null\n"
						   "  br i1 %tobool, label %then, label %ifcont\n"
						   "\n"
						   "then:                                             ; preds = %entry\n"
						   "  ret i32 1\n"
						   "\n"
						   "ifcont:                                           ; preds = %entry\n"
						   "  ret i32 0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_FunctionOverload_FnPointer_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void foo(){}"
							  "fn void foo(i32 x){}"
							  "fn i32 main() {"
							  "    fn* void(i32) f = &foo;"
							  "    f(0);"
							  "    return 0;"
							  "}");
	const char *expected_call = "call void %0(i32 0)";
	const char *expected_store = "store ptr @__main_foo__i32";
	TEST_ASSERT_NOT_NULL(strstr(output, expected_call));
	TEST_ASSERT_NOT_NULL(strstr(output, expected_store));
	free(error);
}

void test_FunctionOverload_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("struct S {i32 i;}"
							  "fn void foo(){}"
							  "fn void foo(i32 i){ foo(); }"
							  "fn void foo(i32* p_i){ foo(*p_i); }"
							  "fn void foo(i32** p_p_i){ foo(*p_p_i); }"
							  "fn void foo(S s){ foo(s.i); }"
							  "fn void foo(S* p_s){ foo(*p_s); }"
							  "fn void foo(S** p_p_s){ foo(*p_p_s); }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%__main_S = type { i32 }\n\n"
						   "define void @__main_foo() {\n"
						   "entry:\n"
						   "  ret void\n"
						   "}\n"
						   "\n"
						   "define void @__main_foo__i32(i32 %0) {\n"
						   "entry:\n"
						   "  %__main_foo__i32_i = alloca i32, align 4\n"
						   "  store i32 %0, ptr %__main_foo__i32_i, align 4\n"
						   "  call void @__main_foo()\n"
						   "  ret void\n"
						   "}\n"
						   "\n"
						   "define void @\"__main_foo__i32*\"(ptr %0) {\n"
						   "entry:\n"
						   "  %\"__main_foo__i32*_p_i\" = alloca ptr, align 8\n"
						   "  store ptr %0, ptr %\"__main_foo__i32*_p_i\", align 8\n"
						   "  %1 = load ptr, ptr %\"__main_foo__i32*_p_i\", align 8\n"
						   "  %deref = load i32, ptr %1, align 4\n"
						   "  call void @__main_foo__i32(i32 %deref)\n"
						   "  ret void\n"
						   "}\n"
						   "\n"
						   "define void @\"__main_foo__i32**\"(ptr %0) {\n"
						   "entry:\n"
						   "  %\"__main_foo__i32**_p_p_i\" = alloca ptr, align 8\n"
						   "  store ptr %0, ptr %\"__main_foo__i32**_p_p_i\", align 8\n"
						   "  %1 = load ptr, ptr %\"__main_foo__i32**_p_p_i\", align 8\n"
						   "  %deref = load ptr, ptr %1, align 8\n"
						   "  call void @\"__main_foo__i32*\"(ptr %deref)\n"
						   "  ret void\n"
						   "}\n"
						   "\n"
						   "define void @__main_foo____main_S(%__main_S %0) {\n"
						   "entry:\n"
						   "  %__main_foo____main_S_s = alloca %__main_S, align 8\n"
						   "  store %__main_S %0, ptr %__main_foo____main_S_s, align 4\n"
						   "  %i = getelementptr inbounds %__main_S, ptr %__main_foo____main_S_s, i32 0, i32 0\n"
						   "  %1 = load i32, ptr %i, align 4\n"
						   "  call void @__main_foo__i32(i32 %1)\n"
						   "  ret void\n"
						   "}\n"
						   "\n"
						   "define void @\"__main_foo____main_S*\"(ptr %0) {\n"
						   "entry:\n"
						   "  %\"__main_foo____main_S*_p_s\" = alloca ptr, align 8\n"
						   "  store ptr %0, ptr %\"__main_foo____main_S*_p_s\", align 8\n"
						   "  %1 = load ptr, ptr %\"__main_foo____main_S*_p_s\", align 8\n"
						   "  %deref = load %__main_S, ptr %1, align 4\n"
						   "  call void @__main_foo____main_S(%__main_S %deref)\n"
						   "  ret void\n"
						   "}\n"
						   "\n"
						   "define void @\"__main_foo____main_S**\"(ptr %0) {\n"
						   "entry:\n"
						   "  %\"__main_foo____main_S**_p_p_s\" = alloca ptr, align 8\n"
						   "  store ptr %0, ptr %\"__main_foo____main_S**_p_p_s\", align 8\n"
						   "  %1 = load ptr, ptr %\"__main_foo____main_S**_p_p_s\", align 8\n"
						   "  %deref = load ptr, ptr %1, align 8\n"
						   "  call void @\"__main_foo____main_S*\"(ptr %deref)\n"
						   "  ret void\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}
#define EXH_TEST_SETUP(input_string)                                                                                                                                                                                                              \
	const char *input = input_string;                                                                                                                                                                                                              \
	const char *path = "exhaustive_tests.sl";                                                                                                                                                                                                      \
	Scanner scanner;                                                                                                                                                                                                                               \
	scanner_init_from_string(&scanner, path, input);                                                                                                                                                                                               \
	Parser parser;                                                                                                                                                                                                                                 \
	FILE *old_stderr = capture_error_begin();                                                                                                                                                                                                      \
	parser_init(&parser, scanner, NULL);                                                                                                                                                                                                           \
	Module *module = parse_input(&parser);                                                                                                                                                                                                         \
	int parse_ok = (module && !module->has_errors);                                                                                                                                                                                                \
	int sema_ok = 1;                                                                                                                                                                                                                               \
	char *output = NULL;                                                                                                                                                                                                                           \
	CodegenLLVM cg_ctx;                                                                                                                                                                                                                            \
	if (parse_ok) {                                                                                                                                                                                                                                \
		symbol_table_set_type_info(module->symbol_table);                                                                                                                                                                                          \
		for (ASTNode *node = module->ast; node != NULL; node = node->next) {                                                                                                                                                                       \
			sema_ok &= analyze_ast(module->symbol_table, node, 0, "") == RESULT_SUCCESS;                                                                                                                                                           \
			sema_ok &= resolve_types(module->symbol_table, node, 1) == RESULT_SUCCESS;                                                                                                                                                             \
		}                                                                                                                                                                                                                                          \
		if (sema_ok) {                                                                                                                                                                                                                             \
			CodegenInitContext cg_init_ctx = {"test", "test", ".", 0};                                                                                                                                                                             \
			cg_ctx = codegen_init(&cg_init_ctx);                                                                                                                                                                                                   \
			codegen_run(&cg_ctx, module->ast, module->symbol_table);                                                                                                                                                                               \
			output = codegen_output_str(&cg_ctx);                                                                                                                                                                                                  \
		}                                                                                                                                                                                                                                          \
	}                                                                                                                                                                                                                                              \
	char *captured_err = capture_error_end(old_stderr)

#define EXH_TEST_TEARDOWN()                                                                                                                                                                                                                       \
	do {                                                                                                                                                                                                                                           \
		if (output) {                                                                                                                                                                                                                              \
			codegen_deinit(&cg_ctx);                                                                                                                                                                                                               \
		}                                                                                                                                                                                                                                          \
		free(captured_err);                                                                                                                                                                                                                        \
	} while (0)

#define EXH_REQUIRE_OK()                                                                                                                                                                                                                          \
	do {                                                                                                                                                                                                                                           \
		if (!parse_ok)                                                                                                                                                                                                                             \
			TEST_FAIL_MESSAGE("parse failed");                                                                                                                                                                                                     \
		if (!sema_ok)                                                                                                                                                                                                                              \
			TEST_FAIL_MESSAGE(captured_err);                                                                                                                                                                                                       \
	} while (0)

// ---------------------------------------------------------------------------
// 1. Built-in primitive types: globals (no init) emit `zeroinitializer`
//    constants of the natural type.
// ---------------------------------------------------------------------------

void test_GlobalNoInit_AllIntWidths_codegen(void) {
	EXH_TEST_SETUP("i8 a; i16 b; i32 c; i64 d; u8 e; u16 f; u32 g; u64 h;");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "@__main_a = global i8 0"));
	TEST_ASSERT_NOT_NULL(strstr(output, "@__main_b = global i16 0"));
	TEST_ASSERT_NOT_NULL(strstr(output, "@__main_c = global i32 0"));
	TEST_ASSERT_NOT_NULL(strstr(output, "@__main_d = global i64 0"));
	TEST_ASSERT_NOT_NULL(strstr(output, "@__main_e = global i8 0"));
	TEST_ASSERT_NOT_NULL(strstr(output, "@__main_f = global i16 0"));
	TEST_ASSERT_NOT_NULL(strstr(output, "@__main_g = global i32 0"));
	TEST_ASSERT_NOT_NULL(strstr(output, "@__main_h = global i64 0"));
	EXH_TEST_TEARDOWN();
}

void test_GlobalNoInit_FloatWidths_codegen(void) {
	EXH_TEST_SETUP("f32 a; f64 b;");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "@__main_a = global float 0.000000e+00"));
	TEST_ASSERT_NOT_NULL(strstr(output, "@__main_b = global double 0.000000e+00"));
	EXH_TEST_TEARDOWN();
}

void test_GlobalNoInit_PointerIsNull_codegen(void) {
	EXH_TEST_SETUP("i32* p; u8** pp;");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "@__main_p = global ptr null"));
	TEST_ASSERT_NOT_NULL(strstr(output, "@__main_pp = global ptr null"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 2. Integer literals: decimal, hex, binary. Sign-extended into the
//    declared type.
// ---------------------------------------------------------------------------

void test_LiteralHex_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 0xDEAD_BEEF; return a; }");
	EXH_REQUIRE_OK();
	// 0xDEADBEEF as i32 is -559038737 in signed two's complement.
	TEST_ASSERT_NOT_NULL(strstr(output, "store i32 -559038737"));
	EXH_TEST_TEARDOWN();
}

void test_LiteralBinary_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 0b1010; return a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "store i32 10"));
	EXH_TEST_TEARDOWN();
}

void test_LiteralBinaryWithUnderscore_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 0b1010_1010; return a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "store i32 170"));
	EXH_TEST_TEARDOWN();
}

void test_LiteralHexWithUnderscore_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 0xDEAD_BEEF; return a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "store i32 -559038737"));
	EXH_TEST_TEARDOWN();
}

void test_DecimalUnderscoreSeparator_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 1_000_000; return a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "store i32 1000000"));
	EXH_TEST_TEARDOWN();
}

void test_U64MaxLiteral_codegen(void) {
	EXH_TEST_SETUP("fn u64 foo() { u64 a = 0xFFFFFFFFFFFFFFFF; return a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "store i64 -1"));
	EXH_TEST_TEARDOWN();
}

void test_LiteralNegativeI8_codegen(void) {
	EXH_TEST_SETUP("fn i8 foo() { i8 a = -128; return a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "store i8 -128"));
	EXH_TEST_TEARDOWN();
}

void test_LiteralUnsignedU8_HighBitSet_codegen(void) {
	EXH_TEST_SETUP("fn u8 foo() { u8 a = 255; return a; }");
	EXH_REQUIRE_OK();
	// 255 reinterpreted as i8 is -1 (the printer always uses signed).
	TEST_ASSERT_NOT_NULL(strstr(output, "store i8 -1"));
	EXH_TEST_TEARDOWN();
}

void test_LiteralBool_codegen(void) {
	EXH_TEST_SETUP("fn bool foo() { bool a = true; bool b = false; return a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "store i1 true"));
	TEST_ASSERT_NOT_NULL(strstr(output, "store i1 false"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 3. Char literals.
// ---------------------------------------------------------------------------

void test_CharLiteralBasic_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { u8 c = 'A'; return 0; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "store i8 65"));
	EXH_TEST_TEARDOWN();
}

void test_CharLiteralEscapeNewline_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { u8 c = '\\n'; return 0; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "store i8 10"));
	EXH_TEST_TEARDOWN();
}

void test_CharLiteralEscapeTab_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { u8 c = '\\t'; return 0; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "store i8 9"));
	EXH_TEST_TEARDOWN();
}

void test_CharLiteralEscapeNul_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { u8 c = '\\0'; return 0; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "store i8 0"));
	EXH_TEST_TEARDOWN();
}

void test_CharLiteralEscapeBackslash_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { u8 c = '\\\\'; return 0; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "store i8 92"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 4. Float literals and arithmetic.
// ---------------------------------------------------------------------------

void test_LiteralF64_codegen(void) {
	EXH_TEST_SETUP("fn f64 foo() { f64 a = 3.14; return a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "store double 3.140000e+00"));
	EXH_TEST_TEARDOWN();
}

void test_FloatAdd_codegen(void) {
	EXH_TEST_SETUP("fn f32 foo() { f32 a = 4.0; f32 b = 2.0; return a + b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "fadd float"));
	EXH_TEST_TEARDOWN();
}

void test_FloatSub_codegen(void) {
	EXH_TEST_SETUP("fn f32 foo() { f32 a = 4.0; f32 b = 2.0; return a - b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "fsub float"));
	EXH_TEST_TEARDOWN();
}

void test_FloatMul_codegen(void) {
	EXH_TEST_SETUP("fn f32 foo() { f32 a = 4.0; f32 b = 2.0; return a * b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "fmul float"));
	EXH_TEST_TEARDOWN();
}

void test_FloatDiv_codegen(void) {
	EXH_TEST_SETUP("fn f32 foo() { f32 a = 4.0; f32 b = 2.0; return a / b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "fdiv float"));
	EXH_TEST_TEARDOWN();
}

void test_FloatNeg_codegen(void) {
	EXH_TEST_SETUP("fn f32 foo() { f32 a = 1.0; return -a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "fneg float"));
	EXH_TEST_TEARDOWN();
}

void test_FloatCmp_codegen(void) {
	EXH_TEST_SETUP("fn bool foo() { f32 a = 1.0; f32 b = 2.0; return a < b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "fcmp olt float"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 5. Integer arithmetic — correct cases.
// ---------------------------------------------------------------------------

void test_IntAdd_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 1; i32 b = 2; return a + b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%add = add i32"));
	EXH_TEST_TEARDOWN();
}

void test_IntSub_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 1; i32 b = 2; return a - b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%sub = sub i32"));
	EXH_TEST_TEARDOWN();
}

void test_IntMul_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 2; i32 b = 3; return a * b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%mul = mul i32"));
	EXH_TEST_TEARDOWN();
}

void test_SignedDiv_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 10; i32 b = 3; return a / b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%div = sdiv i32"));
	EXH_TEST_TEARDOWN();
}

void test_SignedMod_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 10; i32 b = 3; return a % b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%rem = srem i32"));
	EXH_TEST_TEARDOWN();
}

void test_UnsignedDiv_codegen(void) {
	EXH_TEST_SETUP("fn u32 main() { u32 a = 10; u32 b = 3; return a / b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "udiv i32"));
	EXH_TEST_TEARDOWN();
}

void test_UnsignedMod_codegen(void) {
	EXH_TEST_SETUP("fn u32 main() { u32 a = 10; u32 b = 3; return a % b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "urem i32"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 6. Bitwise and shift ops.
// ---------------------------------------------------------------------------

void test_BitwiseAnd_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 7; i32 b = 5; return a & b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%and = and i32"));
	EXH_TEST_TEARDOWN();
}

void test_BitwiseOr_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 1; i32 b = 2; return a | b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%or = or i32"));
	EXH_TEST_TEARDOWN();
}

void test_BitwiseXor_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 1; i32 b = 2; return a ^ b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%xor = xor i32"));
	EXH_TEST_TEARDOWN();
}

void test_LeftShift_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 1; return a << 4; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%shl = shl i32"));
	EXH_TEST_TEARDOWN();
}

void test_SignedRightShift_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = -16; return a >> 2; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%shr = ashr i32"));
	EXH_TEST_TEARDOWN();
}

void test_UnsignedRShift_codegen(void) {
	EXH_TEST_SETUP("fn u32 main() { u32 a = 16; return a >> 2; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "lshr i32"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 7. Comparisons.
// ---------------------------------------------------------------------------

void test_SignedLT_codegen(void) {
	EXH_TEST_SETUP("fn bool main() { i32 a = 1; i32 b = 2; return a < b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%cmplt = icmp slt i32"));
	EXH_TEST_TEARDOWN();
}

void test_SignedLE_codegen(void) {
	EXH_TEST_SETUP("fn bool main() { i32 a = 1; i32 b = 2; return a <= b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%cmple = icmp sle i32"));
	EXH_TEST_TEARDOWN();
}

void test_SignedGT_codegen(void) {
	EXH_TEST_SETUP("fn bool main() { i32 a = 1; i32 b = 2; return a > b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%cmpgt = icmp sgt i32"));
	EXH_TEST_TEARDOWN();
}

void test_SignedGE_codegen(void) {
	EXH_TEST_SETUP("fn bool main() { i32 a = 1; i32 b = 2; return a >= b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%cmpge = icmp sge i32"));
	EXH_TEST_TEARDOWN();
}

void test_UnsignedCmp_codegen(void) {
	EXH_TEST_SETUP("fn bool main() { u32 a = 1; u32 b = 2; return a < b; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "icmp ult i32"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 8. Logical ops — CODEGEN_BUGS.md §7. `&&` / `||` crash with
//    `Unknown binary op` assert. No pinning test (assertion abort
//    can't be caught from unity).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 9. Compound assignment.
// ---------------------------------------------------------------------------

void test_SelfOr_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 1; a |= 8; return a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%or = or i32"));
	EXH_TEST_TEARDOWN();
}

void test_SelfAnd_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 7; a &= 3; return a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%and = and i32"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 10. Unary expressions.
// ---------------------------------------------------------------------------

void test_UnaryIntNeg_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 5; return -a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%negtmp = sub i32 0,"));
	EXH_TEST_TEARDOWN();
}

void test_UnaryBitwiseNot_i32_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 0; return ~a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%lnot = xor i32"));
	TEST_ASSERT_NOT_NULL(strstr(output, ", -1"));
	EXH_TEST_TEARDOWN();
}

void test_UnaryLogicalNot_OnInt_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 1; if (!a) { return 1; } return 0; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "icmp ne i32"));
	TEST_ASSERT_NOT_NULL(strstr(output, "nottmp = xor i1"));
	EXH_TEST_TEARDOWN();
}

void test_UnaryLogicalNot_OnPointer_codegen(void) {
	EXH_TEST_SETUP("fn bool main() { i32* p = null; return !p; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "icmp ne ptr"));
	TEST_ASSERT_NOT_NULL(strstr(output, "nottmp = xor i1"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 11. Pointer ops. CODEGEN_BUGS.md §15 — writing through a pointer
//    `*p = v;` crashes the codegen assertion. Spec says deref is a
//    valid l-value.
// ---------------------------------------------------------------------------

void test_PointerAddressOfThenDeref_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 v = 7; i32* p = &v; return *p; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "alloca ptr"));
	TEST_ASSERT_NOT_NULL(strstr(output, "%deref = load i32"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 12. Casts. The four valid cast shapes from SPEC §2.10.
// ---------------------------------------------------------------------------

void test_CastIntWidening_codegen(void) {
	EXH_TEST_SETUP("fn i64 main() { i32 a = 1; return (i64)a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "sext i32"));
	EXH_TEST_TEARDOWN();
}

void test_CastIntNarrowing_codegen(void) {
	EXH_TEST_SETUP("fn i8 main() { i32 a = 1; return (i8)a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "trunc i32"));
	EXH_TEST_TEARDOWN();
}

void test_CastFloatWidening_codegen(void) {
	EXH_TEST_SETUP("fn f64 main() { f32 a = 1.0; return (f64)a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "fpext float"));
	EXH_TEST_TEARDOWN();
}

void test_CastFloatNarrowing_codegen(void) {
	EXH_TEST_SETUP("fn f32 main() { f64 a = 1.0; return (f32)a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "fptrunc double"));
	EXH_TEST_TEARDOWN();
}

void test_CastFloatToInt_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { f32 a = 1.5; return (i32)a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "fptosi float"));
	EXH_TEST_TEARDOWN();
}

void test_CastIntToFloat_codegen(void) {
	EXH_TEST_SETUP("fn f32 main() { i32 a = 5; return (f32)a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "sitofp i32"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 13. Enum codegen — `EnumType::Member` literally resolves to its
//    integer value at the expression site.
// ---------------------------------------------------------------------------

void test_EnumImplicitBaseValue_codegen(void) {
	EXH_TEST_SETUP("enum E { A, B, C } fn i32 main() { return E::C; }");
	EXH_REQUIRE_OK();
	// A=0, B=1, C=2 with implicit i32 base.
	TEST_ASSERT_NOT_NULL(strstr(output, "ret i32 2"));
	EXH_TEST_TEARDOWN();
}

void test_EnumExplicitU8Base_codegen(void) {
	EXH_TEST_SETUP("enum E : u8 { A, B } fn i32 main() { E e = E::B; return 0; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "alloca i8"));
	TEST_ASSERT_NOT_NULL(strstr(output, "store i8 1"));
	EXH_TEST_TEARDOWN();
}

void test_EnumExplicitJump_codegen(void) {
	EXH_TEST_SETUP("enum E { A, B = 5, C } fn i32 main() { return E::C; }");
	EXH_REQUIRE_OK();
	// B=5 explicitly, C auto-increments → 6.
	TEST_ASSERT_NOT_NULL(strstr(output, "ret i32 6"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 14. Struct literals and member access.
// ---------------------------------------------------------------------------

void test_StructDeclLayout_codegen(void) {
	EXH_TEST_SETUP("struct S { i32 a; i32 b; }"
				   "fn i32 main() { S s; return 0; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "%__main_S = type { i32, i32 }"));
	TEST_ASSERT_NOT_NULL(strstr(output, "alloca %__main_S"));
	EXH_TEST_TEARDOWN();
}

void test_StructLiteralAllDesignated_codegen(void) {
	EXH_TEST_SETUP("struct S { i32 a; i32 b; }"
				   "fn i32 main() { S s = {.b = 4, .a = 3}; return s.a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "store i32 3,"));
	TEST_ASSERT_NOT_NULL(strstr(output, "store i32 4,"));
	EXH_TEST_TEARDOWN();
}

void test_StructPassedByValue_codegen(void) {
	EXH_TEST_SETUP("struct S { i32 a; i32 b; }"
				   "fn i32 foo(S s) { return s.a + s.b; }"
				   "fn i32 main() { S x = {3, 4}; return foo(x); }");
	EXH_REQUIRE_OK();
	// The struct is loaded as a single aggregate value at the call
	// site and passed to the parameter slot. (Stage 1's SysV-ABI
	// fidelity is best-effort; this just asserts the shape, not the
	// exact ABI lowering.)
	TEST_ASSERT_NOT_NULL(strstr(output, "load %__main_S, ptr %__main_main_x"));
	TEST_ASSERT_NOT_NULL(strstr(output, "call i32 @__main_foo____main_S(%__main_S"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 15. Union codegen — laid out as a struct of just the largest member.
// ---------------------------------------------------------------------------

void test_UnionDeclLayout_codegen(void) {
	EXH_TEST_SETUP("union U { i32 a; i64 b; }"
				   "fn i32 main() { U u; return 0; }");
	EXH_REQUIRE_OK();
	// The union picks the widest field (i64) for its storage.
	TEST_ASSERT_NOT_NULL(strstr(output, "%union.__main_U = type { i64 }"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 16. Arrays.
// ---------------------------------------------------------------------------

void test_ArrayLiteralStorage_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32[3] arr = [10, 20, 30]; return arr[0]; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "alloca [3 x i32]"));
	TEST_ASSERT_NOT_NULL(strstr(output, "store i32 10"));
	TEST_ASSERT_NOT_NULL(strstr(output, "store i32 20"));
	TEST_ASSERT_NOT_NULL(strstr(output, "store i32 30"));
	EXH_TEST_TEARDOWN();
}

void test_ArrayElementWriteAndRead_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32[2] arr; arr[0] = 1; arr[1] = arr[0]; return arr[1]; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "store i32 1, ptr %arrgep"));
	TEST_ASSERT_NOT_NULL(strstr(output, "load i32, ptr %arrgep"));
	EXH_TEST_TEARDOWN();
}

void test_ArrayLenIsCompileTimeConstant_codegen(void) {
	EXH_TEST_SETUP("fn u64 main() { i32[5] arr = [1,2,3,4,5]; return arr.len; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "ret i64 5"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 17. Function declarations / calls.
// ---------------------------------------------------------------------------

void test_MainNotMangled_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { return 0; }");
	EXH_REQUIRE_OK();
	// `main` is the program entry; its name must NOT be mangled.
	TEST_ASSERT_NOT_NULL(strstr(output, "define i32 @main()"));
	TEST_ASSERT_NULL(strstr(output, "@__main_main()"));
	EXH_TEST_TEARDOWN();
}

void test_FnMangledByModuleAndParams_codegen(void) {
	EXH_TEST_SETUP("fn i32 add(i32 a, i32 b) { return a + b; }"
				   "fn i32 main() { return add(1, 2); }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "define i32 @__main_add__i32_i32(i32 %0, i32 %1)"));
	TEST_ASSERT_NOT_NULL(strstr(output, "call i32 @__main_add__i32_i32"));
	EXH_TEST_TEARDOWN();
}

void test_VoidFunction_codegen(void) {
	EXH_TEST_SETUP("fn void foo() {} fn i32 main() { foo(); return 0; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "define void @__main_foo()"));
	TEST_ASSERT_NOT_NULL(strstr(output, "ret void"));
	TEST_ASSERT_NOT_NULL(strstr(output, "call void @__main_foo()"));
	EXH_TEST_TEARDOWN();
}

void test_ChainedFnCalls_codegen(void) {
	EXH_TEST_SETUP("fn i32 a() { return 1; }"
				   "fn i32 b() { return a(); }"
				   "fn i32 main() { return b(); }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "call i32 @__main_a()"));
	TEST_ASSERT_NOT_NULL(strstr(output, "call i32 @__main_b()"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 18. Extern blocks.
// ---------------------------------------------------------------------------

void test_ExternFnDeclaresUnmangled_codegen(void) {
	EXH_TEST_SETUP("extern { fn i32 puts(const u8* s); }"
				   "fn i32 main() { return puts(\"hi\"); }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "declare i32 @puts(ptr)"));
	TEST_ASSERT_NOT_NULL(strstr(output, "call i32 @puts(ptr"));
	EXH_TEST_TEARDOWN();
}

void test_MultipleStringLiteralsGetSuffixedNames_codegen(void) {
	EXH_TEST_SETUP("extern { fn i32 puts(const u8* s); }"
				   "fn i32 main() { puts(\"hi\"); puts(\"bye\"); return 0; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "@.str = constant [3 x i8] c\"hi\\00\""));
	TEST_ASSERT_NOT_NULL(strstr(output, "@.str.1 = constant [4 x i8] c\"bye\\00\""));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 19. Control flow — if / else / while / for.
// ---------------------------------------------------------------------------

void test_IfEmptyThenAndElse_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 1; if (a) {} else {} return 0; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "br i1 %tobool, label %then, label %else"));
	TEST_ASSERT_NOT_NULL(strstr(output, "then:"));
	TEST_ASSERT_NOT_NULL(strstr(output, "else:"));
	TEST_ASSERT_NOT_NULL(strstr(output, "ifcont:"));
	EXH_TEST_TEARDOWN();
}

void test_NestedWhileLoops_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() {"
				   "  i32 a = 0; i32 b = 0;"
				   "  while (a < 2) { while (b < 2) { b += 1; } a += 1; }"
				   "  return a; }");
	EXH_REQUIRE_OK();
	// The outer and inner condition blocks both exist and don't share
	// names.
	TEST_ASSERT_NOT_NULL(strstr(output, "whilecond:"));
	TEST_ASSERT_NOT_NULL(strstr(output, "whilecond1:"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 20. Defer. Defer at function-block level inlines before returns; the
//    inside-loop case is broken (CODEGEN_BUGS.md §12).
// ---------------------------------------------------------------------------

void test_DeferAtFnEnd_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 0; defer { a = 99; } return a; }");
	EXH_REQUIRE_OK();
	// Defer runs before the return — the assignment goes ahead of the
	// load that feeds `ret`.
	const char *store = strstr(output, "store i32 99, ptr %__main_main_a");
	const char *load = strstr(output, "load i32, ptr %__main_main_a");
	TEST_ASSERT_NOT_NULL(store);
	TEST_ASSERT_NOT_NULL(load);
	TEST_ASSERT_TRUE_MESSAGE(store < load, "defer body must run before the final load that feeds the return");
	EXH_TEST_TEARDOWN();
}

void test_DeferAcrossEarlyReturn_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 0; defer { a = 1; } if (a) { return 5; } return a; }");
	EXH_REQUIRE_OK();
	// The defer body is inlined into BOTH the early-return path and
	// the natural end of the function. Both blocks should contain the
	// `store i32 1` for `a = 1;`.
	const char *first = strstr(output, "store i32 1, ptr %__main_main_a");
	TEST_ASSERT_NOT_NULL(first);
	const char *second = strstr(first + 1, "store i32 1, ptr %__main_main_a");
	TEST_ASSERT_NOT_NULL_MESSAGE(second, "defer body must be inlined at every exit path");
	EXH_TEST_TEARDOWN();
}

void test_DeferInForBody_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() {"
				   "  i32 a = 0;"
				   "  for (i32 i = 0; i < 3; i += 1) { defer { a = 1; } }"
				   "  return a;"
				   "}");
	EXH_REQUIRE_OK();
	const char *body = strstr(output, "forbody:");
	TEST_ASSERT_NOT_NULL(body);
	const char *step = strstr(body, "forstep:");
	TEST_ASSERT_NOT_NULL(step);
	char between[2048];
	size_t len = (size_t)(step - body);
	if (len >= sizeof(between))
		len = sizeof(between) - 1;
	memcpy(between, body, len);
	between[len] = '\0';
	TEST_ASSERT_NOT_NULL(strstr(between, "store i32 1, ptr %__main_main_a"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 21. Stray-branch-after-`ret` bug. The forbody emits `ret i32 0`
//    followed by `br label %forstep` — invalid LLVM IR (two terminators
//    in one block).
// ---------------------------------------------------------------------------

void test_ForBodyReturnNoStrayBr_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() {"
				   "  for (i32 i = 0; i < 1; i += 1) { return 0; }"
				   "  return 0;"
				   "}");
	EXH_REQUIRE_OK();
	const char *body = strstr(output, "forbody:");
	TEST_ASSERT_NOT_NULL(body);
	const char *next_block = strstr(body, "forstep:");
	TEST_ASSERT_NOT_NULL(next_block);
	const char *ret_inst = strstr(body, "ret i32 0");
	TEST_ASSERT_NOT_NULL(ret_inst);
	TEST_ASSERT_TRUE(ret_inst < next_block);
	char between[1024];
	size_t len = (size_t)(next_block - ret_inst);
	if (len >= sizeof(between))
		len = sizeof(between) - 1;
	memcpy(between, ret_inst, len);
	between[len] = '\0';
	TEST_ASSERT_NULL(strstr(between, "br label %forstep"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 22. Parser bugs reachable from codegen-shaped programs.
// ---------------------------------------------------------------------------

// CODEGEN_BUGS.md §11 — `(a)` and `(a + b)` are misparsed as
// `(typename) ...` casts because `is_type_spec` claims every
// identifier is a type. Use a fragment that makes the misparse loud.
void test_ParenExprWithIdent_pinning_CODEGEN_BUGS_11_codegen(void) {
	TEST_IGNORE_MESSAGE("disabled: parser hangs on `(a + b)`.");
}

// CODEGEN_BUGS.md §14 — naked `{ ... }` blocks at statement position
// are not parseable. Spec lists `block` as a statement form.
void test_NakedBlockStmt_pinning_CODEGEN_BUGS_14_codegen(void) {
	TEST_IGNORE_MESSAGE("disabled: parser hangs on naked `{...}`.");
}

void test_PointerWrite_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 v = 5; i32* p = &v; *p = 10; return v; }");
	EXH_REQUIRE_OK();
	const char *load_p = strstr(output, "load ptr, ptr %__main_main_p");
	TEST_ASSERT_NOT_NULL(load_p);
	TEST_ASSERT_NOT_NULL(strstr(load_p, "store i32 10, ptr"));
	EXH_TEST_TEARDOWN();
}

void test_PointerDotMember_codegen(void) {
	EXH_TEST_SETUP("struct S { i32 a; }"
				   "fn i32 main() { S x = {3}; S* p = &x; return p.a; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "getelementptr inbounds %__main_S"));
	EXH_TEST_TEARDOWN();
}

void test_ForEmptyAll_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { for(;;){ return 0; } return 1; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "forcond:"));
	TEST_ASSERT_NOT_NULL(strstr(output, "br label %forbody"));
	EXH_TEST_TEARDOWN();
}

void test_ForEmptyStep_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { for(i32 i = 0; i < 1;) { return 0; } return 1; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "forstep:"));
	EXH_TEST_TEARDOWN();
}

// CODEGEN_BUGS.md §19 — returning a struct by value is rejected at
// parse time because the parser doesn't accept a user-typed name in
// the return-type slot in this position.
void test_FnReturnsStructByValue_pinning_CODEGEN_BUGS_19_codegen(void) {
	TEST_IGNORE_MESSAGE("disabled: parser hangs on `fn S make()`.");
}

// ---------------------------------------------------------------------------
// 23. `null` literal — pinned across the three usage sites.
// ---------------------------------------------------------------------------

void test_NullAsParameter_codegen(void) {
	EXH_TEST_SETUP("fn void take(i32* p) {}"
				   "fn i32 main() { take(null); return 0; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "call void @\"__main_take__i32*\"(ptr null)"));
	EXH_TEST_TEARDOWN();
}

void test_NullReassign_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32* p = null; p = null; return 0; }");
	EXH_REQUIRE_OK();
	// Two stores: the init, then the reassignment.
	const char *first = strstr(output, "store ptr null, ptr %__main_main_p");
	TEST_ASSERT_NOT_NULL(first);
	const char *second = strstr(first + 1, "store ptr null, ptr %__main_main_p");
	TEST_ASSERT_NOT_NULL(second);
	EXH_TEST_TEARDOWN();
}

void test_NullCompareNotEq_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32* p = null; if (p != null) { return 1; } return 0; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "icmp ne ptr"));
	TEST_ASSERT_NOT_NULL(strstr(output, ", null"));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 24. String literal lowering. `"…"` becomes a global byte array with
//    the trailing NUL and `align 1`; use sites pass `ptr` to the
//    callee.
// ---------------------------------------------------------------------------

void test_StringLiteralEscapeSequences_codegen(void) {
	EXH_TEST_SETUP("extern { fn i32 puts(const u8* s); }"
				   "fn i32 main() { return puts(\"a\\nb\"); }");
	EXH_REQUIRE_OK();
	// `\n` inside a string literal IS decoded (the string-literal path
	// in the scanner handles escapes correctly — only char literals
	// don't). Expect the byte `\0A` in the constant array.
	TEST_ASSERT_NOT_NULL(strstr(output, "c\"a\\0Ab\\00\""));
	EXH_TEST_TEARDOWN();
}

// ---------------------------------------------------------------------------
// 25. Short-circuit `&&` and `||` lowering.
// ---------------------------------------------------------------------------

void test_LogicalAndShortCircuit_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 1; i32 b = 2; if (a < b && b > 0) { return 1; } return 0; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "land.rhs"));
	TEST_ASSERT_NOT_NULL(strstr(output, "land.end"));
	TEST_ASSERT_NOT_NULL(strstr(output, "%land = phi i1"));
	EXH_TEST_TEARDOWN();
}

void test_LogicalOrShortCircuit_codegen(void) {
	EXH_TEST_SETUP("fn i32 main() { i32 a = 1; i32 b = 2; if (a < b || b > 0) { return 1; } return 0; }");
	EXH_REQUIRE_OK();
	TEST_ASSERT_NOT_NULL(strstr(output, "lor.rhs"));
	TEST_ASSERT_NOT_NULL(strstr(output, "lor.end"));
	TEST_ASSERT_NOT_NULL(strstr(output, "%lor = phi i1"));
	EXH_TEST_TEARDOWN();
}
