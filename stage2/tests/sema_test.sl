import testing;
import sema;
import module;
import diag;
import types;
import ast;
import symbol;
import arena;
import interner;
import sys;
import token;
import mutex;


// ============================================================================
// Fixtures
// ============================================================================

fn module::Module* fresh_module(arena::Arena* a) {
    module::Module* m = (module::Module*)arena::alloc(a, sizeof(module::Module));
    sys::memset(m, 0, sizeof(module::Module));
    m.arena = a;
    return m;
}

fn module::Module* fresh_module_with_interner(arena::Arena* a) {
    interner::init(a, 16);
    return fresh_module(a);
}

fn sema::Sema mk_sema(module::Module* m) {
    sema::Sema s;
    sys::memset(&s, 0, sizeof(sema::Sema));
    s.m = m;
    return s;
}

fn symbol::Symbol* fake_sym(arena::Arena* a) {
    symbol::Symbol* s = (symbol::Symbol*)arena::alloc(a, sizeof(symbol::Symbol));
    sys::memset(s, 0, sizeof(symbol::Symbol));
    return s;
}

fn symbol::Symbol* fake_sym_interned(module::Module* m, u8[] bytes) {
    return interner::intern(bytes);
}

fn sema::Decl* fake_decl(arena::Arena* a, u16 kind, symbol::Symbol* name, types::Type* ty) {
    sema::Decl* d = (sema::Decl*)arena::alloc(a, sizeof(sema::Decl));
    sys::memset(d, 0, sizeof(sema::Decl));
    d.kind = kind;
    d.name = name;
    d.ty = ty;
    return d;
}

fn sema::Decl* fake_node_decl(arena::Arena* a, symbol::Symbol* name, types::Type* ty, ast::AstNode* node) {
    sema::Decl* d = fake_decl(a, (u16)sema::DeclKind::Node, name, ty);
    d.data.node = node;
    return d;
}

fn sema::Decl* fake_param_decl(arena::Arena* a, symbol::Symbol* name, types::Type* ty) {
    sema::Decl* d = fake_decl(a, (u16)sema::DeclKind::Param, name, ty);
    return d;
}

fn sema::Decl* fake_field_decl_value(arena::Arena* a, symbol::Symbol* name, types::Type* ty) {
    sema::Decl* d = fake_decl(a, (u16)sema::DeclKind::Field, name, ty);
    return d;
}

fn sema::Decl* fake_enum_member_decl_value(arena::Arena* a, symbol::Symbol* name, types::Type* ty) {
    sema::Decl* d = fake_decl(a, (u16)sema::DeclKind::EnumMember, name, ty);
    return d;
}

fn sema::Decl* fake_import_decl(arena::Arena* a, symbol::Symbol* name, module::Module* target) {
    sema::Decl* d = fake_decl(a, (u16)sema::DeclKind::Import, name, null);
    d.data.module = target;
    return d;
}

fn ast::VarDeclNode* fake_var_decl(arena::Arena* a, symbol::Symbol* name, bool is_const) {
    ast::VarDeclNode* v = (ast::VarDeclNode*)arena::alloc(a, sizeof(ast::VarDeclNode));
    sys::memset(v, 0, sizeof(ast::VarDeclNode));
    v.h.kind = ast::AstKind::VarDecl;
    v.name = name;
    v.is_const = is_const;
    return v;
}

fn ast::FnDeclNode* fake_fn_decl(arena::Arena* a, symbol::Symbol* name) {
    ast::FnDeclNode* f = (ast::FnDeclNode*)arena::alloc(a, sizeof(ast::FnDeclNode));
    sys::memset(f, 0, sizeof(ast::FnDeclNode));
    f.h.kind = ast::AstKind::FnDecl;
    f.name = name;
    return f;
}

fn ast::IntLitNode* fake_int_lit(arena::Arena* a, u64 value, u32 src_pos) {
    ast::IntLitNode* n = (ast::IntLitNode*)arena::alloc(a, sizeof(ast::IntLitNode));
    sys::memset(n, 0, sizeof(ast::IntLitNode));
    n.h.kind = ast::AstKind::IntLit;
    n.h.src_pos = src_pos;
    n.value = value;
    return n;
}

fn ast::StructLitNode* fake_struct_lit(arena::Arena* a, u32 src_pos) {
    ast::StructLitNode* n = (ast::StructLitNode*)arena::alloc(a, sizeof(ast::StructLitNode));
    sys::memset(n, 0, sizeof(ast::StructLitNode));
    n.h.kind = ast::AstKind::StructLit;
    n.h.src_pos = src_pos;
    n.inits = {null, 0};
    return n;
}

fn ast::FloatLitNode* fake_float_lit(arena::Arena* a, f64 value, u32 src_pos) {
    ast::FloatLitNode* n = (ast::FloatLitNode*)arena::alloc(a, sizeof(ast::FloatLitNode));
    sys::memset(n, 0, sizeof(ast::FloatLitNode));
    n.h.kind = ast::AstKind::FloatLit;
    n.h.src_pos = src_pos;
    n.value = value;
    return n;
}

fn ast::BoolLitNode* fake_bool_lit(arena::Arena* a, bool value, u32 src_pos) {
    ast::BoolLitNode* n = (ast::BoolLitNode*)arena::alloc(a, sizeof(ast::BoolLitNode));
    sys::memset(n, 0, sizeof(ast::BoolLitNode));
    n.h.kind = ast::AstKind::BoolLit;
    n.h.src_pos = src_pos;
    n.value = value;
    return n;
}

fn ast::CharLitNode* fake_char_lit(arena::Arena* a, u8 value, u32 src_pos) {
    ast::CharLitNode* n = (ast::CharLitNode*)arena::alloc(a, sizeof(ast::CharLitNode));
    sys::memset(n, 0, sizeof(ast::CharLitNode));
    n.h.kind = ast::AstKind::CharLit;
    n.h.src_pos = src_pos;
    n.value = value;
    return n;
}

fn ast::StringLitNode* fake_string_lit_node(arena::Arena* a, u32 src_pos) {
    ast::StringLitNode* n = (ast::StringLitNode*)arena::alloc(a, sizeof(ast::StringLitNode));
    sys::memset(n, 0, sizeof(ast::StringLitNode));
    n.h.kind = ast::AstKind::StringLit;
    n.h.src_pos = src_pos;
    return n;
}

fn ast::NullLitNode* fake_null_lit(arena::Arena* a, u32 src_pos) {
    ast::NullLitNode* n = (ast::NullLitNode*)arena::alloc(a, sizeof(ast::NullLitNode));
    sys::memset(n, 0, sizeof(ast::NullLitNode));
    n.h.kind = ast::AstKind::NullLit;
    n.h.src_pos = src_pos;
    return n;
}

fn ast::UndefinedLitNode* fake_undefined_lit(arena::Arena* a, u32 src_pos) {
    ast::UndefinedLitNode* n = (ast::UndefinedLitNode*)arena::alloc(a, sizeof(ast::UndefinedLitNode));
    sys::memset(n, 0, sizeof(ast::UndefinedLitNode));
    n.h.kind = ast::AstKind::UndefinedLit;
    n.h.src_pos = src_pos;
    return n;
}

fn ast::IdentNode* fake_ident(arena::Arena* a, symbol::Symbol* name, u32 src_pos) {
    ast::IdentNode* n = (ast::IdentNode*)arena::alloc(a, sizeof(ast::IdentNode));
    sys::memset(n, 0, sizeof(ast::IdentNode));
    n.h.kind = ast::AstKind::Ident;
    n.h.src_pos = src_pos;
    n.name = name;
    return n;
}

fn ast::ArrayLitNode* fake_array_lit(arena::Arena* a, u32 src_pos) {
    ast::ArrayLitNode* n = (ast::ArrayLitNode*)arena::alloc(a, sizeof(ast::ArrayLitNode));
    sys::memset(n, 0, sizeof(ast::ArrayLitNode));
    n.h.kind = ast::AstKind::ArrayLit;
    n.h.src_pos = src_pos;
    n.elems = {null, 0};
    return n;
}

fn bool has_flag(ast::AstNode* e, ast::AstFlags f) {
    return ((u16)e.h.flags & (u16)f) != 0;
}

fn ast::BinaryOpNode* fake_binop(arena::Arena* a, token::TokenKind op, ast::AstNode* lhs, ast::AstNode* rhs, u32 src_pos) {
    ast::BinaryOpNode* n = (ast::BinaryOpNode*)arena::alloc(a, sizeof(ast::BinaryOpNode));
    sys::memset(n, 0, sizeof(ast::BinaryOpNode));
    n.h.kind = ast::AstKind::BinaryOp;
    n.h.src_pos = src_pos;
    n.op = op;
    n.lhs = lhs;
    n.rhs = rhs;
    return n;
}

fn ast::UnaryOpNode* fake_unary(arena::Arena* a, token::TokenKind op, ast::AstNode* operand, u32 src_pos) {
    ast::UnaryOpNode* n = (ast::UnaryOpNode*)arena::alloc(a, sizeof(ast::UnaryOpNode));
    sys::memset(n, 0, sizeof(ast::UnaryOpNode));
    n.h.kind = ast::AstKind::UnaryOp;
    n.h.src_pos = src_pos;
    n.op = op;
    n.operand = operand;
    return n;
}

fn sema::Decl* register_var(arena::Arena* a, sema::Scope* sc, symbol::Symbol* name, types::Type* ty, bool is_const) {
    sema::Decl* d = fake_node_decl(a, name, ty, (ast::AstNode*)fake_var_decl(a, name, is_const));
    sema::scope_add(sc, name, d);
    return d;
}

fn ast::MemberAccessNode* fake_member(arena::Arena* a, ast::AstNode* base, symbol::Symbol* field, u32 src_pos) {
    ast::MemberAccessNode* n = (ast::MemberAccessNode*)arena::alloc(a, sizeof(ast::MemberAccessNode));
    sys::memset(n, 0, sizeof(ast::MemberAccessNode));
    n.h.kind = ast::AstKind::MemberAccess;
    n.h.src_pos = src_pos;
    n.base = base;
    n.field = field;
    return n;
}

fn ast::ArrayIndexNode* fake_index(arena::Arena* a, ast::AstNode* base, ast::AstNode* index, u32 src_pos) {
    ast::ArrayIndexNode* n = (ast::ArrayIndexNode*)arena::alloc(a, sizeof(ast::ArrayIndexNode));
    sys::memset(n, 0, sizeof(ast::ArrayIndexNode));
    n.h.kind = ast::AstKind::ArrayIndex;
    n.h.src_pos = src_pos;
    n.base = base;
    n.index = index;
    return n;
}

fn ast::SliceRangeNode* fake_slice_range(arena::Arena* a, ast::AstNode* base, ast::AstNode* lo, ast::AstNode* hi, u32 src_pos) {
    ast::SliceRangeNode* n = (ast::SliceRangeNode*)arena::alloc(a, sizeof(ast::SliceRangeNode));
    sys::memset(n, 0, sizeof(ast::SliceRangeNode));
    n.h.kind = ast::AstKind::SliceRange;
    n.h.src_pos = src_pos;
    n.base = base;
    n.lo = lo;
    n.hi = hi;
    return n;
}

fn ast::CallNode* fake_call(arena::Arena* a, ast::AstNode* callee, ast::AstNode** args, u64 argc, u32 src_pos) {
    ast::CallNode* n = (ast::CallNode*)arena::alloc(a, sizeof(ast::CallNode));
    sys::memset(n, 0, sizeof(ast::CallNode));
    n.h.kind = ast::AstKind::Call;
    n.h.src_pos = src_pos;
    n.callee = callee;
    n.args = {args, argc};
    return n;
}

fn ast::CastNode* fake_cast(arena::Arena* a, ast::AstNode* target_type, ast::AstNode* expr, u32 src_pos) {
    ast::CastNode* n = (ast::CastNode*)arena::alloc(a, sizeof(ast::CastNode));
    sys::memset(n, 0, sizeof(ast::CastNode));
    n.h.kind = ast::AstKind::Cast;
    n.h.src_pos = src_pos;
    n.target_type = target_type;
    n.expr = expr;
    return n;
}

fn sema::Decl* register_fn(arena::Arena* a, sema::Scope* sc, symbol::Symbol* name, types::Type* fnty) {
    sema::Decl* d = fake_node_decl(a, name, fnty, (ast::AstNode*)fake_fn_decl(a, name));
    sema::scope_add(sc, name, d);
    return d;
}

fn ast::NamespaceAccessNode* fake_ns_access(arena::Arena* a, ast::AstNode* base, symbol::Symbol* name, u32 src_pos) {
    ast::NamespaceAccessNode* n = (ast::NamespaceAccessNode*)arena::alloc(a, sizeof(ast::NamespaceAccessNode));
    sys::memset(n, 0, sizeof(ast::NamespaceAccessNode));
    n.h.kind = ast::AstKind::NamespaceAccess;
    n.h.src_pos = src_pos;
    n.base = base;
    n.name = name;
    return n;
}

fn ast::StructLitNode* fake_struct_lit_with(arena::Arena* a, ast::FieldInitializer* inits, u64 count, u32 src_pos) {
    ast::StructLitNode* n = fake_struct_lit(a, src_pos);
    n.inits = {inits, count};
    return n;
}

fn ast::ArrayLitNode* fake_array_lit_with(arena::Arena* a, ast::AstNode** elems, u64 count, u32 src_pos) {
    ast::ArrayLitNode* n = fake_array_lit(a, src_pos);
    n.elems = {elems, count};
    return n;
}

fn void set_init(ast::FieldInitializer* fi, symbol::Symbol* name, ast::AstNode* value, u32 src_pos) {
    fi.name = name;
    fi.value = value;
    fi.src_pos = src_pos;
}

fn ast::AstNode* mk_block(arena::Arena* a, ast::AstNode** stmts, u64 count) {
    ast::BlockNode* block = (ast::BlockNode*)arena::alloc(a, sizeof(ast::BlockNode));
    sys::memset(block, 0, sizeof(ast::BlockNode));
    block.h.kind = ast::AstKind::BlockStmt;
    block.stmts = {stmts, count};
    return (ast::AstNode*)block;
}

fn ast::FnDeclNode* mk_fn_body(arena::Arena* a, symbol::Symbol* name, ast::AstNode* return_type, ast::AstNode* body) {
    ast::FnDeclNode* node = (ast::FnDeclNode*)arena::alloc(a, sizeof(ast::FnDeclNode));
    sys::memset(node, 0, sizeof(ast::FnDeclNode));
    node.h.kind = ast::AstKind::FnDecl;
    node.name = name;
    node.return_type = return_type;
    node.body = body;
    return node;
}

// The module must already exist (interner initialized) before the caller builds
// the fn AST, so interned symbols live in the current interner, not an orphaned one.
fn void run_fn(arena::Arena* a, module::Module* mm, ast::FnDeclNode* func) {
    ast::AstNode** root = (ast::AstNode**)arena::alloc(a, sizeof(ast::AstNode*));
    root[0] = (ast::AstNode*)func;
    set_root(mm, a, root, 1);
    sema::run(mm);
}

fn ast::AstNode* fake_local_var(arena::Arena* a, symbol::Symbol* name, ast::AstNode* type_expr, ast::AstNode* init, u32 pos) {
    ast::VarDeclNode* n = (ast::VarDeclNode*)arena::alloc(a, sizeof(ast::VarDeclNode));
    sys::memset(n, 0, sizeof(ast::VarDeclNode));
    n.h.kind = ast::AstKind::VarDecl;
    n.h.src_pos = pos;
    n.name = name;
    n.type_expr = type_expr;
    n.init = init;
    return (ast::AstNode*)n;
}

fn ast::AstNode* fake_return(arena::Arena* a, ast::AstNode* expr, u32 pos) {
    ast::ReturnNode* n = (ast::ReturnNode*)arena::alloc(a, sizeof(ast::ReturnNode));
    sys::memset(n, 0, sizeof(ast::ReturnNode));
    n.h.kind = ast::AstKind::ReturnStmt;
    n.h.src_pos = pos;
    n.expr = expr;
    return (ast::AstNode*)n;
}

fn ast::AstNode* fake_if(arena::Arena* a, ast::AstNode* cond, ast::AstNode* then_block, ast::AstNode* else_block, u32 pos) {
    ast::IfNode* n = (ast::IfNode*)arena::alloc(a, sizeof(ast::IfNode));
    sys::memset(n, 0, sizeof(ast::IfNode));
    n.h.kind = ast::AstKind::IfStmt;
    n.h.src_pos = pos;
    n.cond = cond;
    n.then_block = then_block;
    n.else_block = else_block;
    return (ast::AstNode*)n;
}

fn ast::AstNode* fake_while(arena::Arena* a, ast::AstNode* cond, ast::AstNode* body, u32 pos) {
    ast::WhileNode* n = (ast::WhileNode*)arena::alloc(a, sizeof(ast::WhileNode));
    sys::memset(n, 0, sizeof(ast::WhileNode));
    n.h.kind = ast::AstKind::WhileStmt;
    n.h.src_pos = pos;
    n.cond = cond;
    n.body = body;
    return (ast::AstNode*)n;
}

fn ast::AstNode* fake_for(arena::Arena* a, ast::AstNode* init, ast::AstNode* cond, ast::AstNode* post, ast::AstNode* body, u32 pos) {
    ast::ForNode* n = (ast::ForNode*)arena::alloc(a, sizeof(ast::ForNode));
    sys::memset(n, 0, sizeof(ast::ForNode));
    n.h.kind = ast::AstKind::ForStmt;
    n.h.src_pos = pos;
    n.init = init;
    n.cond = cond;
    n.post = post;
    n.body = body;
    return (ast::AstNode*)n;
}

fn ast::AstNode* fake_break(arena::Arena* a, u32 pos) {
    ast::BreakNode* n = (ast::BreakNode*)arena::alloc(a, sizeof(ast::BreakNode));
    sys::memset(n, 0, sizeof(ast::BreakNode));
    n.h.kind = ast::AstKind::BreakStmt;
    n.h.src_pos = pos;
    return (ast::AstNode*)n;
}

fn ast::AstNode* fake_continue(arena::Arena* a, u32 pos) {
    ast::ContinueNode* n = (ast::ContinueNode*)arena::alloc(a, sizeof(ast::ContinueNode));
    sys::memset(n, 0, sizeof(ast::ContinueNode));
    n.h.kind = ast::AstKind::ContinueStmt;
    n.h.src_pos = pos;
    return (ast::AstNode*)n;
}

fn ast::AstNode* fake_defer(arena::Arena* a, ast::AstNode* body, u32 pos) {
    ast::DeferNode* n = (ast::DeferNode*)arena::alloc(a, sizeof(ast::DeferNode));
    sys::memset(n, 0, sizeof(ast::DeferNode));
    n.h.kind = ast::AstKind::DeferStmt;
    n.h.src_pos = pos;
    n.body = body;
    return (ast::AstNode*)n;
}

fn ast::AstNode* fake_assign(arena::Arena* a, token::TokenKind op, ast::AstNode* lhs, ast::AstNode* rhs, u32 pos) {
    ast::AssignmentNode* n = (ast::AssignmentNode*)arena::alloc(a, sizeof(ast::AssignmentNode));
    sys::memset(n, 0, sizeof(ast::AssignmentNode));
    n.h.kind = ast::AstKind::AssignmentStmt;
    n.h.src_pos = pos;
    n.op = op;
    n.lhs = lhs;
    n.rhs = rhs;
    return (ast::AstNode*)n;
}

fn ast::AstNode* fake_expr_stmt(arena::Arena* a, ast::AstNode* expr, u32 pos) {
    ast::ExprStmtNode* n = (ast::ExprStmtNode*)arena::alloc(a, sizeof(ast::ExprStmtNode));
    sys::memset(n, 0, sizeof(ast::ExprStmtNode));
    n.h.kind = ast::AstKind::ExprStmt;
    n.h.src_pos = pos;
    n.expr = expr;
    return (ast::AstNode*)n;
}

fn ast::AstNode* fake_switch(arena::Arena* a, ast::AstNode* disc, ast::SwitchArm* arms, u64 arm_count, ast::AstNode* else_block, u32 pos) {
    ast::SwitchNode* n = (ast::SwitchNode*)arena::alloc(a, sizeof(ast::SwitchNode));
    sys::memset(n, 0, sizeof(ast::SwitchNode));
    n.h.kind = ast::AstKind::SwitchStmt;
    n.h.src_pos = pos;
    n.discriminant = disc;
    n.arms = {arms, arm_count};
    n.else_block = else_block;
    return (ast::AstNode*)n;
}

fn types::Type* register_color_enum(arena::Arena* a, sema::Scope* sc) {
    symbol::Symbol*[2] names; names[0] = interner::intern("Red"); names[1] = interner::intern("Green");
    symbol::Symbol*[] nslice = {&names[0], 2};
    ast::EnumDeclNode* d = fake_enum_decl_with_members(a, nslice);
    d.qualified_name = interner::intern("Color");
    types::Type* ety = types::intern_enum((void*)d);
    symbol::Symbol* cname = interner::intern("Color");
    sema::Decl* cd = fake_node_decl(a, cname, ety, (ast::AstNode*)d);
    cd.is_exported = true;
    sema::scope_add(sc, cname, cd);
    return ety;
}

fn types::Type* mk_point_type(arena::Arena* a) {
    symbol::Symbol*[2] fnames; fnames[0] = interner::intern("x"); fnames[1] = interner::intern("y");
    types::Type*[2] ftys; ftys[0] = types::prim_i32(); ftys[1] = types::prim_i32();
    symbol::Symbol*[] fn_slice = {&fnames[0], 2};
    types::Type*[] ft_slice = {&ftys[0], 2};
    ast::StructDeclNode* d = fake_struct_decl_with_fields(a, fn_slice, ft_slice);
    d.qualified_name = interner::intern("Point");
    return types::intern_struct((void*)d);
}

fn ast::StructDeclNode* fake_struct_decl_with_fields(arena::Arena* a, symbol::Symbol*[] names, types::Type*[] tys) {
    ast::StructDeclNode* d = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    sys::memset(d, 0, sizeof(ast::StructDeclNode));
    d.h.kind = ast::AstKind::StructDecl;
    if(names.len > 0) {
        ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, names.len * sizeof(ast::FieldDecl));
        sys::memset(fields, 0, names.len * sizeof(ast::FieldDecl));
        for(u64 i = 0; i < names.len; i += 1) {
            fields[i].name = names[i];
            fields[i].resolved_type = (void*)tys[i];
        }
        d.fields = {fields, names.len};
    } else {
        d.fields = {null, 0};
    }
    return d;
}

fn ast::UnionDeclNode* fake_union_decl_with_fields(arena::Arena* a, symbol::Symbol*[] names, types::Type*[] tys) {
    ast::UnionDeclNode* d = (ast::UnionDeclNode*)arena::alloc(a, sizeof(ast::UnionDeclNode));
    sys::memset(d, 0, sizeof(ast::UnionDeclNode));
    d.h.kind = ast::AstKind::UnionDecl;
    if(names.len > 0) {
        ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, names.len * sizeof(ast::FieldDecl));
        sys::memset(fields, 0, names.len * sizeof(ast::FieldDecl));
        for(u64 i = 0; i < names.len; i += 1) {
            fields[i].name = names[i];
            fields[i].resolved_type = (void*)tys[i];
        }
        d.fields = {fields, names.len};
    } else {
        d.fields = {null, 0};
    }
    return d;
}

fn ast::EnumDeclNode* fake_enum_decl_with_members(arena::Arena* a, symbol::Symbol*[] names) {
    ast::EnumDeclNode* d = (ast::EnumDeclNode*)arena::alloc(a, sizeof(ast::EnumDeclNode));
    sys::memset(d, 0, sizeof(ast::EnumDeclNode));
    d.h.kind = ast::AstKind::EnumDecl;
    if(names.len > 0) {
        ast::EnumMember* members = (ast::EnumMember*)arena::alloc(a, names.len * sizeof(ast::EnumMember));
        sys::memset(members, 0, names.len * sizeof(ast::EnumMember));
        for(u64 i = 0; i < names.len; i += 1) {
            members[i].name = names[i];
        }
        d.members = {members, names.len};
    } else {
        d.members = {null, 0};
    }
    return d;
}

fn types::Type* mk_struct_type(arena::Arena* a, symbol::Symbol*[] names, types::Type*[] tys) {
    ast::StructDeclNode* d = fake_struct_decl_with_fields(a, names, tys);
    return types::intern_struct((void*)d);
}

fn types::Type* mk_union_type(arena::Arena* a, symbol::Symbol*[] names, types::Type*[] tys) {
    ast::UnionDeclNode* d = fake_union_decl_with_fields(a, names, tys);
    return types::intern_union((void*)d);
}

fn symbol::Symbol*[] mk_syms2(arena::Arena* a, symbol::Symbol* s0, symbol::Symbol* s1) {
    symbol::Symbol** mem = (symbol::Symbol**)arena::alloc(a, 2 * sizeof(symbol::Symbol*));
    mem[0] = s0; mem[1] = s1;
    symbol::Symbol*[] r; r.ptr = mem; r.len = 2; return r;
}

fn symbol::Symbol*[] mk_syms3(arena::Arena* a, symbol::Symbol* s0, symbol::Symbol* s1, symbol::Symbol* s2) {
    symbol::Symbol** mem = (symbol::Symbol**)arena::alloc(a, 3 * sizeof(symbol::Symbol*));
    mem[0] = s0; mem[1] = s1; mem[2] = s2;
    symbol::Symbol*[] r; r.ptr = mem; r.len = 3; return r;
}

fn types::Type*[] mk_tys2(arena::Arena* a, types::Type* t0, types::Type* t1) {
    types::Type** mem = (types::Type**)arena::alloc(a, 2 * sizeof(types::Type*));
    mem[0] = t0; mem[1] = t1;
    types::Type*[] r; r.ptr = mem; r.len = 2; return r;
}

fn types::Type*[] mk_tys3(arena::Arena* a, types::Type* t0, types::Type* t1, types::Type* t2) {
    types::Type** mem = (types::Type**)arena::alloc(a, 3 * sizeof(types::Type*));
    mem[0] = t0; mem[1] = t1; mem[2] = t2;
    types::Type*[] r; r.ptr = mem; r.len = 3; return r;
}

fn void fresh_typer(arena::Arena* a) {
    types::typer_init(a, 16);
}

fn bool has_ast_flag(ast::AstNode* n, ast::AstFlags f) {
    return ((u16)n.h.flags & (u16)f) != 0;
}


// ============================================================================
// Scope: scope_new
// ============================================================================

