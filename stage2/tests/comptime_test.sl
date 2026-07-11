import testing;
import comptime;
import value;
import ast;
import module;
import types;
import arena;
import sema;
import symbol;
import interner;
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

fn ast::AstNode* mk_ident_named(arena::Arena* a, symbol::Symbol* name) {
    ast::IdentNode* n = (ast::IdentNode*)arena::alloc(a, sizeof(ast::IdentNode));
    sys::memset(n, 0, sizeof(ast::IdentNode));
    n.h.kind = ast::AstKind::Ident;
    n.name = name;
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

fn ast::AstNode* mk_named_type(arena::Arena* a, symbol::Symbol* name) {
    ast::TypeNamedNode* n = (ast::TypeNamedNode*)arena::alloc(a, sizeof(ast::TypeNamedNode));
    sys::memset(n, 0, sizeof(ast::TypeNamedNode));
    n.h.kind = ast::AstKind::NamedType;
    n.name = name;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_array_type(arena::Arena* a, ast::AstNode* element, ast::AstNode* size_expr) {
    ast::TypeArrayNode* n = (ast::TypeArrayNode*)arena::alloc(a, sizeof(ast::TypeArrayNode));
    sys::memset(n, 0, sizeof(ast::TypeArrayNode));
    n.h.kind = ast::AstKind::ArrayType;
    n.element = element;
    n.size_expr = size_expr;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_sizeof_of(arena::Arena* a, ast::AstNode* arg) {
    ast::SizeofNode* n = (ast::SizeofNode*)arena::alloc(a, sizeof(ast::SizeofNode));
    sys::memset(n, 0, sizeof(ast::SizeofNode));
    n.h.kind = ast::AstKind::Sizeof;
    n.arg = arg;
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

fn ast::AstNode* mk_comperror(arena::Arena* a, ast::AstNode* msg) {
    ast::CompErrorNode* n = (ast::CompErrorNode*)arena::alloc(a, sizeof(ast::CompErrorNode));
    sys::memset(n, 0, sizeof(ast::CompErrorNode));
    n.h.kind = ast::AstKind::ComperrorStmt;
    n.msg_expr = msg;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_compwarning(arena::Arena* a, ast::AstNode* msg) {
    ast::CompWarningNode* n = (ast::CompWarningNode*)arena::alloc(a, sizeof(ast::CompWarningNode));
    sys::memset(n, 0, sizeof(ast::CompWarningNode));
    n.h.kind = ast::AstKind::CompwarningStmt;
    n.msg_expr = msg;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_comprun(arena::Arena* a, ast::AstNode* body) {
    ast::CompRunNode* n = (ast::CompRunNode*)arena::alloc(a, sizeof(ast::CompRunNode));
    sys::memset(n, 0, sizeof(ast::CompRunNode));
    n.h.kind = ast::AstKind::ComprunStmt;
    n.body = body;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_defer(arena::Arena* a, ast::AstNode* body) {
    ast::DeferNode* n = (ast::DeferNode*)arena::alloc(a, sizeof(ast::DeferNode));
    sys::memset(n, 0, sizeof(ast::DeferNode));
    n.h.kind = ast::AstKind::DeferStmt;
    n.body = body;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_slice_range(arena::Arena* a, ast::AstNode* base, ast::AstNode* lo, ast::AstNode* hi) {
    ast::SliceRangeNode* n = (ast::SliceRangeNode*)arena::alloc(a, sizeof(ast::SliceRangeNode));
    sys::memset(n, 0, sizeof(ast::SliceRangeNode));
    n.h.kind = ast::AstKind::SliceRange;
    n.base = base;
    n.lo = lo;
    n.hi = hi;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_cast(arena::Arena* a, ast::AstNode* expr) {
    ast::CastNode* n = (ast::CastNode*)arena::alloc(a, sizeof(ast::CastNode));
    sys::memset(n, 0, sizeof(ast::CastNode));
    n.h.kind = ast::AstKind::Cast;
    n.expr = expr;
    return (ast::AstNode*)n;
}

fn ast::FnDeclNode* mk_fn_node(arena::Arena* a, ast::AstNode* body) {
    ast::FnDeclNode* n = (ast::FnDeclNode*)arena::alloc(a, sizeof(ast::FnDeclNode));
    sys::memset(n, 0, sizeof(ast::FnDeclNode));
    n.h.kind = ast::AstKind::FnDecl;
    n.body = body;
    return n;
}

fn ast::AstNode* mk_call(arena::Arena* a, ast::AstNode* callee) {
    ast::CallNode* n = (ast::CallNode*)arena::alloc(a, sizeof(ast::CallNode));
    sys::memset(n, 0, sizeof(ast::CallNode));
    n.h.kind = ast::AstKind::Call;
    n.callee = callee;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_call_args(arena::Arena* a, ast::AstNode* callee, ast::AstNode** args, u64 nargs) {
    ast::CallNode* n = (ast::CallNode*)arena::alloc(a, sizeof(ast::CallNode));
    sys::memset(n, 0, sizeof(ast::CallNode));
    n.h.kind = ast::AstKind::Call;
    n.callee = callee;
    n.args = {args, nargs};
    return (ast::AstNode*)n;
}

fn sema::Decl* mk_param_decl(arena::Arena* a) {
    sema::Decl* d = mk_decl(a);
    d.kind = (u16)sema::DeclKind::Param;
    return d;
}

fn sema::Decl* mk_fn_decl_for(arena::Arena* a, ast::FnDeclNode* func) {
    sema::Decl* d = mk_decl(a);
    d.kind = (u16)sema::DeclKind::Node;
    d.data.node = (ast::AstNode*)func;
    return d;
}

fn sema::Decl* mk_extern_decl(arena::Arena* a) {
    ast::ExternFnDeclNode* e = (ast::ExternFnDeclNode*)arena::alloc(a, sizeof(ast::ExternFnDeclNode));
    sys::memset(e, 0, sizeof(ast::ExternFnDeclNode));
    e.h.kind = ast::AstKind::ExternFnDecl;
    e.comptime_safe = ast::CompSafe::Unsafe;
    sema::Decl* d = mk_decl(a);
    d.kind = (u16)sema::DeclKind::Node;
    d.data.node = (ast::AstNode*)e;
    return d;
}

fn sema::Decl* mk_global_decl(arena::Arena* a, bool is_const) {
    ast::VarDeclNode* vd = (ast::VarDeclNode*)arena::alloc(a, sizeof(ast::VarDeclNode));
    sys::memset(vd, 0, sizeof(ast::VarDeclNode));
    vd.h.kind = ast::AstKind::VarDecl;
    vd.is_const = is_const;
    vd.qualified_name = (symbol::Symbol*)arena::alloc(a, 8);
    sema::Decl* d = mk_decl(a);
    d.kind = (u16)sema::DeclKind::Node;
    d.data.node = (ast::AstNode*)vd;
    return d;
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

fn i32 comptime_safe_pure_fn(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::AstNode* ret = mk_return(a, mk_binary(a, token::TokenKind::Plus, mk_int(a, 1, types::prim_i32()), mk_int(a, 2, types::prim_i32()), types::prim_i32()));
    ast::AstNode*[1] stmts;
    stmts[0] = ret;
    ast::FnDeclNode* func = mk_fn_node(a, mk_block(a, &stmts[0], 1));
    if(!comptime::ensure_comptime_safe(&ip, func)) { return -1; }
    if(func.comptime_safe != ast::CompSafe::Safe) { return -2; }
    return 0;
}

fn i32 comptime_safe_recursion(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::FnDeclNode* func = mk_fn_node(a, null);
    sema::Decl* df = mk_fn_decl_for(a, func);
    ast::AstNode*[1] stmts;
    stmts[0] = mk_call(a, mk_ident_resolved(a, df, null));
    func.body = mk_block(a, &stmts[0], 1);
    if(!comptime::ensure_comptime_safe(&ip, func)) { return -1; }
    if(func.comptime_safe != ast::CompSafe::Safe) { return -2; }
    return 0;
}

fn i32 comptime_safe_extern_unsafe(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* de = mk_extern_decl(a);
    ast::AstNode*[1] stmts;
    stmts[0] = mk_call(a, mk_ident_resolved(a, de, null));
    ast::FnDeclNode* func = mk_fn_node(a, mk_block(a, &stmts[0], 1));
    if(comptime::ensure_comptime_safe(&ip, func)) { return -1; }
    if(func.comptime_safe != ast::CompSafe::Unsafe) { return -2; }
    return 0;
}

fn i32 comptime_safe_global_read_unsafe(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* dg = mk_global_decl(a, false);
    ast::AstNode*[1] stmts;
    stmts[0] = mk_return(a, mk_ident_resolved(a, dg, types::prim_i32()));
    ast::FnDeclNode* func = mk_fn_node(a, mk_block(a, &stmts[0], 1));
    if(comptime::ensure_comptime_safe(&ip, func)) { return -1; }
    return 0;
}

fn i32 comptime_safe_const_global_safe(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* dg = mk_global_decl(a, true);
    ast::AstNode*[1] stmts;
    stmts[0] = mk_return(a, mk_ident_resolved(a, dg, types::prim_i32()));
    ast::FnDeclNode* func = mk_fn_node(a, mk_block(a, &stmts[0], 1));
    if(!comptime::ensure_comptime_safe(&ip, func)) { return -1; }
    return 0;
}

fn i32 comptime_safe_transitive(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::AstNode*[1] b_stmts;
    b_stmts[0] = mk_return(a, mk_int(a, 1, types::prim_i32()));
    ast::FnDeclNode* fn_b = mk_fn_node(a, mk_block(a, &b_stmts[0], 1));
    sema::Decl* db = mk_fn_decl_for(a, fn_b);
    ast::AstNode*[1] a_stmts;
    a_stmts[0] = mk_call(a, mk_ident_resolved(a, db, null));
    ast::FnDeclNode* fn_a = mk_fn_node(a, mk_block(a, &a_stmts[0], 1));
    if(!comptime::ensure_comptime_safe(&ip, fn_a)) { return -1; }
    if(fn_b.comptime_safe != ast::CompSafe::Safe) { return -2; }
    return 0;
}

fn i32 comptime_safe_calling_unsafe_is_unsafe(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* de = mk_extern_decl(a);
    ast::AstNode*[1] b_stmts;
    b_stmts[0] = mk_call(a, mk_ident_resolved(a, de, null));
    ast::FnDeclNode* fn_b = mk_fn_node(a, mk_block(a, &b_stmts[0], 1));
    sema::Decl* db = mk_fn_decl_for(a, fn_b);
    ast::AstNode*[1] a_stmts;
    a_stmts[0] = mk_call(a, mk_ident_resolved(a, db, null));
    ast::FnDeclNode* fn_a = mk_fn_node(a, mk_block(a, &a_stmts[0], 1));
    if(comptime::ensure_comptime_safe(&ip, fn_a)) { return -1; }
    return 0;
}

fn i32 comptime_safe_extern_in_defer(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* de = mk_extern_decl(a);
    ast::AstNode*[1] defer_stmts;
    defer_stmts[0] = mk_call(a, mk_ident_resolved(a, de, null));
    ast::AstNode*[1] stmts;
    stmts[0] = mk_defer(a, mk_block(a, &defer_stmts[0], 1));
    ast::FnDeclNode* func = mk_fn_node(a, mk_block(a, &stmts[0], 1));
    if(comptime::ensure_comptime_safe(&ip, func)) { return -1; }
    return 0;
}

fn i32 comptime_safe_extern_in_cast(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* de = mk_extern_decl(a);
    ast::AstNode*[1] stmts;
    stmts[0] = mk_return(a, mk_cast(a, mk_call(a, mk_ident_resolved(a, de, null))));
    ast::FnDeclNode* func = mk_fn_node(a, mk_block(a, &stmts[0], 1));
    if(comptime::ensure_comptime_safe(&ip, func)) { return -1; }
    return 0;
}

fn i32 comptime_safe_extern_in_slice_range(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* de = mk_extern_decl(a);
    ast::AstNode* range = mk_slice_range(a, mk_int(a, 0, types::prim_i32()), mk_call(a, mk_ident_resolved(a, de, null)), mk_int(a, 1, types::prim_i32()));
    ast::AstNode*[1] stmts;
    stmts[0] = mk_return(a, range);
    ast::FnDeclNode* func = mk_fn_node(a, mk_block(a, &stmts[0], 1));
    if(comptime::ensure_comptime_safe(&ip, func)) { return -1; }
    return 0;
}

fn i32 eval_comprun_executes(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* dx = mk_decl(a);
    comptime::eval(&ip, mk_var_decl(a, dx, mk_int(a, 0, types::prim_i32())));
    ast::AstNode*[1] body_stmts;
    body_stmts[0] = mk_assign(a, token::TokenKind::Eq, mk_ident_resolved(a, dx, types::prim_i32()), mk_int(a, 42, types::prim_i32()));
    value::Value v = comptime::eval(&ip, mk_comprun(a, mk_block(a, &body_stmts[0], 1)));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Void, m)) { return -1; }
    value::Value* xv = comptime::env_lookup(ip.env, dx);
    if(xv == null) { return -2; }
    if(!testing::expect_eq((u64)xv.data.i, (u64)42, m)) { return -3; }
    return 0;
}

fn i32 eval_comprun_scopes_locals(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* dy = mk_decl(a);
    ast::AstNode*[1] body_stmts;
    body_stmts[0] = mk_var_decl(a, dy, mk_int(a, 5, types::prim_i32()));
    comptime::eval(&ip, mk_comprun(a, mk_block(a, &body_stmts[0], 1)));
    if(comptime::env_lookup(ip.env, dy) != null) { return -1; }
    return 0;
}

fn i32 eval_comprun_loop(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* dsum = mk_decl(a);
    comptime::eval(&ip, mk_var_decl(a, dsum, mk_int(a, 0, types::prim_i32())));
    sema::Decl* di = mk_decl(a);
    ast::AstNode* init = mk_var_decl(a, di, mk_int(a, 0, types::prim_i32()));
    ast::AstNode* cond = mk_binary(a, token::TokenKind::LT, mk_ident_resolved(a, di, types::prim_i32()), mk_int(a, 5, types::prim_i32()), types::prim_i32());
    ast::AstNode* post = mk_assign(a, token::TokenKind::Eq, mk_ident_resolved(a, di, types::prim_i32()), mk_binary(a, token::TokenKind::Plus, mk_ident_resolved(a, di, types::prim_i32()), mk_int(a, 1, types::prim_i32()), types::prim_i32()));
    ast::AstNode*[1] for_body;
    for_body[0] = mk_assign(a, token::TokenKind::Eq, mk_ident_resolved(a, dsum, types::prim_i32()), mk_binary(a, token::TokenKind::Plus, mk_ident_resolved(a, dsum, types::prim_i32()), mk_ident_resolved(a, di, types::prim_i32()), types::prim_i32()));
    ast::AstNode* forn = mk_for(a, init, cond, post, mk_block(a, &for_body[0], 1));
    ast::AstNode*[1] comprun_stmts;
    comprun_stmts[0] = forn;
    comptime::eval(&ip, mk_comprun(a, mk_block(a, &comprun_stmts[0], 1)));
    value::Value* sumv = comptime::env_lookup(ip.env, dsum);
    if(!testing::expect_eq((u64)sumv.data.i, (u64)10, m)) { return -1; }
    return 0;
}

fn i32 eval_comprun_isolates_return(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::AstNode*[1] body_stmts;
    body_stmts[0] = mk_return(a, mk_int(a, 5, types::prim_i32()));
    value::Value v = comptime::eval(&ip, mk_comprun(a, mk_block(a, &body_stmts[0], 1)));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Void, m)) { return -1; }
    if(ip.returning) { return -2; }
    return 0;
}

fn i32 eval_comprun_body_error_continues(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::AstNode*[1] body_stmts;
    body_stmts[0] = mk_ident(a);
    value::Value v = comptime::eval(&ip, mk_comprun(a, mk_block(a, &body_stmts[0], 1)));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Void, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)1, m)) { return -2; }
    return 0;
}

fn i32 comptime_safe_extern_in_comprun(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* de = mk_extern_decl(a);
    ast::AstNode*[1] comprun_stmts;
    comprun_stmts[0] = mk_call(a, mk_ident_resolved(a, de, null));
    ast::AstNode*[1] stmts;
    stmts[0] = mk_comprun(a, mk_block(a, &comprun_stmts[0], 1));
    ast::FnDeclNode* func = mk_fn_node(a, mk_block(a, &stmts[0], 1));
    if(comptime::ensure_comptime_safe(&ip, func)) { return -1; }
    return 0;
}

fn i32 eval_comperror_reports_and_halts(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    mm.literal_pool = "bad value";
    comptime::Interp ip = comptime::new_interp(mm);
    value::Value v = comptime::eval(&ip, mk_comperror(a, mk_string(a, 0, 9)));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)1, m)) { return -2; }
    if(mm.diag.entries[0].is_warning) { return -3; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "bad value", m)) { return -4; }
    return 0;
}

