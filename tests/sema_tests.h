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
		analyze_ast(module->symbol_table, node, 0);                                                                                                                                                                                            \
	}                                                                                                                                                                                                                                          \
	char *output = capture_error_end(old_stdout);

void test_TypePrinting(void) {
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

void test_UndeclaredVariable(void) {
	TEST_SETUP_SINGLE("i32 var_a = var_b;");
	const char *expected = "parser_tests.sl:0:17:Error: undeclared identifier var_b.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ConstNoInit(void) {
	TEST_SETUP_SINGLE("fn void foo() { const i32 i; }");
	const char *expected = "parser_tests.sl:0:27:Error: const variable must have an initializer.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_AssignmentToConst(void) {
	TEST_SETUP_SINGLE("fn void foo() { const i32 i = 1; i = 2; }");
	const char *expected = "parser_tests.sl:0:38:Error: cannot assign a value to a const variable i.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_AssignmentToRValue(void) {
	TEST_SETUP_SINGLE("fn void foo() { const i32 i = 0; 2 = i + 3; }");
	const char *expected = "parser_tests.sl:0:36:Error: cannot assign a value to a literal.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_VarialbeRedeclaration(void) {
	TEST_SETUP_SINGLE("i32 var_a; i32 var_a; ");
	const char *expected = "parser_tests.sl:0:20:Error: variable var_a already declared in this scope.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_FnRedeclaration(void) {
	TEST_SETUP_SINGLE("fn void foo() {} fn void foo() {} ");
	const char *expected = "parser_tests.sl:0:28:Error: variable foo already declared in this scope.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructRedeclaration(void) {
	TEST_SETUP_SINGLE("struct Str {} struct Str {} ");
	const char *expected = "parser_tests.sl:0:24:Error: struct redeclaration.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_EnumRedeclaration(void) {
	TEST_SETUP_SINGLE("enum Str {} enum Str {} ");
	const char *expected = "parser_tests.sl:0:20:Error: enum redeclaration.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructFieldRedeclaration(void) {
	TEST_SETUP_SINGLE("struct Str { i32 a; f32 a; }");
	const char *expected = "parser_tests.sl:0:25:Error: field redeclaration.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_EnumMemberRedeclaration(void) {
	TEST_SETUP_SINGLE("enum Str { One, One } ");
	const char *expected = "parser_tests.sl:0:19:Error: enum member redeclaration.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}
