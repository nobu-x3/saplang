import testing;
import arena;
import diag;
import interner;
import module;
import scanner;
import symbol;
import sys;
import token;

// ---------- helpers ----------

const u64 BUCKET_COUNT = 64;

fn void load_kw_local(interner::Interner* it) {
    for(u64 i = 0; i < token::KEYWORDS.len; i += 1) {
        symbol::Symbol* sym = interner::intern(it, token::KEYWORDS[i].bytes);
        sym.keyword_kind = (u16)token::KEYWORDS[i].kind;
    }
}

fn module::Module* prepare(arena::Arena* a, u8[] src) {
    interner::Interner* it = arena::alloc(a, sizeof(interner::Interner));
    u64 nbytes = BUCKET_COUNT * sizeof(symbol::Symbol*);
    void* raw = arena::alloc(a, nbytes);
    sys::memset(raw, 0, nbytes);
    it.slab_arena = a;
    it.slab = {null, 0};
    it.slab_cap = 0;
    it.buckets = {(symbol::Symbol**)raw, BUCKET_COUNT};
    it.entry_count = 0;
    load_kw_local(it);

    module::Module* m = arena::alloc(a, sizeof(module::Module));
    m.name = null;
    m.source = src;
    m.line_starts = {null, 0};
    m.tokens = {null, 0};
    m.tokens_cap = 0;
    m.literal_pool = {null, 0};
    m.literal_pool_cap = 0;
    m.interner = it;
    m.arena = a;
    m.diag.entries = {null, 0};
    m.diag.entries_cap = 0;
    return m;
}

fn module::Module* scan_src(arena::Arena* a, u8[] src) {
    module::Module* m = prepare(a, src);
    scanner::scan(m);
    return m;
}

fn bool kind_eq(module::Module* m, u64 i, token::TokenKind want, u8[] msg) {
    return testing::expect_eq((u16)m.tokens[i].kind, (u16)want, msg);
}

fn u8[] string_bytes(module::Module* m, u64 i) {
    token::Token* t = &m.tokens[i];
    u8[] s = {&m.literal_pool[t.data.bytes.off], (u64)t.data.bytes.len};
    return s;
}

fn u8[] ident_text(module::Module* m, u64 i) {
    return interner::symbol_str(m.tokens[i].data.sym, m.interner);
}

// ---------- empty / whitespace / comments ----------

fn i32 empty_source_emits_only_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    u8[] empty = {null, 0};
    module::Module* m = scan_src(&local, empty);
    if(!testing::expect_eq(m.tokens.len, (u64)1, msg)) { return -1; }
    if(!kind_eq(m, 0, token::TokenKind::EOF, msg)) { return -2; }
    return 0;
}

fn i32 only_spaces(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "     ");
    if(!testing::expect_eq(m.tokens.len, (u64)1, msg)) { return -1; }
    if(!kind_eq(m, 0, token::TokenKind::EOF, msg)) { return -2; }
    return 0;
}

fn i32 only_tabs(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "\t\t\t");
    if(!testing::expect_eq(m.tokens.len, (u64)1, msg)) { return -1; }
    return 0;
}

fn i32 only_newlines(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "\n\n\n");
    if(!testing::expect_eq(m.tokens.len, (u64)1, msg)) { return -1; }
    return 0;
}

fn i32 only_carriage_returns(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "\r\r");
    if(!testing::expect_eq(m.tokens.len, (u64)1, msg)) { return -1; }
    return 0;
}

fn i32 mixed_whitespace(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, " \t \r \n ");
    if(!testing::expect_eq(m.tokens.len, (u64)1, msg)) { return -1; }
    return 0;
}

fn i32 line_comment_to_newline(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "// hello world\n");
    if(!testing::expect_eq(m.tokens.len, (u64)1, msg)) { return -1; }
    return 0;
}

fn i32 line_comment_to_eof_no_newline(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "// no newline at end");
    if(!testing::expect_eq(m.tokens.len, (u64)1, msg)) { return -1; }
    return 0;
}

fn i32 token_after_line_comment(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "// foo\nbar");
    if(!testing::expect_eq(m.tokens.len, (u64)2, msg)) { return -1; }
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -2; }
    if(!testing::expect_eq(ident_text(m, 0), "bar", msg)) { return -3; }
    return 0;
}

fn i32 comment_between_tokens(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "foo // mid-line\nbar");
    if(!testing::expect_eq(m.tokens.len, (u64)3, msg)) { return -1; }
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -2; }
    if(!kind_eq(m, 1, token::TokenKind::Ident, msg)) { return -3; }
    if(!kind_eq(m, 2, token::TokenKind::EOF, msg)) { return -4; }
    return 0;
}

fn i32 multiple_comments_in_a_row(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "// one\n// two\n// three\nx");
    if(!testing::expect_eq(m.tokens.len, (u64)2, msg)) { return -1; }
    if(!testing::expect_eq(ident_text(m, 0), "x", msg)) { return -2; }
    return 0;
}

// ---------- identifiers ----------

fn i32 ident_single_letter(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "x");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    if(!testing::expect_eq(ident_text(m, 0), "x", msg)) { return -2; }
    return 0;
}

fn i32 ident_single_uppercase(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "X");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    if(!testing::expect_eq(ident_text(m, 0), "X", msg)) { return -2; }
    return 0;
}

fn i32 ident_starts_with_underscore(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "_foo");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    if(!testing::expect_eq(ident_text(m, 0), "_foo", msg)) { return -2; }
    return 0;
}

fn i32 ident_lone_underscore(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "_");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    if(!testing::expect_eq(ident_text(m, 0), "_", msg)) { return -2; }
    return 0;
}

fn i32 ident_with_digits(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "foo123");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    if(!testing::expect_eq(ident_text(m, 0), "foo123", msg)) { return -2; }
    return 0;
}

fn i32 ident_camelcase(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "FooBarBaz");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    if(!testing::expect_eq(ident_text(m, 0), "FooBarBaz", msg)) { return -2; }
    return 0;
}

fn i32 ident_with_inner_underscore(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "foo_bar_baz");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    if(!testing::expect_eq(ident_text(m, 0), "foo_bar_baz", msg)) { return -2; }
    return 0;
}

fn i32 ident_double_underscore(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "__init__");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    if(!testing::expect_eq(ident_text(m, 0), "__init__", msg)) { return -2; }
    return 0;
}

fn i32 ident_long_no_truncation(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    u8[1024] buf;
    for(u64 i = 0; i < 1024; i += 1) { buf[i] = 'a'; }
    u8[] src = {&buf[0], 1024};
    module::Module* m = scan_src(&local, src);
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    if(!testing::expect_eq((u64)m.tokens[0].data.sym.len, (u64)1024, msg)) { return -2; }
    return 0;
}

