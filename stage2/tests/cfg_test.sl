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

fn ast::AstNode* mk_if(arena::Arena* a, ast::AstNode* cond, ast::AstNode* then_block, ast::AstNode* else_block) {
    ast::IfNode* n = (ast::IfNode*)arena::alloc(a, sizeof(ast::IfNode));
    sys::memset(n, 0, sizeof(ast::IfNode));
    n.h.kind = ast::AstKind::IfStmt;
    n.cond = cond;
    n.then_block = then_block;
    n.else_block = else_block;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_while(arena::Arena* a, ast::AstNode* cond, ast::AstNode* body) {
    ast::WhileNode* n = (ast::WhileNode*)arena::alloc(a, sizeof(ast::WhileNode));
    sys::memset(n, 0, sizeof(ast::WhileNode));
    n.h.kind = ast::AstKind::WhileStmt;
    n.cond = cond;
    n.body = body;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_for(arena::Arena* a, ast::AstNode* init, ast::AstNode* cond, ast::AstNode* post, ast::AstNode* body) {
    ast::ForNode* n = (ast::ForNode*)arena::alloc(a, sizeof(ast::ForNode));
    sys::memset(n, 0, sizeof(ast::ForNode));
    n.h.kind = ast::AstKind::ForStmt;
    n.init = init;
    n.cond = cond;
    n.post = post;
    n.body = body;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_return(arena::Arena* a, ast::AstNode* expr) {
    ast::ReturnNode* n = (ast::ReturnNode*)arena::alloc(a, sizeof(ast::ReturnNode));
    sys::memset(n, 0, sizeof(ast::ReturnNode));
    n.h.kind = ast::AstKind::ReturnStmt;
    n.expr = expr;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_break(arena::Arena* a) {
    ast::BreakNode* n = (ast::BreakNode*)arena::alloc(a, sizeof(ast::BreakNode));
    sys::memset(n, 0, sizeof(ast::BreakNode));
    n.h.kind = ast::AstKind::BreakStmt;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_continue(arena::Arena* a) {
    ast::ContinueNode* n = (ast::ContinueNode*)arena::alloc(a, sizeof(ast::ContinueNode));
    sys::memset(n, 0, sizeof(ast::ContinueNode));
    n.h.kind = ast::AstKind::ContinueStmt;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_defer(arena::Arena* a, ast::AstNode* body) {
    ast::DeferNode* n = (ast::DeferNode*)arena::alloc(a, sizeof(ast::DeferNode));
    sys::memset(n, 0, sizeof(ast::DeferNode));
    n.h.kind = ast::AstKind::DeferStmt;
    n.body = body;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_switch(arena::Arena* a, ast::AstNode* disc, ast::SwitchArm[] arms, ast::AstNode* else_block) {
    ast::SwitchNode* n = (ast::SwitchNode*)arena::alloc(a, sizeof(ast::SwitchNode));
    sys::memset(n, 0, sizeof(ast::SwitchNode));
    n.h.kind = ast::AstKind::SwitchStmt;
    n.discriminant = disc;
    n.arms = arms;
    n.else_block = else_block;
    return (ast::AstNode*)n;
}

fn void set_arm(ast::SwitchArm* arm, ast::AstNode** labels, u64 label_count, ast::AstNode* body) {
    arm.labels = {labels, label_count};
    arm.body = body;
    arm.src_pos = 0;
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

fn i32 if_else_merge(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] then_s;
    then_s[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode*[1] else_s;
    else_s[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode* iff = mk_if(a, mk_int_lit(a), mk_block(a, &then_s[0], 1), mk_block(a, &else_s[0], 1));
    ast::AstNode*[1] body;
    body[0] = iff;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq(g.blocks.len, (u64)5, m)) { return -1; }
    if(!testing::expect_eq((u64)g.blocks[0].term.kind, (u64)cfg::TermKind::CondBranch, m)) { return -2; }
    if(!testing::expect_eq((u64)g.blocks[0].term.then_target, (u64)2, m)) { return -3; }
    if(!testing::expect_eq((u64)g.blocks[0].term.else_target, (u64)3, m)) { return -4; }
    if(!testing::expect_eq((u64)g.blocks[2].term.kind, (u64)cfg::TermKind::Goto, m)) { return -5; }
    if(!testing::expect_eq((u64)g.blocks[2].term.goto_target, (u64)4, m)) { return -6; }
    if(!testing::expect_eq(g.blocks[4].predecessors.len, (u64)2, m)) { return -7; }
    if(!testing::expect_eq((u64)g.blocks[4].term.kind, (u64)cfg::TermKind::Return, m)) { return -8; }
    return 0;
}

fn i32 if_no_else(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] then_s;
    then_s[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode* iff = mk_if(a, mk_int_lit(a), mk_block(a, &then_s[0], 1), null);
    ast::AstNode*[1] body;
    body[0] = iff;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq(g.blocks[3].stmts.len, (u64)0, m)) { return -1; }
    if(!testing::expect_eq((u64)g.blocks[3].term.kind, (u64)cfg::TermKind::Goto, m)) { return -2; }
    if(!testing::expect_eq((u64)g.blocks[3].term.goto_target, (u64)4, m)) { return -3; }
    if(!testing::expect_eq(g.blocks[4].predecessors.len, (u64)2, m)) { return -4; }
    return 0;
}

fn i32 if_both_return_after_unreachable(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] then_s;
    then_s[0] = mk_return(a, null);
    ast::AstNode*[1] else_s;
    else_s[0] = mk_return(a, null);
    ast::AstNode* iff = mk_if(a, mk_int_lit(a), mk_block(a, &then_s[0], 1), mk_block(a, &else_s[0], 1));
    ast::AstNode*[1] body;
    body[0] = iff;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq((u64)g.blocks[2].term.kind, (u64)cfg::TermKind::Return, m)) { return -1; }
    if(!testing::expect_eq((u64)g.blocks[3].term.kind, (u64)cfg::TermKind::Return, m)) { return -2; }
    if(!testing::expect_eq(g.blocks[4].predecessors.len, (u64)0, m)) { return -3; }
    return 0;
}

fn i32 while_loop_edges(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] wbody;
    wbody[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode* wh = mk_while(a, mk_int_lit(a), mk_block(a, &wbody[0], 1));
    ast::AstNode*[1] body;
    body[0] = wh;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq((u64)g.blocks[0].term.kind, (u64)cfg::TermKind::Goto, m)) { return -1; }
    if(!testing::expect_eq((u64)g.blocks[0].term.goto_target, (u64)2, m)) { return -2; }
    if(!testing::expect_eq((u64)g.blocks[2].term.kind, (u64)cfg::TermKind::CondBranch, m)) { return -3; }
    if(!testing::expect_eq((u64)g.blocks[2].term.then_target, (u64)3, m)) { return -4; }
    if(!testing::expect_eq((u64)g.blocks[2].term.else_target, (u64)4, m)) { return -5; }
    if(!testing::expect_eq(g.blocks[2].predecessors.len, (u64)2, m)) { return -6; }
    if(!testing::expect_eq((u64)g.blocks[3].term.goto_target, (u64)2, m)) { return -7; }
    if(!testing::expect_eq(g.blocks[4].predecessors.len, (u64)1, m)) { return -8; }
    return 0;
}

fn i32 while_break(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] wbody;
    wbody[0] = mk_break(a);
    ast::AstNode* wh = mk_while(a, mk_int_lit(a), mk_block(a, &wbody[0], 1));
    ast::AstNode*[1] body;
    body[0] = wh;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq((u64)g.blocks[3].term.kind, (u64)cfg::TermKind::Goto, m)) { return -1; }
    if(!testing::expect_eq((u64)g.blocks[3].term.goto_target, (u64)4, m)) { return -2; }
    if(!testing::expect_eq(g.blocks[2].predecessors.len, (u64)1, m)) { return -3; }
    if(!testing::expect_eq(g.blocks[4].predecessors.len, (u64)2, m)) { return -4; }
    return 0;
}

fn i32 while_continue(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] wbody;
    wbody[0] = mk_continue(a);
    ast::AstNode* wh = mk_while(a, mk_int_lit(a), mk_block(a, &wbody[0], 1));
    ast::AstNode*[1] body;
    body[0] = wh;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq((u64)g.blocks[3].term.goto_target, (u64)2, m)) { return -1; }
    if(!testing::expect_eq(g.blocks[2].predecessors.len, (u64)2, m)) { return -2; }
    if(!testing::expect_eq(g.blocks[4].predecessors.len, (u64)1, m)) { return -3; }
    return 0;
}

