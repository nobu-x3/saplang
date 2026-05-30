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

// Human-readable name for a TokenKind, suitable for diagnostic messages.
// Punctuation / operators / keywords are returned single-quoted so they
// stand out from surrounding prose; category tokens (literals, identifiers)
// are returned as plain noun phrases.
export fn u8[] kind_name(TokenKind k) {
	switch(k) {
	case TokenKind::EOF:          { return "end of file"; }
	case TokenKind::ERROR:        { return "<error>"; }

	case TokenKind::IntLit:       { return "integer literal"; }
	case TokenKind::FloatLit:     { return "float literal"; }
	case TokenKind::CharLit:      { return "character literal"; }
	case TokenKind::StringLit:    { return "string literal"; }
	case TokenKind::Ident:        { return "identifier"; }

	case TokenKind::LParen:       { return "'('"; }
	case TokenKind::RParen:       { return "')'"; }
	case TokenKind::LBrace:       { return "'{'"; }
	case TokenKind::RBrace:       { return "'}'"; }
	case TokenKind::LBracket:     { return "'['"; }
	case TokenKind::RBracket:     { return "']'"; }
	case TokenKind::Comma:        { return "','"; }
	case TokenKind::Semi:         { return "';'"; }
	case TokenKind::Colon:        { return "':'"; }
	case TokenKind::ColonColon:   { return "'::'"; }
	case TokenKind::Dot:          { return "'.'"; }
	case TokenKind::DotDot:       { return "'..'"; }
	case TokenKind::DotDotDot:    { return "'...'"; }

	case TokenKind::Plus:         { return "'+'"; }
	case TokenKind::Minus:        { return "'-'"; }
	case TokenKind::Star:         { return "'*'"; }
	case TokenKind::Slash:        { return "'/'"; }
	case TokenKind::Percent:      { return "'%'"; }
	case TokenKind::Amp:          { return "'&'"; }
	case TokenKind::Pipe:         { return "'|'"; }
	case TokenKind::Caret:        { return "'^'"; }
	case TokenKind::Tilde:        { return "'~'"; }
	case TokenKind::Bang:         { return "'!'"; }
	case TokenKind::LShift:       { return "'<<'"; }
	case TokenKind::RShift:       { return "'>>'"; }
	case TokenKind::Eq:           { return "'='"; }
	case TokenKind::PlusEq:       { return "'+='"; }
	case TokenKind::MinusEq:      { return "'-='"; }
	case TokenKind::StarEq:       { return "'*='"; }
	case TokenKind::SlashEq:      { return "'/='"; }
	case TokenKind::PercentEq:    { return "'%='"; }
	case TokenKind::AmpEq:        { return "'&='"; }
	case TokenKind::PipeEq:       { return "'|='"; }
	case TokenKind::CaretEq:      { return "'^='"; }
	case TokenKind::EqEq:         { return "'=='"; }
	case TokenKind::BangEq:       { return "'!='"; }
	case TokenKind::LT:           { return "'<'"; }
	case TokenKind::GT:           { return "'>'"; }
	case TokenKind::LTEQ:         { return "'<='"; }
	case TokenKind::GTEQ:         { return "'>='"; }
	case TokenKind::AmpAmp:       { return "'&&'"; }
	case TokenKind::PipePipe:     { return "'||'"; }

	case TokenKind::I8:           { return "'i8'"; }
	case TokenKind::I16:          { return "'i16'"; }
	case TokenKind::I32:          { return "'i32'"; }
	case TokenKind::I64:          { return "'i64'"; }
	case TokenKind::U8:           { return "'u8'"; }
	case TokenKind::U16:          { return "'u16'"; }
	case TokenKind::U32:          { return "'u32'"; }
	case TokenKind::U64:          { return "'u64'"; }
	case TokenKind::F32:          { return "'f32'"; }
	case TokenKind::F64:          { return "'f64'"; }
	case TokenKind::BOOL:         { return "'bool'"; }
	case TokenKind::VOID:         { return "'void'"; }
	case TokenKind::TYPE:         { return "'Type'"; }

	case TokenKind::STRUCT:       { return "'struct'"; }
	case TokenKind::UNION:        { return "'union'"; }
	case TokenKind::ENUM:         { return "'enum'"; }
	case TokenKind::FN:           { return "'fn'"; }
	case TokenKind::CONST:        { return "'const'"; }
	case TokenKind::RETURN:       { return "'return'"; }
	case TokenKind::EXTERN:       { return "'extern'"; }
	case TokenKind::EXPORT:       { return "'export'"; }
	case TokenKind::IMPORT:       { return "'import'"; }
	case TokenKind::IF:           { return "'if'"; }
	case TokenKind::ELSE:         { return "'else'"; }
	case TokenKind::WHILE:        { return "'while'"; }
	case TokenKind::FOR:          { return "'for'"; }
	case TokenKind::SWITCH:       { return "'switch'"; }
	case TokenKind::CASE:         { return "'case'"; }
	case TokenKind::BREAK:        { return "'break'"; }
	case TokenKind::CONTINUE:     { return "'continue'"; }
	case TokenKind::DEFER:        { return "'defer'"; }
	case TokenKind::TRUE:         { return "'true'"; }
	case TokenKind::FALSE:        { return "'false'"; }
	case TokenKind::NULL:         { return "'null'"; }
	case TokenKind::UNDEFINED:    { return "'undefined'"; }
	case TokenKind::ALIAS:        { return "'alias'"; }

	case TokenKind::COMPTIME:     { return "'comptime'"; }
	case TokenKind::COMPRUN:      { return "'comprun'"; }
	case TokenKind::COMPINSERT:   { return "'compinsert'"; }
	case TokenKind::COMPCODE:     { return "'compcode'"; }
	case TokenKind::COMPSPLICE:   { return "'compsplice'"; }
	case TokenKind::COMPERROR:    { return "'comperror'"; }
	case TokenKind::COMPWARNING:  { return "'compwarning'"; }
	case TokenKind::SIZEOF:       { return "'sizeof'"; }
	case TokenKind::ALIGNOF:      { return "'alignof'"; }
	case TokenKind::TYPEOF:       { return "'typeof'"; }
	case TokenKind::TYPE_INFO:    { return "'type_info'"; }
	else { return "<unknown>"; }
	}
	return "<unknown>";
}

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
