#include "sema.h"

#include <cassert>
#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>

#include "ast.h"
#include "cfg.h"
#include "lexer.h"
#include "utils.h"
#include <algorithm>
#include <numeric>
#include <utility>

namespace saplang {

bool Sema::is_enum(const Type &type) {
  auto decl = lookup_decl(type.name, &type);
  if (!decl)
    return false;
  if (auto *enum_decl = dynamic_cast<const ResolvedEnumDecl *>(decl->decl))
    return true;
  return false;
}

bool is_builtin_type_name(std::string_view name) {
  return name == "i8" || name == "i16" || name == "i32" || name == "i64" || name == "u8" || name == "u16" || name == "u32" || name == "u64" || name == "f32" ||
         name == "f64" || name == "bool" || name == "*";
}

void Sema::dump_type_infos_to_stream(std ::stringstream &stream, size_t indent_level) const {
  for (auto &&[type_name, type_info] : m_TypeInfos) {
    if (is_builtin_type_name(type_name))
      continue;
    stream << indent(indent_level) << "Type info - " << type_name << ":\n";
    type_info.dump_to_stream(stream, indent_level + 1);
  }
}

void Sema::init_builtin_type_infos() {
  m_TypeInfos.insert({"i8", {sizeof(signed char), alignof(signed char), {sizeof(signed char)}}});
  m_TypeInfos.insert({"i16", {sizeof(signed short), alignof(signed short), {sizeof(signed short)}}});
  m_TypeInfos.insert({"i32", {sizeof(signed int), alignof(signed int), {sizeof(signed int)}}});
  m_TypeInfos.insert({"i64", {sizeof(signed long), alignof(signed long), {sizeof(signed long)}}});
  m_TypeInfos.insert({"u8", {sizeof(unsigned char), alignof(unsigned char), {sizeof(unsigned char)}}});
  m_TypeInfos.insert({"u16", {sizeof(unsigned short), alignof(unsigned short), {sizeof(unsigned short)}}});
  m_TypeInfos.insert({"u32", {sizeof(unsigned int), alignof(unsigned int), {sizeof(unsigned int)}}});
  m_TypeInfos.insert({"u64", {sizeof(unsigned long), alignof(unsigned long), {sizeof(unsigned long)}}});
  m_TypeInfos.insert({"*", {PLATFORM_PTR_SIZE, PLATFORM_PTR_ALIGNMENT, {PLATFORM_PTR_SIZE}}});
  m_TypeInfos.insert({"f32", {sizeof(float), alignof(float), {sizeof(float)}}});
  m_TypeInfos.insert({"f64", {sizeof(double), alignof(double), {sizeof(double)}}});
  m_TypeInfos.insert({"bool", {sizeof(bool), alignof(bool), {sizeof(bool)}}});
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

Value construct_value(Type::Kind current_type, Type::Kind new_type, Value *old_value, std::string &errmsg) {

#define CAST_CASE(from, to)                                                                                                                                    \
  case Type::Kind::from:                                                                                                                                       \
    ret_val.to = old_value->from;                                                                                                                              \
    break;

#define BOOL_CAST_CASE(to)                                                                                                                                     \
  case Type::Kind::Bool:                                                                                                                                       \
    ret_val.to = old_value->b8 ? 1 : 0;                                                                                                                        \
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

bool is_void_ptr_cast(const Type &cast_from, const Type &cast_to) {
  return cast_from.kind == Type::Kind::Void && cast_from.pointer_depth == cast_to.pointer_depth && cast_from.pointer_depth > 0;
}

bool float_to_int_cast(const Type &cast_from, const Type &cast_to) {
  return cast_from.kind >= Type::Kind::FLOATS_START && cast_from.kind <= Type::Kind::FLOATS_END && cast_to.kind >= Type::Kind::INTEGERS_START &&
         cast_to.kind <= Type::Kind::INTEGERS_END;
}

bool can_be_cast(Type cast_from, Type cast_to) {
  return (cast_to.kind != Type::Kind::Void && cast_from.kind != Type::Kind::Void && does_type_have_associated_size(cast_from.kind) &&
          does_type_have_associated_size(cast_to.kind) && get_type_size(cast_from.kind) <= get_type_size(cast_to.kind) &&
          !float_to_int_cast(cast_from, cast_to)) ||
         is_void_ptr_cast(cast_from, cast_to);
}

bool implicit_cast_numlit(ResolvedNumberLiteral *number_literal, Type cast_to) {
  if (can_be_cast(number_literal->type, cast_to)) {
    std::string errmsg;
    number_literal->value = construct_value(number_literal->type.kind, cast_to.kind, &number_literal->value, errmsg);
    if (!errmsg.empty())
      report(number_literal->location, errmsg);
    return true;
  }
  return false;
}

bool try_cast_expr(ResolvedExpr &expr, const Type &type, ConstantExpressionEvaluator &cee, bool &is_array_decay) {
  is_array_decay = false;
  if (expr.type.array_data) {
    if (expr.type.kind != type.kind) {
      auto array_data = expr.type.array_data;
      expr.type.array_data = std::nullopt;
      try_cast_expr(expr, type, cee, is_array_decay);
      expr.type.array_data = array_data;
    }
    if (type.pointer_depth == expr.type.array_data->dimension_count && type.pointer_depth == 1) {
      is_array_decay = true;
      return try_cast_expr(expr, type, cee, is_array_decay);
    }
    return false;
  }
  // @TODO: NULLPTR COMPARISONS
  if (type.pointer_depth != expr.type.pointer_depth) {
    if (const auto *binop = dynamic_cast<const ResolvedBinaryOperator *>(&expr)) {
      if (const auto *null_expr_rhs = dynamic_cast<const ResolvedNullExpr *>(binop->rhs.get())) {
        return true;
      } else if (const auto *null_expr_lhs = dynamic_cast<const ResolvedNullExpr *>(binop->lhs.get())) {
        return true;
      } else {
        return try_cast_expr(*binop->lhs, type, cee, is_array_decay) && try_cast_expr(*binop->rhs, type, cee, is_array_decay);
      }
    } else if (const auto *groupexp = dynamic_cast<const ResolvedGroupingExpr *>(&expr)) {
      return try_cast_expr(*groupexp->expr, type, cee, is_array_decay);
    } else if (auto *numlit = dynamic_cast<ResolvedNumberLiteral *>(&expr)) {
      return numlit->type.pointer_depth == 0;
    }
    return false;
  }
  if (auto *groupexp = dynamic_cast<ResolvedGroupingExpr *>(&expr)) {
    if (try_cast_expr(*groupexp->expr, type, cee, is_array_decay)) {
      groupexp->type = type;
      groupexp->set_constant_value(cee.evaluate(*groupexp));
    }
    return true;
  } else if (auto *binop = dynamic_cast<ResolvedBinaryOperator *>(&expr)) {
    Type max_type = binop->lhs->type.kind > binop->rhs->type.kind ? binop->lhs->type : binop->rhs->type;
    max_type = type.kind > max_type.kind ? type : max_type;
    if (try_cast_expr(*binop->lhs, max_type, cee, is_array_decay) && try_cast_expr(*binop->rhs, max_type, cee, is_array_decay)) {
      if (!is_array_decay) {
        binop->type = type;
        binop->set_constant_value(cee.evaluate(*binop));
      }
    }
    return true;
  } else if (auto *unop = dynamic_cast<ResolvedUnaryOperator *>(&expr)) {
    if (try_cast_expr(*unop->rhs, type, cee, is_array_decay)) {
      if (!is_array_decay) {
        unop->type = type;
        unop->set_constant_value(cee.evaluate(*unop));
      }
    }
    return true;
  } else if (auto *number_literal = dynamic_cast<ResolvedNumberLiteral *>(&expr)) {
    if (implicit_cast_numlit(number_literal, type)) {
      number_literal->type = type;
      number_literal->set_constant_value(cee.evaluate(*number_literal));
      return true;
    }
  } else if (auto *decl_ref = dynamic_cast<ResolvedDeclRefExpr *>(&expr)) {
    if (can_be_cast(decl_ref->type, type)) {
      if (!is_array_decay)
        decl_ref->type = type;
    }
    return true;
  } else if (auto *call_expr = dynamic_cast<ResolvedCallExpr *>(&expr)) {
    if (can_be_cast(call_expr->decl->type, type)) {
      if (!is_array_decay) {
        call_expr->type = type;
        call_expr->set_constant_value(cee.evaluate(*call_expr));
      }
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
  bool is_array_decay;
  if (condition->type.kind != Type::Kind::Bool) {
    if (!try_cast_expr(*condition, Type::builtin_bool(false), m_Cee, is_array_decay))
      return report(condition->location, "condition is expected to evaluate to bool.");
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
  return std::make_unique<ResolvedIfStmt>(stmt.location, std::move(condition), std::move(true_block), std::move(false_block));
}

std::unique_ptr<ResolvedDeferStmt> Sema::resolve_defer_stmt(const DeferStmt &stmt) {
  auto block = resolve_block(*stmt.block);
  assert(block && "failed to resolve defer block.");
  return std::make_unique<ResolvedDeferStmt>(stmt.location, std::move(block));
}

std::optional<DeclLookupResult> Sema::lookup_decl(std::string_view id, std::optional<const Type *> type) {
  int scope_id = 0;
  for (auto it = m_Scopes.rbegin(); it != m_Scopes.rend(); ++it) {
    for (const ResolvedDecl *decl : *it) {
      if (decl->id == id) {
        return DeclLookupResult{decl, scope_id};
      }
    }
    ++scope_id;
  }
  return std::nullopt;
}

bool Sema::insert_decl_to_current_scope(ResolvedDecl &decl) {
  std::optional<DeclLookupResult> lookup_result = lookup_decl(decl.id, &decl.type);
  if (lookup_result && lookup_result->index == 0) {
    report(decl.location, "redeclaration of '" + decl.id + "\'.");
    return false;
  }
  m_Scopes.back().emplace_back(&decl);
  return true;
}

bool Sema::insert_decl_to_global_scope(ResolvedDecl &decl) {
  std::optional<DeclLookupResult> lookup_result = lookup_decl(decl.id, &decl.type);
  if (lookup_result && lookup_result->index == 0) {
    report(decl.location, "redeclaration of '" + decl.id + "\'.");
    return false;
  }
  m_Scopes.front().emplace_back(&decl);
  return true;
}

bool is_leaf(const StructDecl *decl) {
  for (auto &&[type, id] : decl->members) {
    if (type.kind == Type::Kind::Custom)
      return false;
  }
  return true;
}

bool Sema::resolve_enum_decls(std::vector<std::unique_ptr<ResolvedDecl>> &resolved_decls, bool partial, const std::vector<std::unique_ptr<Decl>> &ast) {
  bool error = false;
  for (auto &&decl : ast) {
    if (const auto *enum_decl = dynamic_cast<const EnumDecl *>(decl.get())) {
      std::unique_ptr<ResolvedEnumDecl> resolved_enum_decl = resolve_enum_decl(*enum_decl);
      bool is_exported = decl->is_exported;
      bool insert_result = false;
      if (resolved_enum_decl)
        insert_result = is_exported ? insert_decl_to_global_scope(*resolved_enum_decl) : insert_decl_to_current_scope(*resolved_enum_decl);
      if (!insert_result) {
        error = true;
        continue;
      }
      resolved_decls.emplace_back(std::move(resolved_enum_decl));
    }
  }
  if (error && !partial)
    return false;
  return true;
}

size_t align_to(size_t offset, size_t alignment) { return (offset + alignment - 1) & ~(alignment - 1); }

void Sema::init_type_info(ResolvedStructDecl &decl) {
  TypeInfo type_info{};
  type_info.field_sizes.reserve(decl.members.size());
  type_info.field_names.reserve(decl.members.size());
  size_t max_align = 0;
  for (auto &&field : decl.members) {
    const auto &ti = m_TypeInfos[field.first.pointer_depth ? "*" : field.first.name];
    type_info.field_sizes.push_back(ti.total_size);
    type_info.field_names.push_back(field.second);
    type_info.total_size = align_to(type_info.total_size, ti.alignment);
    type_info.total_size += ti.total_size;
    max_align = std::max(max_align, ti.alignment);
  }
  type_info.total_size = align_to(type_info.total_size, max_align);
  type_info.alignment = max_align;
  m_TypeInfos.insert({decl.type.name, std::move(type_info)});
}

bool Sema::resolve_struct_decls(std::vector<std::unique_ptr<ResolvedDecl>> &resolved_decls, bool partial, const std::vector<std::unique_ptr<Decl>> &ast) {
  struct DeclToInspect {
    const StructDecl *decl{nullptr};
    bool resolved{false};
  };
  std::vector<DeclToInspect> non_leaf_struct_decls{};
  non_leaf_struct_decls.reserve(ast.size());
  bool error = false;
  for (const std::unique_ptr<Decl> &decl : ast) {
    if (const auto *struct_decl = dynamic_cast<const StructDecl *>(decl.get())) {
      if (is_leaf(struct_decl)) {
        std::unique_ptr<ResolvedStructDecl> resolved_struct_decl = resolve_struct_decl(*struct_decl);
        init_type_info(*resolved_struct_decl);
        bool insert_result = false;
        if (resolved_struct_decl) {
          bool is_exported = resolved_struct_decl->is_exported;
          insert_result = is_exported ? insert_decl_to_global_scope(*resolved_struct_decl) : insert_decl_to_current_scope(*resolved_struct_decl);
        }
        if (!insert_result) {
          error = true;
          continue;
        }
        resolved_decls.emplace_back(std::move(resolved_struct_decl));
      } else
        non_leaf_struct_decls.push_back({struct_decl});
    }
  }
  if (error && !partial)
    return false;
  if (non_leaf_struct_decls.empty())
    return true;
  bool decl_resolved_last_pass = true;
  while (decl_resolved_last_pass) {
    decl_resolved_last_pass = false;
    for (auto &&[struct_decl, resolved] : non_leaf_struct_decls) {
      bool can_now_resolve = true;
      for (auto &&[type, id] : struct_decl->members) {
        std::optional<DeclLookupResult> lookup_result = lookup_decl(type.name, &type);
        if (type.kind == Type::Kind::Custom && (!lookup_result || !lookup_result->decl))
          can_now_resolve = false;
        break;
      }
      if (!can_now_resolve)
        continue;
      std::unique_ptr<ResolvedStructDecl> resolved_struct_decl = resolve_struct_decl(*struct_decl);
      bool insert_result = false;
      if (resolved_struct_decl) {
        bool is_exported = struct_decl->is_exported;
        insert_result = is_exported ? insert_decl_to_global_scope(*resolved_struct_decl) : insert_decl_to_current_scope(*resolved_struct_decl);
      }
      if (!insert_result) {
        error = true;
        continue;
      }
      resolved = true;
      init_type_info(*resolved_struct_decl);
      resolved_decls.emplace_back(std::move(resolved_struct_decl));
      decl_resolved_last_pass = true;
      continue;
    }
    for (auto it = non_leaf_struct_decls.begin(); it != non_leaf_struct_decls.end();) {
      if (it->resolved) {
        non_leaf_struct_decls.erase(it);
        --it;
      }
      ++it;
    }
  }
  for (auto &&[struct_decl, resolved] : non_leaf_struct_decls) {
    if (!resolved) {
      for (auto &&[type, id] : struct_decl->members) {
        std::optional<DeclLookupResult> lookup_result = lookup_decl(type.name, &type);
        if (!lookup_result)
          report(struct_decl->location, "could not resolve type '" + type.name + "'.");
      }
    }
  }
  if (error && !partial)
    return false;
  return true;
}

bool Sema::resolve_global_var_decls(std::vector<std::unique_ptr<ResolvedDecl>> &resolved_decls, bool partial, const std::vector<std::unique_ptr<Decl>> &ast) {
  bool error = false;
  for (const std::unique_ptr<Decl> &decl : ast) {
    if (const auto *var_decl = dynamic_cast<const VarDecl *>(decl.get())) {
      std::unique_ptr<ResolvedVarDecl> resolved_var_decl = resolve_var_decl(*var_decl);
      bool insert_result = false;
      if (resolved_var_decl) {
        bool is_exported = var_decl->is_exported;
        insert_result = is_exported ? insert_decl_to_global_scope(*resolved_var_decl) : insert_decl_to_current_scope(*resolved_var_decl);
      }
      if (!resolved_var_decl || (!resolved_var_decl->id.empty() && !insert_result)) {
        error = true;
        continue;
      }
      resolved_var_decl->is_global = true;
      resolved_decls.emplace_back(std::move(resolved_var_decl));
      continue;
    }
  }
  if (error && !partial)
    return false;
  return true;
}

std::vector<std::unique_ptr<ResolvedModule>> Sema::resolve_modules(bool partial) {
  std::vector<std::unique_ptr<ResolvedModule>> resolved_module_list{};
  resolved_module_list.reserve(m_Modules.size());
  for (auto &&_module : m_Modules) {
    m_ResolvedModules[_module->name] = std::move(resolve_module(*_module, partial));
  }
  for (auto &&[_, mod] : m_ResolvedModules) {
    resolved_module_list.push_back(std::move(mod));
  }
  return resolved_module_list;
}

std::unique_ptr<ResolvedModule> Sema::resolve_module(const Module &_module, bool partial) {
  if (m_ResolvedModules.count(_module.name)) {
    return std::move(m_ResolvedModules[_module.name]);
  }
  Scope global_scope{this};
  for (auto &&dep : _module.imports) {
    auto it = std::find_if(m_Modules.begin(), m_Modules.end(), [&](auto &&mod) { return mod->name == dep; });
    // We're assuming parser will notify the user and handle the error
    assert(it != m_Modules.end());
    std::unique_ptr<ResolvedModule> resolved_dep = resolve_module(**it, partial);
    if (!resolved_dep)
      return nullptr;
    m_ResolvedModules[dep] = std::move(resolved_dep);
  }
  for (auto &&dep : _module.imports) {
    const ResolvedModule &mod = *m_ResolvedModules[dep];
    for (auto &&decl : mod.declarations) {
      insert_decl_to_global_scope(*decl);
    }
  }
  std::vector<std::unique_ptr<ResolvedDecl>> module_ast = resolve_ast(partial, _module);
  if (!module_ast.size())
    return nullptr;
  return std::make_unique<ResolvedModule>(_module.name, _module.path, std::move(module_ast));
}

std::vector<std::unique_ptr<ResolvedDecl>> Sema::resolve_ast(bool partial, const Module &mod) {
  std::vector<std::unique_ptr<ResolvedDecl>> resolved_decls{};
  Scope module_scope(this);
  // Insert all global scope stuff, e.g. from other modules
  bool error = false;
  if (!resolve_enum_decls(resolved_decls, partial, mod.declarations))
    return {};
  if (!resolve_struct_decls(resolved_decls, partial, mod.declarations))
    return {};
  if (!resolve_global_var_decls(resolved_decls, partial, mod.declarations))
    return {};
  std::unordered_map<std::string, std::unique_ptr<ResolvedFuncDecl>> resolved_functions;
  for (const std::unique_ptr<Decl> &decl : mod.declarations) {
    if (const auto *fn = dynamic_cast<const FunctionDecl *>(decl.get())) {
      auto resolved_fn_decl = resolve_func_decl(*fn);
      bool insert_result = false;
      if (resolved_fn_decl) {
        bool is_exported = fn->is_exported;
        insert_result = is_exported ? insert_decl_to_global_scope(*resolved_fn_decl) : insert_decl_to_current_scope(*resolved_fn_decl);
      }
      if (!insert_result) {
        error = true;
        continue;
      }
      resolved_decls.emplace_back(std::move(resolved_fn_decl));
      if (error && !partial)
        return {};
    }
  }
  for (int i = 0; i < resolved_decls.size(); ++i) {
    Scope fn_scope{this};
    if (auto *fn = dynamic_cast<const FunctionDecl *>(mod.declarations[i].get())) {
      ResolvedDecl *resolved_decl = nullptr;
      for (auto &&decl : resolved_decls) {
        if (mod.declarations[i]->id == decl->id) {
          resolved_decl = decl.get();
          if (!dynamic_cast<ResolvedFuncDecl *>(resolved_decl))
            return {};
          break;
        }
      }
      if (resolved_decl) {
        m_CurrFunction = dynamic_cast<ResolvedFuncDecl *>(resolved_decl);
        for (auto &&param : m_CurrFunction->params) {
          insert_decl_to_current_scope(*param);
        }
        if (fn->body) {
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
    }
  }
  if (error && !partial)
    return {};
  return resolved_decls;
}
std::vector<std::unique_ptr<ResolvedDecl>> Sema::resolve_ast(bool partial) {
  std::vector<std::unique_ptr<ResolvedDecl>> resolved_decls{};
  Scope global_scope(this);
  // Insert all global scope stuff, e.g. from other modules
  bool error = false;
  if (!resolve_enum_decls(resolved_decls, partial, m_AST))
    return {};
  if (!resolve_struct_decls(resolved_decls, partial, m_AST))
    return {};
  if (!resolve_global_var_decls(resolved_decls, partial, m_AST))
    return {};
  std::unordered_map<std::string, std::unique_ptr<ResolvedFuncDecl>> resolved_functions;
  for (std::unique_ptr<Decl> &decl : m_AST) {
    if (const auto *fn = dynamic_cast<const FunctionDecl *>(decl.get())) {
      auto resolved_fn_decl = resolve_func_decl(*fn);
      if (!resolved_fn_decl || !insert_decl_to_current_scope(*resolved_fn_decl)) {
        error = true;
        continue;
      }
      resolved_decls.emplace_back(std::move(resolved_fn_decl));
      if (error && !partial)
        return {};
    }
  }
  for (int i = 0; i < resolved_decls.size(); ++i) {
    Scope fn_scope{this};
    if (auto *fn = dynamic_cast<const FunctionDecl *>(m_AST[i].get())) {
      ResolvedDecl *resolved_decl = nullptr;
      for (auto &&decl : resolved_decls) {
        if (m_AST[i]->id == decl->id) {
          resolved_decl = decl.get();
          if (!dynamic_cast<ResolvedFuncDecl *>(resolved_decl))
            return {};
          break;
        }
      }
      if (resolved_decl) {
        m_CurrFunction = dynamic_cast<ResolvedFuncDecl *>(resolved_decl);
        for (auto &&param : m_CurrFunction->params) {
          insert_decl_to_current_scope(*param);
        }
        if (fn->body) {
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
    }
  }
  if (error && !partial)
    return {};
  return resolved_decls;
}

std::optional<Type> Sema::resolve_type(Type parsed_type) {
  if (parsed_type.kind == Type::Kind::Custom) {
    auto decl = lookup_decl(parsed_type.name, &parsed_type);
    if (!decl)
      return std::nullopt;
    if (const auto *enum_decl = dynamic_cast<const ResolvedEnumDecl *>(decl->decl))
      return enum_decl->type;
    return parsed_type;
  }
  return parsed_type;
}

std::unique_ptr<ResolvedFuncDecl> Sema::resolve_func_decl(const FunctionDecl &func) {
  auto type = resolve_type(func.type);
  if (!type) {
    return report(func.location, "function '" + func.id + "' has invalid '" + func.type.name + "' type");
  }
  std::vector<std::unique_ptr<ResolvedParamDecl>> resolved_params{};
  Scope param_scope{this};
  int param_index{0};
  for (auto &&param : func.params) {
    auto resolved_param = resolve_param_decl(*param, param_index, func.id);
    if (!resolved_param || !insert_decl_to_current_scope(*resolved_param))
      return nullptr;
    resolved_params.emplace_back(std::move(resolved_param));
    ++param_index;
  }
  return std::make_unique<ResolvedFuncDecl>(func.location, func.id, *type, func.module, std::move(resolved_params), nullptr, func.is_vla, func.lib,
                                            func.og_name);
}

std::unique_ptr<ResolvedParamDecl> Sema::resolve_param_decl(const ParamDecl &decl, int index, const std::string function_name) {
  auto type = resolve_type(decl.type);
  std::string id = decl.id;
  if (id.empty()) {
    id = "__param_" + function_name + std::to_string(index);
  }
  if (!type || (type->kind == Type::Kind::Void && type->pointer_depth == 0)) {
    return report(decl.location, "parameter '" + decl.id + "' has invalid '" + decl.type.name + "' type");
  }
  return std::make_unique<ResolvedParamDecl>(decl.location, std::move(id), std::move(*type), decl.is_const);
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
  return std::make_unique<ResolvedBlock>(block.location, std::move(resolved_stmts));
}

std::unique_ptr<ResolvedStmt> Sema::resolve_stmt(const Stmt &stmt) {
  if (auto *expr = dynamic_cast<const Expr *>(&stmt))
    return resolve_expr(*expr);
  if (auto *return_stmt = dynamic_cast<const ReturnStmt *>(&stmt))
    return resolve_return_stmt(*return_stmt);
  if (auto *if_stmt = dynamic_cast<const IfStmt *>(&stmt))
    return resolve_if_stmt(*if_stmt);
  if (auto *defer_stmt = dynamic_cast<const DeferStmt *>(&stmt))
    return resolve_defer_stmt(*defer_stmt);
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

std::unique_ptr<ResolvedNumberLiteral> Sema::resolve_enum_access(const EnumElementAccess &access) {
  auto maybe_decl = lookup_decl(access.enum_id);
  if (!maybe_decl)
    return report(access.location, "undeclared type " + access.enum_id);
  const auto *decl = dynamic_cast<const ResolvedEnumDecl *>(maybe_decl->decl);
  if (!decl)
    return report(access.location, "unknown enum type " + access.enum_id + ".");
  if (!decl->name_values_map.count(access.member_id))
    return report(access.location, "unknown enum field " + access.enum_id + "::" + access.member_id + ".");
  Value value;
  long lookup_value = decl->name_values_map.at(access.member_id);
  switch (decl->type.kind) {
  case Type::Kind::u8:
    value.u8 = lookup_value;
    break;
  case Type::Kind::u16:
    value.u16 = lookup_value;
    break;
  case Type::Kind::u32:
    value.u32 = lookup_value;
    break;
  case Type::Kind::u64:
    value.u64 = lookup_value;
    break;
  case Type::Kind::i8:
    value.i8 = lookup_value;
    break;
  case Type::Kind::i16:
    value.i16 = lookup_value;
    break;
  case Type::Kind::i32:
    value.i32 = lookup_value;
    break;
  case Type::Kind::i64:
    value.i64 = lookup_value;
    break;
  default:
    return report(access.location, "invalid enum underlying type.");
  }
  return std::make_unique<ResolvedNumberLiteral>(access.location, decl->type, value);
}

std::unique_ptr<ResolvedDeclStmt> Sema::resolve_decl_stmt(const DeclStmt &stmt) {
  std::unique_ptr<ResolvedVarDecl> var_decl = resolve_var_decl(*stmt.var_decl);
  if (!var_decl)
    return nullptr;
  bool is_exported = stmt.var_decl->is_exported;
  bool insert_result = is_exported ? insert_decl_to_global_scope(*var_decl) : insert_decl_to_current_scope(*var_decl);
  if (!insert_result)
    return nullptr;
  return std::make_unique<ResolvedDeclStmt>(stmt.location, std::move(var_decl));
}

std::unique_ptr<ResolvedVarDecl> Sema::resolve_var_decl(const VarDecl &decl) {
  std::optional<Type> type = resolve_type(decl.type);
  if (!type || (type->kind == Type::Kind::Void && type->pointer_depth == 0))
    return report(decl.location, "variable '" + decl.id + "' has invalid '" + decl.type.name + "' type.");
  std::unique_ptr<ResolvedExpr> resolved_initializer = nullptr;
  if (decl.initializer) {
    resolved_initializer = resolve_expr(*decl.initializer, &(*type));
    if (!resolved_initializer)
      return nullptr;
    if (!is_same_type(resolved_initializer->type, *type)) {
      bool is_array_decay;
      if (!try_cast_expr(*resolved_initializer, *type, m_Cee, is_array_decay))
        return report(resolved_initializer->location, "initializer type mismatch.");
    }
    resolved_initializer->set_constant_value(m_Cee.evaluate(*resolved_initializer));
  }
  return std::make_unique<ResolvedVarDecl>(decl.location, decl.id, *type, decl.module, std::move(resolved_initializer), decl.is_const);
}

std::unique_ptr<ResolvedStructDecl> Sema::resolve_struct_decl(const StructDecl &decl) {
  std::vector<std::pair<Type, std::string>> types;
  for (auto &&[type, id] : decl.members) {
    std::optional<Type> resolved_type = resolve_type(type);
    if (!resolved_type)
      return nullptr;
    types.emplace_back(std::make_pair(std::move(*resolved_type), std::move(id)));
  }
  return std::make_unique<ResolvedStructDecl>(decl.location, decl.id, Type::custom(decl.id, false), decl.module, std::move(types));
}

std::unique_ptr<ResolvedEnumDecl> Sema::resolve_enum_decl(const EnumDecl &decl) {
  return std::make_unique<ResolvedEnumDecl>(decl.location, decl.id, decl.underlying_type, decl.module, decl.name_values_map);
}

std::unique_ptr<ResolvedGroupingExpr> Sema::resolve_grouping_expr(const GroupingExpr &group) {
  auto resolved_expr = resolve_expr(*group.expr);
  if (!resolved_expr)
    return nullptr;
  return std::make_unique<ResolvedGroupingExpr>(group.location, std::move(resolved_expr));
}

bool is_comp_op(TokenKind op) {
  if (op == TokenKind::LessThan || op == TokenKind::LessThanOrEqual || op == TokenKind::GreaterThan || op == TokenKind::GreaterThanOrEqual ||
      op == TokenKind::ExclamationEqual || op == TokenKind::EqualEqual)
    return true;
  return false;
}

bool is_bitwise_op(TokenKind op) {
  switch (op) {
  case TokenKind::BitwiseShiftR:
  case TokenKind::BitwiseShiftL:
  case TokenKind::Hat:
  case TokenKind::Amp:
  case TokenKind::Pipe:
    return true;
  default:
    return false;
  }
}

std::string get_type_string(const Type &type) {
  std::string type_string = type.name;
  for (int i = 0; i < type.pointer_depth; ++i) {
    type_string += "*";
  }
  return type_string;
}

std::unique_ptr<ResolvedExpr> Sema::resolve_binary_operator(const BinaryOperator &op) {
  auto resolved_lhs = resolve_expr(*op.lhs);
  assert(resolved_lhs);
  Type *rhs_type = nullptr;
  if (const auto *nullexpr = dynamic_cast<const NullExpr *>(op.rhs.get())) {
    rhs_type = &resolved_lhs->type;
  }
  auto resolved_rhs = resolve_expr(*op.rhs, rhs_type);
  if (!resolved_lhs || !resolved_rhs)
    return nullptr;
  if (!is_comp_op(op.op)) {
    if (const auto *lhs = dynamic_cast<const ResolvedDeclRefExpr *>(resolved_lhs.get())) {
      if (const auto *rhs = dynamic_cast<const ResolvedNumberLiteral *>(resolved_rhs.get())) {
        bool is_array_decay;
        if (!try_cast_expr(*resolved_rhs, lhs->type, m_Cee, is_array_decay)) {
          return report(resolved_lhs->location, "cannot implicitly cast rhs to lhs - from type '" + get_type_string(resolved_rhs->type) + "' to type '" +
                                                    get_type_string(resolved_lhs->type) + "'.");
        }
      }
    }
  }
  if (is_comp_op(op.op) && !is_same_type(resolved_lhs->type, resolved_rhs->type)) {
    bool is_array_decay;
    if (!try_cast_expr(*resolved_rhs, resolved_lhs->type, m_Cee, is_array_decay))
      return report(resolved_lhs->location, "cannot implicitly cast rhs to lhs - from type '" + get_type_string(resolved_rhs->type) + "' to type '" +
                                                get_type_string(resolved_lhs->type) + "'.");
  }
  if (is_bitwise_op(op.op) || op.op == TokenKind::Percent) {
    if (const auto *rhs = dynamic_cast<const ResolvedDeclRefExpr *>(resolved_rhs.get())) {
      if (const auto *lhs = dynamic_cast<const ResolvedNumberLiteral *>(resolved_lhs.get())) {
        bool is_array_decay;
        if (!try_cast_expr(*resolved_lhs, rhs->type, m_Cee, is_array_decay)) {
          return report(resolved_lhs->location, "cannot implicitly cast rhs to lhs - from type '" + get_type_string(resolved_rhs->type) + "' to type '" +
                                                    get_type_string(resolved_lhs->type) + "'.");
        }
      }
    }
    if ((op.op == TokenKind::BitwiseShiftL || op.op == TokenKind::BitwiseShiftR) && resolved_rhs->type.kind < Type::Kind::INTEGERS_START &&
        resolved_rhs->type.kind > Type::Kind::INTEGERS_END)
      return report(resolved_rhs->location, "bitshift operator's right hand side can only be an integer.");
  }
  if (const auto *dre = dynamic_cast<const ResolvedDeclRefExpr *>(resolved_lhs.get())) {
    if (dre->type.pointer_depth > 0 && (op.op == TokenKind::Plus || op.op == TokenKind::Minus)) {
      std::vector<std::unique_ptr<ResolvedExpr>> indices{};
      SourceLocation loc = resolved_rhs->location;
      indices.push_back(std::move(resolved_rhs));
      return resolve_array_element_access_no_deref(loc, std::move(indices), dre->decl);
    }
  }
  return std::make_unique<ResolvedBinaryOperator>(op.location, std::move(resolved_lhs), std::move(resolved_rhs), op.op);
}

std::unique_ptr<ResolvedUnaryOperator> Sema::resolve_unary_operator(const UnaryOperator &op, Type *type) {
  auto resolved_rhs = resolve_expr(*op.rhs, type);
  if (!resolved_rhs)
    return nullptr;
  if (resolved_rhs->type.kind == Type::Kind::Void && resolved_rhs->type.pointer_depth == 0) {
    if (type) {
      if (type->kind != Type::Kind::FnPtr) {
        return report(resolved_rhs->location, "void expression cannot be used as operand to unary operator.");
      }
      auto &fn_ptr_ret_type = type->fn_ptr_signature->first.front();
      if (resolved_rhs->type.fn_ptr_signature == fn_ptr_ret_type.fn_ptr_signature && resolved_rhs->type.kind == fn_ptr_ret_type.kind &&
          resolved_rhs->type.pointer_depth == fn_ptr_ret_type.pointer_depth) {
        resolved_rhs->type = *type;
      }
    }
  }
  if (op.op == TokenKind::Amp) {
    if (const ResolvedNumberLiteral *rvalue = dynamic_cast<const ResolvedNumberLiteral *>(resolved_rhs.get())) {
      return report(resolved_rhs->location, "cannot take the address of an rvalue.");
    } else if (const ResolvedDeclRefExpr *decl_ref_expr = dynamic_cast<const ResolvedDeclRefExpr *>(resolved_rhs.get())) {
      if (const ResolvedFuncDecl *fn = dynamic_cast<const ResolvedFuncDecl *>(decl_ref_expr->decl)) {
        std::vector<Type> fn_sig;
        fn_sig.reserve(fn->params.size() + 1);
        fn_sig.push_back(fn->type);
        for (auto &&param : fn->params) {
          fn_sig.push_back(param->type);
        }
        resolved_rhs->type.fn_ptr_signature = std::make_pair(std::move(fn_sig), fn->is_vla);
      } else {
        ++resolved_rhs->type.pointer_depth;
      }
    } else {
      ++resolved_rhs->type.pointer_depth;
    }
  } else if (op.op == TokenKind::Asterisk) {
    if (resolved_rhs->type.pointer_depth < 1)
      return report(resolved_rhs->location, "cannot dereference non-pointer type.");
    if (const ResolvedNumberLiteral *rvalue = dynamic_cast<const ResolvedNumberLiteral *>(resolved_rhs.get())) {
      return report(resolved_rhs->location, "cannot derefenence an rvalue.");
    }
    ++resolved_rhs->type.dereference_counts;
  }
  return std::make_unique<ResolvedUnaryOperator>(op.location, std::move(resolved_rhs), op.op);
}

std::unique_ptr<ResolvedExplicitCastExpr> Sema::resolve_explicit_cast(const ExplicitCast &cast) {
  std::optional<Type> lhs_type = resolve_type(cast.type);
  if (!lhs_type)
    return nullptr;
  std::unique_ptr<ResolvedExpr> rhs = resolve_expr(*cast.rhs);
  if (!rhs)
    return report(cast.rhs->location, "cannot cast expression.");
  /* enum class CastType {  Extend, Truncate,  IntToFloat}; */
  ResolvedExplicitCastExpr::CastType cast_type = ResolvedExplicitCastExpr::CastType::Nop;
  if (lhs_type->kind == Type::Kind::Custom && rhs->type.kind == Type::Kind::Custom) {
    if (lhs_type->pointer_depth < 1)
      return report(cast.location, "cannot cast custom types, must cast custom type pointers.");
    if (lhs_type->pointer_depth != rhs->type.pointer_depth)
      return report(cast.location, "pointer depths must me equal.");
    cast_type = ResolvedExplicitCastExpr::CastType::Ptr;
  } else if (lhs_type->pointer_depth > 0) {
    if ((rhs->type.kind > Type::Kind::INTEGERS_END || rhs->type.kind < Type::Kind::INTEGERS_START) && !rhs->type.pointer_depth)
      return report(cast.location, "cannot cast operand of type " + rhs->type.name + " to pointer type.");
    if (rhs->type.kind <= Type::Kind::INTEGERS_END && rhs->type.kind >= Type::Kind::INTEGERS_START && !rhs->type.pointer_depth)
      cast_type = ResolvedExplicitCastExpr::CastType::IntToPtr;
    if (rhs->type.pointer_depth == lhs_type->pointer_depth)
      cast_type = ResolvedExplicitCastExpr::CastType::Ptr;
  } else if (!lhs_type->pointer_depth) {
    if (rhs->type.kind == Type::Kind::Custom) {
      if (!rhs->type.pointer_depth)
        return report(cast.location, "cannot cast custom type non-pointer to integer.");
      if (lhs_type->kind > Type::Kind::INTEGERS_END || lhs_type->kind < Type::Kind::INTEGERS_START)
        return report(cast.location, "cannot cast operand of type " + rhs->type.name + " where arithmetic or pointer type is required.");
      cast_type = ResolvedExplicitCastExpr::CastType::PtrToInt;
    } else if (rhs->type.kind >= Type::Kind::FLOATS_START && rhs->type.kind <= Type::Kind::FLOATS_END) {
      if (lhs_type->kind >= Type::Kind::INTEGERS_START && lhs_type->kind <= Type::Kind::INTEGERS_END)
        cast_type = ResolvedExplicitCastExpr::CastType::FloatToInt;
      if (lhs_type->kind >= Type::Kind::FLOATS_START && lhs_type->kind <= Type::Kind::FLOATS_END) {
        if (get_type_size(lhs_type->kind) > get_type_size(rhs->type.kind))
          cast_type = ResolvedExplicitCastExpr::CastType::Extend;
        else if (get_type_size(lhs_type->kind) < get_type_size(rhs->type.kind))
          cast_type = ResolvedExplicitCastExpr::CastType::Truncate;
      }
    } else if (rhs->type.kind >= Type::Kind::INTEGERS_START && rhs->type.kind <= Type::Kind::INTEGERS_END) {
      if (lhs_type->kind >= Type::Kind::FLOATS_START && lhs_type->kind <= Type::Kind::FLOATS_END)
        cast_type = ResolvedExplicitCastExpr::CastType::IntToFloat;
      if (lhs_type->kind >= Type::Kind::INTEGERS_START && lhs_type->kind <= Type::Kind::INTEGERS_END) {
        if (get_type_size(lhs_type->kind) > get_type_size(rhs->type.kind))
          cast_type = ResolvedExplicitCastExpr::CastType::Extend;
        else if (get_type_size(lhs_type->kind) < get_type_size(rhs->type.kind))
          cast_type = ResolvedExplicitCastExpr::CastType::Truncate;
      }
    }
  }
  return std::make_unique<ResolvedExplicitCastExpr>(cast.location, *lhs_type, cast_type, std::move(rhs));
}

std::unique_ptr<ResolvedWhileStmt> Sema::resolve_while_stmt(const WhileStmt &stmt) {
  std::unique_ptr<ResolvedExpr> condition = resolve_expr(*stmt.condition);
  if (!condition)
    return nullptr;
  if (condition->type.kind != Type::Kind::Bool) {
    bool is_array_decay;
    if (!try_cast_expr(*condition, Type::builtin_bool(false), m_Cee, is_array_decay))
      return report(condition->location, "condition is expected to evaluate to bool.");
  }
  std::unique_ptr<ResolvedBlock> body = resolve_block(*stmt.body);
  if (!body)
    return nullptr;
  condition->set_constant_value(m_Cee.evaluate(*condition));
  return std::make_unique<ResolvedWhileStmt>(stmt.location, std::move(condition), std::move(body));
}

std::unique_ptr<ResolvedForStmt> Sema::resolve_for_stmt(const ForStmt &stmt) {
  std::unique_ptr<ResolvedDeclStmt> counter_variable = resolve_decl_stmt(*stmt.counter_variable);
  if (!counter_variable)
    return nullptr;
  std::unique_ptr<ResolvedExpr> condition = resolve_expr(*stmt.condition);
  if (!condition)
    return nullptr;
  condition->set_constant_value(m_Cee.evaluate(*condition));
  std::unique_ptr<ResolvedStmt> increment_expr = resolve_stmt(*stmt.increment_expr);
  if (!increment_expr)
    return nullptr;
  std::unique_ptr<ResolvedBlock> body = resolve_block(*stmt.body);
  if (!body)
    return nullptr;
  return std::make_unique<ResolvedForStmt>(stmt.location, std::move(counter_variable), std::move(condition), std::move(increment_expr), std::move(body));
}

bool Sema::flow_sensitive_analysis(const ResolvedFuncDecl &fn) {
  CFG cfg = CFGBuilder().build(fn);
  bool error = false;
  error |= check_return_on_all_paths(fn, cfg);
  return error;
}

bool Sema::check_return_on_all_paths(const ResolvedFuncDecl &fn, const CFG &cfg) {
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
    report(fn.location, return_count > 0 ? "non-void function does not have a return on every path." : "non-void function does not have a return value.");
  }
  return exit_reached || return_count == 0;
}

std::unique_ptr<ResolvedReturnStmt> Sema::resolve_return_stmt(const ReturnStmt &stmt) {
  assert(m_CurrFunction && "return statement outside of function.");
  if (m_CurrFunction->type.kind == Type::Kind::Void && stmt.expr)
    return report(stmt.location, "unexpected return value in void function.");
  if (m_CurrFunction->type.kind != Type::Kind::Void && !stmt.expr)
    return report(stmt.location, "expected return value.");
  std::unique_ptr<ResolvedExpr> resolved_expr;
  if (stmt.expr) {
    resolved_expr = resolve_expr(*stmt.expr, &m_CurrFunction->type);
    if (!resolved_expr)
      return nullptr;
    if (!is_same_type(m_CurrFunction->type, resolved_expr->type)) {
      bool is_array_decay;
      if (!try_cast_expr(*resolved_expr, m_CurrFunction->type, m_Cee, is_array_decay)) {
        return report(resolved_expr->location, "unexpected return type.");
      }
    }
    resolved_expr->set_constant_value(m_Cee.evaluate(*resolved_expr));
  }
  return std::make_unique<ResolvedReturnStmt>(stmt.location, std::move(resolved_expr));
}

std::unique_ptr<ResolvedExpr> Sema::resolve_expr(const Expr &expr, Type *type) {
  if (const auto *number = dynamic_cast<const NumberLiteral *>(&expr))
    return std::make_unique<ResolvedNumberLiteral>(number->location, number->type, number->value);
  if (const auto *enum_access = dynamic_cast<const EnumElementAccess *>(&expr))
    return resolve_enum_access(*enum_access);
  if (const auto *decl_ref_expr = dynamic_cast<const DeclRefExpr *>(&expr))
    return resolve_decl_ref_expr(*decl_ref_expr, type);
  if (const auto *call_expr = dynamic_cast<const CallExpr *>(&expr))
    return resolve_call_expr(*call_expr);
  if (const auto *group_expr = dynamic_cast<const GroupingExpr *>(&expr))
    return resolve_grouping_expr(*group_expr);
  if (const auto *binary_op = dynamic_cast<const BinaryOperator *>(&expr))
    return resolve_binary_operator(*binary_op);
  if (const auto *unary_op = dynamic_cast<const UnaryOperator *>(&expr))
    return resolve_unary_operator(*unary_op, type);
  if (const auto *explicit_cast = dynamic_cast<const ExplicitCast *>(&expr))
    return resolve_explicit_cast(*explicit_cast);
  if (const auto *string_lit = dynamic_cast<const StringLiteralExpr *>(&expr))
    return resolve_string_literal_expr(*string_lit);
  if (const auto *sizeof_expr = dynamic_cast<const SizeofExpr *>(&expr)) {
    if (sizeof_expr->is_ptr) {
      Value value;
      value.u64 = m_TypeInfos["*"].total_size * sizeof_expr->array_element_count;
      return std::make_unique<ResolvedNumberLiteral>(sizeof_expr->location, Type::builtin_u64(0), value);
    } else if (m_TypeInfos.count(sizeof_expr->type_name)) {
      Value value;
      value.u64 = m_TypeInfos[sizeof_expr->type_name].total_size * sizeof_expr->array_element_count;
      return std::make_unique<ResolvedNumberLiteral>(sizeof_expr->location, Type::builtin_u64(0), value);
    } else {
      return report(sizeof_expr->location, "unknown type " + sizeof_expr->type_name + ".");
    }
  }
  if (const auto *alignof_expr = dynamic_cast<const AlignofExpr *>(&expr)) {
    if (alignof_expr->is_ptr) {
      Value value;
      value.u64 = m_TypeInfos["*"].alignment;
      return std::make_unique<ResolvedNumberLiteral>(alignof_expr->location, Type::builtin_u64(0), value);
    } else if (m_TypeInfos.count(alignof_expr->type_name)) {
      Value value;
      value.u64 = m_TypeInfos[alignof_expr->type_name].alignment;
      return std::make_unique<ResolvedNumberLiteral>(alignof_expr->location, Type::builtin_u64(0), value);
    } else {
      return report(alignof_expr->location, "unknown type " + alignof_expr->type_name + ".");
    }
  }
  if (type) {
    if (const auto *struct_literal = dynamic_cast<const StructLiteralExpr *>(&expr))
      return resolve_struct_literal_expr(*struct_literal, *type);
    if (const auto *array_literal = dynamic_cast<const ArrayLiteralExpr *>(&expr))
      return resolve_array_literal_expr(*array_literal, *type);
    if (const auto *nullexpr = dynamic_cast<const NullExpr *>(&expr)) {
      return std::make_unique<ResolvedNullExpr>(nullexpr->location, *type);
    }
  }
  assert(false && "unexpected expression.");
  return nullptr;
}

std::unique_ptr<InnerMemberAccess> Sema::resolve_inner_member_access(const MemberAccess &access, Type type) {
  std::optional<DeclLookupResult> lookup_res = lookup_decl(type.name, &type);
  if (!lookup_res)
    return nullptr;
  const ResolvedStructDecl *struct_decl = dynamic_cast<const ResolvedStructDecl *>(lookup_res->decl);
  if (!struct_decl)
    return report(access.location, lookup_res->decl->id + " is not a struct type.");
  int inner_member_index = 0;
  for (auto &&struct_member : struct_decl->members) {
    // compare field names
    if (struct_member.second == access.field) {
      std::optional<FnPtrCallParams> fn_ptr_call_params;
      if (access.params) {
        FnPtrCallParams tmp_fn_ptr_call_params;
        tmp_fn_ptr_call_params.reserve(access.params->size());
        for (auto &&param : *access.params) {
          auto expr = resolve_expr(*param);
          if (!expr)
            return nullptr;
          tmp_fn_ptr_call_params.emplace_back(std::move(expr));
        }
        fn_ptr_call_params = std::move(tmp_fn_ptr_call_params);
      }
      std::unique_ptr<InnerMemberAccess> inner_member_access =
          std::make_unique<InnerMemberAccess>(inner_member_index, struct_member.second, struct_member.first, nullptr, std::move(fn_ptr_call_params));
      if (access.inner_decl_ref_expr) {
        if (struct_member.first.kind != Type::Kind::Custom) {
          return report(access.inner_decl_ref_expr->location, struct_member.first.name + " is not a struct type.");
        }
        if (const auto *inner_access_parser = dynamic_cast<const MemberAccess *>(access.inner_decl_ref_expr.get())) {
          Type struct_member_type = struct_member.first;
          if (struct_member.first.fn_ptr_signature) {
            struct_member_type = struct_member.first.fn_ptr_signature->first.front();
          }
          inner_member_access->inner_member_access = std::move(resolve_inner_member_access(*inner_access_parser, struct_member_type));
        }
      }
      return std::move(inner_member_access);
    }
    ++inner_member_index;
  }
  return nullptr;
}

std::unique_ptr<ResolvedStructMemberAccess> Sema::resolve_member_access(const MemberAccess &access, const ResolvedDecl *decl) {
  if (!decl)
    return nullptr;
  std::optional<Type> type = resolve_type(decl->type);
  if (!type)
    return nullptr;
  if (type->kind != Type::Kind::Custom)
    return report(access.location, type->name + " is not a struct type.");
  std::optional<DeclLookupResult> lookup_res = lookup_decl(type->name, &(*type));
  if (!lookup_res)
    return nullptr;
  const ResolvedStructDecl *struct_decl = dynamic_cast<const ResolvedStructDecl *>(lookup_res->decl);
  if (!struct_decl)
    return report(access.location, lookup_res->decl->id + " is not a struct type.");
  const ResolvedDecl *struct_or_param_decl = dynamic_cast<const ResolvedVarDecl *>(decl);
  if (!struct_or_param_decl) {
    struct_or_param_decl = dynamic_cast<const ResolvedParamDecl *>(decl);
    if (!struct_or_param_decl)
      return report(access.location, "unknown variable '" + decl->id + "'.");
  }
  int decl_member_index = 0;
  for (auto &&struct_member : struct_decl->members) {
    // compare field names
    if (struct_member.second == access.field) {
      std::optional<FnPtrCallParams> fn_ptr_call_params{std::nullopt};
      if (access.params) {
        FnPtrCallParams tmp_fn_ptr_call_params;
        tmp_fn_ptr_call_params.reserve(access.params->size());
        for (auto &&param : *access.params) {
          auto expr = resolve_expr(*param);
          if (!expr)
            return nullptr;
          tmp_fn_ptr_call_params.emplace_back(std::move(expr));
        }
        fn_ptr_call_params = std::move(tmp_fn_ptr_call_params);
      }
      std::unique_ptr<InnerMemberAccess> inner_member_access =
          std::make_unique<InnerMemberAccess>(decl_member_index, struct_member.second, struct_member.first, nullptr, std::nullopt);
      Type innermost_type = struct_member.first;
      if (access.inner_decl_ref_expr) {
        if (struct_member.first.kind != Type::Kind::Custom &&
            (struct_member.first.kind != Type::Kind::FnPtr ||
             (struct_member.first.fn_ptr_signature && struct_member.first.fn_ptr_signature->first[0].kind != Type::Kind::Custom))) {
          return report(access.inner_decl_ref_expr->location, struct_member.first.name + " is not a struct type.");
        }
        if (const auto *inner_access = dynamic_cast<const MemberAccess *>(access.inner_decl_ref_expr.get())) {
          Type struct_member_type = struct_member.first;
          if (struct_member.first.fn_ptr_signature) {
            struct_member_type = struct_member.first.fn_ptr_signature->first.front();
          }
          inner_member_access->inner_member_access = std::move(resolve_inner_member_access(*inner_access, struct_member_type));
          innermost_type = inner_member_access->inner_member_access->type;
        }
      }
      std::unique_ptr<ResolvedStructMemberAccess> member_access =
          std::make_unique<ResolvedStructMemberAccess>(access.location, struct_or_param_decl, std::move(inner_member_access), std::nullopt);
      member_access->params = std::move(fn_ptr_call_params);
      member_access->type = innermost_type;
      return std::move(member_access);
    }
    ++decl_member_index;
  }
  return report(access.location, "no member named '" + access.field + "' in struct type '" + struct_decl->id + "'.");
}

std::unique_ptr<ResolvedArrayElementAccess> Sema::resolve_array_element_access(const ArrayElementAccess &access, const ResolvedDecl *decl) {
  if (!decl->type.array_data && (decl->type.pointer_depth - decl->type.dereference_counts < 1))
    return report(access.location, "trying to access an array element of a variable that is not "
                                   "an array or pointer: " +
                                       decl->id + ".");
  std::vector<std::unique_ptr<ResolvedExpr>> indices{};
  uint deindex_count = 0;
  for (auto &&index : access.indices) {
    auto expr = resolve_expr(*index);
    if (!expr)
      return nullptr;
    const auto *decl_ref_expr = dynamic_cast<const ResolvedDeclRefExpr *>(expr.get());
    const auto *binop = dynamic_cast<const ResolvedBinaryOperator *>(expr.get());
    if (binop) {
      Type max_type = binop->lhs->type.kind > binop->rhs->type.kind ? binop->lhs->type : binop->rhs->type;
      bool is_decay;
      try_cast_expr(*binop->lhs, max_type, m_Cee, is_decay);
      try_cast_expr(*binop->rhs, max_type, m_Cee, is_decay);
    }
    if (!decl_ref_expr && !binop) {
      if (expr->type.kind != platform_ptr_type().kind) {
        bool is_decay;
        if (!try_cast_expr(*expr, platform_ptr_type(), m_Cee, is_decay))
          return report(expr->location, "cannot cast to address index type.");
      }
    }
    indices.emplace_back(std::move(expr));
    ++deindex_count;
    // @TODO: on constant value it's possible to do bounds check
    /* if(expr->get_constant_value()) { */
    /*     auto constant_val = expr->get_constant_value().value(); */
    /* } */
  }
  auto resolved_access = std::make_unique<ResolvedArrayElementAccess>(access.location, decl, std::move(indices));
  if ((resolved_access->type.array_data && resolved_access->type.array_data->dimension_count < deindex_count) &&
      resolved_access->type.pointer_depth - resolved_access->type.dereference_counts < deindex_count)
    return report(access.location, "more array accesses than there are dimensions.");
  de_array_type(resolved_access->type, deindex_count);
  return std::move(resolved_access);
}

std::unique_ptr<ResolvedArrayElementAccess> Sema::resolve_array_element_access_no_deref(SourceLocation loc, std::vector<std::unique_ptr<ResolvedExpr>> indices,
                                                                                        const ResolvedDecl *decl) {
  if (!decl->type.array_data && (decl->type.pointer_depth - decl->type.dereference_counts < 1))
    return report(loc, "trying to access an array element of a variable that is not "
                       "an array or pointer: " +
                           decl->id + ".");
  for (auto &&expr : indices) {
    const auto *decl_ref_expr = dynamic_cast<const ResolvedDeclRefExpr *>(expr.get());
    const auto *binop = dynamic_cast<const ResolvedBinaryOperator *>(expr.get());
    if (binop) {
      Type max_type = binop->lhs->type.kind > binop->rhs->type.kind ? binop->lhs->type : binop->rhs->type;
      bool is_decay;
      try_cast_expr(*binop->lhs, max_type, m_Cee, is_decay);
      try_cast_expr(*binop->rhs, max_type, m_Cee, is_decay);
    }
    if (!decl_ref_expr && !binop) {
      if (expr->type.kind != platform_ptr_type().kind) {
        bool is_decay;
        if (!try_cast_expr(*expr, platform_ptr_type(), m_Cee, is_decay))
          return report(expr->location, "cannot cast to address index type.");
      }
    }
  }
  return std::make_unique<ResolvedArrayElementAccess>(loc, decl, std::move(indices));
}

std::unique_ptr<ResolvedStructLiteralExpr> Sema::resolve_struct_literal_expr(const StructLiteralExpr &lit, Type struct_type) {
  std::optional<Type> type = resolve_type(struct_type);
  if (!type)
    return nullptr;
  if (type->pointer_depth > 0)
    return report(lit.location, "cannot initialize a pointer type struct "
                                "variable with a struct literal.");
  std::optional<DeclLookupResult> lookup_res = lookup_decl(type->name, &(*type));
  if (!lookup_res)
    return nullptr;
  const ResolvedStructDecl *struct_decl = dynamic_cast<const ResolvedStructDecl *>(lookup_res->decl);
  if (!struct_decl)
    return nullptr;
  int member_index = 0;
  std::vector<ResolvedFieldInitializer> resolved_field_initializers{};
  bool errors = false;
  for (auto &&field_init : lit.field_initializers) {
    std::optional<Type> inner_member_type = std::nullopt;
    if (!field_init.first.empty()) {
      int decl_member_index = 0;
      for (auto &&struct_member : struct_decl->members) {
        // compare field names
        if (struct_member.second == field_init.first) {
          member_index = decl_member_index;
          inner_member_type = struct_member.first;
          break;
        }
        ++decl_member_index;
      }
    } else {
      auto &decl_member = struct_decl->members[member_index];
      inner_member_type = decl_member.first;
    }
    std::unique_ptr<ResolvedExpr> expr;
    if (const auto *inner_struct_lit = dynamic_cast<const StructLiteralExpr *>(field_init.second.get())) {
      expr = resolve_struct_literal_expr(*inner_struct_lit, *inner_member_type);
    } else {
      expr = resolve_expr(*field_init.second, &(*inner_member_type));
    }
    if (!expr) {
      errors = true;
      ++member_index;
      continue;
    }
    expr->set_constant_value(m_Cee.evaluate(*expr));
    const Type &declared_member_type = struct_decl->members[member_index].first;
    if (!is_same_type(expr->type, declared_member_type)) {
      bool is_array_decay;
      if (!try_cast_expr(*expr, declared_member_type, m_Cee, is_array_decay)) {
        errors = true;
        report(expr->location, "cannot implicitly cast from type '" + expr->type.name + "' to type '" + declared_member_type.name + "'.");
        ++member_index;
        continue;
      }
    }
    auto it = resolved_field_initializers.begin() + member_index;
    resolved_field_initializers.emplace_back(std::make_pair(struct_decl->members[member_index].second, std::move(expr)));
    ++member_index;
  }
  // Sorting
  std::vector<ResolvedFieldInitializer> sorted_field_initializers{};
  for (int i = 0; i < struct_decl->members.size(); ++i) {
    bool found = false;
    auto &decl_member = struct_decl->members[i];
    for (auto &&init : resolved_field_initializers) {
      if (init.first == decl_member.second) {
        sorted_field_initializers.emplace_back(init.first, std::move(init.second));
        found = true;
        break;
      }
    }
    if (!found)
      sorted_field_initializers.emplace_back(decl_member.second, nullptr);
  }
  if (errors)
    return nullptr;
  return std::make_unique<ResolvedStructLiteralExpr>(lit.location, *type, std::move(sorted_field_initializers));
}

std::unique_ptr<ResolvedArrayLiteralExpr> Sema::resolve_array_literal_expr(const ArrayLiteralExpr &lit, Type array_type) {
  if (!array_type.array_data)
    return report(lit.location, "trying to initialize a non-array type with array literal.");
  std::vector<std::unique_ptr<ResolvedExpr>> expressions;
  for (auto &expr : lit.element_initializers) {
    Type type = array_type;
    de_array_type(type, 1);
    auto expression = resolve_expr(*expr, &type);
    if (!expression)
      return nullptr;
    if (expression->type.kind != array_type.kind) {
      bool is_decay;
      if (!try_cast_expr(*expression, type, m_Cee, is_decay))
        return report(expression->location, "cannot cast type.");
    }
    expression->set_constant_value(expression->get_constant_value());
    expressions.emplace_back(std::move(expression));
  }
  return std::make_unique<ResolvedArrayLiteralExpr>(lit.location, array_type, std::move(expressions));
}

std::unique_ptr<ResolvedStringLiteralExpr> Sema::resolve_string_literal_expr(const StringLiteralExpr &lit) {
  return std::make_unique<ResolvedStringLiteralExpr>(lit.location, lit.val);
}

std::unique_ptr<ResolvedDeclRefExpr> Sema::resolve_decl_ref_expr(const DeclRefExpr &decl_ref_expr, bool is_call, Type *type) {
  auto &&maybe_decl = lookup_decl(decl_ref_expr.id);
  if (!maybe_decl)
    return report(decl_ref_expr.location, "symbol '" + decl_ref_expr.id + "' undefined.");
  const ResolvedDecl *decl = maybe_decl->decl;
  if (!decl)
    return report(decl_ref_expr.location, "symbol '" + decl_ref_expr.id + "' undefined.");
  if (!is_call && (dynamic_cast<const ResolvedFuncDecl *>(decl) || (type && type->fn_ptr_signature)))
    return report(decl_ref_expr.location, "expected to call function '" + decl_ref_expr.id + "'.");
  if (const auto *member_access = dynamic_cast<const MemberAccess *>(&decl_ref_expr))
    return resolve_member_access(*member_access, decl);
  if (const auto *array_access = dynamic_cast<const ArrayElementAccess *>(&decl_ref_expr))
    return resolve_array_element_access(*array_access, decl);
  return std::make_unique<ResolvedDeclRefExpr>(decl_ref_expr.location, decl);
}

std::unique_ptr<ResolvedCallExpr> Sema::resolve_call_expr(const CallExpr &call) {
  auto &&resolved_callee = resolve_decl_ref_expr(*call.id, true);
  if (!resolved_callee)
    return nullptr;
  const auto *decl_ref_expr = dynamic_cast<const DeclRefExpr *>(call.id.get());
  if (!decl_ref_expr)
    return report(call.location, "expression cannot be called as a function.");
  // Normal function call
  std::vector<std::unique_ptr<ResolvedExpr>> resolved_args;
  if (const auto *resolved_func_decl = dynamic_cast<const ResolvedFuncDecl *>(resolved_callee->decl)) {
    if (call.args.size() != resolved_func_decl->params.size() && !resolved_func_decl->is_vla)
      return report(call.location, "argument count mismatch.");
    for (int i = 0; i < call.args.size(); ++i) {
      auto *decl_type = i < resolved_func_decl->params.size() ? &resolved_func_decl->params[i]->type : nullptr;
      std::unique_ptr<ResolvedExpr> resolved_arg = resolve_expr(*call.args[i], decl_type);
      if (!resolved_arg)
        return nullptr;
      Type resolved_type = resolved_arg->type;
      if (const auto *member_access = dynamic_cast<const ResolvedStructMemberAccess *>(resolved_arg.get())) {
        resolved_type = member_access->type;
      }
      if (i < resolved_func_decl->params.size()) {
        if (!is_same_type(resolved_type, resolved_func_decl->params[i]->type)) {
          bool is_array_decay;
          if (!try_cast_expr(*resolved_arg, resolved_func_decl->params[i]->type, m_Cee, is_array_decay) &&
              !is_same_array_decay(resolved_arg->type, resolved_func_decl->params[i]->type)) {
            std::string unexected_type_str = resolved_arg->type.name;
            for (int i = 0; i < resolved_arg->type.pointer_depth; ++i) {
              unexected_type_str += "*";
            }
            std::string expected_type_str = resolved_func_decl->params[i]->type.name;
            for (int i = 0; i < resolved_func_decl->params[i]->type.pointer_depth; ++i) {
              expected_type_str += "*";
            }
            return report(resolved_arg->location, "unexpected type '" + unexected_type_str + "', expected '" + expected_type_str + "'.");
          }
        }
      }
      resolved_arg->set_constant_value(m_Cee.evaluate(*resolved_arg));
      resolved_args.emplace_back(std::move(resolved_arg));
    }
    return std::make_unique<ResolvedCallExpr>(call.location, resolved_func_decl, std::move(resolved_args));
  } else { // could be function pointer
    if (!resolved_callee->type.fn_ptr_signature)
      return report(call.location, "calling non-function symbol.");
    if (call.args.size() != resolved_callee->type.fn_ptr_signature->first.size() - 1 && !resolved_func_decl->is_vla)
      return report(call.location, "argument count mismatch.");
    auto &fn_sig = resolved_callee->type.fn_ptr_signature->first;
    bool is_vla = resolved_callee->type.fn_ptr_signature->second;
    for (int i = 0; i < call.args.size(); ++i) {
      auto *decl_type = i < fn_sig.size() - 1 ? &fn_sig[i + 1] : nullptr;
      std::unique_ptr<ResolvedExpr> resolved_arg = resolve_expr(*call.args[i], decl_type);
      if (!resolved_arg)
        return nullptr;
      Type resolved_type = resolved_arg->type;
      if (const auto *member_access = dynamic_cast<const ResolvedStructMemberAccess *>(resolved_arg.get())) {
        resolved_type = member_access->type;
      }
      if (i < fn_sig.size()) {
        if (!is_same_type(resolved_type, fn_sig[i + 1])) {
          bool is_array_decay;
          if (!try_cast_expr(*resolved_arg, fn_sig[i + 1], m_Cee, is_array_decay) && !is_same_array_decay(resolved_arg->type, fn_sig[i + 1])) {
            std::string unexected_type_str = resolved_arg->type.name;
            for (int i = 0; i < resolved_arg->type.pointer_depth; ++i) {
              unexected_type_str += "*";
            }
            std::string expected_type_str = fn_sig[i + 1].name;
            for (int i = 0; i < fn_sig[i + 1].pointer_depth; ++i) {
              expected_type_str += "*";
            }
            return report(resolved_arg->location, "unexpected type '" + unexected_type_str + "', expected '" + expected_type_str + "'.");
          }
        }
      }
      resolved_arg->set_constant_value(m_Cee.evaluate(*resolved_arg));
      resolved_args.emplace_back(std::move(resolved_arg));
    }
    return std::make_unique<ResolvedCallExpr>(call.location, resolved_callee->decl, std::move(resolved_args));
  }
}

std::unique_ptr<ResolvedAssignment> Sema::resolve_assignment(const Assignment &assignment) {
  std::unique_ptr<ResolvedDeclRefExpr> lhs = resolve_decl_ref_expr(*assignment.variable);
  if (!lhs)
    return nullptr;
  if (const auto *param_decl = dynamic_cast<const ResolvedParamDecl *>(lhs->decl)) {
    if (param_decl->is_const)
      return report(lhs->location, "trying to assign to const variable.");
  } else if (const auto *var_decl = dynamic_cast<const ResolvedVarDecl *>(lhs->decl)) {
    if (var_decl->is_const)
      return report(lhs->location, "trying to assign to const variable.");
  }
  Type *type = nullptr;
  if (auto *member_access = dynamic_cast<ResolvedStructMemberAccess *>(lhs.get()))
    type = &member_access->type;
  std::unique_ptr<ResolvedExpr> rhs = resolve_expr(*assignment.expr, type ? type : &lhs->type);
  if (!rhs)
    return nullptr;
  Type lhs_derefed_type = lhs->type;
  lhs_derefed_type.pointer_depth -= assignment.lhs_deref_count;
  if (!is_same_type(lhs_derefed_type, rhs->type)) {
    bool is_array_decay;
    if (!try_cast_expr(*rhs, lhs_derefed_type, m_Cee, is_array_decay) && !is_same_array_decay(rhs->type, lhs_derefed_type)) {
      std::string lhs_type_str = lhs_derefed_type.name;
      for (int i = 0; i < lhs_derefed_type.pointer_depth - lhs_derefed_type.dereference_counts; ++i) {
        lhs_type_str += "*";
      }
      std::string rhs_type_str = rhs->type.name;
      for (int i = 0; i < rhs->type.pointer_depth - rhs->type.dereference_counts; ++i) {
        rhs_type_str += "*";
      }
      return report(rhs->location, "assigned value type of '" + rhs_type_str + "' does not match variable type '" + lhs_type_str + "'.");
    }
  }
  rhs->set_constant_value(m_Cee.evaluate(*rhs));
  return std::make_unique<ResolvedAssignment>(assignment.location, std::move(lhs), std::move(rhs), assignment.lhs_deref_count);
}
} // namespace saplang
