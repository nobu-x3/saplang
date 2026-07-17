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

fn void wl(io::OutBuf* b, u8[] line) {
    io::outbuf_write(b, line);
    io::outbuf_write(b, "\n");
}

fn i32 golden(arena::Arena* a, u8[] src, io::OutBuf* want, u8[] msg) {
    if(!testing::expect_eq(lower_and_print(a, src), io::outbuf_bytes(want), msg)) { return -1; }
    return 0;
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

fn i32 for_loop(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f(i32) -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i32 0");
    wl(&w, "    %1 = const.i32 0");
    wl(&w, "    %2 = const.i32 0");
    wl(&w, "    br b2");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds: b0, b4");
    wl(&w, "    %5 = phi.i32 [b0: %2, b4: %13]");
    wl(&w, "    %9 = phi.i32 [b0: %1, b4: %10]");
    wl(&w, "    %7 = cmplt.i32 %5, %0");
    wl(&w, "    condbr %7, b3, b5");
    wl(&w, "b3:  ; preds: b2");
    wl(&w, "    %10 = add.i32 %9, %5");
    wl(&w, "    br b4");
    wl(&w, "b4:  ; preds: b3");
    wl(&w, "    %12 = const.i32 1");
    wl(&w, "    %13 = add.i32 %5, %12");
    wl(&w, "    br b2");
    wl(&w, "b5:  ; preds: b2");
    wl(&w, "    ret %9");
    wl(&w, "b6:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i32 f(i32 n) { i32 s = 0; for(i32 i = 0; i < n; i = i + 1) { s = s + i; } return s; }", &w, msg);
}

fn i32 or_short_circuit(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f(bool, bool) -> bool {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.bool 0");
    wl(&w, "    %1 = param.bool 1");
    wl(&w, "    %2 = const.bool 1");
    wl(&w, "    condbr %0, b4, b3");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b3:  ; preds: b0");
    wl(&w, "    br b4");
    wl(&w, "b4:  ; preds: b0, b3");
    wl(&w, "    %5 = phi.bool [b0: %2, b3: %1]");
    wl(&w, "    ret %5");
    wl(&w, "}");
    return golden(a, "fn bool f(bool a, bool b) { return a || b; }", &w, msg);
}

fn i32 partial_assign(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f(bool) -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.bool 0");
    wl(&w, "    %1 = const.i32 0");
    wl(&w, "    condbr %0, b2, b3");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds: b0");
    wl(&w, "    %4 = const.i32 5");
    wl(&w, "    br b4");
    wl(&w, "b3:  ; preds: b0");
    wl(&w, "    br b4");
    wl(&w, "b4:  ; preds: b2, b3");
    wl(&w, "    %7 = phi.i32 [b2: %4, b3: %1]");
    wl(&w, "    ret %7");
    wl(&w, "b5:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i32 f(bool c) { i32 x = 0; if(c) { x = 5; } return x; }", &w, msg);
}

fn i32 nested_if_in_while(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 768);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f(i32) -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i32 0");
    wl(&w, "    %1 = const.i32 0");
    wl(&w, "    %2 = const.i32 0");
    wl(&w, "    br b2");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds: b0, b7");
    wl(&w, "    %5 = phi.i32 [b0: %2, b7: %19]");
    wl(&w, "    %12 = phi.i32 [b0: %1, b7: %22]");
    wl(&w, "    %7 = cmplt.i32 %5, %0");
    wl(&w, "    condbr %7, b3, b4");
    wl(&w, "b3:  ; preds: b2");
    wl(&w, "    %9 = const.i32 2");
    wl(&w, "    %10 = cmpgt.i32 %5, %9");
    wl(&w, "    condbr %10, b5, b6");
    wl(&w, "b4:  ; preds: b2");
    wl(&w, "    ret %12");
    wl(&w, "b5:  ; preds: b3");
    wl(&w, "    %14 = add.i32 %12, %5");
    wl(&w, "    br b7");
    wl(&w, "b6:  ; preds: b3");
    wl(&w, "    br b7");
    wl(&w, "b7:  ; preds: b5, b6");
    wl(&w, "    %22 = phi.i32 [b5: %14, b6: %12]");
    wl(&w, "    %18 = const.i32 1");
    wl(&w, "    %19 = add.i32 %5, %18");
    wl(&w, "    br b2");
    wl(&w, "b8:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i32 f(i32 n) { i32 s = 0; i32 i = 0; while(i < n) { if(i > 2) { s = s + i; } i = i + 1; } return s; }", &w, msg);
}

fn i32 enum_switch(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 640);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f(main::E) -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.main::E 0");
    wl(&w, "    %1 = const.i32 0");
    wl(&w, "    switchbr %0, default b3 [0: b4, 1: b5]");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds: b3, b4, b5");
    wl(&w, "    %4 = phi.i32 [b3: %6, b4: %8, b5: %10]");
    wl(&w, "    ret %4");
    wl(&w, "b3:  ; preds: b0");
    wl(&w, "    %6 = const.i32 9");
    wl(&w, "    br b2");
    wl(&w, "b4:  ; preds: b0");
    wl(&w, "    %8 = const.i32 1");
    wl(&w, "    br b2");
    wl(&w, "b5:  ; preds: b0");
    wl(&w, "    %10 = const.i32 2");
    wl(&w, "    br b2");
    wl(&w, "b6:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "enum E : i32 { A, B, C } fn i32 f(E e) { i32 r = 0; switch(e) { case E::A: { r = 1; } case E::B: { r = 2; } else { r = 9; } } return r; }", &w, msg);
}

fn i32 global_read_diag(arena::Arena* a, u8[] msg) {
    module::Module* m = test_util::frontend(a, "const i32 LIMIT = 10; fn i32 f() { return LIMIT; }");
    if(!testing::expect_eq(test_util::error_count(m), (u64)0, msg)) { return -1; }
    lower::lower_module(m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "reference to a non-local declaration is not yet supported in lowering", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)42, msg)) { return -4; }
    return 0;
}

