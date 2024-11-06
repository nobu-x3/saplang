#include <llvm/Support/ErrorHandling.h>

#include "ast.h"
#include "constexpr.h"
#include "lexer.h"
#include <cassert>
#include <limits>

namespace saplang {
std::optional<bool> to_bool(std::optional<ConstexprResult> res) {
  if (!res)
    return std::nullopt;
  switch (res->kind) {
  case Type::Kind::Bool:
    return res->value.b8;
  case Type::Kind::u8:
    return res->value.u8 != 0;
  case Type::Kind::i8:
    return res->value.i8 != 0;
  case Type::Kind::u16:
    return res->value.u16 != 0;
  case Type::Kind::i16:
    return res->value.i16 != 0;
  case Type::Kind::u32:
    return res->value.u32 != 0;
  case Type::Kind::i32:
    return res->value.i32 != 0;
  case Type::Kind::u64:
    return res->value.u64 != 0;
  case Type::Kind::i64:
    return res->value.i64 != 0;
  case Type::Kind::f32:
    return res->value.f32 != 0;
  case Type::Kind::f64:
    return res->value.f64 != 0;
  }
  llvm_unreachable("Given expression evaluates to bool, while the expected "
                   "expression is not of type bool.");
}

bool within_range_float(double val, Type::Kind kind) {
  switch (kind) {
  case Type::Kind::f32:
    if (val > F32_MAX || val < F32_MIN)
      return false;
    break;
  case Type::Kind::f64:
    if (val > F64_MAX || val < F64_MIN)
      return false;
    break;
  }
  return true;
}

bool within_range_unsigned(unsigned long val, Type::Kind kind) {
  switch (kind) {
  case Type::Kind::u8:
    if (val > U8_MAX || val < U8_MIN)
      return false;
    break;
  case Type::Kind::u16:
    if (val > U16_MAX || val < U16_MIN)
      return false;
    break;
  case Type::Kind::u32:
    if (val > U32_MAX || val < U32_MIN)
      return false;
    break;
  case Type::Kind::u64:
    if (val > U64_MAX || val < U64_MIN)
      return false;
    break;
  }
  return true;
}

bool within_range_signed(long val, Type::Kind kind) {
  switch (kind) {
  case Type::Kind::i8:
    if (val > I8_MAX || val < I8_MIN)
      return false;
  case Type::Kind::i16:
    if (val > I16_MAX || val < I16_MIN)
      return false;
  case Type::Kind::i32:
    if (val > I32_MAX || val < I32_MIN)
      return false;
  case Type::Kind::i64:
    if (val > I64_MAX || val < I64_MIN)
      return false;
  }
  return true;
}

ConstexprResult cast_up_signed(long val, Type::Kind kind) {
  ConstexprResult result;
  if (within_range_signed(val, kind)) {
    result.kind = kind;
    switch (kind) {
    case Type::Kind::i8:
      result.value.i8 = static_cast<signed char>(val);
      break;
    case Type::Kind::i16:
      result.value.i16 = static_cast<short>(val);
      break;
    case Type::Kind::i32:
      result.value.i32 = static_cast<int>(val);
      break;
    case Type::Kind::i64:
      result.value.i64 = static_cast<long>(val);
      break;
    }
    return result;
  }
  Type::Kind next_up_kind = (Type::Kind)((unsigned int)(kind) + 1);
  if (next_up_kind <= Type::Kind::SIGNED_INT_END)
    return cast_up_signed(val, next_up_kind);
  result.value.i64 = val;
  result.kind = Type::Kind::i64;
  return result;
}

ConstexprResult cast_up_unsigned(unsigned long val, Type::Kind kind) {
  ConstexprResult result;
  if (within_range_unsigned(val, kind)) {
    result.kind = kind;
    switch (kind) {
    case Type::Kind::u8:
      result.value.u8 = static_cast<unsigned char>(val);
      break;
    case Type::Kind::u16:
      result.value.u16 = static_cast<unsigned short>(val);
      break;
    case Type::Kind::u32:
      result.value.i32 = static_cast<unsigned int>(val);
      break;
    case Type::Kind::u64:
      result.value.u64 = static_cast<unsigned long>(val);
      break;
    case Type::Kind::Void:
    case Type::Kind::Bool:
    case Type::Kind::i8:
    case Type::Kind::i16:
    case Type::Kind::i32:
    case Type::Kind::i64:
    case Type::Kind::f32:
    case Type::Kind::f64:
    case Type::Kind::Custom:
      break;
    }
    return result;
  }
  Type::Kind next_up_kind = (Type::Kind)((unsigned int)(kind) + 1);
  if (next_up_kind <= Type::Kind::UNSIGNED_INT_END)
    return cast_up_signed(val, next_up_kind);
  result.value.u64 = val;
  result.kind = Type::Kind::u64;
  return result;
}

ConstexprResult cast_up_float(double val, Type::Kind kind) {
  ConstexprResult result;
  if (within_range_float(val, kind)) {
    result.kind = kind;
    switch (kind) {
    case Type::Kind::f32:
      result.value.f32 = static_cast<float>(val);
      break;
    case Type::Kind::f64:
      result.value.f64 = static_cast<double>(val);
      break;
    case Type::Kind::Void:
    case Type::Kind::Bool:
    case Type::Kind::i8:
    case Type::Kind::i16:
    case Type::Kind::i32:
    case Type::Kind::i64:
    case Type::Kind::u8:
    case Type::Kind::u16:
    case Type::Kind::u32:
    case Type::Kind::u64:
    case Type::Kind::Custom:
      break;
    }
    return result;
  }
  Type::Kind next_up_kind = (Type::Kind)((unsigned int)(kind) + 1);
  if (next_up_kind <= Type::Kind::FLOATS_END)
    return cast_up_signed(val, next_up_kind);
  result.value.f64 = val;
  result.kind = Type::Kind::f64;
  return result;
}

unsigned long get_value(Value value, Type::Kind kind) {
  switch (kind) {
  case Type::Kind::u8:
    return value.u8;
  case Type::Kind::u16:
    return value.u16;
  case Type::Kind::u32:
    return value.u32;
  case Type::Kind::u64:
    return value.u64;
  case Type::Kind::i8:
    return value.i8;
  case Type::Kind::i16:
    return value.i16;
  case Type::Kind::i32:
    return value.i32;
  case Type::Kind::i64:
    return value.i64;
  case Type::Kind::f32:
    return value.f32;
  case Type::Kind::f64:
    return value.f64;
  case Type::Kind::Bool:
    return value.b8;
  }
  llvm_unreachable("unexpected value type.");
}

ConstexprResult simple_signed_to_float(const Value &val, Type::Kind kind) {
  Type::Kind casted_float_kind;
  Value casted_float_value;
  switch (kind) {
  case Type::Kind::i8: {
    casted_float_kind = Type::Kind::f32;
    casted_float_value.f32 = static_cast<float>(val.i8);
  } break;
  case Type::Kind::i16: {
    casted_float_kind = Type::Kind::f32;
    casted_float_value.f32 = static_cast<float>(val.i16);
  } break;
  case Type::Kind::i32: {
    casted_float_kind = Type::Kind::f32;
    casted_float_value.f32 = static_cast<float>(val.i32);
  } break;
  case Type::Kind::i64: {
    casted_float_kind = Type::Kind::f64;
    casted_float_value.f64 = static_cast<float>(val.i64);
  } break;
  }
  return ConstexprResult{casted_float_value, casted_float_kind};
}

ConstexprResult simple_unsigned_to_float(const Value &val, Type::Kind kind) {
  Type::Kind casted_float_kind;
  Value casted_float_value;
  switch (kind) {
  case Type::Kind::u8: {
    casted_float_kind = Type::Kind::f32;
    casted_float_value.f32 = static_cast<float>(val.u8);
  } break;
  case Type::Kind::u16: {
    casted_float_kind = Type::Kind::f32;
    casted_float_value.f32 = static_cast<float>(val.u16);
  } break;
  case Type::Kind::u32: {
    casted_float_kind = Type::Kind::f32;
    casted_float_value.f32 = static_cast<float>(val.u32);
  } break;
  case Type::Kind::u64: {
    casted_float_kind = Type::Kind::f64;
    casted_float_value.f64 = static_cast<float>(val.u64);
  } break;
  }
  return ConstexprResult{casted_float_value, casted_float_kind};
}

std::optional<ConstexprResult> mul(const std::optional<ConstexprResult> &lhs,
                                   const std::optional<ConstexprResult> &rhs) {
  if (!lhs || !rhs)
    return std::nullopt;
  ConstexprResult ret_res;
  if (lhs->kind == rhs->kind) {
    switch (lhs->kind) {
    case Type::Kind::Bool: {
      std::optional<bool> b_lhs = to_bool(lhs);
      std::optional<bool> b_rhs = to_bool(rhs);
      ret_res.kind = Type::Kind::Bool;
      if (b_lhs && b_rhs) {
        ret_res.value.b8 = *b_lhs * *b_rhs;
      }
      return ret_res;
    } break;
    case Type::Kind::i8:
      return cast_up_signed(lhs->value.i8 * rhs->value.i8, Type::Kind::i8);
    case Type::Kind::i16:
      return cast_up_signed(lhs->value.i16 * rhs->value.i16, Type::Kind::i16);
    case Type::Kind::i32:
      return cast_up_signed(lhs->value.i32 * rhs->value.i32, Type::Kind::i32);
    case Type::Kind::i64:
      return cast_up_signed(lhs->value.i64 * rhs->value.i64, Type::Kind::i64);
    case Type::Kind::u8:
      return cast_up_unsigned(lhs->value.u8 * rhs->value.u8, Type::Kind::u8);
    case Type::Kind::u16:
      return cast_up_unsigned(lhs->value.u16 * rhs->value.u16, Type::Kind::u16);
    case Type::Kind::u32:
      return cast_up_unsigned(lhs->value.u32 * rhs->value.u32, Type::Kind::u32);
    case Type::Kind::u64:
      return cast_up_unsigned(lhs->value.u64 * rhs->value.u64, Type::Kind::u64);
    case Type::Kind::f32:
      return cast_up_float(lhs->value.f32 * rhs->value.f32, Type::Kind::f32);
    case Type::Kind::f64:
      return cast_up_float(lhs->value.f64 * rhs->value.f64, Type::Kind::f64);
    }
  }
  if (is_signed(lhs->kind) && is_signed(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind));
    return cast_up_signed(get_value(lhs->value, lhs->kind) *
                              get_value(rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_signed(lhs->kind) && is_unsigned(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind + 4));
    return cast_up_signed(get_value(lhs->value, lhs->kind) *
                              get_value(rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_unsigned(lhs->kind) && is_signed(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind + 4, (unsigned int)rhs->kind));
    return cast_up_signed(get_value(lhs->value, lhs->kind) *
                              get_value(rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_unsigned(lhs->kind) && is_unsigned(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind));
    return cast_up_unsigned(get_value(lhs->value, lhs->kind) *
                                get_value(rhs->value, rhs->kind),
                            max_kind);
  }
  if (is_float(lhs->kind) || is_float(rhs->kind)) {
    ConstexprResult casted_result;
    ConstexprResult result_other;
    if (is_unsigned(lhs->kind)) {
      casted_result = simple_unsigned_to_float(lhs->value, lhs->kind);
      result_other = {rhs->value, rhs->kind};
    } else if (is_unsigned(rhs->kind)) {
      result_other = {lhs->value, lhs->kind};
      casted_result = simple_unsigned_to_float(rhs->value, rhs->kind);
    } else if (is_signed(lhs->kind)) {
      casted_result = simple_signed_to_float(lhs->value, lhs->kind);
      result_other = {rhs->value, rhs->kind};
    } else if (is_signed(rhs->kind)) {
      result_other = {lhs->value, lhs->kind};
      casted_result = simple_signed_to_float(rhs->value, rhs->kind);
    } else if (is_float(lhs->kind) && is_float(rhs->kind)) {
      casted_result = {lhs->value, lhs->kind};
      result_other = {rhs->value, rhs->kind};
    }
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)casted_result.kind, (unsigned int)result_other.kind));
    return cast_up_float(get_value(casted_result.value, casted_result.kind) *
                             get_value(result_other.value, result_other.kind),
                         max_kind);
  }
  llvm_unreachable("unexpected constexpr type.");
}

