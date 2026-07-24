import types;
import token;
import value;

// An enum acts as its base integer type in arithmetic/bitwise/shift; comparisons keep the enum type.
fn types::Ty* enum_base_or_self(types::Ty* t) {
    if(t.kind == types::TypeKind::Enum) { return types::enum_base_type(t); }
    return t;
}

export fn types::Ty* binop_result_type(token::TokenKind op, types::Ty* lt, types::Ty* rt) {
    if(lt == null || rt == null) { return null; }
    types::Ty* base_lt = enum_base_or_self(lt);
    types::Ty* base_rt = enum_base_or_self(rt);
    switch(op) {
    case token::TokenKind::Plus: {
        if(types::is_ptr(base_lt) && types::is_int(base_rt)) { return base_lt; }   // ptr + int
        if(types::is_int(base_lt) && types::is_ptr(base_rt)) { return base_rt; }   // int + ptr
        return arithmetic_result(base_lt, base_rt);
    }
    case token::TokenKind::Minus: {
        if(types::is_ptr(base_lt) && types::is_int(base_rt)) { return base_lt; }   // ptr - int
        if(types::is_ptr(base_lt) && types::is_ptr(base_rt)) { return types::prim_i64(); }   // ptr - ptr: element count
        return arithmetic_result(base_lt, base_rt);
    }
    case token::TokenKind::Star:
    case token::TokenKind::Slash:
    case token::TokenKind::Percent: {
        return arithmetic_result(base_lt, base_rt);
    }
    case token::TokenKind::Amp:
    case token::TokenKind::Pipe:
    case token::TokenKind::Caret: {
        if(types::is_int(base_lt) && types::is_int(base_rt)) { return int_common(base_lt, base_rt); }
        return null;
    }
    case token::TokenKind::LShift:
    case token::TokenKind::RShift: {
        if(types::is_int(base_lt) && types::is_int(base_rt)) { return base_lt; }
        return null;
    }
    case token::TokenKind::EqEq:
    case token::TokenKind::BangEq: {
        if(comparable_eq(lt, rt)) { return types::prim_bool(); }
        return null;
    }
    case token::TokenKind::LT:
    case token::TokenKind::GT:
    case token::TokenKind::LTEQ:
    case token::TokenKind::GTEQ: {
        if(comparable_order(lt, rt)) { return types::prim_bool(); }
        return null;
    }
    case token::TokenKind::AmpAmp:
    case token::TokenKind::PipePipe: {
        // Truthy operands (bool/int/ptr/slice), consistent with `if` and `!`; lowering's to_bool converts each.
        if(types::is_convertible_in_cond(lt) && types::is_convertible_in_cond(rt)) { return types::prim_bool(); }
        return null;
    }
    else { return null; }
    }
    return null;
}

export fn types::Ty* unaryop_result_type(token::TokenKind op, types::Ty* operand) {
    if(operand == null) { return null; }
    types::Ty* base = enum_base_or_self(operand);
    switch(op) {
    case token::TokenKind::Minus: {
        if(types::is_int(base) || types::is_float(base)) { return base; }
        return null;
    }
    case token::TokenKind::Bang: {
        if(types::is_convertible_in_cond(operand)) { return types::prim_bool(); }
        return null;
    }
    case token::TokenKind::Tilde: {
        if(types::is_int(base)) { return base; }
        return null;
    }
    case token::TokenKind::Amp: {
        return types::intern_pointer(operand, false);
    }
    case token::TokenKind::Star: {
        if(types::is_ptr(operand)) { return operand.data.pointee; }
        return null;
    }
    else { return null; }
    }
    return null;
}

export fn value::Value binop_eval(token::TokenKind op, value::Value l, value::Value r) {
    if(l.kind == value::ValueKind::Error) { return l; }
    if(r.kind == value::ValueKind::Error) { return r; }
    types::Ty* rt = binop_result_type(op, l.ty, r.ty);

    if(op == token::TokenKind::EqEq)  { return val_eq(l, r, false); }
    if(op == token::TokenKind::BangEq) { return val_eq(l, r, true); }
    if(op == token::TokenKind::LT || op == token::TokenKind::GT || op == token::TokenKind::LTEQ || op == token::TokenKind::GTEQ) {
        return val_order(op, l, r);
    }
    if(op == token::TokenKind::AmpAmp) {
        if(l.kind == value::ValueKind::Bool && r.kind == value::ValueKind::Bool) { return value::val_bool(l.data.b && r.data.b); }
        return value::val_error();
    }
    if(op == token::TokenKind::PipePipe) {
        if(l.kind == value::ValueKind::Bool && r.kind == value::ValueKind::Bool) { return value::val_bool(l.data.b || r.data.b); }
        return value::val_error();
    }
    if(l.kind == value::ValueKind::Float && r.kind == value::ValueKind::Float) {
        return float_arith(op, l.data.f, r.data.f, rt);
    }
    if(l.kind == value::ValueKind::Int && r.kind == value::ValueKind::Int) {
        return int_arith(op, l.data.i, r.data.i, rt);
    }
    return value::val_error();
}

