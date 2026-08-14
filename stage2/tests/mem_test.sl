import testing;
import test_util;
import mem;
import arena;
import list;
import io;
import sys;

// test_util::Counting is defined outside std, so driving std through it proves the interface is the seam.
test_util::Counting g_counting;

fn i32 arena_allocator_allocates(arena::Arena* a, const u8[]m) {
    mem::Allocator alloc = arena::allocator(a);
    u8* first = (u8*)mem::alloc_bytes(alloc, 8);
    u8* second = (u8*)mem::alloc_bytes(alloc, 8);
    if(!testing::expect_not_null((void*)first, m)) { return -1; }
    if(!testing::expect_true(first != second, m)) { return -2; }
    first[0] = 3;
    second[0] = 4;
    if(!testing::expect_eq((i32)first[0] + (i32)second[0], 7, m)) { return -3; }
    return 0;
}

// An arena releases in bulk, so free must not disturb what was handed out.
fn i32 arena_free_is_a_no_op(arena::Arena* a, const u8[]m) {
    mem::Allocator alloc = arena::allocator(a);
    u8* p = (u8*)mem::alloc_bytes(alloc, 16);
    p[0] = 9;
    mem::free_bytes(alloc, (void*)p, 16);
    if(!testing::expect_eq((i32)p[0], 9, m)) { return -1; }
    return 0;
}

fn i32 libc_allocator_round_trips(arena::Arena* a, const u8[]m) {
    mem::Allocator alloc = mem::libc_allocator();
    u8* p = (u8*)mem::alloc_bytes(alloc, 32);
    if(!testing::expect_not_null((void*)p, m)) { return -1; }
    p[0] = 5;
    p = (u8*)mem::realloc_grow_bytes(alloc, (void*)p, 32, 64);
    if(!testing::expect_not_null((void*)p, m)) { return -2; }
    if(!testing::expect_eq((i32)p[0], 5, m)) { return -3; }
    mem::free_bytes(alloc, (void*)p, 64);
    return 0;
}

// A zeroed Allocator has null thunks; every entry point has to tolerate it rather than jump to null.
fn i32 null_allocator_is_inert(arena::Arena* a, const u8[]m) {
    mem::Allocator empty;
    sys::memset(&empty, 0, sizeof(mem::Allocator));
    if(!testing::expect_null(mem::alloc_bytes(empty, 16), m)) { return -1; }
    if(!testing::expect_null(mem::realloc_grow_bytes(empty, null, 0, 16), m)) { return -2; }
    mem::free_bytes(empty, null, 0);
    return 0;
}

fn i32 list_grows_through_any_allocator(arena::Arena* a, const u8[]m) {
    sys::memset(&g_counting, 0, sizeof(test_util::Counting));
    g_counting.inner = arena::allocator(a);
    mem::Allocator alloc = test_util::counting_allocator(&g_counting);

    list::List(i32) xs = {{null, 0}, 0};
    for(i32 value = 0; value < 10; value += 1) { list::push(&xs, alloc, value); }

    if(!testing::expect_eq(xs.data.len, (u64)10, m)) { return -1; }
    if(!testing::expect_eq(xs.cap, (u64)16, m)) { return -2; }
    i32 sum = 0;
    for(u64 index = 0; index < xs.data.len; index += 1) { sum += xs.data[index]; }
    if(!testing::expect_eq(sum, 45, m)) { return -3; }
    // 4 -> 8 -> 16 is three grows, and every one goes through the caller's allocator.
    if(!testing::expect_eq(g_counting.allocs, (u64)3, m)) { return -4; }
    return 0;
}

fn i32 outbuf_writes_through_any_allocator(arena::Arena* a, const u8[]m) {
    sys::memset(&g_counting, 0, sizeof(test_util::Counting));
    g_counting.inner = arena::allocator(a);
    mem::Allocator alloc = test_util::counting_allocator(&g_counting);

    io::OutBuf buf;
    io::outbuf_init(&buf, alloc, 4);
    io::outbuf_write(&buf, "hello ");
    io::outbuf_write(&buf, "allocator");
    if(!testing::expect_eq(io::outbuf_bytes(&buf), "hello allocator", m)) { return -1; }
    if(!testing::expect_true(g_counting.allocs >= (u64)2, m)) { return -2; }
    return 0;
}

// The arena overload still exists, so the 100+ call sites that pass an arena keep working.
fn i32 outbuf_arena_overload(arena::Arena* a, const u8[]m) {
    io::OutBuf buf;
    io::outbuf_init(&buf, a, 8);
    io::outbuf_write(&buf, "arena");
    if(!testing::expect_eq(io::outbuf_bytes(&buf), "arena", m)) { return -1; }
    return 0;
}

struct Pair { i32 left; i32 right; }

