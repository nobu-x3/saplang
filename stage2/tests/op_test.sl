import testing;
import op;
import types;
import token;
import arena;

fn i32 arith_add_i32_i32(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::Plus, types::prim_i32(), types::prim_i32());
    if(!testing::expect_eq((void*)r, (void*)types::prim_i32(), m)) { return -1; }
    return 0;
}

fn i32 arith_all_ops_i32(arena::Arena* a, u8[] m) {
    token::TokenKind[4] ops; ops[0] = token::TokenKind::Minus; ops[1] = token::TokenKind::Star; ops[2] = token::TokenKind::Slash; ops[3] = token::TokenKind::Percent;
    for(u64 i = 0; i < 4; i += 1) {
        types::Type* r = op::binop_result_type(ops[i], types::prim_i32(), types::prim_i32());
        if(!testing::expect_eq((void*)r, (void*)types::prim_i32(), m)) { return -1; }
    }
    return 0;
}

fn i32 arith_widen_i16_i32(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::Plus, types::prim_i16(), types::prim_i32());
    if(!testing::expect_eq((void*)r, (void*)types::prim_i32(), m)) { return -1; }
    return 0;
}

fn i32 arith_widen_i32_i16(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::Plus, types::prim_i32(), types::prim_i16());
    if(!testing::expect_eq((void*)r, (void*)types::prim_i32(), m)) { return -1; }
    return 0;
}

fn i32 arith_u8_u8(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::Star, types::prim_u8(), types::prim_u8());
    if(!testing::expect_eq((void*)r, (void*)types::prim_u8(), m)) { return -1; }
    return 0;
}

fn i32 arith_mixed_sign_null(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::Plus, types::prim_i32(), types::prim_u32());
    if(!testing::expect_eq((void*)r, null, m)) { return -1; }
    return 0;
}

fn i32 arith_f32_f32(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::Plus, types::prim_f32(), types::prim_f32());
    if(!testing::expect_eq((void*)r, (void*)types::prim_f32(), m)) { return -1; }
    return 0;
}

fn i32 arith_f32_f64_widens(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::Plus, types::prim_f32(), types::prim_f64());
    if(!testing::expect_eq((void*)r, (void*)types::prim_f64(), m)) { return -1; }
    return 0;
}

fn i32 arith_f64_f32_widens(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::Plus, types::prim_f64(), types::prim_f32());
    if(!testing::expect_eq((void*)r, (void*)types::prim_f64(), m)) { return -1; }
    return 0;
}

fn i32 arith_int_float_null(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::Plus, types::prim_i32(), types::prim_f32());
    if(!testing::expect_eq((void*)r, null, m)) { return -1; }
    return 0;
}

fn i32 arith_bool_null(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::Plus, types::prim_bool(), types::prim_bool());
    if(!testing::expect_eq((void*)r, null, m)) { return -1; }
    return 0;
}

fn i32 arith_null_operand(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::Plus, null, types::prim_i32());
    if(!testing::expect_eq((void*)r, null, m)) { return -1; }
    return 0;
}

fn i32 bit_and_i32(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::Amp, types::prim_i32(), types::prim_i32());
    if(!testing::expect_eq((void*)r, (void*)types::prim_i32(), m)) { return -1; }
    return 0;
}

fn i32 bit_widen_i8_i32(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::Pipe, types::prim_i8(), types::prim_i32());
    if(!testing::expect_eq((void*)r, (void*)types::prim_i32(), m)) { return -1; }
    return 0;
}

fn i32 bit_mixed_sign_null(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::Amp, types::prim_i32(), types::prim_u32());
    if(!testing::expect_eq((void*)r, null, m)) { return -1; }
    return 0;
}

fn i32 bit_float_null(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::Caret, types::prim_i32(), types::prim_f32());
    if(!testing::expect_eq((void*)r, null, m)) { return -1; }
    return 0;
}

fn i32 shift_result_is_lhs(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::LShift, types::prim_u8(), types::prim_i32());
    if(!testing::expect_eq((void*)r, (void*)types::prim_u8(), m)) { return -1; }
    return 0;
}

