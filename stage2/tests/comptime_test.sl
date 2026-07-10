import testing;
import comptime;
import value;
import ast;
import module;
import types;
import arena;
import sema;
import token;
import sys;

fn module::Module* mk_module(arena::Arena* a) {
    module::Module* m = (module::Module*)arena::alloc(a, sizeof(module::Module));
    sys::memset(m, 0, sizeof(module::Module));
    m.arena = a;
    return m;
}

fn ast::AstNode* mk_int(arena::Arena* a, u64 v, types::Type* ty) {
    ast::IntLitNode* n = (ast::IntLitNode*)arena::alloc(a, sizeof(ast::IntLitNode));
    sys::memset(n, 0, sizeof(ast::IntLitNode));
    n.h.kind = ast::AstKind::IntLit;
    n.h.ty = (void*)ty;
    n.value = v;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_float(arena::Arena* a, f64 v, types::Type* ty) {
    ast::FloatLitNode* n = (ast::FloatLitNode*)arena::alloc(a, sizeof(ast::FloatLitNode));
    sys::memset(n, 0, sizeof(ast::FloatLitNode));
    n.h.kind = ast::AstKind::FloatLit;
    n.h.ty = (void*)ty;
    n.value = v;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_bool(arena::Arena* a, bool v) {
    ast::BoolLitNode* n = (ast::BoolLitNode*)arena::alloc(a, sizeof(ast::BoolLitNode));
    sys::memset(n, 0, sizeof(ast::BoolLitNode));
    n.h.kind = ast::AstKind::BoolLit;
    n.value = v;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_char(arena::Arena* a, u8 v, types::Type* ty) {
    ast::CharLitNode* n = (ast::CharLitNode*)arena::alloc(a, sizeof(ast::CharLitNode));
    sys::memset(n, 0, sizeof(ast::CharLitNode));
    n.h.kind = ast::AstKind::CharLit;
    n.h.ty = (void*)ty;
    n.value = v;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_null(arena::Arena* a, types::Type* ty) {
    ast::NullLitNode* n = (ast::NullLitNode*)arena::alloc(a, sizeof(ast::NullLitNode));
    sys::memset(n, 0, sizeof(ast::NullLitNode));
    n.h.kind = ast::AstKind::NullLit;
    n.h.ty = (void*)ty;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_string(arena::Arena* a, u32 off, u32 len) {
    ast::StringLitNode* n = (ast::StringLitNode*)arena::alloc(a, sizeof(ast::StringLitNode));
    sys::memset(n, 0, sizeof(ast::StringLitNode));
    n.h.kind = ast::AstKind::StringLit;
    n.pool_off = off;
    n.pool_len = len;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_binary(arena::Arena* a, token::TokenKind op, ast::AstNode* lhs, ast::AstNode* rhs, types::Type* ty) {
    ast::BinaryOpNode* n = (ast::BinaryOpNode*)arena::alloc(a, sizeof(ast::BinaryOpNode));
    sys::memset(n, 0, sizeof(ast::BinaryOpNode));
    n.h.kind = ast::AstKind::BinaryOp;
    n.h.ty = (void*)ty;
    n.op = op;
    n.lhs = lhs;
    n.rhs = rhs;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_unary(arena::Arena* a, token::TokenKind op, ast::AstNode* operand, types::Type* ty) {
    ast::UnaryOpNode* n = (ast::UnaryOpNode*)arena::alloc(a, sizeof(ast::UnaryOpNode));
    sys::memset(n, 0, sizeof(ast::UnaryOpNode));
    n.h.kind = ast::AstKind::UnaryOp;
    n.h.ty = (void*)ty;
    n.op = op;
    n.operand = operand;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_ident(arena::Arena* a) {
    ast::IdentNode* n = (ast::IdentNode*)arena::alloc(a, sizeof(ast::IdentNode));
    sys::memset(n, 0, sizeof(ast::IdentNode));
    n.h.kind = ast::AstKind::Ident;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_var_decl(arena::Arena* a, sema::Decl* d, ast::AstNode* init) {
    ast::VarDeclNode* n = (ast::VarDeclNode*)arena::alloc(a, sizeof(ast::VarDeclNode));
    sys::memset(n, 0, sizeof(ast::VarDeclNode));
    n.h.kind = ast::AstKind::VarDecl;
    n.decl = (void*)d;
    n.init = init;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_ident_resolved(arena::Arena* a, sema::Decl* d, types::Type* ty) {
    ast::IdentNode* n = (ast::IdentNode*)arena::alloc(a, sizeof(ast::IdentNode));
    sys::memset(n, 0, sizeof(ast::IdentNode));
    n.h.kind = ast::AstKind::Ident;
    n.h.ty = (void*)ty;
    n.resolved = (void*)d;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_block(arena::Arena* a, ast::AstNode** stmts, u64 count) {
    ast::BlockNode* n = (ast::BlockNode*)arena::alloc(a, sizeof(ast::BlockNode));
    sys::memset(n, 0, sizeof(ast::BlockNode));
    n.h.kind = ast::AstKind::BlockStmt;
    n.stmts = {stmts, count};
    return (ast::AstNode*)n;
}

fn sema::Decl* mk_decl(arena::Arena* a) {
    return (sema::Decl*)arena::alloc(a, sizeof(sema::Decl));
}

fn sema::Decl* mk_global_var(arena::Arena* a, i64 value, bool is_const) {
    ast::VarDeclNode* vd = (ast::VarDeclNode*)arena::alloc(a, sizeof(ast::VarDeclNode));
    sys::memset(vd, 0, sizeof(ast::VarDeclNode));
    vd.h.kind = ast::AstKind::VarDecl;
    vd.is_const = is_const;
    vd.init = mk_int(a, (u64)value, types::prim_i32());
    sema::Decl* d = mk_decl(a);
    d.kind = (u16)sema::DeclKind::Node;
    d.data.node = (ast::AstNode*)vd;
    return d;
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

fn ast::AstNode* mk_assign(arena::Arena* a, token::TokenKind op, ast::AstNode* lhs, ast::AstNode* rhs) {
    ast::AssignmentNode* n = (ast::AssignmentNode*)arena::alloc(a, sizeof(ast::AssignmentNode));
    sys::memset(n, 0, sizeof(ast::AssignmentNode));
    n.h.kind = ast::AstKind::AssignmentStmt;
    n.op = op;
    n.lhs = lhs;
    n.rhs = rhs;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_type_arg(arena::Arena* a, types::Type* ty) {
    ast::TypePrimitiveNode* n = (ast::TypePrimitiveNode*)arena::alloc(a, sizeof(ast::TypePrimitiveNode));
    sys::memset(n, 0, sizeof(ast::TypePrimitiveNode));
    n.h.kind = ast::AstKind::PrimitiveType;
    n.h.ty = (void*)ty;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_sizeof(arena::Arena* a, types::Type* ty) {
    ast::SizeofNode* n = (ast::SizeofNode*)arena::alloc(a, sizeof(ast::SizeofNode));
    sys::memset(n, 0, sizeof(ast::SizeofNode));
    n.h.kind = ast::AstKind::Sizeof;
    n.arg = mk_type_arg(a, ty);
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_alignof(arena::Arena* a, types::Type* ty) {
    ast::AlignofNode* n = (ast::AlignofNode*)arena::alloc(a, sizeof(ast::AlignofNode));
    sys::memset(n, 0, sizeof(ast::AlignofNode));
    n.h.kind = ast::AstKind::Alignof;
    n.arg = mk_type_arg(a, ty);
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_typeof(arena::Arena* a, types::Type* ty) {
    ast::TypeofNode* n = (ast::TypeofNode*)arena::alloc(a, sizeof(ast::TypeofNode));
    sys::memset(n, 0, sizeof(ast::TypeofNode));
    n.h.kind = ast::AstKind::Typeof;
    n.expr = mk_type_arg(a, ty);
    return (ast::AstNode*)n;
}

fn i64 sz(arena::Arena* a, comptime::Interp* ip, types::Type* ty) {
    value::Value v = comptime::eval(ip, mk_sizeof(a, ty));
    return v.data.i;
}

fn i64 al(arena::Arena* a, comptime::Interp* ip, types::Type* ty) {
    value::Value v = comptime::eval(ip, mk_alignof(a, ty));
    return v.data.i;
}

fn i32 env_bind_lookup(arena::Arena* a, u8[] m) {
    sema::Decl* decls = (sema::Decl*)arena::alloc(a, 50 * sizeof(sema::Decl));
    comptime::Env* env = comptime::env_push(null, a, 4);
    for(u64 i = 0; i < 50; i += 1) {
        comptime::env_bind(env, a, &decls[i], value::val_int((i64)i, types::prim_i32()));
    }
    for(u64 i = 0; i < 50; i += 1) {
        value::Value* v = comptime::env_lookup(env, &decls[i]);
        if(v == null) { return -1; }
        if(!testing::expect_eq((u64)v.data.i, i, m)) { return -2; }
    }
    sema::Decl* missing = (sema::Decl*)arena::alloc(a, sizeof(sema::Decl));
    if(comptime::env_lookup(env, missing) != null) { return -3; }
    return 0;
}

fn i32 env_parent_chain(arena::Arena* a, u8[] m) {
    sema::Decl* d1 = (sema::Decl*)arena::alloc(a, sizeof(sema::Decl));
    sema::Decl* d2 = (sema::Decl*)arena::alloc(a, sizeof(sema::Decl));
    comptime::Env* parent = comptime::env_push(null, a, 4);
    comptime::env_bind(parent, a, d1, value::val_int(100, types::prim_i32()));
    comptime::Env* child = comptime::env_push(parent, a, 4);
    comptime::env_bind(child, a, d2, value::val_int(200, types::prim_i32()));
    value::Value* v1 = comptime::env_lookup(child, d1);
    if(v1 == null) { return -1; }
    if(!testing::expect_eq((u64)v1.data.i, (u64)100, m)) { return -2; }
    value::Value* v2 = comptime::env_lookup(child, d2);
    if(v2 == null) { return -3; }
    if(!testing::expect_eq((u64)v2.data.i, (u64)200, m)) { return -4; }
    if(comptime::env_lookup(parent, d2) != null) { return -5; }
    return 0;
}

fn i32 eval_literals(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    value::Value vi = comptime::eval(&ip, mk_int(a, 42, types::prim_i32()));
    if(!testing::expect_eq((u64)vi.kind, (u64)value::ValueKind::Int, m)) { return -1; }
    if(!testing::expect_eq((u64)vi.data.i, (u64)42, m)) { return -2; }
    if(!testing::expect_eq((void*)vi.ty, (void*)types::prim_i32(), m)) { return -3; }

    value::Value vf = comptime::eval(&ip, mk_float(a, 3.5, types::prim_f64()));
    if(!testing::expect_eq((u64)vf.kind, (u64)value::ValueKind::Float, m)) { return -4; }
    if(vf.data.f != 3.5) { return -5; }

    value::Value vb = comptime::eval(&ip, mk_bool(a, true));
    if(!testing::expect_eq((u64)vb.kind, (u64)value::ValueKind::Bool, m)) { return -6; }
    if(!vb.data.b) { return -7; }

    value::Value vc = comptime::eval(&ip, mk_char(a, 65, types::prim_u8()));
    if(!testing::expect_eq((u64)vc.kind, (u64)value::ValueKind::Int, m)) { return -8; }
    if(!testing::expect_eq((u64)vc.data.i, (u64)65, m)) { return -9; }

    value::Value vn = comptime::eval(&ip, mk_null(a, types::prim_i32()));
    if(!testing::expect_eq((u64)vn.kind, (u64)value::ValueKind::Null, m)) { return -10; }
    return 0;
}

fn i32 eval_string(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    mm.literal_pool = "hello";
    comptime::Interp ip = comptime::new_interp(mm);
    value::Value v = comptime::eval(&ip, mk_string(a, 0, 5));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Bytes, m)) { return -1; }
    if(!testing::expect_eq(v.data.bytes.len, (u64)5, m)) { return -2; }
    if(!testing::expect_substr(v.data.bytes, "hello", m)) { return -3; }
    return 0;
}

fn i32 eval_unsupported_errors(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    value::Value v = comptime::eval(&ip, mk_ident(a));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)1, m)) { return -2; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "not supported", m)) { return -3; }
    return 0;
}

fn i32 eval_haderror_short_circuits(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::AstNode* node = mk_int(a, 42, types::prim_i32());
    node.h.flags = ast::AstFlags::HadError;
    value::Value v = comptime::eval(&ip, node);
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)0, m)) { return -2; }
    return 0;
}

fn i32 eval_null_returns_error(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    value::Value v = comptime::eval(&ip, null);
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)0, m)) { return -2; }
    return 0;
}

fn i32 bin(arena::Arena* a, comptime::Interp* ip, token::TokenKind op, u64 l, u64 r) {
    ast::AstNode* node = mk_binary(a, op, mk_int(a, l, types::prim_i32()), mk_int(a, r, types::prim_i32()), types::prim_i32());
    value::Value v = comptime::eval(ip, node);
    return (i32)v.data.i;
}

fn i32 eval_binary_arithmetic(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    if(!testing::expect_eq((u64)bin(a, &ip, token::TokenKind::Plus, 2, 3), (u64)5, m)) { return -1; }
    if(!testing::expect_eq((u64)bin(a, &ip, token::TokenKind::Minus, 10, 4), (u64)6, m)) { return -2; }
    if(!testing::expect_eq((u64)bin(a, &ip, token::TokenKind::Star, 6, 7), (u64)42, m)) { return -3; }
    if(!testing::expect_eq((u64)bin(a, &ip, token::TokenKind::Slash, 20, 5), (u64)4, m)) { return -4; }
    if(!testing::expect_eq((u64)bin(a, &ip, token::TokenKind::Percent, 17, 5), (u64)2, m)) { return -5; }
    return 0;
}

fn i32 eval_binary_bitwise_shift(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    if(!testing::expect_eq((u64)bin(a, &ip, token::TokenKind::Amp, 12, 10), (u64)8, m)) { return -1; }
    if(!testing::expect_eq((u64)bin(a, &ip, token::TokenKind::Pipe, 12, 3), (u64)15, m)) { return -2; }
    if(!testing::expect_eq((u64)bin(a, &ip, token::TokenKind::Caret, 5, 1), (u64)4, m)) { return -3; }
    if(!testing::expect_eq((u64)bin(a, &ip, token::TokenKind::LShift, 1, 4), (u64)16, m)) { return -4; }
    if(!testing::expect_eq((u64)bin(a, &ip, token::TokenKind::RShift, 256, 2), (u64)64, m)) { return -5; }
    return 0;
}

fn i32 eval_binary_comparison(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    value::Value lt = comptime::eval(&ip, mk_binary(a, token::TokenKind::LT, mk_int(a, 3, types::prim_i32()), mk_int(a, 5, types::prim_i32()), types::prim_i32()));
    if(!testing::expect_eq((u64)lt.kind, (u64)value::ValueKind::Bool, m)) { return -1; }
    if(!lt.data.b) { return -2; }
    value::Value eq = comptime::eval(&ip, mk_binary(a, token::TokenKind::EqEq, mk_int(a, 5, types::prim_i32()), mk_int(a, 5, types::prim_i32()), types::prim_i32()));
    if(!eq.data.b) { return -3; }
    value::Value ne = comptime::eval(&ip, mk_binary(a, token::TokenKind::BangEq, mk_int(a, 5, types::prim_i32()), mk_int(a, 5, types::prim_i32()), types::prim_i32()));
    if(ne.data.b) { return -4; }
    value::Value ge = comptime::eval(&ip, mk_binary(a, token::TokenKind::GTEQ, mk_int(a, 7, types::prim_i32()), mk_int(a, 7, types::prim_i32()), types::prim_i32()));
    if(!ge.data.b) { return -5; }
    return 0;
}

fn i32 eval_binary_float_and_logical(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    value::Value f = comptime::eval(&ip, mk_binary(a, token::TokenKind::Plus, mk_float(a, 1.5, types::prim_f64()), mk_float(a, 2.5, types::prim_f64()), types::prim_f64()));
    if(!testing::expect_eq((u64)f.kind, (u64)value::ValueKind::Float, m)) { return -1; }
    if(f.data.f != 4.0) { return -2; }
    value::Value andv = comptime::eval(&ip, mk_binary(a, token::TokenKind::AmpAmp, mk_bool(a, true), mk_bool(a, false), types::prim_bool()));
    if(andv.data.b) { return -3; }
    value::Value orv = comptime::eval(&ip, mk_binary(a, token::TokenKind::PipePipe, mk_bool(a, true), mk_bool(a, false), types::prim_bool()));
    if(!orv.data.b) { return -4; }
    return 0;
}

fn i32 eval_unary_ops(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    value::Value neg = comptime::eval(&ip, mk_unary(a, token::TokenKind::Minus, mk_int(a, 5, types::prim_i32()), types::prim_i32()));
    if(!testing::expect_eq((u64)neg.data.i, (u64)-5, m)) { return -1; }
    value::Value notv = comptime::eval(&ip, mk_unary(a, token::TokenKind::Bang, mk_bool(a, true), types::prim_bool()));
    if(notv.data.b) { return -2; }
    value::Value bnot = comptime::eval(&ip, mk_unary(a, token::TokenKind::Tilde, mk_int(a, 0, types::prim_i32()), types::prim_i32()));
    if(!testing::expect_eq((u64)bnot.data.i, (u64)-1, m)) { return -3; }
    return 0;
}

fn i32 eval_binary_nested(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::AstNode* inner = mk_binary(a, token::TokenKind::Plus, mk_int(a, 2, types::prim_i32()), mk_int(a, 3, types::prim_i32()), types::prim_i32());
    ast::AstNode* outer = mk_binary(a, token::TokenKind::Star, inner, mk_int(a, 4, types::prim_i32()), types::prim_i32());
    value::Value v = comptime::eval(&ip, outer);
    if(!testing::expect_eq((u64)v.data.i, (u64)20, m)) { return -1; }
    return 0;
}

fn i32 eval_binary_div_zero(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    value::Value v = comptime::eval(&ip, mk_binary(a, token::TokenKind::Slash, mk_int(a, 5, types::prim_i32()), mk_int(a, 0, types::prim_i32()), types::prim_i32()));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    return 0;
}

fn i32 eval_binary_error_propagates(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::AstNode* node = mk_binary(a, token::TokenKind::Plus, mk_ident(a), mk_int(a, 1, types::prim_i32()), types::prim_i32());
    value::Value v = comptime::eval(&ip, node);
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)1, m)) { return -2; }
    return 0;
}

fn i32 eval_unary_error_cases(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    value::Value notv = comptime::eval(&ip, mk_unary(a, token::TokenKind::Bang, mk_int(a, 5, types::prim_i32()), types::prim_i32()));
    if(!testing::expect_eq((u64)notv.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    value::Value neg = comptime::eval(&ip, mk_unary(a, token::TokenKind::Minus, mk_bool(a, true), types::prim_bool()));
    if(!testing::expect_eq((u64)neg.kind, (u64)value::ValueKind::Error, m)) { return -2; }
    return 0;
}

fn i32 eval_binary_rhs_error_propagates(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::AstNode* node = mk_binary(a, token::TokenKind::Plus, mk_int(a, 1, types::prim_i32()), mk_ident(a), types::prim_i32());
    value::Value v = comptime::eval(&ip, node);
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)1, m)) { return -2; }
    return 0;
}

