import module;
import scanner;
import parser;
import sema;
import comptime_interp;
import cfg;
import cfg_print;
import lower;
import codegen;
import link_paths;
import sapir;
import sapir_print;
import ast_print;
import bench;
import diag;
import arena;
import mem;
import list;
import sys;
import io;
import interner;
import symbol;
import token;
import pool;

export struct Compiler {
    mem::Allocator       allocator;
    list::List(module::Module*) modules;  // flat, indexed by ModuleId (the array index)
    list::List(const u8[]) entry_sources; // user-supplied source file paths
    list::List(const u8[]) import_paths;  // -i search list
    const u8[]           target;          // conditional-compilation infix; empty = none
    bool                 is_multithreaded; // run phases on a thread pool sized to cpu_count
    bool                 cfg_dump;         // -cfg-dump: print each function's CFG to stdout
    bool                 sapir_dump;       // -sapir-dump: print each module's lowered sapir to stdout
    bool                 token_dump;       // -token-dump: print the scanner's tokens
    bool                 ast_dump;         // -ast-dump: print the parsed AST
    bool                 llvm_dump;        // -llvm-dump: print the generated LLVM IR
    bool                 show_timings;     // -show-timings: print per-phase wall time
    i32                  comptime_depth;      // -comptime-depth: interpreter recursion cap; 0 = default
    u64                  comptime_iterations; // -comptime-iterations: interpreter per-loop cap; 0 = default
    pool::ThreadPool*    pool;            // non-null only while multithreaded
    i64                  error_count;
    const u8[]           output_path;     // -o; empty defaults to "a.out"
    list::List(const u8[]) extern_libs;   // -l names, passed to the linker as -l<name>
    list::List(const u8[]) lib_dirs;      // -L paths, passed to the linker as -L<path>
    codegen::BuildConfig config;          // -config: optimization / instrumentation pipeline; default Debug
    const u8[]           deps_path;       // -deps: write every discovered source path here (for build-system caching)
    bool                 wants_exit;      // --help / --version handled; the driver should stop before compiling
    const u8[]           link_config;     // -link-config: file overriding the probed link paths
    bool                 compile_only;    // -c: emit one object per module and skip the link step
    list::List(module::Define) defines;   // -D<name>[=<value>]: readable from `comprun if (build::defined(...))`
}

export const u8[] VERSION = "0.2.1 (stage2, self-hosted)";

export fn void print_usage() {
    sys::dprintf(1, "Usage: saplangc <file.sl>... [options]\n");
    sys::dprintf(1, "       saplangc build [step]... [-Dkey=value]...\n\n");
    sys::dprintf(1, "Options:\n");
    sys::dprintf(1, "  -o <path>              output executable (default a.out)\n");
    sys::dprintf(1, "  -i \"<p1;p2>\"           module search paths, ;-separated\n");
    sys::dprintf(1, "  -l <name>              link library <name>\n");
    sys::dprintf(1, "  -L <dir>               add a library search directory\n");
    sys::dprintf(1, "  -target <name>         target platform for conditional compilation\n");
    sys::dprintf(1, "  -config <mode>         Debug | Release | ReleaseDebug | AddressSanitizer | ThreadSanitizer\n");
    sys::dprintf(1, "  -D<name>[=<value>]     define a flag readable from `comprun if (build::defined(...))`\n");
    sys::dprintf(1, "  -deps <path>           write every discovered source path to <path>\n");
    sys::dprintf(1, "  -link-config <file>    override probed link paths (key=value per line)\n");
    sys::dprintf(1, "  -c                     emit <module>.o per module, skip linking (-o renames the entry object)\n");
    sys::dprintf(1, "  -mt                    compile modules on a thread pool\n");
    sys::dprintf(1, "  -comptime-depth <N>    comptime recursion cap (0 = default)\n");
    sys::dprintf(1, "  -comptime-iterations <N>  comptime per-loop cap (0 = default)\n");
    sys::dprintf(1, "  -cfg-dump              print each function's CFG, then stop\n");
    sys::dprintf(1, "  -sapir-dump            print each module's sapir IR, then stop\n");
    sys::dprintf(1, "  -token-dump            print the scanner's tokens, then stop\n");
    sys::dprintf(1, "  -ast-dump              print the parsed AST, then stop\n");
    sys::dprintf(1, "  -llvm-dump             print the generated LLVM IR, then stop\n");
    sys::dprintf(1, "  -show-timings          print per-phase wall time\n");
    sys::dprintf(1, "  --help, -h             show this help\n");
    sys::dprintf(1, "  --version              show the version\n");
}

export fn Compiler* new(arena::Arena* a) {
    Compiler* c = (Compiler*)arena::alloc(a, sizeof(Compiler));
    sys::memset(c, 0, sizeof(Compiler));
    c.allocator = arena::allocator(a);
    return c;
}

export fn void add_module(Compiler* c, module::Module* m) {
    list::push(&c.modules, c.allocator, m);
}

export fn void add_source(Compiler* c, const u8[] path) {
    list::push(&c.entry_sources, c.allocator, path);
}

