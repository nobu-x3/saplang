import module;
import scanner;
import parser;
import sema;
import comptime;
import cfg;
import cfg_print;
import diag;
import arena;
import sys;
import io;
import interner;
import symbol;
import token;
import pool;

export struct Compiler {
    arena::Arena*        arena;
    module::Module*[]    modules;         // flat, indexed by ModuleId (the array index)
    u64                  modules_cap;
    u8[][]               entry_sources;   // user-supplied source file paths
    u64                  entry_sources_cap;
    u8[][]               import_paths;    // -i search list
    u64                  import_paths_cap;
    u8[]                 target;          // conditional-compilation infix; empty = none
    bool                 is_multithreaded; // run phases on a thread pool sized to cpu_count
    bool                 cfg_dump;         // -cfg-dump: print each function's CFG to stdout
    pool::ThreadPool*    pool;            // non-null only while multithreaded
    i64                  error_count;
}

export fn Compiler* new(arena::Arena* a) {
    Compiler* c = (Compiler*)arena::alloc(a, sizeof(Compiler));
    sys::memset(c, 0, sizeof(Compiler));
    c.arena = a;
    return c;
}

export fn void add_module(Compiler* c, module::Module* m) {
    if(c.modules.len == c.modules_cap) {
        u64 new_cap = 8;
        if(c.modules_cap > 0) { new_cap = c.modules_cap * 2; }
        c.modules.ptr = (module::Module**)arena::realloc_grow(c.arena, (void*)c.modules.ptr, c.modules.len * sizeof(module::Module*), new_cap * sizeof(module::Module*));
        c.modules_cap = new_cap;
    }
    c.modules[c.modules.len] = m;
    c.modules.len += 1;
}

export fn void add_source(Compiler* c, u8[] path) {
    if(c.entry_sources.len == c.entry_sources_cap) {
        u64 new_cap = 4;
        if(c.entry_sources_cap > 0) { new_cap = c.entry_sources_cap * 2; }
        c.entry_sources.ptr = arena::realloc_grow(c.arena, (void*)c.entry_sources.ptr, c.entry_sources.len * sizeof(u8[]), new_cap * sizeof(u8[]));
        c.entry_sources_cap = new_cap;
    }
    c.entry_sources[c.entry_sources.len] = path;
    c.entry_sources.len += 1;
}

export fn void add_import_path(Compiler* c, u8[] path) {
    if(c.import_paths.len == c.import_paths_cap) {
        u64 new_cap = 4;
        if(c.import_paths_cap > 0) { new_cap = c.import_paths_cap * 2; }
        c.import_paths.ptr = arena::realloc_grow(c.arena, (void*)c.import_paths.ptr, c.import_paths.len * sizeof(u8[]), new_cap * sizeof(u8[]));
        c.import_paths_cap = new_cap;
    }
    c.import_paths[c.import_paths.len] = path;
    c.import_paths.len += 1;
}

export fn void set_target(Compiler* c, u8[] t) {
    c.target = t;
}

export fn void set_multithreaded(Compiler* c, bool on) {
    c.is_multithreaded = on;
}