fn i32 eval_binary_float_comparison(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    value::Value lt = comptime::eval(&ip, mk_binary(a, token::TokenKind::LT, mk_float(a, 1.5, types::prim_f64()), mk_float(a, 2.5, types::prim_f64()), types::prim_f64()));
    if(!testing::expect_eq((u64)lt.kind, (u64)value::ValueKind::Bool, m)) { return -1; }
    if(!lt.data.b) { return -2; }
    return 0;
}

fn i32 eval_width_wrap(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    value::Value w = comptime::eval(&ip, mk_binary(a, token::TokenKind::Plus, mk_int(a, 200, types::prim_u8()), mk_int(a, 100, types::prim_u8()), types::prim_u8()));
    if(!testing::expect_eq((u64)w.data.i, (u64)44, m)) { return -1; }
    value::Value o = comptime::eval(&ip, mk_binary(a, token::TokenKind::Plus, mk_int(a, 127, types::prim_i8()), mk_int(a, 1, types::prim_i8()), types::prim_i8()));
    if(!testing::expect_eq((u64)o.data.i, (u64)-128, m)) { return -2; }
    return 0;
}

fn i32 eval_unsigned_semantics(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    u64 high = (u64)1 << 63;
    value::Value c = comptime::eval(&ip, mk_binary(a, token::TokenKind::GT, mk_int(a, high, types::prim_u64()), mk_int(a, 1, types::prim_u64()), types::prim_u64()));
    if(!c.data.b) { return -1; }
    value::Value d = comptime::eval(&ip, mk_binary(a, token::TokenKind::Slash, mk_int(a, high, types::prim_u64()), mk_int(a, 2, types::prim_u64()), types::prim_u64()));
    if(!testing::expect_eq((u64)d.data.i, high / 2, m)) { return -2; }
    value::Value s = comptime::eval(&ip, mk_binary(a, token::TokenKind::RShift, mk_int(a, high, types::prim_u64()), mk_int(a, 4, types::prim_u64()), types::prim_u64()));
    if(!testing::expect_eq((u64)s.data.i, high >> 4, m)) { return -3; }
    return 0;
}

