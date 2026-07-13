import arena;
import diag;
import symbol;
import token;
import ast;

export struct Module {
    symbol::Symbol*         name;
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
    void*                   mono_cache;      // comptime::MonoCache* — caller-side monomorphization cache (void* breaks the cycle)
    ast::FnDeclNode*[]      instantiated_fns; // monomorphized clones; CFG + codegen pick these up
    u64                     instantiated_fns_cap;
    u32                     next_inserted_base;   // first virtual src_pos for compinsert-generated code; set to source.len at scan
    InsertedSource[]        inserted_sources;
    u64                     inserted_sources_cap;
    void*                   reflect_typeinfo;     // types::Type* — synthesized TypeInfo/FieldInfo, built lazily per module
    void*                   reflect_fieldinfo;
    // cfg/codegen fields added by later phases
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
    if(m.inserted_sources.len == m.inserted_sources_cap) {
        u64 new_cap = 4;
        if(m.inserted_sources_cap > 0) { new_cap = m.inserted_sources_cap * 2; }
        m.inserted_sources.ptr = (InsertedSource*)arena::realloc_grow(m.arena, (void*)m.inserted_sources.ptr, m.inserted_sources.len * sizeof(InsertedSource), new_cap * sizeof(InsertedSource));
        m.inserted_sources_cap = new_cap;
    }
    InsertedSource entry;
    entry.base = base;
    entry.bytes = bytes;
    entry.generator_pos = generator_pos;
    m.inserted_sources[m.inserted_sources.len] = entry;
    m.inserted_sources.len += 1;
    m.next_inserted_base = base + (u32)bytes.len;
    return base;
}

export fn InsertedSource* find_inserted_source(Module* m, u32 pos) {
    for(u64 i = 0; i < m.inserted_sources.len; i += 1) {
        InsertedSource* src = &m.inserted_sources[i];
        if(pos >= src.base && pos < src.base + (u32)src.bytes.len) { return src; }
    }
    return null;
}
