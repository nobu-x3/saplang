#pragma once

#include "ast.h"
#include "lexer.h"
#include <memory>
#include <vector>

namespace saplang {

struct FuncParsingResult {
  bool is_complete_ast;
  std::vector<std::unique_ptr<FunctionDecl>> functions;
};

class Parser {
public:
  explicit Parser(Lexer *lexer);
  FuncParsingResult parse_source_file();

private:
  inline void eat_next_token() { m_NextToken = m_Lexer->get_next_token(); }

  inline void sync_on(TokenKind kind) {
    while (m_NextToken.kind != kind && m_NextToken.kind != TokenKind::Eof)
      eat_next_token();
  }

  std::unique_ptr<FunctionDecl> parse_function_decl();
  std::unique_ptr<Block> parse_block();
  std::optional<Type> parse_type();

private:
  Lexer *m_Lexer;
  Token m_NextToken;
};
} // namespace saplang