fn i32 global_write_diag(arena::Arena* a, u8[] msg) {
    module::Module* m = test_util::frontend(a, "i32 g = 0; fn void f() { g = 5; }");
    if(!testing::expect_eq(test_util::error_count(m), (u64)0, msg)) { return -1; }
    lower::lower_module(m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "assignment to a non-local declaration is not yet supported in lowering", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)25, msg)) { return -4; }
    return 0;
}

fn i32 addr_of(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = alloca.i32*");
    wl(&w, "    %1 = const.i32 5");
    wl(&w, "    store %0, %1");
    wl(&w, "    %3 = const.i32 9");
    wl(&w, "    store %0, %3");
    wl(&w, "    %5 = load.i32 %0");
    wl(&w, "    ret %5");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i32 f() { i32 x = 5; i32* p = &x; *p = 9; return x; }", &w, msg);
}

fn i32 struct_field(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 1024);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = alloca.main::P*");
    wl(&w, "    zero %0, 8");
    wl(&w, "    %2 = fieldaddr %0, 0");
    wl(&w, "    %3 = const.i32 1");
    wl(&w, "    store %2, %3");
    wl(&w, "    %5 = fieldaddr %0, 1");
    wl(&w, "    %6 = const.i32 2");
    wl(&w, "    store %5, %6");
    wl(&w, "    %8 = fieldaddr %0, 1");
    wl(&w, "    %9 = const.i32 7");
    wl(&w, "    store %8, %9");
    wl(&w, "    %11 = fieldaddr %0, 0");
    wl(&w, "    %12 = load.i32 %11");
    wl(&w, "    %13 = fieldaddr %0, 1");
    wl(&w, "    %14 = load.i32 %13");
    wl(&w, "    %15 = add.i32 %12, %14");
    wl(&w, "    ret %15");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "struct P { i32 x; i32 y; } fn i32 f() { P p = {.x = 1, .y = 2}; p.y = 7; return p.x + p.y; }", &w, msg);
}

fn i32 array_index(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 1024);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = alloca.i32[3]*");
    wl(&w, "    %1 = const.u64 0");
    wl(&w, "    %2 = indexaddr %0, %1");
    wl(&w, "    %3 = const.i32 10");
    wl(&w, "    store %2, %3");
    wl(&w, "    %5 = const.u64 1");
    wl(&w, "    %6 = indexaddr %0, %5");
    wl(&w, "    %7 = const.i32 20");
    wl(&w, "    store %6, %7");
    wl(&w, "    %9 = const.u64 2");
    wl(&w, "    %10 = indexaddr %0, %9");
    wl(&w, "    %11 = const.i32 30");
    wl(&w, "    store %10, %11");
    wl(&w, "    %13 = const.i32 1");
    wl(&w, "    %14 = indexaddr %0, %13");
    wl(&w, "    %15 = const.i32 99");
    wl(&w, "    store %14, %15");
    wl(&w, "    %17 = const.i32 1");
    wl(&w, "    %18 = indexaddr %0, %17");
    wl(&w, "    %19 = load.i32 %18");
    wl(&w, "    ret %19");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i32 f() { i32[3] arr = [10, 20, 30]; arr[1] = 99; return arr[1]; }", &w, msg);
}

