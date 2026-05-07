#pragma once

#include <scanner.h>
#include <unity.h>

// Helper: scan a single source string and return the first token. The
// scanner's source buffer is freed before returning, since `Token` carries
// its own copy of the text.
static Token scan_first(const char *input) {
	Scanner scanner;
	scanner_init_from_string(&scanner, "scanner_tests.sl", input);
	Token tok = next_token(&scanner);
	scanner_deinit(&scanner);
	return tok;
}

void test_TokenText_SelfDiv_scanner(void) {
	Token tok = scan_first("/=");
	TEST_ASSERT_EQUAL_INT(TOK_SELFDIV, tok.type);
	TEST_ASSERT_EQUAL_STRING("/=", tok.text);
}

void test_TokenText_SelfOr_scanner(void) {
	Token tok = scan_first("|=");
	TEST_ASSERT_EQUAL_INT(TOK_SELFOR, tok.type);
	TEST_ASSERT_EQUAL_STRING("|=", tok.text);
}

void test_TokenText_LogicalOr_scanner(void) {
	Token tok = scan_first("||");
	TEST_ASSERT_EQUAL_INT(TOK_OR, tok.type);
	TEST_ASSERT_EQUAL_STRING("||", tok.text);
}

void test_TokenText_SelfMul_scanner(void) {
	Token tok = scan_first("*=");
	TEST_ASSERT_EQUAL_INT(TOK_SELFMUL, tok.type);
	TEST_ASSERT_EQUAL_STRING("*=", tok.text);
}