fn i32 eval_compwarning_continues(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    mm.literal_pool = "heads up";
    comptime::Interp ip = comptime::new_interp(mm);
    value::Value v = comptime::eval(&ip, mk_compwarning(a, mk_string(a, 0, 8)));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Void, m)) { return -1; }
    if(!mm.diag.entries[0].is_warning) { return -2; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "heads up", m)) { return -3; }
    return 0;
}

fn i32 eval_comperror_halts_comprun(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    mm.literal_pool = "stop";
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* dx = mk_decl(a);
    comptime::eval(&ip, mk_var_decl(a, dx, mk_int(a, 0, types::prim_i32())));
    ast::AstNode*[2] body_stmts;
    body_stmts[0] = mk_comperror(a, mk_string(a, 0, 4));
    body_stmts[1] = mk_assign(a, token::TokenKind::Eq, mk_ident_resolved(a, dx, types::prim_i32()), mk_int(a, 99, types::prim_i32()));
    comptime::eval(&ip, mk_comprun(a, mk_block(a, &body_stmts[0], 2)));
    value::Value* xv = comptime::env_lookup(ip.env, dx);
    if(!testing::expect_eq((u64)xv.data.i, (u64)0, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)1, m)) { return -2; }
    return 0;
}

fn i32 eval_compwarning_continues_comprun(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    mm.literal_pool = "warn";
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* dx = mk_decl(a);
    comptime::eval(&ip, mk_var_decl(a, dx, mk_int(a, 0, types::prim_i32())));
    ast::AstNode*[2] body_stmts;
    body_stmts[0] = mk_compwarning(a, mk_string(a, 0, 4));
    body_stmts[1] = mk_assign(a, token::TokenKind::Eq, mk_ident_resolved(a, dx, types::prim_i32()), mk_int(a, 7, types::prim_i32()));
    comptime::eval(&ip, mk_comprun(a, mk_block(a, &body_stmts[0], 2)));
    value::Value* xv = comptime::env_lookup(ip.env, dx);
    if(!testing::expect_eq((u64)xv.data.i, (u64)7, m)) { return -1; }
    if(!mm.diag.entries[0].is_warning) { return -2; }
    return 0;
}