fn i32 create_returns_a_typed_pointer(arena::Arena* a, const u8[]m) {
    mem::Allocator alloc = arena::allocator(a);
    Pair* p = mem::create(Pair, alloc);
    if(!testing::expect_not_null((void*)p, m)) { return -1; }
    p.left = 3;
    p.right = 4;
    if(!testing::expect_eq(p.left + p.right, 7, m)) { return -2; }
    mem::destroy(Pair, alloc, p);
    return 0;
}

fn i32 create_asks_for_the_type_size(arena::Arena* a, const u8[]m) {
    sys::memset(&g_counting, 0, sizeof(test_util::Counting));
    g_counting.inner = arena::allocator(a);
    mem::Allocator alloc = test_util::counting_allocator(&g_counting);
    if(!testing::expect_not_null((void*)mem::create(Pair, alloc), m)) { return -1; }
    if(!testing::expect_eq(g_counting.bytes, sizeof(Pair), m)) { return -2; }
    return 0;
}

fn i32 alloc_returns_a_typed_slice(arena::Arena* a, const u8[]m) {
    mem::Allocator alloc = arena::allocator(a);
    i32[] xs = mem::alloc(i32, alloc, 16);
    if(!testing::expect_not_null((void*)xs.ptr, m)) { return -1; }
    if(!testing::expect_eq(xs.len, (u64)16, m)) { return -2; }
    xs[0] = 11;
    xs[15] = 99;
    if(!testing::expect_eq(xs[0] + xs[15], 110, m)) { return -3; }
    mem::free(i32, alloc, xs);
    return 0;
}

fn i32 alloc_scales_the_request_by_element_size(arena::Arena* a, const u8[]m) {
    sys::memset(&g_counting, 0, sizeof(test_util::Counting));
    g_counting.inner = arena::allocator(a);
    mem::Allocator alloc = test_util::counting_allocator(&g_counting);
    i32[] xs = mem::alloc(i32, alloc, 8);
    if(!testing::expect_eq(xs.len, (u64)8, m)) { return -1; }
    if(!testing::expect_eq(g_counting.bytes, 8 * sizeof(i32), m)) { return -2; }
    return 0;
}

fn i32 alloc_of_a_struct_element(arena::Arena* a, const u8[]m) {
    mem::Allocator alloc = arena::allocator(a);
    Pair[] pairs = mem::alloc(Pair, alloc, 4);
    if(!testing::expect_eq(pairs.len, (u64)4, m)) { return -1; }
    pairs[3].left = 5;
    pairs[3].right = 6;
    if(!testing::expect_eq(pairs[3].left + pairs[3].right, 11, m)) { return -2; }
    return 0;
}

fn i32 generic_realloc_grow_keeps_the_elements(arena::Arena* a, const u8[]m) {
    mem::Allocator alloc = arena::allocator(a);
    i32[] xs = mem::alloc(i32, alloc, 4);
    if(!testing::expect_not_null((void*)xs.ptr, m)) { return -1; }
    for(u64 index = 0; index < xs.len; index += 1) { xs[index] = (i32)index + 1; }
    xs = mem::realloc_grow(i32, alloc, xs, 16);
    if(!testing::expect_eq(xs.len, (u64)16, m)) { return -2; }
    if(!testing::expect_eq(xs[0], 1, m)) { return -3; }
    if(!testing::expect_eq(xs[3], 4, m)) { return -4; }
    return 0;
}

// A zeroed Allocator reaches the byte layer through the generics too, so they must not deref null.
fn i32 generics_tolerate_a_null_allocator(arena::Arena* a, const u8[]m) {
    mem::Allocator empty;
    sys::memset(&empty, 0, sizeof(mem::Allocator));
    if(!testing::expect_null((void*)mem::create(Pair, empty), m)) { return -1; }
    i32[] xs = mem::alloc(i32, empty, 4);
    if(!testing::expect_null((void*)xs.ptr, m)) { return -2; }
    if(!testing::expect_eq(xs.len, (u64)0, m)) { return -3; }
    i32[] grown = mem::realloc_grow(i32, empty, xs, 8);
    if(!testing::expect_null((void*)grown.ptr, m)) { return -4; }
    if(!testing::expect_eq(grown.len, (u64)0, m)) { return -5; }
    mem::free(i32, empty, xs);
    mem::destroy(Pair, empty, null);
    return 0;
}

fn i32 generics_work_over_the_libc_allocator(arena::Arena* a, const u8[]m) {
    mem::Allocator alloc = mem::libc_allocator();
    i32[] xs = mem::alloc(i32, alloc, 8);
    if(!testing::expect_not_null((void*)xs.ptr, m)) { return -1; }
    xs[7] = 21;
    if(!testing::expect_eq(xs[7], 21, m)) { return -2; }
    mem::free(i32, alloc, xs);
    Pair* p = mem::create(Pair, alloc);
    if(!testing::expect_not_null((void*)p, m)) { return -3; }
    mem::destroy(Pair, alloc, p);
    return 0;
}

