#include <llvm-18/llvm/Support/ErrorHandling.h>

#include "constexpr.h"
#include <cassert>
#include <limits>

namespace saplang {
std::optional<bool> to_bool(std::optional<ConstexprResult> res) {
  if (!res || !res->value)
    return std::nullopt;
  switch (res->kind) {
  case Type::Kind::Bool:
    return res->value->b8;
  case Type::Kind::u8:
    return res->value->u8 != 0;
  case Type::Kind::i8:
    return res->value->i8 != 0;
  case Type::Kind::u16:
    return res->value->u16 != 0;
  case Type::Kind::i16:
    return res->value->i16 != 0;
  case Type::Kind::u32:
    return res->value->u32 != 0;
  case Type::Kind::i32:
    return res->value->i32 != 0;
  case Type::Kind::u64:
    return res->value->u64 != 0;
  case Type::Kind::i64:
    return res->value->i64 != 0;
  case Type::Kind::f32:
    return res->value->f32 != 0;
  case Type::Kind::f64:
    return res->value->f64 != 0;
  }
  llvm_unreachable("Unknown kind");
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
      result.value->i8 = static_cast<signed char>(val);
      break;
    case Type::Kind::i16:
      result.value->i16 = static_cast<short>(val);
      break;
    case Type::Kind::i32:
      result.value->i32 = static_cast<int>(val);
      break;
    case Type::Kind::i64:
      result.value->i64 = static_cast<long>(val);
      break;
    }
    return result;
  }
  Type::Kind next_up_kind = (Type::Kind)((unsigned int)(kind) + 1);
  if (next_up_kind <= Type::Kind::SIGNED_INT_END)
    return cast_up_signed(val, next_up_kind);
  result.value->i64 = val;
  result.kind = Type::Kind::i64;
  return result;
}

ConstexprResult cast_up_unsigned(unsigned long val, Type::Kind kind) {
  ConstexprResult result;
  if (within_range_unsigned(val, kind)) {
    result.kind = kind;
    switch (kind) {
    case Type::Kind::u8:
      result.value->u8 = static_cast<unsigned char>(val);
      break;
    case Type::Kind::u16:
      result.value->u16 = static_cast<unsigned short>(val);
      break;
    case Type::Kind::u32:
      result.value->i32 = static_cast<unsigned int>(val);
      break;
    case Type::Kind::u64:
      result.value->u64 = static_cast<unsigned long>(val);
      break;
    }
    return result;
  }
  Type::Kind next_up_kind = (Type::Kind)((unsigned int)(kind) + 1);
  if (next_up_kind <= Type::Kind::UNSIGNED_INT_END)
    return cast_up_signed(val, next_up_kind);
  result.value->u64 = val;
  result.kind = Type::Kind::u64;
  return result;
}

ConstexprResult cast_up_float(double val, Type::Kind kind) {
  ConstexprResult result;
  if (within_range_float(val, kind)) {
    result.kind = kind;
    switch (kind) {
    case Type::Kind::f32:
      result.value->f32 = static_cast<float>(val);
      break;
    case Type::Kind::f64:
      result.value->f64 = static_cast<double>(val);
      break;
    }
    return result;
  }
  Type::Kind next_up_kind = (Type::Kind)((unsigned int)(kind) + 1);
  if (next_up_kind <= Type::Kind::FLOATS_END)
    return cast_up_signed(val, next_up_kind);
  result.value->f64 = val;
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
}

bool is_signed(Type::Kind kind) {
  if (kind >= Type::Kind::SIGNED_INT_START &&
      kind <= Type::Kind::SIGNED_INT_END)
    return true;
  return false;
}

bool is_unsigned(Type::Kind kind) {
  if (kind >= Type::Kind::UNSIGNED_INT_START &&
      kind <= Type::Kind::UNSIGNED_INT_END)
    return true;
  return false;
}

