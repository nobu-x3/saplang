// Probed at run time: crt paths differ per distribution and the clang runtime dir carries its major version.
import arena;
import io;
import sys;

export struct LinkPaths {
    i8* dynamic_linker;
    i8* crt_start;
    i8* crt_init;
    i8* crt_fini;
    i8* lib_dir;
    i8* asan_runtime;
    i8* asan_runtime_static;
    i8* asan_dynamic_list;
    i8* unwind_runtime;
    bool found_crt;
    bool found_asan;
}

export fn LinkPaths resolve(arena::Arena* arena_ptr) {
    LinkPaths paths;
    sys::memset(&paths, 0, sizeof(LinkPaths));

    u8[] linker = find_dynamic_linker();
    u8[] crt_dir = find_crt_dir(arena_ptr);
    paths.found_crt = linker.len > 0 && crt_dir.len > 0;
    if(linker.len > 0) { paths.dynamic_linker = cstr(arena_ptr, linker); }
    if(crt_dir.len > 0) {
        paths.crt_start = cstr(arena_ptr, join(arena_ptr, crt_dir, "/Scrt1.o"));
        paths.crt_init  = cstr(arena_ptr, join(arena_ptr, crt_dir, "/crti.o"));
        paths.crt_fini  = cstr(arena_ptr, join(arena_ptr, crt_dir, "/crtn.o"));
        paths.lib_dir   = cstr(arena_ptr, join(arena_ptr, "-L", crt_dir));
    }

    u8[] clang_dir = find_clang_runtime_dir(arena_ptr);
    u8[] unwind = find_unwind_runtime();
    paths.found_asan = clang_dir.len > 0 && unwind.len > 0;
    if(clang_dir.len > 0) {
        paths.asan_runtime        = cstr(arena_ptr, join(arena_ptr, clang_dir, "libclang_rt.asan-x86_64.a"));
        paths.asan_runtime_static = cstr(arena_ptr, join(arena_ptr, clang_dir, "libclang_rt.asan_static-x86_64.a"));
        paths.asan_dynamic_list   = cstr(arena_ptr, join(arena_ptr, "--dynamic-list=", join(arena_ptr, clang_dir, "libclang_rt.asan-x86_64.a.syms")));
    }
    if(unwind.len > 0) { paths.unwind_runtime = cstr(arena_ptr, unwind); }
    return paths;
}

// An unknown key is ignored so a config file can outlive a field.
export fn bool apply_override(LinkPaths* paths, arena::Arena* arena_ptr, u8[] config_path) {
    io::File config_file = io::open(config_path, "r");
    if(config_file.fp == null) { return false; }
    u8[] text = io::read_all(&config_file, arena_ptr);
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
        assign_entry(paths, arena_ptr, key, value);
    }
    return true;
}

fn void assign_entry(LinkPaths* paths, arena::Arena* arena_ptr, u8[] key, u8[] value) {
    if(slice_eq(key, "dynamic_linker"))      { paths.dynamic_linker = cstr(arena_ptr, value); paths.found_crt = true; return; }
    if(slice_eq(key, "crt_start"))           { paths.crt_start = cstr(arena_ptr, value); return; }
    if(slice_eq(key, "crt_init"))            { paths.crt_init = cstr(arena_ptr, value); return; }
    if(slice_eq(key, "crt_fini"))            { paths.crt_fini = cstr(arena_ptr, value); return; }
    if(slice_eq(key, "lib_dir"))             { paths.lib_dir = cstr(arena_ptr, join(arena_ptr, "-L", value)); return; }
    if(slice_eq(key, "asan_runtime"))        { paths.asan_runtime = cstr(arena_ptr, value); paths.found_asan = true; return; }
    if(slice_eq(key, "asan_runtime_static")) { paths.asan_runtime_static = cstr(arena_ptr, value); return; }
    if(slice_eq(key, "asan_dynamic_list"))   { paths.asan_dynamic_list = cstr(arena_ptr, join(arena_ptr, "--dynamic-list=", value)); return; }
    if(slice_eq(key, "unwind_runtime"))      { paths.unwind_runtime = cstr(arena_ptr, value); return; }
}

// Scrt1.o, crti.o and crtn.o ship together, so one probe locates all three.
fn u8[] find_crt_dir(arena::Arena* arena_ptr) {
    u8[][4] candidates;
    candidates[0] = "/usr/lib";
    candidates[1] = "/usr/lib/x86_64-linux-gnu";
    candidates[2] = "/usr/lib64";
    candidates[3] = "/lib/x86_64-linux-gnu";
    for(u64 candidate_index = 0; candidate_index < 4; candidate_index += 1) {
        if(file_exists(join(arena_ptr, candidates[candidate_index], "/Scrt1.o"))) { return candidates[candidate_index]; }
    }
    u8[] none = {null, 0};
    return none;
}

