#include "sema.h"

#include <cassert>

namespace saplang {

std::optional<DeclLookupResult> Sema::lookup_decl(std::string_view id,
                                                  std::optional<Type *> type) {
  int scope_id = 0;
  for (auto it = m_Scopes.rbegin(); it != m_Scopes.rend(); ++it) {
    for (const auto *decl : *it) {
      if (decl->id == id &&
          (!type || (decl->type.kind == type.value()->kind))) {
        return DeclLookupResult{decl, scope_id};
      }
    }
    ++scope_id;
  }
  return std::nullopt;
}

bool Sema::insert_decl_to_current_scope(ResolvedDecl &decl) {
  auto lookup_result = lookup_decl(decl.id, &decl.type);
  if (lookup_result && lookup_result->index == 0) {
    report(decl.location, "redeclaration of '" + decl.id + "\'");
    return false;
  }
  m_Scopes.back().emplace_back(&decl);
  return true;
}

std::vector<std::unique_ptr<ResolvedFuncDecl>> Sema::resolve_ast() {
  std::vector<std::unique_ptr<ResolvedFuncDecl>> resolved_functions{};
  Scope global_scope(this);
  // Insert all global scope stuff, e.g. from other modules
  bool error = false;
  for (auto &&fn : m_AST) {
    auto resolved_fn_decl = resolve_func_decl(*fn);
    if (!resolved_fn_decl || !insert_decl_to_current_scope(*resolved_fn_decl)) {
      error = true;
      continue;
    }
    resolved_functions.emplace_back(std::move(resolved_fn_decl));
  }
  if (error)
    return {};
  for (int i = 1; i < resolved_functions.size(); ++i) {
    Scope fn_scope{this};
    m_CurrFunction = resolved_functions[i].get();
    for (auto &&param : m_CurrFunction->params) {
      insert_decl_to_current_scope(*param);
    }
    auto resolved_body = resolve_block(*m_AST[i - 1]->body);
    if (!resolved_body) {
      error = true;
      continue;
    }
    m_CurrFunction->body = std::move(resolved_body);
  }
  if (error)
    return {};
  return std::move(resolved_functions);
}

std::optional<Type> Sema::resolve_type(Type parsed_type) {
  if (parsed_type.kind == Type::Kind::Custom) {
    return std::nullopt;
  }
  return parsed_type;
}

std::unique_ptr<ResolvedFuncDecl>
Sema::resolve_func_decl(const FunctionDecl &func) {
  auto type = resolve_type(func.type);
  if (!type) {
    return report(func.location, "function '" + func.id + "' has invalid '" +
                                     func.type.name + "' type");
  }
  std::vector<std::unique_ptr<ResolvedParamDecl>> resolved_params{};
  Scope param_scope{this};
  for (auto &&param : func.params) {
    auto resolved_param = resolve_param_decl(*param);
    if (!resolved_param || !insert_decl_to_current_scope(*resolved_param))
      return nullptr;
    resolved_params.emplace_back(std::move(resolved_param));
  }
  return std::make_unique<ResolvedFuncDecl>(
      func.location, func.id, *type, std::move(resolved_params), nullptr);
}

std::unique_ptr<ResolvedParamDecl>
Sema::resolve_param_decl(const ParamDecl &decl) {
  auto type = resolve_type(decl.type);
  if (!type || type->kind == Type::Kind::Void) {
    return report(decl.location, "parameter '" + decl.id + "' has invalid '" +
                                     decl.type.name + "' type");
  }
  return std::make_unique<ResolvedParamDecl>(decl.location, decl.id,
                                             std::move(*type));
}

std::unique_ptr<ResolvedBlock> Sema::resolve_block(const Block &block) {
  std::vector<std::unique_ptr<ResolvedStmt>> resolved_stmts{};
  bool error = false;
  Scope block_scope{this};
  int unreachable_count = 0;
  for (auto &&stmt : block.statements) {
    auto resolved_stmt = resolve_stmt(*stmt);
    error |= !resolved_stmts.emplace_back(std::move(resolved_stmt));
    if (error)
      continue;
    if (unreachable_count == 1) {
      report(stmt->location, "unreachable statement.", true);
      ++unreachable_count;
    }
    if (dynamic_cast<ReturnStmt *>(stmt.get())) {
      ++unreachable_count;
    }
  }
  if (error)
    return nullptr;
  return std::make_unique<ResolvedBlock>(block.location,
                                         std::move(resolved_stmts));
}

std::unique_ptr<ResolvedStmt> Sema::resolve_stmt(const Stmt &stmt) {
  if (auto *expr = dynamic_cast<const Expr *>(&stmt))
    return resolve_expr(*expr);
  if (auto *return_stmt = dynamic_cast<const ReturnStmt *>(&stmt)) {
    return resolve_return_stmt(*return_stmt);
  }
  assert(false && "unexpected expression.");
}

std::unique_ptr<ResolvedReturnStmt>
Sema::resolve_return_stmt(const ReturnStmt &stmt) {
  if (m_CurrFunction->type.kind == Type::Kind::Void && stmt.expr)
    return report(stmt.location, "unexpected return value in void function.");
  if (m_CurrFunction->type.kind != Type::Kind::Void && !stmt.expr)
    return report(stmt.location, "expected return value.");
  std::unique_ptr<ResolvedExpr> resolved_expr;
  if (stmt.expr) {
    resolved_expr = resolve_expr(*stmt.expr);
    if (!resolved_expr)
      return nullptr;
    if (m_CurrFunction->type.kind != resolved_expr->type.kind) {
      return report(resolved_expr->location, "unexpected return type.");
    }
  }
  return std::make_unique<ResolvedReturnStmt>(stmt.location,
                                              std::move(resolved_expr));
}

std::unique_ptr<ResolvedExpr> Sema::resolve_expr(const Expr &expr) {
  if (const auto *number = dynamic_cast<const NumberLiteral *>(&expr))
    return std::make_unique<ResolvedNumberLiteral>(number->location,
                                                   number->type, number->value);
  if (const auto *decl_ref_expr = dynamic_cast<const DeclRefExpr *>(&expr)) {
    return resolve_decl_ref_expr(*decl_ref_expr);
  }
  if (const auto *call_expr = dynamic_cast<const CallExpr *>(&expr))
    return resolve_call_expr(*call_expr);
  assert(false && "unexpected expression.");
}

std::unique_ptr<ResolvedDeclRefExpr>
Sema::resolve_decl_ref_expr(const DeclRefExpr &decl_ref_expr, bool is_call) {
  auto &&maybe_decl = lookup_decl(decl_ref_expr.id);
  if (!maybe_decl)
    return report(decl_ref_expr.location,
                  "symbol '" + decl_ref_expr.id + "' undefined.");
  const ResolvedDecl *decl = maybe_decl->decl;
  if (!decl)
    return report(decl_ref_expr.location,
                  "symbol '" + decl_ref_expr.id + "' undefined.");
  if (!is_call && dynamic_cast<const ResolvedFuncDecl *>(decl))
    return report(decl_ref_expr.location,
                  "expected to call function '" + decl_ref_expr.id + "',");
  return std::make_unique<ResolvedDeclRefExpr>(decl_ref_expr.location, decl);
}

std::unique_ptr<ResolvedCallExpr>
Sema::resolve_call_expr(const CallExpr &call) {
  const auto *decl_ref_expr = dynamic_cast<const DeclRefExpr *>(call.id.get());
  if (!decl_ref_expr)
    return report(call.location, "expression cannot be called as a function.");
  auto &&resolved_callee = resolve_decl_ref_expr(*call.id, true);
  if (!resolved_callee)
    return nullptr;
  const auto *resolved_func_decl =
      dynamic_cast<const ResolvedFuncDecl *>(resolved_callee->decl);
  if (!resolved_func_decl)
    return report(call.location, "calling non-function symbol.");
  if (call.args.size() != resolved_func_decl->params.size())
    return report(call.location, "argument count mismatch.");
  std::vector<std::unique_ptr<ResolvedExpr>> resolved_args;
  for (int i = 0; i < call.args.size(); ++i) {
    auto &&resolved_arg = resolve_expr(*call.args[i]);
    if (!resolved_arg)
      return nullptr;
    if (resolved_arg->type.kind != resolved_func_decl->params[i]->type.kind)
      return report(resolved_arg->location,
                    "unexpected type '" + resolved_arg->type.name +
                        "', expected '" +
                        resolved_func_decl->params[i]->type.name + "'.");
    resolved_args.emplace_back(std::move(resolved_arg));
  }
  return std::make_unique<ResolvedCallExpr>(call.location, resolved_func_decl,
                                            std::move(resolved_args));
}
} // namespace saplang