fn i32 two_adjacent_idents_separated_by_space(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "foo bar");
    if(!testing::expect_eq(m.tokens.len, (u64)3, msg)) { return -1; }
    if(!testing::expect_eq(ident_text(m, 0), "foo", msg)) { return -2; }
    if(!testing::expect_eq(ident_text(m, 1), "bar", msg)) { return -3; }
    return 0;
}

fn i32 same_ident_interned_once(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "foo foo");
    if(!testing::expect_eq((void*)m.tokens[0].data.sym, (void*)m.tokens[1].data.sym, msg)) { return -1; }
    return 0;
}

// ---------- keywords (all of them) ----------

fn i32 all_keywords_recognized(arena::Arena* a, u8[] msg) {
    for(u64 i = 0; i < token::KEYWORDS.len; i += 1) {
        arena::Arena local = {4096, null};
        module::Module* m = scan_src(&local, token::KEYWORDS[i].bytes);
        if((u16)m.tokens[0].kind != (u16)token::KEYWORDS[i].kind) {
            sys::printf("[____FAIL____] keyword '%.*s' scanned as kind %u, expected %u\n",
                (i32)token::KEYWORDS[i].bytes.len, token::KEYWORDS[i].bytes.ptr,
                (u32)m.tokens[0].kind, (u32)token::KEYWORDS[i].kind);
            return -1;
        }
        if((u16)m.tokens[1].kind != (u16)token::TokenKind::EOF) {
            return -2;
        }
    }
    return 0;
}

fn i32 keyword_prefix_iffy_is_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "iffy");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    return 0;
}

fn i32 keyword_prefix_nullable_is_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "nullable");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    return 0;
}

fn i32 keyword_prefix_sizeofx_is_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "sizeofx");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    return 0;
}

fn i32 keyword_prefix_fnx_is_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "fnx");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    return 0;
}

fn i32 keyword_prefix_comptimex_is_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "comptimex");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    return 0;
}

fn i32 keyword_with_trailing_digit_is_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "if2");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    return 0;
}

fn i32 keyword_with_leading_underscore_is_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "_if");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    return 0;
}

fn i32 keyword_opaque_recognized(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "opaque");
    if(!kind_eq(m, 0, token::TokenKind::OPAQUE, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::EOF, msg)) { return -2; }
    return 0;
}

fn i32 keyword_opaque_in_extern_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "extern { opaque struct FILE; }");
    if(!kind_eq(m, 0, token::TokenKind::EXTERN, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::LBrace, msg)) { return -2; }
    if(!kind_eq(m, 2, token::TokenKind::OPAQUE, msg)) { return -3; }
    if(!kind_eq(m, 3, token::TokenKind::STRUCT, msg)) { return -4; }
    if(!kind_eq(m, 4, token::TokenKind::Ident, msg)) { return -5; }
    if(!kind_eq(m, 5, token::TokenKind::Semi, msg)) { return -6; }
    if(!kind_eq(m, 6, token::TokenKind::RBrace, msg)) { return -7; }
    return 0;
}

fn i32 keyword_opaque_prefix_opaquex_is_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "opaquex");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    return 0;
}

fn i32 keyword_opaque_suffix_xopaque_is_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "xopaque");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    return 0;
}

fn i32 keyword_opaque_with_trailing_digit_is_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "opaque1");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    return 0;
}

fn i32 keyword_opaque_with_leading_underscore_is_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "_opaque");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    return 0;
}

fn i32 keyword_opaque_uppercase_is_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "OPAQUE");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    return 0;
}

// ---------- integer literals ----------

fn i32 int_zero(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "0");
    if(!kind_eq(m, 0, token::TokenKind::IntLit, msg)) { return -1; }
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)0, msg)) { return -2; }
    return 0;
}

fn i32 int_one(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "1");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)1, msg)) { return -1; }
    return 0;
}

fn i32 int_nine(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "9");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)9, msg)) { return -1; }
    return 0;
}

fn i32 int_multi_digit(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "12345");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)12345, msg)) { return -1; }
    return 0;
}

fn i32 int_with_underscores(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "1_000_000");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)1000000, msg)) { return -1; }
    return 0;
}

fn i32 int_consecutive_underscores(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "1__2");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)12, msg)) { return -1; }
    return 0;
}

fn i32 int_hex_lower(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "0x1a3f");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)0x1a3f, msg)) { return -1; }
    return 0;
}

fn i32 int_hex_upper(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "0XDEAD");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)0xdead, msg)) { return -1; }
    return 0;
}

fn i32 int_hex_zero(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "0x0");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)0, msg)) { return -1; }
    return 0;
}

fn i32 int_hex_with_underscores(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "0xDE_AD_BE_EF");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)0xdeadbeef, msg)) { return -1; }
    return 0;
}

fn i32 int_hex_mixed_case(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "0xAbCdEf");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)0xabcdef, msg)) { return -1; }
    return 0;
}

fn i32 int_binary_lower(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "0b0101");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)5, msg)) { return -1; }
    return 0;
}

fn i32 int_binary_upper(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "0B1111");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)15, msg)) { return -1; }
    return 0;
}

fn i32 int_binary_zero(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "0b0");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)0, msg)) { return -1; }
    return 0;
}

fn i32 int_binary_with_underscores(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "0b0101_0000");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)80, msg)) { return -1; }
    return 0;
}

fn i32 int_max_u64(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "0xFFFFFFFFFFFFFFFF");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)0xFFFFFFFFFFFFFFFF, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -2; }
    return 0;
}

fn i32 int_overflow_reports_diag(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "99999999999999999999999");
    if(!kind_eq(m, 0, token::TokenKind::IntLit, msg)) { return -1; }
    if(!testing::expect_gt(m.diag.entries.len, (u64)0, msg)) { return -2; }
    return 0;
}

fn i32 int_range_lexes_as_three_tokens(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "1..4");
    if(!testing::expect_eq(m.tokens.len, (u64)4, msg)) { return -1; }
    if(!kind_eq(m, 0, token::TokenKind::IntLit, msg)) { return -2; }
    if(!kind_eq(m, 1, token::TokenKind::DotDot, msg)) { return -3; }
    if(!kind_eq(m, 2, token::TokenKind::IntLit, msg)) { return -4; }
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)1, msg)) { return -5; }
    if(!testing::expect_eq(m.tokens[2].data.ival, (u64)4, msg)) { return -6; }
    return 0;
}