fn i32 for_loop_edges(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] fbody;
    fbody[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode* fr = mk_for(a, mk_expr_stmt(a, mk_int_lit(a)), mk_int_lit(a), mk_expr_stmt(a, mk_int_lit(a)), mk_block(a, &fbody[0], 1));
    ast::AstNode*[1] body;
    body[0] = fr;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq(g.blocks[0].stmts.len, (u64)1, m)) { return -1; }
    if(!testing::expect_eq((u64)g.blocks[0].term.goto_target, (u64)2, m)) { return -2; }
    if(!testing::expect_eq((u64)g.blocks[2].term.kind, (u64)cfg::TermKind::CondBranch, m)) { return -3; }
    if(!testing::expect_eq((u64)g.blocks[2].term.then_target, (u64)3, m)) { return -4; }
    if(!testing::expect_eq((u64)g.blocks[2].term.else_target, (u64)5, m)) { return -5; }
    if(!testing::expect_eq((u64)g.blocks[3].term.goto_target, (u64)4, m)) { return -6; }
    if(!testing::expect_eq((u64)g.blocks[4].term.goto_target, (u64)2, m)) { return -7; }
    if(!testing::expect_eq(g.blocks[2].predecessors.len, (u64)2, m)) { return -8; }
    return 0;
}

