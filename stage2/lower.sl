import ast;
import cfg;
import module;
import sema;
import types;
import token;
import symbol;
import interner;
import sapir;
import io;
import arena;
import sys;

struct VarDef {
    void*   decl;       // sema::Decl*
    u32     value;
}

// TODO: add sealing + incomplete-phi fields once control-flow lowering needs them.
struct BlockState {
    VarDef[]    defs;
    u64         defs_cap;
}

struct Lower {
    module::Module*     m;
    arena::Arena*       arena;
    sapir::SapirModule* out;
    sapir::SapirFn*     func;
    cfg::Cfg*           g;
    BlockState[]        states;
    u32                 current;
}

export fn sapir::SapirModule* lower_module(module::Module* m) {
    Lower lo;
    sys::memset(&lo, 0, sizeof(Lower));
    lo.m = m;
    lo.arena = m.arena;
    lo.out = sapir::new_module(m.arena, m.name);
    lo.out.src_path = m.path;
    lo.out.line_starts = m.line_starts;
    lo.out.literal_pool = m.literal_pool;

    ast::BlockNode* root = (ast::BlockNode*)m.root_node;
    for(u64 stmt_index = 0; stmt_index < root.stmts.len; stmt_index += 1) {
        ast::AstNode* node = root.stmts[stmt_index];
        if(node.h.kind == ast::AstKind::FnDecl) { lower_fn(&lo, (ast::FnDeclNode*)node); }
    }
    return lo.out;
}

fn void lower_fn(Lower* lo, ast::FnDeclNode* fn_node) {
    if(fn_node.cfg == null) { return; }
    if(sema::is_generic_fn(fn_node)) { return; }        // only monomorphized clones get lowered
    sema::Decl* decl = (sema::Decl*)fn_node.decl;

    sapir::SapirDecl sapir_decl;
    sys::memset(&sapir_decl, 0, sizeof(sapir::SapirDecl));
    sapir_decl.kind = sapir::SapirDeclKind::Fn;
    if(fn_node.is_exported) { sapir_decl.linkage = sapir::SapirLinkage::Export; }
    else { sapir_decl.linkage = sapir::SapirLinkage::Internal; }
    sapir_decl.link_name = mangle_fn(lo, fn_node);
    sapir_decl.ty = decl.ty;
    sapir_decl.global_index = sapir::INVALID_ID;
    u32 decl_index = sapir::add_decl(lo.arena, lo.out, sapir_decl);

    u32 fn_index = sapir::add_fn(lo.arena, lo.out);
    lo.out.decls[decl_index].fn_index = fn_index;
    sapir::SapirFn* func = &lo.out.fns[fn_index];
    func.decl_index = decl_index;
    func.name = fn_node.name;
    func.src_pos = fn_node.h.src_pos;
    func.param_count = (u32)fn_node.params.len;

    cfg::Cfg* g = (cfg::Cfg*)fn_node.cfg;
    lo.func = func;
    lo.g = g;
    func.entry = g.entry;

    for(u64 block_index = 0; block_index < g.blocks.len; block_index += 1) {
        sapir::new_block(lo.arena, func);
    }
    lo.states.ptr = (BlockState*)arena::alloc(lo.arena, g.blocks.len * sizeof(BlockState));
    lo.states.len = g.blocks.len;
    sys::memset(lo.states.ptr, 0, g.blocks.len * sizeof(BlockState));
    for(u64 block_index = 0; block_index < g.blocks.len; block_index += 1) {
        cfg::BasicBlock* cfg_block = &g.blocks[block_index];
        for(u64 pred_index = 0; pred_index < cfg_block.predecessors.len; pred_index += 1) {
            sapir::add_pred(lo.arena, func, (u32)block_index, cfg_block.predecessors[pred_index]);
        }
    }

    for(u64 block_index = 0; block_index < g.blocks.len; block_index += 1) {
        lo.current = (u32)block_index;
        func.blocks[block_index].body_start = (u32)func.insts.len;
        if((u32)block_index == g.entry) { emit_params(lo, fn_node); }
        cfg::BasicBlock* cfg_block = &g.blocks[block_index];
        for(u64 s = 0; s < cfg_block.stmts.len; s += 1) { lower_stmt(lo, cfg_block.stmts[s]); }
        lower_terminator(lo, &cfg_block.term);
        func.blocks[block_index].body_end = (u32)func.insts.len;
    }
}

