import value;
import ast;
import module;
import arena;
import list;
import types;
import types_print;
import diag;
import sema;
import scanner;
import parser;
import op;
import token;
import symbol;
import interner;
import sys;

export struct EnvEntry { sema::Decl* key; value::Value val; }

export struct Env {
    EnvEntry[]    entries;      // .len is the live count
    u64           cap;
    Env*          parent;
    arena::Arena* arena;
}

export struct MonoCtx {
    ast::FnDeclNode* callee;
    value::Value[]   args;
    u32              call_site_pos;
}

export struct Interp {
    module::Module* m;
    Env*            env;
    i32             depth;
    i32             max_depth;      // recursion-call limit; -comptime-depth
    u64             max_iterations; // per-loop iteration cap; -comptime-iterations
    MonoCtx[]       mono_stack;
    u64             mono_cap;
    Flow            flow;           // non-None unwinds block eval; loops consume Break/Continue, fns consume Return
    value::Value    return_value;
}

export enum Flow : i8 {
    None     = 0,
    Return   = 1,
    Break    = 2,
    Continue = 3,
}

export fn Env* env_push(Env* parent, arena::Arena* a, u64 initial_cap) {
    Env* e = (Env*)arena::alloc(a, sizeof(Env));
    sys::memset(e, 0, sizeof(Env));
    e.parent = parent;
    e.arena = a;
    e.cap = initial_cap;
    if(initial_cap > 0) {
        e.entries.ptr = (EnvEntry*)arena::alloc(a, initial_cap * sizeof(EnvEntry));
    }
    return e;
}

export fn value::Value* env_lookup(Env* e, sema::Decl* d) {
    while(e != null) {
        for(u64 entry_index = 0; entry_index < e.entries.len; entry_index += 1) {
            if(e.entries[entry_index].key == d) { return &e.entries[entry_index].val; }
        }
        e = e.parent;
    }
    return null;
}

export fn void env_bind(Env* e, arena::Arena* a, sema::Decl* d, value::Value v) {
    if(e.entries.len == e.cap) {
        u64 new_cap = 8;
        if(e.cap > 0) { new_cap = e.cap * 2; }
        e.entries.ptr = (EnvEntry*)arena::realloc_grow(a, (void*)e.entries.ptr, e.entries.len * sizeof(EnvEntry), new_cap * sizeof(EnvEntry));
        e.cap = new_cap;
    }
    e.entries[e.entries.len].key = d;
    e.entries[e.entries.len].val = v;
    e.entries.len += 1;
}

export fn void env_pop(Env* current) {
    // frames are arena-allocated; the caller restores ip.env to the parent
}

export fn Interp new_interp(module::Module* m) {
    Interp ip;
    sys::memset(&ip, 0, sizeof(Interp));
    ip.m = m;
    ip.max_depth = 1024;
    if(m.comptime_max_depth > 0) { ip.max_depth = m.comptime_max_depth; }
    ip.max_iterations = 10000000;
    if(m.comptime_max_iterations > 0) { ip.max_iterations = m.comptime_max_iterations; }
    ip.env = env_push(null, m.arena, 16);
    return ip;
}

export fn value::Value eval(Interp* ip, ast::AstNode* e) {
    if(e == null) { return value::val_error(); }
    if(((u16)e.h.flags & (u16)ast::AstFlags::HadError) != 0) { return value::val_error(); }
    switch(e.h.kind) {
    case ast::AstKind::IntLit: {
        ast::IntLitNode* lit = (ast::IntLitNode*)e;
        return value::val_int((i64)lit.value, (types::Ty*)e.h.ty);
    }
    case ast::AstKind::FloatLit: {
        ast::FloatLitNode* lit = (ast::FloatLitNode*)e;
        return value::val_float(lit.value, (types::Ty*)e.h.ty);
    }
    case ast::AstKind::BoolLit: {
        ast::BoolLitNode* lit = (ast::BoolLitNode*)e;
        return value::val_bool(lit.value);
    }
    case ast::AstKind::CharLit: {
        ast::CharLitNode* lit = (ast::CharLitNode*)e;
        return value::val_int((i64)lit.value, (types::Ty*)e.h.ty);
    }
    case ast::AstKind::StringLit: { return eval_string_lit(ip, (ast::StringLitNode*)e); }
    case ast::AstKind::NullLit:   { return value::val_null((types::Ty*)e.h.ty); }
    case ast::AstKind::UndefinedLit: { return value::val_int(0, (types::Ty*)e.h.ty); }
    case ast::AstKind::BinaryOp:  { return eval_binary(ip, (ast::BinaryOpNode*)e); }
    case ast::AstKind::UnaryOp:   { return eval_unary(ip, (ast::UnaryOpNode*)e); }
    case ast::AstKind::Cast:      { return eval_cast(ip, (ast::CastNode*)e); }
    case ast::AstKind::ArrayLit:     { return eval_array_lit(ip, (ast::ArrayLitNode*)e); }
    case ast::AstKind::StructLit:    { return eval_struct_lit(ip, (ast::StructLitNode*)e); }
    case ast::AstKind::MemberAccess: { return eval_member_access(ip, (ast::MemberAccessNode*)e); }
    case ast::AstKind::ArrayIndex:   { return eval_array_index(ip, (ast::ArrayIndexNode*)e); }
    case ast::AstKind::SliceRange:   { return eval_slice_range(ip, (ast::SliceRangeNode*)e); }
    case ast::AstKind::Ident:     { return eval_ident(ip, (ast::IdentNode*)e); }
    case ast::AstKind::NamespaceAccess: { return eval_namespace_access(ip, (ast::NamespaceAccessNode*)e); }
    case ast::AstKind::Call:      { return eval_call(ip, (ast::CallNode*)e); }
    case ast::AstKind::BlockStmt: { return eval_block(ip, (ast::BlockNode*)e); }
    case ast::AstKind::VarDecl:   { return eval_local_var_decl(ip, (ast::VarDeclNode*)e); }
    case ast::AstKind::ExprStmt: {
        ast::ExprStmtNode* s = (ast::ExprStmtNode*)e;
        return eval(ip, s.expr);
    }
    case ast::AstKind::IfStmt:        { return eval_if(ip, (ast::IfNode*)e); }
    case ast::AstKind::WhileStmt:     { return eval_while(ip, (ast::WhileNode*)e); }
    case ast::AstKind::ForStmt:       { return eval_for(ip, (ast::ForNode*)e); }
    case ast::AstKind::SwitchStmt:    { return eval_switch(ip, (ast::SwitchNode*)e); }
    case ast::AstKind::BreakStmt:     { return eval_break(ip); }
    case ast::AstKind::ContinueStmt:  { return eval_continue(ip); }
    case ast::AstKind::ReturnStmt:    { return eval_return(ip, (ast::ReturnNode*)e); }
    case ast::AstKind::AssignmentStmt: { return eval_assignment(ip, (ast::AssignmentNode*)e); }
    case ast::AstKind::Sizeof:    { return eval_sizeof(ip, (ast::SizeofNode*)e); }
    case ast::AstKind::Alignof:   { return eval_alignof(ip, (ast::AlignofNode*)e); }
    case ast::AstKind::Typeof:    { return eval_typeof(ip, (ast::TypeofNode*)e); }
    case ast::AstKind::Type_info: { return eval_type_info(ip, (ast::TypeInfoNode*)e); }
    case ast::AstKind::PrimitiveType:
    case ast::AstKind::NamedType:
    case ast::AstKind::PointerType:
    case ast::AstKind::ArrayType:
    case ast::AstKind::SliceType:
    case ast::AstKind::StructType:
    case ast::AstKind::UnionType:
    case ast::AstKind::FnPtrType: { return eval_type_expr(ip, e); }
    case ast::AstKind::ComprunStmt: { return eval_comprun(ip, (ast::CompRunNode*)e); }
    case ast::AstKind::ComperrorStmt:   { return eval_comperror(ip, (ast::CompErrorNode*)e); }
    case ast::AstKind::CompwarningStmt: { return eval_compwarning(ip, (ast::CompWarningNode*)e); }
    case ast::AstKind::CompinsertStmt:  { return eval_compinsert(ip, (ast::CompInsertNode*)e); }
    else {
        diag_unsupported(ip, e.h.src_pos);
        return value::val_error();
    }
    }
    return value::val_error();
}

fn value::Value eval_ident(Interp* ip, ast::IdentNode* n) {
    sema::Decl* d = (sema::Decl*)n.resolved;
    if(d == null) {
        diag_unsupported(ip, n.h.src_pos);
        return value::val_error();
    }
    value::Value* slot = env_lookup(ip.env, d);
    if(slot != null) {
        value::Value copy = *slot;
        return copy;
    }
    return eval_decl_value(ip, d, n.h.src_pos);
}

// A const global folds to its initializer, checked on demand in its home module so cross-module reads work.
fn value::Value eval_decl_value(Interp* ip, sema::Decl* d, u32 pos) {
    if(d.kind == sema::DeclKind::Node && d.data.node != null && d.data.node.h.kind == ast::AstKind::VarDecl) {
        ast::VarDeclNode* vd = (ast::VarDeclNode*)d.data.node;
        if(vd.is_const && vd.init != null) {
            if(d.home != null) { sema::ensure_var_init_checked(d.home, vd); }
            return eval(ip, vd.init);
        }
    }
    if(d.kind == sema::DeclKind::EnumMember && d.ty != null && d.ty.kind == types::TypeKind::Enum) {
        return eval_enum_member(ip, d);
    }
    if(d.kind == sema::DeclKind::Node && d.data.node != null && d.data.node.h.kind == ast::AstKind::FnDecl) {
        return value::val_fn((ast::FnDeclNode*)d.data.node, d.ty);
    }
    u8[] msg = "identifier is not a comptime value";
    diag::report(&ip.m.diag, ip.m.arena, pos, msg);
    return value::val_error();
}

fn value::Value eval_enum_member(Interp* ip, sema::Decl* d) {
    ast::EnumDeclNode* edecl = (ast::EnumDeclNode*)d.ty.data.enum_decl;
    ast::EnumMember* target = d.data.member;
    i64 running = 0;
    for(u64 member_index = 0; member_index < edecl.members.len; member_index += 1) {
        i64 member_value = running;
        if(edecl.members[member_index].value_expr != null) {
            value::Value ev = eval(ip, edecl.members[member_index].value_expr);
            if(ev.kind == value::ValueKind::Error) { return ev; }
            member_value = ev.data.i;
        }
        running = member_value + 1;
        if(edecl.members[member_index].name == target.name) { return value::val_int(member_value, d.ty); }
    }
    return value::val_error();
}

fn value::Value eval_namespace_access(Interp* ip, ast::NamespaceAccessNode* n) {
    sema::Decl* d = (sema::Decl*)n.resolved;
    if(d == null) {
        diag_unsupported(ip, n.h.src_pos);
        return value::val_error();
    }
    return eval_decl_value(ip, d, n.h.src_pos);
}

