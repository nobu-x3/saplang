import ast;
import arena;
import diag;
import interner;
import module;
import parser;
import scanner;
import symbol;
import sys;
import testing;
import token;

const u64 BUCKET_COUNT = 64;

// MODULE SETUP / DRIVER //////////////////////////////////////////////////////
export fn module::Module* prepare(arena::Arena* a, u8[] src) {
    interner::Interner* it = arena::alloc(a, sizeof(interner::Interner));
    u64 nbytes = BUCKET_COUNT * sizeof(symbol::Symbol*);
    void* raw = arena::alloc(a, nbytes);
    sys::memset(raw, 0, nbytes);
    it.slab_arena = a;
    it.slab = {null, 0};
    it.slab_cap = 0;
    it.buckets = {(symbol::Symbol**)raw, BUCKET_COUNT};
    it.entry_count = 0;
    for(u64 i = 0; i < token::KEYWORDS.len; i += 1) {
        symbol::Symbol* sym = interner::intern(it, token::KEYWORDS[i].bytes);
        sym.keyword_kind = (u16)token::KEYWORDS[i].kind;
    }
    module::Module* m = arena::alloc(a, sizeof(module::Module));
    m.name = null;
    m.source = src;
    m.line_starts = {null, 0};
    m.tokens = {null, 0};
    m.tokens_cap = 0;
    m.literal_pool = {null, 0};
    m.literal_pool_cap = 0;
    m.interner = it;
    m.arena = a;
    m.diag.entries = {null, 0};
    m.diag.entries_cap = 0;
    return m;
}

export fn ast::AstNode* parse_src(arena::Arena* a, u8[] src, module::Module** out_m) {
    module::Module* m = prepare(a, src);
    scanner::scan(m);
    ast::AstNode* root = parser::parse(m);
    *out_m = m;
    return root;
}

// NAVIGATION /////////////////////////////////////////////////////////////////
export fn ast::AstNode* nth_stmt(ast::AstNode* root, u64 i) {
    if(!root || root.h.kind != ast::AstKind::BlockStmt) { return null; }
    ast::BlockNode* b = (ast::BlockNode*)root;
    if(i >= b.stmts.len) { return null; }
    return b.stmts.ptr[i];
}

export fn ast::VarDeclNode* nth_var(ast::AstNode* root, u64 i) {
    ast::AstNode* s = nth_stmt(root, i);
    if(!s || s.h.kind != ast::AstKind::VarDecl) { return null; }
    return (ast::VarDeclNode*)s;
}

export fn ast::AstNode* var_init(ast::AstNode* root, u64 i) {
    ast::VarDeclNode* v = nth_var(root, i);
    if(!v) { return null; }
    return v.init;
}

export fn ast::AstNode* var_type(ast::AstNode* root, u64 i) {
    ast::VarDeclNode* v = nth_var(root, i);
    if(!v) { return null; }
    return v.type_expr;
}

export fn bool has_error_stmt(ast::AstNode* root) {
    if(!root || root.h.kind != ast::AstKind::BlockStmt) { return false; }
    ast::BlockNode* b = (ast::BlockNode*)root;
    for(u64 i = 0; i < b.stmts.len; i += 1) {
        if(b.stmts.ptr[i] && b.stmts.ptr[i].h.kind == ast::AstKind::ERROR) {
            return true;
        }
    }
    return false;
}

export fn bool has_error_flag(ast::AstNode* n) {
    if(!n) { return false; }
    return ((u16)n.h.flags & (u16)ast::AstFlags::HadError) != 0;
}

export fn bool has_paren_flag(ast::AstNode* n) {
    if(!n) { return false; }
    return ((u16)n.h.flags & (u16)ast::AstFlags::Parenthesized) != 0;
}

export fn symbol::Symbol* sym(module::Module* m, u8[] s) {
    return interner::intern(m.interner, s);
}

// LITERAL / LEAF ASSERTS (return bool) ///////////////////////////////////////
export fn bool expect_intlit(ast::AstNode* n, u64 value, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return false; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::IntLit, msg)) { return false; }
    ast::IntLitNode* il = (ast::IntLitNode*)n;
    return testing::expect_eq(il.value, value, msg);
}

