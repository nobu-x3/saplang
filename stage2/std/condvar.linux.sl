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
