import ast;
import cfg;
import module;
import sema;
import types;
import token;
import symbol;
import interner;
import sapir;
import diag;
import io;
import arena;
import sys;

struct VarDef {
    void*   decl;       // sema::Decl*
    u32     value;
}

struct IncompletePhi {
    void*   decl;
    u32     phi;
}

// A local/param that lives in memory (address-taken or aggregate): read/written via Load/Store.
struct MemVar {
    void*   decl;       // sema::Decl*
    u32     alloca;     // entry-block alloca inst id; INVALID_ID until emitted
}

struct BlockState {
    VarDef[]        defs;
    u64             defs_cap;
    bool            sealed;
    IncompletePhi[] incomplete;
    u64             incomplete_cap;
    u32             cfg_preds_remaining;    // distinct CFG preds not yet lowered; seal at 0 (short-circuit blocks seal manually)
}

struct Lower {
    module::Module*     m;
    arena::Arena*       arena;
    sapir::SapirModule* out;
    sapir::SapirFn*     func;
    cfg::Cfg*           g;
    BlockState[]        states;
    u64                 states_cap;
    u32                 current;
    u32                 cfg_block_count;
    void*[]             local_decls;    // params + locals of the current fn; anything else is a global/fn ref
    u64                 local_decls_cap;
    MemVar[]            mem_vars;
    u64                 mem_vars_cap;
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
    lo.cfg_block_count = (u32)g.blocks.len;
    lo.local_decls.ptr = null;
    lo.local_decls.len = 0;
    lo.local_decls_cap = 0;
    lo.mem_vars.ptr = null;
    lo.mem_vars.len = 0;
    lo.mem_vars_cap = 0;
    collect_mem_vars(lo, fn_node, g);

    lo.states.ptr = null;
    lo.states.len = 0;
    lo.states_cap = 0;
    for(u64 block_index = 0; block_index < g.blocks.len; block_index += 1) {
        new_sapir_block(lo);
    }
    for(u64 block_index = 0; block_index < g.blocks.len; block_index += 1) {
        lo.states[block_index].cfg_preds_remaining = distinct_pred_count(&g.blocks[block_index]);
    }
    for(u64 block_index = 0; block_index < g.blocks.len; block_index += 1) {
        if(lo.states[block_index].cfg_preds_remaining == 0) { seal_block(lo, (u32)block_index); }
    }

    lo.current = sapir::INVALID_ID;
    for(u64 block_index = 0; block_index < lo.cfg_block_count; block_index += 1) {
        switch_to_block(lo, (u32)block_index);
        if((u32)block_index == g.entry) { emit_mem_var_allocas(lo); emit_params(lo, fn_node); }
        cfg::BasicBlock* cfg_block = &g.blocks[block_index];
        u64 stmt_cut = cfg_block.stmts.len;
        if(cfg_block.term.kind == cfg::TermKind::Return && (u64)cfg_block.term.defer_start < stmt_cut) { stmt_cut = (u64)cfg_block.term.defer_start; }
        for(u64 s = 0; s < stmt_cut; s += 1) { lower_stmt(lo, cfg_block.stmts[s]); }
        lower_terminator(lo, cfg_block);
        seal_cfg_successors(lo, &cfg_block.term);
    }
    func.blocks[lo.current].body_end = (u32)func.insts.len;

    remove_trivial_phis(lo);
}

fn u32 new_sapir_block(Lower* lo) {
    u32 id = sapir::new_block(lo.arena, lo.func);
    if(lo.states.len == lo.states_cap) {
        u64 new_cap = 16;
        if(lo.states_cap > 0) { new_cap = lo.states_cap * 2; }
        lo.states.ptr = (BlockState*)arena::realloc_grow(lo.arena, (void*)lo.states.ptr, lo.states.len * sizeof(BlockState), new_cap * sizeof(BlockState));
        lo.states_cap = new_cap;
    }
    sys::memset(&lo.states[id], 0, sizeof(BlockState));
    lo.states.len += 1;
    return id;
}

// Closes the previously-open block's instruction range and opens block's.
fn void switch_to_block(Lower* lo, u32 block) {
    if(lo.current != sapir::INVALID_ID) { lo.func.blocks[lo.current].body_end = (u32)lo.func.insts.len; }
    lo.current = block;
    lo.func.blocks[block].body_start = (u32)lo.func.insts.len;
}

fn u32 distinct_pred_count(cfg::BasicBlock* block) {
    u32 count = 0;
    for(u64 i = 0; i < block.predecessors.len; i += 1) {
        bool seen = false;
        for(u64 j = 0; j < i; j += 1) {
            if(block.predecessors[j] == block.predecessors[i]) { seen = true; break; }
        }
        if(!seen) { count += 1; }
    }
    return count;
}

fn void emit_params(Lower* lo, ast::FnDeclNode* fn_node) {
    for(u64 param_index = 0; param_index < fn_node.params.len; param_index += 1) {
        ast::Param* param = &fn_node.params[param_index];
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::Param, (types::Type*)param.resolved_type, param.src_pos);
        inst.a = (u32)param_index;
        u32 value = sapir::add_inst(lo.arena, lo.func, inst);
        u32 slot = mem_alloca(lo, param.decl);
        if(slot != sapir::INVALID_ID) { emit_store(lo, slot, value); }
        else { write_var(lo, lo.current, param.decl, value); }
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
    u32 slot = mem_alloca(lo, v.decl);
    if(slot != sapir::INVALID_ID) {
        if(v.init == null) { emit_zero(lo, slot, decl_type(v.decl)); return; }
        if(v.init.h.kind == ast::AstKind::UndefinedLit) { return; }
        lower_init_into(lo, slot, decl_type(v.decl), v.init);
        return;
    }
    if(v.init == null || v.init.h.kind == ast::AstKind::UndefinedLit) {
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::Undef, decl_type(v.decl), v.h.src_pos);
        write_var(lo, lo.current, v.decl, sapir::add_inst(lo.arena, lo.func, inst));
        return;
    }
    write_var(lo, lo.current, v.decl, lower_expr(lo, v.init));
}

