#pragma once

typedef enum {
  RESULT_SUCCESS,
  RESULT_MEMORY_ERROR,
  RESULT_FAILURE,
} CompilerResult;

#define CHK(res)                                                                                                                                               \
  if (res != RESULT_SUCCESS) {                                                                                                                                 \
    printf("%s:%d: Failure code: %d\n", __FILE__, __LINE__, res);                                                                                              \
    return 1;                                                                                                                                                  \
  }