std::optional<ConstexprResult> add(const std::optional<ConstexprResult> &lhs,
                                   const std::optional<ConstexprResult> &rhs) {
  if (!lhs || !rhs)
    return std::nullopt;
  ConstexprResult ret_res;
  if (lhs->kind == rhs->kind) {
    switch (lhs->kind) {
    case Type::Kind::Bool: {
      std::optional<bool> b_lhs = to_bool(lhs);
      std::optional<bool> b_rhs = to_bool(rhs);
      ret_res.kind = Type::Kind::Bool;
      if (b_lhs && b_rhs) {
        ret_res.value.b8 = *b_lhs + *b_rhs;
      }
      return ret_res;
    } break;
    case Type::Kind::i8:
      return cast_up_signed(lhs->value.i8 + rhs->value.i8, Type::Kind::i8);
    case Type::Kind::i16:
      return cast_up_signed(lhs->value.i16 + rhs->value.i16, Type::Kind::i16);
    case Type::Kind::i32:
      return cast_up_signed(lhs->value.i32 + rhs->value.i32, Type::Kind::i32);
    case Type::Kind::i64:
      return cast_up_signed(lhs->value.i64 + rhs->value.i64, Type::Kind::i64);
    case Type::Kind::u8:
      return cast_up_unsigned(lhs->value.u8 + rhs->value.u8, Type::Kind::u8);
    case Type::Kind::u16:
      return cast_up_unsigned(lhs->value.u16 + rhs->value.u16, Type::Kind::u16);
    case Type::Kind::u32:
      return cast_up_unsigned(lhs->value.u32 + rhs->value.u32, Type::Kind::u32);
    case Type::Kind::u64:
      return cast_up_unsigned(lhs->value.u64 + rhs->value.u64, Type::Kind::u64);
    case Type::Kind::f32:
      return cast_up_float(lhs->value.f32 + rhs->value.f32, Type::Kind::f32);
    case Type::Kind::f64:
      return cast_up_float(lhs->value.f64 + rhs->value.f64, Type::Kind::f64);
    }
  }
  if (is_signed(lhs->kind) && is_signed(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind));
    return cast_up_signed(get_value(lhs->value, lhs->kind) +
                              get_value(rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_signed(lhs->kind) && is_unsigned(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind + 4));
    return cast_up_signed(get_value(lhs->value, lhs->kind) +
                              get_value(rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_unsigned(lhs->kind) && is_signed(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind + 4, (unsigned int)rhs->kind));
    return cast_up_signed(get_value(lhs->value, lhs->kind) +
                              get_value(rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_unsigned(lhs->kind) && is_unsigned(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind));
    return cast_up_unsigned(get_value(lhs->value, lhs->kind) +
                                get_value(rhs->value, rhs->kind),
                            max_kind);
  }
  if (is_float(lhs->kind) || is_float(rhs->kind)) {
    ConstexprResult casted_result;
    ConstexprResult result_other;
    if (is_unsigned(lhs->kind)) {
      casted_result = simple_unsigned_to_float(lhs->value, lhs->kind);
      result_other = {rhs->value, rhs->kind};
    } else if (is_unsigned(rhs->kind)) {
      result_other = {lhs->value, lhs->kind};
      casted_result = simple_unsigned_to_float(rhs->value, rhs->kind);
    } else if (is_signed(lhs->kind)) {
      casted_result = simple_signed_to_float(lhs->value, lhs->kind);
      result_other = {rhs->value, rhs->kind};
    } else if (is_signed(rhs->kind)) {
      result_other = {lhs->value, lhs->kind};
      casted_result = simple_signed_to_float(rhs->value, rhs->kind);
    } else if (is_float(lhs->kind) && is_float(rhs->kind)) {
      casted_result = {lhs->value, lhs->kind};
      result_other = {rhs->value, rhs->kind};
    }
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)casted_result.kind, (unsigned int)result_other.kind));
    return cast_up_float(get_value(casted_result.value, casted_result.kind) +
                             get_value(result_other.value, result_other.kind),
                         max_kind);
  }
  llvm_unreachable("unexpected constexpr type.");
}

