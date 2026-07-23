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

fn i32 jit_arithmetic(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { i32 x = 6; i32 y = 7; return x * y; }", 42, msg);
}

fn i32 jit_precedence(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { return (10 - 2) * 5 + 2; }", 42, msg);
}

fn i32 jit_if_else(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { i32 x = 5; i32 r = 0; if(x > 3) { r = 42; } else { r = 7; } return r; }", 42, msg);
}

fn i32 jit_while_loop(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { i32 i = 0; i32 s = 0; while(i < 4) { s = s + i; i = i + 1; } return s; }", 6, msg);
}

fn i32 jit_for_loop(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { i32 s = 0; for(i32 i = 0; i < 10; i = i + 1) { s = s + 1; } return s; }", 10, msg);
}

fn i32 jit_call(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 dbl(i32 x) { return x * 2; } fn i32 main() { return dbl(21); }", 42, msg);
}

fn i32 jit_recursion(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 fac(i32 n) { if(n <= 1) { return 1; } return n * fac(n - 1); } fn i32 main() { return fac(5); }", 120, msg);
}

fn i32 jit_struct(arena::Arena* a, u8[] msg) {
    return jit_return(a, "struct P { i32 x; i32 y; } fn i32 main() { P p = {.x = 40, .y = 2}; return p.x + p.y; }", 42, msg);
}

fn i32 jit_array(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { i32[3] a = [10, 20, 12]; return a[0] + a[1] + a[2]; }", 42, msg);
}

fn i32 jit_pointer(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { i32 x = 21; i32* p = &x; *p = 42; return x; }", 42, msg);
}

fn i32 jit_cast(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { i64 big = 42; return (i32)big; }", 42, msg);
}

fn i32 jit_slice_sum(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 sum(i32[] s) { i32 t = 0; for(i32 i = 0; i < (i32)s.len; i = i + 1) { t = t + s[i]; } return t; } fn i32 main() { i32[3] a = [10, 20, 12]; return sum(a); }", 42, msg);
}

fn i32 jit_switch(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { i32 x = 2; i32 r = 0; switch(x) { case 1: { r = 10; } case 2: { r = 42; } else { r = 99; } } return r; }", 42, msg);
}

fn i32 jit_global(arena::Arena* a, u8[] msg) {
    return jit_return(a, "i32 g = 42; fn i32 main() { return g; }", 42, msg);
}

fn i32 jit_bool(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { bool b = 5 > 3; if(b) { return 42; } return 0; }", 42, msg);
}

fn i32 jit_string_len(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { u8[] s = \"hello\"; return (i32)s.len; }", 5, msg);
}

fn i32 jit_printf(arena::Arena* a, u8[] msg) {
    return jit_return(a, "extern { fn i32 printf(u8* fmt, ...); } fn i32 main() { printf(\"[codegen jit_printf ok]\\n\"); return 0; }", 0, msg);
}

fn i32 jit_struct_global(arena::Arena* a, u8[] msg) {
    return jit_return(a, "struct P { i32 x; i32 y; } const P o = {.x = 40, .y = 2}; fn i32 main() { return o.x + o.y; }", 42, msg);
}

fn i32 jit_array_global(arena::Arena* a, u8[] msg) {
    return jit_return(a, "const i32[3] t = [10, 20, 12]; fn i32 main() { return t[0] + t[1] + t[2]; }", 42, msg);
}

fn i32 jit_float(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { f64 x = 3.5; f64 y = 12.0; return (i32)(x * y); }", 42, msg);
}

fn i32 jit_float_cmp(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { f32 x = 1.5; if(x < 2.0) { return 42; } return 0; }", 42, msg);
}

fn i32 jit_sub_slice(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 sum(i32[] s) { i32 t = 0; for(i32 i = 0; i < (i32)s.len; i = i + 1) { t = t + s[i]; } return t; } fn i32 main() { i32[4] a = [1, 20, 21, 9]; return sum(a[1..3]); }", 41, msg);
}

fn i32 jit_union(arena::Arena* a, u8[] msg) {
    return jit_return(a, "union U { i32 i; f32 f; } fn i32 main() { U u; u.i = 42; return u.i; }", 42, msg);
}