export fn value::Value unaryop_eval(token::TokenKind op, value::Value v) {
    if(v.kind == value::ValueKind::Error) { return v; }
    if(op == token::TokenKind::Minus) {
        if(v.kind == value::ValueKind::Int) { return value::val_int(-v.data.i, v.ty); }
        if(v.kind == value::ValueKind::Float) { return value::val_float(-v.data.f, v.ty); }
        return value::val_error();
    }
    if(op == token::TokenKind::Bang) {
        if(v.kind == value::ValueKind::Bool) { return value::val_bool(!v.data.b); }
        return value::val_error();
    }
    if(op == token::TokenKind::Tilde) {
        if(v.kind == value::ValueKind::Int) { return value::val_int(~v.data.i, v.ty); }
        return value::val_error();
    }
    return value::val_error();
}

// PRIVATE

fn types::Ty* arithmetic_result(types::Ty* lt, types::Ty* rt) {
    if(types::is_int(lt) && types::is_int(rt)) { return int_common(lt, rt); }
    if(types::is_float(lt) && types::is_float(rt)) {
        if(lt.size >= rt.size) { return lt; }
        return rt;
    }
    return null;
}

fn types::Ty* int_common(types::Ty* lt, types::Ty* rt) {
    if(types::is_signed_int(lt) != types::is_signed_int(rt)) { return null; }
    if(lt.size >= rt.size) { return lt; }
    return rt;
}

fn bool comparable_eq(types::Ty* lt, types::Ty* rt) {
    types::Ty* l = enum_base_or_self(lt);
    types::Ty* r = enum_base_or_self(rt);
    if(arithmetic_result(l, r) != null) { return true; }
    if(types::is_ptr(l) && types::is_ptr(r)) { return true; }
    if(types::is_bool(l) && types::is_bool(r)) { return true; }
    return lt == rt;
}

fn bool comparable_order(types::Ty* lt, types::Ty* rt) {
    types::Ty* l = enum_base_or_self(lt);
    types::Ty* r = enum_base_or_self(rt);
    if(arithmetic_result(l, r) != null) { return true; }
    return types::is_ptr(l) && types::is_ptr(r);
}

fn value::Value val_eq(value::Value l, value::Value r, bool negate) {
    bool eq = false;
    if(l.kind == value::ValueKind::Int && r.kind == value::ValueKind::Int) { eq = l.data.i == r.data.i; }
    else if(l.kind == value::ValueKind::Float && r.kind == value::ValueKind::Float) { eq = l.data.f == r.data.f; }
    else if(l.kind == value::ValueKind::Bool && r.kind == value::ValueKind::Bool) { eq = l.data.b == r.data.b; }
    else if(l.kind == value::ValueKind::TYPE && r.kind == value::ValueKind::TYPE) { eq = l.data.type_ref == r.data.type_ref; }
    else if(l.kind == value::ValueKind::Null && r.kind == value::ValueKind::Null) { eq = true; }
    else { return value::val_error(); }
    if(negate) { eq = !eq; }
    return value::val_bool(eq);
}

fn value::Value val_order(token::TokenKind op, value::Value l, value::Value r) {
    bool result = false;
    if(l.kind == value::ValueKind::Int && r.kind == value::ValueKind::Int) {
        bool is_signed = true;
        if(l.ty != null) { is_signed = types::is_signed_int(l.ty); }
        if(is_signed) { result = order_cmp_i(op, l.data.i, r.data.i); } else { result = order_cmp_u(op, (u64)l.data.i, (u64)r.data.i); }
    } else if(l.kind == value::ValueKind::Float && r.kind == value::ValueKind::Float) {
        result = order_cmp_f(op, l.data.f, r.data.f);
    } else {
        return value::val_error();
    }
    return value::val_bool(result);
}

