import module;
import scanner;
import parser;
import sema;
import diag;
import arena;
import sys;

export struct Compiler {
    arena::Arena*        arena;
    module::Module*[]    modules;         // flat, indexed by ModuleId (the array index)
    u64                  modules_cap;
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