fn i32 eval_locals_and_ident(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* dx = mk_decl(a);
    sema::Decl* dy = mk_decl(a);
    comptime::eval(&ip, mk_var_decl(a, dx, mk_int(a, 40, types::prim_i32())));
    ast::AstNode* yinit = mk_binary(a, token::TokenKind::Plus, mk_ident_resolved(a, dx, types::prim_i32()), mk_int(a, 2, types::prim_i32()), types::prim_i32());
    comptime::eval(&ip, mk_var_decl(a, dy, yinit));
    value::Value* yv = comptime::env_lookup(ip.env, dy);
    if(yv == null) { return -1; }
    if(!testing::expect_eq((u64)yv.data.i, (u64)42, m)) { return -2; }
    value::Value xv = comptime::eval(&ip, mk_ident_resolved(a, dx, types::prim_i32()));
    if(!testing::expect_eq((u64)xv.data.i, (u64)40, m)) { return -3; }
    return 0;
}

fn i32 eval_var_decl_no_init(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* d = mk_decl(a);
    comptime::eval(&ip, mk_var_decl(a, d, null));
    value::Value* v = comptime::env_lookup(ip.env, d);
    if(v == null) { return -1; }
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Void, m)) { return -2; }
    return 0;
}

fn i32 eval_block_scoping(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* dz = mk_decl(a);
    ast::AstNode*[1] stmts;
    stmts[0] = mk_var_decl(a, dz, mk_int(a, 5, types::prim_i32()));
    value::Value r = comptime::eval(&ip, mk_block(a, &stmts[0], 1));
    if(!testing::expect_eq((u64)r.kind, (u64)value::ValueKind::Void, m)) { return -1; }
    if(comptime::env_lookup(ip.env, dz) != null) { return -2; }
    return 0;
}

