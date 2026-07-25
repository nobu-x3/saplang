import arena;

// Generic arena-backed dynamic array: replaces the hand-rolled grow-and-append idiom.
// `items` is a {ptr, len} slice; `cap` tracks the allocated element count separately.

// Append value, doubling capacity (min 4) when full.
export fn void dyn_push(comptime Type T, T[]* items, u64* cap, arena::Arena* a, T value) {
    if(items.len == *cap) {
        u64 new_cap = 4;
        if(*cap > 0) { new_cap = *cap * 2; }
        items.ptr = (T*)arena::realloc_grow(a, (void*)items.ptr, items.len * sizeof(T), new_cap * sizeof(T));
        *cap = new_cap;
    }
    items.ptr[items.len] = value;
    items.len += 1;
}