std::optional<ConstexprResult> sub(const std::optional<ConstexprResult> &lhs,
                                   const std::optional<ConstexprResult> &rhs) {
  if (!lhs || !rhs)
    return std::nullopt;
  ConstexprResult ret_res;
  if (lhs->kind == rhs->kind) {
    switch (lhs->kind) {
    case Type::Kind::Bool: {
      std::optional<bool> b_lhs = to_bool(lhs);
      std::optional<bool> b_rhs = to_bool(rhs);
      ret_res.kind = Type::Kind::Bool;
      if (b_lhs && b_rhs) {
        ret_res.value.b8 = *b_lhs - *b_rhs;
      }
      return ret_res;
    } break;
    case Type::Kind::i8:
      return cast_up_signed(lhs->value.i8 - rhs->value.i8, Type::Kind::i8);
    case Type::Kind::i16:
      return cast_up_signed(lhs->value.i16 - rhs->value.i16, Type::Kind::i16);
    case Type::Kind::i32:
      return cast_up_signed(lhs->value.i32 - rhs->value.i32, Type::Kind::i32);
    case Type::Kind::i64:
      return cast_up_signed(lhs->value.i64 - rhs->value.i64, Type::Kind::i64);
    case Type::Kind::u8:
      return cast_up_unsigned(lhs->value.u8 - rhs->value.u8, Type::Kind::u8);
    case Type::Kind::u16:
      return cast_up_unsigned(lhs->value.u16 - rhs->value.u16, Type::Kind::u16);
    case Type::Kind::u32:
      return cast_up_unsigned(lhs->value.u32 - rhs->value.u32, Type::Kind::u32);
    case Type::Kind::u64:
      return cast_up_unsigned(lhs->value.u64 - rhs->value.u64, Type::Kind::u64);
    case Type::Kind::f32:
      return cast_up_float(lhs->value.f32 - rhs->value.f32, Type::Kind::f32);
    case Type::Kind::f64:
      return cast_up_float(lhs->value.f64 - rhs->value.f64, Type::Kind::f64);
    }
  }
  if (is_signed(lhs->kind) && is_signed(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind));
    return cast_up_signed(get_value(lhs->value, lhs->kind) -
                              get_value(rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_signed(lhs->kind) && is_unsigned(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind + 4));
    return cast_up_signed(get_value(lhs->value, lhs->kind) -
                              get_value(rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_unsigned(lhs->kind) && is_signed(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind + 4, (unsigned int)rhs->kind));
    return cast_up_signed(get_value(lhs->value, lhs->kind) -
                              get_value(rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_unsigned(lhs->kind) && is_unsigned(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind));
    return cast_up_unsigned(get_value(lhs->value, lhs->kind) -
                                get_value(rhs->value, rhs->kind),
                            max_kind);
  }
  if (is_float(lhs->kind) || is_float(rhs->kind)) {
    ConstexprResult casted_result;
    ConstexprResult result_other;
    if (is_unsigned(lhs->kind)) {
      casted_result = simple_unsigned_to_float(lhs->value, lhs->kind);
      result_other = {rhs->value, rhs->kind};
    } else if (is_unsigned(rhs->kind)) {
      result_other = {lhs->value, lhs->kind};
      casted_result = simple_unsigned_to_float(rhs->value, rhs->kind);
    } else if (is_signed(lhs->kind)) {
      casted_result = simple_signed_to_float(lhs->value, lhs->kind);
      result_other = {rhs->value, rhs->kind};
    } else if (is_signed(rhs->kind)) {
      result_other = {lhs->value, lhs->kind};
      casted_result = simple_signed_to_float(rhs->value, rhs->kind);
    } else if (is_float(lhs->kind) && is_float(rhs->kind)) {
      casted_result = {lhs->value, lhs->kind};
      result_other = {rhs->value, rhs->kind};
    }
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)casted_result.kind, (unsigned int)result_other.kind));
    return cast_up_float(get_value(casted_result.value, casted_result.kind) -
                             get_value(result_other.value, result_other.kind),
                         max_kind);
  }
  llvm_unreachable("unexpected constexpr type.");
}

