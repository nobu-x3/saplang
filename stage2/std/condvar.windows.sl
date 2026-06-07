import mutex;

// Win32 CONDITION_VARIABLE is a pointer-sized slot.
export struct Condvar {
    void* ptr;
}

extern {
    fn void InitializeConditionVariable(Condvar* c);
    fn i32  SleepConditionVariableCS(Condvar* c, mutex::Mutex* m, u32 ms);
    fn void WakeConditionVariable(Condvar* c);
    fn void WakeAllConditionVariable(Condvar* c);
}

const u32 INFINITE = 0xFFFFFFFF;

export fn i32 create(Condvar* c) {
    InitializeConditionVariable(c);
    return 0;
}

// Win32 has no destroy.
export fn i32 destroy(Condvar* c) {
    return 0;
}

export fn i32 wait(Condvar* c, mutex::Mutex* m) {
    if (SleepConditionVariableCS(c, m, INFINITE) == 0) {
        return -1;
    }
    return 0;
}

export fn i32 signal(Condvar* c) {
    WakeConditionVariable(c);
    return 0;
}

export fn i32 broadcast(Condvar* c) {
    WakeAllConditionVariable(c);
    return 0;
}
