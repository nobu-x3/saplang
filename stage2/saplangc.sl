import compiler;
import arena;
import interner;
import types;
import token;
import sys;
import io;
import hash;

fn u8[] cstr_slice(u8* cstr) {
    u64 len = 0;
    while(cstr[len] != 0) { len += 1; }
    u8[] out = {cstr, len};
    return out;
}

fn i8* cstr(arena::Arena* arena_ptr, const u8[] bytes) {
    i8* out = (i8*)arena::alloc(arena_ptr, bytes.len + 1);
    for(u64 i = 0; i < bytes.len; i += 1) { out[i] = (i8)bytes[i]; }
    out[bytes.len] = 0;
    return out;
}

fn bool cstr_eq(u8* s, const u8[] lit) {
    for(u64 i = 0; i < lit.len; i += 1) {
        if(s[i] == 0 || s[i] != lit[i]) { return false; }
    }
    return s[lit.len] == 0;
}

// std/ ships beside the binary; SAPLANG_STD overrides it, and an empty result means neither exists.
fn u8[] find_std_dir(arena::Arena* arena_ptr, u8** argv) {
    i8* override_dir = sys::getenv(cstr(arena_ptr, "SAPLANG_STD"));
    if(override_dir != null) { return cstr_slice((u8*)override_dir); }
    u8[] exe_dir = find_exe_dir(arena_ptr, argv);
    if(exe_dir.len == 0) { u8[] none = {null, 0}; return none; }
    u8[] candidate = join_path(arena_ptr, exe_dir, "/std");
    if(dir_has_std(candidate, arena_ptr)) { return candidate; }
    u8[] none = {null, 0};
    return none;
}

fn u8[] find_exe_dir(arena::Arena* arena_ptr, u8** argv) {
    u8* path_buf = (u8*)arena::alloc(arena_ptr, 4096);
    i64 written = sys::readlink(cstr(arena_ptr, "/proc/self/exe"), (i8*)path_buf, 4095);
    u8[] exe_path = {null, 0};
    if(written > 0) {
        exe_path = {path_buf, (u64)written};
    } else if(argv != null && argv[0] != null) {
        exe_path = cstr_slice(argv[0]);
    }
    u64 last_slash = exe_path.len;
    for(u64 char_index = 0; char_index < exe_path.len; char_index += 1) {
        if(exe_path[char_index] == '/') { last_slash = char_index; }
    }
    if(last_slash == exe_path.len) { u8[] none = {null, 0}; return none; }
    u8[] dir = {exe_path.ptr, last_slash};
    return dir;
}

fn bool dir_has_std(u8[] dir, arena::Arena* arena_ptr) {
    io::File probe = io::open(join_path(arena_ptr, dir, "/sys.sl"), "r");
    if(probe.fp == null) { return false; }
    io::close(&probe);
    return true;
}

fn u8[] join_path(arena::Arena* arena_ptr, const u8[] prefix, const u8[] suffix) {
    io::OutBuf buf;
    io::outbuf_init(&buf, arena_ptr, prefix.len + suffix.len + 1);
    io::outbuf_write(&buf, prefix);
    io::outbuf_write(&buf, suffix);
    return io::outbuf_bytes(&buf);
}

fn i32 main(i32 argc, u8** argv) {
    if(argc < 2) {
        compiler::print_usage();
        return 0;
    }
    arena::Arena symbol_arena;
    arena::Arena type_arena;
    arena::Arena arena;
    sys::memset(&symbol_arena, 0, sizeof(arena::Arena));
    sys::memset(&type_arena, 0, sizeof(arena::Arena));
    sys::memset(&arena, 0, sizeof(arena::Arena));
    symbol_arena.default_page_size = 1048576;
    type_arena.default_page_size = 1048576;
    arena.default_page_size = 1048576;
    interner::init(&symbol_arena, 1024);
    types::typer_init(&type_arena, 1024);
    token::load_keywords();

    if(argc >= 2 && cstr_eq(argv[1], "build")) {
        return run_build(&arena, argc, argv);
    }

    compiler::Compiler* c = compiler::new(&arena);

    const u8[][] args = {null, 0};
    if(argc > 1) {
        args.len = (u64)(argc - 1);
        args.ptr = arena::alloc(&arena, args.len * sizeof(const u8[]));
        for(i32 arg_index = 1; arg_index < argc; arg_index += 1) {
            args[arg_index - 1] = cstr_slice(argv[arg_index]);
        }
    }
    if(!compiler::parse_argv(c, args)) { return 1; }
    u8[] std_dir = find_std_dir(&arena, argv);
    if(std_dir.len > 0) { compiler::add_import_path(c, std_dir); }
    return compiler::run(c);
}

