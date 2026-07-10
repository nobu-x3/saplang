import value;
import ast;
import module;
import arena;
import types;
import diag;
import sema;
import op;
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
    i32             max_depth;
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
