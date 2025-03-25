#pragma once

#if defined(__linux__) || defined(__unix__)
#include <pthread.h>
#include <unistd.h>
#endif

typedef struct Task{
	void (*function)(void *);
	void *argument;
	struct Task *next;
} Task;

typedef struct {
#if defined(__linux__) || defined(__unix__)
	pthread_mutex_t lock;  // Mutex for task queue access.
	pthread_cond_t notify; // Condition variable to signal task availability.
	pthread_cond_t empty;  // Condition variable to signal empty queue.
	pthread_t *threads;	   // Array of worker threads.
	Task *queue_head;	   // Head of the task queue.
	Task *queue_tail;	   // Tail of the task queue.
	int thread_count;	   // Number of worker threads.
	int shutdown;		   // Flag to indicate shutdown.
	int pending;		   // Number of tasks currrently enqueued or in execution.
#endif
} ThreadPool;

ThreadPool *threadpool_create(int num_threads);

void threadpool_submit_task(ThreadPool* pool, void(*function)(void*), void* argument);

void threadpool_wait_all(ThreadPool* pool);

void threadpool_destroy(ThreadPool* pool);
