import value;
import ast;
import module;
import arena;
import types;
import diag;
import sema;
import op;
import token;
import symbol;
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
    case ast::AstKind::ReturnStmt:    { return eval_return(ip, (ast::ReturnNode*)e); }
    case ast::AstKind::AssignmentStmt: { return eval_assignment(ip, (ast::AssignmentNode*)e); }
    case ast::AstKind::Sizeof:    { return eval_sizeof(ip, (ast::SizeofNode*)e); }
    case ast::AstKind::Alignof:   { return eval_alignof(ip, (ast::AlignofNode*)e); }
    case ast::AstKind::Typeof:    { return eval_typeof(ip, (ast::TypeofNode*)e); }
    case ast::AstKind::PrimitiveType:
    case ast::AstKind::NamedType:
    case ast::AstKind::PointerType:
    case ast::AstKind::ArrayType:
    case ast::AstKind::SliceType:
    case ast::AstKind::FnPtrType: { return eval_type_expr(ip, e); }
    case ast::AstKind::ComprunStmt: { return eval_comprun(ip, (ast::CompRunNode*)e); }
    case ast::AstKind::ComperrorStmt:   { return eval_comperror(ip, (ast::CompErrorNode*)e); }
    case ast::AstKind::CompwarningStmt: { return eval_compwarning(ip, (ast::CompWarningNode*)e); }
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
    bool saved_returning = ip.returning;
    value::Value saved_return_value = ip.return_value;
    ip.returning = false;
    value::Value body_result = eval(ip, func.body);
    value::Value result = value::val_void();
    if(body_result.kind == (u16)value::ValueKind::Error) { result = body_result; } else if(ip.returning) { result = ip.return_value; }
    ip.returning = saved_returning;
    ip.return_value = saved_return_value;
    env_pop(ip.env);
    ip.env = saved;
    ip.depth -= 1;
    return result;
}

fn value::Value eval_call(Interp* ip, ast::CallNode* n) {
    sema::Decl* d = resolved_decl(n.callee);
    if(d == null || d.kind != (u16)sema::DeclKind::Node || d.data.node == null) {
        u8[] msg = "cannot resolve comptime call target";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg);
        return value::val_error();
    }
    ast::AstNode* fnode = d.data.node;
    if(fnode.h.kind == ast::AstKind::ExternFnDecl) {
        u8[] msg = "cannot call an extern function at comptime";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg);
        return value::val_error();
    }
    if(fnode.h.kind != ast::AstKind::FnDecl) {
        u8[] msg = "comptime call target is not a function";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg);
        return value::val_error();
    }
    ast::FnDeclNode* func = (ast::FnDeclNode*)fnode;
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
            if(args[arg_index].kind == (u16)value::ValueKind::Error) { return args[arg_index]; }
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
    return invoke(ip, func, args, n.h.src_pos);
}

fn value::Value eval_comperror(Interp* ip, ast::CompErrorNode* n) {
    value::Value msg = eval(ip, n.msg_expr);
    if(msg.kind == (u16)value::ValueKind::Error) { return msg; }
    if(msg.kind != (u16)value::ValueKind::Bytes) {
        u8[] bad = "comperror message must be a string";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, bad);
        return value::val_error();
    }
    diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, msg.data.bytes);
    return value::val_error();
}

fn value::Value eval_compwarning(Interp* ip, ast::CompWarningNode* n) {
    value::Value msg = eval(ip, n.msg_expr);
    if(msg.kind == (u16)value::ValueKind::Error) { return msg; }
    if(msg.kind != (u16)value::ValueKind::Bytes) {
        u8[] bad = "compwarning message must be a string";
        diag::report(&ip.m.diag, ip.m.arena, n.h.src_pos, bad);
        return value::val_error();
    }
    diag::report_warning(&ip.m.diag, ip.m.arena, n.h.src_pos, msg.data.bytes);
    return value::val_void();
}