fn i32 eval_ident_unbound_errors(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* d = mk_decl(a);
    value::Value v = comptime::eval(&ip, mk_ident_resolved(a, d, types::prim_i32()));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)1, m)) { return -2; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "not a comptime value", m)) { return -3; }
    return 0;
}

fn i32 eval_block_error_propagates(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::AstNode*[1] stmts;
    stmts[0] = mk_ident(a);
    value::Value r = comptime::eval(&ip, mk_block(a, &stmts[0], 1));
    if(!testing::expect_eq((u64)r.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    return 0;
}

fn i32 eval_global_const_ident(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* nconst = mk_global_var(a, 8, true);
    value::Value v = comptime::eval(&ip, mk_ident_resolved(a, nconst, types::prim_i32()));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Int, m)) { return -1; }
    if(!testing::expect_eq((u64)v.data.i, (u64)8, m)) { return -2; }
    return 0;
}

fn i32 eval_mutable_global_not_comptime(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* g = mk_global_var(a, 5, false);
    value::Value v = comptime::eval(&ip, mk_ident_resolved(a, g, types::prim_i32()));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "not a comptime value", m)) { return -2; }
    return 0;
}

fn i32 eval_block_outer_local(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* dx = mk_decl(a);
    comptime::eval(&ip, mk_var_decl(a, dx, mk_int(a, 10, types::prim_i32())));
    sema::Decl* dy = mk_decl(a);
    ast::AstNode* yinit = mk_binary(a, token::TokenKind::Plus, mk_ident_resolved(a, dx, types::prim_i32()), mk_int(a, 3, types::prim_i32()), types::prim_i32());
    ast::AstNode*[1] stmts;
    stmts[0] = mk_var_decl(a, dy, yinit);
    value::Value r = comptime::eval(&ip, mk_block(a, &stmts[0], 1));
    if(!testing::expect_eq((u64)r.kind, (u64)value::ValueKind::Void, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)0, m)) { return -2; }
    return 0;
}