fn i32 scope_new_returns_non_null(arena::Arena* a, u8[] m) {
    sema::Scope* s = sema::scope_new(a, null, 16);
    if(!testing::expect_not_null((void*)s, m)) { return -1; }
    return 0;
}

fn i32 scope_new_parent_null_for_module(arena::Arena* a, u8[] m) {
    sema::Scope* s = sema::scope_new(a, null, 16);
    if(!testing::expect_not_null((void*)s, m)) { return -1; }
    if(!testing::expect_eq((void*)s.parent, (void*)null, m)) { return -2; }
    return 0;
}

fn i32 scope_new_records_parent(arena::Arena* a, u8[] m) {
    sema::Scope* parent = sema::scope_new(a, null, 16);
    sema::Scope* child  = sema::scope_new(a, parent, 16);
    if(!testing::expect_not_null((void*)child, m)) { return -1; }
    if(!testing::expect_eq((void*)child.parent, (void*)parent, m)) { return -2; }
    return 0;
}

fn i32 scope_new_cap_matches(arena::Arena* a, u8[] m) {
    sema::Scope* s = sema::scope_new(a, null, 16);
    if(!testing::expect_not_null((void*)s, m)) { return -1; }
    if(!testing::expect_eq(s.cap, 16, m)) { return -2; }
    return 0;
}

fn i32 scope_new_count_zero(arena::Arena* a, u8[] m) {
    sema::Scope* s = sema::scope_new(a, null, 16);
    if(!testing::expect_not_null((void*)s, m)) { return -1; }
    if(!testing::expect_eq(s.count, 0, m)) { return -2; }
    return 0;
}

fn i32 scope_new_entries_allocated(arena::Arena* a, u8[] m) {
    sema::Scope* s = sema::scope_new(a, null, 16);
    if(!testing::expect_not_null((void*)s, m)) { return -1; }
    if(!testing::expect_not_null((void*)s.entries.ptr, m)) { return -2; }
    if(!testing::expect_eq(s.entries.len, 16, m)) { return -3; }
    return 0;
}

fn i32 scope_new_entries_zeroed(arena::Arena* a, u8[] m) {
    sema::Scope* s = sema::scope_new(a, null, 16);
    if(!testing::expect_not_null((void*)s, m)) { return -1; }
    if(!testing::expect_not_null((void*)s.entries.ptr, m)) { return -2; }
    for(u64 i = 0; i < s.entries.len; i += 1) {
        if(!testing::expect_eq((void*)s.entries[i].name, (void*)null, m)) { return -3; }
        if(!testing::expect_eq((void*)s.entries[i].decl, (void*)null, m)) { return -4; }
    }
    return 0;
}

fn i32 scope_new_arena_bound(arena::Arena* a, u8[] m) {
    sema::Scope* s = sema::scope_new(a, null, 16);
    if(!testing::expect_not_null((void*)s, m)) { return -1; }
    if(!testing::expect_eq((void*)s.arena, (void*)a, m)) { return -2; }
    return 0;
}


// ============================================================================
// Scope: scope_add
// ============================================================================

fn i32 scope_add_first_returns_true(arena::Arena* a, u8[] m) {
    sema::Scope* s = sema::scope_new(a, null, 16);
    if(!testing::expect_not_null((void*)s, m)) { return -1; }
    symbol::Symbol* k = fake_sym(a);
    sema::Decl* d = fake_decl(a, (u16)sema::DeclKind::Node, k, null);
    if(!testing::expect_eq(sema::scope_add(s, k, d), true, m)) { return -2; }
    return 0;
}

fn i32 scope_add_increments_count(arena::Arena* a, u8[] m) {
    sema::Scope* s = sema::scope_new(a, null, 16);
    if(!testing::expect_not_null((void*)s, m)) { return -1; }
    symbol::Symbol* k = fake_sym(a);
    sema::Decl* d = fake_decl(a, (u16)sema::DeclKind::Node, k, null);
    sema::scope_add(s, k, d);
    if(!testing::expect_eq(s.count, 1, m)) { return -2; }
    return 0;
}

fn i32 scope_add_duplicate_returns_false(arena::Arena* a, u8[] m) {
    sema::Scope* s = sema::scope_new(a, null, 16);
    if(!testing::expect_not_null((void*)s, m)) { return -1; }
    symbol::Symbol* k = fake_sym(a);
    sema::Decl* d1 = fake_decl(a, (u16)sema::DeclKind::Node, k, null);
    sema::Decl* d2 = fake_decl(a, (u16)sema::DeclKind::Node, k, null);
    sema::scope_add(s, k, d1);
    if(!testing::expect_eq(sema::scope_add(s, k, d2), false, m)) { return -2; }
    return 0;
}

fn i32 scope_add_duplicate_does_not_change_count(arena::Arena* a, u8[] m) {
    sema::Scope* s = sema::scope_new(a, null, 16);
    if(!testing::expect_not_null((void*)s, m)) { return -1; }
    symbol::Symbol* k = fake_sym(a);
    sema::Decl* d1 = fake_decl(a, (u16)sema::DeclKind::Node, k, null);
    sema::Decl* d2 = fake_decl(a, (u16)sema::DeclKind::Node, k, null);
    sema::scope_add(s, k, d1);
    sema::scope_add(s, k, d2);
    if(!testing::expect_eq(s.count, 1, m)) { return -2; }
    return 0;
}

fn i32 scope_add_two_different_keys(arena::Arena* a, u8[] m) {
    sema::Scope* s = sema::scope_new(a, null, 16);
    if(!testing::expect_not_null((void*)s, m)) { return -1; }
    symbol::Symbol* k1 = fake_sym(a);
    symbol::Symbol* k2 = fake_sym(a);
    sema::Decl* d1 = fake_decl(a, (u16)sema::DeclKind::Node, k1, null);
    sema::Decl* d2 = fake_decl(a, (u16)sema::DeclKind::Node, k2, null);
    if(!testing::expect_eq(sema::scope_add(s, k1, d1), true, m)) { return -2; }
    if(!testing::expect_eq(sema::scope_add(s, k2, d2), true, m)) { return -3; }
    if(!testing::expect_eq(s.count, 2, m)) { return -4; }
    return 0;
}


// ============================================================================
// Scope: scope_lookup_local
// ============================================================================

fn i32 lookup_local_finds_inserted(arena::Arena* a, u8[] m) {
    sema::Scope* s = sema::scope_new(a, null, 16);
    if(!testing::expect_not_null((void*)s, m)) { return -1; }
    symbol::Symbol* k = fake_sym(a);
    sema::Decl* d = fake_decl(a, (u16)sema::DeclKind::Node, k, null);
    sema::scope_add(s, k, d);
    if(!testing::expect_eq((void*)sema::scope_lookup_local(s, k), (void*)d, m)) { return -2; }
    return 0;
}

fn i32 lookup_local_returns_null_for_missing(arena::Arena* a, u8[] m) {
    sema::Scope* s = sema::scope_new(a, null, 16);
    if(!testing::expect_not_null((void*)s, m)) { return -1; }
    symbol::Symbol* k = fake_sym(a);
    if(!testing::expect_eq((void*)sema::scope_lookup_local(s, k), (void*)null, m)) { return -2; }
    return 0;
}

fn i32 lookup_local_does_not_walk_parent(arena::Arena* a, u8[] m) {
    sema::Scope* parent = sema::scope_new(a, null, 16);
    sema::Scope* child  = sema::scope_new(a, parent, 16);
    if(!testing::expect_not_null((void*)parent, m)) { return -1; }
    if(!testing::expect_not_null((void*)child,  m)) { return -2; }
    symbol::Symbol* k = fake_sym(a);
    sema::Decl* d = fake_decl(a, (u16)sema::DeclKind::Node, k, null);
    sema::scope_add(parent, k, d);
    if(!testing::expect_eq((void*)sema::scope_lookup_local(child, k), (void*)null, m)) { return -3; }
    return 0;
}


// ============================================================================
// Scope: scope_lookup (walks parent chain)
// ============================================================================

fn i32 lookup_finds_in_self(arena::Arena* a, u8[] m) {
    sema::Scope* s = sema::scope_new(a, null, 16);
    if(!testing::expect_not_null((void*)s, m)) { return -1; }
    symbol::Symbol* k = fake_sym(a);
    sema::Decl* d = fake_decl(a, (u16)sema::DeclKind::Node, k, null);
    sema::scope_add(s, k, d);
    if(!testing::expect_eq((void*)sema::scope_lookup(s, k), (void*)d, m)) { return -2; }
    return 0;
}

fn i32 lookup_walks_to_parent(arena::Arena* a, u8[] m) {
    sema::Scope* parent = sema::scope_new(a, null, 16);
    sema::Scope* child  = sema::scope_new(a, parent, 16);
    if(!testing::expect_not_null((void*)parent, m)) { return -1; }
    if(!testing::expect_not_null((void*)child,  m)) { return -2; }
    symbol::Symbol* k = fake_sym(a);
    sema::Decl* d = fake_decl(a, (u16)sema::DeclKind::Node, k, null);
    sema::scope_add(parent, k, d);
    if(!testing::expect_eq((void*)sema::scope_lookup(child, k), (void*)d, m)) { return -3; }
    return 0;
}

fn i32 lookup_self_shadows_parent(arena::Arena* a, u8[] m) {
    sema::Scope* parent = sema::scope_new(a, null, 16);
    sema::Scope* child  = sema::scope_new(a, parent, 16);
    if(!testing::expect_not_null((void*)parent, m)) { return -1; }
    if(!testing::expect_not_null((void*)child,  m)) { return -2; }
    symbol::Symbol* k = fake_sym(a);
    sema::Decl* outer = fake_decl(a, (u16)sema::DeclKind::Node, k, null);
    sema::Decl* inner = fake_decl(a, (u16)sema::DeclKind::Node, k, null);
    sema::scope_add(parent, k, outer);
    sema::scope_add(child,  k, inner);
    if(!testing::expect_eq((void*)sema::scope_lookup(child, k), (void*)inner, m)) { return -3; }
    return 0;
}

fn i32 lookup_walks_two_levels(arena::Arena* a, u8[] m) {
    sema::Scope* g  = sema::scope_new(a, null, 16);
    sema::Scope* mid = sema::scope_new(a, g, 16);
    sema::Scope* leaf = sema::scope_new(a, mid, 16);
    if(!testing::expect_not_null((void*)g,    m)) { return -1; }
    if(!testing::expect_not_null((void*)mid,  m)) { return -2; }
    if(!testing::expect_not_null((void*)leaf, m)) { return -3; }
    symbol::Symbol* k = fake_sym(a);
    sema::Decl* d = fake_decl(a, (u16)sema::DeclKind::Node, k, null);
    sema::scope_add(g, k, d);
    if(!testing::expect_eq((void*)sema::scope_lookup(leaf, k), (void*)d, m)) { return -4; }
    return 0;
}

fn i32 lookup_returns_null_when_not_in_chain(arena::Arena* a, u8[] m) {
    sema::Scope* parent = sema::scope_new(a, null, 16);
    sema::Scope* child  = sema::scope_new(a, parent, 16);
    if(!testing::expect_not_null((void*)parent, m)) { return -1; }
    if(!testing::expect_not_null((void*)child,  m)) { return -2; }
    symbol::Symbol* k = fake_sym(a);
    if(!testing::expect_eq((void*)sema::scope_lookup(child, k), (void*)null, m)) { return -3; }
    return 0;
}


// ============================================================================
// Scope: grow / rehash
// ============================================================================

fn i32 scope_grow_preserves_entries(arena::Arena* a, u8[] m) {
    sema::Scope* s = sema::scope_new(a, null, 4);
    if(!testing::expect_not_null((void*)s, m)) { return -1; }
    symbol::Symbol*[10] keys;
    sema::Decl*[10] decls;
    for(u64 i = 0; i < 10; i += 1) {
        keys[i]  = fake_sym(a);
        decls[i] = fake_decl(a, (u16)sema::DeclKind::Node, keys[i], null);
        sema::scope_add(s, keys[i], decls[i]);
    }
    if(!testing::expect_eq(s.count, 10, m)) { return -2; }
    if(!testing::expect_gt(s.cap, 4, m)) { return -3; }
    for(u64 i = 0; i < 10; i += 1) {
        if(!testing::expect_eq((void*)sema::scope_lookup_local(s, keys[i]), (void*)decls[i], m)) { return -4; }
    }
    return 0;
}

fn i32 scope_grow_cap_is_power_of_two(arena::Arena* a, u8[] m) {
    sema::Scope* s = sema::scope_new(a, null, 4);
    if(!testing::expect_not_null((void*)s, m)) { return -1; }
    for(u64 i = 0; i < 32; i += 1) {
        symbol::Symbol* k = fake_sym(a);
        sema::Decl* d = fake_decl(a, (u16)sema::DeclKind::Node, k, null);
        sema::scope_add(s, k, d);
    }
    u64 c = s.cap;
    if(!testing::expect_eq(c & (c - 1), 0, m)) { return -2; }
    return 0;
}


// ============================================================================
// ResolutionStack
// ============================================================================

fn i32 stack_empty_does_not_contain(arena::Arena* a, u8[] m) {
    sema::ResolutionStack st;
    sys::memset(&st, 0, sizeof(sema::ResolutionStack));
    st.arena = a;
    sema::ResolutionKey k = { fresh_module(a), fake_sym(a) };
    if(!testing::expect_eq(sema::stack_contains(&st, k), false, m)) { return -1; }
    return 0;
}

fn i32 stack_push_then_contains(arena::Arena* a, u8[] m) {
    sema::ResolutionStack st;
    sys::memset(&st, 0, sizeof(sema::ResolutionStack));
    st.arena = a;
    sema::ResolutionKey k = { fresh_module(a), fake_sym(a) };
    sema::stack_push(&st, k);
    if(!testing::expect_eq(sema::stack_contains(&st, k), true, m)) { return -1; }
    return 0;
}

fn i32 stack_push_pop_no_longer_contains(arena::Arena* a, u8[] m) {
    sema::ResolutionStack st;
    sys::memset(&st, 0, sizeof(sema::ResolutionStack));
    st.arena = a;
    sema::ResolutionKey k = { fresh_module(a), fake_sym(a) };
    sema::stack_push(&st, k);
    sema::stack_pop(&st);
    if(!testing::expect_eq(sema::stack_contains(&st, k), false, m)) { return -1; }
    return 0;
}

fn i32 stack_distinguishes_module(arena::Arena* a, u8[] m) {
    sema::ResolutionStack st;
    sys::memset(&st, 0, sizeof(sema::ResolutionStack));
    st.arena = a;
    symbol::Symbol* name = fake_sym(a);
    sema::ResolutionKey kA = { fresh_module(a), name };
    sema::ResolutionKey kB = { fresh_module(a), name };
    sema::stack_push(&st, kA);
    if(!testing::expect_eq(sema::stack_contains(&st, kB), false, m)) { return -1; }
    if(!testing::expect_eq(sema::stack_contains(&st, kA), true,  m)) { return -2; }
    return 0;
}

fn i32 stack_distinguishes_name(arena::Arena* a, u8[] m) {
    sema::ResolutionStack st;
    sys::memset(&st, 0, sizeof(sema::ResolutionStack));
    st.arena = a;
    module::Module* mm = fresh_module(a);
    sema::ResolutionKey kA = { mm, fake_sym(a) };
    sema::ResolutionKey kB = { mm, fake_sym(a) };
    sema::stack_push(&st, kA);
    if(!testing::expect_eq(sema::stack_contains(&st, kB), false, m)) { return -1; }
    if(!testing::expect_eq(sema::stack_contains(&st, kA), true,  m)) { return -2; }
    return 0;
}

fn i32 stack_multi_push_all_contained(arena::Arena* a, u8[] m) {
    sema::ResolutionStack st;
    sys::memset(&st, 0, sizeof(sema::ResolutionStack));
    st.arena = a;
    module::Module* mm = fresh_module(a);
    sema::ResolutionKey k1 = { mm, fake_sym(a) };
    sema::ResolutionKey k2 = { mm, fake_sym(a) };
    sema::ResolutionKey k3 = { mm, fake_sym(a) };
    sema::stack_push(&st, k1);
    sema::stack_push(&st, k2);
    sema::stack_push(&st, k3);
    if(!testing::expect_eq(sema::stack_contains(&st, k1), true, m)) { return -1; }
    if(!testing::expect_eq(sema::stack_contains(&st, k2), true, m)) { return -2; }
    if(!testing::expect_eq(sema::stack_contains(&st, k3), true, m)) { return -3; }
    return 0;
}

fn i32 stack_pop_only_removes_top(arena::Arena* a, u8[] m) {
    sema::ResolutionStack st;
    sys::memset(&st, 0, sizeof(sema::ResolutionStack));
    st.arena = a;
    module::Module* mm = fresh_module(a);
    sema::ResolutionKey k1 = { mm, fake_sym(a) };
    sema::ResolutionKey k2 = { mm, fake_sym(a) };
    sema::stack_push(&st, k1);
    sema::stack_push(&st, k2);
    sema::stack_pop(&st);
    if(!testing::expect_eq(sema::stack_contains(&st, k1), true,  m)) { return -1; }
    if(!testing::expect_eq(sema::stack_contains(&st, k2), false, m)) { return -2; }
    return 0;
}


// ============================================================================
// decl_is_lvalue / decl_is_const_expr per DeclKind
// ============================================================================

fn i32 lvalue_var_non_const_true(arena::Arena* a, u8[] m) {
    ast::VarDeclNode* v = fake_var_decl(a, fake_sym(a), false);
    sema::Decl* d = fake_node_decl(a, v.name, null, (ast::AstNode*)v);
    if(!testing::expect_eq(sema::decl_is_lvalue(d), true, m)) { return -1; }
    return 0;
}

fn i32 lvalue_var_const_true(arena::Arena* a, u8[] m) {
    ast::VarDeclNode* v = fake_var_decl(a, fake_sym(a), true);
    sema::Decl* d = fake_node_decl(a, v.name, null, (ast::AstNode*)v);
    if(!testing::expect_eq(sema::decl_is_lvalue(d), true, m)) { return -1; }
    return 0;
}

fn i32 lvalue_fn_false(arena::Arena* a, u8[] m) {
    ast::FnDeclNode* f = fake_fn_decl(a, fake_sym(a));
    sema::Decl* d = fake_node_decl(a, f.name, null, (ast::AstNode*)f);
    if(!testing::expect_eq(sema::decl_is_lvalue(d), false, m)) { return -1; }
    return 0;
}

fn i32 lvalue_param_true(arena::Arena* a, u8[] m) {
    sema::Decl* d = fake_param_decl(a, fake_sym(a), null);
    if(!testing::expect_eq(sema::decl_is_lvalue(d), true, m)) { return -1; }
    return 0;
}

fn i32 lvalue_field_true(arena::Arena* a, u8[] m) {
    sema::Decl* d = fake_field_decl_value(a, fake_sym(a), null);
    if(!testing::expect_eq(sema::decl_is_lvalue(d), true, m)) { return -1; }
    return 0;
}

fn i32 lvalue_enum_member_false(arena::Arena* a, u8[] m) {
    sema::Decl* d = fake_enum_member_decl_value(a, fake_sym(a), null);
    if(!testing::expect_eq(sema::decl_is_lvalue(d), false, m)) { return -1; }
    return 0;
}

fn i32 lvalue_import_false(arena::Arena* a, u8[] m) {
    sema::Decl* d = fake_import_decl(a, fake_sym(a), fresh_module(a));
    if(!testing::expect_eq(sema::decl_is_lvalue(d), false, m)) { return -1; }
    return 0;
}

fn i32 constexpr_var_const_true(arena::Arena* a, u8[] m) {
    ast::VarDeclNode* v = fake_var_decl(a, fake_sym(a), true);
    sema::Decl* d = fake_node_decl(a, v.name, null, (ast::AstNode*)v);
    if(!testing::expect_eq(sema::decl_is_const_expr(d), true, m)) { return -1; }
    return 0;
}

fn i32 constexpr_var_non_const_false(arena::Arena* a, u8[] m) {
    ast::VarDeclNode* v = fake_var_decl(a, fake_sym(a), false);
    sema::Decl* d = fake_node_decl(a, v.name, null, (ast::AstNode*)v);
    if(!testing::expect_eq(sema::decl_is_const_expr(d), false, m)) { return -1; }
    return 0;
}

fn i32 constexpr_enum_member_true(arena::Arena* a, u8[] m) {
    sema::Decl* d = fake_enum_member_decl_value(a, fake_sym(a), null);
    if(!testing::expect_eq(sema::decl_is_const_expr(d), true, m)) { return -1; }
    return 0;
}

fn i32 constexpr_fn_true(arena::Arena* a, u8[] m) {
    ast::FnDeclNode* f = fake_fn_decl(a, fake_sym(a));
    sema::Decl* d = fake_node_decl(a, f.name, null, (ast::AstNode*)f);
    if(!testing::expect_eq(sema::decl_is_const_expr(d), true, m)) { return -1; }
    return 0;
}

fn i32 constexpr_param_false(arena::Arena* a, u8[] m) {
    sema::Decl* d = fake_param_decl(a, fake_sym(a), null);
    if(!testing::expect_eq(sema::decl_is_const_expr(d), false, m)) { return -1; }
    return 0;
}

fn i32 constexpr_field_false(arena::Arena* a, u8[] m) {
    sema::Decl* d = fake_field_decl_value(a, fake_sym(a), null);
    if(!testing::expect_eq(sema::decl_is_const_expr(d), false, m)) { return -1; }
    return 0;
}

fn i32 constexpr_import_false(arena::Arena* a, u8[] m) {
    sema::Decl* d = fake_import_decl(a, fake_sym(a), fresh_module(a));
    if(!testing::expect_eq(sema::decl_is_const_expr(d), false, m)) { return -1; }
    return 0;
}


// ============================================================================
// container_decl
// ============================================================================

fn i32 container_decl_for_struct(arena::Arena* a, u8[] m) {
    fresh_typer(a);
    symbol::Symbol*[] names = mk_syms2(a, fake_sym(a), fake_sym(a));
    types::Type*[] tys = mk_tys2(a, types::prim_i32(), types::prim_u8());
    ast::StructDeclNode* d = fake_struct_decl_with_fields(a, names, tys);
    types::Type* t = types::intern_struct((void*)d);
    if(!testing::expect_eq((void*)sema::container_decl(t), (void*)d, m)) { return -1; }
    return 0;
}

fn i32 container_decl_for_union(arena::Arena* a, u8[] m) {
    fresh_typer(a);
    symbol::Symbol*[] names = mk_syms2(a, fake_sym(a), fake_sym(a));
    types::Type*[] tys = mk_tys2(a, types::prim_i32(), types::prim_u8());
    ast::UnionDeclNode* d = fake_union_decl_with_fields(a, names, tys);
    types::Type* t = types::intern_union((void*)d);
    if(!testing::expect_eq((void*)sema::container_decl(t), (void*)d, m)) { return -1; }
    return 0;
}

fn i32 container_decl_for_primitive_null(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq((void*)sema::container_decl(types::prim_i32()), (void*)null, m)) { return -1; }
    return 0;
}

fn i32 container_decl_for_pointer_null(arena::Arena* a, u8[] m) {
    fresh_typer(a);
    types::Type* p = types::intern_pointer(types::prim_i32(), false);
    if(!testing::expect_eq((void*)sema::container_decl(p), (void*)null, m)) { return -1; }
    return 0;
}

fn i32 container_decl_for_slice_null(arena::Arena* a, u8[] m) {
    fresh_typer(a);
    types::Type* sl = types::intern_slice(types::prim_i32());
    if(!testing::expect_eq((void*)sema::container_decl(sl), (void*)null, m)) { return -1; }
    return 0;
}


// ============================================================================
// find_field / find_field_index
// ============================================================================

fn i32 find_field_returns_existing(arena::Arena* a, u8[] m) {
    symbol::Symbol* n0 = fake_sym(a);
    symbol::Symbol* n1 = fake_sym(a);
    symbol::Symbol*[] names = mk_syms2(a, n0, n1);
    types::Type*[] tys = mk_tys2(a, types::prim_i32(), types::prim_u8());
    ast::StructDeclNode* d = fake_struct_decl_with_fields(a, names, tys);
    ast::FieldDecl* found = sema::find_field((ast::AstNode*)d, n1);
    if(!testing::expect_not_null((void*)found, m)) { return -1; }
    if(!testing::expect_eq((void*)found.name, (void*)n1, m)) { return -2; }
    return 0;
}

fn i32 find_field_returns_null_for_missing(arena::Arena* a, u8[] m) {
    symbol::Symbol*[] names = mk_syms2(a, fake_sym(a), fake_sym(a));
    types::Type*[] tys = mk_tys2(a, types::prim_i32(), types::prim_u8());
    ast::StructDeclNode* d = fake_struct_decl_with_fields(a, names, tys);
    symbol::Symbol* missing = fake_sym(a);
    if(!testing::expect_eq((void*)sema::find_field((ast::AstNode*)d, missing), (void*)null, m)) { return -1; }
    return 0;
}

fn i32 find_field_empty_returns_null(arena::Arena* a, u8[] m) {
    symbol::Symbol*[] names = {null, 0};
    types::Type*[] tys = {null, 0};
    ast::StructDeclNode* d = fake_struct_decl_with_fields(a, names, tys);
    if(!testing::expect_eq((void*)sema::find_field((ast::AstNode*)d, fake_sym(a)), (void*)null, m)) { return -1; }
    return 0;
}

fn i32 find_field_works_on_union(arena::Arena* a, u8[] m) {
    symbol::Symbol* n0 = fake_sym(a);
    symbol::Symbol* n1 = fake_sym(a);
    symbol::Symbol*[] names = mk_syms2(a, n0, n1);
    types::Type*[] tys = mk_tys2(a, types::prim_i32(), types::prim_u8());
    ast::UnionDeclNode* d = fake_union_decl_with_fields(a, names, tys);
    ast::FieldDecl* found = sema::find_field((ast::AstNode*)d, n0);
    if(!testing::expect_not_null((void*)found, m)) { return -1; }
    if(!testing::expect_eq((void*)found.name, (void*)n0, m)) { return -2; }
    return 0;
}

fn i32 find_field_index_first(arena::Arena* a, u8[] m) {
    symbol::Symbol* n0 = fake_sym(a);
    symbol::Symbol*[] names = mk_syms3(a, n0, fake_sym(a), fake_sym(a));
    types::Type*[] tys = mk_tys3(a, types::prim_i32(), types::prim_u8(), types::prim_bool());
    ast::StructDeclNode* d = fake_struct_decl_with_fields(a, names, tys);
    if(!testing::expect_eq(sema::find_field_index(d, n0), 0, m)) { return -1; }
    return 0;
}

