import arena;
import sys;

export struct DiagEntry {
    u32  src_pos;
    bool is_warning;
    u8[] msg;
}

export struct DiagBuf {
    DiagEntry[] entries;
    u64         entries_cap;
}

// DiagBuf*+Arena* not Module*, avoids diag<->module cycle.
export fn void report(DiagBuf* d, arena::Arena* a, u32 src_pos, const u8[] msg) {
    append(d, a, src_pos, msg, false);
}

export fn void report_warning(DiagBuf* d, arena::Arena* a, u32 src_pos, const u8[] msg) {
    append(d, a, src_pos, msg, true);
}

export fn void reset(DiagBuf* d) {
    d.entries.len = 0;
}

fn void append(DiagBuf* d, arena::Arena* a, u32 src_pos, const u8[] msg, bool is_warning) {
    if(d.entries.len == d.entries_cap) {
        u64 new_cap = 8;
        if(d.entries_cap > 0) {
            new_cap = d.entries_cap * 2;
        }
        d.entries.ptr = arena::realloc_grow(a, (void*)d.entries.ptr,
                d.entries.len * sizeof(DiagEntry),
                new_cap * sizeof(DiagEntry));
        d.entries_cap = new_cap;
    }
    // Copy msg bytes into the arena so callers can pass any slice — stack
    // buffers, string literals, or transient buffers — without dangling.
    u8[] stored = {null, 0};
    if(msg.len > 0) {
        u8* dst = arena::alloc(a, msg.len);
        if(dst) {
            sys::memcpy(dst, msg.ptr, msg.len);
            stored.ptr = dst;
            stored.len = msg.len;
        }
    }
    DiagEntry* e = &d.entries[d.entries.len];
    e.src_pos = src_pos;
    e.is_warning = is_warning;
    e.msg = stored;
    d.entries.len += 1;
}