fn i32 for_no_cond(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] fbody;
    fbody[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode* fr = mk_for(a, null, null, null, mk_block(a, &fbody[0], 1));
    ast::AstNode*[1] body;
    body[0] = fr;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq((u64)g.blocks[2].term.kind, (u64)cfg::TermKind::Goto, m)) { return -1; }
    if(!testing::expect_eq((u64)g.blocks[2].term.goto_target, (u64)3, m)) { return -2; }
    if(!testing::expect_eq((u64)g.blocks[4].term.goto_target, (u64)2, m)) { return -3; }
    return 0;
}

fn i32 for_continue_targets_post(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] fbody;
    fbody[0] = mk_continue(a);
    ast::AstNode* fr = mk_for(a, mk_expr_stmt(a, mk_int_lit(a)), mk_int_lit(a), mk_expr_stmt(a, mk_int_lit(a)), mk_block(a, &fbody[0], 1));
    ast::AstNode*[1] body;
    body[0] = fr;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq((u64)g.blocks[3].term.goto_target, (u64)4, m)) { return -1; }
    return 0;
}

fn i32 switch_arms_dispatch(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] a0;
    a0[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode*[1] a1;
    a1[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode*[1] els;
    els[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode*[1] l0;
    l0[0] = mk_int_lit(a);
    ast::AstNode*[1] l1;
    l1[0] = mk_int_lit(a);
    ast::SwitchArm[2] arms;
    set_arm(&arms[0], &l0[0], 1, mk_block(a, &a0[0], 1));
    set_arm(&arms[1], &l1[0], 1, mk_block(a, &a1[0], 1));
    ast::SwitchArm[] arms_slice = {&arms[0], 2};
    ast::AstNode* sw = mk_switch(a, mk_int_lit(a), arms_slice, mk_block(a, &els[0], 1));
    ast::AstNode*[1] body;
    body[0] = sw;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq((u64)g.blocks[0].term.kind, (u64)cfg::TermKind::Switch, m)) { return -1; }
    if(!testing::expect_eq((u64)g.blocks[0].term.switch_default, (u64)3, m)) { return -2; }
    if(!testing::expect_eq(g.blocks[0].term.switch_arms.len, (u64)2, m)) { return -3; }
    if(!testing::expect_eq((u64)g.blocks[0].term.switch_arms[0].target, (u64)4, m)) { return -4; }
    if(!testing::expect_eq((u64)g.blocks[0].term.switch_arms[1].target, (u64)5, m)) { return -5; }
    if(!testing::expect_eq(g.blocks[2].predecessors.len, (u64)3, m)) { return -6; }
    if(!testing::expect_eq((u64)g.blocks[4].term.goto_target, (u64)2, m)) { return -7; }
    return 0;
}

fn i32 switch_no_else_default_unreachable(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] a0;
    a0[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode*[1] l0;
    l0[0] = mk_int_lit(a);
    ast::SwitchArm[1] arms;
    set_arm(&arms[0], &l0[0], 1, mk_block(a, &a0[0], 1));
    ast::SwitchArm[] arms_slice = {&arms[0], 1};
    ast::AstNode* sw = mk_switch(a, mk_int_lit(a), arms_slice, null);
    ast::AstNode*[1] body;
    body[0] = sw;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq((u64)g.blocks[0].term.switch_default, (u64)3, m)) { return -1; }
    if(!testing::expect_eq((u64)g.blocks[3].term.kind, (u64)cfg::TermKind::Unreachable, m)) { return -2; }
    if(!testing::expect_eq(g.blocks[0].term.switch_arms.len, (u64)1, m)) { return -3; }
    return 0;
}

fn i32 switch_break_fresh_continuation(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] a0;
    a0[0] = mk_break(a);
    ast::AstNode*[1] l0;
    l0[0] = mk_int_lit(a);
    ast::SwitchArm[1] arms;
    set_arm(&arms[0], &l0[0], 1, mk_block(a, &a0[0], 1));
    ast::SwitchArm[] arms_slice = {&arms[0], 1};
    ast::AstNode* sw = mk_switch(a, mk_int_lit(a), arms_slice, null);
    ast::AstNode*[1] body;
    body[0] = sw;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq((u64)g.blocks[4].term.goto_target, (u64)2, m)) { return -1; }
    if(!testing::expect_eq(g.blocks.len, (u64)6, m)) { return -2; }
    return 0;
}

fn i32 return_fresh_unreachable(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] body;
    body[0] = mk_return(a, null);
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq((u64)g.blocks[0].term.kind, (u64)cfg::TermKind::Return, m)) { return -1; }
    if(!testing::expect_eq((void*)g.blocks[0].term.return_value, null, m)) { return -2; }
    if(!testing::expect_eq(g.blocks.len, (u64)3, m)) { return -3; }
    if(!testing::expect_eq((u64)g.blocks[2].term.kind, (u64)cfg::TermKind::Unreachable, m)) { return -4; }
    return 0;
}

