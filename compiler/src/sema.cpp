#include "sema.h"

#include <cassert>
#include <unordered_map>

#include "cfg.h"

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
                      Value *old_value, std::string &errmsg) {

#define CAST_CASE(from, to)                                                    \
  case Type::Kind::from:                                                       \
    ret_val.to = old_value->from;                                              \
    break;

#define BOOL_CAST_CASE(to)                                                     \
  case Type::Kind::Bool:                                                       \
    ret_val.to = old_value->b8 ? 1 : 0;                                        \
    break;

  if (new_type == current_type)
    return *old_value;
  Value ret_val;
  switch (new_type) {
  case Type::Kind::Bool: {
    switch (current_type) {
    case Type::Kind::Bool:
      ret_val.b8 = old_value->b8;
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
    switch (current_type) {
      BOOL_CAST_CASE(i8)
    case Type::Kind::u8: {
      if (old_value->u8 > INT8_MAX)
        errmsg = "implicitly casting u8 to i8 with overflow";
      ret_val.i8 = static_cast<signed char>(old_value->u8);
    } break;
    }
  } break;
  case Type::Kind::i16: {
    switch (current_type) {
      BOOL_CAST_CASE(i16)
      CAST_CASE(i8, i16)
      CAST_CASE(u8, i16)
    case Type::Kind::u16: {
      if (old_value->u16 > INT16_MAX)
        errmsg = "casting u16 to i16 with overflow";
      ret_val.i16 = static_cast<short>(old_value->u16);
    } break;
    }
  } break;
  case Type::Kind::i32: {
    switch (current_type) {
      BOOL_CAST_CASE(i32)
      CAST_CASE(i8, i32)
      CAST_CASE(i16, i32)
      CAST_CASE(u8, i32);
      CAST_CASE(u16, i32)
    case Type::Kind::u32: {
      if (old_value->u32 > INT32_MAX)
        errmsg = "casting u32 to i32 with overflow";
      ret_val.i32 = static_cast<int>(old_value->u32);
    } break;
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
    case Type::Kind::u64: {
      if (old_value->u64 > INT64_MAX)
        errmsg = "casting u64 to i64 with overflow";
      ret_val.i64 = static_cast<long>(old_value->u64);
    } break;
    }
  } break;
  case Type::Kind::u8: {
    switch (current_type) {
      BOOL_CAST_CASE(u8)
    case Type::Kind::i8: {
      if (old_value->i8 < 0)
        errmsg = "implicitly casting i8 to u8 with underflow";
      ret_val.u8 = static_cast<unsigned char>(old_value->i8);
    } break;
    }
  } break;
  case Type::Kind::u16: {
    switch (current_type) {
      BOOL_CAST_CASE(u16)
      CAST_CASE(u8, u16)
    case Type::Kind::i16: {
      if (old_value->i16 < 0)
        errmsg = "implicitly casting i16 to u16 with underflow";
      ret_val.u16 = static_cast<unsigned short>(old_value->i16);
    } break;
    case Type::Kind::i8: {
      if (old_value->i8 < 0)
        errmsg = "implicitly casting i8 to u16 with underflow";
      ret_val.u16 = static_cast<unsigned int>(old_value->i8);
    } break;
    }
  } break;
  case Type::Kind::u32: {
    switch (current_type) {
      BOOL_CAST_CASE(u32)
      CAST_CASE(u8, u32)
      CAST_CASE(u16, u32)
    case Type::Kind::i32: {
      if (old_value->i32 < 0)
        errmsg = "implicitly casting i32 to u32 with underflow";
      ret_val.u32 = static_cast<unsigned int>(old_value->i32);
    } break;
    case Type::Kind::i16: {
      if (old_value->i16 < 0)
        errmsg = "implicitly casting i16 to u32 with underflow";
      ret_val.u32 = static_cast<unsigned int>(old_value->i16);
    } break;
    case Type::Kind::i8: {
      if (old_value->i8 < 0)
        errmsg = "implicitly casting i8 to u32 with underflow";
      ret_val.u32 = static_cast<unsigned int>(old_value->i8);
    } break;
    }
  } break;
  case Type::Kind::u64: {
    switch (current_type) {
      BOOL_CAST_CASE(u64)
      CAST_CASE(u8, u64)
      CAST_CASE(u16, u64)
      CAST_CASE(u32, u64)
    case Type::Kind::i64: {
      if (old_value->i64 < 0)
        errmsg = "implicitly casting i64 to u64 with underflow";
      ret_val.u64 = static_cast<unsigned long>(old_value->i64);
    } break;
    case Type::Kind::i32: {
      if (old_value->i32 < 0)
        errmsg = "implicitly casting i32 to u64 with underflow";
      ret_val.u64 = static_cast<unsigned int>(old_value->i32);
    } break;
    case Type::Kind::i16: {
      if (old_value->i16 < 0)
        errmsg = "implicitly casting i16 to u64 with underflow";
      ret_val.u64 = static_cast<unsigned int>(old_value->i16);
    } break;
    case Type::Kind::i8: {
      if (old_value->i8 < 0)
        errmsg = "implicitly casting i8 to u64 with underflow";
      ret_val.u64 = static_cast<unsigned int>(old_value->i8);
    } break;
    }
  } break;
  case Type::Kind::f32: {
    switch (current_type) {
      BOOL_CAST_CASE(f32)
      CAST_CASE(u8, f32)
      CAST_CASE(u16, f32)
      CAST_CASE(i8, f32)
      CAST_CASE(i16, f32)
    }
  } break;
  case Type::Kind::f64: {
    switch (current_type) {
      BOOL_CAST_CASE(f64)
      CAST_CASE(f32, f64)
      CAST_CASE(u8, f64)
      CAST_CASE(u16, f64)
      CAST_CASE(u32, f64)
      CAST_CASE(i8, f64)
      CAST_CASE(i16, f64)
      CAST_CASE(i32, f64)
    }
  } break;
  }
  return ret_val;
}

bool can_be_cast(Type::Kind cast_from, Type::Kind cast_to) {
  return cast_to != Type::Kind::Void && cast_from != Type::Kind::Void &&
         g_AssociatedNumberLiteralSizes.count(cast_from) &&
         g_AssociatedNumberLiteralSizes.count(cast_to) &&
         g_AssociatedNumberLiteralSizes[cast_from] <=
             g_AssociatedNumberLiteralSizes[cast_to];
}

bool implicit_cast_numlit(ResolvedNumberLiteral *number_literal,
                          Type::Kind cast_to) {
  if (can_be_cast(number_literal->type.kind, cast_to)) {
    std::string errmsg;
    number_literal->value = construct_value(number_literal->type.kind, cast_to,
                                            &number_literal->value, errmsg);
    if (!errmsg.empty())
      report(number_literal->location, errmsg);
    return true;
  }
  return false;
}

bool try_cast_expr(ResolvedExpr &expr, const Type &type,
                   ConstantExpressionEvaluator &cee) {
  if (auto *groupexp = dynamic_cast<ResolvedGroupingExpr *>(&expr)) {
    if (try_cast_expr(*groupexp->expr, type, cee)) {
      groupexp->type = type;
      groupexp->set_constant_value(cee.evaluate(*groupexp));
    }
    return true;
  } else if (auto *binop = dynamic_cast<ResolvedBinaryOperator *>(&expr)) {
    Type max_type = binop->lhs->type.kind > binop->rhs->type.kind
                        ? binop->lhs->type
                        : binop->rhs->type;
    max_type = type.kind > max_type.kind ? type : max_type;
    if (try_cast_expr(*binop->lhs, max_type, cee) &&
        try_cast_expr(*binop->rhs, max_type, cee)) {
      binop->type = type;
      binop->set_constant_value(cee.evaluate(*binop));
    }
    return true;
  } else if (auto *unop = dynamic_cast<ResolvedUnaryOperator *>(&expr)) {
    if (try_cast_expr(*unop->rhs, type, cee)) {
      unop->type = type;
      unop->set_constant_value(cee.evaluate(*unop));
    }
    return true;
  } else if (auto *number_literal =
                 dynamic_cast<ResolvedNumberLiteral *>(&expr)) {
    if (implicit_cast_numlit(number_literal, type.kind)) {
      number_literal->type = type;
      number_literal->set_constant_value(cee.evaluate(*number_literal));
    }
    return true;
  } else if (auto *decl_ref = dynamic_cast<ResolvedDeclRefExpr *>(&expr)) {
    if (can_be_cast(decl_ref->type.kind, type.kind)) {
      decl_ref->type = type;
    }
    return true;
  } else if (auto *call_expr = dynamic_cast<ResolvedCallExpr *>(&expr)) {
    if (can_be_cast(call_expr->func_decl->type.kind, type.kind)) {
      call_expr->type = type;
      call_expr->set_constant_value(cee.evaluate(*call_expr));
      return true;
    }
    return false;
  }
  return false;
}

std::unique_ptr<ResolvedIfStmt> Sema::resolve_if_stmt(const IfStmt &stmt) {
  std::unique_ptr<ResolvedExpr> condition = resolve_expr(*stmt.condition);
  if (!condition)
    return nullptr;
  if (condition->type.kind != Type::Kind::Bool) {
    if (!try_cast_expr(*condition, Type::builtin_bool(), m_Cee))
      return report(condition->location,
                    "condition is expected to evaluate to bool.");
  }
  std::unique_ptr<ResolvedBlock> true_block = resolve_block(*stmt.true_block);
  if (!true_block)
    return nullptr;
  std::unique_ptr<ResolvedBlock> false_block;
  if (stmt.false_block) {
    false_block = resolve_block(*stmt.false_block);
    if (!false_block)
      return nullptr;
  }
  condition->set_constant_value(m_Cee.evaluate(*condition));
  return std::make_unique<ResolvedIfStmt>(stmt.location, std::move(condition),
                                          std::move(true_block),
                                          std::move(false_block));
}

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
  for (auto &&decl : m_AST) {
    if (auto *fn = dynamic_cast<const FunctionDecl *>(decl.get())) {
      auto resolved_fn_decl = resolve_func_decl(*fn);
      if (!resolved_fn_decl ||
          !insert_decl_to_current_scope(*resolved_fn_decl)) {
        error = true;
        continue;
      }
      resolved_functions.emplace_back(std::move(resolved_fn_decl));
      if (error && !partial)
        return {};
    }
  }
  for (int i = 0; i < resolved_functions.size(); ++i) {
    Scope fn_scope{this};
    if (auto *fn = dynamic_cast<const FunctionDecl *>(m_AST[i].get())) {
      m_CurrFunction = resolved_functions[i].get();
      for (auto &&param : m_CurrFunction->params) {
        insert_decl_to_current_scope(*param);
      }
      auto resolved_body = resolve_block(*fn->body);
      if (!resolved_body) {
        error = true;
        continue;
      }
      m_CurrFunction->body = std::move(resolved_body);
      if (m_ShouldRunFlowSensitiveAnalysis)
        error |= flow_sensitive_analysis(*m_CurrFunction);
    }
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
                                             std::move(*type), decl.is_const);
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
  if (auto *return_stmt = dynamic_cast<const ReturnStmt *>(&stmt))
    return resolve_return_stmt(*return_stmt);
  if (auto *if_stmt = dynamic_cast<const IfStmt *>(&stmt))
    return resolve_if_stmt(*if_stmt);
  if (auto *while_stmt = dynamic_cast<const WhileStmt *>(&stmt))
    return resolve_while_stmt(*while_stmt);
  if (auto *var_decl_stmt = dynamic_cast<const DeclStmt *>(&stmt))
    return resolve_decl_stmt(*var_decl_stmt);
  if (auto *assignment = dynamic_cast<const Assignment *>(&stmt))
    return resolve_assignment(*assignment);
  if (auto *for_stmt = dynamic_cast<const ForStmt *>(&stmt))
    return resolve_for_stmt(*for_stmt);
  assert(false && "unexpected expression.");
  return nullptr;
}