fn i32 int_followed_by_dotdotdot(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "3...");
    if(!kind_eq(m, 0, token::TokenKind::IntLit, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::DotDotDot, msg)) { return -2; }
    return 0;
}

// ---------- float literals ----------

fn i32 float_pi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "3.14");
    if(!kind_eq(m, 0, token::TokenKind::FloatLit, msg)) { return -1; }
    if(!testing::expect_near(m.tokens[0].data.fval, 3.14, 0.0000001, msg)) { return -2; }
    return 0;
}

fn i32 float_zero_point_zero(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "0.0");
    if(!kind_eq(m, 0, token::TokenKind::FloatLit, msg)) { return -1; }
    if(!testing::expect_eq(m.tokens[0].data.fval, 0.0, msg)) { return -2; }
    return 0;
}

fn i32 float_half(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "0.5");
    if(!kind_eq(m, 0, token::TokenKind::FloatLit, msg)) { return -1; }
    if(!testing::expect_eq(m.tokens[0].data.fval, 0.5, msg)) { return -2; }
    return 0;
}

fn i32 float_many_decimals(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "123.456789");
    if(!kind_eq(m, 0, token::TokenKind::FloatLit, msg)) { return -1; }
    if(!testing::expect_near(m.tokens[0].data.fval, 123.456789, 0.0000001, msg)) { return -2; }
    return 0;
}

fn i32 float_underscores_in_int_part(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "1_000.5");
    if(!kind_eq(m, 0, token::TokenKind::FloatLit, msg)) { return -1; }
    if(!testing::expect_eq(m.tokens[0].data.fval, 1000.5, msg)) { return -2; }
    return 0;
}

fn i32 float_underscores_in_frac_part(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "3.14_159");
    if(!kind_eq(m, 0, token::TokenKind::FloatLit, msg)) { return -1; }
    if(!testing::expect_near(m.tokens[0].data.fval, 3.14159, 0.0000001, msg)) { return -2; }
    return 0;
}

fn i32 float_trailing_dot(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "3.");
    if(!kind_eq(m, 0, token::TokenKind::FloatLit, msg)) { return -1; }
    if(!testing::expect_eq(m.tokens[0].data.fval, 3.0, msg)) { return -2; }
    return 0;
}

fn i32 leading_dot_then_digit_is_not_float(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, ".5");
    if(!kind_eq(m, 0, token::TokenKind::Dot, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::IntLit, msg)) { return -2; }
    return 0;
}

// ---------- char literals ----------

fn i32 char_simple_lowercase(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "'a'");
    if(!kind_eq(m, 0, token::TokenKind::CharLit, msg)) { return -1; }
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)'a', msg)) { return -2; }
    return 0;
}

fn i32 char_simple_digit(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "'5'");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)'5', msg)) { return -1; }
    return 0;
}

fn i32 char_space(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "' '");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)32, msg)) { return -1; }
    return 0;
}

fn i32 char_escape_newline(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "'\\n'");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)10, msg)) { return -1; }
    return 0;
}

fn i32 char_escape_tab(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "'\\t'");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)9, msg)) { return -1; }
    return 0;
}

fn i32 char_escape_return(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "'\\r'");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)13, msg)) { return -1; }
    return 0;
}

fn i32 char_escape_backslash(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "'\\\\'");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)92, msg)) { return -1; }
    return 0;
}

fn i32 char_escape_dquote(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "'\\\"'");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)34, msg)) { return -1; }
    return 0;
}

fn i32 char_escape_squote(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "'\\''");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)39, msg)) { return -1; }
    return 0;
}

fn i32 char_escape_null(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "'\\0'");
    if(!testing::expect_eq(m.tokens[0].data.ival, (u64)0, msg)) { return -1; }
    return 0;
}

fn i32 char_unknown_escape_reports_diag(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "'\\q'");
    if(!testing::expect_gt(m.diag.entries.len, (u64)0, msg)) { return -1; }
    return 0;
}

fn i32 char_multi_emits_error(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "'ab'");
    if(!kind_eq(m, 0, token::TokenKind::ERROR, msg)) { return -1; }
    if(!testing::expect_gt(m.diag.entries.len, (u64)0, msg)) { return -2; }
    return 0;
}

fn i32 char_unterminated_emits_error(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "'a");
    if(!kind_eq(m, 0, token::TokenKind::ERROR, msg)) { return -1; }
    if(!testing::expect_gt(m.diag.entries.len, (u64)0, msg)) { return -2; }
    return 0;
}

fn i32 char_eof_after_open_quote(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "'");
    if(!kind_eq(m, 0, token::TokenKind::ERROR, msg)) { return -1; }
    if(!testing::expect_gt(m.diag.entries.len, (u64)0, msg)) { return -2; }
    return 0;
}

// ---------- string literals ----------

fn i32 string_empty(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "\"\"");
    if(!kind_eq(m, 0, token::TokenKind::StringLit, msg)) { return -1; }
    if(!testing::expect_eq((u64)m.tokens[0].data.bytes.len, (u64)0, msg)) { return -2; }
    return 0;
}

fn i32 string_hello(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "\"hello\"");
    if(!kind_eq(m, 0, token::TokenKind::StringLit, msg)) { return -1; }
    if(!testing::expect_eq(string_bytes(m, 0), "hello", msg)) { return -2; }
    return 0;
}

fn i32 string_with_newline_escape(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "\"a\\nb\"");
    u8[] want = "a\nb";
    if(!testing::expect_eq(string_bytes(m, 0), want, msg)) { return -1; }
    return 0;
}

fn i32 string_with_tab_escape(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "\"x\\ty\"");
    u8[] want = "x\ty";
    if(!testing::expect_eq(string_bytes(m, 0), want, msg)) { return -1; }
    return 0;
}

fn i32 string_with_return_escape(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "\"x\\ry\"");
    u8[] want = "x\ry";
    if(!testing::expect_eq(string_bytes(m, 0), want, msg)) { return -1; }
    return 0;
}

fn i32 string_with_backslash_escape(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "\"x\\\\y\"");
    u8[] want = "x\\y";
    if(!testing::expect_eq(string_bytes(m, 0), want, msg)) { return -1; }
    return 0;
}

fn i32 string_with_dquote_escape(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "\"x\\\"y\"");
    u8[] want = "x\"y";
    if(!testing::expect_eq(string_bytes(m, 0), want, msg)) { return -1; }
    return 0;
}

fn i32 string_with_squote_escape(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "\"x\\'y\"");
    u8[] want = "x'y";
    if(!testing::expect_eq(string_bytes(m, 0), want, msg)) { return -1; }
    return 0;
}