fn void lower_assignment(Lower* lo, ast::AssignmentNode* a) {
    types::Type* lhs_ty = (types::Type*)a.lhs.h.ty;
    if(a.lhs.h.kind == ast::AstKind::Ident) {
        void* target = ((ast::IdentNode*)a.lhs).resolved;
        if(!is_local_decl(lo, target)) {
            diag::report(&lo.m.diag, lo.m.arena, a.h.src_pos, "assignment to a non-local declaration is not yet supported in lowering");
            return;
        }
        u32 slot = mem_alloca(lo, target);
        if(slot != sapir::INVALID_ID) { store_to_addr(lo, slot, lhs_ty, a.op, a.rhs); return; }
        u32 rhs = lower_expr(lo, a.rhs);
        sapir::Opcode combine = compound_opcode(a.op);
        if(combine != sapir::Opcode::INVALID) {
            u32 current_value = read_var(lo, lo.current, target);
            sapir::Inst inst = sapir::new_inst(combine, lhs_ty, a.h.src_pos);
            inst.a = current_value;
            inst.b = rhs;
            rhs = sapir::add_inst(lo.arena, lo.func, inst);
        }
        write_var(lo, lo.current, target, rhs);
        return;
    }
    if(is_lvalue_kind(a.lhs)) {
        store_to_addr(lo, lower_addr(lo, a.lhs), lhs_ty, a.op, a.rhs);
    }
}

fn bool is_lvalue_kind(ast::AstNode* e) {
    if(e.h.kind == ast::AstKind::MemberAccess || e.h.kind == ast::AstKind::ArrayIndex) { return true; }
    if(e.h.kind == ast::AstKind::UnaryOp && ((ast::UnaryOpNode*)e).op == token::TokenKind::Star) { return true; }
    return false;
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
        void* resolved = ((ast::IdentNode*)e).resolved;
        if(!is_local_decl(lo, resolved)) {
            diag::report(&lo.m.diag, lo.m.arena, e.h.src_pos, "reference to a non-local declaration is not yet supported in lowering");
            return sapir::add_inst(lo.arena, lo.func, sapir::new_inst(sapir::Opcode::Undef, (types::Type*)e.h.ty, e.h.src_pos));
        }
        u32 slot = mem_alloca(lo, resolved);
        if(slot != sapir::INVALID_ID) { return emit_load(lo, slot, (types::Type*)e.h.ty); }
        return read_var(lo, lo.current, resolved);
    }
    case ast::AstKind::MemberAccess: {
        ast::MemberAccessNode* n = (ast::MemberAccessNode*)e;
        types::Type* container = (types::Type*)n.base.h.ty;
        if(types::is_ptr(container)) { container = container.data.pointee; }
        if(types::is_slice(container)) { return lower_slice_field(lo, n, (types::Type*)e.h.ty); }
        return emit_load(lo, lower_addr(lo, e), (types::Type*)e.h.ty);
    }
    case ast::AstKind::ArrayIndex: {
        ast::ArrayIndexNode* n = (ast::ArrayIndexNode*)e;
        if(types::is_slice((types::Type*)n.base.h.ty)) {
            return sapir::add_inst(lo.arena, lo.func, sapir::new_inst(sapir::Opcode::Undef, (types::Type*)e.h.ty, e.h.src_pos));  // TODO: slice indexing
        }
        return emit_load(lo, lower_addr(lo, e), (types::Type*)e.h.ty);
    }
    case ast::AstKind::StructLit: {
        u32 temp = emit_temp_alloca(lo, (types::Type*)e.h.ty);
        build_struct_lit(lo, temp, (types::Type*)e.h.ty, (ast::StructLitNode*)e);
        return emit_load(lo, temp, (types::Type*)e.h.ty);
    }
    case ast::AstKind::ArrayLit: {
        u32 temp = emit_temp_alloca(lo, (types::Type*)e.h.ty);
        build_array_lit(lo, temp, (types::Type*)e.h.ty, (ast::ArrayLitNode*)e);
        return emit_load(lo, temp, (types::Type*)e.h.ty);
    }
    case ast::AstKind::Cast: { return lower_cast(lo, (ast::CastNode*)e, (types::Type*)e.h.ty); }
    case ast::AstKind::BinaryOp: {
        ast::BinaryOpNode* n = (ast::BinaryOpNode*)e;
        if(n.op == token::TokenKind::AmpAmp) { return lower_short_circuit(lo, n, true); }
        if(n.op == token::TokenKind::PipePipe) { return lower_short_circuit(lo, n, false); }
        return lower_binary(lo, n);
    }
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
    if(n.op == token::TokenKind::Amp) { return lower_addr(lo, n.operand); }
    if(n.op == token::TokenKind::Star) { return emit_load(lo, lower_expr(lo, n.operand), (types::Type*)n.h.ty); }
    if(n.op == token::TokenKind::Bang) {
        u32 operand = to_bool(lo, (types::Type*)n.operand.h.ty, lower_expr(lo, n.operand));
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::Not, types::prim_bool(), n.h.src_pos);
        inst.a = operand;
        return sapir::add_inst(lo.arena, lo.func, inst);
    }
    sapir::Opcode op = sapir::Opcode::INVALID;
    if(n.op == token::TokenKind::Minus) { op = sapir::Opcode::Neg; }
    else if(n.op == token::TokenKind::Tilde) { op = sapir::Opcode::BitNot; }
    if(op == sapir::Opcode::INVALID) {
        return sapir::add_inst(lo.arena, lo.func, sapir::new_inst(sapir::Opcode::Undef, (types::Type*)n.h.ty, n.h.src_pos));
    }
    u32 operand = lower_expr(lo, n.operand);
    sapir::Inst inst = sapir::new_inst(op, (types::Type*)n.h.ty, n.h.src_pos);
    inst.a = operand;
    return sapir::add_inst(lo.arena, lo.func, inst);
}

