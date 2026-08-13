import sys;
import mem;

// Fixed-size arena: one block up front, a bump cursor through it, and no deallocation until
// deinit. `free` rewinds the cursor so the block is handed out again, overwriting what was there.

export struct BumpArena {
    u64  cap;
    u8[] data;
}

// size in bytes
export fn bool init(BumpArena* bump, u64 size) {
    if(!bump) {
        return false;
    }
    bump.cap = 0;
    bump.data.ptr = null;
    bump.data.len = 0;
    if(!size) {
        return false;
    }
    u8* block = sys::malloc(size);
    if(!block) {
        return false;
    }
    bump.cap = size;
    bump.data.ptr = block;
    return true;
}

export fn void deinit(BumpArena* bump) {
    if(!bump) {
        return;
    }
    sys::free((void*)bump.data.ptr);
    bump.cap = 0;
    bump.data.ptr = null;
    bump.data.len = 0;
}

// Rewinds the cursor; the block stays live and the next allocation overwrites it.
export fn void free(BumpArena* bump) {
    if(!bump) {
        return;
    }
    bump.data.len = 0;
}

// size in bytes
export fn void* alloc(BumpArena* bump, u64 size) {
    return alloc(bump, size, BUMP_ALIGN);
}

// size in bytes
export fn void* alloc(BumpArena* bump, u64 size, u64 align) {
    if(!bump) {
        return null;
    }
    if(!size) {
        return null;
    }
    if(align < BUMP_ALIGN) {
        align = BUMP_ALIGN;
    }
    size = mem::align_up(size, BUMP_ALIGN);
    // The block carries only malloc's alignment, so the cursor steps against its absolute address.
    u64 base = (u64)bump.data.ptr;
    u64 offset = mem::align_up(base + bump.data.len, align) - base;
    if(offset + size > bump.cap) {
        return null;
    }
    u8* ptr = bump.data.ptr + offset;
    bump.data.len = offset + size;
    return ptr;
}

// size in bytes
export fn void* realloc_grow(BumpArena* bump, void* old, u64 old_size, u64 new_size) {
    return realloc_grow(bump, old, old_size, new_size, BUMP_ALIGN);
}

// size in bytes
export fn void* realloc_grow(BumpArena* bump, void* old, u64 old_size, u64 new_size, u64 align) {
    void* fresh = alloc(bump, new_size, align);
    if(!fresh) {
        return null;
    }
    if(old_size > 0 && old) {
        sys::memcpy(fresh, old, old_size);
    }
    return fresh;
}

export fn mem::Allocator allocator(BumpArena* bump) {
    mem::Allocator out;
    out.ctx = (void*)bump;
    out.alloc_fn = &alloc_thunk;
    out.realloc_grow_fn = &realloc_grow_thunk;
    out.free_fn = &free_thunk;
    return out;
}

fn void* alloc_thunk(void* ctx, u64 size, u64 align) {
    return alloc((BumpArena*)ctx, size, align);
}

fn void* realloc_grow_thunk(void* ctx, void* old, u64 old_size, u64 new_size, u64 align) {
    return realloc_grow((BumpArena*)ctx, old, old_size, new_size, align);
}

// A bump arena rewinds in bulk, so a single allocation cannot be reclaimed.
fn void free_thunk(void* ctx, void* ptr, u64 size, u64 align) {
}

// PRIVATE FUNCTIONS
const u64 BUMP_ALIGN = 8;
