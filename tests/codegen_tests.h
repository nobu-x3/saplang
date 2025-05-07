#pragma once
#include "test_util.h"
#include "unity_internals.h"
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
	int success = 1;                                                                                                                                                                                                                           \
	for (ASTNode *node = module->ast; node != NULL; node = node->next) {                                                                                                                                                                       \
		success &= analyze_ast(module->symbol_table, node, 0, "") == RESULT_SUCCESS;                                                                                                                                                           \
		resolve_types(module->symbol_table, node);                                                                                                                                                                                             \
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

void test_LocalVarDeclWithInitOfIdent_codegen(void) {
	CODEGEN_TEST_SETUP_SINGLE("fn void some_func() { i32 a; i32 i = a; }");
	const char *expected = "; ModuleID = 'test'\n"
						   "source_filename = \"test\"\n\n"
						   "define void @some_func() {\n"
						   "entry:\n"
						   "  %__some_func_a = alloca i32, align 4\n"
						   "  %__some_func_i = alloca i32, align 4\n"
						   "  store ptr %__some_func_a, ptr %__some_func_i, align 8\n"
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
