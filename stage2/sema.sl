import module;
import symbol;
import arena;
import ast;
import diag;
import token;
import types;
import mutex;
import sys;
import interner;

export struct Sema {
    module::Module*     m;
    Scope*              scope;              // current scope; module-scope at the top, pushed/popped through blocks
    ast::AstNode*       current_fn;         // FnDeclNode being analyzed during body checking; null at module scope
    types::Type*        current_return;     // return type of current_fn; null at module scope
    i32                 loop_depth;         // for break/continue validity
    i32                 switch_depth;
    ResolutionStack     resolution_stack;   // alias / named-type cycle detection
}

export enum DeclKind : u16 {
    Node,          // top-level decl (fn, struct, union, enum, alias, var) — data.node
    Param,         // function parameter — data.param
    Field,         // struct/union field — data.field
    EnumMember,   // enum member — data.member
    Import,        // imported module — data.module
}

export enum SemaPhase : u16 {
    Names      = 1,    // 1 << 0 — name collection complete
    Signatures = 2,    // 1 << 1 — top-level signatures resolved
    Bodies     = 4,    // 1 << 2 — function bodies checked
}

export union DeclData {
    ast::AstNode*       node;
    ast::Param*         param;
    ast::FieldDecl*     field;
    ast::EnumMember*    member;
    module::Module*     module;
}

export struct Decl {
    u16                 kind;
    bool                is_exported;    // top-level decl marked `export`; used by cross-module lookup to filter
    symbol::Symbol*     name;           // mirrors the key under which the Decl is registered
    types::Type*        ty;             // resolved type; for fns the fn-pointer type; for type-decls the canonical Type*
    DeclData            data;
}

export struct SymEntry {
    symbol::Symbol*     name;       // null = empty slot; (Symbol*)1 = tombstone
    Decl*               decl;
}

export struct Scope {
    Scope*              parent;     // null = module scope
    SymEntry[]          entries;
    u64                 count;      // live entries (excludes tombstones); grow trigger
    u64                 cap;        // power of 2
    arena::Arena*       arena;      // for growth
}

// (Module*, Symbol*) pair: identifies a single named decl being resolved.
// Pushed onto Sema.resolution_stack around named-type / alias lookups so
// `alias A = B; alias B = A;` style cycles can be detected.
export struct ResolutionKey {
    module::Module*     mod;
    symbol::Symbol*     name;
}

export struct ResolutionStack {
    ResolutionKey[]     entries;
    u64                 cap;
    arena::Arena*       arena;
}

// Public entry: stack-allocates a Sema and runs the three sub-passes on `m`.
// Idempotent (guarded by Module.sema_phase bits). Called by the driver per module.
export fn void run(module::Module* m) {
    Sema s;
    sys::memset(&s, 0, sizeof(Sema));
    s.m = m;
    mutex::lock(&m.sema_mutex);
    collect_names_locked(&s);
    resolve_signatures_locked(&s);
    check_bodies_locked(&s);
    mutex::unlock(&m.sema_mutex);
}

