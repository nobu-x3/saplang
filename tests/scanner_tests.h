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

void test_TokenText_Null_scanner(void) {
	Token tok = scan_first("null");
	TEST_ASSERT_EQUAL_INT(TOK_NULL, tok.type);
	TEST_ASSERT_EQUAL_STRING("null", tok.text);
}

void test_TokenText_NullPrefix_NotAKeyword_scanner(void) {
	Token tok = scan_first("nullable");
	TEST_ASSERT_EQUAL_INT(TOK_IDENTIFIER, tok.type);
	TEST_ASSERT_EQUAL_STRING("nullable", tok.text);
}

void test_TokenText_Switch_scanner(void) {
	Token tok = scan_first("switch");
	TEST_ASSERT_EQUAL_INT(TOK_SWITCH, tok.type);
	TEST_ASSERT_EQUAL_STRING("switch", tok.text);
}

void test_TokenText_Case_scanner(void) {
	Token tok = scan_first("case");
	TEST_ASSERT_EQUAL_INT(TOK_CASE, tok.type);
	TEST_ASSERT_EQUAL_STRING("case", tok.text);
}

// `..` lexes as TOK_DOTDOT (used for slice ranges). Must be distinct from
// `...` (varargs) and a bare `.` (member access / float decimal point).
void test_TokenText_DotDot_scanner(void) {
	Token tok = scan_first("..");
	TEST_ASSERT_EQUAL_INT(TOK_DOTDOT, tok.type);
	TEST_ASSERT_EQUAL_STRING("..", tok.text);
}

void test_TokenText_DotDotDot_StillTriDot_scanner(void) {
	Token tok = scan_first("...");
	TEST_ASSERT_EQUAL_INT(TOK_DOTDOTDOT, tok.type);
}
