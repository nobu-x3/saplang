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

fn i32 import_not_reexport_by_default(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import io;", &m);
    ast::ImportNode* imp = compiler_testing::expect_import(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "io"), msg);
    if(!imp) { return -1; }
    if(!testing::expect_eq(imp.is_reexport, false, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -3; }
    return 0;
}

fn i32 import_export_marks_reexport(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "export import io;", &m);
    ast::ImportNode* imp = compiler_testing::expect_import(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "io"), msg);
    if(!imp) { return -1; }
    if(!testing::expect_eq(imp.is_reexport, true, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -3; }
    if(!testing::expect_eq((u16)imp.h.flags, (u16)0, msg)) { return -4; }
    return 0;
}

fn i32 import_export_then_plain_import(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "export import a; import b;", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::ImportNode* i0 = compiler_testing::expect_import(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "a"), msg);
    if(!i0) { return -2; }
    if(!testing::expect_eq(i0.is_reexport, true, msg)) { return -3; }
    ast::ImportNode* i1 = compiler_testing::expect_import(compiler_testing::nth_stmt(root, 1), compiler_testing::sym(m, "b"), msg);
    if(!i1) { return -4; }
    if(!testing::expect_eq(i1.is_reexport, false, msg)) { return -5; }
    return 0;
}

fn i32 import_export_with_bad_module_name_recovers(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "export import 123; import io;", &m);
    ast::BlockNode* b = (ast::BlockNode*)root;
    bool found_io = false;
    bool io_is_reexport = true;
    symbol::Symbol* want = compiler_testing::sym(m, "io");
    for(u64 i = 0; i < b.stmts.len; i += 1) {
        ast::AstNode* s = b.stmts.ptr[i];
        if(s && s.h.kind == ast::AstKind::ImportDecl) {
            ast::ImportNode* ii = (ast::ImportNode*)s;
            if(ii.module_name == want) {
                found_io = true;
                io_is_reexport = ii.is_reexport;
            }
        }
    }
    if(!testing::expect_true(found_io, msg)) { return -1; }
    if(!testing::expect_eq(io_is_reexport, false, msg)) { return -2; }
    return 0;
}

fn i32 import_export_with_keyword_module_name_recovers(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "export import const; import io;", &m);
    ast::BlockNode* b = (ast::BlockNode*)root;
    bool found_io = false;
    bool io_is_reexport = true;
    symbol::Symbol* want = compiler_testing::sym(m, "io");
    for(u64 i = 0; i < b.stmts.len; i += 1) {
        ast::AstNode* s = b.stmts.ptr[i];
        if(s && s.h.kind == ast::AstKind::ImportDecl) {
            ast::ImportNode* ii = (ast::ImportNode*)s;
            if(ii.module_name == want) {
                found_io = true;
                io_is_reexport = ii.is_reexport;
            }
        }
    }
    if(!testing::expect_true(found_io, msg)) { return -1; }
    if(!testing::expect_eq(io_is_reexport, false, msg)) { return -2; }
    return 0;
}

// ============================================================================
// VAR DECLS
// ============================================================================

fn i32 var_decl_basic_int_init(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = 5;", &m);
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -1; }
    if(!compiler_testing::expect_ty_prim(v.type_expr, token::TokenKind::I32, msg)) { return -2; }
    if(!compiler_testing::expect_intlit(v.init, 5, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 var_decl_no_init(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x;", &m);
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -1; }
    if(!compiler_testing::expect_ty_prim(v.type_expr, token::TokenKind::I32, msg)) { return -2; }
    if(!testing::expect_null((void*)v.init, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 var_decl_const(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "const i32 PI_X3 = 9;", &m);
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "PI_X3"), true, false, msg);
    if(!v) { return -1; }
    if(!compiler_testing::expect_intlit(v.init, 9, msg)) { return -2; }
    return 0;
}

fn i32 var_decl_export(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "export i32 g = 1;", &m);
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "g"), false, true, msg);
    if(!v) { return -1; }
    if(!compiler_testing::expect_intlit(v.init, 1, msg)) { return -2; }
    return 0;
}

fn i32 var_decl_export_const(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "export const i32 K = 42;", &m);
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "K"), true, true, msg);
    if(!v) { return -1; }
    if(!compiler_testing::expect_intlit(v.init, 42, msg)) { return -2; }
    return 0;
}

fn i32 var_decl_undefined_init(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = undefined;", &m);
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -1; }
    if(!compiler_testing::expect_undeflit(v.init, msg)) { return -2; }
    return 0;
}

fn i32 var_decl_src_pos_on_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "  i32 x = 5;", &m);
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -1; }
    if(!testing::expect_eq(v.h.src_pos, 2, msg)) { return -2; }
    return 0;
}

fn i32 var_decl_src_pos_on_const(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "  const i32 x = 5;", &m);
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "x"), true, false, msg);
    if(!v) { return -1; }
    if(!testing::expect_eq(v.h.src_pos, 2, msg)) { return -2; }
    return 0;
}

fn i32 var_decl_multiple_decls(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 a = 1; i32 b = 2; i32 c = 3;", &m);
    ast::BlockNode* blk = (ast::BlockNode*)root;
    if(!testing::expect_eq(blk.stmts.len, 3, msg)) { return -1; }
    ast::VarDeclNode* v0 = compiler_testing::expect_var(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "a"), false, false, msg);
    ast::VarDeclNode* v1 = compiler_testing::expect_var(compiler_testing::nth_stmt(root, 1), compiler_testing::sym(m, "b"), false, false, msg);
    ast::VarDeclNode* v2 = compiler_testing::expect_var(compiler_testing::nth_stmt(root, 2), compiler_testing::sym(m, "c"), false, false, msg);
    if(!v0 || !v1 || !v2) { return -2; }
    if(!compiler_testing::expect_intlit(v0.init, 1, msg)) { return -3; }
    if(!compiler_testing::expect_intlit(v1.init, 2, msg)) { return -4; }
    if(!compiler_testing::expect_intlit(v2.init, 3, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 var_decl_named_type_decl(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "MyType x;", &m);
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -1; }
    if(!compiler_testing::expect_ty_named(v.type_expr, null, compiler_testing::sym(m, "MyType"), msg)) { return -2; }
    return 0;
}

// --- VarDecl error paths ---

fn i32 var_decl_missing_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 = 5;", &m);
    ast::AstNode* n = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_true(compiler_testing::has_error_flag(n), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got '='", msg)) { return -2; }
    return 0;
}

fn i32 var_decl_missing_semi_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = 5", &m);
    ast::AstNode* n = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_true(compiler_testing::has_error_flag(n), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got end of file", msg)) { return -2; }
    return 0;
}

fn i32 var_decl_missing_semi_no_init(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x", &m);
    ast::AstNode* n = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_true(compiler_testing::has_error_flag(n), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got end of file", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 5, msg)) { return -3; }
    return 0;
}

fn i32 var_decl_missing_init_expr(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = ;", &m);
    ast::AstNode* n = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_true(compiler_testing::has_error_flag(n), msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ';'", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 8, msg)) { return -3; }
    return 0;
}

// ============================================================================
// TYPES
// ============================================================================

fn i32 ty_primitive_i32(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x;", &m);
    if(!(compiler_testing::expect_ty_prim(compiler_testing::var_type(root, 0), token::TokenKind::I32, msg))) { return -1; } return 0;
}

fn i32 ty_primitive_bool(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "bool b;", &m);
    if(!(compiler_testing::expect_ty_prim(compiler_testing::var_type(root, 0), token::TokenKind::BOOL, msg))) { return -1; } return 0;
}

fn i32 ty_primitive_f64(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "f64 x;", &m);
    if(!(compiler_testing::expect_ty_prim(compiler_testing::var_type(root, 0), token::TokenKind::F64, msg))) { return -1; } return 0;
}

fn i32 ty_primitive_void(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "void* p;", &m);
    ast::TypePointerNode* tp = compiler_testing::expect_ty_ptr(compiler_testing::var_type(root, 0), msg);
    if(!tp) { return -1; }
    if(!(compiler_testing::expect_ty_prim(tp.pointee, token::TokenKind::VOID, msg))) { return -2; } return 0;
}

fn i32 ty_pointer(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32* p;", &m);
    ast::TypePointerNode* tp = compiler_testing::expect_ty_ptr(compiler_testing::var_type(root, 0), msg);
    if(!tp) { return -1; }
    if(!testing::expect_false(tp.is_const, msg)) { return -2; }
    if(!(compiler_testing::expect_ty_prim(tp.pointee, token::TokenKind::I32, msg))) { return -3; } return 0;
}

fn i32 ty_pointer_to_pointer(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32** pp;", &m);
    ast::TypePointerNode* outer = compiler_testing::expect_ty_ptr(compiler_testing::var_type(root, 0), msg);
    if(!outer) { return -1; }
    ast::TypePointerNode* inner = compiler_testing::expect_ty_ptr(outer.pointee, msg);
    if(!inner) { return -2; }
    if(!(compiler_testing::expect_ty_prim(inner.pointee, token::TokenKind::I32, msg))) { return -3; } return 0;
}

fn i32 ty_slice(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32[] s;", &m);
    ast::TypeSliceNode* ts = compiler_testing::expect_ty_slice(compiler_testing::var_type(root, 0), msg);
    if(!ts) { return -1; }
    if(!(compiler_testing::expect_ty_prim(ts.element, token::TokenKind::I32, msg))) { return -2; } return 0;
}

fn i32 ty_array(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32[4] arr;", &m);
    ast::TypeArrayNode* ta = compiler_testing::expect_ty_array(compiler_testing::var_type(root, 0), msg);
    if(!ta) { return -1; }
    if(!compiler_testing::expect_ty_prim(ta.element, token::TokenKind::I32, msg)) { return -2; }
    if(!(compiler_testing::expect_intlit(ta.size_expr, 4, msg))) { return -3; } return 0;
}

fn i32 ty_named(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "Foo x;", &m);
    if(!(compiler_testing::expect_ty_named(compiler_testing::var_type(root, 0), null, compiler_testing::sym(m, "Foo"), msg))) { return -1; } return 0;
}

fn i32 ty_named_qualified(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "mod::Foo x;", &m);
    if(!(compiler_testing::expect_ty_named(compiler_testing::var_type(root, 0), compiler_testing::sym(m, "mod"), compiler_testing::sym(m, "Foo"), msg))) { return -1; } return 0;
}

fn i32 ty_fn_ptr_two_params(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn* i32(i32, i32) f;", &m);
    ast::TypeFnPtrNode* fp = compiler_testing::expect_ty_fnptr(compiler_testing::var_type(root, 0), 2, msg);
    if(!fp) { return -1; }
    if(!compiler_testing::expect_ty_prim(fp.return_type, token::TokenKind::I32, msg)) { return -2; }
    if(!compiler_testing::expect_ty_prim(fp.param_types.ptr[0], token::TokenKind::I32, msg)) { return -3; }
    if(!compiler_testing::expect_ty_prim(fp.param_types.ptr[1], token::TokenKind::I32, msg)) { return -4; }
    return 0;
}

fn i32 ty_fn_ptr_zero_params(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn* void() cb;", &m);
    ast::TypeFnPtrNode* fp = compiler_testing::expect_ty_fnptr(compiler_testing::var_type(root, 0), 0, msg);
    if(!fp) { return -1; }
    if(!(compiler_testing::expect_ty_prim(fp.return_type, token::TokenKind::VOID, msg))) { return -2; } return 0;
}

fn i32 ty_ptr_slice_chain(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32*[] s;", &m);
    ast::TypeSliceNode* ts = compiler_testing::expect_ty_slice(compiler_testing::var_type(root, 0), msg);
    if(!ts) { return -1; }
    ast::TypePointerNode* tp = compiler_testing::expect_ty_ptr(ts.element, msg);
    if(!tp) { return -2; }
    if(!(compiler_testing::expect_ty_prim(tp.pointee, token::TokenKind::I32, msg))) { return -3; } return 0;
}

fn i32 ty_array_of_ptr(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    // i32*[4] — parsed as ArrayType(elem=PointerType(i32), size=4)
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32*[4] arr;", &m);
    ast::TypeArrayNode* ta = compiler_testing::expect_ty_array(compiler_testing::var_type(root, 0), msg);
    if(!ta) { return -1; }
    ast::TypePointerNode* tp = compiler_testing::expect_ty_ptr(ta.element, msg);
    if(!tp) { return -2; }
    if(!compiler_testing::expect_ty_prim(tp.pointee, token::TokenKind::I32, msg)) { return -3; }
    if(!(compiler_testing::expect_intlit(ta.size_expr, 4, msg))) { return -4; } return 0;
}

// ============================================================================
// FN DECLS / PARAMS
// ============================================================================

fn i32 fn_empty_params(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 0, false, msg);
    if(!f) { return -1; }
    if(!compiler_testing::expect_ty_prim(f.return_type, token::TokenKind::VOID, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -3; }
    return 0;
}

fn i32 fn_single_param(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(i32 x) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 1, false, msg);
    if(!f) { return -1; }
    ast::Param* p0 = &f.params[0];
    if(!compiler_testing::expect_param(p0, compiler_testing::sym(m, "x"), false, false, msg)) { return -2; }
    if(!compiler_testing::expect_ty_prim(p0.type_expr, token::TokenKind::I32, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 fn_two_params(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 add(i32 a, i32 b) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "add"), 2, false, msg);
    if(!f) { return -1; }
    if(!compiler_testing::expect_ty_prim(f.return_type, token::TokenKind::I32, msg)) { return -2; }
    ast::Param* p0 = &f.params[0];
    ast::Param* p1 = &f.params[1];
    if(!compiler_testing::expect_param(p0, compiler_testing::sym(m, "a"), false, false, msg)) { return -3; }
    if(!compiler_testing::expect_ty_prim(p0.type_expr, token::TokenKind::I32, msg)) { return -4; }
    if(!compiler_testing::expect_param(p1, compiler_testing::sym(m, "b"), false, false, msg)) { return -5; }
    if(!compiler_testing::expect_ty_prim(p1.type_expr, token::TokenKind::I32, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 fn_param_const(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(const i32 x) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 1, false, msg);
    if(!f) { return -1; }
    ast::Param* p0 = &f.params[0];
    if(!compiler_testing::expect_param(p0, compiler_testing::sym(m, "x"), true, false, msg)) { return -2; }
    if(!compiler_testing::expect_ty_prim(p0.type_expr, token::TokenKind::I32, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 fn_param_comptime(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(comptime Type T) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 1, false, msg);
    if(!f) { return -1; }
    ast::Param* p0 = &f.params[0];
    if(!compiler_testing::expect_param(p0, compiler_testing::sym(m, "T"), false, true, msg)) { return -2; }
    if(!compiler_testing::expect_ty_prim(p0.type_expr, token::TokenKind::TYPE, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 fn_param_comptime_const(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(comptime const i32 N) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 1, false, msg);
    if(!f) { return -1; }
    ast::Param* p0 = &f.params[0];
    if(!compiler_testing::expect_param(p0, compiler_testing::sym(m, "N"), true, true, msg)) { return -2; }
    if(!compiler_testing::expect_ty_prim(p0.type_expr, token::TokenKind::I32, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 fn_param_pointer_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(i32* p) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 1, false, msg);
    if(!f) { return -1; }
    ast::Param* p0 = &f.params[0];
    if(!compiler_testing::expect_param(p0, compiler_testing::sym(m, "p"), false, false, msg)) { return -2; }
    ast::TypePointerNode* tp = compiler_testing::expect_ty_ptr(p0.type_expr, msg);
    if(!tp) { return -3; }
    if(!compiler_testing::expect_ty_prim(tp.pointee, token::TokenKind::I32, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 fn_param_slice_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(i32[] s) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 1, false, msg);
    if(!f) { return -1; }
    ast::Param* p0 = &f.params[0];
    ast::TypeSliceNode* ts = compiler_testing::expect_ty_slice(p0.type_expr, msg);
    if(!ts) { return -2; }
    if(!compiler_testing::expect_ty_prim(ts.element, token::TokenKind::I32, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 fn_param_named_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(Foo x) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 1, false, msg);
    if(!f) { return -1; }
    ast::Param* p0 = &f.params[0];
    if(!compiler_testing::expect_ty_named(p0.type_expr, null, compiler_testing::sym(m, "Foo"), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -3; }
    return 0;
}

fn i32 fn_param_qualified_named_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(io::FILE* p) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 1, false, msg);
    if(!f) { return -1; }
    ast::Param* p0 = &f.params[0];
    ast::TypePointerNode* tp = compiler_testing::expect_ty_ptr(p0.type_expr, msg);
    if(!tp) { return -2; }
    if(!compiler_testing::expect_ty_named(tp.pointee, compiler_testing::sym(m, "io"), compiler_testing::sym(m, "FILE"), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 fn_params_mixed_modifiers(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(const i32 a, i32 b, comptime Type T) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 3, false, msg);
    if(!f) { return -1; }
    if(!compiler_testing::expect_param(&f.params[0], compiler_testing::sym(m, "a"), true, false, msg)) { return -2; }
    if(!compiler_testing::expect_param(&f.params[1], compiler_testing::sym(m, "b"), false, false, msg)) { return -3; }
    if(!compiler_testing::expect_param(&f.params[2], compiler_testing::sym(m, "T"), false, true, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 fn_param_trailing_comma(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(i32 a, i32 b,) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 2, false, msg);
    if(!f) { return -1; }
    if(!compiler_testing::expect_param(&f.params[0], compiler_testing::sym(m, "a"), false, false, msg)) { return -2; }
    if(!compiler_testing::expect_param(&f.params[1], compiler_testing::sym(m, "b"), false, false, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 fn_exported(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "export fn void f(i32 x) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 1, true, msg);
    if(!f) { return -1; }
    if(!compiler_testing::expect_param(&f.params[0], compiler_testing::sym(m, "x"), false, false, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -3; }
    return 0;
}

// `fn void f(const i32 x) {}` — `const` starts at byte 10
fn i32 fn_param_src_pos_on_const(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(const i32 x) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_eq(f.params[0].src_pos, 10, msg)) { return -2; }
    return 0;
}

// `fn void f(i32 x) {}` — `i32` starts at byte 10
fn i32 fn_param_src_pos_on_type_when_no_modifier(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(i32 x) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_eq(f.params[0].src_pos, 10, msg)) { return -2; }
    return 0;
}

// `fn void f(comptime Type T) {}` — `comptime` starts at byte 10
fn i32 fn_param_src_pos_on_comptime(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(comptime Type T) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_eq(f.params[0].src_pos, 10, msg)) { return -2; }
    return 0;
}

fn i32 fn_missing_param_name(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(i32) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 1, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)f), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ')'", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 13, msg)) { return -4; }
    return 0;
}

fn i32 fn_missing_rparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(i32 x {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 1, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)f), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ')', got '{'", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 16, msg)) { return -4; }
    return 0;
}

fn i32 fn_missing_fn_name(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void (i32 x) {}", &m);
    ast::AstNode* stmt0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)stmt0, msg)) { return -1; }
    if(!testing::expect_eq((u16)stmt0.h.kind, (u16)ast::AstKind::FnDecl, msg)) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag(stmt0), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got '('", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 8, msg)) { return -5; }
    return 0;
}

fn i32 fn_src_pos_on_fn_keyword(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "   fn void f() {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 0, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_eq(f.h.src_pos, 3, msg)) { return -2; }
    return 0;
}

fn i32 fn_export_src_pos_on_export(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "export fn void f() {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 0, true, msg);
    if(!f) { return -1; }
    if(!testing::expect_eq(f.h.src_pos, 7, msg)) { return -2; }
    return 0;
}

fn i32 fn_multiple_decls(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() {} fn i32 g(i32 x) {}", &m);
    ast::BlockNode* b = (ast::BlockNode*)root;
    if(!testing::expect_eq(b.stmts.len, 2, msg)) { return -1; }
    if(!compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 0, false, msg)) { return -2; }
    if(!compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 1), compiler_testing::sym(m, "g"), 1, false, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 fn_fn_ptr_return_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn fn* void(i32) make() {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "make"), 0, false, msg);
    if(!f) { return -1; }
    if(!compiler_testing::expect_ty_fnptr(f.return_type, 1, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -3; }
    return 0;
}

fn i32 fn_param_fn_ptr_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(fn* void(i32) cb) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 1, false, msg);
    if(!f) { return -1; }
    ast::Param* p0 = &f.params[0];
    if(!compiler_testing::expect_param(p0, compiler_testing::sym(m, "cb"), false, false, msg)) { return -2; }
    if(!compiler_testing::expect_ty_fnptr(p0.type_expr, 1, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 fn_missing_lparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f i32 x) {}", &m);
    ast::AstNode* stmt0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)stmt0, msg)) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag(stmt0), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '(', got 'i32'", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 10, msg)) { return -4; }
    return 0;
}

fn i32 fn_missing_return_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn f() {}", &m);
    ast::AstNode* stmt0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)stmt0, msg)) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag(stmt0), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got '('", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 4, msg)) { return -4; }
    return 0;
}

fn i32 fn_missing_param_comma(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(i32 a i32 b) {}", &m);
    ast::AstNode* stmt0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)stmt0, msg)) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag(stmt0), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ')', got 'i32'", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 16, msg)) { return -4; }
    return 0;
}

fn i32 fn_param_modifier_only(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(const) {}", &m);
    ast::AstNode* stmt0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)stmt0, msg)) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag(stmt0), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ')'", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 15, msg)) { return -4; }
    return 0;
}

fn i32 fn_param_wrong_modifier_order(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(const comptime i32 x) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 1, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)f), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "`comptime` must come before `const`", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)16, msg)) { return -5; }
    ast::Param* p0 = &f.params[0];
    if(!compiler_testing::expect_param(p0, compiler_testing::sym(m, "x"), true, true, msg)) { return -6; }
    if(!compiler_testing::expect_ty_prim(p0.type_expr, token::TokenKind::I32, msg)) { return -7; }
    return 0;
}

fn i32 fn_param_wrong_order_with_pointer_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(const comptime i32* x) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 1, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -2; }
    ast::Param* p0 = &f.params[0];
    if(!compiler_testing::expect_param(p0, compiler_testing::sym(m, "x"), true, true, msg)) { return -3; }
    ast::TypePointerNode* tp = compiler_testing::expect_ty_ptr(p0.type_expr, msg);
    if(!tp) { return -4; }
    if(!compiler_testing::expect_ty_prim(tp.pointee, token::TokenKind::I32, msg)) { return -5; }
    return 0;
}

fn i32 fn_param_wrong_order_with_qualified_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(const comptime mod::Foo x) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 1, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -2; }
    ast::Param* p0 = &f.params[0];
    if(!compiler_testing::expect_param(p0, compiler_testing::sym(m, "x"), true, true, msg)) { return -3; }
    if(!compiler_testing::expect_ty_named(p0.type_expr, compiler_testing::sym(m, "mod"), compiler_testing::sym(m, "Foo"), msg)) { return -4; }
    return 0;
}

fn i32 fn_param_wrong_order_one_of_many_recovers(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(i32 a, const comptime i32 b, i32 c) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 3, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -2; }
    if(!compiler_testing::expect_param(&f.params[0], compiler_testing::sym(m, "a"), false, false, msg)) { return -3; }
    if(!compiler_testing::expect_param(&f.params[1], compiler_testing::sym(m, "b"), true, true, msg)) { return -4; }
    if(!compiler_testing::expect_param(&f.params[2], compiler_testing::sym(m, "c"), false, false, msg)) { return -5; }
    return 0;
}

fn i32 fn_param_comptime_only_no_diag(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(comptime Type T) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 1, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -2; }
    if(!compiler_testing::expect_param(&f.params[0], compiler_testing::sym(m, "T"), false, true, msg)) { return -3; }
    return 0;
}

fn i32 fn_param_const_only_no_diag(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(const i32 x) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 1, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -2; }
    if(!compiler_testing::expect_param(&f.params[0], compiler_testing::sym(m, "x"), true, false, msg)) { return -3; }
    return 0;
}

fn i32 fn_param_two_wrong_order_two_diags(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(const comptime i32 a, const comptime i32 b) {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 2, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, (u64)2, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "`comptime` must come before `const`", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[1].msg, "`comptime` must come before `const`", msg)) { return -4; }
    if(!compiler_testing::expect_param(&f.params[0], compiler_testing::sym(m, "a"), true, true, msg)) { return -5; }
    if(!compiler_testing::expect_param(&f.params[1], compiler_testing::sym(m, "b"), true, true, msg)) { return -6; }
    return 0;
}

fn i32 extern_fn_param_wrong_modifier_order(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { fn void g(const comptime i32 x); }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "`comptime` must come before `const`", msg)) { return -3; }
    ast::ExternFnDeclNode* f = compiler_testing::expect_extern_fn(b.items[0], compiler_testing::sym(m, "g"), 1, false, false, msg);
    if(!f) { return -4; }
    if(!compiler_testing::expect_param(&f.params[0], compiler_testing::sym(m, "x"), true, true, msg)) { return -5; }
    return 0;
}

// ============================================================================
// LOCAL VAR DECLS
// ============================================================================

fn i32 local_var_decl_basic(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = (ast::BlockNode*)f.body;
    if(!testing::expect_eq(body.stmts.len, 1, msg)) { return -2; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -3; }
    if(!compiler_testing::expect_ty_prim(v.type_expr, token::TokenKind::I32, msg)) { return -4; }
    if(!compiler_testing::expect_intlit(v.init, 5, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 local_var_decl_const(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { const i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "x"), true, false, msg);
    if(!v) { return -2; }
    if(!compiler_testing::expect_ty_prim(v.type_expr, token::TokenKind::I32, msg)) { return -3; }
    if(!compiler_testing::expect_intlit(v.init, 5, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 local_var_decl_no_init(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 x; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -2; }
    if(!compiler_testing::expect_ty_prim(v.type_expr, token::TokenKind::I32, msg)) { return -3; }
    if(!testing::expect_null((void*)v.init, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 local_var_decl_pointer_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32* p = null; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "p"), false, false, msg);
    if(!v) { return -2; }
    ast::TypePointerNode* tp = compiler_testing::expect_ty_ptr(v.type_expr, msg);
    if(!tp) { return -3; }
    if(!compiler_testing::expect_ty_prim(tp.pointee, token::TokenKind::I32, msg)) { return -4; }
    if(!compiler_testing::expect_nulllit(v.init, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 local_var_decl_named_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { Foo x; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -2; }
    if(!compiler_testing::expect_ty_named(v.type_expr, null, compiler_testing::sym(m, "Foo"), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 local_var_decl_qualified_named_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { io::FILE* p; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "p"), false, false, msg);
    if(!v) { return -2; }
    ast::TypePointerNode* tp = compiler_testing::expect_ty_ptr(v.type_expr, msg);
    if(!tp) { return -3; }
    if(!compiler_testing::expect_ty_named(tp.pointee, compiler_testing::sym(m, "io"), compiler_testing::sym(m, "FILE"), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 local_var_decl_qualified_type_too_deep(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { mod::Foo::Bar x; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.ptr[0].msg, "expected a type here, but this chain looks like an enum variant (a value); types max out at `module::Name`", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.ptr[0].src_pos, (u32)22, msg)) { return -4; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -5; }
    if(!testing::expect_true(((u16)v.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -6; }
    if(!testing::expect_true(((u16)v.type_expr.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -7; }
    if(!compiler_testing::expect_ty_named(v.type_expr, compiler_testing::sym(m, "mod"), compiler_testing::sym(m, "Foo"), msg)) { return -8; }
    return 0;
}

fn i32 local_var_decl_qualified_type_four_levels_one_diag(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { mod::A::B::C x; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.ptr[0].src_pos, (u32)20, msg)) { return -3; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -4; }
    if(!testing::expect_true(((u16)v.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -5; }
    return 0;
}

fn i32 fn_param_qualified_type_too_deep_recovers(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(mod::A::B x, i32 y) { }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 2, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -2; }
    if(!testing::expect_eq((void*)f.params.ptr[0].name, (void*)compiler_testing::sym(m, "x"), msg)) { return -3; }
    if(!testing::expect_eq((void*)f.params.ptr[1].name, (void*)compiler_testing::sym(m, "y"), msg)) { return -4; }
    return 0;
}

fn i32 local_var_decl_multiple(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 a = 1; i32 b = 2; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = (ast::BlockNode*)f.body;
    if(!testing::expect_eq(body.stmts.len, 2, msg)) { return -2; }
    if(!compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "a"), false, false, msg)) { return -3; }
    if(!compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 1), compiler_testing::sym(m, "b"), false, false, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 local_var_decl_complex_init_expr(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 x = 1 + 2 * 3; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -2; }
    ast::BinaryOpNode* plus = compiler_testing::expect_binop(v.init, token::TokenKind::Plus, msg);
    if(!plus) { return -3; }
    if(!compiler_testing::expect_intlit(plus.lhs, 1, msg)) { return -4; }
    ast::BinaryOpNode* mul = compiler_testing::expect_binop(plus.rhs, token::TokenKind::Star, msg);
    if(!mul) { return -5; }
    if(!compiler_testing::expect_intlit(mul.lhs, 2, msg)) { return -6; }
    if(!compiler_testing::expect_intlit(mul.rhs, 3, msg)) { return -7; }
    return 0;
}

fn i32 local_var_decl_missing_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 x = 5 }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)f), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got '}'", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 24, msg)) { return -4; }
    return 0;
}

// `fn void f() { i32 x = 5; }` — `i32` starts at byte 14
fn i32 local_var_decl_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), null, false, false, msg);
    if(!v) { return -2; }
    if(!testing::expect_eq(v.h.src_pos, 14, msg)) { return -3; }
    return 0;
}

// `fn void f() { const i32 x = 5; }` — `const` starts at byte 14
fn i32 local_var_decl_src_pos_on_const(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { const i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), null, true, false, msg);
    if(!v) { return -2; }
    if(!testing::expect_eq(v.h.src_pos, 14, msg)) { return -3; }
    return 0;
}

fn i32 local_var_decl_empty_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = (ast::BlockNode*)f.body;
    if(!testing::expect_eq(body.stmts.len, 0, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -3; }
    return 0;
}

fn i32 local_var_decl_fn_ptr_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { fn* i32(i32) cb = null; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "cb"), false, false, msg);
    if(!v) { return -2; }
    ast::TypeFnPtrNode* fp = compiler_testing::expect_ty_fnptr(v.type_expr, 1, msg);
    if(!fp) { return -3; }
    if(!compiler_testing::expect_ty_prim(fp.return_type, token::TokenKind::I32, msg)) { return -4; }
    if(!compiler_testing::expect_ty_prim(fp.param_types.ptr[0], token::TokenKind::I32, msg)) { return -5; }
    if(!compiler_testing::expect_nulllit(v.init, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 local_var_decl_slice_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32[] s; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "s"), false, false, msg);
    if(!v) { return -2; }
    ast::TypeSliceNode* ts = compiler_testing::expect_ty_slice(v.type_expr, msg);
    if(!ts) { return -3; }
    if(!compiler_testing::expect_ty_prim(ts.element, token::TokenKind::I32, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 local_var_decl_array_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32[3] arr; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "arr"), false, false, msg);
    if(!v) { return -2; }
    ast::TypeArrayNode* ta = compiler_testing::expect_ty_array(v.type_expr, msg);
    if(!ta) { return -3; }
    if(!compiler_testing::expect_ty_prim(ta.element, token::TokenKind::I32, msg)) { return -4; }
    if(!compiler_testing::expect_intlit(ta.size_expr, 3, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 local_var_decl_struct_lit_init(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { Foo x = { 1, 2 }; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -2; }
    if(!compiler_testing::expect_ty_named(v.type_expr, null, compiler_testing::sym(m, "Foo"), msg)) { return -3; }
    ast::StructLitNode* sl = compiler_testing::expect_struct_lit(v.init, 2, msg);
    if(!sl) { return -4; }
    if(!compiler_testing::expect_field_init(&sl.inits[0], null, msg)) { return -5; }
    if(!compiler_testing::expect_intlit(sl.inits[0].value, 1, msg)) { return -6; }
    if(!compiler_testing::expect_field_init(&sl.inits[1], null, msg)) { return -7; }
    if(!compiler_testing::expect_intlit(sl.inits[1].value, 2, msg)) { return -8; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -9; }
    return 0;
}

fn i32 local_var_decl_struct_lit_designated_init(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { Foo x = { .a = 1, .b = 2 }; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -2; }
    ast::StructLitNode* sl = compiler_testing::expect_struct_lit(v.init, 2, msg);
    if(!sl) { return -3; }
    if(!compiler_testing::expect_field_init(&sl.inits[0], compiler_testing::sym(m, "a"), msg)) { return -4; }
    if(!compiler_testing::expect_intlit(sl.inits[0].value, 1, msg)) { return -5; }
    if(!compiler_testing::expect_field_init(&sl.inits[1], compiler_testing::sym(m, "b"), msg)) { return -6; }
    if(!compiler_testing::expect_intlit(sl.inits[1].value, 2, msg)) { return -7; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -8; }
    return 0;
}

fn i32 local_var_decl_array_lit_init(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32[3] arr = [1, 2, 3]; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "arr"), false, false, msg);
    if(!v) { return -2; }
    ast::ArrayLitNode* al = compiler_testing::expect_array_lit(v.init, 3, msg);
    if(!al) { return -3; }
    if(!compiler_testing::expect_intlit(al.elems.ptr[0], 1, msg)) { return -4; }
    if(!compiler_testing::expect_intlit(al.elems.ptr[1], 2, msg)) { return -5; }
    if(!compiler_testing::expect_intlit(al.elems.ptr[2], 3, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 local_var_decl_cast_init(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 x = (i32)y; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -2; }
    ast::CastNode* c = compiler_testing::expect_cast(v.init, msg);
    if(!c) { return -3; }
    if(!compiler_testing::expect_ty_prim(c.target_type, token::TokenKind::I32, msg)) { return -4; }
    if(!compiler_testing::expect_ident(c.expr, compiler_testing::sym(m, "y"), msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 local_var_decl_call_init(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 x = foo(1, 2); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -2; }
    ast::CallNode* c = compiler_testing::expect_call(v.init, 2, msg);
    if(!c) { return -3; }
    if(!compiler_testing::expect_ident(c.callee, compiler_testing::sym(m, "foo"), msg)) { return -4; }
    if(!compiler_testing::expect_intlit(c.args.ptr[0], 1, msg)) { return -5; }
    if(!compiler_testing::expect_intlit(c.args.ptr[1], 2, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 local_var_decl_undefined_init(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 x = undefined; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -2; }
    if(!compiler_testing::expect_ty_prim(v.type_expr, token::TokenKind::I32, msg)) { return -3; }
    if(!compiler_testing::expect_undeflit(v.init, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

// `i32 = 5;` at stmt position: `looks_like_var_decl` rewinds (no Ident after type),
// falls through to the stubbed expr_stmt path → error stmt, not a malformed var decl.
fn i32 local_var_decl_dispatch_falls_through_on_no_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = (ast::BlockNode*)f.body;
    if(!testing::expect_true(body.stmts.len > 0, msg)) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag(body.stmts.ptr[0]), msg)) { return -3; }
    if(!testing::expect_eq((u16)body.stmts.ptr[0].h.kind, (u16)ast::AstKind::ERROR, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got 'i32'", msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 14, msg)) { return -6; }
    return 0;
}

fn i32 local_var_decl_export_rejected(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { export i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)f), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got 'export'", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 14, msg)) { return -4; }
    return 0;
}

// ============================================================================
// EXPRESSION / ASSIGNMENT STATEMENTS
// ============================================================================

fn i32 expr_stmt_bare_call(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { foo(); }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::ExprStmtNode* es = compiler_testing::expect_expr_stmt(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!es) { return -3; }
    ast::CallNode* c = compiler_testing::expect_call(es.expr, 0, msg);
    if(!c) { return -4; }
    if(!compiler_testing::expect_ident(c.callee, compiler_testing::sym(m, "foo"), msg)) { return -5; }
    return 0;
}

fn i32 expr_stmt_call_with_args(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { foo(1, x); }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::ExprStmtNode* es = compiler_testing::expect_expr_stmt(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!es) { return -3; }
    ast::CallNode* c = compiler_testing::expect_call(es.expr, 2, msg);
    if(!c) { return -4; }
    if(!compiler_testing::expect_intlit(c.args.ptr[0], 1, msg)) { return -5; }
    if(!compiler_testing::expect_ident(c.args.ptr[1], compiler_testing::sym(m, "x"), msg)) { return -6; }
    return 0;
}

fn i32 expr_stmt_method_chain_call(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { a.b.c(); }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::ExprStmtNode* es = compiler_testing::expect_expr_stmt(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!es) { return -3; }
    if(!compiler_testing::expect_call(es.expr, 0, msg)) { return -4; }
    return 0;
}

fn i32 expr_stmt_assignment_plain(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { x = 1; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::AssignmentNode* an = compiler_testing::expect_assign(compiler_testing::nth_stmt(f.body, 0), token::TokenKind::Eq, msg);
    if(!an) { return -3; }
    if(!compiler_testing::expect_ident(an.lhs, compiler_testing::sym(m, "x"), msg)) { return -4; }
    if(!compiler_testing::expect_intlit(an.rhs, 1, msg)) { return -5; }
    return 0;
}

fn i32 expr_stmt_assignment_compound_plus_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { x += 2; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    if(!compiler_testing::expect_assign(compiler_testing::nth_stmt(f.body, 0), token::TokenKind::PlusEq, msg)) { return -3; }
    return 0;
}

fn i32 expr_stmt_assignment_compound_star_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { x *= 2; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    if(!compiler_testing::expect_assign(compiler_testing::nth_stmt(f.body, 0), token::TokenKind::StarEq, msg)) { return -3; }
    return 0;
}

fn i32 expr_stmt_assignment_compound_amp_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { x &= 3; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    if(!compiler_testing::expect_assign(compiler_testing::nth_stmt(f.body, 0), token::TokenKind::AmpEq, msg)) { return -3; }
    return 0;
}

fn i32 expr_stmt_assignment_compound_minus_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { x -= 2; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    if(!compiler_testing::expect_assign(compiler_testing::nth_stmt(f.body, 0), token::TokenKind::MinusEq, msg)) { return -3; }
    return 0;
}

fn i32 expr_stmt_assignment_compound_slash_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { x /= 2; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    if(!compiler_testing::expect_assign(compiler_testing::nth_stmt(f.body, 0), token::TokenKind::SlashEq, msg)) { return -3; }
    return 0;
}

fn i32 expr_stmt_assignment_compound_percent_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { x %= 2; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    if(!compiler_testing::expect_assign(compiler_testing::nth_stmt(f.body, 0), token::TokenKind::PercentEq, msg)) { return -3; }
    return 0;
}

fn i32 expr_stmt_assignment_compound_pipe_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { x |= 3; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    if(!compiler_testing::expect_assign(compiler_testing::nth_stmt(f.body, 0), token::TokenKind::PipeEq, msg)) { return -3; }
    return 0;
}

fn i32 expr_stmt_assignment_compound_caret_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { x ^= 3; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    if(!compiler_testing::expect_assign(compiler_testing::nth_stmt(f.body, 0), token::TokenKind::CaretEq, msg)) { return -3; }
    return 0;
}

fn i32 expr_stmt_bare_deref(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { *p; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::ExprStmtNode* es = compiler_testing::expect_expr_stmt(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!es) { return -3; }
    ast::UnaryOpNode* u = compiler_testing::expect_unop(es.expr, token::TokenKind::Star, msg);
    if(!u) { return -4; }
    if(!compiler_testing::expect_ident(u.operand, compiler_testing::sym(m, "p"), msg)) { return -5; }
    return 0;
}

fn i32 expr_stmt_capitalized_call(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { Foo(); }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::ExprStmtNode* es = compiler_testing::expect_expr_stmt(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!es) { return -3; }
    ast::CallNode* c = compiler_testing::expect_call(es.expr, 0, msg);
    if(!c) { return -4; }
    if(!compiler_testing::expect_ident(c.callee, compiler_testing::sym(m, "Foo"), msg)) { return -5; }
    return 0;
}

fn i32 defer_call_canonical(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer fclose(file); }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -3; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)d), msg)) { return -4; }
    ast::BlockNode* blk = compiler_testing::expect_block(d.body, 1, msg);
    if(!blk) { return -5; }
    ast::ExprStmtNode* es = compiler_testing::expect_expr_stmt(blk.stmts.ptr[0], msg);
    if(!es) { return -6; }
    ast::CallNode* c = compiler_testing::expect_call(es.expr, 1, msg);
    if(!c) { return -7; }
    if(!compiler_testing::expect_ident(c.callee, compiler_testing::sym(m, "fclose"), msg)) { return -8; }
    return 0;
}

fn i32 expr_stmt_assignment_index_lhs(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { arr[i] = v; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::AssignmentNode* an = compiler_testing::expect_assign(compiler_testing::nth_stmt(f.body, 0), token::TokenKind::Eq, msg);
    if(!an) { return -3; }
    if(!compiler_testing::expect_index(an.lhs, msg)) { return -4; }
    return 0;
}

fn i32 expr_stmt_assignment_deref_lhs(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { *p = v; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::AssignmentNode* an = compiler_testing::expect_assign(compiler_testing::nth_stmt(f.body, 0), token::TokenKind::Eq, msg);
    if(!an) { return -3; }
    if(!compiler_testing::expect_unop(an.lhs, token::TokenKind::Star, msg)) { return -4; }
    return 0;
}

fn i32 expr_stmt_assignment_member_lhs(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { s.field = v; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::AssignmentNode* an = compiler_testing::expect_assign(compiler_testing::nth_stmt(f.body, 0), token::TokenKind::Eq, msg);
    if(!an) { return -3; }
    if(!compiler_testing::expect_member(an.lhs, compiler_testing::sym(m, "field"), msg)) { return -4; }
    return 0;
}

fn i32 expr_stmt_bare_literal(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { 5; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::ExprStmtNode* es = compiler_testing::expect_expr_stmt(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!es) { return -3; }
    if(!compiler_testing::expect_intlit(es.expr, 5, msg)) { return -4; }
    return 0;
}

fn i32 expr_stmt_bare_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { x; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::ExprStmtNode* es = compiler_testing::expect_expr_stmt(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!es) { return -3; }
    if(!compiler_testing::expect_ident(es.expr, compiler_testing::sym(m, "x"), msg)) { return -4; }
    return 0;
}

fn i32 expr_stmt_missing_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { foo() }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got '}'", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)20, msg)) { return -3; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -4; }
    ast::ExprStmtNode* es = compiler_testing::expect_expr_stmt(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!es) { return -5; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)es), msg)) { return -6; }
    return 0;
}

fn i32 expr_stmt_two_consecutive_calls(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { foo(); bar(); }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_expr_stmt(body.stmts.ptr[0], msg)) { return -4; }
    if(!compiler_testing::expect_expr_stmt(body.stmts.ptr[1], msg)) { return -5; }
    return 0;
}

fn i32 expr_stmt_mixed_with_var_decl_and_return(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 x = 1; foo(x); return; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 3, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "x"), false, false, msg)) { return -4; }
    if(!compiler_testing::expect_expr_stmt(body.stmts.ptr[1], msg)) { return -5; }
    if(!compiler_testing::expect_return(body.stmts.ptr[2], msg)) { return -6; }
    return 0;
}

fn i32 expr_stmt_assignment_to_namespaced_lhs(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { mod::counter = 0; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::AssignmentNode* an = compiler_testing::expect_assign(compiler_testing::nth_stmt(f.body, 0), token::TokenKind::Eq, msg);
    if(!an) { return -3; }
    if(!compiler_testing::expect_nsacc(an.lhs, compiler_testing::sym(m, "mod"), compiler_testing::sym(m, "counter"), msg)) { return -4; }
    return 0;
}

fn i32 expr_stmt_cast(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { (i32)x; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::ExprStmtNode* es = compiler_testing::expect_expr_stmt(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!es) { return -3; }
    if(!compiler_testing::expect_cast(es.expr, msg)) { return -4; }
    return 0;
}

// ============================================================================
// NESTED BLOCKS
// ============================================================================

fn i32 block_empty_inner(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* outer = compiler_testing::expect_block(f.body, 1, msg);
    if(!outer) { return -2; }
    if(!compiler_testing::expect_block(outer.stmts.ptr[0], 0, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 block_inner_single_stmt(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { i32 x = 5; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* outer = compiler_testing::expect_block(f.body, 1, msg);
    if(!outer) { return -2; }
    ast::BlockNode* inner = compiler_testing::expect_block(outer.stmts.ptr[0], 1, msg);
    if(!inner) { return -3; }
    ast::VarDeclNode* v = compiler_testing::expect_var(inner.stmts.ptr[0], compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -4; }
    if(!compiler_testing::expect_intlit(v.init, 5, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 block_two_sibling_inner_blocks(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { i32 a = 1; } { i32 b = 2; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* outer = compiler_testing::expect_block(f.body, 2, msg);
    if(!outer) { return -2; }
    ast::BlockNode* b0 = compiler_testing::expect_block(outer.stmts.ptr[0], 1, msg);
    if(!b0) { return -3; }
    if(!compiler_testing::expect_var(b0.stmts.ptr[0], compiler_testing::sym(m, "a"), false, false, msg)) { return -4; }
    ast::BlockNode* b1 = compiler_testing::expect_block(outer.stmts.ptr[1], 1, msg);
    if(!b1) { return -5; }
    if(!compiler_testing::expect_var(b1.stmts.ptr[0], compiler_testing::sym(m, "b"), false, false, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 block_triple_nested(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* l1 = compiler_testing::expect_block(f.body, 1, msg);
    if(!l1) { return -2; }
    ast::BlockNode* l2 = compiler_testing::expect_block(l1.stmts.ptr[0], 1, msg);
    if(!l2) { return -3; }
    if(!compiler_testing::expect_block(l2.stmts.ptr[0], 0, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 block_mixed_stmts_and_inner(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 a = 1; { i32 b = 2; } i32 c = 3; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* outer = compiler_testing::expect_block(f.body, 3, msg);
    if(!outer) { return -2; }
    if(!compiler_testing::expect_var(outer.stmts.ptr[0], compiler_testing::sym(m, "a"), false, false, msg)) { return -3; }
    ast::BlockNode* inner = compiler_testing::expect_block(outer.stmts.ptr[1], 1, msg);
    if(!inner) { return -4; }
    if(!compiler_testing::expect_var(inner.stmts.ptr[0], compiler_testing::sym(m, "b"), false, false, msg)) { return -5; }
    if(!compiler_testing::expect_var(outer.stmts.ptr[2], compiler_testing::sym(m, "c"), false, false, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 block_inner_error_propagates(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { i32 x = 5 } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)f), msg)) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag(f.body), msg)) { return -3; }
    ast::BlockNode* outer = (ast::BlockNode*)f.body;
    if(!testing::expect_true(compiler_testing::has_error_flag(outer.stmts.ptr[0]), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got '}'", msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 26, msg)) { return -6; }
    return 0;
}

fn i32 block_unclosed_inner(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)f), msg)) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag(f.body), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '}', got end of file", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 28, msg)) { return -5; }
    return 0;
}

// `fn void f() { { } }` — inner `{` at byte 14
fn i32 block_src_pos_on_inner_lbrace(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* outer = compiler_testing::expect_block(f.body, 1, msg);
    if(!outer) { return -2; }
    ast::BlockNode* inner = compiler_testing::expect_block(outer.stmts.ptr[0], 0, msg);
    if(!inner) { return -3; }
    if(!testing::expect_eq(inner.h.src_pos, 14, msg)) { return -4; }
    return 0;
}

fn i32 block_deeply_nested_var(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { { { i32 deep = 42; } } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* l1 = compiler_testing::expect_block(f.body, 1, msg);
    if(!l1) { return -2; }
    ast::BlockNode* l2 = compiler_testing::expect_block(l1.stmts.ptr[0], 1, msg);
    if(!l2) { return -3; }
    ast::BlockNode* l3 = compiler_testing::expect_block(l2.stmts.ptr[0], 1, msg);
    if(!l3) { return -4; }
    ast::BlockNode* l4 = compiler_testing::expect_block(l3.stmts.ptr[0], 1, msg);
    if(!l4) { return -5; }
    ast::VarDeclNode* v = compiler_testing::expect_var(l4.stmts.ptr[0], compiler_testing::sym(m, "deep"), false, false, msg);
    if(!v) { return -6; }
    if(!compiler_testing::expect_intlit(v.init, 42, msg)) { return -7; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -8; }
    return 0;
}

fn i32 block_clean_outer_no_error_flag(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { i32 x = 5; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)f), msg)) { return -2; }
    if(!testing::expect_false(compiler_testing::has_error_flag(f.body), msg)) { return -3; }
    ast::BlockNode* outer = (ast::BlockNode*)f.body;
    if(!testing::expect_false(compiler_testing::has_error_flag(outer.stmts.ptr[0]), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 block_inner_multi_stmt(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { i32 a = 1; i32 b = 2; i32 c = 3; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* outer = compiler_testing::expect_block(f.body, 1, msg);
    if(!outer) { return -2; }
    ast::BlockNode* inner = compiler_testing::expect_block(outer.stmts.ptr[0], 3, msg);
    if(!inner) { return -3; }
    if(!compiler_testing::expect_var(inner.stmts.ptr[0], compiler_testing::sym(m, "a"), false, false, msg)) { return -4; }
    if(!compiler_testing::expect_var(inner.stmts.ptr[1], compiler_testing::sym(m, "b"), false, false, msg)) { return -5; }
    if(!compiler_testing::expect_var(inner.stmts.ptr[2], compiler_testing::sym(m, "c"), false, false, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 block_sibling_error_isolation(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { i32 x = 5 } { i32 y = 6; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* outer = compiler_testing::expect_block(f.body, 2, msg);
    if(!outer) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag(outer.stmts.ptr[0]), msg)) { return -3; }
    if(!testing::expect_false(compiler_testing::has_error_flag(outer.stmts.ptr[1]), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got '}'", msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 26, msg)) { return -6; }
    return 0;
}

// `fn void f() { ... }` — outer `{` at byte 12
fn i32 block_outer_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 x; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_eq(f.body.h.src_pos, 12, msg)) { return -2; }
    return 0;
}

fn i32 block_recovery_resumes_outer(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { i32 x = 5 } i32 y = 6; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* outer = compiler_testing::expect_block(f.body, 2, msg);
    if(!outer) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag(outer.stmts.ptr[0]), msg)) { return -3; }
    ast::VarDeclNode* y = compiler_testing::expect_var(outer.stmts.ptr[1], compiler_testing::sym(m, "y"), false, false, msg);
    if(!y) { return -4; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)y), msg)) { return -5; }
    if(!compiler_testing::expect_intlit(y.init, 6, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got '}'", msg)) { return -7; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 26, msg)) { return -8; }
    return 0;
}

fn i32 block_many_stmts_growth(arena::Arena* a, u8[] msg) {
    arena::Arena local = {16384, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local,
        "fn void f() { i32 s0 = 0; i32 s1 = 1; i32 s2 = 2; i32 s3 = 3; i32 s4 = 4; i32 s5 = 5; i32 s6 = 6; i32 s7 = 7; i32 s8 = 8; i32 s9 = 9; i32 s10 = 10; i32 s11 = 11; }",
        &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 12, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "s0"), false, false, msg)) { return -3; }
    if(!compiler_testing::expect_var(body.stmts.ptr[7], compiler_testing::sym(m, "s7"), false, false, msg)) { return -4; }
    if(!compiler_testing::expect_var(body.stmts.ptr[8], compiler_testing::sym(m, "s8"), false, false, msg)) { return -5; }
    if(!compiler_testing::expect_var(body.stmts.ptr[11], compiler_testing::sym(m, "s11"), false, false, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 block_multiple_garbage_tokens(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { ; ; ; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 3, msg);
    if(!body) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag(body.stmts.ptr[0]), msg)) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag(body.stmts.ptr[1]), msg)) { return -4; }
    if(!testing::expect_true(compiler_testing::has_error_flag(body.stmts.ptr[2]), msg)) { return -5; }
    if(!testing::expect_true(compiler_testing::has_error_flag(f.body), msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got ';'", msg)) { return -7; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 14, msg)) { return -8; }
    return 0;
}

fn i32 block_all_error_stmts(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 a = ; i32 b = ; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag(body.stmts.ptr[0]), msg)) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag(body.stmts.ptr[1]), msg)) { return -4; }
    if(!testing::expect_true(compiler_testing::has_error_flag(f.body), msg)) { return -5; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)f), msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ';'", msg)) { return -7; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 22, msg)) { return -8; }
    return 0;
}

fn i32 block_error_interleaved_with_valid(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 a = 1; ; i32 b = 2; ; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 4, msg);
    if(!body) { return -2; }
    ast::VarDeclNode* a_node = compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "a"), false, false, msg);
    if(!a_node) { return -3; }
    if(!testing::expect_false(compiler_testing::has_error_flag(body.stmts.ptr[0]), msg)) { return -4; }
    if(!testing::expect_true(compiler_testing::has_error_flag(body.stmts.ptr[1]), msg)) { return -5; }
    ast::VarDeclNode* b_node = compiler_testing::expect_var(body.stmts.ptr[2], compiler_testing::sym(m, "b"), false, false, msg);
    if(!b_node) { return -6; }
    if(!testing::expect_false(compiler_testing::has_error_flag(body.stmts.ptr[2]), msg)) { return -7; }
    if(!testing::expect_true(compiler_testing::has_error_flag(body.stmts.ptr[3]), msg)) { return -8; }
    if(!testing::expect_true(compiler_testing::has_error_flag(f.body), msg)) { return -9; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got ';'", msg)) { return -10; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 25, msg)) { return -11; }
    return 0;
}

fn i32 block_unrecognized_leading_token(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { ; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 1, msg);
    if(!body) { return -2; }
    if(!testing::expect_eq((u16)body.stmts.ptr[0].h.kind, (u16)ast::AstKind::ERROR, msg)) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag(body.stmts.ptr[0]), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got ';'", msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 14, msg)) { return -6; }
    return 0;
}

fn i32 block_unclosed_inner_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { i32 x = 5;", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)f), msg)) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag(f.body), msg)) { return -3; }
    ast::BlockNode* outer = (ast::BlockNode*)f.body;
    if(!testing::expect_true(compiler_testing::has_error_flag(outer.stmts.ptr[0]), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '}', got end of file", msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 26, msg)) { return -6; }
    return 0;
}

fn i32 block_no_lbrace_returns_error(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f();", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 0, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)f), msg)) { return -2; }
    if(!testing::expect_not_null((void*)f.body, msg)) { return -3; }
    if(!testing::expect_eq((u16)f.body.h.kind, (u16)ast::AstKind::ERROR, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '{', got ';'", msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 11, msg)) { return -6; }
    return 0;
}

// ============================================================================
// RETURN STMTS
// ============================================================================

fn i32 return_bare(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { return; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 1, msg);
    if(!body) { return -2; }
    ast::ReturnNode* r = compiler_testing::expect_return(body.stmts.ptr[0], msg);
    if(!r) { return -3; }
    if(!testing::expect_null((void*)r.expr, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 return_intlit(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return 42; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!compiler_testing::expect_intlit(r.expr, 42, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 return_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return x; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!compiler_testing::expect_ident(r.expr, compiler_testing::sym(m, "x"), msg)) { return -3; }
    return 0;
}

fn i32 return_null(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32* f() { return null; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!compiler_testing::expect_nulllit(r.expr, msg)) { return -3; }
    return 0;
}

fn i32 return_bool(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn bool f() { return true; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!compiler_testing::expect_boollit(r.expr, true, msg)) { return -3; }
    return 0;
}

fn i32 return_pratt_expr(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return 1 + 2 * 3; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::BinaryOpNode* plus = compiler_testing::expect_binop(r.expr, token::TokenKind::Plus, msg);
    if(!plus) { return -3; }
    if(!compiler_testing::expect_intlit(plus.lhs, 1, msg)) { return -4; }
    ast::BinaryOpNode* mul = compiler_testing::expect_binop(plus.rhs, token::TokenKind::Star, msg);
    if(!mul) { return -5; }
    if(!compiler_testing::expect_intlit(mul.lhs, 2, msg)) { return -6; }
    if(!compiler_testing::expect_intlit(mul.rhs, 3, msg)) { return -7; }
    return 0;
}

fn i32 return_unary(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return -x; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::UnaryOpNode* u = compiler_testing::expect_unop(r.expr, token::TokenKind::Minus, msg);
    if(!u) { return -3; }
    if(!compiler_testing::expect_ident(u.operand, compiler_testing::sym(m, "x"), msg)) { return -4; }
    return 0;
}

fn i32 return_deref(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return *p; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::UnaryOpNode* u = compiler_testing::expect_unop(r.expr, token::TokenKind::Star, msg);
    if(!u) { return -3; }
    if(!compiler_testing::expect_ident(u.operand, compiler_testing::sym(m, "p"), msg)) { return -4; }
    return 0;
}

fn i32 return_call(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return g(1, 2); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::CallNode* c = compiler_testing::expect_call(r.expr, 2, msg);
    if(!c) { return -3; }
    if(!compiler_testing::expect_ident(c.callee, compiler_testing::sym(m, "g"), msg)) { return -4; }
    if(!compiler_testing::expect_intlit(c.args.ptr[0], 1, msg)) { return -5; }
    if(!compiler_testing::expect_intlit(c.args.ptr[1], 2, msg)) { return -6; }
    return 0;
}

fn i32 return_cast(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return (i32)y; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::CastNode* c = compiler_testing::expect_cast(r.expr, msg);
    if(!c) { return -3; }
    if(!compiler_testing::expect_ty_prim(c.target_type, token::TokenKind::I32, msg)) { return -4; }
    if(!compiler_testing::expect_ident(c.expr, compiler_testing::sym(m, "y"), msg)) { return -5; }
    return 0;
}

fn i32 return_struct_lit(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn Foo f() { return { 1, 2 }; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::StructLitNode* sl = compiler_testing::expect_struct_lit(r.expr, 2, msg);
    if(!sl) { return -3; }
    if(!compiler_testing::expect_intlit(sl.inits[0].value, 1, msg)) { return -4; }
    if(!compiler_testing::expect_intlit(sl.inits[1].value, 2, msg)) { return -5; }
    return 0;
}

fn i32 return_array_lit(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32[3] f() { return [1, 2, 3]; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::ArrayLitNode* al = compiler_testing::expect_array_lit(r.expr, 3, msg);
    if(!al) { return -3; }
    if(!compiler_testing::expect_intlit(al.elems.ptr[0], 1, msg)) { return -4; }
    if(!compiler_testing::expect_intlit(al.elems.ptr[2], 3, msg)) { return -5; }
    return 0;
}

fn i32 return_member_chain(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return obj.field.sub; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::MemberAccessNode* sub = compiler_testing::expect_member(r.expr, compiler_testing::sym(m, "sub"), msg);
    if(!sub) { return -3; }
    ast::MemberAccessNode* field = compiler_testing::expect_member(sub.base, compiler_testing::sym(m, "field"), msg);
    if(!field) { return -4; }
    if(!compiler_testing::expect_ident(field.base, compiler_testing::sym(m, "obj"), msg)) { return -5; }
    return 0;
}

fn i32 return_with_other_stmts(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { i32 x = 5; return x; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "x"), false, false, msg)) { return -3; }
    ast::ReturnNode* r = compiler_testing::expect_return(body.stmts.ptr[1], msg);
    if(!r) { return -4; }
    if(!compiler_testing::expect_ident(r.expr, compiler_testing::sym(m, "x"), msg)) { return -5; }
    return 0;
}

fn i32 return_inside_nested_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { { return 7; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* outer = compiler_testing::expect_block(f.body, 1, msg);
    if(!outer) { return -2; }
    ast::BlockNode* inner = compiler_testing::expect_block(outer.stmts.ptr[0], 1, msg);
    if(!inner) { return -3; }
    ast::ReturnNode* r = compiler_testing::expect_return(inner.stmts.ptr[0], msg);
    if(!r) { return -4; }
    if(!compiler_testing::expect_intlit(r.expr, 7, msg)) { return -5; }
    return 0;
}

// `fn i32 f() { return 5; }` — `return` at byte 13
fn i32 return_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!testing::expect_eq(r.h.src_pos, 13, msg)) { return -3; }
    return 0;
}

fn i32 return_missing_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return 5 }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)r), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got '}'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 22, msg)) { return -5; }
    return 0;
}

fn i32 return_missing_expr_no_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)r), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got '}'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 20, msg)) { return -5; }
    return 0;
}

fn i32 return_floatlit(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn f64 f() { return 3.14; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!compiler_testing::expect_floatlit(r.expr, 3.14, msg)) { return -3; }
    return 0;
}

fn i32 return_charlit(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn u8 f() { return 'a'; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!compiler_testing::expect_charlit(r.expr, 'a', msg)) { return -3; }
    return 0;
}

fn i32 return_strlit(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn u8* f() { return \"hi\"; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!testing::expect_not_null((void*)r.expr, msg)) { return -3; }
    if(!testing::expect_eq((u16)r.expr.h.kind, (u16)ast::AstKind::StringLit, msg)) { return -4; }
    return 0;
}

fn i32 return_false(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn bool f() { return false; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!compiler_testing::expect_boollit(r.expr, false, msg)) { return -3; }
    return 0;
}

fn i32 return_undefined(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return undefined; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!compiler_testing::expect_undeflit(r.expr, msg)) { return -3; }
    return 0;
}

fn i32 return_unary_bang(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn bool f() { return !x; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::UnaryOpNode* u = compiler_testing::expect_unop(r.expr, token::TokenKind::Bang, msg);
    if(!u) { return -3; }
    if(!compiler_testing::expect_ident(u.operand, compiler_testing::sym(m, "x"), msg)) { return -4; }
    return 0;
}

fn i32 return_unary_tilde(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return ~x; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::UnaryOpNode* u = compiler_testing::expect_unop(r.expr, token::TokenKind::Tilde, msg);
    if(!u) { return -3; }
    if(!compiler_testing::expect_ident(u.operand, compiler_testing::sym(m, "x"), msg)) { return -4; }
    return 0;
}

fn i32 return_unary_addrof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32* f() { return &x; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::UnaryOpNode* u = compiler_testing::expect_unop(r.expr, token::TokenKind::Amp, msg);
    if(!u) { return -3; }
    if(!compiler_testing::expect_ident(u.operand, compiler_testing::sym(m, "x"), msg)) { return -4; }
    return 0;
}

fn i32 return_array_index(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return arr[0]; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::ArrayIndexNode* ai = compiler_testing::expect_index(r.expr, msg);
    if(!ai) { return -3; }
    if(!compiler_testing::expect_ident(ai.base, compiler_testing::sym(m, "arr"), msg)) { return -4; }
    if(!compiler_testing::expect_intlit(ai.index, 0, msg)) { return -5; }
    return 0;
}

fn i32 return_slice_range(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32[] f() { return arr[1..4]; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::SliceRangeNode* sr = compiler_testing::expect_slice_range(r.expr, msg);
    if(!sr) { return -3; }
    if(!compiler_testing::expect_ident(sr.base, compiler_testing::sym(m, "arr"), msg)) { return -4; }
    if(!compiler_testing::expect_intlit(sr.lo, 1, msg)) { return -5; }
    if(!compiler_testing::expect_intlit(sr.hi, 4, msg)) { return -6; }
    return 0;
}

fn i32 return_paren(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return (1 + 2); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!testing::expect_true(compiler_testing::has_paren_flag(r.expr), msg)) { return -3; }
    ast::BinaryOpNode* b = compiler_testing::expect_binop(r.expr, token::TokenKind::Plus, msg);
    if(!b) { return -4; }
    if(!compiler_testing::expect_intlit(b.lhs, 1, msg)) { return -5; }
    if(!compiler_testing::expect_intlit(b.rhs, 2, msg)) { return -6; }
    return 0;
}

fn i32 return_namespace_access(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return io::stdout; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!compiler_testing::expect_nsacc(r.expr, compiler_testing::sym(m, "io"), compiler_testing::sym(m, "stdout"), msg)) { return -3; }
    return 0;
}

fn i32 return_namespace_access_three_levels(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return mod::Color::Red; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -3; }
    if(!compiler_testing::expect_nsacc3(r.expr,
            compiler_testing::sym(m, "mod"),
            compiler_testing::sym(m, "Color"),
            compiler_testing::sym(m, "Red"), msg)) { return -4; }
    return 0;
}

fn i32 return_namespace_access_four_levels(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return a::b::c::d; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -3; }
    if(!testing::expect_eq((u16)r.expr.h.kind, (u16)ast::AstKind::NamespaceAccess, msg)) { return -4; }
    ast::NamespaceAccessNode* outer = (ast::NamespaceAccessNode*)r.expr;
    if(!testing::expect_eq((void*)outer.name, (void*)compiler_testing::sym(m, "d"), msg)) { return -5; }
    if(!compiler_testing::expect_nsacc3(outer.base,
            compiler_testing::sym(m, "a"),
            compiler_testing::sym(m, "b"),
            compiler_testing::sym(m, "c"), msg)) { return -6; }
    return 0;
}

fn i32 return_designated_struct_lit(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn Foo f() { return { .a = 1 }; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::StructLitNode* sl = compiler_testing::expect_struct_lit(r.expr, 1, msg);
    if(!sl) { return -3; }
    if(!compiler_testing::expect_field_init(&sl.inits[0], compiler_testing::sym(m, "a"), msg)) { return -4; }
    if(!compiler_testing::expect_intlit(sl.inits[0].value, 1, msg)) { return -5; }
    return 0;
}

fn i32 return_comparison(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn bool f() { return x == y; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::BinaryOpNode* b = compiler_testing::expect_binop(r.expr, token::TokenKind::EqEq, msg);
    if(!b) { return -3; }
    if(!compiler_testing::expect_ident(b.lhs, compiler_testing::sym(m, "x"), msg)) { return -4; }
    if(!compiler_testing::expect_ident(b.rhs, compiler_testing::sym(m, "y"), msg)) { return -5; }
    return 0;
}

fn i32 return_logical_and(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn bool f() { return a && b; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::BinaryOpNode* b = compiler_testing::expect_binop(r.expr, token::TokenKind::AmpAmp, msg);
    if(!b) { return -3; }
    if(!compiler_testing::expect_ident(b.lhs, compiler_testing::sym(m, "a"), msg)) { return -4; }
    if(!compiler_testing::expect_ident(b.rhs, compiler_testing::sym(m, "b"), msg)) { return -5; }
    return 0;
}

fn i32 return_two_consecutive(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return 1; return 2; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    ast::ReturnNode* r0 = compiler_testing::expect_return(body.stmts.ptr[0], msg);
    if(!r0) { return -3; }
    if(!compiler_testing::expect_intlit(r0.expr, 1, msg)) { return -4; }
    ast::ReturnNode* r1 = compiler_testing::expect_return(body.stmts.ptr[1], msg);
    if(!r1) { return -5; }
    if(!compiler_testing::expect_intlit(r1.expr, 2, msg)) { return -6; }
    return 0;
}

fn i32 return_in_middle_of_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { i32 a = 1; return a; i32 b = 2; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 3, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "a"), false, false, msg)) { return -3; }
    ast::ReturnNode* r = compiler_testing::expect_return(body.stmts.ptr[1], msg);
    if(!r) { return -4; }
    if(!compiler_testing::expect_ident(r.expr, compiler_testing::sym(m, "a"), msg)) { return -5; }
    if(!compiler_testing::expect_var(body.stmts.ptr[2], compiler_testing::sym(m, "b"), false, false, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 return_trailing_tokens_before_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return 5 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)r), msg)) { return -3; }
    if(!compiler_testing::expect_intlit(r.expr, 5, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got integer literal", msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 22, msg)) { return -6; }
    return 0;
}

fn i32 return_missing_semi_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return 5", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)r), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got end of file", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 21, msg)) { return -5; }
    return 0;
}

fn i32 return_unary_no_operand(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return *; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)r), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ';'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 21, msg)) { return -5; }
    return 0;
}

fn i32 return_malformed_expr(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { return = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)r), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got '='", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 20, msg)) { return -5; }
    return 0;
}

// ============================================================================
// IF STMTS
// ============================================================================

fn i32 if_basic_no_else(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (x) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    if(!compiler_testing::expect_ident(i.cond, compiler_testing::sym(m, "x"), msg)) { return -3; }
    if(!compiler_testing::expect_block(i.then_block, 0, msg)) { return -4; }
    if(!testing::expect_null((void*)i.else_block, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 if_else(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { if (x) { return 1; } else { return 2; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    if(!compiler_testing::expect_ident(i.cond, compiler_testing::sym(m, "x"), msg)) { return -3; }
    ast::BlockNode* then_b = compiler_testing::expect_block(i.then_block, 1, msg);
    if(!then_b) { return -4; }
    ast::ReturnNode* r1 = compiler_testing::expect_return(then_b.stmts.ptr[0], msg);
    if(!r1) { return -5; }
    if(!compiler_testing::expect_intlit(r1.expr, 1, msg)) { return -6; }
    ast::BlockNode* else_b = compiler_testing::expect_block(i.else_block, 1, msg);
    if(!else_b) { return -7; }
    ast::ReturnNode* r2 = compiler_testing::expect_return(else_b.stmts.ptr[0], msg);
    if(!r2) { return -8; }
    if(!compiler_testing::expect_intlit(r2.expr, 2, msg)) { return -9; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -10; }
    return 0;
}

fn i32 if_else_if(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (x) { } else if (y) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* outer = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!outer) { return -2; }
    if(!compiler_testing::expect_ident(outer.cond, compiler_testing::sym(m, "x"), msg)) { return -3; }
    ast::IfNode* inner = compiler_testing::expect_if(outer.else_block, msg);
    if(!inner) { return -4; }
    if(!compiler_testing::expect_ident(inner.cond, compiler_testing::sym(m, "y"), msg)) { return -5; }
    if(!testing::expect_null((void*)inner.else_block, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 if_else_if_else(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (x) { } else if (y) { } else { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* outer = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!outer) { return -2; }
    if(!compiler_testing::expect_ident(outer.cond, compiler_testing::sym(m, "x"), msg)) { return -3; }
    ast::IfNode* inner = compiler_testing::expect_if(outer.else_block, msg);
    if(!inner) { return -4; }
    if(!compiler_testing::expect_ident(inner.cond, compiler_testing::sym(m, "y"), msg)) { return -5; }
    if(!compiler_testing::expect_block(inner.else_block, 0, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 if_chain_three(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local,
        "fn void f() { if (a) { } else if (b) { } else if (c) { } else { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* l1 = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!l1) { return -2; }
    if(!compiler_testing::expect_ident(l1.cond, compiler_testing::sym(m, "a"), msg)) { return -3; }
    ast::IfNode* l2 = compiler_testing::expect_if(l1.else_block, msg);
    if(!l2) { return -4; }
    if(!compiler_testing::expect_ident(l2.cond, compiler_testing::sym(m, "b"), msg)) { return -5; }
    ast::IfNode* l3 = compiler_testing::expect_if(l2.else_block, msg);
    if(!l3) { return -6; }
    if(!compiler_testing::expect_ident(l3.cond, compiler_testing::sym(m, "c"), msg)) { return -7; }
    if(!compiler_testing::expect_block(l3.else_block, 0, msg)) { return -8; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -9; }
    return 0;
}

fn i32 if_chain_no_terminal_else(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local,
        "fn void f() { if (a) { } else if (b) { } else if (c) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* l1 = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!l1) { return -2; }
    ast::IfNode* l2 = compiler_testing::expect_if(l1.else_block, msg);
    if(!l2) { return -3; }
    ast::IfNode* l3 = compiler_testing::expect_if(l2.else_block, msg);
    if(!l3) { return -4; }
    if(!testing::expect_null((void*)l3.else_block, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 if_cond_pratt(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (a + b * 2 == 5) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    ast::BinaryOpNode* eq = compiler_testing::expect_binop(i.cond, token::TokenKind::EqEq, msg);
    if(!eq) { return -3; }
    ast::BinaryOpNode* plus = compiler_testing::expect_binop(eq.lhs, token::TokenKind::Plus, msg);
    if(!plus) { return -4; }
    if(!compiler_testing::expect_ident(plus.lhs, compiler_testing::sym(m, "a"), msg)) { return -5; }
    ast::BinaryOpNode* mul = compiler_testing::expect_binop(plus.rhs, token::TokenKind::Star, msg);
    if(!mul) { return -6; }
    if(!compiler_testing::expect_ident(mul.lhs, compiler_testing::sym(m, "b"), msg)) { return -7; }
    if(!compiler_testing::expect_intlit(mul.rhs, 2, msg)) { return -8; }
    if(!compiler_testing::expect_intlit(eq.rhs, 5, msg)) { return -9; }
    return 0;
}

fn i32 if_cond_call(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (foo(1)) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    ast::CallNode* c = compiler_testing::expect_call(i.cond, 1, msg);
    if(!c) { return -3; }
    if(!compiler_testing::expect_ident(c.callee, compiler_testing::sym(m, "foo"), msg)) { return -4; }
    if(!compiler_testing::expect_intlit(c.args.ptr[0], 1, msg)) { return -5; }
    return 0;
}

fn i32 if_cond_logical(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (a && b) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    ast::BinaryOpNode* b = compiler_testing::expect_binop(i.cond, token::TokenKind::AmpAmp, msg);
    if(!b) { return -3; }
    if(!compiler_testing::expect_ident(b.lhs, compiler_testing::sym(m, "a"), msg)) { return -4; }
    if(!compiler_testing::expect_ident(b.rhs, compiler_testing::sym(m, "b"), msg)) { return -5; }
    return 0;
}

fn i32 if_cond_comparison(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (x > 0) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    ast::BinaryOpNode* b = compiler_testing::expect_binop(i.cond, token::TokenKind::GT, msg);
    if(!b) { return -3; }
    if(!compiler_testing::expect_ident(b.lhs, compiler_testing::sym(m, "x"), msg)) { return -4; }
    if(!compiler_testing::expect_intlit(b.rhs, 0, msg)) { return -5; }
    return 0;
}

fn i32 if_cond_unary(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (!flag) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    ast::UnaryOpNode* u = compiler_testing::expect_unop(i.cond, token::TokenKind::Bang, msg);
    if(!u) { return -3; }
    if(!compiler_testing::expect_ident(u.operand, compiler_testing::sym(m, "flag"), msg)) { return -4; }
    return 0;
}

fn i32 if_then_body_multi_stmts(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { if (x) { i32 y = 1; return y; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    ast::BlockNode* then_b = compiler_testing::expect_block(i.then_block, 2, msg);
    if(!then_b) { return -3; }
    if(!compiler_testing::expect_var(then_b.stmts.ptr[0], compiler_testing::sym(m, "y"), false, false, msg)) { return -4; }
    if(!compiler_testing::expect_return(then_b.stmts.ptr[1], msg)) { return -5; }
    return 0;
}

fn i32 if_nested(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (a) { if (b) { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* outer = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!outer) { return -2; }
    if(!compiler_testing::expect_ident(outer.cond, compiler_testing::sym(m, "a"), msg)) { return -3; }
    ast::BlockNode* outer_then = compiler_testing::expect_block(outer.then_block, 1, msg);
    if(!outer_then) { return -4; }
    ast::IfNode* inner = compiler_testing::expect_if(outer_then.stmts.ptr[0], msg);
    if(!inner) { return -5; }
    if(!compiler_testing::expect_ident(inner.cond, compiler_testing::sym(m, "b"), msg)) { return -6; }
    return 0;
}

fn i32 if_combined_with_var_and_return(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { i32 x = 5; if (x) { return 1; } return 2; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 3, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "x"), false, false, msg)) { return -3; }
    ast::IfNode* i = compiler_testing::expect_if(body.stmts.ptr[1], msg);
    if(!i) { return -4; }
    if(!compiler_testing::expect_ident(i.cond, compiler_testing::sym(m, "x"), msg)) { return -5; }
    ast::ReturnNode* r = compiler_testing::expect_return(body.stmts.ptr[2], msg);
    if(!r) { return -6; }
    if(!compiler_testing::expect_intlit(r.expr, 2, msg)) { return -7; }
    return 0;
}

// `fn void f() { if (x) { } }` — `if` at byte 14
fn i32 if_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (x) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    if(!testing::expect_eq(i.h.src_pos, 14, msg)) { return -3; }
    return 0;
}

fn i32 if_missing_lparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if x) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)i), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '(', got identifier", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 17, msg)) { return -5; }
    return 0;
}

fn i32 if_missing_rparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (x { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)i), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ')', got '{'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 20, msg)) { return -5; }
    return 0;
}

fn i32 if_missing_then_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (x) ; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)i), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '{', got ';'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 21, msg)) { return -5; }
    return 0;
}

fn i32 if_empty_cond(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if () { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)i), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ')'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 18, msg)) { return -5; }
    return 0;
}

fn i32 if_else_missing_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (x) { } else ; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)i), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '{', got ';'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 30, msg)) { return -5; }
    return 0;
}

fn i32 if_else_if_missing_lparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (x) { } else if y) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* outer = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!outer) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)outer), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '(', got identifier", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 33, msg)) { return -5; }
    return 0;
}

fn i32 if_else_body_multi_stmts(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { if (x) {} else { i32 a = 1; return a; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    if(!compiler_testing::expect_block(i.then_block, 0, msg)) { return -3; }
    ast::BlockNode* else_b = compiler_testing::expect_block(i.else_block, 2, msg);
    if(!else_b) { return -4; }
    if(!compiler_testing::expect_var(else_b.stmts.ptr[0], compiler_testing::sym(m, "a"), false, false, msg)) { return -5; }
    if(!compiler_testing::expect_return(else_b.stmts.ptr[1], msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 if_else_in_then_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (a) { if (b) {} else {} } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* outer = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!outer) { return -2; }
    if(!compiler_testing::expect_ident(outer.cond, compiler_testing::sym(m, "a"), msg)) { return -3; }
    if(!testing::expect_null((void*)outer.else_block, msg)) { return -4; }
    ast::BlockNode* outer_then = compiler_testing::expect_block(outer.then_block, 1, msg);
    if(!outer_then) { return -5; }
    ast::IfNode* inner = compiler_testing::expect_if(outer_then.stmts.ptr[0], msg);
    if(!inner) { return -6; }
    if(!compiler_testing::expect_ident(inner.cond, compiler_testing::sym(m, "b"), msg)) { return -7; }
    if(!compiler_testing::expect_block(inner.then_block, 0, msg)) { return -8; }
    if(!compiler_testing::expect_block(inner.else_block, 0, msg)) { return -9; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -10; }
    return 0;
}

fn i32 if_body_error_propagates(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (x) { return 5 5; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)i), msg)) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag(i.then_block), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got integer literal", msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 32, msg)) { return -6; }
    return 0;
}

fn i32 if_else_without_if(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { else { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    if(!testing::expect_eq((u16)body.stmts.ptr[0].h.kind, (u16)ast::AstKind::ERROR, msg)) { return -3; }
    if(!compiler_testing::expect_block(body.stmts.ptr[1], 0, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got 'else'", msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 14, msg)) { return -6; }
    return 0;
}

fn i32 if_double_else(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (x) {} else {} else {} }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 3, msg);
    if(!body) { return -2; }
    ast::IfNode* i = compiler_testing::expect_if(body.stmts.ptr[0], msg);
    if(!i) { return -3; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)i), msg)) { return -4; }
    if(!testing::expect_eq((u16)body.stmts.ptr[1].h.kind, (u16)ast::AstKind::ERROR, msg)) { return -5; }
    if(!compiler_testing::expect_block(body.stmts.ptr[2], 0, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got 'else'", msg)) { return -7; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 32, msg)) { return -8; }
    return 0;
}

fn i32 if_two_consecutive_at_same_level(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (a) {} if (b) {} }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    ast::IfNode* i0 = compiler_testing::expect_if(body.stmts.ptr[0], msg);
    if(!i0) { return -3; }
    if(!compiler_testing::expect_ident(i0.cond, compiler_testing::sym(m, "a"), msg)) { return -4; }
    if(!testing::expect_null((void*)i0.else_block, msg)) { return -5; }
    ast::IfNode* i1 = compiler_testing::expect_if(body.stmts.ptr[1], msg);
    if(!i1) { return -6; }
    if(!compiler_testing::expect_ident(i1.cond, compiler_testing::sym(m, "b"), msg)) { return -7; }
    if(!testing::expect_null((void*)i1.else_block, msg)) { return -8; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -9; }
    return 0;
}

fn i32 if_else_block_missing_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (x) {} else", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)i), msg)) { return -3; }
    if(!testing::expect_not_null((void*)i.else_block, msg)) { return -4; }
    if(!testing::expect_eq((u16)i.else_block.h.kind, (u16)ast::AstKind::ERROR, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '{', got end of file", msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 28, msg)) { return -7; }
    return 0;
}

fn i32 if_body_contains_nested_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (x) { { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    ast::BlockNode* then_b = compiler_testing::expect_block(i.then_block, 1, msg);
    if(!then_b) { return -3; }
    if(!compiler_testing::expect_block(then_b.stmts.ptr[0], 0, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 if_else_body_with_nested_if(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (a) {} else { if (b) {} } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* outer = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!outer) { return -2; }
    if(!compiler_testing::expect_ident(outer.cond, compiler_testing::sym(m, "a"), msg)) { return -3; }
    ast::BlockNode* else_b = compiler_testing::expect_block(outer.else_block, 1, msg);
    if(!else_b) { return -4; }
    ast::IfNode* inner = compiler_testing::expect_if(else_b.stmts.ptr[0], msg);
    if(!inner) { return -5; }
    if(!compiler_testing::expect_ident(inner.cond, compiler_testing::sym(m, "b"), msg)) { return -6; }
    if(!testing::expect_null((void*)inner.else_block, msg)) { return -7; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -8; }
    return 0;
}

fn i32 if_else_if_missing_rparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (x) {} else if (y { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* outer = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!outer) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)outer), msg)) { return -3; }
    ast::IfNode* inner = compiler_testing::expect_if(outer.else_block, msg);
    if(!inner) { return -4; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)inner), msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ')', got '{'", msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 35, msg)) { return -7; }
    return 0;
}

fn i32 if_else_if_missing_then_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (x) {} else if (y); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* outer = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!outer) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)outer), msg)) { return -3; }
    ast::IfNode* inner = compiler_testing::expect_if(outer.else_block, msg);
    if(!inner) { return -4; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)inner), msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '{', got ';'", msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 35, msg)) { return -7; }
    return 0;
}

fn i32 if_recovery_continues(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (5 +) {} i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    ast::IfNode* i = compiler_testing::expect_if(body.stmts.ptr[0], msg);
    if(!i) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)i), msg)) { return -4; }
    ast::VarDeclNode* v = compiler_testing::expect_var(body.stmts.ptr[1], compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -5; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)v), msg)) { return -6; }
    if(!compiler_testing::expect_intlit(v.init, 5, msg)) { return -7; }
    return 0;
}

fn i32 if_cond_bool_literal(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (true) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    if(!compiler_testing::expect_boollit(i.cond, true, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

// `fn void f() { if (x) {} else if (y) {} }` — second `if` at byte 29
fn i32 if_else_if_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (x) {} else if (y) {} }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* outer = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!outer) { return -2; }
    if(!testing::expect_eq(outer.h.src_pos, 14, msg)) { return -3; }
    ast::IfNode* inner = compiler_testing::expect_if(outer.else_block, msg);
    if(!inner) { return -4; }
    if(!testing::expect_eq(inner.h.src_pos, 29, msg)) { return -5; }
    return 0;
}

fn i32 if_malformed_cond(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (5 +) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)i), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ')'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 21, msg)) { return -5; }
    return 0;
}

// ============================================================================
// WHILE LOOPS
// ============================================================================

fn i32 while_basic(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (x) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    if(!compiler_testing::expect_ident(w.cond, compiler_testing::sym(m, "x"), msg)) { return -3; }
    if(!compiler_testing::expect_block(w.body, 0, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 while_cond_pratt(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (a + b * 2 == 5) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BinaryOpNode* eq = compiler_testing::expect_binop(w.cond, token::TokenKind::EqEq, msg);
    if(!eq) { return -3; }
    ast::BinaryOpNode* plus = compiler_testing::expect_binop(eq.lhs, token::TokenKind::Plus, msg);
    if(!plus) { return -4; }
    if(!compiler_testing::expect_ident(plus.lhs, compiler_testing::sym(m, "a"), msg)) { return -5; }
    ast::BinaryOpNode* mul = compiler_testing::expect_binop(plus.rhs, token::TokenKind::Star, msg);
    if(!mul) { return -6; }
    if(!compiler_testing::expect_ident(mul.lhs, compiler_testing::sym(m, "b"), msg)) { return -7; }
    if(!compiler_testing::expect_intlit(mul.rhs, 2, msg)) { return -8; }
    if(!compiler_testing::expect_intlit(eq.rhs, 5, msg)) { return -9; }
    return 0;
}

fn i32 while_cond_call(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (foo(1)) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::CallNode* c = compiler_testing::expect_call(w.cond, 1, msg);
    if(!c) { return -3; }
    if(!compiler_testing::expect_ident(c.callee, compiler_testing::sym(m, "foo"), msg)) { return -4; }
    if(!compiler_testing::expect_intlit(c.args.ptr[0], 1, msg)) { return -5; }
    return 0;
}

fn i32 while_cond_logical(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (a && b) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BinaryOpNode* b = compiler_testing::expect_binop(w.cond, token::TokenKind::AmpAmp, msg);
    if(!b) { return -3; }
    if(!compiler_testing::expect_ident(b.lhs, compiler_testing::sym(m, "a"), msg)) { return -4; }
    if(!compiler_testing::expect_ident(b.rhs, compiler_testing::sym(m, "b"), msg)) { return -5; }
    return 0;
}

fn i32 while_cond_comparison(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (i < 10) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BinaryOpNode* b = compiler_testing::expect_binop(w.cond, token::TokenKind::LT, msg);
    if(!b) { return -3; }
    if(!compiler_testing::expect_ident(b.lhs, compiler_testing::sym(m, "i"), msg)) { return -4; }
    if(!compiler_testing::expect_intlit(b.rhs, 10, msg)) { return -5; }
    return 0;
}

fn i32 while_cond_unary(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (!flag) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::UnaryOpNode* u = compiler_testing::expect_unop(w.cond, token::TokenKind::Bang, msg);
    if(!u) { return -3; }
    if(!compiler_testing::expect_ident(u.operand, compiler_testing::sym(m, "flag"), msg)) { return -4; }
    return 0;
}

fn i32 while_cond_bool_literal(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (true) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    if(!compiler_testing::expect_boollit(w.cond, true, msg)) { return -3; }
    return 0;
}

fn i32 while_body_multi_stmts(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { while (x) { i32 y = 1; return y; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(w.body, 2, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "y"), false, false, msg)) { return -4; }
    if(!compiler_testing::expect_return(body.stmts.ptr[1], msg)) { return -5; }
    return 0;
}

fn i32 while_body_contains_nested_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (x) { { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(w.body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_block(body.stmts.ptr[0], 0, msg)) { return -4; }
    return 0;
}

fn i32 while_body_contains_if(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (x) { if (y) { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(w.body, 1, msg);
    if(!body) { return -3; }
    ast::IfNode* i = compiler_testing::expect_if(body.stmts.ptr[0], msg);
    if(!i) { return -4; }
    if(!compiler_testing::expect_ident(i.cond, compiler_testing::sym(m, "y"), msg)) { return -5; }
    return 0;
}

fn i32 while_body_contains_return(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { while (x) { return 5; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(w.body, 1, msg);
    if(!body) { return -3; }
    ast::ReturnNode* r = compiler_testing::expect_return(body.stmts.ptr[0], msg);
    if(!r) { return -4; }
    if(!compiler_testing::expect_intlit(r.expr, 5, msg)) { return -5; }
    return 0;
}

fn i32 while_nested(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (a) { while (b) { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* outer = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!outer) { return -2; }
    if(!compiler_testing::expect_ident(outer.cond, compiler_testing::sym(m, "a"), msg)) { return -3; }
    ast::BlockNode* outer_body = compiler_testing::expect_block(outer.body, 1, msg);
    if(!outer_body) { return -4; }
    ast::WhileNode* inner = compiler_testing::expect_while(outer_body.stmts.ptr[0], msg);
    if(!inner) { return -5; }
    if(!compiler_testing::expect_ident(inner.cond, compiler_testing::sym(m, "b"), msg)) { return -6; }
    return 0;
}

fn i32 while_combined_with_var_and_return(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { i32 i = 0; while (i < 10) { } return i; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 3, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "i"), false, false, msg)) { return -3; }
    ast::WhileNode* w = compiler_testing::expect_while(body.stmts.ptr[1], msg);
    if(!w) { return -4; }
    ast::BinaryOpNode* b = compiler_testing::expect_binop(w.cond, token::TokenKind::LT, msg);
    if(!b) { return -5; }
    ast::ReturnNode* r = compiler_testing::expect_return(body.stmts.ptr[2], msg);
    if(!r) { return -6; }
    if(!compiler_testing::expect_ident(r.expr, compiler_testing::sym(m, "i"), msg)) { return -7; }
    return 0;
}

fn i32 while_two_consecutive_at_same_level(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (a) {} while (b) {} }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    ast::WhileNode* w0 = compiler_testing::expect_while(body.stmts.ptr[0], msg);
    if(!w0) { return -3; }
    if(!compiler_testing::expect_ident(w0.cond, compiler_testing::sym(m, "a"), msg)) { return -4; }
    ast::WhileNode* w1 = compiler_testing::expect_while(body.stmts.ptr[1], msg);
    if(!w1) { return -5; }
    if(!compiler_testing::expect_ident(w1.cond, compiler_testing::sym(m, "b"), msg)) { return -6; }
    return 0;
}

// `fn void f() { while (x) { } }` — `while` at byte 14
fn i32 while_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (x) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    if(!testing::expect_eq(w.h.src_pos, 14, msg)) { return -3; }
    return 0;
}

fn i32 while_missing_lparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while x) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)w), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '(', got identifier", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 20, msg)) { return -5; }
    return 0;
}

fn i32 while_missing_rparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (x { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)w), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ')', got '{'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 23, msg)) { return -5; }
    return 0;
}

fn i32 while_missing_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (x); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)w), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '{', got ';'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 23, msg)) { return -5; }
    return 0;
}

fn i32 while_empty_cond(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while () { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)w), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ')'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 21, msg)) { return -5; }
    return 0;
}

fn i32 while_malformed_cond(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (5 +) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)w), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ')'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 24, msg)) { return -5; }
    return 0;
}

fn i32 while_inside_if_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (a) { while (b) { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* i = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!i) { return -2; }
    if(!compiler_testing::expect_ident(i.cond, compiler_testing::sym(m, "a"), msg)) { return -3; }
    ast::BlockNode* then_b = compiler_testing::expect_block(i.then_block, 1, msg);
    if(!then_b) { return -4; }
    ast::WhileNode* w = compiler_testing::expect_while(then_b.stmts.ptr[0], msg);
    if(!w) { return -5; }
    if(!compiler_testing::expect_ident(w.cond, compiler_testing::sym(m, "b"), msg)) { return -6; }
    return 0;
}

fn i32 while_recovery_continues(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (5 +) {} i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    ast::WhileNode* w = compiler_testing::expect_while(body.stmts.ptr[0], msg);
    if(!w) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)w), msg)) { return -4; }
    ast::VarDeclNode* v = compiler_testing::expect_var(body.stmts.ptr[1], compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -5; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)v), msg)) { return -6; }
    if(!compiler_testing::expect_intlit(v.init, 5, msg)) { return -7; }
    return 0;
}

fn i32 while_else_not_consumed(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (x) {} else {} }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 3, msg);
    if(!body) { return -2; }
    ast::WhileNode* w = compiler_testing::expect_while(body.stmts.ptr[0], msg);
    if(!w) { return -3; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)w), msg)) { return -4; }
    if(!testing::expect_eq((u16)body.stmts.ptr[1].h.kind, (u16)ast::AstKind::ERROR, msg)) { return -5; }
    if(!compiler_testing::expect_block(body.stmts.ptr[2], 0, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got 'else'", msg)) { return -7; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 27, msg)) { return -8; }
    return 0;
}

fn i32 while_body_error_propagates(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (x) { return 5 5; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)w), msg)) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag(w.body), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got integer literal", msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 35, msg)) { return -6; }
    return 0;
}

// ============================================================================
// FOR
// ============================================================================

// SHAPES — which of init/cond/post are present
fn i32 for_basic_full(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i32 i = 0; i < 10; i += 1) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::VarDeclNode* v = compiler_testing::expect_var(fr.init, compiler_testing::sym(m, "i"), false, false, msg);
    if(!v) { return -3; }
    if(!compiler_testing::expect_intlit(v.init, 0, msg)) { return -4; }
    ast::BinaryOpNode* cond = compiler_testing::expect_binop(fr.cond, token::TokenKind::LT, msg);
    if(!cond) { return -5; }
    if(!compiler_testing::expect_ident(cond.lhs, compiler_testing::sym(m, "i"), msg)) { return -6; }
    if(!compiler_testing::expect_intlit(cond.rhs, 10, msg)) { return -7; }
    ast::AssignmentNode* post = compiler_testing::expect_assign(fr.post, token::TokenKind::PlusEq, msg);
    if(!post) { return -8; }
    if(!compiler_testing::expect_ident(post.lhs, compiler_testing::sym(m, "i"), msg)) { return -9; }
    if(!compiler_testing::expect_intlit(post.rhs, 1, msg)) { return -10; }
    if(!compiler_testing::expect_block(fr.body, 0, msg)) { return -11; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -12; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)fr), msg)) { return -13; }
    return 0;
}

fn i32 for_empty_all(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_null((void*)fr.init, msg)) { return -3; }
    if(!testing::expect_null((void*)fr.cond, msg)) { return -4; }
    if(!testing::expect_null((void*)fr.post, msg)) { return -5; }
    if(!compiler_testing::expect_block(fr.body, 0, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 for_empty_init(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (; i < 10; i += 1) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_null((void*)fr.init, msg)) { return -3; }
    if(!compiler_testing::expect_binop(fr.cond, token::TokenKind::LT, msg)) { return -4; }
    if(!compiler_testing::expect_assign(fr.post, token::TokenKind::PlusEq, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 for_empty_cond(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i32 i = 0; ; i += 1) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_var(fr.init, compiler_testing::sym(m, "i"), false, false, msg)) { return -3; }
    if(!testing::expect_null((void*)fr.cond, msg)) { return -4; }
    if(!compiler_testing::expect_assign(fr.post, token::TokenKind::PlusEq, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 for_empty_post(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i32 i = 0; i < 10;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_var(fr.init, compiler_testing::sym(m, "i"), false, false, msg)) { return -3; }
    if(!compiler_testing::expect_binop(fr.cond, token::TokenKind::LT, msg)) { return -4; }
    if(!testing::expect_null((void*)fr.post, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 for_empty_init_cond(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;; i += 1) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_null((void*)fr.init, msg)) { return -3; }
    if(!testing::expect_null((void*)fr.cond, msg)) { return -4; }
    if(!compiler_testing::expect_assign(fr.post, token::TokenKind::PlusEq, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 for_empty_init_post(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (; i < 10;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_null((void*)fr.init, msg)) { return -3; }
    if(!compiler_testing::expect_binop(fr.cond, token::TokenKind::LT, msg)) { return -4; }
    if(!testing::expect_null((void*)fr.post, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 for_empty_cond_post(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i32 i = 0;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_var(fr.init, compiler_testing::sym(m, "i"), false, false, msg)) { return -3; }
    if(!testing::expect_null((void*)fr.cond, msg)) { return -4; }
    if(!testing::expect_null((void*)fr.post, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

// INIT: var-decl forms exercising old features
fn i32 for_init_var_decl_no_init_expr(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i32 i; ;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::VarDeclNode* v = compiler_testing::expect_var(fr.init, compiler_testing::sym(m, "i"), false, false, msg);
    if(!v) { return -3; }
    if(!testing::expect_null((void*)v.init, msg)) { return -4; }
    if(!compiler_testing::expect_ty_prim(v.type_expr, token::TokenKind::I32, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 for_init_const_var_decl(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (const i32 i = 0; i < 10; i += 1) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_var(fr.init, compiler_testing::sym(m, "i"), true, false, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_init_pointer_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i32* p = &x; p < end; p += 1) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::VarDeclNode* v = compiler_testing::expect_var(fr.init, compiler_testing::sym(m, "p"), false, false, msg);
    if(!v) { return -3; }
    ast::TypePointerNode* pty = compiler_testing::expect_ty_ptr(v.type_expr, msg);
    if(!pty) { return -4; }
    if(!compiler_testing::expect_ty_prim(pty.pointee, token::TokenKind::I32, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 for_init_slice_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i32[] s = arr;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::VarDeclNode* v = compiler_testing::expect_var(fr.init, compiler_testing::sym(m, "s"), false, false, msg);
    if(!v) { return -3; }
    ast::TypeSliceNode* sty = compiler_testing::expect_ty_slice(v.type_expr, msg);
    if(!sty) { return -4; }
    if(!compiler_testing::expect_ty_prim(sty.element, token::TokenKind::I32, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 for_init_array_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i32[5] arr = undefined;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::VarDeclNode* v = compiler_testing::expect_var(fr.init, compiler_testing::sym(m, "arr"), false, false, msg);
    if(!v) { return -3; }
    ast::TypeArrayNode* aty = compiler_testing::expect_ty_array(v.type_expr, msg);
    if(!aty) { return -4; }
    if(!compiler_testing::expect_ty_prim(aty.element, token::TokenKind::I32, msg)) { return -5; }
    if(!compiler_testing::expect_intlit(aty.size_expr, 5, msg)) { return -6; }
    if(!compiler_testing::expect_undeflit(v.init, msg)) { return -7; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -8; }
    return 0;
}

fn i32 for_init_named_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (Foo bar = baz;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::VarDeclNode* v = compiler_testing::expect_var(fr.init, compiler_testing::sym(m, "bar"), false, false, msg);
    if(!v) { return -3; }
    if(!compiler_testing::expect_ty_named(v.type_expr, null, compiler_testing::sym(m, "Foo"), msg)) { return -4; }
    if(!compiler_testing::expect_ident(v.init, compiler_testing::sym(m, "baz"), msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 for_init_qualified_named_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (mod::Foo x = y;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::VarDeclNode* v = compiler_testing::expect_var(fr.init, compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -3; }
    if(!compiler_testing::expect_ty_named(v.type_expr, compiler_testing::sym(m, "mod"), compiler_testing::sym(m, "Foo"), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 for_init_fn_ptr_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (fn* void() fp = g;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::VarDeclNode* v = compiler_testing::expect_var(fr.init, compiler_testing::sym(m, "fp"), false, false, msg);
    if(!v) { return -3; }
    if(!compiler_testing::expect_ty_fnptr(v.type_expr, 0, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 for_init_var_decl_struct_lit_init(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (Foo p = {1, 2};;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::VarDeclNode* v = compiler_testing::expect_var(fr.init, compiler_testing::sym(m, "p"), false, false, msg);
    if(!v) { return -3; }
    ast::StructLitNode* sl = compiler_testing::expect_struct_lit(v.init, 2, msg);
    if(!sl) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 for_init_var_decl_array_lit_init(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i32[3] arr = [1, 2, 3];;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::VarDeclNode* v = compiler_testing::expect_var(fr.init, compiler_testing::sym(m, "arr"), false, false, msg);
    if(!v) { return -3; }
    if(!compiler_testing::expect_array_lit(v.init, 3, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 for_init_var_decl_cast_init(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i32 x = (i32)y;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::VarDeclNode* v = compiler_testing::expect_var(fr.init, compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -3; }
    if(!compiler_testing::expect_cast(v.init, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 for_init_var_decl_call_init(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i32 x = foo(1, 2);;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::VarDeclNode* v = compiler_testing::expect_var(fr.init, compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -3; }
    if(!compiler_testing::expect_call(v.init, 2, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 for_init_var_decl_undefined(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i32 x = undefined;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::VarDeclNode* v = compiler_testing::expect_var(fr.init, compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -3; }
    if(!compiler_testing::expect_undeflit(v.init, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

// INIT: assignment / expression forms — exhaustive op coverage
fn i32 for_init_assign_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i = 0;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::AssignmentNode* an = compiler_testing::expect_assign(fr.init, token::TokenKind::Eq, msg);
    if(!an) { return -3; }
    if(!compiler_testing::expect_ident(an.lhs, compiler_testing::sym(m, "i"), msg)) { return -4; }
    if(!compiler_testing::expect_intlit(an.rhs, 0, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 for_init_assign_plus_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i += 1;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_assign(fr.init, token::TokenKind::PlusEq, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_init_assign_minus_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i -= 1;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_assign(fr.init, token::TokenKind::MinusEq, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_init_assign_star_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i *= 2;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_assign(fr.init, token::TokenKind::StarEq, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_init_assign_slash_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i /= 2;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_assign(fr.init, token::TokenKind::SlashEq, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_init_assign_percent_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i %= 2;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_assign(fr.init, token::TokenKind::PercentEq, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_init_assign_amp_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i &= 3;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_assign(fr.init, token::TokenKind::AmpEq, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_init_assign_pipe_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i |= 3;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_assign(fr.init, token::TokenKind::PipeEq, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_init_assign_caret_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i ^= 3;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_assign(fr.init, token::TokenKind::CaretEq, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_init_assign_member_lhs(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (obj.field = 0;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::AssignmentNode* an = compiler_testing::expect_assign(fr.init, token::TokenKind::Eq, msg);
    if(!an) { return -3; }
    if(!compiler_testing::expect_member(an.lhs, compiler_testing::sym(m, "field"), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 for_init_assign_index_lhs(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (arr[0] = 5;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::AssignmentNode* an = compiler_testing::expect_assign(fr.init, token::TokenKind::Eq, msg);
    if(!an) { return -3; }
    if(!compiler_testing::expect_index(an.lhs, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 for_init_assign_deref_lhs(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (*p = 5;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::AssignmentNode* an = compiler_testing::expect_assign(fr.init, token::TokenKind::Eq, msg);
    if(!an) { return -3; }
    if(!compiler_testing::expect_unop(an.lhs, token::TokenKind::Star, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 for_init_assign_complex_rhs(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i = a + b * c;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::AssignmentNode* an = compiler_testing::expect_assign(fr.init, token::TokenKind::Eq, msg);
    if(!an) { return -3; }
    ast::BinaryOpNode* plus = compiler_testing::expect_binop(an.rhs, token::TokenKind::Plus, msg);
    if(!plus) { return -4; }
    if(!compiler_testing::expect_binop(plus.rhs, token::TokenKind::Star, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 for_init_bare_call_expr(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (foo();;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_call(fr.init, 0, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_init_bare_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (x;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_ident(fr.init, compiler_testing::sym(m, "x"), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

// COND: every expression form
fn i32 for_cond_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;x;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_ident(fr.cond, compiler_testing::sym(m, "x"), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_cond_bool_literal(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;true;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_boollit(fr.cond, true, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_cond_pratt(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;a + b * 2 == 5;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::BinaryOpNode* eq = compiler_testing::expect_binop(fr.cond, token::TokenKind::EqEq, msg);
    if(!eq) { return -3; }
    ast::BinaryOpNode* plus = compiler_testing::expect_binop(eq.lhs, token::TokenKind::Plus, msg);
    if(!plus) { return -4; }
    if(!compiler_testing::expect_binop(plus.rhs, token::TokenKind::Star, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 for_cond_comparison(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;i < 10;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_binop(fr.cond, token::TokenKind::LT, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_cond_logical(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;a && b;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_binop(fr.cond, token::TokenKind::AmpAmp, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_cond_call(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;foo(1);) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_call(fr.cond, 1, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_cond_unary(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;!flag;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_unop(fr.cond, token::TokenKind::Bang, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_cond_member_access(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;obj.flag;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_member(fr.cond, compiler_testing::sym(m, "flag"), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

// POST: every assignment op + complex lhs
fn i32 for_post_assign_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;i = 0) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::AssignmentNode* an = compiler_testing::expect_assign(fr.post, token::TokenKind::Eq, msg);
    if(!an) { return -3; }
    if(!compiler_testing::expect_ident(an.lhs, compiler_testing::sym(m, "i"), msg)) { return -4; }
    if(!compiler_testing::expect_intlit(an.rhs, 0, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 for_post_assign_plus_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;i += 1) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_assign(fr.post, token::TokenKind::PlusEq, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_post_assign_minus_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;i -= 1) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_assign(fr.post, token::TokenKind::MinusEq, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_post_assign_star_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;i *= 2) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_assign(fr.post, token::TokenKind::StarEq, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_post_assign_slash_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;i /= 2) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_assign(fr.post, token::TokenKind::SlashEq, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_post_assign_percent_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;i %= 2) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_assign(fr.post, token::TokenKind::PercentEq, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_post_assign_amp_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;i &= 3) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_assign(fr.post, token::TokenKind::AmpEq, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_post_assign_pipe_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;i |= 3) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_assign(fr.post, token::TokenKind::PipeEq, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_post_assign_caret_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;i ^= 3) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_assign(fr.post, token::TokenKind::CaretEq, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_post_member_assign(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;obj.f = 5) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::AssignmentNode* an = compiler_testing::expect_assign(fr.post, token::TokenKind::Eq, msg);
    if(!an) { return -3; }
    if(!compiler_testing::expect_member(an.lhs, compiler_testing::sym(m, "f"), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 for_post_index_assign(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;arr[0] = 5) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::AssignmentNode* an = compiler_testing::expect_assign(fr.post, token::TokenKind::Eq, msg);
    if(!an) { return -3; }
    if(!compiler_testing::expect_index(an.lhs, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 for_post_deref_assign(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;*p = 5) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::AssignmentNode* an = compiler_testing::expect_assign(fr.post, token::TokenKind::Eq, msg);
    if(!an) { return -3; }
    if(!compiler_testing::expect_unop(an.lhs, token::TokenKind::Star, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 for_post_bare_call(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;foo()) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_call(fr.post, 0, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_post_complex_rhs(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;i = a + b * c) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::AssignmentNode* an = compiler_testing::expect_assign(fr.post, token::TokenKind::Eq, msg);
    if(!an) { return -3; }
    ast::BinaryOpNode* plus = compiler_testing::expect_binop(an.rhs, token::TokenKind::Plus, msg);
    if(!plus) { return -4; }
    if(!compiler_testing::expect_binop(plus.rhs, token::TokenKind::Star, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

// BODY: assorted statements inside
fn i32 for_body_multi_stmts(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { for (;;) { i32 y = 1; return y; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(fr.body, 2, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "y"), false, false, msg)) { return -4; }
    if(!compiler_testing::expect_return(body.stmts.ptr[1], msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 for_body_nested_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(fr.body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_block(body.stmts.ptr[0], 0, msg)) { return -4; }
    return 0;
}

fn i32 for_body_with_if(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { if (y) { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(fr.body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_if(body.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 for_body_with_while(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { while (x) { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(fr.body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_while(body.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 for_body_with_return(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { for (;;) { return 5; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(fr.body, 1, msg);
    if(!body) { return -3; }
    ast::ReturnNode* r = compiler_testing::expect_return(body.stmts.ptr[0], msg);
    if(!r) { return -4; }
    if(!compiler_testing::expect_intlit(r.expr, 5, msg)) { return -5; }
    return 0;
}

// NESTING / SEQUENCING
fn i32 for_nested(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i32 i = 0; i < 5; i += 1) { for (i32 j = 0; j < 5; j += 1) { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* outer = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!outer) { return -2; }
    ast::BlockNode* outer_body = compiler_testing::expect_block(outer.body, 1, msg);
    if(!outer_body) { return -3; }
    ast::ForNode* inner = compiler_testing::expect_for(outer_body.stmts.ptr[0], msg);
    if(!inner) { return -4; }
    if(!compiler_testing::expect_var(inner.init, compiler_testing::sym(m, "j"), false, false, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 for_inside_if(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (a) { for (;;) { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* ifn = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ifn) { return -2; }
    ast::BlockNode* then_b = compiler_testing::expect_block(ifn.then_block, 1, msg);
    if(!then_b) { return -3; }
    if(!compiler_testing::expect_for(then_b.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 for_inside_while(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (a) { for (;;) { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BlockNode* wb = compiler_testing::expect_block(w.body, 1, msg);
    if(!wb) { return -3; }
    if(!compiler_testing::expect_for(wb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 for_two_consecutive(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { } for (;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_for(body.stmts.ptr[0], msg)) { return -3; }
    if(!compiler_testing::expect_for(body.stmts.ptr[1], msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 for_combined_with_var_and_return(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { i32 i = 0; for (;;) { } return i; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 3, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "i"), false, false, msg)) { return -3; }
    if(!compiler_testing::expect_for(body.stmts.ptr[1], msg)) { return -4; }
    if(!compiler_testing::expect_return(body.stmts.ptr[2], msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

// SRC POS
fn i32 for_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_eq(fr.h.src_pos, 14, msg)) { return -3; }
    return 0;
}

fn i32 for_init_src_pos_var_decl(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i32 i = 0;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_eq(fr.init.h.src_pos, 19, msg)) { return -3; }
    return 0;
}

fn i32 for_init_src_pos_assign(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i = 0;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_eq(fr.init.h.src_pos, 19, msg)) { return -3; }
    return 0;
}

fn i32 for_body_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_eq(fr.body.h.src_pos, 23, msg)) { return -3; }
    return 0;
}

// NEGATIVE — every error mode with pinned diag msg + src_pos
fn i32 for_missing_lparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for x;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)fr), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '(', got identifier", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 18, msg)) { return -5; }
    return 0;
}

fn i32 for_missing_first_semi_var_decl(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i32 i = 0) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)fr), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got ')'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 28, msg)) { return -5; }
    return 0;
}

fn i32 for_missing_first_semi_assign(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i = 0) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)fr), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got ')'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 24, msg)) { return -5; }
    return 0;
}

fn i32 for_missing_first_semi_bare_expr(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (x) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)fr), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got ')'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 20, msg)) { return -5; }
    return 0;
}

fn i32 for_missing_second_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)fr), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ')'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 20, msg)) { return -5; }
    return 0;
}

// Post must NOT be `{`-led — that would be eaten as a struct literal. Use a
// bare ident post so `expect(RParen)` actually sees `{` at the body LBrace.
fn i32 for_missing_rparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;a { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)fr), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ')', got '{'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 23, msg)) { return -5; }
    return 0;
}

fn i32 for_missing_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)fr), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '{', got ';'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 22, msg)) { return -5; }
    return 0;
}

fn i32 for_malformed_init_expr(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (5 +;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)fr), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ';'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 22, msg)) { return -5; }
    return 0;
}

fn i32 for_malformed_cond(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;5 +;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)fr), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ';'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 23, msg)) { return -5; }
    return 0;
}

fn i32 for_malformed_post(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;5 +) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)fr), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ')'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 24, msg)) { return -5; }
    return 0;
}

fn i32 for_body_error_propagates(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { return 5 5; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)fr), msg)) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag(fr.body), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got integer literal", msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 34, msg)) { return -6; }
    return 0;
}

fn i32 for_recovery_continues(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) {} i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_for(body.stmts.ptr[0], msg)) { return -3; }
    ast::VarDeclNode* v = compiler_testing::expect_var(body.stmts.ptr[1], compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -4; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)v), msg)) { return -5; }
    if(!compiler_testing::expect_intlit(v.init, 5, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 for_recovery_continues_after_error(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (5 +;;) {} i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    ast::ForNode* fr = compiler_testing::expect_for(body.stmts.ptr[0], msg);
    if(!fr) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)fr), msg)) { return -4; }
    ast::VarDeclNode* v = compiler_testing::expect_var(body.stmts.ptr[1], compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -5; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)v), msg)) { return -6; }
    if(!compiler_testing::expect_intlit(v.init, 5, msg)) { return -7; }
    return 0;
}

fn i32 for_else_not_consumed(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) {} else {} }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 3, msg);
    if(!body) { return -2; }
    ast::ForNode* fr = compiler_testing::expect_for(body.stmts.ptr[0], msg);
    if(!fr) { return -3; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)fr), msg)) { return -4; }
    if(!testing::expect_eq((u16)body.stmts.ptr[1].h.kind, (u16)ast::AstKind::ERROR, msg)) { return -5; }
    if(!compiler_testing::expect_block(body.stmts.ptr[2], 0, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got 'else'", msg)) { return -7; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 26, msg)) { return -8; }
    return 0;
}

fn i32 for_bare_keyword_only(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)fr), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '(', got '}'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 18, msg)) { return -5; }
    return 0;
}

// GAP FILL — additional coverage

fn i32 for_cond_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;x;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_eq(fr.cond.h.src_pos, 20, msg)) { return -3; }
    return 0;
}

fn i32 for_post_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;x) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_eq(fr.post.h.src_pos, 21, msg)) { return -3; }
    return 0;
}

// Non-assignment expression in init must not be wrapped in an AssignmentNode.
fn i32 for_init_bare_binop(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (a + b;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::BinaryOpNode* b = compiler_testing::expect_binop(fr.init, token::TokenKind::Plus, msg);
    if(!b) { return -3; }
    if(!testing::expect_eq((u16)fr.init.h.kind, (u16)ast::AstKind::BinaryOp, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 for_init_bare_member_access(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (obj.f;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_member(fr.init, compiler_testing::sym(m, "f"), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

// (i + 1) = 2 — parser MUST accept; lvalue rules deferred to sema.
fn i32 for_init_paren_lhs_assign(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for ((i + 1) = 2;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::AssignmentNode* an = compiler_testing::expect_assign(fr.init, token::TokenKind::Eq, msg);
    if(!an) { return -3; }
    ast::BinaryOpNode* plus = compiler_testing::expect_binop(an.lhs, token::TokenKind::Plus, msg);
    if(!plus) { return -4; }
    if(!testing::expect_true(compiler_testing::has_paren_flag(an.lhs), msg)) { return -5; }
    if(!compiler_testing::expect_intlit(an.rhs, 2, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 for_cond_namespace_access(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;mod::flag;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_nsacc(fr.cond, compiler_testing::sym(m, "mod"), compiler_testing::sym(m, "flag"), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_cond_cast(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;(bool)x;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_cast(fr.cond, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_cond_array_index(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;arr[0] < 10;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::BinaryOpNode* lt = compiler_testing::expect_binop(fr.cond, token::TokenKind::LT, msg);
    if(!lt) { return -3; }
    if(!compiler_testing::expect_index(lt.lhs, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 for_cond_chained_postfix(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;obj.arr[0] < 10;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::BinaryOpNode* lt = compiler_testing::expect_binop(fr.cond, token::TokenKind::LT, msg);
    if(!lt) { return -3; }
    ast::ArrayIndexNode* idx = compiler_testing::expect_index(lt.lhs, msg);
    if(!idx) { return -4; }
    if(!compiler_testing::expect_member(idx.base, compiler_testing::sym(m, "arr"), msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 for_post_bare_binop(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;a + b) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_binop(fr.post, token::TokenKind::Plus, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 for_post_bare_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;x) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!compiler_testing::expect_ident(fr.post, compiler_testing::sym(m, "x"), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

// `for (i32* p = ; x; ;)` — multiple errors in same for; both should be reported separately.
fn i32 for_multi_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (5 +;;5 +) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)fr), msg)) { return -3; }
    if(!testing::expect_true(m.diag.entries.len >= 2, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ';'", msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 22, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries[1].msg, "expected identifier, got ')'", msg)) { return -7; }
    if(!testing::expect_eq(m.diag.entries[1].src_pos, 27, msg)) { return -8; }
    return 0;
}

fn i32 for_unclosed_body_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) {", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)fr), msg)) { return -3; }
    if(!compiler_testing::expect_diag_substr(m, "expected '}'", msg)) { return -4; }
    return 0;
}

fn i32 for_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)fr), msg)) { return -3; }
    if(!compiler_testing::expect_diag_substr(m, "expected '('", msg)) { return -4; }
    return 0;
}

fn i32 for_init_var_decl_pointer_to_pointer(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (i32** pp = null;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::VarDeclNode* v = compiler_testing::expect_var(fr.init, compiler_testing::sym(m, "pp"), false, false, msg);
    if(!v) { return -3; }
    ast::TypePointerNode* outer = compiler_testing::expect_ty_ptr(v.type_expr, msg);
    if(!outer) { return -4; }
    ast::TypePointerNode* inner = compiler_testing::expect_ty_ptr(outer.pointee, msg);
    if(!inner) { return -5; }
    if(!compiler_testing::expect_ty_prim(inner.pointee, token::TokenKind::I32, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

// ============================================================================
// BREAK / CONTINUE
// ============================================================================

fn i32 break_basic(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { break; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BreakNode* b = compiler_testing::expect_break(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!b) { return -2; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)b), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 continue_basic(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { continue; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ContinueNode* c = compiler_testing::expect_continue(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!c) { return -2; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)c), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 break_in_while(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (x) { break; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(w.body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_break(body.stmts.ptr[0], msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 break_in_for(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { break; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(fr.body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_break(body.stmts.ptr[0], msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 continue_in_while(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (x) { continue; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(w.body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_continue(body.stmts.ptr[0], msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 continue_in_for(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { continue; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(fr.body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_continue(body.stmts.ptr[0], msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 break_in_nested_if(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (x) { if (y) { break; } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BlockNode* wbody = compiler_testing::expect_block(w.body, 1, msg);
    if(!wbody) { return -3; }
    ast::IfNode* ifn = compiler_testing::expect_if(wbody.stmts.ptr[0], msg);
    if(!ifn) { return -4; }
    ast::BlockNode* tbody = compiler_testing::expect_block(ifn.then_block, 1, msg);
    if(!tbody) { return -5; }
    if(!compiler_testing::expect_break(tbody.stmts.ptr[0], msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 continue_in_nested_if(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { if (y) { continue; } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::BlockNode* fbody = compiler_testing::expect_block(fr.body, 1, msg);
    if(!fbody) { return -3; }
    ast::IfNode* ifn = compiler_testing::expect_if(fbody.stmts.ptr[0], msg);
    if(!ifn) { return -4; }
    ast::BlockNode* tbody = compiler_testing::expect_block(ifn.then_block, 1, msg);
    if(!tbody) { return -5; }
    if(!compiler_testing::expect_continue(tbody.stmts.ptr[0], msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 break_in_nested_loop(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { for (;;) { break; } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* outer = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!outer) { return -2; }
    ast::BlockNode* obody = compiler_testing::expect_block(outer.body, 1, msg);
    if(!obody) { return -3; }
    ast::ForNode* inner = compiler_testing::expect_for(obody.stmts.ptr[0], msg);
    if(!inner) { return -4; }
    ast::BlockNode* ibody = compiler_testing::expect_block(inner.body, 1, msg);
    if(!ibody) { return -5; }
    if(!compiler_testing::expect_break(ibody.stmts.ptr[0], msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 break_in_bare_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { break; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* inner = compiler_testing::expect_block(compiler_testing::nth_stmt(f.body, 0), 1, msg);
    if(!inner) { return -2; }
    if(!compiler_testing::expect_break(inner.stmts.ptr[0], msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 break_then_other_stmt(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (x) { break; i32 y = 5; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(w.body, 2, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_break(body.stmts.ptr[0], msg)) { return -4; }
    if(!compiler_testing::expect_var(body.stmts.ptr[1], compiler_testing::sym(m, "y"), false, false, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 multiple_breaks(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (x) { break; break; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(w.body, 2, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_break(body.stmts.ptr[0], msg)) { return -4; }
    if(!compiler_testing::expect_break(body.stmts.ptr[1], msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 break_continue_sequence(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { break; continue; break; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(fr.body, 3, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_break(body.stmts.ptr[0], msg)) { return -4; }
    if(!compiler_testing::expect_continue(body.stmts.ptr[1], msg)) { return -5; }
    if(!compiler_testing::expect_break(body.stmts.ptr[2], msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

// `fn void f() { break; }` — `break` at byte 14
fn i32 break_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { break; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BreakNode* b = compiler_testing::expect_break(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!b) { return -2; }
    if(!testing::expect_eq(b.h.src_pos, 14, msg)) { return -3; }
    return 0;
}

fn i32 continue_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { continue; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ContinueNode* c = compiler_testing::expect_continue(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!c) { return -2; }
    if(!testing::expect_eq(c.h.src_pos, 14, msg)) { return -3; }
    return 0;
}

fn i32 break_missing_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { break }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BreakNode* b = compiler_testing::expect_break(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!b) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)b), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got '}'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 20, msg)) { return -5; }
    return 0;
}

fn i32 continue_missing_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { continue }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ContinueNode* c = compiler_testing::expect_continue(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!c) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)c), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got '}'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 23, msg)) { return -5; }
    return 0;
}

fn i32 break_extra_token(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { break x; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BreakNode* b = compiler_testing::expect_break(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!b) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)b), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got identifier", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 20, msg)) { return -5; }
    return 0;
}

fn i32 break_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { break", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BreakNode* b = compiler_testing::expect_break(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!b) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)b), msg)) { return -3; }
    if(!compiler_testing::expect_diag_substr(m, "expected ';'", msg)) { return -4; }
    return 0;
}

fn i32 continue_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { continue", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ContinueNode* c = compiler_testing::expect_continue(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!c) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)c), msg)) { return -3; }
    if(!compiler_testing::expect_diag_substr(m, "expected ';'", msg)) { return -4; }
    return 0;
}

fn i32 break_recovery_continues(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { break i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    ast::BreakNode* b = compiler_testing::expect_break(body.stmts.ptr[0], msg);
    if(!b) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)b), msg)) { return -4; }
    ast::VarDeclNode* v = compiler_testing::expect_var(body.stmts.ptr[1], compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -5; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)v), msg)) { return -6; }
    if(!compiler_testing::expect_intlit(v.init, 5, msg)) { return -7; }
    return 0;
}

// continue mirrors of break-specific tests
fn i32 continue_in_bare_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { continue; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* inner = compiler_testing::expect_block(compiler_testing::nth_stmt(f.body, 0), 1, msg);
    if(!inner) { return -2; }
    if(!compiler_testing::expect_continue(inner.stmts.ptr[0], msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 continue_in_nested_loop(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { for (;;) { continue; } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* outer = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!outer) { return -2; }
    ast::BlockNode* obody = compiler_testing::expect_block(outer.body, 1, msg);
    if(!obody) { return -3; }
    ast::ForNode* inner = compiler_testing::expect_for(obody.stmts.ptr[0], msg);
    if(!inner) { return -4; }
    ast::BlockNode* ibody = compiler_testing::expect_block(inner.body, 1, msg);
    if(!ibody) { return -5; }
    if(!compiler_testing::expect_continue(ibody.stmts.ptr[0], msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 continue_then_other_stmt(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (x) { continue; i32 y = 5; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(w.body, 2, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_continue(body.stmts.ptr[0], msg)) { return -4; }
    if(!compiler_testing::expect_var(body.stmts.ptr[1], compiler_testing::sym(m, "y"), false, false, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 multiple_continues(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (x) { continue; continue; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(w.body, 2, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_continue(body.stmts.ptr[0], msg)) { return -4; }
    if(!compiler_testing::expect_continue(body.stmts.ptr[1], msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 continue_extra_token(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { continue x; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ContinueNode* c = compiler_testing::expect_continue(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!c) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)c), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got identifier", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 23, msg)) { return -5; }
    return 0;
}

fn i32 continue_recovery_continues(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { continue i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    ast::ContinueNode* c = compiler_testing::expect_continue(body.stmts.ptr[0], msg);
    if(!c) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)c), msg)) { return -4; }
    ast::VarDeclNode* v = compiler_testing::expect_var(body.stmts.ptr[1], compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -5; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)v), msg)) { return -6; }
    if(!compiler_testing::expect_intlit(v.init, 5, msg)) { return -7; }
    return 0;
}

// Else-branch coverage — exercises the parse_if else_block path, which is a
// distinct parent from the then-branch tests above.
fn i32 break_in_else_branch(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (a) { if (b) { } else { break; } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BlockNode* wbody = compiler_testing::expect_block(w.body, 1, msg);
    if(!wbody) { return -3; }
    ast::IfNode* ifn = compiler_testing::expect_if(wbody.stmts.ptr[0], msg);
    if(!ifn) { return -4; }
    ast::BlockNode* elseb = compiler_testing::expect_block(ifn.else_block, 1, msg);
    if(!elseb) { return -5; }
    if(!compiler_testing::expect_break(elseb.stmts.ptr[0], msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 continue_in_else_branch(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { if (b) { } else { continue; } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::BlockNode* fbody = compiler_testing::expect_block(fr.body, 1, msg);
    if(!fbody) { return -3; }
    ast::IfNode* ifn = compiler_testing::expect_if(fbody.stmts.ptr[0], msg);
    if(!ifn) { return -4; }
    ast::BlockNode* elseb = compiler_testing::expect_block(ifn.else_block, 1, msg);
    if(!elseb) { return -5; }
    if(!compiler_testing::expect_continue(elseb.stmts.ptr[0], msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

// ============================================================================
// UNION
// ============================================================================

fn i32 union_empty(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union Foo { }", &m);
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "Foo"), 0, false, msg);
    if(!u) { return -1; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)u), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -3; }
    return 0;
}

fn i32 union_single_field(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union Tagged { i32 i; }", &m);
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "Tagged"), 1, false, msg);
    if(!u) { return -1; }
    if(!compiler_testing::expect_field(&u.fields.ptr[0], compiler_testing::sym(m, "i"), msg)) { return -2; }
    if(!compiler_testing::expect_ty_prim(u.fields.ptr[0].type_expr, token::TokenKind::I32, msg)) { return -3; }
    return 0;
}

fn i32 union_multi_field(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union Tagged { i32 i; f64 f; bool b; }", &m);
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "Tagged"), 3, false, msg);
    if(!u) { return -1; }
    if(!compiler_testing::expect_field(&u.fields.ptr[0], compiler_testing::sym(m, "i"), msg)) { return -2; }
    if(!compiler_testing::expect_field(&u.fields.ptr[1], compiler_testing::sym(m, "f"), msg)) { return -3; }
    if(!compiler_testing::expect_field(&u.fields.ptr[2], compiler_testing::sym(m, "b"), msg)) { return -4; }
    if(!compiler_testing::expect_ty_prim(u.fields.ptr[0].type_expr, token::TokenKind::I32, msg)) { return -5; }
    if(!compiler_testing::expect_ty_prim(u.fields.ptr[1].type_expr, token::TokenKind::F64, msg)) { return -6; }
    if(!compiler_testing::expect_ty_prim(u.fields.ptr[2].type_expr, token::TokenKind::BOOL, msg)) { return -7; }
    return 0;
}

fn i32 union_field_pointer_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union U { i32* p; }", &m);
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!u) { return -1; }
    if(!compiler_testing::expect_ty_ptr(u.fields.ptr[0].type_expr, msg)) { return -2; }
    return 0;
}

fn i32 union_field_array_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union U { i32[8] arr; }", &m);
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!u) { return -1; }
    ast::TypeArrayNode* ta = compiler_testing::expect_ty_array(u.fields.ptr[0].type_expr, msg);
    if(!ta) { return -2; }
    if(!compiler_testing::expect_intlit(ta.size_expr, 8, msg)) { return -3; }
    return 0;
}

fn i32 union_field_named_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union U { Bar b; }", &m);
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!u) { return -1; }
    if(!compiler_testing::expect_ty_named(u.fields.ptr[0].type_expr, null, compiler_testing::sym(m, "Bar"), msg)) { return -2; }
    return 0;
}

fn i32 union_field_qualified_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union U { mod::Bar b; }", &m);
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!u) { return -1; }
    if(!compiler_testing::expect_ty_named(u.fields.ptr[0].type_expr, compiler_testing::sym(m, "mod"), compiler_testing::sym(m, "Bar"), msg)) { return -2; }
    return 0;
}

fn i32 union_field_fn_ptr_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union U { fn* void(i32) cb; }", &m);
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!u) { return -1; }
    if(!compiler_testing::expect_ty_fnptr(u.fields.ptr[0].type_expr, 1, msg)) { return -2; }
    return 0;
}

fn i32 union_field_nested_anon_union_rejected(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union U { union { i32 x; } inner; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "anonymous union types are only allowed on the right-hand side of an `alias` declaration; use a named union or wrap this in `alias`", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)10, msg)) { return -3; }
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!u) { return -4; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)u), msg)) { return -5; }
    ast::TypeUnionNode* inner = compiler_testing::expect_ty_anon_union(u.fields.ptr[0].type_expr, 1, msg);
    if(!inner) { return -6; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)inner), msg)) { return -7; }
    return 0;
}

fn i32 union_field_anon_struct_rejected(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union U { struct { i32 x; u8 y; } s; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "anonymous struct types are only allowed on the right-hand side of an `alias` declaration; use a named struct or wrap this in `alias`", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)10, msg)) { return -3; }
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!u) { return -4; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)u), msg)) { return -5; }
    ast::TypeStructNode* inner = compiler_testing::expect_ty_anon_struct(u.fields.ptr[0].type_expr, 2, msg);
    if(!inner) { return -6; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)inner), msg)) { return -7; }
    return 0;
}

fn i32 union_exported(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "export union U { i32 i; }", &m);
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "U"), 1, true, msg);
    if(!u) { return -1; }
    return 0;
}

fn i32 union_many_fields_growth(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union U { i32 a; i32 b; i32 c; i32 d; i32 e; i32 f; }", &m);
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), null, 6, false, msg);
    if(!u) { return -1; }
    if(!compiler_testing::expect_field(&u.fields.ptr[5], compiler_testing::sym(m, "f"), msg)) { return -2; }
    return 0;
}

fn i32 anon_union_in_alias(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias V = union { i32 i; f64 f; };", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "V"), false, msg);
    if(!al) { return -1; }
    ast::TypeUnionNode* tu = compiler_testing::expect_ty_anon_union(al.target, 2, msg);
    if(!tu) { return -2; }
    if(!compiler_testing::expect_field(&tu.fields.ptr[0], compiler_testing::sym(m, "i"), msg)) { return -3; }
    if(!compiler_testing::expect_field(&tu.fields.ptr[1], compiler_testing::sym(m, "f"), msg)) { return -4; }
    return 0;
}

fn i32 anon_union_in_var_decl_rejected(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { union { i32 i; } v; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "anonymous union types are only allowed on the right-hand side of an `alias` declaration; use a named union or wrap this in `alias`", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)14, msg)) { return -3; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -4; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "v"), false, false, msg);
    if(!v) { return -5; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)v), msg)) { return -6; }
    if(!testing::expect_true(compiler_testing::has_error_flag(v.type_expr), msg)) { return -7; }
    return 0;
}

fn i32 anon_union_in_fn_param_rejected(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void g(union { i32 i; } v) { }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "anonymous union types are only allowed on the right-hand side of an `alias` declaration; use a named union or wrap this in `alias`", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)10, msg)) { return -3; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "g"), 1, false, msg);
    if(!f) { return -4; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)f), msg)) { return -5; }
    if(!testing::expect_true(compiler_testing::has_error_flag(f.params.ptr[0].type_expr), msg)) { return -6; }
    return 0;
}

fn i32 anon_union_empty(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias V = union { };", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), null, false, msg);
    if(!al) { return -1; }
    if(!compiler_testing::expect_ty_anon_union(al.target, 0, msg)) { return -2; }
    return 0;
}

// Union literals reuse parse_struct_lit — same AST shape, sema discriminates at use site.
fn i32 union_lit_via_struct_lit_syntax(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { Tagged t = { .i = 5 }; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "t"), false, false, msg);
    if(!v) { return -2; }
    ast::StructLitNode* sl = compiler_testing::expect_struct_lit(v.init, 1, msg);
    if(!sl) { return -3; }
    if(!compiler_testing::expect_field_init(&sl.inits.ptr[0], compiler_testing::sym(m, "i"), msg)) { return -4; }
    if(!compiler_testing::expect_intlit(sl.inits.ptr[0].value, 5, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 union_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union Foo { }", &m);
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!u) { return -1; }
    if(!testing::expect_eq(u.h.src_pos, 0, msg)) { return -2; }
    return 0;
}

fn i32 union_field_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union Foo { i32 x; }", &m);
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!u) { return -1; }
    if(!testing::expect_eq(u.fields.ptr[0].src_pos, 12, msg)) { return -2; }
    return 0;
}

fn i32 union_missing_name(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union { i32 i; }", &m);
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!u) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)u), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got '{'", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 6, msg)) { return -4; }
    return 0;
}

fn i32 union_missing_lbrace(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union Foo i32 x; }", &m);
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!u) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)u), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '{', got 'i32'", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 10, msg)) { return -4; }
    return 0;
}

fn i32 union_missing_rbrace_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union Foo { i32 x;", &m);
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!u) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)u), msg)) { return -2; }
    if(!compiler_testing::expect_diag_substr(m, "expected '}'", msg)) { return -3; }
    return 0;
}

fn i32 union_field_missing_name(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union Foo { i32; }", &m);
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!u) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)u), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ';'", msg)) { return -3; }
    return 0;
}

fn i32 union_field_missing_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union Foo { i32 x }", &m);
    ast::UnionDeclNode* u = compiler_testing::expect_union_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!u) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)u), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got '}'", msg)) { return -3; }
    return 0;
}

// `union` at type position not followed by `{` — parse_base_type's UNION case reports "expected '{'".
fn i32 anon_union_missing_lbrace_at_type_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias V = union x;", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), null, false, msg);
    if(!al) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)al), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '{', got identifier", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 16, msg)) { return -4; }
    return 0;
}

fn i32 union_recovery_continues(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "union Foo { i32; } union Bar { u8 y; }", &m);
    ast::BlockNode* r = (ast::BlockNode*)root;
    if(!testing::expect_eq(r.stmts.len, 2, msg)) { return -1; }
    ast::UnionDeclNode* foo = compiler_testing::expect_union_decl(r.stmts.ptr[0], compiler_testing::sym(m, "Foo"), 1, false, msg);
    if(!foo) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)foo), msg)) { return -3; }
    ast::UnionDeclNode* bar = compiler_testing::expect_union_decl(r.stmts.ptr[1], compiler_testing::sym(m, "Bar"), 1, false, msg);
    if(!bar) { return -4; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)bar), msg)) { return -5; }
    return 0;
}

// ============================================================================
// STRUCT
// ============================================================================

fn i32 struct_empty(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo { }", &m);
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "Foo"), 0, false, msg);
    if(!s) { return -1; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -3; }
    return 0;
}

fn i32 struct_single_field(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo { i32 x; }", &m);
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "Foo"), 1, false, msg);
    if(!s) { return -1; }
    if(!compiler_testing::expect_field(&s.fields.ptr[0], compiler_testing::sym(m, "x"), msg)) { return -2; }
    if(!compiler_testing::expect_ty_prim(s.fields.ptr[0].type_expr, token::TokenKind::I32, msg)) { return -3; }
    return 0;
}

fn i32 struct_multi_field(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo { i32 x; u8 y; bool z; }", &m);
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "Foo"), 3, false, msg);
    if(!s) { return -1; }
    if(!compiler_testing::expect_field(&s.fields.ptr[0], compiler_testing::sym(m, "x"), msg)) { return -2; }
    if(!compiler_testing::expect_field(&s.fields.ptr[1], compiler_testing::sym(m, "y"), msg)) { return -3; }
    if(!compiler_testing::expect_field(&s.fields.ptr[2], compiler_testing::sym(m, "z"), msg)) { return -4; }
    if(!compiler_testing::expect_ty_prim(s.fields.ptr[0].type_expr, token::TokenKind::I32, msg)) { return -5; }
    if(!compiler_testing::expect_ty_prim(s.fields.ptr[1].type_expr, token::TokenKind::U8, msg)) { return -6; }
    if(!compiler_testing::expect_ty_prim(s.fields.ptr[2].type_expr, token::TokenKind::BOOL, msg)) { return -7; }
    return 0;
}

fn i32 struct_field_pointer_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo { i32* p; }", &m);
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!s) { return -1; }
    if(!compiler_testing::expect_ty_ptr(s.fields.ptr[0].type_expr, msg)) { return -2; }
    return 0;
}

fn i32 struct_field_array_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo { i32[8] arr; }", &m);
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!s) { return -1; }
    ast::TypeArrayNode* ta = compiler_testing::expect_ty_array(s.fields.ptr[0].type_expr, msg);
    if(!ta) { return -2; }
    if(!compiler_testing::expect_intlit(ta.size_expr, 8, msg)) { return -3; }
    return 0;
}

fn i32 struct_field_named_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo { Bar b; }", &m);
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!s) { return -1; }
    if(!compiler_testing::expect_ty_named(s.fields.ptr[0].type_expr, null, compiler_testing::sym(m, "Bar"), msg)) { return -2; }
    return 0;
}

fn i32 struct_field_qualified_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo { mod::Bar b; }", &m);
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!s) { return -1; }
    if(!compiler_testing::expect_ty_named(s.fields.ptr[0].type_expr, compiler_testing::sym(m, "mod"), compiler_testing::sym(m, "Bar"), msg)) { return -2; }
    return 0;
}

fn i32 struct_field_fn_ptr_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo { fn* void(i32) cb; }", &m);
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!s) { return -1; }
    if(!compiler_testing::expect_ty_fnptr(s.fields.ptr[0].type_expr, 1, msg)) { return -2; }
    return 0;
}

fn i32 struct_field_nested_anon_struct_rejected(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo { struct { i32 x; } inner; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "anonymous struct types are only allowed on the right-hand side of an `alias` declaration; use a named struct or wrap this in `alias`", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)13, msg)) { return -3; }
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!s) { return -4; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -5; }
    if(!testing::expect_true(compiler_testing::has_error_flag(s.fields.ptr[0].type_expr), msg)) { return -6; }
    return 0;
}

fn i32 struct_exported(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "export struct Foo { i32 x; }", &m);
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "Foo"), 1, true, msg);
    if(!s) { return -1; }
    return 0;
}

// 6 fields exercises the realloc-grow path (initial cap=4).
fn i32 struct_many_fields_growth(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo { i32 a; i32 b; i32 c; i32 d; i32 e; i32 f; }", &m);
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), null, 6, false, msg);
    if(!s) { return -1; }
    if(!compiler_testing::expect_field(&s.fields.ptr[5], compiler_testing::sym(m, "f"), msg)) { return -2; }
    return 0;
}

// Anonymous struct in alias RHS: legacy `struct { ... }` form.
fn i32 anon_struct_in_alias_legacy(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias VecI32 = struct { i32 x; u64 len; };", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "VecI32"), false, msg);
    if(!al) { return -1; }
    ast::TypeStructNode* ts = compiler_testing::expect_ty_anon_struct(al.target, 2, msg);
    if(!ts) { return -2; }
    if(!compiler_testing::expect_field(&ts.fields.ptr[0], compiler_testing::sym(m, "x"), msg)) { return -3; }
    if(!compiler_testing::expect_field(&ts.fields.ptr[1], compiler_testing::sym(m, "len"), msg)) { return -4; }
    return 0;
}

// Anonymous struct in alias RHS: dot-prefix `.{ ... }` form.
fn i32 anon_struct_in_alias_dot(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias VecI32 = .{ i32 x; u64 len; };", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "VecI32"), false, msg);
    if(!al) { return -1; }
    ast::TypeStructNode* ts = compiler_testing::expect_ty_anon_struct(al.target, 2, msg);
    if(!ts) { return -2; }
    if(!compiler_testing::expect_field(&ts.fields.ptr[0], compiler_testing::sym(m, "x"), msg)) { return -3; }
    if(!compiler_testing::expect_field(&ts.fields.ptr[1], compiler_testing::sym(m, "len"), msg)) { return -4; }
    return 0;
}

fn i32 anon_struct_in_var_decl_dot_rejected(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { .{ i32 x; } v; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "anonymous struct types are only allowed on the right-hand side of an `alias` declaration; use a named struct or wrap this in `alias`", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)14, msg)) { return -3; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -4; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "v"), false, false, msg);
    if(!v) { return -5; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)v), msg)) { return -6; }
    if(!testing::expect_true(compiler_testing::has_error_flag(v.type_expr), msg)) { return -7; }
    return 0;
}

fn i32 anon_struct_empty_dot(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias V = .{ };", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), null, false, msg);
    if(!al) { return -1; }
    if(!compiler_testing::expect_ty_anon_struct(al.target, 0, msg)) { return -2; }
    return 0;
}

fn i32 struct_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo { }", &m);
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!s) { return -1; }
    if(!testing::expect_eq(s.h.src_pos, 0, msg)) { return -2; }
    return 0;
}

fn i32 struct_field_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo { i32 x; }", &m);
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!s) { return -1; }
    if(!testing::expect_eq(s.fields.ptr[0].src_pos, 13, msg)) { return -2; }
    return 0;
}

fn i32 struct_missing_name(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct { i32 x; }", &m);
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!s) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got '{'", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 7, msg)) { return -4; }
    return 0;
}

fn i32 struct_missing_lbrace(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo i32 x; }", &m);
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!s) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '{', got 'i32'", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 11, msg)) { return -4; }
    return 0;
}

fn i32 struct_missing_rbrace_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo { i32 x;", &m);
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!s) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -2; }
    if(!compiler_testing::expect_diag_substr(m, "expected '}'", msg)) { return -3; }
    return 0;
}

fn i32 struct_field_missing_name(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo { i32; }", &m);
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!s) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ';'", msg)) { return -3; }
    return 0;
}

fn i32 struct_field_missing_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo { i32 x }", &m);
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!s) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got '}'", msg)) { return -3; }
    return 0;
}

fn i32 struct_recovery_continues(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo { i32; } struct Bar { u8 y; }", &m);
    ast::BlockNode* r = (ast::BlockNode*)root;
    if(!testing::expect_eq(r.stmts.len, 2, msg)) { return -1; }
    ast::StructDeclNode* foo = compiler_testing::expect_struct_decl(r.stmts.ptr[0], compiler_testing::sym(m, "Foo"), 1, false, msg);
    if(!foo) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)foo), msg)) { return -3; }
    ast::StructDeclNode* bar = compiler_testing::expect_struct_decl(r.stmts.ptr[1], compiler_testing::sym(m, "Bar"), 1, false, msg);
    if(!bar) { return -4; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)bar), msg)) { return -5; }
    return 0;
}

// `struct Foo { 1 }` — `1` consumes no tokens via parse_type / expect chain;
// the no-progress guard in parse_fields must force advance to avoid infinite loop.
fn i32 struct_no_progress_safety(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo { 1 } struct Bar { }", &m);
    ast::BlockNode* r = (ast::BlockNode*)root;
    if(!testing::expect_eq(r.stmts.len, 2, msg)) { return -1; }
    ast::StructDeclNode* foo = compiler_testing::expect_struct_decl(r.stmts.ptr[0], compiler_testing::sym(m, "Foo"), 1, false, msg);
    if(!foo) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)foo), msg)) { return -3; }
    if(!compiler_testing::expect_struct_decl(r.stmts.ptr[1], compiler_testing::sym(m, "Bar"), 0, false, msg)) { return -4; }
    return 0;
}

fn i32 anon_struct_in_alias_body_error_propagates(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias T = struct { i32 ; };", &m);
    if(!testing::expect_true(m.diag.entries.len >= (u64)1, msg)) { return -1; }
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "T"), false, msg);
    if(!al) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)al), msg)) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag(al.target), msg)) { return -4; }
    return 0;
}

fn i32 anon_struct_in_alias_unclosed_brace_propagates(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias T = struct { i32 x;", &m);
    if(!testing::expect_true(m.diag.entries.len >= (u64)1, msg)) { return -1; }
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "T"), false, msg);
    if(!al) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)al), msg)) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag(al.target), msg)) { return -4; }
    return 0;
}

fn i32 anon_union_in_alias_body_error_propagates(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias V = union { i32 ; };", &m);
    if(!testing::expect_true(m.diag.entries.len >= (u64)1, msg)) { return -1; }
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "V"), false, msg);
    if(!al) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)al), msg)) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag(al.target), msg)) { return -4; }
    return 0;
}

fn i32 anon_struct_dot_in_alias_body_error_propagates(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias T = .{ i32 ; };", &m);
    if(!testing::expect_true(m.diag.entries.len >= (u64)1, msg)) { return -1; }
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "T"), false, msg);
    if(!al) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)al), msg)) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag(al.target), msg)) { return -4; }
    return 0;
}

fn i32 anon_struct_nested_in_alias_rejected(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias T = struct { struct { i32 x; } y; };", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "anonymous struct types are only allowed on the right-hand side of an `alias` declaration; use a named struct or wrap this in `alias`", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)19, msg)) { return -3; }
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "T"), false, msg);
    if(!al) { return -4; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)al), msg)) { return -5; }
    ast::TypeStructNode* outer = compiler_testing::expect_ty_anon_struct(al.target, 1, msg);
    if(!outer) { return -6; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)outer), msg)) { return -7; }
    if(!testing::expect_true(compiler_testing::has_error_flag(outer.fields.ptr[0].type_expr), msg)) { return -8; }
    return 0;
}

fn i32 anon_struct_in_cast_target_rejected(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 v = (struct { i32 x; })x;", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "anonymous struct types are only allowed on the right-hand side of an `alias` declaration; use a named struct or wrap this in `alias`", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)9, msg)) { return -3; }
    return 0;
}

fn i32 anon_struct_behind_pointer_rejected(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { struct { i32 x; }* p; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "anonymous struct types are only allowed on the right-hand side of an `alias` declaration; use a named struct or wrap this in `alias`", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)14, msg)) { return -3; }
    return 0;
}

fn i32 anon_struct_in_extern_fn_return_rejected(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { fn struct { i32 x; } f(); }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "anonymous struct types are only allowed on the right-hand side of an `alias` declaration; use a named struct or wrap this in `alias`", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)12, msg)) { return -3; }
    return 0;
}

fn i32 anon_two_decls_two_diags(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { struct { i32 a; } x; union { i32 b; } y; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)2, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "anonymous struct types are only allowed on the right-hand side of an `alias` declaration; use a named struct or wrap this in `alias`", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)14, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[1].msg, "anonymous union types are only allowed on the right-hand side of an `alias` declaration; use a named union or wrap this in `alias`", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[1].src_pos, (u32)35, msg)) { return -5; }
    return 0;
}

fn i32 anon_struct_in_fn_return_type_rejected(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn struct { i32 x; } g() { return { .x = 0 }; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "anonymous struct types are only allowed on the right-hand side of an `alias` declaration; use a named struct or wrap this in `alias`", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)3, msg)) { return -3; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "g"), 0, false, msg);
    if(!f) { return -4; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)f), msg)) { return -5; }
    if(!testing::expect_true(compiler_testing::has_error_flag(f.return_type), msg)) { return -6; }
    return 0;
}

fn i32 struct_field_nested_dot_anon_rejected(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "struct Foo { .{ i32 x; } inner; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "anonymous struct types are only allowed on the right-hand side of an `alias` declaration; use a named struct or wrap this in `alias`", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)13, msg)) { return -3; }
    ast::StructDeclNode* s = compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 0), null, 1, false, msg);
    if(!s) { return -4; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -5; }
    if(!testing::expect_true(compiler_testing::has_error_flag(s.fields.ptr[0].type_expr), msg)) { return -6; }
    return 0;
}

fn i32 anon_struct_in_fn_param_dot_rejected(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void g(.{ i32 x; } v) { }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "anonymous struct types are only allowed on the right-hand side of an `alias` declaration; use a named struct or wrap this in `alias`", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)10, msg)) { return -3; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "g"), 1, false, msg);
    if(!f) { return -4; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)f), msg)) { return -5; }
    if(!testing::expect_true(compiler_testing::has_error_flag(f.params.ptr[0].type_expr), msg)) { return -6; }
    return 0;
}

// `.` not followed by `{` at type position — parse_base_type's Dot case reports "expected '{'".
fn i32 dot_struct_dot_not_followed_by_lbrace(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias V = .x;", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), null, false, msg);
    if(!al) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)al), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '{', got identifier", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 11, msg)) { return -4; }
    return 0;
}

// ============================================================================
// ALIAS
// ============================================================================

fn i32 alias_primitive_rhs(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias U32 = u32;", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "U32"), false, msg);
    if(!al) { return -1; }
    if(!compiler_testing::expect_ty_prim(al.target, token::TokenKind::U32, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -3; }
    return 0;
}

fn i32 alias_named_rhs(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias MyFoo = Foo;", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "MyFoo"), false, msg);
    if(!al) { return -1; }
    if(!compiler_testing::expect_ty_named(al.target, null, compiler_testing::sym(m, "Foo"), msg)) { return -2; }
    return 0;
}

// User-requested pattern: `alias TestCase = testing::TestCase;` — qualified RHS.
fn i32 alias_qualified_named_rhs(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import testing; alias TestCase = testing::TestCase;", &m);
    ast::BlockNode* r = (ast::BlockNode*)root;
    if(!testing::expect_eq(r.stmts.len, 2, msg)) { return -1; }
    if(!compiler_testing::expect_import(r.stmts.ptr[0], compiler_testing::sym(m, "testing"), msg)) { return -2; }
    ast::AliasDeclNode* al = compiler_testing::expect_alias(r.stmts.ptr[1], compiler_testing::sym(m, "TestCase"), false, msg);
    if(!al) { return -3; }
    if(!compiler_testing::expect_ty_named(al.target, compiler_testing::sym(m, "testing"), compiler_testing::sym(m, "TestCase"), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 alias_pointer_rhs(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias Ptr = i32*;", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "Ptr"), false, msg);
    if(!al) { return -1; }
    ast::TypePointerNode* p = compiler_testing::expect_ty_ptr(al.target, msg);
    if(!p) { return -2; }
    if(!compiler_testing::expect_ty_prim(p.pointee, token::TokenKind::I32, msg)) { return -3; }
    return 0;
}

fn i32 alias_slice_rhs(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias Bytes = u8[];", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "Bytes"), false, msg);
    if(!al) { return -1; }
    ast::TypeSliceNode* s = compiler_testing::expect_ty_slice(al.target, msg);
    if(!s) { return -2; }
    if(!compiler_testing::expect_ty_prim(s.element, token::TokenKind::U8, msg)) { return -3; }
    return 0;
}

fn i32 alias_array_rhs(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias Pair = i32[2];", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "Pair"), false, msg);
    if(!al) { return -1; }
    ast::TypeArrayNode* ar = compiler_testing::expect_ty_array(al.target, msg);
    if(!ar) { return -2; }
    if(!compiler_testing::expect_ty_prim(ar.element, token::TokenKind::I32, msg)) { return -3; }
    if(!compiler_testing::expect_intlit(ar.size_expr, 2, msg)) { return -4; }
    return 0;
}

fn i32 alias_fn_ptr_rhs(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias Cb = fn* void(i32);", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "Cb"), false, msg);
    if(!al) { return -1; }
    if(!compiler_testing::expect_ty_fnptr(al.target, 1, msg)) { return -2; }
    return 0;
}

fn i32 alias_exported(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "export alias TokenId = u32;", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "TokenId"), true, msg);
    if(!al) { return -1; }
    if(!compiler_testing::expect_ty_prim(al.target, token::TokenKind::U32, msg)) { return -2; }
    return 0;
}

fn i32 alias_multiple_in_file(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias A = u32; alias B = A; alias C = B;", &m);
    ast::BlockNode* r = (ast::BlockNode*)root;
    if(!testing::expect_eq(r.stmts.len, 3, msg)) { return -1; }
    if(!compiler_testing::expect_alias(r.stmts.ptr[0], compiler_testing::sym(m, "A"), false, msg)) { return -2; }
    if(!compiler_testing::expect_alias(r.stmts.ptr[1], compiler_testing::sym(m, "B"), false, msg)) { return -3; }
    if(!compiler_testing::expect_alias(r.stmts.ptr[2], compiler_testing::sym(m, "C"), false, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 alias_mixed_with_other_decls(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import foo; alias A = u32; fn void f() { }", &m);
    ast::BlockNode* r = (ast::BlockNode*)root;
    if(!testing::expect_eq(r.stmts.len, 3, msg)) { return -1; }
    if(!compiler_testing::expect_import(r.stmts.ptr[0], compiler_testing::sym(m, "foo"), msg)) { return -2; }
    if(!compiler_testing::expect_alias(r.stmts.ptr[1], compiler_testing::sym(m, "A"), false, msg)) { return -3; }
    if(!compiler_testing::expect_fn_decl(r.stmts.ptr[2], compiler_testing::sym(m, "f"), 0, false, msg)) { return -4; }
    return 0;
}

fn i32 alias_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias U32 = u32;", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), null, false, msg);
    if(!al) { return -1; }
    if(!testing::expect_eq(al.h.src_pos, 0, msg)) { return -2; }
    return 0;
}

// With `export`: alias.src_pos points at the `alias` keyword, NOT at `export`
// (parse_top_decl consumes `export` before dispatching).
fn i32 alias_exported_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "export alias U32 = u32;", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), null, true, msg);
    if(!al) { return -1; }
    if(!testing::expect_eq(al.h.src_pos, 7, msg)) { return -2; }
    return 0;
}

fn i32 alias_missing_name(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias = u32;", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), null, false, msg);
    if(!al) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)al), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got '='", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 6, msg)) { return -4; }
    return 0;
}

fn i32 alias_missing_eq(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias U32 u32;", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), null, false, msg);
    if(!al) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)al), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '=', got 'u32'", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 10, msg)) { return -4; }
    return 0;
}

fn i32 alias_missing_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias U32 = ;", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), null, false, msg);
    if(!al) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)al), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ';'", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 12, msg)) { return -4; }
    return 0;
}

fn i32 alias_missing_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias U32 = u32", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), null, false, msg);
    if(!al) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)al), msg)) { return -2; }
    if(!compiler_testing::expect_diag_substr(m, "expected ';'", msg)) { return -3; }
    return 0;
}

fn i32 alias_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), null, false, msg);
    if(!al) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)al), msg)) { return -2; }
    if(!compiler_testing::expect_diag_substr(m, "expected identifier", msg)) { return -3; }
    return 0;
}

fn i32 alias_export_preserved_through_error(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "export alias = u32;", &m);
    ast::AliasDeclNode* al = compiler_testing::expect_alias(compiler_testing::nth_stmt(root, 0), null, true, msg);
    if(!al) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)al), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got '='", msg)) { return -3; }
    return 0;
}

fn i32 alias_exported_qualified_rhs(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import testing; export alias TestCase = testing::TestCase;", &m);
    ast::BlockNode* r = (ast::BlockNode*)root;
    if(!testing::expect_eq(r.stmts.len, 2, msg)) { return -1; }
    if(!compiler_testing::expect_import(r.stmts.ptr[0], compiler_testing::sym(m, "testing"), msg)) { return -2; }
    ast::AliasDeclNode* al = compiler_testing::expect_alias(r.stmts.ptr[1], compiler_testing::sym(m, "TestCase"), true, msg);
    if(!al) { return -3; }
    if(!compiler_testing::expect_ty_named(al.target, compiler_testing::sym(m, "testing"), compiler_testing::sym(m, "TestCase"), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 alias_recovery_continues(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "alias = u32; fn void f() { }", &m);
    ast::BlockNode* r = (ast::BlockNode*)root;
    if(!testing::expect_eq(r.stmts.len, 2, msg)) { return -1; }
    ast::AliasDeclNode* al = compiler_testing::expect_alias(r.stmts.ptr[0], null, false, msg);
    if(!al) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)al), msg)) { return -3; }
    if(!compiler_testing::expect_fn_decl(r.stmts.ptr[1], compiler_testing::sym(m, "f"), 0, false, msg)) { return -4; }
    return 0;
}

// ============================================================================
// COMPCODE  (expression: compcode { ... })
// ============================================================================

fn i32 compcode_in_var_decl_init(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 x = compcode { }; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -2; }
    ast::CompCodeNode* cc = compiler_testing::expect_compcode(v.init, msg);
    if(!cc) { return -3; }
    if(!compiler_testing::expect_block(cc.body, 0, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 compcode_in_return(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { return compcode { }; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!compiler_testing::expect_compcode(r.expr, msg)) { return -3; }
    return 0;
}

fn i32 compcode_in_compsplice_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compsplice compcode { }; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompSpliceNode* cs = compiler_testing::expect_compsplice(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cs) { return -2; }
    if(!compiler_testing::expect_compcode(cs.code_expr, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 compcode_in_compinsert_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compinsert(compcode { }); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompInsertNode* ci = compiler_testing::expect_compinsert(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ci) { return -2; }
    if(!compiler_testing::expect_compcode(ci.source_expr, msg)) { return -3; }
    return 0;
}

fn i32 compcode_in_call_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { return foo(compcode { }); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::CallNode* c = compiler_testing::expect_call(r.expr, 1, msg);
    if(!c) { return -3; }
    if(!compiler_testing::expect_compcode(c.args.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 compcode_as_if_cond(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (compcode { }) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* ifn = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ifn) { return -2; }
    if(!compiler_testing::expect_compcode(ifn.cond, msg)) { return -3; }
    return 0;
}

fn i32 compcode_as_switch_disc(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (compcode { }) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!compiler_testing::expect_compcode(s.discriminant, msg)) { return -3; }
    return 0;
}

fn i32 compcode_in_paren(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { return (compcode { }); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    if(!compiler_testing::expect_compcode(r.expr, msg)) { return -3; }
    if(!testing::expect_true(compiler_testing::has_paren_flag(r.expr), msg)) { return -4; }
    return 0;
}

fn i32 compcode_empty_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { return compcode { }; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::CompCodeNode* cc = compiler_testing::expect_compcode(r.expr, msg);
    if(!cc) { return -3; }
    if(!compiler_testing::expect_block(cc.body, 0, msg)) { return -4; }
    return 0;
}

fn i32 compcode_multi_stmt_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { return compcode { i32 y = 5; return y; }; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::CompCodeNode* cc = compiler_testing::expect_compcode(r.expr, msg);
    if(!cc) { return -3; }
    ast::BlockNode* body = compiler_testing::expect_block(cc.body, 2, msg);
    if(!body) { return -4; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "y"), false, false, msg)) { return -5; }
    if(!compiler_testing::expect_return(body.stmts.ptr[1], msg)) { return -6; }
    return 0;
}

fn i32 compcode_body_with_control_flow(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { return compcode { if (x) { } while (y) { } }; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::CompCodeNode* cc = compiler_testing::expect_compcode(r.expr, msg);
    if(!cc) { return -3; }
    ast::BlockNode* body = compiler_testing::expect_block(cc.body, 2, msg);
    if(!body) { return -4; }
    if(!compiler_testing::expect_if(body.stmts.ptr[0], msg)) { return -5; }
    if(!compiler_testing::expect_while(body.stmts.ptr[1], msg)) { return -6; }
    return 0;
}

fn i32 compcode_nested(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { return compcode { return compcode { }; }; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -2; }
    ast::CompCodeNode* outer = compiler_testing::expect_compcode(r.expr, msg);
    if(!outer) { return -3; }
    ast::BlockNode* obody = compiler_testing::expect_block(outer.body, 1, msg);
    if(!obody) { return -4; }
    ast::ReturnNode* inner_r = compiler_testing::expect_return(obody.stmts.ptr[0], msg);
    if(!inner_r) { return -5; }
    if(!compiler_testing::expect_compcode(inner_r.expr, msg)) { return -6; }
    return 0;
}

fn i32 compcode_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 x = compcode { }; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -2; }
    ast::CompCodeNode* cc = compiler_testing::expect_compcode(v.init, msg);
    if(!cc) { return -3; }
    if(!testing::expect_eq(cc.h.src_pos, 22, msg)) { return -4; }
    return 0;
}

fn i32 compcode_body_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 x = compcode { }; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -2; }
    ast::CompCodeNode* cc = compiler_testing::expect_compcode(v.init, msg);
    if(!cc) { return -3; }
    if(!testing::expect_eq(cc.body.h.src_pos, 31, msg)) { return -4; }
    return 0;
}

fn i32 compcode_missing_lbrace(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 x = compcode; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -2; }
    ast::CompCodeNode* cc = compiler_testing::expect_compcode(v.init, msg);
    if(!cc) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cc), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '{', got ';'", msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 30, msg)) { return -6; }
    return 0;
}

fn i32 compcode_unclosed_body_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 x = compcode {", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -2; }
    ast::CompCodeNode* cc = compiler_testing::expect_compcode(v.init, msg);
    if(!cc) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cc), msg)) { return -4; }
    if(!compiler_testing::expect_diag_substr(m, "expected '}'", msg)) { return -5; }
    return 0;
}

fn i32 compcode_body_error_propagates(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { i32 x = compcode { return 5 5; }; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::VarDeclNode* v = compiler_testing::expect_var(compiler_testing::nth_stmt(f.body, 0), compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -2; }
    ast::CompCodeNode* cc = compiler_testing::expect_compcode(v.init, msg);
    if(!cc) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cc), msg)) { return -4; }
    if(!testing::expect_true(compiler_testing::has_error_flag(cc.body), msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got integer literal", msg)) { return -6; }
    return 0;
}

// ============================================================================
// COMPSPLICE
// ============================================================================

fn i32 compsplice_ident_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compsplice code; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompSpliceNode* cs = compiler_testing::expect_compsplice(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cs) { return -2; }
    if(!compiler_testing::expect_ident(cs.code_expr, compiler_testing::sym(m, "code"), msg)) { return -3; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)cs), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 compsplice_call_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compsplice gen(); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompSpliceNode* cs = compiler_testing::expect_compsplice(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cs) { return -2; }
    if(!compiler_testing::expect_call(cs.code_expr, 0, msg)) { return -3; }
    return 0;
}

fn i32 compsplice_namespace_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compsplice mod::x; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompSpliceNode* cs = compiler_testing::expect_compsplice(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cs) { return -2; }
    if(!compiler_testing::expect_nsacc(cs.code_expr, compiler_testing::sym(m, "mod"), compiler_testing::sym(m, "x"), msg)) { return -3; }
    return 0;
}

fn i32 compsplice_pratt_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compsplice a + b * 2; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompSpliceNode* cs = compiler_testing::expect_compsplice(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cs) { return -2; }
    ast::BinaryOpNode* plus = compiler_testing::expect_binop(cs.code_expr, token::TokenKind::Plus, msg);
    if(!plus) { return -3; }
    if(!compiler_testing::expect_binop(plus.rhs, token::TokenKind::Star, msg)) { return -4; }
    return 0;
}

fn i32 compsplice_in_bare_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { compsplice x; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* inner = compiler_testing::expect_block(compiler_testing::nth_stmt(f.body, 0), 1, msg);
    if(!inner) { return -2; }
    if(!compiler_testing::expect_compsplice(inner.stmts.ptr[0], msg)) { return -3; }
    return 0;
}

fn i32 compsplice_in_defer_single_stmt(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer compsplice x; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    ast::BlockNode* db = compiler_testing::expect_block(d.body, 1, msg);
    if(!db) { return -3; }
    if(!compiler_testing::expect_compsplice(db.stmts.ptr[0], msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 compsplice_full_comp_family_sequence(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compsplice x; compinsert(\"a\"); comperror(\"b\"); compwarning(\"c\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 4, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_compsplice(body.stmts.ptr[0], msg)) { return -3; }
    if(!compiler_testing::expect_compinsert(body.stmts.ptr[1], msg)) { return -4; }
    if(!compiler_testing::expect_comperror(body.stmts.ptr[2], msg)) { return -5; }
    if(!compiler_testing::expect_compwarning(body.stmts.ptr[3], msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 compsplice_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compsplice x; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompSpliceNode* cs = compiler_testing::expect_compsplice(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cs) { return -2; }
    if(!testing::expect_eq(cs.h.src_pos, 14, msg)) { return -3; }
    return 0;
}

fn i32 compsplice_arg_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compsplice x; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompSpliceNode* cs = compiler_testing::expect_compsplice(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cs) { return -2; }
    if(!testing::expect_eq(cs.code_expr.h.src_pos, 25, msg)) { return -3; }
    return 0;
}

fn i32 compsplice_just_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compsplice; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompSpliceNode* cs = compiler_testing::expect_compsplice(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cs) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cs), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ';'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 24, msg)) { return -5; }
    return 0;
}

fn i32 compsplice_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compsplice", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompSpliceNode* cs = compiler_testing::expect_compsplice(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cs) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cs), msg)) { return -3; }
    if(!compiler_testing::expect_diag_substr(m, "expected identifier", msg)) { return -4; }
    return 0;
}

fn i32 compsplice_missing_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compsplice x }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompSpliceNode* cs = compiler_testing::expect_compsplice(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cs) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cs), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got '}'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 27, msg)) { return -5; }
    return 0;
}

fn i32 compsplice_malformed_expr(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compsplice 5 +; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompSpliceNode* cs = compiler_testing::expect_compsplice(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cs) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cs), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ';'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 28, msg)) { return -5; }
    return 0;
}

fn i32 compsplice_recovery_continues(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compsplice; i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    ast::CompSpliceNode* cs = compiler_testing::expect_compsplice(body.stmts.ptr[0], msg);
    if(!cs) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cs), msg)) { return -4; }
    ast::VarDeclNode* v = compiler_testing::expect_var(body.stmts.ptr[1], compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -5; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)v), msg)) { return -6; }
    return 0;
}

// ============================================================================
// COMPINSERT
// ============================================================================

fn i32 compinsert_string_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compinsert(\"src\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompInsertNode* ci = compiler_testing::expect_compinsert(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ci) { return -2; }
    if(!testing::expect_eq((u16)ci.source_expr.h.kind, (u16)ast::AstKind::StringLit, msg)) { return -3; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)ci), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 compinsert_intlit_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compinsert(7); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompInsertNode* ci = compiler_testing::expect_compinsert(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ci) { return -2; }
    if(!compiler_testing::expect_intlit(ci.source_expr, 7, msg)) { return -3; }
    return 0;
}

fn i32 compinsert_ident_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compinsert(SRC); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompInsertNode* ci = compiler_testing::expect_compinsert(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ci) { return -2; }
    if(!compiler_testing::expect_ident(ci.source_expr, compiler_testing::sym(m, "SRC"), msg)) { return -3; }
    return 0;
}

fn i32 compinsert_pratt_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compinsert(a + b); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompInsertNode* ci = compiler_testing::expect_compinsert(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ci) { return -2; }
    if(!compiler_testing::expect_binop(ci.source_expr, token::TokenKind::Plus, msg)) { return -3; }
    return 0;
}

fn i32 compinsert_call_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compinsert(gen()); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompInsertNode* ci = compiler_testing::expect_compinsert(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ci) { return -2; }
    if(!compiler_testing::expect_call(ci.source_expr, 0, msg)) { return -3; }
    return 0;
}

fn i32 compinsert_in_bare_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { compinsert(\"x\"); } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* inner = compiler_testing::expect_block(compiler_testing::nth_stmt(f.body, 0), 1, msg);
    if(!inner) { return -2; }
    if(!compiler_testing::expect_compinsert(inner.stmts.ptr[0], msg)) { return -3; }
    return 0;
}

fn i32 compinsert_in_defer_single_stmt(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer compinsert(\"x\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    ast::BlockNode* db = compiler_testing::expect_block(d.body, 1, msg);
    if(!db) { return -3; }
    if(!compiler_testing::expect_compinsert(db.stmts.ptr[0], msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 compinsert_comperror_compwarning_sequence(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compinsert(\"a\"); comperror(\"b\"); compwarning(\"c\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 3, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_compinsert(body.stmts.ptr[0], msg)) { return -3; }
    if(!compiler_testing::expect_comperror(body.stmts.ptr[1], msg)) { return -4; }
    if(!compiler_testing::expect_compwarning(body.stmts.ptr[2], msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 compinsert_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compinsert(\"x\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompInsertNode* ci = compiler_testing::expect_compinsert(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ci) { return -2; }
    if(!testing::expect_eq(ci.h.src_pos, 14, msg)) { return -3; }
    return 0;
}

fn i32 compinsert_arg_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compinsert(\"x\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompInsertNode* ci = compiler_testing::expect_compinsert(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ci) { return -2; }
    if(!testing::expect_eq(ci.source_expr.h.src_pos, 25, msg)) { return -3; }
    return 0;
}

fn i32 compinsert_missing_lparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compinsert \"x\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompInsertNode* ci = compiler_testing::expect_compinsert(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ci) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)ci), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '(', got string literal", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 25, msg)) { return -5; }
    return 0;
}

fn i32 compinsert_missing_rparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compinsert(\"x\"; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompInsertNode* ci = compiler_testing::expect_compinsert(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ci) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)ci), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ')', got ';'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 28, msg)) { return -5; }
    return 0;
}

fn i32 compinsert_missing_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compinsert(\"x\") }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompInsertNode* ci = compiler_testing::expect_compinsert(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ci) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)ci), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got '}'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 30, msg)) { return -5; }
    return 0;
}

fn i32 compinsert_empty_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compinsert(); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompInsertNode* ci = compiler_testing::expect_compinsert(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ci) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)ci), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ')'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 25, msg)) { return -5; }
    return 0;
}

fn i32 compinsert_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compinsert", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompInsertNode* ci = compiler_testing::expect_compinsert(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ci) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)ci), msg)) { return -3; }
    if(!compiler_testing::expect_diag_substr(m, "expected '('", msg)) { return -4; }
    return 0;
}

fn i32 compinsert_recovery_continues(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compinsert(); i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    ast::CompInsertNode* ci = compiler_testing::expect_compinsert(body.stmts.ptr[0], msg);
    if(!ci) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)ci), msg)) { return -4; }
    ast::VarDeclNode* v = compiler_testing::expect_var(body.stmts.ptr[1], compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -5; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)v), msg)) { return -6; }
    return 0;
}

// ============================================================================
// COMPRUN
// ============================================================================

fn i32 comprun_top_level_empty(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "comprun { }", &m);
    ast::CompRunNode* cr = compiler_testing::expect_comprun(compiler_testing::nth_stmt(root, 0), msg);
    if(!cr) { return -1; }
    if(!compiler_testing::expect_block(cr.body, 0, msg)) { return -2; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)cr), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 comprun_top_level_with_stmts(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "comprun { i32 x = 5; }", &m);
    ast::CompRunNode* cr = compiler_testing::expect_comprun(compiler_testing::nth_stmt(root, 0), msg);
    if(!cr) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(cr.body, 1, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "x"), false, false, msg)) { return -3; }
    return 0;
}

fn i32 comprun_top_level_mixed_with_decls(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import foo; comprun { } fn void f() { }", &m);
    ast::BlockNode* r = (ast::BlockNode*)root;
    if(!testing::expect_eq(r.stmts.len, 3, msg)) { return -1; }
    if(!compiler_testing::expect_import(r.stmts.ptr[0], compiler_testing::sym(m, "foo"), msg)) { return -2; }
    if(!compiler_testing::expect_comprun(r.stmts.ptr[1], msg)) { return -3; }
    if(!compiler_testing::expect_fn_decl(r.stmts.ptr[2], compiler_testing::sym(m, "f"), 0, false, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 comprun_export_is_error(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "export comprun { i32 x = 5; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "`export` is not valid on `comprun` (it does not declare a named symbol)", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)7, msg)) { return -3; }
    ast::CompRunNode* cr = compiler_testing::expect_comprun(compiler_testing::nth_stmt(root, 0), msg);
    if(!cr) { return -4; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cr), msg)) { return -5; }
    ast::BlockNode* body = compiler_testing::expect_block(cr.body, 1, msg);
    if(!body) { return -6; }
    return 0;
}

fn i32 comprun_export_then_valid_decl_recovers(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "export comprun { } export fn void f() { }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -1; }
    ast::BlockNode* r = (ast::BlockNode*)root;
    if(!testing::expect_eq(r.stmts.len, (u64)2, msg)) { return -2; }
    if(!compiler_testing::expect_comprun(r.stmts.ptr[0], msg)) { return -3; }
    if(!compiler_testing::expect_fn_decl(r.stmts.ptr[1], compiler_testing::sym(m, "f"), 0, true, msg)) { return -4; }
    return 0;
}

fn i32 comprun_two_exports_two_diags(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "export comprun { } export comprun { }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)2, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "`export` is not valid on `comprun` (it does not declare a named symbol)", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[1].msg, "`export` is not valid on `comprun` (it does not declare a named symbol)", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)7, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[1].src_pos, (u32)26, msg)) { return -5; }
    ast::BlockNode* r = (ast::BlockNode*)root;
    if(!testing::expect_eq(r.stmts.len, (u64)2, msg)) { return -6; }
    ast::CompRunNode* cr0 = compiler_testing::expect_comprun(r.stmts.ptr[0], msg);
    if(!cr0) { return -7; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cr0), msg)) { return -8; }
    ast::CompRunNode* cr1 = compiler_testing::expect_comprun(r.stmts.ptr[1], msg);
    if(!cr1) { return -9; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cr1), msg)) { return -10; }
    return 0;
}

fn i32 comprun_in_fn_empty(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comprun { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompRunNode* cr = compiler_testing::expect_comprun(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cr) { return -2; }
    if(!compiler_testing::expect_block(cr.body, 0, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 comprun_in_fn_multi_stmt(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comprun { i32 y = 5; return; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompRunNode* cr = compiler_testing::expect_comprun(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cr) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(cr.body, 2, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "y"), false, false, msg)) { return -4; }
    if(!compiler_testing::expect_return(body.stmts.ptr[1], msg)) { return -5; }
    return 0;
}

fn i32 comprun_in_bare_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { comprun { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* inner = compiler_testing::expect_block(compiler_testing::nth_stmt(f.body, 0), 1, msg);
    if(!inner) { return -2; }
    if(!compiler_testing::expect_comprun(inner.stmts.ptr[0], msg)) { return -3; }
    return 0;
}

fn i32 comprun_in_if_then(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (a) { comprun { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* ifn = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ifn) { return -2; }
    ast::BlockNode* tb = compiler_testing::expect_block(ifn.then_block, 1, msg);
    if(!tb) { return -3; }
    if(!compiler_testing::expect_comprun(tb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 comprun_in_if_else(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (a) { } else { comprun { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* ifn = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ifn) { return -2; }
    ast::BlockNode* eb = compiler_testing::expect_block(ifn.else_block, 1, msg);
    if(!eb) { return -3; }
    if(!compiler_testing::expect_comprun(eb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 comprun_in_while_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (a) { comprun { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BlockNode* wb = compiler_testing::expect_block(w.body, 1, msg);
    if(!wb) { return -3; }
    if(!compiler_testing::expect_comprun(wb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 comprun_in_for_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { comprun { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::BlockNode* fb = compiler_testing::expect_block(fr.body, 1, msg);
    if(!fb) { return -3; }
    if(!compiler_testing::expect_comprun(fb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 comprun_in_switch_arm(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: { comprun { } } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    ast::BlockNode* armb = compiler_testing::expect_block(s.arms.ptr[0].body, 1, msg);
    if(!armb) { return -3; }
    if(!compiler_testing::expect_comprun(armb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 comprun_in_switch_else(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { else { comprun { } } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    ast::BlockNode* eb = compiler_testing::expect_block(s.else_block, 1, msg);
    if(!eb) { return -3; }
    if(!compiler_testing::expect_comprun(eb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 comprun_in_defer_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer { comprun { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    ast::BlockNode* db = compiler_testing::expect_block(d.body, 1, msg);
    if(!db) { return -3; }
    if(!compiler_testing::expect_comprun(db.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 comprun_in_defer_single_stmt(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer comprun { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    ast::BlockNode* db = compiler_testing::expect_block(d.body, 1, msg);
    if(!db) { return -3; }
    if(!compiler_testing::expect_comprun(db.stmts.ptr[0], msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 comprun_two_consecutive_top_level(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "comprun { } comprun { }", &m);
    ast::BlockNode* r = (ast::BlockNode*)root;
    if(!testing::expect_eq(r.stmts.len, 2, msg)) { return -1; }
    if(!compiler_testing::expect_comprun(r.stmts.ptr[0], msg)) { return -2; }
    if(!compiler_testing::expect_comprun(r.stmts.ptr[1], msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 comprun_two_consecutive_in_fn(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comprun { } comprun { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_comprun(body.stmts.ptr[0], msg)) { return -3; }
    if(!compiler_testing::expect_comprun(body.stmts.ptr[1], msg)) { return -4; }
    return 0;
}

fn i32 comprun_combined_with_var_and_return(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { i32 r = 0; comprun { } return r; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 3, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "r"), false, false, msg)) { return -3; }
    if(!compiler_testing::expect_comprun(body.stmts.ptr[1], msg)) { return -4; }
    if(!compiler_testing::expect_return(body.stmts.ptr[2], msg)) { return -5; }
    return 0;
}

fn i32 comprun_nested(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "comprun { comprun { } }", &m);
    ast::CompRunNode* outer = compiler_testing::expect_comprun(compiler_testing::nth_stmt(root, 0), msg);
    if(!outer) { return -1; }
    ast::BlockNode* obody = compiler_testing::expect_block(outer.body, 1, msg);
    if(!obody) { return -2; }
    ast::CompRunNode* inner = compiler_testing::expect_comprun(obody.stmts.ptr[0], msg);
    if(!inner) { return -3; }
    if(!compiler_testing::expect_block(inner.body, 0, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 comprun_body_with_control_flow(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "comprun { if (x) { } while (y) { } }", &m);
    ast::CompRunNode* cr = compiler_testing::expect_comprun(compiler_testing::nth_stmt(root, 0), msg);
    if(!cr) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(cr.body, 2, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_if(body.stmts.ptr[0], msg)) { return -3; }
    if(!compiler_testing::expect_while(body.stmts.ptr[1], msg)) { return -4; }
    return 0;
}

fn i32 comprun_src_pos_top_level(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "comprun { }", &m);
    ast::CompRunNode* cr = compiler_testing::expect_comprun(compiler_testing::nth_stmt(root, 0), msg);
    if(!cr) { return -1; }
    if(!testing::expect_eq(cr.h.src_pos, 0, msg)) { return -2; }
    return 0;
}

fn i32 comprun_src_pos_in_fn(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comprun { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompRunNode* cr = compiler_testing::expect_comprun(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cr) { return -2; }
    if(!testing::expect_eq(cr.h.src_pos, 14, msg)) { return -3; }
    return 0;
}

fn i32 comprun_body_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "comprun { }", &m);
    ast::CompRunNode* cr = compiler_testing::expect_comprun(compiler_testing::nth_stmt(root, 0), msg);
    if(!cr) { return -1; }
    if(!testing::expect_eq(cr.body.h.src_pos, 8, msg)) { return -2; }
    return 0;
}

fn i32 comprun_missing_lbrace_top_level(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "comprun }", &m);
    ast::CompRunNode* cr = compiler_testing::expect_comprun(compiler_testing::nth_stmt(root, 0), msg);
    if(!cr) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cr), msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '{', got '}'", msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 8, msg)) { return -4; }
    return 0;
}

fn i32 comprun_missing_lbrace_in_fn(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comprun ; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompRunNode* cr = compiler_testing::expect_comprun(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cr) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cr), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '{', got ';'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 22, msg)) { return -5; }
    return 0;
}

fn i32 comprun_unclosed_body_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "comprun {", &m);
    ast::CompRunNode* cr = compiler_testing::expect_comprun(compiler_testing::nth_stmt(root, 0), msg);
    if(!cr) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cr), msg)) { return -2; }
    if(!compiler_testing::expect_diag_substr(m, "expected '}'", msg)) { return -3; }
    return 0;
}

fn i32 comprun_body_error_propagates(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "comprun { return 5 5; }", &m);
    ast::CompRunNode* cr = compiler_testing::expect_comprun(compiler_testing::nth_stmt(root, 0), msg);
    if(!cr) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cr), msg)) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag(cr.body), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got integer literal", msg)) { return -4; }
    return 0;
}

fn i32 comprun_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "comprun", &m);
    ast::CompRunNode* cr = compiler_testing::expect_comprun(compiler_testing::nth_stmt(root, 0), msg);
    if(!cr) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cr), msg)) { return -2; }
    if(!compiler_testing::expect_diag_substr(m, "expected '{'", msg)) { return -3; }
    return 0;
}

fn i32 comprun_recovery_continues_top_level(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "comprun { return 5 5; } fn void f() { }", &m);
    ast::BlockNode* r = (ast::BlockNode*)root;
    if(!testing::expect_eq(r.stmts.len, 2, msg)) { return -1; }
    ast::CompRunNode* cr = compiler_testing::expect_comprun(r.stmts.ptr[0], msg);
    if(!cr) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cr), msg)) { return -3; }
    if(!compiler_testing::expect_fn_decl(r.stmts.ptr[1], compiler_testing::sym(m, "f"), 0, false, msg)) { return -4; }
    return 0;
}

fn i32 comprun_recovery_continues_in_fn(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comprun { return 5 5; } i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    ast::CompRunNode* cr = compiler_testing::expect_comprun(body.stmts.ptr[0], msg);
    if(!cr) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cr), msg)) { return -4; }
    ast::VarDeclNode* v = compiler_testing::expect_var(body.stmts.ptr[1], compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -5; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)v), msg)) { return -6; }
    return 0;
}

// ============================================================================
// COMPERROR / COMPWARNING
// ============================================================================

fn i32 comperror_string_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comperror(\"oops\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompErrorNode* ce = compiler_testing::expect_comperror(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ce) { return -2; }
    if(!testing::expect_eq((u16)ce.msg_expr.h.kind, (u16)ast::AstKind::StringLit, msg)) { return -3; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)ce), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 comperror_intlit_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comperror(42); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompErrorNode* ce = compiler_testing::expect_comperror(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ce) { return -2; }
    if(!compiler_testing::expect_intlit(ce.msg_expr, 42, msg)) { return -3; }
    return 0;
}

fn i32 comperror_ident_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comperror(MSG); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompErrorNode* ce = compiler_testing::expect_comperror(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ce) { return -2; }
    if(!compiler_testing::expect_ident(ce.msg_expr, compiler_testing::sym(m, "MSG"), msg)) { return -3; }
    return 0;
}

fn i32 comperror_namespace_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comperror(mod::MSG); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompErrorNode* ce = compiler_testing::expect_comperror(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ce) { return -2; }
    if(!compiler_testing::expect_nsacc(ce.msg_expr, compiler_testing::sym(m, "mod"), compiler_testing::sym(m, "MSG"), msg)) { return -3; }
    return 0;
}

fn i32 comperror_pratt_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comperror(a + b * 2); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompErrorNode* ce = compiler_testing::expect_comperror(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ce) { return -2; }
    ast::BinaryOpNode* plus = compiler_testing::expect_binop(ce.msg_expr, token::TokenKind::Plus, msg);
    if(!plus) { return -3; }
    if(!compiler_testing::expect_binop(plus.rhs, token::TokenKind::Star, msg)) { return -4; }
    return 0;
}

fn i32 comperror_call_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comperror(fmt(\"%d\", x)); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompErrorNode* ce = compiler_testing::expect_comperror(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ce) { return -2; }
    if(!compiler_testing::expect_call(ce.msg_expr, 2, msg)) { return -3; }
    return 0;
}

fn i32 comperror_in_bare_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { comperror(\"oops\"); } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* inner = compiler_testing::expect_block(compiler_testing::nth_stmt(f.body, 0), 1, msg);
    if(!inner) { return -2; }
    if(!compiler_testing::expect_comperror(inner.stmts.ptr[0], msg)) { return -3; }
    return 0;
}

fn i32 comperror_in_if_then(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (a) { comperror(\"x\"); } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* ifn = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ifn) { return -2; }
    ast::BlockNode* tb = compiler_testing::expect_block(ifn.then_block, 1, msg);
    if(!tb) { return -3; }
    if(!compiler_testing::expect_comperror(tb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 comperror_in_if_else(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (a) { } else { comperror(\"x\"); } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* ifn = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ifn) { return -2; }
    ast::BlockNode* eb = compiler_testing::expect_block(ifn.else_block, 1, msg);
    if(!eb) { return -3; }
    if(!compiler_testing::expect_comperror(eb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 comperror_in_while_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (a) { comperror(\"x\"); } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BlockNode* wb = compiler_testing::expect_block(w.body, 1, msg);
    if(!wb) { return -3; }
    if(!compiler_testing::expect_comperror(wb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 comperror_in_for_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { comperror(\"x\"); } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::BlockNode* fb = compiler_testing::expect_block(fr.body, 1, msg);
    if(!fb) { return -3; }
    if(!compiler_testing::expect_comperror(fb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 comperror_in_switch_arm(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: { comperror(\"x\"); } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    ast::BlockNode* armb = compiler_testing::expect_block(s.arms.ptr[0].body, 1, msg);
    if(!armb) { return -3; }
    if(!compiler_testing::expect_comperror(armb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 comperror_in_switch_else(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { else { comperror(\"x\"); } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    ast::BlockNode* eb = compiler_testing::expect_block(s.else_block, 1, msg);
    if(!eb) { return -3; }
    if(!compiler_testing::expect_comperror(eb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 comperror_in_defer_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer { comperror(\"x\"); } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    ast::BlockNode* db = compiler_testing::expect_block(d.body, 1, msg);
    if(!db) { return -3; }
    if(!compiler_testing::expect_comperror(db.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 comperror_two_consecutive(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comperror(\"a\"); comperror(\"b\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_comperror(body.stmts.ptr[0], msg)) { return -3; }
    if(!compiler_testing::expect_comperror(body.stmts.ptr[1], msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 comperror_combined_with_var_and_return(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { i32 r = 0; comperror(\"x\"); return r; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 3, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "r"), false, false, msg)) { return -3; }
    if(!compiler_testing::expect_comperror(body.stmts.ptr[1], msg)) { return -4; }
    if(!compiler_testing::expect_return(body.stmts.ptr[2], msg)) { return -5; }
    return 0;
}

fn i32 comperror_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comperror(\"x\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompErrorNode* ce = compiler_testing::expect_comperror(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ce) { return -2; }
    if(!testing::expect_eq(ce.h.src_pos, 14, msg)) { return -3; }
    return 0;
}

fn i32 comperror_arg_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comperror(\"x\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompErrorNode* ce = compiler_testing::expect_comperror(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ce) { return -2; }
    if(!testing::expect_eq(ce.msg_expr.h.src_pos, 24, msg)) { return -3; }
    return 0;
}

fn i32 comperror_missing_lparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comperror \"x\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompErrorNode* ce = compiler_testing::expect_comperror(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ce) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)ce), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '(', got string literal", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 24, msg)) { return -5; }
    return 0;
}

fn i32 comperror_missing_rparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comperror(\"x\"; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompErrorNode* ce = compiler_testing::expect_comperror(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ce) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)ce), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ')', got ';'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 27, msg)) { return -5; }
    return 0;
}

fn i32 comperror_empty_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comperror(); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompErrorNode* ce = compiler_testing::expect_comperror(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ce) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)ce), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ')'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 24, msg)) { return -5; }
    return 0;
}

fn i32 comperror_missing_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comperror(\"x\") }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompErrorNode* ce = compiler_testing::expect_comperror(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ce) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)ce), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got '}'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 29, msg)) { return -5; }
    return 0;
}

fn i32 comperror_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comperror", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompErrorNode* ce = compiler_testing::expect_comperror(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ce) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)ce), msg)) { return -3; }
    if(!compiler_testing::expect_diag_substr(m, "expected '('", msg)) { return -4; }
    return 0;
}

fn i32 comperror_recovery_continues(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comperror(); i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    ast::CompErrorNode* ce = compiler_testing::expect_comperror(body.stmts.ptr[0], msg);
    if(!ce) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)ce), msg)) { return -4; }
    ast::VarDeclNode* v = compiler_testing::expect_var(body.stmts.ptr[1], compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -5; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)v), msg)) { return -6; }
    return 0;
}

// compwarning mirrors (structurally identical parser; sample coverage to verify dispatch)
fn i32 compwarning_string_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compwarning(\"slow\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompWarningNode* cw = compiler_testing::expect_compwarning(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cw) { return -2; }
    if(!testing::expect_eq((u16)cw.msg_expr.h.kind, (u16)ast::AstKind::StringLit, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 compwarning_intlit_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compwarning(7); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompWarningNode* cw = compiler_testing::expect_compwarning(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cw) { return -2; }
    if(!compiler_testing::expect_intlit(cw.msg_expr, 7, msg)) { return -3; }
    return 0;
}

fn i32 compwarning_pratt_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compwarning(a + b); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompWarningNode* cw = compiler_testing::expect_compwarning(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cw) { return -2; }
    if(!compiler_testing::expect_binop(cw.msg_expr, token::TokenKind::Plus, msg)) { return -3; }
    return 0;
}

fn i32 compwarning_in_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { compwarning(\"x\"); } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* inner = compiler_testing::expect_block(compiler_testing::nth_stmt(f.body, 0), 1, msg);
    if(!inner) { return -2; }
    if(!compiler_testing::expect_compwarning(inner.stmts.ptr[0], msg)) { return -3; }
    return 0;
}

fn i32 compwarning_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compwarning(\"x\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompWarningNode* cw = compiler_testing::expect_compwarning(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cw) { return -2; }
    if(!testing::expect_eq(cw.h.src_pos, 14, msg)) { return -3; }
    return 0;
}

fn i32 compwarning_missing_lparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compwarning \"x\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompWarningNode* cw = compiler_testing::expect_compwarning(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cw) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cw), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '(', got string literal", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 26, msg)) { return -5; }
    return 0;
}

fn i32 compwarning_missing_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compwarning(\"x\") }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompWarningNode* cw = compiler_testing::expect_compwarning(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cw) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cw), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got '}'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 31, msg)) { return -5; }
    return 0;
}

fn i32 compwarning_arg_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compwarning(\"x\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompWarningNode* cw = compiler_testing::expect_compwarning(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cw) { return -2; }
    if(!testing::expect_eq(cw.msg_expr.h.src_pos, 26, msg)) { return -3; }
    return 0;
}

fn i32 compwarning_missing_rparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compwarning(\"x\"; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompWarningNode* cw = compiler_testing::expect_compwarning(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cw) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cw), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ')', got ';'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 29, msg)) { return -5; }
    return 0;
}

fn i32 compwarning_empty_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compwarning(); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompWarningNode* cw = compiler_testing::expect_compwarning(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cw) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cw), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ')'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 26, msg)) { return -5; }
    return 0;
}

fn i32 compwarning_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compwarning", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::CompWarningNode* cw = compiler_testing::expect_compwarning(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!cw) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cw), msg)) { return -3; }
    if(!compiler_testing::expect_diag_substr(m, "expected '('", msg)) { return -4; }
    return 0;
}

fn i32 compwarning_recovery_continues(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { compwarning(); i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    ast::CompWarningNode* cw = compiler_testing::expect_compwarning(body.stmts.ptr[0], msg);
    if(!cw) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)cw), msg)) { return -4; }
    ast::VarDeclNode* v = compiler_testing::expect_var(body.stmts.ptr[1], compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -5; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)v), msg)) { return -6; }
    return 0;
}

fn i32 comperror_in_defer_single_stmt(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer comperror(\"x\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    ast::BlockNode* db = compiler_testing::expect_block(d.body, 1, msg);
    if(!db) { return -3; }
    if(!compiler_testing::expect_comperror(db.stmts.ptr[0], msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 compwarning_in_defer_single_stmt(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer compwarning(\"x\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    ast::BlockNode* db = compiler_testing::expect_block(d.body, 1, msg);
    if(!db) { return -3; }
    if(!compiler_testing::expect_compwarning(db.stmts.ptr[0], msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 comperror_then_compwarning(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { comperror(\"a\"); compwarning(\"b\"); }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_comperror(body.stmts.ptr[0], msg)) { return -3; }
    if(!compiler_testing::expect_compwarning(body.stmts.ptr[1], msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

// ============================================================================
// DEFER
// ============================================================================

fn i32 defer_block_empty(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    if(!compiler_testing::expect_block(d.body, 0, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 defer_block_multi_stmt(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer { i32 x = 5; return; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(d.body, 2, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "x"), false, false, msg)) { return -4; }
    if(!compiler_testing::expect_return(body.stmts.ptr[1], msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

// Single-stmt body is wrapped in a synthetic BlockNode of length 1.
fn i32 defer_single_body_is_synthetic_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer break; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(d.body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_break(body.stmts.ptr[0], msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 defer_single_return(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer return; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(d.body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_return(body.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 defer_single_continue(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer continue; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(d.body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_continue(body.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 defer_single_if(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer if (x) { } else { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(d.body, 1, msg);
    if(!body) { return -3; }
    ast::IfNode* ifn = compiler_testing::expect_if(body.stmts.ptr[0], msg);
    if(!ifn) { return -4; }
    if(!testing::expect_not_null((void*)ifn.else_block, msg)) { return -5; }
    return 0;
}

fn i32 defer_single_while(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer while (x) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(d.body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_while(body.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 defer_single_for(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer for (;;) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(d.body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_for(body.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 defer_single_switch(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer switch (x) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(d.body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_switch(body.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 defer_single_var_decl(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(d.body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "x"), false, false, msg)) { return -4; }
    return 0;
}

fn i32 defer_single_const_var_decl(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer const i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(d.body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "x"), true, false, msg)) { return -4; }
    return 0;
}

// NESTING
fn i32 defer_nested_block_in_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer { defer { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* outer = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!outer) { return -2; }
    ast::BlockNode* obody = compiler_testing::expect_block(outer.body, 1, msg);
    if(!obody) { return -3; }
    ast::DeferNode* inner = compiler_testing::expect_defer(obody.stmts.ptr[0], msg);
    if(!inner) { return -4; }
    if(!compiler_testing::expect_block(inner.body, 0, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 defer_nested_single_in_single(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer defer break; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* outer = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!outer) { return -2; }
    ast::BlockNode* obody = compiler_testing::expect_block(outer.body, 1, msg);
    if(!obody) { return -3; }
    ast::DeferNode* inner = compiler_testing::expect_defer(obody.stmts.ptr[0], msg);
    if(!inner) { return -4; }
    ast::BlockNode* ibody = compiler_testing::expect_block(inner.body, 1, msg);
    if(!ibody) { return -5; }
    if(!compiler_testing::expect_break(ibody.stmts.ptr[0], msg)) { return -6; }
    return 0;
}

fn i32 defer_single_inside_block_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer { defer break; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* outer = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!outer) { return -2; }
    ast::BlockNode* obody = compiler_testing::expect_block(outer.body, 1, msg);
    if(!obody) { return -3; }
    ast::DeferNode* inner = compiler_testing::expect_defer(obody.stmts.ptr[0], msg);
    if(!inner) { return -4; }
    ast::BlockNode* ibody = compiler_testing::expect_block(inner.body, 1, msg);
    if(!ibody) { return -5; }
    if(!compiler_testing::expect_break(ibody.stmts.ptr[0], msg)) { return -6; }
    return 0;
}

// SURROUNDING CONTEXTS
fn i32 defer_in_bare_block(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { { defer { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* inner = compiler_testing::expect_block(compiler_testing::nth_stmt(f.body, 0), 1, msg);
    if(!inner) { return -2; }
    if(!compiler_testing::expect_defer(inner.stmts.ptr[0], msg)) { return -3; }
    return 0;
}

fn i32 defer_in_if_then(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (a) { defer { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* ifn = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ifn) { return -2; }
    ast::BlockNode* tb = compiler_testing::expect_block(ifn.then_block, 1, msg);
    if(!tb) { return -3; }
    if(!compiler_testing::expect_defer(tb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 defer_in_else_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (a) { } else { defer { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* ifn = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ifn) { return -2; }
    ast::BlockNode* eb = compiler_testing::expect_block(ifn.else_block, 1, msg);
    if(!eb) { return -3; }
    if(!compiler_testing::expect_defer(eb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 defer_in_while_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (a) { defer { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BlockNode* wb = compiler_testing::expect_block(w.body, 1, msg);
    if(!wb) { return -3; }
    if(!compiler_testing::expect_defer(wb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 defer_in_for_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { defer { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::BlockNode* fb = compiler_testing::expect_block(fr.body, 1, msg);
    if(!fb) { return -3; }
    if(!compiler_testing::expect_defer(fb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 defer_in_switch_arm(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: { defer { } } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    ast::BlockNode* abody = compiler_testing::expect_block(s.arms.ptr[0].body, 1, msg);
    if(!abody) { return -3; }
    if(!compiler_testing::expect_defer(abody.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

// SEQUENCING
fn i32 defer_two_consecutive(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer { } defer break; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_defer(body.stmts.ptr[0], msg)) { return -3; }
    if(!compiler_testing::expect_defer(body.stmts.ptr[1], msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 defer_combined_with_var_and_return(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { i32 r = 0; defer { } return r; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 3, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "r"), false, false, msg)) { return -3; }
    if(!compiler_testing::expect_defer(body.stmts.ptr[1], msg)) { return -4; }
    if(!compiler_testing::expect_return(body.stmts.ptr[2], msg)) { return -5; }
    return 0;
}

// SRC POS
fn i32 defer_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    if(!testing::expect_eq(d.h.src_pos, 14, msg)) { return -3; }
    return 0;
}

// Synthetic block in single-stmt form must carry the inner stmt's src_pos.
fn i32 defer_single_synthetic_block_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer break; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    if(!testing::expect_eq(d.h.src_pos, 14, msg)) { return -3; }
    if(!testing::expect_eq(d.body.h.src_pos, 20, msg)) { return -4; }
    return 0;
}

// NEGATIVE
fn i32 defer_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)d), msg)) { return -3; }
    return 0;
}

fn i32 defer_semicolon_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer ; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)d), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got ';'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 20, msg)) { return -5; }
    return 0;
}

fn i32 defer_expr_stmt_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer 5; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -3; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)d), msg)) { return -4; }
    ast::BlockNode* blk = compiler_testing::expect_block(d.body, 1, msg);
    if(!blk) { return -5; }
    if(!testing::expect_eq((u16)blk.stmts.ptr[0].h.kind, (u16)ast::AstKind::ExprStmt, msg)) { return -6; }
    return 0;
}

fn i32 defer_block_body_error_propagates(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer { return 5 5; } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)d), msg)) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag(d.body), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got integer literal", msg)) { return -5; }
    return 0;
}

fn i32 defer_single_body_error_propagates(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer return 5 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)d), msg)) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag(d.body), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got integer literal", msg)) { return -5; }
    return 0;
}

fn i32 defer_in_switch_else(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { else { defer { } } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    ast::BlockNode* eb = compiler_testing::expect_block(s.else_block, 1, msg);
    if(!eb) { return -3; }
    if(!compiler_testing::expect_defer(eb.stmts.ptr[0], msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 defer_unclosed_block_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer {", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::DeferNode* d = compiler_testing::expect_defer(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!d) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)d), msg)) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag(d.body), msg)) { return -4; }
    if(!compiler_testing::expect_diag_substr(m, "expected '}'", msg)) { return -5; }
    return 0;
}

fn i32 defer_expr_stmt_then_var_decl(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { defer 5; i32 x = 5; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -3; }
    ast::DeferNode* d = compiler_testing::expect_defer(body.stmts.ptr[0], msg);
    if(!d) { return -4; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)d), msg)) { return -5; }
    ast::VarDeclNode* v = compiler_testing::expect_var(body.stmts.ptr[1], compiler_testing::sym(m, "x"), false, false, msg);
    if(!v) { return -6; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)v), msg)) { return -7; }
    return 0;
}

// ============================================================================
// SWITCH
// ============================================================================

// SHAPES
fn i32 switch_empty(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!compiler_testing::expect_ident(s.discriminant, compiler_testing::sym(m, "x"), msg)) { return -3; }
    if(!testing::expect_eq(s.arms.len, 0, msg)) { return -4; }
    if(!testing::expect_null((void*)s.else_block, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 switch_single_arm_single_label(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_eq(s.arms.len, 1, msg)) { return -3; }
    if(!testing::expect_eq(s.arms.ptr[0].labels.len, 1, msg)) { return -4; }
    if(!compiler_testing::expect_intlit(s.arms.ptr[0].labels.ptr[0], 1, msg)) { return -5; }
    if(!compiler_testing::expect_block(s.arms.ptr[0].body, 0, msg)) { return -6; }
    if(!testing::expect_null((void*)s.else_block, msg)) { return -7; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -8; }
    return 0;
}

// `case 1: case 2: { body }` — case 1 falls through to case 2's body, encoded
// as two arms where arm[0].body is null.
fn i32 switch_fallthrough_2_cases(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: case 2: { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_eq(s.arms.len, 2, msg)) { return -3; }
    if(!testing::expect_eq(s.arms.ptr[0].labels.len, 1, msg)) { return -4; }
    if(!compiler_testing::expect_intlit(s.arms.ptr[0].labels.ptr[0], 1, msg)) { return -5; }
    if(!testing::expect_null((void*)s.arms.ptr[0].body, msg)) { return -6; }
    if(!testing::expect_eq(s.arms.ptr[1].labels.len, 1, msg)) { return -7; }
    if(!compiler_testing::expect_intlit(s.arms.ptr[1].labels.ptr[0], 2, msg)) { return -8; }
    if(!compiler_testing::expect_block(s.arms.ptr[1].body, 0, msg)) { return -9; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -10; }
    return 0;
}

fn i32 switch_fallthrough_3_cases(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: case 2: case 3: { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_eq(s.arms.len, 3, msg)) { return -3; }
    if(!compiler_testing::expect_intlit(s.arms.ptr[0].labels.ptr[0], 1, msg)) { return -4; }
    if(!testing::expect_null((void*)s.arms.ptr[0].body, msg)) { return -5; }
    if(!compiler_testing::expect_intlit(s.arms.ptr[1].labels.ptr[0], 2, msg)) { return -6; }
    if(!testing::expect_null((void*)s.arms.ptr[1].body, msg)) { return -7; }
    if(!compiler_testing::expect_intlit(s.arms.ptr[2].labels.ptr[0], 3, msg)) { return -8; }
    if(!compiler_testing::expect_block(s.arms.ptr[2].body, 0, msg)) { return -9; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -10; }
    return 0;
}

fn i32 switch_multiple_arms(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: { } case 2: { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_eq(s.arms.len, 2, msg)) { return -3; }
    if(!testing::expect_eq(s.arms.ptr[0].labels.len, 1, msg)) { return -4; }
    if(!compiler_testing::expect_intlit(s.arms.ptr[0].labels.ptr[0], 1, msg)) { return -5; }
    if(!testing::expect_eq(s.arms.ptr[1].labels.len, 1, msg)) { return -6; }
    if(!compiler_testing::expect_intlit(s.arms.ptr[1].labels.ptr[0], 2, msg)) { return -7; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -8; }
    return 0;
}

fn i32 switch_else_only(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { else { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_eq(s.arms.len, 0, msg)) { return -3; }
    if(!compiler_testing::expect_block(s.else_block, 0, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 switch_arm_and_else(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: { } else { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_eq(s.arms.len, 1, msg)) { return -3; }
    if(!compiler_testing::expect_block(s.else_block, 0, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 switch_multi_arms_and_else(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: { } case 2: { } else { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_eq(s.arms.len, 2, msg)) { return -3; }
    if(!compiler_testing::expect_block(s.else_block, 0, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 switch_mixed_fallthrough_and_standalone(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: case 2: { } case 3: { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_eq(s.arms.len, 3, msg)) { return -3; }
    if(!compiler_testing::expect_intlit(s.arms.ptr[0].labels.ptr[0], 1, msg)) { return -4; }
    if(!testing::expect_null((void*)s.arms.ptr[0].body, msg)) { return -5; }
    if(!compiler_testing::expect_intlit(s.arms.ptr[1].labels.ptr[0], 2, msg)) { return -6; }
    if(!compiler_testing::expect_block(s.arms.ptr[1].body, 0, msg)) { return -7; }
    if(!compiler_testing::expect_intlit(s.arms.ptr[2].labels.ptr[0], 3, msg)) { return -8; }
    if(!compiler_testing::expect_block(s.arms.ptr[2].body, 0, msg)) { return -9; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -10; }
    return 0;
}

fn i32 switch_fallthrough_to_else(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: else { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -3; }
    if(!testing::expect_eq(s.arms.len, 1, msg)) { return -4; }
    if(!compiler_testing::expect_intlit(s.arms.ptr[0].labels.ptr[0], 1, msg)) { return -5; }
    if(!testing::expect_null((void*)s.arms.ptr[0].body, msg)) { return -6; }
    if(!compiler_testing::expect_block(s.else_block, 0, msg)) { return -7; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -8; }
    return 0;
}

fn i32 switch_two_cases_fallthrough_to_else(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: case 2: else { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -3; }
    if(!testing::expect_eq(s.arms.len, 2, msg)) { return -4; }
    if(!testing::expect_null((void*)s.arms.ptr[0].body, msg)) { return -5; }
    if(!testing::expect_null((void*)s.arms.ptr[1].body, msg)) { return -6; }
    if(!compiler_testing::expect_block(s.else_block, 0, msg)) { return -7; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -8; }
    return 0;
}

// Fallthrough between standalone arms: 1 has body, 2 falls through, 3 has body.
fn i32 switch_fallthrough_in_middle(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: { } case 2: case 3: { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_eq(s.arms.len, 3, msg)) { return -3; }
    if(!compiler_testing::expect_block(s.arms.ptr[0].body, 0, msg)) { return -4; }
    if(!testing::expect_null((void*)s.arms.ptr[1].body, msg)) { return -5; }
    if(!compiler_testing::expect_block(s.arms.ptr[2].body, 0, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

// DISCRIMINANT FORMS
fn i32 switch_disc_intlit(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (42) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!compiler_testing::expect_intlit(s.discriminant, 42, msg)) { return -3; }
    return 0;
}

fn i32 switch_disc_member_access(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (obj.field) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!compiler_testing::expect_member(s.discriminant, compiler_testing::sym(m, "field"), msg)) { return -3; }
    return 0;
}

fn i32 switch_disc_pratt(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (a + b * 2) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    ast::BinaryOpNode* plus = compiler_testing::expect_binop(s.discriminant, token::TokenKind::Plus, msg);
    if(!plus) { return -3; }
    if(!compiler_testing::expect_binop(plus.rhs, token::TokenKind::Star, msg)) { return -4; }
    return 0;
}

fn i32 switch_disc_call(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (foo(1)) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!compiler_testing::expect_call(s.discriminant, 1, msg)) { return -3; }
    return 0;
}

fn i32 switch_disc_namespace(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (mod::x) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!compiler_testing::expect_nsacc(s.discriminant, compiler_testing::sym(m, "mod"), compiler_testing::sym(m, "x"), msg)) { return -3; }
    return 0;
}

// LABEL FORMS
fn i32 switch_label_charlit(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 'a': { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!compiler_testing::expect_charlit(s.arms.ptr[0].labels.ptr[0], 97, msg)) { return -3; }
    return 0;
}

fn i32 switch_label_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case A: { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!compiler_testing::expect_ident(s.arms.ptr[0].labels.ptr[0], compiler_testing::sym(m, "A"), msg)) { return -3; }
    return 0;
}

fn i32 switch_label_namespace_access(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case E::A: { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!compiler_testing::expect_nsacc(s.arms.ptr[0].labels.ptr[0], compiler_testing::sym(m, "E"), compiler_testing::sym(m, "A"), msg)) { return -3; }
    return 0;
}

fn i32 switch_label_namespace_access_three_levels(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case mod::Color::Red: { } } }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -3; }
    if(!compiler_testing::expect_nsacc3(s.arms.ptr[0].labels.ptr[0],
            compiler_testing::sym(m, "mod"),
            compiler_testing::sym(m, "Color"),
            compiler_testing::sym(m, "Red"), msg)) { return -4; }
    return 0;
}

fn i32 switch_disc_namespace_three_levels(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (mod::E::V) { } }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -3; }
    if(!compiler_testing::expect_nsacc3(s.discriminant,
            compiler_testing::sym(m, "mod"),
            compiler_testing::sym(m, "E"),
            compiler_testing::sym(m, "V"), msg)) { return -4; }
    return 0;
}

fn i32 switch_label_negative(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case -1: { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    ast::UnaryOpNode* u = compiler_testing::expect_unop(s.arms.ptr[0].labels.ptr[0], token::TokenKind::Minus, msg);
    if(!u) { return -3; }
    if(!compiler_testing::expect_intlit(u.operand, 1, msg)) { return -4; }
    return 0;
}

fn i32 switch_label_pratt(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case a + b: { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!compiler_testing::expect_binop(s.arms.ptr[0].labels.ptr[0], token::TokenKind::Plus, msg)) { return -3; }
    return 0;
}

// BODY CONTENT
fn i32 switch_body_multi_stmts(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { switch (x) { case 1: { i32 y = 5; return y; } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(s.arms.ptr[0].body, 2, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "y"), false, false, msg)) { return -4; }
    if(!compiler_testing::expect_return(body.stmts.ptr[1], msg)) { return -5; }
    return 0;
}

fn i32 switch_body_with_break(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: { break; } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(s.arms.ptr[0].body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_break(body.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 switch_body_with_continue(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: { continue; } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(s.arms.ptr[0].body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_continue(body.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 switch_body_with_if(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: { if (y) { } } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(s.arms.ptr[0].body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_if(body.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 switch_body_with_while(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: { while (y) { } } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(s.arms.ptr[0].body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_while(body.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 switch_body_with_for(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: { for (;;) { } } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    ast::BlockNode* body = compiler_testing::expect_block(s.arms.ptr[0].body, 1, msg);
    if(!body) { return -3; }
    if(!compiler_testing::expect_for(body.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 switch_body_with_nested_switch(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: { switch (y) { case 2: { } } } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* outer = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!outer) { return -2; }
    ast::BlockNode* outer_body = compiler_testing::expect_block(outer.arms.ptr[0].body, 1, msg);
    if(!outer_body) { return -3; }
    ast::SwitchNode* inner = compiler_testing::expect_switch(outer_body.stmts.ptr[0], msg);
    if(!inner) { return -4; }
    if(!compiler_testing::expect_ident(inner.discriminant, compiler_testing::sym(m, "y"), msg)) { return -5; }
    return 0;
}

// ELSE BLOCK
fn i32 switch_else_body_multi_stmts(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { switch (x) { else { i32 y = 5; return y; } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    ast::BlockNode* eb = compiler_testing::expect_block(s.else_block, 2, msg);
    if(!eb) { return -3; }
    if(!compiler_testing::expect_var(eb.stmts.ptr[0], compiler_testing::sym(m, "y"), false, false, msg)) { return -4; }
    if(!compiler_testing::expect_return(eb.stmts.ptr[1], msg)) { return -5; }
    return 0;
}

fn i32 switch_else_with_nested_switch(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { else { switch (y) { } } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* outer = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!outer) { return -2; }
    ast::BlockNode* eb = compiler_testing::expect_block(outer.else_block, 1, msg);
    if(!eb) { return -3; }
    if(!compiler_testing::expect_switch(eb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

// NESTING / SEQUENCING
fn i32 switch_inside_if(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (a) { switch (x) { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* ifn = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ifn) { return -2; }
    ast::BlockNode* tb = compiler_testing::expect_block(ifn.then_block, 1, msg);
    if(!tb) { return -3; }
    if(!compiler_testing::expect_switch(tb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 switch_inside_while(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { while (a) { switch (x) { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::WhileNode* w = compiler_testing::expect_while(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!w) { return -2; }
    ast::BlockNode* wb = compiler_testing::expect_block(w.body, 1, msg);
    if(!wb) { return -3; }
    if(!compiler_testing::expect_switch(wb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 switch_inside_for(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { for (;;) { switch (x) { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::ForNode* fr = compiler_testing::expect_for(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!fr) { return -2; }
    ast::BlockNode* fb = compiler_testing::expect_block(fr.body, 1, msg);
    if(!fb) { return -3; }
    if(!compiler_testing::expect_switch(fb.stmts.ptr[0], msg)) { return -4; }
    return 0;
}

fn i32 switch_two_consecutive(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { } switch (y) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_switch(body.stmts.ptr[0], msg)) { return -3; }
    if(!compiler_testing::expect_switch(body.stmts.ptr[1], msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 switch_combined_with_var_and_return(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32 f() { i32 r = 0; switch (x) { } return r; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 3, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_var(body.stmts.ptr[0], compiler_testing::sym(m, "r"), false, false, msg)) { return -3; }
    if(!compiler_testing::expect_switch(body.stmts.ptr[1], msg)) { return -4; }
    if(!compiler_testing::expect_return(body.stmts.ptr[2], msg)) { return -5; }
    return 0;
}

// SRC POS
fn i32 switch_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_eq(s.h.src_pos, 14, msg)) { return -3; }
    return 0;
}

fn i32 switch_disc_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_eq(s.discriminant.h.src_pos, 22, msg)) { return -3; }
    return 0;
}

fn i32 switch_arm_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_eq(s.arms.ptr[0].src_pos, 32, msg)) { return -3; }
    return 0;
}

// Each arm's src_pos points at its own label, not the position of any earlier
// fallthrough label.
fn i32 switch_fallthrough_arm_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: case 2: { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_eq(s.arms.ptr[0].src_pos, 32, msg)) { return -3; }
    if(!testing::expect_eq(s.arms.ptr[1].src_pos, 40, msg)) { return -4; }
    return 0;
}

// NEGATIVE
fn i32 switch_missing_lparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch x) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '(', got identifier", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 21, msg)) { return -5; }
    return 0;
}

fn i32 switch_missing_rparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ')', got '{'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 24, msg)) { return -5; }
    return 0;
}

fn i32 switch_missing_lbrace(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '{', got '}'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 25, msg)) { return -5; }
    return 0;
}

fn i32 switch_missing_rbrace_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) {", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -3; }
    if(!compiler_testing::expect_diag_substr(m, "expected '}'", msg)) { return -4; }
    return 0;
}

fn i32 switch_missing_colon(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1 { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ':', got '{'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 34, msg)) { return -5; }
    return 0;
}

fn i32 switch_missing_label_expr(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case : { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ':'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 32, msg)) { return -5; }
    return 0;
}

// `case 1:` with no body before `}` is a dangling fallthrough — parser accepts
// it without diagnostic (sema's job to flag fallthrough with no successor).
fn i32 switch_dangling_fallthrough_at_close(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -3; }
    if(!testing::expect_eq(s.arms.len, 1, msg)) { return -4; }
    if(!compiler_testing::expect_intlit(s.arms.ptr[0].labels.ptr[0], 1, msg)) { return -5; }
    if(!testing::expect_null((void*)s.arms.ptr[0].body, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 switch_junk_token_in_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { foo; case 1: { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected 'case', got identifier", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 27, msg)) { return -5; }
    // After recovery, the `case 1: { }` arm must still parse.
    if(!testing::expect_eq(s.arms.len, 1, msg)) { return -6; }
    if(!compiler_testing::expect_intlit(s.arms.ptr[0].labels.ptr[0], 1, msg)) { return -7; }
    return 0;
}

fn i32 switch_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -3; }
    if(!compiler_testing::expect_diag_substr(m, "expected '('", msg)) { return -4; }
    return 0;
}

fn i32 switch_recovery_continues(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { } i32 y = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    if(!compiler_testing::expect_switch(body.stmts.ptr[0], msg)) { return -3; }
    ast::VarDeclNode* v = compiler_testing::expect_var(body.stmts.ptr[1], compiler_testing::sym(m, "y"), false, false, msg);
    if(!v) { return -4; }
    if(!compiler_testing::expect_intlit(v.init, 5, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 switch_malformed_disc(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (5 +) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ')'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 25, msg)) { return -5; }
    return 0;
}

// Second `else` is rejected with a diagnostic; the FIRST else's body is kept.
fn i32 switch_double_else_first_wins(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { else { i32 a = 1; } else { i32 z = 5; } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -3; }
    ast::BlockNode* eb = compiler_testing::expect_block(s.else_block, 1, msg);
    if(!eb) { return -4; }
    if(!compiler_testing::expect_var(eb.stmts.ptr[0], compiler_testing::sym(m, "a"), false, false, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "duplicate 'else' in switch", msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 47, msg)) { return -7; }
    return 0;
}

fn i32 switch_else_before_case(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { else { } case 1: { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_eq(s.arms.len, 1, msg)) { return -3; }
    if(!testing::expect_not_null((void*)s.else_block, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

// GAP FILL

fn i32 switch_case_body_error_propagates(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: { return 5 5; } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag(s.arms.ptr[0].body), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got integer literal", msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 46, msg)) { return -6; }
    return 0;
}

fn i32 switch_else_body_error_propagates(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { else { return 5 5; } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag(s.else_block), msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected ';', got integer literal", msg)) { return -5; }
    return 0;
}

// 6 arms exercises the realloc-grow path (arms_cap starts at 4).
fn i32 switch_arms_growth_past_initial_cap(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: { } case 2: { } case 3: { } case 4: { } case 5: { } case 6: { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_eq(s.arms.len, 6, msg)) { return -3; }
    if(!compiler_testing::expect_intlit(s.arms.ptr[0].labels.ptr[0], 1, msg)) { return -4; }
    if(!compiler_testing::expect_intlit(s.arms.ptr[5].labels.ptr[0], 6, msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

fn i32 switch_multi_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (5 +) { case 1 { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -3; }
    if(!testing::expect_true(m.diag.entries.len >= 2, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ')'", msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 25, msg)) { return -6; }
    return 0;
}

fn i32 switch_label_bool_literal(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case true: { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!compiler_testing::expect_boollit(s.arms.ptr[0].labels.ptr[0], true, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

// `;` between cases is illegal. Parser hits the else-branch on `;` and recovers
// to the next `case`. Pins the diagnostic so the behavior is locked.
fn i32 switch_semicolon_between_cases(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: ; case 2: { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -3; }
    if(!testing::expect_eq(s.arms.len, 2, msg)) { return -4; }
    if(!compiler_testing::expect_intlit(s.arms.ptr[0].labels.ptr[0], 1, msg)) { return -5; }
    if(!compiler_testing::expect_intlit(s.arms.ptr[1].labels.ptr[0], 2, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected 'case', got ';'", msg)) { return -7; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, 35, msg)) { return -8; }
    return 0;
}

fn i32 switch_inside_else_branch(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { if (a) { } else { switch (x) { } } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::IfNode* ifn = compiler_testing::expect_if(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!ifn) { return -2; }
    ast::BlockNode* eb = compiler_testing::expect_block(ifn.else_block, 1, msg);
    if(!eb) { return -3; }
    if(!compiler_testing::expect_switch(eb.stmts.ptr[0], msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 switch_disc_cast(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch ((bool)x) { } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    ast::CastNode* c = compiler_testing::expect_cast(s.discriminant, msg);
    if(!c) { return -3; }
    if(!compiler_testing::expect_ty_prim(c.target_type, token::TokenKind::BOOL, msg)) { return -4; }
    if(!compiler_testing::expect_ident(c.expr, compiler_testing::sym(m, "x"), msg)) { return -5; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -6; }
    return 0;
}

// All arms fall through with no terminating body — sema flags, parser accepts.
fn i32 switch_pure_fallthrough_no_terminator(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (x) { case 1: case 2: case 3: } }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::SwitchNode* s = compiler_testing::expect_switch(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!s) { return -2; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -3; }
    if(!testing::expect_eq(s.arms.len, 3, msg)) { return -4; }
    if(!testing::expect_null((void*)s.arms.ptr[0].body, msg)) { return -5; }
    if(!testing::expect_null((void*)s.arms.ptr[1].body, msg)) { return -6; }
    if(!testing::expect_null((void*)s.arms.ptr[2].body, msg)) { return -7; }
    if(!testing::expect_null((void*)s.else_block, msg)) { return -8; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -9; }
    return 0;
}

fn i32 switch_recovery_after_error(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { switch (5 +) { } i32 y = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    ast::BlockNode* body = compiler_testing::expect_block(f.body, 2, msg);
    if(!body) { return -2; }
    ast::SwitchNode* s = compiler_testing::expect_switch(body.stmts.ptr[0], msg);
    if(!s) { return -3; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)s), msg)) { return -4; }
    ast::VarDeclNode* v = compiler_testing::expect_var(body.stmts.ptr[1], compiler_testing::sym(m, "y"), false, false, msg);
    if(!v) { return -5; }
    if(!testing::expect_false(compiler_testing::has_error_flag((ast::AstNode*)v), msg)) { return -6; }
    if(!compiler_testing::expect_intlit(v.init, 5, msg)) { return -7; }
    return 0;
}

// ============================================================================
// EXPRESSIONS: PRIMARY / LITERALS
// ============================================================================

fn i32 expr_int_literal(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = 42;", &m);
    if(!(compiler_testing::expect_intlit(compiler_testing::var_init(root, 0), 42, msg))) { return -1; } return 0;
}

fn i32 expr_int_literal_zero(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = 0;", &m);
    if(!(compiler_testing::expect_intlit(compiler_testing::var_init(root, 0), 0, msg))) { return -1; } return 0;
}

fn i32 expr_float_literal(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "f64 x = 3.5;", &m);
    if(!(compiler_testing::expect_floatlit(compiler_testing::var_init(root, 0), 3.5, msg))) { return -1; } return 0;
}

fn i32 expr_char_literal(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "u8 c = 'a';", &m);
    if(!(compiler_testing::expect_charlit(compiler_testing::var_init(root, 0), 'a', msg))) { return -1; } return 0;
}

fn i32 expr_string_literal(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "u8[] s = \"hi\";", &m);
    if(!(compiler_testing::expect_strlit(compiler_testing::var_init(root, 0), 0, 2, msg))) { return -1; } return 0;
}

fn i32 expr_bool_true(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "bool x = true;", &m);
    if(!(compiler_testing::expect_boollit(compiler_testing::var_init(root, 0), true, msg))) { return -1; } return 0;
}

fn i32 expr_bool_false(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "bool x = false;", &m);
    if(!(compiler_testing::expect_boollit(compiler_testing::var_init(root, 0), false, msg))) { return -1; } return 0;
}

fn i32 expr_null(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32* p = null;", &m);
    if(!(compiler_testing::expect_nulllit(compiler_testing::var_init(root, 0), msg))) { return -1; } return 0;
}

fn i32 expr_ident(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = y;", &m);
    if(!(compiler_testing::expect_ident(compiler_testing::var_init(root, 0), compiler_testing::sym(m, "y"), msg))) { return -1; } return 0;
}

fn i32 expr_namespace_access(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = mod::y;", &m);
    if(!(compiler_testing::expect_nsacc(compiler_testing::var_init(root, 0), compiler_testing::sym(m, "mod"), compiler_testing::sym(m, "y"), msg))) { return -1; } return 0;
}

fn i32 expr_namespace_three_levels_in_call_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = f(mod::E::V);", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::CallNode* c = compiler_testing::expect_call(compiler_testing::var_init(root, 0), 1, msg);
    if(!c) { return -2; }
    if(!compiler_testing::expect_nsacc3(c.args.ptr[0],
            compiler_testing::sym(m, "mod"),
            compiler_testing::sym(m, "E"),
            compiler_testing::sym(m, "V"), msg)) { return -3; }
    return 0;
}

fn i32 expr_namespace_three_levels_in_struct_lit(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "Foo x = { .field = mod::E::V };", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::StructLitNode* sl = compiler_testing::expect_struct_lit(compiler_testing::var_init(root, 0), 1, msg);
    if(!sl) { return -2; }
    if(!compiler_testing::expect_field_init(&sl.inits[0], compiler_testing::sym(m, "field"), msg)) { return -3; }
    if(!compiler_testing::expect_nsacc3(sl.inits[0].value,
            compiler_testing::sym(m, "mod"),
            compiler_testing::sym(m, "E"),
            compiler_testing::sym(m, "V"), msg)) { return -4; }
    return 0;
}

fn i32 expr_namespace_three_levels_in_binop(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = mod::E::A + mod::E::B;", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::BinaryOpNode* b = compiler_testing::expect_binop(compiler_testing::var_init(root, 0), token::TokenKind::Plus, msg);
    if(!b) { return -2; }
    if(!compiler_testing::expect_nsacc3(b.lhs,
            compiler_testing::sym(m, "mod"),
            compiler_testing::sym(m, "E"),
            compiler_testing::sym(m, "A"), msg)) { return -3; }
    if(!compiler_testing::expect_nsacc3(b.rhs,
            compiler_testing::sym(m, "mod"),
            compiler_testing::sym(m, "E"),
            compiler_testing::sym(m, "B"), msg)) { return -4; }
    return 0;
}

fn i32 expr_namespace_three_levels_then_member_access(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = mod::Foo::Bar.field;", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::MemberAccessNode* ma = compiler_testing::expect_member(compiler_testing::var_init(root, 0), compiler_testing::sym(m, "field"), msg);
    if(!ma) { return -2; }
    if(!compiler_testing::expect_nsacc3(ma.base,
            compiler_testing::sym(m, "mod"),
            compiler_testing::sym(m, "Foo"),
            compiler_testing::sym(m, "Bar"), msg)) { return -3; }
    return 0;
}

// ============================================================================
// EXPRESSIONS: PRATT PRECEDENCE / ASSOCIATIVITY
// ============================================================================

// 1 + 2  =>  Plus(1, 2)
fn i32 expr_add(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = 1 + 2;", &m);
    ast::BinaryOpNode* b = compiler_testing::expect_binop(compiler_testing::var_init(root, 0), token::TokenKind::Plus, msg);
    if(!b) { return -1; }
    if(!compiler_testing::expect_intlit(b.lhs, 1, msg)) { return -2; }
    if(!(compiler_testing::expect_intlit(b.rhs, 2, msg))) { return -3; } return 0;
}

// 1 + 2 * 3  =>  Plus(1, Star(2, 3))
fn i32 expr_precedence_plus_mul(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = 1 + 2 * 3;", &m);
    ast::BinaryOpNode* top = compiler_testing::expect_binop(compiler_testing::var_init(root, 0), token::TokenKind::Plus, msg);
    if(!top) { return -1; }
    if(!compiler_testing::expect_intlit(top.lhs, 1, msg)) { return -2; }
    ast::BinaryOpNode* rhs = compiler_testing::expect_binop(top.rhs, token::TokenKind::Star, msg);
    if(!rhs) { return -3; }
    if(!compiler_testing::expect_intlit(rhs.lhs, 2, msg)) { return -4; }
    if(!(compiler_testing::expect_intlit(rhs.rhs, 3, msg))) { return -5; } return 0;
}

// 1 * 2 + 3  =>  Plus(Star(1, 2), 3)
fn i32 expr_precedence_mul_plus(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = 1 * 2 + 3;", &m);
    ast::BinaryOpNode* top = compiler_testing::expect_binop(compiler_testing::var_init(root, 0), token::TokenKind::Plus, msg);
    if(!top) { return -1; }
    ast::BinaryOpNode* lhs = compiler_testing::expect_binop(top.lhs, token::TokenKind::Star, msg);
    if(!lhs) { return -2; }
    if(!compiler_testing::expect_intlit(lhs.lhs, 1, msg)) { return -3; }
    if(!compiler_testing::expect_intlit(lhs.rhs, 2, msg)) { return -4; }
    if(!(compiler_testing::expect_intlit(top.rhs, 3, msg))) { return -5; } return 0;
}

// 1 - 2 - 3  =>  Minus(Minus(1, 2), 3)   (left-assoc)
fn i32 expr_left_associativity(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = 1 - 2 - 3;", &m);
    ast::BinaryOpNode* top = compiler_testing::expect_binop(compiler_testing::var_init(root, 0), token::TokenKind::Minus, msg);
    if(!top) { return -1; }
    ast::BinaryOpNode* lhs = compiler_testing::expect_binop(top.lhs, token::TokenKind::Minus, msg);
    if(!lhs) { return -2; }
    if(!compiler_testing::expect_intlit(lhs.lhs, 1, msg)) { return -3; }
    if(!compiler_testing::expect_intlit(lhs.rhs, 2, msg)) { return -4; }
    if(!(compiler_testing::expect_intlit(top.rhs, 3, msg))) { return -5; } return 0;
}

// a == b && c == d  =>  AmpAmp(EqEq(a,b), EqEq(c,d))
fn i32 expr_eq_and_chain(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "bool x = a == b && c == d;", &m);
    ast::BinaryOpNode* top = compiler_testing::expect_binop(compiler_testing::var_init(root, 0), token::TokenKind::AmpAmp, msg);
    if(!top) { return -1; }
    ast::BinaryOpNode* lhs = compiler_testing::expect_binop(top.lhs, token::TokenKind::EqEq, msg);
    if(!lhs) { return -2; }
    ast::BinaryOpNode* rhs = compiler_testing::expect_binop(top.rhs, token::TokenKind::EqEq, msg);
    if(!rhs) { return -3; }
    if(!compiler_testing::expect_ident(lhs.lhs, compiler_testing::sym(m, "a"), msg)) { return -4; }
    if(!compiler_testing::expect_ident(lhs.rhs, compiler_testing::sym(m, "b"), msg)) { return -5; }
    if(!compiler_testing::expect_ident(rhs.lhs, compiler_testing::sym(m, "c"), msg)) { return -6; }
    if(!(compiler_testing::expect_ident(rhs.rhs, compiler_testing::sym(m, "d"), msg))) { return -7; } return 0;
}

// a | b & c  =>  Pipe(a, Amp(b, c))   (& tighter than |)
fn i32 expr_pipe_amp_precedence(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = a | b & c;", &m);
    ast::BinaryOpNode* top = compiler_testing::expect_binop(compiler_testing::var_init(root, 0), token::TokenKind::Pipe, msg);
    if(!top) { return -1; }
    if(!compiler_testing::expect_ident(top.lhs, compiler_testing::sym(m, "a"), msg)) { return -2; }
    ast::BinaryOpNode* rhs = compiler_testing::expect_binop(top.rhs, token::TokenKind::Amp, msg);
    if(!rhs) { return -3; }
    if(!compiler_testing::expect_ident(rhs.lhs, compiler_testing::sym(m, "b"), msg)) { return -4; }
    if(!(compiler_testing::expect_ident(rhs.rhs, compiler_testing::sym(m, "c"), msg))) { return -5; } return 0;
}

// a < b << c  =>  LT(a, LShift(b, c))
fn i32 expr_shift_lower_than_compare(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "bool x = a < b << c;", &m);
    ast::BinaryOpNode* top = compiler_testing::expect_binop(compiler_testing::var_init(root, 0), token::TokenKind::LT, msg);
    if(!top) { return -1; }
    if(!compiler_testing::expect_ident(top.lhs, compiler_testing::sym(m, "a"), msg)) { return -2; }
    ast::BinaryOpNode* rhs = compiler_testing::expect_binop(top.rhs, token::TokenKind::LShift, msg);
    if(!rhs) { return -3; }
    if(!compiler_testing::expect_ident(rhs.lhs, compiler_testing::sym(m, "b"), msg)) { return -4; }
    if(!(compiler_testing::expect_ident(rhs.rhs, compiler_testing::sym(m, "c"), msg))) { return -5; } return 0;
}

// All operators reach Pratt: || && | ^ & == != < <= > >= << >> + - * / %
fn i32 expr_ladder_all_ops(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    // a || b && c | d ^ e & f == g != h < i <= j > k >= l << m >> n + o - p * q / r % s
    // Top should be ||; deepest right-spine should bottom out at a Percent.
    ast::AstNode* root = compiler_testing::parse_src(&local,
        "bool x = a || b && c | d ^ e & f == g != h < i <= j > k >= l << m >> n + o - p * q / r % s;", &m);
    ast::BinaryOpNode* top = compiler_testing::expect_binop(compiler_testing::var_init(root, 0), token::TokenKind::PipePipe, msg);
    if(!top) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -2; }
    return 0;
}

// ============================================================================
// EXPRESSIONS: UNARY
// ============================================================================

fn i32 expr_unary_minus(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = -y;", &m);
    ast::UnaryOpNode* u = compiler_testing::expect_unop(compiler_testing::var_init(root, 0), token::TokenKind::Minus, msg);
    if(!u) { return -1; }
    if(!(compiler_testing::expect_ident(u.operand, compiler_testing::sym(m, "y"), msg))) { return -2; } return 0;
}

fn i32 expr_unary_bang(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "bool x = !y;", &m);
    ast::UnaryOpNode* u = compiler_testing::expect_unop(compiler_testing::var_init(root, 0), token::TokenKind::Bang, msg);
    if(!u) { return -1; }
    if(!(compiler_testing::expect_ident(u.operand, compiler_testing::sym(m, "y"), msg))) { return -2; } return 0;
}

fn i32 expr_unary_tilde(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = ~y;", &m);
    ast::UnaryOpNode* u = compiler_testing::expect_unop(compiler_testing::var_init(root, 0), token::TokenKind::Tilde, msg);
    if(!u) { return -1; }
    if(!(compiler_testing::expect_ident(u.operand, compiler_testing::sym(m, "y"), msg))) { return -2; } return 0;
}

fn i32 expr_unary_addrof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32* p = &x;", &m);
    ast::UnaryOpNode* u = compiler_testing::expect_unop(compiler_testing::var_init(root, 0), token::TokenKind::Amp, msg);
    if(!u) { return -1; }
    if(!(compiler_testing::expect_ident(u.operand, compiler_testing::sym(m, "x"), msg))) { return -2; } return 0;
}

fn i32 expr_unary_deref(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = *p;", &m);
    ast::UnaryOpNode* u = compiler_testing::expect_unop(compiler_testing::var_init(root, 0), token::TokenKind::Star, msg);
    if(!u) { return -1; }
    if(!(compiler_testing::expect_ident(u.operand, compiler_testing::sym(m, "p"), msg))) { return -2; } return 0;
}

// !-y  =>  Bang(Minus(y))
fn i32 expr_unary_stacked(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "bool x = !-y;", &m);
    ast::UnaryOpNode* outer = compiler_testing::expect_unop(compiler_testing::var_init(root, 0), token::TokenKind::Bang, msg);
    if(!outer) { return -1; }
    ast::UnaryOpNode* inner = compiler_testing::expect_unop(outer.operand, token::TokenKind::Minus, msg);
    if(!inner) { return -2; }
    if(!(compiler_testing::expect_ident(inner.operand, compiler_testing::sym(m, "y"), msg))) { return -3; } return 0;
}

// **p  =>  Star(Star(p))
fn i32 expr_unary_double_deref(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = **p;", &m);
    ast::UnaryOpNode* outer = compiler_testing::expect_unop(compiler_testing::var_init(root, 0), token::TokenKind::Star, msg);
    if(!outer) { return -1; }
    ast::UnaryOpNode* inner = compiler_testing::expect_unop(outer.operand, token::TokenKind::Star, msg);
    if(!inner) { return -2; }
    if(!(compiler_testing::expect_ident(inner.operand, compiler_testing::sym(m, "p"), msg))) { return -3; } return 0;
}

// -1 + 2  =>  Plus(Minus(1), 2)
fn i32 expr_unary_binds_tighter_than_binary(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = -1 + 2;", &m);
    ast::BinaryOpNode* top = compiler_testing::expect_binop(compiler_testing::var_init(root, 0), token::TokenKind::Plus, msg);
    if(!top) { return -1; }
    ast::UnaryOpNode* lhs = compiler_testing::expect_unop(top.lhs, token::TokenKind::Minus, msg);
    if(!lhs) { return -2; }
    if(!compiler_testing::expect_intlit(lhs.operand, 1, msg)) { return -3; }
    if(!(compiler_testing::expect_intlit(top.rhs, 2, msg))) { return -4; } return 0;
}

// ============================================================================
// EXPRESSIONS: POSTFIX
// ============================================================================

fn i32 expr_call_no_args(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = f();", &m);
    ast::CallNode* c = compiler_testing::expect_call(compiler_testing::var_init(root, 0), 0, msg);
    if(!c) { return -1; }
    if(!(compiler_testing::expect_ident(c.callee, compiler_testing::sym(m, "f"), msg))) { return -2; } return 0;
}

fn i32 expr_call_with_args(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = f(1, 2, 3);", &m);
    ast::CallNode* c = compiler_testing::expect_call(compiler_testing::var_init(root, 0), 3, msg);
    if(!c) { return -1; }
    if(!compiler_testing::expect_ident(c.callee, compiler_testing::sym(m, "f"), msg)) { return -2; }
    if(!compiler_testing::expect_intlit(c.args.ptr[0], 1, msg)) { return -3; }
    if(!compiler_testing::expect_intlit(c.args.ptr[1], 2, msg)) { return -4; }
    if(!(compiler_testing::expect_intlit(c.args.ptr[2], 3, msg))) { return -5; } return 0;
}

fn i32 expr_call_nested(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    // f(g(1), 2)  =>  Call(f, [Call(g, [1]), 2])
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = f(g(1), 2);", &m);
    ast::CallNode* outer = compiler_testing::expect_call(compiler_testing::var_init(root, 0), 2, msg);
    if(!outer) { return -1; }
    ast::CallNode* inner = compiler_testing::expect_call(outer.args.ptr[0], 1, msg);
    if(!inner) { return -2; }
    if(!compiler_testing::expect_ident(inner.callee, compiler_testing::sym(m, "g"), msg)) { return -3; }
    if(!compiler_testing::expect_intlit(inner.args.ptr[0], 1, msg)) { return -4; }
    if(!(compiler_testing::expect_intlit(outer.args.ptr[1], 2, msg))) { return -5; } return 0;
}

fn i32 expr_array_index(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = a[0];", &m);
    ast::ArrayIndexNode* ai = compiler_testing::expect_index(compiler_testing::var_init(root, 0), msg);
    if(!ai) { return -1; }
    if(!compiler_testing::expect_ident(ai.base, compiler_testing::sym(m, "a"), msg)) { return -2; }
    if(!(compiler_testing::expect_intlit(ai.index, 0, msg))) { return -3; } return 0;
}

fn i32 expr_slice_range(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32[] x = a[1..3];", &m);
    ast::SliceRangeNode* sr = compiler_testing::expect_slice_range(compiler_testing::var_init(root, 0), msg);
    if(!sr) { return -1; }
    if(!compiler_testing::expect_ident(sr.base, compiler_testing::sym(m, "a"), msg)) { return -2; }
    if(!compiler_testing::expect_intlit(sr.lo, 1, msg)) { return -3; }
    if(!(compiler_testing::expect_intlit(sr.hi, 3, msg))) { return -4; } return 0;
}

fn i32 expr_slice_range_lo_only(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32[] x = a[2..];", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::SliceRangeNode* sr = compiler_testing::expect_slice_range(compiler_testing::var_init(root, 0), msg);
    if(!sr) { return -2; }
    if(!compiler_testing::expect_ident(sr.base, compiler_testing::sym(m, "a"), msg)) { return -3; }
    if(!compiler_testing::expect_intlit(sr.lo, 2, msg)) { return -4; }
    if(!testing::expect_eq((void*)sr.hi, null, msg)) { return -5; }
    return 0;
}

fn i32 expr_slice_range_hi_only(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32[] x = a[..5];", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::SliceRangeNode* sr = compiler_testing::expect_slice_range(compiler_testing::var_init(root, 0), msg);
    if(!sr) { return -2; }
    if(!compiler_testing::expect_ident(sr.base, compiler_testing::sym(m, "a"), msg)) { return -3; }
    if(!testing::expect_eq((void*)sr.lo, null, msg)) { return -4; }
    if(!compiler_testing::expect_intlit(sr.hi, 5, msg)) { return -5; }
    return 0;
}

fn i32 expr_slice_range_both_missing_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32[] x = a[..];", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "slice range `[..]` must have at least one bound; use `[lo..hi]`, `[lo..]`, or `[..hi]`", msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)12, msg)) { return -3; }
    ast::SliceRangeNode* sr = compiler_testing::expect_slice_range(compiler_testing::var_init(root, 0), msg);
    if(!sr) { return -4; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)sr), msg)) { return -5; }
    if(!testing::expect_eq((void*)sr.lo, null, msg)) { return -6; }
    if(!testing::expect_eq((void*)sr.hi, null, msg)) { return -7; }
    return 0;
}

fn i32 expr_slice_range_complex_bounds(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32[] x = a[i + 1..n - 1];", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::SliceRangeNode* sr = compiler_testing::expect_slice_range(compiler_testing::var_init(root, 0), msg);
    if(!sr) { return -2; }
    ast::BinaryOpNode* lo = compiler_testing::expect_binop(sr.lo, token::TokenKind::Plus, msg);
    if(!lo) { return -3; }
    ast::BinaryOpNode* hi = compiler_testing::expect_binop(sr.hi, token::TokenKind::Minus, msg);
    if(!hi) { return -4; }
    return 0;
}

fn i32 expr_slice_range_hi_only_then_member_access(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "u64 x = a[..n].len;", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::MemberAccessNode* ma = compiler_testing::expect_member(compiler_testing::var_init(root, 0), compiler_testing::sym(m, "len"), msg);
    if(!ma) { return -2; }
    ast::SliceRangeNode* sr = compiler_testing::expect_slice_range(ma.base, msg);
    if(!sr) { return -3; }
    if(!testing::expect_eq((void*)sr.lo, null, msg)) { return -4; }
    if(!compiler_testing::expect_ident(sr.hi, compiler_testing::sym(m, "n"), msg)) { return -5; }
    return 0;
}

fn i32 expr_slice_range_lo_only_after_call(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32[] x = f()[2..];", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::SliceRangeNode* sr = compiler_testing::expect_slice_range(compiler_testing::var_init(root, 0), msg);
    if(!sr) { return -2; }
    ast::CallNode* c = compiler_testing::expect_call(sr.base, 0, msg);
    if(!c) { return -3; }
    if(!compiler_testing::expect_intlit(sr.lo, 2, msg)) { return -4; }
    if(!testing::expect_eq((void*)sr.hi, null, msg)) { return -5; }
    return 0;
}

fn i32 expr_slice_range_hi_only_in_call_arg(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = g(a[..n]);", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::CallNode* c = compiler_testing::expect_call(compiler_testing::var_init(root, 0), 1, msg);
    if(!c) { return -2; }
    ast::SliceRangeNode* sr = compiler_testing::expect_slice_range(c.args.ptr[0], msg);
    if(!sr) { return -3; }
    if(!testing::expect_eq((void*)sr.lo, null, msg)) { return -4; }
    if(!compiler_testing::expect_ident(sr.hi, compiler_testing::sym(m, "n"), msg)) { return -5; }
    return 0;
}

fn i32 return_slice_range_lo_only(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32[] f() { return arr[3..]; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -3; }
    ast::SliceRangeNode* sr = compiler_testing::expect_slice_range(r.expr, msg);
    if(!sr) { return -4; }
    if(!compiler_testing::expect_intlit(sr.lo, 3, msg)) { return -5; }
    if(!testing::expect_eq((void*)sr.hi, null, msg)) { return -6; }
    return 0;
}

fn i32 return_slice_range_hi_only(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn i32[] f() { return arr[..4]; }", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -2; }
    ast::ReturnNode* r = compiler_testing::expect_return(compiler_testing::nth_stmt(f.body, 0), msg);
    if(!r) { return -3; }
    ast::SliceRangeNode* sr = compiler_testing::expect_slice_range(r.expr, msg);
    if(!sr) { return -4; }
    if(!testing::expect_eq((void*)sr.lo, null, msg)) { return -5; }
    if(!compiler_testing::expect_intlit(sr.hi, 4, msg)) { return -6; }
    return 0;
}

fn i32 expr_slice_range_lo_only_identifier(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32[] x = a[start..];", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::SliceRangeNode* sr = compiler_testing::expect_slice_range(compiler_testing::var_init(root, 0), msg);
    if(!sr) { return -2; }
    if(!compiler_testing::expect_ident(sr.lo, compiler_testing::sym(m, "start"), msg)) { return -3; }
    if(!testing::expect_eq((void*)sr.hi, null, msg)) { return -4; }
    return 0;
}

fn i32 expr_slice_range_chained(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32[] x = a[..n][m..];", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::SliceRangeNode* outer = compiler_testing::expect_slice_range(compiler_testing::var_init(root, 0), msg);
    if(!outer) { return -2; }
    if(!compiler_testing::expect_ident(outer.lo, compiler_testing::sym(m, "m"), msg)) { return -3; }
    if(!testing::expect_eq((void*)outer.hi, null, msg)) { return -4; }
    ast::SliceRangeNode* inner = compiler_testing::expect_slice_range(outer.base, msg);
    if(!inner) { return -5; }
    if(!testing::expect_eq((void*)inner.lo, null, msg)) { return -6; }
    if(!compiler_testing::expect_ident(inner.hi, compiler_testing::sym(m, "n"), msg)) { return -7; }
    if(!compiler_testing::expect_ident(inner.base, compiler_testing::sym(m, "a"), msg)) { return -8; }
    return 0;
}

fn i32 expr_slice_range_hi_only_on_namespace_base(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32[] x = mod::arr[..n];", &m);
    if(!testing::expect_eq(m.diag.entries.len, (u64)0, msg)) { return -1; }
    ast::SliceRangeNode* sr = compiler_testing::expect_slice_range(compiler_testing::var_init(root, 0), msg);
    if(!sr) { return -2; }
    if(!compiler_testing::expect_nsacc(sr.base, compiler_testing::sym(m, "mod"), compiler_testing::sym(m, "arr"), msg)) { return -3; }
    if(!testing::expect_eq((void*)sr.lo, null, msg)) { return -4; }
    if(!compiler_testing::expect_ident(sr.hi, compiler_testing::sym(m, "n"), msg)) { return -5; }
    return 0;
}

fn i32 expr_member_access(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = s.field;", &m);
    ast::MemberAccessNode* ma = compiler_testing::expect_member(compiler_testing::var_init(root, 0), compiler_testing::sym(m, "field"), msg);
    if(!ma) { return -1; }
    if(!(compiler_testing::expect_ident(ma.base, compiler_testing::sym(m, "s"), msg))) { return -2; } return 0;
}

// a.b[0]  =>  ArrayIndex(MemberAccess(a, b), 0)
fn i32 expr_chained_postfix(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = a.b[0];", &m);
    ast::ArrayIndexNode* ai = compiler_testing::expect_index(compiler_testing::var_init(root, 0), msg);
    if(!ai) { return -1; }
    ast::MemberAccessNode* ma = compiler_testing::expect_member(ai.base, compiler_testing::sym(m, "b"), msg);
    if(!ma) { return -2; }
    if(!compiler_testing::expect_ident(ma.base, compiler_testing::sym(m, "a"), msg)) { return -3; }
    if(!(compiler_testing::expect_intlit(ai.index, 0, msg))) { return -4; } return 0;
}

// f(1).x  =>  MemberAccess(Call(f, [1]), x)
fn i32 expr_chained_postfix_call_member(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = f(1).x;", &m);
    ast::MemberAccessNode* ma = compiler_testing::expect_member(compiler_testing::var_init(root, 0), compiler_testing::sym(m, "x"), msg);
    if(!ma) { return -1; }
    ast::CallNode* c = compiler_testing::expect_call(ma.base, 1, msg);
    if(!c) { return -2; }
    if(!compiler_testing::expect_ident(c.callee, compiler_testing::sym(m, "f"), msg)) { return -3; }
    if(!(compiler_testing::expect_intlit(c.args.ptr[0], 1, msg))) { return -4; } return 0;
}

// a.b.c  =>  MemberAccess(MemberAccess(a, b), c)
fn i32 expr_member_chain_three(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = a.b.c;", &m);
    ast::MemberAccessNode* outer = compiler_testing::expect_member(compiler_testing::var_init(root, 0), compiler_testing::sym(m, "c"), msg);
    if(!outer) { return -1; }
    ast::MemberAccessNode* inner = compiler_testing::expect_member(outer.base, compiler_testing::sym(m, "b"), msg);
    if(!inner) { return -2; }
    if(!(compiler_testing::expect_ident(inner.base, compiler_testing::sym(m, "a"), msg))) { return -3; } return 0;
}

// ============================================================================
// EXPRESSIONS: PAREN vs CAST
// ============================================================================

// (1 + 2) * 3  =>  Star(Plus(1, 2)[paren], 3)
fn i32 expr_paren_grouping(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = (1 + 2) * 3;", &m);
    ast::BinaryOpNode* top = compiler_testing::expect_binop(compiler_testing::var_init(root, 0), token::TokenKind::Star, msg);
    if(!top) { return -1; }
    ast::BinaryOpNode* lhs = compiler_testing::expect_binop(top.lhs, token::TokenKind::Plus, msg);
    if(!lhs) { return -2; }
    if(!testing::expect_true(compiler_testing::has_paren_flag((ast::AstNode*)lhs), msg)) { return -3; }
    if(!compiler_testing::expect_intlit(lhs.lhs, 1, msg)) { return -4; }
    if(!compiler_testing::expect_intlit(lhs.rhs, 2, msg)) { return -5; }
    if(!(compiler_testing::expect_intlit(top.rhs, 3, msg))) { return -6; } return 0;
}

// (i32)y  =>  Cast(i32, Ident(y))
fn i32 expr_cast_primitive(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = (i32)y;", &m);
    ast::CastNode* c = compiler_testing::expect_cast(compiler_testing::var_init(root, 0), msg);
    if(!c) { return -1; }
    if(!compiler_testing::expect_ty_prim(c.target_type, token::TokenKind::I32, msg)) { return -2; }
    if(!(compiler_testing::expect_ident(c.expr, compiler_testing::sym(m, "y"), msg))) { return -3; } return 0;
}

// (i32*)q  =>  Cast(PointerType(i32), Ident(q))
fn i32 expr_cast_pointer(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32* p = (i32*)q;", &m);
    ast::CastNode* c = compiler_testing::expect_cast(compiler_testing::var_init(root, 0), msg);
    if(!c) { return -1; }
    ast::TypePointerNode* tp = compiler_testing::expect_ty_ptr(c.target_type, msg);
    if(!tp) { return -2; }
    if(!compiler_testing::expect_ty_prim(tp.pointee, token::TokenKind::I32, msg)) { return -3; }
    if(!(compiler_testing::expect_ident(c.expr, compiler_testing::sym(m, "q"), msg))) { return -4; } return 0;
}

// (i32)-y  =>  Cast(i32, UnaryOp(Minus, y))
fn i32 expr_cast_then_unary(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = (i32)-y;", &m);
    ast::CastNode* c = compiler_testing::expect_cast(compiler_testing::var_init(root, 0), msg);
    if(!c) { return -1; }
    if(!compiler_testing::expect_ty_prim(c.target_type, token::TokenKind::I32, msg)) { return -2; }
    ast::UnaryOpNode* u = compiler_testing::expect_unop(c.expr, token::TokenKind::Minus, msg);
    if(!u) { return -3; }
    if(!(compiler_testing::expect_ident(u.operand, compiler_testing::sym(m, "y"), msg))) { return -4; } return 0;
}

// (1 + 2) — parse_type tries 1, fails, rewinds; diag must stay clean.
fn i32 expr_paren_arith_rewinds(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = (1 + 2);", &m);
    ast::BinaryOpNode* b = compiler_testing::expect_binop(compiler_testing::var_init(root, 0), token::TokenKind::Plus, msg);
    if(!b) { return -1; }
    if(!compiler_testing::expect_intlit(b.lhs, 1, msg)) { return -2; }
    if(!compiler_testing::expect_intlit(b.rhs, 2, msg)) { return -3; }
    if(!(testing::expect_eq(m.diag.entries.len, 0, msg))) { return -4; } return 0;
}

// ============================================================================
// EXPRESSIONS: STRUCT / ARRAY LITERALS
// ============================================================================

fn i32 expr_struct_lit_positional(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "Point p = {1, 2};", &m);
    ast::StructLitNode* sl = compiler_testing::expect_struct_lit(compiler_testing::var_init(root, 0), 2, msg);
    if(!sl) { return -1; }
    if(!compiler_testing::expect_field_init(&sl.inits[0], null, msg)) { return -2; }
    if(!compiler_testing::expect_intlit(sl.inits[0].value, 1, msg)) { return -3; }
    if(!compiler_testing::expect_field_init(&sl.inits[1], null, msg)) { return -4; }
    if(!(compiler_testing::expect_intlit(sl.inits[1].value, 2, msg))) { return -5; } return 0;
}

fn i32 expr_struct_lit_designated(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "Point p = {.a = 1, .b = 2};", &m);
    ast::StructLitNode* sl = compiler_testing::expect_struct_lit(compiler_testing::var_init(root, 0), 2, msg);
    if(!sl) { return -1; }
    if(!compiler_testing::expect_field_init(&sl.inits[0], compiler_testing::sym(m, "a"), msg)) { return -2; }
    if(!compiler_testing::expect_intlit(sl.inits[0].value, 1, msg)) { return -3; }
    if(!compiler_testing::expect_field_init(&sl.inits[1], compiler_testing::sym(m, "b"), msg)) { return -4; }
    if(!(compiler_testing::expect_intlit(sl.inits[1].value, 2, msg))) { return -5; } return 0;
}

fn i32 expr_struct_lit_mixed_pos_designated(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "Point p = {1, .b = 2};", &m);
    ast::StructLitNode* sl = compiler_testing::expect_struct_lit(compiler_testing::var_init(root, 0), 2, msg);
    if(!sl) { return -1; }
    if(!compiler_testing::expect_field_init(&sl.inits[0], null, msg)) { return -2; }
    if(!compiler_testing::expect_field_init(&sl.inits[1], compiler_testing::sym(m, "b"), msg)) { return -3; }
    return 0;
}

fn i32 expr_struct_lit_trailing_comma(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "Point p = {1, 2,};", &m);
    ast::StructLitNode* sl = compiler_testing::expect_struct_lit(compiler_testing::var_init(root, 0), 2, msg);
    if(!sl) { return -1; }
    if(!(testing::expect_eq(m.diag.entries.len, 0, msg))) { return -2; } return 0;
}

fn i32 expr_struct_lit_empty(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "Point p = {};", &m);
    ast::StructLitNode* sl = compiler_testing::expect_struct_lit(compiler_testing::var_init(root, 0), 0, msg);
    if(!sl) { return -1; }
    if(!(testing::expect_eq(m.diag.entries.len, 0, msg))) { return -2; } return 0;
}

fn i32 expr_array_lit(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32[3] arr = [1, 2, 3];", &m);
    ast::ArrayLitNode* al = compiler_testing::expect_array_lit(compiler_testing::var_init(root, 0), 3, msg);
    if(!al) { return -1; }
    if(!compiler_testing::expect_intlit(al.elems.ptr[0], 1, msg)) { return -2; }
    if(!compiler_testing::expect_intlit(al.elems.ptr[1], 2, msg)) { return -3; }
    if(!(compiler_testing::expect_intlit(al.elems.ptr[2], 3, msg))) { return -4; } return 0;
}

fn i32 expr_array_lit_empty(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32[] s = [];", &m);
    ast::ArrayLitNode* al = compiler_testing::expect_array_lit(compiler_testing::var_init(root, 0), 0, msg);
    if(!al) { return -1; }
    if(!(testing::expect_eq(m.diag.entries.len, 0, msg))) { return -2; } return 0;
}

// ============================================================================
// EXPRESSIONS: COMBOS
// ============================================================================

// (a + b) * (c - d)  =>  Star(Plus(a,b), Minus(c,d))
fn i32 expr_combo_paren_mul(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = (a + b) * (c - d);", &m);
    ast::BinaryOpNode* top = compiler_testing::expect_binop(compiler_testing::var_init(root, 0), token::TokenKind::Star, msg);
    if(!top) { return -1; }
    ast::BinaryOpNode* lhs = compiler_testing::expect_binop(top.lhs, token::TokenKind::Plus, msg);
    if(!lhs) { return -2; }
    if(!compiler_testing::expect_ident(lhs.lhs, compiler_testing::sym(m, "a"), msg)) { return -3; }
    if(!compiler_testing::expect_ident(lhs.rhs, compiler_testing::sym(m, "b"), msg)) { return -4; }
    ast::BinaryOpNode* rhs = compiler_testing::expect_binop(top.rhs, token::TokenKind::Minus, msg);
    if(!rhs) { return -5; }
    if(!compiler_testing::expect_ident(rhs.lhs, compiler_testing::sym(m, "c"), msg)) { return -6; }
    if(!(compiler_testing::expect_ident(rhs.rhs, compiler_testing::sym(m, "d"), msg))) { return -7; } return 0;
}

// f(a, b) + g(c)  =>  Plus(Call(f, [a, b]), Call(g, [c]))
fn i32 expr_combo_call_plus_call(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = f(a, b) + g(c);", &m);
    ast::BinaryOpNode* top = compiler_testing::expect_binop(compiler_testing::var_init(root, 0), token::TokenKind::Plus, msg);
    if(!top) { return -1; }
    ast::CallNode* lhs = compiler_testing::expect_call(top.lhs, 2, msg);
    if(!lhs) { return -2; }
    if(!compiler_testing::expect_ident(lhs.callee, compiler_testing::sym(m, "f"), msg)) { return -3; }
    ast::CallNode* rhs = compiler_testing::expect_call(top.rhs, 1, msg);
    if(!rhs) { return -4; }
    if(!(compiler_testing::expect_ident(rhs.callee, compiler_testing::sym(m, "g"), msg))) { return -5; } return 0;
}

// -a.b  =>  Minus(MemberAccess(a, b))
fn i32 expr_combo_unary_member(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = -a.b;", &m);
    ast::UnaryOpNode* u = compiler_testing::expect_unop(compiler_testing::var_init(root, 0), token::TokenKind::Minus, msg);
    if(!u) { return -1; }
    ast::MemberAccessNode* ma = compiler_testing::expect_member(u.operand, compiler_testing::sym(m, "b"), msg);
    if(!ma) { return -2; }
    if(!(compiler_testing::expect_ident(ma.base, compiler_testing::sym(m, "a"), msg))) { return -3; } return 0;
}

// a[0] + b[1]  =>  Plus(ArrayIndex(a, 0), ArrayIndex(b, 1))
fn i32 expr_combo_index_plus_index(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = a[0] + b[1];", &m);
    ast::BinaryOpNode* top = compiler_testing::expect_binop(compiler_testing::var_init(root, 0), token::TokenKind::Plus, msg);
    if(!top) { return -1; }
    ast::ArrayIndexNode* la = compiler_testing::expect_index(top.lhs, msg);
    if(!la) { return -2; }
    if(!compiler_testing::expect_ident(la.base, compiler_testing::sym(m, "a"), msg)) { return -3; }
    if(!compiler_testing::expect_intlit(la.index, 0, msg)) { return -4; }
    ast::ArrayIndexNode* ra = compiler_testing::expect_index(top.rhs, msg);
    if(!ra) { return -5; }
    if(!compiler_testing::expect_ident(ra.base, compiler_testing::sym(m, "b"), msg)) { return -6; }
    if(!(compiler_testing::expect_intlit(ra.index, 1, msg))) { return -7; } return 0;
}

// (i32)x + y  =>  Plus(Cast(i32, x), y)   (cast binds like a unary, tighter than +)
fn i32 expr_combo_cast_then_binary(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = (i32)y + z;", &m);
    ast::BinaryOpNode* top = compiler_testing::expect_binop(compiler_testing::var_init(root, 0), token::TokenKind::Plus, msg);
    if(!top) { return -1; }
    ast::CastNode* c = compiler_testing::expect_cast(top.lhs, msg);
    if(!c) { return -2; }
    if(!compiler_testing::expect_ty_prim(c.target_type, token::TokenKind::I32, msg)) { return -3; }
    if(!compiler_testing::expect_ident(c.expr, compiler_testing::sym(m, "y"), msg)) { return -4; }
    if(!(compiler_testing::expect_ident(top.rhs, compiler_testing::sym(m, "z"), msg))) { return -5; } return 0;
}

// ============================================================================
// EXPRESSIONS: SRC_POS SANITY
// ============================================================================

// `i32 x = 1 + 2;` — `+` lives at byte 10
fn i32 expr_binop_src_pos_on_operator(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = 1 + 2;", &m);
    ast::BinaryOpNode* b = compiler_testing::expect_binop(compiler_testing::var_init(root, 0), token::TokenKind::Plus, msg);
    if(!b) { return -1; }
    if(!(testing::expect_eq(b.h.src_pos, 10, msg))) { return -2; } return 0;
}

// `i32 x = -y;` — `-` lives at byte 8
fn i32 expr_unop_src_pos_on_operator(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = -y;", &m);
    ast::UnaryOpNode* u = compiler_testing::expect_unop(compiler_testing::var_init(root, 0), token::TokenKind::Minus, msg);
    if(!u) { return -1; }
    if(!(testing::expect_eq(u.h.src_pos, 8, msg))) { return -2; } return 0;
}

// ---- extern blocks ----

fn i32 extern_block_empty(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 0, msg);
    if(!b) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -2; }
    return 0;
}

fn i32 extern_block_named_lib(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern \"mylib\" { }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "mylib"), 0, msg);
    if(!b) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -2; }
    return 0;
}

fn i32 extern_block_lib_c_explicit(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern \"c\" { }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "c"), 0, msg);
    if(!b) { return -1; }
    return 0;
}

fn i32 extern_block_src_pos_on_extern_kw(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 0, msg);
    if(!b) { return -1; }
    if(!testing::expect_eq(b.h.src_pos, 0, msg)) { return -2; }
    return 0;
}

fn i32 extern_fn_no_params(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { fn void f(); }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternFnDeclNode* f = compiler_testing::expect_extern_fn(b.items[0], compiler_testing::sym(m, "f"), 0, false, false, msg);
    if(!f) { return -2; }
    if(!compiler_testing::expect_ty_prim(f.return_type, token::TokenKind::VOID, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -4; }
    return 0;
}

fn i32 extern_fn_with_params(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { fn i32 puts(u8* s); }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternFnDeclNode* f = compiler_testing::expect_extern_fn(b.items[0], compiler_testing::sym(m, "puts"), 1, false, false, msg);
    if(!f) { return -2; }
    if(!compiler_testing::expect_ty_prim(f.return_type, token::TokenKind::I32, msg)) { return -3; }
    if(!compiler_testing::expect_param(&f.params[0], compiler_testing::sym(m, "s"), false, false, msg)) { return -4; }
    ast::TypePointerNode* pty = compiler_testing::expect_ty_ptr(f.params[0].type_expr, msg);
    if(!pty) { return -5; }
    if(!compiler_testing::expect_ty_prim(pty.pointee, token::TokenKind::U8, msg)) { return -6; }
    return 0;
}

fn i32 extern_fn_variadic(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { fn i32 printf(u8* fmt, ...); }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternFnDeclNode* f = compiler_testing::expect_extern_fn(b.items[0], compiler_testing::sym(m, "printf"), 1, true, false, msg);
    if(!f) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -3; }
    return 0;
}

fn i32 extern_fn_variadic_only(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { fn void f(...); }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternFnDeclNode* f = compiler_testing::expect_extern_fn(b.items[0], compiler_testing::sym(m, "f"), 0, true, false, msg);
    if(!f) { return -2; }
    return 0;
}

fn i32 extern_fn_multi_param_variadic(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { fn i32 f(i32 a, u8* b, ...); }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternFnDeclNode* f = compiler_testing::expect_extern_fn(b.items[0], compiler_testing::sym(m, "f"), 2, true, false, msg);
    if(!f) { return -2; }
    if(!compiler_testing::expect_ty_prim(f.params[0].type_expr, token::TokenKind::I32, msg)) { return -3; }
    ast::TypePointerNode* p1 = compiler_testing::expect_ty_ptr(f.params[1].type_expr, msg);
    if(!p1) { return -4; }
    if(!compiler_testing::expect_ty_prim(p1.pointee, token::TokenKind::U8, msg)) { return -5; }
    return 0;
}

fn i32 extern_fn_exported(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { export fn void f(); }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternFnDeclNode* f = compiler_testing::expect_extern_fn(b.items[0], compiler_testing::sym(m, "f"), 0, false, true, msg);
    if(!f) { return -2; }
    return 0;
}

fn i32 extern_fn_comptime_safe_is_minus_one(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { fn void f(); }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternFnDeclNode* f = compiler_testing::expect_extern_fn(b.items[0], compiler_testing::sym(m, "f"), 0, false, false, msg);
    if(!f) { return -2; }
    if(!testing::expect_eq((i32)f.comptime_safe, (i32)-1, msg)) { return -3; }
    return 0;
}

fn i32 extern_struct_opaque(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { opaque struct FILE; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternStructDeclNode* s = compiler_testing::expect_extern_struct(b.items[0], compiler_testing::sym(m, "FILE"), 0, true, false, msg);
    if(!s) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -3; }
    return 0;
}

fn i32 extern_struct_opaque_exported(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { export opaque struct FILE; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternStructDeclNode* s = compiler_testing::expect_extern_struct(b.items[0], compiler_testing::sym(m, "FILE"), 0, true, true, msg);
    if(!s) { return -2; }
    return 0;
}

fn i32 extern_struct_full(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { struct Point { i32 x; i32 y; }; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternStructDeclNode* s = compiler_testing::expect_extern_struct(b.items[0], compiler_testing::sym(m, "Point"), 2, false, false, msg);
    if(!s) { return -2; }
    if(!compiler_testing::expect_field(&s.fields[0], compiler_testing::sym(m, "x"), msg)) { return -3; }
    if(!compiler_testing::expect_ty_prim(s.fields[0].type_expr, token::TokenKind::I32, msg)) { return -4; }
    if(!compiler_testing::expect_field(&s.fields[1], compiler_testing::sym(m, "y"), msg)) { return -5; }
    if(!compiler_testing::expect_ty_prim(s.fields[1].type_expr, token::TokenKind::I32, msg)) { return -6; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -7; }
    return 0;
}

fn i32 extern_struct_full_empty_body(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { struct E { }; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternStructDeclNode* s = compiler_testing::expect_extern_struct(b.items[0], compiler_testing::sym(m, "E"), 0, false, false, msg);
    if(!s) { return -2; }
    return 0;
}

fn i32 extern_struct_full_exported(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { export struct Point { i32 x; }; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternStructDeclNode* s = compiler_testing::expect_extern_struct(b.items[0], compiler_testing::sym(m, "Point"), 1, false, true, msg);
    if(!s) { return -2; }
    return 0;
}

fn i32 extern_struct_no_body_no_opaque_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { struct Foo; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternStructDeclNode* s = compiler_testing::expect_extern_struct(b.items[0], compiler_testing::sym(m, "Foo"), 0, false, false, msg);
    if(!s) { return -2; }
    if(!testing::expect_true(((u16)s.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 1, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "extern struct without body must be marked 'opaque'", msg)) { return -5; }
    return 0;
}

fn i32 extern_struct_opaque_with_body_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { opaque struct Foo { i32 x; }; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternStructDeclNode* s = compiler_testing::expect_extern_struct(b.items[0], compiler_testing::sym(m, "Foo"), 1, true, false, msg);
    if(!s) { return -2; }
    if(!testing::expect_true(((u16)s.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 1, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "opaque extern type cannot have a body", msg)) { return -5; }
    return 0;
}

fn i32 extern_union_opaque(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { opaque union V; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternUnionDeclNode* u = compiler_testing::expect_extern_union(b.items[0], compiler_testing::sym(m, "V"), 0, true, false, msg);
    if(!u) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -3; }
    return 0;
}

fn i32 extern_union_opaque_exported(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { export opaque union V; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternUnionDeclNode* u = compiler_testing::expect_extern_union(b.items[0], compiler_testing::sym(m, "V"), 0, true, true, msg);
    if(!u) { return -2; }
    return 0;
}

fn i32 extern_union_full(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { union U { i32 i; f32 f; }; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternUnionDeclNode* u = compiler_testing::expect_extern_union(b.items[0], compiler_testing::sym(m, "U"), 2, false, false, msg);
    if(!u) { return -2; }
    if(!compiler_testing::expect_field(&u.fields[0], compiler_testing::sym(m, "i"), msg)) { return -3; }
    if(!compiler_testing::expect_ty_prim(u.fields[0].type_expr, token::TokenKind::I32, msg)) { return -4; }
    if(!compiler_testing::expect_field(&u.fields[1], compiler_testing::sym(m, "f"), msg)) { return -5; }
    if(!compiler_testing::expect_ty_prim(u.fields[1].type_expr, token::TokenKind::F32, msg)) { return -6; }
    return 0;
}

fn i32 extern_union_full_exported(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { export union U { i32 i; }; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternUnionDeclNode* u = compiler_testing::expect_extern_union(b.items[0], compiler_testing::sym(m, "U"), 1, false, true, msg);
    if(!u) { return -2; }
    return 0;
}

fn i32 extern_union_no_body_no_opaque_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { union Foo; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternUnionDeclNode* u = compiler_testing::expect_extern_union(b.items[0], compiler_testing::sym(m, "Foo"), 0, false, false, msg);
    if(!u) { return -2; }
    if(!testing::expect_true(((u16)u.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 1, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "extern union without body must be marked 'opaque'", msg)) { return -5; }
    return 0;
}

fn i32 extern_union_opaque_with_body_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { opaque union Foo { i32 x; }; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternUnionDeclNode* u = compiler_testing::expect_extern_union(b.items[0], compiler_testing::sym(m, "Foo"), 1, true, false, msg);
    if(!u) { return -2; }
    if(!testing::expect_true(((u16)u.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 1, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "opaque extern type cannot have a body", msg)) { return -5; }
    return 0;
}

fn i32 extern_opaque_on_fn_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { opaque fn void f(); }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternFnDeclNode* f = compiler_testing::expect_extern_fn(b.items[0], compiler_testing::sym(m, "f"), 0, false, false, msg);
    if(!f) { return -2; }
    if(!testing::expect_true(((u16)f.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries.len, 1, msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "'opaque' is only valid on struct or union", msg)) { return -5; }
    return 0;
}

fn i32 extern_block_multi_item(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local,
        "extern { opaque struct FILE; fn i32 puts(u8* s); fn i32 printf(u8* fmt, ...); }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 3, msg);
    if(!b) { return -1; }
    ast::ExternStructDeclNode* s = compiler_testing::expect_extern_struct(b.items[0], compiler_testing::sym(m, "FILE"), 0, true, false, msg);
    if(!s) { return -2; }
    ast::ExternFnDeclNode* f1 = compiler_testing::expect_extern_fn(b.items[1], compiler_testing::sym(m, "puts"), 1, false, false, msg);
    if(!f1) { return -3; }
    ast::ExternFnDeclNode* f2 = compiler_testing::expect_extern_fn(b.items[2], compiler_testing::sym(m, "printf"), 1, true, false, msg);
    if(!f2) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 extern_block_mixed_export(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local,
        "extern { export fn void a(); fn void b(); export opaque struct C; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 3, msg);
    if(!b) { return -1; }
    if(!compiler_testing::expect_extern_fn(b.items[0], compiler_testing::sym(m, "a"), 0, false, true, msg)) { return -2; }
    if(!compiler_testing::expect_extern_fn(b.items[1], compiler_testing::sym(m, "b"), 0, false, false, msg)) { return -3; }
    if(!compiler_testing::expect_extern_struct(b.items[2], compiler_testing::sym(m, "C"), 0, true, true, msg)) { return -4; }
    return 0;
}

fn i32 extern_block_after_import(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import io; extern { fn void f(); }", &m);
    if(!compiler_testing::expect_import(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "io"), msg)) { return -1; }
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 1), null, 1, msg);
    if(!b) { return -2; }
    return 0;
}

fn i32 extern_unknown_item_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { i32 x; }", &m);
    ast::AstNode* n0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)n0, msg)) { return -1; }
    if(!testing::expect_eq((u16)n0.h.kind, (u16)ast::AstKind::ExternBlock, msg)) { return -2; }
    ast::ExternBlockNode* b = (ast::ExternBlockNode*)n0;
    if(!testing::expect_true(((u16)b.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_true(m.diag.entries.len >= 1, msg)) { return -4; }
    return 0;
}

fn i32 extern_missing_rbrace_at_eof(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { fn void f();", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    if(!testing::expect_true(((u16)b.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -2; }
    return 0;
}

fn i32 extern_named_lib_with_items(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local,
        "extern \"sodium\" { fn i32 sodium_init(); opaque struct sodium_state; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "sodium"), 2, msg);
    if(!b) { return -1; }
    if(!compiler_testing::expect_extern_fn(b.items[0], compiler_testing::sym(m, "sodium_init"), 0, false, false, msg)) { return -2; }
    if(!compiler_testing::expect_extern_struct(b.items[1], compiler_testing::sym(m, "sodium_state"), 0, true, false, msg)) { return -3; }
    return 0;
}

fn i32 extern_struct_full_with_pointer_field(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { struct Node { Node* next; i32 value; }; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternStructDeclNode* s = compiler_testing::expect_extern_struct(b.items[0], compiler_testing::sym(m, "Node"), 2, false, false, msg);
    if(!s) { return -2; }
    if(!compiler_testing::expect_ty_ptr(s.fields[0].type_expr, msg)) { return -3; }
    if(!compiler_testing::expect_ty_prim(s.fields[1].type_expr, token::TokenKind::I32, msg)) { return -4; }
    return 0;
}

fn i32 extern_fn_returns_pointer(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { fn u8* malloc(u64 size); }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternFnDeclNode* f = compiler_testing::expect_extern_fn(b.items[0], compiler_testing::sym(m, "malloc"), 1, false, false, msg);
    if(!f) { return -2; }
    ast::TypePointerNode* pty = compiler_testing::expect_ty_ptr(f.return_type, msg);
    if(!pty) { return -3; }
    if(!compiler_testing::expect_ty_prim(pty.pointee, token::TokenKind::U8, msg)) { return -4; }
    if(!compiler_testing::expect_ty_prim(f.params[0].type_expr, token::TokenKind::U64, msg)) { return -5; }
    return 0;
}

fn i32 extern_fn_takes_opaque_pointer(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local,
        "extern { opaque struct FILE; fn i32 fclose(FILE* fp); }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 2, msg);
    if(!b) { return -1; }
    if(!compiler_testing::expect_extern_struct(b.items[0], compiler_testing::sym(m, "FILE"), 0, true, false, msg)) { return -2; }
    ast::ExternFnDeclNode* f = compiler_testing::expect_extern_fn(b.items[1], compiler_testing::sym(m, "fclose"), 1, false, false, msg);
    if(!f) { return -3; }
    ast::TypePointerNode* pty = compiler_testing::expect_ty_ptr(f.params[0].type_expr, msg);
    if(!pty) { return -4; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -5; }
    return 0;
}

fn i32 extern_two_blocks(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local,
        "extern { fn void a(); } extern \"x\" { fn void b(); }", &m);
    ast::ExternBlockNode* b0 = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b0) { return -1; }
    ast::ExternBlockNode* b1 = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 1), compiler_testing::sym(m, "x"), 1, msg);
    if(!b1) { return -2; }
    return 0;
}

fn i32 extern_fn_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { fn void f(); }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternFnDeclNode* f = compiler_testing::expect_extern_fn(b.items[0], compiler_testing::sym(m, "f"), 0, false, false, msg);
    if(!f) { return -2; }
    if(!testing::expect_eq(f.h.src_pos, (u32)9, msg)) { return -3; }
    return 0;
}

fn i32 extern_struct_src_pos_at_start(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { opaque struct FILE; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternStructDeclNode* s = compiler_testing::expect_extern_struct(b.items[0], compiler_testing::sym(m, "FILE"), 0, true, false, msg);
    if(!s) { return -2; }
    if(!testing::expect_eq(s.h.src_pos, (u32)9, msg)) { return -3; }
    return 0;
}

fn i32 extern_export_struct_src_pos_includes_export(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { export opaque struct FILE; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternStructDeclNode* s = compiler_testing::expect_extern_struct(b.items[0], compiler_testing::sym(m, "FILE"), 0, true, true, msg);
    if(!s) { return -2; }
    if(!testing::expect_eq(s.h.src_pos, (u32)9, msg)) { return -3; }
    return 0;
}

fn i32 fn_variadic_at_top_level_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(...) { }", &m);
    if(!testing::expect_true(m.diag.entries.len >= 1, msg)) { return -1; }
    return 0;
}

fn i32 extern_bare_no_brace_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern;", &m);
    ast::AstNode* n0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)n0, msg)) { return -1; }
    if(!testing::expect_eq((u16)n0.h.kind, (u16)ast::AstKind::ExternBlock, msg)) { return -2; }
    ast::ExternBlockNode* b = (ast::ExternBlockNode*)n0;
    if(!testing::expect_true(((u16)b.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_true(m.diag.entries.len >= 1, msg)) { return -4; }
    return 0;
}

fn i32 extern_non_string_lib_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern foo { }", &m);
    ast::AstNode* n0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)n0, msg)) { return -1; }
    if(!testing::expect_eq((u16)n0.h.kind, (u16)ast::AstKind::ExternBlock, msg)) { return -2; }
    ast::ExternBlockNode* b = (ast::ExternBlockNode*)n0;
    if(!testing::expect_true(((u16)b.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_eq((void*)b.lib_name, (void*)null, msg)) { return -4; }
    if(!testing::expect_true(m.diag.entries.len >= 1, msg)) { return -5; }
    return 0;
}

fn i32 extern_wrong_modifier_order_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { opaque export struct X; }", &m);
    ast::AstNode* n0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)n0, msg)) { return -1; }
    if(!testing::expect_eq((u16)n0.h.kind, (u16)ast::AstKind::ExternBlock, msg)) { return -2; }
    ast::ExternBlockNode* b = (ast::ExternBlockNode*)n0;
    if(!testing::expect_true(((u16)b.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_true(m.diag.entries.len >= 1, msg)) { return -4; }
    return 0;
}

fn i32 extern_fn_missing_semi_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { fn void f() }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    ast::ExternFnDeclNode* f = compiler_testing::expect_extern_fn(b.items[0], compiler_testing::sym(m, "f"), 0, false, false, msg);
    if(!f) { return -2; }
    if(!testing::expect_true(((u16)f.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_true(m.diag.entries.len >= 1, msg)) { return -4; }
    return 0;
}

fn i32 extern_struct_no_body_no_opaque_src_pos_at_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { struct Foo; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, 1, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)19, msg)) { return -3; }
    return 0;
}

fn i32 extern_struct_opaque_with_body_src_pos_at_lbrace(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { opaque struct Foo { i32 x; }; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, 1, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)27, msg)) { return -3; }
    return 0;
}

fn i32 extern_union_no_body_no_opaque_src_pos_at_semi(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { union Foo; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, 1, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)18, msg)) { return -3; }
    return 0;
}

fn i32 extern_union_opaque_with_body_src_pos_at_lbrace(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { opaque union Foo { i32 x; }; }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, 1, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)26, msg)) { return -3; }
    return 0;
}

fn i32 extern_opaque_on_fn_src_pos_at_opaque(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { opaque fn void f(); }", &m);
    ast::ExternBlockNode* b = compiler_testing::expect_extern_block(compiler_testing::nth_stmt(root, 0), null, 1, msg);
    if(!b) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, 1, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)9, msg)) { return -3; }
    return 0;
}

fn i32 extern_double_export_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { export export fn void f(); }", &m);
    ast::AstNode* n0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)n0, msg)) { return -1; }
    if(!testing::expect_eq((u16)n0.h.kind, (u16)ast::AstKind::ExternBlock, msg)) { return -2; }
    ast::ExternBlockNode* b = (ast::ExternBlockNode*)n0;
    if(!testing::expect_true(((u16)b.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_true(m.diag.entries.len >= 1, msg)) { return -4; }
    return 0;
}

fn i32 opaque_at_top_level_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "opaque struct Foo;", &m);
    if(!testing::expect_true(m.diag.entries.len >= 1, msg)) { return -1; }
    return 0;
}

fn i32 extern_opaque_on_var_decl_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { opaque i32 x; }", &m);
    ast::AstNode* n0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)n0, msg)) { return -1; }
    if(!testing::expect_eq((u16)n0.h.kind, (u16)ast::AstKind::ExternBlock, msg)) { return -2; }
    ast::ExternBlockNode* b = (ast::ExternBlockNode*)n0;
    if(!testing::expect_true(((u16)b.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_true(m.diag.entries.len >= 1, msg)) { return -4; }
    return 0;
}

// ---- enum decls ----

fn i32 enum_empty(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E { }", &m);
    ast::EnumDeclNode* e = compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "E"), 0, false, token::TokenKind::I32, false, msg);
    if(!e) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -2; }
    return 0;
}

fn i32 enum_single_member(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E { A }", &m);
    ast::EnumDeclNode* e = compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "E"), 1, false, token::TokenKind::I32, false, msg);
    if(!e) { return -1; }
    if(!compiler_testing::expect_enum_member(&e.members[0], compiler_testing::sym(m, "A"), false, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -3; }
    return 0;
}

fn i32 enum_multi_member(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum Color { Red, Green, Blue }", &m);
    ast::EnumDeclNode* e = compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "Color"), 3, false, token::TokenKind::I32, false, msg);
    if(!e) { return -1; }
    if(!compiler_testing::expect_enum_member(&e.members[0], compiler_testing::sym(m, "Red"), false, msg)) { return -2; }
    if(!compiler_testing::expect_enum_member(&e.members[1], compiler_testing::sym(m, "Green"), false, msg)) { return -3; }
    if(!compiler_testing::expect_enum_member(&e.members[2], compiler_testing::sym(m, "Blue"), false, msg)) { return -4; }
    return 0;
}

fn i32 enum_explicit_base_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E : u8 { A, B }", &m);
    ast::EnumDeclNode* e = compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "E"), 2, true, token::TokenKind::U8, false, msg);
    if(!e) { return -1; }
    return 0;
}

fn i32 enum_all_int_base_types(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local,
        "enum A : i8 { } enum B : i16 { } enum C : i32 { } enum D : i64 { } enum E : u8 { } enum F : u16 { } enum G : u32 { } enum H : u64 { }", &m);
    if(!compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "A"), 0, true, token::TokenKind::I8, false, msg)) { return -1; }
    if(!compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 1), compiler_testing::sym(m, "B"), 0, true, token::TokenKind::I16, false, msg)) { return -2; }
    if(!compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 2), compiler_testing::sym(m, "C"), 0, true, token::TokenKind::I32, false, msg)) { return -3; }
    if(!compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 3), compiler_testing::sym(m, "D"), 0, true, token::TokenKind::I64, false, msg)) { return -4; }
    if(!compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 4), compiler_testing::sym(m, "E"), 0, true, token::TokenKind::U8, false, msg)) { return -5; }
    if(!compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 5), compiler_testing::sym(m, "F"), 0, true, token::TokenKind::U16, false, msg)) { return -6; }
    if(!compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 6), compiler_testing::sym(m, "G"), 0, true, token::TokenKind::U32, false, msg)) { return -7; }
    if(!compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 7), compiler_testing::sym(m, "H"), 0, true, token::TokenKind::U64, false, msg)) { return -8; }
    return 0;
}

fn i32 enum_explicit_int_value(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E { A = 42 }", &m);
    ast::EnumDeclNode* e = compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "E"), 1, false, token::TokenKind::I32, false, msg);
    if(!e) { return -1; }
    if(!compiler_testing::expect_enum_member(&e.members[0], compiler_testing::sym(m, "A"), true, msg)) { return -2; }
    if(!compiler_testing::expect_intlit(e.members[0].value_expr, (u64)42, msg)) { return -3; }
    return 0;
}

fn i32 enum_mixed_explicit_and_auto(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E { A, B = 10, C }", &m);
    ast::EnumDeclNode* e = compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "E"), 3, false, token::TokenKind::I32, false, msg);
    if(!e) { return -1; }
    if(!compiler_testing::expect_enum_member(&e.members[0], compiler_testing::sym(m, "A"), false, msg)) { return -2; }
    if(!compiler_testing::expect_enum_member(&e.members[1], compiler_testing::sym(m, "B"), true, msg)) { return -3; }
    if(!compiler_testing::expect_intlit(e.members[1].value_expr, (u64)10, msg)) { return -4; }
    if(!compiler_testing::expect_enum_member(&e.members[2], compiler_testing::sym(m, "C"), false, msg)) { return -5; }
    return 0;
}

fn i32 enum_symbolic_value(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E { A = 10, B = A }", &m);
    ast::EnumDeclNode* e = compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "E"), 2, false, token::TokenKind::I32, false, msg);
    if(!e) { return -1; }
    if(!compiler_testing::expect_enum_member(&e.members[1], compiler_testing::sym(m, "B"), true, msg)) { return -2; }
    if(!compiler_testing::expect_ident(e.members[1].value_expr, compiler_testing::sym(m, "A"), msg)) { return -3; }
    return 0;
}

fn i32 enum_negative_value(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E { A = -1 }", &m);
    ast::EnumDeclNode* e = compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "E"), 1, false, token::TokenKind::I32, false, msg);
    if(!e) { return -1; }
    if(!compiler_testing::expect_enum_member(&e.members[0], compiler_testing::sym(m, "A"), true, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -3; }
    return 0;
}

fn i32 enum_expression_value(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E { A = 1 + 2 }", &m);
    ast::EnumDeclNode* e = compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "E"), 1, false, token::TokenKind::I32, false, msg);
    if(!e) { return -1; }
    if(!compiler_testing::expect_enum_member(&e.members[0], compiler_testing::sym(m, "A"), true, msg)) { return -2; }
    return 0;
}

fn i32 enum_trailing_comma(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E { A, B, }", &m);
    ast::EnumDeclNode* e = compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "E"), 2, false, token::TokenKind::I32, false, msg);
    if(!e) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -2; }
    return 0;
}

fn i32 enum_exported(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "export enum Color { Red }", &m);
    ast::EnumDeclNode* e = compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "Color"), 1, false, token::TokenKind::I32, true, msg);
    if(!e) { return -1; }
    return 0;
}

fn i32 enum_exported_with_base_type(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "export enum Status : u8 { Ok, Err }", &m);
    ast::EnumDeclNode* e = compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "Status"), 2, true, token::TokenKind::U8, true, msg);
    if(!e) { return -1; }
    return 0;
}

fn i32 enum_spec_example(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum Status : u8 { Ok, Err = 234, Warn, Same = Err }", &m);
    ast::EnumDeclNode* e = compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "Status"), 4, true, token::TokenKind::U8, false, msg);
    if(!e) { return -1; }
    if(!compiler_testing::expect_enum_member(&e.members[0], compiler_testing::sym(m, "Ok"), false, msg)) { return -2; }
    if(!compiler_testing::expect_enum_member(&e.members[1], compiler_testing::sym(m, "Err"), true, msg)) { return -3; }
    if(!compiler_testing::expect_intlit(e.members[1].value_expr, (u64)234, msg)) { return -4; }
    if(!compiler_testing::expect_enum_member(&e.members[2], compiler_testing::sym(m, "Warn"), false, msg)) { return -5; }
    if(!compiler_testing::expect_enum_member(&e.members[3], compiler_testing::sym(m, "Same"), true, msg)) { return -6; }
    if(!compiler_testing::expect_ident(e.members[3].value_expr, compiler_testing::sym(m, "Err"), msg)) { return -7; }
    return 0;
}

fn i32 enum_src_pos_at_enum_kw(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E { A }", &m);
    ast::EnumDeclNode* e = compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "E"), 1, false, token::TokenKind::I32, false, msg);
    if(!e) { return -1; }
    if(!testing::expect_eq(e.h.src_pos, (u32)0, msg)) { return -2; }
    return 0;
}

fn i32 enum_member_src_pos(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E { A, B }", &m);
    ast::EnumDeclNode* e = compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "E"), 2, false, token::TokenKind::I32, false, msg);
    if(!e) { return -1; }
    if(!testing::expect_eq(e.members[0].src_pos, (u32)9, msg)) { return -2; }
    if(!testing::expect_eq(e.members[1].src_pos, (u32)12, msg)) { return -3; }
    return 0;
}

fn i32 enum_missing_name_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum { A }", &m);
    ast::AstNode* n0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)n0, msg)) { return -1; }
    if(!testing::expect_eq((u16)n0.h.kind, (u16)ast::AstKind::EnumDecl, msg)) { return -2; }
    if(!testing::expect_true(((u16)n0.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got '{'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)5, msg)) { return -5; }
    return 0;
}

fn i32 enum_missing_lbrace_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E A, B }", &m);
    ast::AstNode* n0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)n0, msg)) { return -1; }
    if(!testing::expect_eq((u16)n0.h.kind, (u16)ast::AstKind::EnumDecl, msg)) { return -2; }
    if(!testing::expect_true(((u16)n0.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '{', got identifier", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)7, msg)) { return -5; }
    return 0;
}

fn i32 enum_missing_rbrace_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E { A", &m);
    ast::AstNode* n0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)n0, msg)) { return -1; }
    if(!testing::expect_eq((u16)n0.h.kind, (u16)ast::AstKind::EnumDecl, msg)) { return -2; }
    if(!testing::expect_true(((u16)n0.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected '}', got end of file", msg)) { return -4; }
    return 0;
}

fn i32 enum_missing_member_after_comma_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E { A, , B }", &m);
    ast::AstNode* n0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)n0, msg)) { return -1; }
    if(!testing::expect_eq((u16)n0.h.kind, (u16)ast::AstKind::EnumDecl, msg)) { return -2; }
    if(!testing::expect_true(((u16)n0.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got ','", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)12, msg)) { return -5; }
    return 0;
}

fn i32 enum_missing_value_after_eq_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E { A = , B }", &m);
    ast::AstNode* n0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)n0, msg)) { return -1; }
    if(!testing::expect_eq((u16)n0.h.kind, (u16)ast::AstKind::EnumDecl, msg)) { return -2; }
    if(!testing::expect_true(((u16)n0.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_true(m.diag.entries.len >= 1, msg)) { return -4; }
    return 0;
}

fn i32 enum_member_is_keyword_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E { fn }", &m);
    ast::AstNode* n0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)n0, msg)) { return -1; }
    if(!testing::expect_eq((u16)n0.h.kind, (u16)ast::AstKind::EnumDecl, msg)) { return -2; }
    if(!testing::expect_true(((u16)n0.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got 'fn'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)9, msg)) { return -5; }
    return 0;
}

fn i32 enum_base_type_missing_after_colon_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E : { A }", &m);
    ast::AstNode* n0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)n0, msg)) { return -1; }
    if(!testing::expect_eq((u16)n0.h.kind, (u16)ast::AstKind::EnumDecl, msg)) { return -2; }
    if(!testing::expect_true(((u16)n0.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_eq(m.diag.entries[0].msg, "expected identifier, got '{'", msg)) { return -4; }
    if(!testing::expect_eq(m.diag.entries[0].src_pos, (u32)9, msg)) { return -5; }
    return 0;
}

fn i32 enum_missing_comma_between_members(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E { A B C }", &m);
    ast::AstNode* n0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)n0, msg)) { return -1; }
    if(!testing::expect_eq((u16)n0.h.kind, (u16)ast::AstKind::EnumDecl, msg)) { return -2; }
    if(!testing::expect_true(((u16)n0.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_true(m.diag.entries.len >= 1, msg)) { return -4; }
    return 0;
}

fn i32 enum_trailing_comma_single_member(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E { A, }", &m);
    ast::EnumDeclNode* e = compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "E"), 1, false, token::TokenKind::I32, false, msg);
    if(!e) { return -1; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -2; }
    return 0;
}

fn i32 enum_complex_expression_value(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E { A = (1 + 2) * 3 }", &m);
    ast::EnumDeclNode* e = compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "E"), 1, false, token::TokenKind::I32, false, msg);
    if(!e) { return -1; }
    if(!compiler_testing::expect_enum_member(&e.members[0], compiler_testing::sym(m, "A"), true, msg)) { return -2; }
    if(!testing::expect_eq(m.diag.entries.len, 0, msg)) { return -3; }
    return 0;
}

fn i32 enum_zero_value(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "enum E { A = 0 }", &m);
    ast::EnumDeclNode* e = compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "E"), 1, false, token::TokenKind::I32, false, msg);
    if(!e) { return -1; }
    if(!compiler_testing::expect_enum_member(&e.members[0], compiler_testing::sym(m, "A"), true, msg)) { return -2; }
    if(!compiler_testing::expect_intlit(e.members[0].value_expr, (u64)0, msg)) { return -3; }
    return 0;
}

fn i32 enum_after_other_decls(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "import io; enum E { A } struct S { i32 x; }", &m);
    if(!compiler_testing::expect_import(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "io"), msg)) { return -1; }
    if(!compiler_testing::expect_enum(compiler_testing::nth_stmt(root, 1), compiler_testing::sym(m, "E"), 1, false, token::TokenKind::I32, false, msg)) { return -2; }
    if(!compiler_testing::expect_struct_decl(compiler_testing::nth_stmt(root, 2), compiler_testing::sym(m, "S"), 1, false, msg)) { return -3; }
    return 0;
}

fn i32 extern_fn_with_body_errors(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "extern { fn void f() { } }", &m);
    ast::AstNode* n0 = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_not_null((void*)n0, msg)) { return -1; }
    if(!testing::expect_eq((u16)n0.h.kind, (u16)ast::AstKind::ExternBlock, msg)) { return -2; }
    ast::ExternBlockNode* b = (ast::ExternBlockNode*)n0;
    if(!testing::expect_true(((u16)b.h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -3; }
    if(!testing::expect_true(b.items.len >= 1, msg)) { return -4; }
    if(!testing::expect_eq((u16)b.items[0].h.kind, (u16)ast::AstKind::ExternFnDecl, msg)) { return -5; }
    if(!testing::expect_true(((u16)b.items[0].h.flags & (u16)ast::AstFlags::HadError) != 0, msg)) { return -6; }
    if(!testing::expect_true(m.diag.entries.len >= 1, msg)) { return -7; }
    return 0;
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
    testing::add(s_imp, "import_not_reexport_by_default", &import_not_reexport_by_default);
    testing::add(s_imp, "import_export_marks_reexport", &import_export_marks_reexport);
    testing::add(s_imp, "import_export_then_plain_import", &import_export_then_plain_import);
    testing::add(s_imp, "import_export_with_bad_module_name_recovers", &import_export_with_bad_module_name_recovers);
    testing::add(s_imp, "import_export_with_keyword_module_name_recovers", &import_export_with_keyword_module_name_recovers);

    u8[] s_var_decl = "Parser VarDecls";
    testing::add(s_var_decl, "var_decl_basic_int_init", &var_decl_basic_int_init);
    testing::add(s_var_decl, "var_decl_no_init", &var_decl_no_init);
    testing::add(s_var_decl, "var_decl_const", &var_decl_const);
    testing::add(s_var_decl, "var_decl_export", &var_decl_export);
    testing::add(s_var_decl, "var_decl_export_const", &var_decl_export_const);
    testing::add(s_var_decl, "var_decl_undefined_init", &var_decl_undefined_init);
    testing::add(s_var_decl, "var_decl_src_pos_on_type", &var_decl_src_pos_on_type);
    testing::add(s_var_decl, "var_decl_src_pos_on_const", &var_decl_src_pos_on_const);
    testing::add(s_var_decl, "var_decl_multiple_decls", &var_decl_multiple_decls);
    testing::add(s_var_decl, "var_decl_named_type_decl", &var_decl_named_type_decl);
    testing::add(s_var_decl, "var_decl_missing_ident", &var_decl_missing_ident);
    testing::add(s_var_decl, "var_decl_missing_semi_at_eof", &var_decl_missing_semi_at_eof);
    testing::add(s_var_decl, "var_decl_missing_semi_no_init", &var_decl_missing_semi_no_init);
    testing::add(s_var_decl, "var_decl_missing_init_expr", &var_decl_missing_init_expr);

    u8[] s_ty = "Parser Types";
    testing::add(s_ty, "ty_primitive_i32", &ty_primitive_i32);
    testing::add(s_ty, "ty_primitive_bool", &ty_primitive_bool);
    testing::add(s_ty, "ty_primitive_f64", &ty_primitive_f64);
    testing::add(s_ty, "ty_primitive_void", &ty_primitive_void);
    testing::add(s_ty, "ty_pointer", &ty_pointer);
    testing::add(s_ty, "ty_pointer_to_pointer", &ty_pointer_to_pointer);
    testing::add(s_ty, "ty_slice", &ty_slice);
    testing::add(s_ty, "ty_array", &ty_array);
    testing::add(s_ty, "ty_named", &ty_named);
    testing::add(s_ty, "ty_named_qualified", &ty_named_qualified);
    testing::add(s_ty, "ty_fn_ptr_two_params", &ty_fn_ptr_two_params);
    testing::add(s_ty, "ty_fn_ptr_zero_params", &ty_fn_ptr_zero_params);
    testing::add(s_ty, "ty_ptr_slice_chain", &ty_ptr_slice_chain);
    testing::add(s_ty, "ty_array_of_ptr", &ty_array_of_ptr);

    u8[] s_fn = "Parser FnDecls";
    testing::add(s_fn, "fn_empty_params", &fn_empty_params);
    testing::add(s_fn, "fn_single_param", &fn_single_param);
    testing::add(s_fn, "fn_two_params", &fn_two_params);
    testing::add(s_fn, "fn_param_const", &fn_param_const);
    testing::add(s_fn, "fn_param_comptime", &fn_param_comptime);
    testing::add(s_fn, "fn_param_comptime_const", &fn_param_comptime_const);
    testing::add(s_fn, "fn_param_pointer_type", &fn_param_pointer_type);
    testing::add(s_fn, "fn_param_slice_type", &fn_param_slice_type);
    testing::add(s_fn, "fn_param_named_type", &fn_param_named_type);
    testing::add(s_fn, "fn_param_qualified_named_type", &fn_param_qualified_named_type);
    testing::add(s_fn, "fn_params_mixed_modifiers", &fn_params_mixed_modifiers);
    testing::add(s_fn, "fn_param_trailing_comma", &fn_param_trailing_comma);
    testing::add(s_fn, "fn_exported", &fn_exported);
    testing::add(s_fn, "fn_param_src_pos_on_const", &fn_param_src_pos_on_const);
    testing::add(s_fn, "fn_param_src_pos_on_type_when_no_modifier", &fn_param_src_pos_on_type_when_no_modifier);
    testing::add(s_fn, "fn_param_src_pos_on_comptime", &fn_param_src_pos_on_comptime);
    testing::add(s_fn, "fn_missing_param_name", &fn_missing_param_name);
    testing::add(s_fn, "fn_missing_rparen", &fn_missing_rparen);
    testing::add(s_fn, "fn_missing_fn_name", &fn_missing_fn_name);
    testing::add(s_fn, "fn_src_pos_on_fn_keyword", &fn_src_pos_on_fn_keyword);
    testing::add(s_fn, "fn_export_src_pos_on_export", &fn_export_src_pos_on_export);
    testing::add(s_fn, "fn_multiple_decls", &fn_multiple_decls);
    testing::add(s_fn, "fn_fn_ptr_return_type", &fn_fn_ptr_return_type);
    testing::add(s_fn, "fn_param_fn_ptr_type", &fn_param_fn_ptr_type);
    testing::add(s_fn, "fn_missing_lparen", &fn_missing_lparen);
    testing::add(s_fn, "fn_missing_return_type", &fn_missing_return_type);
    testing::add(s_fn, "fn_missing_param_comma", &fn_missing_param_comma);
    testing::add(s_fn, "fn_param_modifier_only", &fn_param_modifier_only);
    testing::add(s_fn, "fn_param_wrong_modifier_order", &fn_param_wrong_modifier_order);
    testing::add(s_fn, "fn_param_wrong_order_with_pointer_type", &fn_param_wrong_order_with_pointer_type);
    testing::add(s_fn, "fn_param_wrong_order_with_qualified_type", &fn_param_wrong_order_with_qualified_type);
    testing::add(s_fn, "fn_param_wrong_order_one_of_many_recovers", &fn_param_wrong_order_one_of_many_recovers);
    testing::add(s_fn, "fn_param_comptime_only_no_diag", &fn_param_comptime_only_no_diag);
    testing::add(s_fn, "fn_param_const_only_no_diag", &fn_param_const_only_no_diag);
    testing::add(s_fn, "fn_param_two_wrong_order_two_diags", &fn_param_two_wrong_order_two_diags);

    u8[] s_local_var_decl = "Parser Local VarDecls";
    testing::add(s_local_var_decl, "local_var_decl_basic", &local_var_decl_basic);
    testing::add(s_local_var_decl, "local_var_decl_const", &local_var_decl_const);
    testing::add(s_local_var_decl, "local_var_decl_no_init", &local_var_decl_no_init);
    testing::add(s_local_var_decl, "local_var_decl_pointer_type", &local_var_decl_pointer_type);
    testing::add(s_local_var_decl, "local_var_decl_named_type", &local_var_decl_named_type);
    testing::add(s_local_var_decl, "local_var_decl_qualified_named_type", &local_var_decl_qualified_named_type);
    testing::add(s_local_var_decl, "local_var_decl_qualified_type_too_deep", &local_var_decl_qualified_type_too_deep);
    testing::add(s_local_var_decl, "local_var_decl_qualified_type_four_levels_one_diag", &local_var_decl_qualified_type_four_levels_one_diag);
    testing::add(s_local_var_decl, "fn_param_qualified_type_too_deep_recovers", &fn_param_qualified_type_too_deep_recovers);
    testing::add(s_local_var_decl, "local_var_decl_multiple", &local_var_decl_multiple);
    testing::add(s_local_var_decl, "local_var_decl_complex_init_expr", &local_var_decl_complex_init_expr);
    testing::add(s_local_var_decl, "local_var_decl_missing_semi", &local_var_decl_missing_semi);
    testing::add(s_local_var_decl, "local_var_decl_src_pos", &local_var_decl_src_pos);
    testing::add(s_local_var_decl, "local_var_decl_src_pos_on_const", &local_var_decl_src_pos_on_const);
    testing::add(s_local_var_decl, "local_var_decl_empty_body", &local_var_decl_empty_body);
    testing::add(s_local_var_decl, "local_var_decl_fn_ptr_type", &local_var_decl_fn_ptr_type);
    testing::add(s_local_var_decl, "local_var_decl_slice_type", &local_var_decl_slice_type);
    testing::add(s_local_var_decl, "local_var_decl_array_type", &local_var_decl_array_type);
    testing::add(s_local_var_decl, "local_var_decl_struct_lit_init", &local_var_decl_struct_lit_init);
    testing::add(s_local_var_decl, "local_var_decl_struct_lit_designated_init", &local_var_decl_struct_lit_designated_init);
    testing::add(s_local_var_decl, "local_var_decl_array_lit_init", &local_var_decl_array_lit_init);
    testing::add(s_local_var_decl, "local_var_decl_cast_init", &local_var_decl_cast_init);
    testing::add(s_local_var_decl, "local_var_decl_call_init", &local_var_decl_call_init);
    testing::add(s_local_var_decl, "local_var_decl_undefined_init", &local_var_decl_undefined_init);
    testing::add(s_local_var_decl, "local_var_decl_dispatch_falls_through_on_no_ident", &local_var_decl_dispatch_falls_through_on_no_ident);
    testing::add(s_local_var_decl, "local_var_decl_export_rejected", &local_var_decl_export_rejected);

    u8[] s_es = "Parser ExprStmts";
    testing::add(s_es, "expr_stmt_bare_call", &expr_stmt_bare_call);
    testing::add(s_es, "expr_stmt_call_with_args", &expr_stmt_call_with_args);
    testing::add(s_es, "expr_stmt_method_chain_call", &expr_stmt_method_chain_call);
    testing::add(s_es, "expr_stmt_assignment_plain", &expr_stmt_assignment_plain);
    testing::add(s_es, "expr_stmt_assignment_compound_plus_eq", &expr_stmt_assignment_compound_plus_eq);
    testing::add(s_es, "expr_stmt_assignment_compound_star_eq", &expr_stmt_assignment_compound_star_eq);
    testing::add(s_es, "expr_stmt_assignment_compound_amp_eq", &expr_stmt_assignment_compound_amp_eq);
    testing::add(s_es, "expr_stmt_assignment_compound_minus_eq", &expr_stmt_assignment_compound_minus_eq);
    testing::add(s_es, "expr_stmt_assignment_compound_slash_eq", &expr_stmt_assignment_compound_slash_eq);
    testing::add(s_es, "expr_stmt_assignment_compound_percent_eq", &expr_stmt_assignment_compound_percent_eq);
    testing::add(s_es, "expr_stmt_assignment_compound_pipe_eq", &expr_stmt_assignment_compound_pipe_eq);
    testing::add(s_es, "expr_stmt_assignment_compound_caret_eq", &expr_stmt_assignment_compound_caret_eq);
    testing::add(s_es, "expr_stmt_bare_deref", &expr_stmt_bare_deref);
    testing::add(s_es, "expr_stmt_capitalized_call", &expr_stmt_capitalized_call);
    testing::add(s_es, "expr_stmt_assignment_index_lhs", &expr_stmt_assignment_index_lhs);
    testing::add(s_es, "expr_stmt_assignment_deref_lhs", &expr_stmt_assignment_deref_lhs);
    testing::add(s_es, "expr_stmt_assignment_member_lhs", &expr_stmt_assignment_member_lhs);
    testing::add(s_es, "expr_stmt_bare_literal", &expr_stmt_bare_literal);
    testing::add(s_es, "expr_stmt_bare_ident", &expr_stmt_bare_ident);
    testing::add(s_es, "expr_stmt_missing_semi", &expr_stmt_missing_semi);
    testing::add(s_es, "expr_stmt_two_consecutive_calls", &expr_stmt_two_consecutive_calls);
    testing::add(s_es, "expr_stmt_mixed_with_var_decl_and_return", &expr_stmt_mixed_with_var_decl_and_return);
    testing::add(s_es, "expr_stmt_assignment_to_namespaced_lhs", &expr_stmt_assignment_to_namespaced_lhs);
    testing::add(s_es, "expr_stmt_cast", &expr_stmt_cast);

    u8[] s_block = "Parser Blocks";
    testing::add(s_block, "block_empty_inner", &block_empty_inner);
    testing::add(s_block, "block_inner_single_stmt", &block_inner_single_stmt);
    testing::add(s_block, "block_two_sibling_inner_blocks", &block_two_sibling_inner_blocks);
    testing::add(s_block, "block_triple_nested", &block_triple_nested);
    testing::add(s_block, "block_mixed_stmts_and_inner", &block_mixed_stmts_and_inner);
    testing::add(s_block, "block_inner_error_propagates", &block_inner_error_propagates);
    testing::add(s_block, "block_unclosed_inner", &block_unclosed_inner);
    testing::add(s_block, "block_src_pos_on_inner_lbrace", &block_src_pos_on_inner_lbrace);
    testing::add(s_block, "block_deeply_nested_var", &block_deeply_nested_var);
    testing::add(s_block, "block_clean_outer_no_error_flag", &block_clean_outer_no_error_flag);
    testing::add(s_block, "block_inner_multi_stmt", &block_inner_multi_stmt);
    testing::add(s_block, "block_sibling_error_isolation", &block_sibling_error_isolation);
    testing::add(s_block, "block_outer_src_pos", &block_outer_src_pos);
    testing::add(s_block, "block_recovery_resumes_outer", &block_recovery_resumes_outer);
    testing::add(s_block, "block_many_stmts_growth", &block_many_stmts_growth);
    testing::add(s_block, "block_multiple_garbage_tokens", &block_multiple_garbage_tokens);
    testing::add(s_block, "block_all_error_stmts", &block_all_error_stmts);
    testing::add(s_block, "block_error_interleaved_with_valid", &block_error_interleaved_with_valid);
    testing::add(s_block, "block_unrecognized_leading_token", &block_unrecognized_leading_token);
    testing::add(s_block, "block_unclosed_inner_at_eof", &block_unclosed_inner_at_eof);
    testing::add(s_block, "block_no_lbrace_returns_error", &block_no_lbrace_returns_error);

    u8[] s_ret = "Parser Returns";
    testing::add(s_ret, "return_bare", &return_bare);
    testing::add(s_ret, "return_intlit", &return_intlit);
    testing::add(s_ret, "return_ident", &return_ident);
    testing::add(s_ret, "return_null", &return_null);
    testing::add(s_ret, "return_bool", &return_bool);
    testing::add(s_ret, "return_false", &return_false);
    testing::add(s_ret, "return_floatlit", &return_floatlit);
    testing::add(s_ret, "return_charlit", &return_charlit);
    testing::add(s_ret, "return_strlit", &return_strlit);
    testing::add(s_ret, "return_undefined", &return_undefined);
    testing::add(s_ret, "return_pratt_expr", &return_pratt_expr);
    testing::add(s_ret, "return_unary", &return_unary);
    testing::add(s_ret, "return_unary_bang", &return_unary_bang);
    testing::add(s_ret, "return_unary_tilde", &return_unary_tilde);
    testing::add(s_ret, "return_unary_addrof", &return_unary_addrof);
    testing::add(s_ret, "return_deref", &return_deref);
    testing::add(s_ret, "return_call", &return_call);
    testing::add(s_ret, "return_cast", &return_cast);
    testing::add(s_ret, "return_struct_lit", &return_struct_lit);
    testing::add(s_ret, "return_designated_struct_lit", &return_designated_struct_lit);
    testing::add(s_ret, "return_array_lit", &return_array_lit);
    testing::add(s_ret, "return_array_index", &return_array_index);
    testing::add(s_ret, "return_slice_range", &return_slice_range);
    testing::add(s_ret, "return_slice_range_lo_only", &return_slice_range_lo_only);
    testing::add(s_ret, "return_slice_range_hi_only", &return_slice_range_hi_only);
    testing::add(s_ret, "return_paren", &return_paren);
    testing::add(s_ret, "return_namespace_access", &return_namespace_access);
    testing::add(s_ret, "return_namespace_access_three_levels", &return_namespace_access_three_levels);
    testing::add(s_ret, "return_namespace_access_four_levels", &return_namespace_access_four_levels);
    testing::add(s_ret, "return_member_chain", &return_member_chain);
    testing::add(s_ret, "return_comparison", &return_comparison);
    testing::add(s_ret, "return_logical_and", &return_logical_and);
    testing::add(s_ret, "return_with_other_stmts", &return_with_other_stmts);
    testing::add(s_ret, "return_two_consecutive", &return_two_consecutive);
    testing::add(s_ret, "return_inside_nested_block", &return_inside_nested_block);
    testing::add(s_ret, "return_in_middle_of_block", &return_in_middle_of_block);
    testing::add(s_ret, "return_trailing_tokens_before_semi", &return_trailing_tokens_before_semi);
    testing::add(s_ret, "return_src_pos", &return_src_pos);
    testing::add(s_ret, "return_missing_semi", &return_missing_semi);
    testing::add(s_ret, "return_missing_semi_at_eof", &return_missing_semi_at_eof);
    testing::add(s_ret, "return_missing_expr_no_semi", &return_missing_expr_no_semi);
    testing::add(s_ret, "return_unary_no_operand", &return_unary_no_operand);
    testing::add(s_ret, "return_malformed_expr", &return_malformed_expr);

    u8[] s_if = "Parser Ifs";
    testing::add(s_if, "if_basic_no_else", &if_basic_no_else);
    testing::add(s_if, "if_else", &if_else);
    testing::add(s_if, "if_else_if", &if_else_if);
    testing::add(s_if, "if_else_if_else", &if_else_if_else);
    testing::add(s_if, "if_chain_three", &if_chain_three);
    testing::add(s_if, "if_chain_no_terminal_else", &if_chain_no_terminal_else);
    testing::add(s_if, "if_cond_pratt", &if_cond_pratt);
    testing::add(s_if, "if_cond_call", &if_cond_call);
    testing::add(s_if, "if_cond_logical", &if_cond_logical);
    testing::add(s_if, "if_cond_comparison", &if_cond_comparison);
    testing::add(s_if, "if_cond_unary", &if_cond_unary);
    testing::add(s_if, "if_cond_bool_literal", &if_cond_bool_literal);
    testing::add(s_if, "if_then_body_multi_stmts", &if_then_body_multi_stmts);
    testing::add(s_if, "if_else_body_multi_stmts", &if_else_body_multi_stmts);
    testing::add(s_if, "if_nested", &if_nested);
    testing::add(s_if, "if_else_in_then_body", &if_else_in_then_body);
    testing::add(s_if, "if_else_body_with_nested_if", &if_else_body_with_nested_if);
    testing::add(s_if, "if_body_contains_nested_block", &if_body_contains_nested_block);
    testing::add(s_if, "if_combined_with_var_and_return", &if_combined_with_var_and_return);
    testing::add(s_if, "if_recovery_continues", &if_recovery_continues);
    testing::add(s_if, "if_two_consecutive_at_same_level", &if_two_consecutive_at_same_level);
    testing::add(s_if, "if_src_pos", &if_src_pos);
    testing::add(s_if, "if_else_if_src_pos", &if_else_if_src_pos);
    testing::add(s_if, "if_missing_lparen", &if_missing_lparen);
    testing::add(s_if, "if_missing_rparen", &if_missing_rparen);
    testing::add(s_if, "if_missing_then_block", &if_missing_then_block);
    testing::add(s_if, "if_empty_cond", &if_empty_cond);
    testing::add(s_if, "if_else_missing_block", &if_else_missing_block);
    testing::add(s_if, "if_else_block_missing_at_eof", &if_else_block_missing_at_eof);
    testing::add(s_if, "if_else_if_missing_lparen", &if_else_if_missing_lparen);
    testing::add(s_if, "if_else_if_missing_rparen", &if_else_if_missing_rparen);
    testing::add(s_if, "if_else_if_missing_then_block", &if_else_if_missing_then_block);
    testing::add(s_if, "if_body_error_propagates", &if_body_error_propagates);
    testing::add(s_if, "if_else_without_if", &if_else_without_if);
    testing::add(s_if, "if_double_else", &if_double_else);
    testing::add(s_if, "if_malformed_cond", &if_malformed_cond);

    u8[] s_while = "Parser Whiles";
    testing::add(s_while, "while_basic", &while_basic);
    testing::add(s_while, "while_cond_pratt", &while_cond_pratt);
    testing::add(s_while, "while_cond_call", &while_cond_call);
    testing::add(s_while, "while_cond_logical", &while_cond_logical);
    testing::add(s_while, "while_cond_comparison", &while_cond_comparison);
    testing::add(s_while, "while_cond_unary", &while_cond_unary);
    testing::add(s_while, "while_cond_bool_literal", &while_cond_bool_literal);
    testing::add(s_while, "while_body_multi_stmts", &while_body_multi_stmts);
    testing::add(s_while, "while_body_contains_nested_block", &while_body_contains_nested_block);
    testing::add(s_while, "while_body_contains_if", &while_body_contains_if);
    testing::add(s_while, "while_body_contains_return", &while_body_contains_return);
    testing::add(s_while, "while_nested", &while_nested);
    testing::add(s_while, "while_combined_with_var_and_return", &while_combined_with_var_and_return);
    testing::add(s_while, "while_two_consecutive_at_same_level", &while_two_consecutive_at_same_level);
    testing::add(s_while, "while_src_pos", &while_src_pos);
    testing::add(s_while, "while_missing_lparen", &while_missing_lparen);
    testing::add(s_while, "while_missing_rparen", &while_missing_rparen);
    testing::add(s_while, "while_missing_body", &while_missing_body);
    testing::add(s_while, "while_empty_cond", &while_empty_cond);
    testing::add(s_while, "while_malformed_cond", &while_malformed_cond);
    testing::add(s_while, "while_inside_if_body", &while_inside_if_body);
    testing::add(s_while, "while_recovery_continues", &while_recovery_continues);
    testing::add(s_while, "while_else_not_consumed", &while_else_not_consumed);
    testing::add(s_while, "while_body_error_propagates", &while_body_error_propagates);

    u8[] s_for = "Parser Fors";
    testing::add(s_for, "for_basic_full", &for_basic_full);
    testing::add(s_for, "for_empty_all", &for_empty_all);
    testing::add(s_for, "for_empty_init", &for_empty_init);
    testing::add(s_for, "for_empty_cond", &for_empty_cond);
    testing::add(s_for, "for_empty_post", &for_empty_post);
    testing::add(s_for, "for_empty_init_cond", &for_empty_init_cond);
    testing::add(s_for, "for_empty_init_post", &for_empty_init_post);
    testing::add(s_for, "for_empty_cond_post", &for_empty_cond_post);
    testing::add(s_for, "for_init_var_decl_no_init_expr", &for_init_var_decl_no_init_expr);
    testing::add(s_for, "for_init_const_var_decl", &for_init_const_var_decl);
    testing::add(s_for, "for_init_pointer_type", &for_init_pointer_type);
    testing::add(s_for, "for_init_slice_type", &for_init_slice_type);
    testing::add(s_for, "for_init_array_type", &for_init_array_type);
    testing::add(s_for, "for_init_named_type", &for_init_named_type);
    testing::add(s_for, "for_init_qualified_named_type", &for_init_qualified_named_type);
    testing::add(s_for, "for_init_fn_ptr_type", &for_init_fn_ptr_type);
    testing::add(s_for, "for_init_var_decl_struct_lit_init", &for_init_var_decl_struct_lit_init);
    testing::add(s_for, "for_init_var_decl_array_lit_init", &for_init_var_decl_array_lit_init);
    testing::add(s_for, "for_init_var_decl_cast_init", &for_init_var_decl_cast_init);
    testing::add(s_for, "for_init_var_decl_call_init", &for_init_var_decl_call_init);
    testing::add(s_for, "for_init_var_decl_undefined", &for_init_var_decl_undefined);
    testing::add(s_for, "for_init_assign_eq", &for_init_assign_eq);
    testing::add(s_for, "for_init_assign_plus_eq", &for_init_assign_plus_eq);
    testing::add(s_for, "for_init_assign_minus_eq", &for_init_assign_minus_eq);
    testing::add(s_for, "for_init_assign_star_eq", &for_init_assign_star_eq);
    testing::add(s_for, "for_init_assign_slash_eq", &for_init_assign_slash_eq);
    testing::add(s_for, "for_init_assign_percent_eq", &for_init_assign_percent_eq);
    testing::add(s_for, "for_init_assign_amp_eq", &for_init_assign_amp_eq);
    testing::add(s_for, "for_init_assign_pipe_eq", &for_init_assign_pipe_eq);
    testing::add(s_for, "for_init_assign_caret_eq", &for_init_assign_caret_eq);
    testing::add(s_for, "for_init_assign_member_lhs", &for_init_assign_member_lhs);
    testing::add(s_for, "for_init_assign_index_lhs", &for_init_assign_index_lhs);
    testing::add(s_for, "for_init_assign_deref_lhs", &for_init_assign_deref_lhs);
    testing::add(s_for, "for_init_assign_complex_rhs", &for_init_assign_complex_rhs);
    testing::add(s_for, "for_init_bare_call_expr", &for_init_bare_call_expr);
    testing::add(s_for, "for_init_bare_ident", &for_init_bare_ident);
    testing::add(s_for, "for_cond_ident", &for_cond_ident);
    testing::add(s_for, "for_cond_bool_literal", &for_cond_bool_literal);
    testing::add(s_for, "for_cond_pratt", &for_cond_pratt);
    testing::add(s_for, "for_cond_comparison", &for_cond_comparison);
    testing::add(s_for, "for_cond_logical", &for_cond_logical);
    testing::add(s_for, "for_cond_call", &for_cond_call);
    testing::add(s_for, "for_cond_unary", &for_cond_unary);
    testing::add(s_for, "for_cond_member_access", &for_cond_member_access);
    testing::add(s_for, "for_post_assign_eq", &for_post_assign_eq);
    testing::add(s_for, "for_post_assign_plus_eq", &for_post_assign_plus_eq);
    testing::add(s_for, "for_post_assign_minus_eq", &for_post_assign_minus_eq);
    testing::add(s_for, "for_post_assign_star_eq", &for_post_assign_star_eq);
    testing::add(s_for, "for_post_assign_slash_eq", &for_post_assign_slash_eq);
    testing::add(s_for, "for_post_assign_percent_eq", &for_post_assign_percent_eq);
    testing::add(s_for, "for_post_assign_amp_eq", &for_post_assign_amp_eq);
    testing::add(s_for, "for_post_assign_pipe_eq", &for_post_assign_pipe_eq);
    testing::add(s_for, "for_post_assign_caret_eq", &for_post_assign_caret_eq);
    testing::add(s_for, "for_post_member_assign", &for_post_member_assign);
    testing::add(s_for, "for_post_index_assign", &for_post_index_assign);
    testing::add(s_for, "for_post_deref_assign", &for_post_deref_assign);
    testing::add(s_for, "for_post_bare_call", &for_post_bare_call);
    testing::add(s_for, "for_post_complex_rhs", &for_post_complex_rhs);
    testing::add(s_for, "for_body_multi_stmts", &for_body_multi_stmts);
    testing::add(s_for, "for_body_nested_block", &for_body_nested_block);
    testing::add(s_for, "for_body_with_if", &for_body_with_if);
    testing::add(s_for, "for_body_with_while", &for_body_with_while);
    testing::add(s_for, "for_body_with_return", &for_body_with_return);
    testing::add(s_for, "for_nested", &for_nested);
    testing::add(s_for, "for_inside_if", &for_inside_if);
    testing::add(s_for, "for_inside_while", &for_inside_while);
    testing::add(s_for, "for_two_consecutive", &for_two_consecutive);
    testing::add(s_for, "for_combined_with_var_and_return", &for_combined_with_var_and_return);
    testing::add(s_for, "for_src_pos", &for_src_pos);
    testing::add(s_for, "for_init_src_pos_var_decl", &for_init_src_pos_var_decl);
    testing::add(s_for, "for_init_src_pos_assign", &for_init_src_pos_assign);
    testing::add(s_for, "for_body_src_pos", &for_body_src_pos);
    testing::add(s_for, "for_missing_lparen", &for_missing_lparen);
    testing::add(s_for, "for_missing_first_semi_var_decl", &for_missing_first_semi_var_decl);
    testing::add(s_for, "for_missing_first_semi_assign", &for_missing_first_semi_assign);
    testing::add(s_for, "for_missing_first_semi_bare_expr", &for_missing_first_semi_bare_expr);
    testing::add(s_for, "for_missing_second_semi", &for_missing_second_semi);
    testing::add(s_for, "for_missing_rparen", &for_missing_rparen);
    testing::add(s_for, "for_missing_body", &for_missing_body);
    testing::add(s_for, "for_malformed_init_expr", &for_malformed_init_expr);
    testing::add(s_for, "for_malformed_cond", &for_malformed_cond);
    testing::add(s_for, "for_malformed_post", &for_malformed_post);
    testing::add(s_for, "for_body_error_propagates", &for_body_error_propagates);
    testing::add(s_for, "for_recovery_continues", &for_recovery_continues);
    testing::add(s_for, "for_recovery_continues_after_error", &for_recovery_continues_after_error);
    testing::add(s_for, "for_else_not_consumed", &for_else_not_consumed);
    testing::add(s_for, "for_bare_keyword_only", &for_bare_keyword_only);
    testing::add(s_for, "for_cond_src_pos", &for_cond_src_pos);
    testing::add(s_for, "for_post_src_pos", &for_post_src_pos);
    testing::add(s_for, "for_init_bare_binop", &for_init_bare_binop);
    testing::add(s_for, "for_init_bare_member_access", &for_init_bare_member_access);
    testing::add(s_for, "for_init_paren_lhs_assign", &for_init_paren_lhs_assign);
    testing::add(s_for, "for_cond_namespace_access", &for_cond_namespace_access);
    testing::add(s_for, "for_cond_cast", &for_cond_cast);
    testing::add(s_for, "for_cond_array_index", &for_cond_array_index);
    testing::add(s_for, "for_cond_chained_postfix", &for_cond_chained_postfix);
    testing::add(s_for, "for_post_bare_binop", &for_post_bare_binop);
    testing::add(s_for, "for_post_bare_ident", &for_post_bare_ident);
    testing::add(s_for, "for_multi_errors", &for_multi_errors);
    testing::add(s_for, "for_unclosed_body_at_eof", &for_unclosed_body_at_eof);
    testing::add(s_for, "for_at_eof", &for_at_eof);
    testing::add(s_for, "for_init_var_decl_pointer_to_pointer", &for_init_var_decl_pointer_to_pointer);

    u8[] s_bc = "Parser Break/Continue";
    testing::add(s_bc, "break_basic", &break_basic);
    testing::add(s_bc, "continue_basic", &continue_basic);
    testing::add(s_bc, "break_in_while", &break_in_while);
    testing::add(s_bc, "break_in_for", &break_in_for);
    testing::add(s_bc, "continue_in_while", &continue_in_while);
    testing::add(s_bc, "continue_in_for", &continue_in_for);
    testing::add(s_bc, "break_in_nested_if", &break_in_nested_if);
    testing::add(s_bc, "continue_in_nested_if", &continue_in_nested_if);
    testing::add(s_bc, "break_in_nested_loop", &break_in_nested_loop);
    testing::add(s_bc, "break_in_bare_block", &break_in_bare_block);
    testing::add(s_bc, "break_then_other_stmt", &break_then_other_stmt);
    testing::add(s_bc, "multiple_breaks", &multiple_breaks);
    testing::add(s_bc, "break_continue_sequence", &break_continue_sequence);
    testing::add(s_bc, "break_src_pos", &break_src_pos);
    testing::add(s_bc, "continue_src_pos", &continue_src_pos);
    testing::add(s_bc, "break_missing_semi", &break_missing_semi);
    testing::add(s_bc, "continue_missing_semi", &continue_missing_semi);
    testing::add(s_bc, "break_extra_token", &break_extra_token);
    testing::add(s_bc, "break_at_eof", &break_at_eof);
    testing::add(s_bc, "continue_at_eof", &continue_at_eof);
    testing::add(s_bc, "break_recovery_continues", &break_recovery_continues);
    testing::add(s_bc, "continue_in_bare_block", &continue_in_bare_block);
    testing::add(s_bc, "continue_in_nested_loop", &continue_in_nested_loop);
    testing::add(s_bc, "continue_then_other_stmt", &continue_then_other_stmt);
    testing::add(s_bc, "multiple_continues", &multiple_continues);
    testing::add(s_bc, "continue_extra_token", &continue_extra_token);
    testing::add(s_bc, "continue_recovery_continues", &continue_recovery_continues);
    testing::add(s_bc, "break_in_else_branch", &break_in_else_branch);
    testing::add(s_bc, "continue_in_else_branch", &continue_in_else_branch);

    u8[] s_un = "Parser Unions";
    testing::add(s_un, "union_empty", &union_empty);
    testing::add(s_un, "union_single_field", &union_single_field);
    testing::add(s_un, "union_multi_field", &union_multi_field);
    testing::add(s_un, "union_field_pointer_type", &union_field_pointer_type);
    testing::add(s_un, "union_field_array_type", &union_field_array_type);
    testing::add(s_un, "union_field_named_type", &union_field_named_type);
    testing::add(s_un, "union_field_qualified_type", &union_field_qualified_type);
    testing::add(s_un, "union_field_fn_ptr_type", &union_field_fn_ptr_type);
    testing::add(s_un, "union_field_nested_anon_union_rejected", &union_field_nested_anon_union_rejected);
    testing::add(s_un, "union_field_anon_struct_rejected", &union_field_anon_struct_rejected);
    testing::add(s_un, "union_exported", &union_exported);
    testing::add(s_un, "union_many_fields_growth", &union_many_fields_growth);
    testing::add(s_un, "anon_union_in_alias", &anon_union_in_alias);
    testing::add(s_un, "anon_union_in_var_decl_rejected", &anon_union_in_var_decl_rejected);
    testing::add(s_un, "anon_union_in_fn_param_rejected", &anon_union_in_fn_param_rejected);
    testing::add(s_un, "anon_union_in_alias_body_error_propagates", &anon_union_in_alias_body_error_propagates);
    testing::add(s_un, "anon_union_empty", &anon_union_empty);
    testing::add(s_un, "union_lit_via_struct_lit_syntax", &union_lit_via_struct_lit_syntax);
    testing::add(s_un, "union_src_pos", &union_src_pos);
    testing::add(s_un, "union_field_src_pos", &union_field_src_pos);
    testing::add(s_un, "union_missing_name", &union_missing_name);
    testing::add(s_un, "union_missing_lbrace", &union_missing_lbrace);
    testing::add(s_un, "union_missing_rbrace_at_eof", &union_missing_rbrace_at_eof);
    testing::add(s_un, "union_field_missing_name", &union_field_missing_name);
    testing::add(s_un, "union_field_missing_semi", &union_field_missing_semi);
    testing::add(s_un, "anon_union_missing_lbrace_at_type_pos", &anon_union_missing_lbrace_at_type_pos);
    testing::add(s_un, "union_recovery_continues", &union_recovery_continues);

    u8[] s_st = "Parser Structs";
    testing::add(s_st, "struct_empty", &struct_empty);
    testing::add(s_st, "struct_single_field", &struct_single_field);
    testing::add(s_st, "struct_multi_field", &struct_multi_field);
    testing::add(s_st, "struct_field_pointer_type", &struct_field_pointer_type);
    testing::add(s_st, "struct_field_array_type", &struct_field_array_type);
    testing::add(s_st, "struct_field_named_type", &struct_field_named_type);
    testing::add(s_st, "struct_field_qualified_type", &struct_field_qualified_type);
    testing::add(s_st, "struct_field_fn_ptr_type", &struct_field_fn_ptr_type);
    testing::add(s_st, "struct_field_nested_anon_struct_rejected", &struct_field_nested_anon_struct_rejected);
    testing::add(s_st, "struct_field_nested_dot_anon_rejected", &struct_field_nested_dot_anon_rejected);
    testing::add(s_st, "struct_exported", &struct_exported);
    testing::add(s_st, "struct_many_fields_growth", &struct_many_fields_growth);
    testing::add(s_st, "anon_struct_in_alias_legacy", &anon_struct_in_alias_legacy);
    testing::add(s_st, "anon_struct_in_alias_dot", &anon_struct_in_alias_dot);
    testing::add(s_st, "anon_struct_in_var_decl_dot_rejected", &anon_struct_in_var_decl_dot_rejected);
    testing::add(s_st, "anon_struct_in_fn_param_dot_rejected", &anon_struct_in_fn_param_dot_rejected);
    testing::add(s_st, "anon_struct_in_alias_body_error_propagates", &anon_struct_in_alias_body_error_propagates);
    testing::add(s_st, "anon_struct_in_alias_unclosed_brace_propagates", &anon_struct_in_alias_unclosed_brace_propagates);
    testing::add(s_st, "anon_struct_dot_in_alias_body_error_propagates", &anon_struct_dot_in_alias_body_error_propagates);
    testing::add(s_st, "anon_struct_in_fn_return_type_rejected", &anon_struct_in_fn_return_type_rejected);
    testing::add(s_st, "anon_struct_nested_in_alias_rejected", &anon_struct_nested_in_alias_rejected);
    testing::add(s_st, "anon_struct_in_cast_target_rejected", &anon_struct_in_cast_target_rejected);
    testing::add(s_st, "anon_struct_behind_pointer_rejected", &anon_struct_behind_pointer_rejected);
    testing::add(s_st, "anon_struct_in_extern_fn_return_rejected", &anon_struct_in_extern_fn_return_rejected);
    testing::add(s_st, "anon_two_decls_two_diags", &anon_two_decls_two_diags);
    testing::add(s_st, "anon_struct_empty_dot", &anon_struct_empty_dot);
    testing::add(s_st, "struct_src_pos", &struct_src_pos);
    testing::add(s_st, "struct_field_src_pos", &struct_field_src_pos);
    testing::add(s_st, "struct_missing_name", &struct_missing_name);
    testing::add(s_st, "struct_missing_lbrace", &struct_missing_lbrace);
    testing::add(s_st, "struct_missing_rbrace_at_eof", &struct_missing_rbrace_at_eof);
    testing::add(s_st, "struct_field_missing_name", &struct_field_missing_name);
    testing::add(s_st, "struct_field_missing_semi", &struct_field_missing_semi);
    testing::add(s_st, "struct_recovery_continues", &struct_recovery_continues);
    testing::add(s_st, "struct_no_progress_safety", &struct_no_progress_safety);
    testing::add(s_st, "dot_struct_dot_not_followed_by_lbrace", &dot_struct_dot_not_followed_by_lbrace);

    u8[] s_al = "Parser Aliases";
    testing::add(s_al, "alias_primitive_rhs", &alias_primitive_rhs);
    testing::add(s_al, "alias_named_rhs", &alias_named_rhs);
    testing::add(s_al, "alias_qualified_named_rhs", &alias_qualified_named_rhs);
    testing::add(s_al, "alias_pointer_rhs", &alias_pointer_rhs);
    testing::add(s_al, "alias_slice_rhs", &alias_slice_rhs);
    testing::add(s_al, "alias_array_rhs", &alias_array_rhs);
    testing::add(s_al, "alias_fn_ptr_rhs", &alias_fn_ptr_rhs);
    testing::add(s_al, "alias_exported", &alias_exported);
    testing::add(s_al, "alias_multiple_in_file", &alias_multiple_in_file);
    testing::add(s_al, "alias_mixed_with_other_decls", &alias_mixed_with_other_decls);
    testing::add(s_al, "alias_src_pos", &alias_src_pos);
    testing::add(s_al, "alias_exported_src_pos", &alias_exported_src_pos);
    testing::add(s_al, "alias_missing_name", &alias_missing_name);
    testing::add(s_al, "alias_missing_eq", &alias_missing_eq);
    testing::add(s_al, "alias_missing_type", &alias_missing_type);
    testing::add(s_al, "alias_missing_semi", &alias_missing_semi);
    testing::add(s_al, "alias_at_eof", &alias_at_eof);
    testing::add(s_al, "alias_export_preserved_through_error", &alias_export_preserved_through_error);
    testing::add(s_al, "alias_exported_qualified_rhs", &alias_exported_qualified_rhs);
    testing::add(s_al, "alias_recovery_continues", &alias_recovery_continues);

    u8[] s_cc = "Parser Compcode";
    testing::add(s_cc, "compcode_in_var_decl_init", &compcode_in_var_decl_init);
    testing::add(s_cc, "compcode_in_return", &compcode_in_return);
    testing::add(s_cc, "compcode_in_compsplice_arg", &compcode_in_compsplice_arg);
    testing::add(s_cc, "compcode_in_compinsert_arg", &compcode_in_compinsert_arg);
    testing::add(s_cc, "compcode_in_call_arg", &compcode_in_call_arg);
    testing::add(s_cc, "compcode_as_if_cond", &compcode_as_if_cond);
    testing::add(s_cc, "compcode_as_switch_disc", &compcode_as_switch_disc);
    testing::add(s_cc, "compcode_in_paren", &compcode_in_paren);
    testing::add(s_cc, "compcode_empty_body", &compcode_empty_body);
    testing::add(s_cc, "compcode_multi_stmt_body", &compcode_multi_stmt_body);
    testing::add(s_cc, "compcode_body_with_control_flow", &compcode_body_with_control_flow);
    testing::add(s_cc, "compcode_nested", &compcode_nested);
    testing::add(s_cc, "compcode_src_pos", &compcode_src_pos);
    testing::add(s_cc, "compcode_body_src_pos", &compcode_body_src_pos);
    testing::add(s_cc, "compcode_missing_lbrace", &compcode_missing_lbrace);
    testing::add(s_cc, "compcode_unclosed_body_at_eof", &compcode_unclosed_body_at_eof);
    testing::add(s_cc, "compcode_body_error_propagates", &compcode_body_error_propagates);

    u8[] s_cs = "Parser Compsplice";
    testing::add(s_cs, "compsplice_ident_arg", &compsplice_ident_arg);
    testing::add(s_cs, "compsplice_call_arg", &compsplice_call_arg);
    testing::add(s_cs, "compsplice_namespace_arg", &compsplice_namespace_arg);
    testing::add(s_cs, "compsplice_pratt_arg", &compsplice_pratt_arg);
    testing::add(s_cs, "compsplice_in_bare_block", &compsplice_in_bare_block);
    testing::add(s_cs, "compsplice_in_defer_single_stmt", &compsplice_in_defer_single_stmt);
    testing::add(s_cs, "compsplice_full_comp_family_sequence", &compsplice_full_comp_family_sequence);
    testing::add(s_cs, "compsplice_src_pos", &compsplice_src_pos);
    testing::add(s_cs, "compsplice_arg_src_pos", &compsplice_arg_src_pos);
    testing::add(s_cs, "compsplice_just_semi", &compsplice_just_semi);
    testing::add(s_cs, "compsplice_at_eof", &compsplice_at_eof);
    testing::add(s_cs, "compsplice_missing_semi", &compsplice_missing_semi);
    testing::add(s_cs, "compsplice_malformed_expr", &compsplice_malformed_expr);
    testing::add(s_cs, "compsplice_recovery_continues", &compsplice_recovery_continues);

    u8[] s_ci = "Parser Compinsert";
    testing::add(s_ci, "compinsert_string_arg", &compinsert_string_arg);
    testing::add(s_ci, "compinsert_intlit_arg", &compinsert_intlit_arg);
    testing::add(s_ci, "compinsert_ident_arg", &compinsert_ident_arg);
    testing::add(s_ci, "compinsert_pratt_arg", &compinsert_pratt_arg);
    testing::add(s_ci, "compinsert_call_arg", &compinsert_call_arg);
    testing::add(s_ci, "compinsert_in_bare_block", &compinsert_in_bare_block);
    testing::add(s_ci, "compinsert_in_defer_single_stmt", &compinsert_in_defer_single_stmt);
    testing::add(s_ci, "compinsert_comperror_compwarning_sequence", &compinsert_comperror_compwarning_sequence);
    testing::add(s_ci, "compinsert_src_pos", &compinsert_src_pos);
    testing::add(s_ci, "compinsert_arg_src_pos", &compinsert_arg_src_pos);
    testing::add(s_ci, "compinsert_missing_lparen", &compinsert_missing_lparen);
    testing::add(s_ci, "compinsert_missing_rparen", &compinsert_missing_rparen);
    testing::add(s_ci, "compinsert_missing_semi", &compinsert_missing_semi);
    testing::add(s_ci, "compinsert_empty_arg", &compinsert_empty_arg);
    testing::add(s_ci, "compinsert_at_eof", &compinsert_at_eof);
    testing::add(s_ci, "compinsert_recovery_continues", &compinsert_recovery_continues);

    u8[] s_cr = "Parser Comprun";
    testing::add(s_cr, "comprun_top_level_empty", &comprun_top_level_empty);
    testing::add(s_cr, "comprun_top_level_with_stmts", &comprun_top_level_with_stmts);
    testing::add(s_cr, "comprun_top_level_mixed_with_decls", &comprun_top_level_mixed_with_decls);
    testing::add(s_cr, "comprun_export_is_error", &comprun_export_is_error);
    testing::add(s_cr, "comprun_export_then_valid_decl_recovers", &comprun_export_then_valid_decl_recovers);
    testing::add(s_cr, "comprun_two_exports_two_diags", &comprun_two_exports_two_diags);
    testing::add(s_cr, "comprun_in_fn_empty", &comprun_in_fn_empty);
    testing::add(s_cr, "comprun_in_fn_multi_stmt", &comprun_in_fn_multi_stmt);
    testing::add(s_cr, "comprun_in_bare_block", &comprun_in_bare_block);
    testing::add(s_cr, "comprun_in_if_then", &comprun_in_if_then);
    testing::add(s_cr, "comprun_in_if_else", &comprun_in_if_else);
    testing::add(s_cr, "comprun_in_while_body", &comprun_in_while_body);
    testing::add(s_cr, "comprun_in_for_body", &comprun_in_for_body);
    testing::add(s_cr, "comprun_in_switch_arm", &comprun_in_switch_arm);
    testing::add(s_cr, "comprun_in_switch_else", &comprun_in_switch_else);
    testing::add(s_cr, "comprun_in_defer_block", &comprun_in_defer_block);
    testing::add(s_cr, "comprun_in_defer_single_stmt", &comprun_in_defer_single_stmt);
    testing::add(s_cr, "comprun_two_consecutive_top_level", &comprun_two_consecutive_top_level);
    testing::add(s_cr, "comprun_two_consecutive_in_fn", &comprun_two_consecutive_in_fn);
    testing::add(s_cr, "comprun_combined_with_var_and_return", &comprun_combined_with_var_and_return);
    testing::add(s_cr, "comprun_nested", &comprun_nested);
    testing::add(s_cr, "comprun_body_with_control_flow", &comprun_body_with_control_flow);
    testing::add(s_cr, "comprun_src_pos_top_level", &comprun_src_pos_top_level);
    testing::add(s_cr, "comprun_src_pos_in_fn", &comprun_src_pos_in_fn);
    testing::add(s_cr, "comprun_body_src_pos", &comprun_body_src_pos);
    testing::add(s_cr, "comprun_missing_lbrace_top_level", &comprun_missing_lbrace_top_level);
    testing::add(s_cr, "comprun_missing_lbrace_in_fn", &comprun_missing_lbrace_in_fn);
    testing::add(s_cr, "comprun_unclosed_body_at_eof", &comprun_unclosed_body_at_eof);
    testing::add(s_cr, "comprun_body_error_propagates", &comprun_body_error_propagates);
    testing::add(s_cr, "comprun_at_eof", &comprun_at_eof);
    testing::add(s_cr, "comprun_recovery_continues_top_level", &comprun_recovery_continues_top_level);
    testing::add(s_cr, "comprun_recovery_continues_in_fn", &comprun_recovery_continues_in_fn);

    u8[] s_ce = "Parser Comperror/Compwarning";
    testing::add(s_ce, "comperror_string_arg", &comperror_string_arg);
    testing::add(s_ce, "comperror_intlit_arg", &comperror_intlit_arg);
    testing::add(s_ce, "comperror_ident_arg", &comperror_ident_arg);
    testing::add(s_ce, "comperror_namespace_arg", &comperror_namespace_arg);
    testing::add(s_ce, "comperror_pratt_arg", &comperror_pratt_arg);
    testing::add(s_ce, "comperror_call_arg", &comperror_call_arg);
    testing::add(s_ce, "comperror_in_bare_block", &comperror_in_bare_block);
    testing::add(s_ce, "comperror_in_if_then", &comperror_in_if_then);
    testing::add(s_ce, "comperror_in_if_else", &comperror_in_if_else);
    testing::add(s_ce, "comperror_in_while_body", &comperror_in_while_body);
    testing::add(s_ce, "comperror_in_for_body", &comperror_in_for_body);
    testing::add(s_ce, "comperror_in_switch_arm", &comperror_in_switch_arm);
    testing::add(s_ce, "comperror_in_switch_else", &comperror_in_switch_else);
    testing::add(s_ce, "comperror_in_defer_block", &comperror_in_defer_block);
    testing::add(s_ce, "comperror_two_consecutive", &comperror_two_consecutive);
    testing::add(s_ce, "comperror_combined_with_var_and_return", &comperror_combined_with_var_and_return);
    testing::add(s_ce, "comperror_src_pos", &comperror_src_pos);
    testing::add(s_ce, "comperror_arg_src_pos", &comperror_arg_src_pos);
    testing::add(s_ce, "comperror_missing_lparen", &comperror_missing_lparen);
    testing::add(s_ce, "comperror_missing_rparen", &comperror_missing_rparen);
    testing::add(s_ce, "comperror_empty_arg", &comperror_empty_arg);
    testing::add(s_ce, "comperror_missing_semi", &comperror_missing_semi);
    testing::add(s_ce, "comperror_at_eof", &comperror_at_eof);
    testing::add(s_ce, "comperror_recovery_continues", &comperror_recovery_continues);
    testing::add(s_ce, "compwarning_string_arg", &compwarning_string_arg);
    testing::add(s_ce, "compwarning_intlit_arg", &compwarning_intlit_arg);
    testing::add(s_ce, "compwarning_pratt_arg", &compwarning_pratt_arg);
    testing::add(s_ce, "compwarning_in_block", &compwarning_in_block);
    testing::add(s_ce, "compwarning_src_pos", &compwarning_src_pos);
    testing::add(s_ce, "compwarning_missing_lparen", &compwarning_missing_lparen);
    testing::add(s_ce, "compwarning_missing_semi", &compwarning_missing_semi);
    testing::add(s_ce, "compwarning_arg_src_pos", &compwarning_arg_src_pos);
    testing::add(s_ce, "compwarning_missing_rparen", &compwarning_missing_rparen);
    testing::add(s_ce, "compwarning_empty_arg", &compwarning_empty_arg);
    testing::add(s_ce, "compwarning_at_eof", &compwarning_at_eof);
    testing::add(s_ce, "compwarning_recovery_continues", &compwarning_recovery_continues);
    testing::add(s_ce, "comperror_in_defer_single_stmt", &comperror_in_defer_single_stmt);
    testing::add(s_ce, "compwarning_in_defer_single_stmt", &compwarning_in_defer_single_stmt);
    testing::add(s_ce, "comperror_then_compwarning", &comperror_then_compwarning);

    u8[] s_df = "Parser Defers";
    testing::add(s_df, "defer_block_empty", &defer_block_empty);
    testing::add(s_df, "defer_block_multi_stmt", &defer_block_multi_stmt);
    testing::add(s_df, "defer_single_body_is_synthetic_block", &defer_single_body_is_synthetic_block);
    testing::add(s_df, "defer_single_return", &defer_single_return);
    testing::add(s_df, "defer_single_continue", &defer_single_continue);
    testing::add(s_df, "defer_single_if", &defer_single_if);
    testing::add(s_df, "defer_single_while", &defer_single_while);
    testing::add(s_df, "defer_single_for", &defer_single_for);
    testing::add(s_df, "defer_single_switch", &defer_single_switch);
    testing::add(s_df, "defer_single_var_decl", &defer_single_var_decl);
    testing::add(s_df, "defer_single_const_var_decl", &defer_single_const_var_decl);
    testing::add(s_df, "defer_nested_block_in_block", &defer_nested_block_in_block);
    testing::add(s_df, "defer_nested_single_in_single", &defer_nested_single_in_single);
    testing::add(s_df, "defer_single_inside_block_body", &defer_single_inside_block_body);
    testing::add(s_df, "defer_in_bare_block", &defer_in_bare_block);
    testing::add(s_df, "defer_in_if_then", &defer_in_if_then);
    testing::add(s_df, "defer_in_else_body", &defer_in_else_body);
    testing::add(s_df, "defer_in_while_body", &defer_in_while_body);
    testing::add(s_df, "defer_in_for_body", &defer_in_for_body);
    testing::add(s_df, "defer_in_switch_arm", &defer_in_switch_arm);
    testing::add(s_df, "defer_in_switch_else", &defer_in_switch_else);
    testing::add(s_df, "defer_two_consecutive", &defer_two_consecutive);
    testing::add(s_df, "defer_combined_with_var_and_return", &defer_combined_with_var_and_return);
    testing::add(s_df, "defer_src_pos", &defer_src_pos);
    testing::add(s_df, "defer_single_synthetic_block_src_pos", &defer_single_synthetic_block_src_pos);
    testing::add(s_df, "defer_at_eof", &defer_at_eof);
    testing::add(s_df, "defer_semicolon_body", &defer_semicolon_body);
    testing::add(s_df, "defer_expr_stmt_body", &defer_expr_stmt_body);
    testing::add(s_df, "defer_block_body_error_propagates", &defer_block_body_error_propagates);
    testing::add(s_df, "defer_single_body_error_propagates", &defer_single_body_error_propagates);
    testing::add(s_df, "defer_unclosed_block_at_eof", &defer_unclosed_block_at_eof);
    testing::add(s_df, "defer_expr_stmt_then_var_decl", &defer_expr_stmt_then_var_decl);
    testing::add(s_df, "defer_call_canonical", &defer_call_canonical);

    u8[] s_sw = "Parser Switches";
    testing::add(s_sw, "switch_empty", &switch_empty);
    testing::add(s_sw, "switch_single_arm_single_label", &switch_single_arm_single_label);
    testing::add(s_sw, "switch_fallthrough_2_cases", &switch_fallthrough_2_cases);
    testing::add(s_sw, "switch_fallthrough_3_cases", &switch_fallthrough_3_cases);
    testing::add(s_sw, "switch_multiple_arms", &switch_multiple_arms);
    testing::add(s_sw, "switch_else_only", &switch_else_only);
    testing::add(s_sw, "switch_arm_and_else", &switch_arm_and_else);
    testing::add(s_sw, "switch_multi_arms_and_else", &switch_multi_arms_and_else);
    testing::add(s_sw, "switch_mixed_fallthrough_and_standalone", &switch_mixed_fallthrough_and_standalone);
    testing::add(s_sw, "switch_fallthrough_to_else", &switch_fallthrough_to_else);
    testing::add(s_sw, "switch_two_cases_fallthrough_to_else", &switch_two_cases_fallthrough_to_else);
    testing::add(s_sw, "switch_fallthrough_in_middle", &switch_fallthrough_in_middle);
    testing::add(s_sw, "switch_disc_intlit", &switch_disc_intlit);
    testing::add(s_sw, "switch_disc_member_access", &switch_disc_member_access);
    testing::add(s_sw, "switch_disc_pratt", &switch_disc_pratt);
    testing::add(s_sw, "switch_disc_call", &switch_disc_call);
    testing::add(s_sw, "switch_disc_namespace", &switch_disc_namespace);
    testing::add(s_sw, "switch_disc_namespace_three_levels", &switch_disc_namespace_three_levels);
    testing::add(s_sw, "switch_label_charlit", &switch_label_charlit);
    testing::add(s_sw, "switch_label_ident", &switch_label_ident);
    testing::add(s_sw, "switch_label_namespace_access", &switch_label_namespace_access);
    testing::add(s_sw, "switch_label_namespace_access_three_levels", &switch_label_namespace_access_three_levels);
    testing::add(s_sw, "switch_label_negative", &switch_label_negative);
    testing::add(s_sw, "switch_label_pratt", &switch_label_pratt);
    testing::add(s_sw, "switch_body_multi_stmts", &switch_body_multi_stmts);
    testing::add(s_sw, "switch_body_with_break", &switch_body_with_break);
    testing::add(s_sw, "switch_body_with_continue", &switch_body_with_continue);
    testing::add(s_sw, "switch_body_with_if", &switch_body_with_if);
    testing::add(s_sw, "switch_body_with_while", &switch_body_with_while);
    testing::add(s_sw, "switch_body_with_for", &switch_body_with_for);
    testing::add(s_sw, "switch_body_with_nested_switch", &switch_body_with_nested_switch);
    testing::add(s_sw, "switch_else_body_multi_stmts", &switch_else_body_multi_stmts);
    testing::add(s_sw, "switch_else_with_nested_switch", &switch_else_with_nested_switch);
    testing::add(s_sw, "switch_inside_if", &switch_inside_if);
    testing::add(s_sw, "switch_inside_while", &switch_inside_while);
    testing::add(s_sw, "switch_inside_for", &switch_inside_for);
    testing::add(s_sw, "switch_two_consecutive", &switch_two_consecutive);
    testing::add(s_sw, "switch_combined_with_var_and_return", &switch_combined_with_var_and_return);
    testing::add(s_sw, "switch_src_pos", &switch_src_pos);
    testing::add(s_sw, "switch_disc_src_pos", &switch_disc_src_pos);
    testing::add(s_sw, "switch_arm_src_pos", &switch_arm_src_pos);
    testing::add(s_sw, "switch_fallthrough_arm_src_pos", &switch_fallthrough_arm_src_pos);
    testing::add(s_sw, "switch_missing_lparen", &switch_missing_lparen);
    testing::add(s_sw, "switch_missing_rparen", &switch_missing_rparen);
    testing::add(s_sw, "switch_missing_lbrace", &switch_missing_lbrace);
    testing::add(s_sw, "switch_missing_rbrace_at_eof", &switch_missing_rbrace_at_eof);
    testing::add(s_sw, "switch_missing_colon", &switch_missing_colon);
    testing::add(s_sw, "switch_missing_label_expr", &switch_missing_label_expr);
    testing::add(s_sw, "switch_dangling_fallthrough_at_close", &switch_dangling_fallthrough_at_close);
    testing::add(s_sw, "switch_junk_token_in_body", &switch_junk_token_in_body);
    testing::add(s_sw, "switch_at_eof", &switch_at_eof);
    testing::add(s_sw, "switch_recovery_continues", &switch_recovery_continues);
    testing::add(s_sw, "switch_malformed_disc", &switch_malformed_disc);
    testing::add(s_sw, "switch_double_else_first_wins", &switch_double_else_first_wins);
    testing::add(s_sw, "switch_else_before_case", &switch_else_before_case);
    testing::add(s_sw, "switch_case_body_error_propagates", &switch_case_body_error_propagates);
    testing::add(s_sw, "switch_else_body_error_propagates", &switch_else_body_error_propagates);
    testing::add(s_sw, "switch_arms_growth_past_initial_cap", &switch_arms_growth_past_initial_cap);
    testing::add(s_sw, "switch_multi_errors", &switch_multi_errors);
    testing::add(s_sw, "switch_label_bool_literal", &switch_label_bool_literal);
    testing::add(s_sw, "switch_semicolon_between_cases", &switch_semicolon_between_cases);
    testing::add(s_sw, "switch_inside_else_branch", &switch_inside_else_branch);
    testing::add(s_sw, "switch_disc_cast", &switch_disc_cast);
    testing::add(s_sw, "switch_pure_fallthrough_no_terminator", &switch_pure_fallthrough_no_terminator);
    testing::add(s_sw, "switch_recovery_after_error", &switch_recovery_after_error);

    u8[] s_e = "Parser Expressions";
    testing::add(s_e, "expr_int_literal", &expr_int_literal);
    testing::add(s_e, "expr_int_literal_zero", &expr_int_literal_zero);
    testing::add(s_e, "expr_float_literal", &expr_float_literal);
    testing::add(s_e, "expr_char_literal", &expr_char_literal);
    testing::add(s_e, "expr_string_literal", &expr_string_literal);
    testing::add(s_e, "expr_bool_true", &expr_bool_true);
    testing::add(s_e, "expr_bool_false", &expr_bool_false);
    testing::add(s_e, "expr_null", &expr_null);
    testing::add(s_e, "expr_ident", &expr_ident);
    testing::add(s_e, "expr_namespace_access", &expr_namespace_access);
    testing::add(s_e, "expr_namespace_three_levels_in_call_arg", &expr_namespace_three_levels_in_call_arg);
    testing::add(s_e, "expr_namespace_three_levels_in_struct_lit", &expr_namespace_three_levels_in_struct_lit);
    testing::add(s_e, "expr_namespace_three_levels_in_binop", &expr_namespace_three_levels_in_binop);
    testing::add(s_e, "expr_namespace_three_levels_then_member_access", &expr_namespace_three_levels_then_member_access);
    testing::add(s_e, "expr_add", &expr_add);
    testing::add(s_e, "expr_precedence_plus_mul", &expr_precedence_plus_mul);
    testing::add(s_e, "expr_precedence_mul_plus", &expr_precedence_mul_plus);
    testing::add(s_e, "expr_left_associativity", &expr_left_associativity);
    testing::add(s_e, "expr_eq_and_chain", &expr_eq_and_chain);
    testing::add(s_e, "expr_pipe_amp_precedence", &expr_pipe_amp_precedence);
    testing::add(s_e, "expr_shift_lower_than_compare", &expr_shift_lower_than_compare);
    testing::add(s_e, "expr_ladder_all_ops", &expr_ladder_all_ops);
    testing::add(s_e, "expr_unary_minus", &expr_unary_minus);
    testing::add(s_e, "expr_unary_bang", &expr_unary_bang);
    testing::add(s_e, "expr_unary_tilde", &expr_unary_tilde);
    testing::add(s_e, "expr_unary_addrof", &expr_unary_addrof);
    testing::add(s_e, "expr_unary_deref", &expr_unary_deref);
    testing::add(s_e, "expr_unary_stacked", &expr_unary_stacked);
    testing::add(s_e, "expr_unary_double_deref", &expr_unary_double_deref);
    testing::add(s_e, "expr_unary_binds_tighter_than_binary", &expr_unary_binds_tighter_than_binary);
    testing::add(s_e, "expr_call_no_args", &expr_call_no_args);
    testing::add(s_e, "expr_call_with_args", &expr_call_with_args);
    testing::add(s_e, "expr_call_nested", &expr_call_nested);
    testing::add(s_e, "expr_array_index", &expr_array_index);
    testing::add(s_e, "expr_slice_range", &expr_slice_range);
    testing::add(s_e, "expr_slice_range_lo_only", &expr_slice_range_lo_only);
    testing::add(s_e, "expr_slice_range_hi_only", &expr_slice_range_hi_only);
    testing::add(s_e, "expr_slice_range_both_missing_errors", &expr_slice_range_both_missing_errors);
    testing::add(s_e, "expr_slice_range_complex_bounds", &expr_slice_range_complex_bounds);
    testing::add(s_e, "expr_slice_range_hi_only_then_member_access", &expr_slice_range_hi_only_then_member_access);
    testing::add(s_e, "expr_slice_range_lo_only_after_call", &expr_slice_range_lo_only_after_call);
    testing::add(s_e, "expr_slice_range_hi_only_in_call_arg", &expr_slice_range_hi_only_in_call_arg);
    testing::add(s_e, "expr_slice_range_lo_only_identifier", &expr_slice_range_lo_only_identifier);
    testing::add(s_e, "expr_slice_range_chained", &expr_slice_range_chained);
    testing::add(s_e, "expr_slice_range_hi_only_on_namespace_base", &expr_slice_range_hi_only_on_namespace_base);
    testing::add(s_e, "expr_member_access", &expr_member_access);
    testing::add(s_e, "expr_chained_postfix", &expr_chained_postfix);
    testing::add(s_e, "expr_chained_postfix_call_member", &expr_chained_postfix_call_member);
    testing::add(s_e, "expr_member_chain_three", &expr_member_chain_three);
    testing::add(s_e, "expr_paren_grouping", &expr_paren_grouping);
    testing::add(s_e, "expr_cast_primitive", &expr_cast_primitive);
    testing::add(s_e, "expr_cast_pointer", &expr_cast_pointer);
    testing::add(s_e, "expr_cast_then_unary", &expr_cast_then_unary);
    testing::add(s_e, "expr_paren_arith_rewinds", &expr_paren_arith_rewinds);
    testing::add(s_e, "expr_struct_lit_positional", &expr_struct_lit_positional);
    testing::add(s_e, "expr_struct_lit_designated", &expr_struct_lit_designated);
    testing::add(s_e, "expr_struct_lit_mixed_pos_designated", &expr_struct_lit_mixed_pos_designated);
    testing::add(s_e, "expr_struct_lit_trailing_comma", &expr_struct_lit_trailing_comma);
    testing::add(s_e, "expr_struct_lit_empty", &expr_struct_lit_empty);
    testing::add(s_e, "expr_array_lit", &expr_array_lit);
    testing::add(s_e, "expr_array_lit_empty", &expr_array_lit_empty);
    testing::add(s_e, "expr_combo_paren_mul", &expr_combo_paren_mul);
    testing::add(s_e, "expr_combo_call_plus_call", &expr_combo_call_plus_call);
    testing::add(s_e, "expr_combo_unary_member", &expr_combo_unary_member);
    testing::add(s_e, "expr_combo_index_plus_index", &expr_combo_index_plus_index);
    testing::add(s_e, "expr_combo_cast_then_binary", &expr_combo_cast_then_binary);
    testing::add(s_e, "expr_binop_src_pos_on_operator", &expr_binop_src_pos_on_operator);
    testing::add(s_e, "expr_unop_src_pos_on_operator", &expr_unop_src_pos_on_operator);

    u8[] s_ext = "Parser Extern";
    testing::add(s_ext, "extern_block_empty", &extern_block_empty);
    testing::add(s_ext, "extern_block_named_lib", &extern_block_named_lib);
    testing::add(s_ext, "extern_block_lib_c_explicit", &extern_block_lib_c_explicit);
    testing::add(s_ext, "extern_block_src_pos_on_extern_kw", &extern_block_src_pos_on_extern_kw);
    testing::add(s_ext, "extern_fn_no_params", &extern_fn_no_params);
    testing::add(s_ext, "extern_fn_with_params", &extern_fn_with_params);
    testing::add(s_ext, "extern_fn_param_wrong_modifier_order", &extern_fn_param_wrong_modifier_order);
    testing::add(s_ext, "extern_fn_variadic", &extern_fn_variadic);
    testing::add(s_ext, "extern_fn_variadic_only", &extern_fn_variadic_only);
    testing::add(s_ext, "extern_fn_multi_param_variadic", &extern_fn_multi_param_variadic);
    testing::add(s_ext, "extern_fn_exported", &extern_fn_exported);
    testing::add(s_ext, "extern_fn_comptime_safe_is_minus_one", &extern_fn_comptime_safe_is_minus_one);
    testing::add(s_ext, "extern_struct_opaque", &extern_struct_opaque);
    testing::add(s_ext, "extern_struct_opaque_exported", &extern_struct_opaque_exported);
    testing::add(s_ext, "extern_struct_full", &extern_struct_full);
    testing::add(s_ext, "extern_struct_full_empty_body", &extern_struct_full_empty_body);
    testing::add(s_ext, "extern_struct_full_exported", &extern_struct_full_exported);
    testing::add(s_ext, "extern_struct_no_body_no_opaque_errors", &extern_struct_no_body_no_opaque_errors);
    testing::add(s_ext, "extern_struct_opaque_with_body_errors", &extern_struct_opaque_with_body_errors);
    testing::add(s_ext, "extern_union_opaque", &extern_union_opaque);
    testing::add(s_ext, "extern_union_opaque_exported", &extern_union_opaque_exported);
    testing::add(s_ext, "extern_union_full", &extern_union_full);
    testing::add(s_ext, "extern_union_full_exported", &extern_union_full_exported);
    testing::add(s_ext, "extern_union_no_body_no_opaque_errors", &extern_union_no_body_no_opaque_errors);
    testing::add(s_ext, "extern_union_opaque_with_body_errors", &extern_union_opaque_with_body_errors);
    testing::add(s_ext, "extern_opaque_on_fn_errors", &extern_opaque_on_fn_errors);
    testing::add(s_ext, "extern_block_multi_item", &extern_block_multi_item);
    testing::add(s_ext, "extern_block_mixed_export", &extern_block_mixed_export);
    testing::add(s_ext, "extern_block_after_import", &extern_block_after_import);
    testing::add(s_ext, "extern_unknown_item_errors", &extern_unknown_item_errors);
    testing::add(s_ext, "extern_missing_rbrace_at_eof", &extern_missing_rbrace_at_eof);
    testing::add(s_ext, "extern_named_lib_with_items", &extern_named_lib_with_items);
    testing::add(s_ext, "extern_struct_full_with_pointer_field", &extern_struct_full_with_pointer_field);
    testing::add(s_ext, "extern_fn_returns_pointer", &extern_fn_returns_pointer);
    testing::add(s_ext, "extern_fn_takes_opaque_pointer", &extern_fn_takes_opaque_pointer);
    testing::add(s_ext, "extern_two_blocks", &extern_two_blocks);
    testing::add(s_ext, "extern_fn_src_pos", &extern_fn_src_pos);
    testing::add(s_ext, "extern_struct_src_pos_at_start", &extern_struct_src_pos_at_start);
    testing::add(s_ext, "extern_export_struct_src_pos_includes_export", &extern_export_struct_src_pos_includes_export);
    testing::add(s_ext, "fn_variadic_at_top_level_errors", &fn_variadic_at_top_level_errors);
    testing::add(s_ext, "extern_bare_no_brace_errors", &extern_bare_no_brace_errors);
    testing::add(s_ext, "extern_non_string_lib_errors", &extern_non_string_lib_errors);
    testing::add(s_ext, "extern_wrong_modifier_order_errors", &extern_wrong_modifier_order_errors);
    testing::add(s_ext, "extern_fn_missing_semi_errors", &extern_fn_missing_semi_errors);
    testing::add(s_ext, "extern_struct_no_body_no_opaque_src_pos_at_semi", &extern_struct_no_body_no_opaque_src_pos_at_semi);
    testing::add(s_ext, "extern_struct_opaque_with_body_src_pos_at_lbrace", &extern_struct_opaque_with_body_src_pos_at_lbrace);
    testing::add(s_ext, "extern_union_no_body_no_opaque_src_pos_at_semi", &extern_union_no_body_no_opaque_src_pos_at_semi);
    testing::add(s_ext, "extern_union_opaque_with_body_src_pos_at_lbrace", &extern_union_opaque_with_body_src_pos_at_lbrace);
    testing::add(s_ext, "extern_opaque_on_fn_src_pos_at_opaque", &extern_opaque_on_fn_src_pos_at_opaque);
    testing::add(s_ext, "extern_double_export_errors", &extern_double_export_errors);
    testing::add(s_ext, "opaque_at_top_level_errors", &opaque_at_top_level_errors);
    testing::add(s_ext, "extern_opaque_on_var_decl_errors", &extern_opaque_on_var_decl_errors);
    testing::add(s_ext, "extern_fn_with_body_errors", &extern_fn_with_body_errors);

    u8[] s_en = "Parser Enum";
    testing::add(s_en, "enum_empty", &enum_empty);
    testing::add(s_en, "enum_single_member", &enum_single_member);
    testing::add(s_en, "enum_multi_member", &enum_multi_member);
    testing::add(s_en, "enum_explicit_base_type", &enum_explicit_base_type);
    testing::add(s_en, "enum_all_int_base_types", &enum_all_int_base_types);
    testing::add(s_en, "enum_explicit_int_value", &enum_explicit_int_value);
    testing::add(s_en, "enum_mixed_explicit_and_auto", &enum_mixed_explicit_and_auto);
    testing::add(s_en, "enum_symbolic_value", &enum_symbolic_value);
    testing::add(s_en, "enum_negative_value", &enum_negative_value);
    testing::add(s_en, "enum_expression_value", &enum_expression_value);
    testing::add(s_en, "enum_trailing_comma", &enum_trailing_comma);
    testing::add(s_en, "enum_exported", &enum_exported);
    testing::add(s_en, "enum_exported_with_base_type", &enum_exported_with_base_type);
    testing::add(s_en, "enum_spec_example", &enum_spec_example);
    testing::add(s_en, "enum_src_pos_at_enum_kw", &enum_src_pos_at_enum_kw);
    testing::add(s_en, "enum_member_src_pos", &enum_member_src_pos);
    testing::add(s_en, "enum_missing_name_errors", &enum_missing_name_errors);
    testing::add(s_en, "enum_missing_lbrace_errors", &enum_missing_lbrace_errors);
    testing::add(s_en, "enum_missing_rbrace_errors", &enum_missing_rbrace_errors);
    testing::add(s_en, "enum_missing_member_after_comma_errors", &enum_missing_member_after_comma_errors);
    testing::add(s_en, "enum_missing_value_after_eq_errors", &enum_missing_value_after_eq_errors);
    testing::add(s_en, "enum_member_is_keyword_errors", &enum_member_is_keyword_errors);
    testing::add(s_en, "enum_base_type_missing_after_colon_errors", &enum_base_type_missing_after_colon_errors);
    testing::add(s_en, "enum_missing_comma_between_members", &enum_missing_comma_between_members);
    testing::add(s_en, "enum_trailing_comma_single_member", &enum_trailing_comma_single_member);
    testing::add(s_en, "enum_complex_expression_value", &enum_complex_expression_value);
    testing::add(s_en, "enum_zero_value", &enum_zero_value);
    testing::add(s_en, "enum_after_other_decls", &enum_after_other_decls);

    return testing::run();
}