fn void emit_params(Lower* lo, ast::FnDeclNode* fn_node) {
    for(u64 param_index = 0; param_index < fn_node.params.len; param_index += 1) {
        ast::Param* param = &fn_node.params[param_index];
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::Param, (types::Type*)param.resolved_type, param.src_pos);
        inst.a = (u32)param_index;
        u32 value = sapir::add_inst(lo.arena, lo.func, inst);
        write_var(lo, lo.current, param.decl, value);
    }
}

// STATEMENTS /////////////////////////////////////////////////////////////////////

fn void lower_stmt(Lower* lo, ast::AstNode* s) {
    switch(s.h.kind) {
    case ast::AstKind::VarDecl:        { lower_var_decl(lo, (ast::VarDeclNode*)s); }
    case ast::AstKind::AssignmentStmt: { lower_assignment(lo, (ast::AssignmentNode*)s); }
    case ast::AstKind::ExprStmt:       { lower_expr(lo, ((ast::ExprStmtNode*)s).expr); }
    else { }
    }
}

fn void lower_var_decl(Lower* lo, ast::VarDeclNode* v) {
    if(v.init == null || v.init.h.kind == ast::AstKind::UndefinedLit) {
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::Undef, (types::Type*)v.h.ty, v.h.src_pos);
        write_var(lo, lo.current, v.decl, sapir::add_inst(lo.arena, lo.func, inst));
        return;
    }
    write_var(lo, lo.current, v.decl, lower_expr(lo, v.init));
}

fn void lower_assignment(Lower* lo, ast::AssignmentNode* a) {
    if(a.lhs.h.kind != ast::AstKind::Ident) { return; }     // TODO: member / index / deref lvalues
    void* target = ((ast::IdentNode*)a.lhs).resolved;
    u32 rhs = lower_expr(lo, a.rhs);
    sapir::Opcode combine = compound_opcode(a.op);
    if(combine != sapir::Opcode::INVALID) {
        u32 current_value = read_var(lo, lo.current, target);
        sapir::Inst inst = sapir::new_inst(combine, (types::Type*)a.lhs.h.ty, a.h.src_pos);
        inst.a = current_value;
        inst.b = rhs;
        rhs = sapir::add_inst(lo.arena, lo.func, inst);
    }
    write_var(lo, lo.current, target, rhs);
}

// EXPRESSIONS ////////////////////////////////////////////////////////////////////

fn u32 lower_expr(Lower* lo, ast::AstNode* e) {
    switch(e.h.kind) {
    case ast::AstKind::IntLit: {
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::ConstInt, (types::Type*)e.h.ty, e.h.src_pos);
        inst.imm = ((ast::IntLitNode*)e).value;
        return sapir::add_inst(lo.arena, lo.func, inst);
    }
    case ast::AstKind::FloatLit: {
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::ConstFloat, (types::Type*)e.h.ty, e.h.src_pos);
        f64 value = ((ast::FloatLitNode*)e).value;
        inst.imm = *(u64*)&value;
        return sapir::add_inst(lo.arena, lo.func, inst);
    }
    case ast::AstKind::BoolLit: {
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::ConstBool, types::prim_bool(), e.h.src_pos);
        if(((ast::BoolLitNode*)e).value) { inst.imm = 1; }
        return sapir::add_inst(lo.arena, lo.func, inst);
    }
    case ast::AstKind::CharLit: {
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::ConstInt, (types::Type*)e.h.ty, e.h.src_pos);
        inst.imm = (u64)((ast::CharLitNode*)e).value;
        return sapir::add_inst(lo.arena, lo.func, inst);
    }
    case ast::AstKind::NullLit: {
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::ConstNull, (types::Type*)e.h.ty, e.h.src_pos);
        return sapir::add_inst(lo.arena, lo.func, inst);
    }
    case ast::AstKind::Ident: {
        return read_var(lo, lo.current, ((ast::IdentNode*)e).resolved);
    }
    case ast::AstKind::BinaryOp: { return lower_binary(lo, (ast::BinaryOpNode*)e); }
    case ast::AstKind::UnaryOp:  { return lower_unary(lo, (ast::UnaryOpNode*)e); }
    else {
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::Undef, (types::Type*)e.h.ty, e.h.src_pos);
        return sapir::add_inst(lo.arena, lo.func, inst);
    }
    }
    return sapir::INVALID_ID;
}