fn i32 aggregate_copy(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 640);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = alloca.main::P*");
    wl(&w, "    %1 = alloca.main::P*");
    wl(&w, "    zero %0, 4");
    wl(&w, "    %3 = fieldaddr %0, 0");
    wl(&w, "    %4 = const.i32 5");
    wl(&w, "    store %3, %4");
    wl(&w, "    memcpy %1, %0, 4");
    wl(&w, "    %7 = fieldaddr %1, 0");
    wl(&w, "    %8 = load.i32 %7");
    wl(&w, "    ret %8");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "struct P { i32 x; } fn i32 f() { P a = {.x = 5}; P b = a; return b.x; }", &w, msg);
}

fn i32 struct_param(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 640);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f(main::P) -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = alloca.main::P*");
    wl(&w, "    %1 = param.main::P 0");
    wl(&w, "    store %0, %1");
    wl(&w, "    %3 = fieldaddr %0, 0");
    wl(&w, "    %4 = load.i32 %3");
    wl(&w, "    %5 = fieldaddr %0, 1");
    wl(&w, "    %6 = load.i32 %5");
    wl(&w, "    %7 = add.i32 %4, %6");
    wl(&w, "    ret %7");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "struct P { i32 x; i32 y; } fn i32 f(P p) { return p.x + p.y; }", &w, msg);
}

fn i32 pointer_field(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f(main::P*) -> void {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.main::P* 0");
    wl(&w, "    %1 = fieldaddr %0, 0");
    wl(&w, "    %2 = const.i32 8");
    wl(&w, "    store %1, %2");
    wl(&w, "    ret");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "struct P { i32 x; } fn void f(P* p) { p.x = 8; }", &w, msg);
}

fn i32 chained_field(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 768);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = alloca.main::Outer*");
    wl(&w, "    zero %0, 4");
    wl(&w, "    %2 = fieldaddr %0, 0");
    wl(&w, "    zero %2, 4");
    wl(&w, "    %4 = fieldaddr %2, 0");
    wl(&w, "    %5 = const.i32 3");
    wl(&w, "    store %4, %5");
    wl(&w, "    %7 = fieldaddr %0, 0");
    wl(&w, "    %8 = fieldaddr %7, 0");
    wl(&w, "    %9 = load.i32 %8");
    wl(&w, "    ret %9");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "struct Inner { i32 v; } struct Outer { Inner in; } fn i32 f() { Outer o = {.in = {.v = 3}}; return o.in.v; }", &w, msg);
}

fn i32 compound_member(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 768);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = alloca.main::P*");
    wl(&w, "    zero %0, 4");
    wl(&w, "    %2 = fieldaddr %0, 0");
    wl(&w, "    %3 = const.i32 1");
    wl(&w, "    store %2, %3");
    wl(&w, "    %5 = fieldaddr %0, 0");
    wl(&w, "    %6 = load.i32 %5");
    wl(&w, "    %7 = const.i32 5");
    wl(&w, "    %8 = add.i32 %6, %7");
    wl(&w, "    store %5, %8");
    wl(&w, "    %10 = fieldaddr %0, 0");
    wl(&w, "    %11 = load.i32 %10");
    wl(&w, "    ret %11");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "struct P { i32 x; } fn i32 f() { P p = {.x = 1}; p.x += 5; return p.x; }", &w, msg);
}

fn i32 return_struct(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f() -> main::P {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = alloca.main::P*");
    wl(&w, "    zero %0, 4");
    wl(&w, "    %2 = fieldaddr %0, 0");
    wl(&w, "    %3 = const.i32 7");
    wl(&w, "    store %2, %3");
    wl(&w, "    %5 = load.main::P %0");
    wl(&w, "    ret %5");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "struct P { i32 x; } fn P f() { P p = {.x = 7}; return p; }", &w, msg);
}

fn i32 union_field(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = alloca.main::U*");
    wl(&w, "    zero %0, 4");
    wl(&w, "    %2 = fieldaddr %0, 0");
    wl(&w, "    %3 = const.i32 5");
    wl(&w, "    store %2, %3");
    wl(&w, "    %5 = fieldaddr %0, 0");
    wl(&w, "    %6 = load.i32 %5");
    wl(&w, "    ret %6");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "union U { i32 i; f32 f; } fn i32 f() { U u; u.i = 5; return u.i; }", &w, msg);
}

