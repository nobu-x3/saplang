import testing;
import arena;
import list;
import mem;

fn i32 alloc_with_null_arena(arena::Arena* a, const u8[]m) {
    void* p = arena::alloc(null, 16);
    if(!testing::expect_null(p, m)) {
        return -1;
    }
    return 0;
}

fn i32 alloc_zero_size(arena::Arena* a, const u8[]m) {
    arena::Arena local = {64, null};
    defer arena::free(&local);
    void* p = arena::alloc(&local, 0);
    if(!testing::expect_null(p, m)) {
        return -1;
    }
    return 0;
}

fn i32 alloc_returns_pointer(arena::Arena* a, const u8[]m) {
    arena::Arena local = {64, null};
    defer arena::free(&local);
    void* p = arena::alloc(&local, 16);
    if(!testing::expect_not_null(p, m)) {
        return -1;
    }
    return 0;
}

fn i32 alloc_consecutive_are_aligned(arena::Arena* a, const u8[]m) {
    arena::Arena local = {64, null};
    defer arena::free(&local);
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
    defer arena::free(&local);
    void* p1 = arena::alloc(&local, 8);
    void* p2 = arena::alloc(&local, 8);
    if(!testing::expect_ne(p1, p2, m)) { return -1; }
    return 0;
}

fn i32 alloc_larger_than_page(arena::Arena* a, const u8[]m) {
    arena::Arena local = {16, null};
    defer arena::free(&local);
    void* p = arena::alloc(&local, 64);
    if(!testing::expect_not_null(p, m)) { return -1; }
    return 0;
}

fn i32 realloc_grow_copies_bytes(arena::Arena* a, const u8[]m) {
    arena::Arena local = {128, null};
    defer arena::free(&local);
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
    defer arena::free(&local);
    void* fresh = arena::realloc_grow(&local, null, 0, 16);
    if(!testing::expect_not_null(fresh, m)) { return -1; }
    return 0;
}

fn i32 alloc_honours_an_explicit_alignment(arena::Arena* a, const u8[]m) {
    arena::Arena local = {512, null};
    defer arena::free(&local);
    if(!testing::expect_not_null(arena::alloc(&local, 1), m)) { return -1; }
    void* aligned = arena::alloc(&local, 16, 64);
    if(!testing::expect_not_null(aligned, m)) { return -2; }
    if(!testing::expect_eq((u64)aligned % 64, (u64)0, m)) { return -3; }
    return 0;
}

// Every step is a multiple of 8, so an odd cursor must be walked forward, not just rounded.
fn i32 alignment_holds_from_an_unaligned_cursor(arena::Arena* a, const u8[]m) {
    arena::Arena local = {512, null};
    defer arena::free(&local);
    for(u64 step = 1; step <= 5; step = step + 1) {
        if(!testing::expect_not_null(arena::alloc(&local, step), m)) { return -1; }
        void* aligned = arena::alloc(&local, 8, 32);
        if(!testing::expect_not_null(aligned, m)) { return -2; }
        if(!testing::expect_eq((u64)aligned % 32, (u64)0, m)) { return -3; }
    }
    return 0;
}

// A fresh page only carries malloc's alignment, so the page needs slack to step forward in.
fn i32 alignment_holds_on_a_fresh_page(arena::Arena* a, const u8[]m) {
    arena::Arena local = {16, null};
    defer arena::free(&local);
    u8* aligned = arena::alloc(&local, 64, 128);
    if(!testing::expect_not_null((void*)aligned, m)) { return -1; }
    if(!testing::expect_eq((u64)aligned % 128, (u64)0, m)) { return -2; }
    // Touching both ends catches a page that was not grown to cover the alignment step.
    aligned[0] = 1;
    aligned[63] = 2;
    if(!testing::expect_eq((u64)aligned[0] + (u64)aligned[63], (u64)3, m)) { return -3; }
    return 0;
}

fn i32 aligned_allocations_stay_usable(arena::Arena* a, const u8[]m) {
    arena::Arena local = {512, null};
    defer arena::free(&local);
    u8* first = arena::alloc(&local, 32, 64);
    u8* second = arena::alloc(&local, 32, 64);
    if(!testing::expect_not_null((void*)first, m)) { return -1; }
    if(!testing::expect_ne((void*)first, (void*)second, m)) { return -2; }
    if(!testing::expect_eq((u64)second % 64, (u64)0, m)) { return -3; }
    if(!testing::expect_ge((u64)second, (u64)first + 32, m)) { return -4; }
    first[0] = 1;
    first[31] = 2;
    second[0] = 3;
    second[31] = 4;
    if(!testing::expect_eq((u64)first[0] + (u64)first[31] + (u64)second[0] + (u64)second[31], (u64)10, m)) { return -5; }
    return 0;
}