// Recognizes <file>.sl, -i <;-list>, -target <name>, -mt, -cfg-dump; false on anything else.
export fn bool parse_argv(Compiler* c, u8[][] args) {
    bool ok = true;
    u64 arg_index = 0;
    while(arg_index < args.len) {
        u8[] arg = args[arg_index];
        if(slice_eq(arg, "-i")) {
            arg_index += 1;
            if(arg_index < args.len) { add_import_path_list(c, args[arg_index]); } else { ok = false; }
        } else if(slice_eq(arg, "-target")) {
            arg_index += 1;
            if(arg_index < args.len) { c.target = args[arg_index]; } else { ok = false; }
        } else if(slice_eq(arg, "-mt")) {
            c.is_multithreaded = true;
        } else if(slice_eq(arg, "-cfg-dump")) {
            c.cfg_dump = true;
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

fn void add_import_path_list(Compiler* c, u8[] list) {
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

fn bool slice_eq(u8[] a, u8[] b) {
    if(a.len != b.len) { return false; }
    for(u64 char_index = 0; char_index < a.len; char_index += 1) {
        if(a[char_index] != b[char_index]) { return false; }
    }
    return true;
}

fn bool ends_with(u8[] s, u8[] suffix) {
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
        add_entry_module(c, c.entry_sources[entry_index]);
    }
    u64 cursor = 0;
    while(cursor < c.modules.len) {
        module::Module* m = c.modules[cursor];
        scanner::scan(m);
        discover_imports(c, m);
        cursor += 1;
    }
}

// Unreadable is an error; an empty file is valid (imports get their check in resolve_import_source).
fn void add_entry_module(Compiler* c, u8[] path) {
    u8[] empty = {null, 0};
    module::Module* m = new_source_module(c, interner::intern(path_stem(path)), empty);
    add_module(c, m);
    io::File f = io::open(path, "r");
    if(f.fp == null) {
        diag::report(&m.diag, m.arena, 0, "cannot read source file");
        return;
    }
    m.source = io::read_all(&f, c.arena);
    io::close(&f);
}

fn module::Module* new_source_module(Compiler* c, symbol::Symbol* name, u8[] src) {
    module::Module* m = (module::Module*)arena::alloc(c.arena, sizeof(module::Module));
    sys::memset(m, 0, sizeof(module::Module));
    arena::Arena* module_arena = (arena::Arena*)arena::alloc(c.arena, sizeof(arena::Arena));
    sys::memset(module_arena, 0, sizeof(arena::Arena));
    module_arena.default_page_size = 1048576;
    m.arena = module_arena;
    m.name = name;
    m.source = src;
    return m;
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
    module::Module** import_list = (module::Module**)arena::alloc(c.arena, import_count * sizeof(module::Module*));
    u64 filled = 0;
    token_index = 0;
    while(token_index < toks.len) {
        if(is_import_at(toks, token_index)) {
            symbol::Symbol* import_name = toks[token_index + 1].data.sym;
            module::Module* dep = find_module(c, import_name);
            if(dep == null) {
                bool found = false;
                u8[] src = resolve_import_source(c, import_name, &found);
                if(!found) {
                    diag::report(&m.diag, m.arena, toks[token_index].src_pos, "module not found");
                    token_index += 3;
                    continue;
                }
                dep = new_source_module(c, import_name, src);
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
        if(c.modules[module_index].name == name) { return c.modules[module_index]; }
    }
    return null;
}

// Search import paths for <name>.<target>.sl (if a target is set), then <name>.sl; read the first that opens.
// Reading at resolution time (one open per candidate) means a module is only created from source we actually read.
fn u8[] resolve_import_source(Compiler* c, symbol::Symbol* name, bool* found) {
    u8[] name_bytes = interner::symbol_str(name);
    u8[] empty = {null, 0};
    for(u64 path_index = 0; path_index < c.import_paths.len; path_index += 1) {
        if(c.target.len > 0) {
            u8[] platform = join_filename(c, c.import_paths[path_index], name_bytes, c.target);
            u8[] bytes = open_and_read(c, platform, found);
            if(*found) { return bytes; }
        }
        u8[] candidate = join_filename(c, c.import_paths[path_index], name_bytes, empty);
        u8[] bytes = open_and_read(c, candidate, found);
        if(*found) { return bytes; }
    }
    *found = false;
    return empty;
}

fn u8[] join_filename(Compiler* c, u8[] dir, u8[] name, u8[] target) {
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
    u8* out = (u8*)arena::alloc(c.arena, len);
    sys::memcpy(out, &buf[0], len);
    u8[] result = {out, len};
    return result;
}

// *found is whether the file could be opened; the io API can't distinguish absent from unreadable, so both are "not found".
fn u8[] open_and_read(Compiler* c, u8[] path, bool* found) {
    io::File f = io::open(path, "r");
    u8[] empty = {null, 0};
    if(f.fp == null) { *found = false; return empty; }
    u8[] bytes = io::read_all(&f, c.arena);
    io::close(&f);
    *found = true;
    return bytes;
}

fn u8[] path_stem(u8[] path) {
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

// Discover + frontend; CFG/codegen/link land later. Returns 0 on success.
export fn i32 run(Compiler* c) {
    discover(c);
    drain_diagnostics(c);
    if(bail_on_errors(c)) { return 1; }
    return run_frontend(c);
}

// Runs the frontend phases (parse -> barriered sema); 0 on success, 1 on any error.
export fn i32 run_frontend(Compiler* c) {
    comptime::install_hooks();
    sema::init_body_sync();
    if(c.is_multithreaded) { c.pool = pool::new(c.arena, sys::cpu_count()); }
    run_parse(c);
    i32 rc = 0;
    if(bail_on_errors(c)) {
        rc = 1;
    } else {
        run_sema(c);
        if(bail_on_errors(c)) {
            rc = 1;
        } else {
            run_cfg(c);
            if(bail_on_errors(c)) { rc = 1; }
            if(c.cfg_dump) { dump_cfgs(c); }
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
            pool::submit(c.pool, job, (void*)c.modules[module_index]);
        }
        pool::wait_all(c.pool);
        return;
    }
    for(u64 module_index = 0; module_index < c.modules.len; module_index += 1) {
        job((void*)c.modules[module_index]);
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

fn void dump_cfgs(Compiler* c) {
    io::OutBuf out;
    io::outbuf_init(&out, c.arena, 4096);
    for(u64 module_index = 0; module_index < c.modules.len; module_index += 1) {
        cfg_print::print_module(c.modules[module_index], &out);
    }
    u8[] bytes = io::outbuf_bytes(&out);
    sys::dprintf(1, "%.*s", (i32)bytes.len, (i8*)bytes.ptr);
}

// Write each module's diagnostics to stderr in ModuleId order, tally errors, reset.
export fn void drain_diagnostics(Compiler* c) {
    for(u64 module_index = 0; module_index < c.modules.len; module_index += 1) {
        module::Module* m = c.modules[module_index];
        for(u64 entry_index = 0; entry_index < m.diag.entries.len; entry_index += 1) {
            diag::DiagEntry* entry = &m.diag.entries[entry_index];
            if(!entry.is_warning) { c.error_count += 1; }
            sys::dprintf(2, "%.*s\n", (i32)entry.msg.len, (i8*)entry.msg.ptr);
        }
        diag::reset(&m.diag);
    }
}

export fn bool bail_on_errors(Compiler* c) {
    return c.error_count > 0;
}
