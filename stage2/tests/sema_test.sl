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
    module::Module* m = fresh_module(a);
    interner::Interner* it = (interner::Interner*)arena::alloc(a, sizeof(interner::Interner));
    sys::memset(it, 0, sizeof(interner::Interner));
    it.slab_arena = a;
    it.slab = {null, 0};
    it.slab_cap = 0;
    u64 bucket_count = 16;
    u64 nbytes = bucket_count * sizeof(symbol::Symbol*);
    void* raw = arena::alloc(a, nbytes);
    sys::memset(raw, 0, nbytes);
    it.buckets = {(symbol::Symbol**)raw, bucket_count};
    it.entry_count = 0;
    m.interner = it;
    return m;
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
    return interner::intern(m.interner, bytes);
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

fn types::Type* mk_struct_type(arena::Arena* a, types::TypeInterner* it, symbol::Symbol*[] names, types::Type*[] tys) {
    ast::StructDeclNode* d = fake_struct_decl_with_fields(a, names, tys);
    return types::intern_struct(it, (void*)d);
}

fn types::Type* mk_union_type(arena::Arena* a, types::TypeInterner* it, symbol::Symbol*[] names, types::Type*[] tys) {
    ast::UnionDeclNode* d = fake_union_decl_with_fields(a, names, tys);
    return types::intern_union(it, (void*)d);
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

fn types::TypeInterner* fresh_typer(arena::Arena* a) {
    types::TypeInterner* it = (types::TypeInterner*)arena::alloc(a, sizeof(types::TypeInterner));
    types::typer_init(it, a, null, 16);
    return it;
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
    m.name = interner::intern(m.interner, mod_name);
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
    u8[] q = interner::symbol_str(func.qualified_name, mm.interner);
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
    u8[] q = interner::symbol_str(v.qualified_name, mm.interner);
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
    module::Module* target = fresh_module_with_interner(a);
    target.name = interner::intern(target.interner, "io");
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
    u8[] q = interner::symbol_str(v.qualified_name, mm.interner);
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

    return testing::run();
}
