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

fn i8* cstr(arena::Arena* a, u8[] bytes) {
    i8* out = (i8*)arena::alloc(a, bytes.len + 1);
    for(u64 i = 0; i < bytes.len; i += 1) { out[i] = (i8)bytes[i]; }
    out[bytes.len] = 0;
    return out;
}

fn bool cstr_eq(u8* s, u8[] lit) {
    for(u64 i = 0; i < lit.len; i += 1) {
        if(s[i] == 0 || s[i] != lit[i]) { return false; }
    }
    return s[lit.len] == 0;
}

fn i32 main(i32 argc, u8** argv) {
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

    u8[][] args = {null, 0};
    if(argc > 1) {
        args.len = (u64)(argc - 1);
        args.ptr = arena::alloc(&arena, args.len * sizeof(u8[]));
        for(i32 arg_index = 1; arg_index < argc; arg_index += 1) {
            args[arg_index - 1] = cstr_slice(argv[arg_index]);
        }
    }
    if(!compiler::parse_argv(c, args)) { return 1; }
    return compiler::run(c);
}

// `saplangc build [step] [-Dopt=val]`: compile builder + ./build.sl into a runner, then exec it.
fn i32 run_build(arena::Arena* a, i32 argc, u8** argv) {
    io::File bf = io::open("build.sl", "r");
    if(bf.fp == null) {
        sys::dprintf(2, "error: no build.sl in the current directory\n");
        return 1;
    }
    io::close(&bf);

    sys::mkdir(cstr(a, ".sap-cache"), 493);
    u8[] runner_path = ".sap-cache/__build_runner.sl";
    if(!write_runner(runner_path)) {
        sys::dprintf(2, "error: could not write build runner\n");
        return 1;
    }

    // The runner recompile is skipped when build.sl and everything it pulls in are unchanged.
    if(!runner_fresh(a)) {
        compiler::Compiler* c = compiler::new(a);
        compiler::add_source(c, runner_path);
        compiler::add_import_path(c, ".");
        i8* std_env = sys::getenv(cstr(a, "SAPLANG_STD"));
        if(std_env != null) { compiler::add_import_path(c, cstr_slice((u8*)std_env)); }
        add_passthrough_import_paths(c, argc, argv);
        c.deps_path = ".sap-cache/build.dep";
        c.output_path = ".sap-cache/build";
        if(compiler::run(c) != 0) {
            sys::dprintf(2, "error: could not compile build.sl (is `builder` on the include path? set SAPLANG_STD or pass -i)\n");
            return 1;
        }
        write_runner_stamp(a);
    }

    sys::setenv(cstr(a, "SAPLANGC"), argv[0], 1);
    // Forward the build args to the runner, minus the driver-only `-i <path>` pairs (those
    // located `builder`; the runner already has build.sl baked in and only wants steps / -D).
    i8** rargv = (i8**)arena::alloc(a, (u64)argc * sizeof(i8*));
    u64 forwarded = 0;
    rargv[forwarded] = cstr(a, ".sap-cache/build"); forwarded += 1;
    for(i32 arg_index = 2; arg_index < argc; arg_index += 1) {
        if(cstr_eq(argv[arg_index], "-i")) { arg_index += 1; continue; }
        rargv[forwarded] = (i8*)argv[arg_index]; forwarded += 1;
    }
    rargv[forwarded] = null;
    sys::execvp(rargv[0], rargv);
    sys::dprintf(2, "error: could not exec build runner\n");
    return 127;
}

fn bool write_runner(u8[] path) {
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

fn bool file_exists(u8[] path) {
    io::File f = io::open(path, "r");
    if(f.fp == null) { return false; }
    io::close(&f);
    return true;
}

// A content hash over every source the last runner compile read (the `-deps` depfile); empty if
// the depfile is missing or a listed source vanished.
fn u8[] runner_stamp(arena::Arena* a) {
    io::File df = io::open(".sap-cache/build.dep", "r");
    if(df.fp == null) { u8[] e = {null, 0}; return e; }
    u8[] listing = io::read_all(&df, a);
    io::close(&df);

    io::OutBuf buf;
    io::outbuf_init(&buf, a, 4096);
    u64 start = 0;
    for(u64 char_index = 0; char_index <= listing.len; char_index += 1) {
        if(char_index == listing.len || listing[char_index] == '\n') {
            if(char_index > start) {
                u8[] path = {&listing.ptr[start], char_index - start};
                io::File sf = io::open(path, "r");
                if(sf.fp == null) { u8[] e = {null, 0}; return e; }
                io::outbuf_write(&buf, io::read_all(&sf, a));
                io::close(&sf);
            }
            start = char_index + 1;
        }
    }
    io::OutBuf hb;
    io::outbuf_init(&hb, a, 24);
    io::outbuf_write_u64(&hb, hash::fnv1a_64(io::outbuf_bytes(&buf)));
    return io::outbuf_bytes(&hb);
}

fn bool runner_fresh(arena::Arena* a) {
    if(!file_exists(".sap-cache/build")) { return false; }
    io::File sf = io::open(".sap-cache/build.stamp", "r");
    if(sf.fp == null) { return false; }
    u8[] stored = io::read_all(&sf, a);
    io::close(&sf);
    u8[] current = runner_stamp(a);
    if(current.len == 0) { return false; }
    return slice_eq(stored, current);
}

fn void write_runner_stamp(arena::Arena* a) {
    u8[] current = runner_stamp(a);
    if(current.len == 0) { return; }
    io::File f = io::open(".sap-cache/build.stamp", "w");
    if(f.fp == null) { return; }
    io::write_string(&f, current);
    io::close(&f);
}

fn bool slice_eq(u8[] x, u8[] y) {
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
