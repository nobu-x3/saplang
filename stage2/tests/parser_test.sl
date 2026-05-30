import testing;
import compiler_testing;
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

// ============================================================================
// IMPORTS
// ============================================================================

fn i32 import_single(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import io;", &m);
    ast::ImportNode* imp = compiler_testing::expect_import(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "io"), msg);
    if(!imp) { return -1; }
    if(!testing::expect_eq(imp.h.src_pos, 0, msg)) { return -2; }
    if(!testing::expect_eq((u16)imp.h.flags, 0, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 import_src_pos_on_import_keyword(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "   import io;", &m);
    ast::ImportNode* imp = compiler_testing::expect_import(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "io"), msg);
    if(!imp) { return -1; }
    if(!testing::expect_eq(imp.h.src_pos, 3, msg)) { return -2; }
    return 0;
}

fn i32 import_underscore_identifier(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import abc_def;", &m);
    if(!compiler_testing::expect_import(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "abc_def"), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -2; }
    return 0;
}

fn i32 import_multiple_in_sequence(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import a; import b; import c;", &m);
    ast::BlockNode* b = (ast::BlockNode*)root;
    if(!testing::expect_eq(b.stmts.len, 3, msg)) { return -1; }
    if(!compiler_testing::expect_import(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "a"), msg)) { return -2; }
    if(!compiler_testing::expect_import(compiler_testing::nth_stmt(root, 1), compiler_testing::sym(m, "b"), msg)) { return -3; }
    if(!compiler_testing::expect_import(compiler_testing::nth_stmt(root, 2), compiler_testing::sym(m, "c"), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 import_with_trailing_whitespace(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import io;\n   \t  ", &m);
    ast::BlockNode* b = (ast::BlockNode*)root;
    if(!testing::expect_eq(b.stmts.len, 1, msg)) { return -1; }
    if(!compiler_testing::expect_import(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "io"), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -3; }
    return 0;
}

fn i32 import_with_line_comment_before(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "// hi\nimport io;", &m);
    if(!compiler_testing::expect_import(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "io"), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -2; }
    return 0;
}

// --- import error paths ---

fn i32 import_missing_module_name_int_literal(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import 123;", &m);
    if(!testing::expect_true(compiler_testing::has_error_stmt(root), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got integer literal", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 7, msg)) { return -3; }
    return 0;
}

fn i32 import_missing_module_name_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import ;", &m);
    if(!testing::expect_true(compiler_testing::has_error_stmt(root), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ';'", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 7, msg)) { return -3; }
    return 0;
}

fn i32 import_missing_semi_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import io", &m);
    if(!testing::expect_true(compiler_testing::has_error_stmt(root), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got end of file", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 9, msg)) { return -3; }
    return 0;
}

fn i32 import_missing_semi_extra_token(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import io io;", &m);
    if(!testing::expect_true(compiler_testing::has_error_stmt(root), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got identifier", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 10, msg)) { return -3; }
    return 0;
}

fn i32 import_bare_keyword_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import", &m);
    if(!testing::expect_true(compiler_testing::has_error_stmt(root), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got end of file", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 6, msg)) { return -3; }
    return 0;
}

fn i32 import_module_name_is_keyword(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import struct;", &m);
    if(!testing::expect_true(compiler_testing::has_error_stmt(root), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got 'struct'", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 7, msg)) { return -3; }
    return 0;
}

fn i32 import_qualified_name_rejected(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import io::file;", &m);
    if(!testing::expect_true(compiler_testing::has_error_stmt(root), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got '::'", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 9, msg)) { return -3; }
    return 0;
}

fn i32 import_error_then_valid_recovers(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import 123; import io;", &m);
    ast::BlockNode* b = (ast::BlockNode*)root;
    bool found_io = false;
    symbol::Symbol* want = compiler_testing::sym(m, "io");
    for(u64 i = 0; i < b.stmts.len; i += 1) {
        ast::AstNode* s = b.stmts.ptr[i];
        if(s && s.h.kind == ast::AstKind::ImportDecl) {
            ast::ImportNode* ii = (ast::ImportNode*)s;
            if(ii.module_name == want) { found_io = true; }
        }
    }
    if(!(testing::expect_true(found_io, msg))) { return -1; } return 0;
}

fn i32 import_error_does_not_loop_forever(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import import import import import", &m);
    if(!(testing::expect_not_null((void*)root, msg))) { return -1; } return 0;
}

fn i32 main() {
    testing::init();

    u8[] s_imp = "Parser Imports";
    testing::add(s_imp, "import_single", &import_single);
    testing::add(s_imp, "import_src_pos_on_import_keyword", &import_src_pos_on_import_keyword);
    testing::add(s_imp, "import_underscore_identifier", &import_underscore_identifier);
    testing::add(s_imp, "import_multiple_in_sequence", &import_multiple_in_sequence);
    testing::add(s_imp, "import_with_trailing_whitespace", &import_with_trailing_whitespace);
    testing::add(s_imp, "import_with_line_comment_before", &import_with_line_comment_before);
    testing::add(s_imp, "import_missing_module_name_int_literal", &import_missing_module_name_int_literal);
    testing::add(s_imp, "import_missing_module_name_semi", &import_missing_module_name_semi);
    testing::add(s_imp, "import_missing_semi_at_eof", &import_missing_semi_at_eof);
    testing::add(s_imp, "import_missing_semi_extra_token", &import_missing_semi_extra_token);
    testing::add(s_imp, "import_bare_keyword_at_eof", &import_bare_keyword_at_eof);
    testing::add(s_imp, "import_module_name_is_keyword", &import_module_name_is_keyword);
    testing::add(s_imp, "import_qualified_name_rejected", &import_qualified_name_rejected);
    testing::add(s_imp, "import_error_then_valid_recovers", &import_error_then_valid_recovers);
    testing::add(s_imp, "import_error_does_not_loop_forever", &import_error_does_not_loop_forever);

    return testing::run();
}
