#include <catch2/catch_test_macros.hpp>

#include <sstream>
#include <string>

#include <lexer.h>
#include <parser.h>
#include <sema.h>
#include <utils.h>

#define TEST_SETUP(file_contents)                                              \
  saplang::clear_error_stream();                                               \
  std::stringstream buffer{file_contents};                                     \
  std::stringstream output_buffer{};                                           \
  saplang::SourceFile src_file{"sema_test", buffer.str()};                     \
  saplang::Lexer lexer{src_file};                                              \
  saplang::Parser parser(&lexer);                                              \
  auto parse_result = parser.parse_source_file();                              \
  saplang::Sema sema{std::move(parse_result.functions)};                       \
  auto resolved_ast = sema.resolve_ast();                                      \
  for (auto &&fn : resolved_ast) {                                             \
    fn->dump_to_stream(output_buffer);                                         \
  }                                                                            \
  const auto &error_stream = saplang::get_error_stream();

#define TEST_SETUP_PARTIAL(file_contents)                                      \
  saplang::clear_error_stream();                                               \
  std::stringstream buffer{file_contents};                                     \
  std::stringstream output_buffer{};                                           \
  saplang::SourceFile src_file{"sema_test", buffer.str()};                     \
  saplang::Lexer lexer{src_file};                                              \
  saplang::Parser parser(&lexer);                                              \
  auto parse_result = parser.parse_source_file();                              \
  saplang::Sema sema{std::move(parse_result.functions)};                       \
  auto resolved_ast = sema.resolve_ast(true);                                  \
  for (auto &&fn : resolved_ast) {                                             \
    fn->dump_to_stream(output_buffer);                                         \
  }                                                                            \
  const auto &error_stream = saplang::get_error_stream();

TEST_CASE("Undeclared type", "[sema]") {
  TEST_SETUP(R"(
fn CustomType foo(){}
)");
  REQUIRE(output_buffer.str().empty());
  REQUIRE(
      error_stream.str() ==
      "sema_test:2:1 error: function 'foo' has invalid 'CustomType' type\n");
}

TEST_CASE("Function redeclared", "[sema]") {
  TEST_SETUP(R"(
fn void foo(){}

fn void foo(){}
)");
  REQUIRE(output_buffer.str().empty());
  REQUIRE(error_stream.str() ==
          "sema_test:4:1 error: redeclaration of 'foo'.\n");
}

TEST_CASE("Function declarations", "[sema]") {
  SECTION("Undeclared functions") {
    TEST_SETUP(R"(
fn void main() {
    a();
}
)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            "sema_test:3:5 error: symbol 'a' undefined.\n");
  }
  SECTION("Incorrect parameter types") {
    TEST_SETUP(R"(
fn void foo(){}

fn void bar(i32 a, i32 b){}

fn void main() {
  foo(1);
  bar(foo(), foo());
  bar(1.0, foo());
  bar();
  bar(1, 2, 3);
  bar(1, 2);
  foo();
}
)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            R"(sema_test:7:6 error: argument count mismatch.
sema_test:8:10 error: unexpected type 'void', expected 'i32'.
sema_test:9:7 error: unexpected type 'f32', expected 'i32'.
sema_test:10:6 error: argument count mismatch.
sema_test:11:6 error: argument count mismatch.
sema_test:12:7 error: unexpected type 'u8', expected 'i32'.
)");
  }
}

TEST_CASE("Declref", "[sema]") {
  SECTION("Using function as variable") {
    TEST_SETUP(R"(
fn void foo(){}

fn void main() {
  foo;
  y;
  foo();
}
)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            R"(sema_test:5:3 error: expected to call function 'foo',
sema_test:6:3 error: symbol 'y' undefined.
)");
  }
}

TEST_CASE("Function parameters", "[sema]") {
  SECTION("Unknown paramatere type") {
    TEST_SETUP(R"(
fn void foo(u32 a, CustomType b) {}
)");
    REQUIRE(
        error_stream.str() ==
        "sema_test:2:20 error: parameter 'b' has invalid 'CustomType' type\n");
    REQUIRE(output_buffer.str().empty());
  }
  SECTION("Invalid parameter 'void'") {
    TEST_SETUP(R"(
fn void foo(void a, u32 b){}
)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            "sema_test:2:13 error: invalid paramater type 'void'.\n");
  }
  SECTION("Parameter redeclaration") {
    TEST_SETUP(R"(
fn void foo(i32 x, f32 x){}
)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            "sema_test:2:20 error: redeclaration of 'x'.\n");
  }
}

TEST_CASE("Error recovery", "[sema]") {
  TEST_SETUP_PARTIAL(R"(
fn CustomType foo() {}

fn void main() {}
)");
  auto buf_str = output_buffer.str();
  std::cerr << buf_str;
  REQUIRE(
      error_stream.str() ==
      "sema_test:2:1 error: function 'foo' has invalid 'CustomType' type\n");
  REQUIRE(!buf_str.empty());
  REQUIRE(buf_str.find("ResolvedFuncDecl:") == 0);
  REQUIRE(buf_str.find("main") == 38);
  REQUIRE(buf_str.find("ResolvedBlock:") == 46);
}
