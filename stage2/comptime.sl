import value;
import ast;
import module;
import arena;
import types;
import diag;
import sema;
import op;
import token;
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
    bool            returning;      // set by eval_return; unwinds block/loop evaluation
    value::Value    return_value;
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
    ip.max_iterations = 10000000;
    ip.env = env_push(null, m.arena, 16);
    return ip;
}

export fn value::Value eval(Interp* ip, ast::AstNode* e) {
    if(e == null) { return value::val_error(); }
    if(((u16)e.h.flags & (u16)ast::AstFlags::HadError) != 0) { return value::val_error(); }
    switch(e.h.kind) {
    case ast::AstKind::IntLit: {
        ast::IntLitNode* lit = (ast::IntLitNode*)e;
        return value::val_int((i64)lit.value, (types::Type*)e.h.ty);
    }
    case ast::AstKind::FloatLit: {
        ast::FloatLitNode* lit = (ast::FloatLitNode*)e;
        return value::val_float(lit.value, (types::Type*)e.h.ty);
    }
    case ast::AstKind::BoolLit: {
        ast::BoolLitNode* lit = (ast::BoolLitNode*)e;
        return value::val_bool(lit.value);
    }
    case ast::AstKind::CharLit: {
        ast::CharLitNode* lit = (ast::CharLitNode*)e;
        return value::val_int((i64)lit.value, (types::Type*)e.h.ty);
    }
    case ast::AstKind::StringLit: { return eval_string_lit(ip, (ast::StringLitNode*)e); }
    case ast::AstKind::NullLit:   { return value::val_null((types::Type*)e.h.ty); }
    case ast::AstKind::BinaryOp:  { return eval_binary(ip, (ast::BinaryOpNode*)e); }
    case ast::AstKind::UnaryOp:   { return eval_unary(ip, (ast::UnaryOpNode*)e); }
    case ast::AstKind::Ident:     { return eval_ident(ip, (ast::IdentNode*)e); }
    case ast::AstKind::BlockStmt: { return eval_block(ip, (ast::BlockNode*)e); }
    case ast::AstKind::VarDecl:   { return eval_local_var_decl(ip, (ast::VarDeclNode*)e); }
    case ast::AstKind::ExprStmt: {
        ast::ExprStmtNode* s = (ast::ExprStmtNode*)e;
        return eval(ip, s.expr);
    }
    case ast::AstKind::IfStmt:        { return eval_if(ip, (ast::IfNode*)e); }
    case ast::AstKind::WhileStmt:     { return eval_while(ip, (ast::WhileNode*)e); }
    case ast::AstKind::ForStmt:       { return eval_for(ip, (ast::ForNode*)e); }
    case ast::AstKind::ReturnStmt:    { return eval_return(ip, (ast::ReturnNode*)e); }
    case ast::AstKind::AssignmentStmt: { return eval_assignment(ip, (ast::AssignmentNode*)e); }
    case ast::AstKind::Sizeof:    { return eval_sizeof(ip, (ast::SizeofNode*)e); }
    case ast::AstKind::Alignof:   { return eval_alignof(ip, (ast::AlignofNode*)e); }
    case ast::AstKind::Typeof:    { return eval_typeof(ip, (ast::TypeofNode*)e); }
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
    if(d.kind == (u16)sema::DeclKind::Node && d.data.node != null && d.data.node.h.kind == ast::AstKind::VarDecl) {
        ast::VarDeclNode* vd = (ast::VarDeclNode*)d.data.node;
        if(vd.is_const && vd.init != null) { return eval(ip, vd.init); }
    }
    u8[] msg = "identifier is not a comptime value";
    diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg);
    return value::val_error();
}

fn value::Value eval_block(Interp* ip, ast::BlockNode* n) {
    Env* saved = ip.env;
    ip.env = env_push(saved, ip.m.arena, 8);
    value::Value result = value::val_void();
    for(u64 stmt_index = 0; stmt_index < n.stmts.len; stmt_index += 1) {
        value::Value v = eval(ip, n.stmts[stmt_index]);
        if(v.kind == (u16)value::ValueKind::Error) { result = v; break; }
        if(ip.returning) { break; }
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
        if(v.kind == (u16)value::ValueKind::Error) { return v; }
    }
    env_bind(ip.env, ip.m.arena, d, v);
    return value::val_void();
}

// Saplang conditions accept bool, integer (zero/non-zero), and pointer/slice (null/non-null).
fn value::Value eval_cond(Interp* ip, ast::AstNode* cond) {
    value::Value v = eval(ip, cond);
    if(v.kind == (u16)value::ValueKind::Error) { return v; }
    if(v.kind == (u16)value::ValueKind::Bool) { return v; }
    if(v.kind == (u16)value::ValueKind::Int) { return value::val_bool(v.data.i != 0); }
    if(v.kind == (u16)value::ValueKind::Null) { return value::val_bool(false); }
    if(v.kind == (u16)value::ValueKind::Bytes) { return value::val_bool(v.data.bytes.ptr != null); }
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
        if(v.kind == (u16)value::ValueKind::Error) { return v; }
    }
    ip.return_value = v;
    ip.returning = true;
    return v;
}