fn i32 jit_aggregate_arg(arena::Arena* a, u8[] msg) {
    return jit_return(a, "struct P { i32 x; i32 y; } fn i32 g(P p) { return p.x + p.y; } fn i32 main() { P p = {.x = 40, .y = 2}; return g(p); }", 42, msg);
}

fn i32 jit_struct_return(arena::Arena* a, u8[] msg) {
    return jit_return(a, "struct P { i32 x; } fn P make() { return {.x = 42}; } fn i32 main() { P p = make(); return p.x; }", 42, msg);
}

fn i32 jit_fn_pointer(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 g(i32 x) { return x + 1; } fn i32 main() { fn* i32(i32) p = &g; return p(41); }", 42, msg);
}

fn i32 jit_short_circuit(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { i32 x = 5; if(x > 3 && x < 10) { return 42; } return 0; }", 42, msg);
}

fn i32 jit_string_array(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { u8[3] s = \"hi\"; return (i32)s[0]; }", 104, msg);
}

fn i32 jit_sizeof(arena::Arena* a, u8[] msg) {
    return jit_return(a, "struct P { i32 x; i32 y; } fn i32 main() { return (i32)sizeof(i32) * 5 + (i32)sizeof(P) * 4 - 10; }", 42, msg);
}

fn i32 jit_alignof(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { return (i32)alignof(i64) * 5 + 2; }", 42, msg);
}

// A no-op pointer cast must carry its destination type so a later index GEPs the right element (not void).
fn i32 jit_ptr_cast_index(arena::Arena* a, u8[] msg) {
    return jit_return(a, "extern { fn void* malloc(u64 n); } fn i32 main() { i32* p = (i32*)malloc(16); p[0] = 40; p[1] = 2; return p[0] + p[1]; }", 42, msg);
}

// A const slice global from an array literal materializes a backing array; index and .len read it back.
fn i32 jit_const_slice_index(arena::Arena* a, u8[] msg) {
    return jit_return(a, "const i32[] nums = [5, 6, 7, 8]; fn i32 main() { return nums[2] + (i32)nums.len; }", 11, msg);
}

// A const u8[] from a string literal: .len and byte reads through .ptr.
fn i32 jit_const_string_slice(arena::Arena* a, u8[] msg) {
    return jit_return(a, "const u8[] s = \"hello\"; fn i32 main() { return (i32)s.len + (i32)s.ptr[1]; }", 106, msg);
}

// A const table of structs whose fields include a string slice — value + nested slice len.
fn i32 jit_const_struct_table(arena::Arena* a, u8[] msg) {
    return jit_return(a, "struct E { u8[] name; i32 v; } const E[] t = [ {\"ab\", 10}, {\"c\", 20} ]; fn i32 main() { return t[1].v + (i32)t[0].name.len; }", 22, msg);
}

fn bool contains(u8[] hay, u8[] needle) {
    if(needle.len > hay.len) { return false; }
    for(u64 i = 0; i + needle.len <= hay.len; i += 1) {
        bool match = true;
        for(u64 j = 0; j < needle.len; j += 1) { if(hay[i + j] != needle[j]) { match = false; } }
        if(match) { return true; }
    }
    return false;
}

// Debug/ReleaseDebug configs emit DWARF (a DISubprogram per function); Release omits it. The
// void return and struct/pointer params exercise the unspecified-DIType path in the subroutine type.
fn i32 opt_debug_info(arena::Arena* a, u8[] msg) {
    arena::Arena* ja = fresh_arena(a);
    module::Module* m = test_util::frontend(ja, "struct P { i32 x; } fn void noop() {} fn i32 g(P p, i32* q) { return p.x + *q; } fn i32 main() { noop(); P p = {.x = 40}; i32 y = 2; return g(p, &y); }");
    if(!testing::expect_eq(test_util::error_count(m), (u64)0, msg)) { return -1; }
    sapir::SapirModule* sm = lower::lower_module(m);
    u8[] debug_ir = codegen::codegen_ir_string(sm, ja, codegen::BuildConfig::Debug);
    u8[] release_ir = codegen::codegen_ir_string(sm, ja, codegen::BuildConfig::Release);
    if(!contains(debug_ir, "DISubprogram")) { return -2; }        // fails if the module didn't verify (returns "<codegen failed>")
    if(!contains(debug_ir, "DILocation")) { return -3; }
    if(!contains(debug_ir, "DILocalVariable")) { return -4; }     // the i32* param gets a variable
    if(contains(release_ir, "DISubprogram")) { return -5; }
    return 0;
}