fn i32 string_with_embedded_null(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "\"a\\0b\"");
    if(!testing::expect_eq((u64)m.tokens[0].data.bytes.len, (u64)3, msg)) { return -1; }
    u8[] got = string_bytes(m, 0);
    if(!testing::expect_eq((u64)got.ptr[0], (u64)'a', msg)) { return -2; }
    if(!testing::expect_eq((u64)got.ptr[1], (u64)0, msg)) { return -3; }
    if(!testing::expect_eq((u64)got.ptr[2], (u64)'b', msg)) { return -4; }
    return 0;
}

fn i32 string_unterminated_reports_diag(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "\"hello");
    if(!testing::expect_gt(m.diag.entries.len, (u64)0, msg)) { return -1; }
    return 0;
}

fn i32 string_unknown_escape_reports_diag(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "\"x\\qy\"");
    if(!testing::expect_gt(m.diag.entries.len, (u64)0, msg)) { return -1; }
    return 0;
}

fn i32 string_two_in_a_row_use_distinct_pool_offsets(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "\"hi\" \"there\"");
    if(!testing::expect_eq((u32)m.tokens[0].data.bytes.off, (u32)0, msg)) { return -1; }
    if(!testing::expect_eq((u32)m.tokens[0].data.bytes.len, (u32)2, msg)) { return -2; }
    if(!testing::expect_eq((u32)m.tokens[1].data.bytes.off, (u32)2, msg)) { return -3; }
    if(!testing::expect_eq((u32)m.tokens[1].data.bytes.len, (u32)5, msg)) { return -4; }
    if(!testing::expect_eq(string_bytes(m, 0), "hi", msg)) { return -5; }
    if(!testing::expect_eq(string_bytes(m, 1), "there", msg)) { return -6; }
    return 0;
}

// ---------- punctuation ----------

fn i32 punct_lparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "(");
    if(!kind_eq(m, 0, token::TokenKind::LParen, msg)) { return -1; }
    return 0;
}

fn i32 punct_rparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, ")");
    if(!kind_eq(m, 0, token::TokenKind::RParen, msg)) { return -1; }
    return 0;
}

fn i32 punct_lbrace(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "{");
    if(!kind_eq(m, 0, token::TokenKind::LBrace, msg)) { return -1; }
    return 0;
}

fn i32 punct_rbrace(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "}");
    if(!kind_eq(m, 0, token::TokenKind::RBrace, msg)) { return -1; }
    return 0;
}

fn i32 punct_lbracket(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "[");
    if(!kind_eq(m, 0, token::TokenKind::LBracket, msg)) { return -1; }
    return 0;
}

fn i32 punct_rbracket(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "]");
    if(!kind_eq(m, 0, token::TokenKind::RBracket, msg)) { return -1; }
    return 0;
}

fn i32 punct_comma(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, ",");
    if(!kind_eq(m, 0, token::TokenKind::Comma, msg)) { return -1; }
    return 0;
}

fn i32 punct_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, ";");
    if(!kind_eq(m, 0, token::TokenKind::Semi, msg)) { return -1; }
    return 0;
}

fn i32 punct_colon_single(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, ":");
    if(!kind_eq(m, 0, token::TokenKind::Colon, msg)) { return -1; }
    return 0;
}

fn i32 punct_colon_colon(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "::");
    if(!testing::expect_eq(m.tokens.len, (u64)2, msg)) { return -1; }
    if(!kind_eq(m, 0, token::TokenKind::ColonColon, msg)) { return -2; }
    return 0;
}

fn i32 punct_dot_single(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, ".");
    if(!kind_eq(m, 0, token::TokenKind::Dot, msg)) { return -1; }
    return 0;
}

fn i32 punct_dot_dot(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "..");
    if(!testing::expect_eq(m.tokens.len, (u64)2, msg)) { return -1; }
    if(!kind_eq(m, 0, token::TokenKind::DotDot, msg)) { return -2; }
    return 0;
}

fn i32 punct_dot_dot_dot(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "...");
    if(!testing::expect_eq(m.tokens.len, (u64)2, msg)) { return -1; }
    if(!kind_eq(m, 0, token::TokenKind::DotDotDot, msg)) { return -2; }
    return 0;
}

fn i32 punct_tilde(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "~");
    if(!kind_eq(m, 0, token::TokenKind::Tilde, msg)) { return -1; }
    return 0;
}

// ---------- operators (plain + compound) ----------

fn i32 op_plus(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "+");
    if(!kind_eq(m, 0, token::TokenKind::Plus, msg)) { return -1; }
    return 0;
}

fn i32 op_plus_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "+=");
    if(!kind_eq(m, 0, token::TokenKind::PlusEq, msg)) { return -1; }
    return 0;
}

fn i32 op_minus(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "-");
    if(!kind_eq(m, 0, token::TokenKind::Minus, msg)) { return -1; }
    return 0;
}

fn i32 op_minus_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "-=");
    if(!kind_eq(m, 0, token::TokenKind::MinusEq, msg)) { return -1; }
    return 0;
}

fn i32 op_star(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "*");
    if(!kind_eq(m, 0, token::TokenKind::Star, msg)) { return -1; }
    return 0;
}

fn i32 op_star_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "*=");
    if(!kind_eq(m, 0, token::TokenKind::StarEq, msg)) { return -1; }
    return 0;
}

fn i32 op_slash(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "/");
    if(!kind_eq(m, 0, token::TokenKind::Slash, msg)) { return -1; }
    return 0;
}

fn i32 op_slash_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "/=");
    if(!kind_eq(m, 0, token::TokenKind::SlashEq, msg)) { return -1; }
    return 0;
}

fn i32 op_percent(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "%");
    if(!kind_eq(m, 0, token::TokenKind::Percent, msg)) { return -1; }
    return 0;
}

fn i32 op_percent_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "%=");
    if(!kind_eq(m, 0, token::TokenKind::PercentEq, msg)) { return -1; }
    return 0;
}

fn i32 op_caret(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "^");
    if(!kind_eq(m, 0, token::TokenKind::Caret, msg)) { return -1; }
    return 0;
}

fn i32 op_caret_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "^=");
    if(!kind_eq(m, 0, token::TokenKind::CaretEq, msg)) { return -1; }
    return 0;
}

fn i32 op_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "=");
    if(!kind_eq(m, 0, token::TokenKind::Eq, msg)) { return -1; }
    return 0;
}

fn i32 op_eq_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "==");
    if(!kind_eq(m, 0, token::TokenKind::EqEq, msg)) { return -1; }
    return 0;
}

fn i32 op_bang(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "!");
    if(!kind_eq(m, 0, token::TokenKind::Bang, msg)) { return -1; }
    return 0;
}

