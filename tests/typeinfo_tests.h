#pragma once
#include "test_util.h"
#include <arena.h>
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
	Type type = {.type_kind = TYPE_PRIMITIVE, .type_name = "i32"};
	TypeInfo info = get_type_info(&type, &dummynody);
	TEST_ASSERT_EQUAL_UINT32(4, info.size);
	TEST_ASSERT_EQUAL_UINT32(4, info.align);
}

void test_Primitivei64_typeinfo(void) {
    ASTNode dummynody;
	Type type = {.type_kind = TYPE_PRIMITIVE, .type_name = "i64"};
	TypeInfo info = get_type_info(&type, &dummynody);
	TEST_ASSERT_EQUAL_UINT32(8, info.size);
	TEST_ASSERT_EQUAL_UINT32(8, info.align);
}

void test_Pointer_typeinfo(void) {
    ASTNode dummynody;
	Type type = {.type_kind = TYPE_POINTER};
	TypeInfo info = get_type_info(&type, &dummynody);
	TEST_ASSERT_EQUAL_UINT32(sizeof(void *), info.size);
	TEST_ASSERT_EQUAL_UINT32(sizeof(void *), info.align);
}

void test_ArrayType_typeinfo(void) {
    ASTNode dummynody;
	Type elem = {.type_kind = TYPE_PRIMITIVE, .type_name = "u8"};
	Type type = {.type_kind = TYPE_ARRAY, .array = {.element_type = &elem, .size = 10}};
	TypeInfo info = get_type_info(&type, &dummynody);
	TEST_ASSERT_EQUAL_UINT32(10, info.size);
	TEST_ASSERT_EQUAL_UINT32(1, info.align);
}

void test_EnumType_typeinfo(void) {
    TEST_SETUP_SINGLE_TYPEINFO("enum Enum : u32 {}");
	Type type = {.type_kind = TYPE_ENUM, .type_name = "u32"};
	TypeInfo info = get_type_info(&type, module->ast);
	TEST_ASSERT_EQUAL_UINT32(4, info.size);
	TEST_ASSERT_EQUAL_UINT32(4, info.align);
}

void test_StructDecl_typeinfo(void) {
    TEST_SETUP_SINGLE_TYPEINFO("struct Struct { i32 first; f64 second; bool third; }");
	Type type = {.type_kind = TYPE_STRUCT, .type_name = "Struct"};
	TypeInfo info = get_type_info(&type, module->ast);
	TEST_ASSERT_EQUAL_UINT32(24, info.size);
	TEST_ASSERT_EQUAL_UINT32(8, info.align);
}

// Two i32 fields lay out at offsets 0 and 4; offset after the last field
// (8) is already a multiple of the struct's alignment (4), so the
// trailing pad must be zero rather than a full alignment unit.
void test_StructAlreadyAlignedI32Pair_typeinfo(void) {
	TEST_SETUP_SINGLE_TYPEINFO("struct S { i32 a; i32 b; }");
	Type type = {.type_kind = TYPE_STRUCT, .type_name = "S"};
	TypeInfo info = get_type_info(&type, module->ast);
	TEST_ASSERT_EQUAL_UINT32(8, info.size);
	TEST_ASSERT_EQUAL_UINT32(4, info.align);
}

// A single f64 field is already at the struct's alignment; the trailing
// pad must be zero, not a duplicate 8-byte unit at the end.
void test_StructAlreadyAlignedSingleF64_typeinfo(void) {
	TEST_SETUP_SINGLE_TYPEINFO("struct S { f64 a; }");
	Type type = {.type_kind = TYPE_STRUCT, .type_name = "S"};
	TypeInfo info = get_type_info(&type, module->ast);
	TEST_ASSERT_EQUAL_UINT32(8, info.size);
	TEST_ASSERT_EQUAL_UINT32(8, info.align);
}

// Four i32 fields end at offset 16, already aligned to 4; no trailing
// pad must be added.
void test_StructAlreadyAlignedI32Quad_typeinfo(void) {
	TEST_SETUP_SINGLE_TYPEINFO("struct S { i32 a; i32 b; i32 c; i32 d; }");
	Type type = {.type_kind = TYPE_STRUCT, .type_name = "S"};
	TypeInfo info = get_type_info(&type, module->ast);
	TEST_ASSERT_EQUAL_UINT32(16, info.size);
	TEST_ASSERT_EQUAL_UINT32(4, info.align);
}