bool is_float(Type::Kind kind) {
  if (kind >= Type::Kind::FLOATS_START && kind <= Type::Kind::FLOATS_END)
    return true;
  return false;
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
  if (!lhs || !lhs->value || !rhs || !rhs->value)
    return std::nullopt;
  ConstexprResult ret_res;
  if (lhs->kind == rhs->kind) {
    switch (lhs->kind) {
    case Type::Kind::Bool: {
      std::optional<bool> b_lhs = to_bool(lhs);
      std::optional<bool> b_rhs = to_bool(rhs);
      ret_res.kind = Type::Kind::Bool;
      if (b_lhs && b_rhs) {
        ret_res.value->b8 = *b_lhs * *b_rhs;
      }
      return ret_res;
    } break;
    case Type::Kind::i8:
      return cast_up_signed(lhs->value->i8 * rhs->value->i8, Type::Kind::i8);
    case Type::Kind::i16:
      return cast_up_signed(lhs->value->i16 * rhs->value->i16, Type::Kind::i16);
    case Type::Kind::i32:
      return cast_up_signed(lhs->value->i32 * rhs->value->i32, Type::Kind::i32);
    case Type::Kind::i64:
      return cast_up_signed(lhs->value->i64 * rhs->value->i64, Type::Kind::i64);
    case Type::Kind::u8:
      return cast_up_unsigned(lhs->value->u8 * rhs->value->u8, Type::Kind::u8);
    case Type::Kind::u16:
      return cast_up_unsigned(lhs->value->u16 * rhs->value->u16,
                              Type::Kind::u16);
    case Type::Kind::u32:
      return cast_up_unsigned(lhs->value->u32 * rhs->value->u32,
                              Type::Kind::u32);
    case Type::Kind::u64:
      return cast_up_unsigned(lhs->value->u64 * rhs->value->u64,
                              Type::Kind::u64);
    case Type::Kind::f32:
      return cast_up_float(lhs->value->f32 * rhs->value->f32, Type::Kind::f32);
    case Type::Kind::f64:
      return cast_up_float(lhs->value->f64 * rhs->value->f64, Type::Kind::f64);
    }
  }
  if (is_signed(lhs->kind) && is_signed(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind));
    return cast_up_signed(get_value(*lhs->value, lhs->kind) *
                              get_value(*rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_signed(lhs->kind) && is_unsigned(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind - 4));
    return cast_up_signed(get_value(*lhs->value, lhs->kind) *
                              get_value(*rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_unsigned(lhs->kind) && is_signed(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind - 4, (unsigned int)rhs->kind));
    return cast_up_signed(get_value(*lhs->value, lhs->kind) *
                              get_value(*rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_unsigned(lhs->kind) && is_unsigned(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind));
    return cast_up_unsigned(get_value(*lhs->value, lhs->kind) *
                                get_value(*rhs->value, rhs->kind),
                            max_kind);
  }
  if (is_float(lhs->kind) || is_float(rhs->kind)) {
    ConstexprResult casted_result;
    ConstexprResult result_other;
    if (is_unsigned(lhs->kind)) {
      casted_result = simple_unsigned_to_float(*lhs->value, lhs->kind);
      result_other = {*rhs->value, rhs->kind};
    } else if (is_unsigned(rhs->kind)) {
      result_other = {*lhs->value, lhs->kind};
      casted_result = simple_unsigned_to_float(*rhs->value, rhs->kind);
    } else if (is_signed(lhs->kind)) {
      casted_result = simple_signed_to_float(*lhs->value, lhs->kind);
      result_other = {*rhs->value, rhs->kind};
    } else if (is_signed(rhs->kind)) {
      result_other = {*lhs->value, lhs->kind};
      casted_result = simple_signed_to_float(*rhs->value, rhs->kind);
    } else if (is_float(lhs->kind) && is_float(rhs->kind)) {
      casted_result = {*lhs->value, lhs->kind};
      result_other = {*rhs->value, rhs->kind};
    }
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)casted_result.kind, (unsigned int)result_other.kind));
    return cast_up_float(get_value(*casted_result.value, casted_result.kind) *
                             get_value(*result_other.value, result_other.kind),
                         max_kind);
  }
}

