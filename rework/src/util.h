#pragma once

#include <stddef.h>
typedef enum {
  RESULT_SUCCESS,
  RESULT_PASSED_NULL_PTR,
  RESULT_MEMORY_ERROR,
  RESULT_FAILURE,
  RESULT_PARSING_ERROR,
} CompilerResult;

#define CHK(res)                                                                                                                                               \
  if (res != RESULT_SUCCESS) {                                                                                                                                 \
    printf("%s:%d: Failure code: %d\n", __FILE__, __LINE__, res);                                                                                              \
    return res;                                                                                                                                                  \
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

void *report(SourceLocation location, const char* msg, int is_warning);