// An i32 followed by a bool ends at offset 5; the trailing pad must
// round the size up to the struct's alignment (4), giving size 8.
// Sanity check that the modulo subtraction still works in the common
// non-degenerate case.
void test_StructTrailingPadI32Bool_typeinfo(void) {
	TEST_SETUP_SINGLE_TYPEINFO("struct S { i32 a; bool b; }");
	Type type = {.type_kind = TYPE_STRUCT, .type_name = "S"};
	TypeInfo info = get_type_info(&type, module->ast);
	TEST_ASSERT_EQUAL_UINT32(8, info.size);
	TEST_ASSERT_EQUAL_UINT32(4, info.align);
}

void test_UnionDecl_typeinfo(void) {
    TEST_SETUP_SINGLE_TYPEINFO("union Union { i32 first; f64 second; bool third; }");
	Type type = {.type_kind = TYPE_UNION, .type_name = "Union"};
	TypeInfo info = get_type_info(&type, module->ast);
	TEST_ASSERT_EQUAL_UINT32(8, info.size);
	TEST_ASSERT_EQUAL_UINT32(8, info.align);
}

void test_NamedType_ResolvedNameMangling_types(void) {
	Arena arena;
	arena_init(&arena, 0);
	type_arena_set(&arena);

	Type *t = new_named_type("Point", "geom", TYPE_STRUCT);
	TEST_ASSERT_NOT_NULL(t);
	TEST_ASSERT_EQUAL_STRING("Point", t->type_name);
	TEST_ASSERT_EQUAL_STRING("geom", t->type_namespace);
	TEST_ASSERT_EQUAL_STRING("__geom_Point", t->type_resolved_name);

	type_arena_set(NULL);
	arena_deinit(&arena);
}

// Worst-case lengths: a 63-byte namespace plus a 63-byte name plus the
// 3-byte "__%s_%s" wrapper is 129 bytes — one byte over the 128-byte
// type_resolved_name buffer. Pre-fix this overflowed via sprintf; the fix
// is to snprintf-bound the write and refuse to produce a Type whose mangled
// name would silently collide with another similarly-prefixed symbol.
void test_NamedType_MangledNameOverflow_types(void) {
	Arena arena;
	arena_init(&arena, 0);
	type_arena_set(&arena);

	char long_name[64];
	char long_namespace[64];
	memset(long_name, 'A', sizeof(long_name) - 1);
	long_name[sizeof(long_name) - 1] = '\0';
	memset(long_namespace, 'B', sizeof(long_namespace) - 1);
	long_namespace[sizeof(long_namespace) - 1] = '\0';

	FILE *old_stderr = capture_error_begin();
	Type *t = new_named_type(long_name, long_namespace, TYPE_STRUCT);
	char *err = capture_error_end(old_stderr);

	TEST_ASSERT_NULL(t);
	TEST_ASSERT_NOT_NULL(strstr(err, "exceeds"));

	free(err);
	type_arena_set(NULL);
	arena_deinit(&arena);
}

// One byte under the cap: 62-byte namespace + 62-byte name + 3 wrapper bytes
// = 127, which fits with the trailing null. The boundary should be respected
// without false-positive truncation diagnostics.
void test_NamedType_MangledNameBoundary_types(void) {
	Arena arena;
	arena_init(&arena, 0);
	type_arena_set(&arena);

	char name[63];
	char namespace[63];
	memset(name, 'C', sizeof(name) - 1);
	name[sizeof(name) - 1] = '\0';
	memset(namespace, 'D', sizeof(namespace) - 1);
	namespace[sizeof(namespace) - 1] = '\0';

	Type *t = new_named_type(name, namespace, TYPE_STRUCT);
	TEST_ASSERT_NOT_NULL(t);
	TEST_ASSERT_EQUAL_UINT32(127, strlen(t->type_resolved_name));

	type_arena_set(NULL);
	arena_deinit(&arena);
}
