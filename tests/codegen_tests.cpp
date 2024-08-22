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

TEST_CASE("Codegen test", "[codegen]") {
  SECTION("return stmt") {
    TEST_SETUP("fn bool foo() { return true; }");
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
}
