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