fn i32 eval_comperror_non_string(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    value::Value v = comptime::eval(&ip, mk_comperror(a, mk_int(a, 5, types::prim_i32())));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "must be a string", m)) { return -2; }
    return 0;
}

fn i32 comptime_safe_extern_in_comperror(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* de = mk_extern_decl(a);
    ast::AstNode*[1] stmts;
    stmts[0] = mk_comperror(a, mk_call(a, mk_ident_resolved(a, de, null)));
    ast::FnDeclNode* func = mk_fn_node(a, mk_block(a, &stmts[0], 1));
    if(comptime::ensure_comptime_safe(&ip, func)) { return -1; }
    return 0;
}

fn i32 mono_cache_hit_and_miss(arena::Arena* a, u8[] m) {
    comptime::MonoCache cache;
    sys::memset(&cache, 0, sizeof(comptime::MonoCache));
    ast::FnDeclNode* callee = mk_fn_node(a, null);
    ast::FnDeclNode* clone_i32 = mk_fn_node(a, null);
    ast::FnDeclNode* clone_f64 = mk_fn_node(a, null);

    value::Value[1] args_i32;
    args_i32[0] = value::val_type(types::prim_i32());
    comptime::MonoKey key_i32;
    key_i32.callee = callee;
    key_i32.args = {&args_i32[0], 1};

    if(comptime::mono_cache_lookup(&cache, &key_i32) != null) { return -1; }
    comptime::mono_cache_insert(&cache, a, key_i32, clone_i32);
    if(comptime::mono_cache_lookup(&cache, &key_i32) != clone_i32) { return -2; }

    value::Value[1] args_f64;
    args_f64[0] = value::val_type(types::prim_f64());
    comptime::MonoKey key_f64;
    key_f64.callee = callee;
    key_f64.args = {&args_f64[0], 1};
    if(comptime::mono_cache_lookup(&cache, &key_f64) != null) { return -3; }
    comptime::mono_cache_insert(&cache, a, key_f64, clone_f64);
    if(comptime::mono_cache_lookup(&cache, &key_f64) != clone_f64) { return -4; }
    if(comptime::mono_cache_lookup(&cache, &key_i32) != clone_i32) { return -5; }

    ast::FnDeclNode* other = mk_fn_node(a, null);
    comptime::MonoKey key_other;
    key_other.callee = other;
    key_other.args = {&args_i32[0], 1};
    if(comptime::mono_cache_lookup(&cache, &key_other) != null) { return -6; }
    return 0;
}

fn i32 mono_cache_grows(arena::Arena* a, u8[] m) {
    comptime::MonoCache cache;
    sys::memset(&cache, 0, sizeof(comptime::MonoCache));
    ast::FnDeclNode* callee = mk_fn_node(a, null);
    ast::FnDeclNode*[20] clones;
    for(u64 i = 0; i < 20; i += 1) {
        clones[i] = mk_fn_node(a, null);
        value::Value* args = (value::Value*)arena::alloc(a, sizeof(value::Value));
        args[0] = value::val_int((i64)i, types::prim_i32());
        comptime::MonoKey key;
        key.callee = callee;
        key.args = {args, 1};
        comptime::mono_cache_insert(&cache, a, key, clones[i]);
    }
    for(u64 i = 0; i < 20; i += 1) {
        value::Value* args = (value::Value*)arena::alloc(a, sizeof(value::Value));
        args[0] = value::val_int((i64)i, types::prim_i32());
        comptime::MonoKey key;
        key.callee = callee;
        key.args = {args, 1};
        if(comptime::mono_cache_lookup(&cache, &key) != clones[i]) { return -1; }
    }
    if(!testing::expect_eq(cache.count, (u64)20, m)) { return -2; }
    return 0;
}

