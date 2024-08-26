#include "ast.h"

#include <cfloat>
#include <climits>
#include <iostream>

namespace saplang {

void Block::dump_to_stream(std::stringstream &stream,
                           size_t indent_level) const {
  stream << indent(indent_level) << "Block\n";
  for (auto &&stmt : statements) {
    stmt->dump_to_stream(stream, indent_level + 1);
  }
}

void FunctionDecl::dump_to_stream(std::stringstream &stream,
                                  size_t indent_level) const {
  stream << indent(indent_level) << "FunctionDecl: " << id << ":" << type.name
         << '\n';
  for (auto &&param : params) {
    param->dump_to_stream(stream, indent_level + 1);
  }
  body->dump_to_stream(stream, indent_level + 1);
}

void ReturnStmt::dump_to_stream(std::stringstream &stream,
                                size_t indent_level) const {
  stream << indent(indent_level) << "ReturnStmt\n";
  if (expr) {
    expr->dump_to_stream(stream, indent_level + 1);
  }
}

void NumberLiteral::dump_to_stream(std::stringstream &stream,
                                   size_t indent_level) const {
  stream << indent(indent_level) << "NumberLiteral: ";
  switch (type) {
  case NumberType::Integer:
    stream << "integer(";
    break;
  case NumberType::Real:
    stream << "real(";
    break;
  case NumberType::Bool:
    stream << "bool(";
  }
  stream << value << ")"
         << "\n";
}

void GroupingExpr::dump_to_stream(std::stringstream &stream,
                                  size_t indent_level) const {
  stream << indent(indent_level) << "GroupingExpr:\n";
  expr->dump_to_stream(stream, indent_level + 1);
}

void dump_op(std::stringstream &stream, TokenKind op) {
  if (op == TokenKind::Plus)
    stream << '+';
  if (op == TokenKind::Minus)
    stream << '-';
  if (op == TokenKind::Asterisk)
    stream << '*';
  if (op == TokenKind::Slash)
    stream << '/';
  if (op == TokenKind::EqualEqual)
    stream << "==";
  if (op == TokenKind::AmpAmp)
    stream << "&&";
  if (op == TokenKind::PipePipe)
    stream << "||";
  if (op == TokenKind::LessThan)
    stream << '<';
  if (op == TokenKind::GreaterThan)
    stream << '>';
  if (op == TokenKind::Exclamation)
    stream << '!';
  else if (op == TokenKind::GreaterThanOrEqual)
    stream << ">=";
  else if (op == TokenKind::LessThanOrEqual)
    stream << "<=";
  else if (op == TokenKind::ExclamationEqual)
    stream << "!=";
}

void BinaryOperator::dump_to_stream(std::stringstream &stream,
                                    size_t indent_level) const {
  stream << indent(indent_level) << "BinaryOperator: '";
  dump_op(stream, op);
  stream << "\'\n";
  lhs->dump_to_stream(stream, indent_level + 1);
  rhs->dump_to_stream(stream, indent_level + 1);
}

void UnaryOperator::dump_to_stream(std::stringstream &stream,
                                   size_t indent_level) const {
  stream << indent(indent_level) << "UnaryOperator: '";
  dump_op(stream, op);
  stream << "\'\n";
  rhs->dump_to_stream(stream, indent_level + 1);
}

void DeclRefExpr::dump_to_stream(std::stringstream &stream,
                                 size_t indent_level) const {
  stream << indent(indent_level) << "DeclRefExpr: " << id << "\n";
}

void CallExpr::dump_to_stream(std::stringstream &stream,
                              size_t indent_level) const {
  stream << indent(indent_level) << "CallExpr:\n";
  id->dump_to_stream(stream, indent_level + 1);
  for (auto &&arg : args) {
    arg->dump_to_stream(stream, indent_level + 1);
  }
}

void ParamDecl::dump_to_stream(std::stringstream &stream,
                               size_t indent_level) const {
  stream << indent(indent_level) << "ParamDecl: " << id << ":" << type.name
         << "\n";
}

void ResolvedBlock::dump_to_stream(std::stringstream &stream,
                                   size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedBlock:\n";
  for (auto &&statement : statements) {
    statement->dump_to_stream(stream, indent_level + 1);
  }
}

void ResolvedParamDecl::dump_to_stream(std::stringstream &stream,
                                       size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedParamDecl: @(" << this << ") "
         << id << ":\n";
}

void ResolvedFuncDecl::dump_to_stream(std::stringstream &stream,
                                      size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedFuncDecl: @(" << this << ") " << id
         << ":\n";
  for (auto &&param : params) {
    param->dump_to_stream(stream, indent_level + 1);
  }
  if (body)
    body->dump_to_stream(stream, indent_level + 1);
}

void ResolvedDeclRefExpr::dump_to_stream(std::stringstream &stream,
                                         size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedDeclRefExpr: @(" << decl << ") "
         << decl->id << ":\n";
}

void ResolvedCallExpr::dump_to_stream(std::stringstream &stream,
                                      size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedCallExpr: @(" << func_decl << ") "
         << func_decl->id << ":\n";
  for (auto &&arg : args) {
    arg->dump_to_stream(stream, indent_level + 1);
  }
}

void ResolvedReturnStmt::dump_to_stream(std::stringstream &stream,
                                        size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedReturnStmt:\n";
  if (expr)
    expr->dump_to_stream(stream, indent_level + 1);
}

ResolvedNumberLiteral::ResolvedNumberLiteral(SourceLocation loc,
                                             NumberLiteral::NumberType num_type,
                                             const std::string &value_str)
    : ResolvedExpr(loc, Type::builtin_void()) {
  if (num_type == NumberLiteral::NumberType::Integer) {
    std::int64_t wide_type = std::stoll(value_str);
    if (wide_type > 0) {
      if (wide_type <= CHAR_MAX)
        type = Type::builtin_u8();
      else if (wide_type <= USHRT_MAX)
        type = Type::builtin_u16();
      else if (wide_type <= UINT_MAX)
        type = Type::builtin_u32();
      else if (wide_type <= ULONG_MAX)
        type = Type::builtin_u64();
    } else {
      if (wide_type >= SCHAR_MIN && wide_type <= SCHAR_MAX)
        type = Type::builtin_i8();
      else if (wide_type >= SHRT_MIN && wide_type <= SHRT_MAX)
        type = Type::builtin_i16();
      else if (wide_type >= INT_MIN && wide_type <= INT_MAX)
        type = Type::builtin_i32();
      else if (wide_type >= LONG_MIN && wide_type <= LONG_MAX)
        type = Type::builtin_i64();
    }
  } else if (num_type == NumberLiteral::NumberType::Bool) {
    type = Type::builtin_bool();
  } else {
    double wide_type = std::stod(value_str);
    if (wide_type >= FLT_MIN && wide_type <= FLT_MAX) {
      type = Type::builtin_f32();
    } else {
      type = Type::builtin_f64();
    }
  }
  switch (type.kind) {
  case Type::Kind::i8:
    value.i8 = static_cast<std::int8_t>(std::stoi(value_str));
    break;
  case Type::Kind::i16:
    value.i16 = static_cast<std::int16_t>(std::stoi(value_str));
    break;
  case Type::Kind::i32:
    value.i32 = static_cast<std::int32_t>(std::stol(value_str));
    break;
  case Type::Kind::i64:
    value.i64 = static_cast<std::int64_t>(std::stoll(value_str));
    break;
  case Type::Kind::u8:
    value.u8 = static_cast<std::uint8_t>(std::stoi(value_str));
    break;
  case Type::Kind::u16:
    value.u16 = static_cast<std::uint16_t>(std::stoi(value_str));
    break;
  case Type::Kind::u32:
    value.u32 = static_cast<std::uint32_t>(std::stol(value_str));
    break;
  case Type::Kind::u64:
    value.u64 = static_cast<std::uint64_t>(std::stoll(value_str));
    break;
  case Type::Kind::f32:
    value.f32 = std::stof(value_str);
    break;
  case Type::Kind::f64:
    value.f64 = std::stod(value_str);
    break;
  case Type::Kind::Bool:
    value.b8 = value_str == "true" ? true : false;
    break;
  default:
    // @TODO: implement rest
    break;
  }
}

void ResolvedGroupingExpr::dump_to_stream(std::stringstream &stream,
                                          size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedGroupingExpr:\n";
  expr->dump_to_stream(stream, indent_level + 1);
}
void ResolvedBinaryOperator::dump_to_stream(std::stringstream &stream,
                                            size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedBinaryOperator: '";
  dump_op(stream, op);
  stream << "\'\n";
  lhs->dump_to_stream(stream, indent_level + 1);
  rhs->dump_to_stream(stream, indent_level + 1);
}

void ResolvedUnaryOperator::dump_to_stream(std::stringstream &stream,
                                           size_t indent_level) const {

  stream << indent(indent_level) << "ResolvedBinaryOperator: '";
  dump_op(stream, op);
  stream << "\'\n";
  rhs->dump_to_stream(stream, indent_level + 1);
}

void ResolvedNumberLiteral::dump_to_stream(std::stringstream &stream,
                                           size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedNumberLiteral:\n";
  switch (type.kind) {
  case Type::Kind::i8:
    stream << indent(indent_level + 1) << "i8(" << value.i8 << ")";
    break;
  case Type::Kind::i16:
    stream << indent(indent_level + 1) << "i16(" << value.i16 << ")";
    break;
  case Type::Kind::i32:
    stream << indent(indent_level + 1) << "i32(" << value.i32 << ")";
    break;
  case Type::Kind::i64:
    stream << indent(indent_level + 1) << "i64(" << value.i64 << ")";
    break;
  case Type::Kind::u8:
    stream << indent(indent_level + 1) << "u8(" << value.u8 << ")";
    break;
  case Type::Kind::u16:
    stream << indent(indent_level + 1) << "u16(" << value.u16 << ")";
    break;
  case Type::Kind::u32:
    stream << indent(indent_level + 1) << "u32(" << value.u32 << ")";
    break;
  case Type::Kind::u64:
    stream << indent(indent_level + 1) << "u64(" << value.u64 << ")";
    break;
  case Type::Kind::f32:
    stream << indent(indent_level + 1) << "f32(" << value.f32 << ")";
    break;
  case Type::Kind::f64:
    stream << indent(indent_level + 1) << "f64(" << value.f64 << ")";
    break;
  case Type::Kind::Bool:
    stream << indent(indent_level + 1) << "bool(" << value.b8 << ")";
    break;
  default:
    // @TODO: implement rest
    break;
  }
}
} // namespace saplang
