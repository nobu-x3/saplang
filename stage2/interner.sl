import arena;
import hash;
import mutex;
import sys;
import symbol;

export struct Interner {
    arena::Arena*       slab_arena;
    u8[]                slab;
    u64                 slab_cap;
    symbol::Symbol*[]   buckets;
    u64                 entry_count;
    mutex::Mutex        lock;
}

// Process-global; reached only through acquire()/release() or the self-locking wrappers.
Interner GLOBAL;

// bucket_count must be a power of two.
export fn void init(arena::Arena* a, u64 bucket_count) {
    u64 nbytes = bucket_count * sizeof(symbol::Symbol*);
    void* raw = arena::alloc(a, nbytes);
    sys::memset(raw, 0, nbytes);
    GLOBAL.slab_arena = a;
    GLOBAL.slab = {null, 0};
    GLOBAL.slab_cap = 0;
    GLOBAL.buckets = {(symbol::Symbol**)raw, bucket_count};
    GLOBAL.entry_count = 0;
    mutex::create(&GLOBAL.lock);
}

export fn Interner* acquire() {
    mutex::lock(&GLOBAL.lock);
    return &GLOBAL;
}

export fn void release() {
    mutex::unlock(&GLOBAL.lock);
}

export fn symbol::Symbol* intern(u8[] bytes) {
    Interner* it = interner::acquire();
    symbol::Symbol* result = _intern(it, bytes);
    interner::release();
    return result;
}

fn symbol::Symbol* _intern(Interner* it, u8[] bytes) {
    u32 hash = hash::fnv1a_32(bytes);
    u64 idx = (u64)hash & (it.buckets.len - 1);
    // walk the chain at this bucket
    symbol::Symbol* cur = it.buckets[idx];
    while (cur != null) {
        if (cur.hash == hash && cur.len == (u32)bytes.len) {
            if (slab_equals(it, cur.offset, bytes)) { return cur; }
        }
        cur = cur.chain;
    }
    // not found — append to slab, install in bucket
    u64 off = slab_append(it, bytes);
    symbol::Symbol* sym = arena::alloc(it.slab_arena, sizeof(Symbol));
    sym.offset = off;
    sym.len = (u32)bytes.len;
    sym.hash = hash;
    sym.keyword_kind = 0;                // arena memory may be dirty
    sym._pad = 0;
    sym.chain = it.buckets[idx];
    it.buckets[idx] = sym;
    it.entry_count += 1;
    return sym;
}

// Lock-free: the slab is append-only, so a concurrent grow leaves these bytes valid.
export fn u8[] symbol_str(symbol::Symbol* s) {
    return { .ptr = &GLOBAL.slab[s.offset], .len = (u64)s.len };
}

// PRIVATE
fn u64 slab_append(Interner* it, u8[] bytes) {
    u64 length_needed = it.slab.len + bytes.len;
    if(length_needed >= it.slab_cap) {
        u64 new_cap = it.slab_cap * 2;
        if(new_cap < 4096) {
            new_cap = 4096;
        }
        if(new_cap < bytes.len) {
            new_cap = arena::align_up(bytes.len, 4096);
        }
        it.slab.ptr = arena::realloc_grow(it.slab_arena, it.slab.ptr, it.slab.len, new_cap);
        it.slab_cap = new_cap;
    }
    u64 off = it.slab.len;
    sys::memcpy(&it.slab[it.slab.len], bytes.ptr, bytes.len);
    it.slab.len += bytes.len;
    return off;
}

fn bool slab_equals(const Interner* it, u64 offset, const u8[] bytes) {
    return sys::memcmp(&it.slab[offset], bytes.ptr, bytes.len) == 0;
}
