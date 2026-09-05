// Probed at run time: crt paths differ per distribution and the clang runtime dir carries its major version.
import mem;
import io;
import sys;

export struct LinkPaths {
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

    const u8[] linker = find_dynamic_linker();
    const u8[] crt_dir = find_crt_dir(allocator);
    paths.found_crt = linker.len > 0 && crt_dir.len > 0;
    if(linker.len > 0) { paths.dynamic_linker = cstr(allocator, linker); }
    if(crt_dir.len > 0) {
        paths.crt_start = cstr(allocator, join(allocator, crt_dir, "/Scrt1.o"));
        paths.crt_init  = cstr(allocator, join(allocator, crt_dir, "/crti.o"));
        paths.crt_fini  = cstr(allocator, join(allocator, crt_dir, "/crtn.o"));
        paths.lib_dir   = cstr(allocator, join(allocator, "-L", crt_dir));
    }

    const u8[] gcc_dir = find_gcc_lib_dir(allocator, crt_dir);
    if(gcc_dir.len > 0) { paths.gcc_lib_dir = cstr(allocator, join(allocator, "-L", gcc_dir)); }

    const u8[] clang_dir = find_clang_runtime_dir(allocator);
    const u8[] unwind = find_unwind_runtime();
    paths.found_asan = clang_dir.len > 0 && unwind.len > 0;
    if(clang_dir.len > 0) {
        paths.asan_runtime        = cstr(allocator, join(allocator, clang_dir, "libclang_rt.asan-x86_64.a"));
        paths.asan_runtime_static = cstr(allocator, join(allocator, clang_dir, "libclang_rt.asan_static-x86_64.a"));
        paths.asan_dynamic_list   = cstr(allocator, join(allocator, "--dynamic-list=", join(allocator, clang_dir, "libclang_rt.asan-x86_64.a.syms")));
    }
    paths.found_tsan = clang_dir.len > 0 && unwind.len > 0;
    if(clang_dir.len > 0) {
        paths.tsan_runtime      = cstr(allocator, join(allocator, clang_dir, "libclang_rt.tsan-x86_64.a"));
        paths.tsan_dynamic_list = cstr(allocator, join(allocator, "--dynamic-list=", join(allocator, clang_dir, "libclang_rt.tsan-x86_64.a.syms")));
    }
    if(unwind.len > 0) { paths.unwind_runtime = cstr(allocator, unwind); }
    return paths;
}

// An unknown key is ignored so a config file can outlive a field.
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

// Scrt1.o, crti.o and crtn.o ship together, so one probe locates all three.
fn const u8[] find_crt_dir(mem::Allocator allocator) {
    const u8[][4] candidates = ["/usr/lib", "/usr/lib/x86_64-linux-gnu", "/usr/lib64", "/lib/x86_64-linux-gnu"];
    for(u64 candidate_index = 0; candidate_index < 4; candidate_index += 1) {
        if(file_exists(join(allocator, candidates[candidate_index], "/Scrt1.o"))) { return candidates[candidate_index]; }
    }
    u8[] none = {null, 0};
    return none;
}

fn const u8[] find_gcc_lib_dir(mem::Allocator allocator, const u8[] crt_dir) {
    u8[] none = {null, 0};
    if(crt_dir.len > 0 && file_exists(join(allocator, crt_dir, "/libstdc++.so"))) { return none; }
    const u8[] answer = clang_file_dir(allocator, "libstdc++.so");
    if(answer.len > 0) { return answer; }
    return probe_gcc_lib_dir(allocator);
}

fn const u8[] clang_file_dir(mem::Allocator allocator, const u8[] library) {
    u8[] none = {null, 0};
    i8* command = cstr(allocator, join(allocator, "clang -print-file-name=", library));
    sys::FILE* pipe = sys::popen((const i8*)command, "r");
    if(pipe == null) { return none; }
    u8[1024] answer;
    u64 length = sys::fread(&answer[0], 1, 1024, pipe);
    sys::pclose(pipe);

    while(length > 0 && (answer[length - 1] == '\n' || answer[length - 1] == '\r')) { length -= 1; }
    u64 separator = length;
    for(u64 char_index = 0; char_index < length; char_index += 1) {
        if(answer[char_index] == '/') { separator = char_index; }
    }
    if(separator == length) { return none; }

    u8[] path = {&answer[0], separator};
    return copy_bytes(allocator, path);
}

