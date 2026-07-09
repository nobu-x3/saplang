import ast;
import module;
import arena;
import types;
import sys;

export const u32 INVALID_BLOCK = 4294967295;

export enum TermKind : u16 {
    Goto,
    CondBranch,
    Switch,
    Return,
    Unreachable,
}

export struct SwitchTarget {
    ast::AstNode*   label;
    u32             target;
}

export struct Terminator {
    u16             kind;
    u32             src_pos;
    u32             goto_target;
    ast::AstNode*   cond;
    u32             then_target;
    u32             else_target;
    ast::AstNode*   switch_value;
    SwitchTarget[]  switch_arms;
    u32             switch_default;
    ast::AstNode*   return_value;
}

export struct BasicBlock {
    u32             id;
    bool            terminated;
    ast::AstNode*[] stmts;
    u64             stmts_cap;
    Terminator      term;
    u32[]           predecessors;
    u64             pred_cap;
}

export struct Cfg {
    BasicBlock[]    blocks;
    u64             blocks_cap;
    u32             entry;
    u32             exit;
}

struct LoopFrame { u32 header; u32 after; }
struct DeferEntry { ast::AstNode* body; u32 src_pos; }
struct ScopeFrame { DeferEntry[] defers; u64 defer_count; u64 defer_cap; }

struct CfgBuilder {
    Cfg*            cfg;
    arena::Arena*   arena;
    u32             current;
    LoopFrame[]     loop_stack;
    u64             loop_cap;
    ScopeFrame[]    scope_stack;
    u64             scope_cap;
    module::Module* m;
}

export fn Cfg* build_cfg(module::Module* m, ast::FnDeclNode* func) {
    Cfg* g = (Cfg*)arena::alloc(m.arena, sizeof(Cfg));
    sys::memset(g, 0, sizeof(Cfg));

    CfgBuilder builder;
    sys::memset(&builder, 0, sizeof(CfgBuilder));
    builder.cfg = g;
    builder.arena = m.arena;
    builder.m = m;

    g.entry = new_block(g, m.arena);
    g.exit = new_block(g, m.arena);
    builder.current = g.entry;

    push_scope(&builder);
    build_stmt(&builder, func.body);
    if(!block_terminated(&builder, builder.current)) {
        emit_pending_defers_for_exit(&builder);
        if(types::is_void(fn_return_type(func))) {
            terminate_return(&builder, builder.current, null, 0);
        } else {
            terminate_unreachable(&builder, builder.current);
        }
    }
    pop_scope(&builder);
    for(u64 block_index = 0; block_index < g.blocks.len; block_index += 1) {
        if(!g.blocks[block_index].terminated) { terminate_unreachable(&builder, (u32)block_index); }
    }
    compute_predecessors(g, m.arena);
    return g;
}

fn void build_stmt(CfgBuilder* b, ast::AstNode* s) {
    if(s == null) { return; }
    if(((u16)s.h.flags & (u16)ast::AstFlags::HadError) != 0) { return; }
    switch(s.h.kind) {
    case ast::AstKind::BlockStmt:      { build_block(b, (ast::BlockNode*)s); }
    case ast::AstKind::IfStmt:         { build_if(b, (ast::IfNode*)s); }
    case ast::AstKind::WhileStmt:      { build_while(b, (ast::WhileNode*)s); }
    case ast::AstKind::ForStmt:        { build_for(b, (ast::ForNode*)s); }
    case ast::AstKind::SwitchStmt:     { build_switch(b, (ast::SwitchNode*)s); }
    case ast::AstKind::ReturnStmt:     { build_return(b, (ast::ReturnNode*)s); }
    case ast::AstKind::BreakStmt:      { build_break(b, (ast::BreakNode*)s); }
    case ast::AstKind::ContinueStmt:   { build_continue(b, (ast::ContinueNode*)s); }
    case ast::AstKind::DeferStmt:      { register_defer(b, (ast::DeferNode*)s); }
    case ast::AstKind::VarDecl:        { append_stmt(b, s); }
    case ast::AstKind::AssignmentStmt: { append_stmt(b, s); }
    case ast::AstKind::ExprStmt:       { append_stmt(b, s); }
    else { }
    }
}