fn bool parse_config(Compiler* c, const u8[] name) {
    if(slice_eq(name, "Debug"))            { c.config = codegen::BuildConfig::Debug; return true; }
    if(slice_eq(name, "Release"))          { c.config = codegen::BuildConfig::Release; return true; }
    if(slice_eq(name, "ReleaseDebug"))     { c.config = codegen::BuildConfig::ReleaseDebug; return true; }
    if(slice_eq(name, "AddressSanitizer")) { c.config = codegen::BuildConfig::AddressSanitizer; return true; }
    if(slice_eq(name, "ThreadSanitizer"))  { c.config = codegen::BuildConfig::ThreadSanitizer; return true; }
    sys::dprintf(2, "unknown -config value: %.*s (expected Debug|Release|ReleaseDebug|AddressSanitizer|ThreadSanitizer)\n", (i32)name.len, (i8*)name.ptr);
    return false;
}

export fn void add_extern_lib(Compiler* c, const u8[] name) {
    list::push(&c.extern_libs, c.allocator, name);
}

export fn void add_lib_dir(Compiler* c, const u8[] path) {
    list::push(&c.lib_dirs, c.allocator, path);
}

// `-Dname` or `-Dname=value`; a bare name carries an empty value and is still "defined".
export fn void add_define(Compiler* c, const u8[] arg) {
    u8[] body = {&arg.ptr[2], arg.len - 2};
    u64 separator = body.len;
    for(u64 char_index = 0; char_index < body.len; char_index += 1) {
        if(body[char_index] == '=') {
            separator = char_index;
            break;
        }
    }
    module::Define entry;
    entry.name = {body.ptr, separator};
    entry.value = {null, 0};
    if(separator < body.len) { entry.value = {&body.ptr[separator + 1], body.len - separator - 1}; }
    list::push(&c.defines, c.allocator, entry);
}

export fn void add_import_path(Compiler* c, const u8[] path) {
    list::push(&c.import_paths, c.allocator, path);
}

export fn void set_target(Compiler* c, const u8[] t) {
    c.target = t;
}

// Only Linux links today: link_paths is Linux-only, so any other target would silently emit an ELF.
export fn bool set_validated_target(Compiler* c, const u8[] t) {
    if(slice_eq(t, "linux")) {
        c.target = t;
        return true;
    }
    sys::dprintf(2, "unsupported -target %.*s (only 'linux' is supported)\n", (i32)t.len, (i8*)t.ptr);
    return false;
}

export fn void set_multithreaded(Compiler* c, bool on) {
    c.is_multithreaded = on;
}

// Recognizes <file>.sl, -i <;-list>, -target <name>, -mt, -cfg-dump; false on anything else.
export fn bool parse_argv(Compiler* c, const u8[][] args) {
    bool ok = true;
    u64 arg_index = 0;
    while(arg_index < args.len) {
        const u8[] arg = args[arg_index];
        if(slice_eq(arg, "-i")) {
            arg_index += 1;
            if(arg_index < args.len) { add_import_path_list(c, args[arg_index]); } else { ok = false; }
        } else if(slice_eq(arg, "-target")) {
            arg_index += 1;
            if(arg_index < args.len) {
                if(!set_validated_target(c, args[arg_index])) { ok = false; }
            } else { ok = false; }
        } else if(slice_eq(arg, "-o")) {
            arg_index += 1;
            if(arg_index < args.len) { c.output_path = args[arg_index]; } else { ok = false; }
        } else if(slice_eq(arg, "-l")) {
            arg_index += 1;
            if(arg_index < args.len) { add_extern_lib(c, args[arg_index]); } else { ok = false; }
        } else if(slice_eq(arg, "-L")) {
            arg_index += 1;
            if(arg_index < args.len) { add_lib_dir(c, args[arg_index]); } else { ok = false; }
        } else if(starts_with(arg, "-D")) {
            if(arg.len > 2) { add_define(c, arg); } else { ok = false; }
        } else if(slice_eq(arg, "-config")) {
            arg_index += 1;
            if(arg_index < args.len) {
                if(!parse_config(c, args[arg_index])) { ok = false; }
            } else { ok = false; }
        } else if(slice_eq(arg, "-link-config")) {
            arg_index += 1;
            if(arg_index < args.len) { c.link_config = args[arg_index]; } else { ok = false; }
        } else if(slice_eq(arg, "-deps")) {
            arg_index += 1;
            if(arg_index < args.len) { c.deps_path = args[arg_index]; } else { ok = false; }
        } else if(slice_eq(arg, "--help") || slice_eq(arg, "-h")) {
            print_usage();
            c.wants_exit = true;
        } else if(slice_eq(arg, "--version")) {
            sys::dprintf(1, "saplangc %.*s\n", (i32)VERSION.len, (i8*)VERSION.ptr);
            c.wants_exit = true;
        } else if(slice_eq(arg, "-c")) {
            c.compile_only = true;
        } else if(slice_eq(arg, "-mt")) {
            c.is_multithreaded = true;
        } else if(slice_eq(arg, "-cfg-dump")) {
            c.cfg_dump = true;
        } else if(slice_eq(arg, "-sapir-dump")) {
            c.sapir_dump = true;
        } else if(slice_eq(arg, "-token-dump")) {
            c.token_dump = true;
        } else if(slice_eq(arg, "-ast-dump")) {
            c.ast_dump = true;
        } else if(slice_eq(arg, "-llvm-dump")) {
            c.llvm_dump = true;
        } else if(slice_eq(arg, "-show-timings")) {
            c.show_timings = true;
        } else if(slice_eq(arg, "-comptime-depth")) {
            arg_index += 1;
            if(arg_index < args.len) { c.comptime_depth = (i32)parse_u64(args[arg_index]); } else { ok = false; }
        } else if(slice_eq(arg, "-comptime-iterations")) {
            arg_index += 1;
            if(arg_index < args.len) { c.comptime_iterations = parse_u64(args[arg_index]); } else { ok = false; }
        } else if(ends_with(arg, ".sl")) {
            add_source(c, arg);
        } else {
            sys::dprintf(2, "unknown argument: %.*s\n", (i32)arg.len, (i8*)arg.ptr);
            ok = false;
        }
        arg_index += 1;
    }
    return ok;
}