fn bool order_cmp_i(token::TokenKind op, i64 a, i64 b) {
    if(op == token::TokenKind::LT) { return a < b; }
    if(op == token::TokenKind::GT) { return a > b; }
    if(op == token::TokenKind::LTEQ) { return a <= b; }
    return a >= b;
}

fn bool order_cmp_u(token::TokenKind op, u64 a, u64 b) {
    if(op == token::TokenKind::LT) { return a < b; }
    if(op == token::TokenKind::GT) { return a > b; }
    if(op == token::TokenKind::LTEQ) { return a <= b; }
    return a >= b;
}

fn bool order_cmp_f(token::TokenKind op, f64 a, f64 b) {
    if(op == token::TokenKind::LT) { return a < b; }
    if(op == token::TokenKind::GT) { return a > b; }
    if(op == token::TokenKind::LTEQ) { return a <= b; }
    return a >= b;
}

export fn i64 wrap_to_type(i64 v, types::Ty* t) {
    return wrap_int(v, int_bits(t), types::is_signed_int(t));
}

// Two's-complement wrap of a computed result into the operand type's bit width.
fn i64 wrap_int(i64 v, u32 bits, bool is_signed) {
    if(bits >= 64) { return v; }
    u64 mask = ((u64)1 << bits) - 1;
    u64 masked = (u64)v & mask;
    if(is_signed) {
        u64 sign_bit = (u64)1 << (bits - 1);
        if((masked & sign_bit) != 0) { masked = masked | (~mask); }
    }
    return (i64)masked;
}

fn u32 int_bits(types::Ty* t) {
    if(t == null) { return 64; }
    u32 b = t.size * 8;
    if(b == 0 || b > 64) { return 64; }
    return b;
}

fn value::Value int_arith(token::TokenKind op, i64 a, i64 b, types::Ty* rt) {
    bool is_signed = true;
    if(rt != null) { is_signed = types::is_signed_int(rt); }
    u32 bits = int_bits(rt);
    if(op == token::TokenKind::Plus)    { return value::val_int(wrap_int(a + b, bits, is_signed), rt); }
    if(op == token::TokenKind::Minus)   { return value::val_int(wrap_int(a - b, bits, is_signed), rt); }
    if(op == token::TokenKind::Star)    { return value::val_int(wrap_int(a * b, bits, is_signed), rt); }
    if(op == token::TokenKind::Slash) {
        if(b == 0) { return value::val_error(); }
        i64 result = a / b;
        if(!is_signed) { result = (i64)((u64)a / (u64)b); }
        return value::val_int(wrap_int(result, bits, is_signed), rt);
    }
    if(op == token::TokenKind::Percent) {
        if(b == 0) { return value::val_error(); }
        i64 result = a % b;
        if(!is_signed) { result = (i64)((u64)a % (u64)b); }
        return value::val_int(wrap_int(result, bits, is_signed), rt);
    }
    if(op == token::TokenKind::Amp)     { return value::val_int(wrap_int(a & b, bits, is_signed), rt); }
    if(op == token::TokenKind::Pipe)    { return value::val_int(wrap_int(a | b, bits, is_signed), rt); }
    if(op == token::TokenKind::Caret)   { return value::val_int(wrap_int(a ^ b, bits, is_signed), rt); }
    if(op == token::TokenKind::LShift)  { if(b < 0 || b >= 64) { return value::val_error(); } return value::val_int(wrap_int(a << b, bits, is_signed), rt); }
    if(op == token::TokenKind::RShift) {
        if(b < 0 || b >= 64) { return value::val_error(); }
        i64 result = a >> b;
        if(!is_signed) { result = (i64)((u64)a >> (u64)b); }
        return value::val_int(wrap_int(result, bits, is_signed), rt);
    }
    return value::val_error();
}

fn value::Value float_arith(token::TokenKind op, f64 a, f64 b, types::Ty* rt) {
    if(op == token::TokenKind::Plus)  { return value::val_float(a + b, rt); }
    if(op == token::TokenKind::Minus) { return value::val_float(a - b, rt); }
    if(op == token::TokenKind::Star)  { return value::val_float(a * b, rt); }
    if(op == token::TokenKind::Slash) { return value::val_float(a / b, rt); }
    return value::val_error();
}
