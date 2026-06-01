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
    return 0;
}

fn i32 var_decl_missing_init_expr(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "i32 x = ;", &m);
    ast::AstNode* n = compiler_testing::nth_stmt(root, 0);
    if(!testing::expect_true(compiler_testing::has_error_flag(n), msg)) { return -1; }
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

fn i32 fn_param_const_comptime(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(const comptime i32 N) {}", &m);
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
    if(!testing::expect_true(m.diag.entries.len > 0, msg)) { return -3; }
    return 0;
}

fn i32 fn_missing_rparen(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f(i32 x {}", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), compiler_testing::sym(m, "f"), 1, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)f), msg)) { return -2; }
    if(!testing::expect_true(m.diag.entries.len > 0, msg)) { return -3; }
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
    if(!testing::expect_true(m.diag.entries.len > 0, msg)) { return -4; }
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
    if(!testing::expect_true(m.diag.entries.len > 0, msg)) { return -3; }
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

fn i32 local_var_decl_export_rejected(arena::Arena* a, u8[] msg) {
    arena::Arena local = {8192, null};
    module::Module* m;
    ast::AstNode* root = compiler_testing::parse_src(&local, "fn void f() { export i32 x = 5; }", &m);
    ast::FnDeclNode* f = compiler_testing::expect_fn_decl(compiler_testing::nth_stmt(root, 0), null, 0, false, msg);
    if(!f) { return -1; }
    if(!testing::expect_true(compiler_testing::has_error_flag((ast::AstNode*)f), msg)) { return -2; }
    if(!testing::expect_true(m.diag.entries.len > 0, msg)) { return -3; }
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
    if(!testing::expect_true(m.diag.entries.len > 0, msg)) { return -5; }
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
    if(!testing::expect_true(m.diag.entries.len > 0, msg)) { return -4; }
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
    if(!testing::expect_true(m.diag.entries.len > 0, msg)) { return -7; }
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
    if(!testing::expect_true(m.diag.entries.len > 0, msg)) { return -5; }
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
    if(!testing::expect_true(m.diag.entries.len > 0, msg)) { return -5; }
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
    if(!testing::expect_true(m.diag.entries.len > 0, msg)) { return -5; }
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
    testing::add(s_fn, "fn_param_const_comptime", &fn_param_const_comptime);
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

    u8[] s_local_var_decl = "Parser Local VarDecls";
    testing::add(s_local_var_decl, "local_var_decl_basic", &local_var_decl_basic);
    testing::add(s_local_var_decl, "local_var_decl_const", &local_var_decl_const);
    testing::add(s_local_var_decl, "local_var_decl_no_init", &local_var_decl_no_init);
    testing::add(s_local_var_decl, "local_var_decl_pointer_type", &local_var_decl_pointer_type);
    testing::add(s_local_var_decl, "local_var_decl_named_type", &local_var_decl_named_type);
    testing::add(s_local_var_decl, "local_var_decl_qualified_named_type", &local_var_decl_qualified_named_type);
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
    testing::add(s_local_var_decl, "local_var_decl_export_rejected", &local_var_decl_export_rejected);

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

    return testing::run();
}