fn i32 mono_cache_composite_args(arena::Arena* a, u8[] m) {
    comptime::MonoCache cache;
    sys::memset(&cache, 0, sizeof(comptime::MonoCache));
    ast::FnDeclNode* callee = mk_fn_node(a, null);
    ast::FnDeclNode* clone = mk_fn_node(a, null);

    value::Value[2] fields;
    fields[0] = value::val_int(1, types::prim_i32());
    fields[1] = value::val_int(2, types::prim_i32());
    value::Value[1] args;
    value::Value[] fslice = {&fields[0], 2};
    args[0] = value::val_struct(null, fslice);
    comptime::MonoKey key;
    key.callee = callee;
    key.args = {&args[0], 1};
    comptime::mono_cache_insert(&cache, a, key, clone);

    value::Value[2] fields2;
    fields2[0] = value::val_int(1, types::prim_i32());
    fields2[1] = value::val_int(2, types::prim_i32());
    value::Value[1] args2;
    value::Value[] fslice2 = {&fields2[0], 2};
    args2[0] = value::val_struct(null, fslice2);
    comptime::MonoKey key2;
    key2.callee = callee;
    key2.args = {&args2[0], 1};
    if(comptime::mono_cache_lookup(&cache, &key2) != clone) { return -1; }

    value::Value[2] fields3;
    fields3[0] = value::val_int(1, types::prim_i32());
    fields3[1] = value::val_int(3, types::prim_i32());
    value::Value[1] args3;
    value::Value[] fslice3 = {&fields3[0], 2};
    args3[0] = value::val_struct(null, fslice3);
    comptime::MonoKey key3;
    key3.callee = callee;
    key3.args = {&args3[0], 1};
    if(comptime::mono_cache_lookup(&cache, &key3) != null) { return -2; }
    return 0;
}

fn i32 mono_cache_zero_args(arena::Arena* a, u8[] m) {
    comptime::MonoCache cache;
    sys::memset(&cache, 0, sizeof(comptime::MonoCache));
    ast::FnDeclNode* callee_a = mk_fn_node(a, null);
    ast::FnDeclNode* callee_b = mk_fn_node(a, null);
    ast::FnDeclNode* clone_a = mk_fn_node(a, null);
    value::Value[] empty = {null, 0};
    comptime::MonoKey key_a;
    key_a.callee = callee_a;
    key_a.args = empty;
    comptime::mono_cache_insert(&cache, a, key_a, clone_a);
    comptime::MonoKey key_a2;
    key_a2.callee = callee_a;
    key_a2.args = empty;
    if(comptime::mono_cache_lookup(&cache, &key_a2) != clone_a) { return -1; }
    comptime::MonoKey key_b;
    key_b.callee = callee_b;
    key_b.args = empty;
    if(comptime::mono_cache_lookup(&cache, &key_b) != null) { return -2; }
    return 0;
}

fn i32 mono_cache_multi_args(arena::Arena* a, u8[] m) {
    comptime::MonoCache cache;
    sys::memset(&cache, 0, sizeof(comptime::MonoCache));
    ast::FnDeclNode* callee = mk_fn_node(a, null);
    ast::FnDeclNode* clone = mk_fn_node(a, null);
    value::Value[2] args;
    args[0] = value::val_type(types::prim_i32());
    args[1] = value::val_type(types::prim_f64());
    comptime::MonoKey key;
    key.callee = callee;
    key.args = {&args[0], 2};
    comptime::mono_cache_insert(&cache, a, key, clone);

    value::Value[2] args2;
    args2[0] = value::val_type(types::prim_i32());
    args2[1] = value::val_type(types::prim_f64());
    comptime::MonoKey key2;
    key2.callee = callee;
    key2.args = {&args2[0], 2};
    if(comptime::mono_cache_lookup(&cache, &key2) != clone) { return -1; }

    value::Value[2] swapped;
    swapped[0] = value::val_type(types::prim_f64());
    swapped[1] = value::val_type(types::prim_i32());
    comptime::MonoKey key_swapped;
    key_swapped.callee = callee;
    key_swapped.args = {&swapped[0], 2};
    if(comptime::mono_cache_lookup(&cache, &key_swapped) != null) { return -2; }

    value::Value[1] shorter;
    shorter[0] = value::val_type(types::prim_i32());
    comptime::MonoKey key_short;
    key_short.callee = callee;
    key_short.args = {&shorter[0], 1};
    if(comptime::mono_cache_lookup(&cache, &key_short) != null) { return -3; }
    return 0;
}

fn i32 mono_cache_float_args(arena::Arena* a, u8[] m) {
    comptime::MonoCache cache;
    sys::memset(&cache, 0, sizeof(comptime::MonoCache));
    ast::FnDeclNode* callee = mk_fn_node(a, null);
    ast::FnDeclNode* clone = mk_fn_node(a, null);
    value::Value[1] args;
    args[0] = value::val_float(3.14, types::prim_f64());
    comptime::MonoKey key;
    key.callee = callee;
    key.args = {&args[0], 1};
    comptime::mono_cache_insert(&cache, a, key, clone);

    value::Value[1] args2;
    args2[0] = value::val_float(3.14, types::prim_f64());
    comptime::MonoKey key2;
    key2.callee = callee;
    key2.args = {&args2[0], 1};
    if(comptime::mono_cache_lookup(&cache, &key2) != clone) { return -1; }

    value::Value[1] args3;
    args3[0] = value::val_float(2.71, types::prim_f64());
    comptime::MonoKey key3;
    key3.callee = callee;
    key3.args = {&args3[0], 1};
    if(comptime::mono_cache_lookup(&cache, &key3) != null) { return -2; }
    return 0;
}

fn i32 mono_cache_bytes_args(arena::Arena* a, u8[] m) {
    comptime::MonoCache cache;
    sys::memset(&cache, 0, sizeof(comptime::MonoCache));
    ast::FnDeclNode* callee = mk_fn_node(a, null);
    ast::FnDeclNode* clone = mk_fn_node(a, null);

    u8[] s1 = "abc";
    value::Value[1] args;
    args[0] = value::val_bytes(s1, null);
    comptime::MonoKey key;
    key.callee = callee;
    key.args = {&args[0], 1};
    comptime::mono_cache_insert(&cache, a, key, clone);

    u8[] s2 = "abc";
    value::Value[1] args2;
    args2[0] = value::val_bytes(s2, null);
    comptime::MonoKey key2;
    key2.callee = callee;
    key2.args = {&args2[0], 1};
    if(comptime::mono_cache_lookup(&cache, &key2) != clone) { return -1; }

    u8[] s3 = "abd";
    value::Value[1] args3;
    args3[0] = value::val_bytes(s3, null);
    comptime::MonoKey key3;
    key3.callee = callee;
    key3.args = {&args3[0], 1};
    if(comptime::mono_cache_lookup(&cache, &key3) != null) { return -2; }
    return 0;
}

fn i32 eval_call_simple(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::FnDeclNode* add1 = mk_fn_node(a, null);
    sema::Decl* decl_add1 = mk_fn_decl_for(a, add1);
    sema::Decl* param_x = mk_param_decl(a);
    ast::Param[1] params;
    sys::memset(&params[0], 0, sizeof(ast::Param));
    params[0].decl = (void*)param_x;
    add1.params = {&params[0], 1};
    ast::AstNode*[1] body_s;
    body_s[0] = mk_return(a, mk_binary(a, token::TokenKind::Plus, mk_ident_resolved(a, param_x, types::prim_i32()), mk_int(a, 1, types::prim_i32()), types::prim_i32()));
    add1.body = mk_block(a, &body_s[0], 1);
    ast::AstNode*[1] args;
    args[0] = mk_int(a, 41, types::prim_i32());
    value::Value v = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_add1, null), &args[0], 1));
    if(!testing::expect_eq((u64)v.data.i, (u64)42, m)) { return -1; }
    return 0;
}