std::optional<ConstexprResult> add(const std::optional<ConstexprResult> &lhs,
                                   const std::optional<ConstexprResult> &rhs) {
  if (!lhs || !lhs->value || !rhs || !rhs->value)
    return std::nullopt;
  ConstexprResult ret_res;
  if (lhs->kind == rhs->kind) {
    switch (lhs->kind) {
    case Type::Kind::Bool: {
      std::optional<bool> b_lhs = to_bool(lhs);
      std::optional<bool> b_rhs = to_bool(rhs);
      ret_res.kind = Type::Kind::Bool;
      if (b_lhs && b_rhs) {
        ret_res.value->b8 = *b_lhs + *b_rhs;
      }
      return ret_res;
    } break;
    case Type::Kind::i8:
      return cast_up_signed(lhs->value->i8 + rhs->value->i8, Type::Kind::i8);
    case Type::Kind::i16:
      return cast_up_signed(lhs->value->i16 + rhs->value->i16, Type::Kind::i16);
    case Type::Kind::i32:
      return cast_up_signed(lhs->value->i32 + rhs->value->i32, Type::Kind::i32);
    case Type::Kind::i64:
      return cast_up_signed(lhs->value->i64 + rhs->value->i64, Type::Kind::i64);
    case Type::Kind::u8:
      return cast_up_unsigned(lhs->value->u8 + rhs->value->u8, Type::Kind::u8);
    case Type::Kind::u16:
      return cast_up_unsigned(lhs->value->u16 + rhs->value->u16,
                              Type::Kind::u16);
    case Type::Kind::u32:
      return cast_up_unsigned(lhs->value->u32 + rhs->value->u32,
                              Type::Kind::u32);
    case Type::Kind::u64:
      return cast_up_unsigned(lhs->value->u64 + rhs->value->u64,
                              Type::Kind::u64);
    case Type::Kind::f32:
      return cast_up_float(lhs->value->f32 + rhs->value->f32, Type::Kind::f32);
    case Type::Kind::f64:
      return cast_up_float(lhs->value->f64 + rhs->value->f64, Type::Kind::f64);
    }
  }
  if (is_signed(lhs->kind) && is_signed(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind));
    return cast_up_signed(get_value(*lhs->value, lhs->kind) +
                              get_value(*rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_signed(lhs->kind) && is_unsigned(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind - 4));
    return cast_up_signed(get_value(*lhs->value, lhs->kind) +
                              get_value(*rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_unsigned(lhs->kind) && is_signed(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind - 4, (unsigned int)rhs->kind));
    return cast_up_signed(get_value(*lhs->value, lhs->kind) +
                              get_value(*rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_unsigned(lhs->kind) && is_unsigned(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind));
    return cast_up_unsigned(get_value(*lhs->value, lhs->kind) +
                                get_value(*rhs->value, rhs->kind),
                            max_kind);
  }
  if (is_float(lhs->kind) || is_float(rhs->kind)) {
    ConstexprResult casted_result;
    ConstexprResult result_other;
    if (is_unsigned(lhs->kind)) {
      casted_result = simple_unsigned_to_float(*lhs->value, lhs->kind);
      result_other = {*rhs->value, rhs->kind};
    } else if (is_unsigned(rhs->kind)) {
      result_other = {*lhs->value, lhs->kind};
      casted_result = simple_unsigned_to_float(*rhs->value, rhs->kind);
    } else if (is_signed(lhs->kind)) {
      casted_result = simple_signed_to_float(*lhs->value, lhs->kind);
      result_other = {*rhs->value, rhs->kind};
    } else if (is_signed(rhs->kind)) {
      result_other = {*lhs->value, lhs->kind};
      casted_result = simple_signed_to_float(*rhs->value, rhs->kind);
    } else if (is_float(lhs->kind) && is_float(rhs->kind)) {
      casted_result = {*lhs->value, lhs->kind};
      result_other = {*rhs->value, rhs->kind};
    }
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)casted_result.kind, (unsigned int)result_other.kind));
    return cast_up_float(get_value(*casted_result.value, casted_result.kind) +
                             get_value(*result_other.value, result_other.kind),
                         max_kind);
  }
}

