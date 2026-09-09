struct SystemInfo {
    u32   oem_id;
    u32   page_size;
    void* min_app_addr;
    void* max_app_addr;
    u64   active_processor_mask;
    u32   number_of_processors;
    u32   processor_type;
    u32   allocation_granularity;
    u16   processor_level;
    u16   processor_revision;
}

extern {
    // Memory from _aligned_malloc may not be released with free, so every allocation takes this route.
    fn void* _aligned_malloc(u64 size, u64 alignment);
    fn void* _aligned_realloc(void* p, u64 size, u64 alignment);
    fn void  _aligned_free(void* p);

    export fn void* memcpy(void* dst, const void* src, u64 n);
    export fn void* memset(void* p, i32 byte, u64 n);
    export fn i32   memcmp(const void *str1, const void *str2, u64 n);

    export fn void exit(i32 code);
    export fn void abort();
    export fn i8*  getenv(const i8* name);

    fn i32 _mkdir(const i8* path);
    fn i32 _putenv_s(const i8* name, const i8* value);
    fn i32 _open(const i8* path, i32 flags, i32 mode);
    fn i32 _close(i32 fd);
    fn i32 _read(i32 fd, void* buf, u32 count);
    fn i32 _dup(i32 fd);
    fn i32 _dup2(i32 old_fd, i32 new_fd);
    fn i32 _unlink(const i8* path);
    fn i64 _spawnvp(i32 mode, const i8* file, i8** argv);

    export struct FILE { i8 _opaque; }

    fn FILE* _fsopen(const i8* filename, const i8* mode, i32 shflag);
    export fn i32   fclose(FILE* stream);
    export fn i32   fflush(FILE* stream);
    export fn i32   setvbuf(FILE* stream, i8* buf, i32 mode, u64 size);

    fn FILE* _popen(const i8* command, const i8* mode);
    fn i32   _pclose(FILE* stream);

    // The UCRT has no stdout/stderr data symbols; they are slots 1 and 2 of this accessor.
    fn FILE* __acrt_iob_func(u32 index);

    export fn i32 printf(const i8* fmt, ...);
    export fn i32 fprintf(FILE* stream, const i8* fmt, ...);
    export fn i32 snprintf(i8* buf, u64 cap, const i8* fmt, ...);

    export fn i32 fputs(const i8* s, FILE* stream);
    export fn i32 puts(const i8* s);
    export fn i32 putchar(i32 c);
    export fn i32 fputc(i32 c, FILE* stream);

    export fn u64 fread(void* buf, u64 size, u64 nmemb, FILE* stream);
    export fn u64 fwrite(const void* buf, u64 size, u64 nmemb, FILE* stream);

    export fn i32 fgetc(FILE* stream);
    export fn i32 feof(FILE* stream);
    export fn i32 ferror(FILE* stream);

    export fn i32 fseek(FILE* stream, i64 offset, i32 whence);
    export fn i64 ftell(FILE* stream);

    export fn i32 remove(const i8* path);

    export fn f64 strtod(const i8* nptr, i8** endptr);

    fn i32  QueryPerformanceCounter(i64* count);
    fn i32  QueryPerformanceFrequency(i64* freq);
    fn u32  WaitForMultipleObjects(u32 count, void** handles, i32 wait_all, u32 milliseconds);
    fn i32  GetExitCodeProcess(void* process, u32* code);
    fn i32  CloseHandle(void* h);
    fn void GetSystemInfo(SystemInfo* info);
    fn u32  GetModuleFileNameA(void* module, i8* buf, u32 size);
}

export const i32 O_RDONLY = 0;
export const i32 O_WRONLY = 1;
export const i32 O_CREAT  = 256;
export const i32 O_TRUNC  = 512;

export const i32 SEEK_SET = 0;
export const i32 SEEK_CUR = 1;
export const i32 SEEK_END = 2;

export const i32 IONBF = 4;

const i32 P_WAIT = 0;
const i32 P_NOWAIT = 1;
const u32 INFINITE = 4294967295;
const i32 SH_DENYNO = 64;
const u64 MALLOC_ALIGN = 16;

// Text mode would translate a newline in both directions, so every byte count would differ from Linux.
export fn FILE* fopen(const i8* filename, const i8* mode) {
    i8[8] binary_mode;
    u64 length = 0;
    bool already_binary = false;
    while(length < 6 && mode[length] != 0) {
        if(mode[length] == (i8)'b') { already_binary = true; }
        binary_mode[length] = mode[length];
        length += 1;
    }
    if(!already_binary) { binary_mode[length] = (i8)'b'; length += 1; }
    binary_mode[length] = 0;
    return _fsopen(filename, (const i8*)&binary_mode[0], SH_DENYNO);
}

export fn void* malloc(u64 size) {
    return _aligned_malloc(size, MALLOC_ALIGN);
}

export fn void* aligned_alloc(u64 alignment, u64 size) {
    return _aligned_malloc(size, alignment);
}

export fn void* realloc(void* p, u64 size) {
    return _aligned_realloc(p, size, MALLOC_ALIGN);
}

export fn void free(void* p) {
    _aligned_free(p);
}

