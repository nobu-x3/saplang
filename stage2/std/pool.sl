import mem;
import threads;
import mutex;
import condvar;
import sys;

struct Job {
    fn* void(void*)     proc;
    void*               arg;
}

export struct ThreadPool {
    mem::Allocator      allocator;
    threads::Thread*    workers;
    u64*                worker_ids;      // each worker publishes its own; spawn() need not fill workers[] before the thread runs
    u32                 n_workers;
    u32                 worker_cap;
    u32                 registered;
    Job*                queue;
    u64                 queue_cap;
    u64                 head;
    u64                 tail;
    u64                 pending;         // submitted but not yet completed (queued + in-flight)
    mutex::Mutex        lock;
    condvar::Condvar    not_empty;
    condvar::Condvar    idle;            // signaled when pending reaches 0
    condvar::Condvar    all_registered;
    bool                shutdown;
}

export fn ThreadPool* new(mem::Allocator a, u32 n_workers) {
    if(n_workers < 1) { n_workers = 1; }        // 0 workers would deadlock wait_all
    ThreadPool* pool = (ThreadPool*)mem::alloc(a, sizeof(ThreadPool));
    sys::memset(pool, 0, sizeof(ThreadPool));
    pool.allocator = a;
    mutex::create(&pool.lock);
    condvar::create(&pool.not_empty);
    condvar::create(&pool.idle);
    condvar::create(&pool.all_registered);
    pool.queue_cap = 64;
    pool.queue = (Job*)mem::alloc(a, pool.queue_cap * sizeof(Job));
    pool.workers = (threads::Thread*)mem::alloc(a, (u64)n_workers * sizeof(threads::Thread));
    pool.worker_ids = (u64*)mem::alloc(a, (u64)n_workers * sizeof(u64));
    pool.worker_cap = n_workers;
    u32 spawned = 0;
    for(u32 worker_index = 0; worker_index < n_workers; worker_index += 1) {
        if(threads::spawn(&pool.workers[spawned], &worker_main, (void*)pool) == 0) { spawned += 1; }
    }

    // thread_index reads worker_ids unlocked, so no worker may still be publishing when new returns.
    mutex::lock(&pool.lock);
    pool.n_workers = spawned;
    while(pool.registered < spawned) { condvar::wait(&pool.all_registered, &pool.lock); }
    mutex::unlock(&pool.lock);
    return pool;
}

fn void* worker_main(void* arg) {
    ThreadPool* pool = (ThreadPool*)arg;
    mutex::lock(&pool.lock);
    pool.worker_ids[pool.registered] = threads::self();
    pool.registered += 1;
    condvar::broadcast(&pool.all_registered);
    mutex::unlock(&pool.lock);
    while(true) {
        mutex::lock(&pool.lock);
        while(pool.head == pool.tail && !pool.shutdown) {
            condvar::wait(&pool.not_empty, &pool.lock);
        }
        if(pool.shutdown && pool.head == pool.tail) {
            mutex::unlock(&pool.lock);
            return null;
        }
        Job job = pool.queue[pool.head];
        pool.head += 1;
        mutex::unlock(&pool.lock);

        job.proc(job.arg);

        mutex::lock(&pool.lock);
        pool.pending -= 1;
        if(pool.pending == 0) { condvar::signal(&pool.idle); }
        mutex::unlock(&pool.lock);
    }
    return null;
}

export fn void submit(ThreadPool* pool, fn* void(void*) proc, void* arg) {
    mutex::lock(&pool.lock);
    if(pool.pending == 0) { pool.head = 0; pool.tail = 0; }       // empty: reclaim the ring for the next batch
    if(pool.tail == pool.queue_cap) {
        u64 new_cap = pool.queue_cap * 2;
        pool.queue = (Job*)mem::realloc_grow(pool.allocator, (void*)pool.queue, pool.queue_cap * sizeof(Job), new_cap * sizeof(Job));
        pool.queue_cap = new_cap;
    }
    pool.queue[pool.tail].proc = proc;
    pool.queue[pool.tail].arg = arg;
    pool.tail += 1;
    pool.pending += 1;
    condvar::signal(&pool.not_empty);
    mutex::unlock(&pool.lock);
}

export fn void wait_all(ThreadPool* pool) {
    mutex::lock(&pool.lock);
    while(pool.pending > 0) {
        condvar::wait(&pool.idle, &pool.lock);
    }
    mutex::unlock(&pool.lock);
}

// Workers occupy [0, n_workers); every other thread shares the slot at n_workers.
export fn u32 thread_index(ThreadPool* pool) {
    u64 id = threads::self();
    for(u32 worker_index = 0; worker_index < pool.n_workers; worker_index += 1) {
        if(pool.worker_ids[worker_index] == id) { return worker_index; }
    }
    return pool.n_workers;
}

export fn u32 thread_index_count(ThreadPool* pool) {
    return pool.n_workers + 1;
}

export fn void destroy(ThreadPool* pool) {
    mutex::lock(&pool.lock);
    pool.shutdown = true;
    condvar::broadcast(&pool.not_empty);
    mutex::unlock(&pool.lock);
    for(u32 worker_index = 0; worker_index < pool.n_workers; worker_index += 1) {
        threads::join(&pool.workers[worker_index], null);
    }
    mutex::destroy(&pool.lock);
    condvar::destroy(&pool.not_empty);
    condvar::destroy(&pool.idle);
    condvar::destroy(&pool.all_registered);
    mem::Allocator allocator = pool.allocator;
    mem::free(allocator, (void*)pool.worker_ids, (u64)pool.worker_cap * sizeof(u64));
    mem::free(allocator, (void*)pool.workers, (u64)pool.worker_cap * sizeof(threads::Thread));
    mem::free(allocator, (void*)pool.queue, pool.queue_cap * sizeof(Job));
    mem::free(allocator, (void*)pool, sizeof(ThreadPool));
}
