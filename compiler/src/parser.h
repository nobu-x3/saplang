#pragma once

#include "ast.h"
#include "lexer.h"
#include <algorithm>
#include <memory>
#include <vector>

namespace saplang {

struct ParsingResult {
  bool is_complete_ast;
  std::unique_ptr<Module> module;
};

struct ParserConfig {
  const std::vector<std::string> &include_paths;
  bool check_paths;
};

class Parser {
public:
  explicit Parser(Lexer *lexer, ParserConfig cfg);
  ParsingResult parse_source_file();
  inline bool is_complete_ast() const { return m_IsCompleteAst; }

private:
  enum class Context {
    Binop,
    VarDecl,
    Stmt,
  };

  inline void eat_next_token() { m_NextToken = m_Lexer->get_next_token(); }
  inline void go_back_to_prev_token(const Token &token) { m_NextToken = m_Lexer->get_prev_token(token); }

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
  std::unique_ptr<FunctionDecl> parse_function_decl(SourceLocation decl_loc, Type return_type, std::string function_identifier);
  std::unique_ptr<GenericFunctionDecl> parse_generic_function_decl(SourceLocation decl_loc, Type return_type, std::string function_identifier);

  using MaybeExternBlock = std::optional<std::vector<std::unique_ptr<Decl>>>;
  MaybeExternBlock parse_extern_block();

  std::string parse_import();
  std::unique_ptr<Block> parse_block();
  std::unique_ptr<Stmt> parse_stmt();
  std::unique_ptr<ReturnStmt> parse_return_stmt();
  std::unique_ptr<Expr> parse_prefix_expr(Context context);
  std::unique_ptr<Expr> parse_primary_expr(Context context);
  std::unique_ptr<Expr> parse_call_expr(SourceLocation location, std::unique_ptr<DeclRefExpr> decl_ref_expr);
  std::unique_ptr<ExplicitCast> parse_explicit_cast(Type type);
  std::unique_ptr<StructLiteralExpr> parse_struct_literal_expr();
  std::unique_ptr<ArrayLiteralExpr> parse_array_literal_expr();
  std::unique_ptr<StringLiteralExpr> parse_string_literal_expr();
  std::unique_ptr<Expr> parse_expr(Context context);
  std::unique_ptr<Expr> parse_expr_rhs(std::unique_ptr<Expr> lhs, int precedence);
  std::unique_ptr<SizeofExpr> parse_sizeof_expr();
  std::unique_ptr<AlignofExpr> parse_alignof_expr();
  std::unique_ptr<EnumElementAccess> parse_enum_element_access(std::string enum_id);
  std::unique_ptr<ParamDecl> parse_param_decl();
  std::unique_ptr<DeferStmt> parse_defer_stmt();
  std::optional<Type> parse_type();

  using ArgumentList = std::vector<std::unique_ptr<Expr>>;
  std::optional<ArgumentList> parse_argument_list();

  std::optional<ParameterList> parse_parameter_list();

  std::optional<ParameterList> parse_parameter_list_of_generic_fn(const std::vector<std::string> &placeholders);

  std::unique_ptr<IfStmt> parse_if_stmt();
  std::unique_ptr<SwitchStmt> parse_switch_stmt();
  std::unique_ptr<WhileStmt> parse_while_stmt();
  std::unique_ptr<ForStmt> parse_for_stmt();

  std::unique_ptr<DeclStmt> parse_var_decl_stmt(bool is_global = false);
  std::unique_ptr<VarDecl> parse_var_decl(bool is_const, bool is_global = false);
  std::unique_ptr<StructDecl> parse_struct_decl(SourceLocation struct_token_loc);
  std::unique_ptr<GenericStructDecl> parse_generic_struct_decl(SourceLocation struct_token_loc);
  std::unique_ptr<EnumDecl> parse_enum_decl();
  std::unique_ptr<MemberAccess> parse_member_access(std::unique_ptr<DeclRefExpr> decl_ref_expr, const std::string &var_id);
  std::unique_ptr<ArrayElementAccess> parse_array_element_access(std::string var_id);
  std::unique_ptr<Stmt> parse_assignment_or_expr(Context context);
  std::unique_ptr<Assignment> parse_assignment(std::unique_ptr<Expr> lhs);
  std::unique_ptr<Assignment> parse_assignment_rhs(std::unique_ptr<DeclRefExpr> lhs, int lhs_deref_count);

private:
  ParserConfig m_Config;
  std::unordered_map<std::string, Type> m_EnumTypes;
  Lexer *m_Lexer;
  Token m_NextToken;
  bool m_IsCompleteAst{true};
  std::string m_ModuleName;
  std::string m_ModulePath;
};

} // namespace saplang
