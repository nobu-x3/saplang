import ast;
import module;
import arena;
import types;
import diag;
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

struct LoopFrame { u32 header; u32 after; u64 scope_base; }
struct DeferEntry { ast::AstNode* body; u32 src_pos; }
struct ScopeFrame { DeferEntry[] defers; u64 defer_cap; }

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
    // comp* statements are resolved by sema/comptime — no runtime control flow
    case ast::AstKind::ComprunStmt:     { }
    case ast::AstKind::CompinsertStmt:  { }
    case ast::AstKind::CompspliceStmt:  { }
    case ast::AstKind::ComperrorStmt:   { }
    case ast::AstKind::CompwarningStmt: { }
    else { }
    }
}

fn void build_block(CfgBuilder* b, ast::BlockNode* blk) {
    push_scope(b);
    for(u64 stmt_index = 0; stmt_index < blk.stmts.len; stmt_index += 1) {
        build_stmt(b, blk.stmts[stmt_index]);
        if(block_terminated(b, b.current)) {
            if(stmt_index + 1 < blk.stmts.len) {
                u8[] msg = "unreachable code";
                diag::report_warning(&b.m.diag, b.m.arena, blk.stmts[stmt_index + 1].h.src_pos, msg);
            }
            break;
        }
    }
    if(!block_terminated(b, b.current)) {
        run_top_scope_defers(b);
    }
    pop_scope(b);
}

fn void build_if(CfgBuilder* b, ast::IfNode* n) {
    u32 then_blk = new_block(b.cfg, b.arena);
    u32 else_blk = new_block(b.cfg, b.arena);
    u32 after    = new_block(b.cfg, b.arena);

    terminate_cond(b, b.current, n.cond, then_blk, else_blk, n.h.src_pos);

    b.current = then_blk;
    build_stmt(b, n.then_block);
    if(!block_terminated(b, b.current)) { terminate_goto(b, b.current, after, n.h.src_pos); }

    b.current = else_blk;
    if(n.else_block != null) { build_stmt(b, n.else_block); }
    if(!block_terminated(b, b.current)) { terminate_goto(b, b.current, after, n.h.src_pos); }

    b.current = after;
}

fn void build_while(CfgBuilder* b, ast::WhileNode* n) {
    u32 header = new_block(b.cfg, b.arena);
    u32 body   = new_block(b.cfg, b.arena);
    u32 after  = new_block(b.cfg, b.arena);

    terminate_goto(b, b.current, header, n.h.src_pos);
    terminate_cond(b, header, n.cond, body, after, n.h.src_pos);

    push_loop(b, header, after);
    push_scope(b);
    b.current = body;
    build_stmt(b, n.body);
    if(!block_terminated(b, b.current)) {
        run_top_scope_defers(b);
        terminate_goto(b, b.current, header, n.h.src_pos);
    }
    pop_scope(b);
    pop_loop(b);

    b.current = after;
}

fn void build_for(CfgBuilder* b, ast::ForNode* n) {
    push_scope(b);
    if(n.init != null) { build_stmt(b, n.init); }
    u32 header = new_block(b.cfg, b.arena);
    u32 body   = new_block(b.cfg, b.arena);
    u32 post   = new_block(b.cfg, b.arena);
    u32 after  = new_block(b.cfg, b.arena);

    terminate_goto(b, b.current, header, n.h.src_pos);
    if(n.cond != null) {
        terminate_cond(b, header, n.cond, body, after, n.h.src_pos);
    } else {
        terminate_goto(b, header, body, n.h.src_pos);
    }

    push_loop(b, post, after);
    push_scope(b);
    b.current = body;
    build_stmt(b, n.body);
    if(!block_terminated(b, b.current)) {
        run_top_scope_defers(b);
        terminate_goto(b, b.current, post, n.h.src_pos);
    }
    pop_scope(b);
    pop_loop(b);

    b.current = post;
    if(n.post != null) { build_stmt(b, n.post); }
    terminate_goto(b, b.current, header, n.h.src_pos);

    b.current = after;
    pop_scope(b);
}