fn value::Value eval_block(Interp* ip, ast::BlockNode* n) {
    Env* saved = ip.env;
    ip.env = env_push(saved, ip.m.arena, 8);
    value::Value result = value::val_void();
    ast::AstNode*[] defers;
    defers.ptr = null;
    defers.len = 0;
    u64 defer_count = 0;
    for(u64 stmt_index = 0; stmt_index < n.stmts.len; stmt_index += 1) {
        ast::AstNode* st = n.stmts[stmt_index];
        if(st.h.kind == ast::AstKind::DeferStmt) {
            if(defers.ptr == null) { defers.ptr = (ast::AstNode**)arena::alloc(ip.m.arena, n.stmts.len * sizeof(ast::AstNode*)); }
            defers.ptr[defer_count] = ((ast::DeferNode*)st).body;
            defer_count += 1;
            continue;
        }
        value::Value v = eval(ip, st);
        if(v.kind == value::ValueKind::Error) { result = v; break; }
        if(ip.flow != Flow::None) { break; }
    }
    while(defer_count > 0) {                     // LIFO; a defer body must not clobber the in-progress return/break
        defer_count -= 1;
        Flow saved_flow = ip.flow;
        value::Value saved_rv = ip.return_value;
        ip.flow = Flow::None;
        eval(ip, defers.ptr[defer_count]);
        ip.flow = saved_flow;
        ip.return_value = saved_rv;
    }
    env_pop(ip.env);
    ip.env = saved;
    return result;
}

fn value::Value eval_local_var_decl(Interp* ip, ast::VarDeclNode* n) {
    sema::Decl* d = (sema::Decl*)n.decl;
    if(d == null) {
        diag_unsupported(ip, n.h.src_pos);
        return value::val_error();
    }
    value::Value v = value::val_void();
    if(n.init != null) {
        v = eval(ip, n.init);
        if(v.kind == value::ValueKind::Error) { return v; }
    }
    env_bind(ip.env, ip.m.arena, d, v);
    return value::val_void();
}

// Saplang conditions accept bool, integer (zero/non-zero), and pointer/slice (null/non-null).
fn value::Value eval_cond(Interp* ip, ast::AstNode* cond) {
    value::Value v = eval(ip, cond);
    if(v.kind == value::ValueKind::Error) { return v; }
    if(v.kind == value::ValueKind::Bool) { return v; }
    if(v.kind == value::ValueKind::Int) { return value::val_bool(v.data.i != 0); }
    if(v.kind == value::ValueKind::Null) { return value::val_bool(false); }
    if(v.kind == value::ValueKind::Bytes) { return value::val_bool(v.data.bytes.ptr != null); }
    u8[] msg = "comptime condition is not convertible to bool";
    diag::report(&ip.m.diag, ip.m.arena, cond.h.src_pos, msg);
    return value::val_error();
}

fn value::Value iteration_limit_error(Interp* ip, u32 pos) {
    u8[] msg = "comptime loop exceeded iteration limit";
    diag::report(&ip.m.diag, ip.m.arena, pos, msg);
    return value::val_error();
}

fn value::Value eval_return(Interp* ip, ast::ReturnNode* n) {
    value::Value v = value::val_void();
    if(n.expr != null) {
        v = eval(ip, n.expr);
        if(v.kind == value::ValueKind::Error) { return v; }
    }
    ip.return_value = v;
    ip.flow = Flow::Return;
    return v;
}

fn bool values_equal(value::Value a, value::Value b) {
    if(a.kind != b.kind) { return false; }
    if(a.kind == value::ValueKind::Int || a.kind == value::ValueKind::Char) { return a.data.i == b.data.i; }
    if(a.kind == value::ValueKind::Bool) { return a.data.b == b.data.b; }
    return false;
}

// A null-body arm chains to the next arm's body; break stops the switch, return/continue propagate.
fn value::Value eval_switch_body(Interp* ip, ast::SwitchNode* n, u64 start) {
    for(u64 arm_index = start; arm_index < n.arms.len; arm_index += 1) {
        if(n.arms[arm_index].body != null) {
            value::Value r = eval(ip, n.arms[arm_index].body);
            if(r.kind == value::ValueKind::Error) { return r; }
            if(ip.flow == Flow::Break) { ip.flow = Flow::None; }
            return value::val_void();
        }
    }
    return value::val_void();
}

fn value::Value eval_switch(Interp* ip, ast::SwitchNode* n) {
    value::Value disc = eval(ip, n.discriminant);
    if(disc.kind == value::ValueKind::Error) { return disc; }
    for(u64 arm_index = 0; arm_index < n.arms.len; arm_index += 1) {
        for(u64 label_index = 0; label_index < n.arms[arm_index].labels.len; label_index += 1) {
            value::Value label = eval(ip, n.arms[arm_index].labels[label_index]);
            if(label.kind == value::ValueKind::Error) { return label; }
            if(values_equal(label, disc)) { return eval_switch_body(ip, n, arm_index); }
        }
    }
    if(n.else_block != null) {
        value::Value r = eval(ip, n.else_block);
        if(r.kind == value::ValueKind::Error) { return r; }
        if(ip.flow == Flow::Break) { ip.flow = Flow::None; }
    }
    return value::val_void();
}

fn value::Value eval_break(Interp* ip) {
    ip.flow = Flow::Break;
    return value::val_void();
}

fn value::Value eval_continue(Interp* ip) {
    ip.flow = Flow::Continue;
    return value::val_void();
}

fn value::Value eval_if(Interp* ip, ast::IfNode* n) {
    value::Value cond = eval_cond(ip, n.cond);
    if(cond.kind == value::ValueKind::Error) { return cond; }
    if(cond.data.b) { return eval(ip, n.then_block); }
    if(n.else_block != null) { return eval(ip, n.else_block); }
    return value::val_void();
}

fn value::Value eval_while(Interp* ip, ast::WhileNode* n) {
    u64 iterations = 0;
    while(true) {
        value::Value cond = eval_cond(ip, n.cond);
        if(cond.kind == value::ValueKind::Error) { return cond; }
        if(!cond.data.b) { break; }
        value::Value body = eval(ip, n.body);
        if(body.kind == value::ValueKind::Error) { return body; }
        if(ip.flow == Flow::Break) { ip.flow = Flow::None; break; }
        if(ip.flow == Flow::Return) { break; }
        if(ip.flow == Flow::Continue) { ip.flow = Flow::None; }
        iterations += 1;
        if(iterations > ip.max_iterations) { return iteration_limit_error(ip, n.h.src_pos); }
    }
    return value::val_void();
}

fn value::Value eval_for(Interp* ip, ast::ForNode* n) {
    Env* saved = ip.env;
    ip.env = env_push(saved, ip.m.arena, 8);
    value::Value result = value::val_void();
    if(n.init != null) {
        value::Value iv = eval(ip, n.init);
        if(iv.kind == value::ValueKind::Error) { result = iv; }
    }
    if(result.kind != value::ValueKind::Error) {
        u64 iterations = 0;
        while(true) {
            if(n.cond != null) {
                value::Value c = eval_cond(ip, n.cond);
                if(c.kind == value::ValueKind::Error) { result = c; break; }
                if(!c.data.b) { break; }
            }
            value::Value b = eval(ip, n.body);
            if(b.kind == value::ValueKind::Error) { result = b; break; }
            if(ip.flow == Flow::Break) { ip.flow = Flow::None; break; }
            if(ip.flow == Flow::Return) { break; }
            if(ip.flow == Flow::Continue) { ip.flow = Flow::None; }
            if(n.post != null) {
                value::Value p = eval(ip, n.post);
                if(p.kind == value::ValueKind::Error) { result = p; break; }
            }
            iterations += 1;
            if(iterations > ip.max_iterations) { result = iteration_limit_error(ip, n.h.src_pos); break; }
        }
    }
    env_pop(ip.env);
    ip.env = saved;
    return result;
}

fn token::TokenKind compound_base(token::TokenKind op) {
    if(op == token::TokenKind::PlusEq) { return token::TokenKind::Plus; }
    if(op == token::TokenKind::MinusEq) { return token::TokenKind::Minus; }
    if(op == token::TokenKind::StarEq) { return token::TokenKind::Star; }
    if(op == token::TokenKind::SlashEq) { return token::TokenKind::Slash; }
    if(op == token::TokenKind::PercentEq) { return token::TokenKind::Percent; }
    if(op == token::TokenKind::AmpEq) { return token::TokenKind::Amp; }
    if(op == token::TokenKind::PipeEq) { return token::TokenKind::Pipe; }
    return token::TokenKind::Caret;
}

// The storage slot for an assignable comptime location: a local, or an element/field reached through one. Null if not assignable.
fn value::Value* eval_lvalue(Interp* ip, ast::AstNode* node) {
    if(node.h.kind == ast::AstKind::Ident) {
        sema::Decl* d = (sema::Decl*)((ast::IdentNode*)node).resolved;
        if(d == null) { return null; }
        return env_lookup(ip.env, d);
    }
    if(node.h.kind == ast::AstKind::ArrayIndex) {
        ast::ArrayIndexNode* ai = (ast::ArrayIndexNode*)node;
        value::Value* base = eval_lvalue(ip, ai.base);
        if(base == null || base.kind != value::ValueKind::Array) { return null; }
        value::Value idx = eval(ip, ai.index);
        if(idx.kind != value::ValueKind::Int || idx.data.i < 0 || (u64)idx.data.i >= base.data.elems.len) { return null; }
        return &base.data.elems[(u64)idx.data.i];
    }
    if(node.h.kind == ast::AstKind::MemberAccess) {
        ast::MemberAccessNode* ma = (ast::MemberAccessNode*)node;
        value::Value* base = eval_lvalue(ip, ma.base);
        if(base == null || base.kind != value::ValueKind::Struct || base.ty == null || base.ty.kind != types::TypeKind::Struct) { return null; }
        u64 field_index = struct_field_index((ast::StructDeclNode*)base.ty.data.struct_decl, ma.field);
        if(field_index >= base.data.elems.len) { return null; }
        return &base.data.elems[field_index];
    }
    return null;
}

fn value::Value eval_assignment(Interp* ip, ast::AssignmentNode* n) {
    value::Value* slot = eval_lvalue(ip, n.lhs);
    if(slot == null) {
        u8[] msg = "comptime assignment target is not an assignable comptime location";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg);
        return value::val_error();
    }
    value::Value rhs = eval(ip, n.rhs);
    if(rhs.kind == value::ValueKind::Error) { return rhs; }
    value::Value newval = rhs;
    if(n.op != token::TokenKind::Eq) {
        value::Value combined = eval_binop_checked(ip, compound_base(n.op), *slot, rhs, n.h.src_pos);
        if(combined.kind == value::ValueKind::Error) { return combined; }
        newval = combined;
    }
    *slot = newval;
    return value::val_void();
}

// op.sl can only signal an operator failure as val_error; translate it to a specific comptime diagnostic here.
fn value::Value eval_binop_checked(Interp* ip, token::TokenKind op, value::Value l, value::Value r, u32 pos) {
    if((op == token::TokenKind::Slash || op == token::TokenKind::Percent) && r.kind == value::ValueKind::Int && r.data.i == 0) {
        diag::report(&ip.m.diag, ip.m.arena, pos, "division by zero at comptime");
        return value::val_error();
    }
    if((op == token::TokenKind::LShift || op == token::TokenKind::RShift) && r.kind == value::ValueKind::Int && (r.data.i < 0 || r.data.i >= 64)) {
        diag::report(&ip.m.diag, ip.m.arena, pos, "shift amount out of range at comptime");
        return value::val_error();
    }
    value::Value result = op::binop_eval(op, l, r);
    if(result.kind == value::ValueKind::Error) {
        diag::report(&ip.m.diag, ip.m.arena, pos, "operator cannot be evaluated at comptime");
    }
    return result;
}