// An alignment below the arena's own floor must not weaken it.
fn i32 alignment_below_the_floor_is_ignored(arena::Arena* a, const u8[]m) {
    arena::Arena local = {64, null};
    defer arena::free(&local);
    if(!testing::expect_not_null(arena::alloc(&local, 1, 1), m)) { return -1; }
    void* second = arena::alloc(&local, 1, 1);
    if(!testing::expect_eq((u64)second % 8, (u64)0, m)) { return -2; }
    return 0;
}

fn i32 realloc_grow_honours_an_explicit_alignment(arena::Arena* a, const u8[]m) {
    arena::Arena local = {512, null};
    defer arena::free(&local);
    u8* p = arena::alloc(&local, 8, 64);
    if(!testing::expect_not_null((void*)p, m)) { return -1; }
    p[0] = 7;
    if(!testing::expect_not_null(arena::alloc(&local, 1), m)) { return -2; }
    u8* grown = arena::realloc_grow(&local, p, 8, 32, 64);
    if(!testing::expect_not_null((void*)grown, m)) { return -3; }
    if(!testing::expect_eq((u64)grown % 64, (u64)0, m)) { return -4; }
    if(!testing::expect_eq((u64)grown[0], (u64)7, m)) { return -5; }
    return 0;
}

fn i32 free_with_null_arena(arena::Arena* a, const u8[]m) {
    arena::free(null);
    return 0;
}

fn i32 free_empty_arena(arena::Arena* a, const u8[]m) {
    arena::Arena local = {64, null};
    arena::free(&local);
    if(!testing::expect_null((void*)local.head, m)) { return -1; }
    return 0;
}

fn i32 free_single_page(arena::Arena* a, const u8[]m) {
    arena::Arena local = {64, null};
    void* p = arena::alloc(&local, 16);
    if(!testing::expect_not_null(p, m)) { return -1; }
    arena::free(&local);
    if(!testing::expect_null((void*)local.head, m)) { return -2; }
    return 0;
}

fn i32 free_multiple_pages(arena::Arena* a, const u8[]m) {
    arena::Arena local = {16, null};
    defer arena::free(&local);
    for(u64 i = 0; i < 3; i = i + 1) {
        if(!testing::expect_not_null(arena::alloc(&local, 16), m)) { return -1; }
    }
    arena::free(&local);
    if(!testing::expect_null((void*)local.head, m)) { return -2; }
    return 0;
}

// A zero default page size gives every allocation its own exact-size page.
fn i32 free_arena_with_zero_page_size(arena::Arena* a, const u8[]m) {
    arena::Arena local = {0, null};
    defer arena::free(&local);
    for(u64 i = 0; i < 8; i = i + 1) {
        if(!testing::expect_not_null(arena::alloc(&local, 24), m)) { return -1; }
    }
    arena::free(&local);
    if(!testing::expect_null((void*)local.head, m)) { return -2; }
    return 0;
}

fn i32 free_oversized_page(arena::Arena* a, const u8[]m) {
    arena::Arena local = {16, null};
    if(!testing::expect_not_null(arena::alloc(&local, 128), m)) { return -1; }
    arena::free(&local);
    if(!testing::expect_null((void*)local.head, m)) { return -2; }
    return 0;
}

fn i32 free_after_realloc_grow(arena::Arena* a, const u8[]m) {
    arena::Arena local = {16, null};
    defer arena::free(&local);
    u8* p = arena::alloc(&local, 8);
    if(!testing::expect_not_null(p, m)) { return -1; }
    p = arena::realloc_grow(&local, p, 8, 32);
    if(!testing::expect_not_null(p, m)) { return -2; }
    p = arena::realloc_grow(&local, p, 32, 64);
    if(!testing::expect_not_null(p, m)) { return -3; }
    arena::free(&local);
    if(!testing::expect_null((void*)local.head, m)) { return -4; }
    return 0;
}

fn i32 free_twice_is_safe(arena::Arena* a, const u8[]m) {
    arena::Arena local = {16, null};
    defer arena::free(&local);
    if(!testing::expect_not_null(arena::alloc(&local, 8), m)) { return -1; }
    if(!testing::expect_not_null(arena::alloc(&local, 8), m)) { return -2; }
    arena::free(&local);
    arena::free(&local);
    if(!testing::expect_null((void*)local.head, m)) { return -3; }
    return 0;
}

