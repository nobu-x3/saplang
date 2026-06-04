#pragma once

// fd-level stdio helpers, spelled differently on Windows vs POSIX.
#if defined(_WIN32)
#include <io.h>
#define SL_DUP _dup
#define SL_DUP2 _dup2
#define SL_FILENO _fileno
#define SL_CLOSE _close
#define SL_DEVNULL "NUL"
#define SL_POPEN _popen
#define SL_PCLOSE _pclose
#else
#include <unistd.h>
#define SL_DUP dup
#define SL_DUP2 dup2
#define SL_FILENO fileno
#define SL_CLOSE close
#define SL_DEVNULL "/dev/null"
#define SL_POPEN popen
#define SL_PCLOSE pclose
#endif
