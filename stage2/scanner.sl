import arena;
import diag;
import io;
import module;
import interner;
import symbol;
import sys;
import token;

export fn void scan(module::Module* m) {
    if(!char_class_init) {
        build_char_class_table();
    }
    compute_line_starts(m);
    m.next_inserted_base = (u32)m.source.len;
    u32 pos = 0;
    u32 end = (u32)m.source.len;
    while(pos < end) {
        pos = skip_trivia(m, pos, end);
        if(pos >= end) { break; }
        u8 c = m.source[pos];
        CharClass cc = CHAR_CLASS[c];
        if(((u8)(cc & CharClass::ID_Start)) != 0) {
            pos = scan_identifier(m, pos);
        } else if(((u8)(cc & CharClass::Digit)) != 0) {
            pos = scan_number(m, pos);
        } else if(c == '"') {
            pos = scan_string(m, pos);
        } else if(c == '\'') {
            pos = scan_char(m, pos);
        } else {
            pos = scan_punct(m, pos);
        }
    }
    emit_token(m, token::TokenKind::EOF, pos, 0);
}

fn void check_and_regrow_tokens(module::Module* m) {
    if(m.tokens.len == m.tokens_cap) {
        u64 new_cap = 256;
        if(m.tokens_cap > 0) { new_cap = m.tokens_cap * 2; }
        m.tokens.ptr = arena::realloc_grow(m.arena, m.tokens.ptr,
                m.tokens.len * sizeof(token::Token),
                new_cap * sizeof(token::Token));
        m.tokens_cap = new_cap;
    }
}

fn void emit_token(module::Module* m, token::TokenKind kind, u32 src_pos, u64 raw_data) {
    check_and_regrow_tokens(m);
    token::Token* t = &m.tokens[m.tokens.len];
    t.kind = kind;
    t.flags = 0;
    t.src_pos = src_pos;
    t.data.none = raw_data;
    m.tokens.len += 1;
}

fn void emit_sym_token(module::Module* m, token::TokenKind kind, u32 src_pos, symbol::Symbol* sym) {
    check_and_regrow_tokens(m);
    token::Token* t = &m.tokens[m.tokens.len];
    t.kind = kind;
    t.flags = 0;
    t.src_pos = src_pos;
    t.data.sym = sym;
    m.tokens.len += 1;
}

fn void emit_int_token(module::Module* m, token::TokenKind kind, u32 src_pos, u64 val) {
    check_and_regrow_tokens(m);
    token::Token* t = &m.tokens[m.tokens.len];
    t.kind = kind;
    t.flags = 0;
    t.src_pos = src_pos;
    t.data.ival = val;
    m.tokens.len += 1;
}

fn void emit_float_token(module::Module* m, token::TokenKind kind, u32 src_pos, f64 val) {
    check_and_regrow_tokens(m);
    token::Token* t = &m.tokens[m.tokens.len];
    t.kind = kind;
    t.flags = 0;
    t.src_pos = src_pos;
    t.data.fval = val;
    m.tokens.len += 1;
}

fn void emit_bytes_token(module::Module* m, token::TokenKind kind, u32 src_pos, u32 off, u32 len) {
    check_and_regrow_tokens(m);
    token::Token* t = &m.tokens[m.tokens.len];
    t.kind = kind;
    t.flags = 0;
    t.src_pos = src_pos;
    t.data.bytes.off = off;
    t.data.bytes.len = len;
    m.tokens.len += 1;
}

fn void literal_pool_push(module::Module* m, u8 c) {
    if(m.literal_pool.len == m.literal_pool_cap) {
        u64 new_cap = 256;
        if(m.literal_pool_cap > 0) { new_cap = m.literal_pool_cap * 2; }
        m.literal_pool.ptr = arena::realloc_grow(m.arena, m.literal_pool.ptr,
                m.literal_pool.len, new_cap);
        m.literal_pool_cap = new_cap;
    }
    m.literal_pool[m.literal_pool.len] = c;
    m.literal_pool.len += 1;
}

fn void compute_line_starts(module::Module* m) {
    u32 end = (u32)m.source.len;
    u64 count = 1;
    for(u32 i = 0; i < end; i += 1) {
        if(m.source[i] == '\n') { count += 1; }
    }
    m.line_starts = {(u32*)arena::alloc(m.arena, count * sizeof(u32)), count};
    m.line_starts[0] = 0;
    u64 offset = 1;
    for(u32 i = 0; i < end; i += 1) {
        if(m.source[i] == '\n') {
            m.line_starts[offset] = i + 1;
            offset += 1;
        }
    }
}