fn value::Value eval_binary(Interp* ip, ast::BinaryOpNode* n) {
    value::Value l = eval(ip, n.lhs);
    if(l.kind == value::ValueKind::Error) { return l; }
    if(l.kind == value::ValueKind::Bool) {
        if(n.op == token::TokenKind::AmpAmp && !l.data.b) { return value::val_bool(false); }
        if(n.op == token::TokenKind::PipePipe && l.data.b) { return value::val_bool(true); }
    }
    value::Value r = eval(ip, n.rhs);
    if(r.kind == value::ValueKind::Error) { return r; }
    return eval_binop_checked(ip, n.op, l, r, n.h.src_pos);
}

fn value::Value eval_unary(Interp* ip, ast::UnaryOpNode* n) {
    value::Value v = eval(ip, n.operand);
    if(v.kind == value::ValueKind::Error) { return v; }
    // &fn is the function pointer itself, same value as the bare function.
    if(n.op == token::TokenKind::Amp && v.kind == value::ValueKind::FnRef) { return v; }
    value::Value result = op::unaryop_eval(n.op, v);
    if(result.kind == value::ValueKind::Error) {
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, "operator cannot be evaluated at comptime");
    }
    return result;
}

fn value::Value eval_cast(Interp* ip, ast::CastNode* n) {
    value::Value v = eval(ip, n.expr);
    if(v.kind == value::ValueKind::Error) { return v; }
    types::Ty* target = (types::Ty*)n.h.ty;
    if(target == null) { return v; }
    bool v_is_float = v.kind == value::ValueKind::Float;
    if(types::is_float(target)) {
        if(v_is_float) { return value::val_float(v.data.f, target); }
        return value::val_float((f64)v.data.i, target);
    }
    if(types::is_int(target)) {
        i64 raw = v.data.i;
        if(v_is_float) { raw = (i64)v.data.f; }
        return value::val_int(op::wrap_to_type(raw, target), target);
    }
    return v;
}

fn u64 struct_field_index(ast::StructDeclNode* sd, symbol::Symbol* name) {
    for(u64 field_index = 0; field_index < sd.fields.len; field_index += 1) {
        if(sd.fields[field_index].name == name) { return field_index; }
    }
    return sd.fields.len;
}

fn value::Value build_field_info_array(Interp* ip, types::Ty* t) {
    types::Ty* fi_ty = sema::reflection_fieldinfo_type(ip.m);
    ast::FieldDecl[] flds;
    if(t.kind == types::TypeKind::Struct) { flds = ((ast::StructDeclNode*)t.data.struct_decl).fields; }
    else { flds = ((ast::UnionDeclNode*)t.data.union_decl).fields; }
    types::size_of(&ip.m.diag, t);
    types::Ty* u8slice = types::intern_slice(types::prim_u8());
    value::Value[] elems;
    elems.ptr = (value::Value*)arena::alloc(ip.m.arena, flds.len * sizeof(value::Value));
    elems.len = flds.len;
    for(u64 i = 0; i < flds.len; i += 1) {
        value::Value[] finfo;
        finfo.ptr = (value::Value*)arena::alloc(ip.m.arena, 3 * sizeof(value::Value));
        finfo.len = 3;
        finfo[0] = value::val_bytes(interner::symbol_str(flds[i].name), u8slice);
        finfo[1] = value::val_type((types::Ty*)flds[i].resolved_type);
        u64 offset = 0;
        if(t.layout != null && i < t.layout.offsets.len) { offset = (u64)t.layout.offsets[i]; }
        finfo[2] = value::val_int((i64)offset, types::prim_u64());
        elems[i] = value::val_struct(fi_ty, finfo);
    }
    return value::val_array(types::intern_slice(fi_ty), elems);
}

fn value::Value build_type_info_value(Interp* ip, types::Ty* t) {
    types::Ty* ti_ty = sema::reflection_typeinfo_type(ip.m);
    value::Value[] fields;
    fields.ptr = (value::Value*)arena::alloc(ip.m.arena, 8 * sizeof(value::Value));
    fields.len = 8;
    fields[0] = value::val_int((i64)t.kind, types::prim_i32());
    fields[1] = value::val_bytes(types_print::print_to_arena(t, ip.m.arena), types::intern_slice(types::prim_u8()));
    fields[2] = value::val_int((i64)types::size_of(&ip.m.diag, t), types::prim_u64());
    fields[3] = value::val_int((i64)types::align_of(&ip.m.diag, t), types::prim_u64());
    if(t.kind == types::TypeKind::Struct || t.kind == types::TypeKind::Union) {
        fields[4] = build_field_info_array(ip, t);
    } else {
        value::Value[] empty;
        empty.ptr = null;
        empty.len = 0;
        fields[4] = value::val_array(types::intern_slice(sema::reflection_fieldinfo_type(ip.m)), empty);
    }
    types::Ty* none = null;
    fields[5] = value::val_type(none);
    fields[6] = value::val_type(none);
    fields[7] = value::val_int(0, types::prim_u64());
    if(t.kind == types::TypeKind::Pointer) { fields[5] = value::val_type(t.data.pointee); }
    if(t.kind == types::TypeKind::Array) { fields[6] = value::val_type(t.data.array.elem); fields[7] = value::val_int((i64)t.data.array.count, types::prim_u64()); }
    if(t.kind == types::TypeKind::Slice) { fields[6] = value::val_type(t.data.slice_elem); }
    return value::val_struct(ti_ty, fields);
}

fn value::Value eval_type_info(Interp* ip, ast::TypeInfoNode* n) {
    types::Ty* t = (types::Ty*)n.arg.h.ty;
    if(t == null) {
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, "type_info argument is unresolved at comptime");
        return value::val_error();
    }
    return build_type_info_value(ip, t);
}

fn value::Value eval_array_lit(Interp* ip, ast::ArrayLitNode* n) {
    value::Value[] elems;
    elems.ptr = (value::Value*)arena::alloc(ip.m.arena, n.elems.len * sizeof(value::Value));
    elems.len = n.elems.len;
    for(u64 elem_index = 0; elem_index < n.elems.len; elem_index += 1) {
        elems[elem_index] = eval(ip, n.elems[elem_index]);
        if(elems[elem_index].kind == value::ValueKind::Error) { return elems[elem_index]; }
    }
    return value::val_array((types::Ty*)n.h.ty, elems);
}

// Fields the literal omits default to 0.
fn value::Value eval_struct_lit(Interp* ip, ast::StructLitNode* n) {
    types::Ty* ty = (types::Ty*)n.h.ty;
    if(ty == null || ty.kind != types::TypeKind::Struct) {
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, "struct literal is not a comptime struct value");
        return value::val_error();
    }
    ast::StructDeclNode* sd = (ast::StructDeclNode*)ty.data.struct_decl;
    u64 field_count = sd.fields.len;
    value::Value[] fields;
    fields.ptr = (value::Value*)arena::alloc(ip.m.arena, field_count * sizeof(value::Value));
    fields.len = field_count;
    for(u64 field_index = 0; field_index < field_count; field_index += 1) { fields[field_index] = value::val_int(0, null); }
    u64 positional = 0;
    for(u64 init_index = 0; init_index < n.inits.len; init_index += 1) {
        u64 target = positional;
        if(n.inits[init_index].name != null) { target = struct_field_index(sd, n.inits[init_index].name); }
        else { positional += 1; }
        value::Value fv = eval(ip, n.inits[init_index].value);
        if(fv.kind == value::ValueKind::Error) { return fv; }
        if(target < field_count) { fields[target] = fv; }
    }
    return value::val_struct(ty, fields);
}

fn value::Value eval_member_access(Interp* ip, ast::MemberAccessNode* n) {
    value::Value base = eval(ip, n.base);
    if(base.kind == value::ValueKind::Error) { return base; }
    if(base.kind == value::ValueKind::Bytes && n.field == interner::intern("len")) {
        return value::val_int((i64)base.data.bytes.len, types::prim_u64());
    }
    if(base.kind == value::ValueKind::Array && n.field == interner::intern("len")) {
        return value::val_int((i64)base.data.elems.len, types::prim_u64());
    }
    if(base.kind != value::ValueKind::Struct || base.ty == null || base.ty.kind != types::TypeKind::Struct) {
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, "member access on a non-struct comptime value");
        return value::val_error();
    }
    ast::StructDeclNode* sd = (ast::StructDeclNode*)base.ty.data.struct_decl;
    u64 field_index = struct_field_index(sd, n.field);
    if(field_index >= base.data.elems.len) {
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, "unknown field in comptime struct value");
        return value::val_error();
    }
    return base.data.elems[field_index];
}

fn value::Value eval_array_index(Interp* ip, ast::ArrayIndexNode* n) {
    value::Value base = eval(ip, n.base);
    if(base.kind == value::ValueKind::Error) { return base; }
    value::Value idx = eval(ip, n.index);
    if(idx.kind == value::ValueKind::Error) { return idx; }
    if(base.kind == value::ValueKind::Bytes) {
        if(idx.data.i < 0 || (u64)idx.data.i >= base.data.bytes.len) {
            diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, "comptime byte slice index out of bounds");
            return value::val_error();
        }
        return value::val_int((i64)base.data.bytes[(u64)idx.data.i], types::prim_u8());
    }
    if(base.kind != value::ValueKind::Array) {
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, "index on a non-array comptime value");
        return value::val_error();
    }
    if(idx.data.i < 0 || (u64)idx.data.i >= base.data.elems.len) {
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, "comptime array index out of bounds");
        return value::val_error();
    }
    return base.data.elems[(u64)idx.data.i];
}

fn value::Value eval_slice_range(Interp* ip, ast::SliceRangeNode* n) {
    value::Value base = eval(ip, n.base);
    if(base.kind == value::ValueKind::Error) { return base; }
    if(base.kind != value::ValueKind::Array) {
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, "range on a non-array comptime value");
        return value::val_error();
    }
    i64 lo = 0;
    i64 hi = (i64)base.data.elems.len;
    if(n.lo != null) { value::Value lv = eval(ip, n.lo); if(lv.kind == value::ValueKind::Error) { return lv; } lo = lv.data.i; }
    if(n.hi != null) { value::Value hv = eval(ip, n.hi); if(hv.kind == value::ValueKind::Error) { return hv; } hi = hv.data.i; }
    if(lo < 0 || hi > (i64)base.data.elems.len || lo > hi) {
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, "comptime slice range out of bounds");
        return value::val_error();
    }
    u64 count = (u64)(hi - lo);
    value::Value[] sub;
    sub.ptr = (value::Value*)arena::alloc(ip.m.arena, count * sizeof(value::Value));
    sub.len = count;
    for(u64 sub_index = 0; sub_index < count; sub_index += 1) { sub[sub_index] = base.data.elems[(u64)lo + sub_index]; }
    return value::val_array(base.ty, sub);
}

fn value::Value eval_sizeof(Interp* ip, ast::SizeofNode* n) {
    types::Ty* t = null;
    if(n.arg != null) { t = (types::Ty*)n.arg.h.ty; }
    if(t == null) {
        u8[] msg = "sizeof operand type is unresolved";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg);
        return value::val_error();
    }
    return value::val_int((i64)types::size_of(&ip.m.diag, t), types::prim_u64());
}