fn void add_import_path_list(Compiler* c, const u8[] list) {
    u64 start = 0;
    for(u64 char_index = 0; char_index <= list.len; char_index += 1) {
        if(char_index == list.len || list[char_index] == ';') {
            if(char_index > start) {
                u8[] part = {&list.ptr[start], char_index - start};
                add_import_path(c, part);
            }
            start = char_index + 1;
        }
    }
}

fn bool slice_eq(const u8[] a, const u8[] b) {
    if(a.len != b.len) { return false; }
    for(u64 char_index = 0; char_index < a.len; char_index += 1) {
        if(a[char_index] != b[char_index]) { return false; }
    }
    return true;
}

fn u64 parse_u64(const u8[] s) {
    u64 value = 0;
    for(u64 i = 0; i < s.len; i += 1) {
        if(s[i] < '0' || s[i] > '9') { break; }
        value = value * 10 + (u64)(s[i] - '0');
    }
    return value;
}

fn bool ends_with(const u8[] s, const u8[] suffix) {
    if(suffix.len > s.len) { return false; }
    u64 offset = s.len - suffix.len;
    for(u64 char_index = 0; char_index < suffix.len; char_index += 1) {
        if(s[offset + char_index] != suffix[char_index]) { return false; }
    }
    return true;
}

// Scanner output only, no parsing; import cycles are fine.
export fn void discover(Compiler* c) {
    for(u64 entry_index = 0; entry_index < c.entry_sources.len; entry_index += 1) {
        add_entry_module(c, c.entry_sources.ptr[entry_index]);
    }
    u64 cursor = 0;
    while(cursor < c.modules.len) {
        module::Module* m = c.modules.ptr[cursor];
        scanner::scan(m);
        discover_imports(c, m);
        cursor += 1;
    }
}

// Unreadable is an error; an empty file is valid (imports get their check in resolve_import_source).
fn void add_entry_module(Compiler* c, const u8[] path) {
    u8[] empty = {null, 0};
    module::Module* m = new_source_module(c, interner::intern(path_stem(path)), path, empty);
    add_module(c, m);
    io::File f = io::open(path, "r");
    if(f.fp == null) {
        diag::report(&m.diag, m.arena, 0, "cannot read source file");
        return;
    }
    m.source = io::read_all(&f, c.allocator);
    io::close(&f);
}

fn module::Module* new_source_module(Compiler* c, symbol::Symbol* name, const u8[] path, const u8[] src) {
    module::Module* m = (module::Module*)mem::alloc(c.allocator, sizeof(module::Module));
    sys::memset(m, 0, sizeof(module::Module));
    arena::Arena* module_arena = (arena::Arena*)mem::alloc(c.allocator, sizeof(arena::Arena));
    sys::memset(module_arena, 0, sizeof(arena::Arena));
    module_arena.default_page_size = 1048576;
    module::set_arena(m, module_arena);
    m.name = name;
    m.path = path;
    m.source = src;
    m.build = build_info(c);
    return m;
}

// The parser reads this while folding `comprun if`, so it has to be set before any module is parsed.
fn module::BuildInfo build_info(Compiler* c) {
    module::BuildInfo info;
    info.os = "linux";
    if(c.target.len > 0) { info.os = c.target; }
    info.arch = "x86_64";
    info.config = config_name(c.config);
    info.defines = {c.defines.ptr, c.defines.len};
    return info;
}

fn const u8[] config_name(codegen::BuildConfig config) {
    switch(config) {
    case codegen::BuildConfig::Debug:            { return "Debug"; }
    case codegen::BuildConfig::Release:          { return "Release"; }
    case codegen::BuildConfig::ReleaseDebug:     { return "ReleaseDebug"; }
    case codegen::BuildConfig::AddressSanitizer: { return "AddressSanitizer"; }
    case codegen::BuildConfig::ThreadSanitizer:  { return "ThreadSanitizer"; }
    else                                         { return "Debug"; }
    }
}

fn bool starts_with(const u8[] text, const u8[] prefix) {
    if(prefix.len > text.len) { return false; }
    for(u64 char_index = 0; char_index < prefix.len; char_index += 1) {
        if(text[char_index] != prefix[char_index]) { return false; }
    }
    return true;
}