// Lowers a && b / a || b to an i1 value via a short-circuit diamond.
fn u32 lower_short_circuit(Lower* lo, ast::BinaryOpNode* n, bool is_and) {
    u32 lhs = to_bool(lo, (types::Type*)n.lhs.h.ty, lower_expr(lo, n.lhs));
    u32 lhs_block = lo.current;
    sapir::Inst short_inst = sapir::new_inst(sapir::Opcode::ConstBool, types::prim_bool(), n.h.src_pos);
    if(!is_and) { short_inst.imm = 1; }
    u32 short_const = sapir::add_inst(lo.arena, lo.func, short_inst);

    u32 rhs_block = new_sapir_block(lo);
    u32 join_block = new_sapir_block(lo);
    u32 then_target = rhs_block;
    u32 else_target = join_block;
    if(!is_and) { then_target = join_block; else_target = rhs_block; }
    emit_cond_br(lo, lhs, then_target, else_target);
    link_pred(lo, rhs_block, lhs_block);
    link_pred(lo, join_block, lhs_block);
    seal_block(lo, rhs_block);

    switch_to_block(lo, rhs_block);
    u32 rhs = to_bool(lo, (types::Type*)n.rhs.h.ty, lower_expr(lo, n.rhs));
    u32 rhs_end = lo.current;
    emit_br(lo, join_block);
    link_pred(lo, join_block, rhs_end);
    seal_block(lo, join_block);

    switch_to_block(lo, join_block);
    u32 phi = emit_phi_inst(lo, join_block, types::prim_bool());
    u32 base = sapir::add_extra(lo.arena, lo.func, 2);
    sapir::add_extra(lo.arena, lo.func, lhs_block);
    sapir::add_extra(lo.arena, lo.func, short_const);
    sapir::add_extra(lo.arena, lo.func, rhs_end);
    sapir::add_extra(lo.arena, lo.func, rhs);
    lo.func.insts[phi].b = base;
    return phi;
}

// A pointer condition compares against null, never truncated to its low bit.
fn u32 to_bool(Lower* lo, types::Type* ty, u32 value) {
    switch(sapir::cond_test(ty)) {
    case sapir::CondTest::AsBool: { return value; }
    case sapir::CondTest::IntNonZero: {
        sapir::Inst zero = sapir::new_inst(sapir::Opcode::ConstInt, ty, lo.func.src_pos);
        return emit_cmp_ne(lo, value, sapir::add_inst(lo.arena, lo.func, zero));
    }
    case sapir::CondTest::PtrNonNull: {
        sapir::Inst nul = sapir::new_inst(sapir::Opcode::ConstNull, ty, lo.func.src_pos);
        return emit_cmp_ne(lo, value, sapir::add_inst(lo.arena, lo.func, nul));
    }
    case sapir::CondTest::SliceNonEmpty: {
        sapir::Inst len = sapir::new_inst(sapir::Opcode::SliceLen, types::prim_u64(), lo.func.src_pos);
        len.a = value;
        u32 len_val = sapir::add_inst(lo.arena, lo.func, len);
        sapir::Inst zero = sapir::new_inst(sapir::Opcode::ConstInt, types::prim_u64(), lo.func.src_pos);
        return emit_cmp_ne(lo, len_val, sapir::add_inst(lo.arena, lo.func, zero));
    }
    else { return value; }
    }
    return value;
}

fn u32 emit_cmp_ne(Lower* lo, u32 lhs, u32 rhs) {
    sapir::Inst inst = sapir::new_inst(sapir::Opcode::CmpNe, types::prim_bool(), lo.func.src_pos);
    inst.a = lhs;
    inst.b = rhs;
    return sapir::add_inst(lo.arena, lo.func, inst);
}

// TERMINATORS ////////////////////////////////////////////////////////////////////

fn void lower_terminator(Lower* lo, cfg::BasicBlock* cfg_block) {
    cfg::Terminator* term = &cfg_block.term;
    switch(term.kind) {
    case cfg::TermKind::Goto: {
        emit_br(lo, term.goto_target);
        link_pred(lo, term.goto_target, lo.current);
    }
    case cfg::TermKind::CondBranch: {
        u32 cond = to_bool(lo, (types::Type*)term.cond.h.ty, lower_expr(lo, term.cond));
        emit_cond_br(lo, cond, term.then_target, term.else_target);
        link_pred(lo, term.then_target, lo.current);
        link_pred(lo, term.else_target, lo.current);
    }
    case cfg::TermKind::Switch: {
        u32 disc = lower_expr(lo, term.switch_value);
        u32 base = sapir::add_extra(lo.arena, lo.func, term.switch_default);
        sapir::add_extra(lo.arena, lo.func, (u32)term.switch_arms.len);
        for(u64 arm_index = 0; arm_index < term.switch_arms.len; arm_index += 1) {
            i64 label = 0;
            if(sema::eval_const_i64_hook != null) { sema::eval_const_i64_hook(lo.m, term.switch_arms[arm_index].label, &label); }
            sapir::add_extra(lo.arena, lo.func, (u32)((u64)label & 4294967295));
            sapir::add_extra(lo.arena, lo.func, (u32)((u64)label >> 32));
            sapir::add_extra(lo.arena, lo.func, term.switch_arms[arm_index].target);
        }
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::SwitchBr, types::prim_void(), term.src_pos);
        inst.a = disc;
        inst.b = base;
        sapir::add_inst(lo.arena, lo.func, inst);
        link_pred(lo, term.switch_default, lo.current);
        for(u64 arm_index = 0; arm_index < term.switch_arms.len; arm_index += 1) {
            link_pred(lo, term.switch_arms[arm_index].target, lo.current);
        }
    }
    case cfg::TermKind::Return: {
        u32 value = sapir::INVALID_ID;
        if(term.return_value != null) { value = lower_expr(lo, term.return_value); }
        for(u64 s = (u64)term.defer_start; s < cfg_block.stmts.len; s += 1) { lower_stmt(lo, cfg_block.stmts[s]); }
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::Ret, types::prim_void(), term.src_pos);
        inst.a = value;
        sapir::add_inst(lo.arena, lo.func, inst);
    }
    else {
        sapir::add_inst(lo.arena, lo.func, sapir::new_inst(sapir::Opcode::Unreachable, types::prim_void(), term.src_pos));
    }
    }
}

