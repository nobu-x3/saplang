import ast;
import arena;
import cfg;
import interner;
import module;
import parser;
import scanner;
import sema;
import sys;
import token;
import types;

const u64 E2E_BUCKETS = 64;

// Runs the single-module frontend (scan → parse → sema → cfg) with driver-style bail between phases.
// Diagnostics stay in m.diag (not drained), so tests can pin exact messages + src_pos.
export fn module::Module* frontend(arena::Arena* a, u8[] src) {
    interner::init(a, E2E_BUCKETS);
    token::load_keywords();
    types::typer_init(a, E2E_BUCKETS);
    module::Module* m = (module::Module*)arena::alloc(a, sizeof(module::Module));
    sys::memset(m, 0, sizeof(module::Module));
    m.arena = a;
    m.source = src;
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
