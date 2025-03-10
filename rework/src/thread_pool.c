#include "thread_pool.h"
#include <stdio.h>
#include <stdlib.h>

void *threadpool_worker(void *arg) {
	ThreadPool *pool = (ThreadPool *)arg;
	Task *task;

	for (;;) {
		pthread_mutex_lock(&(pool->lock));

		// Wait for task or shutdown
		while (pool->queue_head == NULL && !pool->shutdown) {
			pthread_cond_wait(&(pool->notify), &(pool->lock));
		}

		if (pool->shutdown && pool->queue_head == NULL) {
			pthread_mutex_unlock(&(pool->lock));
			break;
		}

		// Dequeue
		task = pool->queue_head;
		if (task) {
			pool->queue_head = task->next;
			if (pool->queue_head == NULL)
				pool->queue_tail = NULL;
		}
		pthread_mutex_unlock(&(pool->lock));

		if (task) {
			task->function(task->argument);
			free(task);

			// Task is complete, decrement pending
			pthread_mutex_lock(&(pool->lock));
			--pool->pending;

			// Notify if empty
			if (pool->pending == 0) {
				pthread_cond_signal(&(pool->empty));
			}
			pthread_mutex_unlock(&(pool->lock));
		}
	}
	pthread_exit(NULL);
	return NULL;
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

	if (pthread_mutex_init(&(pool->lock), NULL) || pthread_cond_init(&(pool->notify), NULL) || pthread_cond_init(&(pool->empty), NULL)) {
		fprintf(stderr, "error: unable to init mutex and/or condition vars");
		free(pool);
		return NULL;
	}

	pool->threads = malloc(sizeof(pthread_t) * num_threads);
	if (!pool->threads) {
		pthread_mutex_destroy(&(pool->lock));
		pthread_cond_destroy(&(pool->notify));
		pthread_cond_destroy(&(pool->empty));
		free(pool);
		return NULL;
	}

	for (int i = 0; i < num_threads; ++i) {
		if (pthread_create(&(pool->threads[i]), NULL, threadpool_worker, pool)) {
			pool->shutdown = 1;
			for (int j = 0; j < i; ++j) {
				pthread_join(pool->threads[j], NULL);
			}
			free(pool->threads);
			pthread_mutex_destroy(&(pool->lock));
			pthread_cond_destroy(&(pool->notify));
			pthread_cond_destroy(&(pool->empty));
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

	pthread_mutex_lock(&(pool->lock));

	++pool->pending;

	if (pool->queue_tail == NULL) {
		pool->queue_head = task;
		pool->queue_tail = task;
	} else {
		pool->queue_tail->next = task;
		pool->queue_tail = task;
	}

	pthread_cond_signal(&(pool->notify));
	pthread_mutex_unlock(&(pool->lock));
	return;
}

void threadpool_wait_all(ThreadPool *pool) {
	if (!pool)
		return;

	pthread_mutex_lock(&(pool->lock));
	while (pool->pending != 0) {
		pthread_cond_wait(&(pool->empty), &(pool->lock));
	}
	pthread_mutex_unlock(&(pool->lock));
}

void threadpool_destroy(ThreadPool *pool) {
	if (!pool)
		return;

	pthread_mutex_lock(&(pool->lock));
	pool->shutdown = 1;
	pthread_cond_broadcast(&(pool->notify));
	pthread_mutex_unlock(&(pool->lock));

	for (int i = 0; i < pool->thread_count; ++i) {
		pthread_join(pool->threads[i], NULL);
	}

	Task *current_task = pool->queue_head;
	while (current_task) {
		Task *next_task = current_task->next;
		free(current_task);
		current_task = next_task;
	}

	free(pool->threads);
	pthread_mutex_destroy(&(pool->lock));
	pthread_cond_destroy(&(pool->notify));
	pthread_cond_destroy(&(pool->empty));
	free(pool);
}
