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
  inline bool is_complete_ast() const { return m_IsCompleteAst; }

private:
  inline void eat_next_token() { m_NextToken = m_Lexer->get_next_token(); }

  inline void sync_on(TokenKind kind) {
    m_IsCompleteAst = false;
    while (m_NextToken.kind != kind && m_NextToken.kind != TokenKind::Eof)
      eat_next_token();
  }

  void synchronize();
  std::unique_ptr<FunctionDecl> parse_function_decl();
  std::unique_ptr<Block> parse_block();
  std::unique_ptr<Stmt> parse_stmt();
  std::unique_ptr<ReturnStmt> parse_return_stmt();
  std::unique_ptr<Expr> parse_primary_expr();
  std::unique_ptr<Expr> parse_expr();
  std::unique_ptr<ParamDecl> parse_param_decl();
  std::optional<Type> parse_type();

  using ArgumentList = std::vector<std::unique_ptr<Expr>>;
  std::optional<ArgumentList> parse_argument_list();

  using ParameterList = std::vector<std::unique_ptr<ParamDecl>>;
  std::optional<ParameterList> parse_parameter_list();

private:
  Lexer *m_Lexer;
  Token m_NextToken;
  bool m_IsCompleteAst{true};
};
} // namespace saplang