fn u32 skip_trivia(module::Module* m, u32 pos, u32 end) {
    while(pos < end) {
        u8 c = m.source[pos];
        CharClass cc = CHAR_CLASS[c];
        if(((u8)(cc & (CharClass::Whitespace | CharClass::NewLine))) != 0) {
            pos += 1;
            continue;
        }
        if(c == '/' && pos + 1 < end && m.source[pos + 1] == '/') {
            pos += 2;
            while(pos < end && m.source[pos] != '\n') { pos += 1; }
            continue;
        }
        break;
    }
    return pos;
}

fn bool digit_of(u8 c, u64 base, u64* out) {
    if(c >= '0' && c <= '9') {
        u64 d = (u64)(c - '0');
        if(d >= base) { return false; }
        *out = d;
        return true;
    }
    if(base == 16) {
        if(c >= 'a' && c <= 'f') { *out = (u64)(c - 'a') + 10; return true; }
        if(c >= 'A' && c <= 'F') { *out = (u64)(c - 'A') + 10; return true; }
    }
    return false;
}

fn u32 scan_identifier(module::Module* m, u32 start) {
    u32 pos = start + 1;
    while(pos < (u32)m.source.len && ((u8)(CHAR_CLASS[m.source[pos]] & CharClass::ID_Cont)) != 0) {
        pos += 1;
    }
    u8[] bytes = {&m.source[start], (u64)(pos - start)};
    symbol::Symbol* sym = interner::intern(bytes);
    token::TokenKind kind = (token::TokenKind)sym.keyword_kind;
    if(sym.keyword_kind == 0) { kind = token::TokenKind::Ident; }
    emit_sym_token(m, kind, start, sym);
    return pos;
}

fn u32 scan_number(module::Module* m, u32 start) {
    u32 pos = start;
    u64 base = 10;
    if(m.source[pos] == '0' && pos + 1 < (u32)m.source.len) {
        u8 c1 = m.source[pos + 1];
        if(c1 == 'x' || c1 == 'X') { base = 16; pos += 2; }
        else if(c1 == 'b' || c1 == 'B') { base = 2; pos += 2; }
    }
    u64 val = 0;
    bool overflow = false;
    while(pos < (u32)m.source.len) {
        u8 c = m.source[pos];
        if(c == '_') { pos += 1; continue; }
        u64 digit;
        if(!digit_of(c, base, &digit)) { break; }
        u64 limit = (0xFFFFFFFFFFFFFFFF - digit) / base;
        if(val > limit) { overflow = true; }
        val = val * base + digit;
        pos += 1;
    }
    if(base == 10 && (pos < (u32)m.source.len && m.source[pos] == '.') && (pos + 1 >= (u32)m.source.len || m.source[pos + 1] != '.')) {
        return parse_float_tail(m, start, pos);
    }
    if(overflow) { diag::report(&m.diag, m.arena, start, "integer literal overflows u64"); }
    emit_int_token(m, token::TokenKind::IntLit, start, val);
    return pos;
}

// strtod can't see '_', so strip them on the way in.
fn u32 parse_float_tail(module::Module* m, u32 start, u32 pos) {
    pos += 1; // skip '.'
    while(pos < (u32)m.source.len) {
        u8 c = m.source[pos];
        if(c == '_') { pos += 1; continue; }
        if(((u8)(CHAR_CLASS[c] & CharClass::Digit)) == 0) { break; }
        pos += 1;
    }
    u8[128] buf;
    u64 j = 0;
    for(u32 i = start; i < pos; i += 1) {
        u8 c = m.source[i];
        if(c == '_') { continue; }
        if(j + 1 >= 128) {
            diag::report(&m.diag, m.arena, start, "float literal too long");
            emit_token(m, token::TokenKind::ERROR, start, 0);
            return pos;
        }
        buf[j] = c;
        j += 1;
    }
    buf[j] = 0;
    i8* endptr = null;
    f64 val = sys::strtod((const i8*)&buf[0], &endptr);
    emit_float_token(m, token::TokenKind::FloatLit, start, val);
    return pos;
}