fn i32 return_value_recorded(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode* val = mk_int_lit(a);
    ast::AstNode*[1] body;
    body[0] = mk_return(a, val);
    ast::AstNode* ret_ty = mk_prim_type(a, types::prim_i32());
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, ret_ty, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq((void*)g.blocks[0].term.return_value, (void*)val, m)) { return -1; }
    return 0;
}

fn i32 defer_fallthrough(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode* s = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode*[1] dbody;
    dbody[0] = s;
    ast::AstNode*[1] body;
    body[0] = mk_defer(a, mk_block(a, &dbody[0], 1));
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq(g.blocks[0].stmts.len, (u64)1, m)) { return -1; }
    if(!testing::expect_eq((void*)g.blocks[0].stmts[0], (void*)s, m)) { return -2; }
    if(!testing::expect_eq((u64)g.blocks[0].term.kind, (u64)cfg::TermKind::Return, m)) { return -3; }
    return 0;
}

fn i32 defer_reverse_order(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode* sa = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode* sb = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode*[1] da;
    da[0] = sa;
    ast::AstNode*[1] db;
    db[0] = sb;
    ast::AstNode*[2] body;
    body[0] = mk_defer(a, mk_block(a, &da[0], 1));
    body[1] = mk_defer(a, mk_block(a, &db[0], 1));
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 2)));
    if(!testing::expect_eq(g.blocks[0].stmts.len, (u64)2, m)) { return -1; }
    if(!testing::expect_eq((void*)g.blocks[0].stmts[0], (void*)sb, m)) { return -2; }
    if(!testing::expect_eq((void*)g.blocks[0].stmts[1], (void*)sa, m)) { return -3; }
    return 0;
}

fn i32 defer_on_return(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode* s = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode*[1] dbody;
    dbody[0] = s;
    ast::AstNode*[2] body;
    body[0] = mk_defer(a, mk_block(a, &dbody[0], 1));
    body[1] = mk_return(a, null);
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 2)));
    if(!testing::expect_eq(g.blocks[0].stmts.len, (u64)1, m)) { return -1; }
    if(!testing::expect_eq((void*)g.blocks[0].stmts[0], (void*)s, m)) { return -2; }
    if(!testing::expect_eq((u64)g.blocks[0].term.kind, (u64)cfg::TermKind::Return, m)) { return -3; }
    return 0;
}

fn i32 defer_on_break(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode* s = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode*[1] dbody;
    dbody[0] = s;
    ast::AstNode*[2] wbody;
    wbody[0] = mk_defer(a, mk_block(a, &dbody[0], 1));
    wbody[1] = mk_break(a);
    ast::AstNode* wh = mk_while(a, mk_int_lit(a), mk_block(a, &wbody[0], 2));
    ast::AstNode*[1] body;
    body[0] = wh;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq(g.blocks[3].stmts.len, (u64)1, m)) { return -1; }
    if(!testing::expect_eq((void*)g.blocks[3].stmts[0], (void*)s, m)) { return -2; }
    if(!testing::expect_eq((u64)g.blocks[3].term.goto_target, (u64)4, m)) { return -3; }
    return 0;
}

fn i32 nested_if_in_while(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] then_s;
    then_s[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode* iff = mk_if(a, mk_int_lit(a), mk_block(a, &then_s[0], 1), null);
    ast::AstNode*[1] wbody;
    wbody[0] = iff;
    ast::AstNode* wh = mk_while(a, mk_int_lit(a), mk_block(a, &wbody[0], 1));
    ast::AstNode*[1] body;
    body[0] = wh;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq((u64)g.blocks[3].term.kind, (u64)cfg::TermKind::CondBranch, m)) { return -1; }
    if(!testing::expect_eq((u64)g.blocks[7].term.kind, (u64)cfg::TermKind::Goto, m)) { return -2; }
    if(!testing::expect_eq((u64)g.blocks[7].term.goto_target, (u64)2, m)) { return -3; }
    return 0;
}

fn i32 continue_through_switch(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] arm_body;
    arm_body[0] = mk_continue(a);
    ast::AstNode*[1] l0;
    l0[0] = mk_int_lit(a);
    ast::SwitchArm[1] arms;
    set_arm(&arms[0], &l0[0], 1, mk_block(a, &arm_body[0], 1));
    ast::SwitchArm[] arms_slice = {&arms[0], 1};
    ast::AstNode* sw = mk_switch(a, mk_int_lit(a), arms_slice, null);
    ast::AstNode*[1] wbody;
    wbody[0] = sw;
    ast::AstNode* wh = mk_while(a, mk_int_lit(a), mk_block(a, &wbody[0], 1));
    ast::AstNode*[1] body;
    body[0] = wh;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq((u64)g.blocks[7].term.kind, (u64)cfg::TermKind::Goto, m)) { return -1; }
    if(!testing::expect_eq((u64)g.blocks[7].term.goto_target, (u64)2, m)) { return -2; }
    return 0;
}

