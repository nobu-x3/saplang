#include <catch2/catch_test_macros.hpp>

#include <sstream>
#include <string>

#include <lexer.h>
#include <parser.h>
#include <utils.h>

#define TEST_SETUP(file_contents)                                              \
  std::stringstream buffer{file_contents};                                     \
  std::stringstream output_buffer{};                                           \
  saplang::SourceFile src_file{"test", buffer.str()};                          \
  saplang::Lexer lexer{src_file};                                              \
  saplang::Parser parser(&lexer);                                              \
  auto parse_result = parser.parse_source_file();                              \
  for (auto &&fn : parse_result.functions) {                                   \
    fn->dump_to_stream(output_buffer);                                         \
  }

TEST_CASE("Function declarations", "[parser]") {
  SECTION("Undeclared function name") {
    TEST_SETUP(R"(fn{}))");
    REQUIRE(output_buffer.str().empty());
    const auto &error_stream = saplang::get_error_stream();
    REQUIRE(error_stream.str() == "test:1:3 error: expected type specifier.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  saplang::clear_error_stream();
  SECTION("expected function identifier") {
    TEST_SETUP(R"(fn int{}))");
    REQUIRE(output_buffer.str().empty());
    const auto &error_stream = saplang::get_error_stream();
    REQUIRE(error_stream.str() ==
            "test:1:7 error: expected function identifier.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  saplang::clear_error_stream();
  SECTION("expected '('") {
    TEST_SETUP(R"(fn int f{}))");
    REQUIRE(output_buffer.str().empty());
    const auto &error_stream = saplang::get_error_stream();
    REQUIRE(error_stream.str() == "test:1:9 error: expected '('.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  saplang::clear_error_stream();
  SECTION("expected parameter declaration") {
    TEST_SETUP(R"(fn int f({})");
    REQUIRE(output_buffer.str().empty());
    const auto &error_stream = saplang::get_error_stream();
    REQUIRE(error_stream.str() ==
            "test:1:10 error: expected parameter declaration.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  saplang::clear_error_stream();
  SECTION("expected parameter identifier") {
    TEST_SETUP(R"(fn int f(int{})");
    REQUIRE(output_buffer.str().empty());
    const auto &error_stream = saplang::get_error_stream();
    REQUIRE(error_stream.str() == "test:1:10 error: expected identifier.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  saplang::clear_error_stream();
  SECTION("Expected '{'") {
    TEST_SETUP(R"(fn int f(int a)})");
    REQUIRE(output_buffer.str().empty());
    const auto &error_stream = saplang::get_error_stream();
    REQUIRE(error_stream.str() ==
            R"(test:1:16 error: expected '{' at the beginning of a block.
test:1:16 error: failed to parse function block.
)");
    REQUIRE(!parser.is_complete_ast());
  }
  saplang::clear_error_stream();
  SECTION("Expected '}'") {
    TEST_SETUP(R"(fn int f(int a){)");
    REQUIRE(output_buffer.str().empty());
    const auto &error_stream = saplang::get_error_stream();
    REQUIRE(error_stream.str() ==
            R"(test:1:17 error: expected '}' at the end of a block.
test:1:17 error: failed to parse function block.
)");
    REQUIRE(!parser.is_complete_ast());
  }
  saplang::clear_error_stream();
  SECTION("Forward decl attempt") {
    TEST_SETUP(R"(fn int f(int a);)");
    REQUIRE(output_buffer.str().empty());
    const auto &error_stream = saplang::get_error_stream();
    REQUIRE(error_stream.str() ==
            R"(test:1:16 error: expected '{' at the beginning of a block.
test:1:16 error: failed to parse function block.
)");
    REQUIRE(!parser.is_complete_ast());
  }
  saplang::clear_error_stream();
  SECTION("Correct function declaration") {
    TEST_SETUP(R"(fn int f(int a){})");
    REQUIRE(output_buffer.str() == R"(FunctionDecl: f:int
  ParamDecl: a:int
  Block
)");
    const auto &error_stream = saplang::get_error_stream();
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
    const auto &error_stream = saplang::get_error_stream();
    REQUIRE(error_stream.str().empty());
    REQUIRE(parser.is_complete_ast());
  }
}