fn i32 op_bang_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "!=");
    if(!kind_eq(m, 0, token::TokenKind::BangEq, msg)) { return -1; }
    return 0;
}

fn i32 op_amp(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "&");
    if(!kind_eq(m, 0, token::TokenKind::Amp, msg)) { return -1; }
    return 0;
}

fn i32 op_amp_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "&=");
    if(!kind_eq(m, 0, token::TokenKind::AmpEq, msg)) { return -1; }
    return 0;
}

fn i32 op_amp_amp(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "&&");
    if(!kind_eq(m, 0, token::TokenKind::AmpAmp, msg)) { return -1; }
    return 0;
}

fn i32 op_pipe(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "|");
    if(!kind_eq(m, 0, token::TokenKind::Pipe, msg)) { return -1; }
    return 0;
}

fn i32 op_pipe_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "|=");
    if(!kind_eq(m, 0, token::TokenKind::PipeEq, msg)) { return -1; }
    return 0;
}

fn i32 op_pipe_pipe(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "||");
    if(!kind_eq(m, 0, token::TokenKind::PipePipe, msg)) { return -1; }
    return 0;
}

fn i32 op_lt(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "<");
    if(!kind_eq(m, 0, token::TokenKind::LT, msg)) { return -1; }
    return 0;
}

fn i32 op_lt_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "<=");
    if(!kind_eq(m, 0, token::TokenKind::LTEQ, msg)) { return -1; }
    return 0;
}

fn i32 op_lshift(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "<<");
    if(!kind_eq(m, 0, token::TokenKind::LShift, msg)) { return -1; }
    return 0;
}

fn i32 op_gt(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, ">");
    if(!kind_eq(m, 0, token::TokenKind::GT, msg)) { return -1; }
    return 0;
}

fn i32 op_gt_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, ">=");
    if(!kind_eq(m, 0, token::TokenKind::GTEQ, msg)) { return -1; }
    return 0;
}

fn i32 op_rshift(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, ">>");
    if(!kind_eq(m, 0, token::TokenKind::RShift, msg)) { return -1; }
    return 0;
}

// ---------- operator disambiguation / greediness ----------

fn i32 plus_space_eq_lexes_as_two(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "+ =");
    if(!kind_eq(m, 0, token::TokenKind::Plus, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::Eq, msg)) { return -2; }
    return 0;
}

fn i32 amp_amp_amp_lexes_as_two(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "&&&");
    if(!kind_eq(m, 0, token::TokenKind::AmpAmp, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::Amp, msg)) { return -2; }
    return 0;
}

fn i32 triple_eq_lexes_as_eqeq_then_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "===");
    if(!kind_eq(m, 0, token::TokenKind::EqEq, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::Eq, msg)) { return -2; }
    return 0;
}

fn i32 lshift_eq_lexes_as_lshift_then_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "<<=");
    if(!kind_eq(m, 0, token::TokenKind::LShift, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::Eq, msg)) { return -2; }
    return 0;
}

fn i32 colon_then_colon_only_in_pair(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, ": :");
    if(!kind_eq(m, 0, token::TokenKind::Colon, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::Colon, msg)) { return -2; }
    return 0;
}

fn i32 four_dots_lexes_as_three_then_one(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "....");
    if(!kind_eq(m, 0, token::TokenKind::DotDotDot, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::Dot, msg)) { return -2; }
    return 0;
}

// ---------- position tracking ----------

fn i32 src_pos_at_zero(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "x");
    if(!testing::expect_eq((u32)m.tokens[0].src_pos, (u32)0, msg)) { return -1; }
    return 0;
}

fn i32 src_pos_after_leading_whitespace(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "   x");
    if(!testing::expect_eq((u32)m.tokens[0].src_pos, (u32)3, msg)) { return -1; }
    return 0;
}

fn i32 src_pos_eof_at_end(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "foo");
    u64 last = m.tokens.len - 1;
    if(!kind_eq(m, last, token::TokenKind::EOF, msg)) { return -1; }
    if(!testing::expect_eq((u32)m.tokens[last].src_pos, (u32)3, msg)) { return -2; }
    return 0;
}

fn i32 src_pos_each_token_in_sequence(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "ab cd ef");
    if(!testing::expect_eq((u32)m.tokens[0].src_pos, (u32)0, msg)) { return -1; }
    if(!testing::expect_eq((u32)m.tokens[1].src_pos, (u32)3, msg)) { return -2; }
    if(!testing::expect_eq((u32)m.tokens[2].src_pos, (u32)6, msg)) { return -3; }
    return 0;
}

fn i32 src_pos_across_newline(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "x\ny");
    if(!testing::expect_eq((u32)m.tokens[0].src_pos, (u32)0, msg)) { return -1; }
    if(!testing::expect_eq((u32)m.tokens[1].src_pos, (u32)2, msg)) { return -2; }
    return 0;
}

// ---------- line_starts ----------

fn i32 line_starts_single_line(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "abc");
    if(!testing::expect_eq(m.line_starts.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq((u32)m.line_starts[0], (u32)0, msg)) { return -2; }
    return 0;
}

fn i32 line_starts_two_lines(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "ab\ncd");
    if(!testing::expect_eq(m.line_starts.len, (u64)2, msg)) { return -1; }
    if(!testing::expect_eq((u32)m.line_starts[0], (u32)0, msg)) { return -2; }
    if(!testing::expect_eq((u32)m.line_starts[1], (u32)3, msg)) { return -3; }
    return 0;
}

fn i32 line_starts_trailing_newline(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "ab\n");
    if(!testing::expect_eq(m.line_starts.len, (u64)2, msg)) { return -1; }
    return 0;
}

fn i32 line_starts_empty_source(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    u8[] empty = {null, 0};
    module::Module* m = scan_src(&local, empty);
    if(!testing::expect_eq(m.line_starts.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq((u32)m.line_starts[0], (u32)0, msg)) { return -2; }
    return 0;
}

fn i32 line_starts_many_lines(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "a\nb\nc\nd");
    if(!testing::expect_eq(m.line_starts.len, (u64)4, msg)) { return -1; }
    if(!testing::expect_eq((u32)m.line_starts[1], (u32)2, msg)) { return -2; }
    if(!testing::expect_eq((u32)m.line_starts[2], (u32)4, msg)) { return -3; }
    if(!testing::expect_eq((u32)m.line_starts[3], (u32)6, msg)) { return -4; }
    return 0;
}

// ---------- error tokens / recovery ----------

fn i32 unknown_char_emits_diag(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "@");
    if(!testing::expect_gt(m.diag.entries.len, (u64)0, msg)) { return -1; }
    return 0;
}