fn value::Value eval_alignof(Interp* ip, ast::AlignofNode* n) {
    types::Ty* t = null;
    if(n.arg != null) { t = (types::Ty*)n.arg.h.ty; }
    if(t == null) {
        u8[] msg = "alignof operand type is unresolved";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg);
        return value::val_error();
    }
    return value::val_int((i64)types::align_of(&ip.m.diag, t), types::prim_u64());
}

fn bool has_comptime_params(ast::FnDeclNode* func) {
    for(u64 param_index = 0; param_index < func.params.len; param_index += 1) {
        if(func.params[param_index].is_comptime) { return true; }
    }
    return false;
}

fn value::Value invoke(Interp* ip, ast::FnDeclNode* func, value::Value[] args, u32 call_site_pos) {
    if(ip.depth >= ip.max_depth) {
        u8[] msg = "comptime recursion limit exceeded";
        diag::report(&ip.m.diag, ip.m.arena, call_site_pos, msg);
        return value::val_error();
    }
    ip.depth += 1;
    Env* saved = ip.env;
    ip.env = env_push(saved, ip.m.arena, 16);
    for(u64 param_index = 0; param_index < func.params.len; param_index += 1) {
        sema::Decl* pd = (sema::Decl*)func.params[param_index].decl;
        if(pd != null && param_index < args.len) { env_bind(ip.env, ip.m.arena, pd, args[param_index]); }
    }
    Flow saved_flow = ip.flow;
    value::Value saved_return_value = ip.return_value;
    ip.flow = Flow::None;
    value::Value body_result = eval(ip, func.body);
    value::Value result = value::val_void();
    if(body_result.kind == value::ValueKind::Error) { result = body_result; } else if(ip.flow == Flow::Return) { result = ip.return_value; }
    ip.flow = saved_flow;
    ip.return_value = saved_return_value;
    env_pop(ip.env);
    ip.env = saved;
    ip.depth -= 1;
    return result;
}

fn value::Value eval_call(Interp* ip, ast::CallNode* n) {
    // sema already monomorphized an explicit generic call (e.g. `Vec(i32)` in type position); invoke the clone directly.
    if(n.resolved_fn != null) {
        ast::FnDeclNode* clone = (ast::FnDeclNode*)n.resolved_fn;
        if(n.args.len == clone.params.len) {
            value::Value[] cargs = {null, 0};
            if(n.args.len > 0) {
                cargs.ptr = arena::alloc(ip.m.arena, n.args.len * sizeof(value::Value));
                cargs.len = n.args.len;
                for(u64 i = 0; i < n.args.len; i += 1) {
                    cargs[i] = eval(ip, n.args[i]);
                    if(cargs[i].kind == value::ValueKind::Error) { return cargs[i]; }
                }
            }
            return invoke(ip, clone, cargs, n.h.src_pos);
        }
    }
    sema::Decl* d = resolved_decl(n.callee);
    if(d != null && d.kind == sema::DeclKind::Node && d.data.node != null && d.data.node.h.kind == ast::AstKind::ExternFnDecl) {
        u8[] msg = "cannot call an extern function at comptime";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg);
        return value::val_error();
    }
    ast::FnDeclNode* func;
    if(d != null && d.kind == sema::DeclKind::Node && d.data.node != null && d.data.node.h.kind == ast::AstKind::FnDecl) {
        func = (ast::FnDeclNode*)d.data.node;
    } else {
        value::Value callee_val = eval(ip, n.callee);       // fn-pointer / indirect call: the callee evaluates to a fn value
        if(callee_val.kind == value::ValueKind::Error) { return callee_val; }
        if(callee_val.kind != value::ValueKind::FnRef || callee_val.data.fn_ref == null) {
            u8[] msg = "comptime call target is not a function";
            diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg);
            return value::val_error();
        }
        func = callee_val.data.fn_ref;
        module::Module* fn_home = ip.m;
        if(func.decl != null) { fn_home = ((sema::Decl*)func.decl).home; }
        sema::ensure_body_checked(fn_home, func, ip.m);          // body-check the target in its own module, like the direct path
    }
    if(!ensure_comptime_safe(ip, func)) {
        u8[] msg = "cannot call a non-comptime-safe function at comptime";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg);
        return value::val_error();
    }
    value::Value[] args;
    args.ptr = null;
    args.len = 0;
    if(n.args.len > 0) {
        args.ptr = arena::alloc(ip.m.arena, n.args.len * sizeof(value::Value));
        args.len = n.args.len;
        for(u64 arg_index = 0; arg_index < n.args.len; arg_index += 1) {
            args[arg_index] = eval(ip, n.args[arg_index]);
            if(args[arg_index].kind == value::ValueKind::Error) { return args[arg_index]; }
        }
    }
    if(has_comptime_params(func)) {
        if(n.args.len != func.params.len) {
            u8[] msg = "comptime argument inference not yet supported; pass all arguments explicitly";
            diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg);
            return value::val_error();
        }
        value::Value[] cargs;
        cargs.ptr = arena::alloc(ip.m.arena, func.params.len * sizeof(value::Value));
        cargs.len = 0;
        for(u64 param_index = 0; param_index < func.params.len; param_index += 1) {
            if(func.params[param_index].is_comptime) {
                cargs[cargs.len] = args[param_index];
                cargs.len += 1;
            }
        }
        ast::FnDeclNode* mono = monomorphize(ip, func, cargs);
        return invoke(ip, mono, args, n.h.src_pos);
    }
    if(d != null && d.home != null) { sema::ensure_body_checked(d.home, func, ip.m); }     // same- or cross-module: check the callee in its own module
    return invoke(ip, func, args, n.h.src_pos);
}

fn value::Value eval_comperror(Interp* ip, ast::CompErrorNode* n) {
    value::Value msg = eval(ip, n.msg_expr);
    if(msg.kind == value::ValueKind::Error) { return msg; }
    if(msg.kind != value::ValueKind::Bytes) {
        u8[] bad = "comperror message must be a string";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, bad);
        return value::val_error();
    }
    diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg.data.bytes);
    return value::val_error();
}

fn value::Value eval_compwarning(Interp* ip, ast::CompWarningNode* n) {
    value::Value msg = eval(ip, n.msg_expr);
    if(msg.kind == value::ValueKind::Error) { return msg; }
    if(msg.kind != value::ValueKind::Bytes) {
        u8[] bad = "compwarning message must be a string";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, bad);
        return value::val_error();
    }
    diag::report_warning(&ip.m.diag, ip.m.arena, n.h.src_pos, msg.data.bytes);
    return value::val_void();
}

// The fragment shares the module's literal pool so generated string offsets stay valid after the splice.
fn ast::AstNode* compile_fragment(module::Module* m, u8[] bytes, bool as_stmts, u32 generator_pos) {
    module::Module* frag = (module::Module*)arena::alloc(m.arena, sizeof(module::Module));
    sys::memset(frag, 0, sizeof(module::Module));
    frag.arena = m.arena;
    frag.name = m.name;
    frag.source = bytes;
    frag.literal_pool = m.literal_pool;
    frag.literal_pool_cap = m.literal_pool_cap;
    scanner::scan(frag);
    u32 base = module::register_inserted_source(m, bytes, generator_pos);
    for(u64 token_index = 0; token_index < frag.tokens.len; token_index += 1) { frag.tokens[token_index].src_pos += base; }
    ast::AstNode* root;
    if(as_stmts) { root = parser::parse_stmt_fragment(frag); } else { root = parser::parse(frag); }
    m.literal_pool = frag.literal_pool;
    m.literal_pool_cap = frag.literal_pool_cap;
    for(u64 diag_index = 0; diag_index < frag.diag.entries.len; diag_index += 1) {
        diag::report(&m.diag, m.arena, generator_pos, frag.diag.entries[diag_index].msg);
    }
    if(frag.diag.entries.len > 0) { return null; }
    return root;
}

fn value::Value eval_compinsert(Interp* ip, ast::CompInsertNode* n) {
    value::Value src = eval(ip, n.source_expr);
    if(src.kind == value::ValueKind::Error) { return src; }
    if(src.kind != value::ValueKind::Bytes) {
        u8[] msg = "compinsert argument must be a string";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg);
        return value::val_error();
    }
    ast::AstNode* frag_root = compile_fragment(ip.m, src.data.bytes, false, n.h.src_pos);
    if(frag_root == null) { return value::val_error(); }
    ast::BlockNode* frag_block = (ast::BlockNode*)frag_root;
    for(u64 decl_index = 0; decl_index < frag_block.stmts.len; decl_index += 1) {
        sema::splice_top_decl(ip.m, frag_block.stmts[decl_index], n.h.src_pos);
    }
    return value::val_void();
}

// In-function compinsert: sema calls this while walking a block, then splices the returned stmts in place.
fn ast::AstNode*[] run_compinsert_stmts(module::Module* m, ast::CompInsertNode* n) {
    ast::AstNode*[] empty = {null, 0};
    Interp ip = new_interp(m);
    value::Value src = eval(&ip, n.source_expr);
    if(src.kind != value::ValueKind::Bytes) {
        if(src.kind != value::ValueKind::Error) { diag::report(&m.diag, m.arena, n.h.src_pos, "compinsert argument must be a string"); }
        return empty;
    }
    ast::AstNode* frag_root = compile_fragment(m, src.data.bytes, true, n.h.src_pos);
    if(frag_root == null) { return empty; }
    return ((ast::BlockNode*)frag_root).stmts;
}

fn value::Value eval_comprun(Interp* ip, ast::CompRunNode* n) {
    Env* saved = ip.env;
    ip.env = env_push(saved, ip.m.arena, 16);
    Flow saved_flow = ip.flow;
    value::Value saved_return_value = ip.return_value;
    eval(ip, n.body);
    ip.flow = saved_flow;                        // a comprun is an execution boundary; a return inside it doesn't propagate out
    ip.return_value = saved_return_value;
    env_pop(ip.env);
    ip.env = saved;
    return value::val_void();
}

fn value::Value eval_type_expr(Interp* ip, ast::AstNode* e) {
    if(e.h.ty == null) {
        u8[] msg = "type expression is unresolved at comptime";
        diag::report(&ip.m.diag, ip.m.arena, e.h.src_pos, msg);
        return value::val_error();
    }
    return value::val_type((types::Ty*)e.h.ty);
}

fn value::Value eval_typeof(Interp* ip, ast::TypeofNode* n) {
    types::Ty* t = null;
    if(n.expr != null) { t = (types::Ty*)n.expr.h.ty; }
    if(t == null) {
        u8[] msg = "typeof operand type is unresolved";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg);
        return value::val_error();
    }
    return value::val_type(t);
}

fn sema::Decl* resolved_decl(ast::AstNode* n) {
    if(n == null) { return null; }
    if(n.h.kind == ast::AstKind::Ident) { return (sema::Decl*)((ast::IdentNode*)n).resolved; }
    if(n.h.kind == ast::AstKind::NamespaceAccess) { return (sema::Decl*)((ast::NamespaceAccessNode*)n).resolved; }
    return null;
}

fn bool decl_is_mutable_global(sema::Decl* d) {
    if(d == null || d.kind != sema::DeclKind::Node || d.data.node == null) { return false; }
    if(d.data.node.h.kind != ast::AstKind::VarDecl) { return false; }
    ast::VarDeclNode* vd = (ast::VarDeclNode*)d.data.node;
    return vd.qualified_name != null && !vd.is_const;
}

