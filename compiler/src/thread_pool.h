#pragma once

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
typedef CRITICAL_SECTION sl_mutex_t;
typedef CONDITION_VARIABLE sl_cond_t;
typedef HANDLE sl_thread_t;
#else
#include <pthread.h>
#include <unistd.h>
typedef pthread_mutex_t sl_mutex_t;
typedef pthread_cond_t sl_cond_t;
typedef pthread_t sl_thread_t;
#endif

typedef struct Task {
	void (*function)(void *);
	void *argument;
	struct Task *next;
} Task;

typedef struct {
	sl_mutex_t lock;
	sl_cond_t notify;
	sl_cond_t empty;
	sl_thread_t *threads;
	Task *queue_head;
	Task *queue_tail;
	int thread_count;
	int shutdown;
	int pending;
} ThreadPool;

ThreadPool *threadpool_create(int num_threads);

void threadpool_submit_task(ThreadPool* pool, void(*function)(void*), void* argument);

void threadpool_wait_all(ThreadPool* pool);

void threadpool_destroy(ThreadPool* pool);
