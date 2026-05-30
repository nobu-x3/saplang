import testing;
import arena;
import ast;
import diag;
import interner;
import module;
import parser;
import scanner;
import symbol;
import sys;
import token;

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

fn ast::AstNode* parse_src(arena::Arena* a, u8[] src, module::Module** out_m) {
    module::Module* m = prepare(a, src);
    scanner::scan(m);
    ast::AstNode* root = parser::parse(m);
    *out_m = m;
    return root;
}

fn ast::AstNode* nth_stmt(ast::AstNode* root, u64 i) {
    if(!root) { return null; }
    if(root.h.kind != ast::AstKind::BlockStmt) { return null; }
    ast::BlockNode* b = (ast::BlockNode*)root;
    if(i >= b.stmts.len) { return null; }
    return b.stmts.ptr[i];
}

fn bool has_error_stmt(ast::AstNode* root) {
    if(!root || root.h.kind != ast::AstKind::BlockStmt) { return false; }
    ast::BlockNode* b = (ast::BlockNode*)root;
    for(u64 i = 0; i < b.stmts.len; i += 1) {
        if(b.stmts.ptr[i] && b.stmts.ptr[i].h.kind == ast::AstKind::ERROR) {
            return true;
        }
    }
    return false;
}

// ---------- happy paths ----------

fn i32 import_single(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m;
    ast::AstNode* root = parse_src(&local, "import io;", &m);
    if(!testing::expect_not_null((void*)root, msg)) { return -1; }
    if(!testing::expect_eq((u16)root.h.kind, (u16)ast::AstKind::BlockStmt, msg)) { return -2; }
    ast::BlockNode* b = (ast::BlockNode*)root;
    if(!testing::expect_eq(b.stmts.len, 1, msg)) { return -3; }
    ast::AstNode* s = nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)s, msg)) { return -4; }
    if(!testing::expect_eq((u16)s.h.kind, (u16)ast::AstKind::ImportDecl, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 import_module_name_matches_symbol(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m;
    ast::AstNode* root = parse_src(&local, "import io;", &m);
    ast::ImportNode* imp = (ast::ImportNode*)nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)imp, msg)) { return -1; }
    symbol::Symbol* want = interner::intern(m.interner, "io");
    if(!testing::expect_eq((void*)imp.module_name, (void*)want, msg)) { return -2; }
    return 0;
}

fn i32 import_src_pos_on_import_keyword(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m;
    ast::AstNode* root = parse_src(&local, "   import io;", &m);
    ast::ImportNode* imp = (ast::ImportNode*)nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)imp, msg)) { return -1; }
    if(!testing::expect_eq(imp.h.src_pos, 3, msg)) { return -2; }
    return 0;
}

fn i32 import_flags_clean(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m;
    ast::AstNode* root = parse_src(&local, "import io;", &m);
    ast::AstNode* s = nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)s, msg)) { return -1; }
    if(!testing::expect_eq((u16)s.h.flags, 0, msg)) { return -2; }
    return 0;
}

fn i32 import_underscore_identifier(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m;
    ast::AstNode* root = parse_src(&local, "import abc_def;", &m);
    ast::ImportNode* imp = (ast::ImportNode*)nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)imp, msg)) { return -1; }
    symbol::Symbol* want = interner::intern(m.interner, "abc_def");
    if(!testing::expect_eq((void*)imp.module_name, (void*)want, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -3; }
    return 0;
}

fn i32 import_multiple_in_sequence(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m;
    ast::AstNode* root = parse_src(&local, "import a; import b; import c;", &m);
    ast::BlockNode* b = (ast::BlockNode*)root;
    if(!testing::expect_eq(b.stmts.len, 3, msg)) { return -1; }
    ast::ImportNode* i0 = (ast::ImportNode*)nth_stmt(root, 0);
    ast::ImportNode* i1 = (ast::ImportNode*)nth_stmt(root, 1);
    ast::ImportNode* i2 = (ast::ImportNode*)nth_stmt(root, 2);
    symbol::Symbol* sa = interner::intern(m.interner, "a");
    symbol::Symbol* sb = interner::intern(m.interner, "b");
    symbol::Symbol* sc = interner::intern(m.interner, "c");
    if(!testing::expect_eq((u16)i0.h.kind, (u16)ast::AstKind::ImportDecl, msg)) { return -2; }
    if(!testing::expect_eq((u16)i1.h.kind, (u16)ast::AstKind::ImportDecl, msg)) { return -3; }
    if(!testing::expect_eq((u16)i2.h.kind, (u16)ast::AstKind::ImportDecl, msg)) { return -4; }
    if(!testing::expect_eq((void*)i0.module_name, (void*)sa, msg)) { return -5; }
    if(!testing::expect_eq((void*)i1.module_name, (void*)sb, msg)) { return -6; }
    if(!testing::expect_eq((void*)i2.module_name, (void*)sc, msg)) { return -7; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -8; }
    return 0;
}