fn void emit_br(Lower* lo, u32 target) {
    sapir::Inst inst = sapir::new_inst(sapir::Opcode::Br, types::prim_void(), lo.func.src_pos);
    inst.a = target;
    sapir::add_inst(lo.arena, lo.func, inst);
}

fn void emit_cond_br(Lower* lo, u32 cond, u32 then_target, u32 else_target) {
    u32 base = sapir::add_extra(lo.arena, lo.func, then_target);
    sapir::add_extra(lo.arena, lo.func, else_target);
    sapir::Inst inst = sapir::new_inst(sapir::Opcode::CondBr, types::prim_void(), lo.func.src_pos);
    inst.a = cond;
    inst.b = base;
    sapir::add_inst(lo.arena, lo.func, inst);
}

// SSA CONSTRUCTION (Braun et al.) //////////////////////////////////////////////////

fn void link_pred(Lower* lo, u32 block, u32 pred) {
    sapir::SapirBlock* target = &lo.func.blocks[block];
    for(u64 i = 0; i < target.preds.len; i += 1) {
        if(target.preds[i] == pred) { return; }         // one phi operand per distinct predecessor
    }
    sapir::add_pred(lo.arena, lo.func, block, pred);
}

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

fn u32 var_map_lookup(Lower* lo, u32 block, void* decl) {
    BlockState* state = &lo.states[block];
    for(u64 i = 0; i < state.defs.len; i += 1) {
        if(state.defs[i].decl == decl) { return state.defs[i].value; }
    }
    return sapir::INVALID_ID;
}

fn u32 read_var(Lower* lo, u32 block, void* decl) {
    u32 hit = var_map_lookup(lo, block, decl);
    if(hit != sapir::INVALID_ID) { return hit; }
    return read_var_recursive(lo, block, decl);
}

fn u32 read_var_recursive(Lower* lo, u32 block, void* decl) {
    u32 value;
    if(!lo.states[block].sealed) {
        value = emit_phi_inst(lo, block, decl_type(decl));
        incomplete_push(lo, block, decl, value);
    } else {
        sapir::SapirBlock* sapir_block = &lo.func.blocks[block];
        if(sapir_block.preds.len == 0) {
            value = sapir::add_inst(lo.arena, lo.func, sapir::new_inst(sapir::Opcode::Undef, decl_type(decl), lo.func.src_pos));
        } else if(sapir_block.preds.len == 1) {
            value = read_var(lo, sapir_block.preds[0], decl);
        } else {
            value = emit_phi_inst(lo, block, decl_type(decl));
            write_var(lo, block, decl, value);                  // pre-insert breaks lookup cycles through loops
            fill_phi_operands(lo, block, decl, value);
        }
    }
    write_var(lo, block, decl, value);
    return value;
}

fn u32 emit_phi_inst(Lower* lo, u32 block, types::Type* ty) {
    sapir::Inst inst = sapir::new_inst(sapir::Opcode::Phi, ty, lo.func.src_pos);
    u32 phi = sapir::add_inst(lo.arena, lo.func, inst);
    sapir::add_phi_to_block(lo.arena, lo.func, block, phi);
    return phi;
}

fn void fill_phi_operands(Lower* lo, u32 block, void* decl, u32 phi) {
    u64 pred_count = lo.func.blocks[block].preds.len;
    u32 base = sapir::add_extra(lo.arena, lo.func, (u32)pred_count);
    for(u64 i = 0; i < pred_count * 2; i += 1) { sapir::add_extra(lo.arena, lo.func, 0); }
    lo.func.insts[phi].b = base;
    for(u64 i = 0; i < pred_count; i += 1) {
        u32 pred = lo.func.blocks[block].preds[i];
        u32 value = read_var(lo, pred, decl);
        lo.func.extra[(u64)base + 1 + i * 2] = pred;
        lo.func.extra[(u64)base + 2 + i * 2] = value;
    }
}

fn void incomplete_push(Lower* lo, u32 block, void* decl, u32 phi) {
    BlockState* state = &lo.states[block];
    if(state.incomplete.len == state.incomplete_cap) {
        u64 new_cap = 4;
        if(state.incomplete_cap > 0) { new_cap = state.incomplete_cap * 2; }
        state.incomplete.ptr = (IncompletePhi*)arena::realloc_grow(lo.arena, (void*)state.incomplete.ptr, state.incomplete.len * sizeof(IncompletePhi), new_cap * sizeof(IncompletePhi));
        state.incomplete_cap = new_cap;
    }
    state.incomplete[state.incomplete.len].decl = decl;
    state.incomplete[state.incomplete.len].phi = phi;
    state.incomplete.len += 1;
}

fn void seal_block(Lower* lo, u32 block) {
    BlockState* state = &lo.states[block];
    if(state.sealed) { return; }
    u64 count = state.incomplete.len;
    for(u64 i = 0; i < count; i += 1) {
        fill_phi_operands(lo, block, state.incomplete[i].decl, state.incomplete[i].phi);
    }
    state.sealed = true;
}

fn void seal_cfg_successors(Lower* lo, cfg::Terminator* term) {
    switch(term.kind) {
    case cfg::TermKind::Goto: { dec_and_seal(lo, term.goto_target); }
    case cfg::TermKind::CondBranch: {
        dec_and_seal(lo, term.then_target);
        if(term.else_target != term.then_target) { dec_and_seal(lo, term.else_target); }
    }
    case cfg::TermKind::Switch: {
        dec_and_seal(lo, term.switch_default);
        for(u64 arm_index = 0; arm_index < term.switch_arms.len; arm_index += 1) {
            u32 target = term.switch_arms[arm_index].target;
            bool already = target == term.switch_default;
            for(u64 j = 0; j < arm_index; j += 1) {
                if(term.switch_arms[j].target == target) { already = true; break; }
            }
            if(!already) { dec_and_seal(lo, target); }
        }
    }
    else { }
    }
}

