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

#define SETUP_TEST(input_string) \
  const char *input = input_string; \
  const char *path = "test"; \
  Scanner scanner; \
  scanner_init(&scanner, path, input); \
  Parser parser; \
  parser_init(&parser, scanner, NULL); \
  ASTNode *ast = parse_input(&parser); \
  char *output = capture_ast_output(ast);

//---------------------------------------------------------------------
// Test Case 1: Simple Variable Declaration
// Input: "i32 x = 42;"
// Expected AST (as printed by the existing printAST function):
//      VarDecl:  i32 x:
//          Literal Int: 42;

//---------------------------------------------------------------------
void test_VariableDeclaration(void) {
    SETUP_TEST(R"(i32 x = 42;)");

  const char *expected =
      "VarDecl:  i32 x:\n"
      "  Literal Int: 42\n";
  TEST_ASSERT_EQUAL_STRING(expected, output);
  free(output);
  parser_deinit(&parser);
}

//---------------------------------------------------------------------
// Test Case 2: Arithmetic Expression in a Variable Declaration
// Input: "i32 x = 1 + 2 * 3;"
// Expected AST:
//    VarDecl:  i32 x:
//      Binary Expression: +
//        Literal Int: 1
//        Binary Expression: *
//          Literal Int: 2
//          Literal Int: 3;

//---------------------------------------------------------------------
void test_ArithmeticExpression(void) {
  SETUP_TEST(R"(i32 x = 1 + 2 * 3;)");;
  const char *expected =
    "VarDecl:  i32 x:\n"
    "  Binary Expression: +\n"
    "    Literal Int: 1\n"
    "    Binary Expression: *\n"
    "      Literal Int: 2\n"
    "      Literal Int: 3\n";

  TEST_ASSERT_EQUAL_STRING(expected, output);
  free(output);
}

//---------------------------------------------------------------------
// Test Case 3: Struct Declaration
// Input: "struct Point { i32 x; i32 y; };"
// Expected AST (with indenting as produced by printAST):
//   StructDecl: Point
//     FieldDecl: i32 x
//     FieldDecl: i32 y
//---------------------------------------------------------------------
void test_StructDeclaration(void) {
  SETUP_TEST("struct Point { i32 x; i32 y; }");
  const char *expected = "StructDecl: Point\n"
                         "  FieldDecl: i32 x\n"
                         "  FieldDecl: i32 y\n";

  TEST_ASSERT_EQUAL_STRING(expected, output);
  free(output);
}

//---------------------------------------------------------------------
// Test Case 4: Function Declaration with Return Statement and Arithmetic
// Input: "func add(i32 a, i32 b) { i32 result = a + b * 2; return result - 1; }"
// Expected AST:
//      FuncDecl: add
//        Params:
//          ParamDecl: i32 a
//          ParamDecl: i32 b
//        Body:
//          Block with 2 statement(s):
//            VarDecl:  i32 result:
//              Binary Expression: +
//                Ident: a
//                Binary Expression: *
//                  Ident: b
//                  Literal Int: 2
//            Return:
//              Binary Expression: -
//                Ident: result
//                Literal Int: 1;
//---------------------------------------------------------------------
void test_FunctionDeclaration(void) {
  SETUP_TEST("fn i32 add(i32 a, i32 b) { i32 result = a + b * 2; return result - 1; }");
  const char *expected =
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

//---------------------------------------------------------------------
// Test Case 5: Combined Global Declarations
// Input includes variable declarations (with various types), a struct, and a function.
//---------------------------------------------------------------------
void test_CombinedDeclarations(void) {
SETUP_TEST("i32 x = 42; "
          "const f64 y = 3.14; "
          "bool flag = true; "
          "i32 a;"
          "struct Point { i32 x; i32 y; } "
          "fn i32 add(i32 a, i32 b) {"
          " i32 result = a + b * 2;"
          " return result - 1;"
          "}");
  const char *expected =
      "VarDecl:  i32 x:\n"
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