fn i32 eval_if_branches(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* dx = mk_decl(a);
    comptime::eval(&ip, mk_var_decl(a, dx, mk_int(a, 0, types::prim_i32())));
    ast::AstNode*[1] then_s;
    then_s[0] = mk_assign(a, token::TokenKind::Eq, mk_ident_resolved(a, dx, types::prim_i32()), mk_int(a, 1, types::prim_i32()));
    ast::AstNode*[1] else_s;
    else_s[0] = mk_assign(a, token::TokenKind::Eq, mk_ident_resolved(a, dx, types::prim_i32()), mk_int(a, 2, types::prim_i32()));
    comptime::eval(&ip, mk_if(a, mk_bool(a, true), mk_block(a, &then_s[0], 1), mk_block(a, &else_s[0], 1)));
    value::Value* xv = comptime::env_lookup(ip.env, dx);
    if(!testing::expect_eq((u64)xv.data.i, (u64)1, m)) { return -1; }
    comptime::eval(&ip, mk_if(a, mk_bool(a, false), mk_block(a, &then_s[0], 1), mk_block(a, &else_s[0], 1)));
    if(!testing::expect_eq((u64)xv.data.i, (u64)2, m)) { return -2; }
    return 0;
}

fn i32 eval_return_sets_returning(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* dx = mk_decl(a);
    comptime::eval(&ip, mk_var_decl(a, dx, mk_int(a, 0, types::prim_i32())));
    ast::AstNode*[2] stmts;
    stmts[0] = mk_return(a, mk_int(a, 5, types::prim_i32()));
    stmts[1] = mk_assign(a, token::TokenKind::Eq, mk_ident_resolved(a, dx, types::prim_i32()), mk_int(a, 99, types::prim_i32()));
    comptime::eval(&ip, mk_block(a, &stmts[0], 2));
    if(!ip.returning) { return -1; }
    if(!testing::expect_eq((u64)ip.return_value.data.i, (u64)5, m)) { return -2; }
    value::Value* xv = comptime::env_lookup(ip.env, dx);
    if(!testing::expect_eq((u64)xv.data.i, (u64)0, m)) { return -3; }
    return 0;
}

