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
