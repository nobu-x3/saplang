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
  class Scope;

public:
  inline explicit Sema(std::vector<std::unique_ptr<Decl>> ast, bool run_flow_sensitive_analysis = false)
      : m_AST(std::move(ast)), m_ShouldRunFlowSensitiveAnalysis(run_flow_sensitive_analysis) {
    init_builtin_type_infos();
  }

  inline explicit Sema(std::vector<std::unique_ptr<Module>> modules, bool run_flow_sensitive_analysis = false)
      : m_Modules(std::move(modules)), m_ShouldRunFlowSensitiveAnalysis(run_flow_sensitive_analysis) {
    init_builtin_type_infos();
  }

  std::vector<std::unique_ptr<ResolvedDecl>> resolve_ast(bool partial = false);

  std::vector<std::unique_ptr<ResolvedModule>> resolve_modules(bool partial = false);

  void dump_type_infos_to_stream(std ::stringstream &stream, size_t indent = 0) const;

  inline std::unordered_map<std::string, TypeInfo> &&move_type_infos() { return std::move(m_TypeInfos); }

private:
  struct AstResolveResult {
    std::vector<std::unique_ptr<ResolvedDecl>> resolved_ast;
  };
  std::unique_ptr<ResolvedModule> resolve_module(const Module &mod, bool partial);

  AstResolveResult resolve_ast(bool partial, const Module &mod);

  void init_builtin_type_infos();

  void init_type_info(ResolvedStructDecl &decl);

  std::optional<DeclLookupResult> lookup_decl(std::string_view id, std::optional<const Type *> type = std::nullopt);

  bool resolve_struct_decls(std::vector<std::unique_ptr<ResolvedDecl>> &resolved_decls, bool partial, const std::vector<std::unique_ptr<Decl>> &ast);

  bool resolve_enum_decls(std::vector<std::unique_ptr<ResolvedDecl>> &resolved_decls, bool partial, const std::vector<std::unique_ptr<Decl>> &ast);

  bool resolve_global_var_decls(std::vector<std::unique_ptr<ResolvedDecl>> &resolved_decls, bool partial, const std::vector<std::unique_ptr<Decl>> &ast);

  bool insert_decl_to_current_scope(ResolvedDecl &decl);

  bool insert_decl_to_module_scope(ResolvedDecl& decl);

  bool insert_decl_to_global_scope(ResolvedDecl &decl);

  bool instantiate_generic_type(const DeclLookupResult &generic_decl, std::string_view instance_name, const std::vector<Type> &instance_types,
                                std::string &out_name);

  std::optional<Type> resolve_type(Type parsed_type);

  bool is_enum(const Type &type);

  std::unique_ptr<ResolvedFuncDecl> resolve_func_decl(const FunctionDecl &func);

  std::unique_ptr<ResolvedGenericFunctionDecl> resolve_generic_func_decl(const GenericFunctionDecl &func);

  std::unique_ptr<ResolvedParamDecl> resolve_param_decl(const ParamDecl &decl, int index, const std::string function_name);

  std::unique_ptr<ResolvedBlock> resolve_block(const Block &block, bool is_inner_block = false, bool is_defer_block = false);

  std::unique_ptr<ResolvedStmt> resolve_stmt(const Stmt &stmt, bool is_inner_block = false);

  std::unique_ptr<ResolvedNumberLiteral> resolve_enum_access(const EnumElementAccess &access);

  std::unique_ptr<ResolvedGroupingExpr> resolve_grouping_expr(const GroupingExpr &group);

  std::unique_ptr<ResolvedExpr> resolve_binary_operator(const BinaryOperator &op);

  std::unique_ptr<ResolvedUnaryOperator> resolve_unary_operator(const UnaryOperator &op, Type *type);

  std::unique_ptr<ResolvedExplicitCastExpr> resolve_explicit_cast(const ExplicitCast &cast);

  std::unique_ptr<ResolvedStructLiteralExpr> resolve_struct_literal_expr(const StructLiteralExpr &lit, Type struct_type);

  std::unique_ptr<ResolvedArrayLiteralExpr> resolve_array_literal_expr(const ArrayLiteralExpr &lit, Type array_type);

  std::unique_ptr<ResolvedStringLiteralExpr> resolve_string_literal_expr(const StringLiteralExpr &lit);

  std::unique_ptr<ResolvedReturnStmt> resolve_return_stmt(const ReturnStmt &stmt, bool is_inner_block = false);

  std::unique_ptr<ResolvedExpr> resolve_expr(const Expr &expr, Type *type = nullptr);

  std::unique_ptr<ResolvedDeclRefExpr> resolve_decl_ref_expr(const DeclRefExpr &decl_ref_expr, bool is_call = false, Type *type = nullptr);

  std::unique_ptr<ResolvedCallExpr> resolve_call_expr(const CallExpr &call);

  std::unique_ptr<ResolvedIfStmt> resolve_if_stmt(const IfStmt &stmt);

  std::unique_ptr<ResolvedSwitchStmt> resolve_switch_stmt(const SwitchStmt& stmt);

  std::unique_ptr<ResolvedDeferStmt> resolve_defer_stmt(const DeferStmt &stmt);

  std::unique_ptr<ResolvedWhileStmt> resolve_while_stmt(const WhileStmt &stmt);

  std::unique_ptr<ResolvedForStmt> resolve_for_stmt(const ForStmt &stmt);

  std::unique_ptr<ResolvedDeclStmt> resolve_decl_stmt(const DeclStmt &stmt);

  std::unique_ptr<ResolvedVarDecl> resolve_var_decl(const VarDecl &decl);

  std::unique_ptr<ResolvedStructDecl> resolve_struct_decl(const StructDecl &decl);

  std::unique_ptr<ResolvedGenericStructDecl> resolve_generic_struct_decl(const GenericStructDecl &decl);

  std::unique_ptr<ResolvedEnumDecl> resolve_enum_decl(const EnumDecl &decl);

  std::unique_ptr<ResolvedAssignment> resolve_assignment(const Assignment &assignment);

  std::unique_ptr<ResolvedStructMemberAccess> resolve_member_access(const MemberAccess &access, const ResolvedDecl *decl);

  std::unique_ptr<InnerMemberAccess> resolve_inner_member_access(const MemberAccess &access, Type type);

  std::unique_ptr<ResolvedArrayElementAccess> resolve_array_element_access(const ArrayElementAccess &access, const ResolvedDecl *decl);

  std::unique_ptr<ResolvedArrayElementAccess> resolve_array_element_access_no_deref(SourceLocation loc, std::vector<std::unique_ptr<ResolvedExpr>> indices,
                                                                                    const ResolvedDecl *decl);

  bool flow_sensitive_analysis(const ResolvedFuncDecl &fn);

  bool check_return_on_all_paths(const ResolvedFuncDecl &fn, const CFG &cfg);

private:
  std::vector<std::unique_ptr<Module>> m_Modules;
  // @TODO: to refactor out
  // @NOTE: deprecated
  std::vector<std::unique_ptr<Decl>> m_AST;
  std::vector<std::vector<ResolvedDecl *>> m_Scopes{};
  std::vector<std::unique_ptr<ResolvedDecl>> m_GenericInstances{};
  std::unordered_map<std::string, std::unique_ptr<ResolvedModule>> m_ResolvedModules{};
  std::unordered_map<std::string, TypeInfo> m_TypeInfos;
  ResolvedFuncDecl *m_CurrFunction{nullptr};
  ConstantExpressionEvaluator m_Cee;
  int m_ModuleScopeId{0};
  bool m_ShouldRunFlowSensitiveAnalysis;

private:
  class Scope {
  public:
    inline explicit Scope(Sema *sema) : m_Sema(sema) { m_Sema->m_Scopes.emplace_back(); }

    inline ~Scope() { m_Sema->m_Scopes.pop_back(); }

  private:
    Sema *m_Sema;
  };
};
} // namespace saplang