fn void build_switch(CfgBuilder* b, ast::SwitchNode* n) {
    u32 origin = b.current;
    u32 after = new_block(b.cfg, b.arena);
    u32 def_blk = new_block(b.cfg, b.arena);
    if(n.else_block == null) { terminate_unreachable(b, def_blk); }

    u32* arm_blocks = arena::alloc(b.arena, n.arms.len * sizeof(u32));
    for(u64 arm_index = 0; arm_index < n.arms.len; arm_index += 1) {
        ast::SwitchArm* arm = &n.arms[arm_index];
        if(arm.body == null) {
            arm_blocks[arm_index] = INVALID_BLOCK;
        } else {
            u32 arm_blk = new_block(b.cfg, b.arena);
            arm_blocks[arm_index] = arm_blk;
            push_loop(b, INVALID_BLOCK, after);
            push_scope(b);
            b.current = arm_blk;
            build_stmt(b, arm.body);
            if(!block_terminated(b, b.current)) {
                run_top_scope_defers(b);
                terminate_goto(b, b.current, after, n.h.src_pos);
            }
            pop_scope(b);
            pop_loop(b);
        }
    }

    SwitchTarget[] arms = {null, 0};
    u64 arms_cap = 0;
    for(u64 arm_index = 0; arm_index < n.arms.len; arm_index += 1) {
        u32 target = arm_blocks[arm_index];
        if(target == INVALID_BLOCK) {                       // null body: fall through to the next bodied arm
            u64 look = arm_index + 1;
            while(look < n.arms.len) {
                if(arm_blocks[look] != INVALID_BLOCK) { break; }
                look += 1;
            }
            if(look < n.arms.len) { target = arm_blocks[look]; } else { target = after; }
        }
        ast::SwitchArm* arm = &n.arms[arm_index];
        for(u64 label_index = 0; label_index < arm.labels.len; label_index += 1) {
            arms = push_switch_target(arms, &arms_cap, b.arena, arm.labels[label_index], target);
        }
    }

    if(n.else_block != null) {
        push_scope(b);
        b.current = def_blk;
        build_stmt(b, n.else_block);
        if(!block_terminated(b, b.current)) {
            run_top_scope_defers(b);
            terminate_goto(b, b.current, after, n.h.src_pos);
        }
        pop_scope(b);
    }

    terminate_switch(b, origin, n.discriminant, def_blk, arms, n.h.src_pos);
    b.current = after;
}

fn void build_return(CfgBuilder* b, ast::ReturnNode* n) {
    emit_pending_defers_for_exit(b);
    terminate_return(b, b.current, n.expr, n.h.src_pos);
    b.current = new_block(b.cfg, b.arena);
    terminate_unreachable(b, b.current);
}

fn void build_break(CfgBuilder* b, ast::BreakNode* n) {
    LoopFrame* frame = top_loop(b);
    if(frame == null) { return; }
    u32 after = frame.after;
    u64 base = frame.scope_base;
    emit_pending_defers_through_loop(b, base);
    terminate_goto(b, b.current, after, n.h.src_pos);
    b.current = new_block(b.cfg, b.arena);
    terminate_unreachable(b, b.current);
}

fn void build_continue(CfgBuilder* b, ast::ContinueNode* n) {
    LoopFrame* frame = nearest_loop(b);
    if(frame == null) { return; }
    u32 header = frame.header;
    u64 base = frame.scope_base;
    emit_pending_defers_through_loop(b, base);
    terminate_goto(b, b.current, header, n.h.src_pos);
    b.current = new_block(b.cfg, b.arena);
    terminate_unreachable(b, b.current);
}

fn void register_defer(CfgBuilder* b, ast::DeferNode* n) {
    push_defer(current_scope(b), b.arena, n.body, n.h.src_pos);
}

// Snapshot the pending defer bodies (LIFO) before building them: build_stmt pushes scopes and may realloc the
// scope stack, which would dangle a live pointer into it.
fn void run_pending_defers(CfgBuilder* b, i64 from_scope, i64 to_scope) {
    if(from_scope < to_scope) { return; }
    u64 total = 0;
    for(i64 scope_index = from_scope; scope_index >= to_scope; scope_index -= 1) { total += b.scope_stack[(u64)scope_index].defers.len; }
    if(total == 0) { return; }
    ast::AstNode** bodies = (ast::AstNode**)arena::alloc(b.arena, total * sizeof(ast::AstNode*));
    u64 count = 0;
    for(i64 scope_index = from_scope; scope_index >= to_scope; scope_index -= 1) {
        ScopeFrame* sc = &b.scope_stack[(u64)scope_index];
        for(i64 defer_index = (i64)sc.defers.len - 1; defer_index >= 0; defer_index -= 1) {
            bodies[count] = sc.defers[(u64)defer_index].body;
            count += 1;
        }
    }
    for(u64 i = 0; i < count; i += 1) {
        if(block_terminated(b, b.current)) { break; }
        build_stmt(b, bodies[i]);
    }
}