fn i32 shift_i32(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::RShift, types::prim_i32(), types::prim_i32());
    if(!testing::expect_eq((void*)r, (void*)types::prim_i32(), m)) { return -1; }
    return 0;
}

fn i32 shift_float_null(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::LShift, types::prim_f32(), types::prim_i32());
    if(!testing::expect_eq((void*)r, null, m)) { return -1; }
    return 0;
}

fn i32 eq_i32_is_bool(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::EqEq, types::prim_i32(), types::prim_i32());
    if(!testing::expect_eq((void*)r, (void*)types::prim_bool(), m)) { return -1; }
    return 0;
}

fn i32 eq_widen_is_bool(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::BangEq, types::prim_i16(), types::prim_i32());
    if(!testing::expect_eq((void*)r, (void*)types::prim_bool(), m)) { return -1; }
    return 0;
}

fn i32 eq_ptr_is_bool(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Type* p = types::intern_pointer(types::prim_i32(), false);
    types::Type* r = op::binop_result_type(token::TokenKind::EqEq, p, p);
    if(!testing::expect_eq((void*)r, (void*)types::prim_bool(), m)) { return -1; }
    return 0;
}

fn i32 eq_null_ptr_is_bool(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Type* p = types::intern_pointer(types::prim_i32(), false);
    types::Type* r = op::binop_result_type(token::TokenKind::EqEq, types::prim_null_ptr(), p);
    if(!testing::expect_eq((void*)r, (void*)types::prim_bool(), m)) { return -1; }
    return 0;
}

fn i32 eq_bool_is_bool(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::EqEq, types::prim_bool(), types::prim_bool());
    if(!testing::expect_eq((void*)r, (void*)types::prim_bool(), m)) { return -1; }
    return 0;
}

fn i32 eq_int_float_null(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::EqEq, types::prim_i32(), types::prim_f32());
    if(!testing::expect_eq((void*)r, null, m)) { return -1; }
    return 0;
}

fn i32 eq_mixed_sign_null(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::EqEq, types::prim_i32(), types::prim_u32());
    if(!testing::expect_eq((void*)r, null, m)) { return -1; }
    return 0;
}

fn i32 ord_i32_is_bool(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::LT, types::prim_i32(), types::prim_i32());
    if(!testing::expect_eq((void*)r, (void*)types::prim_bool(), m)) { return -1; }
    return 0;
}

fn i32 ord_float_widen_is_bool(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::GT, types::prim_f32(), types::prim_f64());
    if(!testing::expect_eq((void*)r, (void*)types::prim_bool(), m)) { return -1; }
    return 0;
}

fn i32 ord_ptr_is_bool(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Type* p = types::intern_pointer(types::prim_i32(), false);
    types::Type* r = op::binop_result_type(token::TokenKind::LTEQ, p, p);
    if(!testing::expect_eq((void*)r, (void*)types::prim_bool(), m)) { return -1; }
    return 0;
}

fn i32 ord_geeq_is_bool(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::GTEQ, types::prim_i32(), types::prim_i32());
    if(!testing::expect_eq((void*)r, (void*)types::prim_bool(), m)) { return -1; }
    return 0;
}

fn i32 ord_bool_null(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::LT, types::prim_bool(), types::prim_bool());
    if(!testing::expect_eq((void*)r, null, m)) { return -1; }
    return 0;
}

fn i32 logic_and_bool(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::AmpAmp, types::prim_bool(), types::prim_bool());
    if(!testing::expect_eq((void*)r, (void*)types::prim_bool(), m)) { return -1; }
    return 0;
}

fn i32 logic_or_bool(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::PipePipe, types::prim_bool(), types::prim_bool());
    if(!testing::expect_eq((void*)r, (void*)types::prim_bool(), m)) { return -1; }
    return 0;
}

fn i32 logic_int_null(arena::Arena* a, u8[] m) {
    types::Type* r = op::binop_result_type(token::TokenKind::AmpAmp, types::prim_i32(), types::prim_bool());
    if(!testing::expect_eq((void*)r, null, m)) { return -1; }
    return 0;
}