fn u32 lower_binary(Lower* lo, ast::BinaryOpNode* n) {
    u32 lhs = lower_expr(lo, n.lhs);
    u32 rhs = lower_expr(lo, n.rhs);
    sapir::Inst inst = sapir::new_inst(binary_opcode(n.op), (types::Type*)n.h.ty, n.h.src_pos);
    inst.a = lhs;
    inst.b = rhs;
    return sapir::add_inst(lo.arena, lo.func, inst);
}

fn u32 lower_unary(Lower* lo, ast::UnaryOpNode* n) {
    sapir::Opcode op = sapir::Opcode::INVALID;
    switch(n.op) {
    case token::TokenKind::Minus: { op = sapir::Opcode::Neg; }
    case token::TokenKind::Tilde: { op = sapir::Opcode::BitNot; }
    case token::TokenKind::Bang:  { op = sapir::Opcode::Not; }
    else { }
    }
    if(op == sapir::Opcode::INVALID) {
        // TODO: & / * (address-of, deref) need memory lowering.
        return sapir::add_inst(lo.arena, lo.func, sapir::new_inst(sapir::Opcode::Undef, (types::Type*)n.h.ty, n.h.src_pos));
    }
    u32 operand = lower_expr(lo, n.operand);
    sapir::Inst inst = sapir::new_inst(op, (types::Type*)n.h.ty, n.h.src_pos);
    inst.a = operand;
    return sapir::add_inst(lo.arena, lo.func, inst);
}

// TERMINATORS ////////////////////////////////////////////////////////////////////

fn void lower_terminator(Lower* lo, cfg::Terminator* term) {
    switch(term.kind) {
    case cfg::TermKind::Goto: {
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::Br, types::prim_void(), term.src_pos);
        inst.a = term.goto_target;
        sapir::add_inst(lo.arena, lo.func, inst);
    }
    case cfg::TermKind::Return: {
        u32 value = sapir::INVALID_ID;
        if(term.return_value != null) { value = lower_expr(lo, term.return_value); }
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::Ret, types::prim_void(), term.src_pos);
        inst.a = value;
        sapir::add_inst(lo.arena, lo.func, inst);
    }
    case cfg::TermKind::Unreachable: {
        sapir::add_inst(lo.arena, lo.func, sapir::new_inst(sapir::Opcode::Unreachable, types::prim_void(), term.src_pos));
    }
    else {
        sapir::add_inst(lo.arena, lo.func, sapir::new_inst(sapir::Opcode::Unreachable, types::prim_void(), term.src_pos));
    }
    }
}

// SSA VARIABLE MAP ///////////////////////////////////////////////////////////////

fn void write_var(Lower* lo, u32 block, void* decl, u32 value) {
    BlockState* state = &lo.states[block];
    for(u64 i = 0; i < state.defs.len; i += 1) {
        if(state.defs[i].decl == decl) { state.defs[i].value = value; return; }
    }
    if(state.defs.len == state.defs_cap) {
        u64 new_cap = 4;
        if(state.defs_cap > 0) { new_cap = state.defs_cap * 2; }
        state.defs.ptr = (VarDef*)arena::realloc_grow(lo.arena, (void*)state.defs.ptr, state.defs.len * sizeof(VarDef), new_cap * sizeof(VarDef));
        state.defs_cap = new_cap;
    }
    state.defs[state.defs.len].decl = decl;
    state.defs[state.defs.len].value = value;
    state.defs.len += 1;
}