fn i32 find_field_index_last(arena::Arena* a, u8[] m) {
    symbol::Symbol* n2 = fake_sym(a);
    symbol::Symbol*[] names = mk_syms3(a, fake_sym(a), fake_sym(a), n2);
    types::Type*[] tys = mk_tys3(a, types::prim_i32(), types::prim_u8(), types::prim_bool());
    ast::StructDeclNode* d = fake_struct_decl_with_fields(a, names, tys);
    if(!testing::expect_eq(sema::find_field_index(d, n2), 2, m)) { return -1; }
    return 0;
}

fn i32 find_field_index_missing_is_max(arena::Arena* a, u8[] m) {
    symbol::Symbol*[] names = mk_syms2(a, fake_sym(a), fake_sym(a));
    types::Type*[] tys = mk_tys2(a, types::prim_i32(), types::prim_u8());
    ast::StructDeclNode* d = fake_struct_decl_with_fields(a, names, tys);
    u64 idx = sema::find_field_index(d, fake_sym(a));
    if(!testing::expect_eq(idx, (u64)-1, m)) { return -1; }
    return 0;
}


// ============================================================================
// find_enum_member
// ============================================================================

fn i32 find_enum_member_existing(arena::Arena* a, u8[] m) {
    symbol::Symbol* red   = fake_sym(a);
    symbol::Symbol* green = fake_sym(a);
    symbol::Symbol*[] names = mk_syms2(a, red, green);
    ast::EnumDeclNode* d = fake_enum_decl_with_members(a, names);
    ast::EnumMember* mem = sema::find_enum_member(d, green);
    if(!testing::expect_not_null((void*)mem, m)) { return -1; }
    if(!testing::expect_eq((void*)mem.name, (void*)green, m)) { return -2; }
    return 0;
}

fn i32 find_enum_member_missing(arena::Arena* a, u8[] m) {
    symbol::Symbol*[] names = mk_syms2(a, fake_sym(a), fake_sym(a));
    ast::EnumDeclNode* d = fake_enum_decl_with_members(a, names);
    if(!testing::expect_eq((void*)sema::find_enum_member(d, fake_sym(a)), (void*)null, m)) { return -1; }
    return 0;
}

fn i32 find_enum_member_empty(arena::Arena* a, u8[] m) {
    symbol::Symbol*[] names = {null, 0};
    ast::EnumDeclNode* d = fake_enum_decl_with_members(a, names);
    if(!testing::expect_eq((void*)sema::find_enum_member(d, fake_sym(a)), (void*)null, m)) { return -1; }
    return 0;
}


// ============================================================================
// make_field_decl / make_enum_member_decl
// ============================================================================

fn i32 make_field_decl_kind(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module(a);
    sema::Sema s = mk_sema(mm);
    ast::FieldDecl f;
    sys::memset(&f, 0, sizeof(ast::FieldDecl));
    symbol::Symbol* n = fake_sym(a);
    f.name = n;
    sema::Decl* d = sema::make_field_decl(&s, &f, types::prim_i32());
    if(!testing::expect_not_null((void*)d, m)) { return -1; }
    if(!testing::expect_eq(d.kind, (u16)sema::DeclKind::Field, m)) { return -2; }
    return 0;
}

fn i32 make_field_decl_name_set(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module(a);
    sema::Sema s = mk_sema(mm);
    ast::FieldDecl f;
    sys::memset(&f, 0, sizeof(ast::FieldDecl));
    symbol::Symbol* n = fake_sym(a);
    f.name = n;
    sema::Decl* d = sema::make_field_decl(&s, &f, types::prim_i32());
    if(!testing::expect_not_null((void*)d, m)) { return -1; }
    if(!testing::expect_eq((void*)d.name, (void*)n, m)) { return -2; }
    return 0;
}

fn i32 make_field_decl_ty_set(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module(a);
    sema::Sema s = mk_sema(mm);
    ast::FieldDecl f;
    sys::memset(&f, 0, sizeof(ast::FieldDecl));
    types::Type* ty = types::prim_u64();
    sema::Decl* d = sema::make_field_decl(&s, &f, ty);
    if(!testing::expect_not_null((void*)d, m)) { return -1; }
    if(!testing::expect_eq((void*)d.ty, (void*)ty, m)) { return -2; }
    return 0;
}

fn i32 make_field_decl_data_field_set(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module(a);
    sema::Sema s = mk_sema(mm);
    ast::FieldDecl f;
    sys::memset(&f, 0, sizeof(ast::FieldDecl));
    sema::Decl* d = sema::make_field_decl(&s, &f, types::prim_i32());
    if(!testing::expect_not_null((void*)d, m)) { return -1; }
    if(!testing::expect_eq((void*)d.data.field, (void*)&f, m)) { return -2; }
    return 0;
}

fn i32 make_enum_member_decl_kind(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module(a);
    sema::Sema s = mk_sema(mm);
    ast::EnumMember em;
    sys::memset(&em, 0, sizeof(ast::EnumMember));
    symbol::Symbol* n = fake_sym(a);
    em.name = n;
    types::Type* ety = types::prim_i32();
    sema::Decl* d = sema::make_enum_member_decl(&s, &em, ety);
    if(!testing::expect_not_null((void*)d, m)) { return -1; }
    if(!testing::expect_eq(d.kind, (u16)sema::DeclKind::EnumMember, m)) { return -2; }
    return 0;
}

fn i32 make_enum_member_decl_name_set(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module(a);
    sema::Sema s = mk_sema(mm);
    ast::EnumMember em;
    sys::memset(&em, 0, sizeof(ast::EnumMember));
    symbol::Symbol* n = fake_sym(a);
    em.name = n;
    sema::Decl* d = sema::make_enum_member_decl(&s, &em, types::prim_i32());
    if(!testing::expect_not_null((void*)d, m)) { return -1; }
    if(!testing::expect_eq((void*)d.name, (void*)n, m)) { return -2; }
    return 0;
}

fn i32 make_enum_member_decl_ty_set(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module(a);
    sema::Sema s = mk_sema(mm);
    ast::EnumMember em;
    sys::memset(&em, 0, sizeof(ast::EnumMember));
    types::Type* ety = types::prim_i32();
    sema::Decl* d = sema::make_enum_member_decl(&s, &em, ety);
    if(!testing::expect_not_null((void*)d, m)) { return -1; }
    if(!testing::expect_eq((void*)d.ty, (void*)ety, m)) { return -2; }
    return 0;
}

fn i32 make_enum_member_decl_data_set(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module(a);
    sema::Sema s = mk_sema(mm);
    ast::EnumMember em;
    sys::memset(&em, 0, sizeof(ast::EnumMember));
    sema::Decl* d = sema::make_enum_member_decl(&s, &em, types::prim_i32());
    if(!testing::expect_not_null((void*)d, m)) { return -1; }
    if(!testing::expect_eq((void*)d.data.member, (void*)&em, m)) { return -2; }
    return 0;
}


// ============================================================================
// Diagnostic helpers
// ============================================================================

fn i32 diag_type_mismatch_emits_one_entry(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    sema::diag_type_mismatch(&s, 42, types::prim_u32(), types::prim_i32());
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -1; }
    return 0;
}

fn i32 diag_type_mismatch_records_src_pos(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    sema::diag_type_mismatch(&s, 137, types::prim_u32(), types::prim_i32());
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 137, m)) { return -2; }
    return 0;
}

fn i32 diag_type_mismatch_mentions_expected(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    sema::diag_type_mismatch(&s, 0, types::prim_u32(), types::prim_i32());
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "i32", m)) { return -2; }
    return 0;
}

fn i32 diag_type_mismatch_mentions_got(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    sema::diag_type_mismatch(&s, 0, types::prim_u32(), types::prim_i32());
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "u32", m)) { return -2; }
    return 0;
}

fn i32 diag_type_mismatch_is_error_not_warning(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    sema::diag_type_mismatch(&s, 0, types::prim_u32(), types::prim_i32());
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].is_warning, false, m)) { return -2; }
    return 0;
}

fn i32 diag_lit_overflow_emits_entry(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    sema::diag_lit_overflow(&s, 7, 300, types::prim_u8());
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 7, m)) { return -2; }
    return 0;
}

fn i32 diag_lit_overflow_mentions_type(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    sema::diag_lit_overflow(&s, 0, 300, types::prim_u8());
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "u8", m)) { return -2; }
    return 0;
}

fn i32 diag_lit_overflow_mentions_value(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    sema::diag_lit_overflow(&s, 0, 300, types::prim_u8());
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "300", m)) { return -2; }
    return 0;
}

fn i32 diag_cast_invalid_mentions_both_types(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    sema::diag_cast_invalid(&s, 0, types::prim_bool(), types::prim_f32());
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "bool", m)) { return -2; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "f32",  m)) { return -3; }
    return 0;
}

fn i32 diag_binop_mismatch_mentions_both_types(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    sema::diag_binop_mismatch(&s, 0, token::TokenKind::Plus, types::prim_i32(), types::prim_bool());
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "i32",  m)) { return -2; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "bool", m)) { return -3; }
    return 0;
}

fn i32 diag_not_bool_convertible_mentions_type(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    fresh_typer(a);
    symbol::Symbol*[] names = mk_syms2(a, fake_sym(a), fake_sym(a));
    types::Type*[] tys = mk_tys2(a, types::prim_i32(), types::prim_u8());
    types::Type* st = mk_struct_type(a, names, tys);
    sema::diag_not_bool_convertible(&s, 0, st);
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -1; }
    return 0;
}

fn i32 diag_resolution_cycle_emits_entry(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    sema::ResolutionKey k = { mm, fake_sym_interned(mm, "Foo") };
    sema::diag_resolution_cycle(&s, 0, k);
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -1; }
    return 0;
}

fn i32 diag_resolution_cycle_mentions_name(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    sema::ResolutionKey k = { mm, fake_sym_interned(mm, "Foo") };
    sema::diag_resolution_cycle(&s, 0, k);
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "Foo", m)) { return -2; }
    return 0;
}

fn i32 diag_needs_context_emits_entry(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    ast::StructLitNode* lit = fake_struct_lit(a, 99);
    sema::diag_needs_context(&s, (ast::AstNode*)lit);
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 99, m)) { return -2; }
    return 0;
}


// ============================================================================
// check_int_lit
// ============================================================================

fn i32 check_int_lit_positive_fits_u8(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    ast::IntLitNode* n = fake_int_lit(a, 200, 0);
    if(!testing::expect_eq(sema::check_int_lit(&s, n, types::prim_u8()), true, m)) { return -1; }
    return 0;
}

fn i32 check_int_lit_sets_ty_on_success(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    ast::IntLitNode* n = fake_int_lit(a, 200, 0);
    sema::check_int_lit(&s, n, types::prim_u8());
    if(!testing::expect_eq((void*)n.h.ty, (void*)types::prim_u8(), m)) { return -1; }
    return 0;
}

fn i32 check_int_lit_overflow_returns_false(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    ast::IntLitNode* n = fake_int_lit(a, 256, 0);
    if(!testing::expect_eq(sema::check_int_lit(&s, n, types::prim_u8()), false, m)) { return -1; }
    return 0;
}

fn i32 check_int_lit_overflow_emits_diag(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    ast::IntLitNode* n = fake_int_lit(a, 256, 11);
    sema::check_int_lit(&s, n, types::prim_u8());
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 11, m)) { return -2; }
    return 0;
}

fn i32 check_int_lit_overflow_sets_had_error(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    ast::IntLitNode* n = fake_int_lit(a, 256, 0);
    sema::check_int_lit(&s, n, types::prim_u8());
    if(!testing::expect_eq(has_ast_flag((ast::AstNode*)n, ast::AstFlags::HadError), true, m)) { return -1; }
    return 0;
}