// Registers every top-level decl in m.global_scope. Caller must hold m.sema_mutex.
fn void collect_names_locked(Sema* s) {
    if((s.m.sema_phase & (u16)SemaPhase::Names) != 0) {
        s.scope = (Scope*)s.m.global_scope;     // re-entry: reattach the existing module scope
        return;
    }
    Scope* module_scope = scope_new(s.m.arena, null, 16);
    s.m.global_scope = (void*)module_scope;
    s.scope = module_scope;
    if(s.m.root_node == null) {
        s.m.sema_phase |= SemaPhase::Names;
        return;
    }
    ast::BlockNode* global_block = (ast::BlockNode*)s.m.root_node;
    for(u64 stmt_index = 0; stmt_index < global_block.stmts.len; stmt_index += 1) {
        ast::AstNode* top_level_node = global_block.stmts[stmt_index];
        switch(top_level_node.h.kind) {
        case ast::AstKind::ImportDecl: {
            ast::ImportNode* import_node = (ast::ImportNode*)top_level_node;
            Decl* decl = register_sym(s, module_scope, import_node.module_name, import_node.is_reexport, (u16)DeclKind::Import, import_node.h.src_pos);
            if(decl != null) { decl.data.module = find_import_module(s, import_node.module_name); }
        }
        case ast::AstKind::VarDecl: {
            ast::VarDeclNode* var_decl = (ast::VarDeclNode*)top_level_node;
            var_decl.qualified_name = qualify_decl_name(s, var_decl.name);
            Decl* decl = register_sym(s, module_scope, var_decl.name, var_decl.is_exported, (u16)DeclKind::Node, var_decl.h.src_pos);
            if(decl != null) { decl.data.node = top_level_node; }
        }
        case ast::AstKind::FnDecl: {
            ast::FnDeclNode* fn_decl = (ast::FnDeclNode*)top_level_node;
            fn_decl.qualified_name = qualify_decl_name(s, fn_decl.name);
            Decl* decl = register_sym(s, module_scope, fn_decl.name, fn_decl.is_exported, (u16)DeclKind::Node, fn_decl.h.src_pos);
            if(decl != null) { decl.data.node = top_level_node; }
        }
        case ast::AstKind::StructDecl: {
            ast::StructDeclNode* struct_decl = (ast::StructDeclNode*)top_level_node;
            struct_decl.qualified_name = qualify_decl_name(s, struct_decl.name);
            Decl* decl = register_sym(s, module_scope, struct_decl.name, struct_decl.is_exported, (u16)DeclKind::Node, struct_decl.h.src_pos);
            if(decl != null) { decl.data.node = top_level_node; }
        }
        case ast::AstKind::UnionDecl: {
            ast::UnionDeclNode* union_decl = (ast::UnionDeclNode*)top_level_node;
            union_decl.qualified_name = qualify_decl_name(s, union_decl.name);
            Decl* decl = register_sym(s, module_scope, union_decl.name, union_decl.is_exported, (u16)DeclKind::Node, union_decl.h.src_pos);
            if(decl != null) { decl.data.node = top_level_node; }
        }
        case ast::AstKind::EnumDecl: {
            ast::EnumDeclNode* enum_decl = (ast::EnumDeclNode*)top_level_node;
            enum_decl.qualified_name = qualify_decl_name(s, enum_decl.name);
            Decl* decl = register_sym(s, module_scope, enum_decl.name, enum_decl.is_exported, (u16)DeclKind::Node, enum_decl.h.src_pos);
            if(decl != null) { decl.data.node = top_level_node; }
        }
        case ast::AstKind::AliasDecl: {
            ast::AliasDeclNode* alias_decl = (ast::AliasDeclNode*)top_level_node;
            alias_decl.qualified_name = qualify_decl_name(s, alias_decl.name);
            Decl* decl = register_sym(s, module_scope, alias_decl.name, alias_decl.is_exported, (u16)DeclKind::Node, alias_decl.h.src_pos);
            if(decl != null) { decl.data.node = top_level_node; }
        }
        case ast::AstKind::ExternBlock: {
            ast::ExternBlockNode* extern_block = (ast::ExternBlockNode*)top_level_node;
            for(u64 item_index = 0; item_index < extern_block.items.len; item_index += 1) {
                ast::AstNode* extern_item = extern_block.items[item_index];
                switch(extern_item.h.kind) {
                case ast::AstKind::ExternFnDecl: {
                    ast::ExternFnDeclNode* extern_fn = (ast::ExternFnDeclNode*)extern_item;
                    Decl* decl = register_sym(s, module_scope, extern_fn.name, extern_fn.is_exported, (u16)DeclKind::Node, extern_fn.h.src_pos);
                    if(decl != null) { decl.data.node = extern_item; }
                }
                case ast::AstKind::ExternStructDecl: {
                    ast::ExternStructDeclNode* extern_struct = (ast::ExternStructDeclNode*)extern_item;
                    Decl* decl = register_sym(s, module_scope, extern_struct.name, extern_struct.is_exported, (u16)DeclKind::Node, extern_struct.h.src_pos);
                    if(decl != null) { decl.data.node = extern_item; }
                }
                case ast::AstKind::ExternUnionDecl: {
                    ast::ExternUnionDeclNode* extern_union = (ast::ExternUnionDeclNode*)extern_item;
                    Decl* decl = register_sym(s, module_scope, extern_union.name, extern_union.is_exported, (u16)DeclKind::Node, extern_union.h.src_pos);
                    if(decl != null) { decl.data.node = extern_item; }
                }
                case ast::AstKind::VarDecl: {
                    ast::VarDeclNode* extern_var = (ast::VarDeclNode*)extern_item;
                    extern_var.qualified_name = qualify_decl_name(s, extern_var.name);
                    Decl* decl = register_sym(s, module_scope, extern_var.name, extern_var.is_exported, (u16)DeclKind::Node, extern_var.h.src_pos);
                    if(decl != null) { decl.data.node = extern_item; }
                }
                else { }
                }
            }
        }
        else { }
        }
    }
    s.m.sema_phase |= SemaPhase::Names;
}

