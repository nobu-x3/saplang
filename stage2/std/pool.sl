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
    u32                 n_workers;
    Job*                queue;
    u64                 queue_cap;
    u64                 head;
    u64                 tail;
    u64                 pending;         // submitted but not yet completed (queued + in-flight)
    mutex::Mutex        lock;
    condvar::Condvar    not_empty;
    condvar::Condvar    idle;            // signaled when pending reaches 0
    bool                shutdown;
}

export fn ThreadPool* new(mem::Allocator a, u32 n_workers) {
    if(n_workers < 1) { n_workers = 1; }        // 0 workers would deadlock wait_all
    ThreadPool* pool = (ThreadPool*)mem::alloc(a, sizeof(ThreadPool));
    sys::memset(pool, 0, sizeof(ThreadPool));
    pool.allocator = a;
    pool.n_workers = n_workers;
    mutex::create(&pool.lock);
    condvar::create(&pool.not_empty);
    condvar::create(&pool.idle);
    pool.queue_cap = 64;
    pool.queue = (Job*)mem::alloc(a, pool.queue_cap * sizeof(Job));
    pool.workers = (threads::Thread*)mem::alloc(a, (u64)n_workers * sizeof(threads::Thread));
    for(u32 worker_index = 0; worker_index < n_workers; worker_index += 1) {
        threads::spawn(&pool.workers[worker_index], &worker_main, (void*)pool);
    }
    return pool;
}

fn void* worker_main(void* arg) {
    ThreadPool* pool = (ThreadPool*)arg;
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
}