fn value::Value eval_if(Interp* ip, ast::IfNode* n) {
    value::Value cond = eval_cond(ip, n.cond);
    if(cond.kind == (u16)value::ValueKind::Error) { return cond; }
    if(cond.data.b) { return eval(ip, n.then_block); }
    if(n.else_block != null) { return eval(ip, n.else_block); }
    return value::val_void();
}

fn value::Value eval_while(Interp* ip, ast::WhileNode* n) {
    u64 iterations = 0;
    while(true) {
        value::Value cond = eval_cond(ip, n.cond);
        if(cond.kind == (u16)value::ValueKind::Error) { return cond; }
        if(!cond.data.b) { break; }
        value::Value body = eval(ip, n.body);
        if(body.kind == (u16)value::ValueKind::Error) { return body; }
        if(ip.returning) { break; }
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
        if(iv.kind == (u16)value::ValueKind::Error) { result = iv; }
    }
    if(result.kind != (u16)value::ValueKind::Error) {
        u64 iterations = 0;
        while(true) {
            if(n.cond != null) {
                value::Value c = eval_cond(ip, n.cond);
                if(c.kind == (u16)value::ValueKind::Error) { result = c; break; }
                if(!c.data.b) { break; }
            }
            value::Value b = eval(ip, n.body);
            if(b.kind == (u16)value::ValueKind::Error) { result = b; break; }
            if(ip.returning) { break; }
            if(n.post != null) {
                value::Value p = eval(ip, n.post);
                if(p.kind == (u16)value::ValueKind::Error) { result = p; break; }
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

fn value::Value eval_assignment(Interp* ip, ast::AssignmentNode* n) {
    if(n.lhs.h.kind != ast::AstKind::Ident) {
        u8[] msg = "comptime assignment target must be a local variable";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg);
        return value::val_error();
    }
    ast::IdentNode* target = (ast::IdentNode*)n.lhs;
    sema::Decl* d = (sema::Decl*)target.resolved;
    value::Value rhs = eval(ip, n.rhs);
    if(rhs.kind == (u16)value::ValueKind::Error) { return rhs; }
    value::Value* slot = null;
    if(d != null) { slot = env_lookup(ip.env, d); }
    if(slot == null) {
        u8[] msg = "comptime assignment target is not a comptime local";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg);
        return value::val_error();
    }
    value::Value newval = rhs;
    if(n.op != token::TokenKind::Eq) {
        value::Value combined = op::binop_eval(compound_base(n.op), *slot, rhs);
        if(combined.kind == (u16)value::ValueKind::Error) { return combined; }
        newval = combined;
    }
    *slot = newval;
    return value::val_void();
}

fn value::Value eval_binary(Interp* ip, ast::BinaryOpNode* n) {
    value::Value l = eval(ip, n.lhs);
    if(l.kind == (u16)value::ValueKind::Error) { return l; }
    value::Value r = eval(ip, n.rhs);
    if(r.kind == (u16)value::ValueKind::Error) { return r; }
    return op::binop_eval(n.op, l, r);
}

fn value::Value eval_unary(Interp* ip, ast::UnaryOpNode* n) {
    value::Value v = eval(ip, n.operand);
    if(v.kind == (u16)value::ValueKind::Error) { return v; }
    return op::unaryop_eval(n.op, v);
}

fn value::Value eval_sizeof(Interp* ip, ast::SizeofNode* n) {
    types::Type* t = null;
    if(n.arg != null) { t = (types::Type*)n.arg.h.ty; }
    if(t == null) {
        u8[] msg = "sizeof operand type is unresolved";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg);
        return value::val_error();
    }
    return value::val_int((i64)types::size_of(&ip.m.diag, t), types::prim_u64());
}

fn value::Value eval_alignof(Interp* ip, ast::AlignofNode* n) {
    types::Type* t = null;
    if(n.arg != null) { t = (types::Type*)n.arg.h.ty; }
    if(t == null) {
        u8[] msg = "alignof operand type is unresolved";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg);
        return value::val_error();
    }
    return value::val_int((i64)types::align_of(&ip.m.diag, t), types::prim_u64());
}

fn value::Value eval_typeof(Interp* ip, ast::TypeofNode* n) {
    types::Type* t = null;
    if(n.expr != null) { t = (types::Type*)n.expr.h.ty; }
    if(t == null) {
        u8[] msg = "typeof operand type is unresolved";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg);
        return value::val_error();
    }
    return value::val_type(t);
}

fn value::Value eval_string_lit(Interp* ip, ast::StringLitNode* n) {
    u8[] bytes;
    bytes.ptr = &ip.m.literal_pool[n.pool_off];
    bytes.len = (u64)n.pool_len;
    return value::val_bytes(bytes, (types::Type*)n.h.ty);
}

fn void diag_unsupported(Interp* ip, u32 pos) {
    u8[] msg = "not supported at comptime";
    diag::report(&ip.m.diag, ip.m.arena, pos, msg);
}
