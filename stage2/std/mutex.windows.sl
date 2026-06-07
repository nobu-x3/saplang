// Win32 RTL_CRITICAL_SECTION on x64 (40B, 8-aligned).
export struct Mutex {
    void* debug_info;
    i32   lock_count;
    i32   recursion_count;
    void* owning_thread;
    void* lock_semaphore;
    u64   spin_count;
}

extern {
    fn void InitializeCriticalSection(Mutex* m);
    fn void DeleteCriticalSection(Mutex* m);
    fn void EnterCriticalSection(Mutex* m);
    fn void LeaveCriticalSection(Mutex* m);
    fn i32  TryEnterCriticalSection(Mutex* m);
}

export fn i32 create(Mutex* m) {
    InitializeCriticalSection(m);
    return 0;
}

export fn i32 destroy(Mutex* m) {
    DeleteCriticalSection(m);
    return 0;
}

export fn i32 lock(Mutex* m) {
    EnterCriticalSection(m);
    return 0;
}

export fn i32 unlock(Mutex* m) {
    LeaveCriticalSection(m);
    return 0;
}

// Win32 returns nonzero on success; normalize to 0=ok.
export fn i32 trylock(Mutex* m) {
    if (TryEnterCriticalSection(m) != 0) {
        return 0;
    }
    return 1;
}