fn i32 neg_i32(arena::Arena* a, u8[] m) {
    types::Type* r = op::unaryop_result_type(token::TokenKind::Minus, types::prim_i32());
    if(!testing::expect_eq((void*)r, (void*)types::prim_i32(), m)) { return -1; }
    return 0;
}

fn i32 neg_f32(arena::Arena* a, u8[] m) {
    types::Type* r = op::unaryop_result_type(token::TokenKind::Minus, types::prim_f32());
    if(!testing::expect_eq((void*)r, (void*)types::prim_f32(), m)) { return -1; }
    return 0;
}

fn i32 neg_bool_null(arena::Arena* a, u8[] m) {
    types::Type* r = op::unaryop_result_type(token::TokenKind::Minus, types::prim_bool());
    if(!testing::expect_eq((void*)r, null, m)) { return -1; }
    return 0;
}

fn i32 not_bool_is_bool(arena::Arena* a, u8[] m) {
    types::Type* r = op::unaryop_result_type(token::TokenKind::Bang, types::prim_bool());
    if(!testing::expect_eq((void*)r, (void*)types::prim_bool(), m)) { return -1; }
    return 0;
}

fn i32 not_int_is_bool(arena::Arena* a, u8[] m) {
    types::Type* r = op::unaryop_result_type(token::TokenKind::Bang, types::prim_i32());
    if(!testing::expect_eq((void*)r, (void*)types::prim_bool(), m)) { return -1; }
    return 0;
}

fn i32 not_ptr_is_bool(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Type* p = types::intern_pointer(types::prim_i32(), false);
    types::Type* r = op::unaryop_result_type(token::TokenKind::Bang, p);
    if(!testing::expect_eq((void*)r, (void*)types::prim_bool(), m)) { return -1; }
    return 0;
}

fn i32 not_float_null(arena::Arena* a, u8[] m) {
    types::Type* r = op::unaryop_result_type(token::TokenKind::Bang, types::prim_f32());
    if(!testing::expect_eq((void*)r, null, m)) { return -1; }
    return 0;
}

fn i32 complement_i32(arena::Arena* a, u8[] m) {
    types::Type* r = op::unaryop_result_type(token::TokenKind::Tilde, types::prim_i32());
    if(!testing::expect_eq((void*)r, (void*)types::prim_i32(), m)) { return -1; }
    return 0;
}

fn i32 complement_float_null(arena::Arena* a, u8[] m) {
    types::Type* r = op::unaryop_result_type(token::TokenKind::Tilde, types::prim_f32());
    if(!testing::expect_eq((void*)r, null, m)) { return -1; }
    return 0;
}

fn i32 addr_of_i32(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Type* r = op::unaryop_result_type(token::TokenKind::Amp, types::prim_i32());
    types::Type* want = types::intern_pointer(types::prim_i32(), false);
    if(!testing::expect_eq((void*)r, (void*)want, m)) { return -1; }
    return 0;
}

fn i32 deref_ptr(arena::Arena* a, u8[] m) {
    types::typer_init(a, 16);
    types::Type* p = types::intern_pointer(types::prim_i32(), false);
    types::Type* r = op::unaryop_result_type(token::TokenKind::Star, p);
    if(!testing::expect_eq((void*)r, (void*)types::prim_i32(), m)) { return -1; }
    return 0;
}

fn i32 deref_non_ptr_null(arena::Arena* a, u8[] m) {
    types::Type* r = op::unaryop_result_type(token::TokenKind::Star, types::prim_i32());
    if(!testing::expect_eq((void*)r, null, m)) { return -1; }
    return 0;
}

fn i32 unary_null_operand(arena::Arena* a, u8[] m) {
    types::Type* r = op::unaryop_result_type(token::TokenKind::Minus, null);
    if(!testing::expect_eq((void*)r, null, m)) { return -1; }
    return 0;
}