std::optional<ConstexprResult> shl(const std::optional<ConstexprResult> &lhs,
                                   const std::optional<ConstexprResult> &rhs) {
#define BIT_SHIFT_L(value_type)                                                \
  case Type::Kind::value_type: {                                               \
    switch (rhs->kind) {                                                       \
    case Type::Kind::i8:                                                       \
      ret_res.value.value_type = lhs->value.value_type << rhs->value.i8;       \
      break;                                                                   \
    case Type::Kind::u8:                                                       \
      ret_res.value.value_type = lhs->value.value_type << rhs->value.u8;       \
      break;                                                                   \
    case Type::Kind::i16:                                                      \
      ret_res.value.value_type = lhs->value.value_type << rhs->value.i16;      \
      break;                                                                   \
    case Type::Kind::u16:                                                      \
      ret_res.value.value_type = lhs->value.value_type << rhs->value.u16;      \
      break;                                                                   \
    case Type::Kind::i32:                                                      \
      ret_res.value.value_type = lhs->value.value_type << rhs->value.i32;      \
      break;                                                                   \
    case Type::Kind::u32:                                                      \
      ret_res.value.value_type = lhs->value.value_type << rhs->value.u32;      \
      break;                                                                   \
    case Type::Kind::i64:                                                      \
      ret_res.value.value_type = lhs->value.value_type << rhs->value.i64;      \
      break;                                                                   \
    case Type::Kind::u64:                                                      \
      ret_res.value.value_type = lhs->value.value_type << rhs->value.u64;      \
      break;                                                                   \
    default:                                                                   \
      return std::nullopt;                                                     \
      break;                                                                   \
    }                                                                          \
  } break;

  if (!lhs || !rhs)
    return std::nullopt;
  if (rhs->kind < Type::Kind::INTEGERS_START ||
      rhs->kind > Type::Kind::INTEGERS_END)
    return std::nullopt;
  ConstexprResult ret_res = *lhs;
  switch (lhs->kind) {
    BIT_SHIFT_L(i8);
    BIT_SHIFT_L(i16);
    BIT_SHIFT_L(i32);
    BIT_SHIFT_L(i64);
    BIT_SHIFT_L(u8);
    BIT_SHIFT_L(u16);
    BIT_SHIFT_L(u32);
    BIT_SHIFT_L(u64);
  default:
    return std::nullopt;
    break;
  }
  return ret_res;
}

std::optional<ConstexprResult> shr(const std::optional<ConstexprResult> &lhs,
                                   const std::optional<ConstexprResult> &rhs) {
#define BIT_SHIFT_R(value_type)                                                \
  case Type::Kind::value_type: {                                               \
    switch (rhs->kind) {                                                       \
    case Type::Kind::i8:                                                       \
      ret_res.value.value_type = lhs->value.value_type >> rhs->value.i8;       \
      break;                                                                   \
    case Type::Kind::u8:                                                       \
      ret_res.value.value_type = lhs->value.value_type >> rhs->value.u8;       \
      break;                                                                   \
    case Type::Kind::i16:                                                      \
      ret_res.value.value_type = lhs->value.value_type >> rhs->value.i16;      \
      break;                                                                   \
    case Type::Kind::u16:                                                      \
      ret_res.value.value_type = lhs->value.value_type >> rhs->value.u16;      \
      break;                                                                   \
    case Type::Kind::i32:                                                      \
      ret_res.value.value_type = lhs->value.value_type >> rhs->value.i32;      \
      break;                                                                   \
    case Type::Kind::u32:                                                      \
      ret_res.value.value_type = lhs->value.value_type >> rhs->value.u32;      \
      break;                                                                   \
    case Type::Kind::i64:                                                      \
      ret_res.value.value_type = lhs->value.value_type >> rhs->value.i64;      \
      break;                                                                   \
    case Type::Kind::u64:                                                      \
      ret_res.value.value_type = lhs->value.value_type >> rhs->value.u64;      \
      break;                                                                   \
    default:                                                                   \
      return std::nullopt;                                                     \
      break;                                                                   \
    }                                                                          \
  } break;

  if (!lhs || !rhs)
    return std::nullopt;
  if (rhs->kind < Type::Kind::INTEGERS_START ||
      rhs->kind > Type::Kind::INTEGERS_END)
    return std::nullopt;
  ConstexprResult ret_res = *lhs;
  switch (lhs->kind) {
    BIT_SHIFT_R(i8);
    BIT_SHIFT_R(i16);
    BIT_SHIFT_R(i32);
    BIT_SHIFT_R(i64);
    BIT_SHIFT_R(u8);
    BIT_SHIFT_R(u16);
    BIT_SHIFT_R(u32);
    BIT_SHIFT_R(u64);
  default:
    return std::nullopt;
    break;
  }
  return ret_res;
}