fn i32 eval_while_counts(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* di = mk_decl(a);
    comptime::eval(&ip, mk_var_decl(a, di, mk_int(a, 0, types::prim_i32())));
    ast::AstNode* cond = mk_binary(a, token::TokenKind::LT, mk_ident_resolved(a, di, types::prim_i32()), mk_int(a, 3, types::prim_i32()), types::prim_i32());
    ast::AstNode*[1] body_s;
    body_s[0] = mk_assign(a, token::TokenKind::Eq, mk_ident_resolved(a, di, types::prim_i32()), mk_binary(a, token::TokenKind::Plus, mk_ident_resolved(a, di, types::prim_i32()), mk_int(a, 1, types::prim_i32()), types::prim_i32()));
    comptime::eval(&ip, mk_while(a, cond, mk_block(a, &body_s[0], 1)));
    value::Value* iv = comptime::env_lookup(ip.env, di);
    if(!testing::expect_eq((u64)iv.data.i, (u64)3, m)) { return -1; }
    return 0;
}

fn i32 eval_for_factorial(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* dacc = mk_decl(a);
    comptime::eval(&ip, mk_var_decl(a, dacc, mk_int(a, 1, types::prim_i64())));
    sema::Decl* di = mk_decl(a);
    ast::AstNode* init = mk_var_decl(a, di, mk_int(a, 1, types::prim_i64()));
    ast::AstNode* cond = mk_binary(a, token::TokenKind::LTEQ, mk_ident_resolved(a, di, types::prim_i64()), mk_int(a, 10, types::prim_i64()), types::prim_i64());
    ast::AstNode* post = mk_assign(a, token::TokenKind::Eq, mk_ident_resolved(a, di, types::prim_i64()), mk_binary(a, token::TokenKind::Plus, mk_ident_resolved(a, di, types::prim_i64()), mk_int(a, 1, types::prim_i64()), types::prim_i64()));
    ast::AstNode*[1] body_s;
    body_s[0] = mk_assign(a, token::TokenKind::Eq, mk_ident_resolved(a, dacc, types::prim_i64()), mk_binary(a, token::TokenKind::Star, mk_ident_resolved(a, dacc, types::prim_i64()), mk_ident_resolved(a, di, types::prim_i64()), types::prim_i64()));
    comptime::eval(&ip, mk_for(a, init, cond, post, mk_block(a, &body_s[0], 1)));
    value::Value* accv = comptime::env_lookup(ip.env, dacc);
    if(!testing::expect_eq((u64)accv.data.i, (u64)3628800, m)) { return -1; }
    return 0;
}

fn i32 eval_cond_int_truthy(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* dx = mk_decl(a);
    comptime::eval(&ip, mk_var_decl(a, dx, mk_int(a, 0, types::prim_i32())));
    ast::AstNode*[1] set1;
    set1[0] = mk_assign(a, token::TokenKind::Eq, mk_ident_resolved(a, dx, types::prim_i32()), mk_int(a, 1, types::prim_i32()));
    ast::AstNode*[1] set2;
    set2[0] = mk_assign(a, token::TokenKind::Eq, mk_ident_resolved(a, dx, types::prim_i32()), mk_int(a, 2, types::prim_i32()));
    comptime::eval(&ip, mk_if(a, mk_int(a, 5, types::prim_i32()), mk_block(a, &set1[0], 1), mk_block(a, &set2[0], 1)));
    value::Value* xv = comptime::env_lookup(ip.env, dx);
    if(!testing::expect_eq((u64)xv.data.i, (u64)1, m)) { return -1; }
    comptime::eval(&ip, mk_if(a, mk_int(a, 0, types::prim_i32()), mk_block(a, &set1[0], 1), mk_block(a, &set2[0], 1)));
    if(!testing::expect_eq((u64)xv.data.i, (u64)2, m)) { return -2; }
    return 0;
}