fn i32 eval_call_recursive_factorial(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::FnDeclNode* fact = mk_fn_node(a, null);
    sema::Decl* decl_fact = mk_fn_decl_for(a, fact);
    sema::Decl* param_n = mk_param_decl(a);
    ast::Param[1] params;
    sys::memset(&params[0], 0, sizeof(ast::Param));
    params[0].decl = (void*)param_n;
    fact.params = {&params[0], 1};

    ast::AstNode* cond = mk_binary(a, token::TokenKind::LTEQ, mk_ident_resolved(a, param_n, types::prim_i32()), mk_int(a, 1, types::prim_i32()), types::prim_i32());
    ast::AstNode*[1] then_s;
    then_s[0] = mk_return(a, mk_int(a, 1, types::prim_i32()));
    ast::AstNode* iff = mk_if(a, cond, mk_block(a, &then_s[0], 1), null);

    ast::AstNode*[1] rec_args;
    rec_args[0] = mk_binary(a, token::TokenKind::Minus, mk_ident_resolved(a, param_n, types::prim_i32()), mk_int(a, 1, types::prim_i32()), types::prim_i32());
    ast::AstNode* rec_call = mk_call_args(a, mk_ident_resolved(a, decl_fact, null), &rec_args[0], 1);
    ast::AstNode* mul = mk_binary(a, token::TokenKind::Star, mk_ident_resolved(a, param_n, types::prim_i32()), rec_call, types::prim_i32());
    ast::AstNode* ret = mk_return(a, mul);

    ast::AstNode*[2] body_s;
    body_s[0] = iff;
    body_s[1] = ret;
    fact.body = mk_block(a, &body_s[0], 2);

    ast::AstNode*[1] top_args;
    top_args[0] = mk_int(a, 5, types::prim_i32());
    value::Value v = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_fact, null), &top_args[0], 1));
    if(!testing::expect_eq((u64)v.data.i, (u64)120, m)) { return -1; }
    return 0;
}

fn i32 eval_call_recursion_limit(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ip.max_depth = 10;
    ast::FnDeclNode* looper = mk_fn_node(a, null);
    sema::Decl* decl_looper = mk_fn_decl_for(a, looper);
    ast::AstNode* inner_call = mk_call_args(a, mk_ident_resolved(a, decl_looper, null), null, 0);
    inner_call.h.src_pos = 555;
    ast::AstNode*[1] body_s;
    body_s[0] = inner_call;
    looper.body = mk_block(a, &body_s[0], 1);
    value::Value v = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_looper, null), null, 0));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    if(!testing::expect_eq((u64)mm.diag.entries[0].src_pos, (u64)555, m)) { return -2; }
    return 0;
}

fn i32 eval_call_extern_rejected(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    sema::Decl* de = mk_extern_decl(a);
    value::Value v = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, de, null), null, 0));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "extern", m)) { return -2; }
    return 0;
}

fn i32 eval_call_generic_needs_inference(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::FnDeclNode* gen = mk_fn_node(a, mk_block(a, null, 0));
    sema::Decl* decl_gen = mk_fn_decl_for(a, gen);
    ast::Param[1] params;
    sys::memset(&params[0], 0, sizeof(ast::Param));
    params[0].is_comptime = true;
    params[0].decl = (void*)mk_param_decl(a);
    gen.params = {&params[0], 1};
    value::Value v = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_gen, null), null, 0));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "inference", m)) { return -2; }
    return 0;
}

fn i32 eval_call_multi_param(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::FnDeclNode* sub = mk_fn_node(a, null);
    sema::Decl* decl_sub = mk_fn_decl_for(a, sub);
    sema::Decl* pa = mk_param_decl(a);
    sema::Decl* pb = mk_param_decl(a);
    ast::Param[2] params;
    sys::memset(&params[0], 0, 2 * sizeof(ast::Param));
    params[0].decl = (void*)pa;
    params[1].decl = (void*)pb;
    sub.params = {&params[0], 2};
    ast::AstNode*[1] body_s;
    body_s[0] = mk_return(a, mk_binary(a, token::TokenKind::Minus, mk_ident_resolved(a, pa, types::prim_i32()), mk_ident_resolved(a, pb, types::prim_i32()), types::prim_i32()));
    sub.body = mk_block(a, &body_s[0], 1);
    ast::AstNode*[2] call_args;
    call_args[0] = mk_int(a, 10, types::prim_i32());
    call_args[1] = mk_int(a, 3, types::prim_i32());
    value::Value v = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_sub, null), &call_args[0], 2));
    if(!testing::expect_eq((u64)v.data.i, (u64)7, m)) { return -1; }
    return 0;
}

fn i32 eval_call_arg_error(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::FnDeclNode* f = mk_fn_node(a, null);
    sema::Decl* decl_f = mk_fn_decl_for(a, f);
    sema::Decl* px = mk_param_decl(a);
    ast::Param[1] params;
    sys::memset(&params[0], 0, sizeof(ast::Param));
    params[0].decl = (void*)px;
    f.params = {&params[0], 1};
    ast::AstNode*[1] call_args;
    call_args[0] = mk_ident(a);
    value::Value v = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_f, null), &call_args[0], 1));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Error, m)) { return -1; }
    return 0;
}

fn i32 clone_fn_deep_copy(arena::Arena* a, u8[] m) {
    ast::FnDeclNode* orig = mk_fn_node(a, null);
    sema::Decl* px = mk_param_decl(a);
    ast::Param[1] params;
    sys::memset(&params[0], 0, sizeof(ast::Param));
    params[0].decl = (void*)px;
    orig.params = {&params[0], 1};
    ast::AstNode* lit1 = mk_int(a, 1, types::prim_i32());
    ast::AstNode* binop = mk_binary(a, token::TokenKind::Plus, mk_ident_resolved(a, px, types::prim_i32()), lit1, types::prim_i32());
    ast::AstNode*[1] body_s;
    body_s[0] = mk_return(a, binop);
    orig.body = mk_block(a, &body_s[0], 1);

    ast::FnDeclNode* clone = comptime::clone_fn_decl(a, orig);
    if((void*)clone == (void*)orig) { return -1; }
    if((void*)clone.body == (void*)orig.body) { return -2; }
    if(clone.params.len != 1) { return -3; }
    ast::BlockNode* cb = (ast::BlockNode*)clone.body;
    if(cb.stmts.len != 1) { return -4; }
    ast::ReturnNode* cret = (ast::ReturnNode*)cb.stmts[0];
    ast::BinaryOpNode* cbin = (ast::BinaryOpNode*)cret.expr;
    ast::IntLitNode* crhs = (ast::IntLitNode*)cbin.rhs;
    if(!testing::expect_eq((u64)crhs.value, (u64)1, m)) { return -5; }
    if((void*)crhs == (void*)lit1) { return -6; }
    crhs.value = 99;
    ast::IntLitNode* olit = (ast::IntLitNode*)lit1;
    if(!testing::expect_eq((u64)olit.value, (u64)1, m)) { return -7; }
    return 0;
}

fn i32 monomorphize_caches_and_dedups(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::FnDeclNode* gen = mk_fn_node(a, mk_block(a, null, 0));
    value::Value[1] c_i32;
    c_i32[0] = value::val_type(types::prim_i32());
    value::Value[] cargs_i32 = {&c_i32[0], 1};
    ast::FnDeclNode* clone1 = comptime::monomorphize(&ip, gen, cargs_i32);
    value::Value[1] c_i32b;
    c_i32b[0] = value::val_type(types::prim_i32());
    value::Value[] cargs_i32b = {&c_i32b[0], 1};
    ast::FnDeclNode* clone1b = comptime::monomorphize(&ip, gen, cargs_i32b);
    if((void*)clone1 != (void*)clone1b) { return -1; }
    value::Value[1] c_f64;
    c_f64[0] = value::val_type(types::prim_f64());
    value::Value[] cargs_f64 = {&c_f64[0], 1};
    ast::FnDeclNode* clone2 = comptime::monomorphize(&ip, gen, cargs_f64);
    if((void*)clone2 == (void*)clone1) { return -2; }
    if((void*)clone1 == (void*)gen) { return -3; }
    if(!testing::expect_eq(mm.instantiated_fns.len, (u64)2, m)) { return -4; }
    return 0;
}

