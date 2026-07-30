import testing;
import test_util;
import mem;
import arena;
import list;
import io;
import sys;

// test_util::Counting is defined outside std, so driving std through it proves the interface is the seam.
test_util::Counting g_counting;

fn i32 arena_allocator_allocates(arena::Arena* a, u8[] m) {
    mem::Allocator alloc = arena::allocator(a);
    u8* first = (u8*)mem::alloc(alloc, 8);
    u8* second = (u8*)mem::alloc(alloc, 8);
    if(!testing::expect_not_null((void*)first, m)) { return -1; }
    if(!testing::expect_true(first != second, m)) { return -2; }
    first[0] = 3;
    second[0] = 4;
    if(!testing::expect_eq((i32)first[0] + (i32)second[0], 7, m)) { return -3; }
    return 0;
}

// An arena releases in bulk, so free must not disturb what was handed out.
fn i32 arena_free_is_a_no_op(arena::Arena* a, u8[] m) {
    mem::Allocator alloc = arena::allocator(a);
    u8* p = (u8*)mem::alloc(alloc, 16);
    p[0] = 9;
    mem::free(alloc, (void*)p, 16);
    if(!testing::expect_eq((i32)p[0], 9, m)) { return -1; }
    return 0;
}

fn i32 libc_allocator_round_trips(arena::Arena* a, u8[] m) {
    mem::Allocator alloc = mem::libc_allocator();
    u8* p = (u8*)mem::alloc(alloc, 32);
    if(!testing::expect_not_null((void*)p, m)) { return -1; }
    p[0] = 5;
    p = (u8*)mem::realloc_grow(alloc, (void*)p, 32, 64);
    if(!testing::expect_not_null((void*)p, m)) { return -2; }
    if(!testing::expect_eq((i32)p[0], 5, m)) { return -3; }
    mem::free(alloc, (void*)p, 64);
    return 0;
}

// A zeroed Allocator has null thunks; every entry point has to tolerate it rather than jump to null.
fn i32 null_allocator_is_inert(arena::Arena* a, u8[] m) {
    mem::Allocator empty;
    sys::memset(&empty, 0, sizeof(mem::Allocator));
    if(!testing::expect_null(mem::alloc(empty, 16), m)) { return -1; }
    if(!testing::expect_null(mem::realloc_grow(empty, null, 0, 16), m)) { return -2; }
    mem::free(empty, null, 0);
    return 0;
}

fn i32 list_grows_through_any_allocator(arena::Arena* a, u8[] m) {
    sys::memset(&g_counting, 0, sizeof(test_util::Counting));
    g_counting.inner = arena::allocator(a);
    mem::Allocator alloc = test_util::counting_allocator(&g_counting);

    list::List(i32) xs = {null, 0, 0};
    for(i32 value = 0; value < 10; value += 1) { list::push(&xs, alloc, value); }

    if(!testing::expect_eq(xs.len, (u64)10, m)) { return -1; }
    if(!testing::expect_eq(xs.cap, (u64)16, m)) { return -2; }
    i32 sum = 0;
    for(u64 index = 0; index < xs.len; index += 1) { sum += xs.ptr[index]; }
    if(!testing::expect_eq(sum, 45, m)) { return -3; }
    // 4 -> 8 -> 16 is three grows, and every one goes through the caller's allocator.
    if(!testing::expect_eq(g_counting.allocs, (u64)3, m)) { return -4; }
    return 0;
}

fn i32 outbuf_writes_through_any_allocator(arena::Arena* a, u8[] m) {
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
fn i32 outbuf_arena_overload(arena::Arena* a, u8[] m) {
    io::OutBuf buf;
    io::outbuf_init(&buf, a, 8);
    io::outbuf_write(&buf, "arena");
    if(!testing::expect_eq(io::outbuf_bytes(&buf), "arena", m)) { return -1; }
    return 0;
}

fn i32 main() {
    testing::init();
    u8[] suite = "Allocator Tests";
    testing::add(suite, "arena_allocator_allocates",         &arena_allocator_allocates);
    testing::add(suite, "arena_free_is_a_no_op",             &arena_free_is_a_no_op);
    testing::add(suite, "libc_allocator_round_trips",        &libc_allocator_round_trips);
    testing::add(suite, "null_allocator_is_inert",           &null_allocator_is_inert);
    testing::add(suite, "list_grows_through_any_allocator",  &list_grows_through_any_allocator);
    testing::add(suite, "outbuf_writes_through_any_allocator", &outbuf_writes_through_any_allocator);
    testing::add(suite, "outbuf_arena_overload",             &outbuf_arena_overload);
    return testing::run();
}
