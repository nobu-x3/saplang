import arena;
import list;
import diag;
import symbol;
import token;
import ast;

export struct Module {
    symbol::Symbol*         name;
    u8[]                    path;            // source file path, for diagnostics
    u8[]                    source;          // owned; loaded by driver
    u32[]                   line_starts;     // byte offset of every line start
    token::Token[]          tokens;          // scanner output
    u64                     tokens_cap;      // arena-grown capacity
    ast::AstNode*           root_node;
    u8[]                    literal_pool;    // decoded string-literal bytes
    u64                     literal_pool_cap;
    arena::Arena*           arena;
    diag::DiagBuf           diag;

    Module*[]               imports;         // resolved at discovery; sema reads to map DeclKind::Import
    void*                   global_scope;    // sema::Scope* — every top-level decl; exports filtered by Decl.is_exported
    u16                     sema_phase;      // bitflags from sema::SemaPhase; later phases assert earlier bits
    void*                   mono_cache;      // comptime_interp::MonoCache* — caller-side monomorphization cache (void* breaks the cycle)
    list::List(ast::FnDeclNode*) instantiated_fns; // monomorphized clones; CFG + codegen pick these up
    u32                     next_inserted_base;   // first virtual src_pos for compinsert-generated code; set to source.len at scan
    list::List(InsertedSource) inserted_sources;
    void*                   reflect_typeinfo;     // types::Ty* — synthesized TypeInfo/FieldInfo, built lazily per module
    void*                   reflect_fieldinfo;
    i32                     comptime_max_depth;      // interpreter recursion cap; 0 = built-in default
    u64                     comptime_max_iterations; // interpreter per-loop cap; 0 = built-in default
    void*                   sapir;                   // sapir::SapirModule* — set by lower, consumed by codegen
    // codegen fields added by later phases
}

// Positions in [base, base+bytes.len) belong to this fragment and render via generator_pos.
export struct InsertedSource {
    u32     base;
    u8[]    bytes;
    u32     generator_pos;
}

export fn u32 register_inserted_source(Module* m, u8[] bytes, u32 generator_pos) {
    if(m.next_inserted_base == 0) { m.next_inserted_base = (u32)m.source.len; }
    u32 base = m.next_inserted_base;
    InsertedSource entry;
    entry.base = base;
    entry.bytes = bytes;
    entry.generator_pos = generator_pos;
    list::push(&m.inserted_sources, m.arena, entry);
    m.next_inserted_base = base + (u32)bytes.len;
    return base;
}

export fn InsertedSource* find_inserted_source(Module* m, u32 pos) {
    for(u64 i = 0; i < m.inserted_sources.len; i += 1) {
        InsertedSource* src = &m.inserted_sources.ptr[i];
        if(pos >= src.base && pos < src.base + (u32)src.bytes.len) { return src; }
    }
    return null;
}

// 1-based line and column for a real source position; falls back to line 1 when line starts aren't computed.
export fn void line_col(Module* m, u32 pos, u32* line, u32* col) {
    u64 found = 0;
    for(u64 k = 0; k < m.line_starts.len; k += 1) {
        if(m.line_starts[k] <= pos) { found = k; } else { break; }
    }
    *line = (u32)found + 1;
    if(m.line_starts.len == 0) { *col = pos + 1; return; }
    *col = pos - m.line_starts[found] + 1;
}