// -O2 (Release) promotes an address-taken scalar out of memory; the Debug IR keeps the alloca.
fn i32 opt_release_mem2reg(arena::Arena* a, u8[] msg) {
    arena::Arena* ja = fresh_arena(a);
    module::Module* m = test_util::frontend(ja, "fn i32 main() { i32 x = 5; i32* p = &x; *p = 42; return x; }");
    if(!testing::expect_eq(test_util::error_count(m), (u64)0, msg)) { return -1; }
    sapir::SapirModule* sm = lower::lower_module(m);
    u8[] debug_ir = codegen::codegen_ir_string(sm, ja, codegen::BuildConfig::Debug);
    u8[] release_ir = codegen::codegen_ir_string(sm, ja, codegen::BuildConfig::Release);
    if(!contains(debug_ir, "alloca")) { return -2; }
    if(contains(release_ir, "alloca")) { return -3; }
    return 0;
}

fn i32 main() {
    testing::init();
    u8[] suite = "Codegen Tests";
    testing::add(suite, "jit_returns_zero",     &jit_returns_zero);
    testing::add(suite, "jit_returns_constant", &jit_returns_constant);
    testing::add(suite, "jit_arithmetic",       &jit_arithmetic);
    testing::add(suite, "jit_precedence",       &jit_precedence);
    testing::add(suite, "jit_if_else",          &jit_if_else);
    testing::add(suite, "jit_while_loop",       &jit_while_loop);
    testing::add(suite, "jit_for_loop",         &jit_for_loop);
    testing::add(suite, "jit_call",             &jit_call);
    testing::add(suite, "jit_recursion",        &jit_recursion);
    testing::add(suite, "jit_struct",           &jit_struct);
    testing::add(suite, "jit_array",            &jit_array);
    testing::add(suite, "jit_pointer",          &jit_pointer);
    testing::add(suite, "jit_cast",             &jit_cast);
    testing::add(suite, "jit_slice_sum",        &jit_slice_sum);
    testing::add(suite, "jit_switch",           &jit_switch);
    testing::add(suite, "jit_global",           &jit_global);
    testing::add(suite, "jit_bool",             &jit_bool);
    testing::add(suite, "jit_string_len",       &jit_string_len);
    testing::add(suite, "jit_printf",           &jit_printf);
    testing::add(suite, "jit_struct_global",    &jit_struct_global);
    testing::add(suite, "jit_array_global",     &jit_array_global);
    testing::add(suite, "jit_float",            &jit_float);
    testing::add(suite, "jit_float_cmp",        &jit_float_cmp);
    testing::add(suite, "jit_sub_slice",        &jit_sub_slice);
    testing::add(suite, "jit_union",            &jit_union);
    testing::add(suite, "jit_aggregate_arg",    &jit_aggregate_arg);
    testing::add(suite, "jit_struct_return",    &jit_struct_return);
    testing::add(suite, "jit_fn_pointer",       &jit_fn_pointer);
    testing::add(suite, "jit_short_circuit",    &jit_short_circuit);
    testing::add(suite, "jit_string_array",     &jit_string_array);
    testing::add(suite, "jit_sizeof",           &jit_sizeof);
    testing::add(suite, "jit_alignof",          &jit_alignof);
    testing::add(suite, "jit_ptr_cast_index",   &jit_ptr_cast_index);
    testing::add(suite, "jit_const_slice_index", &jit_const_slice_index);
    testing::add(suite, "jit_const_string_slice", &jit_const_string_slice);
    testing::add(suite, "jit_const_struct_table", &jit_const_struct_table);
    testing::add(suite, "opt_release_mem2reg",  &opt_release_mem2reg);
    testing::add(suite, "opt_debug_info",       &opt_debug_info);
    return testing::run();
}
