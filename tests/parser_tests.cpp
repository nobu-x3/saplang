#include <catch2/catch_test_macros.hpp>

#include <sstream>
#include <string>

#include <lexer.h>
#include <parser.h>
#include <utils.h>

#define TEST_SETUP(file_contents)                                              \
  saplang::clear_error_stream();                                               \
  std::stringstream buffer{file_contents};                                     \
  std::stringstream output_buffer{};                                           \
  saplang::SourceFile src_file{"test", buffer.str()};                          \
  saplang::Lexer lexer{src_file};                                              \
  saplang::Parser parser(&lexer);                                              \
  auto parse_result = parser.parse_source_file();                              \
  for (auto &&fn : parse_result.functions) {                                   \
    fn->dump_to_stream(output_buffer);                                         \
  }                                                                            \
  const auto &error_stream = saplang::get_error_stream();

TEST_CASE("Function declarations", "[parser]") {
  SECTION("Undeclared function name") {
    TEST_SETUP(R"(fn{}))");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() == "test:1:3 error: expected type specifier.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("expected function identifier") {
    TEST_SETUP(R"(fn int{}))");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            "test:1:7 error: expected function identifier.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("expected '('") {
    TEST_SETUP(R"(fn int f{}))");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() == "test:1:9 error: expected '('.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("expected parameter declaration") {
    TEST_SETUP(R"(fn int f({})");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            "test:1:10 error: expected parameter declaration.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("expected parameter identifier") {
    TEST_SETUP(R"(fn int f(int{})");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() == "test:1:10 error: expected identifier.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("Expected '{'") {
    TEST_SETUP(R"(fn int f(int a)})");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            R"(test:1:16 error: expected '{' at the beginning of a block.
test:1:16 error: failed to parse function block.
)");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("Expected '}'") {
    TEST_SETUP(R"(fn int f(int a){)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            R"(test:1:17 error: expected '}' at the end of a block.
test:1:17 error: failed to parse function block.
)");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("Forward decl attempt") {
    TEST_SETUP(R"(fn int f(int a);)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            R"(test:1:16 error: expected '{' at the beginning of a block.
test:1:16 error: failed to parse function block.
)");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("Correct function declaration") {
    TEST_SETUP(R"(fn int f(int a){})");
    REQUIRE(output_buffer.str() == R"(FunctionDecl: f:int
  ParamDecl: a:int
  Block
)");
    REQUIRE(error_stream.str().empty());
    REQUIRE(parser.is_complete_ast());
  }
  SECTION("Multiple function declarations") {
    TEST_SETUP(R"(
fn int f(int a){}
fn void foo(){}
fn void bar(){}
)");
    REQUIRE(output_buffer.str() ==
            R"(FunctionDecl: f:int
  ParamDecl: a:int
  Block
FunctionDecl: foo:void
  Block
FunctionDecl: bar:void
  Block
)");
    REQUIRE(error_stream.str().empty());
    REQUIRE(parser.is_complete_ast());
  }
}

TEST_CASE("Primary", "[parser]") {
  SECTION("Incorrect number literals") {
    TEST_SETUP(
        R"(
fn void main() {
    .0;
    0.;
}
)");
    REQUIRE(output_buffer.str() ==
            R"(FunctionDecl: main:void
  Block
)");
    REQUIRE(error_stream.str() ==
            R"(test:3:5 error: expected expression.
test:4:5 error: expected expression.
)");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("Correct number literals") {
    TEST_SETUP(R"(
fn void main(){
    1;
    1.0;
}
)");
    REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    NumberLiteral: integer(1)
    NumberLiteral: real(1.0)
)");
    REQUIRE(error_stream.str().empty());
    REQUIRE(parser.is_complete_ast());
  }
  SECTION("Incorrect function calls") {
    TEST_SETUP(
        R"(
fn void main() {
    a(;
    a(x;
    a(x,;
}
)");
    REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
)");
    REQUIRE(error_stream.str() == R"(test:3:7 error: expected expression.
test:4:8 error: expected ')'.
test:5:9 error: expected expression.
)");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("Correct function calls") {
    TEST_SETUP(R"(
fn void main() {
    a;
    a();
    a(1.0, 2);
}
)");
    REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    DeclRefExpr: a
    CallExpr:
      DeclRefExpr: a
    CallExpr:
      DeclRefExpr: a
      NumberLiteral: real(1.0)
      NumberLiteral: integer(2)
)");
    REQUIRE(error_stream.str().empty());
    REQUIRE(parser.is_complete_ast());
  }
}

TEST_CASE("Missing semicolon", "[parser]") {
  TEST_SETUP(R"(
fn void main() {
    a(1.0, 2)
}
)");
  REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
)");
  REQUIRE(error_stream.str() ==
          R"(test:4:1 error: expected ';' at the end of a statement.
)");
  REQUIRE(!parser.is_complete_ast());
}