fn void dec_and_seal(Lower* lo, u32 block) {
    BlockState* state = &lo.states[block];
    if(state.cfg_preds_remaining > 0) { state.cfg_preds_remaining -= 1; }
    if(state.cfg_preds_remaining == 0 && !state.sealed) { seal_block(lo, block); }
}

// Removes phis whose operands are all one value or the phi itself, to fixpoint.
fn void remove_trivial_phis(Lower* lo) {
    sapir::SapirFn* func = lo.func;
    u32[] redirect = {(u32*)arena::alloc(lo.arena, func.insts.len * sizeof(u32)), func.insts.len};
    for(u64 i = 0; i < func.insts.len; i += 1) { redirect[i] = sapir::INVALID_ID; }

    bool changed = true;
    while(changed) {
        changed = false;
        for(u64 block_index = 0; block_index < func.blocks.len; block_index += 1) {
            sapir::SapirBlock* block = &func.blocks[block_index];
            u64 write_index = 0;
            for(u64 phi_index = 0; phi_index < block.phis.len; phi_index += 1) {
                u32 phi = block.phis[phi_index];
                sapir::Inst* inst = &func.insts[phi];
                u32 unique = sapir::INVALID_ID;
                bool has_other = false;
                bool trivial = true;
                if(inst.b != sapir::INVALID_ID) {
                    u32 n = func.extra[inst.b];
                    for(u32 j = 0; j < n; j += 1) {
                        u32 value = resolve(redirect, func.extra[inst.b + 2 + j * 2]);
                        if(value == phi) { continue; }
                        if(!has_other) { unique = value; has_other = true; }
                        else if(value != unique) { trivial = false; break; }
                    }
                } else { trivial = false; }
                if(trivial) {
                    u32 replacement = unique;
                    if(!has_other) {                    // all operands are the phi itself — an unreachable value
                        replacement = sapir::add_inst(lo.arena, func, sapir::new_inst(sapir::Opcode::Undef, inst.ty, func.src_pos));
                    }
                    redirect[phi] = replacement;
                    changed = true;
                } else {
                    block.phis[write_index] = phi;
                    write_index += 1;
                }
            }
            block.phis.len = write_index;
        }
    }
    rewrite_uses(lo, redirect);
}

fn u32 resolve(u32[] redirect, u32 value) {
    while(value != sapir::INVALID_ID && value < (u32)redirect.len && redirect[value] != sapir::INVALID_ID) { value = redirect[value]; }
    return value;
}

fn void rewrite_uses(Lower* lo, u32[] redirect) {
    sapir::SapirFn* func = lo.func;
    for(u64 i = 0; i < func.insts.len; i += 1) {
        sapir::Inst* inst = &func.insts[i];
        if(inst.op == sapir::Opcode::Phi) {
            if(inst.b == sapir::INVALID_ID) { continue; }
            u32 n = func.extra[inst.b];
            for(u32 j = 0; j < n; j += 1) {
                u32 slot = inst.b + 2 + j * 2;
                func.extra[slot] = resolve(redirect, func.extra[slot]);
            }
            continue;
        }
        if(inst.op == sapir::Opcode::Call) {
            if(((u16)inst.flags & (u16)sapir::InstFlags::Indirect) != 0) { inst.a = resolve(redirect, inst.a); }
            u32 argc = func.extra[inst.b];
            for(u32 j = 0; j < argc; j += 1) { func.extra[inst.b + 1 + j] = resolve(redirect, func.extra[inst.b + 1 + j]); }
            continue;
        }
        if(op_a_is_value(inst.op) && !(inst.op == sapir::Opcode::Ret && inst.a == sapir::INVALID_ID)) {
            inst.a = resolve(redirect, inst.a);
        }
        if(op_b_is_value(inst.op)) { inst.b = resolve(redirect, inst.b); }
    }
}

fn bool op_a_is_value(sapir::Opcode op) {
    if(op >= sapir::Opcode::Add && op <= sapir::Opcode::CmpGe) { return true; }
    switch(op) {
    case sapir::Opcode::Zero:
    case sapir::Opcode::Load:
    case sapir::Opcode::Store:
    case sapir::Opcode::Memcpy:
    case sapir::Opcode::FieldAddr:
    case sapir::Opcode::IndexAddr:
    case sapir::Opcode::SliceMake:
    case sapir::Opcode::SlicePtr:
    case sapir::Opcode::SliceLen:
    case sapir::Opcode::Cast:
    case sapir::Opcode::Neg:
    case sapir::Opcode::BitNot:
    case sapir::Opcode::Not:
    case sapir::Opcode::Ret:
    case sapir::Opcode::CondBr:
    case sapir::Opcode::SwitchBr: { return true; }
    else { return false; }
    }
    return false;
}

fn bool op_b_is_value(sapir::Opcode op) {
    if(op >= sapir::Opcode::Add && op <= sapir::Opcode::CmpGe) { return true; }
    switch(op) {
    case sapir::Opcode::Store:
    case sapir::Opcode::Memcpy:
    case sapir::Opcode::IndexAddr:
    case sapir::Opcode::SliceMake:
    case sapir::Opcode::DbgValue: { return true; }
    else { return false; }
    }
    return false;
}

fn void add_local_decl(Lower* lo, void* decl) {
    if(lo.local_decls.len == lo.local_decls_cap) {
        u64 new_cap = 8;
        if(lo.local_decls_cap > 0) { new_cap = lo.local_decls_cap * 2; }
        lo.local_decls.ptr = (void**)arena::realloc_grow(lo.arena, (void*)lo.local_decls.ptr, lo.local_decls.len * sizeof(void*), new_cap * sizeof(void*));
        lo.local_decls_cap = new_cap;
    }
    lo.local_decls[lo.local_decls.len] = decl;
    lo.local_decls.len += 1;
}

fn bool is_local_decl(Lower* lo, void* decl) {
    for(u64 i = 0; i < lo.local_decls.len; i += 1) {
        if(lo.local_decls[i] == decl) { return true; }
    }
    return false;
}

