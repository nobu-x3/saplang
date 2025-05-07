#pragma once
#include "test_util.h"
#include <parser.h>
#include <sema.h>
#include <types.h>
#include <unity.h>
#include <util.h>

#define TEST_SETUP_SINGLE(input_string)                                                                                                                                                                                                        \
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
	char *output = capture_error_end(old_stdout);

void test_TypePrinting_sema(void) {
	const char *input = "i32*[32] test_var;";
	const char *path = "parser_tests.sl";
	Scanner scanner;
	scanner_init_from_string(&scanner, path, input);
	Parser parser;
	parser_init(&parser, scanner, NULL);
	Module *module = parse_input(&parser);
	char type_str[64] = "";
	type_print(type_str, module->ast->data.var_decl.type);
	const char *expected = "i32*[32]";
	TEST_ASSERT_EQUAL_STRING(expected, type_str);
}

void test_UndeclaredVariable_sema(void) {
	TEST_SETUP_SINGLE("fn void foo() { i32 var_a = var_b; }");
	const char *expected = "parser_tests.sl:0:39:Error: undeclared identifier var_b.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ConstNoInit_sema(void) {
	TEST_SETUP_SINGLE("fn void foo() { const i32 i; }");
	const char *expected = "parser_tests.sl:0:27:Error: const variable must have an initializer.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_AssignmentToConst_sema(void) {
	TEST_SETUP_SINGLE("fn void foo() { const i32 i = 1; i = 2; }");
	const char *expected = "parser_tests.sl:0:38:Error: cannot assign a value to a const variable i.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_AssignmentToRValue_sema(void) {
	TEST_SETUP_SINGLE("fn void foo() { const i32 i = 0; 2 = i + 3; }");
	const char *expected = "parser_tests.sl:0:36:Error: cannot assign a value to a literal.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_VarialbeRedeclaration_sema(void) {
	TEST_SETUP_SINGLE("i32 var_a; i32 var_a; ");
	const char *expected = "parser_tests.sl:0:20:Error: variable var_a already declared in this scope.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_FnRedeclaration_sema(void) {
	TEST_SETUP_SINGLE("fn void foo() {} fn void foo() {} ");
	const char *expected = "parser_tests.sl:0:28:Error: variable foo already declared in this scope.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructRedeclaration_sema(void) {
	TEST_SETUP_SINGLE("struct Str {} struct Str {} ");
	const char *expected = "parser_tests.sl:0:24:Error: struct redeclaration.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteralInitUnknownField_sema(void) {
	TEST_SETUP_SINGLE("struct Str { i32 first; } Str str = {.second = 0};");
	const char *expected = "parser_tests.sl:0:37:Error: cannot find a field with name 'second' in the definition of struct 'Str'.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteralInitMoreInitsThanFields_sema(void) {
	TEST_SETUP_SINGLE("struct Str {} Str str = {0};");
	const char *expected = "parser_tests.sl:0:25:Error: struct 'Str' has 0 fields, check initialization.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_EnumRedeclaration_sema(void) {
	TEST_SETUP_SINGLE("enum Str {} enum Str {} ");
	const char *expected = "parser_tests.sl:0:20:Error: enum redeclaration.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructFieldRedeclaration_sema(void) {
	TEST_SETUP_SINGLE("struct Str { i32 a; f32 a; }");
	const char *expected = "parser_tests.sl:0:25:Error: field redeclaration.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_EnumMemberRedeclaration_sema(void) {
	TEST_SETUP_SINGLE("enum Str { One, One } ");
	const char *expected = "parser_tests.sl:0:19:Error: enum member redeclaration.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ParamRedeclaration_sema(void) {
	TEST_SETUP_SINGLE("fn void foo(i32 a, i32 a) {}");
	const char *expected = "parser_tests.sl:0:25:Error: parameter redeclaration: a.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_UndeclaredFunction_sema(void) {
	TEST_SETUP_SINGLE("fn void foo() { baz(); }");
	const char *expected = "parser_tests.sl:0:19:Error: undeclared identifier baz.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ArgCountMismatch_sema(void) {
	TEST_SETUP_SINGLE("fn void foo() { baz(); baz(0); } fn void baz(i32 a, i32 b) {}");
	const char *expected = "parser_tests.sl:0:21:Error: argument count mismatch.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ArgTypeMismatch_sema(void) {
	TEST_SETUP_SINGLE("fn void foo() { baz(0.0, true); } fn void baz(i32 a, i32 b) {}");
	const char *expected = "parser_tests.sl:0:21:Error: cannot implicitly convert from type f32 to type i32 in function call baz.\nparser_tests.sl:0:21:Error: cannot implicitly convert from type bool to type i32 in function call baz.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ParameterNameConflict_sema(void) {
	TEST_SETUP_SINGLE("fn void foo(i32 a, i32 a) {}");
	const char *expected = "parser_tests.sl:0:25:Error: parameter redeclaration: a.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_FuncCallInitWrongType_sema(void) {
	TEST_SETUP_SINGLE("fn i32 foo() { return 1; } fn void main() { f32 float = foo(); }");
	const char *expected = "parser_tests.sl:0:66:Error: type mismatch in initializer.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_FuncCallAssignmentWrongType_sema(void) {
	TEST_SETUP_SINGLE("fn i32 foo() { return 1; } fn void main() { f32 float = 0.0; float = foo(); }");
	const char *expected = "parser_tests.sl:0:76:Error: assignment type mismatch: cannot implicitly convert i32 to f32.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ExplicitCastWrongTypes_ValueToPointer_sema(void) {
	TEST_SETUP_SINGLE("fn i32 foo() { i64 val; i64* p = (i64*)val; }");
	const char *expected = "parser_tests.sl:0:44:Error: cannot convert type i64 into type i64*.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ExplicitCastWrongTypes_PointerToValue_sema(void) {
	TEST_SETUP_SINGLE("fn i32 foo() { i64 *p; i64 val = (i64)p; }");
	const char *expected = "parser_tests.sl:0:44:Error: cannot convert type i64* into type i64.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ExplicitCastWrongTypes_ReturnType_sema(void) {
	TEST_SETUP_SINGLE("fn i32 foo() { i64 val; return (f32)val; }");
	const char *expected = "parser_tests.sl:0:34:Error: cannot implicitly convert from f32 to i32.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_GlobalVariableInitWithGlobalVar(void) {
	TEST_SETUP_SINGLE("i32 i = 0; i32 a = i;");
	const char *expected = "parser_tests.sl:0:16:Error: global variables cannot be initialized with other global variables.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}