fn i32 check_int_lit_float_target_rejected(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    ast::IntLitNode* n = fake_int_lit(a, 1, 0);
    if(!testing::expect_eq(sema::check_int_lit(&s, n, types::prim_f32()), false, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -2; }
    return 0;
}

fn i32 check_int_lit_fits_largest_u64(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    ast::IntLitNode* n = fake_int_lit(a, 18446744073709551615, 0);
    if(!testing::expect_eq(sema::check_int_lit(&s, n, types::prim_u64()), true, m)) { return -1; }
    return 0;
}

fn i32 check_int_lit_zero_fits_any_int(arena::Arena* a, u8[] m) {
    module::Module* mm = fresh_module_with_interner(a);
    sema::Sema s = mk_sema(mm);
    ast::IntLitNode* n = fake_int_lit(a, 0, 0);
    if(!testing::expect_eq(sema::check_int_lit(&s, n, types::prim_u8()),  true, m)) { return -1; }
    if(!testing::expect_eq(sema::check_int_lit(&s, n, types::prim_i64()), true, m)) { return -2; }
    return 0;
}


// ============================================================================
// scope_add: first-write-wins on duplicate
// ============================================================================

fn i32 scope_add_duplicate_keeps_first(arena::Arena* a, u8[] m) {
    sema::Scope* s = sema::scope_new(a, null, 16);
    if(!testing::expect_not_null((void*)s, m)) { return -1; }
    symbol::Symbol* k = fake_sym(a);
    sema::Decl* first  = fake_decl(a, (u16)sema::DeclKind::Node, k, null);
    sema::Decl* second = fake_decl(a, (u16)sema::DeclKind::Node, k, null);
    sema::scope_add(s, k, first);
    sema::scope_add(s, k, second);
    if(!testing::expect_eq((void*)sema::scope_lookup_local(s, k), (void*)first, m)) { return -2; }
    return 0;
}


// ============================================================================
// collect_names_locked — driven through the exported sema::run entry point.
// collect_names_locked is private by design, so we exercise it via run(): build
// a top-level block, run sema, then inspect the module's global_scope, the
// buffered diagnostics, and the qualified_name written back onto each decl.
// (run's other two sub-passes are no-op stubs, so run == name collection here.)
// ============================================================================

fn module::Module* run_module(arena::Arena* a, u8[] mod_name) {
    module::Module* m = fresh_module_with_interner(a);
    types::typer_init(a, 16);
    m.name = interner::intern(mod_name);
    mutex::create(&m.sema_mutex);
    return m;
}

fn void set_root(module::Module* m, arena::Arena* a, ast::AstNode** stmts, u64 count) {
    ast::BlockNode* block = (ast::BlockNode*)arena::alloc(a, sizeof(ast::BlockNode));
    sys::memset(block, 0, sizeof(ast::BlockNode));
    block.h.kind = ast::AstKind::BlockStmt;
    block.stmts.ptr = stmts;
    block.stmts.len = count;
    m.root_node = (ast::AstNode*)block;
}

fn sema::Decl* registered(module::Module* m, symbol::Symbol* name) {
    return sema::scope_lookup_local((sema::Scope*)m.global_scope, name);
}

fn u64 scope_count(module::Module* m) {
    sema::Scope* gs = (sema::Scope*)m.global_scope;
    return gs.count;
}

fn ast::AstNode* mk_fn_decl(arena::Arena* a, symbol::Symbol* name, bool exported, u32 pos) {
    ast::FnDeclNode* n = (ast::FnDeclNode*)arena::alloc(a, sizeof(ast::FnDeclNode));
    sys::memset(n, 0, sizeof(ast::FnDeclNode));
    n.h.kind = ast::AstKind::FnDecl;
    n.h.src_pos = pos;
    n.name = name;
    n.is_exported = exported;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_var_decl2(arena::Arena* a, symbol::Symbol* name, bool exported, bool is_const, u32 pos) {
    ast::VarDeclNode* n = (ast::VarDeclNode*)arena::alloc(a, sizeof(ast::VarDeclNode));
    sys::memset(n, 0, sizeof(ast::VarDeclNode));
    n.h.kind = ast::AstKind::VarDecl;
    n.h.src_pos = pos;
    n.name = name;
    n.is_exported = exported;
    n.is_const = is_const;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_struct_decl(arena::Arena* a, symbol::Symbol* name, bool exported, u32 pos) {
    ast::StructDeclNode* n = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    sys::memset(n, 0, sizeof(ast::StructDeclNode));
    n.h.kind = ast::AstKind::StructDecl;
    n.h.src_pos = pos;
    n.name = name;
    n.is_exported = exported;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_union_decl(arena::Arena* a, symbol::Symbol* name, bool exported, u32 pos) {
    ast::UnionDeclNode* n = (ast::UnionDeclNode*)arena::alloc(a, sizeof(ast::UnionDeclNode));
    sys::memset(n, 0, sizeof(ast::UnionDeclNode));
    n.h.kind = ast::AstKind::UnionDecl;
    n.h.src_pos = pos;
    n.name = name;
    n.is_exported = exported;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_enum_decl(arena::Arena* a, symbol::Symbol* name, bool exported, u32 pos) {
    ast::EnumDeclNode* n = (ast::EnumDeclNode*)arena::alloc(a, sizeof(ast::EnumDeclNode));
    sys::memset(n, 0, sizeof(ast::EnumDeclNode));
    n.h.kind = ast::AstKind::EnumDecl;
    n.h.src_pos = pos;
    n.name = name;
    n.is_exported = exported;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_alias_decl(arena::Arena* a, symbol::Symbol* name, bool exported, u32 pos) {
    ast::AliasDeclNode* n = (ast::AliasDeclNode*)arena::alloc(a, sizeof(ast::AliasDeclNode));
    sys::memset(n, 0, sizeof(ast::AliasDeclNode));
    n.h.kind = ast::AstKind::AliasDecl;
    n.h.src_pos = pos;
    n.name = name;
    n.is_exported = exported;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_import_decl(arena::Arena* a, symbol::Symbol* module_name, bool reexport, u32 pos) {
    ast::ImportNode* n = (ast::ImportNode*)arena::alloc(a, sizeof(ast::ImportNode));
    sys::memset(n, 0, sizeof(ast::ImportNode));
    n.h.kind = ast::AstKind::ImportDecl;
    n.h.src_pos = pos;
    n.module_name = module_name;
    n.is_reexport = reexport;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_extern_fn_decl(arena::Arena* a, symbol::Symbol* name, bool exported, u32 pos) {
    ast::ExternFnDeclNode* n = (ast::ExternFnDeclNode*)arena::alloc(a, sizeof(ast::ExternFnDeclNode));
    sys::memset(n, 0, sizeof(ast::ExternFnDeclNode));
    n.h.kind = ast::AstKind::ExternFnDecl;
    n.h.src_pos = pos;
    n.name = name;
    n.is_exported = exported;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_extern_struct_decl(arena::Arena* a, symbol::Symbol* name, bool exported, u32 pos) {
    ast::ExternStructDeclNode* n = (ast::ExternStructDeclNode*)arena::alloc(a, sizeof(ast::ExternStructDeclNode));
    sys::memset(n, 0, sizeof(ast::ExternStructDeclNode));
    n.h.kind = ast::AstKind::ExternStructDecl;
    n.h.src_pos = pos;
    n.name = name;
    n.is_exported = exported;
    return (ast::AstNode*)n;
}

fn ast::AstNode* mk_extern_block(arena::Arena* a, ast::AstNode** items, u64 count) {
    ast::ExternBlockNode* n = (ast::ExternBlockNode*)arena::alloc(a, sizeof(ast::ExternBlockNode));
    sys::memset(n, 0, sizeof(ast::ExternBlockNode));
    n.h.kind = ast::AstKind::ExternBlock;
    n.items.ptr = items;
    n.items.len = count;
    return (ast::AstNode*)n;
}

fn i32 cn_registers_single_fn(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* foo = fake_sym_interned(mm, "foo");
    ast::AstNode* func = mk_fn_decl(a, foo, true, 3);
    ast::AstNode*[1] stmts;
    stmts[0] = func;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    if(!testing::expect_not_null(mm.global_scope, m)) { return -1; }
    sema::Decl* d = registered(mm, foo);
    if(!testing::expect_not_null((void*)d, m)) { return -2; }
    if(!testing::expect_eq(d.kind, (u16)sema::DeclKind::Node, m)) { return -3; }
    if(!testing::expect_eq(d.is_exported, true, m)) { return -4; }
    if(!testing::expect_eq((void*)d.data.node, (void*)func, m)) { return -5; }
    return 0;
}

fn i32 cn_fn_not_exported(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* foo = fake_sym_interned(mm, "foo");
    ast::AstNode* func = mk_fn_decl(a, foo, false, 0);
    ast::AstNode*[1] stmts;
    stmts[0] = func;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    sema::Decl* d = registered(mm, foo);
    if(!testing::expect_not_null((void*)d, m)) { return -1; }
    if(!testing::expect_eq(d.is_exported, false, m)) { return -2; }
    return 0;
}

fn i32 cn_fn_qualified_name(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* foo = fake_sym_interned(mm, "foo");
    ast::FnDeclNode* func = (ast::FnDeclNode*)mk_fn_decl(a, foo, false, 0);
    ast::AstNode*[1] stmts;
    stmts[0] = (ast::AstNode*)func;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    if(!testing::expect_not_null((void*)func.qualified_name, m)) { return -1; }
    u8[] q = interner::symbol_str(func.qualified_name);
    if(!testing::expect_eq(q, "testmod::foo", m)) { return -2; }
    return 0;
}

fn i32 cn_all_decl_kinds_registered(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* f  = fake_sym_interned(mm, "f");
    symbol::Symbol* st = fake_sym_interned(mm, "S");
    symbol::Symbol* un = fake_sym_interned(mm, "U");
    symbol::Symbol* en = fake_sym_interned(mm, "E");
    symbol::Symbol* al = fake_sym_interned(mm, "A");
    symbol::Symbol* vv = fake_sym_interned(mm, "v");
    ast::AstNode*[6] stmts;
    stmts[0] = mk_fn_decl(a, f, false, 0);
    stmts[1] = mk_struct_decl(a, st, false, 0);
    stmts[2] = mk_union_decl(a, un, false, 0);
    stmts[3] = mk_enum_decl(a, en, false, 0);
    stmts[4] = mk_alias_decl(a, al, false, 0);
    stmts[5] = mk_var_decl2(a, vv, false, false, 0);
    set_root(mm, a, &stmts[0], 6);
    sema::run(mm);
    if(!testing::expect_not_null((void*)registered(mm, f),  m)) { return -1; }
    if(!testing::expect_not_null((void*)registered(mm, st), m)) { return -2; }
    if(!testing::expect_not_null((void*)registered(mm, un), m)) { return -3; }
    if(!testing::expect_not_null((void*)registered(mm, en), m)) { return -4; }
    if(!testing::expect_not_null((void*)registered(mm, al), m)) { return -5; }
    if(!testing::expect_not_null((void*)registered(mm, vv), m)) { return -6; }
    if(!testing::expect_eq(scope_count(mm), 6, m)) { return -7; }
    return 0;
}

fn i32 cn_var_qualified_and_exported(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* g = fake_sym_interned(mm, "g");
    ast::VarDeclNode* v = (ast::VarDeclNode*)mk_var_decl2(a, g, true, true, 0);
    ast::AstNode*[1] stmts;
    stmts[0] = (ast::AstNode*)v;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    sema::Decl* d = registered(mm, g);
    if(!testing::expect_not_null((void*)d, m)) { return -1; }
    if(!testing::expect_eq(d.kind, (u16)sema::DeclKind::Node, m)) { return -2; }
    if(!testing::expect_eq(d.is_exported, true, m)) { return -3; }
    u8[] q = interner::symbol_str(v.qualified_name);
    if(!testing::expect_eq(q, "testmod::g", m)) { return -4; }
    return 0;
}

fn i32 cn_duplicate_one_diag_exact(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* foo = fake_sym_interned(mm, "foo");
    ast::AstNode* fn1 = mk_fn_decl(a, foo, false, 10);
    ast::AstNode* fn2 = mk_fn_decl(a, foo, false, 42);
    ast::AstNode*[2] stmts;
    stmts[0] = fn1;
    stmts[1] = fn2;
    set_root(mm, a, &stmts[0], 2);
    sema::run(mm);
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "duplicate declaration of foo", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 42, m)) { return -3; }
    if(!testing::expect_eq(mm.diag.entries[0].is_warning, false, m)) { return -4; }
    sema::Decl* d = registered(mm, foo);
    if(!testing::expect_eq((void*)d.data.node, (void*)fn1, m)) { return -5; }
    if(!testing::expect_eq(scope_count(mm), 1, m)) { return -6; }
    return 0;
}

fn i32 cn_two_distinct_no_diag(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* foo = fake_sym_interned(mm, "foo");
    symbol::Symbol* bar = fake_sym_interned(mm, "bar");
    ast::AstNode*[2] stmts;
    stmts[0] = mk_fn_decl(a, foo, false, 0);
    stmts[1] = mk_fn_decl(a, bar, false, 0);
    set_root(mm, a, &stmts[0], 2);
    sema::run(mm);
    if(!testing::expect_eq(mm.diag.entries.len, 0, m)) { return -1; }
    if(!testing::expect_eq(scope_count(mm), 2, m)) { return -2; }
    return 0;
}

fn i32 cn_import_resolves_module(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    module::Module* target = fresh_module(a);        // shares the one global interner with mm
    target.name = interner::intern("io");
    module::Module*[1] imps;
    imps[0] = target;
    mm.imports.ptr = &imps[0];
    mm.imports.len = 1;
    symbol::Symbol* io = fake_sym_interned(mm, "io");
    ast::AstNode* imp = mk_import_decl(a, io, false, 0);
    ast::AstNode*[1] stmts;
    stmts[0] = imp;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    sema::Decl* d = registered(mm, io);
    if(!testing::expect_not_null((void*)d, m)) { return -1; }
    if(!testing::expect_eq(d.kind, (u16)sema::DeclKind::Import, m)) { return -2; }
    if(!testing::expect_eq((void*)d.data.module, (void*)target, m)) { return -3; }
    return 0;
}

fn i32 cn_import_reexport_no_match(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* io = fake_sym_interned(mm, "io");
    ast::AstNode* imp = mk_import_decl(a, io, true, 0);
    ast::AstNode*[1] stmts;
    stmts[0] = imp;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    sema::Decl* d = registered(mm, io);
    if(!testing::expect_not_null((void*)d, m)) { return -1; }
    if(!testing::expect_eq(d.kind, (u16)sema::DeclKind::Import, m)) { return -2; }
    if(!testing::expect_eq(d.is_exported, true, m)) { return -3; }
    if(!testing::expect_eq((void*)d.data.module, (void*)null, m)) { return -4; }
    return 0;
}

fn i32 cn_extern_block_items_registered(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* malloc_s = fake_sym_interned(mm, "malloc");
    symbol::Symbol* file_s   = fake_sym_interned(mm, "FILE");
    ast::AstNode* efn    = mk_extern_fn_decl(a, malloc_s, false, 0);
    ast::AstNode* estruct = mk_extern_struct_decl(a, file_s, false, 0);
    ast::AstNode*[2] items;
    items[0] = efn;
    items[1] = estruct;
    ast::AstNode* eblock = mk_extern_block(a, &items[0], 2);
    ast::AstNode*[1] stmts;
    stmts[0] = eblock;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    sema::Decl* dm = registered(mm, malloc_s);
    sema::Decl* df = registered(mm, file_s);
    if(!testing::expect_not_null((void*)dm, m)) { return -1; }
    if(!testing::expect_eq(dm.kind, (u16)sema::DeclKind::Node, m)) { return -2; }
    if(!testing::expect_eq((void*)dm.data.node, (void*)efn, m)) { return -3; }
    if(!testing::expect_not_null((void*)df, m)) { return -4; }
    if(!testing::expect_eq((void*)df.data.node, (void*)estruct, m)) { return -5; }
    return 0;
}

fn i32 cn_extern_var_qualified(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* errno_s = fake_sym_interned(mm, "errno");
    ast::VarDeclNode* v = (ast::VarDeclNode*)mk_var_decl2(a, errno_s, false, false, 0);
    ast::AstNode*[1] items;
    items[0] = (ast::AstNode*)v;
    ast::AstNode* eblock = mk_extern_block(a, &items[0], 1);
    ast::AstNode*[1] stmts;
    stmts[0] = eblock;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    if(!testing::expect_not_null((void*)registered(mm, errno_s), m)) { return -1; }
    if(!testing::expect_not_null((void*)v.qualified_name, m)) { return -2; }
    u8[] q = interner::symbol_str(v.qualified_name);
    if(!testing::expect_eq(q, "testmod::errno", m)) { return -3; }
    return 0;
}

fn i32 cn_sets_names_phase(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    set_root(mm, a, null, 0);
    sema::run(mm);
    if(!testing::expect_eq((mm.sema_phase & (u16)sema::SemaPhase::Names) != 0, true, m)) { return -1; }
    return 0;
}

fn i32 cn_null_root_no_crash(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    mm.root_node = null;
    sema::run(mm);
    if(!testing::expect_not_null(mm.global_scope, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, 0, m)) { return -2; }
    return 0;
}

fn i32 cn_empty_block_no_decls(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    set_root(mm, a, null, 0);
    sema::run(mm);
    if(!testing::expect_not_null(mm.global_scope, m)) { return -1; }
    if(!testing::expect_eq(scope_count(mm), 0, m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries.len, 0, m)) { return -3; }
    return 0;
}

fn i32 cn_idempotent_second_run(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* foo = fake_sym_interned(mm, "foo");
    ast::AstNode*[1] stmts;
    stmts[0] = mk_fn_decl(a, foo, false, 0);
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    u64 count_after_first = scope_count(mm);
    u64 diags_after_first = mm.diag.entries.len;
    sema::run(mm);
    if(!testing::expect_eq(scope_count(mm), count_after_first, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries.len, diags_after_first, m)) { return -2; }
    if(!testing::expect_eq(count_after_first, 1, m)) { return -3; }
    return 0;
}

fn i32 cn_non_decl_skipped(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* foo = fake_sym_interned(mm, "foo");
    ast::IntLitNode* lit = fake_int_lit(a, 5, 0);
    ast::AstNode*[2] stmts;
    stmts[0] = (ast::AstNode*)lit;
    stmts[1] = mk_fn_decl(a, foo, false, 0);
    set_root(mm, a, &stmts[0], 2);
    sema::run(mm);
    if(!testing::expect_not_null((void*)registered(mm, foo), m)) { return -1; }
    if(!testing::expect_eq(scope_count(mm), 1, m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries.len, 0, m)) { return -3; }
    return 0;
}

fn i32 cn_combined_mixed(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* st = fake_sym_interned(mm, "S");
    symbol::Symbol* func_sym = fake_sym_interned(mm, "run");
    symbol::Symbol* g  = fake_sym_interned(mm, "g");
    ast::AstNode*[4] stmts;
    stmts[0] = mk_struct_decl(a, st, true, 0);
    stmts[1] = mk_fn_decl(a, func_sym, false, 0);
    stmts[2] = mk_var_decl2(a, g, false, true, 5);
    stmts[3] = mk_var_decl2(a, g, false, true, 30);
    set_root(mm, a, &stmts[0], 4);
    sema::run(mm);
    sema::Decl* ds  = registered(mm, st);
    sema::Decl* dfn = registered(mm, func_sym);
    if(!testing::expect_eq(ds.is_exported, true, m)) { return -1; }
    if(!testing::expect_eq(dfn.is_exported, false, m)) { return -2; }
    if(!testing::expect_not_null((void*)registered(mm, g), m)) { return -3; }
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -4; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 30, m)) { return -5; }
    if(!testing::expect_eq(scope_count(mm), 3, m)) { return -6; }
    return 0;
}


// ============================================================================
// Entry
// ============================================================================

// ---- type-expression node builders (for signature resolution) ----
fn ast::AstNode* mk_ty_prim(arena::Arena* a, token::TokenKind kind) {
    ast::TypePrimitiveNode* node = (ast::TypePrimitiveNode*)arena::alloc(a, sizeof(ast::TypePrimitiveNode));
    sys::memset(node, 0, sizeof(ast::TypePrimitiveNode));
    node.h.kind = ast::AstKind::PrimitiveType;
    node.kind = kind;
    return (ast::AstNode*)node;
}

fn ast::AstNode* mk_ty_ptr(arena::Arena* a, ast::AstNode* pointee, bool is_const) {
    ast::TypePointerNode* node = (ast::TypePointerNode*)arena::alloc(a, sizeof(ast::TypePointerNode));
    sys::memset(node, 0, sizeof(ast::TypePointerNode));
    node.h.kind = ast::AstKind::PointerType;
    node.pointee = pointee;
    node.is_const = is_const;
    return (ast::AstNode*)node;
}

fn ast::AstNode* mk_ty_slice(arena::Arena* a, ast::AstNode* element) {
    ast::TypeSliceNode* node = (ast::TypeSliceNode*)arena::alloc(a, sizeof(ast::TypeSliceNode));
    sys::memset(node, 0, sizeof(ast::TypeSliceNode));
    node.h.kind = ast::AstKind::SliceType;
    node.element = element;
    return (ast::AstNode*)node;
}

fn ast::AstNode* mk_int_lit_node(arena::Arena* a, u64 value) {
    ast::IntLitNode* node = (ast::IntLitNode*)arena::alloc(a, sizeof(ast::IntLitNode));
    sys::memset(node, 0, sizeof(ast::IntLitNode));
    node.h.kind = ast::AstKind::IntLit;
    node.value = value;
    return (ast::AstNode*)node;
}

fn ast::AstNode* mk_ty_array(arena::Arena* a, ast::AstNode* element, ast::AstNode* size_expr) {
    ast::TypeArrayNode* node = (ast::TypeArrayNode*)arena::alloc(a, sizeof(ast::TypeArrayNode));
    sys::memset(node, 0, sizeof(ast::TypeArrayNode));
    node.h.kind = ast::AstKind::ArrayType;
    node.element = element;
    node.size_expr = size_expr;
    return (ast::AstNode*)node;
}

fn ast::AstNode*[] mk_texprs1(arena::Arena* a, ast::AstNode* t0) {
    ast::AstNode** mem = (ast::AstNode**)arena::alloc(a, sizeof(ast::AstNode*));
    mem[0] = t0;
    ast::AstNode*[] out = {mem, 1};
    return out;
}

fn ast::AstNode*[] mk_texprs2(arena::Arena* a, ast::AstNode* t0, ast::AstNode* t1) {
    ast::AstNode** mem = (ast::AstNode**)arena::alloc(a, sizeof(ast::AstNode*) * 2);
    mem[0] = t0; mem[1] = t1;
    ast::AstNode*[] out = {mem, 2};
    return out;
}

fn ast::AstNode* mk_ty_fnptr(arena::Arena* a, ast::AstNode* return_type, ast::AstNode*[] param_types) {
    ast::TypeFnPtrNode* node = (ast::TypeFnPtrNode*)arena::alloc(a, sizeof(ast::TypeFnPtrNode));
    sys::memset(node, 0, sizeof(ast::TypeFnPtrNode));
    node.h.kind = ast::AstKind::FnPtrType;
    node.return_type = return_type;
    node.param_types = param_types;
    return (ast::AstNode*)node;
}

fn ast::AstNode* mk_var_typed(arena::Arena* a, symbol::Symbol* name, ast::AstNode* type_expr) {
    ast::AstNode* var = mk_var_decl2(a, name, false, false, 0);
    ((ast::VarDeclNode*)var).type_expr = type_expr;
    return var;
}

fn ast::AstNode* mk_fn_sig(arena::Arena* a, symbol::Symbol* name, ast::AstNode* return_type, ast::AstNode*[] param_type_exprs) {
    ast::FnDeclNode* node = (ast::FnDeclNode*)arena::alloc(a, sizeof(ast::FnDeclNode));
    sys::memset(node, 0, sizeof(ast::FnDeclNode));
    node.h.kind = ast::AstKind::FnDecl;
    node.name = name;
    node.return_type = return_type;
    if(param_type_exprs.len > 0) {
        ast::Param* params = (ast::Param*)arena::alloc(a, param_type_exprs.len * sizeof(ast::Param));
        sys::memset(params, 0, param_type_exprs.len * sizeof(ast::Param));
        for(u64 param_index = 0; param_index < param_type_exprs.len; param_index += 1) {
            params[param_index].type_expr = param_type_exprs[param_index];
        }
        node.params = {params, param_type_exprs.len};
    }
    return (ast::AstNode*)node;
}

fn ast::AstNode* mk_struct_sig(arena::Arena* a, symbol::Symbol* name, ast::AstNode*[] field_type_exprs) {
    ast::StructDeclNode* node = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    sys::memset(node, 0, sizeof(ast::StructDeclNode));
    node.h.kind = ast::AstKind::StructDecl;
    node.name = name;
    if(field_type_exprs.len > 0) {
        ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, field_type_exprs.len * sizeof(ast::FieldDecl));
        sys::memset(fields, 0, field_type_exprs.len * sizeof(ast::FieldDecl));
        for(u64 field_index = 0; field_index < field_type_exprs.len; field_index += 1) {
            fields[field_index].type_expr = field_type_exprs[field_index];
        }
        node.fields = {fields, field_type_exprs.len};
    }
    return (ast::AstNode*)node;
}

// ---- signature resolution tests ----
fn i32 rs_var_primitive(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* x = fake_sym_interned(mm, "x");
    ast::AstNode* var = mk_var_typed(a, x, mk_ty_prim(a, token::TokenKind::I32));
    ast::AstNode*[1] stmts; stmts[0] = var;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    sema::Decl* d = registered(mm, x);
    if(!testing::expect_not_null((void*)d, m)) { return -1; }
    if(!testing::expect_eq((void*)d.ty, (void*)types::prim_i32(), m)) { return -2; }
    return 0;
}

fn i32 rs_var_pointer(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* p = fake_sym_interned(mm, "p");
    ast::AstNode* var = mk_var_typed(a, p, mk_ty_ptr(a, mk_ty_prim(a, token::TokenKind::I32), false));
    ast::AstNode*[1] stmts; stmts[0] = var;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    sema::Decl* d = registered(mm, p);
    if(!testing::expect_not_null((void*)d, m)) { return -1; }
    if(!testing::expect_eq((u64)d.ty.kind, (u64)types::TypeKind::Pointer, m)) { return -2; }
    if(!testing::expect_eq((void*)d.ty.data.pointee, (void*)types::prim_i32(), m)) { return -3; }
    return 0;
}

fn i32 rs_var_const_pointer(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* p = fake_sym_interned(mm, "p");
    ast::AstNode* var = mk_var_typed(a, p, mk_ty_ptr(a, mk_ty_prim(a, token::TokenKind::I32), true));
    ast::AstNode*[1] stmts; stmts[0] = var;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    sema::Decl* d = registered(mm, p);
    bool is_const = ((u8)d.ty.flags & (u8)types::LayoutFlags::Const) != 0;
    if(!testing::expect_true(is_const, m)) { return -1; }
    return 0;
}

fn i32 rs_var_slice(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* s = fake_sym_interned(mm, "s");
    ast::AstNode* var = mk_var_typed(a, s, mk_ty_slice(a, mk_ty_prim(a, token::TokenKind::U8)));
    ast::AstNode*[1] stmts; stmts[0] = var;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    sema::Decl* d = registered(mm, s);
    if(!testing::expect_eq((u64)d.ty.kind, (u64)types::TypeKind::Slice, m)) { return -1; }
    if(!testing::expect_eq((void*)d.ty.data.slice_elem, (void*)types::prim_u8(), m)) { return -2; }
    return 0;
}

fn i32 rs_var_array(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* arr = fake_sym_interned(mm, "arr");
    ast::AstNode* elem = mk_ty_prim(a, token::TokenKind::I32);
    ast::AstNode* var = mk_var_typed(a, arr, mk_ty_array(a, elem, mk_int_lit_node(a, 4)));
    ast::AstNode*[1] stmts; stmts[0] = var;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    sema::Decl* d = registered(mm, arr);
    if(!testing::expect_eq((u64)d.ty.kind, (u64)types::TypeKind::Array, m)) { return -1; }
    if(!testing::expect_eq(d.ty.data.array.count, (u64)4, m)) { return -2; }
    if(!testing::expect_eq((void*)d.ty.data.array.elem, (void*)types::prim_i32(), m)) { return -3; }
    return 0;
}

fn i32 rs_var_identity(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* p = fake_sym_interned(mm, "p");
    symbol::Symbol* q = fake_sym_interned(mm, "q");
    ast::AstNode* vp = mk_var_typed(a, p, mk_ty_ptr(a, mk_ty_prim(a, token::TokenKind::I32), false));
    ast::AstNode* vq = mk_var_typed(a, q, mk_ty_ptr(a, mk_ty_prim(a, token::TokenKind::I32), false));
    ast::AstNode*[2] stmts; stmts[0] = vp; stmts[1] = vq;
    set_root(mm, a, &stmts[0], 2);
    sema::run(mm);
    if(!testing::expect_eq((void*)registered(mm, p).ty, (void*)registered(mm, q).ty, m)) { return -1; }
    return 0;
}

fn i32 rs_fn_void_no_params(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* foo = fake_sym_interned(mm, "foo");
    ast::AstNode*[] no_params = {null, 0};
    ast::AstNode* func = mk_fn_sig(a, foo, null, no_params);
    ast::AstNode*[1] stmts; stmts[0] = func;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    sema::Decl* d = registered(mm, foo);
    if(!testing::expect_eq((u64)d.ty.kind, (u64)types::TypeKind::FnPtr, m)) { return -1; }
    if(!testing::expect_eq((void*)d.ty.data.fn_ptr.ret, (void*)types::prim_void(), m)) { return -2; }
    if(!testing::expect_eq(d.ty.data.fn_ptr.params.len, (u64)0, m)) { return -3; }
    return 0;
}

fn i32 rs_fn_return_and_params(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* foo = fake_sym_interned(mm, "foo");
    ast::AstNode*[] param_types = mk_texprs2(a, mk_ty_prim(a, token::TokenKind::I32), mk_ty_ptr(a, mk_ty_prim(a, token::TokenKind::U8), false));
    ast::AstNode* func = mk_fn_sig(a, foo, mk_ty_prim(a, token::TokenKind::I32), param_types);
    ast::AstNode*[1] stmts; stmts[0] = func;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    sema::Decl* d = registered(mm, foo);
    if(!testing::expect_eq((void*)d.ty.data.fn_ptr.ret, (void*)types::prim_i32(), m)) { return -1; }
    if(!testing::expect_eq(d.ty.data.fn_ptr.params.len, (u64)2, m)) { return -2; }
    if(!testing::expect_eq((void*)d.ty.data.fn_ptr.params[0], (void*)types::prim_i32(), m)) { return -3; }
    ast::FnDeclNode* fn_node = (ast::FnDeclNode*)func;
    if(!testing::expect_eq((void*)fn_node.params[0].resolved_type, (void*)types::prim_i32(), m)) { return -4; }
    return 0;
}

fn i32 rs_struct_fields(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* point = fake_sym_interned(mm, "Point");
    ast::AstNode*[] field_types = mk_texprs2(a, mk_ty_prim(a, token::TokenKind::I8), mk_ty_prim(a, token::TokenKind::I32));
    ast::AstNode* struct_decl = mk_struct_sig(a, point, field_types);
    ast::AstNode*[1] stmts; stmts[0] = struct_decl;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    sema::Decl* d = registered(mm, point);
    if(!testing::expect_eq((u64)d.ty.kind, (u64)types::TypeKind::Struct, m)) { return -1; }
    ast::StructDeclNode* struct_node = (ast::StructDeclNode*)struct_decl;
    if(!testing::expect_eq((void*)struct_node.fields[0].resolved_type, (void*)types::prim_i8(), m)) { return -2; }
    if(!testing::expect_eq((void*)struct_node.fields[1].resolved_type, (void*)types::prim_i32(), m)) { return -3; }
    return 0;
}

fn i32 rs_enum_base(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* color = fake_sym_interned(mm, "Color");
    ast::AstNode* enum_decl = mk_enum_decl(a, color, false, 0);
    ((ast::EnumDeclNode*)enum_decl).base_type = mk_ty_prim(a, token::TokenKind::U8);
    ast::AstNode*[1] stmts; stmts[0] = enum_decl;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    sema::Decl* d = registered(mm, color);
    if(!testing::expect_eq((u64)d.ty.kind, (u64)types::TypeKind::Enum, m)) { return -1; }
    if(!testing::expect_eq((void*)((ast::EnumDeclNode*)enum_decl).base_type.h.ty, (void*)types::prim_u8(), m)) { return -2; }
    return 0;
}

fn i32 rs_alias_dissolves(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* my_int = fake_sym_interned(mm, "MyInt");
    ast::AstNode* alias_decl = mk_alias_decl(a, my_int, false, 0);
    ((ast::AliasDeclNode*)alias_decl).target = mk_ty_ptr(a, mk_ty_prim(a, token::TokenKind::I32), false);
    ast::AstNode*[1] stmts; stmts[0] = alias_decl;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    sema::Decl* d = registered(mm, my_int);
    if(!testing::expect_eq((u64)d.ty.kind, (u64)types::TypeKind::Pointer, m)) { return -1; }
    if(!testing::expect_eq((void*)d.ty.data.pointee, (void*)types::prim_i32(), m)) { return -2; }
    return 0;
}

fn i32 rs_sets_signatures_phase(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* x = fake_sym_interned(mm, "x");
    ast::AstNode* var = mk_var_typed(a, x, mk_ty_prim(a, token::TokenKind::I32));
    ast::AstNode*[1] stmts; stmts[0] = var;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    bool has_signatures = (mm.sema_phase & (u16)sema::SemaPhase::Signatures) != 0;
    if(!testing::expect_true(has_signatures, m)) { return -1; }
    return 0;
}

// ---- named-type resolution tests ----
fn ast::AstNode* mk_ty_named(arena::Arena* a, symbol::Symbol* namespace, symbol::Symbol* name) {
    ast::TypeNamedNode* node = (ast::TypeNamedNode*)arena::alloc(a, sizeof(ast::TypeNamedNode));
    sys::memset(node, 0, sizeof(ast::TypeNamedNode));
    node.h.kind = ast::AstKind::NamedType;
    node.namespace = namespace;
    node.name = name;
    return (ast::AstNode*)node;
}

fn ast::AstNode* mk_alias_typed(arena::Arena* a, symbol::Symbol* name, ast::AstNode* target, u32 pos) {
    ast::AstNode* alias = mk_alias_decl(a, name, false, pos);
    ((ast::AliasDeclNode*)alias).target = target;
    return alias;
}

fn i32 rnt_named_struct(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* foo = fake_sym_interned(mm, "Foo");
    symbol::Symbol* x = fake_sym_interned(mm, "x");
    ast::AstNode* struct_decl = mk_struct_sig(a, foo, mk_texprs1(a, mk_ty_prim(a, token::TokenKind::I32)));
    ast::AstNode* var = mk_var_typed(a, x, mk_ty_named(a, null, foo));
    ast::AstNode*[2] stmts; stmts[0] = struct_decl; stmts[1] = var;
    set_root(mm, a, &stmts[0], 2);
    sema::run(mm);
    sema::Decl* dx = registered(mm, x);
    if(!testing::expect_eq((u64)dx.ty.kind, (u64)types::TypeKind::Struct, m)) { return -1; }
    if(!testing::expect_eq((void*)sema::container_decl(dx.ty), (void*)struct_decl, m)) { return -2; }
    return 0;
}

fn i32 rnt_named_enum(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* color = fake_sym_interned(mm, "Color");
    symbol::Symbol* c = fake_sym_interned(mm, "c");
    ast::AstNode* enum_decl = mk_enum_decl(a, color, false, 0);
    ast::AstNode* var = mk_var_typed(a, c, mk_ty_named(a, null, color));
    ast::AstNode*[2] stmts; stmts[0] = enum_decl; stmts[1] = var;
    set_root(mm, a, &stmts[0], 2);
    sema::run(mm);
    if(!testing::expect_eq((u64)registered(mm, c).ty.kind, (u64)types::TypeKind::Enum, m)) { return -1; }
    return 0;
}

fn i32 rnt_named_union(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* u = fake_sym_interned(mm, "U");
    symbol::Symbol* v = fake_sym_interned(mm, "v");
    ast::AstNode* union_decl = mk_union_decl(a, u, false, 0);
    ast::AstNode* var = mk_var_typed(a, v, mk_ty_named(a, null, u));
    ast::AstNode*[2] stmts; stmts[0] = union_decl; stmts[1] = var;
    set_root(mm, a, &stmts[0], 2);
    sema::run(mm);
    if(!testing::expect_eq((u64)registered(mm, v).ty.kind, (u64)types::TypeKind::Union, m)) { return -1; }
    return 0;
}

fn i32 rnt_named_in_pointer(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* foo = fake_sym_interned(mm, "Foo");
    symbol::Symbol* p = fake_sym_interned(mm, "p");
    ast::AstNode* struct_decl = mk_struct_sig(a, foo, mk_texprs1(a, mk_ty_prim(a, token::TokenKind::I32)));
    ast::AstNode* var = mk_var_typed(a, p, mk_ty_ptr(a, mk_ty_named(a, null, foo), false));
    ast::AstNode*[2] stmts; stmts[0] = struct_decl; stmts[1] = var;
    set_root(mm, a, &stmts[0], 2);
    sema::run(mm);
    sema::Decl* dp = registered(mm, p);
    if(!testing::expect_eq((u64)dp.ty.kind, (u64)types::TypeKind::Pointer, m)) { return -1; }
    if(!testing::expect_eq((u64)dp.ty.data.pointee.kind, (u64)types::TypeKind::Struct, m)) { return -2; }
    return 0;
}

fn i32 rnt_named_in_slice(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* foo = fake_sym_interned(mm, "Foo");
    symbol::Symbol* s = fake_sym_interned(mm, "s");
    ast::AstNode* struct_decl = mk_struct_sig(a, foo, mk_texprs1(a, mk_ty_prim(a, token::TokenKind::I32)));
    ast::AstNode* var = mk_var_typed(a, s, mk_ty_slice(a, mk_ty_named(a, null, foo)));
    ast::AstNode*[2] stmts; stmts[0] = struct_decl; stmts[1] = var;
    set_root(mm, a, &stmts[0], 2);
    sema::run(mm);
    if(!testing::expect_eq((u64)registered(mm, s).ty.kind, (u64)types::TypeKind::Slice, m)) { return -1; }
    return 0;
}

fn i32 rnt_named_as_field(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* foo = fake_sym_interned(mm, "Foo");
    symbol::Symbol* bar = fake_sym_interned(mm, "Bar");
    ast::AstNode* foo_decl = mk_struct_sig(a, foo, mk_texprs1(a, mk_ty_prim(a, token::TokenKind::I32)));
    ast::AstNode* bar_decl = mk_struct_sig(a, bar, mk_texprs1(a, mk_ty_named(a, null, foo)));
    ast::AstNode*[2] stmts; stmts[0] = foo_decl; stmts[1] = bar_decl;
    set_root(mm, a, &stmts[0], 2);
    sema::run(mm);
    ast::StructDeclNode* bar_node = (ast::StructDeclNode*)bar_decl;
    types::Type* field_type = (types::Type*)bar_node.fields[0].resolved_type;
    if(!testing::expect_eq((u64)field_type.kind, (u64)types::TypeKind::Struct, m)) { return -1; }
    if(!testing::expect_eq((void*)sema::container_decl(field_type), (void*)foo_decl, m)) { return -2; }
    return 0;
}

fn i32 rnt_alias_to_primitive(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* id = fake_sym_interned(mm, "Id");
    symbol::Symbol* x = fake_sym_interned(mm, "x");
    ast::AstNode* alias = mk_alias_typed(a, id, mk_ty_prim(a, token::TokenKind::I32), 0);
    ast::AstNode* var = mk_var_typed(a, x, mk_ty_named(a, null, id));
    ast::AstNode*[2] stmts; stmts[0] = alias; stmts[1] = var;
    set_root(mm, a, &stmts[0], 2);
    sema::run(mm);
    if(!testing::expect_eq((void*)registered(mm, x).ty, (void*)types::prim_i32(), m)) { return -1; }
    return 0;
}

fn i32 rnt_alias_to_pointer(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* p = fake_sym_interned(mm, "P");
    symbol::Symbol* x = fake_sym_interned(mm, "x");
    ast::AstNode* alias = mk_alias_typed(a, p, mk_ty_ptr(a, mk_ty_prim(a, token::TokenKind::I32), false), 0);
    ast::AstNode* var = mk_var_typed(a, x, mk_ty_named(a, null, p));
    ast::AstNode*[2] stmts; stmts[0] = alias; stmts[1] = var;
    set_root(mm, a, &stmts[0], 2);
    sema::run(mm);
    sema::Decl* dx = registered(mm, x);
    if(!testing::expect_eq((u64)dx.ty.kind, (u64)types::TypeKind::Pointer, m)) { return -1; }
    if(!testing::expect_eq((void*)dx.ty.data.pointee, (void*)types::prim_i32(), m)) { return -2; }
    return 0;
}

fn i32 rnt_alias_to_named(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* foo = fake_sym_interned(mm, "Foo");
    symbol::Symbol* b = fake_sym_interned(mm, "B");
    symbol::Symbol* x = fake_sym_interned(mm, "x");
    ast::AstNode* struct_decl = mk_struct_sig(a, foo, mk_texprs1(a, mk_ty_prim(a, token::TokenKind::I32)));
    ast::AstNode* alias = mk_alias_typed(a, b, mk_ty_named(a, null, foo), 0);
    ast::AstNode* var = mk_var_typed(a, x, mk_ty_named(a, null, b));
    ast::AstNode*[3] stmts; stmts[0] = struct_decl; stmts[1] = alias; stmts[2] = var;
    set_root(mm, a, &stmts[0], 3);
    sema::run(mm);
    if(!testing::expect_eq((void*)sema::container_decl(registered(mm, x).ty), (void*)struct_decl, m)) { return -1; }
    return 0;
}

fn i32 rnt_alias_chain(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* first = fake_sym_interned(mm, "A");
    symbol::Symbol* second = fake_sym_interned(mm, "B");
    symbol::Symbol* x = fake_sym_interned(mm, "x");
    ast::AstNode* alias_a = mk_alias_typed(a, first, mk_ty_prim(a, token::TokenKind::I32), 0);
    ast::AstNode* alias_b = mk_alias_typed(a, second, mk_ty_named(a, null, first), 0);
    ast::AstNode* var = mk_var_typed(a, x, mk_ty_named(a, null, second));
    ast::AstNode*[3] stmts; stmts[0] = alias_a; stmts[1] = alias_b; stmts[2] = var;
    set_root(mm, a, &stmts[0], 3);
    sema::run(mm);
    if(!testing::expect_eq((void*)registered(mm, x).ty, (void*)types::prim_i32(), m)) { return -1; }
    return 0;
}

fn i32 rnt_alias_cycle_reports(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* first = fake_sym_interned(mm, "A");
    symbol::Symbol* second = fake_sym_interned(mm, "B");
    ast::AstNode* alias_a = mk_alias_typed(a, first, mk_ty_named(a, null, second), 0);
    ast::AstNode* alias_b = mk_alias_typed(a, second, mk_ty_named(a, null, first), 42);
    ast::AstNode*[2] stmts; stmts[0] = alias_a; stmts[1] = alias_b;
    set_root(mm, a, &stmts[0], 2);
    sema::run(mm);
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "circular type resolution", m)) { return -2; }
    return 0;
}

fn i32 rnt_unknown_name_reports(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* missing = fake_sym_interned(mm, "Missing");
    symbol::Symbol* x = fake_sym_interned(mm, "x");
    ast::AstNode* var = mk_var_typed(a, x, mk_ty_named(a, null, missing));
    ast::AstNode*[1] stmts; stmts[0] = var;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    if(!testing::expect_eq(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "unknown type", m)) { return -2; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "Missing", m)) { return -3; }
    if(!testing::expect_eq((void*)registered(mm, x).ty, null, m)) { return -4; }
    return 0;
}

fn i32 rnt_order_independent(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* foo = fake_sym_interned(mm, "Foo");
    symbol::Symbol* x = fake_sym_interned(mm, "x");
    ast::AstNode* var = mk_var_typed(a, x, mk_ty_named(a, null, foo));
    ast::AstNode* struct_decl = mk_struct_sig(a, foo, mk_texprs1(a, mk_ty_prim(a, token::TokenKind::I32)));
    ast::AstNode*[2] stmts; stmts[0] = var; stmts[1] = struct_decl;
    set_root(mm, a, &stmts[0], 2);
    sema::run(mm);
    if(!testing::expect_eq((void*)sema::container_decl(registered(mm, x).ty), (void*)struct_decl, m)) { return -1; }
    return 0;
}

fn i32 rnt_identity(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* foo = fake_sym_interned(mm, "Foo");
    symbol::Symbol* x = fake_sym_interned(mm, "x");
    symbol::Symbol* y = fake_sym_interned(mm, "y");
    ast::AstNode* struct_decl = mk_struct_sig(a, foo, mk_texprs1(a, mk_ty_prim(a, token::TokenKind::I32)));
    ast::AstNode* vx = mk_var_typed(a, x, mk_ty_named(a, null, foo));
    ast::AstNode* vy = mk_var_typed(a, y, mk_ty_named(a, null, foo));
    ast::AstNode*[3] stmts; stmts[0] = struct_decl; stmts[1] = vx; stmts[2] = vy;
    set_root(mm, a, &stmts[0], 3);
    sema::run(mm);
    if(!testing::expect_eq((void*)registered(mm, x).ty, (void*)registered(mm, y).ty, m)) { return -1; }
    return 0;
}

fn i32 rnt_cross_module_struct(arena::Arena* a, u8[] m) {
    interner::init(a, 16);
    types::typer_init(a, 16);
    module::Module* other = fresh_module(a);
    other.name = interner::intern("other");
    mutex::create(&other.sema_mutex);
    symbol::Symbol* foo = interner::intern("Foo");
    ast::AstNode* struct_decl = mk_struct_sig(a, foo, mk_texprs1(a, mk_ty_prim(a, token::TokenKind::I32)));
    ((ast::StructDeclNode*)struct_decl).is_exported = true;
    ast::AstNode*[1] other_stmts; other_stmts[0] = struct_decl;
    set_root(other, a, &other_stmts[0], 1);
    sema::run(other);

    module::Module* main_mod = fresh_module(a);
    main_mod.name = interner::intern("main");
    mutex::create(&main_mod.sema_mutex);
    module::Module*[1] imports; imports[0] = other;
    main_mod.imports.ptr = &imports[0];
    main_mod.imports.len = 1;
    symbol::Symbol* other_name = interner::intern("other");
    symbol::Symbol* x = interner::intern("x");
    ast::AstNode* imp = mk_import_decl(a, other_name, false, 0);
    ast::AstNode* var = mk_var_typed(a, x, mk_ty_named(a, other_name, foo));
    ast::AstNode*[2] main_stmts; main_stmts[0] = imp; main_stmts[1] = var;
    set_root(main_mod, a, &main_stmts[0], 2);
    sema::run(main_mod);
    sema::Decl* dx = registered(main_mod, x);
    if(!testing::expect_not_null((void*)dx, m)) { return -1; }
    if(!testing::expect_eq((u64)dx.ty.kind, (u64)types::TypeKind::Struct, m)) { return -2; }
    if(!testing::expect_eq((void*)sema::container_decl(dx.ty), (void*)struct_decl, m)) { return -3; }
    return 0;
}

fn i32 rnt_cross_module_not_exported_reports(arena::Arena* a, u8[] m) {
    interner::init(a, 16);
    types::typer_init(a, 16);
    module::Module* other = fresh_module(a);
    other.name = interner::intern("other");
    mutex::create(&other.sema_mutex);
    symbol::Symbol* foo = interner::intern("Foo");
    ast::AstNode* struct_decl = mk_struct_sig(a, foo, mk_texprs1(a, mk_ty_prim(a, token::TokenKind::I32)));
    ast::AstNode*[1] other_stmts; other_stmts[0] = struct_decl;
    set_root(other, a, &other_stmts[0], 1);
    sema::run(other);

    module::Module* main_mod = fresh_module(a);
    main_mod.name = interner::intern("main");
    mutex::create(&main_mod.sema_mutex);
    module::Module*[1] imports; imports[0] = other;
    main_mod.imports.ptr = &imports[0];
    main_mod.imports.len = 1;
    symbol::Symbol* other_name = interner::intern("other");
    symbol::Symbol* x = interner::intern("x");
    ast::AstNode* imp = mk_import_decl(a, other_name, false, 0);
    ast::AstNode* var = mk_var_typed(a, x, mk_ty_named(a, other_name, foo));
    ast::AstNode*[2] main_stmts; main_stmts[0] = imp; main_stmts[1] = var;
    set_root(main_mod, a, &main_stmts[0], 2);
    sema::run(main_mod);
    if(!testing::expect_ge(main_mod.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq((void*)registered(main_mod, x).ty, null, m)) { return -2; }
    return 0;
}

fn i32 rnt_non_type_used_as_type(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* v = fake_sym_interned(mm, "v");
    symbol::Symbol* x = fake_sym_interned(mm, "x");
    ast::AstNode* var_v = mk_var_typed(a, v, mk_ty_prim(a, token::TokenKind::I32));
    ast::AstNode* var_x = mk_var_typed(a, x, mk_ty_named(a, null, v));
    ast::AstNode*[2] stmts; stmts[0] = var_v; stmts[1] = var_x;
    set_root(mm, a, &stmts[0], 2);
    sema::run(mm);
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "unknown type", m)) { return -2; }
    if(!testing::expect_eq((void*)registered(mm, x).ty, null, m)) { return -3; }
    return 0;
}