fn i32 unknown_char_advances_position(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "@ x");
    if(!testing::expect_ge(m.tokens.len, (u64)2, msg)) { return -1; }
    u64 last = m.tokens.len - 1;
    if(!kind_eq(m, last, token::TokenKind::EOF, msg)) { return -2; }
    return 0;
}

fn i32 scanner_does_not_loop_forever_on_bad_input(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "@@@");
    u64 last = m.tokens.len - 1;
    if(!kind_eq(m, last, token::TokenKind::EOF, msg)) { return -1; }
    return 0;
}

fn i32 diag_carries_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "    @");
    if(!testing::expect_gt(m.diag.entries.len, (u64)0, msg)) { return -1; }
    if(!testing::expect_eq((u32)m.diag.entries[0].src_pos, (u32)4, msg)) { return -2; }
    return 0;
}

// ---------- token vector grows past initial cap ----------

fn i32 many_tokens_grow_buffer(arena::Arena* a, u8[] msg) {
    arena::Arena local = {16384, null};
    u8[2048] buf;
    for(u64 i = 0; i < 1024; i += 1) {
        buf[i * 2] = '+';
        buf[i * 2 + 1] = ' ';
    }
    u8[] src = {&buf[0], 2048};
    module::Module* m = scan_src(&local, src);
    if(!testing::expect_eq(m.tokens.len, (u64)1025, msg)) { return -1; }
    if(!testing::expect_ge(m.tokens_cap, (u64)1025, msg)) { return -2; }
    return 0;
}

// ---------- integration: realistic snippets ----------

fn i32 snippet_simple_decl(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "i32 x = 0;");
    if(!kind_eq(m, 0, token::TokenKind::I32, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::Ident, msg)) { return -2; }
    if(!kind_eq(m, 2, token::TokenKind::Eq, msg)) { return -3; }
    if(!kind_eq(m, 3, token::TokenKind::IntLit, msg)) { return -4; }
    if(!kind_eq(m, 4, token::TokenKind::Semi, msg)) { return -5; }
    if(!kind_eq(m, 5, token::TokenKind::EOF, msg)) { return -6; }
    return 0;
}

fn i32 snippet_fn_decl(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "fn i32 main() { return 0; }");
    if(!kind_eq(m, 0, token::TokenKind::FN, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::I32, msg)) { return -2; }
    if(!kind_eq(m, 2, token::TokenKind::Ident, msg)) { return -3; }
    if(!kind_eq(m, 3, token::TokenKind::LParen, msg)) { return -4; }
    if(!kind_eq(m, 4, token::TokenKind::RParen, msg)) { return -5; }
    if(!kind_eq(m, 5, token::TokenKind::LBrace, msg)) { return -6; }
    if(!kind_eq(m, 6, token::TokenKind::RETURN, msg)) { return -7; }
    if(!kind_eq(m, 7, token::TokenKind::IntLit, msg)) { return -8; }
    if(!kind_eq(m, 8, token::TokenKind::Semi, msg)) { return -9; }
    if(!kind_eq(m, 9, token::TokenKind::RBrace, msg)) { return -10; }
    if(!kind_eq(m, 10, token::TokenKind::EOF, msg)) { return -11; }
    return 0;
}

fn i32 snippet_import(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "import foo;");
    if(!kind_eq(m, 0, token::TokenKind::IMPORT, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::Ident, msg)) { return -2; }
    if(!testing::expect_eq(ident_text(m, 1), "foo", msg)) { return -3; }
    if(!kind_eq(m, 2, token::TokenKind::Semi, msg)) { return -4; }
    return 0;
}

fn i32 snippet_slice_range(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "arr[1..4]");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::LBracket, msg)) { return -2; }
    if(!kind_eq(m, 2, token::TokenKind::IntLit, msg)) { return -3; }
    if(!kind_eq(m, 3, token::TokenKind::DotDot, msg)) { return -4; }
    if(!kind_eq(m, 4, token::TokenKind::IntLit, msg)) { return -5; }
    if(!kind_eq(m, 5, token::TokenKind::RBracket, msg)) { return -6; }
    return 0;
}

fn i32 snippet_qualified_access(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "foo::bar");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::ColonColon, msg)) { return -2; }
    if(!kind_eq(m, 2, token::TokenKind::Ident, msg)) { return -3; }
    return 0;
}

fn i32 snippet_member_access(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "p.x");
    if(!kind_eq(m, 0, token::TokenKind::Ident, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::Dot, msg)) { return -2; }
    if(!kind_eq(m, 2, token::TokenKind::Ident, msg)) { return -3; }
    return 0;
}

fn i32 snippet_const_float(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "const f64 PI = 3.14;");
    if(!kind_eq(m, 0, token::TokenKind::CONST, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::F64, msg)) { return -2; }
    if(!kind_eq(m, 2, token::TokenKind::Ident, msg)) { return -3; }
    if(!kind_eq(m, 3, token::TokenKind::Eq, msg)) { return -4; }
    if(!kind_eq(m, 4, token::TokenKind::FloatLit, msg)) { return -5; }
    if(!kind_eq(m, 5, token::TokenKind::Semi, msg)) { return -6; }
    return 0;
}

fn i32 snippet_bool_literals(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "true false");
    if(!kind_eq(m, 0, token::TokenKind::TRUE, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::FALSE, msg)) { return -2; }
    return 0;
}

fn i32 snippet_null_undefined(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "null undefined");
    if(!kind_eq(m, 0, token::TokenKind::NULL, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::UNDEFINED, msg)) { return -2; }
    return 0;
}

fn i32 snippet_dense_no_whitespace(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m = scan_src(&local, "1+2*3");
    if(!kind_eq(m, 0, token::TokenKind::IntLit, msg)) { return -1; }
    if(!kind_eq(m, 1, token::TokenKind::Plus, msg)) { return -2; }
    if(!kind_eq(m, 2, token::TokenKind::IntLit, msg)) { return -3; }
    if(!kind_eq(m, 3, token::TokenKind::Star, msg)) { return -4; }
    if(!kind_eq(m, 4, token::TokenKind::IntLit, msg)) { return -5; }
    return 0;
}

// ---------- main ----------

