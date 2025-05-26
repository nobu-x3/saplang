#pragma once
#include "test_util.h"
#include "unity_internals.h"
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
							   "define void @some_func() {\n"
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
							   "@i = global float 0.000000e+00\n";
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
							   "@i = global float 1.000000e+00\n";
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
							   "@i = constant float 1.000000e+00\n";
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
						   "%TestStruct = type { i32, float }\n\n"
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
						   "%TestStruct = type { i32, float, i64 }\n\n"
						   "@str = global %TestStruct { i32 0, float 0x4009C28F60000000, i64 1337 }\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_ConstGlobalStructDeclInit_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("struct TestStruct { i32 first; f32 second; i64 third; } const TestStruct str = {.second = 3.22, 1337}; ");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "%TestStruct = type { i32, float, i64 }\n\n"
						   "@str = constant %TestStruct { i32 0, float 0x4009C28F60000000, i64 1337 }\n";
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
						   "define void @some_func() {\n"
						   "entry:\n"
						   "  %__some_func_i = alloca i32, align 4\n"
						   "  store i32 3, ptr %__some_func_i, align 4\n"
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
						   "define void @some_func() {\n"
						   "entry:\n"
						   "  %__some_func_a = alloca i32, align 4\n"
						   "  %__some_func_i = alloca i32, align 4\n"
						   "  store ptr %__some_func_a, ptr %__some_func_i, align 8\n"
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
						   "define void @some_func() {\n"
						   "entry:\n"
						   "  %__some_func_i = alloca i32, align 4\n"
						   "  store i32 3, ptr %__some_func_i, align 4\n"
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
						   "define void @some_func() {\n"
						   "entry:\n"
						   "  %__some_func_i = alloca i32, align 4\n"
						   "  %__some_func_a = alloca i32, align 4\n"
						   "  %0 = load i32, ptr %__some_func_a, align 4\n"
						   "  store i32 %0, ptr %__some_func_i, align 4\n"
						   "  ret void\n"
						   "}\n";
	;
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_LocalVarReassignmentToGlobalVar_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("i32 a; fn void some_func() { i32 i; i = a; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "@a = global i32 0\n\n"
						   "define void @some_func() {\n"
						   "entry:\n"
						   "  %__some_func_i = alloca i32, align 4\n"
						   "  store ptr @a, ptr %__some_func_i, align 8\n"
						   "  ret void\n"
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
						   "@a = global i32 0\n\n"
						   "define void @some_func() {\n"
						   "entry:\n"
						   "  store i32 3, ptr @a, align 4\n"
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
						   "@a = global i32 0\n"
						   "@i = global i32 0\n\n"
						   "define void @some_func() {\n"
						   "entry:\n"
						   "  store ptr @a, ptr @i, align 8\n"
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
						   "@i = global i32 0\n\n"
						   "define void @some_func() {\n"
						   "entry:\n"
						   "  %__some_func_a = alloca i32, align 4\n"
						   "  %0 = load i32, ptr %__some_func_a, align 4\n"
						   "  store i32 %0, ptr @i, align 4\n"
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
						   "%TestStruct = type { i32, float }\n\n"
						   "define void @foo() {\n"
						   "entry:\n"
						   "  %__foo_str = alloca %TestStruct, align 8\n"
						   "  %gep_0__foo_str = getelementptr inbounds %TestStruct, ptr %__foo_str, i32 0, i32 0\n"
						   "  store i32 3, ptr %gep_0__foo_str, align 4\n"
						   "  %gep_1__foo_str = getelementptr inbounds %TestStruct, ptr %__foo_str, i32 0, i32 1\n"
						   "  store float 4.000000e+00, ptr %gep_1__foo_str, align 4\n"
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
						   "%TestStruct = type { i32, float }\n\n"
						   "define void @foo() {\n"
						   "entry:\n"
						   "  %__foo_str = alloca %TestStruct, align 8\n"
						   "  %gep_0__foo_str = getelementptr inbounds %TestStruct, ptr %__foo_str, i32 0, i32 0\n"
						   "  store i32 0, ptr %gep_0__foo_str, align 4\n"
						   "  %gep_1__foo_str = getelementptr inbounds %TestStruct, ptr %__foo_str, i32 0, i32 1\n"
						   "  store float 0.000000e+00, ptr %gep_1__foo_str, align 4\n"
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
						   "%TestStruct = type { i32, float }\n\n"
						   "define void @foo() {\n"
						   "entry:\n"
						   "  %__foo_str = alloca %TestStruct, align 8\n"
						   "  %gep_0__foo_str = getelementptr inbounds %TestStruct, ptr %__foo_str, i32 0, i32 0\n"
						   "  store i32 1, ptr %gep_0__foo_str, align 4\n"
						   "  %gep_1__foo_str = getelementptr inbounds %TestStruct, ptr %__foo_str, i32 0, i32 1\n"
						   "  store float 1.000000e+00, ptr %gep_1__foo_str, align 4\n"
						   "  %gep_0__foo_str1 = getelementptr inbounds %TestStruct, ptr %__foo_str, i32 0, i32 0\n"
						   "  store i32 0, ptr %gep_0__foo_str1, align 4\n"
						   "  %gep_1__foo_str2 = getelementptr inbounds %TestStruct, ptr %__foo_str, i32 0, i32 1\n"
						   "  store float 0.000000e+00, ptr %gep_1__foo_str2, align 4\n"
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
						   "%TestStruct = type { i32, float }\n\n"
						   "define void @foo() {\n"
						   "entry:\n"
						   "  %__foo_str = alloca %TestStruct, align 8\n"
						   "  %first = getelementptr inbounds %TestStruct, ptr %__foo_str, i32 0, i32 0\n"
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
						   "%TestStruct2 = type { %TestStruct }\n"
						   "%TestStruct = type { i32, float }\n\n"
						   "define void @foo() {\n"
						   "entry:\n"
						   "  %__foo_str = alloca %TestStruct2, align 8\n"
						   "  %nest = getelementptr inbounds %TestStruct2, ptr %__foo_str, i32 0, i32 0\n"
						   "  %first = getelementptr inbounds %TestStruct, ptr %nest, i32 0, i32 0\n"
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
						   "%TestStr = type { i32 }\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_a = alloca %TestStr, align 8\n"
						   "  %gep_0__main_a = getelementptr inbounds %TestStr, ptr %__main_a, i32 0, i32 0\n"
						   "  store i32 8, ptr %gep_0__main_a, align 4\n"
						   "  %__main_b = alloca %TestStr, align 8\n"
						   "  %first = getelementptr inbounds %TestStr, ptr %__main_b, i32 0, i32 0\n"
						   "  %first1 = getelementptr inbounds %TestStr, ptr %__main_a, i32 0, i32 0\n"
						   "  %0 = load i32, ptr %first1, align 4\n"
						   "  store i32 %0, ptr %first, align 4\n"
						   "  %first2 = getelementptr inbounds %TestStr, ptr %__main_b, i32 0, i32 0\n"
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
						   "  %__main_a = alloca i32, align 4\n"
						   "  store i32 8, ptr %__main_a, align 4\n"
						   "  %0 = load i32, ptr %__main_a, align 4\n"
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
						   "%TestStr = type { i32 }\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_a = alloca %TestStr, align 8\n"
						   "  %gep_0__main_a = getelementptr inbounds %TestStr, ptr %__main_a, i32 0, i32 0\n"
						   "  store i32 8, ptr %gep_0__main_a, align 4\n"
						   "  %first = getelementptr inbounds %TestStr, ptr %__main_a, i32 0, i32 0\n"
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
						   "%TestStr2 = type { %TestStr }\n"
						   "%TestStr = type { i32 }\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_str = alloca %TestStr2, align 8\n"
						   "  %tmp_inner_str = alloca %TestStr, align 8\n"
						   "  %gep_0 = getelementptr inbounds %TestStr, ptr %tmp_inner_str, i32 0, i32 0\n"
						   "  store i32 8, ptr %gep_0, align 4\n"
						   "  %inner_struct_val = load %TestStr, ptr %tmp_inner_str, align 4\n"
						   "  %gep_0__main_str = getelementptr inbounds %TestStr2, ptr %__main_str, i32 0, i32 0\n"
						   "  store %TestStr %inner_struct_val, ptr %gep_0__main_str, align 4\n"
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
						   "%TestStr2 = type { %TestStr }\n"
						   "%TestStr = type { i32 }\n"
						   "\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_a = alloca %TestStr2, align 8\n"
						   "  %tmp_inner_str = alloca %TestStr, align 8\n"
						   "  %gep_0 = getelementptr inbounds %TestStr, ptr %tmp_inner_str, i32 0, i32 0\n"
						   "  store i32 8, ptr %gep_0, align 4\n"
						   "  %inner_struct_val = load %TestStr, ptr %tmp_inner_str, align 4\n"
						   "  %gep_0__main_a = getelementptr inbounds %TestStr2, ptr %__main_a, i32 0, i32 0\n"
						   "  store %TestStr %inner_struct_val, ptr %gep_0__main_a, align 4\n"
						   "  %nest = getelementptr inbounds %TestStr2, ptr %__main_a, i32 0, i32 0\n"
						   "  %first = getelementptr inbounds %TestStr, ptr %nest, i32 0, i32 0\n"
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
						   "  %__main_a = alloca i32, align 4\n"
						   "  store i32 5, ptr %__main_a, align 4\n"
						   "  %__main_b = alloca i32, align 4\n"
						   "  %0 = load i32, ptr %__main_a, align 4\n"
						   "  %negtmp = sub i32 0, %0\n"
						   "  store i32 %negtmp, ptr %__main_b, align 4\n"
						   "  %1 = load i32, ptr %__main_b, align 4\n"
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
						   "  %__main_f = alloca i1, align 1\n"
						   "  store i1 true, ptr %__main_f, align 1\n"
						   "  %__main_g = alloca i1, align 1\n"
						   "  %0 = load i1, ptr %__main_f, align 1\n"
						   "  %nottmp = xor i1 %0, true\n"
						   "  store i1 %nottmp, ptr %__main_g, align 1\n"
						   "  %1 = load i1, ptr %__main_g, align 1\n"
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
						   "  %__main_v = alloca i32, align 4\n"
						   "  store i32 42, ptr %__main_v, align 4\n"
						   "  %__main_p = alloca ptr, align 8\n"
						   "  store ptr %__main_v, ptr %__main_p, align 8\n"
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
						   "  %__main_v = alloca i32, align 4\n"
						   "  store i32 7, ptr %__main_v, align 4\n"
						   "  %__main_p = alloca ptr, align 8\n"
						   "  store ptr %__main_v, ptr %__main_p, align 8\n"
						   "  %__main_u = alloca i32, align 4\n"
						   "  %0 = load ptr, ptr %__main_p, align 8\n"
						   "  %deref = load i32, ptr %0, align 4\n"
						   "  store i32 %deref, ptr %__main_u, align 4\n"
						   "  %1 = load i32, ptr %__main_u, align 4\n"
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
						   "  %__main_x = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_x, align 4\n"
						   "  %__main_y = alloca i32, align 4\n"
						   "  %0 = load i32, ptr %__main_x, align 4\n"
						   "  %lnot = xor i32 %0, -1\n"
						   "  store i32 %lnot, ptr %__main_y, align 4\n"
						   "  %1 = load i32, ptr %__main_y, align 4\n"
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
						   "  %__main_x = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_x, align 4\n"
						   "  %__main_y = alloca i32, align 4\n"
						   "  store i32 1, ptr %__main_y, align 4\n"
						   "  %0 = load i32, ptr %__main_y, align 4\n"
						   "  %1 = load i32, ptr %__main_x, align 4\n"
						   "  %add = add i32 %0, %1\n"
						   "  store i32 %add, ptr %__main_y, align 4\n"
						   "  %2 = load i32, ptr %__main_y, align 4\n"
						   "  %add1 = add i32 %2, 1\n"
						   "  store i32 %add1, ptr %__main_y, align 4\n"
						   "  %3 = load i32, ptr %__main_y, align 4\n"
						   "  %add2 = add i32 1, %3\n"
						   "  store i32 %add2, ptr %__main_y, align 4\n"
						   "  %4 = load i32, ptr %__main_y, align 4\n"
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
						   "  %__main_x = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_x, align 4\n"
						   "  %__main_y = alloca i32, align 4\n"
						   "  store i32 1, ptr %__main_y, align 4\n"
						   "  %0 = load i32, ptr %__main_y, align 4\n"
						   "  %1 = load i32, ptr %__main_x, align 4\n"
						   "  %sub = sub i32 %0, %1\n"
						   "  store i32 %sub, ptr %__main_y, align 4\n"
						   "  %2 = load i32, ptr %__main_y, align 4\n"
						   "  %sub1 = sub i32 %2, 1\n"
						   "  store i32 %sub1, ptr %__main_y, align 4\n"
						   "  %3 = load i32, ptr %__main_y, align 4\n"
						   "  %sub2 = sub i32 1, %3\n"
						   "  store i32 %sub2, ptr %__main_y, align 4\n"
						   "  %4 = load i32, ptr %__main_y, align 4\n"
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
						   "define float @foo() {\n"
						   "entry:\n"
						   "  %__foo_x = alloca float, align 4\n"
						   "  store float 4.000000e+00, ptr %__foo_x, align 4\n"
						   "  %__foo_y = alloca float, align 4\n"
						   "  store float 2.000000e+00, ptr %__foo_y, align 4\n"
						   "  %0 = load float, ptr %__foo_x, align 4\n"
						   "  %1 = load float, ptr %__foo_y, align 4\n"
						   "  %div = sdiv float %0, %1\n"
						   "  store float %div, ptr %__foo_y, align 4\n"
						   "  %2 = load float, ptr %__foo_y, align 4\n"
						   "  %div1 = sdiv float %2, 1.000000e+00\n"
						   "  store float %div1, ptr %__foo_y, align 4\n"
						   "  %3 = load float, ptr %__foo_y, align 4\n"
						   "  %div2 = sdiv float 1.000000e+00, %3\n"
						   "  store float %div2, ptr %__foo_y, align 4\n"
						   "  %4 = load float, ptr %__foo_y, align 4\n"
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
						   "  %__main_x = alloca i32, align 4\n"
						   "  store i32 4, ptr %__main_x, align 4\n"
						   "  %__main_y = alloca i32, align 4\n"
						   "  store i32 2, ptr %__main_y, align 4\n"
						   "  %0 = load i32, ptr %__main_x, align 4\n"
						   "  %1 = load i32, ptr %__main_y, align 4\n"
						   "  %mul = mul i32 %0, %1\n"
						   "  store i32 %mul, ptr %__main_y, align 4\n"
						   "  %2 = load i32, ptr %__main_y, align 4\n"
						   "  %mul1 = mul i32 %2, 1\n"
						   "  store i32 %mul1, ptr %__main_y, align 4\n"
						   "  %3 = load i32, ptr %__main_y, align 4\n"
						   "  %mul2 = mul i32 1, %3\n"
						   "  store i32 %mul2, ptr %__main_y, align 4\n"
						   "  %4 = load i32, ptr %__main_y, align 4\n"
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
						   "  %__main_x = alloca i32, align 4\n"
						   "  store i32 4, ptr %__main_x, align 4\n"
						   "  %__main_y = alloca i32, align 4\n"
						   "  store i32 2, ptr %__main_y, align 4\n"
						   "  %0 = load i32, ptr %__main_x, align 4\n"
						   "  %1 = load i32, ptr %__main_y, align 4\n"
						   "  %rem = srem i32 %0, %1\n"
						   "  store i32 %rem, ptr %__main_y, align 4\n"
						   "  %2 = load i32, ptr %__main_y, align 4\n"
						   "  %rem1 = srem i32 %2, 1\n"
						   "  store i32 %rem1, ptr %__main_y, align 4\n"
						   "  %3 = load i32, ptr %__main_y, align 4\n"
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
						   "  %__main_x = alloca i32, align 4\n"
						   "  store i32 1, ptr %__main_x, align 4\n"
						   "  %__main_y = alloca i32, align 4\n"
						   "  store i32 1, ptr %__main_y, align 4\n"
						   "  %0 = load i32, ptr %__main_y, align 4\n"
						   "  %1 = load i32, ptr %__main_x, align 4\n"
						   "  %add = add i32 %0, %1\n"
						   "  store i32 %add, ptr %__main_y, align 4\n"
						   "  %2 = load i32, ptr %__main_y, align 4\n"
						   "  %add1 = add i32 %2, 1\n"
						   "  store i32 %add1, ptr %__main_y, align 4\n"
						   "  %3 = load i32, ptr %__main_y, align 4\n"
						   "  %4 = load i32, ptr %__main_y, align 4\n"
						   "  %add2 = add i32 %3, %4\n"
						   "  store i32 %add2, ptr %__main_y, align 4\n"
						   "  %5 = load i32, ptr %__main_y, align 4\n"
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
						   "  %__main_x = alloca i32, align 4\n"
						   "  store i32 1, ptr %__main_x, align 4\n"
						   "  %__main_y = alloca i32, align 4\n"
						   "  store i32 10, ptr %__main_y, align 4\n"
						   "  %0 = load i32, ptr %__main_y, align 4\n"
						   "  %1 = load i32, ptr %__main_x, align 4\n"
						   "  %sub = sub i32 %0, %1\n"
						   "  store i32 %sub, ptr %__main_y, align 4\n"
						   "  %2 = load i32, ptr %__main_y, align 4\n"
						   "  %sub1 = sub i32 %2, 1\n"
						   "  store i32 %sub1, ptr %__main_y, align 4\n"
						   "  %3 = load i32, ptr %__main_y, align 4\n"
						   "  %4 = load i32, ptr %__main_y, align 4\n"
						   "  %sub2 = sub i32 %3, %4\n"
						   "  store i32 %sub2, ptr %__main_y, align 4\n"
						   "  %5 = load i32, ptr %__main_y, align 4\n"
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
						   "  %__main_x = alloca i32, align 4\n"
						   "  store i32 2, ptr %__main_x, align 4\n"
						   "  %__main_y = alloca i32, align 4\n"
						   "  store i32 10, ptr %__main_y, align 4\n"
						   "  %0 = load i32, ptr %__main_y, align 4\n"
						   "  %1 = load i32, ptr %__main_x, align 4\n"
						   "  %mul = mul i32 %0, %1\n"
						   "  store i32 %mul, ptr %__main_y, align 4\n"
						   "  %2 = load i32, ptr %__main_y, align 4\n"
						   "  %mul1 = mul i32 %2, 1\n"
						   "  store i32 %mul1, ptr %__main_y, align 4\n"
						   "  %3 = load i32, ptr %__main_y, align 4\n"
						   "  %4 = load i32, ptr %__main_y, align 4\n"
						   "  %mul2 = mul i32 %3, %4\n"
						   "  store i32 %mul2, ptr %__main_y, align 4\n"
						   "  %5 = load i32, ptr %__main_y, align 4\n"
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
						   "  %__main_x = alloca i32, align 4\n"
						   "  store i32 2, ptr %__main_x, align 4\n"
						   "  %__main_y = alloca i32, align 4\n"
						   "  store i32 10, ptr %__main_y, align 4\n"
						   "  %0 = load i32, ptr %__main_y, align 4\n"
						   "  %1 = load i32, ptr %__main_x, align 4\n"
						   "  %div = sdiv i32 %0, %1\n"
						   "  store i32 %div, ptr %__main_y, align 4\n"
						   "  %2 = load i32, ptr %__main_y, align 4\n"
						   "  %div1 = sdiv i32 %2, 1\n"
						   "  store i32 %div1, ptr %__main_y, align 4\n"
						   "  %3 = load i32, ptr %__main_y, align 4\n"
						   "  %4 = load i32, ptr %__main_y, align 4\n"
						   "  %div2 = sdiv i32 %3, %4\n"
						   "  store i32 %div2, ptr %__main_y, align 4\n"
						   "  %5 = load i32, ptr %__main_y, align 4\n"
						   "  ret i32 %5\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_CharList_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn i32 main() { u8 lit = 'a'; lit = 'b'; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_lit = alloca i8, align 1\n"
						   "  store i8 97, ptr %__main_lit, align 1\n"
						   "  store i8 98, ptr %__main_lit, align 1\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}

void test_LocalArrayLiteralInit_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void foo() { u8[3] lit = [1, 2, 3]; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define void @foo() {\n"
						   "entry:\n"
						   "  %__foo_lit = alloca [3 x i8], align 1\n"
						   "  %arrayinit.begin = getelementptr inbounds [3 x i8], ptr %__foo_lit, i64 0, i64 0\n"
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
						   "define void @foo() {\n"
						   "entry:\n"
						   "  %__foo_a = alloca i8, align 1\n"
						   "  store i8 0, ptr %__foo_a, align 1\n"
						   "  %__foo_lit = alloca [3 x i8], align 1\n"
						   "  %arrayinit.begin = getelementptr inbounds [3 x i8], ptr %__foo_lit, i64 0, i64 0\n"
						   "  %0 = load i8, ptr %__foo_a, align 1\n"
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
						   "define void @foo() {\n"
						   "entry:\n"
						   "  %__foo_lit = alloca [3 x [2 x i8]], align 1\n"
						   "  %arrayinit.begin = getelementptr inbounds [3 x [2 x i8]], ptr %__foo_lit, i64 0, i64 0\n"
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
						   "  %__main_lit = alloca [3 x i32], align 4\n"
						   "  %arrayinit.begin = getelementptr inbounds [3 x i32], ptr %__main_lit, i64 0, i64 0\n"
						   "  store i32 1, ptr %arrayinit.begin, align 4\n"
						   "  %arrayinit.element = getelementptr inbounds i32, ptr %arrayinit.begin, i64 1\n"
						   "  store i32 2, ptr %arrayinit.element, align 4\n"
						   "  %arrayinit.element1 = getelementptr inbounds i32, ptr %arrayinit.element, i64 1\n"
						   "  store i32 3, ptr %arrayinit.element1, align 4\n"
						   "  %arrgep = getelementptr inbounds [3 x i32], ptr %__main_lit, i64 0, i64 0\n"
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
						   "  %__main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_a, align 4\n"
						   "  %__main_lit = alloca [3 x i32], align 4\n"
						   "  %arrayinit.begin = getelementptr inbounds [3 x i32], ptr %__main_lit, i64 0, i64 0\n"
						   "  store i32 1, ptr %arrayinit.begin, align 4\n"
						   "  %arrayinit.element = getelementptr inbounds i32, ptr %arrayinit.begin, i64 1\n"
						   "  store i32 2, ptr %arrayinit.element, align 4\n"
						   "  %arrayinit.element1 = getelementptr inbounds i32, ptr %arrayinit.element, i64 1\n"
						   "  store i32 3, ptr %arrayinit.element1, align 4\n"
						   "  %0 = load i32, ptr %__main_a, align 4\n"
						   "  %idx64 = sext i32 %0 to i64\n"
						   "  %arrgep = getelementptr inbounds [3 x i32], ptr %__main_lit, i64 0, i64 %idx64\n"
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
						   "  %__main_lit = alloca [3 x [2 x i32]], align 4\n"
						   "  %arrayinit.begin = getelementptr inbounds [3 x [2 x i32]], ptr %__main_lit, i64 0, i64 0\n"
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
						   "  %arrgep = getelementptr inbounds [3 x [2 x i32]], ptr %__main_lit, i64 0, i64 0\n"
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
						   "define void @foo() {\n"
						   "entry:\n"
						   "  ret void\n"
						   "}\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  call void @foo()\n"
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
						   "define void @foo(i32 %0, i32 %1) {\n"
						   "entry:\n"
						   "  %__foo_a = alloca i32, align 4\n"
						   "  store i32 %0, ptr %__foo_a, align 4\n"
						   "  %__foo_b = alloca i32, align 4\n"
						   "  store i32 %1, ptr %__foo_b, align 4\n"
						   "  ret void\n"
						   "}\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_a, align 4\n"
						   "  %__main_b = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_b, align 4\n"
						   "  %0 = load i32, ptr %__main_a, align 4\n"
						   "  %1 = load i32, ptr %__main_b, align 4\n"
						   "  call void @foo(i32 %0, i32 %1)\n"
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
						   "define i32 @foo(i32 %0, i32 %1) {\n"
						   "entry:\n"
						   "  %__foo_a = alloca i32, align 4\n"
						   "  store i32 %0, ptr %__foo_a, align 4\n"
						   "  %__foo_b = alloca i32, align 4\n"
						   "  store i32 %1, ptr %__foo_b, align 4\n"
						   "  ret i32 5\n"
						   "}\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_a, align 4\n"
						   "  %__main_b = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_b, align 4\n"
						   "  %0 = load i32, ptr %__main_a, align 4\n"
						   "  %1 = load i32, ptr %__main_b, align 4\n"
						   "  %calltmp = call i32 @foo(i32 %0, i32 %1)\n"
						   "  store i32 %calltmp, ptr %__main_a, align 4\n"
						   "  %2 = load i32, ptr %__main_a, align 4\n"
						   "  %3 = load i32, ptr %__main_b, align 4\n"
						   "  %calltmp1 = call i32 @foo(i32 %2, i32 %3)\n"
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
						   "  %__main_a = alloca i32, align 4\n"
						   "  store i32 234, ptr %__main_a, align 4\n"
						   "  %0 = load i32, ptr %__main_a, align 4\n"
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
						   "declare void @printf(ptr)\n\n"
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
						   "declare void @printf(ptr)\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_a = alloca i32, align 4\n"
						   "  store i32 1, ptr %__main_a, align 4\n"
						   "  %0 = load i32, ptr %__main_a, align 4\n"
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
						   "declare void @printf(ptr)\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_i = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_i, align 4\n"
						   "  br label %forcond\n\n"
						   "forcond:                                          ; preds = %forstep, %entry\n"
						   "  %0 = load i32, ptr %__main_i, align 4\n"
						   "  %cmplt = icmp slt i32 %0, 10\n"
						   "  br i1 %cmplt, label %forbody, label %forend\n\n"
						   "forbody:                                          ; preds = %forcond\n"
						   "  %1 = load i32, ptr %__main_i, align 4\n"
						   "  call void @printf(ptr @.str, i32 %1)\n"
						   "  br label %forstep\n\n"
						   "forstep:                                          ; preds = %forbody\n"
						   "  %2 = load i32, ptr %__main_i, align 4\n"
						   "  %add = add i32 %2, 1\n"
						   "  store i32 %add, ptr %__main_i, align 4\n"
						   "  br label %forcond\n\n"
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
						   "declare void @printf(ptr)\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_a = alloca i32, align 4\n"
						   "  store i32 10, ptr %__main_a, align 4\n"
						   "  %__main_i = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_i, align 4\n"
						   "  br label %forcond\n\n"
						   "forcond:                                          ; preds = %forstep, %entry\n"
						   "  %0 = load i32, ptr %__main_i, align 4\n"
						   "  %1 = load i32, ptr %__main_a, align 4\n"
						   "  %cmplt = icmp slt i32 %0, %1\n"
						   "  br i1 %cmplt, label %forbody, label %forend\n\n"
						   "forbody:                                          ; preds = %forcond\n"
						   "  %2 = load i32, ptr %__main_i, align 4\n"
						   "  call void @printf(ptr @.str, i32 %2)\n"
						   "  br label %forstep\n\n"
						   "forstep:                                          ; preds = %forbody\n"
						   "  %3 = load i32, ptr %__main_i, align 4\n"
						   "  %add = add i32 %3, 1\n"
						   "  store i32 %add, ptr %__main_i, align 4\n"
						   "  br label %forcond\n\n"
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
						   "declare void @printf(ptr)\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_a, align 4\n"
						   "  br label %whilecond\n"
						   "\n"
						   "whilecond:                                        ; preds = %whilebody, %entry\n"
						   "  %0 = load i32, ptr %__main_a, align 4\n"
						   "  %cmplt = icmp slt i32 %0, 10\n"
						   "  br i1 %cmplt, label %whilebody, label %whileend\n"
						   "\n"
						   "whilebody:                                        ; preds = %whilecond\n"
						   "  %1 = load i32, ptr %__main_a, align 4\n"
						   "  call void @printf(ptr @.str, i32 %1)\n"
						   "  %2 = load i32, ptr %__main_a, align 4\n"
						   "  %add = add i32 %2, 1\n"
						   "  store i32 %add, ptr %__main_a, align 4\n"
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
						   "declare void @printf(ptr)\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_a, align 4\n"
						   "  %__main_b = alloca i32, align 4\n"
						   "  store i32 10, ptr %__main_b, align 4\n"
						   "  br label %whilecond\n"
						   "\n"
						   "whilecond:                                        ; preds = %whilebody, %entry\n"
						   "  %0 = load i32, ptr %__main_a, align 4\n"
						   "  %1 = load i32, ptr %__main_b, align 4\n"
						   "  %cmplt = icmp slt i32 %0, %1\n"
						   "  br i1 %cmplt, label %whilebody, label %whileend\n"
						   "\n"
						   "whilebody:                                        ; preds = %whilecond\n"
						   "  %2 = load i32, ptr %__main_a, align 4\n"
						   "  call void @printf(ptr @.str, i32 %2)\n"
						   "  %3 = load i32, ptr %__main_a, align 4\n"
						   "  %add = add i32 %3, 1\n"
						   "  store i32 %add, ptr %__main_a, align 4\n"
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
						   "declare void @printf(ptr)\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_a, align 4\n"
						   "  %0 = load i1, ptr %__main_a, align 1\n"
						   "  br i1 %0, label %then, label %ifcont\n\n"
						   "then:                                             ; preds = %entry\n"
						   "  %1 = load i32, ptr %__main_a, align 4\n"
						   "  call void @printf(ptr @.str, i32 %1)\n"
						   "  br label %ifcont\n\n"
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
						   "declare void @printf(ptr)\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_a, align 4\n"
						   "  br label %whilecond\n\n"
						   "whilecond:                                        ; preds = %ifcont, %entry\n"
						   "  %0 = load i32, ptr %__main_a, align 4\n"
						   "  %cmplt = icmp slt i32 %0, 10\n"
						   "  br i1 %cmplt, label %whilebody, label %whileend\n\n"
						   "whilebody:                                        ; preds = %whilecond\n"
						   "  %1 = load i32, ptr %__main_a, align 4\n"
						   "  %rem = srem i32 %1, 2\n"
						   "  %2 = icmp eq i32 %rem, 0\n"
						   "  br i1 %2, label %then, label %ifcont\n\n"
						   "whileend:                                         ; preds = %whilecond\n"
						   "  ret i32 0\n\n"
						   "then:                                             ; preds = %whilebody\n"
						   "  %3 = load i32, ptr %__main_a, align 4\n"
						   "  call void @printf(ptr @.str, i32 %3)\n"
						   "  br label %ifcont\n\n"
						   "ifcont:                                           ; preds = %then, %whilebody\n"
						   "  %4 = load i32, ptr %__main_a, align 4\n"
						   "  %add = add i32 %4, 1\n"
						   "  store i32 %add, ptr %__main_a, align 4\n"
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
						   "declare void @printf(ptr)\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_a, align 4\n"
						   "  br label %whilecond\n\n"
						   "whilecond:                                        ; preds = %ifcont, %entry\n"
						   "  %0 = load i32, ptr %__main_a, align 4\n"
						   "  %cmplt = icmp slt i32 %0, 10\n"
						   "  br i1 %cmplt, label %whilebody, label %whileend\n\n"
						   "whilebody:                                        ; preds = %whilecond\n"
						   "  %1 = load i32, ptr %__main_a, align 4\n"
						   "  %rem = srem i32 %1, 2\n"
						   "  %2 = icmp eq i32 %rem, 0\n"
						   "  br i1 %2, label %then, label %else\n\n"
						   "whileend:                                         ; preds = %whilecond\n"
						   "  store i32 50, ptr %__main_a, align 4\n"
						   "  %3 = load i32, ptr %__main_a, align 4\n"
						   "  ret i32 %3\n\n"
						   "then:                                             ; preds = %whilebody\n"
						   "  %4 = load i32, ptr %__main_a, align 4\n"
						   "  call void @printf(ptr @.str, i32 %4)\n"
						   "  br label %ifcont\n\n"
						   "else:                                             ; preds = %whilebody\n"
						   "  call void @printf(ptr @.str.1)\n"
						   "  br label %ifcont\n\n"
						   "ifcont:                                           ; preds = %else, %then\n"
						   "  %5 = load i32, ptr %__main_a, align 4\n"
						   "  %add = add i32 %5, 1\n"
						   "  store i32 %add, ptr %__main_a, align 4\n"
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
						   "  %__main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_a, align 4\n"
						   "  %__main_b = alloca i64, align 8\n"
						   "  %0 = load i32, ptr %__main_a, align 4\n"
						   "  %casttmp = sext i32 %0 to i64\n"
						   "  store i64 %casttmp, ptr %__main_b, align 4\n"
						   "  %__main_c = alloca i8, align 1\n"
						   "  %1 = load i32, ptr %__main_a, align 4\n"
						   "  %casttmp1 = trunc i32 %1 to i8\n"
						   "  store i8 %casttmp1, ptr %__main_c, align 1\n"
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
						   "  %__main_a = alloca float, align 4\n"
						   "  store float 0.000000e+00, ptr %__main_a, align 4\n"
						   "  %__main_b = alloca double, align 8\n"
						   "  %0 = load float, ptr %__main_a, align 4\n"
						   "  %fpext = fpext float %0 to double\n"
						   "  store double %fpext, ptr %__main_b, align 8\n"
						   "  %__main_c = alloca float, align 4\n"
						   "  %1 = load double, ptr %__main_b, align 8\n"
						   "  %fptrunc = fptrunc double %1 to float\n"
						   "  store float %fptrunc, ptr %__main_c, align 4\n"
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
						   "  %__main_a = alloca float, align 4\n"
						   "  store float 0.000000e+00, ptr %__main_a, align 4\n"
						   "  %__main_b = alloca i64, align 8\n"
						   "  %0 = load float, ptr %__main_a, align 4\n"
						   "  %fptosi = fptosi float %0 to i64\n"
						   "  store i64 %fptosi, ptr %__main_b, align 4\n"
						   "  %__main_c = alloca double, align 8\n"
						   "  %1 = load i64, ptr %__main_b, align 4\n"
						   "  %sitofp = sitofp i64 %1 to double\n"
						   "  store double %sitofp, ptr %__main_c, align 8\n"
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
						   "  %__main_a = alloca i64, align 8\n"
						   "  store i64 0, ptr %__main_a, align 4\n"
						   "  %__main_b = alloca ptr, align 8\n"
						   "  store ptr %__main_a, ptr %__main_b, align 8\n"
						   "  %__main_c = alloca i64, align 8\n"
						   "  %0 = load ptr, ptr %__main_b, align 8\n"
						   "  %inttoptr = ptrtoint ptr %0 to i64\n"
						   "  store i64 %inttoptr, ptr %__main_c, align 4\n"
						   "  %__main_d = alloca ptr, align 8\n"
						   "  %1 = load i64, ptr %__main_c, align 4\n"
						   "  %ptrtoint = inttoptr i64 %1 to ptr\n"
						   "  store ptr %ptrtoint, ptr %__main_d, align 8\n"
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
						   "  %__main_ts1 = alloca ptr, align 8\n"
						   "  %__main_ts2 = alloca ptr, align 8\n"
						   "  %0 = load ptr, ptr %__main_ts1, align 8\n"
						   "  store ptr %0, ptr %__main_ts2, align 8\n"
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
						   "%TestStruct1 = type { i32 }\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_ts1 = alloca %TestStruct1, align 8\n"
						   "  %__main_ts2 = alloca ptr, align 8\n"
						   "  store ptr %__main_ts1, ptr %__main_ts2, align 8\n"
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
						   "declare void @printf(ptr)\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_a, align 4\n"
						   "  br label %whilecond\n\n"
						   "whilecond:                                        ; preds = %ifcont2, %then, %entry\n"
						   "  %0 = load i32, ptr %__main_a, align 4\n"
						   "  %cmplt = icmp slt i32 %0, 10\n"
						   "  br i1 %cmplt, label %whilebody, label %whileend\n\n"
						   "whilebody:                                        ; preds = %whilecond\n"
						   "  %1 = load i32, ptr %__main_a, align 4\n"
						   "  %rem = srem i32 %1, 2\n"
						   "  %2 = icmp eq i32 %rem, 0\n"
						   "  br i1 %2, label %then, label %ifcont\n\n"
						   "whileend:                                         ; preds = %then1, %whilecond\n"
						   "  ret i32 0\n\n"
						   "then:                                             ; preds = %whilebody\n"
						   "  call void @printf(ptr @.str)\n"
						   "  %3 = load i32, ptr %__main_a, align 4\n"
						   "  %add = add i32 %3, 1\n"
						   "  store i32 %add, ptr %__main_a, align 4\n"
						   "  br label %whilecond\n\n"
						   "ifcont:                                           ; preds = %whilebody\n"
						   "  %4 = load i32, ptr %__main_a, align 4\n"
						   "  %cmpge = icmp sge i32 %4, 7\n"
						   "  br i1 %cmpge, label %then1, label %ifcont2\n\n"
						   "then1:                                            ; preds = %ifcont\n"
						   "  call void @printf(ptr @.str.1)\n"
						   "  br label %whileend\n\n"
						   "ifcont2:                                          ; preds = %ifcont\n"
						   "  call void @printf(ptr @.str.2)\n"
						   "  %5 = load i32, ptr %__main_a, align 4\n"
						   "  %add3 = add i32 %5, 1\n"
						   "  store i32 %add3, ptr %__main_a, align 4\n"
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
						   "declare void @printf(ptr)\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_a = alloca i32, align 4\n"
						   "  store i32 0, ptr %__main_a, align 4\n"
						   "  br label %forcond\n\n"
						   "forcond:                                          ; preds = %forstep, %entry\n"
						   "  %0 = load i32, ptr %__main_a, align 4\n"
						   "  %cmplt = icmp slt i32 %0, 10\n"
						   "  br i1 %cmplt, label %forbody, label %forend\n\n"
						   "forbody:                                          ; preds = %forcond\n"
						   "  %1 = load i32, ptr %__main_a, align 4\n"
						   "  %rem = srem i32 %1, 2\n"
						   "  %2 = icmp eq i32 %rem, 0\n"
						   "  br i1 %2, label %then, label %ifcont\n\n"
						   "forstep:                                          ; preds = %ifcont2, %then\n"
						   "  %3 = load i32, ptr %__main_a, align 4\n"
						   "  %add = add i32 %3, 1\n"
						   "  store i32 %add, ptr %__main_a, align 4\n"
						   "  br label %forcond\n\n"
						   "forend:                                           ; preds = %then1, %forcond\n"
						   "  ret i32 0\n\n"
						   "then:                                             ; preds = %forbody\n"
						   "  call void @printf(ptr @.str)\n"
						   "  br label %forstep\n\n"
						   "ifcont:                                           ; preds = %forbody\n"
						   "  %4 = load i32, ptr %__main_a, align 4\n"
						   "  %cmpge = icmp sge i32 %4, 7\n"
						   "  br i1 %cmpge, label %then1, label %ifcont2\n\n"
						   "then1:                                            ; preds = %ifcont\n"
						   "  call void @printf(ptr @.str.1)\n"
						   "  br label %forend\n\n"
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
						   "%union.TestUnion = type { i64 }\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_ts = alloca %union.TestUnion, align 8\n"
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
						   "%union.TestUnion = type { i64 }\n\n"
						   "define i32 @main() {\n"
						   "entry:\n"
						   "  %__main_ts = alloca %union.TestUnion, align 8\n"
						   "  store i32 50, ptr %__main_ts, align 4\n"
						   "  %0 = load i32, ptr %__main_ts, align 4\n"
						   "  ret i32 %0\n"
						   "}\n";
	const char *expected_error = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	TEST_ASSERT_EQUAL_STRING(expected_error, error);
	free(error);
}