std::optional<ConstexprResult>
bitwise_and(const std::optional<ConstexprResult> &lhs,
            const std::optional<ConstexprResult> &rhs) {
#define BITWISE_AND(value_type)                                                \
  case Type::Kind::value_type: {                                               \
    switch (rhs->kind) {                                                       \
    case Type::Kind::i8:                                                       \
      ret_res.value.value_type = lhs->value.value_type & rhs->value.i8;        \
      break;                                                                   \
    case Type::Kind::u8:                                                       \
      ret_res.value.value_type = lhs->value.value_type & rhs->value.u8;        \
      break;                                                                   \
    case Type::Kind::i16:                                                      \
      ret_res.value.value_type = lhs->value.value_type & rhs->value.i16;       \
      break;                                                                   \
    case Type::Kind::u16:                                                      \
      ret_res.value.value_type = lhs->value.value_type & rhs->value.u16;       \
      break;                                                                   \
    case Type::Kind::i32:                                                      \
      ret_res.value.value_type = lhs->value.value_type & rhs->value.i32;       \
      break;                                                                   \
    case Type::Kind::u32:                                                      \
      ret_res.value.value_type = lhs->value.value_type & rhs->value.u32;       \
      break;                                                                   \
    case Type::Kind::i64:                                                      \
      ret_res.value.value_type = lhs->value.value_type & rhs->value.i64;       \
      break;                                                                   \
    case Type::Kind::u64:                                                      \
      ret_res.value.value_type = lhs->value.value_type & rhs->value.u64;       \
      break;                                                                   \
    default:                                                                   \
      return std::nullopt;                                                     \
      break;                                                                   \
    }                                                                          \
  } break;

  if (!lhs || !rhs)
    return std::nullopt;
  if (rhs->kind < Type::Kind::INTEGERS_START ||
      rhs->kind > Type::Kind::INTEGERS_END)
    return std::nullopt;
  ConstexprResult ret_res = *lhs;
  switch (lhs->kind) {
    BITWISE_AND(i8);
    BITWISE_AND(i16);
    BITWISE_AND(i32);
    BITWISE_AND(i64);
    BITWISE_AND(u8);
    BITWISE_AND(u16);
    BITWISE_AND(u32);
    BITWISE_AND(u64);
  default:
    return std::nullopt;
    break;
  }
  return ret_res;
}

std::optional<ConstexprResult>
bitwise_or(const std::optional<ConstexprResult> &lhs,
           const std::optional<ConstexprResult> &rhs) {
#define BITWISE_OR(value_type)                                                 \
  case Type::Kind::value_type: {                                               \
    switch (rhs->kind) {                                                       \
    case Type::Kind::i8:                                                       \
      ret_res.value.value_type = lhs->value.value_type | rhs->value.i8;        \
      break;                                                                   \
    case Type::Kind::u8:                                                       \
      ret_res.value.value_type = lhs->value.value_type | rhs->value.u8;        \
      break;                                                                   \
    case Type::Kind::i16:                                                      \
      ret_res.value.value_type = lhs->value.value_type | rhs->value.i16;       \
      break;                                                                   \
    case Type::Kind::u16:                                                      \
      ret_res.value.value_type = lhs->value.value_type | rhs->value.u16;       \
      break;                                                                   \
    case Type::Kind::i32:                                                      \
      ret_res.value.value_type = lhs->value.value_type | rhs->value.i32;       \
      break;                                                                   \
    case Type::Kind::u32:                                                      \
      ret_res.value.value_type = lhs->value.value_type | rhs->value.u32;       \
      break;                                                                   \
    case Type::Kind::i64:                                                      \
      ret_res.value.value_type = lhs->value.value_type | rhs->value.i64;       \
      break;                                                                   \
    case Type::Kind::u64:                                                      \
      ret_res.value.value_type = lhs->value.value_type | rhs->value.u64;       \
      break;                                                                   \
    default:                                                                   \
      return std::nullopt;                                                     \
      break;                                                                   \
    }                                                                          \
  } break;

  if (!lhs || !rhs)
    return std::nullopt;
  if (rhs->kind < Type::Kind::INTEGERS_START ||
      rhs->kind > Type::Kind::INTEGERS_END)
    return std::nullopt;
  ConstexprResult ret_res = *lhs;
  switch (lhs->kind) {
    BITWISE_OR(i8);
    BITWISE_OR(i16);
    BITWISE_OR(i32);
    BITWISE_OR(i64);
    BITWISE_OR(u8);
    BITWISE_OR(u16);
    BITWISE_OR(u32);
    BITWISE_OR(u64);
  default:
    return std::nullopt;
    break;
  }
  return ret_res;
}

