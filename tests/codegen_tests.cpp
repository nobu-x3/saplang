#include <catch2/catch_test_macros.hpp>

#include <sstream>
#include <string>

#include <lexer.h>
#include <parser.h>
#include <sema.h>
#include <codegen.h>
#include <utils.h>

#include <llvm/Support/raw_ostream.h>

TEST_CASE("Codegen test", "[codegen]") {
  saplang::clear_error_stream();
  std::stringstream buffer{"fn bool foo() { return true; }"};
  std::string output_string;
  llvm::raw_string_ostream output_buffer{output_string};
  saplang::SourceFile src_file{"sema_test", buffer.str()};
  saplang::Lexer lexer{src_file};
  saplang::Parser parser(&lexer);
  auto parse_result = parser.parse_source_file();
  saplang::Sema sema{std::move(parse_result.functions)};
  auto resolved_ast = sema.resolve_ast();
  saplang::Codegen codegen{std::move(resolved_ast), "codegen_tests"};
  auto generated_code = codegen.generate_ir();
  generated_code->print(output_buffer, nullptr, true, true);
  std::cerr << output_buffer.str();
  const auto &error_stream = saplang::get_error_stream();
}