export fn bool ensure_comptime_safe(Interp* ip, ast::FnDeclNode* func) {
    if(func.comptime_safe == ast::CompSafe::Safe) { return true; }
    if(func.comptime_safe == ast::CompSafe::Unsafe) { return false; }
    if(func.comptime_safe == ast::CompSafe::InProgress) { return true; }   // mid-check: tolerate the recursion cycle
    func.comptime_safe = ast::CompSafe::InProgress;
    bool safe = walk_safe(ip, func.body);
    if(safe) { func.comptime_safe = ast::CompSafe::Safe; } else { func.comptime_safe = ast::CompSafe::Unsafe; }
    return safe;
}

fn bool walk_safe(Interp* ip, ast::AstNode* n) {
    if(n == null) { return true; }
    switch(n.h.kind) {
    case ast::AstKind::BlockStmt: {
        ast::BlockNode* b = (ast::BlockNode*)n;
        for(u64 stmt_index = 0; stmt_index < b.stmts.len; stmt_index += 1) {
            if(!walk_safe(ip, b.stmts[stmt_index])) { return false; }
        }
        return true;
    }
    case ast::AstKind::IfStmt: {
        ast::IfNode* s = (ast::IfNode*)n;
        if(!walk_safe(ip, s.cond)) { return false; }
        if(!walk_safe(ip, s.then_block)) { return false; }
        return walk_safe(ip, s.else_block);
    }
    case ast::AstKind::WhileStmt: {
        ast::WhileNode* s = (ast::WhileNode*)n;
        if(!walk_safe(ip, s.cond)) { return false; }
        return walk_safe(ip, s.body);
    }
    case ast::AstKind::ForStmt: {
        ast::ForNode* s = (ast::ForNode*)n;
        if(!walk_safe(ip, s.init)) { return false; }
        if(!walk_safe(ip, s.cond)) { return false; }
        if(!walk_safe(ip, s.post)) { return false; }
        return walk_safe(ip, s.body);
    }
    case ast::AstKind::ReturnStmt:     { return walk_safe(ip, ((ast::ReturnNode*)n).expr); }
    case ast::AstKind::AssignmentStmt: {
        ast::AssignmentNode* s = (ast::AssignmentNode*)n;
        if(!walk_safe(ip, s.lhs)) { return false; }
        return walk_safe(ip, s.rhs);
    }
    case ast::AstKind::VarDecl:  { return walk_safe(ip, ((ast::VarDeclNode*)n).init); }
    case ast::AstKind::ExprStmt: { return walk_safe(ip, ((ast::ExprStmtNode*)n).expr); }
    case ast::AstKind::BinaryOp: {
        ast::BinaryOpNode* e = (ast::BinaryOpNode*)n;
        if(!walk_safe(ip, e.lhs)) { return false; }
        return walk_safe(ip, e.rhs);
    }
    case ast::AstKind::UnaryOp: { return walk_safe(ip, ((ast::UnaryOpNode*)n).operand); }
    case ast::AstKind::Call: {
        ast::CallNode* c = (ast::CallNode*)n;
        sema::Decl* callee_d = resolved_decl(c.callee);
        if(callee_d != null && callee_d.kind == sema::DeclKind::Node && callee_d.data.node != null) {
            ast::AstNode* fnode = callee_d.data.node;
            if(fnode.h.kind == ast::AstKind::ExternFnDecl) { return false; }
            if(fnode.h.kind == ast::AstKind::FnDecl) {
                if(!ensure_comptime_safe(ip, (ast::FnDeclNode*)fnode)) { return false; }
            }
        }
        if(!walk_safe(ip, c.callee)) { return false; }
        for(u64 arg_index = 0; arg_index < c.args.len; arg_index += 1) {
            if(!walk_safe(ip, c.args[arg_index])) { return false; }
        }
        return true;
    }
    case ast::AstKind::Ident:           { return !decl_is_mutable_global(resolved_decl(n)); }
    case ast::AstKind::NamespaceAccess: { return !decl_is_mutable_global(resolved_decl(n)); }
    case ast::AstKind::MemberAccess:    { return walk_safe(ip, ((ast::MemberAccessNode*)n).base); }
    case ast::AstKind::ArrayIndex: {
        ast::ArrayIndexNode* e = (ast::ArrayIndexNode*)n;
        if(!walk_safe(ip, e.base)) { return false; }
        return walk_safe(ip, e.index);
    }
    case ast::AstKind::SliceRange: {
        ast::SliceRangeNode* e = (ast::SliceRangeNode*)n;
        if(!walk_safe(ip, e.base)) { return false; }
        if(!walk_safe(ip, e.lo)) { return false; }
        return walk_safe(ip, e.hi);
    }
    case ast::AstKind::Cast: { return walk_safe(ip, ((ast::CastNode*)n).expr); }
    case ast::AstKind::StructLit: {
        ast::StructLitNode* e = (ast::StructLitNode*)n;
        for(u64 init_index = 0; init_index < e.inits.len; init_index += 1) {
            if(!walk_safe(ip, e.inits[init_index].value)) { return false; }
        }
        return true;
    }
    case ast::AstKind::ArrayLit: {
        ast::ArrayLitNode* e = (ast::ArrayLitNode*)n;
        for(u64 elem_index = 0; elem_index < e.elems.len; elem_index += 1) {
            if(!walk_safe(ip, e.elems[elem_index])) { return false; }
        }
        return true;
    }
    case ast::AstKind::DeferStmt:   { return walk_safe(ip, ((ast::DeferNode*)n).body); }
    case ast::AstKind::ComprunStmt: { return walk_safe(ip, ((ast::CompRunNode*)n).body); }
    case ast::AstKind::ComperrorStmt:   { return walk_safe(ip, ((ast::CompErrorNode*)n).msg_expr); }
    case ast::AstKind::CompwarningStmt: { return walk_safe(ip, ((ast::CompWarningNode*)n).msg_expr); }
    case ast::AstKind::SwitchStmt: {
        ast::SwitchNode* s = (ast::SwitchNode*)n;
        if(!walk_safe(ip, s.discriminant)) { return false; }
        for(u64 arm_index = 0; arm_index < s.arms.len; arm_index += 1) {
            for(u64 label_index = 0; label_index < s.arms[arm_index].labels.len; label_index += 1) {
                if(!walk_safe(ip, s.arms[arm_index].labels[label_index])) { return false; }
            }
            if(!walk_safe(ip, s.arms[arm_index].body)) { return false; }
        }
        return walk_safe(ip, s.else_block);
    }
    else { return true; }
    }
    return true;
}

fn value::Value eval_string_lit(Interp* ip, ast::StringLitNode* n) {
    u8[] bytes;
    bytes.ptr = &ip.m.literal_pool[n.pool_off];
    bytes.len = (u64)n.pool_len;
    return value::val_bytes(bytes, (types::Ty*)n.h.ty);
}

fn void diag_unsupported(Interp* ip, u32 pos) {
    u8[] msg = "not supported at comptime";
    diag::report(&ip.m.diag, ip.m.arena, pos, msg);
}

// MONOMORPHIZATION CACHE

const u64 FNV_BASIS = 14695981039346656037;
const u64 FNV_PRIME = 1099511628211;

export struct MonoKey {
    ast::FnDeclNode* callee;
    value::Value[]   args;
}

export struct MonoEntry {
    u64              hash;      // 0 = empty slot
    MonoKey          key;
    ast::FnDeclNode* clone;
}

export struct MonoCache {
    MonoEntry* buckets;
    u64        count;
    u64        cap;
}

union FloatBits { f64 f; u64 u; }

fn u64 hash_combine(u64 h, u64 v) { return (h ^ v) * FNV_PRIME; }

fn u64 float_bits(f64 f) {
    FloatBits fb;
    fb.f = f;
    return fb.u;
}

fn u64 hash_value(value::Value v) {
    value::ValueKind kind = v.kind;
    u64 h = hash_combine(FNV_BASIS, (u64)kind);
    if(kind == value::ValueKind::Int || kind == value::ValueKind::Char) { return hash_combine(h, (u64)v.data.i); }
    if(kind == value::ValueKind::Float) { return hash_combine(h, float_bits(v.data.f)); }
    if(kind == value::ValueKind::Bool) {
        u64 b = 0;
        if(v.data.b) { b = 1; }
        return hash_combine(h, b);
    }
    if(kind == value::ValueKind::Bytes) {
        for(u64 byte_index = 0; byte_index < v.data.bytes.len; byte_index += 1) { h = hash_combine(h, (u64)v.data.bytes[byte_index]); }
        return h;
    }
    if(kind == value::ValueKind::TYPE) { return hash_combine(h, (u64)v.data.type_ref); }
    if(kind == value::ValueKind::FnRef) { return hash_combine(h, (u64)v.data.fn_ref); }
    if(kind == value::ValueKind::Struct || kind == value::ValueKind::Array) {
        for(u64 elem_index = 0; elem_index < v.data.elems.len; elem_index += 1) { h = hash_combine(h, hash_value(v.data.elems[elem_index])); }
        return h;
    }
    return h;
}

fn bool value_equal(value::Value a, value::Value b) {
    if(a.kind != b.kind) { return false; }
    value::ValueKind kind = a.kind;
    if(kind == value::ValueKind::Int || kind == value::ValueKind::Char) { return a.data.i == b.data.i; }
    if(kind == value::ValueKind::Float) { return a.data.f == b.data.f; }
    if(kind == value::ValueKind::Bool) { return a.data.b == b.data.b; }
    if(kind == value::ValueKind::Bytes) {
        if(a.data.bytes.len != b.data.bytes.len) { return false; }
        for(u64 byte_index = 0; byte_index < a.data.bytes.len; byte_index += 1) { if(a.data.bytes[byte_index] != b.data.bytes[byte_index]) { return false; } }
        return true;
    }
    if(kind == value::ValueKind::TYPE) { return a.data.type_ref == b.data.type_ref; }
    if(kind == value::ValueKind::FnRef) { return a.data.fn_ref == b.data.fn_ref; }
    if(kind == value::ValueKind::Struct || kind == value::ValueKind::Array) {
        if(a.data.elems.len != b.data.elems.len) { return false; }
        for(u64 elem_index = 0; elem_index < a.data.elems.len; elem_index += 1) { if(!value_equal(a.data.elems[elem_index], b.data.elems[elem_index])) { return false; } }
        return true;
    }
    return true;
}

fn u64 hash_mono_key(MonoKey* k) {
    u64 h = hash_combine(FNV_BASIS, (u64)k.callee);
    for(u64 arg_index = 0; arg_index < k.args.len; arg_index += 1) { h = hash_combine(h, hash_value(k.args[arg_index])); }
    if(h == 0) { h = 1; }
    return h;
}

fn bool mono_key_equal(MonoKey* a, MonoKey* b) {
    if(a.callee != b.callee) { return false; }
    if(a.args.len != b.args.len) { return false; }
    for(u64 arg_index = 0; arg_index < a.args.len; arg_index += 1) { if(!value_equal(a.args[arg_index], b.args[arg_index])) { return false; } }
    return true;
}

