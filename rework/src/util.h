#pragma once

#include <stddef.h>
typedef enum {
	RESULT_SUCCESS,
	RESULT_PASSED_NULL_PTR,
	RESULT_MEMORY_ERROR,
	RESULT_FAILURE,
	RESULT_PARSING_ERROR,
} CompilerResult;

#define CHK(res)                                                                                                                                                                                                                               \
	if (res != RESULT_SUCCESS) {                                                                                                                                                                                                               \
		printf("%s:%d: Failure code: %d\n", __FILE__, __LINE__, res);                                                                                                                                                                          \
		return res;                                                                                                                                                                                                                            \
	}

typedef struct {
	char *path;
	char *buffer;
} SourceFile;

typedef struct {
	const char *path;
	int line;
	int col;
	size_t id;
} SourceLocation;

void *report(SourceLocation location, const char *msg, int is_warning);

#define da_push(xs, x)                                                                                                                                                                                                                         \
	do {                                                                                                                                                                                                                                       \
		if (xs.count >= xs.capacity) {                                                                                                                                                                                                         \
			xs.capacity *= 2;                                                                                                                                                                                                                  \
			xs.data = realloc(xs.data, xs.capacity * sizeof(*xs.data));                                                                                                                                                                        \
			if (!xs.data)                                                                                                                                                                                                                      \
				return NULL;                                                                                                                                                                                                                   \
		}                                                                                                                                                                                                                                      \
		xs.data[xs.count++] = x;                                                                                                                                                                                                               \
	} while (0)

#define da_push_unsafe(xs, x)                                                                                                                                                                                                                  \
	do {                                                                                                                                                                                                                                       \
		if (xs.count >= xs.capacity) {                                                                                                                                                                                                         \
			xs.capacity *= 2;                                                                                                                                                                                                                  \
			xs.data = realloc(xs.data, xs.capacity * sizeof(*xs.data));                                                                                                                                                                        \
		}                                                                                                                                                                                                                                      \
		xs.data[xs.count++] = x;                                                                                                                                                                                                               \
	} while (0)

#define da_init(xs, cap)                                                                                                                                                                                                                       \
	do {                                                                                                                                                                                                                                       \
		xs.count = 0;                                                                                                                                                                                                                          \
		xs.capacity = cap;                                                                                                                                                                                                                     \
		xs.data = malloc(xs.capacity * sizeof(*xs.data));                                                                                                                                                                                      \
		if (!xs.data)                                                                                                                                                                                                                          \
			return NULL;                                                                                                                                                                                                                       \
	} while (0)

#define da_init_unsafe(xs, cap)                                                                                                                                                                                                                \
	do {                                                                                                                                                                                                                                       \
		xs.count = 0;                                                                                                                                                                                                                          \
		xs.capacity = cap;                                                                                                                                                                                                                     \
		xs.data = malloc(xs.capacity * sizeof(*xs.data));                                                                                                                                                                                      \
	} while (0)

#define da_deinit(xs)                                                                                                                                                                                                                          \
	do {                                                                                                                                                                                                                                       \
		if (xs.data && xs.capacity) {                                                                                                                                                                                                          \
			free(*xs.data);                                                                                                                                                                                                                    \
			xs.count = 0;                                                                                                                                                                                                                      \
			xs.capacity = 0;                                                                                                                                                                                                                   \
			free(xs.data);                                                                                                                                                                                                                     \
			xs.data = NULL;                                                                                                                                                                                                                    \
		}                                                                                                                                                                                                                                      \
	} while (0)

typedef struct {
	char **data;
	int capacity, count;
} StringList;