fn i32 rnt_qualified_namespace_not_imported(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* nomod = fake_sym_interned(mm, "NoMod");
    symbol::Symbol* foo = fake_sym_interned(mm, "Foo");
    symbol::Symbol* x = fake_sym_interned(mm, "x");
    ast::AstNode* var = mk_var_typed(a, x, mk_ty_named(a, nomod, foo));
    ast::AstNode*[1] stmts; stmts[0] = var;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "unknown type", m)) { return -2; }
    if(!testing::expect_eq((void*)registered(mm, x).ty, null, m)) { return -3; }
    return 0;
}

fn i32 rnt_qualified_name_not_in_target(arena::Arena* a, u8[] m) {
    interner::init(a, 16);
    types::typer_init(a, 16);
    module::Module* other = fresh_module(a);
    other.name = interner::intern("other");
    mutex::create(&other.sema_mutex);
    symbol::Symbol* foo = interner::intern("Foo");
    ast::AstNode* struct_decl = mk_struct_sig(a, foo, mk_texprs1(a, mk_ty_prim(a, token::TokenKind::I32)));
    ((ast::StructDeclNode*)struct_decl).is_exported = true;
    ast::AstNode*[1] other_stmts; other_stmts[0] = struct_decl;
    set_root(other, a, &other_stmts[0], 1);
    sema::run(other);

    module::Module* main_mod = fresh_module(a);
    main_mod.name = interner::intern("main");
    mutex::create(&main_mod.sema_mutex);
    module::Module*[1] imports; imports[0] = other;
    main_mod.imports.ptr = &imports[0];
    main_mod.imports.len = 1;
    symbol::Symbol* other_name = interner::intern("other");
    symbol::Symbol* missing = interner::intern("Missing");
    symbol::Symbol* x = interner::intern("x");
    ast::AstNode* imp = mk_import_decl(a, other_name, false, 0);
    ast::AstNode* var = mk_var_typed(a, x, mk_ty_named(a, other_name, missing));
    ast::AstNode*[2] main_stmts; main_stmts[0] = imp; main_stmts[1] = var;
    set_root(main_mod, a, &main_stmts[0], 2);
    sema::run(main_mod);
    if(!testing::expect_ge(main_mod.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq((void*)registered(main_mod, x).ty, null, m)) { return -2; }
    return 0;
}

fn i32 rnt_self_alias_cycle_reports(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* self = fake_sym_interned(mm, "A");
    ast::AstNode* alias = mk_alias_typed(a, self, mk_ty_named(a, null, self), 0);
    ast::AstNode*[1] stmts; stmts[0] = alias;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "circular type resolution", m)) { return -2; }
    return 0;
}

fn i32 rnt_alias_to_unknown_reports(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* first = fake_sym_interned(mm, "A");
    symbol::Symbol* missing = fake_sym_interned(mm, "Missing");
    ast::AstNode* alias = mk_alias_typed(a, first, mk_ty_named(a, null, missing), 0);
    ast::AstNode*[1] stmts; stmts[0] = alias;
    set_root(mm, a, &stmts[0], 1);
    sema::run(mm);
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_substr(mm.diag.entries[0].msg, "unknown type", m)) { return -2; }
    if(!testing::expect_eq((void*)registered(mm, first).ty, null, m)) { return -3; }
    return 0;
}

fn i32 rnt_fn_named_param_return(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* foo = fake_sym_interned(mm, "Foo");
    symbol::Symbol* make = fake_sym_interned(mm, "make");
    ast::AstNode* struct_decl = mk_struct_sig(a, foo, mk_texprs1(a, mk_ty_prim(a, token::TokenKind::I32)));
    ast::AstNode* fn_decl = mk_fn_sig(a, make, mk_ty_named(a, null, foo), mk_texprs1(a, mk_ty_named(a, null, foo)));
    ast::AstNode*[2] stmts; stmts[0] = struct_decl; stmts[1] = fn_decl;
    set_root(mm, a, &stmts[0], 2);
    sema::run(mm);
    sema::Decl* d = registered(mm, make);
    if(!testing::expect_eq((u64)d.ty.data.fn_ptr.ret.kind, (u64)types::TypeKind::Struct, m)) { return -1; }
    if(!testing::expect_eq((u64)d.ty.data.fn_ptr.params[0].kind, (u64)types::TypeKind::Struct, m)) { return -2; }
    ast::FnDeclNode* fn_node = (ast::FnDeclNode*)fn_decl;
    if(!testing::expect_eq((void*)sema::container_decl((types::Type*)fn_node.params[0].resolved_type), (void*)struct_decl, m)) { return -3; }
    return 0;
}

fn i32 synth_int_lit_i32(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::IntLitNode* lit = fake_int_lit(a, 42, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)lit);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i32(), m)) { return -1; }
    if(!testing::expect_eq((void*)lit.h.ty, (void*)types::prim_i32(), m)) { return -2; }
    if(!testing::expect_true(has_flag((ast::AstNode*)lit, ast::AstFlags::ConstExpr), m)) { return -3; }
    return 0;
}

fn i32 synth_int_lit_i64(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::IntLitNode* lit = fake_int_lit(a, 3000000000, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)lit);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i64(), m)) { return -1; }
    return 0;
}

fn i32 synth_int_lit_u64(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::IntLitNode* lit = fake_int_lit(a, 18446744073709551615, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)lit);
    if(!testing::expect_eq((void*)t, (void*)types::prim_u64(), m)) { return -1; }
    return 0;
}

fn i32 synth_float_lit(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::FloatLitNode* lit = fake_float_lit(a, 1.5, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)lit);
    if(!testing::expect_eq((void*)t, (void*)types::prim_f64(), m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)lit, ast::AstFlags::ConstExpr), m)) { return -2; }
    return 0;
}

fn i32 synth_bool_lit(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::BoolLitNode* lit = fake_bool_lit(a, true, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)lit);
    if(!testing::expect_eq((void*)t, (void*)types::prim_bool(), m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)lit, ast::AstFlags::ConstExpr), m)) { return -2; }
    return 0;
}

fn i32 synth_char_lit(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::CharLitNode* lit = fake_char_lit(a, 65, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)lit);
    if(!testing::expect_eq((void*)t, (void*)types::prim_u8(), m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)lit, ast::AstFlags::ConstExpr), m)) { return -2; }
    return 0;
}

fn i32 synth_string_lit(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::StringLitNode* lit = fake_string_lit_node(a, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)lit);
    types::Type* want = types::intern_pointer(types::prim_u8(), false);
    if(!testing::expect_eq((void*)t, (void*)want, m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)lit, ast::AstFlags::ConstExpr), m)) { return -2; }
    return 0;
}

fn i32 synth_null_lit(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::NullLitNode* lit = fake_null_lit(a, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)lit);
    if(!testing::expect_eq((void*)t, (void*)types::prim_null_ptr(), m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)lit, ast::AstFlags::ConstExpr), m)) { return -2; }
    return 0;
}

fn i32 synth_struct_lit_needs_context(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::StructLitNode* lit = fake_struct_lit(a, 12);
    types::Type* t = sema::synth(&s, (ast::AstNode*)lit);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "literal requires an expected type", m)) { return -3; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 12, m)) { return -4; }
    return 0;
}

fn i32 synth_array_lit_needs_context(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::ArrayLitNode* lit = fake_array_lit(a, 7);
    types::Type* t = sema::synth(&s, (ast::AstNode*)lit);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "literal requires an expected type", m)) { return -3; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 7, m)) { return -4; }
    return 0;
}

fn i32 synth_undefined_needs_context(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::UndefinedLitNode* lit = fake_undefined_lit(a, 3);
    types::Type* t = sema::synth(&s, (ast::AstNode*)lit);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 3, m)) { return -3; }
    return 0;
}

fn i32 synth_ident_var(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    symbol::Symbol* x = interner::intern("x");
    sema::Decl* d = fake_node_decl(a, x, types::prim_i32(), (ast::AstNode*)fake_var_decl(a, x, false));
    sema::scope_add(sc, x, d);
    ast::IdentNode* id = fake_ident(a, x, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)id);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i32(), m)) { return -1; }
    if(!testing::expect_eq((void*)id.resolved, (void*)d, m)) { return -2; }
    if(!testing::expect_true(has_flag((ast::AstNode*)id, ast::AstFlags::LValue), m)) { return -3; }
    if(!testing::expect_true(!has_flag((ast::AstNode*)id, ast::AstFlags::ConstExpr), m)) { return -4; }
    return 0;
}

fn i32 synth_ident_param(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    symbol::Symbol* p = interner::intern("p");
    sema::Decl* d = fake_param_decl(a, p, types::prim_f32());
    sema::scope_add(sc, p, d);
    ast::IdentNode* id = fake_ident(a, p, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)id);
    if(!testing::expect_eq((void*)t, (void*)types::prim_f32(), m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)id, ast::AstFlags::LValue), m)) { return -2; }
    return 0;
}

fn i32 synth_ident_const_var(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    symbol::Symbol* c = interner::intern("c");
    sema::Decl* d = fake_node_decl(a, c, types::prim_i32(), (ast::AstNode*)fake_var_decl(a, c, true));
    sema::scope_add(sc, c, d);
    ast::IdentNode* id = fake_ident(a, c, 0);
    sema::synth(&s, (ast::AstNode*)id);
    if(!testing::expect_true(has_flag((ast::AstNode*)id, ast::AstFlags::LValue), m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)id, ast::AstFlags::ConstExpr), m)) { return -2; }
    return 0;
}

fn i32 synth_ident_fn(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    symbol::Symbol* f = interner::intern("f");
    sema::Decl* d = fake_node_decl(a, f, types::prim_i32(), (ast::AstNode*)fake_fn_decl(a, f));
    sema::scope_add(sc, f, d);
    ast::IdentNode* id = fake_ident(a, f, 0);
    sema::synth(&s, (ast::AstNode*)id);
    if(!testing::expect_true(has_flag((ast::AstNode*)id, ast::AstFlags::ConstExpr), m)) { return -1; }
    if(!testing::expect_true(!has_flag((ast::AstNode*)id, ast::AstFlags::LValue), m)) { return -2; }
    return 0;
}

fn i32 synth_ident_enum_member(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    symbol::Symbol* e = interner::intern("Red");
    sema::Decl* d = fake_enum_member_decl_value(a, e, types::prim_i32());
    sema::scope_add(sc, e, d);
    ast::IdentNode* id = fake_ident(a, e, 0);
    sema::synth(&s, (ast::AstNode*)id);
    if(!testing::expect_true(has_flag((ast::AstNode*)id, ast::AstFlags::ConstExpr), m)) { return -1; }
    if(!testing::expect_true(!has_flag((ast::AstNode*)id, ast::AstFlags::LValue), m)) { return -2; }
    return 0;
}

fn i32 synth_ident_undefined(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    symbol::Symbol* missing = interner::intern("nope");
    ast::IdentNode* id = fake_ident(a, missing, 9);
    types::Type* t = sema::synth(&s, (ast::AstNode*)id);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "undefined identifier nope", m)) { return -3; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 9, m)) { return -4; }
    if(!testing::expect_true(has_flag((ast::AstNode*)id, ast::AstFlags::HadError), m)) { return -5; }
    return 0;
}

fn i32 check_int_lit_fits_u8(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::IntLitNode* lit = fake_int_lit(a, 200, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, types::prim_u8());
    if(!testing::expect_true(ok, m)) { return -1; }
    if(!testing::expect_eq((void*)lit.h.ty, (void*)types::prim_u8(), m)) { return -2; }
    return 0;
}

fn i32 check_int_lit_overflow_u8(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::IntLitNode* lit = fake_int_lit(a, 300, 7);
    bool ok = sema::check(&s, (ast::AstNode*)lit, types::prim_u8());
    if(!testing::expect_true(!ok, m)) { return -1; }
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "literal 300 does not fit in u8", m)) { return -3; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 7, m)) { return -4; }
    return 0;
}

fn i32 check_null_to_ptr(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    types::Type* ptr = types::intern_pointer(types::prim_i32(), false);
    ast::NullLitNode* lit = fake_null_lit(a, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, ptr);
    if(!testing::expect_true(ok, m)) { return -1; }
    if(!testing::expect_eq((void*)lit.h.ty, (void*)ptr, m)) { return -2; }
    if(!testing::expect_true(has_flag((ast::AstNode*)lit, ast::AstFlags::ConstExpr), m)) { return -3; }
    return 0;
}

fn i32 check_null_to_slice(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    types::Type* slice = types::intern_slice(types::prim_i32());
    ast::NullLitNode* lit = fake_null_lit(a, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, slice);
    if(!testing::expect_true(ok, m)) { return -1; }
    if(!testing::expect_eq((void*)lit.h.ty, (void*)slice, m)) { return -2; }
    return 0;
}

fn i32 check_null_to_int_fails(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::NullLitNode* lit = fake_null_lit(a, 5);
    bool ok = sema::check(&s, (ast::AstNode*)lit, types::prim_i32());
    if(!testing::expect_true(!ok, m)) { return -1; }
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "expected i32, found void*", m)) { return -3; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 5, m)) { return -4; }
    if(!testing::expect_true(has_flag((ast::AstNode*)lit, ast::AstFlags::HadError), m)) { return -5; }
    return 0;
}

fn i32 check_float_to_int_fails(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::FloatLitNode* lit = fake_float_lit(a, 2.0, 4);
    bool ok = sema::check(&s, (ast::AstNode*)lit, types::prim_i32());
    if(!testing::expect_true(!ok, m)) { return -1; }
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "expected i32, found f64", m)) { return -3; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 4, m)) { return -4; }
    return 0;
}

fn i32 check_undefined_to_type(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::UndefinedLitNode* lit = fake_undefined_lit(a, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, types::prim_i32());
    if(!testing::expect_true(ok, m)) { return -1; }
    if(!testing::expect_eq((void*)lit.h.ty, (void*)types::prim_i32(), m)) { return -2; }
    return 0;
}

fn i32 check_bool_ok(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::BoolLitNode* lit = fake_bool_lit(a, false, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, types::prim_bool());
    if(!testing::expect_true(ok, m)) { return -1; }
    return 0;
}

fn i32 check_ident_widen(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    symbol::Symbol* v = interner::intern("v");
    sema::Decl* d = fake_node_decl(a, v, types::prim_i16(), (ast::AstNode*)fake_var_decl(a, v, false));
    sema::scope_add(sc, v, d);
    ast::IdentNode* id = fake_ident(a, v, 0);
    bool ok = sema::check(&s, (ast::AstNode*)id, types::prim_i32());
    if(!testing::expect_true(ok, m)) { return -1; }
    return 0;
}

fn i32 check_ident_narrow_fails(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    symbol::Symbol* v = interner::intern("v");
    sema::Decl* d = fake_node_decl(a, v, types::prim_i32(), (ast::AstNode*)fake_var_decl(a, v, false));
    sema::scope_add(sc, v, d);
    ast::IdentNode* id = fake_ident(a, v, 9);
    bool ok = sema::check(&s, (ast::AstNode*)id, types::prim_i16());
    if(!testing::expect_true(!ok, m)) { return -1; }
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "expected i16, found i32", m)) { return -3; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 9, m)) { return -4; }
    return 0;
}

fn i32 check_char_to_u8(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::CharLitNode* lit = fake_char_lit(a, 65, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, types::prim_u8());
    if(!testing::expect_true(ok, m)) { return -1; }
    return 0;
}

fn i32 check_string_to_u8_ptr(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    types::Type* u8ptr = types::intern_pointer(types::prim_u8(), false);
    ast::StringLitNode* lit = fake_string_lit_node(a, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, u8ptr);
    if(!testing::expect_true(ok, m)) { return -1; }
    return 0;
}

fn i32 bin_add_two_lits(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::AstNode* lhs = (ast::AstNode*)fake_int_lit(a, 1, 0);
    ast::AstNode* rhs = (ast::AstNode*)fake_int_lit(a, 2, 0);
    ast::BinaryOpNode* bin = fake_binop(a, token::TokenKind::Plus, lhs, rhs, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)bin);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i32(), m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)bin, ast::AstFlags::ConstExpr), m)) { return -2; }
    return 0;
}

fn i32 bin_comparison_is_bool(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::AstNode* lhs = (ast::AstNode*)fake_int_lit(a, 1, 0);
    ast::AstNode* rhs = (ast::AstNode*)fake_int_lit(a, 2, 0);
    ast::BinaryOpNode* bin = fake_binop(a, token::TokenKind::LT, lhs, rhs, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)bin);
    if(!testing::expect_eq((void*)t, (void*)types::prim_bool(), m)) { return -1; }
    return 0;
}

fn i32 bin_logical_is_bool(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::AstNode* lhs = (ast::AstNode*)fake_bool_lit(a, true, 0);
    ast::AstNode* rhs = (ast::AstNode*)fake_bool_lit(a, false, 0);
    ast::BinaryOpNode* bin = fake_binop(a, token::TokenKind::AmpAmp, lhs, rhs, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)bin);
    if(!testing::expect_eq((void*)t, (void*)types::prim_bool(), m)) { return -1; }
    return 0;
}

fn i32 bin_nested_const(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::AstNode* inner = (ast::AstNode*)fake_binop(a, token::TokenKind::Plus, (ast::AstNode*)fake_int_lit(a, 1, 0), (ast::AstNode*)fake_int_lit(a, 2, 0), 0);
    ast::BinaryOpNode* outer = fake_binop(a, token::TokenKind::Star, inner, (ast::AstNode*)fake_int_lit(a, 3, 0), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)outer);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i32(), m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)outer, ast::AstFlags::ConstExpr), m)) { return -2; }
    return 0;
}