std::unique_ptr<ResolvedDeclStmt>
Sema::resolve_decl_stmt(const DeclStmt &stmt) {
  std::unique_ptr<ResolvedVarDecl> var_decl = resolve_var_decl(*stmt.var_decl);
  if (!var_decl)
    return nullptr;
  if (!insert_decl_to_current_scope(*var_decl))
    return nullptr;
  return std::make_unique<ResolvedDeclStmt>(stmt.location, std::move(var_decl));
}

std::unique_ptr<ResolvedVarDecl> Sema::resolve_var_decl(const VarDecl &decl) {
  std::optional<Type> type = resolve_type(decl.type);
  if (!type || type->kind == Type::Kind::Void)
    return report(decl.location, "variable '" + decl.id + "' has invalid '" +
                                     decl.type.name + "' type.");
  std::unique_ptr<ResolvedExpr> resolved_initializer = nullptr;
  if (decl.initializer) {
    resolved_initializer = resolve_expr(*decl.initializer);
    if (!resolved_initializer)
      return nullptr;
    if (resolved_initializer->type.kind != type->kind) {
      if (!try_cast_expr(*resolved_initializer, *type, m_Cee))
        return report(resolved_initializer->location,
                      "initializer type mismatch.");
    }
    resolved_initializer->set_constant_value(
        m_Cee.evaluate(*resolved_initializer));
  }
  return std::make_unique<ResolvedVarDecl>(decl.location, decl.id, decl.type,
                                           std::move(resolved_initializer),
                                           decl.is_const);
}