fn i32 eval_compound_assignment(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* dacc = mk_decl(a);
    comptime::eval(&ip, mk_var_decl(a, dacc, mk_int(a, 6, types::prim_i32())));
    comptime::eval(&ip, mk_assign(a, token::TokenKind::StarEq, mk_ident_resolved(a, dacc, types::prim_i32()), mk_int(a, 7, types::prim_i32())));
    value::Value* accv = comptime::env_lookup(ip.env, dacc);
    if(!testing::expect_eq((u64)accv.data.i, (u64)42, m)) { return -1; }
    comptime::eval(&ip, mk_assign(a, token::TokenKind::MinusEq, mk_ident_resolved(a, dacc, types::prim_i32()), mk_int(a, 2, types::prim_i32())));
    if(!testing::expect_eq((u64)accv.data.i, (u64)40, m)) { return -2; }
    return 0;
}

fn i32 eval_assign_errors(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* unbound = mk_decl(a);
    value::Value v1 = comptime::eval(&ip, mk_assign(a, token::TokenKind::Eq, mk_ident_resolved(a, unbound, types::prim_i32()), mk_int(a, 1, types::prim_i32())));
    if(!testing::expect_eq((u64)v1.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "not a comptime local", m)) { return -2; }
    value::Value v2 = comptime::eval(&ip, mk_assign(a, token::TokenKind::Eq, mk_int(a, 3, types::prim_i32()), mk_int(a, 1, types::prim_i32())));
    if(!testing::expect_eq((u64)v2.kind, (u64)value::ValueKind::Error, m)) { return -3; }
    if(!testing::expect_substr(mm.diag.entries[1].msg, "must be a local variable", m)) { return -4; }
    return 0;
}

fn i32 eval_iteration_limit(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ip.max_iterations = 5;
    sema::Decl* di = mk_decl(a);
    comptime::eval(&ip, mk_var_decl(a, di, mk_int(a, 0, types::prim_i32())));
    ast::AstNode* cond = mk_binary(a, token::TokenKind::LT, mk_ident_resolved(a, di, types::prim_i32()), mk_int(a, 100, types::prim_i32()), types::prim_i32());
    ast::AstNode*[1] body_s;
    body_s[0] = mk_assign(a, token::TokenKind::Eq, mk_ident_resolved(a, di, types::prim_i32()), mk_binary(a, token::TokenKind::Plus, mk_ident_resolved(a, di, types::prim_i32()), mk_int(a, 1, types::prim_i32()), types::prim_i32()));
    value::Value v = comptime::eval(&ip, mk_while(a, cond, mk_block(a, &body_s[0], 1)));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "iteration limit", m)) { return -2; }
    return 0;
}

fn i32 eval_sizeof_primitives(arena::Arena* a, u8[] m) {
    types::typer_init(a, 64);
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    if(!testing::expect_eq((u64)sz(a, &ip, types::prim_i32()), (u64)4, m)) { return -1; }
    if(!testing::expect_eq((u64)sz(a, &ip, types::prim_i64()), (u64)8, m)) { return -2; }
    if(!testing::expect_eq((u64)sz(a, &ip, types::prim_u8()), (u64)1, m)) { return -3; }
    if(!testing::expect_eq((u64)sz(a, &ip, types::prim_u16()), (u64)2, m)) { return -4; }
    value::Value v = comptime::eval(&ip, mk_sizeof(a, types::prim_i32()));
    if(!testing::expect_eq((void*)v.ty, (void*)types::prim_u64(), m)) { return -5; }
    return 0;
}

fn i32 eval_sizeof_pointer_slice(arena::Arena* a, u8[] m) {
    types::typer_init(a, 64);
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    types::Type* ptr = types::intern_pointer(types::prim_i32(), false);
    types::Type* slice = types::intern_slice(types::prim_i32());
    if(!testing::expect_eq((u64)sz(a, &ip, ptr), (u64)8, m)) { return -1; }
    if(!testing::expect_eq((u64)sz(a, &ip, slice), (u64)16, m)) { return -2; }
    return 0;
}

fn i32 eval_alignof_primitives(arena::Arena* a, u8[] m) {
    types::typer_init(a, 64);
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    if(!testing::expect_eq((u64)al(a, &ip, types::prim_i32()), (u64)4, m)) { return -1; }
    if(!testing::expect_eq((u64)al(a, &ip, types::prim_i64()), (u64)8, m)) { return -2; }
    if(!testing::expect_eq((u64)al(a, &ip, types::prim_u8()), (u64)1, m)) { return -3; }
    return 0;
}

fn i32 eval_typeof_expr(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    value::Value v = comptime::eval(&ip, mk_typeof(a, types::prim_i32()));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Type, m)) { return -1; }
    if(!testing::expect_eq((void*)v.data.type_ref, (void*)types::prim_i32(), m)) { return -2; }
    return 0;
}

fn i32 eval_sizeof_unresolved_errors(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    value::Value v = comptime::eval(&ip, mk_sizeof(a, null));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "unresolved", m)) { return -2; }
    return 0;
}

