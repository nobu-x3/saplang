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

fn i32 global_read(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "global __main_LIMIT: i32 const = 10"); wl(&w, "");
    wl(&w, "fn __main_f() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = globaladdr.__main_LIMIT");
    wl(&w, "    %1 = load.i32 %0");
    wl(&w, "    ret %1");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "const i32 LIMIT = 10; fn i32 f() { return LIMIT; }", &w, msg);
}

fn i32 global_write(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "global __main_g: i32 = 0"); wl(&w, "");
    wl(&w, "fn __main_f() -> void {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = globaladdr.__main_g");
    wl(&w, "    %1 = const.i32 5");
    wl(&w, "    store %0, %1");
    wl(&w, "    ret");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "i32 g = 0; fn void f() { g = 5; }", &w, msg);
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

fn i32 addr_global(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "global __main_g: i32 = 0"); wl(&w, "");
    wl(&w, "fn __main_f() -> i32* {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = globaladdr.__main_g");
    wl(&w, "    ret %0");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "i32 g = 0; fn i32* f() { return &g; }", &w, msg);
}

fn i32 aggregate_call(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 768);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_make() -> main::P {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = alloca.main::P*");
    wl(&w, "    zero %0, 4");
    wl(&w, "    %2 = fieldaddr %0, 0");
    wl(&w, "    %3 = const.i32 1");
    wl(&w, "    store %2, %3");
    wl(&w, "    %5 = load.main::P %0");
    wl(&w, "    ret %5");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    wl(&w, "");
    wl(&w, "fn __main_f() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = alloca.main::P*");
    wl(&w, "    %1 = call.main::P __main_make()");
    wl(&w, "    store %0, %1");
    wl(&w, "    %3 = fieldaddr %0, 0");
    wl(&w, "    %4 = load.i32 %3");
    wl(&w, "    ret %4");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "struct P { i32 x; } fn P make() { P p = {.x = 1}; return p; } fn i32 f() { P q = make(); return q.x; }", &w, msg);
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

// A redundant slice-to-slice cast forwards the slice unchanged: no instruction, not a null slice.
fn i32 slice_noop_cast(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f(i32[]) -> i32[] {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i32[] 0");
    wl(&w, "    ret %0");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i32[] f(i32[] s) { return (i32[])s; }", &w, msg);
}

// defer runs at scope exit but the return value is captured first (Zig semantics): returns n, not 0.
fn i32 defer_capture(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f(i32) -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i32 0");
    wl(&w, "    %1 = const.i32 0");
    wl(&w, "    ret %0");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i32 f(i32 n) { i32 x = n; defer { x = 0; } return x; }", &w, msg);
}

// Deferred blocks run in reverse (LIFO) order, after the return value is captured.
fn i32 defer_lifo(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = const.i32 1");
    wl(&w, "    %1 = const.i32 3");
    wl(&w, "    %2 = const.i32 2");
    wl(&w, "    ret %0");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i32 f() { i32 x = 1; defer { x = 2; } defer { x = 3; } return x; }", &w, msg);
}

fn i32 direct_call(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 640);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_g(i32) -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i32 0");
    wl(&w, "    ret %0");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    wl(&w, "");
    wl(&w, "fn __main_f() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = const.i32 3");
    wl(&w, "    %1 = call.i32 __main_g(%0)");
    wl(&w, "    ret %1");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i32 g(i32 x) { return x; } fn i32 f() { return g(3); }", &w, msg);
}

// Extern C variadic: fixed args pass through, an i32 tail needs no default-argument promotion.
fn i32 extern_variadic_call(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f() -> void {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = conststr @0+2");
    wl(&w, "    %1 = const.i32 42");
    wl(&w, "    %2 = call.i32 printf(%0, %1)");
    wl(&w, "    ret");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "extern { fn i32 printf(const u8* fmt, ...); } fn void f() { printf(\"%d\", 42); }", &w, msg);
}