fn i32 switch_fallthrough(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] a1;
    a1[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode*[1] l0;
    l0[0] = mk_int_lit(a);
    ast::AstNode*[1] l1;
    l1[0] = mk_int_lit(a);
    ast::SwitchArm[2] arms;
    set_arm(&arms[0], &l0[0], 1, null);
    set_arm(&arms[1], &l1[0], 1, mk_block(a, &a1[0], 1));
    ast::SwitchArm[] arms_slice = {&arms[0], 2};
    ast::AstNode* sw = mk_switch(a, mk_int_lit(a), arms_slice, null);
    ast::AstNode*[1] body;
    body[0] = sw;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq(g.blocks[0].term.switch_arms.len, (u64)2, m)) { return -1; }
    if(!testing::expect_eq((u64)g.blocks[0].term.switch_arms[0].target, (u64)4, m)) { return -2; }
    if(!testing::expect_eq((u64)g.blocks[0].term.switch_arms[1].target, (u64)4, m)) { return -3; }
    if(!testing::expect_eq(g.blocks[4].predecessors.len, (u64)1, m)) { return -4; }
    if(!testing::expect_eq((u64)g.blocks[4].term.goto_target, (u64)2, m)) { return -5; }
    return 0;
}

fn i32 if_else_if_chain(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] a_s;
    a_s[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode*[1] b_s;
    b_s[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode*[1] c_s;
    c_s[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode* inner = mk_if(a, mk_int_lit(a), mk_block(a, &b_s[0], 1), mk_block(a, &c_s[0], 1));
    ast::AstNode* outer = mk_if(a, mk_int_lit(a), mk_block(a, &a_s[0], 1), inner);
    ast::AstNode*[1] body;
    body[0] = outer;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq((u64)g.blocks[3].term.kind, (u64)cfg::TermKind::CondBranch, m)) { return -1; }
    if(!testing::expect_eq((u64)g.blocks[3].term.then_target, (u64)5, m)) { return -2; }
    if(!testing::expect_eq((u64)g.blocks[3].term.else_target, (u64)6, m)) { return -3; }
    if(!testing::expect_eq((u64)g.blocks[7].term.goto_target, (u64)4, m)) { return -4; }
    if(!testing::expect_eq(g.blocks[4].predecessors.len, (u64)2, m)) { return -5; }
    return 0;
}

fn i32 for_break(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] fbody;
    fbody[0] = mk_break(a);
    ast::AstNode* fr = mk_for(a, mk_expr_stmt(a, mk_int_lit(a)), mk_int_lit(a), mk_expr_stmt(a, mk_int_lit(a)), mk_block(a, &fbody[0], 1));
    ast::AstNode*[1] body;
    body[0] = fr;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq((u64)g.blocks[3].term.goto_target, (u64)5, m)) { return -1; }
    return 0;
}

fn i32 defer_on_continue(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode* s = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode*[1] dbody;
    dbody[0] = s;
    ast::AstNode*[2] wbody;
    wbody[0] = mk_defer(a, mk_block(a, &dbody[0], 1));
    wbody[1] = mk_continue(a);
    ast::AstNode* wh = mk_while(a, mk_int_lit(a), mk_block(a, &wbody[0], 2));
    ast::AstNode*[1] body;
    body[0] = wh;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq(g.blocks[3].stmts.len, (u64)1, m)) { return -1; }
    if(!testing::expect_eq((void*)g.blocks[3].stmts[0], (void*)s, m)) { return -2; }
    if(!testing::expect_eq((u64)g.blocks[3].term.goto_target, (u64)2, m)) { return -3; }
    return 0;
}

fn i32 nested_block_defers(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode* sa = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode* sb = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode*[1] da;
    da[0] = sa;
    ast::AstNode*[1] db;
    db[0] = sb;
    ast::AstNode*[1] inner_s;
    inner_s[0] = mk_defer(a, mk_block(a, &db[0], 1));
    ast::AstNode*[2] outer_s;
    outer_s[0] = mk_defer(a, mk_block(a, &da[0], 1));
    outer_s[1] = mk_block(a, &inner_s[0], 1);
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &outer_s[0], 2)));
    if(!testing::expect_eq(g.blocks[0].stmts.len, (u64)2, m)) { return -1; }
    if(!testing::expect_eq((void*)g.blocks[0].stmts[0], (void*)sb, m)) { return -2; }
    if(!testing::expect_eq((void*)g.blocks[0].stmts[1], (void*)sa, m)) { return -3; }
    return 0;
}

fn i32 if_then_returns_else_falls(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] then_s;
    then_s[0] = mk_return(a, null);
    ast::AstNode*[1] else_s;
    else_s[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode* iff = mk_if(a, mk_int_lit(a), mk_block(a, &then_s[0], 1), mk_block(a, &else_s[0], 1));
    ast::AstNode*[1] body;
    body[0] = iff;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 1)));
    if(!testing::expect_eq((u64)g.blocks[2].term.kind, (u64)cfg::TermKind::Return, m)) { return -1; }
    if(!testing::expect_eq((u64)g.blocks[3].term.kind, (u64)cfg::TermKind::Goto, m)) { return -2; }
    if(!testing::expect_eq((u64)g.blocks[3].term.goto_target, (u64)4, m)) { return -3; }
    if(!testing::expect_eq(g.blocks[4].predecessors.len, (u64)1, m)) { return -4; }
    return 0;
}

