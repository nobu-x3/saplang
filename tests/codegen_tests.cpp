#include <catch2/catch_test_macros.hpp>

#include <sstream>
#include <string>

#include <codegen.h>
#include <lexer.h>
#include <parser.h>
#include <sema.h>
#include <utils.h>

#include <llvm/Support/raw_ostream.h>

#define TEST_SETUP(file_contents)                                              \
  saplang::clear_error_stream();                                               \
  std::stringstream buffer{file_contents};                                     \
  std::string output_string;                                                   \
  llvm::raw_string_ostream output_buffer{output_string};                       \
  saplang::SourceFile src_file{"sema_test", buffer.str()};                     \
  saplang::Lexer lexer{src_file};                                              \
  saplang::Parser parser(&lexer);                                              \
  auto parse_result = parser.parse_source_file();                              \
  saplang::Sema sema{std::move(parse_result.functions)};                       \
  auto resolved_ast = sema.resolve_ast();                                      \
  saplang::Codegen codegen{std::move(resolved_ast), "codegen_tests"};          \
  auto generated_code = codegen.generate_ir();                                 \
  generated_code->print(output_buffer, nullptr, true, true);                   \
  const auto &error_stream = saplang::get_error_stream();

TEST_CASE("single return", "[codegen]") {
  SECTION("return stmt 1 fn") {
    TEST_SETUP(R"(fn bool foo() { return true; }
)");
    REQUIRE(output_string ==
            R"(; ModuleID = '<tu>'
source_filename = "codegen_tests"
target triple = "x86-64"

define i1 @foo() {
entry:
  %retval = alloca i1, align 1
  store i1 true, ptr %retval, align 1
  br label %return

return:                                           ; preds = <null operand!>, %entry
  %0 = load i1, ptr %retval, align 1
  ret i1 %0
}
)");
  }
  SECTION("return stmt 2 fns") {
    TEST_SETUP(R"(fn bool foo() { return true; }
fn bool bar() { return true; }
)");
    REQUIRE(output_string ==
            R"(; ModuleID = '<tu>'
source_filename = "codegen_tests"
target triple = "x86-64"

define i1 @foo() {
entry:
  %retval = alloca i1, align 1
  store i1 true, ptr %retval, align 1
  br label %return

return:                                           ; preds = <null operand!>, %entry
  %0 = load i1, ptr %retval, align 1
  ret i1 %0
}

define i1 @bar() {
entry:
  %retval = alloca i1, align 1
  store i1 true, ptr %retval, align 1
  br label %return

return:                                           ; preds = <null operand!>, %entry
  %0 = load i1, ptr %retval, align 1
  ret i1 %0
}
)");
  }
  SECTION("multiple return") {}
}

TEST_CASE("multiple return", "[codegen]") {
  TEST_SETUP("fn void main() { return; 1; return;}");
  REQUIRE(output_string ==
          R"(; ModuleID = '<tu>'
source_filename = "codegen_tests"
target triple = "x86-64"

define void @main() {
entry:
  br label %return

return:                                           ; preds = <null operand!>, %entry
  ret void
}
)");
}

TEST_CASE("alloca order", "[codegen]") {
  SECTION("Basic setup") {
    TEST_SETUP(R"(
fn void foo(i32 x, bool y, i64 z) {
  x;
  y;
  z;
}
)");
    REQUIRE(output_string == R"(; ModuleID = '<tu>'
source_filename = "codegen_tests"
target triple = "x86-64"

define void @foo(i32 %x, i1 %y, i64 %z) {
entry:
  %x1 = alloca i32, align 4
  %y2 = alloca i1, align 1
  %z3 = alloca i64, align 8
  store i32 %x, ptr %x1, align 4
  store i1 %y, ptr %y2, align 1
  store i64 %z, ptr %z3, align 4
  %0 = load i32, ptr %x1, align 4
  %1 = load i1, ptr %y2, align 1
  %2 = load i64, ptr %z3, align 4
  ret void
}
)");
  }
}