fn void run_top_scope_defers(CfgBuilder* b) {
    i64 top = (i64)b.scope_stack.len - 1;
    run_pending_defers(b, top, top);
}

fn void emit_pending_defers_for_exit(CfgBuilder* b) {
    run_pending_defers(b, (i64)b.scope_stack.len - 1, 0);
}

fn void emit_pending_defers_through_loop(CfgBuilder* b, u64 scope_base) {
    run_pending_defers(b, (i64)b.scope_stack.len - 1, (i64)scope_base);
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

fn ScopeFrame* current_scope(CfgBuilder* b) {
    return &b.scope_stack[b.scope_stack.len - 1];
}

fn void push_defer(ScopeFrame* sc, arena::Arena* a, ast::AstNode* body, u32 src_pos) {
    if(sc.defers.len == sc.defer_cap) {
        u64 new_cap = 4;
        if(sc.defer_cap > 0) { new_cap = sc.defer_cap * 2; }
        sc.defers.ptr = arena::realloc_grow(a, (void*)sc.defers.ptr, sc.defers.len * sizeof(DeferEntry), new_cap * sizeof(DeferEntry));
        sc.defer_cap = new_cap;
    }
    DeferEntry e;
    e.body = body;
    e.src_pos = src_pos;
    sc.defers[sc.defers.len] = e;
    sc.defers.len += 1;
}

fn void push_loop(CfgBuilder* b, u32 header, u32 after) {
    if(b.loop_stack.len == b.loop_cap) {
        u64 new_cap = 4;
        if(b.loop_cap > 0) { new_cap = b.loop_cap * 2; }
        b.loop_stack.ptr = arena::realloc_grow(b.arena, (void*)b.loop_stack.ptr, b.loop_stack.len * sizeof(LoopFrame), new_cap * sizeof(LoopFrame));
        b.loop_cap = new_cap;
    }
    LoopFrame frame;
    frame.header = header;
    frame.after = after;
    frame.scope_base = b.scope_stack.len;
    b.loop_stack[b.loop_stack.len] = frame;
    b.loop_stack.len += 1;
}

fn void pop_loop(CfgBuilder* b) {
    if(b.loop_stack.len > 0) { b.loop_stack.len -= 1; }
}

fn LoopFrame* top_loop(CfgBuilder* b) {
    if(b.loop_stack.len == 0) { return null; }
    return &b.loop_stack[b.loop_stack.len - 1];
}

fn LoopFrame* nearest_loop(CfgBuilder* b) {
    for(i64 frame_index = (i64)b.loop_stack.len - 1; frame_index >= 0; frame_index -= 1) {
        if(b.loop_stack[(u64)frame_index].header != INVALID_BLOCK) { return &b.loop_stack[(u64)frame_index]; }
    }
    return null;
}

fn SwitchTarget[] push_switch_target(SwitchTarget[] arms, u64* cap, arena::Arena* a, ast::AstNode* label, u32 target) {
    if(arms.len == *cap) {
        u64 new_cap = 4;
        if(*cap > 0) { new_cap = *cap * 2; }
        arms.ptr = arena::realloc_grow(a, (void*)arms.ptr, arms.len * sizeof(SwitchTarget), new_cap * sizeof(SwitchTarget));
        *cap = new_cap;
    }
    SwitchTarget t;
    t.label = label;
    t.target = target;
    arms[arms.len] = t;
    arms.len += 1;
    return arms;
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
            add_predecessor(g, a, block.term.switch_default, (u32)block_index);
            for(u64 arm_index = 0; arm_index < block.term.switch_arms.len; arm_index += 1) {
                u32 target = block.term.switch_arms[arm_index].target;
                if(target == block.term.switch_default) { continue; }
                bool seen = false;
                for(u64 prev = 0; prev < arm_index; prev += 1) {
                    if(block.term.switch_arms[prev].target == target) { seen = true; }
                }
                if(!seen) { add_predecessor(g, a, target, (u32)block_index); }
            }
        }
    }
}

