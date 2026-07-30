// libc bindings used by other std modules. Kept minimal; grow as the
// compiler picks up new needs.

extern {
    // memory
    export fn void* malloc(u64 size);
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

    // stdio
    export struct FILE { i8 _opaque; }

    export fn FILE* fopen(const i8* filename, const i8* mode);
    export fn i32   fclose(FILE* stream);
    export fn i32   fflush(FILE* stream);

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

    // numeric parsing
    export fn f64 strtod(const i8* nptr, i8** endptr);
}

export const i32 SEEK_SET = 0;
export const i32 SEEK_CUR = 1;
export const i32 SEEK_END = 2;

export const i32 SC_NPROCESSORS_ONLN = 84;   // _SC_NPROCESSORS_ONLN (glibc)

export fn u32 cpu_count() {
    i64 count = sysconf(SC_NPROCESSORS_ONLN);
    if(count < 1) { return 1; }
    return (u32)count;
}
