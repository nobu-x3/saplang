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
    return jit_return(a, "extern { fn i32 printf(const u8* fmt, ...); } fn i32 main() { printf(\"[codegen jit_printf ok]\\n\"); return 0; }", 0, msg);
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

// Pointer arithmetic: ptr+int and ptr-int are GEPs; ptr-ptr is the element-count difference.
fn i32 jit_pointer_arithmetic(arena::Arena* a, u8[] msg) {
    return jit_return(a, "extern { fn void* malloc(u64 n); } fn i32 main() { i32* base = (i32*)malloc(16); base[0] = 10; base[1] = 20; base[2] = 30; i32* p = base + 2; i32* q = p - 1; i64 diff = p - base; return *p + *q + (i32)diff; }", 52, msg);
}

// A void* (malloc) assigned to a typed pointer var is converted to that type, so field access works.
fn i32 jit_voidptr_to_typed(arena::Arena* a, u8[] msg) {
    return jit_return(a, "struct Node { i32 v; Node* next; } extern { fn void* malloc(u64 n); } fn i32 main() { Node* p = malloc(16); p.v = 42; p.next = null; return p.v; }", 42, msg);
}

// A comparison between different int widths (i64 vs i8, same signedness) widens the narrower operand.
fn i32 jit_mixed_int_width_cmp(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { i64 x = 66; i8 lo = 65; i8 hi = 90; if(x >= lo && x <= hi) { return 7; } return 0; }", 7, msg);
}

// Writing a slice local's .ptr/.len fields makes it a memory var; fields address correctly (ptr=0, len=1).
fn i32 jit_slice_field_write(arena::Arena* a, u8[] msg) {
    return jit_return(a, "extern { fn void* malloc(u64 n); } fn i32 main() { u8[] s; s.ptr = (u8*)malloc(4); s.len = 3; s.ptr[0] = 9; return (i32)s.len + (i32)s.ptr[0]; }", 12, msg);
}

// Reading a slice field (.ptr/.len) through a pointer-to-slice loads the slice first (was ExtractValue on a raw pointer).
fn i32 jit_slice_ptr_field_read(arena::Arena* a, u8[] msg) {
    return jit_return(a, "extern { fn void* malloc(u64 n); } fn u64 slen(i32[]* s) { return s.len; } fn i32 sfirst(i32[]* s) { return s.ptr[0]; } fn i32 main() { i32[] xs; xs.ptr = (i32*)malloc(8); xs.len = 2; xs.ptr[0] = 40; xs.ptr[1] = 99; return sfirst(&xs) + (i32)slen(&xs); }", 42, msg);
}

// A `fn Type` comptime function selects a type; an alias binds it and it's used as a runtime var type.
fn i32 jit_type_alias(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn Type choose(bool b) { if(b) { return i64; } return i32; } alias W = choose(false); fn i32 main() { W x = 40; return (i32)x + 2; }", 42, msg);
}

// A comptime fn returns an anonymous struct type; an alias binds it and it's used as a runtime struct.
fn i32 jit_anon_struct_type(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn Type mk() { return struct { i32 x; i32 y; }; } alias P = mk(); fn i32 main() { P p; p.x = 40; p.y = 2; return p.x + p.y; }", 42, msg);
}

// A generic `fn Type Vec(comptime Type T)` monomorphizes to a distinct concrete struct type per type-arg.
fn i32 jit_generic_struct(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn Type Vec(comptime Type T) { return struct { T* ptr; u64 len; }; } alias VI = Vec(i32); alias VU = Vec(u8); extern { fn void* malloc(u64 n); } fn i32 main() { VI a; a.ptr = (i32*)malloc(8); a.ptr[0] = 30; a.len = 1; VU b; b.ptr = (u8*)malloc(4); b.ptr[0] = (u8)12; b.len = 1; return a.ptr[0] + (i32)b.ptr[0]; }", 42, msg);
}

// A comptime type call in general type positions: a direct `Box(i32)` var and a generic fn with a `Box(T)*` param.
fn i32 jit_generic_struct_param(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn Type Box(comptime Type T) { return struct { T value; }; } fn i32 unbox(comptime Type T, Box(T)* b) { return (i32)b.value; } fn i32 main() { Box(i32) b; b.value = 42; return unbox(i32, &b); }", 42, msg);
}