std::optional<ConstexprResult> rem(const std::optional<ConstexprResult> &lhs,
                                   const std::optional<ConstexprResult> &rhs) {
#define REM(value_type)                                                        \
  case Type::Kind::value_type: {                                               \
    switch (rhs->kind) {                                                       \
    case Type::Kind::i8:                                                       \
      ret_res.value.value_type = lhs->value.value_type % rhs->value.i8;        \
      break;                                                                   \
    case Type::Kind::u8:                                                       \
      ret_res.value.value_type = lhs->value.value_type % rhs->value.u8;        \
      break;                                                                   \
    case Type::Kind::i16:                                                      \
      ret_res.value.value_type = lhs->value.value_type % rhs->value.i16;       \
      break;                                                                   \
    case Type::Kind::u16:                                                      \
      ret_res.value.value_type = lhs->value.value_type % rhs->value.u16;       \
      break;                                                                   \
    case Type::Kind::i32:                                                      \
      ret_res.value.value_type = lhs->value.value_type % rhs->value.i32;       \
      break;                                                                   \
    case Type::Kind::u32:                                                      \
      ret_res.value.value_type = lhs->value.value_type % rhs->value.u32;       \
      break;                                                                   \
    case Type::Kind::i64:                                                      \
      ret_res.value.value_type = lhs->value.value_type % rhs->value.i64;       \
      break;                                                                   \
    case Type::Kind::u64:                                                      \
      ret_res.value.value_type = lhs->value.value_type % rhs->value.u64;       \
      break;                                                                   \
    default:                                                                   \
      return std::nullopt;                                                     \
      break;                                                                   \
    }                                                                          \
  } break;

  if (!lhs || !rhs)
    return std::nullopt;
  if (rhs->kind < Type::Kind::INTEGERS_START ||
      rhs->kind > Type::Kind::INTEGERS_END)
    return std::nullopt;
  ConstexprResult ret_res = *lhs;
  switch (lhs->kind) {
    REM(i8);
    REM(i16);
    REM(i32);
    REM(i64);
    REM(u8);
    REM(u16);
    REM(u32);
    REM(u64);
  default:
    return std::nullopt;
    break;
  }
  return ret_res;
}

std::optional<ConstexprResult>
bitwise_xor(const std::optional<ConstexprResult> &lhs,
            const std::optional<ConstexprResult> &rhs) {
#define XOR(value_type)                                                        \
  case Type::Kind::value_type: {                                               \
    switch (rhs->kind) {                                                       \
    case Type::Kind::i8:                                                       \
      ret_res.value.value_type = lhs->value.value_type ^ rhs->value.i8;        \
      break;                                                                   \
    case Type::Kind::u8:                                                       \
      ret_res.value.value_type = lhs->value.value_type ^ rhs->value.u8;        \
      break;                                                                   \
    case Type::Kind::i16:                                                      \
      ret_res.value.value_type = lhs->value.value_type ^ rhs->value.i16;       \
      break;                                                                   \
    case Type::Kind::u16:                                                      \
      ret_res.value.value_type = lhs->value.value_type ^ rhs->value.u16;       \
      break;                                                                   \
    case Type::Kind::i32:                                                      \
      ret_res.value.value_type = lhs->value.value_type ^ rhs->value.i32;       \
      break;                                                                   \
    case Type::Kind::u32:                                                      \
      ret_res.value.value_type = lhs->value.value_type ^ rhs->value.u32;       \
      break;                                                                   \
    case Type::Kind::i64:                                                      \
      ret_res.value.value_type = lhs->value.value_type ^ rhs->value.i64;       \
      break;                                                                   \
    case Type::Kind::u64:                                                      \
      ret_res.value.value_type = lhs->value.value_type ^ rhs->value.u64;       \
      break;                                                                   \
    default:                                                                   \
      return std::nullopt;                                                     \
      break;                                                                   \
    }                                                                          \
  } break;

  if (!lhs || !rhs)
    return std::nullopt;
  if (rhs->kind < Type::Kind::INTEGERS_START ||
      rhs->kind > Type::Kind::INTEGERS_END)
    return std::nullopt;
  ConstexprResult ret_res = *lhs;
  switch (lhs->kind) {
    XOR(i8);
    XOR(i16);
    XOR(i32);
    XOR(i64);
    XOR(u8);
    XOR(u16);
    XOR(u32);
    XOR(u64);
  default:
    return std::nullopt;
    break;
  }
  return ret_res;
}
std::optional<ConstexprResult> div(const std::optional<ConstexprResult> &lhs,
                                   const std::optional<ConstexprResult> &rhs) {
  if (!lhs || !rhs)
    return std::nullopt;
  ConstexprResult ret_res;
  if (lhs->kind == rhs->kind) {
    switch (lhs->kind) {
    case Type::Kind::i8:
      return cast_up_signed(lhs->value.i8 / rhs->value.i8, Type::Kind::i8);
    case Type::Kind::i16:
      return cast_up_signed(lhs->value.i16 / rhs->value.i16, Type::Kind::i16);
    case Type::Kind::i32:
      return cast_up_signed(lhs->value.i32 / rhs->value.i32, Type::Kind::i32);
    case Type::Kind::i64:
      return cast_up_signed(lhs->value.i64 / rhs->value.i64, Type::Kind::i64);
    case Type::Kind::u8:
      return cast_up_unsigned(lhs->value.u8 / rhs->value.u8, Type::Kind::u8);
    case Type::Kind::u16:
      return cast_up_unsigned(lhs->value.u16 / rhs->value.u16, Type::Kind::u16);
    case Type::Kind::u32:
      return cast_up_unsigned(lhs->value.u32 / rhs->value.u32, Type::Kind::u32);
    case Type::Kind::u64:
      return cast_up_unsigned(lhs->value.u64 / rhs->value.u64, Type::Kind::u64);
    case Type::Kind::f32:
      return cast_up_float(lhs->value.f32 / rhs->value.f32, Type::Kind::f32);
    case Type::Kind::f64:
      return cast_up_float(lhs->value.f64 / rhs->value.f64, Type::Kind::f64);
    }
  }
  if (is_signed(lhs->kind) && is_signed(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind));
    return cast_up_signed(get_value(lhs->value, lhs->kind) -
                              get_value(rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_signed(lhs->kind) && is_unsigned(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind + 4));
    return cast_up_signed(get_value(lhs->value, lhs->kind) -
                              get_value(rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_unsigned(lhs->kind) && is_signed(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind + 4, (unsigned int)rhs->kind));
    return cast_up_signed(get_value(lhs->value, lhs->kind) -
                              get_value(rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_unsigned(lhs->kind) && is_unsigned(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind));
    return cast_up_unsigned(get_value(lhs->value, lhs->kind) -
                                get_value(rhs->value, rhs->kind),
                            max_kind);
  }
  if (is_float(lhs->kind) || is_float(rhs->kind)) {
    ConstexprResult casted_result;
    ConstexprResult result_other;
    if (is_unsigned(lhs->kind)) {
      casted_result = simple_unsigned_to_float(lhs->value, lhs->kind);
      result_other = {rhs->value, rhs->kind};
    } else if (is_unsigned(rhs->kind)) {
      result_other = {lhs->value, lhs->kind};
      casted_result = simple_unsigned_to_float(rhs->value, rhs->kind);
    } else if (is_signed(lhs->kind)) {
      casted_result = simple_signed_to_float(lhs->value, lhs->kind);
      result_other = {rhs->value, rhs->kind};
    } else if (is_signed(rhs->kind)) {
      result_other = {lhs->value, lhs->kind};
      casted_result = simple_signed_to_float(rhs->value, rhs->kind);
    } else if (is_float(lhs->kind) && is_float(rhs->kind)) {
      casted_result = {lhs->value, lhs->kind};
      result_other = {rhs->value, rhs->kind};
    }
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)casted_result.kind, (unsigned int)result_other.kind));
    return cast_up_float(get_value(casted_result.value, casted_result.kind) -
                             get_value(result_other.value, result_other.kind),
                         max_kind);
  }
  llvm_unreachable("unexpected constexpr type.");
}

