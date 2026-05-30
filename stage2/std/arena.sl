import sys;

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
    if(!arena) {
        return null;
    }
    if(!size) {
        return null;
    }
    size = align_up(size, ARENA_ALIGN);
    if(arena.head && arena.head.data.len + size <= arena.head.cap) {
        u8* ptr = &arena.head.data[arena.head.data.len];
        arena.head.data.len += size;
        return ptr;
    }
    u64 page_cap = arena.default_page_size;
    if(size > arena.default_page_size) {
        page_cap = size;
    }
    ArenaPage* p = new_page(page_cap);
    if(!p) {
        return null;
    }
    p.next = arena.head;
    arena.head = p;
    p.data.len = size;
    return p.data.ptr;
}

// size in bytes
export fn void* realloc_grow(Arena* arena, void* old, u64 old_size, u64 new_size) {
    void* fresh = alloc(arena, new_size);
    if(!fresh) {
        return null;
    }
    if(old_size > 0 && old) {
        sys::memcpy(fresh, old, old_size);
    }
    return fresh;
}

export fn u64 align_up(u64 value, u64 alignment) {
    return (value + alignment - 1) & ~(alignment - 1);
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
