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
	parser_init(&parser, scanner, NULL);                                                                                                                                                                                                       \
	Module *module = parse_input(&parser);                                                                                                                                                                                                     \
	FILE *old_stdout = capture_error_begin();                                                                                                                                                                                                  \
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