fn u32 scan_char(module::Module* m, u32 start) {
    u32 pos = start + 1;
    if(pos >= (u32)m.source.len) {
        diag::report(&m.diag, m.arena, start, "unterminated char literal");
        emit_token(m, token::TokenKind::ERROR, start, 0);
        return pos;
    }
    u8 c = m.source[pos];
    pos += 1;
    if(c == '\\') {
        if(pos >= (u32)m.source.len) {
            diag::report(&m.diag, m.arena, start, "unterminated char literal");
            emit_token(m, token::TokenKind::ERROR, start, 0);
            return pos;
        }
        c = decode_escape(m, start, m.source[pos]);
        pos += 1;
    }
    if(pos >= (u32)m.source.len || m.source[pos] != '\'') {
        diag::report(&m.diag, m.arena, start, "char literal must be exactly one character");
        // skip to closing quote or newline to resync
        while(pos < (u32)m.source.len && m.source[pos] != '\'' && m.source[pos] != '\n') {
            pos += 1;
        }
        if(pos < (u32)m.source.len && m.source[pos] == '\'') { pos += 1; }
        emit_token(m, token::TokenKind::ERROR, start, 0);
        return pos;
    }
    pos += 1;
    emit_int_token(m, token::TokenKind::CharLit, start, (u64)c);
    return pos;
}

fn u32 scan_string(module::Module* m, u32 start) {
    u32 pos = start + 1;
    u32 pool_off = (u32)m.literal_pool.len;
    while(pos < (u32)m.source.len && m.source[pos] != '"') {
        u8 c = m.source[pos];
        pos += 1;
        if(c == '\\') {
            if(pos >= (u32)m.source.len) { break; }
            c = decode_escape(m, start, m.source[pos]);
            pos += 1;
        }
        literal_pool_push(m, c);
    }
    if(pos >= (u32)m.source.len) {
        diag::report(&m.diag, m.arena, start, "unterminated string literal");
    } else {
        pos += 1;
    }
    u32 pool_len = (u32)m.literal_pool.len - pool_off;
    emit_bytes_token(m, token::TokenKind::StringLit, start, pool_off, pool_len);
    return pos;
}

fn u8 decode_escape(module::Module* m, u32 start, u8 second) {
    switch (second) {
        case 'n':  { return '\n'; }
        case 't':  { return '\t'; }
        case 'r':  { return '\r'; }
        case '\\': { return '\\'; }
        case '"':  { return '"';  }
        case '\'': { return '\''; }
        case '0':  { return 0;    }
        else {
            diag::report(&m.diag, m.arena, start, "unknown escape sequence");
            return second;
        }
    }
    return 0;
}

