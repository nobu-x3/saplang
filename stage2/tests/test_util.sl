import ast;
import arena;
import mem;
import cfg;
import comptime_interp;
import interner;
import module;
import parser;
import scanner;
import sema;
import sys;
import token;
import types;

const u64 E2E_BUCKETS = 64;

// An allocator defined outside std, so tests can prove a std module really allocates through the
// interface rather than through an arena it names. Wraps any inner allocator and tallies the traffic.
export struct Counting {
    mem::Allocator inner;
    u64            allocs;
    u64            frees;
    u64            bytes;
}

export fn mem::Allocator counting_allocator(Counting* c) {
    mem::Allocator out;
    out.ctx = (void*)c;
    out.alloc_fn = &counting_alloc;
    out.realloc_grow_fn = &counting_realloc_grow;
    out.free_fn = &counting_free;
    return out;
}

fn void* counting_alloc(void* ctx, u64 size) {
    Counting* c = (Counting*)ctx;
    c.allocs += 1;
    c.bytes += size;
    return mem::alloc(c.inner, size);
}

fn void* counting_realloc_grow(void* ctx, void* old, u64 old_size, u64 new_size) {
    Counting* c = (Counting*)ctx;
    c.allocs += 1;
    c.bytes += new_size - old_size;
    return mem::realloc_grow(c.inner, old, old_size, new_size);
}

fn void counting_free(void* ctx, void* ptr, u64 size) {
    Counting* c = (Counting*)ctx;
    c.frees += 1;
    mem::free(c.inner, ptr, size);
}

// Each module needs its own arena: the driver gives every module one, and sharing hides ownership bugs.
export fn arena::Arena* sub_arena(arena::Arena* a) {
    arena::Arena* sub = (arena::Arena*)arena::alloc(a, sizeof(arena::Arena));
    sys::memset(sub, 0, sizeof(arena::Arena));
    sub.default_page_size = 1048576;
    return sub;
}

// Process-global state the multi-module path needs; the single-module frontend below does its own.
export fn void boot(arena::Arena* a) {
    interner::init(sub_arena(a), E2E_BUCKETS);
    types::typer_init(sub_arena(a), E2E_BUCKETS);
    token::load_keywords();
    comptime_interp::install_hooks();
}

export fn module::Module* mk_module(arena::Arena* a, u8[] name, u8[] src) {
    module::Module* m = (module::Module*)arena::alloc(a, sizeof(module::Module));
    sys::memset(m, 0, sizeof(module::Module));
    module::set_arena(m, sub_arena(a));
    m.source = src;
    m.name = interner::intern(name);
    m.build = host_build();
    return m;
}

// The multi-module analogue of frontend: the driver's barriered sema order, but without draining the
// diagnostics, so a test can pin a cross-module message and its src_pos.
export fn void frontend_modules(module::Module*[] modules) {
    for(u64 index = 0; index < modules.len; index += 1) {
        scanner::scan(modules[index]);
        modules[index].root_node = parser::parse(modules[index]);
    }
    if(errors_in(modules) > 0) { return; }
    for(u64 index = 0; index < modules.len; index += 1) { sema::collect_names(modules[index]); }
    if(errors_in(modules) > 0) { return; }
    for(u64 index = 0; index < modules.len; index += 1) { sema::resolve_signatures(modules[index]); }
    if(errors_in(modules) > 0) { return; }
    for(u64 index = 0; index < modules.len; index += 1) { sema::check_bodies(modules[index]); }
    if(errors_in(modules) > 0) { return; }
    for(u64 index = 0; index < modules.len; index += 1) { cfg::build_all_functions(modules[index]); }
}

export fn u64 errors_in(module::Module*[] modules) {
    u64 count = 0;
    for(u64 index = 0; index < modules.len; index += 1) { count += error_count(modules[index]); }
    return count;
}

export fn void wire_imports(arena::Arena* a, module::Module* m, module::Module*[] deps) {
    module::Module** imports = (module::Module**)arena::alloc(a, deps.len * sizeof(module::Module*));
    for(u64 dep_index = 0; dep_index < deps.len; dep_index += 1) { imports[dep_index] = deps[dep_index]; }
    m.imports = {imports, deps.len};
}

// Runs the single-module frontend (scan → parse → sema → cfg) with driver-style bail between phases.
// Diagnostics stay in m.diag (not drained), so tests can pin exact messages + src_pos.
export fn module::Module* frontend(arena::Arena* a, u8[] src) {
    return frontend_build(a, src, host_build());
}

export fn module::BuildInfo host_build() {
    module::BuildInfo build;
    build.os = "linux";
    build.arch = "x86_64";
    build.config = "Debug";
    build.defines = {null, 0};
    return build;
}

export fn module::Module* frontend_build(arena::Arena* a, u8[] src, module::BuildInfo build) {
    interner::init(a, E2E_BUCKETS);
    token::load_keywords();
    types::typer_init(a, E2E_BUCKETS);
    comptime_interp::install_hooks();
    module::Module* m = (module::Module*)arena::alloc(a, sizeof(module::Module));
    sys::memset(m, 0, sizeof(module::Module));
    module::set_arena(m, a);
    m.source = src;
    m.build = build;
    m.name = interner::intern("main");
    scanner::scan(m);
    m.root_node = parser::parse(m);
    if(error_count(m) > 0) { return m; }
    sema::collect_names(m);
    if(error_count(m) > 0) { return m; }
    sema::resolve_signatures(m);
    if(error_count(m) > 0) { return m; }
    sema::check_bodies(m);
    if(error_count(m) > 0) { return m; }
    cfg::build_all_functions(m);
    return m;
}

export fn u64 error_count(module::Module* m) {
    u64 count = 0;
    for(u64 i = 0; i < m.diag.entries.len; i += 1) {
        if(!m.diag.entries[i].is_warning) { count += 1; }
    }
    return count;
}

export fn u64 warning_count(module::Module* m) {
    u64 count = 0;
    for(u64 i = 0; i < m.diag.entries.len; i += 1) {
        if(m.diag.entries[i].is_warning) { count += 1; }
    }
    return count;
}
