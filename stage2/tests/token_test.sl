import testing;
import token;
import arena;
import sys;

fn bool has_bit(token::CharClass cc, token::CharClass bit) {
    return ((u8)cc & (u8)bit) != 0;
}

fn i32 is_keyword_basic(arena::Arena* a, u8[] m) {
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

fn i32 is_keyword_boundaries(arena::Arena* a, u8[] m) {
    if (!testing::expect_true(token::is_keyword(token::TokenKind::KW_FIRST), m)) { return -1; }
    if (!testing::expect_true(token::is_keyword(token::TokenKind::KW_LAST), m)) { return -2; }
    return 0;
}

fn i32 is_type_keyword_basic(arena::Arena* a, u8[] m) {
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

fn i32 is_type_keyword_boundaries(arena::Arena* a, u8[] m) {
    if (!testing::expect_true(token::is_type_keyword(token::TokenKind::KW_TYPE_FIRST), m)) { return -1; }
    if (!testing::expect_true(token::is_type_keyword(token::TokenKind::KW_TYPE_LAST), m)) { return -2; }
    return 0;
}

fn i32 is_literal_basic(arena::Arena* a, u8[] m) {
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

fn i32 keywords_table_size(arena::Arena* a, u8[] m) {
    if (!testing::expect_gt(token::KEYWORDS.len, (u64)40, m)) { return -1; }
    if (!testing::expect_lt(token::KEYWORDS.len, (u64)100, m)) { return -2; }
    return 0;
}

fn i32 keywords_table_entries(arena::Arena* a, u8[] m) {
    if (!testing::expect_eq(token::KEYWORDS[0].bytes, "i8", m)) { return -1; }
    if (!testing::expect_eq((u32)token::KEYWORDS[0].kind, (u32)token::TokenKind::I8, m)) { return -2; }
    u64 last = token::KEYWORDS.len - 1;
    if (!testing::expect_eq(token::KEYWORDS[last].bytes, "type_info", m)) { return -3; }
    if (!testing::expect_eq((u32)token::KEYWORDS[last].kind, (u32)token::TokenKind::TYPE_INFO, m)) { return -4; }
    return 0;
}

fn i32 keywords_table_nonempty_bytes(arena::Arena* a, u8[] m) {
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

fn i32 char_class_alpha(arena::Arena* a, u8[] m) {
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['A'], token::CharClass::Alpha), m)) { return -1; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['Z'], token::CharClass::Alpha), m)) { return -2; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['a'], token::CharClass::Alpha), m)) { return -3; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['z'], token::CharClass::Alpha), m)) { return -4; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['M'], token::CharClass::Alpha), m)) { return -5; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['0'], token::CharClass::Alpha), m)) { return -6; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['_'], token::CharClass::Alpha), m)) { return -7; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS[' '], token::CharClass::Alpha), m)) { return -8; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['@'], token::CharClass::Alpha), m)) { return -9; }
    return 0;
}

fn i32 char_class_digit(arena::Arena* a, u8[] m) {
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['0'], token::CharClass::Digit), m)) { return -1; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['5'], token::CharClass::Digit), m)) { return -2; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['9'], token::CharClass::Digit), m)) { return -3; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['a'], token::CharClass::Digit), m)) { return -4; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['/'], token::CharClass::Digit), m)) { return -5; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS[':'], token::CharClass::Digit), m)) { return -6; }
    return 0;
}

fn i32 char_class_hex(arena::Arena* a, u8[] m) {
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['0'], token::CharClass::Hex), m)) { return -1; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['9'], token::CharClass::Hex), m)) { return -2; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['A'], token::CharClass::Hex), m)) { return -3; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['F'], token::CharClass::Hex), m)) { return -4; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['a'], token::CharClass::Hex), m)) { return -5; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['f'], token::CharClass::Hex), m)) { return -6; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['G'], token::CharClass::Hex), m)) { return -7; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['g'], token::CharClass::Hex), m)) { return -8; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['Z'], token::CharClass::Hex), m)) { return -9; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['z'], token::CharClass::Hex), m)) { return -10; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['_'], token::CharClass::Hex), m)) { return -11; }
    return 0;
}

fn i32 char_class_id_start(arena::Arena* a, u8[] m) {
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['A'], token::CharClass::ID_Start), m)) { return -1; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['Z'], token::CharClass::ID_Start), m)) { return -2; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['a'], token::CharClass::ID_Start), m)) { return -3; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['z'], token::CharClass::ID_Start), m)) { return -4; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['_'], token::CharClass::ID_Start), m)) { return -5; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['0'], token::CharClass::ID_Start), m)) { return -6; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['9'], token::CharClass::ID_Start), m)) { return -7; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS[' '], token::CharClass::ID_Start), m)) { return -8; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['+'], token::CharClass::ID_Start), m)) { return -9; }
    return 0;
}

