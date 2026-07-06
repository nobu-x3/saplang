export struct Symbol {
    u64                 offset; // index into Interner.slab
    u32                 len;
    u32                 hash;
    u16                 keyword_kind;  // 0 = regular identifier; else the TK_* of the keyword
    u16                 _pad;
    Symbol*             chain; // open chained bucket
}

export fn u64 hash(Symbol* s) {
    return ((u64)s * 0x9E3779B97F4A7C15) >> 0;
}