#define CMP_CASE(type)                                                         \
  case Type::Kind::type: {                                                     \
    if (lhs->value.type > rhs->value.type)                                     \
      return 1;                                                                \
    else if (lhs->value.type < rhs->value.type)                                \
      return -1;                                                               \
    else                                                                       \
      return 0;                                                                \
  } break;

int cmp(long lhs, long rhs) {
  if (lhs > rhs)
    return 1;
  else if (lhs < rhs)
    return -1;
  else
    return 0;
};

// returns 1 if lhs > rhs, -1 if lhs < rhs, 0 if lhs == rhs
std::optional<int> compare(const std::optional<ConstexprResult> &lhs,
                           const std::optional<ConstexprResult> &rhs) {

  if (!lhs || !rhs)
    return std::nullopt;
  if (lhs->kind == rhs->kind) {
    switch (lhs->kind) {
    case Type::Kind::Bool: {
      if (lhs->value.b8 > rhs->value.b8)
        return 1;
      else if (lhs->value.b8 < rhs->value.b8)
        return -1;
      else
        return 0;
    } break;
      CMP_CASE(u8)
      CMP_CASE(u16)
      CMP_CASE(u32)
      CMP_CASE(u64)
      CMP_CASE(i8)
      CMP_CASE(i16)
      CMP_CASE(i32)
      CMP_CASE(i64)
      CMP_CASE(f32)
      CMP_CASE(f64)
    }
  }
  return cmp(get_value(lhs->value, lhs->kind),
             get_value(rhs->value, rhs->kind));
}

std::optional<ConstexprResult> ConstantExpressionEvaluator::eval_binary_op(
    const ResolvedBinaryOperator &binop) {
  std::optional<ConstexprResult> lhs = evaluate(*binop.lhs);
  ConstexprResult return_value;
  if (binop.op == TokenKind::PipePipe) {
    return_value.kind = Type::Kind::Bool;
    std::optional<bool> val_lhs = to_bool(lhs);
    if (val_lhs.value_or(false)) {
      return_value.value.b8 = true;
      return return_value;
    }
    std::optional<bool> val_rhs = to_bool(evaluate(*binop.rhs));
    if (val_rhs.value_or(false)) {
      return_value.value.b8 = true;
      return return_value;
    }
    if (val_lhs.has_value() && val_rhs.has_value()) {
      return_value.value.b8 = *val_lhs || *val_rhs;
      return return_value;
    }
    return std::nullopt;
  }
  if (binop.op == TokenKind::AmpAmp) {
    return_value.kind = Type::Kind::Bool;
    if (!to_bool(lhs).value_or(true)) {
      return_value.value.b8 = false;
      return return_value;
    }
    std::optional<ConstexprResult> rhs = evaluate(*binop.rhs);
    if (!lhs) {
      std::optional<bool> maybe_rhs = to_bool(rhs);
      if (!to_bool(rhs).value_or(true)) {
        return_value.value.b8 = false;
        return return_value;
      }
      return std::nullopt;
    }
    std::optional<bool> maybe_val = to_bool(rhs);
    if (!maybe_val)
      return std::nullopt;
    return_value.value.b8 = *maybe_val;
    return return_value;
  }
  if (!lhs)
    return std::nullopt;
  std::optional<ConstexprResult> rhs = evaluate(*binop.rhs);
  if (!rhs)
    return std::nullopt;
  switch (binop.op) {
  case TokenKind::Asterisk:
    return mul(lhs, rhs);
  case TokenKind::Plus:
    return add(lhs, rhs);
  case TokenKind::Minus:
    return sub(lhs, rhs);
  case TokenKind::Slash:
    return div(lhs, rhs);
  case TokenKind::BitwiseShiftL:
    return shl(lhs, rhs);
  case TokenKind::BitwiseShiftR:
    return shr(lhs, rhs);
  case TokenKind::Amp:
    return bitwise_and(lhs, rhs);
  case TokenKind::Pipe:
    return bitwise_or(lhs, rhs);
  case TokenKind::Percent:
    return rem(lhs, rhs);
  case TokenKind::Hat:
    return bitwise_xor(rhs, rhs);
  case TokenKind::LessThan: {
    std::optional<int> result = compare(lhs, rhs);
    if (!result)
      return std::nullopt;
    return_value.kind = Type::Kind::Bool;
    return_value.value.b8 = *result == -1;
  } break;
  case TokenKind::LessThanOrEqual: {
    std::optional<int> result = compare(lhs, rhs);
    if (!result)
      return std::nullopt;
    return_value.kind = Type::Kind::Bool;
    return_value.value.b8 = *result == -1 || *result == 0;
  } break;
  case TokenKind::GreaterThan: {
    std::optional<int> result = compare(lhs, rhs);
    if (!result)
      return std::nullopt;
    return_value.kind = Type::Kind::Bool;
    return_value.value.b8 = *result == 1;
  } break;
  case TokenKind::GreaterThanOrEqual: {
    std::optional<int> result = compare(lhs, rhs);
    if (!result)
      return std::nullopt;
    return_value.kind = Type::Kind::Bool;
    return_value.value.b8 = *result == 1 || *result == 0;
  } break;
  case TokenKind::ExclamationEqual: {
    std::optional<int> result = compare(lhs, rhs);
    if (!result)
      return std::nullopt;
    return_value.kind = Type::Kind::Bool;
    return_value.value.b8 = *result != 0;
  } break;
  default:
    assert(binop.op == TokenKind::EqualEqual && "unexpected binary operator");
    std::optional<int> result = compare(lhs, rhs);
    if (!result)
      return std::nullopt;
    return_value.kind = Type::Kind::Bool;
    return_value.value.b8 = *result == 0;
  }
  return return_value;
}