export fn bool expect_floatlit(ast::AstNode* n, f64 value, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return false; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::FloatLit, msg)) { return false; }
    ast::FloatLitNode* fl = (ast::FloatLitNode*)n;
    return testing::expect_eq(fl.value, value, msg);
}

export fn bool expect_charlit(ast::AstNode* n, u8 value, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return false; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::CharLit, msg)) { return false; }
    ast::CharLitNode* cl = (ast::CharLitNode*)n;
    return testing::expect_eq((u32)cl.value, (u32)value, msg);
}

export fn bool expect_strlit(ast::AstNode* n, u32 off, u32 len, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return false; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::StringLit, msg)) { return false; }
    ast::StringLitNode* sl = (ast::StringLitNode*)n;
    if(!testing::expect_eq(sl.pool_off, off, msg)) { return false; }
    return testing::expect_eq(sl.pool_len, len, msg);
}

export fn bool expect_boollit(ast::AstNode* n, bool value, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return false; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::BoolLit, msg)) { return false; }
    ast::BoolLitNode* bl = (ast::BoolLitNode*)n;
    return testing::expect_eq(bl.value, value, msg);
}

export fn bool expect_nulllit(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return false; }
    return testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::NullLit, msg);
}

export fn bool expect_undeflit(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return false; }
    return testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::UndefinedLit, msg);
}

export fn bool expect_ident(ast::AstNode* n, symbol::Symbol* name, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return false; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::Ident, msg)) { return false; }
    ast::IdentNode* id = (ast::IdentNode*)n;
    return testing::expect_eq((void*)id.name, (void*)name, msg);
}

export fn bool expect_nsacc(ast::AstNode* n, symbol::Symbol* ns, symbol::Symbol* name, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return false; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::NamespaceAccess, msg)) { return false; }
    ast::NamespaceAccessNode* na = (ast::NamespaceAccessNode*)n;
    if(!testing::expect_eq((void*)na.namespace, (void*)ns, msg)) { return false; }
    return testing::expect_eq((void*)na.name, (void*)name, msg);
}

export fn bool expect_error_node(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return false; }
    return testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::ERROR, msg);
}

// COMPOSITE EXPRESSION ASSERTS (return typed pointer) ////////////////////////
export fn ast::BinaryOpNode* expect_binop(ast::AstNode* n, token::TokenKind op, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::BinaryOp, msg)) { return null; }
    ast::BinaryOpNode* b = (ast::BinaryOpNode*)n;
    if(!testing::expect_eq((u16)b.op, (u16)op, msg)) { return null; }
    return b;
}

export fn ast::UnaryOpNode* expect_unop(ast::AstNode* n, token::TokenKind op, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::UnaryOp, msg)) { return null; }
    ast::UnaryOpNode* u = (ast::UnaryOpNode*)n;
    if(!testing::expect_eq((u16)u.op, (u16)op, msg)) { return null; }
    return u;
}

export fn ast::CallNode* expect_call(ast::AstNode* n, u64 n_args, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::Call, msg)) { return null; }
    ast::CallNode* c = (ast::CallNode*)n;
    if(!testing::expect_eq(c.args.len, n_args, msg)) { return null; }
    return c;
}

export fn ast::MemberAccessNode* expect_member(ast::AstNode* n, symbol::Symbol* field, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::MemberAccess, msg)) { return null; }
    ast::MemberAccessNode* ma = (ast::MemberAccessNode*)n;
    if(!testing::expect_eq((void*)ma.field, (void*)field, msg)) { return null; }
    return ma;
}

export fn ast::ArrayIndexNode* expect_index(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::ArrayIndex, msg)) { return null; }
    return (ast::ArrayIndexNode*)n;
}

export fn ast::SliceRangeNode* expect_slice_range(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::SliceRange, msg)) { return null; }
    return (ast::SliceRangeNode*)n;
}

export fn ast::CastNode* expect_cast(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::Cast, msg)) { return null; }
    return (ast::CastNode*)n;
}

export fn ast::StructLitNode* expect_struct_lit(ast::AstNode* n, u64 n_inits, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::StructLit, msg)) { return null; }
    ast::StructLitNode* sl = (ast::StructLitNode*)n;
    if(!testing::expect_eq(sl.inits.len, n_inits, msg)) { return null; }
    return sl;
}

