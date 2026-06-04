#include "thread_pool.h"
#include <stdio.h>
#include <stdlib.h>

#if defined(_WIN32)
#include <process.h>
#define WORKER_RET unsigned __stdcall
#else
#define WORKER_RET void *
#endif

static int sl_mutex_init(sl_mutex_t *m) {
#if defined(_WIN32)
	InitializeCriticalSection(m);
	return 0;
#else
	return pthread_mutex_init(m, NULL);
#endif
}

static void sl_mutex_lock(sl_mutex_t *m) {
#if defined(_WIN32)
	EnterCriticalSection(m);
#else
	pthread_mutex_lock(m);
#endif
}

static void sl_mutex_unlock(sl_mutex_t *m) {
#if defined(_WIN32)
	LeaveCriticalSection(m);
#else
	pthread_mutex_unlock(m);
#endif
}

static void sl_mutex_destroy(sl_mutex_t *m) {
#if defined(_WIN32)
	DeleteCriticalSection(m);
#else
	pthread_mutex_destroy(m);
#endif
}

static void sl_cond_init(sl_cond_t *c) {
#if defined(_WIN32)
	InitializeConditionVariable(c);
#else
	pthread_cond_init(c, NULL);
#endif
}

static void sl_cond_wait(sl_cond_t *c, sl_mutex_t *m) {
#if defined(_WIN32)
	SleepConditionVariableCS(c, m, INFINITE);
#else
	pthread_cond_wait(c, m);
#endif
}

static void sl_cond_signal(sl_cond_t *c) {
#if defined(_WIN32)
	WakeConditionVariable(c);
#else
	pthread_cond_signal(c);
#endif
}

static void sl_cond_broadcast(sl_cond_t *c) {
#if defined(_WIN32)
	WakeAllConditionVariable(c);
#else
	pthread_cond_broadcast(c);
#endif
}

static void sl_cond_destroy(sl_cond_t *c) {
#if defined(_WIN32)
	(void)c;
#else
	pthread_cond_destroy(c);
#endif
}

static void sl_thread_join(sl_thread_t t) {
#if defined(_WIN32)
	WaitForSingleObject(t, INFINITE);
	CloseHandle(t);
#else
	pthread_join(t, NULL);
#endif
}

WORKER_RET threadpool_worker(void *arg) {
	ThreadPool *pool = (ThreadPool *)arg;
	Task *task;

	for (;;) {
		sl_mutex_lock(&(pool->lock));

		// Wait for task or shutdown
		while (pool->queue_head == NULL && !pool->shutdown) {
			sl_cond_wait(&(pool->notify), &(pool->lock));
		}

		if (pool->shutdown && pool->queue_head == NULL) {
			sl_mutex_unlock(&(pool->lock));
			break;
		}

		// Dequeue
		task = pool->queue_head;
		if (task) {
			pool->queue_head = task->next;
			if (pool->queue_head == NULL)
				pool->queue_tail = NULL;
		}
		sl_mutex_unlock(&(pool->lock));

		if (task) {
			task->function(task->argument);
			free(task);

			// Task is complete, decrement pending
			sl_mutex_lock(&(pool->lock));
			--pool->pending;

			// Notify if empty
			if (pool->pending == 0) {
				sl_cond_signal(&(pool->empty));
			}
			sl_mutex_unlock(&(pool->lock));
		}
	}
#if defined(_WIN32)
	return 0;
#else
	return NULL;
#endif
}

static int sl_thread_create(sl_thread_t *t, ThreadPool *pool) {
#if defined(_WIN32)
	*t = (HANDLE)_beginthreadex(NULL, 0, threadpool_worker, pool, 0, NULL);
	return *t == NULL;
#else
	return pthread_create(t, NULL, threadpool_worker, pool) != 0;
#endif
}

ThreadPool *threadpool_create(int num_threads) {
	if (num_threads <= 0)
		return NULL;

	ThreadPool *pool = malloc(sizeof(ThreadPool));
	if (!pool) {
		fprintf(stderr, "error: unable to allocate thread pool with %d threads.\n", num_threads);
		return NULL;
	}

	pool->thread_count = num_threads;
	pool->shutdown = 0;
	pool->queue_head = NULL;
	pool->queue_tail = NULL;
	pool->pending = 0;

	if (sl_mutex_init(&(pool->lock))) {
		fprintf(stderr, "error: unable to init mutex and/or condition vars");
		free(pool);
		return NULL;
	}
	sl_cond_init(&(pool->notify));
	sl_cond_init(&(pool->empty));

	pool->threads = malloc(sizeof(sl_thread_t) * num_threads);
	if (!pool->threads) {
		sl_mutex_destroy(&(pool->lock));
		sl_cond_destroy(&(pool->notify));
		sl_cond_destroy(&(pool->empty));
		free(pool);
		return NULL;
	}

	for (int i = 0; i < num_threads; ++i) {
		if (sl_thread_create(&(pool->threads[i]), pool)) {
			pool->shutdown = 1;
			for (int j = 0; j < i; ++j) {
				sl_thread_join(pool->threads[j]);
			}
			free(pool->threads);
			sl_mutex_destroy(&(pool->lock));
			sl_cond_destroy(&(pool->notify));
			sl_cond_destroy(&(pool->empty));
			free(pool);
			return NULL;
		}
	}
	return pool;
}

void threadpool_submit_task(ThreadPool *pool, void (*function)(void *), void *argument) {
	if (!pool || !function)
		return;

	Task *task = malloc(sizeof(Task));
	if (!task)
		return;

	task->function = function;
	task->argument = argument;
	task->next = NULL;

	sl_mutex_lock(&(pool->lock));

	++pool->pending;

	if (pool->queue_tail == NULL) {
		pool->queue_head = task;
		pool->queue_tail = task;
	} else {
		pool->queue_tail->next = task;
		pool->queue_tail = task;
	}

	sl_cond_signal(&(pool->notify));
	sl_mutex_unlock(&(pool->lock));
	return;
}

void threadpool_wait_all(ThreadPool *pool) {
	if (!pool)
		return;

	sl_mutex_lock(&(pool->lock));
	while (pool->pending != 0) {
		sl_cond_wait(&(pool->empty), &(pool->lock));
	}
	sl_mutex_unlock(&(pool->lock));
}

void threadpool_destroy(ThreadPool *pool) {
	if (!pool)
		return;

	sl_mutex_lock(&(pool->lock));
	pool->shutdown = 1;
	sl_cond_broadcast(&(pool->notify));
	sl_mutex_unlock(&(pool->lock));

	for (int i = 0; i < pool->thread_count; ++i) {
		sl_thread_join(pool->threads[i]);
	}

	Task *current_task = pool->queue_head;
	while (current_task) {
		Task *next_task = current_task->next;
		free(current_task);
		current_task = next_task;
	}

	free(pool->threads);
	sl_mutex_destroy(&(pool->lock));
	sl_cond_destroy(&(pool->notify));
	sl_cond_destroy(&(pool->empty));
	free(pool);
}