// A fresh page starts at offset 0, so the follow-up allocation still fits beside it.
fn i32 alloc_after_free_starts_a_fresh_page(arena::Arena* a, const u8[]m) {
    arena::Arena local = {64, null};
    defer arena::free(&local);
    if(!testing::expect_not_null(arena::alloc(&local, 40), m)) { return -1; }
    arena::free(&local);
    if(!testing::expect_null((void*)local.head, m)) { return -5; }
    u8* p1 = arena::alloc(&local, 40);
    u8* p2 = arena::alloc(&local, 16);
    if(!testing::expect_not_null(p1, m)) { return -2; }
    if(!testing::expect_not_null(p2, m)) { return -3; }
    if(!testing::expect_eq((u64)p2 - (u64)p1, 40, m)) { return -4; }
    return 0;
}

fn i32 arena_is_reusable_after_free(arena::Arena* a, const u8[]m) {
    arena::Arena local = {64, null};
    defer arena::free(&local);
    if(!testing::expect_not_null(arena::alloc(&local, 40), m)) { return -1; }
    arena::free(&local);
    if(!testing::expect_null((void*)local.head, m)) { return -7; }

    u8* p1 = arena::alloc(&local, 1);
    u8* p2 = arena::alloc(&local, 1);
    if(!testing::expect_not_null(p1, m)) { return -2; }
    if(!testing::expect_ne((void*)p1, (void*)p2, m)) { return -3; }
    if(!testing::expect_eq((u64)p2 - (u64)p1, 8, m)) { return -4; }
    p1[0] = 7;
    p2[0] = 9;
    if(!testing::expect_eq((u64)p1[0], 7, m)) { return -5; }
    if(!testing::expect_eq((u64)p2[0], 9, m)) { return -6; }
    return 0;
}

fn i32 free_through_the_allocator_interface(arena::Arena* a, const u8[]m) {
    arena::Arena local = {32, null};
    defer arena::free(&local);
    mem::Allocator alloc = arena::allocator(&local);
    if(!testing::expect_not_null(mem::alloc_bytes(alloc, 24), m)) { return -1; }
    if(!testing::expect_not_null(mem::alloc_bytes(alloc, 24), m)) { return -2; }
    arena::free(&local);
    if(!testing::expect_null((void*)local.head, m)) { return -3; }
    if(!testing::expect_not_null(mem::alloc_bytes(alloc, 24), m)) { return -4; }
    return 0;
}

fn i32 free_releases_list_backing_store(arena::Arena* a, const u8[]m) {
    arena::Arena local = {16, null};
    defer arena::free(&local);
    mem::Allocator alloc = arena::allocator(&local);
    list::List(i32) values = {null, 0, 0};
    for(i32 i = 0; i < 32; i = i + 1) {
        list::push(&values, alloc, i);
    }
    if(!testing::expect_eq(values.len, 32, m)) { return -1; }
    if(!testing::expect_eq(values.ptr[31], 31, m)) { return -2; }
    arena::free(&local);
    if(!testing::expect_null((void*)local.head, m)) { return -3; }

    list::List(i32) again = {null, 0, 0};
    list::push(&again, alloc, 5);
    if(!testing::expect_eq(again.ptr[0], 5, m)) { return -4; }
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
    testing::add(suite, "alloc_honours_an_explicit_alignment", &alloc_honours_an_explicit_alignment);
    testing::add(suite, "alignment_holds_from_an_unaligned_cursor", &alignment_holds_from_an_unaligned_cursor);
    testing::add(suite, "alignment_holds_on_a_fresh_page", &alignment_holds_on_a_fresh_page);
    testing::add(suite, "aligned_allocations_stay_usable", &aligned_allocations_stay_usable);
    testing::add(suite, "alignment_below_the_floor_is_ignored", &alignment_below_the_floor_is_ignored);
    testing::add(suite, "realloc_grow_honours_an_explicit_alignment", &realloc_grow_honours_an_explicit_alignment);
    testing::add(suite, "free_with_null_arena", &free_with_null_arena);
    testing::add(suite, "free_empty_arena", &free_empty_arena);
    testing::add(suite, "free_single_page", &free_single_page);
    testing::add(suite, "free_multiple_pages", &free_multiple_pages);
    testing::add(suite, "free_arena_with_zero_page_size", &free_arena_with_zero_page_size);
    testing::add(suite, "free_oversized_page", &free_oversized_page);
    testing::add(suite, "free_after_realloc_grow", &free_after_realloc_grow);
    testing::add(suite, "free_twice_is_safe", &free_twice_is_safe);
    testing::add(suite, "alloc_after_free_starts_a_fresh_page", &alloc_after_free_starts_a_fresh_page);
    testing::add(suite, "arena_is_reusable_after_free", &arena_is_reusable_after_free);
    testing::add(suite, "free_through_the_allocator_interface", &free_through_the_allocator_interface);
    testing::add(suite, "free_releases_list_backing_store", &free_releases_list_backing_store);
    return testing::run();
}