fn i32 main() {
    testing::init();

    u8[] arith = "Op Arithmetic Tests";
    testing::add(arith, "arith_add_i32_i32",     &arith_add_i32_i32);
    testing::add(arith, "arith_all_ops_i32",     &arith_all_ops_i32);
    testing::add(arith, "arith_widen_i16_i32",   &arith_widen_i16_i32);
    testing::add(arith, "arith_widen_i32_i16",   &arith_widen_i32_i16);
    testing::add(arith, "arith_u8_u8",           &arith_u8_u8);
    testing::add(arith, "arith_mixed_sign_null", &arith_mixed_sign_null);
    testing::add(arith, "arith_f32_f32",         &arith_f32_f32);
    testing::add(arith, "arith_f32_f64_widens",  &arith_f32_f64_widens);
    testing::add(arith, "arith_f64_f32_widens",  &arith_f64_f32_widens);
    testing::add(arith, "arith_int_float_null",  &arith_int_float_null);
    testing::add(arith, "arith_bool_null",       &arith_bool_null);
    testing::add(arith, "arith_null_operand",    &arith_null_operand);

    u8[] bits = "Op Bitwise/Shift Tests";
    testing::add(bits, "bit_and_i32",       &bit_and_i32);
    testing::add(bits, "bit_widen_i8_i32",  &bit_widen_i8_i32);
    testing::add(bits, "bit_mixed_sign_null", &bit_mixed_sign_null);
    testing::add(bits, "bit_float_null",    &bit_float_null);
    testing::add(bits, "shift_result_is_lhs", &shift_result_is_lhs);
    testing::add(bits, "shift_i32",         &shift_i32);
    testing::add(bits, "shift_float_null",  &shift_float_null);

    u8[] cmp = "Op Comparison Tests";
    testing::add(cmp, "eq_i32_is_bool",       &eq_i32_is_bool);
    testing::add(cmp, "eq_widen_is_bool",     &eq_widen_is_bool);
    testing::add(cmp, "eq_ptr_is_bool",       &eq_ptr_is_bool);
    testing::add(cmp, "eq_null_ptr_is_bool",  &eq_null_ptr_is_bool);
    testing::add(cmp, "eq_bool_is_bool",      &eq_bool_is_bool);
    testing::add(cmp, "eq_int_float_null",    &eq_int_float_null);
    testing::add(cmp, "eq_mixed_sign_null",   &eq_mixed_sign_null);
    testing::add(cmp, "ord_i32_is_bool",      &ord_i32_is_bool);
    testing::add(cmp, "ord_float_widen_is_bool", &ord_float_widen_is_bool);
    testing::add(cmp, "ord_ptr_is_bool",      &ord_ptr_is_bool);
    testing::add(cmp, "ord_geeq_is_bool",     &ord_geeq_is_bool);
    testing::add(cmp, "ord_bool_null",        &ord_bool_null);

    u8[] logic = "Op Logical Tests";
    testing::add(logic, "logic_and_bool", &logic_and_bool);
    testing::add(logic, "logic_or_bool",  &logic_or_bool);
    testing::add(logic, "logic_int_null", &logic_int_null);

    u8[] un = "Op Unary Tests";
    testing::add(un, "neg_i32",              &neg_i32);
    testing::add(un, "neg_f32",              &neg_f32);
    testing::add(un, "neg_bool_null",        &neg_bool_null);
    testing::add(un, "not_bool_is_bool",     &not_bool_is_bool);
    testing::add(un, "not_int_is_bool",      &not_int_is_bool);
    testing::add(un, "not_ptr_is_bool",      &not_ptr_is_bool);
    testing::add(un, "not_float_null",       &not_float_null);
    testing::add(un, "complement_i32",       &complement_i32);
    testing::add(un, "complement_float_null", &complement_float_null);
    testing::add(un, "addr_of_i32",          &addr_of_i32);
    testing::add(un, "deref_ptr",            &deref_ptr);
    testing::add(un, "deref_non_ptr_null",   &deref_non_ptr_null);
    testing::add(un, "unary_null_operand",   &unary_null_operand);

    return testing::run();
}