// The generic layer is what knows the element type, so it is what must pass the alignment down.
fn i32 generics_pass_the_element_alignment(arena::Arena* a, const u8[]m) {
    sys::memset(&g_counting, 0, sizeof(test_util::Counting));
    g_counting.inner = arena::allocator(a);
    mem::Allocator alloc = test_util::counting_allocator(&g_counting);
    if(!testing::expect_not_null((void*)mem::create(Pair, alloc), m)) { return -1; }
    if(!testing::expect_eq(g_counting.align, alignof(Pair), m)) { return -2; }
    i32[] xs = mem::alloc(i32, alloc, 4);
    if(!testing::expect_eq(g_counting.align, alignof(i32), m)) { return -3; }
    mem::realloc_grow(i32, alloc, xs, 8);
    if(!testing::expect_eq(g_counting.align, alignof(i32), m)) { return -4; }
    return 0;
}

fn i32 byte_entry_points_default_the_alignment(arena::Arena* a, const u8[]m) {
    sys::memset(&g_counting, 0, sizeof(test_util::Counting));
    g_counting.inner = arena::allocator(a);
    mem::Allocator alloc = test_util::counting_allocator(&g_counting);
    if(!testing::expect_not_null(mem::alloc_bytes(alloc, 16), m)) { return -1; }
    if(!testing::expect_eq(g_counting.align, (u64)8, m)) { return -2; }
    if(!testing::expect_not_null(mem::alloc_bytes(alloc, 16, 64), m)) { return -3; }
    if(!testing::expect_eq(g_counting.align, (u64)64, m)) { return -4; }
    return 0;
}

fn i32 over_alignment_through_the_arena(arena::Arena* a, const u8[]m) {
    mem::Allocator alloc = arena::allocator(a);
    void* p = mem::alloc_bytes(alloc, 32, 64);
    if(!testing::expect_not_null(p, m)) { return -1; }
    if(!testing::expect_eq((u64)p % 64, (u64)0, m)) { return -2; }
    return 0;
}

// malloc only guarantees 16, so anything stronger has to come from aligned_alloc.
fn i32 over_alignment_through_libc(arena::Arena* a, const u8[]m) {
    mem::Allocator alloc = mem::libc_allocator();
    u8* p = (u8*)mem::alloc_bytes(alloc, 64, 128);
    if(!testing::expect_not_null((void*)p, m)) { return -1; }
    if(!testing::expect_eq((u64)p % 128, (u64)0, m)) { return -2; }
    p[0] = 4;
    p[63] = 5;
    u8* grown = (u8*)mem::realloc_grow_bytes(alloc, (void*)p, 64, 256, 128);
    if(!testing::expect_not_null((void*)grown, m)) { return -3; }
    if(!testing::expect_eq((u64)grown % 128, (u64)0, m)) { return -4; }
    if(!testing::expect_eq((u64)grown[0] + (u64)grown[63], (u64)9, m)) { return -5; }
    mem::free_bytes(alloc, (void*)grown, 256, 128);
    return 0;
}

fn i32 main() {
    testing::init();
    const u8[] suite = "Allocator Tests";
    testing::add(suite, "arena_allocator_allocates",         &arena_allocator_allocates);
    testing::add(suite, "arena_free_is_a_no_op",             &arena_free_is_a_no_op);
    testing::add(suite, "libc_allocator_round_trips",        &libc_allocator_round_trips);
    testing::add(suite, "null_allocator_is_inert",           &null_allocator_is_inert);
    testing::add(suite, "list_grows_through_any_allocator",  &list_grows_through_any_allocator);
    testing::add(suite, "outbuf_writes_through_any_allocator", &outbuf_writes_through_any_allocator);
    testing::add(suite, "outbuf_arena_overload",             &outbuf_arena_overload);
    testing::add(suite, "create_returns_a_typed_pointer",    &create_returns_a_typed_pointer);
    testing::add(suite, "create_asks_for_the_type_size",     &create_asks_for_the_type_size);
    testing::add(suite, "alloc_returns_a_typed_slice",       &alloc_returns_a_typed_slice);
    testing::add(suite, "alloc_scales_the_request_by_element_size", &alloc_scales_the_request_by_element_size);
    testing::add(suite, "alloc_of_a_struct_element",         &alloc_of_a_struct_element);
    testing::add(suite, "generic_realloc_grow_keeps_the_elements", &generic_realloc_grow_keeps_the_elements);
    testing::add(suite, "generics_tolerate_a_null_allocator", &generics_tolerate_a_null_allocator);
    testing::add(suite, "generics_work_over_the_libc_allocator", &generics_work_over_the_libc_allocator);
    testing::add(suite, "generics_pass_the_element_alignment",  &generics_pass_the_element_alignment);
    testing::add(suite, "byte_entry_points_default_the_alignment", &byte_entry_points_default_the_alignment);
    testing::add(suite, "over_alignment_through_the_arena",     &over_alignment_through_the_arena);
    testing::add(suite, "over_alignment_through_libc",          &over_alignment_through_libc);
    return testing::run();
}
