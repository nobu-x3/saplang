// glibc __pthread_mutex_s on x86_64 (40B, 8-aligned).
export struct Mutex {
    i32   lock;
    u32   count;
    i32   owner;
    u32   nusers;
    i32   kind;
    i16   spins;
    i16   elision;
    void* list_prev;
    void* list_next;
}

// pthread_mutex_init writes through this as glibc's own struct, so drift here corrupts memory instead of failing a check.
comprun {
    TypeInfo info = type_info(Mutex);
    if(info.size != (u64)40 || info.align != (u64)8) { comperror("Mutex must match glibc pthread_mutex_t: 40 bytes, 8-aligned"); }
    if(info.fields.len != (u64)9) { comperror("Mutex field count no longer matches glibc __pthread_mutex_s"); }
    u8[][9] want_names = ["lock", "count", "owner", "nusers", "kind", "spins", "elision", "list_prev", "list_next"];
    u64[9] want_offsets = [0, 4, 8, 12, 16, 20, 22, 24, 32];
    for(u64 field_index = 0; field_index < info.fields.len; field_index += 1) {
        if(!field_matches(info.fields[field_index].name, want_names[field_index], info.fields[field_index].offset, want_offsets[field_index])) {
            comperror("Mutex no longer matches glibc __pthread_mutex_s field-for-field");
        }
    }
}

// Only reachable from the comprun above; TypeInfo can't cross a runtime signature, so the fields come in unpacked.
fn bool field_matches(u8[] name, u8[] want_name, u64 offset, u64 want_offset) {
    if(offset != want_offset || name.len != want_name.len) { return false; }
    for(u64 char_index = 0; char_index < name.len; char_index += 1) {
        if(name[char_index] != want_name[char_index]) { return false; }
    }
    return true;
}

extern {
    fn i32 pthread_mutex_init(Mutex* m, void* attr);
    fn i32 pthread_mutex_destroy(Mutex* m);
    fn i32 pthread_mutex_lock(Mutex* m);
    fn i32 pthread_mutex_unlock(Mutex* m);
    fn i32 pthread_mutex_trylock(Mutex* m);
}

export fn i32 create(Mutex* m) {
    return pthread_mutex_init(m, null);
}

export fn i32 destroy(Mutex* m) {
    return pthread_mutex_destroy(m);
}

export fn i32 lock(Mutex* m) {
    return pthread_mutex_lock(m);
}

export fn i32 unlock(Mutex* m) {
    return pthread_mutex_unlock(m);
}

export fn i32 trylock(Mutex* m) {
    return pthread_mutex_trylock(m);
}