fn i32 main() {
    testing::init();
    u8[] suite = "Scanner Tests";

    // empty / whitespace / comments
    testing::add(suite, "empty_source_emits_only_eof", &empty_source_emits_only_eof);
    testing::add(suite, "only_spaces", &only_spaces);
    testing::add(suite, "only_tabs", &only_tabs);
    testing::add(suite, "only_newlines", &only_newlines);
    testing::add(suite, "only_carriage_returns", &only_carriage_returns);
    testing::add(suite, "mixed_whitespace", &mixed_whitespace);
    testing::add(suite, "line_comment_to_newline", &line_comment_to_newline);
    testing::add(suite, "line_comment_to_eof_no_newline", &line_comment_to_eof_no_newline);
    testing::add(suite, "token_after_line_comment", &token_after_line_comment);
    testing::add(suite, "comment_between_tokens", &comment_between_tokens);
    testing::add(suite, "multiple_comments_in_a_row", &multiple_comments_in_a_row);

    // identifiers
    testing::add(suite, "ident_single_letter", &ident_single_letter);
    testing::add(suite, "ident_single_uppercase", &ident_single_uppercase);
    testing::add(suite, "ident_starts_with_underscore", &ident_starts_with_underscore);
    testing::add(suite, "ident_lone_underscore", &ident_lone_underscore);
    testing::add(suite, "ident_with_digits", &ident_with_digits);
    testing::add(suite, "ident_camelcase", &ident_camelcase);
    testing::add(suite, "ident_with_inner_underscore", &ident_with_inner_underscore);
    testing::add(suite, "ident_double_underscore", &ident_double_underscore);
    testing::add(suite, "ident_long_no_truncation", &ident_long_no_truncation);
    testing::add(suite, "two_adjacent_idents_separated_by_space", &two_adjacent_idents_separated_by_space);
    testing::add(suite, "same_ident_interned_once", &same_ident_interned_once);

    // keywords
    testing::add(suite, "all_keywords_recognized", &all_keywords_recognized);
    testing::add(suite, "keyword_prefix_iffy_is_ident", &keyword_prefix_iffy_is_ident);
    testing::add(suite, "keyword_prefix_nullable_is_ident", &keyword_prefix_nullable_is_ident);
    testing::add(suite, "keyword_prefix_sizeofx_is_ident", &keyword_prefix_sizeofx_is_ident);
    testing::add(suite, "keyword_prefix_fnx_is_ident", &keyword_prefix_fnx_is_ident);
    testing::add(suite, "keyword_prefix_comptimex_is_ident", &keyword_prefix_comptimex_is_ident);
    testing::add(suite, "keyword_with_trailing_digit_is_ident", &keyword_with_trailing_digit_is_ident);
    testing::add(suite, "keyword_with_leading_underscore_is_ident", &keyword_with_leading_underscore_is_ident);
    testing::add(suite, "keyword_opaque_recognized", &keyword_opaque_recognized);
    testing::add(suite, "keyword_opaque_in_extern_block", &keyword_opaque_in_extern_block);
    testing::add(suite, "keyword_opaque_prefix_opaquex_is_ident", &keyword_opaque_prefix_opaquex_is_ident);
    testing::add(suite, "keyword_opaque_suffix_xopaque_is_ident", &keyword_opaque_suffix_xopaque_is_ident);
    testing::add(suite, "keyword_opaque_with_trailing_digit_is_ident", &keyword_opaque_with_trailing_digit_is_ident);
    testing::add(suite, "keyword_opaque_with_leading_underscore_is_ident", &keyword_opaque_with_leading_underscore_is_ident);
    testing::add(suite, "keyword_opaque_uppercase_is_ident", &keyword_opaque_uppercase_is_ident);

    // integer literals
    testing::add(suite, "int_zero", &int_zero);
    testing::add(suite, "int_one", &int_one);
    testing::add(suite, "int_nine", &int_nine);
    testing::add(suite, "int_multi_digit", &int_multi_digit);
    testing::add(suite, "int_with_underscores", &int_with_underscores);
    testing::add(suite, "int_consecutive_underscores", &int_consecutive_underscores);
    testing::add(suite, "int_hex_lower", &int_hex_lower);
    testing::add(suite, "int_hex_upper", &int_hex_upper);
    testing::add(suite, "int_hex_zero", &int_hex_zero);
    testing::add(suite, "int_hex_with_underscores", &int_hex_with_underscores);
    testing::add(suite, "int_hex_mixed_case", &int_hex_mixed_case);
    testing::add(suite, "int_binary_lower", &int_binary_lower);
    testing::add(suite, "int_binary_upper", &int_binary_upper);
    testing::add(suite, "int_binary_zero", &int_binary_zero);
    testing::add(suite, "int_binary_with_underscores", &int_binary_with_underscores);
    testing::add(suite, "int_max_u64", &int_max_u64);
    testing::add(suite, "int_overflow_reports_diag", &int_overflow_reports_diag);
    testing::add(suite, "int_range_lexes_as_three_tokens", &int_range_lexes_as_three_tokens);
    testing::add(suite, "int_followed_by_dotdotdot", &int_followed_by_dotdotdot);

    // float literals
    testing::add(suite, "float_pi", &float_pi);
    testing::add(suite, "float_zero_point_zero", &float_zero_point_zero);
    testing::add(suite, "float_half", &float_half);
    testing::add(suite, "float_many_decimals", &float_many_decimals);
    testing::add(suite, "float_underscores_in_int_part", &float_underscores_in_int_part);
    testing::add(suite, "float_underscores_in_frac_part", &float_underscores_in_frac_part);
    testing::add(suite, "float_trailing_dot", &float_trailing_dot);
    testing::add(suite, "leading_dot_then_digit_is_not_float", &leading_dot_then_digit_is_not_float);

    // char literals
    testing::add(suite, "char_simple_lowercase", &char_simple_lowercase);
    testing::add(suite, "char_simple_digit", &char_simple_digit);
    testing::add(suite, "char_space", &char_space);
    testing::add(suite, "char_escape_newline", &char_escape_newline);
    testing::add(suite, "char_escape_tab", &char_escape_tab);
    testing::add(suite, "char_escape_return", &char_escape_return);
    testing::add(suite, "char_escape_backslash", &char_escape_backslash);
    testing::add(suite, "char_escape_dquote", &char_escape_dquote);
    testing::add(suite, "char_escape_squote", &char_escape_squote);
    testing::add(suite, "char_escape_null", &char_escape_null);
    testing::add(suite, "char_unknown_escape_reports_diag", &char_unknown_escape_reports_diag);
    testing::add(suite, "char_multi_emits_error", &char_multi_emits_error);
    testing::add(suite, "char_unterminated_emits_error", &char_unterminated_emits_error);
    testing::add(suite, "char_eof_after_open_quote", &char_eof_after_open_quote);

    // string literals
    testing::add(suite, "string_empty", &string_empty);
    testing::add(suite, "string_hello", &string_hello);
    testing::add(suite, "string_with_newline_escape", &string_with_newline_escape);
    testing::add(suite, "string_with_tab_escape", &string_with_tab_escape);
    testing::add(suite, "string_with_return_escape", &string_with_return_escape);
    testing::add(suite, "string_with_backslash_escape", &string_with_backslash_escape);
    testing::add(suite, "string_with_dquote_escape", &string_with_dquote_escape);
    testing::add(suite, "string_with_squote_escape", &string_with_squote_escape);
    testing::add(suite, "string_with_embedded_null", &string_with_embedded_null);
    testing::add(suite, "string_unterminated_reports_diag", &string_unterminated_reports_diag);
    testing::add(suite, "string_unknown_escape_reports_diag", &string_unknown_escape_reports_diag);
    testing::add(suite, "string_two_in_a_row_use_distinct_pool_offsets", &string_two_in_a_row_use_distinct_pool_offsets);

    // punctuation
    testing::add(suite, "punct_lparen", &punct_lparen);
    testing::add(suite, "punct_rparen", &punct_rparen);
    testing::add(suite, "punct_lbrace", &punct_lbrace);
    testing::add(suite, "punct_rbrace", &punct_rbrace);
    testing::add(suite, "punct_lbracket", &punct_lbracket);
    testing::add(suite, "punct_rbracket", &punct_rbracket);
    testing::add(suite, "punct_comma", &punct_comma);
    testing::add(suite, "punct_semi", &punct_semi);
    testing::add(suite, "punct_colon_single", &punct_colon_single);
    testing::add(suite, "punct_colon_colon", &punct_colon_colon);
    testing::add(suite, "punct_dot_single", &punct_dot_single);
    testing::add(suite, "punct_dot_dot", &punct_dot_dot);
    testing::add(suite, "punct_dot_dot_dot", &punct_dot_dot_dot);
    testing::add(suite, "punct_tilde", &punct_tilde);

    // operators
    testing::add(suite, "op_plus", &op_plus);
    testing::add(suite, "op_plus_eq", &op_plus_eq);
    testing::add(suite, "op_minus", &op_minus);
    testing::add(suite, "op_minus_eq", &op_minus_eq);
    testing::add(suite, "op_star", &op_star);
    testing::add(suite, "op_star_eq", &op_star_eq);
    testing::add(suite, "op_slash", &op_slash);
    testing::add(suite, "op_slash_eq", &op_slash_eq);
    testing::add(suite, "op_percent", &op_percent);
    testing::add(suite, "op_percent_eq", &op_percent_eq);
    testing::add(suite, "op_caret", &op_caret);
    testing::add(suite, "op_caret_eq", &op_caret_eq);
    testing::add(suite, "op_eq", &op_eq);
    testing::add(suite, "op_eq_eq", &op_eq_eq);
    testing::add(suite, "op_bang", &op_bang);
    testing::add(suite, "op_bang_eq", &op_bang_eq);
    testing::add(suite, "op_amp", &op_amp);
    testing::add(suite, "op_amp_eq", &op_amp_eq);
    testing::add(suite, "op_amp_amp", &op_amp_amp);
    testing::add(suite, "op_pipe", &op_pipe);
    testing::add(suite, "op_pipe_eq", &op_pipe_eq);
    testing::add(suite, "op_pipe_pipe", &op_pipe_pipe);
    testing::add(suite, "op_lt", &op_lt);
    testing::add(suite, "op_lt_eq", &op_lt_eq);
    testing::add(suite, "op_lshift", &op_lshift);
    testing::add(suite, "op_gt", &op_gt);
    testing::add(suite, "op_gt_eq", &op_gt_eq);
    testing::add(suite, "op_rshift", &op_rshift);

    // operator disambiguation
    testing::add(suite, "plus_space_eq_lexes_as_two", &plus_space_eq_lexes_as_two);
    testing::add(suite, "amp_amp_amp_lexes_as_two", &amp_amp_amp_lexes_as_two);
    testing::add(suite, "triple_eq_lexes_as_eqeq_then_eq", &triple_eq_lexes_as_eqeq_then_eq);
    testing::add(suite, "lshift_eq_lexes_as_lshift_then_eq", &lshift_eq_lexes_as_lshift_then_eq);
    testing::add(suite, "colon_then_colon_only_in_pair", &colon_then_colon_only_in_pair);
    testing::add(suite, "four_dots_lexes_as_three_then_one", &four_dots_lexes_as_three_then_one);

    // position tracking
    testing::add(suite, "src_pos_at_zero", &src_pos_at_zero);
    testing::add(suite, "src_pos_after_leading_whitespace", &src_pos_after_leading_whitespace);
    testing::add(suite, "src_pos_eof_at_end", &src_pos_eof_at_end);
    testing::add(suite, "src_pos_each_token_in_sequence", &src_pos_each_token_in_sequence);
    testing::add(suite, "src_pos_across_newline", &src_pos_across_newline);

    // line_starts
    testing::add(suite, "line_starts_single_line", &line_starts_single_line);
    testing::add(suite, "line_starts_two_lines", &line_starts_two_lines);
    testing::add(suite, "line_starts_trailing_newline", &line_starts_trailing_newline);
    testing::add(suite, "line_starts_empty_source", &line_starts_empty_source);
    testing::add(suite, "line_starts_many_lines", &line_starts_many_lines);

    // error / recovery
    testing::add(suite, "unknown_char_emits_diag", &unknown_char_emits_diag);
    testing::add(suite, "unknown_char_advances_position", &unknown_char_advances_position);
    testing::add(suite, "scanner_does_not_loop_forever_on_bad_input", &scanner_does_not_loop_forever_on_bad_input);
    testing::add(suite, "diag_carries_src_pos", &diag_carries_src_pos);

    // growth
    testing::add(suite, "many_tokens_grow_buffer", &many_tokens_grow_buffer);

    // realistic snippets
    testing::add(suite, "snippet_simple_decl", &snippet_simple_decl);
    testing::add(suite, "snippet_fn_decl", &snippet_fn_decl);
    testing::add(suite, "snippet_import", &snippet_import);
    testing::add(suite, "snippet_slice_range", &snippet_slice_range);
    testing::add(suite, "snippet_qualified_access", &snippet_qualified_access);
    testing::add(suite, "snippet_member_access", &snippet_member_access);
    testing::add(suite, "snippet_const_float", &snippet_const_float);
    testing::add(suite, "snippet_bool_literals", &snippet_bool_literals);
    testing::add(suite, "snippet_null_undefined", &snippet_null_undefined);
    testing::add(suite, "snippet_dense_no_whitespace", &snippet_dense_no_whitespace);

    return testing::run();
}
