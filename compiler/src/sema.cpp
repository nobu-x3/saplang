#include "sema.h"

#include <cassert>
#include <unordered_map>

namespace saplang {

std::unordered_map<Type::Kind, size_t> g_AssociatedNumberLiteralSizes{
    {Type::Kind::Bool, sizeof(bool)},
    {Type::Kind::u8, sizeof(char)},
    {Type::Kind::i8, sizeof(char)},
    {Type::Kind::u16, sizeof(std::uint16_t)},
    {Type::Kind::i16, sizeof(std::int16_t)},
    {Type::Kind::u32, sizeof(std::uint32_t)},
    {Type::Kind::i32, sizeof(std::int32_t)},
    {Type::Kind::u64, sizeof(std::uint64_t)},
    {Type::Kind::i64, sizeof(std::int64_t)},
    {Type::Kind::f32, sizeof(float)},
    {Type::Kind::f64, sizeof(double)},
};

std::optional<DeclLookupResult> Sema::lookup_decl(std::string_view id,
                                                  std::optional<Type *> type) {
  int scope_id = 0;
  for (auto it = m_Scopes.rbegin(); it != m_Scopes.rend(); ++it) {
    for (const auto *decl : *it) {
      if (decl->id == id) {
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
    report(decl.location, "redeclaration of '" + decl.id + "\'.");
    return false;
  }
  m_Scopes.back().emplace_back(&decl);
  return true;
}

std::vector<std::unique_ptr<ResolvedFuncDecl>> Sema::resolve_ast(bool partial) {
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
  if (error && !partial)
    return {};
  for (int i = 0; i < resolved_functions.size(); ++i) {
    Scope fn_scope{this};
    m_CurrFunction = resolved_functions[i].get();
    for (auto &&param : m_CurrFunction->params) {
      insert_decl_to_current_scope(*param);
    }
    auto resolved_body = resolve_block(*m_AST[i]->body);
    if (!resolved_body) {
      error = true;
      continue;
    }
    m_CurrFunction->body = std::move(resolved_body);
  }
  if (error && !partial)
    return {};
  return resolved_functions;
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
  return nullptr;
}

std::unique_ptr<ResolvedGroupingExpr>
Sema::resolve_grouping_expr(const GroupingExpr &group) {
  auto resolved_expr = resolve_expr(*group.expr);
  if (!resolved_expr)
    return nullptr;
  return std::make_unique<ResolvedGroupingExpr>(group.location,
                                                std::move(resolved_expr));
}

std::unique_ptr<ResolvedBinaryOperator>
Sema::resolve_binary_operator(const BinaryOperator &op) {
  auto resolved_lhs = resolve_expr(*op.lhs);
  auto resolved_rhs = resolve_expr(*op.rhs);
  if (!resolved_lhs || !resolved_rhs)
    return nullptr;
  return std::make_unique<ResolvedBinaryOperator>(
      op.location, std::move(resolved_lhs), std::move(resolved_rhs), op.op);
}

std::unique_ptr<ResolvedUnaryOperator>
Sema::resolve_unary_operator(const UnaryOperator &op) {
  auto resolved_rhs = resolve_expr(*op.rhs);
  if (!resolved_rhs)
    return nullptr;
  if (resolved_rhs->type.kind == Type::Kind::Void)
    return report(
        resolved_rhs->location,
        "void expression cannot be used as operand to unary operator.");
  return std::make_unique<ResolvedUnaryOperator>(
      op.location, std::move(resolved_rhs), op.op);
}

void apply_unary_op_to_num_literal(ResolvedUnaryOperator *unop) {
  // @TODO: implement call exprs too
  auto *numlit = dynamic_cast<ResolvedNumberLiteral *>(unop->rhs.get());
  if (!numlit)
    return;
  if (unop->op == TokenKind::Minus) {
    switch (numlit->type.kind) {
    case Type::Kind::i8:
      numlit->value.i8 *= -1;
      break;
    case Type::Kind::u8:
      numlit->value.u8 *= -1;
      break;
    case Type::Kind::i16:
      numlit->value.i16 *= -1;
      break;
    case Type::Kind::u16:
      numlit->value.u16 *= -1;
      break;
    case Type::Kind::i32:
      numlit->value.i32 *= -1;
      break;
    case Type::Kind::u32:
      numlit->value.u32 *= -1;
      break;
    case Type::Kind::i64:
      numlit->value.i64 *= -1;
      break;
    case Type::Kind::u64:
      numlit->value.u64 *= -1;
      break;
    case Type::Kind::f32:
      numlit->value.i32 *= -1;
      break;
    case Type::Kind::f64:
      numlit->value.f64 *= -1;
      break;
    case Type::Kind::Bool:
      numlit->value.b8 *= -1;
      break;
    }
  } else if (unop->op == TokenKind::Exclamation) {
    switch (numlit->type.kind) {
    case Type::Kind::i8:
      numlit->value.b8 = !numlit->value.i8;
      break;
    case Type::Kind::u8:
      numlit->value.u8 = !numlit->value.u8;
      break;
    case Type::Kind::i16:
      numlit->value.i16 = !numlit->value.i16;
      break;
    case Type::Kind::u16:
      numlit->value.u16 = !numlit->value.u16;
      break;
    case Type::Kind::i32:
      numlit->value.i32 = !numlit->value.i32;
      break;
    case Type::Kind::u32:
      numlit->value.u32 = !numlit->value.u32;
      break;
    case Type::Kind::i64:
      numlit->value.i64 = !numlit->value.i64;
      break;
    case Type::Kind::u64:
      numlit->value.u64 = !numlit->value.u64;
      break;
    case Type::Kind::f32:
      numlit->value.i32 = !numlit->value.i32;
      break;
    case Type::Kind::f64:
      numlit->value.f64 = !numlit->value.f64;
      break;
    case Type::Kind::Bool:
      numlit->value.b8 = !numlit->value.b8;
      break;
    }
  }
}

Value construct_value(Type::Kind current_type, Type::Kind new_type,
                      Value *old_value) {

#define CAST_CASE(from, to)                                                    \
  case Type::Kind::from:                                                       \
    ret_val.to = old_value->from;                                              \
    break;

#define BOOL_CAST_CASE(to)                                                     \
  case Type::Kind::Bool:                                                       \
    ret_val.to = old_value->b8 ? 1 : 0;                                        \
    break;

  Value ret_val;
  switch (new_type) {
  case Type::Kind::Bool: {
    switch (current_type) {
    case Type::Kind::i8:
      ret_val.b8 = old_value->i8 > 0 ? true : false;
      break;
    case Type::Kind::i16:
      ret_val.b8 = old_value->i16 > 0 ? true : false;
      break;
    case Type::Kind::i32:
      ret_val.b8 = old_value->i32 > 0 ? true : false;
      break;
    case Type::Kind::i64:
      ret_val.b8 = old_value->i64 > 0 ? true : false;
      break;
    case Type::Kind::u8:
      ret_val.b8 = old_value->u8 > 0 ? true : false;
      break;
    case Type::Kind::u16:
      ret_val.b8 = old_value->u16 > 0 ? true : false;
      break;
    case Type::Kind::u32:
      ret_val.b8 = old_value->u32 > 0 ? true : false;
      break;
    case Type::Kind::u64:
      ret_val.b8 = old_value->u64 > 0 ? true : false;
      break;
    case Type::Kind::f32:
      ret_val.b8 = old_value->f32 > 0 ? true : false;
      break;
    case Type::Kind::f64:
      ret_val.b8 = old_value->f64 > 0 ? true : false;
      break;
    }
  } break;
  case Type::Kind::i8: {
    switch (current_type) { BOOL_CAST_CASE(i8) }
  } break;
  case Type::Kind::i16: {
    switch (current_type) {
      BOOL_CAST_CASE(i16)
      CAST_CASE(i8, i16)
      CAST_CASE(u8, i16)
    }
  } break;
  case Type::Kind::i32: {
    switch (current_type) {
      BOOL_CAST_CASE(i32)
      CAST_CASE(i8, i32)
      CAST_CASE(i16, i32)
      CAST_CASE(u8, i32)
      CAST_CASE(u16, i32)
    }
  } break;
  case Type::Kind::i64: {
    switch (current_type) {
      BOOL_CAST_CASE(i64)
      CAST_CASE(i8, i64)
      CAST_CASE(i16, i64)
      CAST_CASE(i32, i64)
      CAST_CASE(u8, i64)
      CAST_CASE(u16, i64)
      CAST_CASE(u32, i64)
    }
  } break;
  case Type::Kind::u8: {
    switch (current_type) { BOOL_CAST_CASE(u8) }
  } break;
  case Type::Kind::u16: {
    switch (current_type) {
      BOOL_CAST_CASE(u16)
      CAST_CASE(u8, u16)
    }
  } break;
  case Type::Kind::u32: {
    switch (current_type) {
      BOOL_CAST_CASE(u32)
      CAST_CASE(u8, u32)
      CAST_CASE(u16, u32)
    }
  } break;
  case Type::Kind::u64: {
    switch (current_type) {
      BOOL_CAST_CASE(u64)
      CAST_CASE(u8, u64)
      CAST_CASE(u16, u64)
      CAST_CASE(u32, u64)
    }
  } break;
  case Type::Kind::f32: {
    switch (current_type) { BOOL_CAST_CASE(f32) }
  } break;
  case Type::Kind::f64: {
    switch (current_type) {
      BOOL_CAST_CASE(f64)
      CAST_CASE(f32, f64)
    }
  } break;
  }
  return ret_val;
}

bool implicit_cast_numlit(ResolvedNumberLiteral *number_literal,
                          Type::Kind cast_to) {
  if (g_AssociatedNumberLiteralSizes.count(number_literal->type.kind) &&
      g_AssociatedNumberLiteralSizes.count(cast_to) &&
      g_AssociatedNumberLiteralSizes[number_literal->type.kind] <=
          g_AssociatedNumberLiteralSizes[cast_to]) {
    number_literal->value = construct_value(number_literal->type.kind, cast_to,
                                            &number_literal->value);
    return true;
  }
  return false;
}

std::unique_ptr<ResolvedReturnStmt>
Sema::resolve_return_stmt(const ReturnStmt &stmt) {
  assert(m_CurrFunction && "return statement outside of function.");
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
      if (auto *unop =
              dynamic_cast<ResolvedUnaryOperator *>(resolved_expr.get())) {
        if (auto *number_literal =
                dynamic_cast<ResolvedNumberLiteral *>(unop->rhs.get())) {
          if (implicit_cast_numlit(number_literal, m_CurrFunction->type.kind)) {
            number_literal->type = m_CurrFunction->type;
            number_literal->set_constant_value(m_Cee.evaluate(*number_literal));
            unop->type = m_CurrFunction->type;
          }
        }
      } else if (auto *number_literal = dynamic_cast<ResolvedNumberLiteral *>(
                     resolved_expr.get())) {
        if (implicit_cast_numlit(number_literal, m_CurrFunction->type.kind)) {
          number_literal->type = m_CurrFunction->type;
          number_literal->set_constant_value(m_Cee.evaluate(*number_literal));
        }
      } else {
        return report(resolved_expr->location, "unexpected return type.");
      }
    }
    resolved_expr->set_constant_value(m_Cee.evaluate(*resolved_expr));
  }
  return std::make_unique<ResolvedReturnStmt>(stmt.location,
                                              std::move(resolved_expr));
}

std::unique_ptr<ResolvedExpr> Sema::resolve_expr(const Expr &expr) {
  if (const auto *number = dynamic_cast<const NumberLiteral *>(&expr))
    return std::make_unique<ResolvedNumberLiteral>(number->location,
                                                   number->type, number->value);
  if (const auto *decl_ref_expr = dynamic_cast<const DeclRefExpr *>(&expr))
    return resolve_decl_ref_expr(*decl_ref_expr);
  if (const auto *call_expr = dynamic_cast<const CallExpr *>(&expr))
    return resolve_call_expr(*call_expr);
  if (const auto *group_expr = dynamic_cast<const GroupingExpr *>(&expr))
    return resolve_grouping_expr(*group_expr);
  if (const auto *binary_op = dynamic_cast<const BinaryOperator *>(&expr))
    return resolve_binary_operator(*binary_op);
  if (const auto *unary_op = dynamic_cast<const UnaryOperator *>(&expr))
    return resolve_unary_operator(*unary_op);
  assert(false && "unexpected expression.");
  return nullptr;
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
  auto &&resolved_callee = resolve_decl_ref_expr(*call.id, true);
  if (!resolved_callee)
    return nullptr;
  const auto *decl_ref_expr = dynamic_cast<const DeclRefExpr *>(call.id.get());
  if (!decl_ref_expr)
    return report(call.location, "expression cannot be called as a function.");
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
      if (auto *number_literal =
              dynamic_cast<ResolvedNumberLiteral *>(resolved_arg.get())) {
        if (implicit_cast_numlit(number_literal, m_CurrFunction->type.kind)) {
          number_literal->type = m_CurrFunction->type;
        }
      } else {
        return report(resolved_arg->location,
                      "unexpected type '" + resolved_arg->type.name +
                          "', expected '" +
                          resolved_func_decl->params[i]->type.name + "'.");
      }
    resolved_arg->set_constant_value(m_Cee.evaluate(*resolved_arg));
    resolved_args.emplace_back(std::move(resolved_arg));
  }
  return std::make_unique<ResolvedCallExpr>(call.location, resolved_func_decl,
                                            std::move(resolved_args));
}
} // namespace saplang
