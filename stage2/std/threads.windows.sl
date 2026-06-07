import sys;

export struct Thread {
    void* handle;
    void* payload;
}

// Win32 start routine is u32(LPVOID); trampoline adapts to void*(void*).
struct Trampoline {
    fn* void*(void*) user_proc;
    void* user_arg;
    void* result;
}

fn u32 trampoline(void* p) {
    Trampoline* tr = (Trampoline*)p;
    tr.result = tr.user_proc(tr.user_arg);
    return 0;
}

extern {
    fn void* CreateThread(void* attrs, u64 stack, fn* u32(void*) start, void* arg, u32 flags, u32* tid);
    fn u32   WaitForSingleObject(void* h, u32 ms);
    fn i32   CloseHandle(void* h);
}

const u32 INFINITE = 0xFFFFFFFF;

export fn i32 spawn(Thread* out, fn* void*(void*) proc, void* arg) {
    Trampoline* tr = (Trampoline*)sys::malloc(sizeof(Trampoline));
    if (!tr) {
        return -1;
    }
    tr.user_proc = proc;
    tr.user_arg = arg;
    tr.result = null;
    out.handle = CreateThread(null, 0, &trampoline, (void*)tr, 0, null);
    out.payload = (void*)tr;
    if (!out.handle) {
        sys::free((void*)tr);
        out.payload = null;
        return -1;
    }
    return 0;
}

export fn i32 join(Thread* t, void** result) {
    WaitForSingleObject(t.handle, INFINITE);
    if (result) {
        Trampoline* tr = (Trampoline*)t.payload;
        *result = tr.result;
    }
    sys::free(t.payload);
    CloseHandle(t.handle);
    t.handle = null;
    t.payload = null;
    return 0;
}

export fn i32 detach(Thread* t) {
    CloseHandle(t.handle);
    sys::free(t.payload);
    t.handle = null;
    t.payload = null;
    return 0;
}
