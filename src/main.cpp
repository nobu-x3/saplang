#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>

#include "lexer.h"
#include "parser.h"
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
  { // Parser test 1
    std::ifstream file{"../tests/parser_01.sl"};
    std::stringstream buffer;
    buffer << file.rdbuf();
    saplang::SourceFile src_file{"../tests/parser_01.sl", buffer.str()};
    saplang::Lexer lexer{src_file};
    saplang::Parser parser(&lexer);
    auto parse_result = parser.parse_source_file();
    for (auto &&fn : parse_result.functions) {
      fn->dump(0);
    }
    std::cout << "Is ast complete? " << parser.is_complete_ast() << std::endl;
  }
  { // Parser test 2
    std::ifstream file{"../tests/parser_02.sl"};
    std::stringstream buffer;
    buffer << file.rdbuf();
    saplang::SourceFile src_file{"../tests/parser_02.sl", buffer.str()};
    saplang::Lexer lexer{src_file};
    saplang::Parser parser(&lexer);
    auto parse_result = parser.parse_source_file();
    for (auto &&fn : parse_result.functions) {
      fn->dump(0);
    }
    std::cout << "Is ast complete? " << parser.is_complete_ast() << std::endl;
  }
  return 0;
}
