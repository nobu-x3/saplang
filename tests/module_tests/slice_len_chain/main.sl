import sys;

struct ArenaPage {
    u64 cap;
    u8[] data;
    ArenaPage* next;
}

struct Arena {
    u64 default_page_size;
    ArenaPage* head;
}

fn i32 main() {
    Arena a = {0, null};
    u64 size = 4;
    if (a.head && a.head.data.len + size <= a.head.cap) {
        u8* via_index = &a.head.data[a.head.data.len];
        u8* via_ptr = a.head.data.ptr;
    }
    return 0;
}
