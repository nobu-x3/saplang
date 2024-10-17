#include "ast.h"

#include <cfloat>
#include <climits>
#include <iostream>
#include <sstream>

namespace saplang {

// Type Type::get_builtin_type(Kind kind) {
//   static std::unordered_map<Kind, Type> s_TypeMap{
//       {Kind::Bool, {Type::builtin_bool()}},
//       {Kind::Void, {Type::builtin_void()}},
//       {Kind::i8, {Type::builtin_i8()}},
//       {Kind::u8, {Type::builtin_u8()}},
//       {Kind::i16, {Type::builtin_i16()}},
//       {Kind::u16, {Type::builtin_u16()}},
//       {Kind::i32, {Type::builtin_i32()}},
//       {Kind::u32, {Type::builtin_u32()}},
//       {Kind::i64, {Type::builtin_i64()}},
//       {Kind::u64, {Type::builtin_u64()}},
//       {Kind::f32, {Type::builtin_f32()}},
//       {Kind::f64, {Type::builtin_f64()}},
//       // {Kind::Bool, {Kind::Bool, "bool"}}, {Kind::Void, {Kind::Void,
//       "void"}},
//       // {Kind::i8, {Kind::i8, "i8"}},       {Kind::u8, {Kind::u8, "u8"}},
//       // {Kind::i16, {Kind::i16, "i16"}},    {Kind::u16, {Kind::u16, "u16"}},
//       // {Kind::i32, {Kind::i32, "i32"}},    {Kind::u32, {Kind::u32, "u32"}},
//       // {Kind::i64, {Kind::i64, "i64"}},    {Kind::u64, {Kind::u64, "u64"}},
//       // {Kind::f32, {Kind::f32, "f32"}},    {Kind::f64, {Kind::f64, "f64"}},
//   };
//   return s_TypeMap[kind];
// }

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

size_t get_size(Type::Kind kind) {
  return g_AssociatedNumberLiteralSizes[kind];
}

bool does_type_have_associated_size(Type::Kind kind) {
  return g_AssociatedNumberLiteralSizes.count(kind);
}

Type platform_ptr_type() { return Type::builtin_i64(0); }

size_t platform_ptr_size() {
  return g_AssociatedNumberLiteralSizes[Type::Kind::i64];
}

void dump_constant(std::stringstream &stream, size_t indent_level, Value value,
                   Type::Kind kind) {
  switch (kind) {
  case Type::Kind::i8:
    stream << indent(indent_level + 1) << "i8(" << static_cast<int>(value.i8)
           << ")";
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
    stream << indent(indent_level + 1) << "u8("
           << static_cast<unsigned int>(value.u8) << ")";
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

void NullExpr::dump_to_stream(std::stringstream &stream,
                              size_t indent_level) const {
  stream << indent(indent_level) << "Null\n";
}

void Block::dump_to_stream(std::stringstream &stream,
                           size_t indent_level) const {
  stream << indent(indent_level) << "Block\n";
  for (auto &&stmt : statements) {
    stmt->dump_to_stream(stream, indent_level + 1);
  }
}

void ForStmt::dump_to_stream(std::stringstream &stream,
                             size_t indent_level) const {
  stream << indent(indent_level) << "ForStmt:\n";
  counter_variable->dump_to_stream(stream, indent_level + 1);
  condition->dump_to_stream(stream, indent_level + 1);
  increment_expr->dump_to_stream(stream, indent_level + 1);
  body->dump_to_stream(stream, indent_level + 1);
}

void WhileStmt::dump_to_stream(std::stringstream &stream,
                               size_t indent_level) const {
  stream << indent(indent_level) << "WhileStmt\n";
  condition->dump_to_stream(stream, indent_level + 1);
  body->dump_to_stream(stream, indent_level + 1);
}

void IfStmt::dump_to_stream(std::stringstream &stream,
                            size_t indent_level) const {
  stream << indent(indent_level) << "IfStmt\n";
  condition->dump_to_stream(stream, indent_level + 1);

  stream << indent(indent_level + 1) << "IfBlock\n";
  true_block->dump_to_stream(stream, indent_level + 2);
  if (false_block) {
    stream << indent(indent_level + 1) << "ElseBlock\n";
    false_block->dump_to_stream(stream, indent_level + 2);
  }
}

void FunctionDecl::dump_to_stream(std::stringstream &stream,
                                  size_t indent_level) const {
  stream << indent(indent_level) << "FunctionDecl: " << id << ":";
  for (uint i = 0; i < type.pointer_depth; ++i) {
    stream << "ptr ";
  }
  stream << type.name << '\n';
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

void StructDecl::dump_to_stream(std::stringstream &stream,
                                size_t indent_level) const {
  stream << indent(indent_level) << "StructDecl: " << id << "\n";
  for (auto &&[type, name] : members) {
    stream << indent(indent_level + 1) << "MemberField: ";
    for (uint i = 0; i < type.pointer_depth; ++i) {
      stream << "ptr ";
    }
    stream << type.name << "(" << name << ")\n";
  }
}

void VarDecl::dump_to_stream(std::stringstream &stream,
                             size_t indent_level) const {
  stream << indent(indent_level) << "VarDecl: " << id << ":"
         << (is_const ? "const " : "");

  for (uint i = 0; i < type.pointer_depth; ++i) {
    stream << "ptr ";
  }
  stream << type.name << "\n";
  if (initializer)
    initializer->dump_to_stream(stream, indent_level + 1);
}

void DeclStmt::dump_to_stream(std::stringstream &stream,
                              size_t indent_level) const {
  stream << indent(indent_level) << "DeclStmt:\n";
  var_decl->dump_to_stream(stream, indent_level + 1);
}

void MemberAccess::dump_to_stream(std::stringstream &stream,
                                  size_t indent_level) const {
  stream << indent(indent_level) << "MemberAccess:\n";
  DeclRefExpr::dump_to_stream(stream, indent_level + 1);
  stream << indent(indent_level + 1) << "Field: " << field << "\n";
  if (inner_decl_ref_expr)
    inner_decl_ref_expr->dump_to_stream(stream, indent_level + 1);
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
  if (op == TokenKind::Amp)
    stream << '&';
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

void ExplicitCast::dump_to_stream(std::stringstream &stream,
                                  size_t indent_level) const {
  stream << indent(indent_level) << "ExplicitCast: ";
  for (uint i = 0; i < type.pointer_depth; ++i) {
    stream << "ptr ";
  }
  stream << type.name << "\n";
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

void StructLiteralExpr::dump_to_stream(std::stringstream &stream,
                                       size_t indent_level) const {
  stream << indent(indent_level) << "StructLiteralExpr:\n";
  for (auto &&[name, expr] : field_initializers) {
    stream << indent(indent_level + 1) << "FieldInitializer: " << name << "\n";
    expr->dump_to_stream(stream, indent_level + 1);
  }
}

void Assignment::dump_to_stream(std::stringstream &stream,
                                size_t indent_level) const {
  stream << indent(indent_level) << "Assignment:\n";
  variable->dump_to_stream(stream, indent_level + 1);
  expr->dump_to_stream(stream, indent_level + 1);
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
  stream << indent(indent_level) << "ParamDecl: " << id << ":"
         << (is_const ? "const " : "");
  for (uint i = 0; i < type.pointer_depth; ++i) {
    stream << "ptr ";
  }
  stream << type.name << "\n";
}

void ResolvedBlock::dump_to_stream(std::stringstream &stream,
                                   size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedBlock:\n";
  for (auto &&statement : statements) {
    statement->dump_to_stream(stream, indent_level + 1);
  }
}

void ResolvedForStmt::dump_to_stream(std::stringstream &stream,
                                     size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedForStmt:\n";
  counter_variable->dump_to_stream(stream, indent_level + 1);
  condition->dump_to_stream(stream, indent_level + 1);
  increment_expr->dump_to_stream(stream, indent_level + 1);
  body->dump_to_stream(stream, indent_level + 1);
}

void ResolvedWhileStmt::dump_to_stream(std::stringstream &stream,
                                       size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedWhileStmt\n";
  condition->dump_to_stream(stream, indent_level + 1);
  body->dump_to_stream(stream, indent_level + 1);
}

void ResolvedIfStmt::dump_to_stream(std::stringstream &stream,
                                    size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedIfStmt\n";
  condition->dump_to_stream(stream, indent_level + 1);

  stream << indent(indent_level + 1) << "ResolvedIfBlock\n";
  true_block->dump_to_stream(stream, indent_level + 2);
  if (false_block) {
    stream << indent(indent_level + 1) << "ResolvedElseBlock\n";
    false_block->dump_to_stream(stream, indent_level + 2);
  }
}

void ResolvedParamDecl::dump_to_stream(std::stringstream &stream,
                                       size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedParamDecl: @(" << this << ") "
         << id << ":\n";
}

void ResolvedVarDecl::dump_to_stream(std::stringstream &stream,
                                     size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedVarDecl: @(" << this << ") " << id
         << ":" << (is_global ? "global " : "") << (is_const ? "const " : "");
  for (uint i = 0; i < type.pointer_depth; ++i) {
    stream << "ptr ";
  }
  stream << type.name << "\n";
  if (initializer)
    initializer->dump_to_stream(stream, indent_level + 1);
}

void ResolvedStructDecl::dump_to_stream(std::stringstream &stream,
                                        size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedStructDecl: " << id << "\n";
  int member_index = 0;
  for (auto &&[type, name] : members) {
    stream << indent(indent_level + 1) << member_index
           << ". ResolvedMemberField: ";
    for (uint i = 0; i < type.pointer_depth; ++i) {
      stream << "ptr ";
    }
    stream << type.name << "(" << name << ")\n";
    ++member_index;
  }
}

void ResolvedDeclStmt::dump_to_stream(std::stringstream &stream,
                                      size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedDeclStmt:\n";
  var_decl->dump_to_stream(stream, indent_level + 1);
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
  if (auto resolved_constant_expr = get_constant_value()) {
    dump_constant(stream, indent_level, resolved_constant_expr->value,
                  resolved_constant_expr->kind);
    stream << "\n";
  }
}

void ResolvedExplicitCastExpr::dump_to_stream(std::stringstream &stream,
                                              size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedExplicitCast: ";
  for (uint i = 0; i < type.pointer_depth; ++i) {
    stream << "ptr ";
  }
  stream << type.name << "\n";
  std::string cast_type_name;
  switch (cast_type) {
  case ResolvedExplicitCastExpr::CastType::Nop:
    cast_type_name = "Nop";
    break;
  case ResolvedExplicitCastExpr::CastType::Extend:
    cast_type_name = "Extend";
    break;
  case ResolvedExplicitCastExpr::CastType::Truncate:
    cast_type_name = "Truncate";
    break;
  case ResolvedExplicitCastExpr::CastType::Ptr:
    cast_type_name = "Ptr";
    break;
  case ResolvedExplicitCastExpr::CastType::IntToPtr:
    cast_type_name = "IntToPtr";
    break;
  case ResolvedExplicitCastExpr::CastType::PtrToInt:
    cast_type_name = "PtrToInt";
    break;
  case ResolvedExplicitCastExpr::CastType::FloatToInt:
    cast_type_name = "FloatToInt";
    break;
  case ResolvedExplicitCastExpr::CastType::IntToFloat:
    cast_type_name = "IntToFloat";
    break;
  }
  stream << indent(indent_level + 1) << "CastType: " << cast_type_name << '\n';
  rhs->dump_to_stream(stream, indent_level + 1);
}

void ResolvedCallExpr::dump_to_stream(std::stringstream &stream,
                                      size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedCallExpr: @(" << func_decl << ") "
         << func_decl->id << ":\n";
  if (auto resolved_constant_expr = get_constant_value()) {
    dump_constant(stream, indent_level, resolved_constant_expr->value,
                  resolved_constant_expr->kind);
    stream << "\n";
  }
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
    : ResolvedExpr(loc, Type::builtin_void(false)) {
  if (num_type == NumberLiteral::NumberType::Integer) {
    std::int64_t wide_type = std::stoll(value_str);
    if (wide_type > 0) {
      if (wide_type <= CHAR_MAX)
        type = Type::builtin_u8(false);
      else if (wide_type <= USHRT_MAX)
        type = Type::builtin_u16(false);
      else if (wide_type <= UINT_MAX)
        type = Type::builtin_u32(false);
      else if (wide_type <= ULONG_MAX)
        type = Type::builtin_u64(false);
    } else {
      if (wide_type >= SCHAR_MIN && wide_type <= SCHAR_MAX)
        type = Type::builtin_i8(false);
      else if (wide_type >= SHRT_MIN && wide_type <= SHRT_MAX)
        type = Type::builtin_i16(false);
      else if (wide_type >= INT_MIN && wide_type <= INT_MAX)
        type = Type::builtin_i32(false);
      else if (wide_type >= LONG_MIN && wide_type <= LONG_MAX)
        type = Type::builtin_i64(false);
    }
  } else if (num_type == NumberLiteral::NumberType::Bool) {
    type = Type::builtin_bool(false);
  } else {
    double wide_type = std::stod(value_str);
    if (wide_type >= FLT_MIN && wide_type <= FLT_MAX) {
      type = Type::builtin_f32(false);
    } else {
      type = Type::builtin_f64(false);
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
    if (value_str == "true") {
      value.b8 = true;
    } else if (value_str == "false")
      value.b8 = false;
    break;
  default:
    // @TODO: implement rest
    break;
  }
}

void ResolvedGroupingExpr::dump_to_stream(std::stringstream &stream,
                                          size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedGroupingExpr:\n";
  if (auto resolved_constant_expr = get_constant_value()) {
    dump_constant(stream, indent_level, resolved_constant_expr->value,
                  resolved_constant_expr->kind);
    stream << "\n";
  }
  expr->dump_to_stream(stream, indent_level + 1);
}
void ResolvedBinaryOperator::dump_to_stream(std::stringstream &stream,
                                            size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedBinaryOperator: '";
  dump_op(stream, op);
  stream << "\'\n";
  if (auto resolved_constant_expr = get_constant_value()) {
    dump_constant(stream, indent_level, resolved_constant_expr->value,
                  resolved_constant_expr->kind);
    stream << "\n";
  }
  lhs->dump_to_stream(stream, indent_level + 1);
  rhs->dump_to_stream(stream, indent_level + 1);
}

void ResolvedUnaryOperator::dump_to_stream(std::stringstream &stream,
                                           size_t indent_level) const {

  stream << indent(indent_level) << "ResolvedUnaryOperator: '";
  dump_op(stream, op);
  stream << "\'\n";
  if (auto resolved_constant_expr = get_constant_value()) {
    dump_constant(stream, indent_level, resolved_constant_expr->value,
                  resolved_constant_expr->kind);
    stream << "\n";
  }
  rhs->dump_to_stream(stream, indent_level + 1);
}

void ResolvedNumberLiteral::dump_to_stream(std::stringstream &stream,
                                           size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedNumberLiteral:\n";
  dump_constant(stream, indent_level, value, type.kind);
  stream << "\n";
}

void ResolvedStructLiteralExpr::dump_to_stream(std::stringstream &stream,
                                               size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedStructLiteralExpr: ";
  for (uint i = 0; i < type.pointer_depth; ++i) {
    stream << "ptr ";
  }
  stream << type.name << "\n";
  for (auto &&[name, expr] : field_initializers) {
    stream << indent(indent_level + 1) << "ResolvedFieldInitializer: " << name
           << "\n";
    if (!expr) {
      stream << indent(indent_level + 1) << "Uninitialized\n";
      continue;
    }
    expr->dump_to_stream(stream, indent_level + 1);
  }
}

void ResolvedAssignment::dump_to_stream(std::stringstream &stream,
                                        size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedAssignment:\n";
  variable->dump_to_stream(stream, indent_level + 1);
  expr->dump_to_stream(stream, indent_level + 1);
}

void InnerMemberAccess::dump_to_stream(std::stringstream &stream,
                                       size_t indent_level) const {
  stream << indent(indent_level) << "MemberIndex: " << member_index << "\n";
  stream << indent(indent_level) << "MemberID:";
  for (uint i = 0; i < type.pointer_depth; ++i) {
    stream << "ptr ";
  }
  stream << type.name << "(" << member_id << ")"
         << "\n";
  if (inner_member_access)
    inner_member_access->dump_to_stream(stream, indent_level + 1);
}

void ResolvedStructMemberAccess::dump_to_stream(std::stringstream &stream,
                                                size_t indent_level) const {
  stream << indent(indent_level) << "ResolvedStructMemberAccess:\n";
  ResolvedDeclRefExpr::dump_to_stream(stream, indent_level + 1);
  inner_member_access->dump_to_stream(stream, indent_level + 1);
}

void ResolvedNullExpr::dump_to_stream(std::stringstream &stream,
                                      size_t indent_level) const {
  stream << indent(indent_level) << "Null\n";
}
} // namespace saplang