// A monomorphized generic fn runs end-to-end, reading slice fields through a T[]* param (generics + the fixed slice path).
fn i32 jit_generic_slice(arena::Arena* a, u8[] msg) {
    return jit_return(a, "extern { fn void* malloc(u64 n); } fn T pick(comptime Type T, T[]* s, u64 i) { return s.ptr[i]; } fn u64 glen(comptime Type T, T[]* s) { return s.len; } fn i32 main() { i32[] xs; xs.ptr = (i32*)malloc(12); xs.len = 3; xs.ptr[0] = 10; xs.ptr[1] = 20; xs.ptr[2] = 12; return pick(&xs, 1) + pick(&xs, 2) + (i32)glen(&xs); }", 35, msg);
}

// A function pointer is nullable and equality-comparable: assign null, compare, reassign, call.
fn i32 jit_fnptr_null(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 dbl(i32 x) { return x * 2; } fn i32 main() { fn* i32(i32) f = null; if(f != null) { return 1; } f = dbl; if(f == null) { return 2; } return f(21); }", 42, msg);
}

// int + ptr and pointer compound-assign (p += n, p -= n) also route through the GEP.
fn i32 jit_pointer_compound(arena::Arena* a, u8[] msg) {
    return jit_return(a, "extern { fn void* malloc(u64 n); } fn i32 main() { i32* base = (i32*)malloc(16); base[0]=10; base[1]=20; base[2]=30; base[3]=40; i32* p = 1 + base; p += 2; i32* q = base; q += 3; q -= 1; return *p + *q; }", 70, msg);
}

// A field read on a by-value struct rvalue (a call result) spills the rvalue to a temp before addressing the field.
fn i32 jit_rvalue_struct_field(arena::Arena* a, u8[] msg) {
    return jit_return(a, "struct P { i32 x; i32 y; } fn P make(i32 v) { P p = {.x = v, .y = v + 1}; return p; } fn i32 main() { return make(40).x + make(40).y; }", 81, msg);
}

// A nested field read through an rvalue struct: make().inner is itself an rvalue struct addressed for the inner field.
fn i32 jit_rvalue_field_nested(arena::Arena* a, u8[] msg) {
    return jit_return(a, "struct Inner { i32 z; } struct Outer { Inner inner; i32 w; } fn Outer make() { Outer o = {.inner = {.z = 30}, .w = 12}; return o; } fn i32 main() { return make().inner.z + make().w; }", 42, msg);
}

