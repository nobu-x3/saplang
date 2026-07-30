// pthread_t = unsigned long on glibc.
export struct Thread {
    u64 id;
}

// pthread_create writes a pthread_t through this pointer; a wider struct would let it scribble past the caller's slot.
comprun {
    if(sizeof(Thread) != (u64)8 || alignof(Thread) != (u64)8) { comperror("Thread must match glibc pthread_t: 8 bytes, 8-aligned"); }
}

extern {
    fn i32 pthread_create(Thread* th, void* attr, fn* void*(void*) start, void* arg);
    fn i32 pthread_join(u64 th, void** retval);
    fn i32 pthread_detach(u64 th);
    fn u64 pthread_self();
}

export fn u64 self() {
    return pthread_self();
}

export fn i32 spawn(Thread* out, fn* void*(void*) proc, void* arg) {
    return pthread_create(out, null, proc, arg);
}

export fn i32 join(Thread* t, void** result) {
    return pthread_join(t.id, result);
}

export fn i32 detach(Thread* t) {
    return pthread_detach(t.id);
}