fn void discover_imports(Compiler* c, module::Module* m) {
    token::Token[] toks = m.tokens;
    u64 import_count = 0;
    u64 token_index = 0;
    while(token_index < toks.len) {
        if(is_import_at(toks, token_index)) { import_count += 1; token_index += 3; continue; }
        token_index += 1;
    }
    if(import_count == 0) { return; }
    module::Module** import_list = (module::Module**)mem::alloc(c.allocator, import_count * sizeof(module::Module*));
    u64 filled = 0;
    token_index = 0;
    while(token_index < toks.len) {
        if(is_import_at(toks, token_index)) {
            symbol::Symbol* import_name = toks[token_index + 1].data.sym;
            module::Module* dep = find_module(c, import_name);
            if(dep == null) {
                ResolvedSource resolved = resolve_import_source(c, import_name);
                if(!resolved.found) {
                    diag::report(&m.diag, m.arena, toks[token_index].src_pos, "module not found");
                    token_index += 3;
                    continue;
                }
                dep = new_source_module(c, import_name, resolved.path, resolved.src);
                add_module(c, dep);
            }
            import_list[filled] = dep;
            filled += 1;
            token_index += 3;
            continue;
        }
        token_index += 1;
    }
    m.imports = {import_list, filled};
}

fn bool is_import_at(token::Token[] toks, u64 token_index) {
    return token_index + 2 < toks.len && toks[token_index].kind == token::TokenKind::IMPORT && toks[token_index + 1].kind == token::TokenKind::Ident && toks[token_index + 2].kind == token::TokenKind::Semi;
}

fn module::Module* find_module(Compiler* c, symbol::Symbol* name) {
    for(u64 module_index = 0; module_index < c.modules.len; module_index += 1) {
        if(c.modules.ptr[module_index].name == name) { return c.modules.ptr[module_index]; }
    }
    return null;
}

struct ResolvedSource {
    bool  found;
    u8[]  path;
    u8[]  src;
}

// Search import paths for <name>.<target>.sl (if a target is set), then <name>.sl; read the first that opens.
// Reading at resolution time (one open per candidate) means a module is only created from source we actually read.
fn ResolvedSource resolve_import_source(Compiler* c, symbol::Symbol* name) {
    u8[] name_bytes = interner::symbol_str(name);
    u8[] empty = {null, 0};
    ResolvedSource result;
    sys::memset(&result, 0, sizeof(ResolvedSource));
    for(u64 path_index = 0; path_index < c.import_paths.len; path_index += 1) {
        bool found = false;
        if(c.target.len > 0) {
            u8[] platform = join_filename(c, c.import_paths.ptr[path_index], name_bytes, c.target);
            u8[] bytes = open_and_read(c, platform, &found);
            if(found) { result.found = true; result.path = platform; result.src = bytes; return result; }
        }
        u8[] candidate = join_filename(c, c.import_paths.ptr[path_index], name_bytes, empty);
        u8[] bytes = open_and_read(c, candidate, &found);
        if(found) { result.found = true; result.path = candidate; result.src = bytes; return result; }
    }
    return result;
}

fn u8[] join_filename(Compiler* c, const u8[] dir, const u8[] name, const u8[] target) {
    u8[1024] buf;
    i32 written = 0;
    if(target.len > 0) {
        written = sys::snprintf((i8*)&buf[0], 1024, "%.*s/%.*s.%.*s.sl", (i32)dir.len, (i8*)dir.ptr, (i32)name.len, (i8*)name.ptr, (i32)target.len, (i8*)target.ptr);
    } else {
        written = sys::snprintf((i8*)&buf[0], 1024, "%.*s/%.*s.sl", (i32)dir.len, (i8*)dir.ptr, (i32)name.len, (i8*)name.ptr);
    }
    if(written <= 0) { u8[] none = {null, 0}; return none; }
    u64 len = (u64)written;
    if(len > 1023) { len = 1023; }
    u8* out = (u8*)mem::alloc(c.allocator, len);
    sys::memcpy(out, &buf[0], len);
    u8[] result = {out, len};
    return result;
}

// *found is whether the file could be opened; the io API can't distinguish absent from unreadable, so both are "not found".
fn u8[] open_and_read(Compiler* c, u8[] path, bool* found) {
    io::File f = io::open(path, "r");
    u8[] empty = {null, 0};
    if(f.fp == null) { *found = false; return empty; }
    u8[] bytes = io::read_all(&f, c.allocator);
    io::close(&f);
    *found = true;
    return bytes;
}

// Keeps the extension, so a per-target file still reports the name it really has (mutex.linux.sl).
fn const u8[] path_basename(const u8[] path) {
    u64 start = 0;
    for(u64 char_index = 0; char_index < path.len; char_index += 1) {
        if(path[char_index] == '/') { start = char_index + 1; }
    }
    const u8[] out = {&path.ptr[start], path.len - start};
    return out;
}

fn const u8[] path_stem(const u8[] path) {
    u64 start = 0;
    for(u64 char_index = 0; char_index < path.len; char_index += 1) {
        if(path[char_index] == '/') { start = char_index + 1; }
    }
    u64 end = path.len;
    for(u64 char_index = start; char_index < path.len; char_index += 1) {
        if(path[char_index] == '.') { end = char_index; break; }
    }
    u8[] out = {&path.ptr[start], end - start};
    return out;
}