std::optional<ConstexprResult> sub(const std::optional<ConstexprResult> &lhs,
                                   const std::optional<ConstexprResult> &rhs) {
  if (!lhs || !lhs->value || !rhs || !rhs->value)
    return std::nullopt;
  ConstexprResult ret_res;
  if (lhs->kind == rhs->kind) {
    switch (lhs->kind) {
    case Type::Kind::Bool: {
      std::optional<bool> b_lhs = to_bool(lhs);
      std::optional<bool> b_rhs = to_bool(rhs);
      ret_res.kind = Type::Kind::Bool;
      if (b_lhs && b_rhs) {
        ret_res.value->b8 = *b_lhs - *b_rhs;
      }
      return ret_res;
    } break;
    case Type::Kind::i8:
      return cast_up_signed(lhs->value->i8 - rhs->value->i8, Type::Kind::i8);
    case Type::Kind::i16:
      return cast_up_signed(lhs->value->i16 - rhs->value->i16, Type::Kind::i16);
    case Type::Kind::i32:
      return cast_up_signed(lhs->value->i32 - rhs->value->i32, Type::Kind::i32);
    case Type::Kind::i64:
      return cast_up_signed(lhs->value->i64 - rhs->value->i64, Type::Kind::i64);
    case Type::Kind::u8:
      return cast_up_unsigned(lhs->value->u8 - rhs->value->u8, Type::Kind::u8);
    case Type::Kind::u16:
      return cast_up_unsigned(lhs->value->u16 - rhs->value->u16,
                              Type::Kind::u16);
    case Type::Kind::u32:
      return cast_up_unsigned(lhs->value->u32 - rhs->value->u32,
                              Type::Kind::u32);
    case Type::Kind::u64:
      return cast_up_unsigned(lhs->value->u64 - rhs->value->u64,
                              Type::Kind::u64);
    case Type::Kind::f32:
      return cast_up_float(lhs->value->f32 - rhs->value->f32, Type::Kind::f32);
    case Type::Kind::f64:
      return cast_up_float(lhs->value->f64 - rhs->value->f64, Type::Kind::f64);
    }
  }
  if (is_signed(lhs->kind) && is_signed(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind));
    return cast_up_signed(get_value(*lhs->value, lhs->kind) -
                              get_value(*rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_signed(lhs->kind) && is_unsigned(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind - 4));
    return cast_up_signed(get_value(*lhs->value, lhs->kind) -
                              get_value(*rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_unsigned(lhs->kind) && is_signed(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind - 4, (unsigned int)rhs->kind));
    return cast_up_signed(get_value(*lhs->value, lhs->kind) -
                              get_value(*rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_unsigned(lhs->kind) && is_unsigned(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind));
    return cast_up_unsigned(get_value(*lhs->value, lhs->kind) -
                                get_value(*rhs->value, rhs->kind),
                            max_kind);
  }
  if (is_float(lhs->kind) || is_float(rhs->kind)) {
    ConstexprResult casted_result;
    ConstexprResult result_other;
    if (is_unsigned(lhs->kind)) {
      casted_result = simple_unsigned_to_float(*lhs->value, lhs->kind);
      result_other = {*rhs->value, rhs->kind};
    } else if (is_unsigned(rhs->kind)) {
      result_other = {*lhs->value, lhs->kind};
      casted_result = simple_unsigned_to_float(*rhs->value, rhs->kind);
    } else if (is_signed(lhs->kind)) {
      casted_result = simple_signed_to_float(*lhs->value, lhs->kind);
      result_other = {*rhs->value, rhs->kind};
    } else if (is_signed(rhs->kind)) {
      result_other = {*lhs->value, lhs->kind};
      casted_result = simple_signed_to_float(*rhs->value, rhs->kind);
    } else if (is_float(lhs->kind) && is_float(rhs->kind)) {
      casted_result = {*lhs->value, lhs->kind};
      result_other = {*rhs->value, rhs->kind};
    }
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)casted_result.kind, (unsigned int)result_other.kind));
    return cast_up_float(get_value(*casted_result.value, casted_result.kind) -
                             get_value(*result_other.value, result_other.kind),
                         max_kind);
  }
}

