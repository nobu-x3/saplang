#pragma once
#include "test_util.h"
#include <parser.h>
#include <sema.h>
#include <string.h>
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
	symbol_table_set_type_info(module->symbol_table);                                                                                                                                                                                          \
	if (!module->has_errors) {                                                                                                                                                                                                                 \
		for (ASTNode *node = module->ast; node != NULL; node = node->next) {                                                                                                                                                                   \
			analyze_ast(module->symbol_table, node, 0, "");                                                                                                                                                                                    \
		}                                                                                                                                                                                                                                      \
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

void test_VariableRedeclaration_sema(void) {
	TEST_SETUP_SINGLE("i32 var_a; i32 var_a; ");
	const char *expected = "parser_tests.sl:0:20:Error: variable var_a already declared in this scope.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_FnRedeclaration_sema(void) {
	TEST_SETUP_SINGLE("fn void foo() {} fn void foo() {} ");
	const char *expected = "parser_tests.sl:0:28:Error: function foo already declared in this scope.\n";
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

void test_StructLiteralPositionalCorrect_sema(void) {
	TEST_SETUP_SINGLE("struct S { i32 a; f32 b; } S s = {1, 2.0};");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteralDesignatedCorrect_sema(void) {
	TEST_SETUP_SINGLE("struct S { i32 a; f32 b; } S s = {.a = 1, .b = 2.0};");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteralLiteralAdaptsToFieldWidth_sema(void) {
	TEST_SETUP_SINGLE("struct S { u8 a; u16 b; u32 c; u64 d; } S s = {1, 2, 3, 4};");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteralPositionalWrongType_sema(void) {
	TEST_SETUP_SINGLE("struct S { i32 a; } S s = {1.0};");
	const char *expected = "parser_tests.sl:0:30:Error: assignment type mismatch: cannot implicitly convert f32 to i32.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteralPositionalSecondFieldWrongType_sema(void) {
	TEST_SETUP_SINGLE("struct S { i32 a; i32 b; } S s = {1, 2.0};");
	const char *expected = "parser_tests.sl:0:40:Error: assignment type mismatch: cannot implicitly convert f32 to i32.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteralDesignatedWrongType_sema(void) {
	TEST_SETUP_SINGLE("struct S { i32 a; f32 b; } S s = {.b = 1, .a = 2.0};");
	const char *expected = "parser_tests.sl:0:40:Error: assignment type mismatch: cannot implicitly convert i32 to f32.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteralBoolLitIntoIntField_sema(void) {
	TEST_SETUP_SINGLE("struct S { i32 a; } S s = {true};");
	const char *expected = "parser_tests.sl:0:31:Error: assignment type mismatch: cannot implicitly convert bool to i32.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteralIntLitIntoBoolField_sema(void) {
	TEST_SETUP_SINGLE("struct S { bool a; } S s = {1};");
	const char *expected = "parser_tests.sl:0:29:Error: assignment type mismatch: cannot implicitly convert i32 to bool.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteralCharLitIntoIntField_sema(void) {
	TEST_SETUP_SINGLE("struct S { i32 a; } S s = {'c'};");
	const char *expected = "parser_tests.sl:0:27:Error: cannot initialize field 'a' of type i32 with a char literal.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteralCharLitIntoU8Field_sema(void) {
	TEST_SETUP_SINGLE("struct S { u8 a; } S s = {'c'};");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteralIdentWrongType_sema(void) {
	TEST_SETUP_SINGLE("struct S { i32 a; } fn void foo() { f32 f = 0.0; S s = {f}; }");
	const char *expected = "parser_tests.sl:0:61:Error: type mismatch initializing field 'a': cannot implicitly convert f32 to i32.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteralNestedInnerWrongType_sema(void) {
	TEST_SETUP_SINGLE("struct Inner { i32 x; } struct Outer { Inner a; } Outer o = {{1.0}};");
	const char *expected = "parser_tests.sl:0:65:Error: assignment type mismatch: cannot implicitly convert f32 to i32.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteralIdentCorrectType_sema(void) {
	TEST_SETUP_SINGLE("struct S { i32 a; } fn void foo() { i32 x = 7; S s = {x}; }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteralNestedCorrect_sema(void) {
	TEST_SETUP_SINGLE("struct Inner { i32 x; i32 y; } struct Outer { Inner a; Inner b; } Outer o = {{0, 1}, {2, 3}};");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteralDesignatedUnknownFieldBeforeTypeCheck_sema(void) {
	TEST_SETUP_SINGLE("struct S { i32 a; } S s = {.b = 1.0};");
	const char *expected = "parser_tests.sl:0:27:Error: cannot find a field with name 'b' in the definition of struct 'S'.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_NullAssignToPointer_sema(void) {
	TEST_SETUP_SINGLE("fn void foo() { i32* p = null; }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_NullAssignToDoublePointer_sema(void) {
	TEST_SETUP_SINGLE("fn void foo() { i32** p = null; }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_NullAssignToIntFails_sema(void) {
	TEST_SETUP_SINGLE("fn void foo() { i32 a = null; }");
	const char *expected = "parser_tests.sl:0:30:Error: assignment type mismatch: cannot implicitly convert void* to i32.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_NullAssignToFloatFails_sema(void) {
	TEST_SETUP_SINGLE("fn void foo() { f32 a = null; }");
	const char *expected = "parser_tests.sl:0:30:Error: assignment type mismatch: cannot implicitly convert void* to f32.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_NullReassignToPointer_sema(void) {
	TEST_SETUP_SINGLE("fn void foo() { i32* p; p = null; }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_NullCompareEqualsPointer_sema(void) {
	TEST_SETUP_SINGLE("fn void foo() { i32* p; if (p == null) {} }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_NullCompareNotEqualsPointer_sema(void) {
	TEST_SETUP_SINGLE("fn void foo() { i32* p; if (p != null) {} }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_PointerTruthyIfStillWorks_sema(void) {
	TEST_SETUP_SINGLE("fn void foo() { i32* p; if (p) {} if (!p) {} }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_NullAsArgument_sema(void) {
	TEST_SETUP_SINGLE("fn void g(i32* p) {} fn void f() { g(null); }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_NullAsReturn_sema(void) {
	TEST_SETUP_SINGLE("fn i32* foo() { return null; }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_NullReturnFromIntFn_sema(void) {
	TEST_SETUP_SINGLE("fn i32 foo() { return null; }");
	const char *expected = "parser_tests.sl:0:21:Error: cannot implicitly convert from void* to i32.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_NullInStructFieldInit_sema(void) {
	TEST_SETUP_SINGLE("struct S { i32* p; } S s = {null};");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_NullInStructFieldInitDesignated_sema(void) {
	TEST_SETUP_SINGLE("struct S { i32 a; i32* p; } S s = {.p = null, .a = 1};");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_NullInStructFieldInitWrongType_sema(void) {
	TEST_SETUP_SINGLE("struct S { i32 a; } S s = {null};");
	const char *expected = "parser_tests.sl:0:31:Error: assignment type mismatch: cannot implicitly convert void* to i32.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_NullableIsStillIdent_sema(void) {
	TEST_SETUP_SINGLE("fn void foo() { i32 nullable = 0; nullable = 1; }");
	const char *expected = "";
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

void test_ExplicitCastCorrectTypes_ValueToPointer_sema(void) {
	TEST_SETUP_SINGLE("fn i32 foo() { i64 val; i64* p = (i64*)val; return 0; }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ExplicitCastCorrectTypes_PointerToValue_sema(void) {
	TEST_SETUP_SINGLE("fn i32 foo() { i64 *p; i64 val = (i64)p; return 0; }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ExplicitCastWrongTypes_ReturnType_sema(void) {
	TEST_SETUP_SINGLE("fn i32 foo() { i64 val; return (f32)val; }");
	const char *expected = "parser_tests.sl:0:34:Error: cannot implicitly convert from f32 to i32.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_GlobalVariableInitWithGlobalVar_sema(void) {
	TEST_SETUP_SINGLE("i32 i = 0; i32 a = i;");
	const char *expected = "parser_tests.sl:0:16:Error: global variables cannot be initialized with other global variables.\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ParamReferencedInBody_sema(void) {
	TEST_SETUP_SINGLE("fn i32 foo(i32 a, i32 b) { return a + b; }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_PointerParamDereferencedInBody_sema(void) {
	TEST_SETUP_SINGLE("fn void take(i32* p) { i32 x = *p; }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ParamPassedToOtherCall_sema(void) {
	TEST_SETUP_SINGLE("fn void sink(i32 v) {} fn void source(i32 a) { sink(a); }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_FunctionOverload_sema(void) {
	TEST_SETUP_SINGLE("struct S {i32 i;}"
					  "union TestUnion { i32 a; i64 b; }"
					  "enum Str { One }"
					  "fn void foo(){}"
					  "fn void foo(i32 i){ foo(); }"
					  "fn void foo(i32* p_i){ foo(*p_i); }"
					  "fn void foo(i32** p_p_i){ foo(*p_p_i); }"
					  "fn void foo(S s){ foo(s.i); }"
					  "fn void foo(S* p_s){ foo(*p_s); }"
					  "fn void foo(S** p_p_s){ foo(*p_p_s); }"
					  "fn void foo(Str s){ foo((i32)s); }"
					  "fn void foo(Str* p_s){ foo(*p_s); }"
					  "fn void foo(Str** p_p_s){ foo(*p_p_s); }"
					  "fn void foo(TestUnion s){ foo(s.a); }"
					  "fn void foo(TestUnion* p_s){ foo(*p_s); }"
					  "fn void foo(TestUnion** p_p_s){ foo(*p_p_s); }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_FunctionOverload_FnPointer_sema(void) {
	TEST_SETUP_SINGLE("fn void foo(){}"
					  "fn void foo(i32 x){}"
					  "fn i32 main() {"
					  "    fn* void(i32) f = &foo;"
					  "    f(0);"
					  "    return 0;"
					  "}");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_Switch_IntSubject_Correct_sema(void) {
	TEST_SETUP_SINGLE("fn void test() {"
					  "    i32 a = 0;"
					  "    switch (a) {"
					  "    case 1:"
					  "    case 2: { a = 10; }"
					  "    case 3: { a = 20; }"
					  "    else { a = 99; }"
					  "    }"
					  "}");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_Switch_NonIntSubject_sema(void) {
	TEST_SETUP_SINGLE("fn void test() {"
					  "    f32 a = 1.0;"
					  "    switch (a) {"
					  "    case 1: { a = 1.0; }"
					  "    }"
					  "}");
	TEST_ASSERT_NOT_NULL(strstr(output, "switch subject must be an integer or enum"));
	free(output);
}

void test_Switch_NonConstCaseValue_sema(void) {
	TEST_SETUP_SINGLE("fn void test() {"
					  "    i32 a = 0;"
					  "    i32 b = 1;"
					  "    switch (a) {"
					  "    case b: { a = 10; }"
					  "    }"
					  "}");
	TEST_ASSERT_NOT_NULL(strstr(output, "case value must be an integer literal compatible with switch subject type"));
	free(output);
}

void test_Switch_DuplicateCaseValue_sema(void) {
	TEST_SETUP_SINGLE("fn void test() {"
					  "    i32 a = 0;"
					  "    switch (a) {"
					  "    case 1: { a = 10; }"
					  "    case 1: { a = 20; }"
					  "    }"
					  "}");
	TEST_ASSERT_NOT_NULL(strstr(output, "duplicate case value 1 in switch"));
	free(output);
}

void test_Switch_EnumSubject_Correct_sema(void) {
	TEST_SETUP_SINGLE("enum Color : i32 { Red, Green, Blue }"
					  "fn void test() {"
					  "    Color c = Color::Red;"
					  "    switch (c) {"
					  "    case Color::Red: { c = Color::Green; }"
					  "    case Color::Blue: { c = Color::Red; }"
					  "    else { c = Color::Red; }"
					  "    }"
					  "}");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

// A fixed-size array `T[N]` is convertible to the matching slice type
// `T[]` at any conversion site (var init, return, argument). Element types
// must match exactly — no implicit element coercion.
void test_SliceAssignFromArray_sema(void) {
	TEST_SETUP_SINGLE("fn void f() { i32[3] arr = [1, 2, 3]; i32[] s = arr; }");
	TEST_ASSERT_EQUAL_STRING("", output);
	free(output);
}

void test_SliceAssignFromArrayWrongElement_sema(void) {
	TEST_SETUP_SINGLE("fn void f() { u8[3] arr = [1, 2, 3]; i32[] s = arr; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "Error"));
	free(output);
}

// Passing a fixed-size array to a slice-typed parameter must succeed —
// the same conversion rule used at var-init.
void test_SlicePassArrayAsArg_sema(void) {
	TEST_SETUP_SINGLE("fn void take(i32[] s) {} fn void f() { i32[3] arr = [1, 2, 3]; take(arr); }");
	TEST_ASSERT_EQUAL_STRING("", output);
	free(output);
}

// `null` is convertible to any slice — it produces the zero slice
// `{ null, 0 }`. Same shape as the `null → pointer` rule.
void test_SliceFromNull_sema(void) {
	TEST_SETUP_SINGLE("fn void f() { i32[] s = null; }");
	TEST_ASSERT_EQUAL_STRING("", output);
	free(output);
}

// A bare pointer is *not* implicitly a slice — slices carry a length and
// the language can't synthesize one out of thin air. This must be a sema
// error so users go through an explicit constructor instead.
void test_SliceFromPointerRejected_sema(void) {
	TEST_SETUP_SINGLE("fn void f() { i32 x = 0; i32* p = &x; i32[] s = p; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "Error"));
	free(output);
}

// Two `T[]` overloads with different element types must mangle distinctly
// from each other and from the `T*` overload — otherwise overload
// resolution silently collides them. Stage 1's resolver uses strict
// exact-match, so the call sites here pass slice / pointer values
// directly rather than relying on the array→slice decay.
void test_SliceOverloadMangling_sema(void) {
	TEST_SETUP_SINGLE("fn void f(i32[] s) {} fn void f(u8[] s) {} fn void f(i32* p) {} fn void g() { i32[] sa = null; u8[] sb = null; i32 x = 0; f(sa); f(sb); f(&x); }");
	TEST_ASSERT_EQUAL_STRING("", output);
	free(output);
}

// A struct literal against a slice lvalue is the slice constructor.
// Positional form is `{ptr, len}`, designated is `{.ptr=p, .len=n}`.
// Sema is the layer that connects the syntax to the slice type.
void test_SliceLiteralPositional_sema(void) {
	TEST_SETUP_SINGLE("fn void f(i32* p) { i32[] s = {p, 4}; }");
	TEST_ASSERT_EQUAL_STRING("", output);
	free(output);
}

void test_SliceLiteralDesignated_sema(void) {
	TEST_SETUP_SINGLE("fn void f(i32* p) { i32[] s = {.ptr = p, .len = 4}; }");
	TEST_ASSERT_EQUAL_STRING("", output);
	free(output);
}

void test_SliceLiteralWrongPtrType_sema(void) {
	TEST_SETUP_SINGLE("fn void f(u8* p) { i32[] s = {p, 4}; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "Error"));
	free(output);
}

void test_SliceLiteralWrongLenType_sema(void) {
	TEST_SETUP_SINGLE("fn void f(i32* p) { i32[] s = {p, 1.5}; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "Error"));
	free(output);
}

void test_SliceLiteralUnknownField_sema(void) {
	TEST_SETUP_SINGLE("fn void f(i32* p) { i32[] s = {.data = p, .len = 4}; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "unknown field 'data'"));
	free(output);
}

void test_SliceLiteralWrongArity_sema(void) {
	TEST_SETUP_SINGLE("fn void f(i32* p) { i32[] s = {p}; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "needs exactly 2 fields"));
	free(output);
}

// Sub-slicing accepts both array and slice bases and produces a `T[]`.
// Bounds must be integral; non-integer bounds are rejected.
void test_SliceRangeFromArray_sema(void) {
	TEST_SETUP_SINGLE("fn void f() { i32[5] arr = [1,2,3,4,5]; i32[] s = arr[1..3]; }");
	TEST_ASSERT_EQUAL_STRING("", output);
	free(output);
}

void test_SliceRangeFromSlice_sema(void) {
	TEST_SETUP_SINGLE("fn void f(i32[] s) { i32[] t = s[0..1]; }");
	TEST_ASSERT_EQUAL_STRING("", output);
	free(output);
}

void test_SliceRangeOnPointerRejected_sema(void) {
	TEST_SETUP_SINGLE("fn void f(i32* p) { i32[] s = p[0..1]; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "slice range can only be applied to arrays or slices"));
	free(output);
}

void test_SliceRangeNonIntBoundRejected_sema(void) {
	TEST_SETUP_SINGLE("fn void f(i32[] s) { i32[] t = s[0..1.5]; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "slice range bounds must be integers"));
	free(output);
}

// Indexing into a slice yields its element type — same shape as the
// existing array/pointer rules — and the index still has to be integral.
void test_SliceIndexValid_sema(void) {
	TEST_SETUP_SINGLE("fn i32 f(i32[] s) { return s[0]; }");
	TEST_ASSERT_EQUAL_STRING("", output);
	free(output);
}

void test_SliceIndexAssignableLvalue_sema(void) {
	TEST_SETUP_SINGLE("fn void f(i32[] s) { s[2] = 7; }");
	TEST_ASSERT_EQUAL_STRING("", output);
	free(output);
}

void test_SliceIndexNonIntRejected_sema(void) {
	TEST_SETUP_SINGLE("fn void f(i32[] s) { i32 x = s[1.5]; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "array index must be an integer type"));
	free(output);
}

// `.len` is the only valid member on slices and arrays. Sema must allow
// it on both and reject any other member name with a targeted message.
void test_SliceDotLen_sema(void) {
	TEST_SETUP_SINGLE("fn u64 f(i32[] s) { return s.len; }");
	TEST_ASSERT_EQUAL_STRING("", output);
	free(output);
}

void test_ArrayDotLen_sema(void) {
	TEST_SETUP_SINGLE("fn u64 f() { i32[5] a = [1,2,3,4,5]; return a.len; }");
	TEST_ASSERT_EQUAL_STRING("", output);
	free(output);
}

void test_SliceDotUnknownMemberRejected_sema(void) {
	TEST_SETUP_SINGLE("fn void f(i32[] s) { u64 x = s.cap; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "slice only exposes the 'len' member"));
	free(output);
}

void test_Switch_EnumSubject_WrongEnumMember_sema(void) {
	TEST_SETUP_SINGLE("enum Color : i32 { Red, Green, Blue }"
					  "enum Mode : i32 { On, Off }"
					  "fn void test() {"
					  "    Color c = Color::Red;"
					  "    switch (c) {"
					  "    case Mode::On: { c = Color::Red; }"
					  "    }"
					  "}");
	TEST_ASSERT_NOT_NULL(strstr(output, "case value belongs to enum Mode but switch subject is of enum Color"));
	free(output);
}

void test_LogicalAnd_PointerAndComparison_sema(void) {
	TEST_SETUP_SINGLE("fn void f() { i32* p = null; i32 a = 0; i32 b = 1; if (p && (a < b)) {} }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_LogicalAnd_ComparisonAndPointer_sema(void) {
	TEST_SETUP_SINGLE("fn void f() { i32* p = null; i32 a = 0; i32 b = 1; if ((a < b) && p) {} }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_LogicalOr_TwoPointers_sema(void) {
	TEST_SETUP_SINGLE("fn void f() { i32* p = null; i32* q = null; if (p || q) {} }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_LogicalAnd_NumericTruthy_sema(void) {
	TEST_SETUP_SINGLE("fn void f() { i32 a = 0; u64 b = 1; if (a && b) {} }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_LogicalAnd_StructOperand_Rejected_sema(void) {
	TEST_SETUP_SINGLE("struct S { i32 x; } fn void f() { S s = {0}; i32 a = 1; if (s && a) {} }");
	TEST_ASSERT_NOT_NULL(strstr(output, "logical '&&' requires a boolean-convertible left operand"));
	free(output);
}

void test_LogicalOr_StructOnRight_Rejected_sema(void) {
	TEST_SETUP_SINGLE("struct S { i32 x; } fn void f() { S s = {0}; i32 a = 1; if (a || s) {} }");
	TEST_ASSERT_NOT_NULL(strstr(output, "logical '||' requires a boolean-convertible right operand"));
	free(output);
}

void test_UnaryTilde_OnU8_sema(void) {
	TEST_SETUP_SINGLE("fn void f() { u8 a = 0; u8 b = ~a; }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_UnaryTilde_OnU16_sema(void) {
	TEST_SETUP_SINGLE("fn void f() { u16 a = 0; u16 b = ~a; }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_UnaryTilde_OnU32_sema(void) {
	TEST_SETUP_SINGLE("fn void f() { u32 a = 0; u32 b = ~a; }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_UnaryTilde_OnU64_sema(void) {
	TEST_SETUP_SINGLE("fn void f() { u64 a = 0; u64 b = ~a; }");
	const char *expected = "";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_UnaryTilde_OnFloat_Rejected_sema(void) {
	TEST_SETUP_SINGLE("fn void f() { f64 a = 0.0; f64 b = ~a; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "unary '~' requires integer operand"));
	free(output);
}

void test_UnaryTilde_OnBool_Rejected_sema(void) {
	TEST_SETUP_SINGLE("fn void f() { bool a = true; bool b = ~a; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "unary '~' requires integer operand"));
	free(output);
}

void test_UnaryTilde_OnPointer_Rejected_sema(void) {
	TEST_SETUP_SINGLE("fn void f() { i32* p = null; i32* q = ~p; }");
	TEST_ASSERT_NOT_NULL(strstr(output, "unary '~' requires integer operand"));
	free(output);
}

