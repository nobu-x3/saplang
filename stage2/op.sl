import types;
import token;

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
