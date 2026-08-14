import testing;
import bump_arena;
import arena;
import mem;
import list;

fn i32 init_with_null_arena(arena::Arena* a, const u8[]m) {
    if(!testing::expect_false(bump_arena::init(null, 64), m)) { return -1; }
    return 0;
}

fn i32 init_zero_size(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    if(!testing::expect_false(bump_arena::init(&local, 0), m)) { return -1; }
    if(!testing::expect_null((void*)local.data.ptr, m)) { return -2; }
    if(!testing::expect_null(bump_arena::alloc(&local, 8), m)) { return -3; }
    return 0;
}

fn i32 init_takes_the_block_up_front(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    if(!testing::expect_true(bump_arena::init(&local, 256), m)) { return -1; }
    defer bump_arena::deinit(&local);
    if(!testing::expect_not_null((void*)local.data.ptr, m)) { return -2; }
    if(!testing::expect_eq(local.cap, (u64)256, m)) { return -3; }
    if(!testing::expect_eq(local.data.len, (u64)0, m)) { return -4; }
    return 0;
}

fn i32 alloc_with_null_arena(arena::Arena* a, const u8[]m) {
    if(!testing::expect_null(bump_arena::alloc(null, 16), m)) { return -1; }
    return 0;
}

fn i32 alloc_zero_size(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 64);
    defer bump_arena::deinit(&local);
    if(!testing::expect_null(bump_arena::alloc(&local, 0), m)) { return -1; }
    return 0;
}

fn i32 alloc_bumps_within_the_block(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 64);
    defer bump_arena::deinit(&local);
    u8* first = bump_arena::alloc(&local, 1);
    u8* second = bump_arena::alloc(&local, 1);
    if(!testing::expect_not_null((void*)first, m)) { return -1; }
    if(!testing::expect_ne((void*)first, (void*)second, m)) { return -2; }
    if(!testing::expect_eq((u64)second - (u64)first, (u64)8, m)) { return -3; }
    first[0] = 3;
    second[0] = 4;
    if(!testing::expect_eq((u64)first[0] + (u64)second[0], (u64)7, m)) { return -4; }
    return 0;
}

// The block never grows, so an over-large request fails instead of allocating a new one.
fn i32 alloc_past_the_block_returns_null(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 32);
    defer bump_arena::deinit(&local);
    if(!testing::expect_not_null(bump_arena::alloc(&local, 32), m)) { return -1; }
    if(!testing::expect_null(bump_arena::alloc(&local, 8), m)) { return -2; }
    return 0;
}

fn i32 alloc_larger_than_the_block_returns_null(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 32);
    defer bump_arena::deinit(&local);
    if(!testing::expect_null(bump_arena::alloc(&local, 64), m)) { return -1; }
    return 0;
}

fn i32 exhaustion_leaves_the_cursor_alone(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 32);
    defer bump_arena::deinit(&local);
    if(!testing::expect_not_null(bump_arena::alloc(&local, 16), m)) { return -1; }
    if(!testing::expect_null(bump_arena::alloc(&local, 64), m)) { return -2; }
    if(!testing::expect_eq(local.data.len, (u64)16, m)) { return -3; }
    if(!testing::expect_not_null(bump_arena::alloc(&local, 16), m)) { return -4; }
    return 0;
}

fn i32 realloc_grow_copies_bytes(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 128);
    defer bump_arena::deinit(&local);
    u8* old = bump_arena::alloc(&local, 4);
    if(!testing::expect_not_null((void*)old, m)) { return -1; }
    old[0] = 1;
    old[3] = 4;
    u8* fresh = bump_arena::realloc_grow(&local, old, 4, 8);
    if(!testing::expect_not_null((void*)fresh, m)) { return -2; }
    if(!testing::expect_eq((u64)fresh[0], (u64)1, m)) { return -3; }
    if(!testing::expect_eq((u64)fresh[3], (u64)4, m)) { return -4; }
    return 0;
}

