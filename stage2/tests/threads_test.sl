import testing;
import arena;
import threads;
import mutex;
import condvar;

fn i32 mutex_create_and_destroy(arena::Arena* a, u8[] m) {
    mutex::Mutex mu;
    if (!testing::expect_eq(mutex::create(&mu), 0, m)) { return -1; }
    if (!testing::expect_eq(mutex::lock(&mu), 0, m)) { return -2; }
    if (!testing::expect_eq(mutex::unlock(&mu), 0, m)) { return -3; }
    if (!testing::expect_eq(mutex::destroy(&mu), 0, m)) { return -4; }
    return 0;
}

fn void* set_one(void* arg) {
    i32* slot = (i32*)arg;
    *slot = 1;
    return null;
}

fn i32 thread_spawn_join_runs_proc(arena::Arena* a, u8[] m) {
    threads::Thread t;
    i32 flag = 0;
    if (!testing::expect_eq(threads::spawn(&t, &set_one, (void*)&flag), 0, m)) { return -1; }
    if (!testing::expect_eq(threads::join(&t, null), 0, m)) { return -2; }
    if (!testing::expect_eq((u32)flag, (u32)1, m)) { return -3; }
    return 0;
}

fn void* return_sentinel(void* arg) {
    return (void*)(u64)0xDEADBEEF;
}

// Exercises the Windows trampoline's result-passing path.
fn i32 thread_join_propagates_return_value(arena::Arena* a, u8[] m) {
    threads::Thread t;
    threads::spawn(&t, &return_sentinel, null);
    void* result = null;
    if (!testing::expect_eq(threads::join(&t, &result), 0, m)) { return -1; }
    if (!testing::expect_eq(result, (void*)(u64)0xDEADBEEF, m)) { return -2; }
    return 0;
}

struct CondvarCtx {
    mutex::Mutex     mu;
    condvar::Condvar cv;
    i32              ready;
}

fn void* condvar_waiter(void* arg) {
    CondvarCtx* c = (CondvarCtx*)arg;
    mutex::lock(&c.mu);
    while (c.ready == 0) {
        condvar::wait(&c.cv, &c.mu);
    }
    mutex::unlock(&c.mu);
    return null;
}

fn i32 condvar_roundtrip(arena::Arena* a, u8[] m) {
    CondvarCtx ctx;
    ctx.ready = 0;
    if (!testing::expect_eq(mutex::create(&ctx.mu), 0, m)) { return -1; }
    if (!testing::expect_eq(condvar::create(&ctx.cv), 0, m)) { return -2; }

    threads::Thread waiter;
    threads::spawn(&waiter, &condvar_waiter, (void*)&ctx);

    mutex::lock(&ctx.mu);
    ctx.ready = 1;
    mutex::unlock(&ctx.mu);
    condvar::signal(&ctx.cv);

    threads::join(&waiter, null);

    if (!testing::expect_eq(condvar::destroy(&ctx.cv), 0, m)) { return -3; }
    if (!testing::expect_eq(mutex::destroy(&ctx.mu), 0, m)) { return -4; }
    return 0;
}

fn i32 main() {
    testing::init();
    u8[] suite = "Threads Tests";
    testing::add(suite, "mutex_create_and_destroy", &mutex_create_and_destroy);
    testing::add(suite, "thread_spawn_join_runs_proc", &thread_spawn_join_runs_proc);
    testing::add(suite, "thread_join_propagates_return_value", &thread_join_propagates_return_value);
    testing::add(suite, "condvar_roundtrip", &condvar_roundtrip);
    return testing::run();
}