fn void build_block(CfgBuilder* b, ast::BlockNode* blk) {
    push_scope(b);
    for(u64 stmt_index = 0; stmt_index < blk.stmts.len; stmt_index += 1) {
        build_stmt(b, blk.stmts[stmt_index]);
        if(block_terminated(b, b.current)) { break; }
    }
    if(!block_terminated(b, b.current)) {
        emit_pending_defers(b);
    }
    pop_scope(b);
}

// control-flow builders — filled in subsequent increments

fn void build_if(CfgBuilder* b, ast::IfNode* n) {
    // TODO
}

fn void build_while(CfgBuilder* b, ast::WhileNode* n) {
    // TODO
}

fn void build_for(CfgBuilder* b, ast::ForNode* n) {
    // TODO
}

fn void build_switch(CfgBuilder* b, ast::SwitchNode* n) {
    // TODO
}

fn void build_return(CfgBuilder* b, ast::ReturnNode* n) {
    // TODO
}

fn void build_break(CfgBuilder* b, ast::BreakNode* n) {
    // TODO
}

fn void build_continue(CfgBuilder* b, ast::ContinueNode* n) {
    // TODO
}

fn void register_defer(CfgBuilder* b, ast::DeferNode* n) {
    // TODO
}

fn void emit_pending_defers(CfgBuilder* b) {
    // TODO
}

fn void emit_pending_defers_for_exit(CfgBuilder* b) {
    // TODO
}

// HELPERS

export fn u32 new_block(Cfg* g, arena::Arena* a) {
    if(g.blocks.len == g.blocks_cap) {
        u64 new_cap = 4;
        if(g.blocks_cap > 0) { new_cap = g.blocks_cap * 2; }
        g.blocks.ptr = arena::realloc_grow(a, (void*)g.blocks.ptr, g.blocks.len * sizeof(BasicBlock), new_cap * sizeof(BasicBlock));
        g.blocks_cap = new_cap;
    }
    u32 id = (u32)g.blocks.len;
    BasicBlock* block = &g.blocks[id];
    sys::memset(block, 0, sizeof(BasicBlock));
    block.id = id;
    g.blocks.len += 1;
    return id;
}

fn void append_stmt(CfgBuilder* b, ast::AstNode* stmt) {
    BasicBlock* block = &b.cfg.blocks[b.current];
    if(block.stmts.len == block.stmts_cap) {
        u64 new_cap = 4;
        if(block.stmts_cap > 0) { new_cap = block.stmts_cap * 2; }
        block.stmts.ptr = arena::realloc_grow(b.arena, (void*)block.stmts.ptr, block.stmts.len * sizeof(ast::AstNode*), new_cap * sizeof(ast::AstNode*));
        block.stmts_cap = new_cap;
    }
    block.stmts[block.stmts.len] = stmt;
    block.stmts.len += 1;
}

fn bool block_terminated(CfgBuilder* b, u32 blk) {
    return b.cfg.blocks[blk].terminated;
}

fn void terminate_goto(CfgBuilder* b, u32 blk, u32 target, u32 src_pos) {
    BasicBlock* block = &b.cfg.blocks[blk];
    block.term.kind = (u16)TermKind::Goto;
    block.term.src_pos = src_pos;
    block.term.goto_target = target;
    block.terminated = true;
}

fn void terminate_cond(CfgBuilder* b, u32 blk, ast::AstNode* cond, u32 then_t, u32 else_t, u32 src_pos) {
    BasicBlock* block = &b.cfg.blocks[blk];
    block.term.kind = (u16)TermKind::CondBranch;
    block.term.src_pos = src_pos;
    block.term.cond = cond;
    block.term.then_target = then_t;
    block.term.else_target = else_t;
    block.terminated = true;
}