// A variadic-tail f32 widens to f64 per the C default argument promotions.
fn i32 vararg_promote_f32(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f(f32) -> void {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.f32 0");
    wl(&w, "    %1 = conststr @0+2");
    wl(&w, "    %2 = cast.f64 %0");
    wl(&w, "    %3 = call.i32 printf(%1, %2)");
    wl(&w, "    ret");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "extern { fn i32 printf(const u8* fmt, ...); } fn void f(f32 x) { printf(\"%f\", x); }", &w, msg);
}

// A variadic-tail u8 promotes to i32 (integer promotion).
fn i32 vararg_promote_int(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f(u8) -> void {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.u8 0");
    wl(&w, "    %1 = conststr @0+2");
    wl(&w, "    %2 = cast.i32 %0");
    wl(&w, "    %3 = call.i32 printf(%1, %2)");
    wl(&w, "    ret");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "extern { fn i32 printf(const u8* fmt, ...); } fn void f(u8 x) { printf(\"%d\", x); }", &w, msg);
}

// A call through a fn-pointer value is Indirect: the callee slot holds a value id, printed with %.
fn i32 indirect_call(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 640);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_g(i32) -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i32 0");
    wl(&w, "    ret %0");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    wl(&w, "");
    wl(&w, "fn __main_f() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = fnaddr.__main_g");
    wl(&w, "    %1 = const.i32 4");
    wl(&w, "    %2 = call.i32 %0(%1)");
    wl(&w, "    ret %2");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i32 g(i32 x) { return x; } fn i32 f() { fn* i32(i32) p = &g; return p(4); }", &w, msg);
}

// A generic call resolves to a monomorphized clone, mangled off its qualified name and lowered after the module functions.
fn i32 generic_call(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 640);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = const.i32 5");
    wl(&w, "    %1 = call.i32 __main_id__i32(%0)");
    wl(&w, "    ret %1");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    wl(&w, "");
    wl(&w, "fn __main_id__i32(i32) -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i32 0");
    wl(&w, "    ret %0");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn T id(comptime Type T, T x) { return x; } fn i32 f() { return id(5); }", &w, msg);
}

fn i32 string_literal(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f() -> const u8* {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = conststr @0+2");
    wl(&w, "    ret %0");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn const u8* f() { return \"hi\"; }", &w, msg);
}

fn i32 slice_index(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f(i32[]) -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i32[] 0");
    wl(&w, "    %1 = const.i32 1");
    wl(&w, "    %2 = sliceptr.i32* %0");
    wl(&w, "    %3 = indexaddr %2, %1");
    wl(&w, "    %4 = load.i32 %3");
    wl(&w, "    ret %4");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i32 f(i32[] s) { return s[1]; }", &w, msg);
}

fn i32 sub_slice(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f(i32[]) -> i32[] {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i32[] 0");
    wl(&w, "    %1 = sliceptr.i32* %0");
    wl(&w, "    %2 = const.i32 1");
    wl(&w, "    %3 = cast.u64 %2");
    wl(&w, "    %4 = const.i32 3");
    wl(&w, "    %5 = cast.u64 %4");
    wl(&w, "    %6 = indexaddr %1, %3");
    wl(&w, "    %7 = sub.u64 %5, %3");
    wl(&w, "    %8 = slicemake %6, %7");
    wl(&w, "    ret %8");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i32[] f(i32[] s) { return s[1..3]; }", &w, msg);
}

// An omitted upper bound defaults to the base length, materialized as a slicelen.
fn i32 range_from(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f(i32[]) -> i32[] {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i32[] 0");
    wl(&w, "    %1 = sliceptr.i32* %0");
    wl(&w, "    %2 = const.i32 2");
    wl(&w, "    %3 = cast.u64 %2");
    wl(&w, "    %4 = slicelen.u64 %0");
    wl(&w, "    %5 = indexaddr %1, %3");
    wl(&w, "    %6 = sub.u64 %4, %3");
    wl(&w, "    %7 = slicemake %5, %6");
    wl(&w, "    ret %7");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i32[] f(i32[] s) { return s[2..]; }", &w, msg);
}

fn i32 global_scalar_init(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "global __main_counter: i32 = 42"); wl(&w, "");
    wl(&w, "fn __main_f() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = globaladdr.__main_counter");
    wl(&w, "    %1 = load.i32 %0");
    wl(&w, "    ret %1");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "export i32 counter = 42; fn i32 f() { return counter; }", &w, msg);
}

// A function-pointer global initializer folds to a FnRef pointing at the mangled function decl.
fn i32 global_fn_ptr_init(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "global __main_gp: fn* i32() = &__main_g"); wl(&w, "");
    wl(&w, "fn __main_g() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = const.i32 1");
    wl(&w, "    ret %0");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i32 g() { return 1; } fn* i32() gp = &g;", &w, msg);
}

