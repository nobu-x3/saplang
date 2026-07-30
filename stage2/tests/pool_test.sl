import testing;
import test_util;
import pool;
import mutex;
import arena;
import mem;
import sys;

struct Counter {
    mutex::Mutex        lock;
    i64                 value;
}

test_util::Counting g_counting;

fn void bump(void* arg) {
    Counter* c = (Counter*)arg;
    mutex::lock(&c.lock);
    c.value += 1;
    mutex::unlock(&c.lock);
}

fn i32 runs_all_jobs(arena::Arena* a, u8[] m) {
    pool::ThreadPool* p = pool::new(arena::allocator(a), 4);
    Counter counter;
    sys::memset(&counter, 0, sizeof(Counter));
    mutex::create(&counter.lock);
    for(u64 i = 0; i < 1000; i += 1) {
        pool::submit(p, &bump, (void*)&counter);
    }
    pool::wait_all(p);
    pool::destroy(p);
    i32 result = 0;
    if(!testing::expect_eq(counter.value, (i64)1000, m)) { result = -1; }
    mutex::destroy(&counter.lock);
    return result;
}

fn i32 multiple_batches(arena::Arena* a, u8[] m) {
    pool::ThreadPool* p = pool::new(arena::allocator(a), 4);
    Counter counter;
    sys::memset(&counter, 0, sizeof(Counter));
    mutex::create(&counter.lock);
    for(u64 i = 0; i < 100; i += 1) { pool::submit(p, &bump, (void*)&counter); }
    pool::wait_all(p);
    for(u64 i = 0; i < 100; i += 1) { pool::submit(p, &bump, (void*)&counter); }
    pool::wait_all(p);
    pool::destroy(p);
    i32 result = 0;
    if(!testing::expect_eq(counter.value, (i64)200, m)) { result = -1; }
    mutex::destroy(&counter.lock);
    return result;
}

fn i32 wait_all_empty(arena::Arena* a, u8[] m) {
    pool::ThreadPool* p = pool::new(arena::allocator(a), 2);
    pool::wait_all(p);
    pool::destroy(p);
    return 0;
}

fn i32 single_worker(arena::Arena* a, u8[] m) {
    pool::ThreadPool* p = pool::new(arena::allocator(a), 1);
    Counter counter;
    sys::memset(&counter, 0, sizeof(Counter));
    mutex::create(&counter.lock);
    for(u64 i = 0; i < 500; i += 1) { pool::submit(p, &bump, (void*)&counter); }
    pool::wait_all(p);
    pool::destroy(p);
    i32 result = 0;
    if(!testing::expect_eq(counter.value, (i64)500, m)) { result = -1; }
    mutex::destroy(&counter.lock);
    return result;
}

fn i32 zero_workers_clamped(arena::Arena* a, u8[] m) {
    pool::ThreadPool* p = pool::new(arena::allocator(a), 0);
    Counter counter;
    sys::memset(&counter, 0, sizeof(Counter));
    mutex::create(&counter.lock);
    for(u64 i = 0; i < 50; i += 1) { pool::submit(p, &bump, (void*)&counter); }
    pool::wait_all(p);
    pool::destroy(p);
    i32 result = 0;
    if(!testing::expect_eq(counter.value, (i64)50, m)) { result = -1; }
    mutex::destroy(&counter.lock);
    return result;
}

// The pool's queue and worker array come from whatever allocator built it, not from an arena it names.
fn i32 allocates_through_caller_allocator(arena::Arena* a, u8[] m) {
    sys::memset(&g_counting, 0, sizeof(test_util::Counting));
    g_counting.inner = arena::allocator(a);

    pool::ThreadPool* p = pool::new(test_util::counting_allocator(&g_counting), 2);
    Counter counter;
    sys::memset(&counter, 0, sizeof(Counter));
    mutex::create(&counter.lock);
    for(u64 job_index = 0; job_index < 200; job_index += 1) {
        pool::submit(p, &bump, (void*)&counter);
    }
    pool::wait_all(p);
    pool::destroy(p);

    i32 result = 0;
    if(!testing::expect_eq(counter.value, (i64)200, m)) { result = -1; }
    // The pool struct, the job queue, and the worker array all come through the caller's allocator.
    if(!testing::expect_true(g_counting.allocs >= (u64)3, m)) { result = -2; }
    mutex::destroy(&counter.lock);
    return result;
}

fn i32 main() {
    testing::init();
    u8[] suite = "Thread Pool Tests";
    testing::add(suite, "allocates_through_caller_allocator", &allocates_through_caller_allocator);
    testing::add(suite, "runs_all_jobs",    &runs_all_jobs);
    testing::add(suite, "multiple_batches", &multiple_batches);
    testing::add(suite, "wait_all_empty",   &wait_all_empty);
    testing::add(suite, "single_worker",    &single_worker);
    testing::add(suite, "zero_workers_clamped", &zero_workers_clamped);
    return testing::run();
}