fn value::Value eval_comprun(Interp* ip, ast::CompRunNode* n) {
    Env* saved = ip.env;
    ip.env = env_push(saved, ip.m.arena, 16);
    bool saved_returning = ip.returning;
    value::Value saved_return_value = ip.return_value;
    eval(ip, n.body);
    ip.returning = saved_returning;             // a comprun is an execution boundary; a return inside it doesn't propagate out
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
    return value::val_type((types::Type*)e.h.ty);
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

fn sema::Decl* resolved_decl(ast::AstNode* n) {
    if(n == null) { return null; }
    if(n.h.kind == ast::AstKind::Ident) { return (sema::Decl*)((ast::IdentNode*)n).resolved; }
    if(n.h.kind == ast::AstKind::NamespaceAccess) { return (sema::Decl*)((ast::NamespaceAccessNode*)n).resolved; }
    return null;
}

fn bool decl_is_mutable_global(sema::Decl* d) {
    if(d == null || d.kind != (u16)sema::DeclKind::Node || d.data.node == null) { return false; }
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
        if(callee_d != null && callee_d.kind == (u16)sema::DeclKind::Node && callee_d.data.node != null) {
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
    return value::val_bytes(bytes, (types::Type*)n.h.ty);
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
    u32 kind = (u32)v.kind;
    u64 h = hash_combine(FNV_BASIS, (u64)kind);
    if(kind == (u32)value::ValueKind::Int || kind == (u32)value::ValueKind::Char) { return hash_combine(h, (u64)v.data.i); }
    if(kind == (u32)value::ValueKind::Float) { return hash_combine(h, float_bits(v.data.f)); }
    if(kind == (u32)value::ValueKind::Bool) {
        u64 b = 0;
        if(v.data.b) { b = 1; }
        return hash_combine(h, b);
    }
    if(kind == (u32)value::ValueKind::Bytes) {
        for(u64 byte_index = 0; byte_index < v.data.bytes.len; byte_index += 1) { h = hash_combine(h, (u64)v.data.bytes[byte_index]); }
        return h;
    }
    if(kind == (u32)value::ValueKind::Type) { return hash_combine(h, (u64)v.data.type_ref); }
    if(kind == (u32)value::ValueKind::FnRef) { return hash_combine(h, (u64)v.data.fn_ref); }
    if(kind == (u32)value::ValueKind::Struct || kind == (u32)value::ValueKind::Array) {
        for(u64 elem_index = 0; elem_index < v.data.elems.len; elem_index += 1) { h = hash_combine(h, hash_value(v.data.elems[elem_index])); }
        return h;
    }
    return h;
}

fn bool value_equal(value::Value a, value::Value b) {
    if(a.kind != b.kind) { return false; }
    u32 kind = (u32)a.kind;
    if(kind == (u32)value::ValueKind::Int || kind == (u32)value::ValueKind::Char) { return a.data.i == b.data.i; }
    if(kind == (u32)value::ValueKind::Float) { return a.data.f == b.data.f; }
    if(kind == (u32)value::ValueKind::Bool) { return a.data.b == b.data.b; }
    if(kind == (u32)value::ValueKind::Bytes) {
        if(a.data.bytes.len != b.data.bytes.len) { return false; }
        for(u64 byte_index = 0; byte_index < a.data.bytes.len; byte_index += 1) { if(a.data.bytes[byte_index] != b.data.bytes[byte_index]) { return false; } }
        return true;
    }
    if(kind == (u32)value::ValueKind::Type) { return a.data.type_ref == b.data.type_ref; }
    if(kind == (u32)value::ValueKind::FnRef) { return a.data.fn_ref == b.data.fn_ref; }
    if(kind == (u32)value::ValueKind::Struct || kind == (u32)value::ValueKind::Array) {
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
    if(m.instantiated_fns.len == m.instantiated_fns_cap) {
        u64 new_cap = 4;
        if(m.instantiated_fns_cap > 0) { new_cap = m.instantiated_fns_cap * 2; }
        m.instantiated_fns.ptr = arena::realloc_grow(m.arena, (void*)m.instantiated_fns.ptr, m.instantiated_fns.len * sizeof(ast::FnDeclNode*), new_cap * sizeof(ast::FnDeclNode*));
        m.instantiated_fns_cap = new_cap;
    }
    m.instantiated_fns[m.instantiated_fns.len] = clone;
    m.instantiated_fns.len += 1;
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
    substitute_type_params(ip.m.arena, clone, cargs);
    sema::sema_check_clone(ip.m, ip.m, clone);
    mono_cache_insert(cache, ip.m.arena, key, clone);
    instantiated_fns_push(ip.m, clone);
    return clone;
}

// A value-param ident is rewritten in place to an IntLit (fits an IdentNode) so eval_const_u64 reads N in T[N].
struct SubstCtx {
    symbol::Symbol*[] tnames;
    types::Type*[]    ttys;
    symbol::Symbol*[] vnames;
    u64[]             vvals;
    types::Type*[]    vtys;
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
            if(cargs[carg_index].kind == (u16)value::ValueKind::Type) { n_type += 1; }
            else if(cargs[carg_index].kind == (u16)value::ValueKind::Int) { n_val += 1; }
            carg_index += 1;
        }
    }
    if(n_type == 0 && n_val == 0) { return; }
    SubstCtx c;
    sys::memset(&c, 0, sizeof(SubstCtx));
    c.tnames.ptr = arena::alloc(a, n_type * sizeof(symbol::Symbol*));
    c.ttys.ptr = arena::alloc(a, n_type * sizeof(types::Type*));
    c.vnames.ptr = arena::alloc(a, n_val * sizeof(symbol::Symbol*));
    c.vvals.ptr = arena::alloc(a, n_val * sizeof(u64));
    c.vtys.ptr = arena::alloc(a, n_val * sizeof(types::Type*));
    carg_index = 0;
    for(u64 i = 0; i < clone.params.len; i += 1) {
        if(clone.params[i].is_comptime) {
            if(cargs[carg_index].kind == (u16)value::ValueKind::Type) {
                c.tnames[c.tnames.len] = clone.params[i].name;
                c.tnames.len += 1;
                c.ttys[c.ttys.len] = cargs[carg_index].data.type_ref;
                c.ttys.len += 1;
            } else if(cargs[carg_index].kind == (u16)value::ValueKind::Int) {
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

// GENERIC CALL RESOLUTION (sema seam): infer comptime args by unifying runtime param patterns
// against the concrete arg types, then monomorphize.

fn bool unify_type(symbol::Symbol*[] names, value::Value[] binds, ast::AstNode* pattern, types::Type* concrete) {
    if(pattern == null || concrete == null) { return false; }
    switch(pattern.h.kind) {
    case ast::AstKind::NamedType: {
        ast::TypeNamedNode* tn = (ast::TypeNamedNode*)pattern;
        if(tn.namespace == null) {
            for(u64 k = 0; k < names.len; k += 1) {
                if(tn.name == names[k]) {
                    if(binds[k].kind == (u16)value::ValueKind::Void) { binds[k] = value::val_type(concrete); return true; }
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
    else { return true; }
    }
    return true;
}

export fn ast::FnDeclNode* resolve_generic_call(module::Module* m, ast::FnDeclNode* callee, types::Type*[] arg_types) {
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
        if(binds[k].kind == (u16)value::ValueKind::Void) { return null; }
    }
    Interp ip = new_interp(m);
    return monomorphize(&ip, callee, binds);
}

export fn void install_hooks() {
    sema::resolve_generic_call_hook = &resolve_generic_call;
}
