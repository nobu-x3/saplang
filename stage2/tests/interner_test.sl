import testing;
import interner;
import arena;
import sys;
import symbol;

fn i32 intern_dedup(arena::Arena* a, u8[] m) {
    interner::Interner it;
    interner::init(&it, a, 16);
    u8[] s = "hello";
    symbol::Symbol* a1 = interner::intern(&it, s);
    symbol::Symbol* a2 = interner::intern(&it, s);
    if(!testing::expect_eq((void*)a1, (void*)a2, m)) { return -1; }
    if(!testing::expect_eq(it.entry_count, 1, m)) { return -2; }
    return 0;
}

fn i32 intern_distinct(arena::Arena* a, u8[] m) {
    interner::Interner it;
    interner::init(&it, a, 16);
    symbol::Symbol* a1 = interner::intern(&it, "foo");
    symbol::Symbol* a2 = interner::intern(&it, "bar");
    if(!testing::expect_ne((void*)a1, (void*)a2, m)) { return -1; }
    if(!testing::expect_eq(it.entry_count, 2, m)) { return -2; }
    return 0;
}

fn i32 intern_roundtrip(arena::Arena* a, u8[] m) {
    interner::Interner it;
    interner::init(&it, a, 16);
    u8[] s = "round-trip";
    symbol::Symbol* sym = interner::intern(&it, s);
    u8[] back = interner::symbol_str(sym, &it);
    if(!testing::expect_eq(back, s, m)) { return -1; }
    return 0;
}

fn i32 intern_symbol_fields(arena::Arena* a, u8[] m) {
    interner::Interner it;
    interner::init(&it, a, 16);
    u8[] s = "abcdef";
    symbol::Symbol* sym = interner::intern(&it, s);
    if(!testing::expect_eq((u64)sym.len, s.len, m)) { return -1; }
    if(!testing::expect_eq(sym.offset, 0, m)) { return -2; }
    symbol::Symbol* sym2 = interner::intern(&it, "xyz");
    if(!testing::expect_eq(sym2.offset, s.len, m)) { return -3; }
    return 0;
}

// Forces multiple entries into the same bucket. With only 2 buckets,
// 4+ inserts guarantee collisions on at least one chain.
fn i32 intern_chain_dedup(arena::Arena* a, u8[] m) {
    interner::Interner it;
    interner::init(&it, a, 2);
    symbol::Symbol* s1 = interner::intern(&it, "alpha");
    symbol::Symbol* s2 = interner::intern(&it, "beta");
    symbol::Symbol* s3 = interner::intern(&it, "gamma");
    symbol::Symbol* s4 = interner::intern(&it, "delta");
    if(!testing::expect_eq(it.entry_count, 4, m)) { return -1; }
    if(!testing::expect_eq((void*)interner::intern(&it, "alpha"), (void*)s1, m)) { return -2; }
    if(!testing::expect_eq((void*)interner::intern(&it, "beta"), (void*)s2, m)) { return -3; }
    if(!testing::expect_eq((void*)interner::intern(&it, "gamma"), (void*)s3, m)) { return -4; }
    if(!testing::expect_eq((void*)interner::intern(&it, "delta"), (void*)s4, m)) { return -5; }
    if(!testing::expect_eq(it.entry_count, 4, m)) { return -6; }
    return 0;
}

fn i32 intern_empty_bytes(arena::Arena* a, u8[] m) {
    interner::Interner it;
    interner::init(&it, a, 16);
    u8[] empty = {null, 0};
    symbol::Symbol* s1 = interner::intern(&it, empty);
    symbol::Symbol* s2 = interner::intern(&it, empty);
    if(!testing::expect_eq((void*)s1, (void*)s2, m)) { return -1; }
    if(!testing::expect_eq((u64)s1.len, 0, m)) { return -2; }
    return 0;
}

fn i32 intern_dedup_distinct_buffers(arena::Arena* a, u8[] m) {
    interner::Interner it;
    interner::init(&it, a, 16);
    u8[] b1 = {(u8*)arena::alloc(a, 3), 3};
    u8[] b2 = {(u8*)arena::alloc(a, 3), 3};
    b1[0] = 'f'; b1[1] = 'o'; b1[2] = 'o';
    b2[0] = 'f'; b2[1] = 'o'; b2[2] = 'o';
    if(!testing::expect_ne((void*)b1.ptr, (void*)b2.ptr, m)) { return -1; }
    symbol::Symbol* s1 = interner::intern(&it, b1);
    symbol::Symbol* s2 = interner::intern(&it, b2);
    if(!testing::expect_eq((void*)s1, (void*)s2, m)) { return -2; }
    if(!testing::expect_eq(s1.hash, s2.hash, m)) { return -3; }
    if(!testing::expect_eq(it.entry_count, 1, m)) { return -4; }
    return 0;
}

fn i32 intern_hash_buffer_independent(arena::Arena* a, u8[] m) {
    interner::Interner it1;
    interner::Interner it2;
    interner::init(&it1, a, 16);
    interner::init(&it2, a, 16);
    u8[] b1 = {(u8*)arena::alloc(a, 5), 5};
    u8[] b2 = {(u8*)arena::alloc(a, 5), 5};
    for(u64 i = 0; i < 5; i += 1) { b1[i] = (u8)('a' + i); b2[i] = (u8)('a' + i); }
    symbol::Symbol* s1 = interner::intern(&it1, b1);
    symbol::Symbol* s2 = interner::intern(&it2, b2);
    if(!testing::expect_eq(s1.hash, s2.hash, m)) { return -1; }
    return 0;
}

// Forces slab capacity to grow past the initial 4096-byte floor.
fn i32 intern_slab_growth(arena::Arena* a, u8[] m) {
    interner::Interner it;
    interner::init(&it, a, 16);
    u64 chunk_size = 600;
    u8[] chunk = {(u8*)arena::alloc(a, chunk_size), chunk_size};
    for(u64 i = 0; i < chunk_size; i += 1) {
        chunk[i] = (u8)(i & 255);
    }
    for(u64 i = 0; i < 10; i += 1) {
        chunk[0] = (u8)i;
        interner::intern(&it, chunk);
    }
    if(!testing::expect_gt(it.slab_cap, 4096, m)) { return -1; }
    if(!testing::expect_ge(it.slab.len, chunk_size * 10, m)) { return -2; }
    return 0;
}

fn i32 main() {
    testing::init();
    u8[] suite = "Interner Tests";
    testing::add(suite, "intern_dedup", &intern_dedup);
    testing::add(suite, "intern_distinct", &intern_distinct);
    testing::add(suite, "intern_roundtrip", &intern_roundtrip);
    testing::add(suite, "intern_symbol_fields", &intern_symbol_fields);
    testing::add(suite, "intern_chain_dedup", &intern_chain_dedup);
    testing::add(suite, "intern_empty_bytes", &intern_empty_bytes);
    testing::add(suite, "intern_dedup_distinct_buffers", &intern_dedup_distinct_buffers);
    testing::add(suite, "intern_hash_buffer_independent", &intern_hash_buffer_independent);
    testing::add(suite, "intern_slab_growth", &intern_slab_growth);
    return testing::run();
}
