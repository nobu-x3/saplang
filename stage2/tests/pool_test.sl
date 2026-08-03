import testing;
import test_util;
import pool;
import mutex;
import condvar;
import threads;
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

fn i32 runs_all_jobs(arena::Arena* a, const u8[]m) {
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

fn i32 multiple_batches(arena::Arena* a, const u8[]m) {
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

fn i32 wait_all_empty(arena::Arena* a, const u8[]m) {
    pool::ThreadPool* p = pool::new(arena::allocator(a), 2);
    pool::wait_all(p);
    pool::destroy(p);
    return 0;
}

fn i32 single_worker(arena::Arena* a, const u8[]m) {
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

fn i32 zero_workers_clamped(arena::Arena* a, const u8[]m) {
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
fn i32 allocates_through_caller_allocator(arena::Arena* a, const u8[]m) {
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

struct IndexProbe {
    pool::ThreadPool*   pool;
    mutex::Mutex        lock;
    condvar::Condvar    all_here;
    u64[8]              slot_owner;
    i64[8]              hits;
    i64                 shared_slots;
    i64                 out_of_range;
    i64                 arrived;
    i64                 expected;
}

fn void claim_index(IndexProbe* probe) {
    u32 index = pool::thread_index(probe.pool);
    u64 id = threads::self();
    mutex::lock(&probe.lock);
    if(index >= pool::thread_index_count(probe.pool)) {
        probe.out_of_range += 1;
    } else {
        if(probe.slot_owner[index] == 0) { probe.slot_owner[index] = id; }
        else if(probe.slot_owner[index] != id) { probe.shared_slots += 1; }
        probe.hits[index] += 1;
    }
}

fn void record_index(void* arg) {
    IndexProbe* probe = (IndexProbe*)arg;
    claim_index(probe);
    mutex::unlock(&probe.lock);
}

fn void record_index_at_barrier(void* arg) {
    IndexProbe* probe = (IndexProbe*)arg;
    claim_index(probe);
    probe.arrived += 1;
    if(probe.arrived >= probe.expected) { condvar::broadcast(&probe.all_here); }
    while(probe.arrived < probe.expected) { condvar::wait(&probe.all_here, &probe.lock); }
    mutex::unlock(&probe.lock);
}

fn i32 thread_index_is_per_worker(arena::Arena* a, const u8[]m) {
    pool::ThreadPool* p = pool::new(arena::allocator(a), 4);
    IndexProbe probe;
    sys::memset(&probe, 0, sizeof(IndexProbe));
    probe.pool = p;
    probe.expected = 4;
    mutex::create(&probe.lock);
    condvar::create(&probe.all_here);
    // One job per worker, each parked until the last arrives, so no worker can take a second.
    for(u64 job_index = 0; job_index < 4; job_index += 1) {
        pool::submit(p, &record_index_at_barrier, (void*)&probe);
    }
    pool::wait_all(p);

    i32 result = 0;
    if(!testing::expect_eq(pool::thread_index_count(p), (u32)5, m)) { result = -1; }
    // The submitting thread is not a worker, so it lands in the spare slot rather than colliding with worker 0.
    if(!testing::expect_eq(pool::thread_index(p), (u32)4, m)) { result = -2; }
    if(!testing::expect_eq(probe.out_of_range, (i64)0, m)) { result = -3; }
    if(!testing::expect_eq(probe.shared_slots, (i64)0, m)) { result = -4; }
    for(u64 slot = 0; slot < 4; slot += 1) {
        if(!testing::expect_eq(probe.hits[slot], (i64)1, m)) { result = -5; }
    }
    if(!testing::expect_eq(probe.hits[4], (i64)0, m)) { result = -6; }

    pool::destroy(p);
    condvar::destroy(&probe.all_here);
    mutex::destroy(&probe.lock);
    return result;
}

fn i32 thread_index_stable_under_churn(arena::Arena* a, const u8[]m) {
    pool::ThreadPool* p = pool::new(arena::allocator(a), 4);
    IndexProbe probe;
    sys::memset(&probe, 0, sizeof(IndexProbe));
    probe.pool = p;
    mutex::create(&probe.lock);
    condvar::create(&probe.all_here);
    for(u64 job_index = 0; job_index < 2000; job_index += 1) {
        pool::submit(p, &record_index, (void*)&probe);
    }
    pool::wait_all(p);

    i32 result = 0;
    if(!testing::expect_eq(probe.out_of_range, (i64)0, m)) { result = -1; }
    if(!testing::expect_eq(probe.shared_slots, (i64)0, m)) { result = -2; }
    i64 total = 0;
    for(u64 slot = 0; slot < 4; slot += 1) { total += probe.hits[slot]; }
    if(!testing::expect_eq(total, (i64)2000, m)) { result = -3; }
    if(!testing::expect_eq(probe.hits[4], (i64)0, m)) { result = -4; }

    pool::destroy(p);
    condvar::destroy(&probe.all_here);
    mutex::destroy(&probe.lock);
    return result;
}

fn i32 thread_index_single_worker(arena::Arena* a, const u8[]m) {
    pool::ThreadPool* p = pool::new(arena::allocator(a), 1);
    IndexProbe probe;
    sys::memset(&probe, 0, sizeof(IndexProbe));
    probe.pool = p;
    mutex::create(&probe.lock);
    condvar::create(&probe.all_here);
    for(u64 job_index = 0; job_index < 100; job_index += 1) {
        pool::submit(p, &record_index, (void*)&probe);
    }
    pool::wait_all(p);

    i32 result = 0;
    if(!testing::expect_eq(probe.hits[0], (i64)100, m)) { result = -1; }
    if(!testing::expect_eq(pool::thread_index(p), (u32)1, m)) { result = -2; }
    pool::destroy(p);
    condvar::destroy(&probe.all_here);
    mutex::destroy(&probe.lock);
    return result;
}

fn i32 main() {
    testing::init();
    const u8[] suite = "Thread Pool Tests";
    testing::add(suite, "allocates_through_caller_allocator", &allocates_through_caller_allocator);
    testing::add(suite, "runs_all_jobs",    &runs_all_jobs);
    testing::add(suite, "multiple_batches", &multiple_batches);
    testing::add(suite, "wait_all_empty",   &wait_all_empty);
    testing::add(suite, "single_worker",    &single_worker);
    testing::add(suite, "zero_workers_clamped", &zero_workers_clamped);
    testing::add(suite, "thread_index_is_per_worker", &thread_index_is_per_worker);
    testing::add(suite, "thread_index_stable_under_churn", &thread_index_stable_under_churn);
    testing::add(suite, "thread_index_single_worker", &thread_index_single_worker);
    return testing::run();
}