fn i32 global_struct_init(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 384);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "global __main_origin: main::P const = { 0, 0 }");
    return golden(a, "struct P { i32 x; i32 y; } const P origin = {.x = 0, .y = 0};", &w, msg);
}

// A struct global with out-of-order named initializers folds to declaration order.
fn i32 global_struct_reordered(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 384);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "global __main_pt: main::P const = { 1, 2 }");
    return golden(a, "struct P { i32 x; i32 y; } const P pt = {.y = 2, .x = 1};", &w, msg);
}

fn i32 global_array_init(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 384);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "global __main_table: i32[3] = [ 10, 20, 30 ]");
    return golden(a, "i32[3] table = [10, 20, 30];", &w, msg);
}

// A const slice global from an array literal: the elements back a static array, the slice is {ptr, len}.
fn i32 global_slice_from_array(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 384);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "global __main_nums: i32[] const = slice[ 1, 2, 3, 4 ]");
    return golden(a, "const i32[] nums = [1, 2, 3, 4];", &w, msg);
}

// A const u8[] global from a string literal lowers to a Bytes init.
fn i32 global_bytes_slice(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 384);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "global __main_s: u8[] const = bytes[2]");
    return golden(a, "const u8[] s = \"hi\";", &w, msg);
}

// A const slice of structs whose fields include a string slice — the table pattern.
fn i32 global_struct_slice_table(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "global __main_tbl: main::E[] const = slice[ { bytes[1], 1 }, { bytes[2], 2 } ]");
    return golden(a, "struct E { u8[] name; i32 v; } const E[] tbl = [ {\"a\", 1}, {\"bb\", 2} ];", &w, msg);
}

// A global compound assignment reads through GlobalAddr, combines, and stores back.
fn i32 global_compound_assign(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "global __main_acc: i32 = 0"); wl(&w, "");
    wl(&w, "fn __main_f() -> void {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = globaladdr.__main_acc");
    wl(&w, "    %1 = load.i32 %0");
    wl(&w, "    %2 = const.i32 5");
    wl(&w, "    %3 = add.i32 %1, %2");
    wl(&w, "    store %0, %3");
    wl(&w, "    ret");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "i32 acc = 0; fn void f() { acc += 5; }", &w, msg);
}

// A nested call lowers the inner call first; each Call gets a contiguous extra block.
fn i32 nested_call(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 640);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_g(i32) -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i32 0");
    wl(&w, "    ret %0");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    wl(&w, "");
    wl(&w, "fn __main_f() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = const.i32 1");
    wl(&w, "    %1 = call.i32 __main_g(%0)");
    wl(&w, "    %2 = call.i32 __main_g(%1)");
    wl(&w, "    ret %2");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i32 g(i32 x) { return x; } fn i32 f() { return g(g(1)); }", &w, msg);
}

// A call argument narrower than its parameter widens via an implicit conversion at the call site.
fn i32 call_arg_widening(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 640);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_g(i64) -> i64 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i64 0");
    wl(&w, "    ret %0");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    wl(&w, "");
    wl(&w, "fn __main_f(i32) -> i64 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i32 0");
    wl(&w, "    %1 = cast.i64 %0");
    wl(&w, "    %2 = call.i64 __main_g(%1)");
    wl(&w, "    ret %2");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i64 g(i64 x) { return x; } fn i64 f(i32 y) { return g(y); }", &w, msg);
}