export fn ast::ArrayLitNode* expect_array_lit(ast::AstNode* n, u64 n_elems, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::ArrayLit, msg)) { return null; }
    ast::ArrayLitNode* al = (ast::ArrayLitNode*)n;
    if(!testing::expect_eq(al.elems.len, n_elems, msg)) { return null; }
    return al;
}

// FieldInitializer is a value, not an AstNode, so we take its address.
export fn bool expect_field_init(ast::FieldInitializer* fi, symbol::Symbol* name, u8[] msg) {
    if(!testing::expect_not_null((void*)fi, msg)) { return false; }
    if(name) {
        return testing::expect_eq((void*)fi.name, (void*)name, msg);
    }
    return testing::expect_null((void*)fi.name, msg);
}

// TYPE ASSERTS ///////////////////////////////////////////////////////////////
export fn bool expect_ty_prim(ast::AstNode* n, token::TokenKind k, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return false; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::PrimitiveType, msg)) { return false; }
    ast::TypePrimitiveNode* p = (ast::TypePrimitiveNode*)n;
    return testing::expect_eq((u16)p.kind, (u16)k, msg);
}

export fn ast::TypePointerNode* expect_ty_ptr(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::PointerType, msg)) { return null; }
    return (ast::TypePointerNode*)n;
}

export fn ast::TypeArrayNode* expect_ty_array(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::ArrayType, msg)) { return null; }
    return (ast::TypeArrayNode*)n;
}

export fn ast::TypeSliceNode* expect_ty_slice(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::SliceType, msg)) { return null; }
    return (ast::TypeSliceNode*)n;
}

export fn bool expect_ty_named(ast::AstNode* n, symbol::Symbol* ns, symbol::Symbol* name, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return false; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::NamedType, msg)) { return false; }
    ast::TypeNamedNode* tn = (ast::TypeNamedNode*)n;
    if(!testing::expect_eq((void*)tn.namespace, (void*)ns, msg)) { return false; }
    return testing::expect_eq((void*)tn.name, (void*)name, msg);
}

export fn ast::TypeFnPtrNode* expect_ty_fnptr(ast::AstNode* n, u64 n_params, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::FnPtrType, msg)) { return null; }
    ast::TypeFnPtrNode* fp = (ast::TypeFnPtrNode*)n;
    if(!testing::expect_eq(fp.param_types.len, n_params, msg)) { return null; }
    return fp;
}

// DECL ASSERTS ///////////////////////////////////////////////////////////////
export fn ast::VarDeclNode* expect_var(ast::AstNode* n, symbol::Symbol* name, bool is_const, bool is_exported, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::VarDecl, msg)) { return null; }
    ast::VarDeclNode* v = (ast::VarDeclNode*)n;
    if(name) {
        if(!testing::expect_eq((void*)v.name, (void*)name, msg)) { return null; }
    }
    if(!testing::expect_eq(v.is_const, is_const, msg)) { return null; }
    if(!testing::expect_eq(v.is_exported, is_exported, msg)) { return null; }
    return v;
}

// DIAG ASSERTS ///////////////////////////////////////////////////////////////
fn bool bytes_contain(u8[] haystack, u8[] needle) {
    if(needle.len == 0) { return true; }
    if(haystack.len < needle.len) { return false; }
    u64 limit = haystack.len - needle.len + 1;
    for(u64 i = 0; i < limit; i += 1) {
        bool match = true;
        for(u64 j = 0; j < needle.len; j += 1) {
            if(haystack.ptr[i + j] != needle.ptr[j]) { match = false; }
        }
        if(match) { return true; }
    }
    return false;
}

export fn bool expect_diag_substr(module::Module* m, u8[] needle, u8[] msg) {
    for(u64 i = 0; i < m.diag.entries.len; i += 1) {
        if(bytes_contain(m.diag.entries.ptr[i].msg, needle)) { return true; }
    }
    return testing::expect_true(false, msg);
}

export fn bool expect_diag_at(module::Module* m, u32 pos, u8[] needle, u8[] msg) {
    for(u64 i = 0; i < m.diag.entries.len; i += 1) {
        if(m.diag.entries.ptr[i].src_pos == pos && bytes_contain(m.diag.entries.ptr[i].msg, needle)) { return true; }
    }
    return testing::expect_true(false, msg);
}