fn i32 eval_call_int_generic(arena::Arena* a, u8[] m) {
    types::typer_init(a, 64);
    interner::init(a, 16);
    symbol::Symbol* sym_n = interner::intern("n");
    symbol::Symbol* sym_y = interner::intern("y");
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::FnDeclNode* make = mk_fn_node(a, null);
    sema::Decl* decl_make = mk_fn_decl_for(a, make);
    ast::Param[2] params;
    sys::memset(&params[0], 0, 2 * sizeof(ast::Param));
    params[0].is_comptime = true;
    params[0].name = sym_n;
    params[0].type_expr = mk_type_arg(a, types::prim_i32());
    params[1].name = sym_y;
    params[1].type_expr = mk_type_arg(a, types::prim_i32());
    make.params = {&params[0], 2};
    make.return_type = mk_type_arg(a, types::prim_i32());
    ast::AstNode*[1] body_s;
    body_s[0] = mk_return(a, mk_binary(a, token::TokenKind::Star, mk_ident_named(a, sym_n), mk_ident_named(a, sym_y), types::prim_i32()));
    make.body = mk_block(a, &body_s[0], 1);

    ast::AstNode*[2] call1;
    call1[0] = mk_int(a, 5, types::prim_i32());
    call1[1] = mk_int(a, 3, types::prim_i32());
    value::Value v = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_make, null), &call1[0], 2));
    if(!testing::expect_eq((u64)v.data.i, (u64)15, m)) { return -1; }

    ast::AstNode*[2] call2;
    call2[0] = mk_int(a, 5, types::prim_i32());
    call2[1] = mk_int(a, 4, types::prim_i32());
    value::Value v2 = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_make, null), &call2[0], 2));
    if(!testing::expect_eq((u64)v2.data.i, (u64)20, m)) { return -2; }
    if(!testing::expect_eq(mm.instantiated_fns.len, (u64)1, m)) { return -3; }

    ast::AstNode*[2] call3;
    call3[0] = mk_int(a, 6, types::prim_i32());
    call3[1] = mk_int(a, 3, types::prim_i32());
    value::Value v3 = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_make, null), &call3[0], 2));
    if(!testing::expect_eq((u64)v3.data.i, (u64)18, m)) { return -4; }
    if(!testing::expect_eq(mm.instantiated_fns.len, (u64)2, m)) { return -5; }
    return 0;
}

fn i32 eval_type_expr_to_value(arena::Arena* a, u8[] m) {
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    value::Value v = comptime::eval(&ip, mk_type_arg(a, types::prim_i32()));
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Type, m)) { return -1; }
    if(!testing::expect_eq((void*)v.data.type_ref, (void*)types::prim_i32(), m)) { return -2; }
    return 0;
}

fn i32 eval_call_type_generic(arena::Arena* a, u8[] m) {
    types::typer_init(a, 64);
    interner::init(a, 16);
    symbol::Symbol* sym_t = interner::intern("T");
    symbol::Symbol* sym_x = interner::intern("x");
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::FnDeclNode* id = mk_fn_node(a, null);
    sema::Decl* decl_id = mk_fn_decl_for(a, id);
    ast::Param[2] params;
    sys::memset(&params[0], 0, 2 * sizeof(ast::Param));
    params[0].is_comptime = true;
    params[0].name = sym_t;
    params[0].type_expr = mk_type_arg(a, types::prim_type());
    params[1].name = sym_x;
    params[1].type_expr = mk_named_type(a, sym_t);
    id.params = {&params[0], 2};
    id.return_type = mk_named_type(a, sym_t);
    ast::AstNode*[1] body_s;
    body_s[0] = mk_return(a, mk_ident_named(a, sym_x));
    id.body = mk_block(a, &body_s[0], 1);

    ast::AstNode*[2] call1;
    call1[0] = mk_type_arg(a, types::prim_i32());
    call1[1] = mk_int(a, 5, types::prim_i32());
    value::Value v = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_id, null), &call1[0], 2));
    if(!testing::expect_eq((u64)v.data.i, (u64)5, m)) { return -1; }

    ast::AstNode*[2] call2;
    call2[0] = mk_type_arg(a, types::prim_f64());
    call2[1] = mk_int(a, 5, types::prim_i32());
    value::Value v2 = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_id, null), &call2[0], 2));
    if(!testing::expect_eq((u64)v2.data.i, (u64)5, m)) { return -2; }
    if(!testing::expect_eq(mm.instantiated_fns.len, (u64)2, m)) { return -3; }

    ast::AstNode*[2] call3;
    call3[0] = mk_type_arg(a, types::prim_i32());
    call3[1] = mk_int(a, 9, types::prim_i32());
    value::Value v3 = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_id, null), &call3[0], 2));
    if(!testing::expect_eq((u64)v3.data.i, (u64)9, m)) { return -4; }
    if(!testing::expect_eq(mm.instantiated_fns.len, (u64)2, m)) { return -5; }
    return 0;
}

fn i32 eval_call_recursive_generic(arena::Arena* a, u8[] m) {
    types::typer_init(a, 64);
    interner::init(a, 16);
    symbol::Symbol* sym_rec = interner::intern("rec");
    symbol::Symbol* sym_n = interner::intern("n");
    symbol::Symbol* sym_x = interner::intern("x");
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::FnDeclNode* rec = mk_fn_node(a, null);
    sema::Decl* decl_rec = mk_fn_decl_for(a, rec);
    decl_rec.name = sym_rec;
    types::Type*[2] rec_ptypes;
    rec_ptypes[0] = types::prim_i32();
    rec_ptypes[1] = types::prim_i32();
    types::Type*[] rec_pslice = {&rec_ptypes[0], 2};
    decl_rec.ty = types::intern_fn_ptr(types::prim_i32(), rec_pslice, false);
    sema::Scope* gs = sema::scope_new(a, null, 16);
    mm.global_scope = (void*)gs;
    sema::scope_add(gs, sym_rec, decl_rec);

    ast::Param[2] params;
    sys::memset(&params[0], 0, 2 * sizeof(ast::Param));
    params[0].is_comptime = true;
    params[0].name = sym_n;
    params[0].type_expr = mk_type_arg(a, types::prim_i32());
    params[1].name = sym_x;
    params[1].type_expr = mk_type_arg(a, types::prim_i32());
    rec.params = {&params[0], 2};
    rec.return_type = mk_type_arg(a, types::prim_i32());

    ast::AstNode* cond = mk_binary(a, token::TokenKind::LTEQ, mk_ident_named(a, sym_x), mk_int(a, 0, types::prim_i32()), types::prim_i32());
    ast::AstNode*[1] then_s;
    then_s[0] = mk_return(a, mk_int(a, 0, types::prim_i32()));
    ast::AstNode* iff = mk_if(a, cond, mk_block(a, &then_s[0], 1), null);

    ast::AstNode*[2] rec_args;
    rec_args[0] = mk_ident_named(a, sym_n);
    rec_args[1] = mk_binary(a, token::TokenKind::Minus, mk_ident_named(a, sym_x), mk_int(a, 1, types::prim_i32()), types::prim_i32());
    ast::AstNode* rec_call = mk_call_args(a, mk_ident_named(a, sym_rec), &rec_args[0], 2);
    ast::AstNode* sum = mk_binary(a, token::TokenKind::Plus, mk_ident_named(a, sym_x), rec_call, types::prim_i32());
    ast::AstNode*[2] body_s;
    body_s[0] = iff;
    body_s[1] = mk_return(a, sum);
    rec.body = mk_block(a, &body_s[0], 2);

    ast::AstNode*[2] call1;
    call1[0] = mk_int(a, 5, types::prim_i32());
    call1[1] = mk_int(a, 3, types::prim_i32());
    value::Value v = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_rec, null), &call1[0], 2));
    if(!testing::expect_eq((u64)v.data.i, (u64)6, m)) { return -1; }
    if(!testing::expect_eq(mm.instantiated_fns.len, (u64)1, m)) { return -2; }
    return 0;
}

