#include <llvm-18/llvm/Support/ErrorHandling.h>

#include "constexpr.h"

namespace saplang {

std::optional<bool> to_bool(std::optional<Value> val, Type::Kind kind) {
  if (!val)
    return std::nullopt;
  switch (kind) {
  case Type::Kind::Bool:
    return val->b8;
  case Type::Kind::u8:
    return val->u8 != 0;
  case Type::Kind::i8:
    return val->i8 != 0;
  case Type::Kind::u16:
    return val->u16 != 0;
  case Type::Kind::i16:
    return val->i16 != 0;
  case Type::Kind::u32:
    return val->u32 != 0;
  case Type::Kind::i32:
    return val->i32 != 0;
  case Type::Kind::u64:
    return val->u64 != 0;
  case Type::Kind::i64:
    return val->i64 != 0;
  case Type::Kind::f32:
    return val->f32 != 0;
  case Type::Kind::f64:
    return val->f64 != 0;
  }
  llvm_unreachable("Unknown kind");
}

std::optional<Value> ConstantExpressionEvaluator::eval_binary_op(
    const ResolvedBinaryOperator &binop) {
  std::optional<Value> lhs = evaluate(*binop.lhs);
  if(binop.op == TokenKind::PipePipe) {
      if(to_bool(lhs, binop.lhs->type.kind).value_or(false))
          return
  }
}

std::optional<Value>
ConstantExpressionEvaluator::eval_unary_op(const ResolvedUnaryOperator &unop) {}

std::optional<Value>
ConstantExpressionEvaluator::evaluate(const ResolvedExpr &expr) {
  if (std::optional<Value> val = expr.get_constant_value())
    return val;
  if (const auto *numlit = dynamic_cast<const ResolvedNumberLiteral *>(&expr)) {
    return numlit->value;
  }
  if (const auto *grouping_expr =
          dynamic_cast<const ResolvedGroupingExpr *>(&expr)) {
    return evaluate(*grouping_expr->expr);
  }
  if (const auto *binop = dynamic_cast<const ResolvedBinaryOperator *>(&expr)) {
    return eval_binary_op(*binop);
  }
  if (const auto *unop = dynamic_cast<const ResolvedUnaryOperator *>(&expr)) {
    return eval_unary_op(*unop);
  }
  return std::nullopt;
}
} // namespace saplang
