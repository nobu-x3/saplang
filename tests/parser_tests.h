#pragma once

#include <parser.h>
#include <unity.h>

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
	const char *path = "parser_tests.sl";                                                                                                                                                                                                      \
	Scanner scanner;                                                                                                                                                                                                                           \
	scanner_init_from_string(&scanner, path, input);                                                                                                                                                                                           \
	Parser parser;                                                                                                                                                                                                                             \
	parser_init(&parser, scanner, NULL);                                                                                                                                                                                                       \
	Module *module = parse_input(&parser);                                                                                                                                                                                                     \
	char *output = capture_ast_output(module->ast);

void test_VariableDeclaration(void) {
	SETUP_TEST("i32 x = 42;");

	const char *expected = "VarDecl: i32 x:\n"
						   "  Literal Int: 42\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
	parser_deinit(&parser);
}

void test_ArithmeticExpression(void) {
	SETUP_TEST("i32 x = 1 + 2 * 3;");
	const char *expected = "VarDecl: i32 x:\n"
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
						   "      VarDecl: i32 result:\n"
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
	const char *expected = "VarDecl: i32 x:\n"
						   "  Literal Int: 42\n"
						   "VarDecl: const f64 y:\n"
						   "  Literal Float: 3.140000\n"
						   "VarDecl: bool flag:\n"
						   "  Literal Bool: true\n"
						   "VarDecl: i32 a\n"
						   "StructDecl: Point\n"
						   "  FieldDecl: i32 x\n"
						   "  FieldDecl: i32 y\n"
						   "FuncDecl: add\n"
						   "  Params:\n"
						   "    ParamDecl: i32 a\n"
						   "    ParamDecl: i32 b\n"
						   "  Body:\n"
						   "    Block with 2 statement(s):\n"
						   "      VarDecl: i32 result:\n"
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
						   "    ParamDecl: i32* x\n"
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
	const char *expected = "VarDecl: i32* x:\n"
						   "  Literal Int: 42\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_MultiPointer(void) {
	SETUP_TEST("i32** x = 42;");
	const char *expected = "VarDecl: i32** x:\n"
						   "  Literal Int: 42\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_CustomTypePointer(void) {
	SETUP_TEST("MyStruct** x = 42;");
	const char *expected = "VarDecl: MyStruct** x:\n"
						   "  Literal Int: 42\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ArrayLiterals(void) {
	SETUP_TEST("i32[4] arr1 = [0, 1, 2, 3];"
			   "i32[2][3] arr2 = [[1,2,3], [4,5,6]];");
	const char *expected = "VarDecl: i32[4] arr1:\n"
						   "  Array literal of size 4:\n"
						   "    Literal Int: 0\n"
						   "    Literal Int: 1\n"
						   "    Literal Int: 2\n"
						   "    Literal Int: 3\n"
						   "VarDecl: i32[2][3] arr2:\n"
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
						   "      VarDecl: i32[4] arr1:\n"
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
						   "      VarDecl: i32[4] arr1:\n"
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
						   "  FieldDecl: i32* field\n"
						   "VarDecl: MyStruct my_struct\n"
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
						   "  FieldDecl: i32* field\n"
						   "VarDecl: MyStruct* my_struct\n"
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
						   "VarDecl: MyStruct2 my_struct2\n"
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
	const char *expected = "VarDecl: ThreeIntStruct my_struct:\n"
						   "  StructLiteral with 3 initializer(s):\n"
						   "    Literal Int: 0\n"
						   "    Literal Int: 1\n"
						   "    Literal Int: 2\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StructLiteral_FullyNamed(void) {
	SETUP_TEST("ThreeIntStruct my_struct = {.second = 1, .first = 0, .third = 2};");
	const char *expected = "VarDecl: ThreeIntStruct my_struct:\n"
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
	const char *expected = "VarDecl: ThreeIntStruct my_struct:\n"
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
						   "VarDecl: Outer outer:\n"
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

void test_EnumDecl_WithReference(void) {
	SETUP_TEST("enum EnumType : u8 { First, Second = 234, Third, EVEN = Second }");
	const char *expected = "EnumDecl with 4 member(s) - EnumType : enum u8:\n"
						   "  First : 0\n"
						   "  Second : 234\n"
						   "  Third : 235\n"
						   "  EVEN : 234\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_EnumDecl_VariableDeclaration(void) {
	SETUP_TEST("enum EnumType { First, Second = 234, Third, EVEN = Second }"
			   "EnumType enum_var = EnumType::Second; ");
	const char *expected = "EnumDecl with 4 member(s) - EnumType : enum i32:\n"
						   "  First : 0\n"
						   "  Second : 234\n"
						   "  Third : 235\n"
						   "  EVEN : 234\n"
						   "VarDecl: EnumType enum_var:\n"
						   "  Ident: EnumType::Second\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ExternBlocks_FullIO(void) {
	SETUP_TEST("extern {"
			   "struct FILE {"
			   "        i8*   _ptr;"
			   "        i32 _cnt;"
			   "        i8*   _base;"
			   "        i32 _flag;"
			   "        i32 _file;"
			   "        i32 _charbuf;"
			   "        i32 _bufsiz;"
			   "        i8*   _tmpfname;"
			   "    }"
			   "    fn FILE* fopen(const u8* filename, const u8* mode);"
			   "    fn i32 fclose(FILE* file);"
			   "    fn void printf(const u8* str, ...);"
			   "    fn i32 fgetc(FILE* stream);"
			   "    fn i32 fputc(i32 ch, FILE* stream);"
			   "}");
	const char *expected = "ExternBlock from lib c:\n"
						   "  StructDecl: FILE\n"
						   "    FieldDecl: i8* _ptr\n"
						   "    FieldDecl: i32 _cnt\n"
						   "    FieldDecl: i8* _base\n"
						   "    FieldDecl: i32 _flag\n"
						   "    FieldDecl: i32 _file\n"
						   "    FieldDecl: i32 _charbuf\n"
						   "    FieldDecl: i32 _bufsiz\n"
						   "    FieldDecl: i8* _tmpfname\n"
						   "  Extern FuncDecl fopen:\n"
						   "    Params:\n"
						   "      ParamDecl: const u8* filename\n"
						   "      ParamDecl: const u8* mode\n"
						   "  Extern FuncDecl fclose:\n"
						   "    Params:\n"
						   "      ParamDecl: FILE* file\n"
						   "  Extern FuncDecl printf:\n"
						   "    Params:\n"
						   "      ParamDecl: const u8* str\n"
						   "      ParamDecl: ...\n"
						   "  Extern FuncDecl fgetc:\n"
						   "    Params:\n"
						   "      ParamDecl: FILE* stream\n"
						   "  Extern FuncDecl fputc:\n"
						   "    Params:\n"
						   "      ParamDecl: i32 ch\n"
						   "      ParamDecl: FILE* stream\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ExportedDecls(void) {
	SETUP_TEST("extern {"
			   "export struct FILE {"
			   "        i8*   _ptr;"
			   "        i32 _cnt;"
			   "        i8*   _base;"
			   "        i32 _flag;"
			   "        i32 _file;"
			   "        i32 _charbuf;"
			   "        i32 _bufsiz;"
			   "        i8*   _tmpfname;"
			   "    }"
			   "    export fn FILE* fopen(const u8* filename, const u8* mode);"
			   "    export fn i32 fclose(FILE* file);"
			   "    export fn void printf(const u8* str, ...);"
			   "    export fn i32 fgetc(FILE* stream);"
			   "    export fn i32 fputc(i32 ch, FILE* stream);"
			   "}");
	const char *expected = "ExternBlock from lib c:\n"
						   "  StructDecl: exported FILE\n"
						   "    FieldDecl: i8* _ptr\n"
						   "    FieldDecl: i32 _cnt\n"
						   "    FieldDecl: i8* _base\n"
						   "    FieldDecl: i32 _flag\n"
						   "    FieldDecl: i32 _file\n"
						   "    FieldDecl: i32 _charbuf\n"
						   "    FieldDecl: i32 _bufsiz\n"
						   "    FieldDecl: i8* _tmpfname\n"
						   "  Extern FuncDecl exported fopen:\n"
						   "    Params:\n"
						   "      ParamDecl: const u8* filename\n"
						   "      ParamDecl: const u8* mode\n"
						   "  Extern FuncDecl exported fclose:\n"
						   "    Params:\n"
						   "      ParamDecl: FILE* file\n"
						   "  Extern FuncDecl exported printf:\n"
						   "    Params:\n"
						   "      ParamDecl: const u8* str\n"
						   "      ParamDecl: ...\n"
						   "  Extern FuncDecl exported fgetc:\n"
						   "    Params:\n"
						   "      ParamDecl: FILE* stream\n"
						   "  Extern FuncDecl exported fputc:\n"
						   "    Params:\n"
						   "      ParamDecl: i32 ch\n"
						   "      ParamDecl: FILE* stream\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_Imports(void) {
	SETUP_TEST("import io;"
			   "import print;"
			   "enum EnumType { First, Second = 234, Third, EVEN = Second }"
			   "import some_module;");
	const char *expected = "EnumDecl with 4 member(s) - EnumType : enum i32:\n"
						   "  First : 0\n"
						   "  Second : 234\n"
						   "  Third : 235\n"
						   "  EVEN : 234\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_Namespaces_Functions(void) {
	SETUP_TEST("import io;"
			   "import print;"
			   "io::File* file = io::fopen();");
	const char *expected = "VarDecl: io::File* file:\n"
						   "  Function call with 0 args:\n"
						   "    Ident: io::fopen\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_IfStatements_NoElse(void) {
	SETUP_TEST("fn i32 test() {"
			   "    i32 x = 1;"
			   "    i32 y = 0;"
			   "    if(x) {"
			   "        y = 1;"
			   "    }"
			   "}");
	const char *expected = "FuncDecl: test\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 3 statement(s):\n"
						   "      VarDecl: i32 x:\n"
						   "        Literal Int: 1\n"
						   "      VarDecl: i32 y:\n"
						   "        Literal Int: 0\n"
						   "      IfElseStmt:\n"
						   "        Condition:\n"
						   "          Ident: x\n"
						   "        Then:\n"
						   "          Block with 1 statement(s):\n"
						   "            Assignment:\n"
						   "              Ident: y\n"
						   "              Literal Int: 1\n"
						   "        Else:\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_IfStatements_WithElse(void) {
	SETUP_TEST("fn i32 test() {"
			   "    i32 x = 1;"
			   "    i32 y = 0;"
			   "    if(x) {"
			   "        y = 1;"
			   "    } else {"
			   "        y = 2;"
			   "    }"
			   "}");
	const char *expected = "FuncDecl: test\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 3 statement(s):\n"
						   "      VarDecl: i32 x:\n"
						   "        Literal Int: 1\n"
						   "      VarDecl: i32 y:\n"
						   "        Literal Int: 0\n"
						   "      IfElseStmt:\n"
						   "        Condition:\n"
						   "          Ident: x\n"
						   "        Then:\n"
						   "          Block with 1 statement(s):\n"
						   "            Assignment:\n"
						   "              Ident: y\n"
						   "              Literal Int: 1\n"
						   "        Else:\n"
						   "          Block with 1 statement(s):\n"
						   "            Assignment:\n"
						   "              Ident: y\n"
						   "              Literal Int: 2\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_IfStatements_ElseIf(void) {
	SETUP_TEST("fn i32 test() {"
			   "    i32 x = 1;"
			   "    i32 y = 0;"
			   "    if(x) {"
			   "        y = 1;"
			   "    } else if(y){"
			   "        y = 2;"
			   "    } else {"
			   "        y = 2;"
			   "    }"
			   "}");
	const char *expected = "FuncDecl: test\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 3 statement(s):\n"
						   "      VarDecl: i32 x:\n"
						   "        Literal Int: 1\n"
						   "      VarDecl: i32 y:\n"
						   "        Literal Int: 0\n"
						   "      IfElseStmt:\n"
						   "        Condition:\n"
						   "          Ident: x\n"
						   "        Then:\n"
						   "          Block with 1 statement(s):\n"
						   "            Assignment:\n"
						   "              Ident: y\n"
						   "              Literal Int: 1\n"
						   "        Else:\n"
						   "          IfElseStmt:\n"
						   "            Condition:\n"
						   "              Ident: y\n"
						   "            Then:\n"
						   "              Block with 1 statement(s):\n"
						   "                Assignment:\n"
						   "                  Ident: y\n"
						   "                  Literal Int: 2\n"
						   "            Else:\n"
						   "              Block with 1 statement(s):\n"
						   "                Assignment:\n"
						   "                  Ident: y\n"
						   "                  Literal Int: 2\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ForLoop_Full(void) {
	SETUP_TEST("fn i32 test() {"
			   "    for (i32 i = 0; i < 10; i += 1) {    y = i;  }"
			   "}");
	const char *expected = "FuncDecl: test\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 1 statement(s):\n"
						   "      ForLoop:\n"
						   "        Init:\n"
						   "          VarDecl: i32 i:\n"
						   "            Literal Int: 0\n"
						   "        Condition:\n"
						   "          Binary Expression: <\n"
						   "            Ident: i\n"
						   "            Literal Int: 10\n"
						   "        Post:\n"
						   "          Assignment:\n"
						   "            Ident: i\n"
						   "            Binary Expression: +\n"
						   "              Ident: i\n"
						   "              Literal Int: 1\n"
						   "        Body:\n"
						   "          Block with 1 statement(s):\n"
						   "            Assignment:\n"
						   "              Ident: y\n"
						   "              Ident: i\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ForLoop_Empty(void) {
	SETUP_TEST("fn i32 test() {"
			   "    for (;;) {    y = i;  }"
			   "}");
	const char *expected = "FuncDecl: test\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 1 statement(s):\n"
						   "      ForLoop:\n"
						   "        Init:\n"
						   "        Condition:\n"
						   "        Post:\n"
						   "        Body:\n"
						   "          Block with 1 statement(s):\n"
						   "            Assignment:\n"
						   "              Ident: y\n"
						   "              Ident: i\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_WhileLoop(void) {
	SETUP_TEST("fn i32 test() {"
			   "    int condition = 1; while(condition) { y += 1; }"
			   "}");
	const char *expected = "FuncDecl: test\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 2 statement(s):\n"
						   "      VarDecl: int condition:\n"
						   "        Literal Int: 1\n"
						   "      WhileLoop:\n"
						   "        Condition:\n"
						   "          Ident: condition\n"
						   "        Body:\n"
						   "          Block with 1 statement(s):\n"
						   "            Assignment:\n"
						   "              Ident: y\n"
						   "              Binary Expression: +\n"
						   "                Ident: y\n"
						   "                Literal Int: 1\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_DeferStmts(void) {
	SETUP_TEST("fn void test() {"
			   "    FILE* file = fopen();"	 // yeah not actually the signature
			   "    defer { fclose(file); }" // yeah this would actly crash real program
			   "    if(!file) { return; }"
			   "    i32 a = 0;"
			   "    if(a == 0) { return; }"
			   "    if(a == 0) {  }"
			   "}");
	const char *expected = "FuncDecl: test\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 6 statement(s):\n"
						   "      VarDecl: FILE* file:\n"
						   "        Function call with 0 args:\n"
						   "          Ident: fopen\n"
						   "      IfElseStmt:\n"
						   "        Condition:\n"
						   "          Unary Expression: !\n"
						   "            Ident: file\n"
						   "        Then:\n"
						   "          Block with 2 statement(s):\n"
						   "            Function call with 1 args:\n"
						   "              Ident: fclose\n"
						   "              Ident: file\n"
						   "            Return:\n"
						   "        Else:\n"
						   "      VarDecl: i32 a:\n"
						   "        Literal Int: 0\n"
						   "      IfElseStmt:\n"
						   "        Condition:\n"
						   "          Binary Expression: ==\n"
						   "            Ident: a\n"
						   "            Literal Int: 0\n"
						   "        Then:\n"
						   "          Block with 2 statement(s):\n"
						   "            Function call with 1 args:\n"
						   "              Ident: fclose\n"
						   "              Ident: file\n"
						   "            Return:\n"
						   "        Else:\n"
						   "      IfElseStmt:\n"
						   "        Condition:\n"
						   "          Binary Expression: ==\n"
						   "            Ident: a\n"
						   "            Literal Int: 0\n"
						   "        Then:\n"
						   "          Block with 0 statement(s):\n"
						   "        Else:\n"
						   "      Function call with 1 args:\n"
						   "        Ident: fclose\n"
						   "        Ident: file\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_FnPtr_BasicDeclNoParam(void) {
	SETUP_TEST("fn* void() test_fn_ptr;");
	const char *expected = "VarDecl: fn()->void test_fn_ptr\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_FnPtr_BasicDeclWithParams(void) {
	SETUP_TEST("fn* void(i32, i64) test_fn_ptr;");
	const char *expected = "VarDecl: fn(i32, i64)->void test_fn_ptr\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_FnPtr_BasicCall(void) {
	SETUP_TEST("fn* void(i32, i64) test_fn_ptr;"
			   "fn void main() {"
			   "   test_fn_ptr(0, 1);"
			   "}");
	const char *expected = "VarDecl: fn(i32, i64)->void test_fn_ptr\n"
						   "FuncDecl: main\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 1 statement(s):\n"
						   "      Function call with 2 args:\n"
						   "        Ident: test_fn_ptr\n"
						   "        Literal Int: 0\n"
						   "        Literal Int: 1\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_FnPtr_BasicAssignment(void) {
	SETUP_TEST("fn* void(i32, i64) test_fn_ptr;"
			   "fn void foo(i32 a, i64 b){}"
			   "fn void main() {"
			   "   test_fn_ptr = &foo;"
			   "   test_fn_ptr(0, 1);"
			   "}");
	const char *expected = "VarDecl: fn(i32, i64)->void test_fn_ptr\n"
						   "FuncDecl: foo\n"
						   "  Params:\n"
						   "    ParamDecl: i32 a\n"
						   "    ParamDecl: i64 b\n"
						   "  Body:\n"
						   "    Block with 0 statement(s):\n"
						   "FuncDecl: main\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 2 statement(s):\n"
						   "      Assignment:\n"
						   "        Ident: test_fn_ptr\n"
						   "        Unary Expression: &\n"
						   "          Ident: foo\n"
						   "      Function call with 2 args:\n"
						   "        Ident: test_fn_ptr\n"
						   "        Literal Int: 0\n"
						   "        Literal Int: 1\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_FnPtr_StructFieldAssignment(void) {
	SETUP_TEST("struct SomeStruct { fn* void(i32, i64) test_fn_ptr; }"
			   "fn void foo(i32 a, i64 b){}"
			   "fn void main() {"
			   "   SomeStruct str = {&foo};"
			   "   str.test_fn_ptr(0, 1);"
			   "}");
	const char *expected = "StructDecl: SomeStruct\n"
						   "  FieldDecl: fn(i32, i64)->void test_fn_ptr\n"
						   "FuncDecl: foo\n"
						   "  Params:\n"
						   "    ParamDecl: i32 a\n"
						   "    ParamDecl: i64 b\n"
						   "  Body:\n"
						   "    Block with 0 statement(s):\n"
						   "FuncDecl: main\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 2 statement(s):\n"
						   "      VarDecl: SomeStruct str:\n"
						   "        StructLiteral with 1 initializer(s):\n"
						   "          Unary Expression: &\n"
						   "            Ident: foo\n"
						   "      Function call with 2 args:\n"
						   "        Member access: test_fn_ptr\n"
						   "          Ident: str\n"
						   "        Literal Int: 0\n"
						   "        Literal Int: 1\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_Binops_AndOrSelf(void) {
	SETUP_TEST("fn void main() {"
			   "   i32 a = 0;"
			   "   i32 b = 0;"
			   "   if(a || a && b){"
			   "        a |= 1; b &= 0;"
			   "    }"
			   "}");
	const char *expected = "FuncDecl: main\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 3 statement(s):\n"
						   "      VarDecl: i32 a:\n"
						   "        Literal Int: 0\n"
						   "      VarDecl: i32 b:\n"
						   "        Literal Int: 0\n"
						   "      IfElseStmt:\n"
						   "        Condition:\n"
						   "          Binary Expression: ||\n"
						   "            Ident: a\n"
						   "            Binary Expression: &&\n"
						   "              Ident: a\n"
						   "              Ident: b\n"
						   "        Then:\n"
						   "          Block with 2 statement(s):\n"
						   "            Assignment:\n"
						   "              Ident: a\n"
						   "              Binary Expression: |\n"
						   "                Ident: a\n"
						   "                Literal Int: 1\n"
						   "            Assignment:\n"
						   "              Ident: b\n"
						   "              Binary Expression: &\n"
						   "                Ident: b\n"
						   "                Literal Int: 0\n"
						   "        Else:\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_StringLiteral(void) {
	SETUP_TEST("fn void main() {"
			   "   const u8* a = \"Hello world\n\";"
			   "}");
	const char *expected = "FuncDecl: main\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 1 statement(s):\n"
						   "      VarDecl: const u8* a:\n"
						   "        String Literal: \"Hello world\n\"\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_CharLiteral(void) {
	SETUP_TEST("fn void main() {"
			   "   const u8 a = 'a';"
			   "   const u8 newline = '\n';"
			   "}");
	const char *expected = "FuncDecl: main\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 2 statement(s):\n"
						   "      VarDecl: const u8 a:\n"
						   "        Char Literal: 'a'\n"
						   "      VarDecl: const u8 newline:\n"
						   "        Char Literal: '\n'\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_BinaryLiteral(void) {
	SETUP_TEST("const u8 a = 0b0101_0000_1111_0101;");
	const char *expected = "VarDecl: const u8 a:\n  Literal Int: 20725\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_HexadecimalLiteral(void) {
	SETUP_TEST("const u8 a = 0x1_A_3f;");
	const char *expected = "VarDecl: const u8 a:\n  Literal Int: 6719\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}

void test_ContinueBreak(void) {
	SETUP_TEST("fn i32 test() {"
			   "    for (i32 i = 0; i < 10; i += 1) {"
			   "        y = i;"
			   "        if(i % 2 == 0){"
			   "            break;"
			   "        } else {"
			   "            continue;"
			   "        }"
			   "    }"
			   "}");
	const char *expected = "FuncDecl: test\n"
						   "  Params:\n"
						   "  Body:\n"
						   "    Block with 1 statement(s):\n"
						   "      ForLoop:\n"
						   "        Init:\n"
						   "          VarDecl: i32 i:\n"
						   "            Literal Int: 0\n"
						   "        Condition:\n"
						   "          Binary Expression: <\n"
						   "            Ident: i\n"
						   "            Literal Int: 10\n"
						   "        Post:\n"
						   "          Assignment:\n"
						   "            Ident: i\n"
						   "            Binary Expression: +\n"
						   "              Ident: i\n"
						   "              Literal Int: 1\n"
						   "        Body:\n"
						   "          Block with 2 statement(s):\n"
						   "            Assignment:\n"
						   "              Ident: y\n"
						   "              Ident: i\n"
						   "            IfElseStmt:\n"
						   "              Condition:\n"
						   "                Binary Expression: ==\n"
						   "                  Binary Expression: %\n"
						   "                    Ident: i\n"
						   "                    Literal Int: 2\n"
						   "                  Literal Int: 0\n"
						   "              Then:\n"
						   "                Block with 1 statement(s):\n"
						   "                  break\n"
						   "              Else:\n"
						   "                Block with 1 statement(s):\n"
						   "                  continue\n";
	TEST_ASSERT_EQUAL_STRING(expected, output);
	free(output);
}
