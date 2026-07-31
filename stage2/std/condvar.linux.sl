import mutex;

// glibc __pthread_cond_s on x86_64 (48B, 8-aligned).
export struct Condvar {
    u64 wseq;
    u64 g1_start;
    u32 g_refs0;
    u32 g_refs1;
    u32 g_size0;
    u32 g_size1;
    u32 g1_orig_size;
    u32 wrefs;
    u32 g_signals0;
    u32 g_signals1;
}

// pthread_cond_init writes through this as glibc's own struct, so drift here corrupts memory instead of failing a check.
comprun {
    TypeInfo info = type_info(Condvar);
    if(info.size != (u64)48 || info.align != (u64)8) { comperror("Condvar must match glibc pthread_cond_t: 48 bytes, 8-aligned"); }
    if(info.fields.len != (u64)10) { comperror("Condvar field count no longer matches glibc __pthread_cond_s"); }
    const u8[][10] want_names = ["wseq", "g1_start", "g_refs0", "g_refs1", "g_size0", "g_size1", "g1_orig_size", "wrefs", "g_signals0", "g_signals1"];
    u64[10] want_offsets = [0, 8, 16, 20, 24, 28, 32, 36, 40, 44];
    for(u64 field_index = 0; field_index < info.fields.len; field_index += 1) {
        if(!field_matches(info.fields[field_index].name, want_names[field_index], info.fields[field_index].offset, want_offsets[field_index])) {
            comperror("Condvar no longer matches glibc __pthread_cond_s field-for-field");
        }
    }
}

// Only reachable from the comprun above; TypeInfo can't cross a runtime signature, so the fields come in unpacked.
fn bool field_matches(const u8[] name, const u8[] want_name, u64 offset, u64 want_offset) {
    if(offset != want_offset || name.len != want_name.len) { return false; }
    for(u64 char_index = 0; char_index < name.len; char_index += 1) {
        if(name[char_index] != want_name[char_index]) { return false; }
    }
    return true;
}

extern {
    fn i32 pthread_cond_init(Condvar* c, void* attr);
    fn i32 pthread_cond_destroy(Condvar* c);
    fn i32 pthread_cond_wait(Condvar* c, mutex::Mutex* m);
    fn i32 pthread_cond_signal(Condvar* c);
    fn i32 pthread_cond_broadcast(Condvar* c);
}

export fn i32 create(Condvar* c) {
    return pthread_cond_init(c, null);
}

export fn i32 destroy(Condvar* c) {
    return pthread_cond_destroy(c);
}

export fn i32 wait(Condvar* c, mutex::Mutex* m) {
    return pthread_cond_wait(c, m);
}

export fn i32 signal(Condvar* c) {
    return pthread_cond_signal(c);
}

export fn i32 broadcast(Condvar* c) {
    return pthread_cond_broadcast(c);
}