fn i32 realloc_grow_with_null_old(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 64);
    defer bump_arena::deinit(&local);
    if(!testing::expect_not_null(bump_arena::realloc_grow(&local, null, 0, 16), m)) { return -1; }
    return 0;
}

fn i32 alloc_honours_an_explicit_alignment(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 512);
    defer bump_arena::deinit(&local);
    if(!testing::expect_not_null(bump_arena::alloc(&local, 1), m)) { return -1; }
    void* aligned = bump_arena::alloc(&local, 16, 64);
    if(!testing::expect_not_null(aligned, m)) { return -2; }
    if(!testing::expect_eq((u64)aligned % 64, (u64)0, m)) { return -3; }
    return 0;
}

fn i32 alignment_holds_from_an_unaligned_cursor(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 1024);
    defer bump_arena::deinit(&local);
    for(u64 step = 1; step <= 5; step = step + 1) {
        if(!testing::expect_not_null(bump_arena::alloc(&local, step), m)) { return -1; }
        void* aligned = bump_arena::alloc(&local, 8, 32);
        if(!testing::expect_not_null(aligned, m)) { return -2; }
        if(!testing::expect_eq((u64)aligned % 32, (u64)0, m)) { return -3; }
    }
    return 0;
}

// The block never grows, so alignment padding has to be counted against the remaining space.
fn i32 alignment_padding_can_exhaust_the_block(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 64);
    defer bump_arena::deinit(&local);
    if(!testing::expect_not_null(bump_arena::alloc(&local, 8), m)) { return -1; }
    if(!testing::expect_null(bump_arena::alloc(&local, 64, 64), m)) { return -2; }
    if(!testing::expect_eq(local.data.len, (u64)8, m)) { return -3; }
    return 0;
}

fn i32 free_rewinds_past_alignment_padding(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 512);
    defer bump_arena::deinit(&local);
    u8* first = bump_arena::alloc(&local, 1);
    if(!testing::expect_not_null((void*)first, m)) { return -1; }
    if(!testing::expect_not_null(bump_arena::alloc(&local, 16, 64), m)) { return -2; }
    bump_arena::free(&local);
    if(!testing::expect_eq((void*)bump_arena::alloc(&local, 1), (void*)first, m)) { return -3; }
    return 0;
}

fn i32 free_with_null_arena(arena::Arena* a, const u8[]m) {
    bump_arena::free(null);
    return 0;
}

fn i32 free_hands_back_the_same_memory(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 64);
    defer bump_arena::deinit(&local);
    u8* first = bump_arena::alloc(&local, 16);
    if(!testing::expect_not_null((void*)first, m)) { return -1; }
    first[0] = 42;
    bump_arena::free(&local);
    u8* second = bump_arena::alloc(&local, 16);
    if(!testing::expect_eq((void*)second, (void*)first, m)) { return -2; }
    second[0] = 7;
    if(!testing::expect_eq((u64)second[0], (u64)7, m)) { return -3; }
    return 0;
}

fn i32 free_keeps_the_block(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 64);
    defer bump_arena::deinit(&local);
    u8* block = bump_arena::alloc(&local, 16);
    bump_arena::free(&local);
    if(!testing::expect_not_null((void*)local.data.ptr, m)) { return -1; }
    if(!testing::expect_eq(local.cap, (u64)64, m)) { return -2; }
    if(!testing::expect_eq(local.data.len, (u64)0, m)) { return -3; }
    if(!testing::expect_eq((void*)bump_arena::alloc(&local, 16), (void*)block, m)) { return -4; }
    return 0;
}

fn i32 free_is_idempotent(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 64);
    defer bump_arena::deinit(&local);
    u8* first = bump_arena::alloc(&local, 16);
    bump_arena::free(&local);
    bump_arena::free(&local);
    if(!testing::expect_eq((void*)bump_arena::alloc(&local, 16), (void*)first, m)) { return -1; }
    return 0;
}