fn void terminate_switch(CfgBuilder* b, u32 blk, ast::AstNode* value, u32 default_t, SwitchTarget[] arms, u32 src_pos) {
    BasicBlock* block = &b.cfg.blocks[blk];
    block.term.kind = (u16)TermKind::Switch;
    block.term.src_pos = src_pos;
    block.term.switch_value = value;
    block.term.switch_default = default_t;
    block.term.switch_arms = arms;
    block.terminated = true;
}

fn void terminate_return(CfgBuilder* b, u32 blk, ast::AstNode* value, u32 src_pos) {
    BasicBlock* block = &b.cfg.blocks[blk];
    block.term.kind = (u16)TermKind::Return;
    block.term.src_pos = src_pos;
    block.term.return_value = value;
    block.terminated = true;
}

fn void terminate_unreachable(CfgBuilder* b, u32 blk) {
    BasicBlock* block = &b.cfg.blocks[blk];
    block.term.kind = (u16)TermKind::Unreachable;
    block.terminated = true;
}

fn void push_scope(CfgBuilder* b) {
    if(b.scope_stack.len == b.scope_cap) {
        u64 new_cap = 4;
        if(b.scope_cap > 0) { new_cap = b.scope_cap * 2; }
        b.scope_stack.ptr = arena::realloc_grow(b.arena, (void*)b.scope_stack.ptr, b.scope_stack.len * sizeof(ScopeFrame), new_cap * sizeof(ScopeFrame));
        b.scope_cap = new_cap;
    }
    ScopeFrame* frame = &b.scope_stack[b.scope_stack.len];
    sys::memset(frame, 0, sizeof(ScopeFrame));
    b.scope_stack.len += 1;
}

fn void pop_scope(CfgBuilder* b) {
    if(b.scope_stack.len > 0) { b.scope_stack.len -= 1; }
}

fn void add_predecessor(Cfg* g, arena::Arena* a, u32 block_id, u32 pred) {
    BasicBlock* block = &g.blocks[block_id];
    if(block.predecessors.len == block.pred_cap) {
        u64 new_cap = 4;
        if(block.pred_cap > 0) { new_cap = block.pred_cap * 2; }
        block.predecessors.ptr = arena::realloc_grow(a, (void*)block.predecessors.ptr, block.predecessors.len * sizeof(u32), new_cap * sizeof(u32));
        block.pred_cap = new_cap;
    }
    block.predecessors[block.predecessors.len] = pred;
    block.predecessors.len += 1;
}

export fn void compute_predecessors(Cfg* g, arena::Arena* a) {
    for(u64 block_index = 0; block_index < g.blocks.len; block_index += 1) {
        BasicBlock* block = &g.blocks[block_index];
        if(!block.terminated) { continue; }      // kind 0 == Goto; never trust an unterminated block
        u32 kind = (u32)block.term.kind;
        if(kind == (u32)TermKind::Goto) {
            add_predecessor(g, a, block.term.goto_target, (u32)block_index);
        } else if(kind == (u32)TermKind::CondBranch) {
            add_predecessor(g, a, block.term.then_target, (u32)block_index);
            add_predecessor(g, a, block.term.else_target, (u32)block_index);
        } else if(kind == (u32)TermKind::Switch) {
            for(u64 arm_index = 0; arm_index < block.term.switch_arms.len; arm_index += 1) {
                add_predecessor(g, a, block.term.switch_arms[arm_index].target, (u32)block_index);
            }
            add_predecessor(g, a, block.term.switch_default, (u32)block_index);
        }
    }
}

export fn types::Type* fn_return_type(ast::FnDeclNode* func) {
    if(func.return_type == null) { return types::prim_void(); }
    types::Type* t = (types::Type*)func.return_type.h.ty;
    if(t == null) { return types::prim_void(); }
    return t;
}