// Discover -> frontend -> codegen -> link. Returns 0 on success.
export fn i32 run(Compiler* c) {
    if(c.wants_exit) { return 0; }
    i32 rc = 1;
    discover(c);
    if(c.deps_path.len > 0) { write_depfile(c); }
    drain_diagnostics(c);
    if(!bail_on_errors(c)) {
        rc = run_frontend(c);
        if(rc == 0 && !stops_before_backend(c)) { rc = run_backend(c); }
    }
    if(rc == 0) { sys::dprintf(2, "Build success\n"); }
    else { sys::dprintf(2, "Build failed\n"); }
    return rc;
}

// One source path per line: the full transitive set discover() walked, for build-system caching.
fn void write_depfile(Compiler* c) {
    io::File f = io::open(c.deps_path, "w");
    if(f.fp == null) { return; }
    for(u64 module_index = 0; module_index < c.modules.len; module_index += 1) {
        const u8[] path = c.modules.ptr[module_index].path;
        if(path.len == 0) { continue; }
        io::write_string(&f, path);
        io::write_string(&f, "\n");
    }
    io::close(&f);
}

// sapir -> object files -> linked executable. Assumes the frontend already ran.
export fn i32 run_backend(Compiler* c) {
    if(!c.compile_only) { sys::mkdir(cstr(c.allocator, ".tmp"), 493); }
    const u8[][] object_paths = run_codegen(c);
    if(bail_on_errors(c)) { return 1; }
    if(c.compile_only) { return 0; }
    return run_link(c, object_paths);
}

// Runs a produced executable and returns its exit code (or -1 on spawn failure).
export fn i32 run_executable(mem::Allocator a, const u8[] path) {
    i8** argv = (i8**)mem::alloc(a, 2 * sizeof(i8*));
    argv[0] = cstr(a, path);
    argv[1] = null;
    return spawn_and_wait(argv);
}

fn const u8[][] run_codegen(Compiler* c) {
    const u8[][] paths;
    paths.ptr = mem::alloc(c.allocator, (c.modules.len + 1) * sizeof(const u8[]));
    paths.len = 0;
    for(u64 module_index = 0; module_index < c.modules.len; module_index += 1) {
        module::Module* m = c.modules.ptr[module_index];
        if(m.sapir == null) { continue; }
        const u8[] name = path_basename(m.path);
        sys::dprintf(2, "Compiling module %.*s...\n", (i32)name.len, (i8*)name.ptr);
        const u8[] obj_path = object_path_for(c, m);
        if(codegen::emit_object((sapir::SapirModule*)m.sapir, c.allocator, cstr(c.allocator, obj_path), c.config) != 0) { c.error_count += 1; }
        paths[paths.len] = obj_path;
        paths.len += 1;
    }
    return paths;
}

fn i32 run_link(Compiler* c, const u8[][] object_paths) {
    link_paths::LinkPaths paths = link_paths::resolve(c.allocator);
    if(c.link_config.len > 0) {
        if(!link_paths::apply_override(&paths, c.allocator, c.link_config)) {
            sys::dprintf(2, "error: cannot read link config %.*s\n", (i32)c.link_config.len, (i8*)c.link_config.ptr);
            return 1;
        }
    }
    if(!paths.found_crt) {
        sys::dprintf(2, "error: cannot locate the C runtime startup files or dynamic linker; pass -link-config\n");
        return 1;
    }
    if(c.config == codegen::BuildConfig::AddressSanitizer && !paths.found_asan) {
        sys::dprintf(2, "error: cannot locate the clang AddressSanitizer runtime; pass -link-config\n");
        return 1;
    }
    if(c.config == codegen::BuildConfig::ThreadSanitizer && !paths.found_tsan) {
        sys::dprintf(2, "error: cannot locate the clang ThreadSanitizer runtime; pass -link-config\n");
        return 1;
    }
    i8** argv = build_link_argv(c, object_paths, &paths);
    if(spawn_and_wait(argv) != 0) {
        sys::dprintf(2, "error: link step failed\n");
        return 1;
    }
    return 0;
}

