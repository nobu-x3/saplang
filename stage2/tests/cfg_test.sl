import testing;
import cfg;
import ast;
import module;
import types;
import arena;
import sys;

fn module::Module* mk_module(arena::Arena* a) {
    module::Module* m = (module::Module*)arena::alloc(a, sizeof(module::Module));
    sys::memset(m, 0, sizeof(module::Module));
    m.arena = a;
    return m;
}

fn ast::AstNode* mk_int_lit(arena::Arena* a) {
    ast::IntLitNode* n = (ast::IntLitNode*)arena::alloc(a, sizeof(ast::IntLitNode));
    sys::memset(n, 0, sizeof(ast::IntLitNode));
    n.h.kind = ast::AstKind::IntLit;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_expr_stmt(arena::Arena* a, ast::AstNode* expr) {
    ast::ExprStmtNode* n = (ast::ExprStmtNode*)arena::alloc(a, sizeof(ast::ExprStmtNode));
    sys::memset(n, 0, sizeof(ast::ExprStmtNode));
    n.h.kind = ast::AstKind::ExprStmt;
    n.expr = expr;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_block(arena::Arena* a, ast::AstNode** stmts, u64 count) {
    ast::BlockNode* n = (ast::BlockNode*)arena::alloc(a, sizeof(ast::BlockNode));
    sys::memset(n, 0, sizeof(ast::BlockNode));
    n.h.kind = ast::AstKind::BlockStmt;
    n.stmts = {stmts, count};
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_prim_type(arena::Arena* a, types::Type* ty) {
    ast::TypePrimitiveNode* n = (ast::TypePrimitiveNode*)arena::alloc(a, sizeof(ast::TypePrimitiveNode));
    sys::memset(n, 0, sizeof(ast::TypePrimitiveNode));
    n.h.kind = ast::AstKind::PrimitiveType;
    n.h.ty = (void*)ty;
    return (ast::AstNode*)n;
}

fn ast::FnDeclNode* mk_fn(arena::Arena* a, ast::AstNode* return_type, ast::AstNode* body) {
    ast::FnDeclNode* n = (ast::FnDeclNode*)arena::alloc(a, sizeof(ast::FnDeclNode));
    sys::memset(n, 0, sizeof(ast::FnDeclNode));
    n.h.kind = ast::AstKind::FnDecl;
    n.return_type = return_type;
    n.body = body;
    return n;
}

fn i32 straight_line_void(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[2] stmts;
    stmts[0] = mk_expr_stmt(a, mk_int_lit(a));
    stmts[1] = mk_expr_stmt(a, mk_int_lit(a));
    ast::FnDeclNode* func = mk_fn(a, null, mk_block(a, &stmts[0], 2));
    cfg::Cfg* g = cfg::build_cfg(mm, func);
    if(!testing::expect_eq(g.blocks.len, (u64)2, m)) { return -1; }
    if(!testing::expect_eq((u64)g.entry, (u64)0, m)) { return -2; }
    if(!testing::expect_eq((u64)g.exit, (u64)1, m)) { return -3; }
    if(!testing::expect_eq(g.blocks[0].stmts.len, (u64)2, m)) { return -4; }
    if(!testing::expect_eq((u64)g.blocks[0].term.kind, (u64)cfg::TermKind::Return, m)) { return -5; }
    if(!testing::expect_true(g.blocks[0].terminated, m)) { return -6; }
    return 0;
}

fn i32 non_void_no_return_is_unreachable(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] stmts;
    stmts[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode* ret_ty = mk_prim_type(a, types::prim_i32());
    ast::FnDeclNode* func = mk_fn(a, ret_ty, mk_block(a, &stmts[0], 1));
    cfg::Cfg* g = cfg::build_cfg(mm, func);
    if(!testing::expect_eq((u64)g.blocks[0].term.kind, (u64)cfg::TermKind::Unreachable, m)) { return -1; }
    return 0;
}

fn ast::AstNode* mk_kind(arena::Arena* a, ast::AstKind kind) {
    ast::ExprStmtNode* n = (ast::ExprStmtNode*)arena::alloc(a, sizeof(ast::ExprStmtNode));
    sys::memset(n, 0, sizeof(ast::ExprStmtNode));
    n.h.kind = kind;
    return (ast::AstNode*)n;
}

fn i32 mixed_leaf_kinds_referenced(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[3] stmts;
    stmts[0] = mk_kind(a, ast::AstKind::VarDecl);
    stmts[1] = mk_kind(a, ast::AstKind::AssignmentStmt);
    stmts[2] = mk_kind(a, ast::AstKind::ExprStmt);
    ast::FnDeclNode* func = mk_fn(a, null, mk_block(a, &stmts[0], 3));
    cfg::Cfg* g = cfg::build_cfg(mm, func);
    if(!testing::expect_eq(g.blocks[0].stmts.len, (u64)3, m)) { return -1; }
    if(!testing::expect_eq((void*)g.blocks[0].stmts[0], (void*)stmts[0], m)) { return -2; }
    if(!testing::expect_eq((void*)g.blocks[0].stmts[2], (void*)stmts[2], m)) { return -3; }
    return 0;
}

fn i32 predecessors_and_exit_finalized(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] stmts;
    stmts[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::FnDeclNode* func = mk_fn(a, null, mk_block(a, &stmts[0], 1));
    cfg::Cfg* g = cfg::build_cfg(mm, func);
    if(!testing::expect_eq(g.blocks[g.entry].predecessors.len, (u64)0, m)) { return -1; }
    if(!testing::expect_eq(g.blocks[g.exit].predecessors.len, (u64)0, m)) { return -2; }
    if(!testing::expect_true(g.blocks[g.exit].terminated, m)) { return -3; }
    if(!testing::expect_eq((u64)g.blocks[g.exit].term.kind, (u64)cfg::TermKind::Unreachable, m)) { return -4; }
    return 0;
}

fn i32 empty_void_body(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::FnDeclNode* func = mk_fn(a, null, mk_block(a, null, 0));
    cfg::Cfg* g = cfg::build_cfg(mm, func);
    if(!testing::expect_eq(g.blocks[0].stmts.len, (u64)0, m)) { return -1; }
    if(!testing::expect_eq((u64)g.blocks[0].term.kind, (u64)cfg::TermKind::Return, m)) { return -2; }
    return 0;
}

fn i32 nested_blocks_flatten(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] inner_stmts;
    inner_stmts[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode* inner = mk_block(a, &inner_stmts[0], 1);
    ast::AstNode*[2] outer_stmts;
    outer_stmts[0] = inner;
    outer_stmts[1] = mk_expr_stmt(a, mk_int_lit(a));
    ast::FnDeclNode* func = mk_fn(a, null, mk_block(a, &outer_stmts[0], 2));
    cfg::Cfg* g = cfg::build_cfg(mm, func);
    if(!testing::expect_eq(g.blocks.len, (u64)2, m)) { return -1; }
    if(!testing::expect_eq(g.blocks[0].stmts.len, (u64)2, m)) { return -2; }
    return 0;
}

fn i32 haderror_stmt_skipped(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode* bad = mk_expr_stmt(a, mk_int_lit(a));
    bad.h.flags = ast::AstFlags::HadError;
    ast::AstNode*[1] stmts;
    stmts[0] = bad;
    ast::FnDeclNode* func = mk_fn(a, null, mk_block(a, &stmts[0], 1));
    cfg::Cfg* g = cfg::build_cfg(mm, func);
    if(!testing::expect_eq(g.blocks[0].stmts.len, (u64)0, m)) { return -1; }
    return 0;
}

fn i32 main() {
    testing::init();
    u8[] suite = "CFG Construction Tests";
    testing::add(suite, "straight_line_void",              &straight_line_void);
    testing::add(suite, "non_void_no_return_is_unreachable", &non_void_no_return_is_unreachable);
    testing::add(suite, "empty_void_body",                 &empty_void_body);
    testing::add(suite, "mixed_leaf_kinds_referenced",     &mixed_leaf_kinds_referenced);
    testing::add(suite, "predecessors_and_exit_finalized", &predecessors_and_exit_finalized);
    testing::add(suite, "nested_blocks_flatten",           &nested_blocks_flatten);
    testing::add(suite, "haderror_stmt_skipped",           &haderror_stmt_skipped);
    return testing::run();
}
