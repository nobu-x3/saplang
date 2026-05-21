// libc bindings used by other std modules. Kept minimal; grow as the
// compiler picks up new needs.

extern {
    // memory
    export fn void* malloc(u64 size);
    export fn void  free(void* p);
    export fn void* memcpy(void* dst, const void* src, u64 n);
    export fn void* memset(void* p, i32 byte, u64 n);

    // process
    export fn void exit(i32 code);
    export fn void abort();

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
}