fn types::Type* decl_type(void* decl) {
    return ((sema::Decl*)decl).ty;
}

// MEMORY VARIABLES + AGGREGATES ////////////////////////////////////////////////////

fn bool is_aggregate(types::Type* t) {
    return t.kind == types::TypeKind::Struct || t.kind == types::TypeKind::Union || t.kind == types::TypeKind::Array;
}

fn void mark_mem_var(Lower* lo, void* decl) {
    if(decl == null) { return; }
    for(u64 i = 0; i < lo.mem_vars.len; i += 1) {
        if(lo.mem_vars[i].decl == decl) { return; }
    }
    if(lo.mem_vars.len == lo.mem_vars_cap) {
        u64 new_cap = 8;
        if(lo.mem_vars_cap > 0) { new_cap = lo.mem_vars_cap * 2; }
        lo.mem_vars.ptr = (MemVar*)arena::realloc_grow(lo.arena, (void*)lo.mem_vars.ptr, lo.mem_vars.len * sizeof(MemVar), new_cap * sizeof(MemVar));
        lo.mem_vars_cap = new_cap;
    }
    lo.mem_vars[lo.mem_vars.len].decl = decl;
    lo.mem_vars[lo.mem_vars.len].alloca = sapir::INVALID_ID;
    lo.mem_vars.len += 1;
}

fn u32 mem_alloca(Lower* lo, void* decl) {
    for(u64 i = 0; i < lo.mem_vars.len; i += 1) {
        if(lo.mem_vars[i].decl == decl) { return lo.mem_vars[i].alloca; }
    }
    return sapir::INVALID_ID;
}

fn void collect_mem_vars(Lower* lo, ast::FnDeclNode* fn_node, cfg::Cfg* g) {
    for(u64 i = 0; i < fn_node.params.len; i += 1) { add_local_decl(lo, fn_node.params[i].decl); }
    for(u64 block_index = 0; block_index < g.blocks.len; block_index += 1) {
        cfg::BasicBlock* block = &g.blocks[block_index];
        for(u64 s = 0; s < block.stmts.len; s += 1) {
            if(block.stmts[s].h.kind == ast::AstKind::VarDecl) { add_local_decl(lo, ((ast::VarDeclNode*)block.stmts[s]).decl); }
        }
    }
    for(u64 i = 0; i < fn_node.params.len; i += 1) {
        if(is_aggregate((types::Type*)fn_node.params[i].resolved_type)) { mark_mem_var(lo, fn_node.params[i].decl); }
    }
    for(u64 block_index = 0; block_index < g.blocks.len; block_index += 1) {
        cfg::BasicBlock* block = &g.blocks[block_index];
        for(u64 s = 0; s < block.stmts.len; s += 1) { scan_stmt_mem(lo, block.stmts[s]); }
        scan_addr_taken(lo, block.term.cond);
        scan_addr_taken(lo, block.term.return_value);
        scan_addr_taken(lo, block.term.switch_value);
    }
}

fn void scan_stmt_mem(Lower* lo, ast::AstNode* s) {
    switch(s.h.kind) {
    case ast::AstKind::VarDecl: {
        ast::VarDeclNode* v = (ast::VarDeclNode*)s;
        if(is_aggregate(decl_type(v.decl))) { mark_mem_var(lo, v.decl); }
        scan_addr_taken(lo, v.init);
    }
    case ast::AstKind::AssignmentStmt: {
        ast::AssignmentNode* a = (ast::AssignmentNode*)s;
        scan_addr_taken(lo, a.lhs);
        scan_addr_taken(lo, a.rhs);
    }
    case ast::AstKind::ExprStmt: { scan_addr_taken(lo, ((ast::ExprStmtNode*)s).expr); }
    else { }
    }
}

// Marks the root decl of any &lvalue as memory-resident (and recurses into children).
fn void scan_addr_taken(Lower* lo, ast::AstNode* e) {
    if(e == null) { return; }
    switch(e.h.kind) {
    case ast::AstKind::UnaryOp: {
        ast::UnaryOpNode* n = (ast::UnaryOpNode*)e;
        if(n.op == token::TokenKind::Amp) {
            void* root = lvalue_root_decl(n.operand);
            if(root != null && is_local_decl(lo, root)) { mark_mem_var(lo, root); }
        }
        scan_addr_taken(lo, n.operand);
    }
    case ast::AstKind::BinaryOp: {
        ast::BinaryOpNode* n = (ast::BinaryOpNode*)e;
        scan_addr_taken(lo, n.lhs);
        scan_addr_taken(lo, n.rhs);
    }
    case ast::AstKind::MemberAccess: { scan_addr_taken(lo, ((ast::MemberAccessNode*)e).base); }
    case ast::AstKind::ArrayIndex: {
        ast::ArrayIndexNode* n = (ast::ArrayIndexNode*)e;
        scan_addr_taken(lo, n.base);
        scan_addr_taken(lo, n.index);
    }
    case ast::AstKind::Cast: { scan_addr_taken(lo, ((ast::CastNode*)e).expr); }
    case ast::AstKind::Call: {
        ast::CallNode* n = (ast::CallNode*)e;
        for(u64 i = 0; i < n.args.len; i += 1) { scan_addr_taken(lo, n.args[i]); }
    }
    case ast::AstKind::StructLit: {
        ast::StructLitNode* n = (ast::StructLitNode*)e;
        for(u64 i = 0; i < n.inits.len; i += 1) { scan_addr_taken(lo, n.inits[i].value); }
    }
    case ast::AstKind::ArrayLit: {
        ast::ArrayLitNode* n = (ast::ArrayLitNode*)e;
        for(u64 i = 0; i < n.elems.len; i += 1) { scan_addr_taken(lo, n.elems[i]); }
    }
    else { }
    }
}

