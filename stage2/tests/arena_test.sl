import testing;
import arena;

fn i32 alloc_with_null_arena(arena::Arena* a, const u8[]m) {
    void* p = arena::alloc(null, 16);
    if(!testing::expect_null(p, m)) {
        return -1;
    }
    return 0;
}

fn i32 alloc_zero_size(arena::Arena* a, const u8[]m) {
    arena::Arena local = {64, null};
    void* p = arena::alloc(&local, 0);
    if(!testing::expect_null(p, m)) {
        return -1;
    }
    return 0;
}

fn i32 alloc_returns_pointer(arena::Arena* a, const u8[]m) {
    arena::Arena local = {64, null};
    void* p = arena::alloc(&local, 16);
    if(!testing::expect_not_null(p, m)) {
        return -1;
    }
    return 0;
}

fn i32 alloc_consecutive_are_aligned(arena::Arena* a, const u8[]m) {
    arena::Arena local = {64, null};
    void* p1 = arena::alloc(&local, 1);
    void* p2 = arena::alloc(&local, 1);
    if(!testing::expect_not_null(p1, m)) { return -1; }
    if(!testing::expect_not_null(p2, m)) { return -2; }
    u64 diff = (u64)p2 - (u64)p1;
    if(!testing::expect_eq(diff, 8, m)) { return -3; }
    return 0;
}

fn i32 alloc_returns_distinct(arena::Arena* a, const u8[]m) {
    arena::Arena local = {64, null};
    void* p1 = arena::alloc(&local, 8);
    void* p2 = arena::alloc(&local, 8);
    if(!testing::expect_ne(p1, p2, m)) { return -1; }
    return 0;
}

fn i32 alloc_larger_than_page(arena::Arena* a, const u8[]m) {
    arena::Arena local = {16, null};
    void* p = arena::alloc(&local, 64);
    if(!testing::expect_not_null(p, m)) { return -1; }
    return 0;
}

fn i32 realloc_grow_copies_bytes(arena::Arena* a, const u8[]m) {
    arena::Arena local = {128, null};
    u8* old = arena::alloc(&local, 4);
    if(!testing::expect_not_null(old, m)) { return -1; }
    old[0] = 1;
    old[1] = 2;
    old[2] = 3;
    old[3] = 4;
    u8* fresh = arena::realloc_grow(&local, old, 4, 8);
    if(!testing::expect_not_null(fresh, m)) { return -2; }
    if(!testing::expect_eq((u64)fresh[0], 1, m)) { return -3; }
    if(!testing::expect_eq((u64)fresh[3], 4, m)) { return -4; }
    return 0;
}

fn i32 realloc_grow_with_null_old(arena::Arena* a, const u8[]m) {
    arena::Arena local = {64, null};
    void* fresh = arena::realloc_grow(&local, null, 0, 16);
    if(!testing::expect_not_null(fresh, m)) { return -1; }
    return 0;
}

fn i32 main() {
    testing::init();
    const u8[] suite = "Arena Tests";
    testing::add(suite, "alloc_with_null_arena", &alloc_with_null_arena);
    testing::add(suite, "alloc_zero_size", &alloc_zero_size);
    testing::add(suite, "alloc_returns_pointer", &alloc_returns_pointer);
    testing::add(suite, "alloc_consecutive_are_aligned", &alloc_consecutive_are_aligned);
    testing::add(suite, "alloc_returns_distinct", &alloc_returns_distinct);
    testing::add(suite, "alloc_larger_than_page", &alloc_larger_than_page);
    testing::add(suite, "realloc_grow_copies_bytes", &realloc_grow_copies_bytes);
    testing::add(suite, "realloc_grow_with_null_old", &realloc_grow_with_null_old);
    return testing::run();
}