fn i32 comp_stmt_emits_nothing(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode* s = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode*[2] body;
    body[0] = mk_kind(a, ast::AstKind::ComprunStmt);
    body[1] = s;
    cfg::Cfg* g = cfg::build_cfg(mm, mk_fn(a, null, mk_block(a, &body[0], 2)));
    if(!testing::expect_eq(g.blocks[0].stmts.len, (u64)1, m)) { return -1; }
    if(!testing::expect_eq((void*)g.blocks[0].stmts[0], (void*)s, m)) { return -2; }
    return 0;
}

fn i32 non_void_missing_return_errors(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] body;
    body[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode* ret_ty = mk_prim_type(a, types::prim_i32());
    ast::FnDeclNode* func = mk_fn(a, ret_ty, mk_block(a, &body[0], 1));
    func.cfg = (void*)cfg::build_cfg(mm, func);
    bool ok = cfg::check_return_paths(mm, func);
    if(ok) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)1, m)) { return -2; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "without a return", m)) { return -3; }
    if(mm.diag.entries[0].is_warning) { return -4; }
    return 0;
}

fn i32 non_void_all_paths_return_ok(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] then_s;
    then_s[0] = mk_return(a, mk_int_lit(a));
    ast::AstNode*[1] else_s;
    else_s[0] = mk_return(a, mk_int_lit(a));
    ast::AstNode* iff = mk_if(a, mk_int_lit(a), mk_block(a, &then_s[0], 1), mk_block(a, &else_s[0], 1));
    ast::AstNode*[1] body;
    body[0] = iff;
    ast::AstNode* ret_ty = mk_prim_type(a, types::prim_i32());
    ast::FnDeclNode* func = mk_fn(a, ret_ty, mk_block(a, &body[0], 1));
    func.cfg = (void*)cfg::build_cfg(mm, func);
    bool ok = cfg::check_return_paths(mm, func);
    if(!ok) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)0, m)) { return -2; }
    return 0;
}

fn i32 void_skips_return_check(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] body;
    body[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::FnDeclNode* func = mk_fn(a, null, mk_block(a, &body[0], 1));
    func.cfg = (void*)cfg::build_cfg(mm, func);
    bool ok = cfg::check_return_paths(mm, func);
    if(!ok) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)0, m)) { return -2; }
    return 0;
}

fn i32 unreachable_after_both_return_warns(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] then_s;
    then_s[0] = mk_return(a, null);
    ast::AstNode*[1] else_s;
    else_s[0] = mk_return(a, null);
    ast::AstNode* iff = mk_if(a, mk_int_lit(a), mk_block(a, &then_s[0], 1), mk_block(a, &else_s[0], 1));
    ast::AstNode* dead = mk_expr_stmt(a, mk_int_lit(a));
    dead.h.src_pos = 4242;
    ast::AstNode*[2] body;
    body[0] = iff;
    body[1] = dead;
    ast::FnDeclNode* func = mk_fn(a, null, mk_block(a, &body[0], 2));
    func.cfg = (void*)cfg::build_cfg(mm, func);
    cfg::check_unreachable(mm, func);
    if(!testing::expect_eq(mm.diag.entries.len, (u64)1, m)) { return -1; }
    if(!testing::expect_eq((u64)mm.diag.entries[0].src_pos, (u64)4242, m)) { return -2; }
    if(!mm.diag.entries[0].is_warning) { return -3; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "unreachable", m)) { return -4; }
    return 0;
}

fn i32 no_unreachable_clean(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] body;
    body[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::FnDeclNode* func = mk_fn(a, null, mk_block(a, &body[0], 1));
    func.cfg = (void*)cfg::build_cfg(mm, func);
    cfg::check_unreachable(mm, func);
    if(!testing::expect_eq(mm.diag.entries.len, (u64)0, m)) { return -1; }
    return 0;
}

fn i32 build_all_functions_reports(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] fbody;
    fbody[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::AstNode* ret_ty = mk_prim_type(a, types::prim_i32());
    ast::FnDeclNode* func = mk_fn(a, ret_ty, mk_block(a, &fbody[0], 1));
    ast::AstNode*[1] root_stmts;
    root_stmts[0] = (ast::AstNode*)func;
    mm.root_node = mk_block(a, &root_stmts[0], 1);
    cfg::build_all_functions(mm);
    if(func.cfg == null) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)1, m)) { return -2; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "without a return", m)) { return -3; }
    return 0;
}

