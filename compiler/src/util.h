#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>

#if !defined(_WIN32)
#include <limits.h>
#endif
#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

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

// Per-thread sink for report() — workers point this at a memstream so the
// driver can drain in graph order without interleaving.
void diag_set_sink(FILE *sink);
// Per-thread source registration for caret echo. Buffer must outlive every
// report() on the thread; path mismatches suppress the echo.
void diag_set_source(const char *path, const char *buf, size_t len);
FILE *diag_stream(void);

void diag_reset_errors(void);
int diag_error_count(void);
void diag_set_errors(int count);

unsigned long djb2(const char *str);

// Dynamic-array helpers. `xs` has `.count`, `.capacity`, `.data`. Return bool.
//   if (!da_init(xs, 4))  return RESULT_MEMORY_ERROR;
#define da_init(xs, cap)                                                                                                                                                                                                                       \
	({                                                                                                                                                                                                                                         \
		(xs).count = 0;                                                                                                                                                                                                                        \
		(xs).capacity = (cap);                                                                                                                                                                                                                 \
		(xs).data = (xs).capacity ? malloc((size_t)(xs).capacity * sizeof(*(xs).data)) : NULL;                                                                                                                                                 \
		(xs).capacity == 0 || (xs).data != NULL;                                                                                                                                                                                               \
	})

#define da_push(xs, x)                                                                                                                                                                                                                         \
	({                                                                                                                                                                                                                                         \
		bool _da_ok = true;                                                                                                                                                                                                                    \
		if ((xs).count >= (xs).capacity) {                                                                                                                                                                                                     \
			int _da_new_cap = (xs).capacity ? (xs).capacity * 2 : 4;                                                                                                                                                                           \
			void *_da_new_data = realloc((xs).data, (size_t)_da_new_cap * sizeof(*(xs).data));                                                                                                                                                 \
			if (!_da_new_data) {                                                                                                                                                                                                               \
				_da_ok = false;                                                                                                                                                                                                                \
			} else {                                                                                                                                                                                                                           \
				(xs).capacity = _da_new_cap;                                                                                                                                                                                                   \
				(xs).data = _da_new_data;                                                                                                                                                                                                      \
			}                                                                                                                                                                                                                                  \
		}                                                                                                                                                                                                                                      \
		if (_da_ok)                                                                                                                                                                                                                            \
			(xs).data[(xs).count++] = (x);                                                                                                                                                                                                     \
		_da_ok;                                                                                                                                                                                                                                \
	})

#define da_deinit(xs)                                                                                                                                                                                                                          \
	do {                                                                                                                                                                                                                                       \
		if ((xs).data && (xs).capacity) {                                                                                                                                                                                                      \
			(xs).count = 0;                                                                                                                                                                                                                    \
			(xs).capacity = 0;                                                                                                                                                                                                                 \
			free((xs).data);                                                                                                                                                                                                                   \
			(xs).data = NULL;                                                                                                                                                                                                                  \
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
