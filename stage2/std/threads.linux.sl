// pthread_t = unsigned long on glibc.
export struct Thread {
    u64 id;
}

extern {
    fn i32 pthread_create(Thread* th, void* attr, fn* void*(void*) start, void* arg);
    fn i32 pthread_join(u64 th, void** retval);
    fn i32 pthread_detach(u64 th);
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