fn i32 char_class_id_cont(arena::Arena* a, u8[] m) {
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['A'], token::CharClass::ID_Cont), m)) { return -1; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['z'], token::CharClass::ID_Cont), m)) { return -2; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['_'], token::CharClass::ID_Cont), m)) { return -3; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['0'], token::CharClass::ID_Cont), m)) { return -4; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['9'], token::CharClass::ID_Cont), m)) { return -5; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS[' '], token::CharClass::ID_Cont), m)) { return -6; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['+'], token::CharClass::ID_Cont), m)) { return -7; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['\n'], token::CharClass::ID_Cont), m)) { return -8; }
    return 0;
}

fn i32 char_class_whitespace(arena::Arena* a, u8[] m) {
    if (!testing::expect_true(has_bit(token::CHAR_CLASS[' '], token::CharClass::Whitespace), m)) { return -1; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['\t'], token::CharClass::Whitespace), m)) { return -2; }
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['\r'], token::CharClass::Whitespace), m)) { return -3; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['\n'], token::CharClass::Whitespace), m)) { return -4; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['a'], token::CharClass::Whitespace), m)) { return -5; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['0'], token::CharClass::Whitespace), m)) { return -6; }
    return 0;
}

fn i32 char_class_newline(arena::Arena* a, u8[] m) {
    if (!testing::expect_true(has_bit(token::CHAR_CLASS['\n'], token::CharClass::NewLine), m)) { return -1; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['\r'], token::CharClass::NewLine), m)) { return -2; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS[' '], token::CharClass::NewLine), m)) { return -3; }
    if (!testing::expect_false(has_bit(token::CHAR_CLASS['\t'], token::CharClass::NewLine), m)) { return -4; }
    return 0;
}

fn i32 char_class_unclassified(arena::Arena* a, u8[] m) {
    if (!testing::expect_eq((u32)(u8)token::CHAR_CLASS['@'], (u32)0, m)) { return -1; }
    if (!testing::expect_eq((u32)(u8)token::CHAR_CLASS['['], (u32)0, m)) { return -2; }
    if (!testing::expect_eq((u32)(u8)token::CHAR_CLASS['{'], (u32)0, m)) { return -3; }
    if (!testing::expect_eq((u32)(u8)token::CHAR_CLASS[0], (u32)0, m)) { return -4; }
    if (!testing::expect_eq((u32)(u8)token::CHAR_CLASS[127], (u32)0, m)) { return -5; }
    if (!testing::expect_eq((u32)(u8)token::CHAR_CLASS[255], (u32)0, m)) { return -6; }
    return 0;
}

fn i32 char_class_combined_bits(arena::Arena* a, u8[] m) {
    u8 a_bits = (u8)token::CHAR_CLASS['A'];
    u8 expect_a = (u8)token::CharClass::Alpha | (u8)token::CharClass::ID_Start | (u8)token::CharClass::ID_Cont | (u8)token::CharClass::Hex;
    if (!testing::expect_eq((u32)a_bits, (u32)expect_a, m)) { return -1; }

    u8 g_bits = (u8)token::CHAR_CLASS['G'];
    u8 expect_g = (u8)token::CharClass::Alpha | (u8)token::CharClass::ID_Start | (u8)token::CharClass::ID_Cont;
    if (!testing::expect_eq((u32)g_bits, (u32)expect_g, m)) { return -2; }

    u8 d_bits = (u8)token::CHAR_CLASS['5'];
    u8 expect_d = (u8)token::CharClass::Digit | (u8)token::CharClass::ID_Cont | (u8)token::CharClass::Hex;
    if (!testing::expect_eq((u32)d_bits, (u32)expect_d, m)) { return -3; }

    u8 u_bits = (u8)token::CHAR_CLASS['_'];
    u8 expect_u = (u8)token::CharClass::ID_Start | (u8)token::CharClass::ID_Cont;
    if (!testing::expect_eq((u32)u_bits, (u32)expect_u, m)) { return -4; }
    return 0;
}

fn i32 main() {
    testing::init();
    u8[] suite = "Token Tests";
    token::build_char_class_table();
    testing::add(suite, "is_keyword_basic", &is_keyword_basic);
    testing::add(suite, "is_keyword_boundaries", &is_keyword_boundaries);
    testing::add(suite, "is_type_keyword_basic", &is_type_keyword_basic);
    testing::add(suite, "is_type_keyword_boundaries", &is_type_keyword_boundaries);
    testing::add(suite, "is_literal_basic", &is_literal_basic);
    testing::add(suite, "keywords_table_size", &keywords_table_size);
    testing::add(suite, "keywords_table_entries", &keywords_table_entries);
    testing::add(suite, "keywords_table_nonempty_bytes", &keywords_table_nonempty_bytes);
    testing::add(suite, "char_class_alpha", &char_class_alpha);
    testing::add(suite, "char_class_digit", &char_class_digit);
    testing::add(suite, "char_class_hex", &char_class_hex);
    testing::add(suite, "char_class_id_start", &char_class_id_start);
    testing::add(suite, "char_class_id_cont", &char_class_id_cont);
    testing::add(suite, "char_class_whitespace", &char_class_whitespace);
    testing::add(suite, "char_class_newline", &char_class_newline);
    testing::add(suite, "char_class_unclassified", &char_class_unclassified);
    testing::add(suite, "char_class_combined_bits", &char_class_combined_bits);
    return testing::run();
}