fn const u8[] probe_gcc_lib_dir(mem::Allocator allocator) {
    const u8[][6] roots = ["/usr/lib/gcc/x86_64-linux-gnu/", "/usr/lib/gcc/x86_64-pc-linux-gnu/", "/usr/lib/gcc/x86_64-redhat-linux/",
                           "/usr/lib64/gcc/x86_64-linux-gnu/", "/usr/lib64/gcc/x86_64-pc-linux-gnu/", "/usr/lib64/gcc/x86_64-redhat-linux/"];
    u64 major_version = 30;
    while(major_version >= 8) {
        for(u64 root_index = 0; root_index < 6; root_index += 1) {
            u8[] dir = gcc_dir_versioned(allocator, roots[root_index], major_version);
            if(file_exists(join(allocator, dir, "/libstdc++.so"))) { return dir; }
        }
        major_version -= 1;
    }
    u8[] none = {null, 0};
    return none;
}

fn u8[] gcc_dir_versioned(mem::Allocator allocator, const u8[] root, u64 major_version) {
    io::OutBuf buf;
    io::outbuf_init(&buf, allocator, 64);
    io::outbuf_write(&buf, root);
    io::outbuf_write_u64(&buf, major_version);
    return io::outbuf_bytes(&buf);
}

fn u8[] copy_bytes(mem::Allocator allocator, const u8[] bytes) {
    io::OutBuf buf;
    io::outbuf_init(&buf, allocator, bytes.len + 1);
    io::outbuf_write(&buf, bytes);
    return io::outbuf_bytes(&buf);
}

fn const u8[] find_dynamic_linker() {
    const u8[][3] candidates = ["/lib64/ld-linux-x86-64.so.2", "/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2", "/usr/lib/ld-linux-x86-64.so.2"];
    for(u64 candidate_index = 0; candidate_index < 3; candidate_index += 1) {
        if(file_exists(candidates[candidate_index])) { return candidates[candidate_index]; }
    }
    u8[] none = {null, 0};
    return none;
}

fn const u8[] find_unwind_runtime() {
    const u8[][4] candidates = ["/usr/lib/libgcc_s.so.1", "/usr/lib/x86_64-linux-gnu/libgcc_s.so.1", "/lib/x86_64-linux-gnu/libgcc_s.so.1", "/usr/lib64/libgcc_s.so.1"];
    for(u64 candidate_index = 0; candidate_index < 4; candidate_index += 1) {
        if(file_exists(candidates[candidate_index])) { return candidates[candidate_index]; }
    }
    u8[] none = {null, 0};
    return none;
}

// Newest major version wins; Arch and Debian nest the runtime differently.
fn const u8[] find_clang_runtime_dir(mem::Allocator allocator) {
    u64 major_version = 40;
    while(major_version >= 14) {
        u8[] arch_dir = clang_dir_arch(allocator, "/usr/lib/clang/", major_version);
        if(file_exists(join(allocator, arch_dir, "libclang_rt.asan-x86_64.a"))) { return arch_dir; }
        u8[] lib64_dir = clang_dir_arch(allocator, "/usr/lib64/clang/", major_version);
        if(file_exists(join(allocator, lib64_dir, "libclang_rt.asan-x86_64.a"))) { return lib64_dir; }
        u8[] debian_dir = clang_dir_debian(allocator, major_version);
        if(file_exists(join(allocator, debian_dir, "libclang_rt.asan-x86_64.a"))) { return debian_dir; }
        major_version -= 1;
    }
    u8[] none = {null, 0};
    return none;
}

fn u8[] clang_dir_arch(mem::Allocator allocator, const u8[] root, u64 major_version) {
    io::OutBuf buf;
    io::outbuf_init(&buf, allocator, 64);
    io::outbuf_write(&buf, root);
    io::outbuf_write_u64(&buf, major_version);
    io::outbuf_write(&buf, "/lib/linux/");
    return io::outbuf_bytes(&buf);
}

fn u8[] clang_dir_debian(mem::Allocator allocator, u64 major_version) {
    io::OutBuf buf;
    io::outbuf_init(&buf, allocator, 80);
    io::outbuf_write(&buf, "/usr/lib/llvm-");
    io::outbuf_write_u64(&buf, major_version);
    io::outbuf_write(&buf, "/lib/clang/");
    io::outbuf_write_u64(&buf, major_version);
    io::outbuf_write(&buf, "/lib/linux/");
    return io::outbuf_bytes(&buf);
}

fn bool file_exists(const u8[] path) {
    io::File probe = io::open(path, "r");
    if(probe.fp == null) { return false; }
    io::close(&probe);
    return true;
}

fn u8[] join(mem::Allocator allocator, const u8[] prefix, const u8[] suffix) {
    io::OutBuf buf;
    io::outbuf_init(&buf, allocator, prefix.len + suffix.len + 1);
    io::outbuf_write(&buf, prefix);
    io::outbuf_write(&buf, suffix);
    return io::outbuf_bytes(&buf);
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