fn i32 switch_all_arms_return_ok(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] arm_s;
    arm_s[0] = mk_return(a, mk_int_lit(a));
    ast::AstNode*[1] els;
    els[0] = mk_return(a, mk_int_lit(a));
    ast::AstNode*[1] l0;
    l0[0] = mk_int_lit(a);
    ast::SwitchArm[1] arms;
    set_arm(&arms[0], &l0[0], 1, mk_block(a, &arm_s[0], 1));
    ast::SwitchArm[] arms_slice = {&arms[0], 1};
    ast::AstNode* sw = mk_switch(a, mk_int_lit(a), arms_slice, mk_block(a, &els[0], 1));
    ast::AstNode*[1] body;
    body[0] = sw;
    ast::AstNode* ret_ty = mk_prim_type(a, types::prim_i32());
    ast::FnDeclNode* func = mk_fn(a, ret_ty, mk_block(a, &body[0], 1));
    func.cfg = (void*)cfg::build_cfg(mm, func);
    bool ok = cfg::check_return_paths(mm, func);
    if(!ok) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)0, m)) { return -2; }
    return 0;
}

fn i32 switch_no_else_missing_return_errors(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] arm_s;
    arm_s[0] = mk_return(a, mk_int_lit(a));
    ast::AstNode*[1] l0;
    l0[0] = mk_int_lit(a);
    ast::SwitchArm[1] arms;
    set_arm(&arms[0], &l0[0], 1, mk_block(a, &arm_s[0], 1));
    ast::SwitchArm[] arms_slice = {&arms[0], 1};
    ast::AstNode* sw = mk_switch(a, mk_int_lit(a), arms_slice, null);
    ast::AstNode*[1] body;
    body[0] = sw;
    ast::AstNode* ret_ty = mk_prim_type(a, types::prim_i32());
    ast::FnDeclNode* func = mk_fn(a, ret_ty, mk_block(a, &body[0], 1));
    func.cfg = (void*)cfg::build_cfg(mm, func);
    bool ok = cfg::check_return_paths(mm, func);
    if(ok) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)1, m)) { return -2; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "without a return", m)) { return -3; }
    return 0;
}

fn i32 build_all_functions_multiple(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[1] good_b;
    good_b[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::FnDeclNode* good = mk_fn(a, null, mk_block(a, &good_b[0], 1));
    ast::AstNode*[1] bad_b;
    bad_b[0] = mk_expr_stmt(a, mk_int_lit(a));
    ast::FnDeclNode* bad = mk_fn(a, mk_prim_type(a, types::prim_i32()), mk_block(a, &bad_b[0], 1));
    ast::AstNode*[3] root_stmts;
    root_stmts[0] = (ast::AstNode*)good;
    root_stmts[1] = (ast::AstNode*)bad;
    root_stmts[2] = mk_kind(a, ast::AstKind::VarDecl);
    mm.root_node = mk_block(a, &root_stmts[0], 3);
    cfg::build_all_functions(mm);
    if(good.cfg == null) { return -1; }
    if(bad.cfg == null) { return -2; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)1, m)) { return -3; }
    return 0;
}

fn i32 code_after_return_warns(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode* dead = mk_expr_stmt(a, mk_int_lit(a));
    dead.h.src_pos = 777;
    ast::AstNode*[2] body;
    body[0] = mk_return(a, null);
    body[1] = dead;
    ast::FnDeclNode* func = mk_fn(a, null, mk_block(a, &body[0], 2));
    cfg::build_cfg(mm, func);
    if(!testing::expect_eq(mm.diag.entries.len, (u64)1, m)) { return -1; }
    if(!testing::expect_eq((u64)mm.diag.entries[0].src_pos, (u64)777, m)) { return -2; }
    if(!mm.diag.entries[0].is_warning) { return -3; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "unreachable", m)) { return -4; }
    return 0;
}

fn i32 code_after_break_warns(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode* dead = mk_expr_stmt(a, mk_int_lit(a));
    dead.h.src_pos = 888;
    ast::AstNode*[2] wbody;
    wbody[0] = mk_break(a);
    wbody[1] = dead;
    ast::AstNode* wh = mk_while(a, mk_int_lit(a), mk_block(a, &wbody[0], 2));
    ast::AstNode*[1] body;
    body[0] = wh;
    ast::FnDeclNode* func = mk_fn(a, null, mk_block(a, &body[0], 1));
    cfg::build_cfg(mm, func);
    if(!testing::expect_eq(mm.diag.entries.len, (u64)1, m)) { return -1; }
    if(!testing::expect_eq((u64)mm.diag.entries[0].src_pos, (u64)888, m)) { return -2; }
    return 0;
}

