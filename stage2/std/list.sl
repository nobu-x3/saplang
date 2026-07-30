import mem;

// A generic dynamic array. `List(T)` bundles the storage pointer, length, and capacity; `push` grows and
// appends through whatever allocator the caller passes. The `dyn_push` free function below is the slice+cap
// form kept for call sites that keep the fields separate.

export fn Type List(comptime Type T) {
    return struct { T* ptr; u64 len; u64 cap; };
}

// Append value to a List(T), doubling capacity (min 4) when full.
export fn void push(comptime Type T, List(T)* l, mem::Allocator a, T value) {
    if(l.len == l.cap) {
        u64 new_cap = 4;
        if(l.cap > 0) { new_cap = l.cap * 2; }
        l.ptr = (T*)mem::realloc_grow(a, (void*)l.ptr, l.len * sizeof(T), new_cap * sizeof(T));
        l.cap = new_cap;
    }
    l.ptr[l.len] = value;
    l.len += 1;
}

// Append value to a {ptr, len} slice with a separate cap, doubling capacity (min 4) when full.
export fn void dyn_push(comptime Type T, T[]* items, u64* cap, mem::Allocator a, T value) {
    if(items.len == *cap) {
        u64 new_cap = 4;
        if(*cap > 0) { new_cap = *cap * 2; }
        items.ptr = (T*)mem::realloc_grow(a, (void*)items.ptr, items.len * sizeof(T), new_cap * sizeof(T));
        *cap = new_cap;
    }
    items.ptr[items.len] = value;
    items.len += 1;
}