fn void mono_cache_grow(MonoCache* c, arena::Arena* a) {
    if(c.cap == 0) {
        c.cap = 8;
        c.buckets = arena::alloc(a, c.cap * sizeof(MonoEntry));
        for(u64 slot = 0; slot < c.cap; slot += 1) { c.buckets[slot].hash = 0; }
        return;
    }
    if(c.count * 4 < c.cap * 3) { return; }
    u64 old_cap = c.cap;
    MonoEntry* old = c.buckets;
    u64 new_cap = c.cap * 2;
    MonoEntry* nb = arena::alloc(a, new_cap * sizeof(MonoEntry));
    for(u64 slot = 0; slot < new_cap; slot += 1) { nb[slot].hash = 0; }
    for(u64 slot = 0; slot < old_cap; slot += 1) {
        if(old[slot].hash != 0) {
            u64 idx = old[slot].hash % new_cap;
            while(nb[idx].hash != 0) { idx = (idx + 1) % new_cap; }
            nb[idx] = old[slot];
        }
    }
    c.buckets = nb;
    c.cap = new_cap;
}

export fn ast::FnDeclNode* mono_cache_lookup(MonoCache* c, MonoKey* key) {
    if(c.cap == 0) { return null; }
    u64 h = hash_mono_key(key);
    u64 idx = h % c.cap;
    while(c.buckets[idx].hash != 0) {
        if(c.buckets[idx].hash == h && mono_key_equal(&c.buckets[idx].key, key)) { return c.buckets[idx].clone; }
        idx = (idx + 1) % c.cap;
    }
    return null;
}

export fn void mono_cache_insert(MonoCache* c, arena::Arena* a, MonoKey key, ast::FnDeclNode* clone) {
    mono_cache_grow(c, a);
    u64 h = hash_mono_key(&key);
    u64 idx = h % c.cap;
    while(c.buckets[idx].hash != 0) {
        if(c.buckets[idx].hash == h && mono_key_equal(&c.buckets[idx].key, &key)) {
            c.buckets[idx].clone = clone;
            return;
        }
        idx = (idx + 1) % c.cap;
    }
    c.buckets[idx].hash = h;
    c.buckets[idx].key = key;
    c.buckets[idx].clone = clone;
    c.count += 1;
}

// AST DEEP-CLONE (for monomorphization)

fn ast::AstNode* dup(arena::Arena* a, ast::AstNode* n, u64 size) {
    void* c = arena::alloc(a, size);
    sys::memcpy(c, (void*)n, size);
    return (ast::AstNode*)c;
}

fn ast::AstNode*[] clone_node_list(arena::Arena* a, ast::AstNode*[] list) {
    ast::AstNode*[] out;
    out.ptr = null;
    out.len = 0;
    if(list.len > 0) {
        out.ptr = arena::alloc(a, list.len * sizeof(ast::AstNode*));
        out.len = list.len;
        for(u64 i = 0; i < list.len; i += 1) { out[i] = clone_node(a, list[i]); }
    }
    return out;
}

fn ast::Param[] clone_params(arena::Arena* a, ast::Param[] params) {
    ast::Param[] out;
    out.ptr = null;
    out.len = 0;
    if(params.len > 0) {
        out.ptr = arena::alloc(a, params.len * sizeof(ast::Param));
        out.len = params.len;
        for(u64 i = 0; i < params.len; i += 1) {
            out[i] = params[i];
            out[i].type_expr = clone_node(a, params[i].type_expr);
        }
    }
    return out;
}

fn ast::FieldDecl[] clone_fields(arena::Arena* a, ast::FieldDecl[] fields) {
    ast::FieldDecl[] out;
    out.ptr = null;
    out.len = 0;
    if(fields.len > 0) {
        out.ptr = arena::alloc(a, fields.len * sizeof(ast::FieldDecl));
        out.len = fields.len;
        for(u64 i = 0; i < fields.len; i += 1) {
            out[i] = fields[i];
            out[i].type_expr = clone_node(a, fields[i].type_expr);
        }
    }
    return out;
}

fn ast::SwitchArm[] clone_arms(arena::Arena* a, ast::SwitchArm[] arms) {
    ast::SwitchArm[] out;
    out.ptr = null;
    out.len = 0;
    if(arms.len > 0) {
        out.ptr = arena::alloc(a, arms.len * sizeof(ast::SwitchArm));
        out.len = arms.len;
        for(u64 i = 0; i < arms.len; i += 1) {
            out[i] = arms[i];
            out[i].labels = clone_node_list(a, arms[i].labels);
            out[i].body = clone_node(a, arms[i].body);
        }
    }
    return out;
}

fn ast::FieldInitializer[] clone_inits(arena::Arena* a, ast::FieldInitializer[] inits) {
    ast::FieldInitializer[] out;
    out.ptr = null;
    out.len = 0;
    if(inits.len > 0) {
        out.ptr = arena::alloc(a, inits.len * sizeof(ast::FieldInitializer));
        out.len = inits.len;
        for(u64 i = 0; i < inits.len; i += 1) {
            out[i] = inits[i];
            out[i].value = clone_node(a, inits[i].value);
        }
    }
    return out;
}