// A qualified enum member used as a value folds to its integer constant, typed as the enum.
fn i32 enum_member_value(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f() -> main::Color {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = const.main::Color 1");
    wl(&w, "    ret %0");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "enum Color { Red, Green, Blue } fn Color f() { return Color::Green; }", &w, msg);
}

// A store to a slice element addresses through the slice data pointer.
fn i32 slice_store(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 512);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f(i32[]) -> void {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i32[] 0");
    wl(&w, "    %1 = const.i32 0");
    wl(&w, "    %2 = sliceptr.i32* %0");
    wl(&w, "    %3 = indexaddr %2, %1");
    wl(&w, "    %4 = const.i32 9");
    wl(&w, "    store %3, %4");
    wl(&w, "    ret");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn void f(i32[] s) { s[0] = 9; }", &w, msg);
}

// A `{ptr, len}` brace literal targeting a slice field lowers to a SliceMake stored through the field address.
fn i32 slice_literal_store(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 640);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = alloca.main::C*");
    wl(&w, "    %1 = constnull.i32*");
    wl(&w, "    zero %0, 16");
    wl(&w, "    %3 = fieldaddr %0, 0");
    wl(&w, "    %4 = const.u64 0");
    wl(&w, "    %5 = slicemake %1, %4");
    wl(&w, "    store %3, %5");
    wl(&w, "    %7 = fieldaddr %0, 0");
    wl(&w, "    %8 = load.i32[] %7");
    wl(&w, "    %9 = slicelen.u64 %8");
    wl(&w, "    %10 = cast.i32 %9");
    wl(&w, "    ret %10");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "struct C { i32[] items; } fn i32 f() { i32* p = null; C c; c.items = {p, 0}; return (i32)c.items.len; }", &w, msg);
}

// Named, reordered slice fields map by name, not position: `.ptr` still feeds SliceMake's pointer slot even when written second.
fn i32 slice_literal_named(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 640);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = alloca.main::C*");
    wl(&w, "    zero %0, 16");
    wl(&w, "    %2 = fieldaddr %0, 0");
    wl(&w, "    %3 = constnull.i32*");
    wl(&w, "    %4 = const.u64 3");
    wl(&w, "    %5 = slicemake %3, %4");
    wl(&w, "    store %2, %5");
    wl(&w, "    %7 = fieldaddr %0, 0");
    wl(&w, "    %8 = load.i32[] %7");
    wl(&w, "    %9 = slicelen.u64 %8");
    wl(&w, "    %10 = cast.i32 %9");
    wl(&w, "    ret %10");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "struct C { i32[] items; } fn i32 f() { C c; c.items = {.len = 3, .ptr = null}; return (i32)c.items.len; }", &w, msg);
}

// Overloaded functions get a "__<paramtypes>" suffix so each has a distinct symbol, and each call targets the right one.
fn i32 overload_dispatch(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 896);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f__i32(i32) -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i32 0");
    wl(&w, "    ret %0");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    wl(&w, "");
    wl(&w, "fn __main_f__bool(bool) -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.bool 0");
    wl(&w, "    %1 = const.i32 9");
    wl(&w, "    ret %1");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    wl(&w, "");
    wl(&w, "fn __main_g() -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = const.i32 1");
    wl(&w, "    %1 = call.i32 __main_f__i32(%0)");
    wl(&w, "    %2 = const.bool 1");
    wl(&w, "    %3 = call.i32 __main_f__bool(%2)");
    wl(&w, "    %4 = add.i32 %1, %3");
    wl(&w, "    ret %4");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i32 f(i32 x) { return x; } fn i32 f(bool b) { return 9; } fn i32 g() { return f(1) + f(true); }", &w, msg);
}