std::optional<ConstexprResult> div(const std::optional<ConstexprResult> &lhs,
                                   const std::optional<ConstexprResult> &rhs) {
  if (!lhs || !lhs->value || !rhs || !rhs->value)
    return std::nullopt;
  ConstexprResult ret_res;
  if (lhs->kind == rhs->kind) {
    switch (lhs->kind) {
    case Type::Kind::i8:
      return cast_up_signed(lhs->value->i8 / rhs->value->i8, Type::Kind::i8);
    case Type::Kind::i16:
      return cast_up_signed(lhs->value->i16 / rhs->value->i16, Type::Kind::i16);
    case Type::Kind::i32:
      return cast_up_signed(lhs->value->i32 / rhs->value->i32, Type::Kind::i32);
    case Type::Kind::i64:
      return cast_up_signed(lhs->value->i64 / rhs->value->i64, Type::Kind::i64);
    case Type::Kind::u8:
      return cast_up_unsigned(lhs->value->u8 / rhs->value->u8, Type::Kind::u8);
    case Type::Kind::u16:
      return cast_up_unsigned(lhs->value->u16 / rhs->value->u16,
                              Type::Kind::u16);
    case Type::Kind::u32:
      return cast_up_unsigned(lhs->value->u32 / rhs->value->u32,
                              Type::Kind::u32);
    case Type::Kind::u64:
      return cast_up_unsigned(lhs->value->u64 / rhs->value->u64,
                              Type::Kind::u64);
    case Type::Kind::f32:
      return cast_up_float(lhs->value->f32 / rhs->value->f32, Type::Kind::f32);
    case Type::Kind::f64:
      return cast_up_float(lhs->value->f64 / rhs->value->f64, Type::Kind::f64);
    }
  }
  if (is_signed(lhs->kind) && is_signed(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind));
    return cast_up_signed(get_value(*lhs->value, lhs->kind) -
                              get_value(*rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_signed(lhs->kind) && is_unsigned(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind - 4));
    return cast_up_signed(get_value(*lhs->value, lhs->kind) -
                              get_value(*rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_unsigned(lhs->kind) && is_signed(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind - 4, (unsigned int)rhs->kind));
    return cast_up_signed(get_value(*lhs->value, lhs->kind) -
                              get_value(*rhs->value, rhs->kind),
                          max_kind);
  }
  if (is_unsigned(lhs->kind) && is_unsigned(rhs->kind)) {
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)lhs->kind, (unsigned int)rhs->kind));
    return cast_up_unsigned(get_value(*lhs->value, lhs->kind) -
                                get_value(*rhs->value, rhs->kind),
                            max_kind);
  }
  if (is_float(lhs->kind) || is_float(rhs->kind)) {
    ConstexprResult casted_result;
    ConstexprResult result_other;
    if (is_unsigned(lhs->kind)) {
      casted_result = simple_unsigned_to_float(*lhs->value, lhs->kind);
      result_other = {*rhs->value, rhs->kind};
    } else if (is_unsigned(rhs->kind)) {
      result_other = {*lhs->value, lhs->kind};
      casted_result = simple_unsigned_to_float(*rhs->value, rhs->kind);
    } else if (is_signed(lhs->kind)) {
      casted_result = simple_signed_to_float(*lhs->value, lhs->kind);
      result_other = {*rhs->value, rhs->kind};
    } else if (is_signed(rhs->kind)) {
      result_other = {*lhs->value, lhs->kind};
      casted_result = simple_signed_to_float(*rhs->value, rhs->kind);
    } else if (is_float(lhs->kind) && is_float(rhs->kind)) {
      casted_result = {*lhs->value, lhs->kind};
      result_other = {*rhs->value, rhs->kind};
    }
    Type::Kind max_kind = (Type::Kind)(std::max<unsigned int>(
        (unsigned int)casted_result.kind, (unsigned int)result_other.kind));
    return cast_up_float(get_value(*casted_result.value, casted_result.kind) -
                             get_value(*result_other.value, result_other.kind),
                         max_kind);
  }
}

