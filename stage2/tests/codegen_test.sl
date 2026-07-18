import testing;
import test_util;
import lower;
import codegen;
import sapir;
import module;
import arena;
import sys;

// A page-per-alloc arena (the runner default) does not survive MCJIT; the real
// compiler runs on megabyte-page arenas everywhere, so tests do the same.
fn arena::Arena* fresh_arena(arena::Arena* host) {
    arena::Arena* a = (arena::Arena*)arena::alloc(host, sizeof(arena::Arena));
    sys::memset(a, 0, sizeof(arena::Arena));
    a.default_page_size = 1048576;
    return a;
}

fn i32 jit_return(arena::Arena* a, u8[] src, i32 expected, u8[] msg) {
    arena::Arena* ja = fresh_arena(a);
    module::Module* m = test_util::frontend(ja, src);
    if(!testing::expect_eq(test_util::error_count(m), (u64)0, msg)) { return -1; }
    sapir::SapirModule* sm = lower::lower_module(m);
    i32 result = codegen::jit_run_main(sm, ja);
    if(!testing::expect_eq((u64)result, (u64)expected, msg)) { return -2; }
    return 0;
}

// End-to-end: source -> frontend -> lower -> LLVM -> MCJIT-run main() in-process.
// Step 8 covers constants and terminators, so main can only return a constant;
// arithmetic and the rest of the opcode set arrive with instruction translation.
fn i32 jit_returns_constant(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { return 42; }", 42, msg);
}

fn i32 jit_returns_zero(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { return 0; }", 0, msg);
}

fn i32 main() {
    testing::init();
    u8[] suite = "Codegen Tests";
    testing::add(suite, "jit_returns_zero",     &jit_returns_zero);
    testing::add(suite, "jit_returns_constant", &jit_returns_constant);
    return testing::run();
}