// The decl an lvalue roots at, or null if it goes through a pointer (separate storage).
fn void* lvalue_root_decl(ast::AstNode* e) {
    switch(e.h.kind) {
    case ast::AstKind::Ident: { return ((ast::IdentNode*)e).resolved; }
    case ast::AstKind::MemberAccess: {
        ast::MemberAccessNode* n = (ast::MemberAccessNode*)e;
        if(types::is_ptr((types::Type*)n.base.h.ty)) { return null; }
        return lvalue_root_decl(n.base);
    }
    case ast::AstKind::ArrayIndex: {
        ast::ArrayIndexNode* n = (ast::ArrayIndexNode*)e;
        if(types::is_ptr((types::Type*)n.base.h.ty)) { return null; }
        return lvalue_root_decl(n.base);
    }
    else { return null; }
    }
    return null;
}

fn void emit_mem_var_allocas(Lower* lo) {
    for(u64 i = 0; i < lo.mem_vars.len; i += 1) {
        types::Type* slot_ty = ((sema::Decl*)lo.mem_vars[i].decl).ty;
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::Alloca, types::intern_pointer(slot_ty, false), lo.func.src_pos);
        lo.mem_vars[i].alloca = sapir::add_inst(lo.arena, lo.func, inst);
    }
}

fn u32 emit_load(Lower* lo, u32 addr, types::Type* ty) {
    sapir::Inst inst = sapir::new_inst(sapir::Opcode::Load, ty, lo.func.src_pos);
    inst.a = addr;
    return sapir::add_inst(lo.arena, lo.func, inst);
}

fn void emit_store(Lower* lo, u32 addr, u32 value) {
    sapir::Inst inst = sapir::new_inst(sapir::Opcode::Store, types::prim_void(), lo.func.src_pos);
    inst.a = addr;
    inst.b = value;
    sapir::add_inst(lo.arena, lo.func, inst);
}

fn void emit_zero(Lower* lo, u32 addr, types::Type* ty) {
    sapir::Inst inst = sapir::new_inst(sapir::Opcode::Zero, types::prim_void(), lo.func.src_pos);
    inst.a = addr;
    inst.imm = (u64)types::size_of(&lo.m.diag, ty);
    sapir::add_inst(lo.arena, lo.func, inst);
}

fn void emit_memcpy(Lower* lo, u32 dst, u32 src, types::Type* ty) {
    sapir::Inst inst = sapir::new_inst(sapir::Opcode::Memcpy, types::prim_void(), lo.func.src_pos);
    inst.a = dst;
    inst.b = src;
    inst.imm = (u64)types::size_of(&lo.m.diag, ty);
    sapir::add_inst(lo.arena, lo.func, inst);
}

fn u32 emit_const_u64(Lower* lo, u64 value, u32 src_pos) {
    sapir::Inst inst = sapir::new_inst(sapir::Opcode::ConstInt, types::prim_u64(), src_pos);
    inst.imm = value;
    return sapir::add_inst(lo.arena, lo.func, inst);
}

fn u32 emit_index0(Lower* lo, u32 base, types::Type* result_ty, u32 src_pos) {
    u32 zero = emit_const_u64(lo, 0, src_pos);
    sapir::Inst inst = sapir::new_inst(sapir::Opcode::IndexAddr, result_ty, src_pos);
    inst.a = base;
    inst.b = zero;
    return sapir::add_inst(lo.arena, lo.func, inst);
}

// Array-decay and null-to-slice casts build a short sequence here; scalar casts are one Cast.
fn u32 lower_cast(Lower* lo, ast::CastNode* n, types::Type* dst) {
    types::Type* src = (types::Type*)n.expr.h.ty;
    switch(sapir::cast_op(src, dst)) {
    case sapir::CastOp::ArrayToElemPtr: { return emit_index0(lo, lower_addr(lo, n.expr), dst, n.h.src_pos); }
    case sapir::CastOp::ArrayToSlice: {
        u32 ptr = emit_index0(lo, lower_addr(lo, n.expr), types::intern_pointer(src.data.array.elem, false), n.h.src_pos);
        u32 len = emit_const_u64(lo, src.data.array.count, n.h.src_pos);
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::SliceMake, dst, n.h.src_pos);
        inst.a = ptr;
        inst.b = len;
        return sapir::add_inst(lo.arena, lo.func, inst);
    }
    case sapir::CastOp::NullToSlice: { return sapir::add_inst(lo.arena, lo.func, sapir::new_inst(sapir::Opcode::ConstNull, dst, n.h.src_pos)); }
    else {
        u32 value = lower_expr(lo, n.expr);
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::Cast, dst, n.h.src_pos);
        inst.a = value;
        return sapir::add_inst(lo.arena, lo.func, inst);
    }
    }
    return sapir::INVALID_ID;
}

fn u32 emit_temp_alloca(Lower* lo, types::Type* ty) {
    sapir::Inst inst = sapir::new_inst(sapir::Opcode::Alloca, types::intern_pointer(ty, false), lo.func.src_pos);
    return sapir::add_inst(lo.arena, lo.func, inst);
}

fn u32 lower_slice_field(Lower* lo, ast::MemberAccessNode* n, types::Type* result_ty) {
    u32 slice_value = lower_expr(lo, n.base);
    sapir::Opcode op = sapir::Opcode::SliceLen;
    if(n.field == interner::intern("ptr")) { op = sapir::Opcode::SlicePtr; }
    sapir::Inst inst = sapir::new_inst(op, result_ty, n.h.src_pos);
    inst.a = slice_value;
    return sapir::add_inst(lo.arena, lo.func, inst);
}

