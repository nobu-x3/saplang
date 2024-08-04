#include <cassert>
#include <fstream>
#include <iostream>
#include <sstream>

#include "lexer.h"
#include "utils.h"

int main(int argc, const char **argv) {
  // if (argc < 2)
  //   return 1;
  // std::ifstream file(argv[1]);
  std::ifstream file{"/home/nobu/projects/saplang/build/bin/main.sl"};
  std::stringstream buffer;
  buffer << file.rdbuf();
  // saplang::SourceFile src_file{argv[1], buffer.str()};
  saplang::SourceFile src_file{"/home/nobu/projects/saplang/build/bin/main.sl",
                               buffer.str()};
  saplang::Lexer lexer{src_file};
  saplang::Token tok = lexer.get_next_token();
  while (tok.kind != saplang::TokenKind::Eof) {
    if (tok.kind == saplang::TokenKind::Identifier) {
      std::cout << "identifier(" << *tok.value << ")";
    } else if (tok.kind == saplang::TokenKind::KwVoid) {
      std::cout << "void";
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
  return 0;
}
