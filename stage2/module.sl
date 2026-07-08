import arena;
import diag;
import symbol;
import token;
import mutex;
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
    u16                     sema_phase;      // bitflags from sema::SemaPhase; guards cross-module re-entry
    mutex::Mutex            sema_mutex;
    // cfg/codegen fields added by later phases
}
