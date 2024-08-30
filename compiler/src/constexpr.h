#pragma once

#include <optional>

#include "ast.h"

namespace saplang {
class ConstantExpressionEvaluator {
public:
  std::optional<ConstexprResult> evaluate(const ResolvedExpr &expr);

private:
  std::optional<ConstexprResult>
  eval_binary_op(const ResolvedBinaryOperator &binop);
  std::optional<ConstexprResult>
  eval_unary_op(const ResolvedUnaryOperator &unop);
};
} // namespace saplang
