import testing;
import token;
import arena;
import sys;

fn i32 is_keyword_basic(arena::Arena* a, const u8[]m) {
    if (!testing::expect_true(token::is_keyword(token::TokenKind::FN), m)) { return -1; }
    if (!testing::expect_true(token::is_keyword(token::TokenKind::I32), m)) { return -2; }
    if (!testing::expect_true(token::is_keyword(token::TokenKind::TYPE_INFO), m)) { return -3; }
    if (!testing::expect_true(token::is_keyword(token::TokenKind::COMPTIME), m)) { return -4; }
    if (!testing::expect_false(token::is_keyword(token::TokenKind::Plus), m)) { return -5; }
    if (!testing::expect_false(token::is_keyword(token::TokenKind::EOF), m)) { return -6; }
    if (!testing::expect_false(token::is_keyword(token::TokenKind::IntLit), m)) { return -7; }
    if (!testing::expect_false(token::is_keyword(token::TokenKind::Ident), m)) { return -8; }
    return 0;
}

fn i32 is_keyword_boundaries(arena::Arena* a, const u8[]m) {
    if (!testing::expect_true(token::is_keyword(token::TokenKind::KW_FIRST), m)) { return -1; }
    if (!testing::expect_true(token::is_keyword(token::TokenKind::KW_LAST), m)) { return -2; }
    return 0;
}

fn i32 is_type_keyword_basic(arena::Arena* a, const u8[]m) {
    if (!testing::expect_true(token::is_type_keyword(token::TokenKind::I8), m)) { return -1; }
    if (!testing::expect_true(token::is_type_keyword(token::TokenKind::U64), m)) { return -2; }
    if (!testing::expect_true(token::is_type_keyword(token::TokenKind::F32), m)) { return -3; }
    if (!testing::expect_true(token::is_type_keyword(token::TokenKind::BOOL), m)) { return -4; }
    if (!testing::expect_true(token::is_type_keyword(token::TokenKind::VOID), m)) { return -5; }
    if (!testing::expect_true(token::is_type_keyword(token::TokenKind::TYPE), m)) { return -6; }
    if (!testing::expect_false(token::is_type_keyword(token::TokenKind::FN), m)) { return -7; }
    if (!testing::expect_false(token::is_type_keyword(token::TokenKind::STRUCT), m)) { return -8; }
    if (!testing::expect_false(token::is_type_keyword(token::TokenKind::IF), m)) { return -9; }
    if (!testing::expect_false(token::is_type_keyword(token::TokenKind::Plus), m)) { return -10; }
    return 0;
}

fn i32 is_type_keyword_boundaries(arena::Arena* a, const u8[]m) {
    if (!testing::expect_true(token::is_type_keyword(token::TokenKind::KW_TYPE_FIRST), m)) { return -1; }
    if (!testing::expect_true(token::is_type_keyword(token::TokenKind::KW_TYPE_LAST), m)) { return -2; }
    return 0;
}

fn i32 is_literal_basic(arena::Arena* a, const u8[]m) {
    if (!testing::expect_true(token::is_literal(token::TokenKind::IntLit), m)) { return -1; }
    if (!testing::expect_true(token::is_literal(token::TokenKind::FloatLit), m)) { return -2; }
    if (!testing::expect_true(token::is_literal(token::TokenKind::CharLit), m)) { return -3; }
    if (!testing::expect_true(token::is_literal(token::TokenKind::StringLit), m)) { return -4; }
    if (!testing::expect_true(token::is_literal(token::TokenKind::Ident), m)) { return -5; }
    if (!testing::expect_false(token::is_literal(token::TokenKind::EOF), m)) { return -6; }
    if (!testing::expect_false(token::is_literal(token::TokenKind::ERROR), m)) { return -7; }
    if (!testing::expect_false(token::is_literal(token::TokenKind::FN), m)) { return -8; }
    if (!testing::expect_false(token::is_literal(token::TokenKind::Plus), m)) { return -9; }
    return 0;
}

fn i32 keywords_table_size(arena::Arena* a, const u8[]m) {
    if (!testing::expect_gt(token::KEYWORDS.len, (u64)40, m)) { return -1; }
    if (!testing::expect_lt(token::KEYWORDS.len, (u64)100, m)) { return -2; }
    return 0;
}

fn i32 keywords_table_entries(arena::Arena* a, const u8[]m) {
    if (!testing::expect_eq(token::KEYWORDS[0].bytes, "i8", m)) { return -1; }
    if (!testing::expect_eq((u32)token::KEYWORDS[0].kind, (u32)token::TokenKind::I8, m)) { return -2; }
    u64 last = token::KEYWORDS.len - 1;
    if (!testing::expect_eq(token::KEYWORDS[last].bytes, "type_info", m)) { return -3; }
    if (!testing::expect_eq((u32)token::KEYWORDS[last].kind, (u32)token::TokenKind::TYPE_INFO, m)) { return -4; }
    return 0;
}

fn i32 keywords_table_nonempty_bytes(arena::Arena* a, const u8[]m) {
    for (u64 i = 0; i < token::KEYWORDS.len; i += 1) {
        if (token::KEYWORDS[i].bytes.len == 0) {
            sys::printf("entry %lu has empty bytes\n", i);
            return -1;
        }
        if (token::KEYWORDS[i].bytes.ptr == null) {
            sys::printf("entry %lu has null bytes ptr\n", i);
            return -2;
        }
    }
    return 0;
}

fn i32 main() {
    testing::init();
    const u8[] suite = "Token Tests";
    testing::add(suite, "is_keyword_basic", &is_keyword_basic);
    testing::add(suite, "is_keyword_boundaries", &is_keyword_boundaries);
    testing::add(suite, "is_type_keyword_basic", &is_type_keyword_basic);
    testing::add(suite, "is_type_keyword_boundaries", &is_type_keyword_boundaries);
    testing::add(suite, "is_literal_basic", &is_literal_basic);
    testing::add(suite, "keywords_table_size", &keywords_table_size);
    testing::add(suite, "keywords_table_entries", &keywords_table_entries);
    testing::add(suite, "keywords_table_nonempty_bytes", &keywords_table_nonempty_bytes);
    return testing::run();
}
