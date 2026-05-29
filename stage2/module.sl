import arena;
import diag;
import interner;
import symbol;
import token;

export struct Module {
    symbol::Symbol*         name;
    u8[]                    source;          // owned; loaded by driver
    u32[]                   line_starts;     // byte offset of every line start
    token::Token[]          tokens;          // scanner output
    u64                     tokens_cap;      // arena-grown capacity
    u8[]                    literal_pool;    // decoded string-literal bytes
    u64                     literal_pool_cap;
    interner::Interner*     interner;
    arena::Arena*           arena;
    diag::DiagBuf           diag;
    // sema/cfg/codegen fields added by later phases
}