// Register `name` in `scope`; on a duplicate, diagnose and return null. Caller fills data.*.
fn Decl* register_sym(Sema* s, Scope* scope, symbol::Symbol* name, bool is_exported, u16 decl_kind, u32 src_pos) {
    if(name == null) { return null; }
    if(scope_lookup_local(scope, name) != null) {
        if(s.m.interner != null) {
            u8[] name_bytes = interner::symbol_str(name, s.m.interner);
            u8[256] scratch;
            i32 written = sys::snprintf((i8*)&scratch[0], 256, "duplicate declaration of %.*s", (i32)name_bytes.len, (i8*)name_bytes.ptr);
            if(written > 0) {
                u64 message_len = (u64)written;
                if(message_len > 255) { message_len = 255; }
                u8[] message = {&scratch[0], message_len};
                diag::report(&s.m.diag, s.m.arena, src_pos, message);
            }
        }
        return null;
    }
    Decl* decl = arena::alloc(s.m.arena, sizeof(Decl));
    sys::memset(decl, 0, sizeof(Decl));
    decl.kind = decl_kind;
    decl.name = name;
    decl.is_exported = is_exported;
    scope_add(scope, name, decl);
    return decl;
}

// Names live in different interners, so match by bytes, not Symbol* identity.
fn module::Module* find_import_module(Sema* s, symbol::Symbol* import_name) {
    if(import_name == null || s.m.interner == null) { return null; }
    u8[] import_name_bytes = interner::symbol_str(import_name, s.m.interner);
    for(u64 import_index = 0; import_index < s.m.imports.len; import_index += 1) {
        module::Module* imported = s.m.imports[import_index];
        if(imported != null && imported.name != null && imported.interner != null) {
            u8[] candidate_bytes = interner::symbol_str(imported.name, imported.interner);
            if(import_name_bytes.len == candidate_bytes.len && sys::memcmp(import_name_bytes.ptr, candidate_bytes.ptr, import_name_bytes.len) == 0) { return imported; }
        }
    }
    return null;
}

// Signature resolution. Resolves every top-level decl's signature into canonical Type*.
// Walks param/return/field/base type expressions, fills FieldDecl.resolved_type,
// Param.resolved_type, Decl.ty. Sets Signatures on m.sema_phase.
// Triggers cross-module ensure_signatures_resolved for any imported NamedType.
fn void resolve_signatures_locked(Sema* s) {
    // TODO
}

// Body checking. Walks every function body with bidirectional check/synth.
// Sets AstHeader.ty + AstFlags on every expression node. Sets `resolved`
// on Ident / NamespaceAccess / MemberAccess. Sets Bodies on m.sema_phase.
fn void check_bodies_locked(Sema* s) {
    // TODO
}