fn i8** build_link_argv(Compiler* c, const u8[][] object_paths, link_paths::LinkPaths* paths) {
    u64 cap = 24 + object_paths.len + c.extern_libs.len + c.lib_dirs.len;
    i8** argv = (i8**)mem::alloc(c.allocator, (cap + 1) * sizeof(i8*));
    u64 n = 0;
    argv[n] = cstr(c.allocator, "ld.lld"); n += 1;
    argv[n] = cstr(c.allocator, "-o"); n += 1;
    argv[n] = output_cstr(c); n += 1;
    argv[n] = cstr(c.allocator, "-dynamic-linker"); n += 1;
    argv[n] = paths.dynamic_linker; n += 1;
    argv[n] = paths.crt_start; n += 1;
    argv[n] = paths.crt_init; n += 1;
    argv[n] = paths.lib_dir; n += 1;
    // User -L dirs precede the objects/libs so ld.lld searches them for the -l libraries.
    for(u64 i = 0; i < c.lib_dirs.len; i += 1) { argv[n] = dir_flag(c, c.lib_dirs.ptr[i]); n += 1; }
    for(u64 i = 0; i < object_paths.len; i += 1) { argv[n] = cstr(c.allocator, object_paths[i]); n += 1; }
    for(u64 i = 0; i < c.extern_libs.len; i += 1) { argv[n] = lib_flag(c, c.extern_libs.ptr[i]); n += 1; }
    if(c.config == codegen::BuildConfig::AddressSanitizer) {
        argv[n] = paths.asan_runtime_static; n += 1;
        argv[n] = paths.asan_runtime; n += 1;
        argv[n] = paths.asan_dynamic_list; n += 1;
        argv[n] = cstr(c.allocator, "-lpthread"); n += 1;
        argv[n] = cstr(c.allocator, "-lrt"); n += 1;
        argv[n] = cstr(c.allocator, "-ldl"); n += 1;
        argv[n] = cstr(c.allocator, "-lresolv"); n += 1;
        argv[n] = cstr(c.allocator, "-lm"); n += 1;
        argv[n] = paths.unwind_runtime; n += 1;
        argv[n] = cstr(c.allocator, "--export-dynamic"); n += 1;
    }
    if(c.config == codegen::BuildConfig::ThreadSanitizer) {
        argv[n] = paths.tsan_runtime; n += 1;
        argv[n] = paths.tsan_dynamic_list; n += 1;
        argv[n] = cstr(c.allocator, "-lpthread"); n += 1;
        argv[n] = cstr(c.allocator, "-lrt"); n += 1;
        argv[n] = cstr(c.allocator, "-ldl"); n += 1;
        argv[n] = cstr(c.allocator, "-lresolv"); n += 1;
        argv[n] = cstr(c.allocator, "-lm"); n += 1;
        argv[n] = paths.unwind_runtime; n += 1;
        argv[n] = cstr(c.allocator, "--export-dynamic"); n += 1;
    }
    argv[n] = cstr(c.allocator, "-lc"); n += 1;
    argv[n] = paths.crt_fini; n += 1;
    argv[n] = null; n += 1;
    return argv;
}

fn i32 spawn_and_wait(i8** argv) {
    i32 pid = sys::fork();
    if(pid < 0) { return -1; }
    if(pid == 0) {
        sys::execvp(argv[0], argv);
        sys::_exit(127);
        return 127;
    }
    i32 status = 0;
    sys::waitpid(pid, &status, 0);
    return (status >> 8) & 255;
}

// -c writes <module>.o beside the caller; -o renames only the entry module's object, since
// discovered imports each get one too and cannot share the name.
fn const u8[] object_path_for(Compiler* c, module::Module* m) {
    if(!c.compile_only) { return tmp_object_path(c, m); }
    if(c.output_path.len > 0 && c.modules.len > 0 && c.modules.ptr[0] == m) { return c.output_path; }
    io::OutBuf buf;
    io::outbuf_init(&buf, c.allocator, 64);
    io::outbuf_write(&buf, interner::symbol_str(m.name));
    io::outbuf_write(&buf, ".o");
    return io::outbuf_bytes(&buf);
}

fn u8[] tmp_object_path(Compiler* c, module::Module* m) {
    io::OutBuf buf;
    io::outbuf_init(&buf, c.allocator, 64);
    io::outbuf_write(&buf, ".tmp/");
    io::outbuf_write(&buf, interner::symbol_str(m.name));
    io::outbuf_write(&buf, ".o");
    return io::outbuf_bytes(&buf);
}

fn i8* output_cstr(Compiler* c) {
    if(c.output_path.len == 0) { return cstr(c.allocator, "a.out"); }
    return cstr(c.allocator, c.output_path);
}

fn i8* lib_flag(Compiler* c, const u8[] name) {
    io::OutBuf buf;
    io::outbuf_init(&buf, c.allocator, 16);
    io::outbuf_write(&buf, "-l");
    io::outbuf_write(&buf, name);
    return cstr(c.allocator, io::outbuf_bytes(&buf));
}

fn i8* dir_flag(Compiler* c, const u8[] path) {
    io::OutBuf buf;
    io::outbuf_init(&buf, c.allocator, 16);
    io::outbuf_write(&buf, "-L");
    io::outbuf_write(&buf, path);
    return cstr(c.allocator, io::outbuf_bytes(&buf));
}

fn i8* cstr(mem::Allocator a, const u8[] bytes) {
    i8* out = (i8*)mem::alloc(a, bytes.len + 1);
    for(u64 i = 0; i < bytes.len; i += 1) { out[i] = (i8)bytes[i]; }
    out[bytes.len] = 0;
    return out;
}