// Compound-assign combines at the lhs width: a narrower rhs is widened (SSA local `h ^= b`, memory var `m += c`).
fn i32 jit_compound_assign_widen(arena::Arena* a, u8[] msg) {
    return jit_return(a, "fn i32 main() { u32 h = 100; u8 b = 7; h ^= b; u32 m = 200; u32* mp = &m; u8 c = 4; m += c; return (i32)h + (i32)(*mp); }", 303, msg);
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

// An enum acts as its base int in arithmetic; the runtime value is the underlying integer.
fn i32 jit_enum_arithmetic(arena::Arena* a, u8[] msg) {
    return jit_return(a, "enum C : i32 { R, G, B } fn i32 main() { C c = C::B; return c - 1 + (2 * c); }", 5, msg);
}

// Unary bitwise-not on an enum operates on its base int at runtime.
fn i32 jit_enum_unary(arena::Arena* a, u8[] msg) {
    return jit_return(a, "enum F : u8 { A = 1 } fn i32 main() { u8 v = ~F::A; return (i32)(v & 6); }", 6, msg);
}

// A string literal into a fixed-array const global stores the bytes inline (NUL included).
fn i32 jit_const_array_string(arena::Arena* a, u8[] msg) {
    return jit_return(a, "const u8[4] MSG = \"abc\"; fn i32 main() { return (i32)MSG[0] + (i32)MSG[3]; }", 97, msg);
}

// A struct local gets a DICompositeType; SSA scalar locals get dbg_value records at each assignment. Verifies (DISubprogram present).
fn i32 opt_debug_aggregate_and_ssa(arena::Arena* a, u8[] msg) {
    arena::Arena* ja = fresh_arena(a);
    module::Module* m = test_util::frontend(ja, "struct P { i32 x; i32 y; } fn i32 main() { P p = {.x = 1, .y = 2}; i32 s = 0; for(i32 i = 0; i < p.y; i = i + 1) { s = s + p.x; } return s; }");
    if(!testing::expect_eq(test_util::error_count(m), (u64)0, msg)) { return -1; }
    sapir::SapirModule* sm = lower::lower_module(m);
    u8[] ir = codegen::codegen_ir_string(sm, ja, codegen::BuildConfig::Debug);
    if(!contains(ir, "DISubprogram")) { return -2; }
    if(!contains(ir, "DICompositeType")) { return -3; }
    if(!contains(ir, "dbg_value")) { return -4; }
    return 0;
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

// GEP sign-extends a narrow index, so an unsigned one past 0x7f must be zero-extended first.
fn i32 unsigned_index_zero_extends(arena::Arena* a, u8[] msg) {
    arena::Arena* ja = fresh_arena(a);
    module::Module* m = test_util::frontend(ja, "fn u8 pick(u8[256] table, u8 index) { return table[index]; }");
    if(!testing::expect_eq(test_util::error_count(m), (u64)0, msg)) { return -1; }
    sapir::SapirModule* sm = lower::lower_module(m);
    u8[] ir = codegen::codegen_ir_string(sm, ja, codegen::BuildConfig::Debug);
    if(!contains(ir, "zext")) { return -2; }
    if(contains(ir, "sext")) { return -3; }
    return 0;
}

fn i32 signed_index_sign_extends(arena::Arena* a, u8[] msg) {
    arena::Arena* ja = fresh_arena(a);
    module::Module* m = test_util::frontend(ja, "fn i32 pick(i32[8] table, i8 index) { return table[index]; }");
    if(!testing::expect_eq(test_util::error_count(m), (u64)0, msg)) { return -1; }
    sapir::SapirModule* sm = lower::lower_module(m);
    u8[] ir = codegen::codegen_ir_string(sm, ja, codegen::BuildConfig::Debug);
    if(!contains(ir, "sext")) { return -2; }
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
    testing::add(suite, "jit_voidptr_to_typed", &jit_voidptr_to_typed);
    testing::add(suite, "jit_mixed_int_width_cmp", &jit_mixed_int_width_cmp);
    testing::add(suite, "jit_slice_field_write", &jit_slice_field_write);
    testing::add(suite, "jit_slice_ptr_field_read", &jit_slice_ptr_field_read);
    testing::add(suite, "jit_type_alias",          &jit_type_alias);
    testing::add(suite, "jit_anon_struct_type",    &jit_anon_struct_type);
    testing::add(suite, "jit_generic_struct",      &jit_generic_struct);
    testing::add(suite, "jit_generic_struct_param", &jit_generic_struct_param);
    testing::add(suite, "jit_generic_slice",       &jit_generic_slice);
    testing::add(suite, "jit_fnptr_null",       &jit_fnptr_null);
    testing::add(suite, "jit_pointer_arithmetic", &jit_pointer_arithmetic);
    testing::add(suite, "jit_pointer_compound",  &jit_pointer_compound);
    testing::add(suite, "jit_rvalue_struct_field", &jit_rvalue_struct_field);
    testing::add(suite, "jit_rvalue_field_nested", &jit_rvalue_field_nested);
    testing::add(suite, "jit_compound_assign_widen", &jit_compound_assign_widen);
    testing::add(suite, "jit_const_slice_index", &jit_const_slice_index);
    testing::add(suite, "jit_const_string_slice", &jit_const_string_slice);
    testing::add(suite, "jit_const_struct_table", &jit_const_struct_table);
    testing::add(suite, "jit_enum_arithmetic",   &jit_enum_arithmetic);
    testing::add(suite, "jit_enum_unary",        &jit_enum_unary);
    testing::add(suite, "jit_const_array_string", &jit_const_array_string);
    testing::add(suite, "opt_release_mem2reg",  &opt_release_mem2reg);
    testing::add(suite, "opt_debug_info",       &opt_debug_info);
    testing::add(suite, "opt_debug_aggregate_and_ssa", &opt_debug_aggregate_and_ssa);
    testing::add(suite, "unsigned_index_zero_extends", &unsigned_index_zero_extends);
    testing::add(suite, "signed_index_sign_extends", &signed_index_sign_extends);
    return testing::run();
}