std::unique_ptr<ResolvedGroupingExpr>
Sema::resolve_grouping_expr(const GroupingExpr &group) {
  auto resolved_expr = resolve_expr(*group.expr);
  if (!resolved_expr)
    return nullptr;
  return std::make_unique<ResolvedGroupingExpr>(group.location,
                                                std::move(resolved_expr));
}

bool is_comp_op(TokenKind op) {
  if (op == TokenKind::LessThan || op == TokenKind::LessThanOrEqual ||
      op == TokenKind::GreaterThan || op == TokenKind::GreaterThanOrEqual ||
      op == TokenKind::ExclamationEqual || op == TokenKind::EqualEqual)
    return true;
  return false;
}

std::unique_ptr<ResolvedBinaryOperator>
Sema::resolve_binary_operator(const BinaryOperator &op) {
  auto resolved_lhs = resolve_expr(*op.lhs);
  auto resolved_rhs = resolve_expr(*op.rhs);
  if (!resolved_lhs || !resolved_rhs)
    return nullptr;
  if (is_comp_op(op.op) && resolved_lhs->type.kind != resolved_rhs->type.kind) {
    if (!try_cast_expr(*resolved_rhs, resolved_lhs->type, m_Cee))
      return report(resolved_lhs->location,
                    "cannot implicitly cast rhs to lhs - from type '" +
                        resolved_rhs->type.name + "' to type '" +
                        resolved_lhs->type.name + "'.");
  }
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

std::unique_ptr<ResolvedWhileStmt>
Sema::resolve_while_stmt(const WhileStmt &stmt) {
  std::unique_ptr<ResolvedExpr> condition = resolve_expr(*stmt.condition);
  if (!condition)
    return nullptr;
  if (condition->type.kind != Type::Kind::Bool) {
    if (!try_cast_expr(*condition, Type::builtin_bool(), m_Cee))
      return report(condition->location,
                    "condition is expected to evaluate to bool.");
  }
  std::unique_ptr<ResolvedBlock> body = resolve_block(*stmt.body);
  if (!body)
    return nullptr;
  condition->set_constant_value(m_Cee.evaluate(*condition));
  return std::make_unique<ResolvedWhileStmt>(
      stmt.location, std::move(condition), std::move(body));
}

std::unique_ptr<ResolvedForStmt> Sema::resolve_for_stmt(const ForStmt &stmt) {
  std::unique_ptr<ResolvedDeclStmt> counter_variable =
      resolve_decl_stmt(*stmt.counter_variable);
  if (!counter_variable)
    return nullptr;
  std::unique_ptr<ResolvedExpr> condition = resolve_expr(*stmt.condition);
  if (!condition)
    return nullptr;
  condition->set_constant_value(m_Cee.evaluate(*condition));
  std::unique_ptr<ResolvedStmt> increment_expr =
      resolve_stmt(*stmt.increment_expr);
  if (!increment_expr)
    return nullptr;
  std::unique_ptr<ResolvedBlock> body = resolve_block(*stmt.body);
  if (!body)
    return nullptr;
  return std::make_unique<ResolvedForStmt>(
      stmt.location, std::move(counter_variable), std::move(condition),
      std::move(increment_expr), std::move(body));
}

bool Sema::flow_sensitive_analysis(const ResolvedFuncDecl &fn) {
  CFG cfg = CFGBuilder().build(fn);
  bool error = false;
  error |= check_return_on_all_paths(fn, cfg);
  return error;
}

bool Sema::check_return_on_all_paths(const ResolvedFuncDecl &fn,
                                     const CFG &cfg) {
  if (fn.type.kind == Type::Kind::Void)
    return false;
  std::set<int> visited{};
  std::vector<int> worklist{};
  worklist.emplace_back(cfg.entry);
  int return_count = 0;
  bool exit_reached = false;
  while (!worklist.empty()) {
    int basic_block = worklist.back();
    worklist.pop_back();
    if (!visited.emplace(basic_block).second)
      continue;
    exit_reached |= basic_block == cfg.exit;
    const auto &[preds, succs, stmts] = cfg.basic_blocks[basic_block];
    if (!stmts.empty() && dynamic_cast<const ResolvedReturnStmt *>(stmts[0])) {
      ++return_count;
      continue;
    }
    for (auto &&[succ, reachable] : succs) {
      if (reachable)
        worklist.emplace_back(succ);
    }
  }
  if (exit_reached || return_count == 0) {
    report(fn.location,
           return_count > 0
               ? "non-void function does not have a return on every path."
               : "non-void function does not have a return value.");
  }
  return exit_reached || return_count == 0;
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
      if (!try_cast_expr(*resolved_expr, m_CurrFunction->type, m_Cee)) {
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
                  "expected to call function '" + decl_ref_expr.id + "'.");
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
    std::unique_ptr<ResolvedExpr> resolved_arg = resolve_expr(*call.args[i]);
    if (!resolved_arg)
      return nullptr;
    if (resolved_arg->type.kind != resolved_func_decl->params[i]->type.kind) {
      if (!try_cast_expr(*resolved_arg, resolved_func_decl->params[i]->type,
                         m_Cee)) {
        return report(resolved_arg->location,
                      "unexpected type '" + resolved_arg->type.name +
                          "', expected '" +
                          resolved_func_decl->params[i]->type.name + "'.");
      }
    }
    resolved_arg->set_constant_value(m_Cee.evaluate(*resolved_arg));
    resolved_args.emplace_back(std::move(resolved_arg));
  }
  return std::make_unique<ResolvedCallExpr>(call.location, resolved_func_decl,
                                            std::move(resolved_args));
}