fn i32 eval_call_generic_sizeof(arena::Arena* a, u8[] m) {
    types::typer_init(a, 64);
    interner::init(a, 16);
    symbol::Symbol* symt = interner::intern("T");
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::FnDeclNode* szfn = mk_fn_node(a, null);
    sema::Decl* decl_sz = mk_fn_decl_for(a, szfn);
    sema::Decl* pt = mk_param_decl(a);
    ast::Param[1] params;
    sys::memset(&params[0], 0, sizeof(ast::Param));
    params[0].is_comptime = true;
    params[0].decl = (void*)pt;
    params[0].name = symt;
    szfn.return_type = mk_type_arg(a, types::prim_u64());
    szfn.params = {&params[0], 1};
    ast::AstNode* named_t = mk_named_type(a, symt);
    ast::AstNode*[1] body_s;
    body_s[0] = mk_return(a, mk_sizeof_of(a, named_t));
    szfn.body = mk_block(a, &body_s[0], 1);

    ast::AstNode*[1] call1;
    call1[0] = mk_type_arg(a, types::prim_i32());
    value::Value v = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_sz, null), &call1[0], 1));
    if(!testing::expect_eq((u64)v.data.i, (u64)4, m)) { return -1; }

    ast::AstNode*[1] call2;
    call2[0] = mk_type_arg(a, types::prim_f64());
    value::Value v2 = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_sz, null), &call2[0], 1));
    if(!testing::expect_eq((u64)v2.data.i, (u64)8, m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)0, m)) { return -3; }
    return 0;
}

fn i32 eval_call_generic_sizeof_array(arena::Arena* a, u8[] m) {
    types::typer_init(a, 64);
    interner::init(a, 16);
    symbol::Symbol* symt = interner::intern("T");
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::FnDeclNode* szfn = mk_fn_node(a, null);
    sema::Decl* decl_sz = mk_fn_decl_for(a, szfn);
    sema::Decl* pt = mk_param_decl(a);
    ast::Param[1] params;
    sys::memset(&params[0], 0, sizeof(ast::Param));
    params[0].is_comptime = true;
    params[0].decl = (void*)pt;
    params[0].name = symt;
    szfn.return_type = mk_type_arg(a, types::prim_u64());
    szfn.params = {&params[0], 1};
    ast::AstNode* arr_t = mk_array_type(a, mk_named_type(a, symt), mk_int(a, 3, types::prim_u64()));
    ast::AstNode*[1] body_s;
    body_s[0] = mk_return(a, mk_sizeof_of(a, arr_t));
    szfn.body = mk_block(a, &body_s[0], 1);

    ast::AstNode*[1] call1;
    call1[0] = mk_type_arg(a, types::prim_i32());
    value::Value v = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_sz, null), &call1[0], 1));
    if(!testing::expect_eq((u64)v.data.i, (u64)12, m)) { return -1; }

    ast::AstNode*[1] call2;
    call2[0] = mk_type_arg(a, types::prim_f64());
    value::Value v2 = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_sz, null), &call2[0], 1));
    if(!testing::expect_eq((u64)v2.data.i, (u64)24, m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)0, m)) { return -3; }
    return 0;
}

fn i32 eval_call_generic_sizeof_anon_struct(arena::Arena* a, u8[] m) {
    types::typer_init(a, 64);
    interner::init(a, 16);
    symbol::Symbol* sym_t = interner::intern("T");
    symbol::Symbol* sym_x = interner::intern("x");
    symbol::Symbol* sym_y = interner::intern("y");
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::FnDeclNode* szfn = mk_fn_node(a, null);
    sema::Decl* decl_sz = mk_fn_decl_for(a, szfn);
    ast::Param[1] params;
    sys::memset(&params[0], 0, sizeof(ast::Param));
    params[0].is_comptime = true;
    params[0].name = sym_t;
    params[0].type_expr = mk_type_arg(a, types::prim_type());
    szfn.params = {&params[0], 1};
    szfn.return_type = mk_type_arg(a, types::prim_u64());
    ast::FieldDecl[2] fields;
    sys::memset(&fields[0], 0, 2 * sizeof(ast::FieldDecl));
    fields[0].name = sym_x;
    fields[0].type_expr = mk_named_type(a, sym_t);
    fields[1].name = sym_y;
    fields[1].type_expr = mk_named_type(a, sym_t);
    ast::TypeStructNode* st = (ast::TypeStructNode*)arena::alloc(a, sizeof(ast::TypeStructNode));
    sys::memset(st, 0, sizeof(ast::TypeStructNode));
    st.h.kind = ast::AstKind::StructType;
    st.fields = {&fields[0], 2};
    ast::AstNode*[1] body_s;
    body_s[0] = mk_return(a, mk_sizeof_of(a, (ast::AstNode*)st));
    szfn.body = mk_block(a, &body_s[0], 1);

    ast::AstNode*[1] call1;
    call1[0] = mk_type_arg(a, types::prim_i32());
    value::Value v = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_sz, null), &call1[0], 1));
    if(!testing::expect_eq((u64)v.data.i, (u64)8, m)) { return -1; }

    ast::AstNode*[1] call2;
    call2[0] = mk_type_arg(a, types::prim_f64());
    value::Value v2 = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_sz, null), &call2[0], 1));
    if(!testing::expect_eq((u64)v2.data.i, (u64)16, m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)0, m)) { return -3; }
    return 0;
}

fn i32 eval_call_generic_array_value_param(arena::Arena* a, u8[] m) {
    types::typer_init(a, 64);
    interner::init(a, 16);
    symbol::Symbol* sym_t = interner::intern("T");
    symbol::Symbol* sym_n = interner::intern("N");
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::FnDeclNode* fn2 = mk_fn_node(a, null);
    sema::Decl* decl_fn = mk_fn_decl_for(a, fn2);
    ast::Param[2] params;
    sys::memset(&params[0], 0, 2 * sizeof(ast::Param));
    params[0].is_comptime = true;
    params[0].name = sym_t;
    params[0].type_expr = mk_type_arg(a, types::prim_type());
    params[1].is_comptime = true;
    params[1].name = sym_n;
    params[1].type_expr = mk_type_arg(a, types::prim_i32());
    fn2.params = {&params[0], 2};
    fn2.return_type = mk_type_arg(a, types::prim_u64());
    ast::AstNode* arr_t = mk_array_type(a, mk_named_type(a, sym_t), mk_ident_named(a, sym_n));
    ast::AstNode*[1] body_s;
    body_s[0] = mk_return(a, mk_sizeof_of(a, arr_t));
    fn2.body = mk_block(a, &body_s[0], 1);

    ast::AstNode*[2] call1;
    call1[0] = mk_type_arg(a, types::prim_i32());
    call1[1] = mk_int(a, 3, types::prim_i32());
    value::Value v = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_fn, null), &call1[0], 2));
    if(!testing::expect_eq((u64)v.data.i, (u64)12, m)) { return -1; }

    ast::AstNode*[2] call2;
    call2[0] = mk_type_arg(a, types::prim_f64());
    call2[1] = mk_int(a, 2, types::prim_i32());
    value::Value v2 = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_fn, null), &call2[0], 2));
    if(!testing::expect_eq((u64)v2.data.i, (u64)16, m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)0, m)) { return -3; }
    return 0;
}