// Address (a pointer value) of an lvalue expression.
fn u32 lower_addr(Lower* lo, ast::AstNode* e) {
    switch(e.h.kind) {
    case ast::AstKind::Ident: {
        void* resolved = ((ast::IdentNode*)e).resolved;
        if(!is_local_decl(lo, resolved)) {
            diag::report(&lo.m.diag, lo.m.arena, e.h.src_pos, "address of a non-local declaration is not yet supported in lowering");
            return sapir::add_inst(lo.arena, lo.func, sapir::new_inst(sapir::Opcode::Undef, (types::Type*)e.h.ty, e.h.src_pos));
        }
        u32 slot = mem_alloca(lo, resolved);
        if(slot != sapir::INVALID_ID) { return slot; }
        return sapir::add_inst(lo.arena, lo.func, sapir::new_inst(sapir::Opcode::Undef, (types::Type*)e.h.ty, e.h.src_pos));
    }
    case ast::AstKind::MemberAccess: {
        ast::MemberAccessNode* n = (ast::MemberAccessNode*)e;
        types::Type* base_ty = (types::Type*)n.base.h.ty;
        u32 base_addr;
        types::Type* container;
        if(types::is_ptr(base_ty)) { base_addr = lower_expr(lo, n.base); container = base_ty.data.pointee; }
        else { base_addr = lower_addr(lo, n.base); container = base_ty; }
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::FieldAddr, types::intern_pointer((types::Type*)e.h.ty, false), e.h.src_pos);
        inst.a = base_addr;
        inst.b = field_index_of(container, n.field);
        return sapir::add_inst(lo.arena, lo.func, inst);
    }
    case ast::AstKind::ArrayIndex: {
        ast::ArrayIndexNode* n = (ast::ArrayIndexNode*)e;
        types::Type* base_ty = (types::Type*)n.base.h.ty;
        u32 index = lower_expr(lo, n.index);
        u32 base_addr;
        if(types::is_ptr(base_ty)) { base_addr = lower_expr(lo, n.base); }
        else { base_addr = lower_addr(lo, n.base); }
        sapir::Inst inst = sapir::new_inst(sapir::Opcode::IndexAddr, types::intern_pointer((types::Type*)e.h.ty, false), e.h.src_pos);
        inst.a = base_addr;
        inst.b = index;
        return sapir::add_inst(lo.arena, lo.func, inst);
    }
    case ast::AstKind::UnaryOp: {
        ast::UnaryOpNode* n = (ast::UnaryOpNode*)e;
        if(n.op == token::TokenKind::Star) { return lower_expr(lo, n.operand); }
        return sapir::add_inst(lo.arena, lo.func, sapir::new_inst(sapir::Opcode::Undef, (types::Type*)e.h.ty, e.h.src_pos));
    }
    else {
        return sapir::add_inst(lo.arena, lo.func, sapir::new_inst(sapir::Opcode::Undef, (types::Type*)e.h.ty, e.h.src_pos));
    }
    }
    return sapir::INVALID_ID;
}

fn u32 field_index_of(types::Type* container, symbol::Symbol* field) {
    ast::AstNode* decl = sema::container_decl(container);
    if(decl == null) { return 0; }
    return (u32)sema::find_field_index((ast::StructDeclNode*)decl, field);
}

// Builds an initializer at addr: literal in place, aggregate copy, or scalar store.
fn void lower_init_into(Lower* lo, u32 addr, types::Type* ty, ast::AstNode* init) {
    if(is_aggregate(ty)) {
        if(init.h.kind == ast::AstKind::StructLit) { build_struct_lit(lo, addr, ty, (ast::StructLitNode*)init); return; }
        if(init.h.kind == ast::AstKind::ArrayLit) { build_array_lit(lo, addr, ty, (ast::ArrayLitNode*)init); return; }
        if(init.h.kind == ast::AstKind::Call) {
            diag::report(&lo.m.diag, lo.m.arena, init.h.src_pos, "an aggregate value returned from a call is not yet supported in lowering");
            return;
        }
        emit_memcpy(lo, addr, lower_addr(lo, init), ty);
        return;
    }
    emit_store(lo, addr, lower_expr(lo, init));
}

fn void build_struct_lit(Lower* lo, u32 addr, types::Type* ty, ast::StructLitNode* lit) {
    emit_zero(lo, addr, ty);
    ast::StructDeclNode* decl = (ast::StructDeclNode*)sema::container_decl(ty);
    for(u64 i = 0; i < lit.inits.len; i += 1) {
        ast::FieldInitializer* fi = &lit.inits[i];
        u32 field_index = (u32)i;
        if(fi.name != null) { field_index = field_index_of(ty, fi.name); }
        types::Type* field_ty = (types::Type*)decl.fields[field_index].resolved_type;
        sapir::Inst addr_inst = sapir::new_inst(sapir::Opcode::FieldAddr, types::intern_pointer(field_ty, false), fi.src_pos);
        addr_inst.a = addr;
        addr_inst.b = field_index;
        u32 field_addr = sapir::add_inst(lo.arena, lo.func, addr_inst);
        lower_init_into(lo, field_addr, field_ty, fi.value);
    }
}

fn void build_array_lit(Lower* lo, u32 addr, types::Type* ty, ast::ArrayLitNode* lit) {
    types::Type* elem_ty = ty.data.array.elem;
    for(u64 i = 0; i < lit.elems.len; i += 1) {
        sapir::Inst index_inst = sapir::new_inst(sapir::Opcode::ConstInt, types::prim_u64(), lit.elems[i].h.src_pos);
        index_inst.imm = i;
        u32 index = sapir::add_inst(lo.arena, lo.func, index_inst);
        sapir::Inst addr_inst = sapir::new_inst(sapir::Opcode::IndexAddr, types::intern_pointer(elem_ty, false), lit.elems[i].h.src_pos);
        addr_inst.a = addr;
        addr_inst.b = index;
        u32 elem_addr = sapir::add_inst(lo.arena, lo.func, addr_inst);
        lower_init_into(lo, elem_addr, elem_ty, lit.elems[i]);
    }
}

// Stores rhs into an address, honoring compound ops and aggregate copies.
fn void store_to_addr(Lower* lo, u32 addr, types::Type* ty, token::TokenKind op, ast::AstNode* rhs) {
    sapir::Opcode combine = compound_opcode(op);
    if(combine == sapir::Opcode::INVALID) {
        lower_init_into(lo, addr, ty, rhs);
        return;
    }
    u32 current_value = emit_load(lo, addr, ty);
    sapir::Inst inst = sapir::new_inst(combine, ty, rhs.h.src_pos);
    inst.a = current_value;
    inst.b = lower_expr(lo, rhs);
    emit_store(lo, addr, sapir::add_inst(lo.arena, lo.func, inst));
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
