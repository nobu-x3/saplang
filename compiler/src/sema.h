#pragma once

#include "ast.h"
#include "constexpr.h"

#include <memory>
#include <optional>
#include <vector>

namespace saplang {

class CFG;

struct DeclLookupResult {
  const ResolvedDecl *decl;
  int index;
};

class Sema {
public:
  inline explicit Sema(std::vector<std::unique_ptr<Decl>> ast,
                       bool run_flow_sensitive_analysis = false)
      : m_AST(std::move(ast)),
        m_ShouldRunFlowSensitiveAnalysis(run_flow_sensitive_analysis) {}

  std::vector<std::unique_ptr<ResolvedDecl>> resolve_ast(bool partial = false);

private:
  std::optional<DeclLookupResult>
  lookup_decl(std::string_view id, std::optional<Type *> type = std::nullopt);

  bool insert_decl_to_current_scope(ResolvedDecl &decl);

  std::optional<Type> resolve_type(Type parsed_type);

  std::unique_ptr<ResolvedFuncDecl> resolve_func_decl(const FunctionDecl &func);

  std::unique_ptr<ResolvedParamDecl> resolve_param_decl(const ParamDecl &decl);

  std::unique_ptr<ResolvedBlock> resolve_block(const Block &block);

  std::unique_ptr<ResolvedStmt> resolve_stmt(const Stmt &stmt);

  std::unique_ptr<ResolvedGroupingExpr>
  resolve_grouping_expr(const GroupingExpr &group);

  std::unique_ptr<ResolvedBinaryOperator>
  resolve_binary_operator(const BinaryOperator &op);

  std::unique_ptr<ResolvedUnaryOperator>
  resolve_unary_operator(const UnaryOperator &op);

  std::unique_ptr<ResolvedStructLiteralExpr>
  resolve_struct_literal_expr(const StructLiteralExpr &lit, Type struct_type);

  std::unique_ptr<ResolvedReturnStmt>
  resolve_return_stmt(const ReturnStmt &stmt);

  std::unique_ptr<ResolvedExpr> resolve_expr(const Expr &expr,
                                             Type *type = nullptr);

  std::unique_ptr<ResolvedDeclRefExpr>
  resolve_decl_ref_expr(const DeclRefExpr &decl_ref_expr, bool is_call = false);

  std::unique_ptr<ResolvedCallExpr> resolve_call_expr(const CallExpr &call);

  std::unique_ptr<ResolvedIfStmt> resolve_if_stmt(const IfStmt &stmt);

  std::unique_ptr<ResolvedWhileStmt> resolve_while_stmt(const WhileStmt &stmt);

  std::unique_ptr<ResolvedForStmt> resolve_for_stmt(const ForStmt &stmt);

  std::unique_ptr<ResolvedDeclStmt> resolve_decl_stmt(const DeclStmt &stmt);

  std::unique_ptr<ResolvedVarDecl> resolve_var_decl(const VarDecl &decl);

  std::unique_ptr<ResolvedStructDecl>
  resolve_struct_decl(const StructDecl &decl);

  std::unique_ptr<ResolvedAssignment>
  resolve_assignment(const Assignment &assignment);

  std::unique_ptr<ResolvedStructMemberAccess>
  resolve_member_access(const MemberAccess &access, const ResolvedDecl* decl);

  bool flow_sensitive_analysis(const ResolvedFuncDecl &fn);

  bool check_return_on_all_paths(const ResolvedFuncDecl &fn, const CFG &cfg);

private:
  std::vector<std::unique_ptr<Decl>> m_AST;
  std::vector<std::vector<ResolvedDecl *>> m_Scopes{};
  ResolvedFuncDecl *m_CurrFunction{nullptr};
  ConstantExpressionEvaluator m_Cee;
  bool m_ShouldRunFlowSensitiveAnalysis;

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
