#pragma once

#include <stddef.h>
#include <stdio.h>

typedef enum {
	RESULT_SUCCESS,
	RESULT_PASSED_NULL_PTR,
	RESULT_MEMORY_ERROR,
	RESULT_FAILURE,
	RESULT_PARSING_ERROR,
	RESULT_DIRECTORY_NOT_FOUND,
} CompilerResult;

#define CHK(res, deinit_seq)                                                                                                                                                                                                                   \
	do {                                                                                                                                                                                                                                       \
		CompilerResult _chk_res = (res);                                                                                                                                                                                                       \
		if (_chk_res != RESULT_SUCCESS) {                                                                                                                                                                                                      \
			printf("%s:%d: Failure code: %d\n", __FILE__, __LINE__, _chk_res);                                                                                                                                                                 \
			deinit_seq;                                                                                                                                                                                                                        \
			return _chk_res;                                                                                                                                                                                                                   \
		}                                                                                                                                                                                                                                      \
	} while (0)

typedef struct {
	char name[64];
	char path[128];
	int len;
	char *buffer;
} SourceFile;

typedef struct {
	const char *path;
	int line;
	int col;
	size_t id;
} SourceLocation;

void *report(SourceLocation location, const char *msg, int is_warning);

// Per-thread diagnostic sink. When set (typically by a worker task to a
// per-module memstream), report() and other diagnostics route here
// instead of stderr; the driver drains the buffer in graph order after
// the threadpool join, so stderr never sees interleaved bytes from
// multiple workers.
void diag_set_sink(FILE *sink);
FILE *diag_stream(void);

unsigned long djb2(const char *str);

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

#define da_push_unsafe_ptr(xs, x)                                                                                                                                                                                                              \
	do {                                                                                                                                                                                                                                       \
		if (xs->count >= xs->capacity) {                                                                                                                                                                                                       \
			xs->capacity *= 2;                                                                                                                                                                                                                 \
			xs->data = realloc(xs->data, xs->capacity * sizeof(*xs->data));                                                                                                                                                                    \
		}                                                                                                                                                                                                                                      \
		xs->data[xs->count++] = x;                                                                                                                                                                                                             \
	} while (0)

#define da_init(xs, cap)                                                                                                                                                                                                                       \
	do {                                                                                                                                                                                                                                       \
		xs.count = 0;                                                                                                                                                                                                                          \
		xs.capacity = cap;                                                                                                                                                                                                                     \
		xs.data = malloc(xs.capacity * sizeof(*xs.data));                                                                                                                                                                                      \
		if (!xs.data)                                                                                                                                                                                                                          \
			return NULL;                                                                                                                                                                                                                       \
	} while (0)

#define da_init_result(xs, cap)                                                                                                                                                                                                                \
	do {                                                                                                                                                                                                                                       \
		xs.count = 0;                                                                                                                                                                                                                          \
		xs.capacity = cap;                                                                                                                                                                                                                     \
		xs.data = malloc(xs.capacity * sizeof(*xs.data));                                                                                                                                                                                      \
		if (!xs.data)                                                                                                                                                                                                                          \
			return RESULT_MEMORY_ERROR;                                                                                                                                                                                                        \
	} while (0)

#define da_push_result(xs, x)                                                                                                                                                                                                                  \
	do {                                                                                                                                                                                                                                       \
		if (xs.count >= xs.capacity) {                                                                                                                                                                                                         \
			xs.capacity *= 2;                                                                                                                                                                                                                  \
			xs.data = realloc(xs.data, xs.capacity * sizeof(*xs.data));                                                                                                                                                                        \
			if (!xs.data)                                                                                                                                                                                                                      \
				return RESULT_MEMORY_ERROR;                                                                                                                                                                                                    \
		}                                                                                                                                                                                                                                      \
		xs.data[xs.count++] = x;                                                                                                                                                                                                               \
	} while (0)

#define da_push_safe_result(xs, x, on_error)                                                                                                                                                                                                   \
	do {                                                                                                                                                                                                                                       \
		if (xs.count >= xs.capacity) {                                                                                                                                                                                                         \
			xs.capacity *= 2;                                                                                                                                                                                                                  \
			xs.data = realloc(xs.data, xs.capacity * sizeof(*xs.data));                                                                                                                                                                        \
			if (!xs.data) {                                                                                                                                                                                                                    \
				on_error return RESULT_MEMORY_ERROR;                                                                                                                                                                                           \
			}                                                                                                                                                                                                                                  \
		}                                                                                                                                                                                                                                      \
		xs.data[xs.count++] = x;                                                                                                                                                                                                               \
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

char *flatten_stringlist(const StringList *list);

#define print(string, format, ...)                                                                                                                                                                                                             \
	do {                                                                                                                                                                                                                                       \
		if (string) {                                                                                                                                                                                                                          \
			char formatted[256] = "";                                                                                                                                                                                                          \
			snprintf(formatted, sizeof(formatted), format, ##__VA_ARGS__);                                                                                                                                                                     \
			strcat(string, formatted);                                                                                                                                                                                                         \
		} else {                                                                                                                                                                                                                               \
			printf(format, ##__VA_ARGS__);                                                                                                                                                                                                     \
		}                                                                                                                                                                                                                                      \
	} while (0)

char* full_path(const char *restrict file_name, char* restrict resolved_name);
// Searches for filename recursively in root_dir. NOT thread safe. Allocates memory.
char* find_file_in_dir(const char* root_dir, const char* filename);
char* file_name(const char* restrict file_name);
int make_dir(const char* pathname, int mode);
char* dir_name(char* path);
int rmrf(char *path);