fn i32 code_after_continue_warns(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode* dead = mk_expr_stmt(a, mk_int_lit(a));
    dead.h.src_pos = 999;
    ast::AstNode*[2] wbody;
    wbody[0] = mk_continue(a);
    wbody[1] = dead;
    ast::AstNode* wh = mk_while(a, mk_int_lit(a), mk_block(a, &wbody[0], 2));
    ast::AstNode*[1] body;
    body[0] = wh;
    ast::FnDeclNode* func = mk_fn(a, null, mk_block(a, &body[0], 1));
    cfg::build_cfg(mm, func);
    if(!testing::expect_eq(mm.diag.entries.len, (u64)1, m)) { return -1; }
    if(!testing::expect_eq((u64)mm.diag.entries[0].src_pos, (u64)999, m)) { return -2; }
    return 0;
}

fn i32 code_after_return_single_warning(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode* first_dead = mk_expr_stmt(a, mk_int_lit(a));
    first_dead.h.src_pos = 500;
    ast::AstNode*[3] body;
    body[0] = mk_return(a, null);
    body[1] = first_dead;
    body[2] = mk_expr_stmt(a, mk_int_lit(a));
    ast::FnDeclNode* func = mk_fn(a, null, mk_block(a, &body[0], 3));
    cfg::build_cfg(mm, func);
    if(!testing::expect_eq(mm.diag.entries.len, (u64)1, m)) { return -1; }
    if(!testing::expect_eq((u64)mm.diag.entries[0].src_pos, (u64)500, m)) { return -2; }
    return 0;
}

fn i32 return_at_block_end_no_warning(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    ast::AstNode*[2] body;
    body[0] = mk_expr_stmt(a, mk_int_lit(a));
    body[1] = mk_return(a, null);
    ast::FnDeclNode* func = mk_fn(a, null, mk_block(a, &body[0], 2));
    cfg::build_cfg(mm, func);
    if(!testing::expect_eq(mm.diag.entries.len, (u64)0, m)) { return -1; }
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
    testing::add(suite, "if_else_merge",                   &if_else_merge);
    testing::add(suite, "if_no_else",                      &if_no_else);
    testing::add(suite, "if_both_return_after_unreachable", &if_both_return_after_unreachable);
    testing::add(suite, "while_loop_edges",                &while_loop_edges);
    testing::add(suite, "while_break",                     &while_break);
    testing::add(suite, "while_continue",                  &while_continue);
    testing::add(suite, "for_loop_edges",                  &for_loop_edges);
    testing::add(suite, "for_no_cond",                     &for_no_cond);
    testing::add(suite, "for_continue_targets_post",       &for_continue_targets_post);
    testing::add(suite, "switch_arms_dispatch",            &switch_arms_dispatch);
    testing::add(suite, "switch_no_else_default_unreachable", &switch_no_else_default_unreachable);
    testing::add(suite, "switch_break_fresh_continuation", &switch_break_fresh_continuation);
    testing::add(suite, "return_fresh_unreachable",        &return_fresh_unreachable);
    testing::add(suite, "return_value_recorded",           &return_value_recorded);
    testing::add(suite, "defer_fallthrough",               &defer_fallthrough);
    testing::add(suite, "defer_reverse_order",             &defer_reverse_order);
    testing::add(suite, "defer_on_return",                 &defer_on_return);
    testing::add(suite, "defer_on_break",                  &defer_on_break);
    testing::add(suite, "nested_if_in_while",              &nested_if_in_while);
    testing::add(suite, "continue_through_switch",         &continue_through_switch);
    testing::add(suite, "switch_fallthrough",              &switch_fallthrough);
    testing::add(suite, "if_else_if_chain",                &if_else_if_chain);
    testing::add(suite, "for_break",                       &for_break);
    testing::add(suite, "defer_on_continue",               &defer_on_continue);
    testing::add(suite, "nested_block_defers",             &nested_block_defers);
    testing::add(suite, "if_then_returns_else_falls",      &if_then_returns_else_falls);
    testing::add(suite, "comp_stmt_emits_nothing",         &comp_stmt_emits_nothing);
    testing::add(suite, "non_void_missing_return_errors",  &non_void_missing_return_errors);
    testing::add(suite, "non_void_all_paths_return_ok",    &non_void_all_paths_return_ok);
    testing::add(suite, "void_skips_return_check",         &void_skips_return_check);
    testing::add(suite, "unreachable_after_both_return_warns", &unreachable_after_both_return_warns);
    testing::add(suite, "no_unreachable_clean",            &no_unreachable_clean);
    testing::add(suite, "build_all_functions_reports",     &build_all_functions_reports);
    testing::add(suite, "switch_all_arms_return_ok",       &switch_all_arms_return_ok);
    testing::add(suite, "switch_no_else_missing_return_errors", &switch_no_else_missing_return_errors);
    testing::add(suite, "build_all_functions_multiple",    &build_all_functions_multiple);
    testing::add(suite, "code_after_return_warns",         &code_after_return_warns);
    testing::add(suite, "code_after_break_warns",          &code_after_break_warns);
    testing::add(suite, "code_after_continue_warns",       &code_after_continue_warns);
    testing::add(suite, "code_after_return_single_warning", &code_after_return_single_warning);
    testing::add(suite, "return_at_block_end_no_warning",  &return_at_block_end_no_warning);
    return testing::run();
}