// Runs the frontend phases (parse -> barriered sema); 0 on success, 1 on any error.
export fn i32 run_frontend(Compiler* c) {
    comptime_interp::install_hooks();
    comptime_interp::init_mono_sync();
    sema::init_body_sync(c.allocator);
    for(u64 module_index = 0; module_index < c.modules.len; module_index += 1) {
        c.modules.ptr[module_index].comptime_max_depth = c.comptime_depth;
        c.modules.ptr[module_index].comptime_max_iterations = c.comptime_iterations;
    }
    if(c.is_multithreaded) { c.pool = pool::new(c.allocator, sys::cpu_count()); }
    u64 phase_start = bench::now_ns();
    run_parse(c);
    phase_start = report_phase(c, "parse", phase_start);
    i32 rc = 0;
    if(bail_on_errors(c)) {
        rc = 1;
        if(c.token_dump) { dump_tokens(c); }
    } else {
        if(c.token_dump) { dump_tokens(c); }
        if(c.ast_dump) { dump_asts(c); }
        run_sema(c);
        phase_start = report_phase(c, "sema", phase_start);
        if(bail_on_errors(c)) {
            rc = 1;
        } else {
            run_cfg(c);
            phase_start = report_phase(c, "cfg", phase_start);
            if(bail_on_errors(c)) { rc = 1; }
            if(c.cfg_dump) { dump_cfgs(c); }
            if(rc == 0) {
                run_lower(c);
                phase_start = report_phase(c, "lower", phase_start);
                drain_diagnostics(c);
                if(bail_on_errors(c)) { rc = 1; }
                if(c.sapir_dump) { dump_sapir(c); }
                if(c.llvm_dump && rc == 0) { dump_llvm(c); }
            }
        }
    }
    if(c.pool != null) {
        pool::destroy(c.pool);
        c.pool = null;
    }
    return rc;
}

// One job per module, joined at the barrier; runs sequentially when single-threaded.
fn void run_phase(Compiler* c, fn* void(void*) job) {
    if(c.pool != null) {
        for(u64 module_index = 0; module_index < c.modules.len; module_index += 1) {
            pool::submit(c.pool, job, (void*)c.modules.ptr[module_index]);
        }
        pool::wait_all(c.pool);
        return;
    }
    for(u64 module_index = 0; module_index < c.modules.len; module_index += 1) {
        job((void*)c.modules.ptr[module_index]);
    }
}

fn void run_parse(Compiler* c) {
    run_phase(c, &parse_job);
    drain_diagnostics(c);
}

// Barriered sub-passes: cross-module lookups always read a complete world.
fn void run_sema(Compiler* c) {
    run_phase(c, &collect_names_job);
    drain_diagnostics(c);
    if(bail_on_errors(c)) { return; }
    run_phase(c, &resolve_signatures_job);
    drain_diagnostics(c);
    if(bail_on_errors(c)) { return; }
    run_phase(c, &check_bodies_job);
    drain_diagnostics(c);
}

fn void parse_job(void* arg) {
    module::Module* m = (module::Module*)arg;
    if(m.tokens.len == 0) { scanner::scan(m); }      // discover already scans; don't re-scan
    m.root_node = parser::parse(m);
}

fn void collect_names_job(void* arg) { sema::collect_names((module::Module*)arg); }
fn void resolve_signatures_job(void* arg) { sema::resolve_signatures((module::Module*)arg); }
fn void check_bodies_job(void* arg) { sema::check_bodies((module::Module*)arg); }

// Per-module CFG construction + return-path / unreachable-code analyses.
fn void run_cfg(Compiler* c) {
    run_phase(c, &build_cfg_job);
    drain_diagnostics(c);
}

fn void build_cfg_job(void* arg) { cfg::build_all_functions((module::Module*)arg); }

// Per-module lowering of the typed AST + CFG into sapir; result stored on m.sapir.
fn void run_lower(Compiler* c) {
    run_phase(c, &lower_job);
}

fn void lower_job(void* arg) {
    module::Module* m = (module::Module*)arg;
    m.sapir = (void*)lower::lower_module(m);
}

// Returns the new mark so a caller can chain phases without repeating the now_ns() dance.
fn u64 report_phase(Compiler* c, const u8[] name, u64 started_ns) {
    u64 now = bench::now_ns();
    if(c.show_timings) {
        sys::dprintf(2, "  %-8.*s %lu ms\n", (i32)name.len, (i8*)name.ptr, (now - started_ns) / 1000000);
    }
    return now;
}

export fn bool stops_before_backend(Compiler* c) {
    return c.cfg_dump || c.sapir_dump || c.token_dump || c.ast_dump;
}

fn void dump_tokens(Compiler* c) {
    io::OutBuf out;
    io::outbuf_init(&out, c.allocator, 4096);
    for(u64 module_index = 0; module_index < c.modules.len; module_index += 1) {
        module::Module* m = c.modules.ptr[module_index];
        io::outbuf_write(&out, "module ");
        io::outbuf_write(&out, interner::symbol_str(m.name));
        io::outbuf_write_byte(&out, 10);
        for(u64 token_index = 0; token_index < m.tokens.len; token_index += 1) {
            io::outbuf_write(&out, "  ");
            io::outbuf_write_u64(&out, (u64)m.tokens[token_index].src_pos);
            io::outbuf_write(&out, " ");
            io::outbuf_write(&out, token::kind_name(m.tokens[token_index].kind));
            io::outbuf_write_byte(&out, 10);
        }
    }
    u8[] bytes = io::outbuf_bytes(&out);
    sys::dprintf(1, "%.*s", (i32)bytes.len, (i8*)bytes.ptr);
}

fn void dump_asts(Compiler* c) {
    io::OutBuf out;
    io::outbuf_init(&out, c.allocator, 4096);
    for(u64 module_index = 0; module_index < c.modules.len; module_index += 1) {
        module::Module* m = c.modules.ptr[module_index];
        if(m.root_node == null) { continue; }
        io::outbuf_write(&out, "module ");
        io::outbuf_write(&out, interner::symbol_str(m.name));
        io::outbuf_write_byte(&out, 10);
        ast_print::print(m.root_node, 1, &out);
    }
    u8[] bytes = io::outbuf_bytes(&out);
    sys::dprintf(1, "%.*s", (i32)bytes.len, (i8*)bytes.ptr);
}

