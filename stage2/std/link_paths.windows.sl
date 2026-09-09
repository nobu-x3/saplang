// Nothing to probe: the clang driver already locates the MSVC and UCRT import libraries.
import mem;
import io;
import sys;

export struct LinkPaths {
    i8* driver;
    i8* dynamic_linker;
    i8* crt_start;
    i8* crt_init;
    i8* crt_fini;
    i8* lib_dir;
    i8* gcc_lib_dir;
    i8* asan_runtime;
    i8* asan_runtime_static;
    i8* asan_dynamic_list;
    i8* tsan_runtime;
    i8* tsan_dynamic_list;
    i8* unwind_runtime;
    bool found_crt;
    bool found_asan;
    bool found_tsan;
}

export fn LinkPaths resolve(mem::Allocator allocator) {
    LinkPaths paths;
    sys::memset(&paths, 0, sizeof(LinkPaths));
    paths.driver = cstr(allocator, "clang");
    paths.found_crt = true;
    paths.found_asan = true;
    paths.found_tsan = true;
    return paths;
}

export fn bool apply_override(LinkPaths* paths, mem::Allocator allocator, const u8[] config_path) {
    io::File config_file = io::open(config_path, "r");
    if(config_file.fp == null) { return false; }
    u8[] text = io::read_all(&config_file, allocator);
    io::close(&config_file);
    u64 line_start = 0;
    for(u64 char_index = 0; char_index <= text.len; char_index += 1) {
        if(char_index != text.len && text[char_index] != '\n') { continue; }
        u8[] line = {&text.ptr[line_start], char_index - line_start};
        line_start = char_index + 1;
        if(line.len > 0 && line[line.len - 1] == '\r') { line.len -= 1; }
        if(line.len == 0 || line[0] == '#') { continue; }
        u64 separator = line.len;
        for(u64 key_index = 0; key_index < line.len; key_index += 1) {
            if(line[key_index] == '=') { separator = key_index; break; }
        }
        if(separator == line.len) { continue; }
        u8[] key = {line.ptr, separator};
        u8[] value = {&line.ptr[separator + 1], line.len - separator - 1};
        assign_entry(paths, allocator, key, value);
    }
    return true;
}

fn void assign_entry(LinkPaths* paths, mem::Allocator allocator, u8[] key, u8[] value) {
    if(slice_eq(key, "driver"))              { paths.driver = cstr(allocator, value); return; }
    if(slice_eq(key, "dynamic_linker"))      { paths.dynamic_linker = cstr(allocator, value); paths.found_crt = true; return; }
    if(slice_eq(key, "crt_start"))           { paths.crt_start = cstr(allocator, value); return; }
    if(slice_eq(key, "crt_init"))            { paths.crt_init = cstr(allocator, value); return; }
    if(slice_eq(key, "crt_fini"))            { paths.crt_fini = cstr(allocator, value); return; }
    if(slice_eq(key, "lib_dir"))             { paths.lib_dir = cstr(allocator, join(allocator, "-L", value)); return; }
    if(slice_eq(key, "gcc_lib_dir"))         { paths.gcc_lib_dir = cstr(allocator, join(allocator, "-L", value)); return; }
    if(slice_eq(key, "asan_runtime"))        { paths.asan_runtime = cstr(allocator, value); paths.found_asan = true; return; }
    if(slice_eq(key, "asan_runtime_static")) { paths.asan_runtime_static = cstr(allocator, value); return; }
    if(slice_eq(key, "asan_dynamic_list"))   { paths.asan_dynamic_list = cstr(allocator, join(allocator, "--dynamic-list=", value)); return; }
    if(slice_eq(key, "tsan_runtime"))        { paths.tsan_runtime = cstr(allocator, value); paths.found_tsan = true; return; }
    if(slice_eq(key, "tsan_dynamic_list"))   { paths.tsan_dynamic_list = cstr(allocator, join(allocator, "--dynamic-list=", value)); return; }
    if(slice_eq(key, "unwind_runtime"))      { paths.unwind_runtime = cstr(allocator, value); return; }
}

fn u8[] join(mem::Allocator allocator, const u8[] prefix, const u8[] suffix) {
    io::OutBuf buf;
    io::outbuf_init(&buf, allocator, prefix.len + suffix.len + 1);
    io::outbuf_write(&buf, prefix);
    io::outbuf_write(&buf, suffix);
    return io::outbuf_bytes(&buf);
}

export fn const u8[] host_os() { return "windows"; }

// _spawnvp appends .exe when the name carries no extension, so an extensionless binary is unrunnable.
export fn i8* output_name(mem::Allocator allocator, const u8[] output_path) {
    if(output_path.len == 0) { return cstr(allocator, "a.exe"); }
    u64 index = output_path.len;
    while(index > 0) {
        index -= 1;
        if(output_path[index] == '.') { return cstr(allocator, output_path); }
        if(io::is_path_separator(output_path[index])) { break; }
    }
    io::OutBuf buf;
    io::outbuf_init(&buf, allocator, output_path.len + 5);
    io::outbuf_write(&buf, output_path);
    io::outbuf_write(&buf, ".exe");
    return cstr(allocator, io::outbuf_bytes(&buf));
}

export fn i8*[] driver_argv(mem::Allocator allocator, LinkPaths* paths, i8* output) {
    i8** argv = (i8**)mem::alloc_bytes(allocator, 6 * sizeof(i8*));
    u64 n = 0;
    argv[n] = paths.driver; n += 1;
    argv[n] = cstr(allocator, "-fuse-ld=lld"); n += 1;
    // Windows reserves 1MB per thread, too little for the compiler's recursive descent; match Linux's 8MB.
    argv[n] = cstr(allocator, "-Wl,/STACK:8388608"); n += 1;
    // A PE header carries a link timestamp, so without this the same objects link to different bytes.
    argv[n] = cstr(allocator, "-Wl,/Brepro"); n += 1;
    argv[n] = cstr(allocator, "-o"); n += 1;
    argv[n] = output; n += 1;
    i8*[] out = {argv, n};
    return out;
}

// The clang driver pulls in the sanitizer runtimes itself, so there is nothing to name here.
export fn i8*[] runtime_argv(mem::Allocator allocator, LinkPaths* paths, bool asan, bool tsan) {
    i8** argv = (i8**)mem::alloc_bytes(allocator, 2 * sizeof(i8*));
    u64 n = 0;
    if(asan) { argv[n] = cstr(allocator, "-fsanitize=address"); n += 1; }
    if(tsan) { argv[n] = cstr(allocator, "-fsanitize=thread"); n += 1; }
    i8*[] out = {argv, n};
    return out;
}

fn i8* cstr(mem::Allocator allocator, const u8[] bytes) {
    i8* out = (i8*)mem::alloc_bytes(allocator, bytes.len + 1);
    for(u64 char_index = 0; char_index < bytes.len; char_index += 1) { out[char_index] = (i8)bytes[char_index]; }
    out[bytes.len] = 0;
    return out;
}

fn bool slice_eq(const u8[] left, const u8[] right) {
    if(left.len != right.len) { return false; }
    for(u64 char_index = 0; char_index < left.len; char_index += 1) {
        if(left[char_index] != right[char_index]) { return false; }
    }
    return true;
}