fn i32 addr_global_diag(arena::Arena* a, u8[] msg) {
    module::Module* m = test_util::frontend(a, "i32 g = 0; fn i32* f() { return &g; }");
    if(!testing::expect_eq(test_util::error_count(m), (u64)0, msg)) { return -1; }
    lower::lower_module(m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "address of a non-local declaration is not yet supported in lowering", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)33, msg)) { return -4; }
    return 0;
}

fn i32 aggregate_call_diag(arena::Arena* a, u8[] msg) {
    module::Module* m = test_util::frontend(a, "struct P { i32 x; } fn P make() { P p = {.x = 1}; return p; } fn i32 f() { P q = make(); return q.x; }");
    if(!testing::expect_eq(test_util::error_count(m), (u64)0, msg)) { return -1; }
    lower::lower_module(m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "an aggregate value returned from a call is not yet supported in lowering", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)85, msg)) { return -4; }
    return 0;
}

fn i32 int_cast(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f(i32) -> i64 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i32 0");
    wl(&w, "    %1 = cast.i8 %0");
    wl(&w, "    %2 = cast.i64 %0");
    wl(&w, "    ret %2");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i64 f(i32 x) { i8 a = (i8)x; i64 b = (i64)x; return b; }", &w, msg);
}

fn i32 float_cast(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f(i32) -> f64 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i32 0");
    wl(&w, "    %1 = cast.f64 %0");
    wl(&w, "    %2 = cast.f32 %1");
    wl(&w, "    %3 = cast.f64 %2");
    wl(&w, "    ret %3");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn f64 f(i32 x) { f64 d = (f64)x; return (f64)(f32)d; }", &w, msg);
}

fn i32 ptr_to_int_cast(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f(i32*) -> u64 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i32* 0");
    wl(&w, "    %1 = cast.u64 %0");
    wl(&w, "    ret %1");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn u64 f(i32* p) { return (u64)p; }", &w, msg);
}

fn i32 array_to_slice_cast(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 768);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f() -> i32[] {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = alloca.i32[3]*");
    wl(&w, "    %1 = const.u64 0");
    wl(&w, "    %2 = indexaddr %0, %1");
    wl(&w, "    %3 = const.i32 1");
    wl(&w, "    store %2, %3");
    wl(&w, "    %5 = const.u64 1");
    wl(&w, "    %6 = indexaddr %0, %5");
    wl(&w, "    %7 = const.i32 2");
    wl(&w, "    store %6, %7");
    wl(&w, "    %9 = const.u64 2");
    wl(&w, "    %10 = indexaddr %0, %9");
    wl(&w, "    %11 = const.i32 3");
    wl(&w, "    store %10, %11");
    wl(&w, "    %13 = const.u64 0");
    wl(&w, "    %14 = indexaddr %0, %13");
    wl(&w, "    %15 = const.u64 3");
    wl(&w, "    %16 = slicemake %14, %15");
    wl(&w, "    ret %16");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i32[] f() { i32[3] arr = [1,2,3]; return (i32[])arr; }", &w, msg);
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
    testing::add(suite, "for_loop",           &for_loop);
    testing::add(suite, "or_short_circuit",   &or_short_circuit);
    testing::add(suite, "partial_assign",     &partial_assign);
    testing::add(suite, "nested_if_in_while", &nested_if_in_while);
    testing::add(suite, "enum_switch",        &enum_switch);
    testing::add(suite, "global_read_diag",   &global_read_diag);
    testing::add(suite, "global_write_diag",  &global_write_diag);
    testing::add(suite, "addr_of",            &addr_of);
    testing::add(suite, "struct_field",       &struct_field);
    testing::add(suite, "array_index",        &array_index);
    testing::add(suite, "aggregate_copy",     &aggregate_copy);
    testing::add(suite, "struct_param",       &struct_param);
    testing::add(suite, "pointer_field",      &pointer_field);
    testing::add(suite, "chained_field",      &chained_field);
    testing::add(suite, "compound_member",    &compound_member);
    testing::add(suite, "return_struct",      &return_struct);
    testing::add(suite, "union_field",        &union_field);
    testing::add(suite, "addr_global_diag",   &addr_global_diag);
    testing::add(suite, "aggregate_call_diag", &aggregate_call_diag);
    testing::add(suite, "int_cast",           &int_cast);
    testing::add(suite, "float_cast",         &float_cast);
    testing::add(suite, "ptr_to_int_cast",    &ptr_to_int_cast);
    testing::add(suite, "array_to_slice_cast", &array_to_slice_cast);
    return testing::run();
}
