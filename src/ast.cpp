#include "ast.h"

#include <iostream>

namespace saplang {

void Block::dump(size_t indent_level) const {
  std::cerr << indent(indent_level) << "Block\n";
  for (auto &&stmt : statements) {
    stmt->dump(indent_level + 1);
  }
}

void FunctionDecl::dump(size_t indent_level) const {
  std::cerr << indent(indent_level) << "FunctionDecl: " << id << ":"
            << type.name << '\n';
  for (auto &&param : params) {
    param->dump(indent_level + 1);
  }
  body->dump(indent_level + 1);
}

void ReturnStmt::dump(size_t indent_level) const {
  std::cerr << indent(indent_level) << "ReturnStmt\n";
  if (expr) {
    expr->dump(indent_level + 1);
  }
}

void NumberLiteral::dump(size_t indent_level) const {
  std::cerr << indent(indent_level) << "NumberLiteral: "
            << (type == NumberType::Integer ? "integer(" : "real(") << value
            << ")" << "\n";
}

void DeclRefExpr::dump(size_t indent_level) const {
  std::cerr << indent(indent_level) << "DeclRefExpr: " << id << "\n";
}

void CallExpr::dump(size_t indent_level) const {
  std::cerr << indent(indent_level) << "CallExpr:\n";
  id->dump(indent_level + 1);
  for (auto &&arg : args) {
    arg->dump(indent_level + 1);
  }
}

void ParamDecl::dump(size_t indent_level) const {
  std::cerr << indent(indent_level) << "ParamDecl: " << id << ":" << type.name
            << "\n";
}
} // namespace saplang