fn i32 eval_type_comparison(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    value::Value same = comptime::eval(&ip, mk_binary(a, token::TokenKind::EqEq, mk_typeof(a, types::prim_i32()), mk_typeof(a, types::prim_i32()), types::prim_bool()));
    if(!testing::expect_eq((u64)same.kind, (u64)value::ValueKind::Bool, m)) { return -1; }
    if(!same.data.b) { return -2; }
    value::Value diff = comptime::eval(&ip, mk_binary(a, token::TokenKind::EqEq, mk_typeof(a, types::prim_i32()), mk_typeof(a, types::prim_u32()), types::prim_bool()));
    if(diff.data.b) { return -3; }
    value::Value ne = comptime::eval(&ip, mk_binary(a, token::TokenKind::BangEq, mk_typeof(a, types::prim_i32()), mk_typeof(a, types::prim_u32()), types::prim_bool()));
    if(!ne.data.b) { return -4; }
    return 0;
}

fn i32 eval_sizeof_in_expression(arena::Arena* a, u8[] m) {
    types::typer_init(a, 64);
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::AstNode* expr = mk_binary(a, token::TokenKind::Plus, mk_sizeof(a, types::prim_i32()), mk_int(a, 4, types::prim_u64()), types::prim_u64());
    value::Value v = comptime::eval(&ip, expr);
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Int, m)) { return -1; }
    if(!testing::expect_eq((u64)v.data.i, (u64)8, m)) { return -2; }
    return 0;
}

fn i32 main() {
    testing::init();
    u8[] suite = "Comptime Tests";
    testing::add(suite, "env_bind_lookup",            &env_bind_lookup);
    testing::add(suite, "env_parent_chain",           &env_parent_chain);
    testing::add(suite, "eval_literals",              &eval_literals);
    testing::add(suite, "eval_string",                &eval_string);
    testing::add(suite, "eval_unsupported_errors",    &eval_unsupported_errors);
    testing::add(suite, "eval_haderror_short_circuits", &eval_haderror_short_circuits);
    testing::add(suite, "eval_null_returns_error",      &eval_null_returns_error);
    testing::add(suite, "eval_binary_arithmetic",       &eval_binary_arithmetic);
    testing::add(suite, "eval_binary_bitwise_shift",    &eval_binary_bitwise_shift);
    testing::add(suite, "eval_binary_comparison",       &eval_binary_comparison);
    testing::add(suite, "eval_binary_float_and_logical", &eval_binary_float_and_logical);
    testing::add(suite, "eval_unary_ops",               &eval_unary_ops);
    testing::add(suite, "eval_binary_nested",           &eval_binary_nested);
    testing::add(suite, "eval_binary_div_zero",         &eval_binary_div_zero);
    testing::add(suite, "eval_binary_error_propagates", &eval_binary_error_propagates);
    testing::add(suite, "eval_unary_error_cases",       &eval_unary_error_cases);
    testing::add(suite, "eval_binary_rhs_error_propagates", &eval_binary_rhs_error_propagates);
    testing::add(suite, "eval_binary_float_comparison", &eval_binary_float_comparison);
    testing::add(suite, "eval_width_wrap",              &eval_width_wrap);
    testing::add(suite, "eval_unsigned_semantics",      &eval_unsigned_semantics);
    testing::add(suite, "eval_locals_and_ident",        &eval_locals_and_ident);
    testing::add(suite, "eval_var_decl_no_init",        &eval_var_decl_no_init);
    testing::add(suite, "eval_block_scoping",           &eval_block_scoping);
    testing::add(suite, "eval_ident_unbound_errors",    &eval_ident_unbound_errors);
    testing::add(suite, "eval_block_error_propagates",  &eval_block_error_propagates);
    testing::add(suite, "eval_global_const_ident",      &eval_global_const_ident);
    testing::add(suite, "eval_mutable_global_not_comptime", &eval_mutable_global_not_comptime);
    testing::add(suite, "eval_block_outer_local",       &eval_block_outer_local);
    testing::add(suite, "eval_if_branches",             &eval_if_branches);
    testing::add(suite, "eval_return_sets_returning",   &eval_return_sets_returning);
    testing::add(suite, "eval_while_counts",            &eval_while_counts);
    testing::add(suite, "eval_for_factorial",           &eval_for_factorial);
    testing::add(suite, "eval_cond_int_truthy",         &eval_cond_int_truthy);
    testing::add(suite, "eval_compound_assignment",     &eval_compound_assignment);
    testing::add(suite, "eval_assign_errors",           &eval_assign_errors);
    testing::add(suite, "eval_iteration_limit",         &eval_iteration_limit);
    testing::add(suite, "eval_sizeof_primitives",       &eval_sizeof_primitives);
    testing::add(suite, "eval_sizeof_pointer_slice",    &eval_sizeof_pointer_slice);
    testing::add(suite, "eval_alignof_primitives",      &eval_alignof_primitives);
    testing::add(suite, "eval_typeof_expr",             &eval_typeof_expr);
    testing::add(suite, "eval_sizeof_unresolved_errors", &eval_sizeof_unresolved_errors);
    testing::add(suite, "eval_type_comparison",         &eval_type_comparison);
    testing::add(suite, "eval_sizeof_in_expression",    &eval_sizeof_in_expression);
    return testing::run();
}