std::optional<ConstexprResult>
ConstantExpressionEvaluator::eval_unary_op(const ResolvedUnaryOperator &unop) {
  std::optional<ConstexprResult> rhs = evaluate(*unop.rhs);
  if (!rhs)
    return std::nullopt;
  ConstexprResult result;
  if (unop.op == TokenKind::Exclamation) {
    result.kind = Type::Kind::Bool;
    result.value.b8 = !*to_bool(rhs);
    return result;
  }
  if (unop.op == TokenKind::Tilda) {
    switch (rhs->kind) {
    case Type::Kind::i8:
    case Type::Kind::u8:
      result.kind = Type::Kind::i8;
      result.value.i8 = rhs->kind == Type::Kind::i8
                            ? ~rhs->value.i8
                            : ~static_cast<std::int8_t>(rhs->value.u8);
      break;
    case Type::Kind::i16:
    case Type::Kind::u16:
      result.kind = Type::Kind::i16;
      result.value.i16 = rhs->kind == Type::Kind::i16
                             ? ~rhs->value.i16
                             : ~static_cast<std::int16_t>(rhs->value.u16);
      break;
    case Type::Kind::i32:
    case Type::Kind::u32:
      result.kind = Type::Kind::i32;
      result.value.i32 = rhs->kind == Type::Kind::i32
                             ? ~rhs->value.i32
                             : ~static_cast<std::int32_t>(rhs->value.u32);
      break;
    case Type::Kind::i64:
    case Type::Kind::u64:
      result.kind = Type::Kind::i64;
      result.value.i64 = rhs->kind == Type::Kind::i64
                             ? ~rhs->value.i64
                             : ~static_cast<std::int64_t>(rhs->value.u64);
      break;
    default:
      return std::nullopt;
    }
  }
  if (unop.op == TokenKind::Minus) {
    switch (rhs->kind) {
    case Type::Kind::i8:
    case Type::Kind::u8:
      result.kind = Type::Kind::i8;
      result.value.i8 = rhs->kind == Type::Kind::i8
                            ? -rhs->value.i8
                            : -static_cast<std::int8_t>(rhs->value.u8);
      break;
    case Type::Kind::i16:
    case Type::Kind::u16:
      result.kind = Type::Kind::i16;
      result.value.i16 = rhs->kind == Type::Kind::i16
                             ? -rhs->value.i16
                             : -static_cast<std::int16_t>(rhs->value.u16);
      break;
    case Type::Kind::i32:
    case Type::Kind::u32:
      result.kind = Type::Kind::i32;
      result.value.i32 = rhs->kind == Type::Kind::i32
                             ? -rhs->value.i32
                             : -static_cast<std::int32_t>(rhs->value.u32);
      break;
    case Type::Kind::i64:
    case Type::Kind::u64:
      result.kind = Type::Kind::i64;
      result.value.i64 = rhs->kind == Type::Kind::i64
                             ? -rhs->value.i64
                             : -static_cast<std::int64_t>(rhs->value.u64);
      break;
    case Type::Kind::f32:
      result.kind = Type::Kind::f32;
      result.value.f32 = -rhs->value.f32;
      break;
    case Type::Kind::f64:
      result.kind = Type::Kind::f64;
      result.value.f64 = -rhs->value.f64;
      break;
    }
  }
  return result;
}

std::optional<ConstexprResult> ConstantExpressionEvaluator::eval_decl_ref_expr(
    const ResolvedDeclRefExpr &ref) {
  const auto *rvd = dynamic_cast<const ResolvedVarDecl *>(ref.decl);
  if (!rvd || !rvd->is_const || !rvd->initializer)
    return std::nullopt;
  return evaluate(*rvd->initializer);
}

std::optional<ConstexprResult>
ConstantExpressionEvaluator::evaluate(const ResolvedExpr &expr) {
  if (const std::optional<ConstexprResult> &res = expr.get_constant_value())
    return res;
  if (const auto *numlit = dynamic_cast<const ResolvedNumberLiteral *>(&expr)) {
    ConstexprResult res{numlit->value, numlit->type.kind};
    return res;
  }
  if (const auto *grouping_expr =
          dynamic_cast<const ResolvedGroupingExpr *>(&expr))
    return evaluate(*grouping_expr->expr);
  if (const auto *binop = dynamic_cast<const ResolvedBinaryOperator *>(&expr))
    return eval_binary_op(*binop);
  if (const auto *unop = dynamic_cast<const ResolvedUnaryOperator *>(&expr))
    return eval_unary_op(*unop);
  if (const auto *decl_ref_expr =
          dynamic_cast<const ResolvedDeclRefExpr *>(&expr))
    return eval_decl_ref_expr(*decl_ref_expr);
  return std::nullopt;
}
} // namespace saplang