fn i32 free_recovers_a_full_block(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 64);
    defer bump_arena::deinit(&local);
    u8* first = bump_arena::alloc(&local, 64);
    if(!testing::expect_not_null((void*)first, m)) { return -1; }
    if(!testing::expect_null(bump_arena::alloc(&local, 8), m)) { return -2; }
    bump_arena::free(&local);
    if(!testing::expect_eq((void*)bump_arena::alloc(&local, 64), (void*)first, m)) { return -3; }
    return 0;
}

fn i32 deinit_with_null_arena(arena::Arena* a, const u8[]m) {
    bump_arena::deinit(null);
    return 0;
}

fn i32 deinit_releases_the_block(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 64);
    if(!testing::expect_not_null(bump_arena::alloc(&local, 16), m)) { return -1; }
    bump_arena::deinit(&local);
    if(!testing::expect_null((void*)local.data.ptr, m)) { return -2; }
    if(!testing::expect_eq(local.cap, (u64)0, m)) { return -3; }
    if(!testing::expect_null(bump_arena::alloc(&local, 8), m)) { return -4; }
    return 0;
}

fn i32 deinit_twice_is_safe(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 64);
    bump_arena::alloc(&local, 16);
    bump_arena::deinit(&local);
    bump_arena::deinit(&local);
    if(!testing::expect_null((void*)local.data.ptr, m)) { return -1; }
    return 0;
}

fn i32 init_after_deinit_reuses_the_arena(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 64);
    bump_arena::alloc(&local, 16);
    bump_arena::deinit(&local);
    if(!testing::expect_true(bump_arena::init(&local, 128), m)) { return -1; }
    defer bump_arena::deinit(&local);
    if(!testing::expect_eq(local.cap, (u64)128, m)) { return -2; }
    if(!testing::expect_not_null(bump_arena::alloc(&local, 128), m)) { return -3; }
    return 0;
}

fn i32 allocates_through_the_allocator_interface(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 128);
    defer bump_arena::deinit(&local);
    mem::Allocator alloc = bump_arena::allocator(&local);
    void* first = mem::alloc_bytes(alloc, 24);
    if(!testing::expect_not_null(first, m)) { return -1; }
    if(!testing::expect_ne(mem::alloc_bytes(alloc, 24), first, m)) { return -2; }
    bump_arena::free(&local);
    if(!testing::expect_eq(mem::alloc_bytes(alloc, 24), first, m)) { return -3; }
    return 0;
}

// free_fn cannot reclaim one allocation, so what was handed out must survive it.
fn i32 allocator_free_is_a_no_op(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 128);
    defer bump_arena::deinit(&local);
    mem::Allocator alloc = bump_arena::allocator(&local);
    u8* p = (u8*)mem::alloc_bytes(alloc, 16);
    p[0] = 9;
    mem::free_bytes(alloc, (void*)p, 16);
    if(!testing::expect_eq((u64)p[0], (u64)9, m)) { return -1; }
    if(!testing::expect_eq(local.data.len, (u64)16, m)) { return -2; }
    return 0;
}

fn i32 exhaustion_through_the_allocator_returns_null(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 32);
    defer bump_arena::deinit(&local);
    mem::Allocator alloc = bump_arena::allocator(&local);
    if(!testing::expect_not_null(mem::alloc_bytes(alloc, 32), m)) { return -1; }
    if(!testing::expect_null(mem::alloc_bytes(alloc, 8), m)) { return -2; }
    return 0;
}

fn i32 backs_the_generic_allocator_layer(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 256);
    defer bump_arena::deinit(&local);
    mem::Allocator alloc = bump_arena::allocator(&local);
    i32[] xs = mem::alloc(i32, alloc, 16);
    if(!testing::expect_eq(xs.len, (u64)16, m)) { return -1; }
    xs[15] = 77;
    if(!testing::expect_eq(xs[15], 77, m)) { return -2; }
    return 0;
}

