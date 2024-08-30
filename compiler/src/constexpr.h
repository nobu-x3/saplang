#pragma once

#include <optional>

#include "ast.h"

namespace saplang {
class ConstantExpressionEvaluator {
public:
  std::optional<Value> evaluate(const ResolvedExpr &expr);

private:
  std::optional<Value> eval_binary_op(const ResolvedBinaryOperator &binop);
  std::optional<Value> eval_unary_op(const ResolvedUnaryOperator &unop);
};
} // namespace saplang