fn i32 subst_respects_local_shadow(arena::Arena* a, u8[] m) {
    types::typer_init(a, 64);
    interner::init(a, 16);
    symbol::Symbol* sym_n = interner::intern("N");
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::FnDeclNode* g = mk_fn_node(a, null);
    sema::Decl* decl_g = mk_fn_decl_for(a, g);
    ast::Param[1] params;
    sys::memset(&params[0], 0, sizeof(ast::Param));
    params[0].is_comptime = true;
    params[0].name = sym_n;
    params[0].type_expr = mk_type_arg(a, types::prim_i32());
    g.params = {&params[0], 1};
    g.return_type = mk_type_arg(a, types::prim_i32());
    ast::VarDeclNode* local = (ast::VarDeclNode*)arena::alloc(a, sizeof(ast::VarDeclNode));
    sys::memset(local, 0, sizeof(ast::VarDeclNode));
    local.h.kind = ast::AstKind::VarDecl;
    local.name = sym_n;
    local.type_expr = mk_type_arg(a, types::prim_i32());
    local.init = mk_int(a, 7, types::prim_i32());
    ast::AstNode*[2] body_s;
    body_s[0] = (ast::AstNode*)local;
    body_s[1] = mk_return(a, mk_ident_named(a, sym_n));
    g.body = mk_block(a, &body_s[0], 2);

    ast::AstNode*[1] call1;
    call1[0] = mk_int(a, 5, types::prim_i32());
    value::Value v = comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_g, null), &call1[0], 1));
    if(!testing::expect_eq((u64)v.data.i, (u64)7, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, (u64)0, m)) { return -2; }
    return 0;
}

fn i32 sema_check_clone_catches_type_error(arena::Arena* a, u8[] m) {
    types::typer_init(a, 64);
    interner::init(a, 16);
    symbol::Symbol* sym_t = interner::intern("T");
    symbol::Symbol* sym_a = interner::intern("a");
    symbol::Symbol* sym_b = interner::intern("b");
    module::Module* mm = mk_module(a);
    comptime::Interp ip = comptime::new_interp(mm);
    ast::FnDeclNode* add = mk_fn_node(a, null);
    sema::Decl* decl_add = mk_fn_decl_for(a, add);
    ast::Param[3] params;
    sys::memset(&params[0], 0, 3 * sizeof(ast::Param));
    params[0].is_comptime = true;
    params[0].name = sym_t;
    params[0].type_expr = mk_type_arg(a, types::prim_type());
    params[1].name = sym_a;
    params[1].type_expr = mk_named_type(a, sym_t);
    params[2].name = sym_b;
    params[2].type_expr = mk_named_type(a, sym_t);
    add.params = {&params[0], 3};
    add.return_type = mk_named_type(a, sym_t);
    ast::AstNode* sum = mk_binary(a, token::TokenKind::Plus, mk_ident_named(a, sym_a), mk_ident_named(a, sym_b), types::prim_i32());
    sum.h.src_pos = 4242;
    ast::AstNode*[1] body_s;
    body_s[0] = mk_return(a, sum);
    add.body = mk_block(a, &body_s[0], 1);

    ast::AstNode*[3] call1;
    call1[0] = mk_type_arg(a, types::prim_bool());
    call1[1] = mk_bool(a, true);
    call1[2] = mk_bool(a, false);
    comptime::eval(&ip, mk_call_args(a, mk_ident_resolved(a, decl_add, null), &call1[0], 3));
    if(!testing::expect_eq(mm.diag.entries.len, (u64)1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "operator is not defined for bool and bool", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, (u32)4242, m)) { return -3; }
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
    testing::add(suite, "comptime_safe_pure_fn",        &comptime_safe_pure_fn);
    testing::add(suite, "comptime_safe_recursion",      &comptime_safe_recursion);
    testing::add(suite, "comptime_safe_extern_unsafe",  &comptime_safe_extern_unsafe);
    testing::add(suite, "comptime_safe_global_read_unsafe", &comptime_safe_global_read_unsafe);
    testing::add(suite, "comptime_safe_const_global_safe", &comptime_safe_const_global_safe);
    testing::add(suite, "comptime_safe_transitive",     &comptime_safe_transitive);
    testing::add(suite, "comptime_safe_calling_unsafe_is_unsafe", &comptime_safe_calling_unsafe_is_unsafe);
    testing::add(suite, "comptime_safe_extern_in_defer", &comptime_safe_extern_in_defer);
    testing::add(suite, "comptime_safe_extern_in_cast", &comptime_safe_extern_in_cast);
    testing::add(suite, "comptime_safe_extern_in_slice_range", &comptime_safe_extern_in_slice_range);
    testing::add(suite, "eval_comprun_executes",       &eval_comprun_executes);
    testing::add(suite, "eval_comprun_scopes_locals",  &eval_comprun_scopes_locals);
    testing::add(suite, "eval_comprun_loop",           &eval_comprun_loop);
    testing::add(suite, "eval_comprun_isolates_return", &eval_comprun_isolates_return);
    testing::add(suite, "eval_comprun_body_error_continues", &eval_comprun_body_error_continues);
    testing::add(suite, "comptime_safe_extern_in_comprun", &comptime_safe_extern_in_comprun);
    testing::add(suite, "eval_comperror_reports_and_halts", &eval_comperror_reports_and_halts);
    testing::add(suite, "eval_compwarning_continues",    &eval_compwarning_continues);
    testing::add(suite, "eval_comperror_halts_comprun",  &eval_comperror_halts_comprun);
    testing::add(suite, "eval_compwarning_continues_comprun", &eval_compwarning_continues_comprun);
    testing::add(suite, "eval_comperror_non_string",     &eval_comperror_non_string);
    testing::add(suite, "comptime_safe_extern_in_comperror", &comptime_safe_extern_in_comperror);
    testing::add(suite, "mono_cache_hit_and_miss",     &mono_cache_hit_and_miss);
    testing::add(suite, "mono_cache_grows",            &mono_cache_grows);
    testing::add(suite, "mono_cache_composite_args",   &mono_cache_composite_args);
    testing::add(suite, "mono_cache_zero_args",        &mono_cache_zero_args);
    testing::add(suite, "mono_cache_multi_args",       &mono_cache_multi_args);
    testing::add(suite, "mono_cache_float_args",       &mono_cache_float_args);
    testing::add(suite, "mono_cache_bytes_args",       &mono_cache_bytes_args);
    testing::add(suite, "eval_call_simple",            &eval_call_simple);
    testing::add(suite, "eval_call_recursive_factorial", &eval_call_recursive_factorial);
    testing::add(suite, "eval_call_recursion_limit",   &eval_call_recursion_limit);
    testing::add(suite, "eval_call_extern_rejected",   &eval_call_extern_rejected);
    testing::add(suite, "eval_call_generic_needs_inference", &eval_call_generic_needs_inference);
    testing::add(suite, "eval_call_multi_param",        &eval_call_multi_param);
    testing::add(suite, "eval_call_arg_error",          &eval_call_arg_error);
    testing::add(suite, "clone_fn_deep_copy",           &clone_fn_deep_copy);
    testing::add(suite, "monomorphize_caches_and_dedups", &monomorphize_caches_and_dedups);
    testing::add(suite, "eval_call_int_generic",        &eval_call_int_generic);
    testing::add(suite, "eval_type_expr_to_value",      &eval_type_expr_to_value);
    testing::add(suite, "eval_call_type_generic",       &eval_call_type_generic);
    testing::add(suite, "eval_call_recursive_generic",  &eval_call_recursive_generic);
    testing::add(suite, "eval_call_generic_sizeof",     &eval_call_generic_sizeof);
    testing::add(suite, "eval_call_generic_sizeof_array", &eval_call_generic_sizeof_array);
    testing::add(suite, "eval_call_generic_sizeof_anon_struct", &eval_call_generic_sizeof_anon_struct);
    testing::add(suite, "eval_call_generic_array_value_param", &eval_call_generic_array_value_param);
    testing::add(suite, "subst_respects_local_shadow",   &subst_respects_local_shadow);
    testing::add(suite, "sema_check_clone_catches_type_error", &sema_check_clone_catches_type_error);
    return testing::run();
}
