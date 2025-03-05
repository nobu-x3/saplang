#include <parser.h>
#include <unity.h>

void setUp() {}

void tearDown() {}

//---------------------------------------------------------------------
// Helper function: Capture the output of printAST() into a string.
// This function temporarily redirects stdout to a temporary file, calls printAST,
// then reads the file contents into a malloc()ed string.
//---------------------------------------------------------------------
static char *capture_ast_output(ASTNode *ast) {
	// Create a temporary file.
	FILE *temp = tmpfile();
	if (!temp) {
		TEST_FAIL_MESSAGE("Failed to create temporary file for output capture");
	}

	// Save the current stdout pointer.
	FILE *old_stdout = stdout;
	stdout = temp;

	// Print the AST.
	ast_print(ast, 0, NULL);
	fflush(stdout);

	// Restore stdout.
	stdout = old_stdout;

	// Determine the size of the output.
	fseek(temp, 0, SEEK_END);
	long size = ftell(temp);
	fseek(temp, 0, SEEK_SET);

	char *buffer = malloc(size + 1);
	if (!buffer) {
		fclose(temp);
		TEST_FAIL_MESSAGE("Memory allocation failed in captureASTOutput");
	}

	fread(buffer, 1, size, temp);
	buffer[size] = '\0';

	fclose(temp);
	return buffer;
}

#define SETUP_TEST(input_string)                                                                                                                                                                                                               \
	const char *input = input_string;                                                                                                                                                                                                          \
	const char path[5] = "test";                                                                                                                                                                                                               \
	Scanner scanner;                                                                                                                                                                                                                           \
	scanner_init(&scanner, path, input);                                                                                                                                                                                                       \
	Parser parser;                                                                                                                                                                                                                             \
	parser_init(&parser, scanner, NULL);                                                                                                                                                                                                       \
	ASTNode *ast = parse_input(&parser);                                                                                                                                                                                                       \
	char *output = capture_ast_output(ast);

void test_VariableDeclaration(void) {
	SETUP_TEST("i32 x = 42;");

	const char *expected = "VarDecl:  i32 x:\n"
						   "  Literal Int: 42\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
	parser_deinit(&parser);
}