// ============================================================================
// Scope / symbol table
// ============================================================================

// initial_cap must be a power of two.
export fn Scope* scope_new(arena::Arena* a, Scope* parent, u64 initial_cap) {
    Scope* scope = arena::alloc(a, sizeof(Scope));
    sys::memset(scope, 0, sizeof(Scope));
    scope.parent = parent;
    scope.arena = a;
    scope.cap = initial_cap;
    u64 entries_bytes = initial_cap * sizeof(SymEntry);
    SymEntry* entries = arena::alloc(a, entries_bytes);
    sys::memset(entries, 0, entries_bytes);
    scope.entries = {entries, initial_cap};
    return scope;
}

// Public insert: dedups, keeps count, and grows the table. Prefer this over _scope_insert.
export fn bool scope_add(Scope* s, symbol::Symbol* name, Decl* d) {
    if(s == null || name == null) { return false; }
    if(scope_lookup_local(s, name) != null) { return false; }
    if((s.count + 1) * 10 > s.cap * 7) { scope_grow_and_rehash(s); }
    _scope_insert(s, name, d);
    s.count += 1;
    return true;
}

export fn Decl* scope_lookup(Scope* s, symbol::Symbol* name) {
    Scope* current = s;
    while(current != null) {
        Decl* found = scope_lookup_local(current, name);
        if(found != null) { return found; }
        current = current.parent;
    }
    return null;
}

export fn Decl* scope_lookup_local(Scope* s, symbol::Symbol* name) {
    if(s == null || name == null) { return null; }
    u64 mask = s.cap - 1;
    u64 index = symbol::hash(name) & mask;
    for(u64 probe = 0; probe < s.cap; probe += 1) {
        SymEntry* entry = &s.entries[index];
        if(entry.name == null) { return null; }
        if(entry.name == name) { return entry.decl; }
        index = (index + 1) & mask;
    }
    return null;
}

fn void scope_grow_and_rehash(Scope* s) {
    SymEntry[] old_entries = s.entries;
    u64 old_cap = s.cap;
    u64 new_cap = old_cap * 2;
    if(new_cap == 0) { new_cap = 1; }
    u64 entries_bytes = new_cap * sizeof(SymEntry);
    SymEntry* new_entries = arena::alloc(s.arena, entries_bytes);
    sys::memset(new_entries, 0, entries_bytes);
    s.entries = {new_entries, new_cap};
    s.cap = new_cap;
    for(u64 i = 0; i < old_cap; i += 1) {
        SymEntry* entry = &old_entries[i];
        if(entry.name != null) { _scope_insert(s, entry.name, entry.decl); }
    }
}

// Raw open-addressed insert: no dedup, no count update. Use scope_add.
fn void _scope_insert(Scope* s, symbol::Symbol* name, Decl* d) {
    u64 mask = s.cap - 1;
    u64 index = symbol::hash(name) & mask;
    SymEntry* entry = &s.entries[index];
    while(entry.name != null) {
        index = (index + 1) & mask;
        entry = &s.entries[index];
    }
    entry.name = name;
    entry.decl = d;
}


// Intern the "module::name" form for the decl's qualified_name.
fn symbol::Symbol* qualify_decl_name(Sema* s, symbol::Symbol* bare_name) {
    if(bare_name == null || s.m.interner == null || s.m.name == null) { return bare_name; }
    u8[] module_name_bytes = interner::symbol_str(s.m.name, s.m.interner);
    u8[] bare_name_bytes = interner::symbol_str(bare_name, s.m.interner);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "%.*s::%.*s", (i32)module_name_bytes.len, (i8*)module_name_bytes.ptr, (i32)bare_name_bytes.len, (i8*)bare_name_bytes.ptr);
    if(written <= 0) { return bare_name; }
    u64 qualified_len = (u64)written;
    if(qualified_len > 255) { qualified_len = 255; }
    u8[] qualified_bytes = {&scratch[0], qualified_len};
    return interner::intern(s.m.interner, qualified_bytes);
}