fn u32 read_var(Lower* lo, u32 block, void* decl) {
    BlockState* state = &lo.states[block];
    for(u64 i = 0; i < state.defs.len; i += 1) {
        if(state.defs[i].decl == decl) { return state.defs[i].value; }
    }
    sapir::SapirBlock* sapir_block = &lo.func.blocks[block];
    if(sapir_block.preds.len == 1) { return read_var(lo, sapir_block.preds[0], decl); }
    sapir::Inst inst = sapir::new_inst(sapir::Opcode::Undef, decl_type(decl), lo.func.src_pos);
    return sapir::add_inst(lo.arena, lo.func, inst);
}

fn types::Type* decl_type(void* decl) {
    return ((sema::Decl*)decl).ty;
}

// MANGLING + OPCODE MAPS ///////////////////////////////////////////////////////////

fn u8[] mangle_fn(Lower* lo, ast::FnDeclNode* fn_node) {
    u8[] name = interner::symbol_str(fn_node.name);
    if(slice_eq(name, "main")) { return "main"; }
    io::OutBuf buf;
    io::outbuf_init(&buf, lo.arena, 32);
    io::outbuf_write(&buf, "__");
    io::outbuf_write(&buf, interner::symbol_str(lo.m.name));
    io::outbuf_write(&buf, "_");
    io::outbuf_write(&buf, name);
    return io::outbuf_bytes(&buf);
}

fn bool slice_eq(u8[] a, u8[] b) {
    if(a.len != b.len) { return false; }
    for(u64 i = 0; i < a.len; i += 1) {
        if(a[i] != b[i]) { return false; }
    }
    return true;
}

fn sapir::Opcode binary_opcode(token::TokenKind op) {
    switch(op) {
    case token::TokenKind::Plus:    { return sapir::Opcode::Add; }
    case token::TokenKind::Minus:   { return sapir::Opcode::Sub; }
    case token::TokenKind::Star:    { return sapir::Opcode::Mul; }
    case token::TokenKind::Slash:   { return sapir::Opcode::Div; }
    case token::TokenKind::Percent: { return sapir::Opcode::Rem; }
    case token::TokenKind::Amp:     { return sapir::Opcode::And; }
    case token::TokenKind::Pipe:    { return sapir::Opcode::Or; }
    case token::TokenKind::Caret:   { return sapir::Opcode::Xor; }
    case token::TokenKind::LShift:  { return sapir::Opcode::Shl; }
    case token::TokenKind::RShift:  { return sapir::Opcode::Shr; }
    case token::TokenKind::EqEq:    { return sapir::Opcode::CmpEq; }
    case token::TokenKind::BangEq:  { return sapir::Opcode::CmpNe; }
    case token::TokenKind::LT:      { return sapir::Opcode::CmpLt; }
    case token::TokenKind::LTEQ:    { return sapir::Opcode::CmpLe; }
    case token::TokenKind::GT:      { return sapir::Opcode::CmpGt; }
    case token::TokenKind::GTEQ:    { return sapir::Opcode::CmpGe; }
    else { return sapir::Opcode::INVALID; }
    }
    return sapir::Opcode::INVALID;
}

fn sapir::Opcode compound_opcode(token::TokenKind op) {
    switch(op) {
    case token::TokenKind::PlusEq:    { return sapir::Opcode::Add; }
    case token::TokenKind::MinusEq:   { return sapir::Opcode::Sub; }
    case token::TokenKind::StarEq:    { return sapir::Opcode::Mul; }
    case token::TokenKind::SlashEq:   { return sapir::Opcode::Div; }
    case token::TokenKind::PercentEq: { return sapir::Opcode::Rem; }
    case token::TokenKind::PipeEq:    { return sapir::Opcode::Or; }
    case token::TokenKind::CaretEq:   { return sapir::Opcode::Xor; }
    else { return sapir::Opcode::INVALID; }
    }
    return sapir::Opcode::INVALID;
}
