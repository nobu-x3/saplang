import sys;

// The allocator interface std allocates through, so no std module names a backend. An implementation is a
// context pointer plus three thunks; `arena::allocator` and `libc_allocator` below are the two in-tree ones.
export struct Allocator {
    void*                                ctx;
    fn* void*(void*, u64)                alloc_fn;
    fn* void*(void*, void*, u64, u64)    realloc_grow_fn;
    fn* void(void*, void*, u64)          free_fn;
}

export fn void* alloc(Allocator a, u64 size) {
    if(a.alloc_fn == null) { return null; }
    return a.alloc_fn(a.ctx, size);
}

export fn void* realloc_grow(Allocator a, void* old, u64 old_size, u64 new_size) {
    if(a.realloc_grow_fn == null) { return null; }
    return a.realloc_grow_fn(a.ctx, old, old_size, new_size);
}

// Size is passed so an implementation can reclaim without a per-allocation header.
export fn void free(Allocator a, void* ptr, u64 size) {
    if(a.free_fn == null) { return; }
    a.free_fn(a.ctx, ptr, size);
}

export fn Allocator libc_allocator() {
    Allocator out;
    out.ctx = null;
    out.alloc_fn = &libc_alloc;
    out.realloc_grow_fn = &libc_realloc_grow;
    out.free_fn = &libc_free;
    return out;
}

fn void* libc_alloc(void* ctx, u64 size) {
    return sys::malloc(size);
}

fn void* libc_realloc_grow(void* ctx, void* old, u64 old_size, u64 new_size) {
    return sys::realloc(old, new_size);
}

fn void libc_free(void* ctx, void* ptr, u64 size) {
    sys::free(ptr);
}
