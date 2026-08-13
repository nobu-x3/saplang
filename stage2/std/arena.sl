import sys;
import mem;

// Growable arena: allocates pages on demand

struct ArenaPage {
    u64 cap;
    u8[] data;
    ArenaPage* next;
}

export struct Arena {
    u64 default_page_size;
    ArenaPage* head;
}

// size in bytes
export fn void* alloc(Arena* arena, u64 size) {
    return alloc(arena, size, ARENA_ALIGN);
}

// size in bytes
export fn void* alloc(Arena* arena, u64 size, u64 align) {
    if(!arena) {
        return null;
    }
    if(!size) {
        return null;
    }
    if(align < ARENA_ALIGN) {
        align = ARENA_ALIGN;
    }
    size = mem::align_up(size, ARENA_ALIGN);
    if(arena.head) {
        u64 base = (u64)arena.head.data.ptr;
        u64 offset = mem::align_up(base + arena.head.data.len, align) - base;
        if(offset + size <= arena.head.cap) {
            u8* ptr = arena.head.data.ptr + offset;
            arena.head.data.len = offset + size;
            return ptr;
        }
    }
    u64 page_cap = arena.default_page_size;
    if(size > arena.default_page_size) {
        page_cap = size;
    }
    // A fresh page is only malloc-aligned, so an over-aligned request needs room to step forward.
    if(align > ARENA_ALIGN) {
        page_cap += align - 1;
    }
    ArenaPage* p = new_page(page_cap);
    if(!p) {
        return null;
    }
    p.next = arena.head;
    arena.head = p;
    u64 page_base = (u64)p.data.ptr;
    u64 page_offset = mem::align_up(page_base, align) - page_base;
    p.data.len = page_offset + size;
    return p.data.ptr + page_offset;
}

// size in bytes
export fn void* realloc_grow(Arena* arena, void* old, u64 old_size, u64 new_size) {
    return realloc_grow(arena, old, old_size, new_size, ARENA_ALIGN);
}

// size in bytes
export fn void* realloc_grow(Arena* arena, void* old, u64 old_size, u64 new_size, u64 align) {
    void* fresh = alloc(arena, new_size, align);
    if(!fresh) {
        return null;
    }
    if(old_size > 0 && old) {
        sys::memcpy(fresh, old, old_size);
    }
    return fresh;
}

export fn void free(Arena* arena) {
    if(!arena) { return; }
    ArenaPage* current = arena.head;
    while(current) {
        ArenaPage* next = current.next;
        sys::free(current);
        current = next;
    }
    arena.head = null;
}

export fn mem::Allocator allocator(Arena* arena) {
    mem::Allocator out;
    out.ctx = (void*)arena;
    out.alloc_fn = &alloc_thunk;
    out.realloc_grow_fn = &realloc_grow_thunk;
    out.free_fn = &free_thunk;
    return out;
}

fn void* alloc_thunk(void* ctx, u64 size, u64 align) {
    return alloc((Arena*)ctx, size, align);
}

fn void* realloc_grow_thunk(void* ctx, void* old, u64 old_size, u64 new_size, u64 align) {
    return realloc_grow((Arena*)ctx, old, old_size, new_size, align);
}

// An arena releases in bulk, so a single allocation cannot be reclaimed.
fn void free_thunk(void* ctx, void* ptr, u64 size, u64 align) {
}

// PRIVATE FUNCTIONS
const u64 ARENA_ALIGN = 8;

fn ArenaPage* new_page(u64 cap) {
    ArenaPage* p = sys::malloc(sizeof(ArenaPage) + cap);
    if(!p) {
        return null;
    }
    p.next = null;
    p.cap = cap;
    p.data.ptr = (u8*)(p + 1);
    p.data.len = 0;
    return p;
}
