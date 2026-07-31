import testing;
import list;
import arena;
import sys;

// Scalar elements: growth doubles (min 4), values survive the reallocs.
fn i32 dyn_push_grows(arena::Arena* a, const u8[]m) {
    i32[] xs = {null, 0}; u64 cap = 0;
    for(i32 i = 0; i < 10; i = i + 1) { list::dyn_push(&xs, &cap, arena::allocator(a), i * i); }
    if(!testing::expect_eq(xs.len, (u64)10, m)) { return -1; }
    if(!testing::expect_eq(cap, (u64)16, m)) { return -2; }
    i32 sum = 0;
    for(u64 j = 0; j < xs.len; j = j + 1) { sum = sum + xs.ptr[j]; }
    if(!testing::expect_eq(sum, 285, m)) { return -3; }
    return 0;
}

// Pointer elements (the ListBuilder use case): a distinct monomorphization from the scalar one.
fn i32 dyn_push_pointer_elem(arena::Arena* a, const u8[]m) {
    i32 v0 = 7; i32 v1 = 8;
    i32*[] ps = {null, 0}; u64 cap = 0;
    list::dyn_push(&ps, &cap, arena::allocator(a), &v0);
    list::dyn_push(&ps, &cap, arena::allocator(a), &v1);
    if(!testing::expect_eq(ps.len, (u64)2, m)) { return -1; }
    if(!testing::expect_eq(*ps.ptr[0] + *ps.ptr[1], 15, m)) { return -2; }
    return 0;
}

// List(T): the bundled generic dynamic array — growth doubles (min 4), values survive the reallocs.
fn i32 list_push_grows(arena::Arena* a, const u8[]m) {
    list::List(i32) xs; xs.ptr = null; xs.len = 0; xs.cap = 0;
    for(i32 i = 0; i < 10; i = i + 1) { list::push(&xs, arena::allocator(a), i * i); }
    if(!testing::expect_eq(xs.len, (u64)10, m)) { return -1; }
    if(!testing::expect_eq(xs.cap, (u64)16, m)) { return -2; }
    i32 sum = 0;
    for(u64 j = 0; j < xs.len; j = j + 1) { sum = sum + xs.ptr[j]; }
    if(!testing::expect_eq(sum, 285, m)) { return -3; }
    return 0;
}

// List(T) with pointer elements: a distinct monomorphization; explicit type argument.
fn i32 list_push_pointer_elem(arena::Arena* a, const u8[]m) {
    i32 v0 = 7; i32 v1 = 8;
    list::List(i32*) ps; ps.ptr = null; ps.len = 0; ps.cap = 0;
    list::push(i32*, &ps, arena::allocator(a), &v0);
    list::push(i32*, &ps, arena::allocator(a), &v1);
    if(!testing::expect_eq(ps.len, (u64)2, m)) { return -1; }
    if(!testing::expect_eq(*ps.ptr[0] + *ps.ptr[1], 15, m)) { return -2; }
    return 0;
}

fn i32 main() {
    testing::init();
    const u8[] suite = "List Tests";
    testing::add(suite, "dyn_push_grows", &dyn_push_grows);
    testing::add(suite, "dyn_push_pointer_elem", &dyn_push_pointer_elem);
    testing::add(suite, "list_push_grows", &list_push_grows);
    testing::add(suite, "list_push_pointer_elem", &list_push_pointer_elem);
    return testing::run();
}
