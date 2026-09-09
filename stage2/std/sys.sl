// libc bindings used by other std modules. Kept minimal; grow as the
// compiler picks up new needs.

extern {
    // memory
    export fn void* malloc(u64 size);
    // size must be a multiple of alignment; the result is still released with free.
    export fn void* aligned_alloc(u64 alignment, u64 size);
    export fn void* realloc(void* p, u64 size);
    export fn void  free(void* p);
    export fn void* memcpy(void* dst, const void* src, u64 n);
    export fn void* memset(void* p, i32 byte, u64 n);
    export fn i32   memcmp(const void *str1, const void *str2, u64 n);

    // process
    export fn void exit(i32 code);
    export fn void abort();
    export fn i64  sysconf(i32 name);
    export fn i32  fork();
    export fn i32  execvp(const i8* file, i8** argv);
    export fn i32  waitpid(i32 pid, i32* status, i32 options);
    export fn void _exit(i32 code);
    export fn i32  mkdir(const i8* path, u32 mode);
    export fn i8*  getenv(const i8* name);
    export fn i64  readlink(const i8* path, i8* buf, u64 size);
    export fn i32  setenv(const i8* name, const i8* value, i32 overwrite);

    // Raw descriptors, so a caller can redirect one of the standard streams and put it back.
    export fn i32  open(const i8* path, i32 flags, u32 mode);
    export fn i32  close(i32 fd);
    export fn i64  read(i32 fd, void* buf, u64 count);
    export fn i32  dup(i32 fd);
    export fn i32  dup2(i32 old_fd, i32 new_fd);
    export fn i32  unlink(const i8* path);

    // stdio
    export struct FILE { i8 _opaque; }

    // glibc exports these as real data symbols; the UCRT does not.
    FILE* stdout;
    FILE* stderr;

    export fn FILE* fopen(const i8* filename, const i8* mode);
    export fn i32   fclose(FILE* stream);
    export fn i32   fflush(FILE* stream);
    export fn i32   setvbuf(FILE* stream, i8* buf, i32 mode, u64 size);

    export fn FILE* popen(const i8* command, const i8* mode);
    export fn i32   pclose(FILE* stream);

    // printf family. Use dprintf(2, ...) for stderr — sidesteps the
    // question of how to expose libc's stdout/stderr globals as externs.
    export fn i32 printf(const i8* fmt, ...);
    export fn i32 fprintf(FILE* stream, const i8* fmt, ...);
    export fn i32 dprintf(i32 fd, const i8* fmt, ...);
    export fn i32 snprintf(i8* buf, u64 cap, const i8* fmt, ...);

    // string + char output
    export fn i32 fputs(const i8* s, FILE* stream);
    export fn i32 puts(const i8* s);
    export fn i32 putchar(i32 c);
    export fn i32 fputc(i32 c, FILE* stream);

    // raw read/write
    export fn u64 fread(void* buf, u64 size, u64 nmemb, FILE* stream);
    export fn u64 fwrite(const void* buf, u64 size, u64 nmemb, FILE* stream);

    // fgetc returns the byte zero-extended or -1 on EOF/error.
    export fn i32 fgetc(FILE* stream);
    export fn i32 feof(FILE* stream);
    export fn i32 ferror(FILE* stream);

    export fn i32 fseek(FILE* stream, i64 offset, i32 whence);
    export fn i64 ftell(FILE* stream);

    export fn i32 remove(const i8* path);

    export fn i32 clock_gettime(i32 clock_id, TimeSpec* ts);

    // numeric parsing
    export fn f64 strtod(const i8* nptr, i8** endptr);
}

// open(2) flags, x86-64 Linux
export const i32 O_RDONLY = 0;
export const i32 O_WRONLY = 1;
export const i32 O_CREAT  = 64;
export const i32 O_TRUNC  = 512;

export const i32 SEEK_SET = 0;
export const i32 SEEK_CUR = 1;
export const i32 SEEK_END = 2;

export const i32 IONBF = 2;

export const i32 SC_NPROCESSORS_ONLN = 84;   // _SC_NPROCESSORS_ONLN (glibc)

export fn FILE* stdout_file() {
    return stdout;
}

export fn FILE* stderr_file() {
    return stderr;
}

export fn i32 spawn_wait(i8** argv) {
    i32 pid = fork();
    if(pid < 0) { return -1; }
    if(pid == 0) {
        execvp(argv[0], argv);
        _exit(127);
        return 127;
    }
    i32 status = 0;
    waitpid(pid, &status, 0);
    return (status >> 8) & 255;
}

// Handles are opaque: a pid here, a process handle on Windows.
export fn i64 spawn_async(i8** argv) {
    i32 pid = fork();
    if(pid < 0) { return (i64)-1; }
    if(pid == 0) {
        execvp(argv[0], argv);
        _exit(127);
    }
    return (i64)pid;
}

// The handle list is unused here: waitpid already reaps whichever child finished first.
export fn i64 wait_any(i64* handles, u64 count, i32* status) {
    i32 raw = 0;
    i32 done = waitpid(-1, &raw, 0);
    *status = (raw >> 8) & 255;
    if(done < 0) { return (i64)-1; }
    return (i64)done;
}
export fn i64 exe_path(i8* buf, u64 size) {
    return readlink("/proc/self/exe", buf, size);
}

struct TimeSpec {
    i64 sec;
    i64 nsec;
}

const i32 CLOCK_MONOTONIC = 1;

// Monotonic nanoseconds; meaningful only as a delta between two calls.
export fn u64 now_ns() {
    TimeSpec ts;
    memset(&ts, 0, sizeof(TimeSpec));
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (u64)ts.sec * 1000000000 + (u64)ts.nsec;
}
export fn u32 cpu_count() {
    i64 count = sysconf(SC_NPROCESSORS_ONLN);
    if(count < 1) { return 1; }
    return (u32)count;
}