export fn types::Type* fn_return_type(ast::FnDeclNode* func) {
    if(func.return_type == null) { return types::prim_void(); }
    types::Type* t = (types::Type*)func.return_type.h.ty;
    if(t == null) { return types::prim_void(); }
    return t;
}

// ANALYSES

fn u64 mark_successor(bool[] reachable, u32* stack, u64 sp, u32 target) {
    if(!reachable[target]) {
        reachable[target] = true;
        stack[sp] = target;
        sp += 1;
    }
    return sp;
}

fn bool[] bfs_reachable_from(Cfg* g, arena::Arena* a, u32 entry) {
    bool[] reachable;
    reachable.ptr = arena::alloc(a, g.blocks.len * sizeof(bool));
    reachable.len = g.blocks.len;
    for(u64 block_index = 0; block_index < reachable.len; block_index += 1) { reachable[block_index] = false; }

    u32* stack = arena::alloc(a, g.blocks.len * sizeof(u32));
    u64 sp = 0;
    reachable[entry] = true;
    stack[0] = entry;
    sp = 1;
    while(sp > 0) {
        sp -= 1;
        u32 blk = stack[sp];
        Terminator* t = &g.blocks[blk].term;
        u32 kind = (u32)t.kind;
        if(kind == (u32)TermKind::Goto) {
            sp = mark_successor(reachable, stack, sp, t.goto_target);
        } else if(kind == (u32)TermKind::CondBranch) {
            sp = mark_successor(reachable, stack, sp, t.then_target);
            sp = mark_successor(reachable, stack, sp, t.else_target);
        } else if(kind == (u32)TermKind::Switch) {
            sp = mark_successor(reachable, stack, sp, t.switch_default);
            for(u64 arm_index = 0; arm_index < t.switch_arms.len; arm_index += 1) {
                sp = mark_successor(reachable, stack, sp, t.switch_arms[arm_index].target);
            }
        }
    }
    return reachable;
}

export fn bool check_return_paths(module::Module* m, ast::FnDeclNode* func) {
    if(types::is_void(fn_return_type(func))) { return true; }
    Cfg* g = (Cfg*)func.cfg;
    bool[] reachable = bfs_reachable_from(g, m.arena, g.entry);
    for(u64 block_index = 0; block_index < g.blocks.len; block_index += 1) {
        if(!reachable[block_index]) { continue; }
        if((u32)g.blocks[block_index].term.kind == (u32)TermKind::Unreachable) {
            u8[] msg = "function may exit without a return statement";
            diag::report(&m.diag, m.arena, func.h.src_pos, msg);
            return false;
        }
    }
    return true;
}

export fn void check_unreachable(module::Module* m, ast::FnDeclNode* func) {
    Cfg* g = (Cfg*)func.cfg;
    bool[] reachable = bfs_reachable_from(g, m.arena, g.entry);
    for(u64 block_index = 0; block_index < g.blocks.len; block_index += 1) {
        if(g.blocks[block_index].id <= 1) { continue; }             // entry/exit
        if(reachable[block_index]) { continue; }
        if(g.blocks[block_index].stmts.len == 0) { continue; }      // synthetic post-terminator continuation
        u32 pos = g.blocks[block_index].stmts[0].h.src_pos;
        u8[] msg = "unreachable code";
        diag::report_warning(&m.diag, m.arena, pos, msg);
    }
}

fn void analyze_function(module::Module* m, ast::FnDeclNode* func) {
    if(func.body == null) { return; }
    func.cfg = (void*)build_cfg(m, func);
    check_return_paths(m, func);
    check_unreachable(m, func);
}

export fn void build_all_functions(module::Module* m) {
    if(m.root_node != null) {
        ast::BlockNode* global_block = (ast::BlockNode*)m.root_node;
        for(u64 stmt_index = 0; stmt_index < global_block.stmts.len; stmt_index += 1) {
            ast::AstNode* node = global_block.stmts[stmt_index];
            if(node.h.kind == ast::AstKind::FnDecl) { analyze_function(m, (ast::FnDeclNode*)node); }
        }
    }
    for(u64 clone_index = 0; clone_index < m.instantiated_fns.len; clone_index += 1) {
        analyze_function(m, m.instantiated_fns[clone_index]);
    }
}
