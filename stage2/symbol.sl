export struct Symbol {
    u64                 offset; // index into Interner.slab
    u32                 len;
    u32                 hash;
    u16                 keyword_kind;  // 0 = regular identifier; else the TK_* of the keyword
    u16                 _pad;
    Symbol*             chain; // open chained bucket
}