void test_ArithmeticExpression(void) {
	SETUP_TEST("i32 x = 1 + 2 * 3;");
	const char *expected = "VarDecl:  i32 x:\n"
						   "  Binary Expression: +\n"
						   "    Literal Int: 1\n"
						   "    Binary Expression: *\n"
						   "      Literal Int: 2\n"
						   "      Literal Int: 3\n";

	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructDeclaration(void) {
	SETUP_TEST("struct Point { i32 x; i32 y; }");
	const char *expected = "StructDecl: Point\n"
						   "  FieldDecl: i32 x\n"
						   "  FieldDecl: i32 y\n";

	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_FunctionDeclaration(void) {
	SETUP_TEST("fn i32 add(i32 a, i32 b) { i32 result = a + b * 2; return result - 1; }");
	const char *expected = "FuncDecl: add\n"
						   "  Params:\n"
						   "    ParamDecl: i32 a\n"
						   "    ParamDecl: i32 b\n"
						   "  Body:\n"
						   "    Block with 2 statement(s):\n"
						   "      VarDecl:  i32 result:\n"
						   "        Binary Expression: +\n"
						   "          Ident: a\n"
						   "          Binary Expression: *\n"
						   "            Ident: b\n"
						   "            Literal Int: 2\n"
						   "      Return:\n"
						   "        Binary Expression: -\n"
						   "          Ident: result\n"
						   "          Literal Int: 1\n";

	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_CombinedDeclarations(void) {
	SETUP_TEST("i32 x = 42;\n"
			   "const f64 y = 3.14; "
			   "bool flag = true; "
			   "i32 a;"
			   "struct Point { i32 x; i32 y; } "
			   "fn i32 add(i32 a, i32 b) {"
			   " i32 result = a + b * 2;"
			   " return result - 1;"
			   "}");
	const char *expected = "VarDecl:  i32 x:\n"
						   "  Literal Int: 42\n"
						   "VarDecl: const f64 y:\n"
						   "  Literal Float: 3.140000\n"
						   "VarDecl:  bool flag:\n"
						   "  Literal Bool: true\n"
						   "VarDecl:  i32 a\n"
						   "StructDecl: Point\n"
						   "  FieldDecl: i32 x\n"
						   "  FieldDecl: i32 y\n"
						   "FuncDecl: add\n"
						   "  Params:\n"
						   "    ParamDecl: i32 a\n"
						   "    ParamDecl: i32 b\n"
						   "  Body:\n"
						   "    Block with 2 statement(s):\n"
						   "      VarDecl:  i32 result:\n"
						   "        Binary Expression: +\n"
						   "          Ident: a\n"
						   "          Binary Expression: *\n"
						   "            Ident: b\n"
						   "            Literal Int: 2\n"
						   "      Return:\n"
						   "        Binary Expression: -\n"
						   "          Ident: result\n"
						   "          Literal Int: 1\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_UnaryExpression_Exclamation(void) {
	SETUP_TEST("fn bool test() { return !false; }");
	const char *expected = "FuncDecl: test\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 1 statement(s):\n"
						   "      Return:\n"
						   "        Unary Expression: !\n"
						   "          Literal Bool: false\n";

	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_UnaryExpression_Dereference(void) {
	SETUP_TEST("fn i32 test(i32* x) { return *x; }");
	const char *expected = "FuncDecl: test\n"
						   "  Params:\n"
						   "    ParamDecl: *i32 x\n"
						   "  Body:\n"
						   "    Block with 1 statement(s):\n"
						   "      Return:\n"
						   "        Unary Expression: *\n"
						   "          Ident: x\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_UnaryExpression_AddressOf(void) {
	SETUP_TEST("fn i32* test(i32 x) { return &x; }");
	const char *expected = "FuncDecl: test\n"
						   "  Params:\n"
						   "    ParamDecl: i32 x\n"
						   "  Body:\n"
						   "    Block with 1 statement(s):\n"
						   "      Return:\n"
						   "        Unary Expression: &\n"
						   "          Ident: x\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_SinglePointer(void) {
	SETUP_TEST("i32* x = 42;");
	const char *expected = "VarDecl:  *i32 x:\n"
						   "  Literal Int: 42\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_MultiPointer(void) {
	SETUP_TEST("i32** x = 42;");
	const char *expected = "VarDecl:  **i32 x:\n"
						   "  Literal Int: 42\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_CustomTypePointer(void) {
	SETUP_TEST("MyStruct** x = 42;");
	const char *expected = "VarDecl:  **MyStruct x:\n"
						   "  Literal Int: 42\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ArrayLiterals(void) {
	SETUP_TEST("i32[4] arr1 = [0, 1, 2, 3];"
			   "i32[2][3] arr2 = [[1,2,3], [4,5,6]];");
	const char *expected = "VarDecl:  [4]i32 arr1:\n"
						   "  Array literal of size 4:\n"
						   "    Literal Int: 0\n"
						   "    Literal Int: 1\n"
						   "    Literal Int: 2\n"
						   "    Literal Int: 3\n"
						   "VarDecl:  [2][3]i32 arr2:\n"
						   "  Array literal of size 2:\n"
						   "    Array literal of size 3:\n"
						   "      Literal Int: 1\n"
						   "      Literal Int: 2\n"
						   "      Literal Int: 3\n"
						   "    Array literal of size 3:\n"
						   "      Literal Int: 4\n"
						   "      Literal Int: 5\n"
						   "      Literal Int: 6\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ArrayAccessAssignment(void) {
	SETUP_TEST("fn i32 test() {"
			   "    i32[4] arr1 = [0, 1, 2, 3];"
			   "    arr1[0] = 1;"
			   "    return arr[0];"
			   "}");
	const char *expected = ""
						   "FuncDecl: test\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 3 statement(s):\n"
						   "      VarDecl:  [4]i32 arr1:\n"
						   "        Array literal of size 4:\n"
						   "          Literal Int: 0\n"
						   "          Literal Int: 1\n"
						   "          Literal Int: 2\n"
						   "          Literal Int: 3\n"
						   "      Assignment:\n"
						   "        Array access:\n"
						   "          Ident: arr1\n"
						   "          Literal Int: 0\n"
						   "        Literal Int: 1\n"
						   "      Return:\n"
						   "        Array access:\n"
						   "          Ident: arr\n"
						   "          Literal Int: 0\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_FunctionCallsWithLiteralArguments(void) {
	SETUP_TEST("fn void foo(i32 a, i32 b) {}"
			   "fn i32 test() {"
			   "   foo(1, 2 + 3);"
			   "   return 0;"
			   "}");
	const char *expected = "FuncDecl: foo\n"
						   "  Params:\n"
						   "    ParamDecl: i32 a\n"
						   "    ParamDecl: i32 b\n"
						   "  Body:\n"
						   "    Block with 0 statement(s):\n"
						   "FuncDecl: test\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 2 statement(s):\n"
						   "      Function call with 2 args:\n"
						   "        Ident: foo\n"
						   "        Literal Int: 1\n"
						   "        Binary Expression: +\n"
						   "          Literal Int: 2\n"
						   "          Literal Int: 3\n"
						   "      Return:\n"
						   "        Literal Int: 0\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_FunctionCallsWithExprArguments(void) {
	SETUP_TEST("fn void foo(i32 a, i32 b) {}"
			   "fn i32 test() {"
			   "    i32[4] arr1 = [0, 1, 2, 3];"
			   "   foo(arr[0], arr[1] + arr[2]);"
			   "   return 0;"
			   "}");
	const char *expected = "FuncDecl: foo\n"
						   "  Params:\n"
						   "    ParamDecl: i32 a\n"
						   "    ParamDecl: i32 b\n"
						   "  Body:\n"
						   "    Block with 0 statement(s):\n"
						   "FuncDecl: test\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 3 statement(s):\n"
						   "      VarDecl:  [4]i32 arr1:\n"
						   "        Array literal of size 4:\n"
						   "          Literal Int: 0\n"
						   "          Literal Int: 1\n"
						   "          Literal Int: 2\n"
						   "          Literal Int: 3\n"
						   "      Function call with 2 args:\n"
						   "        Ident: foo\n"
						   "        Array access:\n"
						   "          Ident: arr\n"
						   "          Literal Int: 0\n"
						   "        Binary Expression: +\n"
						   "          Array access:\n"
						   "            Ident: arr\n"
						   "            Literal Int: 1\n"
						   "          Array access:\n"
						   "            Ident: arr\n"
						   "            Literal Int: 2\n"
						   "      Return:\n"
						   "        Literal Int: 0\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_FunctionCallsNoArguments(void) {
	SETUP_TEST("fn void foo() {}"
			   "fn i32 test() {"
			   "   foo();"
			   "   return 0;"
			   "}");
	const char *expected = "FuncDecl: foo\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 0 statement(s):\n"
						   "FuncDecl: test\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 2 statement(s):\n"
						   "      Function call with 0 args:\n"
						   "        Ident: foo\n"
						   "      Return:\n"
						   "        Literal Int: 0\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_MemberAccessSingle_Value(void) {
	SETUP_TEST("struct MyStruct { i32* field; }"
			   "MyStruct my_struct; "
			   "fn void test() { my_struct.field = 0; }");
	const char *expected = "StructDecl: MyStruct\n"
						   "  FieldDecl: *i32 field\n"
						   "VarDecl:  MyStruct my_struct\n"
						   "FuncDecl: test\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 1 statement(s):\n"
						   "      Assignment:\n"
						   "        Member access: field\n"
						   "          Ident: my_struct\n"
						   "        Literal Int: 0\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_MemberAccessSingle_Pointer(void) {
	SETUP_TEST("struct MyStruct { i32* field; }"
			   "MyStruct* my_struct; "
			   "fn void test() { my_struct.field = 0; }");
	const char *expected = "StructDecl: MyStruct\n"
						   "  FieldDecl: *i32 field\n"
						   "VarDecl:  *MyStruct my_struct\n"
						   "FuncDecl: test\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 1 statement(s):\n"
						   "      Assignment:\n"
						   "        Member access: field\n"
						   "          Ident: my_struct\n"
						   "        Literal Int: 0\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_MemberAccessMulti_Pointer(void) {
	SETUP_TEST("struct MyStruct1 { i32 int_field; }"
			   "struct MyStruct2 { MyStruct1 field; }"
			   "MyStruct2 my_struct2; "
			   "fn void test() { my_struct2.field.int_field = 0; }");
	const char *expected = "StructDecl: MyStruct1\n"
						   "  FieldDecl: i32 int_field\n"
						   "StructDecl: MyStruct2\n"
						   "  FieldDecl: MyStruct1 field\n"
						   "VarDecl:  MyStruct2 my_struct2\n"
						   "FuncDecl: test\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 1 statement(s):\n"
						   "      Assignment:\n"
						   "        Member access: int_field\n"
						   "          Member access: field\n"
						   "            Ident: my_struct2\n"
						   "        Literal Int: 0\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteral_FullyUnnamed(void) {
	SETUP_TEST("ThreeIntStruct my_struct = {0, 1, 2};");
	const char *expected = "VarDecl:  ThreeIntStruct my_struct:\n"
						   "  StructLiteral with 3 initializer(s):\n"
						   "    Literal Int: 0\n"
						   "    Literal Int: 1\n"
						   "    Literal Int: 2\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteral_FullyNamed(void) {
	SETUP_TEST("ThreeIntStruct my_struct = {.second = 1, .first = 0, .third = 2};");
	const char *expected = "VarDecl:  ThreeIntStruct my_struct:\n"
						   "  StructLiteral with 3 initializer(s):\n"
						   "    Designated, field 'second':\n"
						   "      Literal Int: 1\n"
						   "    Designated, field 'first':\n"
						   "      Literal Int: 0\n"
						   "    Designated, field 'third':\n"
						   "      Literal Int: 2\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteral_Mixed(void) {
	SETUP_TEST("ThreeIntStruct my_struct = {.second = 1, 2, .first = 0};");
	const char *expected = "VarDecl:  ThreeIntStruct my_struct:\n"
						   "  StructLiteral with 3 initializer(s):\n"
						   "    Designated, field 'second':\n"
						   "      Literal Int: 1\n"
						   "    Literal Int: 2\n"
						   "    Designated, field 'first':\n"
						   "      Literal Int: 0\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteral_Nested(void) {
	SETUP_TEST("struct Inner { i32 x; i32 y; }"
			   "struct Outer { Inner a; Inner b; } "
			   "Outer outer = { {0, 1}, {2, 3} };");
	const char *expected = "StructDecl: Inner\n"
						   "  FieldDecl: i32 x\n"
						   "  FieldDecl: i32 y\n"
						   "StructDecl: Outer\n"
						   "  FieldDecl: Inner a\n"
						   "  FieldDecl: Inner b\n"
						   "VarDecl:  Outer outer:\n"
						   "  StructLiteral with 2 initializer(s):\n"
						   "    StructLiteral with 2 initializer(s):\n"
						   "      Literal Int: 0\n"
						   "      Literal Int: 1\n"
						   "    StructLiteral with 2 initializer(s):\n"
						   "      Literal Int: 2\n"
						   "      Literal Int: 3\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}