export fn ast::WhileNode* expect_while(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::WhileStmt, msg)) { return null; }
    return (ast::WhileNode*)n;
}

export fn ast::IfNode* expect_if(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::IfStmt, msg)) { return null; }
    return (ast::IfNode*)n;
}

export fn ast::ForNode* expect_for(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::ForStmt, msg)) { return null; }
    return (ast::ForNode*)n;
}

export fn ast::CompInsertNode* expect_compinsert(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::CompinsertStmt, msg)) { return null; }
    return (ast::CompInsertNode*)n;
}

export fn ast::CompRunNode* expect_comprun(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::ComprunStmt, msg)) { return null; }
    return (ast::CompRunNode*)n;
}

export fn ast::CompErrorNode* expect_comperror(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::ComperrorStmt, msg)) { return null; }
    return (ast::CompErrorNode*)n;
}

export fn ast::CompWarningNode* expect_compwarning(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::CompwarningStmt, msg)) { return null; }
    return (ast::CompWarningNode*)n;
}

export fn ast::DeferNode* expect_defer(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::DeferStmt, msg)) { return null; }
    return (ast::DeferNode*)n;
}

export fn ast::SwitchNode* expect_switch(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::SwitchStmt, msg)) { return null; }
    return (ast::SwitchNode*)n;
}

export fn ast::BreakNode* expect_break(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::BreakStmt, msg)) { return null; }
    return (ast::BreakNode*)n;
}

export fn ast::ContinueNode* expect_continue(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::ContinueStmt, msg)) { return null; }
    return (ast::ContinueNode*)n;
}

export fn ast::AssignmentNode* expect_assign(ast::AstNode* n, token::TokenKind op, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::AssignmentStmt, msg)) { return null; }
    ast::AssignmentNode* a = (ast::AssignmentNode*)n;
    if(!testing::expect_eq((u16)a.op, (u16)op, msg)) { return null; }
    return a;
}

export fn ast::ReturnNode* expect_return(ast::AstNode* n, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::ReturnStmt, msg)) { return null; }
    return (ast::ReturnNode*)n;
}

export fn ast::BlockNode* expect_block(ast::AstNode* n, u64 n_stmts, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::BlockStmt, msg)) { return null; }
    ast::BlockNode* b = (ast::BlockNode*)n;
    if(!testing::expect_eq(b.stmts.len, n_stmts, msg)) { return null; }
    return b;
}

export fn ast::FnDeclNode* expect_fn_decl(ast::AstNode* n, symbol::Symbol* name, u64 n_params, bool is_exported, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::FnDecl, msg)) { return null; }
    ast::FnDeclNode* f = (ast::FnDeclNode*)n;
    if(name) {
        if(!testing::expect_eq((void*)f.name, (void*)name, msg)) { return null; }
    }
    if(!testing::expect_eq(f.params.len, n_params, msg)) { return null; }
    if(!testing::expect_eq(f.is_exported, is_exported, msg)) { return null; }
    return f;
}

export fn bool expect_param(ast::Param* prm, symbol::Symbol* name, bool is_const, bool is_comptime, u8[] msg) {
    if(!testing::expect_not_null((void*)prm, msg)) { return false; }
    if(name) {
        if(!testing::expect_eq((void*)prm.name, (void*)name, msg)) { return false; }
    }
    if(!testing::expect_eq(prm.is_const, is_const, msg)) { return false; }
    return testing::expect_eq(prm.is_comptime, is_comptime, msg);
}

export fn ast::ImportNode* expect_import(ast::AstNode* n, symbol::Symbol* mod_name, u8[] msg) {
    if(!testing::expect_not_null((void*)n, msg)) { return null; }
    if(!testing::expect_eq((u16)n.h.kind, (u16)ast::AstKind::ImportDecl, msg)) { return null; }
    ast::ImportNode* i = (ast::ImportNode*)n;
    if(mod_name) {
        if(!testing::expect_eq((void*)i.module_name, (void*)mod_name, msg)) { return null; }
    }
    return i;
}
