#pragma once

#include "ast.h"

#include <memory>
#include <optional>
#include <vector>

namespace saplang {

struct DeclLookupResult {
  const ResolvedDecl *decl;
  int index;
};

class Sema {
public:
  inline explicit Sema(std::vector<std::unique_ptr<FunctionDecl>> ast)
      : m_AST(std::move(ast)) {}

  std::vector<std::unique_ptr<ResolvedFuncDecl>> resolve_ast(bool partial = false);

private:
  std::optional<DeclLookupResult> lookup_decl(std::string_view id,
                                              std::optional<Type *> type = std::nullopt);

  bool insert_decl_to_current_scope(ResolvedDecl &decl);

  std::optional<Type> resolve_type(Type parsed_type);

  std::unique_ptr<ResolvedFuncDecl> resolve_func_decl(const FunctionDecl &func);

  std::unique_ptr<ResolvedParamDecl> resolve_param_decl(const ParamDecl &decl);

  std::unique_ptr<ResolvedBlock> resolve_block(const Block &block);

  std::unique_ptr<ResolvedStmt> resolve_stmt(const Stmt &stmt);

  std::unique_ptr<ResolvedReturnStmt>
  resolve_return_stmt(const ReturnStmt &stmt);

  std::unique_ptr<ResolvedExpr> resolve_expr(const Expr &expr);

  std::unique_ptr<ResolvedDeclRefExpr>
  resolve_decl_ref_expr(const DeclRefExpr &decl_ref_expr, bool is_call = false);

  std::unique_ptr<ResolvedCallExpr> resolve_call_expr(const CallExpr &call);

private:
  std::vector<std::unique_ptr<FunctionDecl>> m_AST;
  std::vector<std::vector<ResolvedDecl *>> m_Scopes{};
  ResolvedFuncDecl *m_CurrFunction{nullptr};

private:
  class Scope {
  public:
    inline explicit Scope(Sema *sema) : m_Sema(sema) {
      m_Sema->m_Scopes.emplace_back();
    }

    inline ~Scope() { m_Sema->m_Scopes.pop_back(); }

  private:
    Sema *m_Sema;
  };
};
} // namespace saplang