fn i32 import_with_trailing_whitespace(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m;
    ast::AstNode* root = parse_src(&local, "import io;\n   \t  ", &m);
    ast::BlockNode* b = (ast::BlockNode*)root;
    if(!testing::expect_eq(b.stmts.len, 1, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -2; }
    return 0;
}

fn i32 import_with_line_comment_before(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m;
    ast::AstNode* root = parse_src(&local, "// hi\nimport io;", &m);
    ast::ImportNode* imp = (ast::ImportNode*)nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)imp, msg)) { return -1; }
    if(!testing::expect_eq((u16)imp.h.kind, (u16)ast::AstKind::ImportDecl, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -3; }
    return 0;
}

// ---------- error paths ----------
// Each test asserts the *first* diagnostic text and its src_pos.
// Trailing recovery diagnostics may follow but aren't pinned — they're noise.

fn i32 import_missing_module_name_int_literal(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m;
    ast::AstNode* root = parse_src(&local, "import 123;", &m);
    if(!testing::expect_true(has_error_stmt(root), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got integer literal", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 7, msg)) { return -3; }
    return 0;
}

fn i32 import_missing_module_name_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m;
    ast::AstNode* root = parse_src(&local, "import ;", &m);
    if(!testing::expect_true(has_error_stmt(root), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ';'", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 7, msg)) { return -3; }
    return 0;
}

fn i32 import_missing_semi_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m;
    ast::AstNode* root = parse_src(&local, "import io", &m);
    if(!testing::expect_true(has_error_stmt(root), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got end of file", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 9, msg)) { return -3; }
    return 0;
}

fn i32 import_missing_semi_extra_token(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m;
    ast::AstNode* root = parse_src(&local, "import io io;", &m);
    if(!testing::expect_true(has_error_stmt(root), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got identifier", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 10, msg)) { return -3; }
    return 0;
}

fn i32 import_bare_keyword_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m;
    ast::AstNode* root = parse_src(&local, "import", &m);
    if(!testing::expect_true(has_error_stmt(root), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got end of file", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 6, msg)) { return -3; }
    return 0;
}

fn i32 import_module_name_is_keyword(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m;
    ast::AstNode* root = parse_src(&local, "import struct;", &m);
    if(!testing::expect_true(has_error_stmt(root), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got 'struct'", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 7, msg)) { return -3; }
    return 0;
}

fn i32 import_qualified_name_rejected(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m;
    ast::AstNode* root = parse_src(&local, "import io::file;", &m);
    if(!testing::expect_true(has_error_stmt(root), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got '::'", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 9, msg)) { return -3; }
    return 0;
}

fn i32 import_error_then_valid_recovers(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m;
    ast::AstNode* root = parse_src(&local, "import 123; import io;", &m);
    ast::BlockNode* b = (ast::BlockNode*)root;
    bool found_io = false;
    symbol::Symbol* want = interner::intern(m.interner, "io");
    for(u64 i = 0; i < b.stmts.len; i += 1) {
        ast::AstNode* s = b.stmts.ptr[i];
        if(s && s.h.kind == ast::AstKind::ImportDecl) {
            ast::ImportNode* ii = (ast::ImportNode*)s;
            if(ii.module_name == want) { found_io = true; }
        }
    }
    if(!testing::expect_true(found_io, msg)) { return -1; }
    return 0;
}

fn i32 import_error_does_not_loop_forever(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    module::Module* m;
    ast::AstNode* root = parse_src(&local, "import import import import import", &m);
    if(!testing::expect_not_null((void*)root, msg)) { return -1; }
    return 0;
}

fn i32 main() {
    testing::init();
    u8[] suite = "Parser Import Tests";

    testing::add(suite, "import_single", &import_single);
    testing::add(suite, "import_module_name_matches_symbol", &import_module_name_matches_symbol);
    testing::add(suite, "import_src_pos_on_import_keyword", &import_src_pos_on_import_keyword);
    testing::add(suite, "import_flags_clean", &import_flags_clean);
    testing::add(suite, "import_underscore_identifier", &import_underscore_identifier);
    testing::add(suite, "import_multiple_in_sequence", &import_multiple_in_sequence);
    testing::add(suite, "import_with_trailing_whitespace", &import_with_trailing_whitespace);
    testing::add(suite, "import_with_line_comment_before", &import_with_line_comment_before);

    testing::add(suite, "import_missing_module_name_int_literal", &import_missing_module_name_int_literal);
    testing::add(suite, "import_missing_module_name_semi", &import_missing_module_name_semi);
    testing::add(suite, "import_missing_semi_at_eof", &import_missing_semi_at_eof);
    testing::add(suite, "import_missing_semi_extra_token", &import_missing_semi_extra_token);
    testing::add(suite, "import_bare_keyword_at_eof", &import_bare_keyword_at_eof);
    testing::add(suite, "import_module_name_is_keyword", &import_module_name_is_keyword);
    testing::add(suite, "import_qualified_name_rejected", &import_qualified_name_rejected);
    testing::add(suite, "import_error_then_valid_recovers", &import_error_then_valid_recovers);
    testing::add(suite, "import_error_does_not_loop_forever", &import_error_does_not_loop_forever);

    return testing::run();
}
