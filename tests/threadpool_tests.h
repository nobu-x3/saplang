#pragma once
#include "platform.h"
#include <stdio.h>
#include <stdlib.h>
#include <thread_pool.h>
#include <unity.h>

#if !defined(_WIN32)
#include <pthread.h>
#endif

int _get_num_of_cores() {
#if defined(_WIN32)
	SYSTEM_INFO info;
	GetSystemInfo(&info);
	return (int)info.dwNumberOfProcessors;
#else
	return sysconf(_SC_NPROCESSORS_ONLN);
#endif
}

typedef struct {
	int saved_fd;
	FILE *temp;
} Log;

Log log_begin() {
	fflush(stdout);
	FILE *temp = tmpfile();
	if (!temp) {
		TEST_FAIL_MESSAGE("Failed to create temporary file for output capture");
	}
	int saved = SL_DUP(SL_FILENO(stdout));
	SL_DUP2(SL_FILENO(temp), SL_FILENO(stdout));
	Log log = {saved, temp};
	return log;
}

char *log_end(Log *log) {
	fflush(stdout);
	SL_DUP2(log->saved_fd, SL_FILENO(stdout));
	SL_CLOSE(log->saved_fd);

	fseek(log->temp, 0, SEEK_END);
	long size = ftell(log->temp);
	fseek(log->temp, 0, SEEK_SET);

	char *buffer = malloc(size + 1);
	if (!buffer) {
		fclose(log->temp);
		TEST_FAIL_MESSAGE("Memory allocation failed in output capture");
	}

	fread(buffer, 1, size, log->temp);
	buffer[size] = '\0';

	fclose(log->temp);
	return buffer;
}

void sample_task(void *arg) {
	int task_num = *(int *)arg;
#if defined(_WIN32)
	printf("Task %d running on thread %lu\n", task_num, (unsigned long)GetCurrentThreadId());
	Sleep(1000);
#else
	printf("Task %d running on thread %lu\n", task_num, (unsigned long)pthread_self());
	sleep(1);
#endif
	printf("Task %d finished.\n", task_num);
}

void test_PrintfTest(void) {
	int num_tasks = 16;
	int num_threads = _get_num_of_cores();
	ThreadPool *pool = threadpool_create(num_threads);
	if (!pool) {
		TEST_FAIL();
		return;
	}
	Log log = log_begin();
	int tasks[num_tasks];
	for (int i = 0; i < num_tasks; ++i) {
		tasks[i] = i;
		threadpool_submit_task(pool, sample_task, &tasks[i]);
	}

	threadpool_wait_all(pool);
	printf("All tasks completed. \n");
	threadpool_destroy(pool);

	char *out = log_end(&log);
	printf("%s\n", out);
	free(out);
}