std::optional<ConstexprResult> ConstantExpressionEvaluator::eval_binary_op(
    const ResolvedBinaryOperator &binop) {
  std::optional<ConstexprResult> lhs = evaluate(*binop.lhs);
  ConstexprResult return_value;
  if (binop.op == TokenKind::PipePipe) {
    return_value.kind = Type::Kind::Bool;
    if (to_bool(lhs).value_or(false)) {
      return_value.value->b8 = true;
      return return_value;
    }
    auto val = to_bool(evaluate(*binop.rhs));
    if (val) {
      return_value.value->b8 = *val;
      return return_value;
    }
    return std::nullopt;
  }
  if (binop.op == TokenKind::AmpAmp) {
    return_value.kind = Type::Kind::Bool;
    if (!to_bool(lhs).value_or(true)) {
      return_value.value->b8 = false;
      return return_value;
    }
    std::optional<ConstexprResult> rhs = evaluate(*binop.rhs);
    if (!lhs || !lhs->value) {
      if (!rhs || rhs->value) {
        return rhs;
      }
      return std::nullopt;
    }
    std::optional<bool> maybe_val = to_bool(rhs);
    if (maybe_val)
      return_value.value->b8 = *maybe_val;
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
  default:
    assert(binop.op == TokenKind::EqualEqual && "unexpected binary operator");
    return_value.kind = Type::Kind::Bool;
    return_value.value->b8 = lhs->value->b8 == rhs->value->b8;
    return return_value;
  }
}

std::optional<ConstexprResult>
ConstantExpressionEvaluator::eval_unary_op(const ResolvedUnaryOperator &unop) {
  std::optional<ConstexprResult> rhs = evaluate(*unop.rhs);
  if (!rhs)
    return std::nullopt;
  ConstexprResult result;
  if (unop.op == TokenKind::Exclamation) {
    result.kind = Type::Kind::Bool;
    result.value->b8 = !*to_bool(rhs);
    return result;
  }
  if (unop.op == TokenKind::Minus) {
    switch (rhs->kind) {
    case Type::Kind::i8:
    case Type::Kind::u8:
      result.kind = Type::Kind::i8;
      result.value->i8 = rhs->kind == Type::Kind::i8
                             ? -rhs->value->i8
                             : -static_cast<std::int8_t>(rhs->value->u8);
      break;
    case Type::Kind::i16:
    case Type::Kind::u16:
      result.kind = Type::Kind::i16;
      result.value->i16 = rhs->kind == Type::Kind::i16
                              ? -rhs->value->i16
                              : -static_cast<std::int16_t>(rhs->value->u16);
      break;
    case Type::Kind::i32:
    case Type::Kind::u32:
      result.kind = Type::Kind::i32;
      result.value->i32 = rhs->kind == Type::Kind::i32
                              ? -rhs->value->i32
                              : -static_cast<std::int32_t>(rhs->value->u32);
      break;
    case Type::Kind::i64:
    case Type::Kind::u64:
      result.kind = Type::Kind::i64;
      result.value->i64 = rhs->kind == Type::Kind::i64
                              ? -rhs->value->i64
                              : -static_cast<std::int64_t>(rhs->value->u64);
      break;
    case Type::Kind::f32:
      result.kind = Type::Kind::f32;
      result.value->f32 = -rhs->value->f32;
      break;
    case Type::Kind::f64:
      result.kind = Type::Kind::f64;
      result.value->f64 = -rhs->value->f64;
      break;
    }
  }
  return result;
}

std::optional<ConstexprResult>
ConstantExpressionEvaluator::evaluate(const ResolvedExpr &expr) {
  if (std::optional<ConstexprResult> res = expr.get_constant_value())
    return res;
  if (const auto *numlit = dynamic_cast<const ResolvedNumberLiteral *>(&expr)) {
    ConstexprResult res{numlit->value, numlit->type.kind};
    return res;
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