fn i32 backs_a_list(arena::Arena* a, const u8[]m) {
    bump_arena::BumpArena local;
    bump_arena::init(&local, 1024);
    defer bump_arena::deinit(&local);
    mem::Allocator alloc = bump_arena::allocator(&local);
    list::List(i32) values = {{null, 0}, 0};
    for(i32 i = 0; i < 32; i = i + 1) {
        list::push(&values, alloc, i);
    }
    if(!testing::expect_eq(values.data.len, (u64)32, m)) { return -1; }
    if(!testing::expect_eq(values.data[31], 31, m)) { return -2; }
    bump_arena::free(&local);

    list::List(i32) again = {{null, 0}, 0};
    list::push(&again, alloc, 5);
    if(!testing::expect_eq(again.data[0], 5, m)) { return -3; }
    return 0;
}

fn i32 main() {
    testing::init();
    const u8[] suite = "BumpArena Tests";
    testing::add(suite, "init_with_null_arena", &init_with_null_arena);
    testing::add(suite, "init_zero_size", &init_zero_size);
    testing::add(suite, "init_takes_the_block_up_front", &init_takes_the_block_up_front);
    testing::add(suite, "alloc_with_null_arena", &alloc_with_null_arena);
    testing::add(suite, "alloc_zero_size", &alloc_zero_size);
    testing::add(suite, "alloc_bumps_within_the_block", &alloc_bumps_within_the_block);
    testing::add(suite, "alloc_past_the_block_returns_null", &alloc_past_the_block_returns_null);
    testing::add(suite, "alloc_larger_than_the_block_returns_null", &alloc_larger_than_the_block_returns_null);
    testing::add(suite, "exhaustion_leaves_the_cursor_alone", &exhaustion_leaves_the_cursor_alone);
    testing::add(suite, "realloc_grow_copies_bytes", &realloc_grow_copies_bytes);
    testing::add(suite, "realloc_grow_with_null_old", &realloc_grow_with_null_old);
    testing::add(suite, "alloc_honours_an_explicit_alignment", &alloc_honours_an_explicit_alignment);
    testing::add(suite, "alignment_holds_from_an_unaligned_cursor", &alignment_holds_from_an_unaligned_cursor);
    testing::add(suite, "alignment_padding_can_exhaust_the_block", &alignment_padding_can_exhaust_the_block);
    testing::add(suite, "free_rewinds_past_alignment_padding", &free_rewinds_past_alignment_padding);
    testing::add(suite, "free_with_null_arena", &free_with_null_arena);
    testing::add(suite, "free_hands_back_the_same_memory", &free_hands_back_the_same_memory);
    testing::add(suite, "free_keeps_the_block", &free_keeps_the_block);
    testing::add(suite, "free_is_idempotent", &free_is_idempotent);
    testing::add(suite, "free_recovers_a_full_block", &free_recovers_a_full_block);
    testing::add(suite, "deinit_with_null_arena", &deinit_with_null_arena);
    testing::add(suite, "deinit_releases_the_block", &deinit_releases_the_block);
    testing::add(suite, "deinit_twice_is_safe", &deinit_twice_is_safe);
    testing::add(suite, "init_after_deinit_reuses_the_arena", &init_after_deinit_reuses_the_arena);
    testing::add(suite, "allocates_through_the_allocator_interface", &allocates_through_the_allocator_interface);
    testing::add(suite, "allocator_free_is_a_no_op", &allocator_free_is_a_no_op);
    testing::add(suite, "exhaustion_through_the_allocator_returns_null", &exhaustion_through_the_allocator_returns_null);
    testing::add(suite, "backs_the_generic_allocator_layer", &backs_the_generic_allocator_layer);
    testing::add(suite, "backs_a_list", &backs_a_list);
    return testing::run();
}