std::unique_ptr<ResolvedAssignment>
Sema::resolve_assignment(const Assignment &assignment) {
  std::unique_ptr<ResolvedDeclRefExpr> lhs =
      resolve_decl_ref_expr(*assignment.variable);
  if (!lhs)
    return nullptr;
  if (const auto *param_decl =
          dynamic_cast<const ResolvedParamDecl *>(lhs->decl)) {
    if (param_decl->is_const)
      return report(lhs->location, "trying to assign to const variable.");
  } else if (const auto *var_decl =
                 dynamic_cast<const ResolvedVarDecl *>(lhs->decl)) {
    if (var_decl->is_const)
      return report(lhs->location, "trying to assign to const variable.");
  }
  std::unique_ptr<ResolvedExpr> rhs = resolve_expr(*assignment.expr);
  if (!rhs)
    return nullptr;
  if (lhs->type.kind != rhs->type.kind) {
    if (!try_cast_expr(*rhs, lhs->type, m_Cee))
      return report(rhs->location, "assigned value type of '" + rhs->type.name +
                                       "' does not match variable type '" +
                                       lhs->type.name + "'.");
  }
  rhs->set_constant_value(m_Cee.evaluate(*rhs));
  return std::make_unique<ResolvedAssignment>(assignment.location,
                                              std::move(lhs), std::move(rhs));
}
} // namespace saplang
