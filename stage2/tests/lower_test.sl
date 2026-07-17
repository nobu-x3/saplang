import testing;
import test_util;
import lower;
import sapir;
import sapir_print;
import module;
import io;
import arena;
import sys;

fn u8[] lower_and_print(arena::Arena* a, u8[] src) {
    module::Module* m = test_util::frontend(a, src);
    if(test_util::error_count(m) > 0) { return "<frontend errors>"; }
    sapir::SapirModule* sm = lower::lower_module(m);
    return sapir_print::print_module_to_arena(sm, a);
}

fn i32 straight_line_add(arena::Arena* a, u8[] msg) {
    u8[] got = lower_and_print(a, "fn i32 add(i32 x, i32 y) { i32 z = x + y; return z * 2; }");
    io::OutBuf want;
    io::outbuf_init(&want, a, 512);
    io::outbuf_write(&want, "module main\n\n");
    io::outbuf_write(&want, "fn __main_add(i32, i32) -> i32 {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = param.i32 0\n");
    io::outbuf_write(&want, "    %1 = param.i32 1\n");
    io::outbuf_write(&want, "    %2 = add.i32 %0, %1\n");
    io::outbuf_write(&want, "    %3 = const.i32 2\n");
    io::outbuf_write(&want, "    %4 = mul.i32 %2, %3\n");
    io::outbuf_write(&want, "    ret %4\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b2:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -1; }
    return 0;
}

fn i32 void_empty(arena::Arena* a, u8[] msg) {
    u8[] got = lower_and_print(a, "fn void nothing() {}");
    io::OutBuf want;
    io::outbuf_init(&want, a, 256);
    io::outbuf_write(&want, "module main\n\n");
    io::outbuf_write(&want, "fn __main_nothing() -> void {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    ret\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -1; }
    return 0;
}

fn i32 compound_assign(arena::Arena* a, u8[] msg) {
    u8[] got = lower_and_print(a, "fn i32 f(i32 x) { x += 5; return x; }");
    io::OutBuf want;
    io::outbuf_init(&want, a, 256);
    io::outbuf_write(&want, "module main\n\n");
    io::outbuf_write(&want, "fn __main_f(i32) -> i32 {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = param.i32 0\n");
    io::outbuf_write(&want, "    %1 = const.i32 5\n");
    io::outbuf_write(&want, "    %2 = add.i32 %0, %1\n");
    io::outbuf_write(&want, "    ret %2\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b2:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -1; }
    return 0;
}

fn i32 unary_ops(arena::Arena* a, u8[] msg) {
    u8[] got = lower_and_print(a, "fn i32 f(i32 a) { i32 c = ~a; return -c; }");
    io::OutBuf want;
    io::outbuf_init(&want, a, 256);
    io::outbuf_write(&want, "module main\n\n");
    io::outbuf_write(&want, "fn __main_f(i32) -> i32 {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = param.i32 0\n");
    io::outbuf_write(&want, "    %1 = bitnot.i32 %0\n");
    io::outbuf_write(&want, "    %2 = neg.i32 %1\n");
    io::outbuf_write(&want, "    ret %2\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b2:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -1; }
    return 0;
}

fn i32 not_and_compare(arena::Arena* a, u8[] msg) {
    u8[] got = lower_and_print(a, "fn bool f(i32 a, i32 b, bool c) { bool d = a < b; return !c; }");
    io::OutBuf want;
    io::outbuf_init(&want, a, 256);
    io::outbuf_write(&want, "module main\n\n");
    io::outbuf_write(&want, "fn __main_f(i32, i32, bool) -> bool {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = param.i32 0\n");
    io::outbuf_write(&want, "    %1 = param.i32 1\n");
    io::outbuf_write(&want, "    %2 = param.bool 2\n");
    io::outbuf_write(&want, "    %3 = cmplt.i32 %0, %1\n");
    io::outbuf_write(&want, "    %4 = not.bool %2\n");
    io::outbuf_write(&want, "    ret %4\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b2:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -1; }
    return 0;
}

fn i32 bitwise_and_shift(arena::Arena* a, u8[] msg) {
    u8[] got = lower_and_print(a, "fn i32 f(i32 a, i32 b) { i32 c = a & b; i32 d = c ^ b; i32 e = d << 2; return e >> 1; }");
    io::OutBuf want;
    io::outbuf_init(&want, a, 512);
    io::outbuf_write(&want, "module main\n\n");
    io::outbuf_write(&want, "fn __main_f(i32, i32) -> i32 {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = param.i32 0\n");
    io::outbuf_write(&want, "    %1 = param.i32 1\n");
    io::outbuf_write(&want, "    %2 = and.i32 %0, %1\n");
    io::outbuf_write(&want, "    %3 = xor.i32 %2, %1\n");
    io::outbuf_write(&want, "    %4 = const.i32 2\n");
    io::outbuf_write(&want, "    %5 = shl.i32 %3, %4\n");
    io::outbuf_write(&want, "    %6 = const.i32 1\n");
    io::outbuf_write(&want, "    %7 = shr.i32 %5, %6\n");
    io::outbuf_write(&want, "    ret %7\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b2:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -1; }
    return 0;
}

fn i32 div_and_rem(arena::Arena* a, u8[] msg) {
    u8[] got = lower_and_print(a, "fn i32 f(i32 a, i32 b) { i32 q = a / b; return q % b; }");
    io::OutBuf want;
    io::outbuf_init(&want, a, 256);
    io::outbuf_write(&want, "module main\n\n");
    io::outbuf_write(&want, "fn __main_f(i32, i32) -> i32 {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = param.i32 0\n");
    io::outbuf_write(&want, "    %1 = param.i32 1\n");
    io::outbuf_write(&want, "    %2 = div.i32 %0, %1\n");
    io::outbuf_write(&want, "    %3 = rem.i32 %2, %1\n");
    io::outbuf_write(&want, "    ret %3\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b2:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -1; }
    return 0;
}

fn i32 literals_bool_char(arena::Arena* a, u8[] msg) {
    u8[] got = lower_and_print(a, "fn u8 f() { bool b = true; return 'A'; }");
    io::OutBuf want;
    io::outbuf_init(&want, a, 256);
    io::outbuf_write(&want, "module main\n\n");
    io::outbuf_write(&want, "fn __main_f() -> u8 {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = const.bool 1\n");
    io::outbuf_write(&want, "    %1 = const.u8 65\n");
    io::outbuf_write(&want, "    ret %1\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b2:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -1; }
    return 0;
}

// main stays unmangled; a plain top-level fn is __main_<name> whether exported or not.
fn i32 mangling(arena::Arena* a, u8[] msg) {
    u8[] got = lower_and_print(a, "export fn i32 pub(i32 x) { return x; } fn i32 main() { return 0; }");
    io::OutBuf want;
    io::outbuf_init(&want, a, 512);
    io::outbuf_write(&want, "module main\n\n");
    io::outbuf_write(&want, "fn __main_pub(i32) -> i32 {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = param.i32 0\n");
    io::outbuf_write(&want, "    ret %0\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b2:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n\n");
    io::outbuf_write(&want, "fn main() -> i32 {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = const.i32 0\n");
    io::outbuf_write(&want, "    ret %0\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b2:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -1; }
    return 0;
}

fn i32 if_else_phi(arena::Arena* a, u8[] msg) {
    u8[] got = lower_and_print(a, "fn i32 f(bool c) { i32 x = 0; if(c) { x = 1; } else { x = 2; } return x; }");
    io::OutBuf want;
    io::outbuf_init(&want, a, 512);
    io::outbuf_write(&want, "module main\n\n");
    io::outbuf_write(&want, "fn __main_f(bool) -> i32 {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = param.bool 0\n");
    io::outbuf_write(&want, "    %1 = const.i32 0\n");
    io::outbuf_write(&want, "    condbr %0, b2, b3\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b2:  ; preds: b0\n");
    io::outbuf_write(&want, "    %4 = const.i32 1\n");
    io::outbuf_write(&want, "    br b4\n");
    io::outbuf_write(&want, "b3:  ; preds: b0\n");
    io::outbuf_write(&want, "    %6 = const.i32 2\n");
    io::outbuf_write(&want, "    br b4\n");
    io::outbuf_write(&want, "b4:  ; preds: b2, b3\n");
    io::outbuf_write(&want, "    %8 = phi.i32 [b2: %4, b3: %6]\n");
    io::outbuf_write(&want, "    ret %8\n");
    io::outbuf_write(&want, "b5:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -1; }
    return 0;
}

fn i32 while_loop_phi(arena::Arena* a, u8[] msg) {
    u8[] got = lower_and_print(a, "fn i32 f(i32 n) { i32 i = 0; while(i < n) { i = i + 1; } return i; }");
    io::OutBuf want;
    io::outbuf_init(&want, a, 512);
    io::outbuf_write(&want, "module main\n\n");
    io::outbuf_write(&want, "fn __main_f(i32) -> i32 {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = param.i32 0\n");
    io::outbuf_write(&want, "    %1 = const.i32 0\n");
    io::outbuf_write(&want, "    br b2\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b2:  ; preds: b0, b3\n");
    io::outbuf_write(&want, "    %4 = phi.i32 [b0: %1, b3: %9]\n");
    io::outbuf_write(&want, "    %6 = cmplt.i32 %4, %0\n");
    io::outbuf_write(&want, "    condbr %6, b3, b4\n");
    io::outbuf_write(&want, "b3:  ; preds: b2\n");
    io::outbuf_write(&want, "    %8 = const.i32 1\n");
    io::outbuf_write(&want, "    %9 = add.i32 %4, %8\n");
    io::outbuf_write(&want, "    br b2\n");
    io::outbuf_write(&want, "b4:  ; preds: b2\n");
    io::outbuf_write(&want, "    ret %4\n");
    io::outbuf_write(&want, "b5:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -1; }
    return 0;
}

fn i32 switch_phi(arena::Arena* a, u8[] msg) {
    u8[] got = lower_and_print(a, "fn i32 f(i32 x) { i32 r = 0; switch(x) { case 1: { r = 10; } case 2: { r = 20; } else { r = 30; } } return r; }");
    io::OutBuf want;
    io::outbuf_init(&want, a, 512);
    io::outbuf_write(&want, "module main\n\n");
    io::outbuf_write(&want, "fn __main_f(i32) -> i32 {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = param.i32 0\n");
    io::outbuf_write(&want, "    %1 = const.i32 0\n");
    io::outbuf_write(&want, "    switchbr %0, default b3 [1: b4, 2: b5]\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b2:  ; preds: b3, b4, b5\n");
    io::outbuf_write(&want, "    %4 = phi.i32 [b3: %6, b4: %8, b5: %10]\n");
    io::outbuf_write(&want, "    ret %4\n");
    io::outbuf_write(&want, "b3:  ; preds: b0\n");
    io::outbuf_write(&want, "    %6 = const.i32 30\n");
    io::outbuf_write(&want, "    br b2\n");
    io::outbuf_write(&want, "b4:  ; preds: b0\n");
    io::outbuf_write(&want, "    %8 = const.i32 10\n");
    io::outbuf_write(&want, "    br b2\n");
    io::outbuf_write(&want, "b5:  ; preds: b0\n");
    io::outbuf_write(&want, "    %10 = const.i32 20\n");
    io::outbuf_write(&want, "    br b2\n");
    io::outbuf_write(&want, "b6:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -1; }
    return 0;
}

fn i32 short_circuit_and(arena::Arena* a, u8[] msg) {
    u8[] got = lower_and_print(a, "fn bool f(bool a, bool b) { return a && b; }");
    io::OutBuf want;
    io::outbuf_init(&want, a, 512);
    io::outbuf_write(&want, "module main\n\n");
    io::outbuf_write(&want, "fn __main_f(bool, bool) -> bool {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = param.bool 0\n");
    io::outbuf_write(&want, "    %1 = param.bool 1\n");
    io::outbuf_write(&want, "    %2 = const.bool 0\n");
    io::outbuf_write(&want, "    condbr %0, b3, b4\n");
    io::outbuf_write(&want, "b1:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b2:  ; preds:\n");
    io::outbuf_write(&want, "    unreachable\n");
    io::outbuf_write(&want, "b3:  ; preds: b0\n");
    io::outbuf_write(&want, "    br b4\n");
    io::outbuf_write(&want, "b4:  ; preds: b0, b3\n");
    io::outbuf_write(&want, "    %5 = phi.bool [b0: %2, b3: %1]\n");
    io::outbuf_write(&want, "    ret %5\n");
    io::outbuf_write(&want, "}\n");
    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -1; }
    return 0;
}

fn i32 main() {
    testing::init();
    u8[] suite = "Lower Tests";
    testing::add(suite, "straight_line_add",  &straight_line_add);
    testing::add(suite, "void_empty",         &void_empty);
    testing::add(suite, "compound_assign",    &compound_assign);
    testing::add(suite, "unary_ops",          &unary_ops);
    testing::add(suite, "not_and_compare",    &not_and_compare);
    testing::add(suite, "bitwise_and_shift",  &bitwise_and_shift);
    testing::add(suite, "div_and_rem",        &div_and_rem);
    testing::add(suite, "literals_bool_char", &literals_bool_char);
    testing::add(suite, "mangling",           &mangling);
    testing::add(suite, "if_else_phi",        &if_else_phi);
    testing::add(suite, "while_loop_phi",     &while_loop_phi);
    testing::add(suite, "switch_phi",         &switch_phi);
    testing::add(suite, "short_circuit_and",  &short_circuit_and);
    return testing::run();
}