fn u8[] find_dynamic_linker() {
    u8[][3] candidates;
    candidates[0] = "/lib64/ld-linux-x86-64.so.2";
    candidates[1] = "/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2";
    candidates[2] = "/usr/lib/ld-linux-x86-64.so.2";
    for(u64 candidate_index = 0; candidate_index < 3; candidate_index += 1) {
        if(file_exists(candidates[candidate_index])) { return candidates[candidate_index]; }
    }
    u8[] none = {null, 0};
    return none;
}

fn u8[] find_unwind_runtime() {
    u8[][4] candidates;
    candidates[0] = "/usr/lib/libgcc_s.so.1";
    candidates[1] = "/usr/lib/x86_64-linux-gnu/libgcc_s.so.1";
    candidates[2] = "/lib/x86_64-linux-gnu/libgcc_s.so.1";
    candidates[3] = "/usr/lib64/libgcc_s.so.1";
    for(u64 candidate_index = 0; candidate_index < 4; candidate_index += 1) {
        if(file_exists(candidates[candidate_index])) { return candidates[candidate_index]; }
    }
    u8[] none = {null, 0};
    return none;
}

// Newest major version wins; the installed clang's version is not knowable up front, and Debian
// nests the runtime under /usr/lib/llvm-<major>/ while Arch keeps it in /usr/lib/clang/<major>/.
fn u8[] find_clang_runtime_dir(arena::Arena* arena_ptr) {
    u64 major_version = 40;
    while(major_version >= 14) {
        u8[] arch_dir = clang_dir_arch(arena_ptr, "/usr/lib/clang/", major_version);
        if(file_exists(join(arena_ptr, arch_dir, "libclang_rt.asan-x86_64.a"))) { return arch_dir; }
        u8[] lib64_dir = clang_dir_arch(arena_ptr, "/usr/lib64/clang/", major_version);
        if(file_exists(join(arena_ptr, lib64_dir, "libclang_rt.asan-x86_64.a"))) { return lib64_dir; }
        u8[] debian_dir = clang_dir_debian(arena_ptr, major_version);
        if(file_exists(join(arena_ptr, debian_dir, "libclang_rt.asan-x86_64.a"))) { return debian_dir; }
        major_version -= 1;
    }
    u8[] none = {null, 0};
    return none;
}

fn u8[] clang_dir_arch(arena::Arena* arena_ptr, u8[] root, u64 major_version) {
    io::OutBuf buf;
    io::outbuf_init(&buf, arena_ptr, 64);
    io::outbuf_write(&buf, root);
    io::outbuf_write_u64(&buf, major_version);
    io::outbuf_write(&buf, "/lib/linux/");
    return io::outbuf_bytes(&buf);
}

fn u8[] clang_dir_debian(arena::Arena* arena_ptr, u64 major_version) {
    io::OutBuf buf;
    io::outbuf_init(&buf, arena_ptr, 80);
    io::outbuf_write(&buf, "/usr/lib/llvm-");
    io::outbuf_write_u64(&buf, major_version);
    io::outbuf_write(&buf, "/lib/clang/");
    io::outbuf_write_u64(&buf, major_version);
    io::outbuf_write(&buf, "/lib/linux/");
    return io::outbuf_bytes(&buf);
}

fn bool file_exists(u8[] path) {
    io::File probe = io::open(path, "r");
    if(probe.fp == null) { return false; }
    io::close(&probe);
    return true;
}

fn u8[] join(arena::Arena* arena_ptr, u8[] prefix, u8[] suffix) {
    io::OutBuf buf;
    io::outbuf_init(&buf, arena_ptr, prefix.len + suffix.len + 1);
    io::outbuf_write(&buf, prefix);
    io::outbuf_write(&buf, suffix);
    return io::outbuf_bytes(&buf);
}

fn i8* cstr(arena::Arena* arena_ptr, u8[] bytes) {
    i8* out = (i8*)arena::alloc(arena_ptr, bytes.len + 1);
    for(u64 char_index = 0; char_index < bytes.len; char_index += 1) { out[char_index] = (i8)bytes[char_index]; }
    out[bytes.len] = 0;
    return out;
}

fn bool slice_eq(u8[] left, u8[] right) {
    if(left.len != right.len) { return false; }
    for(u64 char_index = 0; char_index < left.len; char_index += 1) {
        if(left[char_index] != right[char_index]) { return false; }
    }
    return true;
}
