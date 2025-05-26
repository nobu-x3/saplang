#pragma once
#include "test_util.h"
#include <parser.h>
#include <sema.h>
#include <types.h>
#include <unity.h>
#include <util.h>

#define TEST_SETUP_SINGLE_TYPEINFO(input_string)                                                                                                                                                                                                        \
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


void test_Primitivei32_typeinfo(void) {
    ASTNode dummynody;
	Type type = {.kind = TYPE_PRIMITIVE, .type_name = "i32"};
	TypeInfo info = get_type_info(&type, &dummynody);
	TEST_ASSERT_EQUAL_UINT32(4, info.size);
	TEST_ASSERT_EQUAL_UINT32(4, info.align);
}

void test_Primitivei64_typeinfo(void) {
    ASTNode dummynody;
	Type type = {.kind = TYPE_PRIMITIVE, .type_name = "i64"};
	TypeInfo info = get_type_info(&type, &dummynody);
	TEST_ASSERT_EQUAL_UINT32(8, info.size);
	TEST_ASSERT_EQUAL_UINT32(8, info.align);
}

void test_Pointer_typeinfo(void) {
    ASTNode dummynody;
	Type type = {.kind = TYPE_POINTER};
	TypeInfo info = get_type_info(&type, &dummynody);
	TEST_ASSERT_EQUAL_UINT32(sizeof(void *), info.size);
	TEST_ASSERT_EQUAL_UINT32(sizeof(void *), info.align);
}

void test_ArrayType_typeinfo(void) {
    ASTNode dummynody;
	Type elem = {.kind = TYPE_PRIMITIVE, .type_name = "u8"};
	Type type = {.kind = TYPE_ARRAY, .array = {.element_type = &elem, .size = 10}};
	TypeInfo info = get_type_info(&type, &dummynody);
	TEST_ASSERT_EQUAL_UINT32(10, info.size);
	TEST_ASSERT_EQUAL_UINT32(1, info.align);
}

void test_EnumType_typeinfo(void) {
    TEST_SETUP_SINGLE_TYPEINFO("enum Enum : u32 {}");
	Type type = {.kind = TYPE_ENUM, .type_name = "u32"};
	TypeInfo info = get_type_info(&type, module->ast);
	TEST_ASSERT_EQUAL_UINT32(4, info.size);
	TEST_ASSERT_EQUAL_UINT32(4, info.align);
}

void test_StructDecl_typeinfo(void) {
    TEST_SETUP_SINGLE_TYPEINFO("struct Struct { i32 first; f64 second; bool third; }");
	Type type = {.kind = TYPE_STRUCT, .type_name = "Struct"};
	TypeInfo info = get_type_info(&type, module->ast);
	TEST_ASSERT_EQUAL_UINT32(8, info.size);
	TEST_ASSERT_EQUAL_UINT32(8, info.align);
}

void test_UnionDecl_typeinfo(void) {
    TEST_SETUP_SINGLE_TYPEINFO("union Union { i32 first; f64 second; bool third; }");
	Type type = {.kind = TYPE_UNION, .type_name = "Union"};
	TypeInfo info = get_type_info(&type, module->ast);
	TEST_ASSERT_EQUAL_UINT32(8, info.size);
	TEST_ASSERT_EQUAL_UINT32(8, info.align);
}