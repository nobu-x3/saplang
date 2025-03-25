#pragma once
#include <stdlib.h>
#include <thread_pool.h>
#include <unity.h>

int _get_num_of_cores() {
#if defined(__linux__) || defined(__unix__)
	return sysconf(_SC_NPROCESSORS_ONLN);
#endif
	// @TODO: do this for windows & mac
	return 1;
}

typedef struct {
	FILE *old_stdout;
	FILE *temp;
} Log;

Log log_begin() {
	FILE *temp = tmpfile();
	if (!temp) {
		TEST_FAIL_MESSAGE("Failed to create temporary file for output capture");
	}

	// Save the current stdout pointer.
	FILE *old_stdout = stdout;
	stdout = temp;
	Log log = {old_stdout, temp};
	return log;
}

char *log_end(Log *log) {
	fflush(stdout);
	// Restore stdout.
	//
	stdout = log->old_stdout;

	// Determine the size of the output.
	fseek(log->temp, 0, SEEK_END);
	long size = ftell(log->temp);
	fseek(log->temp, 0, SEEK_SET);

	char *buffer = malloc(size + 1);
	if (!buffer) {
		fclose(log->temp);
		TEST_FAIL_MESSAGE("Memory allocation failed in captureASTOutput");
	}

	fread(buffer, 1, size, log->temp);
	buffer[size] = '\0';

	fclose(log->temp);
	return buffer;
}

void sample_task(void *arg) {
	int task_num = *(int *)arg;
	printf("Task %d running on thread %lu\n", task_num, pthread_self());
	sleep(1);
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
