#pragma once

#include "ast.h"
#include "lexer.h"
#include <algorithm>
#include <memory>
#include <vector>

namespace saplang {

struct ParsingResult {
  bool is_complete_ast;
  std::vector<std::unique_ptr<Decl>> declarations;
};

class Parser {
public:
  explicit Parser(Lexer *lexer);
  ParsingResult parse_source_file();
  inline bool is_complete_ast() const { return m_IsCompleteAst; }

private:
  inline void eat_next_token() { m_NextToken = m_Lexer->get_next_token(); }
  inline void go_back_to_prev_token() {
    m_NextToken = m_Lexer->get_prev_token();
  }

  inline void sync_on(const std::vector<TokenKind> &kinds) {
    m_IsCompleteAst = false;
    bool found_next = false;
    while (!found_next && m_NextToken.kind != TokenKind::Eof) {
      for (auto &&kind : kinds) {
        if (m_NextToken.kind == kind) {
          found_next = true;
          return;
        }
      }
      eat_next_token();
    }
  }

  void synchronize();
  std::unique_ptr<FunctionDecl> parse_function_decl();

  using MaybeExternBlock = std::optional<std::vector<std::unique_ptr<Decl>>>;
  MaybeExternBlock parse_extern_block();

  std::unique_ptr<Block> parse_block();
  std::unique_ptr<Stmt> parse_stmt();
  std::unique_ptr<ReturnStmt> parse_return_stmt();
  std::unique_ptr<Expr> parse_prefix_expr();
  std::unique_ptr<Expr> parse_primary_expr();
  std::unique_ptr<ExplicitCast> parse_explicit_cast(Type type);
  std::unique_ptr<StructLiteralExpr> parse_struct_literal_expr();
  std::unique_ptr<ArrayLiteralExpr> parse_array_literal_expr();
  std::unique_ptr<StringLiteralExpr> parse_string_literal_expr();
  std::unique_ptr<Expr> parse_expr();
  std::unique_ptr<Expr> parse_expr_rhs(std::unique_ptr<Expr> lhs,
                                       int precedence);
  std::unique_ptr<EnumElementAccess>
  parse_enum_element_access(std::string enum_id);
  std::unique_ptr<ParamDecl> parse_param_decl();
  std::optional<Type> parse_type();

  using ArgumentList = std::vector<std::unique_ptr<Expr>>;
  std::optional<ArgumentList> parse_argument_list();

  using ParameterList = std::vector<std::unique_ptr<ParamDecl>>;
  std::optional<ParameterList> parse_parameter_list();

  std::unique_ptr<IfStmt> parse_if_stmt();
  std::unique_ptr<WhileStmt> parse_while_stmt();
  std::unique_ptr<ForStmt> parse_for_stmt();

  std::unique_ptr<DeclStmt> parse_var_decl_stmt(bool is_global = false);
  std::unique_ptr<VarDecl> parse_var_decl(bool is_const,
                                          bool is_global = false);
  std::unique_ptr<StructDecl> parse_struct_decl();
  std::unique_ptr<EnumDecl> parse_enum_decl();
  std::unique_ptr<MemberAccess>
  parse_member_access(std::unique_ptr<DeclRefExpr> decl_ref_expr,
                      const std::string &var_id);
  std::unique_ptr<ArrayElementAccess>
  parse_array_element_access(std::string var_id);
  std::unique_ptr<Stmt> parse_assignment_or_expr();
  std::unique_ptr<Assignment> parse_assignment(std::unique_ptr<Expr> lhs);
  std::unique_ptr<Assignment>
  parse_assignment_rhs(std::unique_ptr<DeclRefExpr> lhs);

private:
  std::unordered_map<std::string, Type> m_EnumTypes;
  Lexer *m_Lexer;
  Token m_NextToken;
  bool m_IsCompleteAst{true};
};
} // namespace saplang