export fn i32 mkdir(const i8* path, u32 mode) {
    return _mkdir(path);
}

export fn i32 setenv(const i8* name, const i8* value, i32 overwrite) {
    return _putenv_s(name, value);
}

export fn i32 open(const i8* path, i32 flags, u32 mode) {
    return _open(path, flags, (i32)mode);
}

export fn i32 close(i32 fd) {
    return _close(fd);
}

export fn i64 read(i32 fd, void* buf, u64 count) {
    return (i64)_read(fd, buf, (u32)count);
}

export fn i32 dup(i32 fd) {
    return _dup(fd);
}

export fn i32 dup2(i32 old_fd, i32 new_fd) {
    return _dup2(old_fd, new_fd);
}

export fn i32 unlink(const i8* path) {
    return _unlink(path);
}

export fn FILE* popen(const i8* command, const i8* mode) {
    return _popen(command, mode);
}

export fn i32 pclose(FILE* stream) {
    return _pclose(stream);
}

export fn FILE* stdout_file() {
    return __acrt_iob_func(1);
}

export fn FILE* stderr_file() {
    return __acrt_iob_func(2);
}

// _spawnvp joins argv into one command line without quoting, so an argument holding a space would split in two.
fn i8* quoted_arg(i8* arg) {
    u64 len = 0;
    bool needs_quotes = false;
    while(arg[len] != 0) {
        if(arg[len] == (i8)' ') { needs_quotes = true; }
        len += 1;
    }
    u64 extra = 0;
    if(needs_quotes) { extra = 2; }
    i8* out = (i8*)malloc(len + extra + 1);
    u64 written = 0;
    if(needs_quotes) { out[written] = (i8)'"'; written += 1; }
    for(u64 i = 0; i < len; i += 1) { out[written] = arg[i]; written += 1; }
    if(needs_quotes) { out[written] = (i8)'"'; written += 1; }
    out[written] = 0;
    return out;
}

// _spawnvp with P_WAIT returns the child's exit code, so there is nothing to reap.
export fn i32 spawn_wait(i8** argv) {
    u64 count = 0;
    while(argv[count] != null) { count += 1; }
    i8** quoted = (i8**)malloc((count + 1) * sizeof(i8*));
    for(u64 i = 0; i < count; i += 1) { quoted[i] = quoted_arg(argv[i]); }
    quoted[count] = null;
    i64 code = _spawnvp(P_WAIT, (const i8*)argv[0], quoted);
    for(u64 i = 0; i < count; i += 1) { free((void*)quoted[i]); }
    free((void*)quoted);
    if(code < 0) { return -1; }
    return (i32)code;
}

// Handles are opaque: a process handle here, a pid on Linux.
export fn i64 spawn_async(i8** argv) {
    u64 count = 0;
    while(argv[count] != null) { count += 1; }
    i8** quoted = (i8**)malloc((count + 1) * sizeof(i8*));
    for(u64 i = 0; i < count; i += 1) { quoted[i] = quoted_arg(argv[i]); }
    quoted[count] = null;
    i64 handle = _spawnvp(P_NOWAIT, (const i8*)argv[0], quoted);
    for(u64 i = 0; i < count; i += 1) { free((void*)quoted[i]); }
    free((void*)quoted);
    return handle;
}

// The CRT can only wait on one child at a time, so this drops to the Win32 call that takes a set.
export fn i64 wait_any(i64* handles, u64 count, i32* status) {
    void*[64] live;
    i64[64] source;
    u32 live_count = 0;
    for(u64 i = 0; i < count && live_count < 64; i += 1) {
        if(handles[i] == 0) { continue; }
        memcpy(&live[live_count], &handles[i], sizeof(void*));
        source[live_count] = handles[i];
        live_count += 1;
    }
    if(live_count == 0) { return (i64)-1; }
    u32 signalled = WaitForMultipleObjects(live_count, &live[0], 0, INFINITE);
    if(signalled >= live_count) { return (i64)-1; }
    u32 code = 0;
    GetExitCodeProcess(live[signalled], &code);
    *status = (i32)code;
    CloseHandle(live[signalled]);
    return source[signalled];
}
export fn i64 exe_path(i8* buf, u64 size) {
    u32 written = GetModuleFileNameA(null, buf, (u32)size);
    if(written == 0) { return (i64)-1; }
    return (i64)written;
}

// Monotonic nanoseconds; meaningful only as a delta between two calls.
// The division is split so the nanosecond scaling cannot overflow on a long uptime.
export fn u64 now_ns() {
    i64 count = 0;
    i64 freq = 0;
    QueryPerformanceCounter(&count);
    QueryPerformanceFrequency(&freq);
    if(freq <= 0) { return 0; }
    u64 ticks = (u64)count;
    u64 per_second = (u64)freq;
    return (ticks / per_second) * 1000000000 + ((ticks % per_second) * 1000000000) / per_second;
}
export fn u32 cpu_count() {
    SystemInfo info;
    memset(&info, 0, sizeof(SystemInfo));
    GetSystemInfo(&info);
    if(info.number_of_processors < 1) { return 1; }
    return info.number_of_processors;
}