// The overload suffix encodes pointers as "Xp" and slices as "sl_X".
fn i32 overload_ptr_slice(arena::Arena* a, u8[] msg) {
    io::OutBuf w;
    io::outbuf_init(&w, a, 896);
    wl(&w, "module main"); wl(&w, "");
    wl(&w, "fn __main_f__u8p(u8*) -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.u8* 0");
    wl(&w, "    %1 = const.i32 0");
    wl(&w, "    ret %1");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    wl(&w, "");
    wl(&w, "fn __main_f__sl_i32(i32[]) -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.i32[] 0");
    wl(&w, "    %1 = const.i32 1");
    wl(&w, "    ret %1");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    wl(&w, "");
    wl(&w, "fn __main_g(u8*, i32[]) -> i32 {");
    wl(&w, "b0:  ; preds:");
    wl(&w, "    %0 = param.u8* 0");
    wl(&w, "    %1 = param.i32[] 1");
    wl(&w, "    %2 = call.i32 __main_f__u8p(%0)");
    wl(&w, "    %3 = call.i32 __main_f__sl_i32(%1)");
    wl(&w, "    %4 = add.i32 %2, %3");
    wl(&w, "    ret %4");
    wl(&w, "b1:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "b2:  ; preds:");
    wl(&w, "    unreachable");
    wl(&w, "}");
    return golden(a, "fn i32 f(u8* p) { return 0; } fn i32 f(i32[] s) { return 1; } fn i32 g(u8* p, i32[] s) { return f(p) + f(s); }", &w, msg);
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
    testing::add(suite, "global_read",        &global_read);
    testing::add(suite, "global_write",       &global_write);
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
    testing::add(suite, "addr_global",        &addr_global);
    testing::add(suite, "aggregate_call",     &aggregate_call);
    testing::add(suite, "int_cast",           &int_cast);
    testing::add(suite, "float_cast",         &float_cast);
    testing::add(suite, "ptr_to_int_cast",    &ptr_to_int_cast);
    testing::add(suite, "array_to_slice_cast", &array_to_slice_cast);
    testing::add(suite, "slice_noop_cast",    &slice_noop_cast);
    testing::add(suite, "defer_capture",      &defer_capture);
    testing::add(suite, "defer_lifo",         &defer_lifo);
    testing::add(suite, "direct_call",        &direct_call);
    testing::add(suite, "extern_variadic_call", &extern_variadic_call);
    testing::add(suite, "vararg_promote_f32", &vararg_promote_f32);
    testing::add(suite, "vararg_promote_int", &vararg_promote_int);
    testing::add(suite, "indirect_call",      &indirect_call);
    testing::add(suite, "generic_call",       &generic_call);
    testing::add(suite, "string_literal",     &string_literal);
    testing::add(suite, "slice_index",        &slice_index);
    testing::add(suite, "sub_slice",          &sub_slice);
    testing::add(suite, "range_from",         &range_from);
    testing::add(suite, "global_scalar_init", &global_scalar_init);
    testing::add(suite, "global_fn_ptr_init", &global_fn_ptr_init);
    testing::add(suite, "global_struct_init", &global_struct_init);
    testing::add(suite, "global_struct_reordered", &global_struct_reordered);
    testing::add(suite, "global_array_init",  &global_array_init);
    testing::add(suite, "global_slice_from_array", &global_slice_from_array);
    testing::add(suite, "global_bytes_slice", &global_bytes_slice);
    testing::add(suite, "global_struct_slice_table", &global_struct_slice_table);
    testing::add(suite, "global_compound_assign", &global_compound_assign);
    testing::add(suite, "nested_call",        &nested_call);
    testing::add(suite, "call_arg_widening",  &call_arg_widening);
    testing::add(suite, "enum_member_value",  &enum_member_value);
    testing::add(suite, "slice_store",        &slice_store);
    testing::add(suite, "slice_literal_store", &slice_literal_store);
    testing::add(suite, "slice_literal_named", &slice_literal_named);
    testing::add(suite, "overload_dispatch",  &overload_dispatch);
    testing::add(suite, "overload_ptr_slice", &overload_ptr_slice);
    return testing::run();
}