fn i32 bin_non_const_operand(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    symbol::Symbol* x = interner::intern("x");
    register_var(a, sc, x, types::prim_i32(), false);
    ast::AstNode* lhs = (ast::AstNode*)fake_ident(a, x, 0);
    ast::AstNode* rhs = (ast::AstNode*)fake_int_lit(a, 1, 0);
    ast::BinaryOpNode* bin = fake_binop(a, token::TokenKind::Plus, lhs, rhs, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)bin);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i32(), m)) { return -1; }
    if(!testing::expect_true(!has_flag((ast::AstNode*)bin, ast::AstFlags::ConstExpr), m)) { return -2; }
    return 0;
}

fn i32 bin_mismatch_reports(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::AstNode* lhs = (ast::AstNode*)fake_int_lit(a, 1, 0);
    ast::AstNode* rhs = (ast::AstNode*)fake_float_lit(a, 2.0, 0);
    ast::BinaryOpNode* bin = fake_binop(a, token::TokenKind::Plus, lhs, rhs, 6);
    types::Type* t = sema::synth(&s, (ast::AstNode*)bin);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "operator is not defined for i32 and f64", m)) { return -3; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 6, m)) { return -4; }
    if(!testing::expect_true(has_flag((ast::AstNode*)bin, ast::AstFlags::HadError), m)) { return -5; }
    return 0;
}

fn i32 bin_operand_error_propagates(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    ast::AstNode* lhs = (ast::AstNode*)fake_ident(a, interner::intern("missing"), 0);
    ast::AstNode* rhs = (ast::AstNode*)fake_int_lit(a, 1, 0);
    ast::BinaryOpNode* bin = fake_binop(a, token::TokenKind::Plus, lhs, rhs, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)bin);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    return 0;
}

fn i32 un_neg_int(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::AstNode* operand = (ast::AstNode*)fake_int_lit(a, 5, 0);
    ast::UnaryOpNode* un = fake_unary(a, token::TokenKind::Minus, operand, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)un);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i32(), m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)un, ast::AstFlags::ConstExpr), m)) { return -2; }
    return 0;
}

fn i32 un_not_bool(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::AstNode* operand = (ast::AstNode*)fake_bool_lit(a, true, 0);
    ast::UnaryOpNode* un = fake_unary(a, token::TokenKind::Bang, operand, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)un);
    if(!testing::expect_eq((void*)t, (void*)types::prim_bool(), m)) { return -1; }
    return 0;
}

fn i32 un_complement_int(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::AstNode* operand = (ast::AstNode*)fake_int_lit(a, 5, 0);
    ast::UnaryOpNode* un = fake_unary(a, token::TokenKind::Tilde, operand, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)un);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i32(), m)) { return -1; }
    return 0;
}

fn i32 un_complement_float_fails(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::AstNode* operand = (ast::AstNode*)fake_float_lit(a, 2.0, 0);
    ast::UnaryOpNode* un = fake_unary(a, token::TokenKind::Tilde, operand, 4);
    types::Type* t = sema::synth(&s, (ast::AstNode*)un);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "operator '~' is not defined for f64", m)) { return -3; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 4, m)) { return -4; }
    return 0;
}

fn i32 un_deref_ptr(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    symbol::Symbol* p = interner::intern("p");
    types::Type* ptr = types::intern_pointer(types::prim_i32(), false);
    register_var(a, sc, p, ptr, false);
    ast::AstNode* operand = (ast::AstNode*)fake_ident(a, p, 0);
    ast::UnaryOpNode* un = fake_unary(a, token::TokenKind::Star, operand, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)un);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i32(), m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)un, ast::AstFlags::LValue), m)) { return -2; }
    return 0;
}

fn i32 un_deref_non_ptr_fails(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::AstNode* operand = (ast::AstNode*)fake_int_lit(a, 5, 0);
    ast::UnaryOpNode* un = fake_unary(a, token::TokenKind::Star, operand, 8);
    types::Type* t = sema::synth(&s, (ast::AstNode*)un);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "operator '*' is not defined for i32", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 8, m)) { return -3; }
    return 0;
}

fn i32 un_addr_of_lvalue(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    symbol::Symbol* x = interner::intern("x");
    register_var(a, sc, x, types::prim_i32(), false);
    ast::AstNode* operand = (ast::AstNode*)fake_ident(a, x, 0);
    ast::UnaryOpNode* un = fake_unary(a, token::TokenKind::Amp, operand, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)un);
    types::Type* want = types::intern_pointer(types::prim_i32(), false);
    if(!testing::expect_eq((void*)t, (void*)want, m)) { return -1; }
    return 0;
}

fn i32 un_addr_of_non_lvalue_fails(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::AstNode* operand = (ast::AstNode*)fake_int_lit(a, 5, 3);
    ast::UnaryOpNode* un = fake_unary(a, token::TokenKind::Amp, operand, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)un);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "cannot take the address of a non-lvalue", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 3, m)) { return -3; }
    return 0;
}

fn i32 un_operand_error_propagates(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    ast::AstNode* operand = (ast::AstNode*)fake_ident(a, interner::intern("missing"), 0);
    ast::UnaryOpNode* un = fake_unary(a, token::TokenKind::Minus, operand, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)un);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    return 0;
}

fn i32 check_fused_neg_fits(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::AstNode* lit = (ast::AstNode*)fake_int_lit(a, 2147483648, 0);
    ast::UnaryOpNode* un = fake_unary(a, token::TokenKind::Minus, lit, 0);
    bool ok = sema::check(&s, (ast::AstNode*)un, types::prim_i32());
    if(!testing::expect_true(ok, m)) { return -1; }
    if(!testing::expect_eq((void*)un.h.ty, (void*)types::prim_i32(), m)) { return -2; }
    if(!testing::expect_true(has_flag((ast::AstNode*)un, ast::AstFlags::ConstExpr), m)) { return -3; }
    return 0;
}

fn i32 check_fused_neg_overflow(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::AstNode* lit = (ast::AstNode*)fake_int_lit(a, 2147483649, 5);
    ast::UnaryOpNode* un = fake_unary(a, token::TokenKind::Minus, lit, 0);
    bool ok = sema::check(&s, (ast::AstNode*)un, types::prim_i32());
    if(!testing::expect_true(!ok, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "literal 2147483649 does not fit in i32", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 5, m)) { return -3; }
    return 0;
}

fn i32 check_fused_neg_to_unsigned_fails(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::AstNode* lit = (ast::AstNode*)fake_int_lit(a, 5, 2);
    ast::UnaryOpNode* un = fake_unary(a, token::TokenKind::Minus, lit, 0);
    bool ok = sema::check(&s, (ast::AstNode*)un, types::prim_u32());
    if(!testing::expect_true(!ok, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "literal 5 does not fit in u32", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 2, m)) { return -3; }
    return 0;
}

fn i32 member_struct_field(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* point = mk_point_type(a);
    symbol::Symbol* p = interner::intern("p");
    register_var(a, sc, p, point, false);
    ast::MemberAccessNode* acc = fake_member(a, (ast::AstNode*)fake_ident(a, p, 0), interner::intern("x"), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)acc);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i32(), m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)acc, ast::AstFlags::LValue), m)) { return -2; }
    if(!testing::expect_not_null((void*)acc.resolved, m)) { return -3; }
    return 0;
}

fn i32 member_pointer_autoderef(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* point_ptr = types::intern_pointer(mk_point_type(a), false);
    symbol::Symbol* p = interner::intern("p");
    register_var(a, sc, p, point_ptr, false);
    ast::MemberAccessNode* acc = fake_member(a, (ast::AstNode*)fake_ident(a, p, 0), interner::intern("y"), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)acc);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i32(), m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)acc, ast::AstFlags::LValue), m)) { return -2; }
    return 0;
}

fn i32 member_slice_ptr(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* slice = types::intern_slice(types::prim_i32());
    symbol::Symbol* sl = interner::intern("sl");
    register_var(a, sc, sl, slice, false);
    ast::MemberAccessNode* acc = fake_member(a, (ast::AstNode*)fake_ident(a, sl, 0), interner::intern("ptr"), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)acc);
    types::Type* want = types::intern_pointer(types::prim_i32(), false);
    if(!testing::expect_eq((void*)t, (void*)want, m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)acc, ast::AstFlags::LValue), m)) { return -2; }
    return 0;
}

fn i32 member_slice_len(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* slice = types::intern_slice(types::prim_i32());
    symbol::Symbol* sl = interner::intern("sl");
    register_var(a, sc, sl, slice, false);
    ast::MemberAccessNode* acc = fake_member(a, (ast::AstNode*)fake_ident(a, sl, 0), interner::intern("len"), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)acc);
    if(!testing::expect_eq((void*)t, (void*)types::prim_u64(), m)) { return -1; }
    return 0;
}

fn i32 member_slice_unknown_field(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* slice = types::intern_slice(types::prim_i32());
    symbol::Symbol* sl = interner::intern("sl");
    register_var(a, sc, sl, slice, false);
    ast::MemberAccessNode* acc = fake_member(a, (ast::AstNode*)fake_ident(a, sl, 0), interner::intern("foo"), 4);
    types::Type* t = sema::synth(&s, (ast::AstNode*)acc);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "type i32[] has no field foo", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 4, m)) { return -3; }
    return 0;
}

fn i32 member_unknown_struct_field(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* point = mk_point_type(a);
    symbol::Symbol* p = interner::intern("p");
    register_var(a, sc, p, point, false);
    ast::MemberAccessNode* acc = fake_member(a, (ast::AstNode*)fake_ident(a, p, 0), interner::intern("z"), 8);
    types::Type* t = sema::synth(&s, (ast::AstNode*)acc);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "type Point has no field z", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 8, m)) { return -3; }
    return 0;
}

fn i32 member_on_non_aggregate(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    symbol::Symbol* x = interner::intern("x");
    register_var(a, sc, x, types::prim_i32(), false);
    ast::MemberAccessNode* acc = fake_member(a, (ast::AstNode*)fake_ident(a, x, 0), interner::intern("foo"), 2);
    types::Type* t = sema::synth(&s, (ast::AstNode*)acc);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "cannot access field of i32", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 2, m)) { return -3; }
    return 0;
}

fn i32 member_base_error(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    ast::MemberAccessNode* acc = fake_member(a, (ast::AstNode*)fake_ident(a, interner::intern("missing"), 0), interner::intern("x"), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)acc);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    return 0;
}

fn i32 index_array(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* arr = types::intern_array(types::prim_i32(), 4);
    symbol::Symbol* av = interner::intern("av");
    register_var(a, sc, av, arr, false);
    ast::ArrayIndexNode* idx = fake_index(a, (ast::AstNode*)fake_ident(a, av, 0), (ast::AstNode*)fake_int_lit(a, 0, 0), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)idx);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i32(), m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)idx, ast::AstFlags::LValue), m)) { return -2; }
    return 0;
}

fn i32 index_slice(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* slice = types::intern_slice(types::prim_f32());
    symbol::Symbol* sl = interner::intern("sl");
    register_var(a, sc, sl, slice, false);
    ast::ArrayIndexNode* idx = fake_index(a, (ast::AstNode*)fake_ident(a, sl, 0), (ast::AstNode*)fake_int_lit(a, 1, 0), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)idx);
    if(!testing::expect_eq((void*)t, (void*)types::prim_f32(), m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)idx, ast::AstFlags::LValue), m)) { return -2; }
    return 0;
}

fn i32 index_pointer(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* ptr = types::intern_pointer(types::prim_i32(), false);
    symbol::Symbol* p = interner::intern("p");
    register_var(a, sc, p, ptr, false);
    ast::ArrayIndexNode* idx = fake_index(a, (ast::AstNode*)fake_ident(a, p, 0), (ast::AstNode*)fake_int_lit(a, 2, 0), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)idx);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i32(), m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)idx, ast::AstFlags::LValue), m)) { return -2; }
    return 0;
}

fn i32 index_non_indexable(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    symbol::Symbol* x = interner::intern("x");
    register_var(a, sc, x, types::prim_i32(), false);
    ast::ArrayIndexNode* idx = fake_index(a, (ast::AstNode*)fake_ident(a, x, 0), (ast::AstNode*)fake_int_lit(a, 0, 0), 3);
    types::Type* t = sema::synth(&s, (ast::AstNode*)idx);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "cannot index i32", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 3, m)) { return -3; }
    return 0;
}

fn i32 index_bad_index_type(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* arr = types::intern_array(types::prim_i32(), 4);
    symbol::Symbol* av = interner::intern("av");
    register_var(a, sc, av, arr, false);
    ast::ArrayIndexNode* idx = fake_index(a, (ast::AstNode*)fake_ident(a, av, 0), (ast::AstNode*)fake_bool_lit(a, true, 5), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)idx);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "expected u64, found bool", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 5, m)) { return -3; }
    return 0;
}

fn i32 slice_range_of_array(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* arr = types::intern_array(types::prim_i32(), 4);
    symbol::Symbol* av = interner::intern("av");
    register_var(a, sc, av, arr, false);
    ast::SliceRangeNode* sr = fake_slice_range(a, (ast::AstNode*)fake_ident(a, av, 0), (ast::AstNode*)fake_int_lit(a, 1, 0), (ast::AstNode*)fake_int_lit(a, 3, 0), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)sr);
    if(!testing::expect_eq((void*)t, (void*)types::intern_slice(types::prim_i32()), m)) { return -1; }
    if(!testing::expect_true(!has_flag((ast::AstNode*)sr, ast::AstFlags::LValue), m)) { return -2; }
    return 0;
}

fn i32 slice_range_of_slice(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* slice = types::intern_slice(types::prim_i32());
    symbol::Symbol* sl = interner::intern("sl");
    register_var(a, sc, sl, slice, false);
    ast::SliceRangeNode* sr = fake_slice_range(a, (ast::AstNode*)fake_ident(a, sl, 0), (ast::AstNode*)fake_int_lit(a, 1, 0), (ast::AstNode*)fake_int_lit(a, 2, 0), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)sr);
    if(!testing::expect_eq((void*)t, (void*)slice, m)) { return -1; }
    return 0;
}

fn i32 slice_range_of_pointer(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* ptr = types::intern_pointer(types::prim_i32(), false);
    symbol::Symbol* p = interner::intern("p");
    register_var(a, sc, p, ptr, false);
    ast::SliceRangeNode* sr = fake_slice_range(a, (ast::AstNode*)fake_ident(a, p, 0), (ast::AstNode*)fake_int_lit(a, 0, 0), (ast::AstNode*)fake_int_lit(a, 2, 0), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)sr);
    if(!testing::expect_eq((void*)t, (void*)types::intern_slice(types::prim_i32()), m)) { return -1; }
    return 0;
}

fn i32 slice_range_omit_lo(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* arr = types::intern_array(types::prim_i32(), 4);
    symbol::Symbol* av = interner::intern("av");
    register_var(a, sc, av, arr, false);
    ast::SliceRangeNode* sr = fake_slice_range(a, (ast::AstNode*)fake_ident(a, av, 0), null, (ast::AstNode*)fake_int_lit(a, 2, 0), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)sr);
    if(!testing::expect_eq((void*)t, (void*)types::intern_slice(types::prim_i32()), m)) { return -1; }
    return 0;
}

fn i32 slice_range_omit_hi(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* arr = types::intern_array(types::prim_i32(), 4);
    symbol::Symbol* av = interner::intern("av");
    register_var(a, sc, av, arr, false);
    ast::SliceRangeNode* sr = fake_slice_range(a, (ast::AstNode*)fake_ident(a, av, 0), (ast::AstNode*)fake_int_lit(a, 1, 0), null, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)sr);
    if(!testing::expect_eq((void*)t, (void*)types::intern_slice(types::prim_i32()), m)) { return -1; }
    return 0;
}

fn i32 slice_range_non_indexable(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    symbol::Symbol* x = interner::intern("x");
    register_var(a, sc, x, types::prim_i32(), false);
    ast::SliceRangeNode* sr = fake_slice_range(a, (ast::AstNode*)fake_ident(a, x, 0), (ast::AstNode*)fake_int_lit(a, 1, 0), (ast::AstNode*)fake_int_lit(a, 2, 0), 6);
    types::Type* t = sema::synth(&s, (ast::AstNode*)sr);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "cannot index i32", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 6, m)) { return -3; }
    return 0;
}

fn i32 slice_range_bad_bound(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* arr = types::intern_array(types::prim_i32(), 4);
    symbol::Symbol* av = interner::intern("av");
    register_var(a, sc, av, arr, false);
    ast::SliceRangeNode* sr = fake_slice_range(a, (ast::AstNode*)fake_ident(a, av, 0), (ast::AstNode*)fake_bool_lit(a, true, 5), (ast::AstNode*)fake_int_lit(a, 2, 0), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)sr);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "expected u64, found bool", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 5, m)) { return -3; }
    return 0;
}

fn i32 call_no_args(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type*[] noparams = {null, 0};
    types::Type* fnty = types::intern_fn_ptr(types::prim_i32(), noparams, false);
    symbol::Symbol* f = interner::intern("f");
    register_fn(a, sc, f, fnty);
    ast::CallNode* call = fake_call(a, (ast::AstNode*)fake_ident(a, f, 0), null, 0, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)call);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i32(), m)) { return -1; }
    return 0;
}

fn i32 call_one_arg(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type*[1] pbuf; pbuf[0] = types::prim_i32();
    types::Type*[] params = {&pbuf[0], 1};
    types::Type* fnty = types::intern_fn_ptr(types::prim_i32(), params, false);
    symbol::Symbol* f = interner::intern("f");
    register_fn(a, sc, f, fnty);
    ast::AstNode*[1] args; args[0] = (ast::AstNode*)fake_int_lit(a, 5, 0);
    ast::CallNode* call = fake_call(a, (ast::AstNode*)fake_ident(a, f, 0), &args[0], 1, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)call);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i32(), m)) { return -1; }
    if(!testing::expect_eq((void*)args[0].h.ty, (void*)types::prim_i32(), m)) { return -2; }
    return 0;
}

fn i32 call_arg_widen(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type*[1] pbuf; pbuf[0] = types::prim_i32();
    types::Type*[] params = {&pbuf[0], 1};
    types::Type* fnty = types::intern_fn_ptr(types::prim_i32(), params, false);
    symbol::Symbol* f = interner::intern("f");
    register_fn(a, sc, f, fnty);
    symbol::Symbol* v = interner::intern("v");
    register_var(a, sc, v, types::prim_i16(), false);
    ast::AstNode*[1] args; args[0] = (ast::AstNode*)fake_ident(a, v, 0);
    ast::CallNode* call = fake_call(a, (ast::AstNode*)fake_ident(a, f, 0), &args[0], 1, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)call);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i32(), m)) { return -1; }
    return 0;
}

fn i32 call_arg_mismatch(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type*[1] pbuf; pbuf[0] = types::prim_i32();
    types::Type*[] params = {&pbuf[0], 1};
    types::Type* fnty = types::intern_fn_ptr(types::prim_void(), params, false);
    symbol::Symbol* f = interner::intern("f");
    register_fn(a, sc, f, fnty);
    ast::AstNode*[1] args; args[0] = (ast::AstNode*)fake_float_lit(a, 1.0, 11);
    ast::CallNode* call = fake_call(a, (ast::AstNode*)fake_ident(a, f, 0), &args[0], 1, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)call);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "expected i32, found f64", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 11, m)) { return -3; }
    return 0;
}

fn i32 call_arity_too_few(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type*[2] pbuf; pbuf[0] = types::prim_i32(); pbuf[1] = types::prim_i32();
    types::Type*[] params = {&pbuf[0], 2};
    types::Type* fnty = types::intern_fn_ptr(types::prim_i32(), params, false);
    symbol::Symbol* f = interner::intern("f");
    register_fn(a, sc, f, fnty);
    ast::AstNode*[1] args; args[0] = (ast::AstNode*)fake_int_lit(a, 1, 0);
    ast::CallNode* call = fake_call(a, (ast::AstNode*)fake_ident(a, f, 0), &args[0], 1, 4);
    types::Type* t = sema::synth(&s, (ast::AstNode*)call);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "call expects 2 arguments but got 1", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 4, m)) { return -3; }
    return 0;
}

fn i32 call_arity_too_many(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type*[1] pbuf; pbuf[0] = types::prim_i32();
    types::Type*[] params = {&pbuf[0], 1};
    types::Type* fnty = types::intern_fn_ptr(types::prim_i32(), params, false);
    symbol::Symbol* f = interner::intern("f");
    register_fn(a, sc, f, fnty);
    ast::AstNode*[2] args; args[0] = (ast::AstNode*)fake_int_lit(a, 1, 0); args[1] = (ast::AstNode*)fake_int_lit(a, 2, 0);
    ast::CallNode* call = fake_call(a, (ast::AstNode*)fake_ident(a, f, 0), &args[0], 2, 6);
    types::Type* t = sema::synth(&s, (ast::AstNode*)call);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "call expects 1 arguments but got 2", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 6, m)) { return -3; }
    return 0;
}

fn i32 call_non_function(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    symbol::Symbol* x = interner::intern("x");
    register_var(a, sc, x, types::prim_i32(), false);
    ast::CallNode* call = fake_call(a, (ast::AstNode*)fake_ident(a, x, 0), null, 0, 3);
    types::Type* t = sema::synth(&s, (ast::AstNode*)call);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "cannot call value of type i32", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 3, m)) { return -3; }
    return 0;
}

fn i32 call_variadic(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type*[1] pbuf; pbuf[0] = types::prim_i32();
    types::Type*[] params = {&pbuf[0], 1};
    types::Type* fnty = types::intern_fn_ptr(types::prim_i32(), params, true);
    symbol::Symbol* f = interner::intern("f");
    register_fn(a, sc, f, fnty);
    ast::AstNode*[3] args; args[0] = (ast::AstNode*)fake_int_lit(a, 1, 0); args[1] = (ast::AstNode*)fake_int_lit(a, 2, 0); args[2] = (ast::AstNode*)fake_int_lit(a, 3, 0);
    ast::CallNode* call = fake_call(a, (ast::AstNode*)fake_ident(a, f, 0), &args[0], 3, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)call);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i32(), m)) { return -1; }
    return 0;
}

fn i32 call_returns_void(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type*[] noparams = {null, 0};
    types::Type* fnty = types::intern_fn_ptr(types::prim_void(), noparams, false);
    symbol::Symbol* f = interner::intern("f");
    register_fn(a, sc, f, fnty);
    ast::CallNode* call = fake_call(a, (ast::AstNode*)fake_ident(a, f, 0), null, 0, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)call);
    if(!testing::expect_eq((void*)t, (void*)types::prim_void(), m)) { return -1; }
    return 0;
}

fn i32 call_callee_error(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    ast::CallNode* call = fake_call(a, (ast::AstNode*)fake_ident(a, interner::intern("missing"), 0), null, 0, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)call);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    return 0;
}

fn i32 cast_int_to_int(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::CastNode* cast = fake_cast(a, mk_ty_prim(a, token::TokenKind::I16), (ast::AstNode*)fake_int_lit(a, 5, 0), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)cast);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i16(), m)) { return -1; }
    return 0;
}

fn i32 cast_int_to_float(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::CastNode* cast = fake_cast(a, mk_ty_prim(a, token::TokenKind::F32), (ast::AstNode*)fake_int_lit(a, 5, 0), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)cast);
    if(!testing::expect_eq((void*)t, (void*)types::prim_f32(), m)) { return -1; }
    return 0;
}

fn i32 cast_float_to_int(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::CastNode* cast = fake_cast(a, mk_ty_prim(a, token::TokenKind::I32), (ast::AstNode*)fake_float_lit(a, 2.5, 0), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)cast);
    if(!testing::expect_eq((void*)t, (void*)types::prim_i32(), m)) { return -1; }
    return 0;
}

fn i32 cast_ptr_to_ptr(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    symbol::Symbol* p = interner::intern("p");
    register_var(a, sc, p, types::intern_pointer(types::prim_i8(), false), false);
    ast::CastNode* cast = fake_cast(a, mk_ty_ptr(a, mk_ty_prim(a, token::TokenKind::I32), false), (ast::AstNode*)fake_ident(a, p, 0), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)cast);
    if(!testing::expect_eq((void*)t, (void*)types::intern_pointer(types::prim_i32(), false), m)) { return -1; }
    return 0;
}

fn i32 cast_const_propagation(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::CastNode* cast = fake_cast(a, mk_ty_prim(a, token::TokenKind::I16), (ast::AstNode*)fake_int_lit(a, 5, 0), 0);
    sema::synth(&s, (ast::AstNode*)cast);
    if(!testing::expect_true(has_flag((ast::AstNode*)cast, ast::AstFlags::ConstExpr), m)) { return -1; }
    return 0;
}

fn i32 cast_invalid(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    symbol::Symbol* p = interner::intern("p");
    register_var(a, sc, p, mk_point_type(a), false);
    ast::CastNode* cast = fake_cast(a, mk_ty_prim(a, token::TokenKind::I32), (ast::AstNode*)fake_ident(a, p, 0), 7);
    types::Type* t = sema::synth(&s, (ast::AstNode*)cast);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "cannot cast Point to i32", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 7, m)) { return -3; }
    return 0;
}

fn i32 cast_expr_error(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    ast::CastNode* cast = fake_cast(a, mk_ty_prim(a, token::TokenKind::I32), (ast::AstNode*)fake_ident(a, interner::intern("missing"), 0), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)cast);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    return 0;
}

fn i32 ns_enum_member(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* ety = register_color_enum(a, sc);
    ast::AstNode* base = (ast::AstNode*)fake_ident(a, interner::intern("Color"), 0);
    ast::NamespaceAccessNode* na = fake_ns_access(a, base, interner::intern("Red"), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)na);
    if(!testing::expect_eq((void*)t, (void*)ety, m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)na, ast::AstFlags::ConstExpr), m)) { return -2; }
    if(!testing::expect_not_null((void*)na.resolved, m)) { return -3; }
    return 0;
}

fn i32 ns_enum_unknown_member(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    register_color_enum(a, sc);
    ast::AstNode* base = (ast::AstNode*)fake_ident(a, interner::intern("Color"), 0);
    ast::NamespaceAccessNode* na = fake_ns_access(a, base, interner::intern("Blue"), 5);
    types::Type* t = sema::synth(&s, (ast::AstNode*)na);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "no member named Blue", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 5, m)) { return -3; }
    return 0;
}

fn i32 ns_not_namespace(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    symbol::Symbol* x = interner::intern("x");
    register_var(a, sc, x, types::prim_i32(), false);
    ast::AstNode* base = (ast::AstNode*)fake_ident(a, x, 0);
    ast::NamespaceAccessNode* na = fake_ns_access(a, base, interner::intern("y"), 2);
    types::Type* t = sema::synth(&s, (ast::AstNode*)na);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "left of '::' is not a module or enum", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 2, m)) { return -3; }
    return 0;
}

