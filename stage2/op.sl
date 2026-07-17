import types;
import token;
import value;

export fn types::Type* binop_result_type(token::TokenKind op, types::Type* lt, types::Type* rt) {
    if(lt == null || rt == null) { return null; }
    switch(op) {
    case token::TokenKind::Plus:
    case token::TokenKind::Minus:
    case token::TokenKind::Star:
    case token::TokenKind::Slash:
    case token::TokenKind::Percent: {
        return arithmetic_result(lt, rt);
    }
    case token::TokenKind::Amp:
    case token::TokenKind::Pipe:
    case token::TokenKind::Caret: {
        if(types::is_int(lt) && types::is_int(rt)) { return int_common(lt, rt); }
        return null;
    }
    case token::TokenKind::LShift:
    case token::TokenKind::RShift: {
        if(types::is_int(lt) && types::is_int(rt)) { return lt; }
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
        if(types::is_bool(lt) && types::is_bool(rt)) { return types::prim_bool(); }
        return null;
    }
    else { return null; }
    }
    return null;
}

export fn types::Type* unaryop_result_type(token::TokenKind op, types::Type* operand) {
    if(operand == null) { return null; }
    switch(op) {
    case token::TokenKind::Minus: {
        if(types::is_int(operand) || types::is_float(operand)) { return operand; }
        return null;
    }
    case token::TokenKind::Bang: {
        if(types::is_convertible_in_cond(operand)) { return types::prim_bool(); }
        return null;
    }
    case token::TokenKind::Tilde: {
        if(types::is_int(operand)) { return operand; }
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
    types::Type* rt = binop_result_type(op, l.ty, r.ty);

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

fn types::Type* arithmetic_result(types::Type* lt, types::Type* rt) {
    if(types::is_int(lt) && types::is_int(rt)) { return int_common(lt, rt); }
    if(types::is_float(lt) && types::is_float(rt)) {
        if(lt.size >= rt.size) { return lt; }
        return rt;
    }
    return null;
}

fn types::Type* int_common(types::Type* lt, types::Type* rt) {
    if(types::is_signed_int(lt) != types::is_signed_int(rt)) { return null; }
    if(lt.size >= rt.size) { return lt; }
    return rt;
}

fn bool comparable_eq(types::Type* lt, types::Type* rt) {
    if(arithmetic_result(lt, rt) != null) { return true; }
    if(types::is_ptr(lt) && types::is_ptr(rt)) { return true; }
    if(types::is_bool(lt) && types::is_bool(rt)) { return true; }
    return lt == rt;
}

fn bool comparable_order(types::Type* lt, types::Type* rt) {
    if(arithmetic_result(lt, rt) != null) { return true; }
    return types::is_ptr(lt) && types::is_ptr(rt);
}

fn value::Value val_eq(value::Value l, value::Value r, bool negate) {
    bool eq = false;
    if(l.kind == value::ValueKind::Int && r.kind == value::ValueKind::Int) { eq = l.data.i == r.data.i; }
    else if(l.kind == value::ValueKind::Float && r.kind == value::ValueKind::Float) { eq = l.data.f == r.data.f; }
    else if(l.kind == value::ValueKind::Bool && r.kind == value::ValueKind::Bool) { eq = l.data.b == r.data.b; }
    else if(l.kind == value::ValueKind::Type && r.kind == value::ValueKind::Type) { eq = l.data.type_ref == r.data.type_ref; }
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

export fn i64 wrap_to_type(i64 v, types::Type* t) {
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

fn u32 int_bits(types::Type* t) {
    if(t == null) { return 64; }
    u32 b = t.size * 8;
    if(b == 0 || b > 64) { return 64; }
    return b;
}

fn value::Value int_arith(token::TokenKind op, i64 a, i64 b, types::Type* rt) {
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

fn value::Value float_arith(token::TokenKind op, f64 a, f64 b, types::Type* rt) {
    if(op == token::TokenKind::Plus)  { return value::val_float(a + b, rt); }
    if(op == token::TokenKind::Minus) { return value::val_float(a - b, rt); }
    if(op == token::TokenKind::Star)  { return value::val_float(a * b, rt); }
    if(op == token::TokenKind::Slash) { return value::val_float(a / b, rt); }
    return value::val_error();
}