fn ast::AstNode* clone_node(arena::Arena* a, ast::AstNode* n) {
    if(n == null) { return null; }
    switch(n.h.kind) {
    case ast::AstKind::IntLit:       { return dup(a, n, sizeof(ast::IntLitNode)); }
    case ast::AstKind::FloatLit:     { return dup(a, n, sizeof(ast::FloatLitNode)); }
    case ast::AstKind::BoolLit:      { return dup(a, n, sizeof(ast::BoolLitNode)); }
    case ast::AstKind::CharLit:      { return dup(a, n, sizeof(ast::CharLitNode)); }
    case ast::AstKind::StringLit:    { return dup(a, n, sizeof(ast::StringLitNode)); }
    case ast::AstKind::NullLit:      { return dup(a, n, sizeof(ast::NullLitNode)); }
    case ast::AstKind::UndefinedLit: { return dup(a, n, sizeof(ast::UndefinedLitNode)); }
    case ast::AstKind::Ident:        { return dup(a, n, sizeof(ast::IdentNode)); }
    case ast::AstKind::PrimitiveType: { return dup(a, n, sizeof(ast::TypePrimitiveNode)); }
    case ast::AstKind::NamedType:    { return dup(a, n, sizeof(ast::TypeNamedNode)); }
    case ast::AstKind::NamespaceAccess: {
        ast::NamespaceAccessNode* c = (ast::NamespaceAccessNode*)dup(a, n, sizeof(ast::NamespaceAccessNode));
        c.base = clone_node(a, c.base);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::MemberAccess: {
        ast::MemberAccessNode* c = (ast::MemberAccessNode*)dup(a, n, sizeof(ast::MemberAccessNode));
        c.base = clone_node(a, c.base);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::ArrayIndex: {
        ast::ArrayIndexNode* c = (ast::ArrayIndexNode*)dup(a, n, sizeof(ast::ArrayIndexNode));
        c.base = clone_node(a, c.base);
        c.index = clone_node(a, c.index);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::SliceRange: {
        ast::SliceRangeNode* c = (ast::SliceRangeNode*)dup(a, n, sizeof(ast::SliceRangeNode));
        c.base = clone_node(a, c.base);
        c.lo = clone_node(a, c.lo);
        c.hi = clone_node(a, c.hi);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::Call: {
        ast::CallNode* c = (ast::CallNode*)dup(a, n, sizeof(ast::CallNode));
        c.callee = clone_node(a, c.callee);
        c.args = clone_node_list(a, c.args);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::Cast: {
        ast::CastNode* c = (ast::CastNode*)dup(a, n, sizeof(ast::CastNode));
        c.target_type = clone_node(a, c.target_type);
        c.expr = clone_node(a, c.expr);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::UnaryOp: {
        ast::UnaryOpNode* c = (ast::UnaryOpNode*)dup(a, n, sizeof(ast::UnaryOpNode));
        c.operand = clone_node(a, c.operand);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::BinaryOp: {
        ast::BinaryOpNode* c = (ast::BinaryOpNode*)dup(a, n, sizeof(ast::BinaryOpNode));
        c.lhs = clone_node(a, c.lhs);
        c.rhs = clone_node(a, c.rhs);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::StructLit: {
        ast::StructLitNode* c = (ast::StructLitNode*)dup(a, n, sizeof(ast::StructLitNode));
        c.inits = clone_inits(a, c.inits);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::ArrayLit: {
        ast::ArrayLitNode* c = (ast::ArrayLitNode*)dup(a, n, sizeof(ast::ArrayLitNode));
        c.elems = clone_node_list(a, c.elems);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::Sizeof: {
        ast::SizeofNode* c = (ast::SizeofNode*)dup(a, n, sizeof(ast::SizeofNode));
        c.arg = clone_node(a, c.arg);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::Alignof: {
        ast::AlignofNode* c = (ast::AlignofNode*)dup(a, n, sizeof(ast::AlignofNode));
        c.arg = clone_node(a, c.arg);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::Typeof: {
        ast::TypeofNode* c = (ast::TypeofNode*)dup(a, n, sizeof(ast::TypeofNode));
        c.expr = clone_node(a, c.expr);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::Type_info: {
        ast::TypeInfoNode* c = (ast::TypeInfoNode*)dup(a, n, sizeof(ast::TypeInfoNode));
        c.arg = clone_node(a, c.arg);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::BlockStmt: {
        ast::BlockNode* c = (ast::BlockNode*)dup(a, n, sizeof(ast::BlockNode));
        c.stmts = clone_node_list(a, c.stmts);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::IfStmt: {
        ast::IfNode* c = (ast::IfNode*)dup(a, n, sizeof(ast::IfNode));
        c.cond = clone_node(a, c.cond);
        c.then_block = clone_node(a, c.then_block);
        c.else_block = clone_node(a, c.else_block);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::WhileStmt: {
        ast::WhileNode* c = (ast::WhileNode*)dup(a, n, sizeof(ast::WhileNode));
        c.cond = clone_node(a, c.cond);
        c.body = clone_node(a, c.body);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::ForStmt: {
        ast::ForNode* c = (ast::ForNode*)dup(a, n, sizeof(ast::ForNode));
        c.init = clone_node(a, c.init);
        c.cond = clone_node(a, c.cond);
        c.post = clone_node(a, c.post);
        c.body = clone_node(a, c.body);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::SwitchStmt: {
        ast::SwitchNode* c = (ast::SwitchNode*)dup(a, n, sizeof(ast::SwitchNode));
        c.discriminant = clone_node(a, c.discriminant);
        c.arms = clone_arms(a, c.arms);
        c.else_block = clone_node(a, c.else_block);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::ReturnStmt: {
        ast::ReturnNode* c = (ast::ReturnNode*)dup(a, n, sizeof(ast::ReturnNode));
        c.expr = clone_node(a, c.expr);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::DeferStmt: {
        ast::DeferNode* c = (ast::DeferNode*)dup(a, n, sizeof(ast::DeferNode));
        c.body = clone_node(a, c.body);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::AssignmentStmt: {
        ast::AssignmentNode* c = (ast::AssignmentNode*)dup(a, n, sizeof(ast::AssignmentNode));
        c.lhs = clone_node(a, c.lhs);
        c.rhs = clone_node(a, c.rhs);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::VarDecl: {
        ast::VarDeclNode* c = (ast::VarDeclNode*)dup(a, n, sizeof(ast::VarDeclNode));
        c.type_expr = clone_node(a, c.type_expr);
        c.init = clone_node(a, c.init);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::ExprStmt: {
        ast::ExprStmtNode* c = (ast::ExprStmtNode*)dup(a, n, sizeof(ast::ExprStmtNode));
        c.expr = clone_node(a, c.expr);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::ComprunStmt: {
        ast::CompRunNode* c = (ast::CompRunNode*)dup(a, n, sizeof(ast::CompRunNode));
        c.body = clone_node(a, c.body);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::ComperrorStmt: {
        ast::CompErrorNode* c = (ast::CompErrorNode*)dup(a, n, sizeof(ast::CompErrorNode));
        c.msg_expr = clone_node(a, c.msg_expr);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::CompwarningStmt: {
        ast::CompWarningNode* c = (ast::CompWarningNode*)dup(a, n, sizeof(ast::CompWarningNode));
        c.msg_expr = clone_node(a, c.msg_expr);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::CompinsertStmt: {
        ast::CompInsertNode* c = (ast::CompInsertNode*)dup(a, n, sizeof(ast::CompInsertNode));
        c.source_expr = clone_node(a, c.source_expr);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::CompspliceStmt: {
        ast::CompSpliceNode* c = (ast::CompSpliceNode*)dup(a, n, sizeof(ast::CompSpliceNode));
        c.code_expr = clone_node(a, c.code_expr);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::Compcode: {
        ast::CompCodeNode* c = (ast::CompCodeNode*)dup(a, n, sizeof(ast::CompCodeNode));
        c.body = clone_node(a, c.body);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::PointerType: {
        ast::TypePointerNode* c = (ast::TypePointerNode*)dup(a, n, sizeof(ast::TypePointerNode));
        c.pointee = clone_node(a, c.pointee);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::ArrayType: {
        ast::TypeArrayNode* c = (ast::TypeArrayNode*)dup(a, n, sizeof(ast::TypeArrayNode));
        c.element = clone_node(a, c.element);
        c.size_expr = clone_node(a, c.size_expr);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::SliceType: {
        ast::TypeSliceNode* c = (ast::TypeSliceNode*)dup(a, n, sizeof(ast::TypeSliceNode));
        c.element = clone_node(a, c.element);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::FnPtrType: {
        ast::TypeFnPtrNode* c = (ast::TypeFnPtrNode*)dup(a, n, sizeof(ast::TypeFnPtrNode));
        c.return_type = clone_node(a, c.return_type);
        c.param_types = clone_node_list(a, c.param_types);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::StructType: {
        ast::TypeStructNode* c = (ast::TypeStructNode*)dup(a, n, sizeof(ast::TypeStructNode));
        c.fields = clone_fields(a, c.fields);
        return (ast::AstNode*)c;
    }
    case ast::AstKind::UnionType: {
        ast::TypeUnionNode* c = (ast::TypeUnionNode*)dup(a, n, sizeof(ast::TypeUnionNode));
        c.fields = clone_fields(a, c.fields);
        return (ast::AstNode*)c;
    }
    else { return n; }      // unreachable — all in-body kinds enumerated; share rather than risk garbage child pointers
    }
    return null;
}

export fn ast::FnDeclNode* clone_fn_decl(arena::Arena* a, ast::FnDeclNode* orig) {
    ast::FnDeclNode* c = (ast::FnDeclNode*)dup(a, (ast::AstNode*)orig, sizeof(ast::FnDeclNode));
    c.return_type = clone_node(a, orig.return_type);
    c.params = clone_params(a, orig.params);
    c.body = clone_node(a, orig.body);
    c.cfg = null;
    c.decl = null;
    return c;
}

fn void instantiated_fns_push(module::Module* m, ast::FnDeclNode* clone) {
    list::push(&m.instantiated_fns, m.arena, clone);
}

// Distinct deterministic name per instantiation (module-qualified type reprs) so it mangles identically across modules for linkonce_odr dedup.
fn void rename_mangled(module::Module* m, ast::FnDeclNode* clone, value::Value[] cargs) {
    symbol::Symbol* base = clone.qualified_name;
    if(base == null) { base = clone.name; }
    if(base == null) { return; }
    u8[256] scratch;
    u8[] base_str = interner::symbol_str(base);
    i32 off = sys::snprintf((i8*)&scratch[0], 256, "%.*s", (i32)base_str.len, (i8*)base_str.ptr);
    for(u64 k = 0; k < cargs.len; k += 1) {
        if(off < 0 || off >= 240) { break; }
        if(cargs[k].kind == value::ValueKind::TYPE) {
            u8[] ts = types_print::print_to_arena(cargs[k].data.type_ref, m.arena);
            off += sys::snprintf((i8*)&scratch[off], (u64)(256 - off), "__%.*s", (i32)ts.len, (i8*)ts.ptr);
        } else if(cargs[k].kind == value::ValueKind::Int) {
            off += sys::snprintf((i8*)&scratch[off], (u64)(256 - off), "__%ld", cargs[k].data.i);
        }
    }
    if(off <= 0) { return; }
    u8[] mangled = {&scratch[0], (u64)off};
    symbol::Symbol* sym = interner::intern(mangled);
    clone.name = sym;
    clone.qualified_name = sym;
}

export fn ast::FnDeclNode* monomorphize(Interp* ip, ast::FnDeclNode* callee, value::Value[] cargs) {
    if(ip.m.mono_cache == null) {
        ip.m.mono_cache = arena::alloc(ip.m.arena, sizeof(MonoCache));
        sys::memset(ip.m.mono_cache, 0, sizeof(MonoCache));
    }
    MonoCache* cache = (MonoCache*)ip.m.mono_cache;
    MonoKey key;
    key.callee = callee;
    key.args = cargs;
    ast::FnDeclNode* hit = mono_cache_lookup(cache, &key);
    if(hit != null) { return hit; }
    ast::FnDeclNode* clone = clone_fn_decl(ip.m.arena, callee);
    rename_mangled(ip.m, clone, cargs);
    substitute_type_params(ip.m.arena, clone, cargs);
    // Cache before re-checking, so a recursive generic call in the body hits the cache, not endless monomorphization.
    mono_cache_insert(cache, ip.m.arena, key, clone);
    instantiated_fns_push(ip.m, clone);
    module::Module* defining = ip.m;
    if(callee.decl != null) { defining = ((sema::Decl*)callee.decl).home; }
    sema::sema_check_clone(ip.m, defining, clone);
    return clone;
}

// A value-param ident is rewritten in place to an IntLit (fits an IdentNode) so eval_const_u64 reads N in T[N].
struct SubstCtx {
    symbol::Symbol*[] tnames;
    types::Ty*[]    ttys;
    symbol::Symbol*[] vnames;
    u64[]             vvals;
    types::Ty*[]    vtys;
}

fn void subst_node(SubstCtx* c, ast::AstNode* n) {
    if(n == null) { return; }
    switch(n.h.kind) {
    case ast::AstKind::NamedType: {
        ast::TypeNamedNode* t = (ast::TypeNamedNode*)n;
        if(t.namespace == null) {
            for(u64 i = 0; i < c.tnames.len; i += 1) {
                if(t.name == c.tnames[i]) { t.h.ty = (void*)c.ttys[i]; return; }
            }
        }
        return;
    }
    case ast::AstKind::PointerType: { subst_node(c, ((ast::TypePointerNode*)n).pointee); return; }
    case ast::AstKind::SliceType:   { subst_node(c, ((ast::TypeSliceNode*)n).element); return; }
    case ast::AstKind::ArrayType: {
        ast::TypeArrayNode* t = (ast::TypeArrayNode*)n;
        subst_node(c, t.element);
        subst_size_expr(c, t.size_expr);
        return;
    }
    case ast::AstKind::FnPtrType: {
        ast::TypeFnPtrNode* t = (ast::TypeFnPtrNode*)n;
        subst_node(c, t.return_type);
        for(u64 i = 0; i < t.param_types.len; i += 1) { subst_node(c, t.param_types[i]); }
        return;
    }
    case ast::AstKind::StructType: {
        ast::TypeStructNode* t = (ast::TypeStructNode*)n;
        for(u64 i = 0; i < t.fields.len; i += 1) { subst_node(c, t.fields[i].type_expr); }
        return;
    }
    case ast::AstKind::UnionType: {
        ast::TypeUnionNode* t = (ast::TypeUnionNode*)n;
        for(u64 i = 0; i < t.fields.len; i += 1) { subst_node(c, t.fields[i].type_expr); }
        return;
    }
    case ast::AstKind::BlockStmt: {
        ast::BlockNode* b = (ast::BlockNode*)n;
        for(u64 i = 0; i < b.stmts.len; i += 1) { subst_node(c, b.stmts[i]); }
        return;
    }
    case ast::AstKind::IfStmt: {
        ast::IfNode* s = (ast::IfNode*)n;
        subst_node(c, s.cond);
        subst_node(c, s.then_block);
        subst_node(c, s.else_block);
        return;
    }
    case ast::AstKind::WhileStmt: {
        ast::WhileNode* s = (ast::WhileNode*)n;
        subst_node(c, s.cond);
        subst_node(c, s.body);
        return;
    }
    case ast::AstKind::ForStmt: {
        ast::ForNode* s = (ast::ForNode*)n;
        subst_node(c, s.init);
        subst_node(c, s.cond);
        subst_node(c, s.post);
        subst_node(c, s.body);
        return;
    }
    case ast::AstKind::SwitchStmt: {
        ast::SwitchNode* s = (ast::SwitchNode*)n;
        subst_node(c, s.discriminant);
        for(u64 i = 0; i < s.arms.len; i += 1) {
            for(u64 j = 0; j < s.arms[i].labels.len; j += 1) { subst_node(c, s.arms[i].labels[j]); }
            subst_node(c, s.arms[i].body);
        }
        subst_node(c, s.else_block);
        return;
    }
    case ast::AstKind::ReturnStmt:     { subst_node(c, ((ast::ReturnNode*)n).expr); return; }
    case ast::AstKind::DeferStmt:      { subst_node(c, ((ast::DeferNode*)n).body); return; }
    case ast::AstKind::ExprStmt:       { subst_node(c, ((ast::ExprStmtNode*)n).expr); return; }
    case ast::AstKind::AssignmentStmt: {
        ast::AssignmentNode* s = (ast::AssignmentNode*)n;
        subst_node(c, s.lhs);
        subst_node(c, s.rhs);
        return;
    }
    case ast::AstKind::VarDecl: {
        ast::VarDeclNode* s = (ast::VarDeclNode*)n;
        subst_node(c, s.type_expr);
        subst_node(c, s.init);
        return;
    }
    case ast::AstKind::BinaryOp: {
        ast::BinaryOpNode* e = (ast::BinaryOpNode*)n;
        subst_node(c, e.lhs);
        subst_node(c, e.rhs);
        return;
    }
    case ast::AstKind::UnaryOp:      { subst_node(c, ((ast::UnaryOpNode*)n).operand); return; }
    case ast::AstKind::MemberAccess: { subst_node(c, ((ast::MemberAccessNode*)n).base); return; }
    case ast::AstKind::ArrayIndex: {
        ast::ArrayIndexNode* e = (ast::ArrayIndexNode*)n;
        subst_node(c, e.base);
        subst_node(c, e.index);
        return;
    }
    case ast::AstKind::SliceRange: {
        ast::SliceRangeNode* e = (ast::SliceRangeNode*)n;
        subst_node(c, e.base);
        subst_node(c, e.lo);
        subst_node(c, e.hi);
        return;
    }
    case ast::AstKind::Call: {
        ast::CallNode* e = (ast::CallNode*)n;
        subst_node(c, e.callee);
        for(u64 i = 0; i < e.args.len; i += 1) { subst_node(c, e.args[i]); }
        return;
    }
    case ast::AstKind::Cast: {
        ast::CastNode* e = (ast::CastNode*)n;
        subst_node(c, e.target_type);
        subst_node(c, e.expr);
        return;
    }
    case ast::AstKind::StructLit: {
        ast::StructLitNode* e = (ast::StructLitNode*)n;
        for(u64 i = 0; i < e.inits.len; i += 1) { subst_node(c, e.inits[i].value); }
        return;
    }
    case ast::AstKind::ArrayLit: {
        ast::ArrayLitNode* e = (ast::ArrayLitNode*)n;
        for(u64 i = 0; i < e.elems.len; i += 1) { subst_node(c, e.elems[i]); }
        return;
    }
    case ast::AstKind::Sizeof:    { subst_node(c, ((ast::SizeofNode*)n).arg); return; }
    case ast::AstKind::Alignof:   { subst_node(c, ((ast::AlignofNode*)n).arg); return; }
    case ast::AstKind::Typeof:    { subst_node(c, ((ast::TypeofNode*)n).expr); return; }
    case ast::AstKind::Type_info: { subst_node(c, ((ast::TypeInfoNode*)n).arg); return; }
    case ast::AstKind::ComprunStmt:     { subst_node(c, ((ast::CompRunNode*)n).body); return; }
    case ast::AstKind::ComperrorStmt:   { subst_node(c, ((ast::CompErrorNode*)n).msg_expr); return; }
    case ast::AstKind::CompwarningStmt: { subst_node(c, ((ast::CompWarningNode*)n).msg_expr); return; }
    case ast::AstKind::CompinsertStmt:  { subst_node(c, ((ast::CompInsertNode*)n).source_expr); return; }
    case ast::AstKind::CompspliceStmt:  { subst_node(c, ((ast::CompSpliceNode*)n).code_expr); return; }
    case ast::AstKind::Compcode:        { subst_node(c, ((ast::CompCodeNode*)n).body); return; }
    case ast::AstKind::NamespaceAccess: { subst_node(c, ((ast::NamespaceAccessNode*)n).base); return; }
    else { return; }
    }
}

// Only array sizes need a value param as a sema-time literal; value idents elsewhere resolve via env (shadow-safe).
fn void subst_size_expr(SubstCtx* c, ast::AstNode* n) {
    if(n == null) { return; }
    switch(n.h.kind) {
    case ast::AstKind::Ident: {
        ast::IdentNode* id = (ast::IdentNode*)n;
        for(u64 i = 0; i < c.vnames.len; i += 1) {
            if(id.name == c.vnames[i]) {
                n.h.kind = ast::AstKind::IntLit;
                n.h.ty = (void*)c.vtys[i];
                ((ast::IntLitNode*)n).value = c.vvals[i];
                return;
            }
        }
        return;
    }
    case ast::AstKind::BinaryOp: {
        ast::BinaryOpNode* e = (ast::BinaryOpNode*)n;
        subst_size_expr(c, e.lhs);
        subst_size_expr(c, e.rhs);
        return;
    }
    case ast::AstKind::UnaryOp: { subst_size_expr(c, ((ast::UnaryOpNode*)n).operand); return; }
    else { subst_node(c, n); return; }
    }
}

fn void substitute_type_params(arena::Arena* a, ast::FnDeclNode* clone, value::Value[] cargs) {
    u64 n_type = 0;
    u64 n_val = 0;
    u64 carg_index = 0;
    for(u64 i = 0; i < clone.params.len; i += 1) {
        if(clone.params[i].is_comptime) {
            if(cargs[carg_index].kind == value::ValueKind::TYPE) { n_type += 1; }
            else if(cargs[carg_index].kind == value::ValueKind::Int) { n_val += 1; }
            carg_index += 1;
        }
    }
    if(n_type == 0 && n_val == 0) { return; }
    SubstCtx c;
    sys::memset(&c, 0, sizeof(SubstCtx));
    c.tnames.ptr = arena::alloc(a, n_type * sizeof(symbol::Symbol*));
    c.ttys.ptr = arena::alloc(a, n_type * sizeof(types::Ty*));
    c.vnames.ptr = arena::alloc(a, n_val * sizeof(symbol::Symbol*));
    c.vvals.ptr = arena::alloc(a, n_val * sizeof(u64));
    c.vtys.ptr = arena::alloc(a, n_val * sizeof(types::Ty*));
    carg_index = 0;
    for(u64 i = 0; i < clone.params.len; i += 1) {
        if(clone.params[i].is_comptime) {
            if(cargs[carg_index].kind == value::ValueKind::TYPE) {
                c.tnames[c.tnames.len] = clone.params[i].name;
                c.tnames.len += 1;
                c.ttys[c.ttys.len] = cargs[carg_index].data.type_ref;
                c.ttys.len += 1;
            } else if(cargs[carg_index].kind == value::ValueKind::Int) {
                c.vnames[c.vnames.len] = clone.params[i].name;
                c.vnames.len += 1;
                c.vvals[c.vvals.len] = (u64)cargs[carg_index].data.i;
                c.vvals.len += 1;
                c.vtys[c.vtys.len] = cargs[carg_index].ty;
                c.vtys.len += 1;
            }
            carg_index += 1;
        }
    }
    subst_node(&c, clone.return_type);
    for(u64 i = 0; i < clone.params.len; i += 1) { subst_node(&c, clone.params[i].type_expr); }
    subst_node(&c, clone.body);
}

// GENERIC CALL RESOLUTION (sema seam): infer comptime args by unifying param patterns against arg types, then monomorphize.

fn bool unify_type(symbol::Symbol*[] names, value::Value[] binds, ast::AstNode* pattern, types::Ty* concrete) {
    if(pattern == null || concrete == null) { return false; }
    switch(pattern.h.kind) {
    case ast::AstKind::NamedType: {
        ast::TypeNamedNode* tn = (ast::TypeNamedNode*)pattern;
        if(tn.namespace == null) {
            for(u64 k = 0; k < names.len; k += 1) {
                if(tn.name == names[k]) {
                    if(binds[k].kind == value::ValueKind::Void) { binds[k] = value::val_type(concrete); return true; }
                    return binds[k].data.type_ref == concrete;
                }
            }
        }
        return true;
    }
    case ast::AstKind::PointerType: {
        if(concrete.kind != types::TypeKind::Pointer) { return false; }
        return unify_type(names, binds, ((ast::TypePointerNode*)pattern).pointee, concrete.data.pointee);
    }
    case ast::AstKind::SliceType: {
        if(concrete.kind != types::TypeKind::Slice) { return false; }
        return unify_type(names, binds, ((ast::TypeSliceNode*)pattern).element, concrete.data.slice_elem);
    }
    case ast::AstKind::ArrayType: {
        if(concrete.kind != types::TypeKind::Array) { return false; }
        return unify_type(names, binds, ((ast::TypeArrayNode*)pattern).element, concrete.data.array.elem);
    }
    case ast::AstKind::FnPtrType: {
        if(concrete.kind != types::TypeKind::FnPtr) { return false; }
        ast::TypeFnPtrNode* fp = (ast::TypeFnPtrNode*)pattern;
        if(!unify_type(names, binds, fp.return_type, concrete.data.fn_ptr.ret)) { return false; }
        if(fp.param_types.len != concrete.data.fn_ptr.params.len) { return false; }
        for(u64 i = 0; i < fp.param_types.len; i += 1) {
            if(!unify_type(names, binds, fp.param_types[i], concrete.data.fn_ptr.params[i])) { return false; }
        }
        return true;
    }
    else { return true; }
    }
    return true;
}

export fn ast::FnDeclNode* resolve_generic_call(module::Module* m, ast::FnDeclNode* callee, types::Ty*[] arg_types) {
    u64 n_comptime = 0;
    for(u64 i = 0; i < callee.params.len; i += 1) {
        if(callee.params[i].is_comptime) { n_comptime += 1; }
    }
    if(n_comptime == 0) { return null; }
    symbol::Symbol*[] names;
    names.ptr = (symbol::Symbol**)arena::alloc(m.arena, n_comptime * sizeof(symbol::Symbol*));
    names.len = 0;
    value::Value[] binds;
    binds.ptr = (value::Value*)arena::alloc(m.arena, n_comptime * sizeof(value::Value));
    binds.len = n_comptime;
    for(u64 i = 0; i < callee.params.len; i += 1) {
        if(callee.params[i].is_comptime) { names[names.len] = callee.params[i].name; names.len += 1; }
    }
    for(u64 k = 0; k < n_comptime; k += 1) { binds[k] = value::val_void(); }
    u64 runtime_index = 0;
    for(u64 i = 0; i < callee.params.len; i += 1) {
        if(callee.params[i].is_comptime) { continue; }
        if(runtime_index >= arg_types.len) { return null; }
        if(!unify_type(names, binds, callee.params[i].type_expr, arg_types[runtime_index])) { return null; }
        runtime_index += 1;
    }
    for(u64 k = 0; k < n_comptime; k += 1) {
        if(binds[k].kind == value::ValueKind::Void) { return null; }
    }
    Interp ip = new_interp(m);
    return monomorphize(&ip, callee, binds);
}

export fn ast::FnDeclNode* resolve_generic_explicit(module::Module* m, ast::FnDeclNode* callee, value::Value[] cargs) {
    Interp ip = new_interp(m);
    return monomorphize(&ip, callee, cargs);
}

fn void run_comprun(module::Module* m, ast::CompRunNode* n) {
    Interp ip = new_interp(m);
    eval_comprun(&ip, n);
}

// Quiet const-eval to i64 (no diagnostic on failure); the caller only asks for known-constant expressions.
fn bool const_eval_i64(module::Module* m, ast::AstNode* expr, i64* out) {
    Interp ip = new_interp(m);
    value::Value v = eval(&ip, expr);
    if(v.kind == value::ValueKind::Int) { *out = v.data.i; return true; }
    return false;
}

// Folds a constant expression to its full value; lowering uses this to build global initializers.
export fn value::Value eval_const_value(module::Module* m, ast::AstNode* expr) {
    Interp ip = new_interp(m);
    return eval(&ip, expr);
}

// Evaluates a comptime expression that must yield a Type (a `fn Type` call in type position); null if it isn't a Type.
fn types::Ty* eval_comptime_type(module::Module* m, ast::AstNode* expr) {
    Interp ip = new_interp(m);
    value::Value v = eval(&ip, expr);
    if(v.kind == value::ValueKind::TYPE) { return (types::Ty*)v.data.type_ref; }
    return null;
}

export fn void install_hooks() {
    sema::resolve_generic_call_hook = &resolve_generic_call;
    sema::resolve_generic_explicit_hook = &resolve_generic_explicit;
    sema::run_comprun_hook = &run_comprun;
    sema::run_compinsert_stmts_hook = &run_compinsert_stmts;
    sema::eval_const_i64_hook = &const_eval_i64;
    sema::eval_comptime_type_hook = &eval_comptime_type;
}