fn u32 scan_punct(module::Module* m, u32 start) {
    u8 c = m.source[start];
    u32 pos = start + 1;
    token::TokenKind kind = token::TokenKind::ERROR;
    switch(c) {
        case '(': { kind = token::TokenKind::LParen; }
        case ')': { kind = token::TokenKind::RParen; }
        case '{': { kind = token::TokenKind::LBrace; }
        case '}': { kind = token::TokenKind::RBrace; }
        case '[': { kind = token::TokenKind::LBracket; }
        case ']': { kind = token::TokenKind::RBracket; }
        case ',': { kind = token::TokenKind::Comma; }
        case ';': { kind = token::TokenKind::Semi; }
        case '~': { kind = token::TokenKind::Tilde; }
        case ':': {
            kind = token::TokenKind::Colon;
            if(pos < (u32)m.source.len && m.source[pos] == ':') { kind = token::TokenKind::ColonColon; pos += 1; }
        }
        case '.': {
            kind = token::TokenKind::Dot;
            if(pos < (u32)m.source.len && m.source[pos] == '.') {
                kind = token::TokenKind::DotDot;
                pos += 1;
                if(pos < (u32)m.source.len && m.source[pos] == '.') {
                    kind = token::TokenKind::DotDotDot;
                    pos += 1;
                }
            }
        }
        case '+': { kind = (token::TokenKind)peek_eq(m, &pos, (u16)token::TokenKind::Plus, (u16)token::TokenKind::PlusEq); }
        case '-': { kind = (token::TokenKind)peek_eq(m, &pos, (u16)token::TokenKind::Minus, (u16)token::TokenKind::MinusEq); }
        case '*': { kind = (token::TokenKind)peek_eq(m, &pos, (u16)token::TokenKind::Star, (u16)token::TokenKind::StarEq); }
        case '/': { kind = (token::TokenKind)peek_eq(m, &pos, (u16)token::TokenKind::Slash, (u16)token::TokenKind::SlashEq); }
        case '%': { kind = (token::TokenKind)peek_eq(m, &pos, (u16)token::TokenKind::Percent, (u16)token::TokenKind::PercentEq); }
        case '^': { kind = (token::TokenKind)peek_eq(m, &pos, (u16)token::TokenKind::Caret, (u16)token::TokenKind::CaretEq); }
        case '=': { kind = (token::TokenKind)peek_eq(m, &pos, (u16)token::TokenKind::Eq, (u16)token::TokenKind::EqEq); }
        case '!': { kind = (token::TokenKind)peek_eq(m, &pos, (u16)token::TokenKind::Bang, (u16)token::TokenKind::BangEq); }
        case '&': {
            kind = token::TokenKind::Amp;
            if(pos < (u32)m.source.len && m.source[pos] == '&') { kind = token::TokenKind::AmpAmp; pos += 1; }
            else if(pos < (u32)m.source.len && m.source[pos] == '=') { kind = token::TokenKind::AmpEq; pos += 1; }
        }
        case '|': {
            kind = token::TokenKind::Pipe;
            if(pos < (u32)m.source.len && m.source[pos] == '|') { kind = token::TokenKind::PipePipe; pos += 1; }
            else if(pos < (u32)m.source.len && m.source[pos] == '=') { kind = token::TokenKind::PipeEq; pos += 1; }
        }
        case '<': {
            kind = token::TokenKind::LT;
            if(pos < (u32)m.source.len && m.source[pos] == '<') { kind = token::TokenKind::LShift; pos += 1; }
            else if(pos < (u32)m.source.len && m.source[pos] == '=') { kind = token::TokenKind::LTEQ; pos += 1; }
        }
        case '>': {
            kind = token::TokenKind::GT;
            if(pos < (u32)m.source.len && m.source[pos] == '>') { kind = token::TokenKind::RShift; pos += 1; }
            else if(pos < (u32)m.source.len && m.source[pos] == '=') { kind = token::TokenKind::GTEQ; pos += 1; }
        }
        else { diag::report(&m.diag, m.arena, start, "unexpected character"); }
    }
    emit_token(m, kind, start, 0);
    return pos;
}

fn u16 peek_eq(module::Module* m, u32* pos_inout, u16 plain, u16 with_eq) {
    if(*pos_inout < (u32)m.source.len && m.source[*pos_inout] == '=') {
        *pos_inout += 1;
        return with_eq;
    }
    return plain;
}

enum CharClass : u8 {
    Alpha = 1,
    Digit = 2,
    ID_Start = 4,
    ID_Cont = 8,
    Hex = 16,
    Whitespace = 32,
    NewLine = 64,
}

CharClass[256] CHAR_CLASS;
bool char_class_init = false;

fn void build_char_class_table() {
    CharClass alpha_hex = (CharClass)((u8)CharClass::Alpha | (u8)CharClass::ID_Start | (u8)CharClass::ID_Cont | (u8)CharClass::Hex);
    CharClass alpha     = (CharClass)((u8)CharClass::Alpha | (u8)CharClass::ID_Start | (u8)CharClass::ID_Cont);
    CharClass digit     = (CharClass)((u8)CharClass::Digit | (u8)CharClass::ID_Cont | (u8)CharClass::Hex);
    CharClass id_only   = (CharClass)((u8)CharClass::ID_Start | (u8)CharClass::ID_Cont);
    sys::memset(CHAR_CLASS, 0, 256);
    for(u64 i = 'A'; i <= 'F'; i += 1) { CHAR_CLASS[i] = alpha_hex; }
    for(u64 i = 'G'; i <= 'Z'; i += 1) { CHAR_CLASS[i] = alpha; }
    for(u64 i = 'a'; i <= 'f'; i += 1) { CHAR_CLASS[i] = alpha_hex; }
    for(u64 i = 'g'; i <= 'z'; i += 1) { CHAR_CLASS[i] = alpha; }
    for(u64 i = '0'; i <= '9'; i += 1) { CHAR_CLASS[i] = digit; }
    CHAR_CLASS['_']  = id_only;
    CHAR_CLASS[' ']  = CharClass::Whitespace;
    CHAR_CLASS['\t'] = CharClass::Whitespace;
    CHAR_CLASS['\r'] = CharClass::Whitespace;
    CHAR_CLASS['\n'] = CharClass::NewLine;
    char_class_init = true;
}