fn i32 ns_base_undefined(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    ast::AstNode* base = (ast::AstNode*)fake_ident(a, interner::intern("Nope"), 0);
    ast::NamespaceAccessNode* na = fake_ns_access(a, base, interner::intern("x"), 3);
    types::Type* t = sema::synth(&s, (ast::AstNode*)na);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "left of '::' is not a module or enum", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 3, m)) { return -3; }
    return 0;
}

fn i32 ns_import_member(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "main");
    sema::Sema s = mk_sema(mm);
    sema::Scope* main_scope = sema::scope_new(a, null, 16);
    s.scope = main_scope;
    module::Module* other = fresh_module(a);
    other.name = interner::intern("other");
    sema::Scope* other_scope = sema::scope_new(a, null, 16);
    other.global_scope = (void*)other_scope;
    symbol::Symbol* helper = interner::intern("helper");
    types::Type*[] noparams = {null, 0};
    types::Type* fnty = types::intern_fn_ptr(types::prim_i32(), noparams, false);
    sema::Decl* hd = register_fn(a, other_scope, helper, fnty);
    hd.is_exported = true;
    symbol::Symbol* othername = interner::intern("other");
    sema::scope_add(main_scope, othername, fake_import_decl(a, othername, other));
    ast::AstNode* base = (ast::AstNode*)fake_ident(a, othername, 0);
    ast::NamespaceAccessNode* na = fake_ns_access(a, base, helper, 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)na);
    if(!testing::expect_eq((void*)t, (void*)fnty, m)) { return -1; }
    if(!testing::expect_eq((void*)na.resolved, (void*)hd, m)) { return -2; }
    return 0;
}

fn i32 ns_import_non_exported(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "main");
    sema::Sema s = mk_sema(mm);
    sema::Scope* main_scope = sema::scope_new(a, null, 16);
    s.scope = main_scope;
    module::Module* other = fresh_module(a);
    other.name = interner::intern("other");
    sema::Scope* other_scope = sema::scope_new(a, null, 16);
    other.global_scope = (void*)other_scope;
    symbol::Symbol* helper = interner::intern("helper");
    types::Type*[] noparams = {null, 0};
    register_fn(a, other_scope, helper, types::intern_fn_ptr(types::prim_i32(), noparams, false));
    symbol::Symbol* othername = interner::intern("other");
    sema::scope_add(main_scope, othername, fake_import_decl(a, othername, other));
    ast::AstNode* base = (ast::AstNode*)fake_ident(a, othername, 0);
    ast::NamespaceAccessNode* na = fake_ns_access(a, base, helper, 7);
    types::Type* t = sema::synth(&s, (ast::AstNode*)na);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "no member named helper", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 7, m)) { return -3; }
    return 0;
}

fn i32 ns_import_unknown_member(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "main");
    sema::Sema s = mk_sema(mm);
    sema::Scope* main_scope = sema::scope_new(a, null, 16);
    s.scope = main_scope;
    module::Module* other = fresh_module(a);
    other.name = interner::intern("other");
    other.global_scope = (void*)sema::scope_new(a, null, 16);
    symbol::Symbol* othername = interner::intern("other");
    sema::scope_add(main_scope, othername, fake_import_decl(a, othername, other));
    ast::AstNode* base = (ast::AstNode*)fake_ident(a, othername, 0);
    ast::NamespaceAccessNode* na = fake_ns_access(a, base, interner::intern("missing"), 4);
    types::Type* t = sema::synth(&s, (ast::AstNode*)na);
    if(!testing::expect_eq((void*)t, null, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "no member named missing", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 4, m)) { return -3; }
    return 0;
}

fn i32 ns_nested_mod_enum_member(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "main");
    sema::Sema s = mk_sema(mm);
    sema::Scope* main_scope = sema::scope_new(a, null, 16);
    s.scope = main_scope;
    module::Module* other = fresh_module(a);
    other.name = interner::intern("other");
    sema::Scope* other_scope = sema::scope_new(a, null, 16);
    other.global_scope = (void*)other_scope;
    types::Type* ety = register_color_enum(a, other_scope);
    symbol::Symbol* othername = interner::intern("other");
    sema::scope_add(main_scope, othername, fake_import_decl(a, othername, other));
    ast::AstNode* base_mod = (ast::AstNode*)fake_ident(a, othername, 0);
    ast::AstNode* base_enum = (ast::AstNode*)fake_ns_access(a, base_mod, interner::intern("Color"), 0);
    ast::NamespaceAccessNode* na = fake_ns_access(a, base_enum, interner::intern("Red"), 0);
    types::Type* t = sema::synth(&s, (ast::AstNode*)na);
    if(!testing::expect_eq((void*)t, (void*)ety, m)) { return -1; }
    if(!testing::expect_true(has_flag((ast::AstNode*)na, ast::AstFlags::ConstExpr), m)) { return -2; }
    return 0;
}

fn i32 slit_positional(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    types::Type* point = mk_point_type(a);
    ast::FieldInitializer[2] inits;
    set_init(&inits[0], null, (ast::AstNode*)fake_int_lit(a, 1, 0), 0);
    set_init(&inits[1], null, (ast::AstNode*)fake_int_lit(a, 2, 0), 0);
    ast::StructLitNode* lit = fake_struct_lit_with(a, &inits[0], 2, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, point);
    if(!testing::expect_true(ok, m)) { return -1; }
    if(!testing::expect_eq((void*)lit.h.ty, (void*)point, m)) { return -2; }
    return 0;
}

fn i32 slit_designated(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    types::Type* point = mk_point_type(a);
    ast::FieldInitializer[2] inits;
    set_init(&inits[0], interner::intern("y"), (ast::AstNode*)fake_int_lit(a, 2, 0), 0);
    set_init(&inits[1], interner::intern("x"), (ast::AstNode*)fake_int_lit(a, 1, 0), 0);
    ast::StructLitNode* lit = fake_struct_lit_with(a, &inits[0], 2, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, point);
    if(!testing::expect_true(ok, m)) { return -1; }
    return 0;
}

fn i32 slit_mixed(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    types::Type* point = mk_point_type(a);
    ast::FieldInitializer[2] inits;
    set_init(&inits[0], null, (ast::AstNode*)fake_int_lit(a, 1, 0), 0);
    set_init(&inits[1], interner::intern("y"), (ast::AstNode*)fake_int_lit(a, 2, 0), 0);
    ast::StructLitNode* lit = fake_struct_lit_with(a, &inits[0], 2, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, point);
    if(!testing::expect_true(ok, m)) { return -1; }
    return 0;
}

fn i32 slit_unknown_field(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    types::Type* point = mk_point_type(a);
    ast::FieldInitializer[1] inits;
    set_init(&inits[0], interner::intern("z"), (ast::AstNode*)fake_int_lit(a, 1, 0), 6);
    ast::StructLitNode* lit = fake_struct_lit_with(a, &inits[0], 1, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, point);
    if(!testing::expect_true(!ok, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "type Point has no field z", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 6, m)) { return -3; }
    return 0;
}

fn i32 slit_duplicate(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    types::Type* point = mk_point_type(a);
    ast::FieldInitializer[2] inits;
    set_init(&inits[0], interner::intern("x"), (ast::AstNode*)fake_int_lit(a, 1, 0), 0);
    set_init(&inits[1], interner::intern("x"), (ast::AstNode*)fake_int_lit(a, 2, 0), 8);
    ast::StructLitNode* lit = fake_struct_lit_with(a, &inits[0], 2, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, point);
    if(!testing::expect_true(!ok, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "duplicate field x in literal", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 8, m)) { return -3; }
    return 0;
}

fn i32 slit_extra_positional(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    types::Type* point = mk_point_type(a);
    ast::FieldInitializer[3] inits;
    set_init(&inits[0], null, (ast::AstNode*)fake_int_lit(a, 1, 0), 0);
    set_init(&inits[1], null, (ast::AstNode*)fake_int_lit(a, 2, 0), 0);
    set_init(&inits[2], null, (ast::AstNode*)fake_int_lit(a, 3, 0), 9);
    ast::StructLitNode* lit = fake_struct_lit_with(a, &inits[0], 3, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, point);
    if(!testing::expect_true(!ok, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "too many initializers", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 9, m)) { return -3; }
    return 0;
}

fn i32 slit_field_type_mismatch(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    types::Type* point = mk_point_type(a);
    ast::FieldInitializer[1] inits;
    set_init(&inits[0], interner::intern("x"), (ast::AstNode*)fake_float_lit(a, 1.0, 4), 0);
    ast::StructLitNode* lit = fake_struct_lit_with(a, &inits[0], 1, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, point);
    if(!testing::expect_true(!ok, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "expected i32, found f64", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 4, m)) { return -3; }
    return 0;
}

fn i32 slit_non_struct_target(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::FieldInitializer[1] inits;
    set_init(&inits[0], null, (ast::AstNode*)fake_int_lit(a, 1, 0), 0);
    ast::StructLitNode* lit = fake_struct_lit_with(a, &inits[0], 1, 5);
    bool ok = sema::check(&s, (ast::AstNode*)lit, types::prim_i32());
    if(!testing::expect_true(!ok, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "cannot use struct literal as i32", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 5, m)) { return -3; }
    return 0;
}

fn i32 alit_exact(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    types::Type* arr = types::intern_array(types::prim_i32(), 3);
    ast::AstNode*[3] elems; elems[0] = (ast::AstNode*)fake_int_lit(a, 1, 0); elems[1] = (ast::AstNode*)fake_int_lit(a, 2, 0); elems[2] = (ast::AstNode*)fake_int_lit(a, 3, 0);
    ast::ArrayLitNode* lit = fake_array_lit_with(a, &elems[0], 3, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, arr);
    if(!testing::expect_true(ok, m)) { return -1; }
    if(!testing::expect_eq((void*)lit.h.ty, (void*)arr, m)) { return -2; }
    return 0;
}

fn i32 alit_count_mismatch(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    types::Type* arr = types::intern_array(types::prim_i32(), 3);
    ast::AstNode*[2] elems; elems[0] = (ast::AstNode*)fake_int_lit(a, 1, 0); elems[1] = (ast::AstNode*)fake_int_lit(a, 2, 0);
    ast::ArrayLitNode* lit = fake_array_lit_with(a, &elems[0], 2, 3);
    bool ok = sema::check(&s, (ast::AstNode*)lit, arr);
    if(!testing::expect_true(!ok, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "array literal has 2 elements but 3 expected", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 3, m)) { return -3; }
    return 0;
}

fn i32 alit_slice_target(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    types::Type* slice = types::intern_slice(types::prim_i32());
    ast::AstNode*[2] elems; elems[0] = (ast::AstNode*)fake_int_lit(a, 1, 0); elems[1] = (ast::AstNode*)fake_int_lit(a, 2, 0);
    ast::ArrayLitNode* lit = fake_array_lit_with(a, &elems[0], 2, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, slice);
    if(!testing::expect_true(ok, m)) { return -1; }
    return 0;
}

fn i32 alit_elem_mismatch(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    types::Type* arr = types::intern_array(types::prim_i32(), 2);
    ast::AstNode*[2] elems; elems[0] = (ast::AstNode*)fake_int_lit(a, 1, 0); elems[1] = (ast::AstNode*)fake_float_lit(a, 2.0, 7);
    ast::ArrayLitNode* lit = fake_array_lit_with(a, &elems[0], 2, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, arr);
    if(!testing::expect_true(!ok, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "expected i32, found f64", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 7, m)) { return -3; }
    return 0;
}

fn i32 alit_non_array_target(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    ast::AstNode*[1] elems; elems[0] = (ast::AstNode*)fake_int_lit(a, 1, 0);
    ast::ArrayLitNode* lit = fake_array_lit_with(a, &elems[0], 1, 2);
    bool ok = sema::check(&s, (ast::AstNode*)lit, types::prim_i32());
    if(!testing::expect_true(!ok, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "cannot use array literal as i32", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 2, m)) { return -3; }
    return 0;
}

fn i32 sllit_designated(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* slice = types::intern_slice(types::prim_i32());
    symbol::Symbol* p = interner::intern("p");
    register_var(a, sc, p, types::intern_pointer(types::prim_i32(), false), false);
    ast::FieldInitializer[2] inits;
    set_init(&inits[0], interner::intern("ptr"), (ast::AstNode*)fake_ident(a, p, 0), 0);
    set_init(&inits[1], interner::intern("len"), (ast::AstNode*)fake_int_lit(a, 3, 0), 0);
    ast::StructLitNode* lit = fake_struct_lit_with(a, &inits[0], 2, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, slice);
    if(!testing::expect_true(ok, m)) { return -1; }
    if(!testing::expect_eq((void*)lit.h.ty, (void*)slice, m)) { return -2; }
    return 0;
}

fn i32 sllit_positional(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* slice = types::intern_slice(types::prim_i32());
    symbol::Symbol* p = interner::intern("p");
    register_var(a, sc, p, types::intern_pointer(types::prim_i32(), false), false);
    ast::FieldInitializer[2] inits;
    set_init(&inits[0], null, (ast::AstNode*)fake_ident(a, p, 0), 0);
    set_init(&inits[1], null, (ast::AstNode*)fake_int_lit(a, 3, 0), 0);
    ast::StructLitNode* lit = fake_struct_lit_with(a, &inits[0], 2, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, slice);
    if(!testing::expect_true(ok, m)) { return -1; }
    return 0;
}

fn i32 sllit_unknown_field(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    types::Type* slice = types::intern_slice(types::prim_i32());
    ast::FieldInitializer[1] inits;
    set_init(&inits[0], interner::intern("foo"), (ast::AstNode*)fake_int_lit(a, 1, 0), 5);
    ast::StructLitNode* lit = fake_struct_lit_with(a, &inits[0], 1, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, slice);
    if(!testing::expect_true(!ok, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "type i32[] has no field foo", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 5, m)) { return -3; }
    return 0;
}

fn i32 sllit_ptr_type_mismatch(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    sema::Sema s = mk_sema(mm);
    sema::Scope* sc = sema::scope_new(a, null, 16);
    s.scope = sc;
    types::Type* slice = types::intern_slice(types::prim_i32());
    symbol::Symbol* v = interner::intern("v");
    register_var(a, sc, v, types::prim_i32(), false);
    ast::FieldInitializer[2] inits;
    set_init(&inits[0], interner::intern("ptr"), (ast::AstNode*)fake_ident(a, v, 3), 0);
    set_init(&inits[1], interner::intern("len"), (ast::AstNode*)fake_int_lit(a, 3, 0), 0);
    ast::StructLitNode* lit = fake_struct_lit_with(a, &inits[0], 2, 0);
    bool ok = sema::check(&s, (ast::AstNode*)lit, slice);
    if(!testing::expect_true(!ok, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "expected i32*, found i32", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 3, m)) { return -3; }
    return 0;
}

fn i32 st_local_var_ok(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode* vd = fake_local_var(a, interner::intern("x"), mk_ty_prim(a, token::TokenKind::I32), (ast::AstNode*)fake_int_lit(a, 5, 0), 0);
    ast::AstNode*[1] stmts; stmts[0] = vd;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 1)));
    if(!testing::expect_eq(mm.diag.entries.len, 0, m)) { return -1; }
    return 0;
}

fn i32 st_local_var_type_mismatch(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode* vd = fake_local_var(a, interner::intern("x"), mk_ty_prim(a, token::TokenKind::I32), (ast::AstNode*)fake_float_lit(a, 1.0, 12), 0);
    ast::AstNode*[1] stmts; stmts[0] = vd;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 1)));
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "expected i32, found f64", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 12, m)) { return -3; }
    return 0;
}

fn i32 st_local_var_use(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode* vx = fake_local_var(a, interner::intern("x"), mk_ty_prim(a, token::TokenKind::I32), (ast::AstNode*)fake_int_lit(a, 5, 0), 0);
    ast::AstNode* vy = fake_local_var(a, interner::intern("y"), mk_ty_prim(a, token::TokenKind::I32), (ast::AstNode*)fake_ident(a, interner::intern("x"), 0), 0);
    ast::AstNode*[2] stmts; stmts[0] = vx; stmts[1] = vy;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 2)));
    if(!testing::expect_eq(mm.diag.entries.len, 0, m)) { return -1; }
    return 0;
}

fn i32 st_local_var_undefined_use(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode* vy = fake_local_var(a, interner::intern("y"), mk_ty_prim(a, token::TokenKind::I32), (ast::AstNode*)fake_ident(a, interner::intern("nope"), 14), 0);
    ast::AstNode*[1] stmts; stmts[0] = vy;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 1)));
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "undefined identifier nope", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 14, m)) { return -3; }
    return 0;
}

fn i32 st_duplicate_local(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode* v1 = fake_local_var(a, interner::intern("x"), mk_ty_prim(a, token::TokenKind::I32), (ast::AstNode*)fake_int_lit(a, 1, 0), 0);
    ast::AstNode* v2 = fake_local_var(a, interner::intern("x"), mk_ty_prim(a, token::TokenKind::I32), (ast::AstNode*)fake_int_lit(a, 2, 0), 20);
    ast::AstNode*[2] stmts; stmts[0] = v1; stmts[1] = v2;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 2)));
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "duplicate declaration of x", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 20, m)) { return -3; }
    return 0;
}

fn i32 st_return_value_ok(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode* r = fake_return(a, (ast::AstNode*)fake_int_lit(a, 5, 0), 0);
    ast::AstNode*[1] stmts; stmts[0] = r;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), mk_ty_prim(a, token::TokenKind::I32), mk_block(a, &stmts[0], 1)));
    if(!testing::expect_eq(mm.diag.entries.len, 0, m)) { return -1; }
    return 0;
}

fn i32 st_return_mismatch(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode* r = fake_return(a, (ast::AstNode*)fake_float_lit(a, 1.0, 8), 0);
    ast::AstNode*[1] stmts; stmts[0] = r;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), mk_ty_prim(a, token::TokenKind::I32), mk_block(a, &stmts[0], 1)));
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "expected i32, found f64", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 8, m)) { return -3; }
    return 0;
}

fn i32 st_return_value_in_void(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode* r = fake_return(a, (ast::AstNode*)fake_int_lit(a, 5, 0), 3);
    ast::AstNode*[1] stmts; stmts[0] = r;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 1)));
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "cannot return a value from a void function", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 3, m)) { return -3; }
    return 0;
}

fn i32 st_return_missing_value(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode* r = fake_return(a, null, 6);
    ast::AstNode*[1] stmts; stmts[0] = r;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), mk_ty_prim(a, token::TokenKind::I32), mk_block(a, &stmts[0], 1)));
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "missing return value; function returns i32", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 6, m)) { return -3; }
    return 0;
}

fn i32 st_return_void_ok(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode* r = fake_return(a, null, 0);
    ast::AstNode*[1] stmts; stmts[0] = r;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 1)));
    if(!testing::expect_eq(mm.diag.entries.len, 0, m)) { return -1; }
    return 0;
}

fn i32 st_if_ok(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode* iff = fake_if(a, (ast::AstNode*)fake_bool_lit(a, true, 0), mk_block(a, null, 0), null, 0);
    ast::AstNode*[1] stmts; stmts[0] = iff;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 1)));
    if(!testing::expect_eq(mm.diag.entries.len, 0, m)) { return -1; }
    return 0;
}

fn i32 st_if_int_cond_ok(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode* iff = fake_if(a, (ast::AstNode*)fake_int_lit(a, 1, 0), mk_block(a, null, 0), null, 0);
    ast::AstNode*[1] stmts; stmts[0] = iff;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 1)));
    if(!testing::expect_eq(mm.diag.entries.len, 0, m)) { return -1; }
    return 0;
}

fn i32 st_if_cond_not_bool(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode* iff = fake_if(a, (ast::AstNode*)fake_float_lit(a, 1.0, 10), mk_block(a, null, 0), null, 0);
    ast::AstNode*[1] stmts; stmts[0] = iff;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 1)));
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "cannot use f64 in condition; expected bool, integer, pointer, or slice", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 10, m)) { return -3; }
    return 0;
}

fn i32 st_while_ok(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode* w = fake_while(a, (ast::AstNode*)fake_bool_lit(a, true, 0), mk_block(a, null, 0), 0);
    ast::AstNode*[1] stmts; stmts[0] = w;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 1)));
    if(!testing::expect_eq(mm.diag.entries.len, 0, m)) { return -1; }
    return 0;
}

fn i32 st_for_ok(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* i = interner::intern("i");
    ast::AstNode* init = fake_local_var(a, i, mk_ty_prim(a, token::TokenKind::I32), (ast::AstNode*)fake_int_lit(a, 0, 0), 0);
    ast::AstNode* cond = (ast::AstNode*)fake_binop(a, token::TokenKind::LT, (ast::AstNode*)fake_ident(a, i, 0), (ast::AstNode*)fake_int_lit(a, 10, 0), 0);
    ast::AstNode* post = fake_assign(a, token::TokenKind::PlusEq, (ast::AstNode*)fake_ident(a, i, 0), (ast::AstNode*)fake_int_lit(a, 1, 0), 0);
    ast::AstNode* forstmt = fake_for(a, init, cond, post, mk_block(a, null, 0), 0);
    ast::AstNode*[1] stmts; stmts[0] = forstmt;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 1)));
    if(!testing::expect_eq(mm.diag.entries.len, 0, m)) { return -1; }
    return 0;
}

fn i32 st_break_in_loop_ok(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode*[1] body_stmts; body_stmts[0] = fake_break(a, 0);
    ast::AstNode* w = fake_while(a, (ast::AstNode*)fake_bool_lit(a, true, 0), mk_block(a, &body_stmts[0], 1), 0);
    ast::AstNode*[1] stmts; stmts[0] = w;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 1)));
    if(!testing::expect_eq(mm.diag.entries.len, 0, m)) { return -1; }
    return 0;
}

fn i32 st_break_outside(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode*[1] stmts; stmts[0] = fake_break(a, 5);
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 1)));
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "break outside loop or switch", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 5, m)) { return -3; }
    return 0;
}

fn i32 st_continue_outside(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode*[1] stmts; stmts[0] = fake_continue(a, 4);
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 1)));
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "continue outside loop", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 4, m)) { return -3; }
    return 0;
}

fn i32 st_break_in_switch_ok(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode*[1] arm_body; arm_body[0] = fake_break(a, 0);
    ast::AstNode*[1] labels; labels[0] = (ast::AstNode*)fake_int_lit(a, 1, 0);
    ast::SwitchArm[1] arms;
    arms[0].labels = {&labels[0], 1};
    arms[0].body = mk_block(a, &arm_body[0], 1);
    arms[0].src_pos = 0;
    ast::AstNode* sw = fake_switch(a, (ast::AstNode*)fake_int_lit(a, 1, 0), &arms[0], 1, null, 0);
    ast::AstNode*[1] stmts; stmts[0] = sw;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 1)));
    if(!testing::expect_eq(mm.diag.entries.len, 0, m)) { return -1; }
    return 0;
}

fn i32 st_assign_ok(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* x = interner::intern("x");
    ast::AstNode* vd = fake_local_var(a, x, mk_ty_prim(a, token::TokenKind::I32), (ast::AstNode*)fake_int_lit(a, 0, 0), 0);
    ast::AstNode* asg = fake_assign(a, token::TokenKind::Eq, (ast::AstNode*)fake_ident(a, x, 0), (ast::AstNode*)fake_int_lit(a, 5, 0), 0);
    ast::AstNode*[2] stmts; stmts[0] = vd; stmts[1] = asg;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 2)));
    if(!testing::expect_eq(mm.diag.entries.len, 0, m)) { return -1; }
    return 0;
}

fn i32 st_assign_non_lvalue(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode* asg = fake_assign(a, token::TokenKind::Eq, (ast::AstNode*)fake_int_lit(a, 5, 9), (ast::AstNode*)fake_int_lit(a, 3, 0), 0);
    ast::AstNode*[1] stmts; stmts[0] = asg;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 1)));
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "cannot assign to a non-lvalue", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 9, m)) { return -3; }
    return 0;
}

fn i32 st_assign_type_mismatch(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* x = interner::intern("x");
    ast::AstNode* vd = fake_local_var(a, x, mk_ty_prim(a, token::TokenKind::I32), (ast::AstNode*)fake_int_lit(a, 0, 0), 0);
    ast::AstNode* asg = fake_assign(a, token::TokenKind::Eq, (ast::AstNode*)fake_ident(a, x, 0), (ast::AstNode*)fake_float_lit(a, 1.0, 15), 0);
    ast::AstNode*[2] stmts; stmts[0] = vd; stmts[1] = asg;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 2)));
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "expected i32, found f64", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 15, m)) { return -3; }
    return 0;
}

fn i32 st_compound_assign_ok(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* x = interner::intern("x");
    ast::AstNode* vd = fake_local_var(a, x, mk_ty_prim(a, token::TokenKind::I32), (ast::AstNode*)fake_int_lit(a, 0, 0), 0);
    ast::AstNode* asg = fake_assign(a, token::TokenKind::PlusEq, (ast::AstNode*)fake_ident(a, x, 0), (ast::AstNode*)fake_int_lit(a, 5, 0), 0);
    ast::AstNode*[2] stmts; stmts[0] = vd; stmts[1] = asg;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 2)));
    if(!testing::expect_eq(mm.diag.entries.len, 0, m)) { return -1; }
    return 0;
}

fn i32 st_compound_assign_bad(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* b = interner::intern("b");
    ast::AstNode* vd = fake_local_var(a, b, mk_ty_prim(a, token::TokenKind::BOOL), (ast::AstNode*)fake_bool_lit(a, true, 0), 0);
    ast::AstNode* asg = fake_assign(a, token::TokenKind::PlusEq, (ast::AstNode*)fake_ident(a, b, 0), (ast::AstNode*)fake_int_lit(a, 5, 0), 18);
    ast::AstNode*[2] stmts; stmts[0] = vd; stmts[1] = asg;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 2)));
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "operator is not defined for bool and i32", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 18, m)) { return -3; }
    return 0;
}

fn i32 st_defer_ok(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode* d = fake_defer(a, mk_block(a, null, 0), 0);
    ast::AstNode*[1] stmts; stmts[0] = d;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 1)));
    if(!testing::expect_eq(mm.diag.entries.len, 0, m)) { return -1; }
    return 0;
}

