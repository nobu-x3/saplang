import sys;

// The allocator interface std allocates through, so no std module names a backend. An implementation is a
// context pointer plus three thunks; `arena::allocator` and `libc_allocator` below are the two in-tree ones.
export struct Allocator {
    void*                                    ctx;
    fn* void*(void*, u64, u64)               alloc_fn;
    fn* void*(void*, void*, u64, u64, u64)   realloc_grow_fn;
    fn* void(void*, void*, u64, u64)         free_fn;
}

// Alignment rides along on every call so a backend can honour it without a per-allocation header;
// the two-argument forms request DEFAULT_ALIGN, which satisfies every type the language can spell.
export fn void* alloc_bytes(Allocator a, u64 size) {
    return alloc_bytes(a, size, DEFAULT_ALIGN);
}

export fn void* alloc_bytes(Allocator a, u64 size, u64 align) {
    if(a.alloc_fn == null) { return null; }
    return a.alloc_fn(a.ctx, size, align);
}

export fn void* realloc_grow_bytes(Allocator a, void* old, u64 old_size, u64 new_size) {
    return realloc_grow_bytes(a, old, old_size, new_size, DEFAULT_ALIGN);
}

export fn void* realloc_grow_bytes(Allocator a, void* old, u64 old_size, u64 new_size, u64 align) {
    if(a.realloc_grow_fn == null) { return null; }
    return a.realloc_grow_fn(a.ctx, old, old_size, new_size, align);
}

// Size is passed so an implementation can reclaim without a per-allocation header.
export fn void free_bytes(Allocator a, void* ptr, u64 size) {
    free_bytes(a, ptr, size, DEFAULT_ALIGN);
}

export fn void free_bytes(Allocator a, void* ptr, u64 size, u64 align) {
    if(a.free_fn == null) { return; }
    a.free_fn(a.ctx, ptr, size, align);
}

export fn u64 align_up(u64 value, u64 alignment) {
    return (value + alignment - 1) & ~(alignment - 1);
}

// The element-typed layer over the byte entry points above: the allocator stays type-erased,
// while callers name what they are allocating instead of computing sizes.
export fn T* create(comptime Type T, Allocator a) {
    return (T*)alloc_bytes(a, sizeof(T), alignof(T));
}

export fn void destroy(comptime Type T, Allocator a, T* ptr) {
    free_bytes(a, (void*)ptr, sizeof(T), alignof(T));
}

export fn T[] alloc(comptime Type T, Allocator a, u64 count) {
    T* ptr = (T*)alloc_bytes(a, count * sizeof(T), alignof(T));
    if(!ptr) { T[] none = {null, 0}; return none; }
    return {ptr, count};
}

export fn T[] realloc_grow(comptime Type T, Allocator a, T[] old, u64 new_count) {
    T* ptr = (T*)realloc_grow_bytes(a, (void*)old.ptr, old.len * sizeof(T), new_count * sizeof(T), alignof(T));
    if(!ptr) { T[] none = {null, 0}; return none; }
    return {ptr, new_count};
}

export fn void free(comptime Type T, Allocator a, T[] items) {
    free_bytes(a, (void*)items.ptr, items.len * sizeof(T), alignof(T));
}

export fn Allocator libc_allocator() {
    Allocator out;
    out.ctx = null;
    out.alloc_fn = &libc_alloc;
    out.realloc_grow_fn = &libc_realloc_grow;
    out.free_fn = &libc_free;
    return out;
}

fn void* libc_alloc(void* ctx, u64 size, u64 align) {
    if(align > LIBC_ALIGN) {
        return sys::aligned_alloc(align, align_up(size, align));
    }
    return sys::malloc(size);
}

// realloc gives back only malloc's alignment, so an over-aligned block has to move by hand.
fn void* libc_realloc_grow(void* ctx, void* old, u64 old_size, u64 new_size, u64 align) {
    if(align > LIBC_ALIGN) {
        void* fresh = sys::aligned_alloc(align, align_up(new_size, align));
        if(!fresh) { return null; }
        if(old_size > 0 && old) { sys::memcpy(fresh, old, old_size); }
        sys::free(old);
        return fresh;
    }
    return sys::realloc(old, new_size);
}

fn void libc_free(void* ctx, void* ptr, u64 size, u64 align) {
    sys::free(ptr);
}

// PRIVATE
const u64 DEFAULT_ALIGN = 8;
const u64 LIBC_ALIGN = 16;
