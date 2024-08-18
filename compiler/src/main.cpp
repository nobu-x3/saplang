#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>

#include "lexer.h"
#include "parser.h"
#include "sema.h"
#include "utils.h"

int main(int argc, const char **argv) {
  // if (argc < 2)
  //   return 1;
  // std::ifstream file(argv[1]);
  // saplang::SourceFile src_file{argv[1], buffer.str()};
  { // Lexer test
    std::cout << std::filesystem::current_path() << std::endl;
    std::ifstream file{"../tests/lexer_01.sl"};
    std::stringstream buffer;
    buffer << file.rdbuf();
    saplang::SourceFile src_file{"../tests/lexer_01.sl", buffer.str()};
    saplang::Lexer lexer{src_file};
    saplang::Token tok = lexer.get_next_token();
    while (tok.kind != saplang::TokenKind::Eof) {
      if (tok.kind == saplang::TokenKind::Identifier) {
        std::cout << "identifier(" << *tok.value << ")";
      } else if (tok.kind == saplang::TokenKind::Integer) {
        std::cout << "integer(" << *tok.value << ")";
      } else if (tok.kind == saplang::TokenKind::Real) {
        std::cout << "real(" << *tok.value << ")";
      } else if (tok.kind == saplang::TokenKind::KwVoid) {
        std::cout << "void";
      } else if (tok.kind == saplang::TokenKind::KwFn) {
        std::cout << "fn";
      } else if (tok.kind == saplang::TokenKind::KwDefer) {
        std::cout << "defer";
      } else if (tok.kind == saplang::TokenKind::KwExport) {
        std::cout << "export";
      } else if (tok.kind == saplang::TokenKind::KwModule) {
        std::cout << "module";
      } else if (tok.kind == saplang::TokenKind::KwReturn) {
        std::cout << "return";
      } else if (tok.kind == saplang::TokenKind::Unknown) {
        std::cout << "unknown";
      } else {
        // single character symbol
        std::cout << static_cast<char>(tok.kind);
      }
      std::cout << std::endl;
      tok = lexer.get_next_token();
    }
    assert(tok.kind == saplang::TokenKind::Eof);
    std::cout << "eof\n";
  }
  saplang::clear_error_stream();
  std::stringstream buffer{R"(
fn void foo(i32 x, f32 x){}
)"};
  std::stringstream output_buffer{};
  saplang::SourceFile src_file{"sema_test", buffer.str()};
  saplang::Lexer lexer{src_file};
  saplang::Parser parser(&lexer);
  auto parse_result = parser.parse_source_file();
  saplang::Sema sema{std::move(parse_result.functions)};
  auto resolved_ast = sema.resolve_ast();
  for (auto &&fn : resolved_ast) {
    fn->dump_to_stream(output_buffer);
  }
  const auto &error_stream = saplang::get_error_stream();
  return 0;
}
