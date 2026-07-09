import module;
import scanner;
import parser;
import sema;
import diag;
import arena;
import sys;
import io;
import interner;
import symbol;
import token;

export struct Compiler {
    arena::Arena*        arena;
    module::Module*[]    modules;         // flat, indexed by ModuleId (the array index)
    u64                  modules_cap;
    u8[][]               entry_sources;   // user-supplied source file paths
    u64                  entry_sources_cap;
    u8[][]               import_paths;    // -i search list
    u64                  import_paths_cap;
    u8[]                 target;          // conditional-compilation infix; empty = none
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

// Walk imports from the entry sources, resolving each to a file and building the
// module graph. Uses scanner output only — no parsing. Import cycles are fine.
export fn void discover(Compiler* c) {
    for(u64 i = 0; i < c.entry_sources.len; i += 1) {
        add_entry_module(c, c.entry_sources[i]);
    }
    u64 cursor = 0;
    while(cursor < c.modules.len) {
        module::Module* m = c.modules[cursor];
        scanner::scan(m);
        discover_imports(c, m);
        cursor += 1;
    }
}

// Entry sources need a not-found check (imports get theirs via resolve_import);
// an unreadable file is an error, but an empty file is legitimately valid.
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
    m.arena = c.arena;
    m.name = name;
    m.source = src;
    return m;
}

fn void discover_imports(Compiler* c, module::Module* m) {
    token::Token[] toks = m.tokens;
    u64 count = 0;
    u64 i = 0;
    while(i < toks.len) {
        if(is_import_at(toks, i)) { count += 1; i += 3; continue; }
        i += 1;
    }
    if(count == 0) { return; }
    module::Module** imps = (module::Module**)arena::alloc(c.arena, count * sizeof(module::Module*));
    u64 fill = 0;
    i = 0;
    while(i < toks.len) {
        if(is_import_at(toks, i)) {
            symbol::Symbol* import_name = toks[i + 1].data.sym;
            module::Module* dep = find_module(c, import_name);
            if(dep == null) {
                u8[] path = resolve_import(c, import_name);
                if(path.len == 0) {
                    diag::report(&m.diag, m.arena, toks[i].src_pos, "module not found");
                    i += 3;
                    continue;
                }
                dep = new_source_module(c, import_name, read_file(c, path));
                add_module(c, dep);
            }
            imps[fill] = dep;
            fill += 1;
            i += 3;
            continue;
        }
        i += 1;
    }
    m.imports = {imps, fill};
}

fn bool is_import_at(token::Token[] toks, u64 i) {
    return i + 2 < toks.len && toks[i].kind == token::TokenKind::IMPORT && toks[i + 1].kind == token::TokenKind::Ident && toks[i + 2].kind == token::TokenKind::Semi;
}

fn module::Module* find_module(Compiler* c, symbol::Symbol* name) {
    for(u64 i = 0; i < c.modules.len; i += 1) {
        if(c.modules[i].name == name) { return c.modules[i]; }
    }
    return null;
}

// Search import paths for <name>.<target>.sl (if a target is set), then <name>.sl.
fn u8[] resolve_import(Compiler* c, symbol::Symbol* name) {
    u8[] name_bytes = interner::symbol_str(name);
    for(u64 i = 0; i < c.import_paths.len; i += 1) {
        if(c.target.len > 0) {
            u8[] platform = join_filename(c, c.import_paths[i], name_bytes, c.target);
            if(exists(platform)) { return platform; }
        }
        u8[] empty = {null, 0};
        u8[] candidate = join_filename(c, c.import_paths[i], name_bytes, empty);
        if(exists(candidate)) { return candidate; }
    }
    u8[] none = {null, 0};
    return none;
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

fn bool exists(u8[] path) {
    io::File f = io::open(path, "r");
    if(f.fp == null) { return false; }
    io::close(&f);
    return true;
}

fn u8[] read_file(Compiler* c, u8[] path) {
    io::File f = io::open(path, "r");
    u8[] empty = {null, 0};
    if(f.fp == null) { return empty; }
    u8[] bytes = io::read_all(&f, c.arena);
    io::close(&f);
    return bytes;
}

fn u8[] path_stem(u8[] path) {
    u64 start = 0;
    for(u64 i = 0; i < path.len; i += 1) {
        if(path[i] == '/') { start = i + 1; }
    }
    u64 end = path.len;
    for(u64 i = start; i < path.len; i += 1) {
        if(path[i] == '.') { end = i; break; }
    }
    u8[] out = {&path.ptr[start], end - start};
    return out;
}

// Runs the frontend phases (parse -> barriered sema); 0 on success, 1 on any error.
export fn i32 run_frontend(Compiler* c) {
    run_parse(c);
    if(bail_on_errors(c)) { return 1; }
    run_sema(c);
    if(bail_on_errors(c)) { return 1; }
    return 0;
}

fn void run_parse(Compiler* c) {
    for(u64 i = 0; i < c.modules.len; i += 1) {
        module::Module* m = c.modules[i];
        scanner::scan(m);
        m.root_node = parser::parse(m);
    }
    drain_diagnostics(c);
}

// The three sema sub-passes are barriered: every module completes a sub-pass
// before any starts the next, so cross-module lookups always read a complete world.
fn void run_sema(Compiler* c) {
    for(u64 i = 0; i < c.modules.len; i += 1) { sema::collect_names(c.modules[i]); }
    drain_diagnostics(c);
    if(bail_on_errors(c)) { return; }
    for(u64 i = 0; i < c.modules.len; i += 1) { sema::resolve_signatures(c.modules[i]); }
    drain_diagnostics(c);
    if(bail_on_errors(c)) { return; }
    for(u64 i = 0; i < c.modules.len; i += 1) { sema::check_bodies(c.modules[i]); }
    drain_diagnostics(c);
}

// Write each module's diagnostics to stderr in ModuleId order, tally errors, reset.
export fn void drain_diagnostics(Compiler* c) {
    for(u64 i = 0; i < c.modules.len; i += 1) {
        module::Module* m = c.modules[i];
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