fn i32 st_expr_stmt_ok(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    symbol::Symbol* x = interner::intern("x");
    ast::AstNode* vd = fake_local_var(a, x, mk_ty_prim(a, token::TokenKind::I32), (ast::AstNode*)fake_int_lit(a, 0, 0), 0);
    ast::AstNode* es = fake_expr_stmt(a, (ast::AstNode*)fake_binop(a, token::TokenKind::Plus, (ast::AstNode*)fake_ident(a, x, 0), (ast::AstNode*)fake_int_lit(a, 1, 0), 0), 0);
    ast::AstNode*[2] stmts; stmts[0] = vd; stmts[1] = es;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 2)));
    if(!testing::expect_eq(mm.diag.entries.len, 0, m)) { return -1; }
    return 0;
}

fn i32 st_block_scope_pops(arena::Arena* a, u8[] m) {
    module::Module* mm = run_module(a, "testmod");
    ast::AstNode*[1] inner; inner[0] = fake_local_var(a, interner::intern("x"), mk_ty_prim(a, token::TokenKind::I32), (ast::AstNode*)fake_int_lit(a, 0, 0), 0);
    ast::AstNode* nested = mk_block(a, &inner[0], 1);
    ast::AstNode* use = fake_expr_stmt(a, (ast::AstNode*)fake_ident(a, interner::intern("x"), 22), 0);
    ast::AstNode*[2] stmts; stmts[0] = nested; stmts[1] = use;
    run_fn(a, mm, mk_fn_body(a, interner::intern("f"), null, mk_block(a, &stmts[0], 2)));
    if(!testing::expect_ge(mm.diag.entries.len, 1, m)) { return -1; }
    if(!testing::expect_eq(mm.diag.entries[0].msg, "undefined identifier x", m)) { return -2; }
    if(!testing::expect_eq(mm.diag.entries[0].src_pos, 22, m)) { return -3; }
    return 0;
}

fn i32 main() {
    testing::init();

    u8[] sc = "Sema Scope Tests";
    testing::add(sc, "scope_new_returns_non_null",        &scope_new_returns_non_null);
    testing::add(sc, "scope_new_parent_null_for_module",  &scope_new_parent_null_for_module);
    testing::add(sc, "scope_new_records_parent",          &scope_new_records_parent);
    testing::add(sc, "scope_new_cap_matches",             &scope_new_cap_matches);
    testing::add(sc, "scope_new_count_zero",              &scope_new_count_zero);
    testing::add(sc, "scope_new_entries_allocated",       &scope_new_entries_allocated);
    testing::add(sc, "scope_new_entries_zeroed",          &scope_new_entries_zeroed);
    testing::add(sc, "scope_new_arena_bound",             &scope_new_arena_bound);

    testing::add(sc, "scope_add_first_returns_true",            &scope_add_first_returns_true);
    testing::add(sc, "scope_add_increments_count",              &scope_add_increments_count);
    testing::add(sc, "scope_add_duplicate_returns_false",       &scope_add_duplicate_returns_false);
    testing::add(sc, "scope_add_duplicate_does_not_change_count", &scope_add_duplicate_does_not_change_count);
    testing::add(sc, "scope_add_two_different_keys",            &scope_add_two_different_keys);

    testing::add(sc, "lookup_local_finds_inserted",         &lookup_local_finds_inserted);
    testing::add(sc, "lookup_local_returns_null_for_missing", &lookup_local_returns_null_for_missing);
    testing::add(sc, "lookup_local_does_not_walk_parent",   &lookup_local_does_not_walk_parent);

    testing::add(sc, "lookup_finds_in_self",                &lookup_finds_in_self);
    testing::add(sc, "lookup_walks_to_parent",              &lookup_walks_to_parent);
    testing::add(sc, "lookup_self_shadows_parent",          &lookup_self_shadows_parent);
    testing::add(sc, "lookup_walks_two_levels",             &lookup_walks_two_levels);
    testing::add(sc, "lookup_returns_null_when_not_in_chain", &lookup_returns_null_when_not_in_chain);

    testing::add(sc, "scope_grow_preserves_entries",        &scope_grow_preserves_entries);
    testing::add(sc, "scope_grow_cap_is_power_of_two",      &scope_grow_cap_is_power_of_two);

    u8[] rs = "Sema ResolutionStack Tests";
    testing::add(rs, "stack_empty_does_not_contain",        &stack_empty_does_not_contain);
    testing::add(rs, "stack_push_then_contains",            &stack_push_then_contains);
    testing::add(rs, "stack_push_pop_no_longer_contains",   &stack_push_pop_no_longer_contains);
    testing::add(rs, "stack_distinguishes_module",          &stack_distinguishes_module);
    testing::add(rs, "stack_distinguishes_name",            &stack_distinguishes_name);
    testing::add(rs, "stack_multi_push_all_contained",      &stack_multi_push_all_contained);
    testing::add(rs, "stack_pop_only_removes_top",          &stack_pop_only_removes_top);

    u8[] dh = "Sema Decl Helper Tests";
    testing::add(dh, "lvalue_var_non_const_true",  &lvalue_var_non_const_true);
    testing::add(dh, "lvalue_var_const_true",      &lvalue_var_const_true);
    testing::add(dh, "lvalue_fn_false",            &lvalue_fn_false);
    testing::add(dh, "lvalue_param_true",          &lvalue_param_true);
    testing::add(dh, "lvalue_field_true",          &lvalue_field_true);
    testing::add(dh, "lvalue_enum_member_false",   &lvalue_enum_member_false);
    testing::add(dh, "lvalue_import_false",        &lvalue_import_false);

    testing::add(dh, "constexpr_var_const_true",     &constexpr_var_const_true);
    testing::add(dh, "constexpr_var_non_const_false", &constexpr_var_non_const_false);
    testing::add(dh, "constexpr_enum_member_true",   &constexpr_enum_member_true);
    testing::add(dh, "constexpr_fn_true",            &constexpr_fn_true);
    testing::add(dh, "constexpr_param_false",        &constexpr_param_false);
    testing::add(dh, "constexpr_field_false",        &constexpr_field_false);
    testing::add(dh, "constexpr_import_false",       &constexpr_import_false);

    u8[] cd = "Sema container_decl Tests";
    testing::add(cd, "container_decl_for_struct",         &container_decl_for_struct);
    testing::add(cd, "container_decl_for_union",          &container_decl_for_union);
    testing::add(cd, "container_decl_for_primitive_null", &container_decl_for_primitive_null);
    testing::add(cd, "container_decl_for_pointer_null",   &container_decl_for_pointer_null);
    testing::add(cd, "container_decl_for_slice_null",     &container_decl_for_slice_null);

    u8[] ff = "Sema Field / Enum Lookup Tests";
    testing::add(ff, "find_field_returns_existing",       &find_field_returns_existing);
    testing::add(ff, "find_field_returns_null_for_missing", &find_field_returns_null_for_missing);
    testing::add(ff, "find_field_empty_returns_null",     &find_field_empty_returns_null);
    testing::add(ff, "find_field_works_on_union",         &find_field_works_on_union);
    testing::add(ff, "find_field_index_first",            &find_field_index_first);
    testing::add(ff, "find_field_index_last",             &find_field_index_last);
    testing::add(ff, "find_field_index_missing_is_max",   &find_field_index_missing_is_max);
    testing::add(ff, "find_enum_member_existing",         &find_enum_member_existing);
    testing::add(ff, "find_enum_member_missing",          &find_enum_member_missing);
    testing::add(ff, "find_enum_member_empty",            &find_enum_member_empty);

    u8[] mk = "Sema make_*_decl Tests";
    testing::add(mk, "make_field_decl_kind",            &make_field_decl_kind);
    testing::add(mk, "make_field_decl_name_set",        &make_field_decl_name_set);
    testing::add(mk, "make_field_decl_ty_set",          &make_field_decl_ty_set);
    testing::add(mk, "make_field_decl_data_field_set",  &make_field_decl_data_field_set);
    testing::add(mk, "make_enum_member_decl_kind",      &make_enum_member_decl_kind);
    testing::add(mk, "make_enum_member_decl_name_set",  &make_enum_member_decl_name_set);
    testing::add(mk, "make_enum_member_decl_ty_set",    &make_enum_member_decl_ty_set);
    testing::add(mk, "make_enum_member_decl_data_set",  &make_enum_member_decl_data_set);

    u8[] dg = "Sema Diagnostic Tests";
    testing::add(dg, "diag_type_mismatch_emits_one_entry",       &diag_type_mismatch_emits_one_entry);
    testing::add(dg, "diag_type_mismatch_records_src_pos",       &diag_type_mismatch_records_src_pos);
    testing::add(dg, "diag_type_mismatch_mentions_expected",     &diag_type_mismatch_mentions_expected);
    testing::add(dg, "diag_type_mismatch_mentions_got",          &diag_type_mismatch_mentions_got);
    testing::add(dg, "diag_type_mismatch_is_error_not_warning",  &diag_type_mismatch_is_error_not_warning);
    testing::add(dg, "diag_lit_overflow_emits_entry",            &diag_lit_overflow_emits_entry);
    testing::add(dg, "diag_lit_overflow_mentions_type",          &diag_lit_overflow_mentions_type);
    testing::add(dg, "diag_lit_overflow_mentions_value",         &diag_lit_overflow_mentions_value);
    testing::add(dg, "diag_cast_invalid_mentions_both_types",    &diag_cast_invalid_mentions_both_types);
    testing::add(dg, "diag_binop_mismatch_mentions_both_types",  &diag_binop_mismatch_mentions_both_types);
    testing::add(dg, "diag_not_bool_convertible_mentions_type",  &diag_not_bool_convertible_mentions_type);
    testing::add(dg, "diag_resolution_cycle_emits_entry",        &diag_resolution_cycle_emits_entry);
    testing::add(dg, "diag_resolution_cycle_mentions_name",      &diag_resolution_cycle_mentions_name);
    testing::add(dg, "diag_needs_context_emits_entry",           &diag_needs_context_emits_entry);

    u8[] ci = "Sema check_int_lit Tests";
    testing::add(ci, "check_int_lit_positive_fits_u8",     &check_int_lit_positive_fits_u8);
    testing::add(ci, "check_int_lit_sets_ty_on_success",   &check_int_lit_sets_ty_on_success);
    testing::add(ci, "check_int_lit_overflow_returns_false", &check_int_lit_overflow_returns_false);
    testing::add(ci, "check_int_lit_overflow_emits_diag",  &check_int_lit_overflow_emits_diag);
    testing::add(ci, "check_int_lit_overflow_sets_had_error", &check_int_lit_overflow_sets_had_error);
    testing::add(ci, "check_int_lit_float_target_rejected", &check_int_lit_float_target_rejected);
    testing::add(ci, "check_int_lit_fits_largest_u64",     &check_int_lit_fits_largest_u64);
    testing::add(ci, "check_int_lit_zero_fits_any_int",    &check_int_lit_zero_fits_any_int);

    testing::add(sc, "scope_add_duplicate_keeps_first",    &scope_add_duplicate_keeps_first);

    u8[] cn = "Sema collect_names Tests";
    testing::add(cn, "cn_registers_single_fn",           &cn_registers_single_fn);
    testing::add(cn, "cn_fn_not_exported",               &cn_fn_not_exported);
    testing::add(cn, "cn_fn_qualified_name",             &cn_fn_qualified_name);
    testing::add(cn, "cn_all_decl_kinds_registered",     &cn_all_decl_kinds_registered);
    testing::add(cn, "cn_var_qualified_and_exported",    &cn_var_qualified_and_exported);
    testing::add(cn, "cn_duplicate_one_diag_exact",      &cn_duplicate_one_diag_exact);
    testing::add(cn, "cn_two_distinct_no_diag",          &cn_two_distinct_no_diag);
    testing::add(cn, "cn_import_resolves_module",        &cn_import_resolves_module);
    testing::add(cn, "cn_import_reexport_no_match",      &cn_import_reexport_no_match);
    testing::add(cn, "cn_extern_block_items_registered", &cn_extern_block_items_registered);
    testing::add(cn, "cn_extern_var_qualified",          &cn_extern_var_qualified);
    testing::add(cn, "cn_sets_names_phase",              &cn_sets_names_phase);
    testing::add(cn, "cn_null_root_no_crash",            &cn_null_root_no_crash);
    testing::add(cn, "cn_empty_block_no_decls",          &cn_empty_block_no_decls);
    testing::add(cn, "cn_idempotent_second_run",         &cn_idempotent_second_run);
    testing::add(cn, "cn_non_decl_skipped",              &cn_non_decl_skipped);
    testing::add(cn, "cn_combined_mixed",                &cn_combined_mixed);

    u8[] sig = "Sema Signature Resolution Tests";
    testing::add(sig, "rs_var_primitive",         &rs_var_primitive);
    testing::add(sig, "rs_var_pointer",           &rs_var_pointer);
    testing::add(sig, "rs_var_const_pointer",     &rs_var_const_pointer);
    testing::add(sig, "rs_var_slice",             &rs_var_slice);
    testing::add(sig, "rs_var_array",             &rs_var_array);
    testing::add(sig, "rs_var_identity",          &rs_var_identity);
    testing::add(sig, "rs_fn_void_no_params",     &rs_fn_void_no_params);
    testing::add(sig, "rs_fn_return_and_params",  &rs_fn_return_and_params);
    testing::add(sig, "rs_struct_fields",         &rs_struct_fields);
    testing::add(sig, "rs_enum_base",             &rs_enum_base);
    testing::add(sig, "rs_alias_dissolves",       &rs_alias_dissolves);
    testing::add(sig, "rs_sets_signatures_phase", &rs_sets_signatures_phase);

    u8[] rnt = "Sema Named Type Resolution Tests";
    testing::add(rnt, "rnt_named_struct",           &rnt_named_struct);
    testing::add(rnt, "rnt_named_enum",             &rnt_named_enum);
    testing::add(rnt, "rnt_named_union",            &rnt_named_union);
    testing::add(rnt, "rnt_named_in_pointer",       &rnt_named_in_pointer);
    testing::add(rnt, "rnt_named_in_slice",         &rnt_named_in_slice);
    testing::add(rnt, "rnt_named_as_field",         &rnt_named_as_field);
    testing::add(rnt, "rnt_alias_to_primitive",     &rnt_alias_to_primitive);
    testing::add(rnt, "rnt_alias_to_pointer",       &rnt_alias_to_pointer);
    testing::add(rnt, "rnt_alias_to_named",         &rnt_alias_to_named);
    testing::add(rnt, "rnt_alias_chain",            &rnt_alias_chain);
    testing::add(rnt, "rnt_alias_cycle_reports",    &rnt_alias_cycle_reports);
    testing::add(rnt, "rnt_unknown_name_reports",   &rnt_unknown_name_reports);
    testing::add(rnt, "rnt_order_independent",      &rnt_order_independent);
    testing::add(rnt, "rnt_identity",               &rnt_identity);
    testing::add(rnt, "rnt_cross_module_struct",    &rnt_cross_module_struct);
    testing::add(rnt, "rnt_cross_module_not_exported_reports", &rnt_cross_module_not_exported_reports);
    testing::add(rnt, "rnt_non_type_used_as_type",  &rnt_non_type_used_as_type);
    testing::add(rnt, "rnt_qualified_namespace_not_imported", &rnt_qualified_namespace_not_imported);
    testing::add(rnt, "rnt_qualified_name_not_in_target", &rnt_qualified_name_not_in_target);
    testing::add(rnt, "rnt_self_alias_cycle_reports", &rnt_self_alias_cycle_reports);
    testing::add(rnt, "rnt_alias_to_unknown_reports", &rnt_alias_to_unknown_reports);
    testing::add(rnt, "rnt_fn_named_param_return",  &rnt_fn_named_param_return);

    u8[] syn = "Sema Synth Tests";
    testing::add(syn, "synth_int_lit_i32",   &synth_int_lit_i32);
    testing::add(syn, "synth_int_lit_i64",   &synth_int_lit_i64);
    testing::add(syn, "synth_int_lit_u64",   &synth_int_lit_u64);
    testing::add(syn, "synth_float_lit",     &synth_float_lit);
    testing::add(syn, "synth_bool_lit",      &synth_bool_lit);
    testing::add(syn, "synth_char_lit",      &synth_char_lit);
    testing::add(syn, "synth_string_lit",    &synth_string_lit);
    testing::add(syn, "synth_null_lit",      &synth_null_lit);
    testing::add(syn, "synth_struct_lit_needs_context", &synth_struct_lit_needs_context);
    testing::add(syn, "synth_array_lit_needs_context",  &synth_array_lit_needs_context);
    testing::add(syn, "synth_undefined_needs_context",  &synth_undefined_needs_context);
    testing::add(syn, "synth_ident_var",         &synth_ident_var);
    testing::add(syn, "synth_ident_param",       &synth_ident_param);
    testing::add(syn, "synth_ident_const_var",   &synth_ident_const_var);
    testing::add(syn, "synth_ident_fn",          &synth_ident_fn);
    testing::add(syn, "synth_ident_enum_member", &synth_ident_enum_member);
    testing::add(syn, "synth_ident_undefined",   &synth_ident_undefined);

    u8[] chk = "Sema Check Tests";
    testing::add(chk, "check_int_lit_fits_u8",     &check_int_lit_fits_u8);
    testing::add(chk, "check_int_lit_overflow_u8", &check_int_lit_overflow_u8);
    testing::add(chk, "check_null_to_ptr",         &check_null_to_ptr);
    testing::add(chk, "check_null_to_slice",       &check_null_to_slice);
    testing::add(chk, "check_null_to_int_fails",   &check_null_to_int_fails);
    testing::add(chk, "check_float_to_int_fails",  &check_float_to_int_fails);
    testing::add(chk, "check_undefined_to_type",   &check_undefined_to_type);
    testing::add(chk, "check_bool_ok",             &check_bool_ok);
    testing::add(chk, "check_ident_widen",         &check_ident_widen);
    testing::add(chk, "check_ident_narrow_fails",  &check_ident_narrow_fails);
    testing::add(chk, "check_char_to_u8",          &check_char_to_u8);
    testing::add(chk, "check_string_to_u8_ptr",    &check_string_to_u8_ptr);

    u8[] binu = "Sema Binary/Unary Tests";
    testing::add(binu, "bin_add_two_lits",          &bin_add_two_lits);
    testing::add(binu, "bin_comparison_is_bool",    &bin_comparison_is_bool);
    testing::add(binu, "bin_logical_is_bool",       &bin_logical_is_bool);
    testing::add(binu, "bin_nested_const",          &bin_nested_const);
    testing::add(binu, "bin_non_const_operand",     &bin_non_const_operand);
    testing::add(binu, "bin_mismatch_reports",      &bin_mismatch_reports);
    testing::add(binu, "bin_operand_error_propagates", &bin_operand_error_propagates);
    testing::add(binu, "un_neg_int",                &un_neg_int);
    testing::add(binu, "un_not_bool",               &un_not_bool);
    testing::add(binu, "un_complement_int",         &un_complement_int);
    testing::add(binu, "un_complement_float_fails", &un_complement_float_fails);
    testing::add(binu, "un_deref_ptr",              &un_deref_ptr);
    testing::add(binu, "un_deref_non_ptr_fails",    &un_deref_non_ptr_fails);
    testing::add(binu, "un_addr_of_lvalue",         &un_addr_of_lvalue);
    testing::add(binu, "un_addr_of_non_lvalue_fails", &un_addr_of_non_lvalue_fails);
    testing::add(binu, "un_operand_error_propagates", &un_operand_error_propagates);
    testing::add(binu, "check_fused_neg_fits",      &check_fused_neg_fits);
    testing::add(binu, "check_fused_neg_overflow",  &check_fused_neg_overflow);
    testing::add(binu, "check_fused_neg_to_unsigned_fails", &check_fused_neg_to_unsigned_fails);

    u8[] acc = "Sema Access Tests";
    testing::add(acc, "member_struct_field",        &member_struct_field);
    testing::add(acc, "member_pointer_autoderef",   &member_pointer_autoderef);
    testing::add(acc, "member_slice_ptr",           &member_slice_ptr);
    testing::add(acc, "member_slice_len",           &member_slice_len);
    testing::add(acc, "member_slice_unknown_field", &member_slice_unknown_field);
    testing::add(acc, "member_unknown_struct_field", &member_unknown_struct_field);
    testing::add(acc, "member_on_non_aggregate",    &member_on_non_aggregate);
    testing::add(acc, "member_base_error",          &member_base_error);
    testing::add(acc, "index_array",                &index_array);
    testing::add(acc, "index_slice",                &index_slice);
    testing::add(acc, "index_pointer",              &index_pointer);
    testing::add(acc, "index_non_indexable",        &index_non_indexable);
    testing::add(acc, "index_bad_index_type",       &index_bad_index_type);
    testing::add(acc, "slice_range_of_array",       &slice_range_of_array);
    testing::add(acc, "slice_range_of_slice",       &slice_range_of_slice);
    testing::add(acc, "slice_range_of_pointer",     &slice_range_of_pointer);
    testing::add(acc, "slice_range_omit_lo",        &slice_range_omit_lo);
    testing::add(acc, "slice_range_omit_hi",        &slice_range_omit_hi);
    testing::add(acc, "slice_range_non_indexable",  &slice_range_non_indexable);
    testing::add(acc, "slice_range_bad_bound",      &slice_range_bad_bound);

    u8[] cc = "Sema Call/Cast Tests";
    testing::add(cc, "call_no_args",         &call_no_args);
    testing::add(cc, "call_one_arg",         &call_one_arg);
    testing::add(cc, "call_arg_widen",       &call_arg_widen);
    testing::add(cc, "call_arg_mismatch",    &call_arg_mismatch);
    testing::add(cc, "call_arity_too_few",   &call_arity_too_few);
    testing::add(cc, "call_arity_too_many",  &call_arity_too_many);
    testing::add(cc, "call_non_function",    &call_non_function);
    testing::add(cc, "call_variadic",        &call_variadic);
    testing::add(cc, "call_returns_void",    &call_returns_void);
    testing::add(cc, "call_callee_error",    &call_callee_error);
    testing::add(cc, "cast_int_to_int",      &cast_int_to_int);
    testing::add(cc, "cast_int_to_float",    &cast_int_to_float);
    testing::add(cc, "cast_float_to_int",    &cast_float_to_int);
    testing::add(cc, "cast_ptr_to_ptr",      &cast_ptr_to_ptr);
    testing::add(cc, "cast_const_propagation", &cast_const_propagation);
    testing::add(cc, "cast_invalid",         &cast_invalid);
    testing::add(cc, "cast_expr_error",      &cast_expr_error);

    u8[] ns = "Sema Namespace Access Tests";
    testing::add(ns, "ns_enum_member",           &ns_enum_member);
    testing::add(ns, "ns_enum_unknown_member",   &ns_enum_unknown_member);
    testing::add(ns, "ns_not_namespace",         &ns_not_namespace);
    testing::add(ns, "ns_base_undefined",        &ns_base_undefined);
    testing::add(ns, "ns_import_member",         &ns_import_member);
    testing::add(ns, "ns_import_non_exported",   &ns_import_non_exported);
    testing::add(ns, "ns_import_unknown_member", &ns_import_unknown_member);
    testing::add(ns, "ns_nested_mod_enum_member", &ns_nested_mod_enum_member);

    u8[] lit = "Sema Literal Check Tests";
    testing::add(lit, "slit_positional",          &slit_positional);
    testing::add(lit, "slit_designated",          &slit_designated);
    testing::add(lit, "slit_mixed",               &slit_mixed);
    testing::add(lit, "slit_unknown_field",       &slit_unknown_field);
    testing::add(lit, "slit_duplicate",           &slit_duplicate);
    testing::add(lit, "slit_extra_positional",    &slit_extra_positional);
    testing::add(lit, "slit_field_type_mismatch", &slit_field_type_mismatch);
    testing::add(lit, "slit_non_struct_target",   &slit_non_struct_target);
    testing::add(lit, "alit_exact",               &alit_exact);
    testing::add(lit, "alit_count_mismatch",      &alit_count_mismatch);
    testing::add(lit, "alit_slice_target",        &alit_slice_target);
    testing::add(lit, "alit_elem_mismatch",       &alit_elem_mismatch);
    testing::add(lit, "alit_non_array_target",    &alit_non_array_target);
    testing::add(lit, "sllit_designated",         &sllit_designated);
    testing::add(lit, "sllit_positional",         &sllit_positional);
    testing::add(lit, "sllit_unknown_field",      &sllit_unknown_field);
    testing::add(lit, "sllit_ptr_type_mismatch",  &sllit_ptr_type_mismatch);

    u8[] stm = "Sema Statement Tests";
    testing::add(stm, "st_local_var_ok",           &st_local_var_ok);
    testing::add(stm, "st_local_var_type_mismatch", &st_local_var_type_mismatch);
    testing::add(stm, "st_local_var_use",          &st_local_var_use);
    testing::add(stm, "st_local_var_undefined_use", &st_local_var_undefined_use);
    testing::add(stm, "st_duplicate_local",        &st_duplicate_local);
    testing::add(stm, "st_return_value_ok",        &st_return_value_ok);
    testing::add(stm, "st_return_mismatch",        &st_return_mismatch);
    testing::add(stm, "st_return_value_in_void",   &st_return_value_in_void);
    testing::add(stm, "st_return_missing_value",   &st_return_missing_value);
    testing::add(stm, "st_return_void_ok",         &st_return_void_ok);
    testing::add(stm, "st_if_ok",                  &st_if_ok);
    testing::add(stm, "st_if_int_cond_ok",         &st_if_int_cond_ok);
    testing::add(stm, "st_if_cond_not_bool",       &st_if_cond_not_bool);
    testing::add(stm, "st_while_ok",               &st_while_ok);
    testing::add(stm, "st_for_ok",                 &st_for_ok);
    testing::add(stm, "st_break_in_loop_ok",       &st_break_in_loop_ok);
    testing::add(stm, "st_break_outside",          &st_break_outside);
    testing::add(stm, "st_continue_outside",       &st_continue_outside);
    testing::add(stm, "st_break_in_switch_ok",     &st_break_in_switch_ok);
    testing::add(stm, "st_assign_ok",              &st_assign_ok);
    testing::add(stm, "st_assign_non_lvalue",      &st_assign_non_lvalue);
    testing::add(stm, "st_assign_type_mismatch",   &st_assign_type_mismatch);
    testing::add(stm, "st_compound_assign_ok",     &st_compound_assign_ok);
    testing::add(stm, "st_compound_assign_bad",    &st_compound_assign_bad);
    testing::add(stm, "st_defer_ok",               &st_defer_ok);
    testing::add(stm, "st_expr_stmt_ok",           &st_expr_stmt_ok);
    testing::add(stm, "st_block_scope_pops",       &st_block_scope_pops);

    return testing::run();
}