fn void dump_llvm(Compiler* c) {
    for(u64 module_index = 0; module_index < c.modules.len; module_index += 1) {
        module::Module* m = c.modules.ptr[module_index];
        if(m.sapir == null) { continue; }
        const u8[] ir = codegen::codegen_ir_string((sapir::SapirModule*)m.sapir, c.allocator, c.config);
        sys::dprintf(1, "%.*s", (i32)ir.len, (i8*)ir.ptr);
    }
}

fn void dump_sapir(Compiler* c) {
    io::OutBuf out;
    io::outbuf_init(&out, c.allocator, 4096);
    for(u64 module_index = 0; module_index < c.modules.len; module_index += 1) {
        module::Module* m = c.modules.ptr[module_index];
        if(m.sapir == null) { continue; }
        sapir_print::print_module((sapir::SapirModule*)m.sapir, &out);
    }
    u8[] bytes = io::outbuf_bytes(&out);
    sys::dprintf(1, "%.*s", (i32)bytes.len, (i8*)bytes.ptr);
}

fn void dump_cfgs(Compiler* c) {
    io::OutBuf out;
    io::outbuf_init(&out, c.allocator, 4096);
    for(u64 module_index = 0; module_index < c.modules.len; module_index += 1) {
        cfg_print::print_module(c.modules.ptr[module_index], &out);
    }
    u8[] bytes = io::outbuf_bytes(&out);
    sys::dprintf(1, "%.*s", (i32)bytes.len, (i8*)bytes.ptr);
}

// Write each module's diagnostics to stderr in ModuleId order, tally errors, reset.
export fn void drain_diagnostics(Compiler* c) {
    for(u64 module_index = 0; module_index < c.modules.len; module_index += 1) {
        module::Module* m = c.modules.ptr[module_index];
        for(u64 entry_index = 0; entry_index < m.diag.entries.len; entry_index += 1) {
            diag::DiagEntry* entry = &m.diag.entries[entry_index];
            if(!entry.is_warning) { c.error_count += 1; }
            print_diagnostic(m, entry);
        }
        diag::reset(&m.diag);
    }
}

const u32 PAD_MAX = 256;
// "<path>:<line>:<col>: <msg>"; a compinsert-generated position resolves back to its (possibly nested) generator site.
fn void print_diagnostic(module::Module* m, diag::DiagEntry* entry) {
    u32 pos = entry.src_pos;
    bool generated = false;
    u32 fragment_line = 0;
    u32 fragment_col = 0;
    while(pos >= (u32)m.source.len) {
        module::InsertedSource* src = module::find_inserted_source(m, pos);
        if(src == null) { break; }
        // Only the innermost fragment's coordinates are reported; outer frames just walk to the generator.
        if(!generated) { fragment_position(src, pos, &fragment_line, &fragment_col); }
        pos = src.generator_pos;
        generated = true;
    }
    u32 line = 0;
    u32 col = 0;
    module::line_col(m, pos, &line, &col);
    if(generated) {
        sys::dprintf(2, "%.*s:%u:%u: %.*s (in generated code at %u:%u)\n", (i32)m.path.len, (i8*)m.path.ptr, line, col, (i32)entry.msg.len, (i8*)entry.msg.ptr, fragment_line, fragment_col);
    } else {
        sys::dprintf(2, "%.*s:%u:%u: %.*s\n", (i32)m.path.len, (i8*)m.path.ptr, line, col, (i32)entry.msg.len, (i8*)entry.msg.ptr);
    }
    // Print the actual line with the error
    if(pos < (u32)m.source.len) {
        if(line == 0 || (u64)line > m.line_starts.len) { return; }
        u32 start = m.line_starts[line - 1];
        u32 end = start;
        while(end < (u32)m.source.len && m.source[end] != '\n') { end += 1; }
        if(end > start && m.source[end - 1] == '\r') { end -= 1; }
        sys::dprintf(2, "%.*s\n", (i32)(end - start), (i8*)(m.source.ptr + start));
        u32 width = col - 1;
        if(width > PAD_MAX) { width = PAD_MAX; }
        u8[PAD_MAX] pad;
        for(u32 i = 0; i < width; i += 1) {
            if(start + i < end && m.source[start + i] == '\t') { pad[i] = '\t'; } else { pad[i] = ' '; }
        }
        sys::dprintf(2, "%.*s^\n", (i32)width, (i8*)&pad[0]);
    }
}

fn void fragment_position(module::InsertedSource* src, u32 pos, u32* line, u32* col) {
    u32 offset = pos - src.base;
    u32 found_line = 1;
    u32 line_start = 0;
    for(u32 scan = 0; scan < offset && scan < (u32)src.bytes.len; scan += 1) {
        if(src.bytes[scan] == 10) {
            found_line += 1;
            line_start = scan + 1;
        }
    }
    *line = found_line;
    *col = offset - line_start + 1;
}

export fn bool bail_on_errors(Compiler* c) {
    return c.error_count > 0;
}
