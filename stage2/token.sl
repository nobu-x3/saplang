import symbol;
import sys;
import interner;

export enum TokenKind : u16 {
    // sentinels
    EOF,
    ERROR,

    // literals
    IntLit,
    FloatLit,
    CharLit,
    StringLit,
    Ident,

    // puctuation
    LParen, RParen, LBrace, RBrace, LBracket, RBracket,
    Comma, Semi, Colon, ColonColon, Dot, DotDot, DotDotDot,

    // operators
    Plus, Minus, Star, Slash, Percent,
    Amp, Pipe, Caret, Tilde, Bang,
    LShift, RShift,
    Eq,
    PlusEq, MinusEq, StarEq, SlashEq, PercentEq,
    AmpEq, PipeEq, CaretEq,
    EqEq, BangEq, LT, GT, LTEQ, GTEQ,
    AmpAmp, PipePipe,

    // keywords
    I8, I16, I32, I64,
    U8, U16, U32, U64,
    F32, F64,
    BOOL, VOID, TYPE,
    KW_TYPE_FIRST = I8,
    KW_TYPE_LAST = TYPE,

    STRUCT, UNION, ENUM, FN,
    CONST, RETURN, EXTERN, EXPORT, IMPORT,
    IF, ELSE, WHILE, FOR, SWITCH, CASE,
    BREAK, CONTINUE, DEFER,
    TRUE, FALSE, NULL, UNDEFINED,
    ALIAS,

    COMPTIME, COMPRUN,
    COMPINSERT, COMPCODE, COMPSPLICE,
    COMPERROR, COMPWARNING,
    SIZEOF, ALIGNOF, TYPEOF, TYPE_INFO,

    KW_FIRST = I8,
    KW_LAST = TYPE_INFO,
}

export struct Token {
    TokenKind kind;                 // TokenKind enum value
    u16 flags;                      // reserved; bit 0 = had_newline_before (future use)
    u32 src_pos;                    // start byte offset into Module.source
    TokenData data;
}

export  struct StringLitBytes { u32 off; u32 len; }

export union TokenData {
        symbol::Symbol* sym;       // TK_IDENT and every KW_* kind
        u64     ival;               // TK_INT_LIT; also TK_CHAR_LIT (u8 zero-extended)
        f64     fval;               // TK_FLOAT_LIT
        StringLitBytes bytes;  // TK_STRING_LIT, indexes into Module.literal_pool
        u64     none;      // operators / punct / EOF / ERROR
}

export fn bool is_keyword(TokenKind k)      { return k >= TokenKind::KW_FIRST && k <= TokenKind::KW_LAST; }
export fn bool is_type_keyword(TokenKind k) { return k >= TokenKind::KW_TYPE_FIRST && k <= TokenKind::KW_TYPE_LAST; }
export fn bool is_literal(TokenKind k)      { return k >= TokenKind::IntLit && k <= TokenKind::Ident; }

export struct KeywordEntry { u8[] bytes; TokenKind kind; }

export const KeywordEntry[] KEYWORDS = [
    { "i8",  TokenKind::I8  }, { "i16", TokenKind::I16 }, { "i32", TokenKind::I32 }, { "i64", TokenKind::I64 },
    { "u8",  TokenKind::U8  }, { "u16", TokenKind::U16 }, { "u32", TokenKind::U32 }, { "u64", TokenKind::U64 },
    { "f32", TokenKind::F32 }, { "f64", TokenKind::F64 },
    { "bool", TokenKind::BOOL }, { "void", TokenKind::VOID }, { "Type", TokenKind::TYPE },
    { "struct", TokenKind::STRUCT }, { "union", TokenKind::UNION }, { "enum", TokenKind::ENUM }, { "fn", TokenKind::FN },
    { "const", TokenKind::CONST }, { "return", TokenKind::RETURN },
    { "extern", TokenKind::EXTERN }, { "export", TokenKind::EXPORT }, { "import", TokenKind::IMPORT },
    { "if", TokenKind::IF }, { "else", TokenKind::ELSE },
    { "while", TokenKind::WHILE }, { "for", TokenKind::FOR },
    { "switch", TokenKind::SWITCH }, { "case", TokenKind::CASE },
    { "break", TokenKind::BREAK }, { "continue", TokenKind::CONTINUE }, { "defer", TokenKind::DEFER },
    { "true", TokenKind::TRUE }, { "false", TokenKind::FALSE }, { "null", TokenKind::NULL },
    { "undefined", TokenKind::UNDEFINED },
    { "alias", TokenKind::ALIAS },
    { "comptime", TokenKind::COMPTIME }, { "comprun", TokenKind::COMPRUN },
    { "compinsert", TokenKind::COMPINSERT }, { "compcode", TokenKind::COMPCODE },
    { "compsplice", TokenKind::COMPSPLICE },
    { "comperror", TokenKind::COMPERROR }, { "compwarning", TokenKind::COMPWARNING },
    { "sizeof", TokenKind::SIZEOF }, { "alignof", TokenKind::ALIGNOF },
    { "typeof", TokenKind::TYPEOF }, { "type_info", TokenKind::TYPE_INFO },
];

export fn void load_keywords(interner::Interner* it) {
    for (u64 i = 0; i < token::KEYWORDS.len; i += 1) {
        symbol::Symbol* sym = interner::intern(it, KEYWORDS[i].bytes);
        sym.keyword_kind = structs::KEYWORDS[i].kind;
    }
}