// `saplangc build [step] [-Dopt=val]`: compile builder + ./build.sl into a runner, then exec it.
fn i32 run_build(arena::Arena* arena_ptr, i32 argc, u8** argv) {
    io::File bf = io::open("build.sl", "r");
    if(bf.fp == null) {
        sys::dprintf(2, "error: no build.sl in the current directory\n");
        return 1;
    }
    io::close(&bf);

    const u8[] cache_dir = compiler::CACHE_DIR;
    io::ensure_directory_exists(cache_dir, 493);
    const u8[] runner_path = join_path(arena_ptr, cache_dir, "/__build_runner.sl");
    if(!write_runner(runner_path)) {
        sys::dprintf(2, "error: could not write build runner\n");
        return 1;
    }

    // The runner recompile is skipped when build.sl and everything it pulls in are unchanged.
    if(!runner_fresh(arena_ptr, cache_dir)) {
        compiler::Compiler* c = compiler::new(arena_ptr);
        compiler::add_source(c, runner_path);
        compiler::add_import_path(c, ".");
        add_passthrough_import_paths(c, argc, argv);
        u8[] std_dir = find_std_dir(arena_ptr, argv);
        if(std_dir.len > 0) { compiler::add_import_path(c, std_dir); }
        c.deps_path = join_path(arena_ptr, cache_dir, "/build.dep");
        c.output_path = join_path(arena_ptr, cache_dir, "/build");
        if(compiler::run(c) != 0) {
            sys::dprintf(2, "error: could not compile build.sl (is `builder` reachable? std/ must sit beside saplangc, or set SAPLANG_STD)\n");
            return 1;
        }
        write_runner_stamp(arena_ptr, cache_dir);
    }

    sys::setenv(cstr(arena_ptr, "SAPLANGC"), (const i8*)argv[0], 1);
    // Drop the driver-only `-i` pairs; the runner has build.sl baked in and wants only steps / -D.
    i8** rargv = (i8**)arena::alloc(arena_ptr, (u64)argc * sizeof(i8*));
    u64 forwarded = 0;
    rargv[forwarded] = cstr(arena_ptr, join_path(arena_ptr, cache_dir, "/build")); forwarded += 1;
    for(i32 arg_index = 2; arg_index < argc; arg_index += 1) {
        if(cstr_eq(argv[arg_index], "-i")) { arg_index += 1; continue; }
        rargv[forwarded] = (i8*)argv[arg_index]; forwarded += 1;
    }
    rargv[forwarded] = null;
    sys::execvp(rargv[0], rargv);
    sys::dprintf(2, "error: could not exec build runner\n");
    return 127;
}

fn bool write_runner(const u8[] path) {
    io::File f = io::open(path, "w");
    if(f.fp == null) { return false; }
    io::write_string(&f, "import builder;\n");
    io::write_string(&f, "import build;\n\n");
    io::write_string(&f, "fn i32 main(i32 argc, u8** argv) {\n");
    io::write_string(&f, "    return builder::run(argc, argv, &build::build);\n");
    io::write_string(&f, "}\n");
    io::close(&f);
    return true;
}

fn bool file_exists(const u8[] path) {
    io::File f = io::open(path, "r");
    if(f.fp == null) { return false; }
    io::close(&f);
    return true;
}

// Content hash over every source the last runner compile read; empty when anything is missing.
fn u8[] runner_stamp(arena::Arena* arena_ptr, const u8[] cache_dir) {
    io::File df = io::open(join_path(arena_ptr, cache_dir, "/build.dep"), "r");
    if(df.fp == null) { u8[] e = {null, 0}; return e; }
    u8[] listing = io::read_all(&df, arena_ptr);
    io::close(&df);

    io::OutBuf buf;
    io::outbuf_init(&buf, arena_ptr, 4096);
    u64 start = 0;
    for(u64 char_index = 0; char_index <= listing.len; char_index += 1) {
        if(char_index == listing.len || listing[char_index] == '\n') {
            if(char_index > start) {
                u8[] path = {&listing.ptr[start], char_index - start};
                io::File sf = io::open(path, "r");
                if(sf.fp == null) { u8[] e = {null, 0}; return e; }
                io::outbuf_write(&buf, io::read_all(&sf, arena_ptr));
                io::close(&sf);
            }
            start = char_index + 1;
        }
    }
    io::OutBuf hb;
    io::outbuf_init(&hb, arena_ptr, 24);
    io::outbuf_write_u64(&hb, hash::fnv1a_64(io::outbuf_bytes(&buf)));
    return io::outbuf_bytes(&hb);
}

fn bool runner_fresh(arena::Arena* arena_ptr, const u8[] cache_dir) {
    if(!file_exists(join_path(arena_ptr, cache_dir, "/build"))) { return false; }
    io::File sf = io::open(join_path(arena_ptr, cache_dir, "/build.stamp"), "r");
    if(sf.fp == null) { return false; }
    u8[] stored = io::read_all(&sf, arena_ptr);
    io::close(&sf);
    u8[] current = runner_stamp(arena_ptr, cache_dir);
    if(current.len == 0) { return false; }
    return slice_eq(stored, current);
}

fn void write_runner_stamp(arena::Arena* arena_ptr, const u8[] cache_dir) {
    u8[] current = runner_stamp(arena_ptr, cache_dir);
    if(current.len == 0) { return; }
    io::File f = io::open(join_path(arena_ptr, cache_dir, "/build.stamp"), "w");
    if(f.fp == null) { return; }
    io::write_string(&f, current);
    io::close(&f);
}

fn bool slice_eq(const u8[] x, const u8[] y) {
    if(x.len != y.len) { return false; }
    for(u64 char_index = 0; char_index < x.len; char_index += 1) {
        if(x[char_index] != y[char_index]) { return false; }
    }
    return true;
}

fn void add_passthrough_import_paths(compiler::Compiler* c, i32 argc, u8** argv) {
    for(i32 arg_index = 2; arg_index < argc; arg_index += 1) {
        if(cstr_eq(argv[arg_index], "-i") && arg_index + 1 < argc) {
            u8[] list = cstr_slice(argv[arg_index + 1]);
            u64 start = 0;
            for(u64 char_index = 0; char_index <= list.len; char_index += 1) {
                if(char_index == list.len || list[char_index] == ';') {
                    if(char_index > start) {
                        u8[] part = {&list.ptr[start], char_index - start};
                        compiler::add_import_path(c, part);
                    }
                    start = char_index + 1;
                }
            }
        }
    }
}
