import module;
import symbol;
import arena;
import ast;
import diag;
import token;
import types;
import types_print;
import op;
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

// (module, name) key for alias / named-type cycle detection.
export struct ResolutionKey {
    module::Module*     mod;
    symbol::Symbol*     name;
}

export struct ResolutionStack {
    ResolutionKey[]     entries;
    u64                 cap;
    arena::Arena*       arena;
}

// Idempotent per Module.sema_phase bits; called by the driver per module.
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
        u8[] name_bytes = interner::symbol_str(name);
        u8[256] scratch;
        i32 written = sys::snprintf((i8*)&scratch[0], 256, "duplicate declaration of %.*s", (i32)name_bytes.len, (i8*)name_bytes.ptr);
        if(written > 0) {
            u64 message_len = (u64)written;
            if(message_len > 255) { message_len = 255; }
            u8[] message = {&scratch[0], message_len};
            diag::report(&s.m.diag, s.m.arena, src_pos, message);
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

// The interner is process-global, so import names match by Symbol* identity.
fn module::Module* find_import_module(Sema* s, symbol::Symbol* import_name) {
    if(import_name == null) { return null; }
    for(u64 import_index = 0; import_index < s.m.imports.len; import_index += 1) {
        module::Module* imported = s.m.imports[import_index];
        if(imported != null && imported.name == import_name) { return imported; }
    }
    return null;
}

fn void resolve_signatures_locked(Sema* s) {
    if((s.m.sema_phase & (u16)SemaPhase::Signatures) != 0) { return; }
    s.scope = (Scope*)s.m.global_scope;
    s.resolution_stack.arena = s.m.arena;
    if(s.m.root_node == null) {
        s.m.sema_phase |= SemaPhase::Signatures;
        return;
    }
    ast::BlockNode* global_block = (ast::BlockNode*)s.m.root_node;
    for(u64 stmt_index = 0; stmt_index < global_block.stmts.len; stmt_index += 1) {
        resolve_decl_signature(s, global_block.stmts[stmt_index]);
    }
    s.m.sema_phase |= SemaPhase::Signatures;
}

fn void resolve_decl_signature(Sema* s, ast::AstNode* decl_node) {
    switch(decl_node.h.kind) {
    case ast::AstKind::VarDecl: {
        ast::VarDeclNode* var_decl = (ast::VarDeclNode*)decl_node;
        set_decl_ty(s, var_decl.name, resolve_type(s, var_decl.type_expr));
    }
    case ast::AstKind::FnDecl: {
        resolve_fn_signature(s, (ast::FnDeclNode*)decl_node);
    }
    case ast::AstKind::StructDecl: {
        ast::StructDeclNode* struct_decl = (ast::StructDeclNode*)decl_node;
        resolve_fields(s, struct_decl.fields);
        set_decl_ty(s, struct_decl.name, types::intern_struct((void*)struct_decl));
    }
    case ast::AstKind::UnionDecl: {
        ast::UnionDeclNode* union_decl = (ast::UnionDeclNode*)decl_node;
        resolve_fields(s, union_decl.fields);
        set_decl_ty(s, union_decl.name, types::intern_union((void*)union_decl));
    }
    case ast::AstKind::EnumDecl: {
        ast::EnumDeclNode* enum_decl = (ast::EnumDeclNode*)decl_node;
        if(enum_decl.base_type != null) { resolve_type(s, enum_decl.base_type); }
        set_decl_ty(s, enum_decl.name, types::intern_enum((void*)enum_decl));
    }
    case ast::AstKind::AliasDecl: {
        ast::AliasDeclNode* alias_decl = (ast::AliasDeclNode*)decl_node;
        set_decl_ty(s, alias_decl.name, resolve_type(s, alias_decl.target));
    }
    else { }
    }
}

fn void resolve_fields(Sema* s, ast::FieldDecl[] fields) {
    for(u64 field_index = 0; field_index < fields.len; field_index += 1) {
        fields[field_index].resolved_type = (void*)resolve_type(s, fields[field_index].type_expr);
    }
}

fn void resolve_fn_signature(Sema* s, ast::FnDeclNode* fn_decl) {
    types::Type* return_type = types::prim_void();
    if(fn_decl.return_type != null) {
        types::Type* resolved_return = resolve_type(s, fn_decl.return_type);
        if(resolved_return != null) { return_type = resolved_return; }
    }
    types::Type*[] param_types = {null, 0};
    if(fn_decl.params.len > 0) {
        types::Type** param_type_mem = (types::Type**)arena::alloc(s.m.arena, fn_decl.params.len * sizeof(types::Type*));
        for(u64 param_index = 0; param_index < fn_decl.params.len; param_index += 1) {
            types::Type* param_type = resolve_type(s, fn_decl.params[param_index].type_expr);
            fn_decl.params[param_index].resolved_type = (void*)param_type;
            param_type_mem[param_index] = param_type;
        }
        param_types = {param_type_mem, fn_decl.params.len};
    }
    set_decl_ty(s, fn_decl.name, types::intern_fn_ptr(return_type, param_types, false));
}

// Look up a top-level decl by name in the module scope and record its resolved type.
fn void set_decl_ty(Sema* s, symbol::Symbol* name, types::Type* ty) {
    Decl* decl = scope_lookup_local(s.scope, name);
    if(decl != null) { decl.ty = ty; }
}

fn void check_bodies_locked(Sema* s) {
    if((s.m.sema_phase & (u16)SemaPhase::Bodies) != 0) { return; }
    s.scope = (Scope*)s.m.global_scope;
    if(s.m.root_node != null) {
        ast::BlockNode* global_block = (ast::BlockNode*)s.m.root_node;
        for(u64 i = 0; i < global_block.stmts.len; i += 1) {
            ast::AstNode* node = global_block.stmts[i];
            if(node.h.kind == ast::AstKind::FnDecl) { check_fn_body(s, (ast::FnDeclNode*)node); }
        }
    }
    s.m.sema_phase |= SemaPhase::Bodies;
}

fn void check_fn_body(Sema* s, ast::FnDeclNode* func) {
    if(func.body == null) { return; }
    Scope* fn_scope = scope_new(s.m.arena, (Scope*)s.m.global_scope, 16);
    for(u64 i = 0; i < func.params.len; i += 1) {
        Decl* param_decl = register_sym(s, fn_scope, func.params[i].name, false, (u16)DeclKind::Param, func.h.src_pos);
        if(param_decl != null) {
            param_decl.ty = (types::Type*)func.params[i].resolved_type;
            param_decl.data.param = &func.params[i];
        }
    }
    Scope* saved_scope = s.scope;
    ast::AstNode* saved_fn = s.current_fn;
    types::Type* saved_return = s.current_return;
    s.scope = fn_scope;
    s.current_fn = (ast::AstNode*)func;
    s.current_return = fn_return_type(s, func);
    stmt(s, func.body);
    s.scope = saved_scope;
    s.current_fn = saved_fn;
    s.current_return = saved_return;
}

fn types::Type* fn_return_type(Sema* s, ast::FnDeclNode* func) {
    Decl* fn_decl = scope_lookup_local((Scope*)s.m.global_scope, func.name);
    if(fn_decl != null && fn_decl.ty != null && fn_decl.ty.kind == types::TypeKind::FnPtr) {
        return fn_decl.ty.data.fn_ptr.ret;
    }
    return types::prim_void();
}


// ============================================================================
// §10 — Cross-module lazy resolution
// ============================================================================

fn void ensure_names_collected(Sema* s, module::Module* target) {
    // TODO
}

fn void ensure_signatures_resolved(Sema* s, module::Module* target) {
    // TODO
}

fn void ensure_bodies_checked(Sema* s, module::Module* target) {
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


// ============================================================================
// Name collection
// ============================================================================

fn void collect_names(Sema* s) {
    // TODO
}

// Intern the "module::name" form for the decl's qualified_name.
fn symbol::Symbol* qualify_decl_name(Sema* s, symbol::Symbol* bare_name) {
    if(bare_name == null || s.m.name == null) { return bare_name; }
    u8[] module_name_bytes = interner::symbol_str(s.m.name);
    u8[] bare_name_bytes = interner::symbol_str(bare_name);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "%.*s::%.*s", (i32)module_name_bytes.len, (i8*)module_name_bytes.ptr, (i32)bare_name_bytes.len, (i8*)bare_name_bytes.ptr);
    if(written <= 0) { return bare_name; }
    u64 qualified_len = (u64)written;
    if(qualified_len > 255) { qualified_len = 255; }
    u8[] qualified_bytes = {&scratch[0], qualified_len};
    return interner::intern(qualified_bytes);
}


// ============================================================================
// §7 — Signature resolution
// ============================================================================

fn void resolve_signatures(Sema* s) {
    // TODO
}

// Aliases are dissolved here; the returned Type* is never an alias wrapper.
export fn types::Type* resolve_type(Sema* s, ast::AstNode* texpr) {
    if(texpr == null) { return null; }
    switch(texpr.h.kind) {
    case ast::AstKind::PrimitiveType: {
        ast::TypePrimitiveNode* primitive_node = (ast::TypePrimitiveNode*)texpr;
        types::Type* resolved = types::primitive(types::get_primitive_kind_from_token(primitive_node.kind));
        texpr.h.ty = (void*)resolved;
        return resolved;
    }
    case ast::AstKind::PointerType: {
        ast::TypePointerNode* pointer_node = (ast::TypePointerNode*)texpr;
        types::Type* pointee = resolve_type(s, pointer_node.pointee);
        if(pointee == null) { return null; }
        types::Type* resolved = types::intern_pointer(pointee, pointer_node.is_const);
        texpr.h.ty = (void*)resolved;
        return resolved;
    }
    case ast::AstKind::ArrayType: {
        ast::TypeArrayNode* array_node = (ast::TypeArrayNode*)texpr;
        types::Type* element_type = resolve_type(s, array_node.element);
        if(element_type == null) { return null; }
        u64 count = eval_const_u64(s, array_node.size_expr);
        types::Type* resolved = types::intern_array(element_type, count);
        texpr.h.ty = (void*)resolved;
        return resolved;
    }
    case ast::AstKind::SliceType: {
        ast::TypeSliceNode* slice_node = (ast::TypeSliceNode*)texpr;
        types::Type* element_type = resolve_type(s, slice_node.element);
        if(element_type == null) { return null; }
        types::Type* resolved = types::intern_slice(element_type);
        texpr.h.ty = (void*)resolved;
        return resolved;
    }
    case ast::AstKind::FnPtrType: {
        ast::TypeFnPtrNode* fnptr_node = (ast::TypeFnPtrNode*)texpr;
        types::Type* return_type = resolve_type(s, fnptr_node.return_type);
        if(return_type == null) { return null; }
        types::Type*[] param_types = resolve_type_list(s, fnptr_node.param_types);
        types::Type* resolved = types::intern_fn_ptr(return_type, param_types, false);
        texpr.h.ty = (void*)resolved;
        return resolved;
    }
    case ast::AstKind::NamedType: {
        types::Type* resolved = resolve_named_type(s, (ast::TypeNamedNode*)texpr);
        texpr.h.ty = (void*)resolved;
        return resolved;
    }
    case ast::AstKind::StructType: {
        if(texpr.h.ty != null) { return (types::Type*)texpr.h.ty; }
        ast::StructDeclNode* anon_decl = synth_anon_struct_decl(s, (ast::TypeStructNode*)texpr);
        if(anon_decl == null) { return null; }
        types::Type* resolved = types::intern_struct((void*)anon_decl);
        texpr.h.ty = (void*)resolved;
        return resolved;
    }
    case ast::AstKind::UnionType: {
        if(texpr.h.ty != null) { return (types::Type*)texpr.h.ty; }
        ast::UnionDeclNode* anon_decl = synth_anon_union_decl(s, (ast::TypeUnionNode*)texpr);
        if(anon_decl == null) { return null; }
        types::Type* resolved = types::intern_union((void*)anon_decl);
        texpr.h.ty = (void*)resolved;
        return resolved;
    }
    else { return null; }
    }
    return null;
}

export fn types::Type*[] resolve_type_list(Sema* s, ast::AstNode*[] type_exprs) {
    if(type_exprs.len == 0) {
        types::Type*[] empty = {null, 0};
        return empty;
    }
    types::Type** resolved_types = (types::Type**)arena::alloc(s.m.arena, type_exprs.len * sizeof(types::Type*));
    for(u64 type_index = 0; type_index < type_exprs.len; type_index += 1) {
        resolved_types[type_index] = resolve_type(s, type_exprs[type_index]);
    }
    types::Type*[] out = {resolved_types, type_exprs.len};
    return out;
}

// Crosses a module boundary when n.namespace names an import.
fn types::Type* resolve_named_type(Sema* s, ast::TypeNamedNode* n) {
    module::Module* target = s.m;
    if(n.namespace != null) {
        Decl* namespace_decl = scope_lookup(s.scope, n.namespace);
        if(namespace_decl == null || namespace_decl.kind != (u16)DeclKind::Import || namespace_decl.data.module == null) {
            diag_unknown_type(s, n.h.src_pos, n.name);
            return null;
        }
        target = namespace_decl.data.module;
    }
    Decl* decl = scope_lookup_local((Scope*)target.global_scope, n.name);
    if(decl == null || (target != s.m && !decl.is_exported)) {
        diag_unknown_type(s, n.h.src_pos, n.name);
        return null;
    }
    return decl_to_type(s, target, decl);
}

fn ast::StructDeclNode* synth_anon_struct_decl(Sema* s, ast::TypeStructNode* n) {
    ast::StructDeclNode* decl = (ast::StructDeclNode*)arena::alloc(s.m.arena, sizeof(ast::StructDeclNode));
    sys::memset(decl, 0, sizeof(ast::StructDeclNode));
    decl.h.kind = ast::AstKind::StructDecl;
    decl.h.src_pos = n.h.src_pos;
    decl.fields = n.fields;
    resolve_fields(s, decl.fields);
    return decl;
}

fn ast::UnionDeclNode* synth_anon_union_decl(Sema* s, ast::TypeUnionNode* n) {
    ast::UnionDeclNode* decl = (ast::UnionDeclNode*)arena::alloc(s.m.arena, sizeof(ast::UnionDeclNode));
    sys::memset(decl, 0, sizeof(ast::UnionDeclNode));
    decl.h.kind = ast::AstKind::UnionDecl;
    decl.h.src_pos = n.h.src_pos;
    decl.fields = n.fields;
    resolve_fields(s, decl.fields);
    return decl;
}

// Only int literals until the comptime interpreter lands.
export fn u64 eval_const_u64(Sema* s, ast::AstNode* expr) {
    if(expr == null) { return 0; }
    if(expr.h.kind == ast::AstKind::IntLit) {
        return ((ast::IntLitNode*)expr).value;
    }
    return 0;
}

fn types::Type* decl_to_type(Sema* s, module::Module* target, Decl* d) {
    ast::AstNode* node = d.data.node;
    if(node == null) { return null; }
    // Nominal types intern by decl pointer; only aliases need the d.ty cache below.
    if(node.h.kind == ast::AstKind::StructDecl) { d.ty = types::intern_struct((void*)node); return d.ty; }
    if(node.h.kind == ast::AstKind::UnionDecl)  { d.ty = types::intern_union((void*)node);  return d.ty; }
    if(node.h.kind == ast::AstKind::EnumDecl)   { d.ty = types::intern_enum((void*)node);   return d.ty; }
    if(node.h.kind == ast::AstKind::AliasDecl) {
        if(d.ty != null) { return d.ty; }
        ResolutionKey key = {target, d.name};
        if(stack_contains(&s.resolution_stack, key)) {
            diag_resolution_cycle(s, node.h.src_pos, key);
            return null;
        }
        stack_push(&s.resolution_stack, key);
        types::Type* resolved = resolve_type(s, ((ast::AliasDeclNode*)node).target);
        stack_pop(&s.resolution_stack);
        d.ty = resolved;
        return resolved;
    }
    diag_unknown_type(s, node.h.src_pos, d.name);
    return null;
}


// ============================================================================
// §8 — Body checking: bidirectional type checking
// ============================================================================

fn void check_bodies(Sema* s) {
    // TODO
}

// StructLit / ArrayLit / UndefinedLit are not synth-able — they need check-mode.
export fn types::Type* synth(Sema* s, ast::AstNode* e) {
    if(e == null) { return null; }
    switch(e.h.kind) {
    case ast::AstKind::IntLit: {
        ast::IntLitNode* lit = (ast::IntLitNode*)e;
        types::Type* t = types::prim_i32();
        if(!types::int_lit_fits(lit.value, false, t)) { t = types::prim_i64(); }
        if(!types::int_lit_fits(lit.value, false, t)) { t = types::prim_u64(); }
        set_expr(e, t, (u16)ast::AstFlags::ConstExpr);
        return t;
    }
    case ast::AstKind::FloatLit: {
        set_expr(e, types::prim_f64(), (u16)ast::AstFlags::ConstExpr);
        return types::prim_f64();
    }
    case ast::AstKind::BoolLit: {
        set_expr(e, types::prim_bool(), (u16)ast::AstFlags::ConstExpr);
        return types::prim_bool();
    }
    case ast::AstKind::CharLit: {
        set_expr(e, types::prim_u8(), (u16)ast::AstFlags::ConstExpr);
        return types::prim_u8();
    }
    case ast::AstKind::StringLit: {
        types::Type* t = types::intern_pointer(types::prim_u8(), false);
        set_expr(e, t, (u16)ast::AstFlags::ConstExpr);
        return t;
    }
    case ast::AstKind::NullLit: {
        set_expr(e, types::prim_null_ptr(), (u16)ast::AstFlags::ConstExpr);
        return types::prim_null_ptr();
    }
    case ast::AstKind::Ident:           { return synth_ident(s, (ast::IdentNode*)e); }
    case ast::AstKind::NamespaceAccess: { return synth_ns_access(s, (ast::NamespaceAccessNode*)e); }
    case ast::AstKind::MemberAccess:    { return synth_member_access(s, (ast::MemberAccessNode*)e); }
    case ast::AstKind::ArrayIndex:      { return synth_array_index(s, (ast::ArrayIndexNode*)e); }
    case ast::AstKind::SliceRange:      { return synth_slice_range(s, (ast::SliceRangeNode*)e); }
    case ast::AstKind::Call:            { return synth_call(s, (ast::CallNode*)e); }
    case ast::AstKind::Cast:            { return synth_cast(s, (ast::CastNode*)e); }
    case ast::AstKind::UnaryOp:         { return synth_unary(s, (ast::UnaryOpNode*)e); }
    case ast::AstKind::BinaryOp:        { return synth_binary(s, (ast::BinaryOpNode*)e); }
    case ast::AstKind::Sizeof:          { return synth_sizeof(s, (ast::SizeofNode*)e); }
    case ast::AstKind::Alignof:         { return synth_alignof(s, (ast::AlignofNode*)e); }
    case ast::AstKind::Typeof:          { return synth_typeof(s, (ast::TypeofNode*)e); }
    case ast::AstKind::Type_info:       { return synth_type_info(s, (ast::TypeInfoNode*)e); }
    case ast::AstKind::Compcode:        { return synth_compcode(s, (ast::CompCodeNode*)e); }
    case ast::AstKind::StructLit:
    case ast::AstKind::ArrayLit:
    case ast::AstKind::UndefinedLit: {
        diag_needs_context(s, e);
        return null;
    }
    else { return null; }
    }
    return null;
}

fn void set_expr(ast::AstNode* e, types::Type* ty, u16 add_flags) {
    e.h.ty = (void*)ty;
    e.h.flags = (ast::AstFlags)((u16)e.h.flags | add_flags);
}

fn void mark_error(ast::AstNode* e) {
    e.h.flags = (ast::AstFlags)((u16)e.h.flags | (u16)ast::AstFlags::HadError);
}

fn bool expr_has_flag(ast::AstNode* e, ast::AstFlags f) {
    return ((u16)e.h.flags & (u16)f) != 0;
}

// Literal carve-outs, then fall back to synth + is_convertible.
export fn bool check(Sema* s, ast::AstNode* e, types::Type* expected) {
    if(e == null || expected == null) { return false; }
    if(e.h.kind == ast::AstKind::UnaryOp) {
        ast::UnaryOpNode* unary = (ast::UnaryOpNode*)e;
        if(unary.op == token::TokenKind::Minus && unary.operand != null && unary.operand.h.kind == ast::AstKind::IntLit) {
            if(!check_int_lit_signed(s, (ast::IntLitNode*)unary.operand, expected, true)) {
                mark_error(e);
                return false;
            }
            set_expr(e, expected, (u16)ast::AstFlags::ConstExpr);
            return true;
        }
    }
    switch(e.h.kind) {
    case ast::AstKind::IntLit: {
        return check_int_lit(s, (ast::IntLitNode*)e, expected);
    }
    case ast::AstKind::NullLit: {
        if(types::is_ptr(expected) || types::is_slice(expected)) {
            set_expr(e, expected, (u16)ast::AstFlags::ConstExpr);
            return true;
        }
        diag_type_mismatch(s, e.h.src_pos, types::prim_null_ptr(), expected);
        mark_error(e);
        return false;
    }
    case ast::AstKind::StringLit: {
        return check_string_lit(s, (ast::StringLitNode*)e, expected);
    }
    case ast::AstKind::UndefinedLit: {
        set_expr(e, expected, 0);
        return true;
    }
    case ast::AstKind::StructLit: {
        return check_struct_lit(s, (ast::StructLitNode*)e, expected);
    }
    case ast::AstKind::ArrayLit: {
        return check_array_lit(s, (ast::ArrayLitNode*)e, expected);
    }
    else {
        types::Type* got = synth(s, e);
        if(got == null) { return false; }
        if(types::is_convertible(got, expected)) { return true; }
        diag_type_mismatch(s, e.h.src_pos, got, expected);
        mark_error(e);
        return false;
    }
    }
    return false;
}


// ----------------------------------------------------------------------------
// Per-AstKind synth helpers
// ----------------------------------------------------------------------------

export fn types::Type* synth_ident(Sema* s, ast::IdentNode* n) {
    Decl* d = scope_lookup(s.scope, n.name);
    if(d == null) {
        diag_undefined_ident(s, n.h.src_pos, n.name);
        mark_error((ast::AstNode*)n);
        return null;
    }
    n.resolved = (void*)d;
    u16 flags = 0;
    if(decl_is_lvalue(d)) { flags = flags | (u16)ast::AstFlags::LValue; }
    if(decl_is_const_expr(d)) { flags = flags | (u16)ast::AstFlags::ConstExpr; }
    set_expr((ast::AstNode*)n, d.ty, flags);
    return d.ty;
}

// Recurses when the base is itself a namespace access (`mod::Enum::Member`).
fn Decl* resolve_namespace_decl(Sema* s, ast::AstNode* base) {
    if(base == null) { return null; }
    if(base.h.kind == ast::AstKind::Ident) {
        return scope_lookup(s.scope, ((ast::IdentNode*)base).name);
    }
    if(base.h.kind == ast::AstKind::NamespaceAccess) {
        ast::NamespaceAccessNode* na = (ast::NamespaceAccessNode*)base;
        Decl* outer = resolve_namespace_decl(s, na.base);
        if(outer == null || outer.kind != (u16)DeclKind::Import || outer.data.module == null) { return null; }
        return scope_lookup_local((Scope*)outer.data.module.global_scope, na.name);
    }
    return null;
}

fn types::Type* synth_ns_access(Sema* s, ast::NamespaceAccessNode* n) {
    Decl* ns = resolve_namespace_decl(s, n.base);
    if(ns == null) {
        diag_not_namespace(s, n.h.src_pos);
        mark_error((ast::AstNode*)n);
        return null;
    }
    if(ns.kind == (u16)DeclKind::Import) {
        module::Module* target = ns.data.module;
        Decl* found = scope_lookup_local((Scope*)target.global_scope, n.name);
        if(found == null || !found.is_exported) {
            diag_unknown_member(s, n.h.src_pos, n.name);
            mark_error((ast::AstNode*)n);
            return null;
        }
        n.resolved = (void*)found;
        u16 flags = 0;
        if(decl_is_lvalue(found)) { flags = flags | (u16)ast::AstFlags::LValue; }
        if(decl_is_const_expr(found)) { flags = flags | (u16)ast::AstFlags::ConstExpr; }
        set_expr((ast::AstNode*)n, found.ty, flags);
        return found.ty;
    }
    if(ns.kind == (u16)DeclKind::Node && ns.data.node != null && ns.data.node.h.kind == ast::AstKind::EnumDecl) {
        ast::EnumDeclNode* edecl = (ast::EnumDeclNode*)ns.data.node;
        ast::EnumMember* mem = find_enum_member(edecl, n.name);
        if(mem == null) {
            diag_unknown_member(s, n.h.src_pos, n.name);
            mark_error((ast::AstNode*)n);
            return null;
        }
        n.resolved = (void*)make_enum_member_decl(s, mem, ns.ty);
        set_expr((ast::AstNode*)n, ns.ty, (u16)ast::AstFlags::ConstExpr);
        return ns.ty;
    }
    diag_not_namespace(s, n.h.src_pos);
    mark_error((ast::AstNode*)n);
    return null;
}

// Auto-derefs one pointer level; slices expose the magic .ptr / .len fields.
fn types::Type* synth_member_access(Sema* s, ast::MemberAccessNode* n) {
    types::Type* base = synth(s, n.base);
    if(base == null) { return null; }
    types::Type* container = base;
    if(container.kind == types::TypeKind::Pointer) { container = container.data.pointee; }
    u16 field_flags = 0;
    if(expr_has_flag(n.base, ast::AstFlags::LValue) || base.kind == types::TypeKind::Pointer) {
        field_flags = (u16)ast::AstFlags::LValue;
    }
    // A field of a const value is read-only; through a pointer it is separate storage.
    if(base.kind != types::TypeKind::Pointer && expr_has_flag(n.base, ast::AstFlags::ConstExpr)) {
        field_flags = field_flags | (u16)ast::AstFlags::ConstExpr;
    }
    if(container.kind == types::TypeKind::Slice) {
        if(n.field == interner::intern("ptr")) {
            types::Type* elem_ptr = types::intern_pointer(container.data.slice_elem, false);
            set_expr((ast::AstNode*)n, elem_ptr, field_flags);
            return elem_ptr;
        }
        if(n.field == interner::intern("len")) {
            set_expr((ast::AstNode*)n, types::prim_u64(), field_flags);
            return types::prim_u64();
        }
        diag_unknown_field(s, n.h.src_pos, n.field, container);
        mark_error((ast::AstNode*)n);
        return null;
    }
    if(container.kind != types::TypeKind::Struct && container.kind != types::TypeKind::Union) {
        diag_not_aggregate(s, n.h.src_pos, base);
        mark_error((ast::AstNode*)n);
        return null;
    }
    ast::FieldDecl* field = find_field(container_decl(container), n.field);
    if(field == null) {
        diag_unknown_field(s, n.h.src_pos, n.field, container);
        mark_error((ast::AstNode*)n);
        return null;
    }
    types::Type* field_ty = (types::Type*)field.resolved_type;
    n.resolved = (void*)make_field_decl(s, field, field_ty);
    set_expr((ast::AstNode*)n, field_ty, field_flags);
    return field_ty;
}

fn types::Type* synth_array_index(Sema* s, ast::ArrayIndexNode* n) {
    types::Type* base = synth(s, n.base);
    if(base == null) { return null; }
    types::Type* elem = null;
    bool base_is_array = false;
    if(base.kind == types::TypeKind::Array)   { elem = base.data.array.elem; base_is_array = true; }
    else if(base.kind == types::TypeKind::Slice)   { elem = base.data.slice_elem; }
    else if(base.kind == types::TypeKind::Pointer) { elem = base.data.pointee; }
    else {
        diag_not_indexable(s, n.h.src_pos, base);
        mark_error((ast::AstNode*)n);
        return null;
    }
    if(!check(s, n.index, types::prim_u64())) {
        mark_error((ast::AstNode*)n);
        return null;
    }
    u16 flags = (u16)ast::AstFlags::LValue;
    if(base_is_array && !expr_has_flag(n.base, ast::AstFlags::LValue)) { flags = 0; }
    // An element of a const value array is read-only; a slice/pointer reaches separate storage.
    if(base_is_array && expr_has_flag(n.base, ast::AstFlags::ConstExpr)) {
        flags = flags | (u16)ast::AstFlags::ConstExpr;
    }
    set_expr((ast::AstNode*)n, elem, flags);
    return elem;
}

fn types::Type* synth_slice_range(Sema* s, ast::SliceRangeNode* n) {
    types::Type* base = synth(s, n.base);
    if(base == null) { return null; }
    types::Type* elem = null;
    if(base.kind == types::TypeKind::Array)   { elem = base.data.array.elem; }
    else if(base.kind == types::TypeKind::Slice)   { elem = base.data.slice_elem; }
    else if(base.kind == types::TypeKind::Pointer) { elem = base.data.pointee; }
    else {
        diag_not_indexable(s, n.h.src_pos, base);
        mark_error((ast::AstNode*)n);
        return null;
    }
    if(n.lo != null && !check(s, n.lo, types::prim_u64())) { mark_error((ast::AstNode*)n); return null; }
    if(n.hi != null && !check(s, n.hi, types::prim_u64())) { mark_error((ast::AstNode*)n); return null; }
    types::Type* result = types::intern_slice(elem);
    set_expr((ast::AstNode*)n, result, 0);
    return result;
}

fn types::Type* synth_call(Sema* s, ast::CallNode* n) {
    types::Type* callee = synth(s, n.callee);
    if(callee == null) { return null; }
    if(callee.kind != types::TypeKind::FnPtr) {
        diag_not_callable(s, n.h.src_pos, callee);
        mark_error((ast::AstNode*)n);
        return null;
    }
    types::Type*[] params = callee.data.fn_ptr.params;
    bool variadic = callee.data.fn_ptr.is_variadic;
    bool arity_ok = n.args.len == params.len;
    if(variadic && n.args.len >= params.len) { arity_ok = true; }
    if(!arity_ok) {
        diag_arity(s, n.h.src_pos, params.len, n.args.len);
        mark_error((ast::AstNode*)n);
        return null;
    }
    bool ok = true;
    for(u64 arg_index = 0; arg_index < params.len; arg_index += 1) {
        if(!check(s, n.args[arg_index], params[arg_index])) { ok = false; }
    }
    for(u64 extra_index = params.len; extra_index < n.args.len; extra_index += 1) {
        if(synth(s, n.args[extra_index]) == null) { ok = false; }
    }
    if(!ok) {
        mark_error((ast::AstNode*)n);
        return null;
    }
    types::Type* ret = callee.data.fn_ptr.ret;
    set_expr((ast::AstNode*)n, ret, 0);
    return ret;
}

fn types::Type* synth_cast(Sema* s, ast::CastNode* n) {
    types::Type* target = resolve_type(s, n.target_type);
    types::Type* src = synth(s, n.expr);
    if(src == null || target == null) { return null; }
    if(!types::is_castable(src, target)) {
        diag_cast_invalid(s, n.h.src_pos, src, target);
        mark_error((ast::AstNode*)n);
        return null;
    }
    u16 flags = 0;
    if(expr_has_flag(n.expr, ast::AstFlags::ConstExpr)) { flags = (u16)ast::AstFlags::ConstExpr; }
    set_expr((ast::AstNode*)n, target, flags);
    return target;
}

fn types::Type* synth_unary(Sema* s, ast::UnaryOpNode* n) {
    types::Type* operand = synth(s, n.operand);
    if(operand == null) { return null; }
    if(n.op == token::TokenKind::Amp && !expr_has_flag(n.operand, ast::AstFlags::LValue)) {
        diag_not_lvalue(s, n.operand.h.src_pos);
        mark_error((ast::AstNode*)n);
        return null;
    }
    types::Type* result = op::unaryop_result_type(n.op, operand);
    if(result == null) {
        diag_unary_mismatch(s, n.h.src_pos, n.op, operand);
        mark_error((ast::AstNode*)n);
        return null;
    }
    u16 flags = 0;
    if(n.op == token::TokenKind::Star) {
        flags = (u16)ast::AstFlags::LValue;
    } else if(n.op != token::TokenKind::Amp && expr_has_flag(n.operand, ast::AstFlags::ConstExpr)) {
        flags = (u16)ast::AstFlags::ConstExpr;
    }
    set_expr((ast::AstNode*)n, result, flags);
    return result;
}

fn types::Type* synth_binary(Sema* s, ast::BinaryOpNode* n) {
    types::Type* lt = synth(s, n.lhs);
    if(lt == null) { return null; }
    types::Type* rt = synth(s, n.rhs);
    if(rt == null) { return null; }
    types::Type* result = op::binop_result_type(n.op, lt, rt);
    if(result == null) {
        diag_binop_mismatch(s, n.h.src_pos, n.op, lt, rt);
        mark_error((ast::AstNode*)n);
        return null;
    }
    u16 flags = 0;
    if(expr_has_flag(n.lhs, ast::AstFlags::ConstExpr) && expr_has_flag(n.rhs, ast::AstFlags::ConstExpr)) {
        flags = (u16)ast::AstFlags::ConstExpr;
    }
    set_expr((ast::AstNode*)n, result, flags);
    return result;
}

fn types::Type* synth_sizeof(Sema* s, ast::SizeofNode* n) {
    types::Type* target = sizeof_operand_type(s, n.arg);
    if(target == null) { return null; }
    types::size_of(&s.m.diag, target);
    set_expr((ast::AstNode*)n, types::prim_u64(), (u16)ast::AstFlags::ConstExpr);
    return types::prim_u64();
}

fn types::Type* synth_alignof(Sema* s, ast::AlignofNode* n) {
    types::Type* target = sizeof_operand_type(s, n.arg);
    if(target == null) { return null; }
    types::align_of(&s.m.diag, target);
    set_expr((ast::AstNode*)n, types::prim_u64(), (u16)ast::AstFlags::ConstExpr);
    return types::prim_u64();
}

// The argument is either a type expression or a value expression to take the type of.
fn types::Type* sizeof_operand_type(Sema* s, ast::AstNode* arg) {
    if(arg == null) { return null; }
    if(ast::is_type((u16)arg.h.kind)) { return resolve_type(s, arg); }
    return synth(s, arg);
}

fn types::Type* synth_typeof(Sema* s, ast::TypeofNode* n) {
    return null; // TODO
}

fn types::Type* synth_type_info(Sema* s, ast::TypeInfoNode* n) {
    return null; // TODO
}

fn types::Type* synth_compcode(Sema* s, ast::CompCodeNode* n) {
    return null; // TODO
}


// ----------------------------------------------------------------------------
// Per-AstKind check helpers (only kinds that need explicit context)
// ----------------------------------------------------------------------------

// An int literal fits any int type whose range holds it.
export fn bool check_int_lit(Sema* s, ast::IntLitNode* n, types::Type* expected) {
    return check_int_lit_signed(s, n, expected, false);
}

fn bool check_int_lit_signed(Sema* s, ast::IntLitNode* n, types::Type* expected, bool negative) {
    if(types::is_int(expected) && types::int_lit_fits(n.value, negative, expected)) {
        n.h.ty = (void*)expected;
        return true;
    }
    diag_lit_overflow(s, n.h.src_pos, n.value, expected);
    mark_error((ast::AstNode*)n);
    return false;
}

fn ast::FieldDecl[] decl_fields(ast::AstNode* decl) {
    ast::FieldDecl[] empty = {null, 0};
    if(decl == null) { return empty; }
    if(decl.h.kind == ast::AstKind::StructDecl) { return ((ast::StructDeclNode*)decl).fields; }
    if(decl.h.kind == ast::AstKind::UnionDecl)  { return ((ast::UnionDeclNode*)decl).fields; }
    return empty;
}

fn u64 fields_index_of(ast::FieldDecl[] fields, symbol::Symbol* name) {
    for(u64 i = 0; i < fields.len; i += 1) {
        if(fields[i].name == name) { return i; }
    }
    return 18446744073709551615;
}

fn bool check_struct_lit(Sema* s, ast::StructLitNode* n, types::Type* expected) {
    if(expected.kind == types::TypeKind::Slice) { return check_slice_lit(s, n, expected); }
    if(expected.kind != types::TypeKind::Struct && expected.kind != types::TypeKind::Union) {
        diag_lit_wrong_target(s, n.h.src_pos, "struct", expected);
        mark_error((ast::AstNode*)n);
        return false;
    }
    ast::FieldDecl[] fields = decl_fields(container_decl(expected));
    bool* seen = (bool*)arena::alloc(s.m.arena, fields.len + 1);
    sys::memset(seen, 0, fields.len + 1);
    bool ok = true;
    u64 positional = 0;
    for(u64 i = 0; i < n.inits.len; i += 1) {
        ast::FieldInitializer* fi = &n.inits[i];
        u64 field_idx = positional;
        if(fi.name == null) { positional += 1; }
        else { field_idx = fields_index_of(fields, fi.name); }
        if(field_idx >= fields.len) {
            if(fi.name == null) { diag_extra_initializer(s, fi.src_pos); }
            else { diag_unknown_field(s, fi.src_pos, fi.name, expected); }
            ok = false;
            continue;
        }
        if(seen[field_idx]) {
            diag_dup_field(s, fi.src_pos, fields[field_idx].name);
            ok = false;
            continue;
        }
        seen[field_idx] = true;
        if(!check(s, fi.value, (types::Type*)fields[field_idx].resolved_type)) { ok = false; }
    }
    set_expr((ast::AstNode*)n, expected, 0);
    if(!ok) { mark_error((ast::AstNode*)n); }
    return ok;
}

fn bool check_array_lit(Sema* s, ast::ArrayLitNode* n, types::Type* expected) {
    types::Type* elem = null;
    bool fixed = false;
    u64 want = 0;
    if(expected.kind == types::TypeKind::Array) { elem = expected.data.array.elem; want = expected.data.array.count; fixed = true; }
    else if(expected.kind == types::TypeKind::Slice) { elem = expected.data.slice_elem; }
    else {
        diag_lit_wrong_target(s, n.h.src_pos, "array", expected);
        mark_error((ast::AstNode*)n);
        return false;
    }
    bool ok = true;
    if(fixed && n.elems.len != want) {
        diag_array_len_mismatch(s, n.h.src_pos, want, n.elems.len);
        ok = false;
    }
    for(u64 i = 0; i < n.elems.len; i += 1) {
        if(!check(s, n.elems[i], elem)) { ok = false; }
    }
    set_expr((ast::AstNode*)n, expected, 0);
    if(!ok) { mark_error((ast::AstNode*)n); }
    return ok;
}

fn bool is_byte(types::Type* t) {
    if(t == null || t.kind != types::TypeKind::Primitive) { return false; }
    return t.prim == types::PrimitiveKind::U8 || t.prim == types::PrimitiveKind::I8;
}

// A string literal targets a `u8`/`i8` pointer, slice, or array (spec §2.13).
fn bool check_string_lit(Sema* s, ast::StringLitNode* n, types::Type* expected) {
    types::Type* elem = null;
    if(expected.kind == types::TypeKind::Pointer)   { elem = expected.data.pointee; }
    else if(expected.kind == types::TypeKind::Slice) { elem = expected.data.slice_elem; }
    else if(expected.kind == types::TypeKind::Array) { elem = expected.data.array.elem; }
    if(!is_byte(elem)) {
        diag_type_mismatch(s, n.h.src_pos, types::intern_pointer(types::prim_u8(), false), expected);
        mark_error((ast::AstNode*)n);
        return false;
    }
    if(expected.kind == types::TypeKind::Array) {
        u64 lit_len = (u64)n.pool_len + 1;
        if(expected.data.array.count != lit_len) {
            diag_string_len_mismatch(s, n.h.src_pos, expected.data.array.count, lit_len);
            mark_error((ast::AstNode*)n);
            return false;
        }
    }
    set_expr((ast::AstNode*)n, expected, (u16)ast::AstFlags::ConstExpr);
    return true;
}

// `{.ptr = ..., .len = ...}` or positional `{ptr, len}` against a slice target.
fn bool check_slice_lit(Sema* s, ast::StructLitNode* n, types::Type* expected) {
    types::Type* ptr_ty = types::intern_pointer(expected.data.slice_elem, false);
    bool ok = true;
    bool seen_ptr = false;
    bool seen_len = false;
    u64 positional = 0;
    for(u64 i = 0; i < n.inits.len; i += 1) {
        ast::FieldInitializer* fi = &n.inits[i];
        bool is_ptr = true;
        if(fi.name == null) {
            if(positional == 0) { is_ptr = true; }
            else if(positional == 1) { is_ptr = false; }
            else { diag_extra_initializer(s, fi.src_pos); ok = false; positional += 1; continue; }
            positional += 1;
        }
        else if(fi.name == interner::intern("ptr")) { is_ptr = true; }
        else if(fi.name == interner::intern("len")) { is_ptr = false; }
        else { diag_unknown_field(s, fi.src_pos, fi.name, expected); ok = false; continue; }
        if(is_ptr) {
            if(seen_ptr) { diag_dup_field(s, fi.src_pos, interner::intern("ptr")); ok = false; continue; }
            seen_ptr = true;
            if(!check(s, fi.value, ptr_ty)) { ok = false; }
        } else {
            if(seen_len) { diag_dup_field(s, fi.src_pos, interner::intern("len")); ok = false; continue; }
            seen_len = true;
            if(!check(s, fi.value, types::prim_u64())) { ok = false; }
        }
    }
    set_expr((ast::AstNode*)n, expected, 0);
    if(!ok) { mark_error((ast::AstNode*)n); }
    return ok;
}


// ============================================================================
// §9 — Statement checking
// ============================================================================

fn void stmt(Sema* s, ast::AstNode* st) {
    if(st == null) { return; }
    switch(st.h.kind) {
    case ast::AstKind::BlockStmt: {
        ast::BlockNode* block = (ast::BlockNode*)st;
        Scope* block_scope = scope_new(s.m.arena, s.scope, 8);
        Scope* saved = s.scope;
        s.scope = block_scope;
        for(u64 i = 0; i < block.stmts.len; i += 1) { stmt(s, block.stmts[i]); }
        s.scope = saved;
    }
    case ast::AstKind::VarDecl: {
        stmt_var_decl(s, (ast::VarDeclNode*)st);
    }
    case ast::AstKind::IfStmt: {
        ast::IfNode* if_node = (ast::IfNode*)st;
        check_cond(s, if_node.cond);
        stmt(s, if_node.then_block);
        if(if_node.else_block != null) { stmt(s, if_node.else_block); }
    }
    case ast::AstKind::WhileStmt: {
        ast::WhileNode* while_node = (ast::WhileNode*)st;
        check_cond(s, while_node.cond);
        s.loop_depth += 1;
        stmt(s, while_node.body);
        s.loop_depth -= 1;
    }
    case ast::AstKind::ForStmt: {
        ast::ForNode* for_node = (ast::ForNode*)st;
        Scope* for_scope = scope_new(s.m.arena, s.scope, 8);
        Scope* saved = s.scope;
        s.scope = for_scope;
        stmt_or_expr(s, for_node.init);
        if(for_node.cond != null) { check_cond(s, for_node.cond); }
        stmt_or_expr(s, for_node.post);
        s.loop_depth += 1;
        stmt(s, for_node.body);
        s.loop_depth -= 1;
        s.scope = saved;
    }
    case ast::AstKind::SwitchStmt: {
        ast::SwitchNode* switch_node = (ast::SwitchNode*)st;
        types::Type* disc = synth(s, switch_node.discriminant);
        s.switch_depth += 1;
        for(u64 arm_index = 0; arm_index < switch_node.arms.len; arm_index += 1) {
            ast::SwitchArm* arm = &switch_node.arms[arm_index];
            for(u64 label_index = 0; label_index < arm.labels.len; label_index += 1) {
                if(disc != null) { check(s, arm.labels[label_index], disc); }
                else { synth(s, arm.labels[label_index]); }
            }
            if(arm.body != null) { stmt(s, arm.body); }
        }
        if(switch_node.else_block != null) { stmt(s, switch_node.else_block); }
        s.switch_depth -= 1;
    }
    case ast::AstKind::ReturnStmt: {
        stmt_return(s, (ast::ReturnNode*)st);
    }
    case ast::AstKind::BreakStmt: {
        if(s.loop_depth == 0 && s.switch_depth == 0) { diag_break_outside(s, st.h.src_pos); }
    }
    case ast::AstKind::ContinueStmt: {
        if(s.loop_depth == 0) { diag_continue_outside(s, st.h.src_pos); }
    }
    case ast::AstKind::DeferStmt: {
        stmt(s, ((ast::DeferNode*)st).body);
    }
    case ast::AstKind::AssignmentStmt: {
        stmt_assignment(s, (ast::AssignmentNode*)st);
    }
    case ast::AstKind::ExprStmt: {
        synth(s, ((ast::ExprStmtNode*)st).expr);
    }
    else { }
    }
}

fn void stmt_or_expr(Sema* s, ast::AstNode* node) {
    if(node == null) { return; }
    if(node.h.kind == ast::AstKind::VarDecl || node.h.kind == ast::AstKind::AssignmentStmt) { stmt(s, node); }
    else { synth(s, node); }
}

fn void stmt_var_decl(Sema* s, ast::VarDeclNode* var) {
    types::Type* declared = resolve_type(s, var.type_expr);
    if(var.init != null) {
        if(declared != null) { check(s, var.init, declared); }
        else { synth(s, var.init); }
    }
    Decl* decl = register_sym(s, s.scope, var.name, false, (u16)DeclKind::Node, var.h.src_pos);
    if(decl != null) {
        decl.ty = declared;
        decl.data.node = (ast::AstNode*)var;
    }
}

fn void stmt_return(Sema* s, ast::ReturnNode* ret) {
    if(ret.expr != null) {
        if(s.current_return == types::prim_void()) {
            diag_return_value_in_void(s, ret.h.src_pos);
            synth(s, ret.expr);
        } else if(s.current_return != null) {
            check(s, ret.expr, s.current_return);
        } else {
            synth(s, ret.expr);
        }
    } else if(s.current_return != null && s.current_return != types::prim_void()) {
        diag_return_missing_value(s, ret.h.src_pos, s.current_return);
    }
}

fn void stmt_assignment(Sema* s, ast::AssignmentNode* assign) {
    types::Type* lt = synth(s, assign.lhs);
    if(lt == null) { synth(s, assign.rhs); return; }
    if(!expr_has_flag(assign.lhs, ast::AstFlags::LValue)) {
        diag_not_assignable(s, assign.lhs.h.src_pos);
        synth(s, assign.rhs);
        return;
    }
    if(expr_has_flag(assign.lhs, ast::AstFlags::ConstExpr)) {
        diag_assign_to_const(s, assign.lhs.h.src_pos);
        synth(s, assign.rhs);
        return;
    }
    if(assign.op == token::TokenKind::Eq) {
        check(s, assign.rhs, lt);
        return;
    }
    types::Type* rt = synth(s, assign.rhs);
    if(rt == null) { return; }
    if(op::binop_result_type(compound_binop(assign.op), lt, rt) == null) {
        diag_binop_mismatch(s, assign.h.src_pos, assign.op, lt, rt);
    }
}

fn token::TokenKind compound_binop(token::TokenKind op) {
    switch(op) {
    case token::TokenKind::PlusEq:    { return token::TokenKind::Plus; }
    case token::TokenKind::MinusEq:   { return token::TokenKind::Minus; }
    case token::TokenKind::StarEq:    { return token::TokenKind::Star; }
    case token::TokenKind::SlashEq:   { return token::TokenKind::Slash; }
    case token::TokenKind::PercentEq: { return token::TokenKind::Percent; }
    case token::TokenKind::AmpEq:     { return token::TokenKind::Amp; }
    case token::TokenKind::PipeEq:    { return token::TokenKind::Pipe; }
    case token::TokenKind::CaretEq:   { return token::TokenKind::Caret; }
    else { return token::TokenKind::Plus; }
    }
    return token::TokenKind::Plus;
}

fn bool check_cond(Sema* s, ast::AstNode* e) {
    types::Type* t = synth(s, e);
    if(t == null) { return false; }
    if(types::is_convertible_in_cond(t)) { return true; }
    diag_not_bool_convertible(s, e.h.src_pos, t);
    mark_error(e);
    return false;
}


// ============================================================================
// §13 — Diagnostic helpers
// ============================================================================

// Report a snprintf result (a stack buffer + its return code) as an error.
fn void emit_diag(Sema* s, u32 src_pos, u8* buf, i32 written) {
    if(written <= 0) { return; }
    u64 len = (u64)written;
    if(len > 255) { len = 255; }
    u8[] msg = {buf, len};
    diag::report(&s.m.diag, s.m.arena, src_pos, msg);
}

// "expected `<expected>`, found `<got>`" — the canonical conversion-failure diagnostic.
export fn void diag_type_mismatch(Sema* s, u32 src_pos, types::Type* got, types::Type* expected) {
    u8[] expected_str = types_print::print_to_arena(expected, s.m.arena);
    u8[] got_str = types_print::print_to_arena(got, s.m.arena);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "expected %.*s, found %.*s", (i32)expected_str.len, (i8*)expected_str.ptr, (i32)got_str.len, (i8*)got_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "literal `<value>` does not fit in `<expected>`". Used by check_int_lit.
export fn void diag_lit_overflow(Sema* s, u32 src_pos, u64 value, types::Type* expected) {
    u8[] expected_str = types_print::print_to_arena(expected, s.m.arena);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "literal %lu does not fit in %.*s", value, (i32)expected_str.len, (i8*)expected_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// Emitted when synth is called on a StructLit or ArrayLit with no expected type.
export fn void diag_needs_context(Sema* s, ast::AstNode* e) {
    u8[] msg = "literal requires an expected type";
    diag::report(&s.m.diag, s.m.arena, e.h.src_pos, msg);
}

// "cannot use `<type>` in condition; expected bool, integer, pointer, or slice".
export fn void diag_not_bool_convertible(Sema* s, u32 src_pos, types::Type* got) {
    u8[] got_str = types_print::print_to_arena(got, s.m.arena);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "cannot use %.*s in condition; expected bool, integer, pointer, or slice", (i32)got_str.len, (i8*)got_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "operator is not defined for `<lhs>` and `<rhs>`".
export fn void diag_binop_mismatch(Sema* s, u32 src_pos, token::TokenKind op, types::Type* lt, types::Type* rt) {
    u8[] lt_str = types_print::print_to_arena(lt, s.m.arena);
    u8[] rt_str = types_print::print_to_arena(rt, s.m.arena);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "operator is not defined for %.*s and %.*s", (i32)lt_str.len, (i8*)lt_str.ptr, (i32)rt_str.len, (i8*)rt_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "operator `<op>` is not defined for `<type>`". Used by synth_unary.
export fn void diag_unary_mismatch(Sema* s, u32 src_pos, token::TokenKind op, types::Type* operand) {
    u8[] op_str = token::kind_name(op);
    u8[] operand_str = types_print::print_to_arena(operand, s.m.arena);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "operator %.*s is not defined for %.*s", (i32)op_str.len, (i8*)op_str.ptr, (i32)operand_str.len, (i8*)operand_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "cannot take the address of a non-lvalue". Used by synth_unary for `&x`.
export fn void diag_not_lvalue(Sema* s, u32 src_pos) {
    u8[] msg = "cannot take the address of a non-lvalue";
    diag::report(&s.m.diag, s.m.arena, src_pos, msg);
}

// "type `<T>` has no field `<name>`". Used by synth_member_access.
export fn void diag_unknown_field(Sema* s, u32 src_pos, symbol::Symbol* field, types::Type* container) {
    u8[] container_str = types_print::print_to_arena(container, s.m.arena);
    u8[] field_str = interner::symbol_str(field);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "type %.*s has no field %.*s", (i32)container_str.len, (i8*)container_str.ptr, (i32)field_str.len, (i8*)field_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "cannot access field of %T". Used by synth_member_access on a non-aggregate.
export fn void diag_not_aggregate(Sema* s, u32 src_pos, types::Type* got) {
    u8[] got_str = types_print::print_to_arena(got, s.m.arena);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "cannot access field of %.*s", (i32)got_str.len, (i8*)got_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "cannot index %T". Used by synth_array_index / synth_slice_range.
export fn void diag_not_indexable(Sema* s, u32 src_pos, types::Type* got) {
    u8[] got_str = types_print::print_to_arena(got, s.m.arena);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "cannot index %.*s", (i32)got_str.len, (i8*)got_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "cannot call value of type %T". Used by synth_call on a non-function callee.
export fn void diag_not_callable(Sema* s, u32 src_pos, types::Type* got) {
    u8[] got_str = types_print::print_to_arena(got, s.m.arena);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "cannot call value of type %.*s", (i32)got_str.len, (i8*)got_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "call expects N arguments but got M". Used by synth_call on arity mismatch.
export fn void diag_arity(Sema* s, u32 src_pos, u64 expected, u64 got) {
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "call expects %lu arguments but got %lu", expected, got);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "left of '::' is not a module or enum". Used by synth_ns_access.
export fn void diag_not_namespace(Sema* s, u32 src_pos) {
    u8[] msg = "left of '::' is not a module or enum";
    diag::report(&s.m.diag, s.m.arena, src_pos, msg);
}

// "no member named `<name>`". Used by synth_ns_access.
export fn void diag_unknown_member(Sema* s, u32 src_pos, symbol::Symbol* name) {
    u8[] name_str = interner::symbol_str(name);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "no member named %.*s", (i32)name_str.len, (i8*)name_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "cannot use `<kind>` literal as `<T>`". Used by the literal-check helpers.
export fn void diag_lit_wrong_target(Sema* s, u32 src_pos, u8[] kind, types::Type* expected) {
    u8[] expected_str = types_print::print_to_arena(expected, s.m.arena);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "cannot use %.*s literal as %.*s", (i32)kind.len, (i8*)kind.ptr, (i32)expected_str.len, (i8*)expected_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "duplicate field `<name>` in literal". Used by check_struct_lit / check_slice_lit.
export fn void diag_dup_field(Sema* s, u32 src_pos, symbol::Symbol* name) {
    u8[] name_str = interner::symbol_str(name);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "duplicate field %.*s in literal", (i32)name_str.len, (i8*)name_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "too many initializers". Used by check_struct_lit / check_slice_lit.
export fn void diag_extra_initializer(Sema* s, u32 src_pos) {
    u8[] msg = "too many initializers";
    diag::report(&s.m.diag, s.m.arena, src_pos, msg);
}

// "array literal has M elements but N expected". Used by check_array_lit.
export fn void diag_array_len_mismatch(Sema* s, u32 src_pos, u64 expected, u64 got) {
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "array literal has %lu elements but %lu expected", got, expected);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "cannot assign to a non-lvalue". Used by stmt_assignment.
export fn void diag_not_assignable(Sema* s, u32 src_pos) {
    u8[] msg = "cannot assign to a non-lvalue";
    diag::report(&s.m.diag, s.m.arena, src_pos, msg);
}

// "cannot assign to a constant". Used by stmt_assignment.
export fn void diag_assign_to_const(Sema* s, u32 src_pos) {
    u8[] msg = "cannot assign to a constant";
    diag::report(&s.m.diag, s.m.arena, src_pos, msg);
}

// "string literal has M bytes (incl. NUL) but N expected". Used by check_string_lit.
export fn void diag_string_len_mismatch(Sema* s, u32 src_pos, u64 expected, u64 got) {
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "string literal has %lu bytes (incl. NUL) but %lu expected", got, expected);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "break outside loop or switch". Used by stmt.
export fn void diag_break_outside(Sema* s, u32 src_pos) {
    u8[] msg = "break outside loop or switch";
    diag::report(&s.m.diag, s.m.arena, src_pos, msg);
}

// "continue outside loop". Used by stmt.
export fn void diag_continue_outside(Sema* s, u32 src_pos) {
    u8[] msg = "continue outside loop";
    diag::report(&s.m.diag, s.m.arena, src_pos, msg);
}

// "cannot return a value from a void function". Used by stmt_return.
export fn void diag_return_value_in_void(Sema* s, u32 src_pos) {
    u8[] msg = "cannot return a value from a void function";
    diag::report(&s.m.diag, s.m.arena, src_pos, msg);
}

// "missing return value; function returns `<T>`". Used by stmt_return.
export fn void diag_return_missing_value(Sema* s, u32 src_pos, types::Type* expected) {
    u8[] expected_str = types_print::print_to_arena(expected, s.m.arena);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "missing return value; function returns %.*s", (i32)expected_str.len, (i8*)expected_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "cannot cast `<src>` to `<target>`". Used by synth_cast on is_castable fail.
export fn void diag_cast_invalid(Sema* s, u32 src_pos, types::Type* src, types::Type* target) {
    u8[] src_str = types_print::print_to_arena(src, s.m.arena);
    u8[] target_str = types_print::print_to_arena(target, s.m.arena);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "cannot cast %.*s to %.*s", (i32)src_str.len, (i8*)src_str.ptr, (i32)target_str.len, (i8*)target_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "circular type resolution: `<name>`". Used by resolve_named_type on a cycle.
export fn void diag_resolution_cycle(Sema* s, u32 src_pos, ResolutionKey key) {
    u8[] name_str = interner::symbol_str(key.name);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "circular type resolution: %.*s", (i32)name_str.len, (i8*)name_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "unknown type `<name>`". Used by resolve_named_type on a missing/non-type name.
export fn void diag_unknown_type(Sema* s, u32 src_pos, symbol::Symbol* name) {
    u8[] name_str = interner::symbol_str(name);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "unknown type %.*s", (i32)name_str.len, (i8*)name_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "undefined identifier `<name>`". Used by synth_ident on a scope miss.
export fn void diag_undefined_ident(Sema* s, u32 src_pos, symbol::Symbol* name) {
    u8[] name_str = interner::symbol_str(name);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "undefined identifier %.*s", (i32)name_str.len, (i8*)name_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}


// ============================================================================
// Resolution stack (alias / named-type cycle detection)
// ============================================================================

// Push a (module, name) key onto the stack. Grows the backing array if needed.
export fn void stack_push(ResolutionStack* st, ResolutionKey key) {
    if(st.entries.len + 1 > st.cap) {
        u64 new_cap = st.cap * 2;
        if(new_cap < 8) { new_cap = 8; }
        ResolutionKey* mem = (ResolutionKey*)arena::alloc(st.arena, new_cap * sizeof(ResolutionKey));
        if(st.entries.len > 0) { sys::memcpy(mem, st.entries.ptr, st.entries.len * sizeof(ResolutionKey)); }
        st.entries.ptr = mem;
        st.cap = new_cap;
    }
    st.entries[st.entries.len] = key;
    st.entries.len += 1;
}

// Pop the top key. Caller is responsible for matching push/pop.
export fn void stack_pop(ResolutionStack* st) {
    if(st.entries.len > 0) { st.entries.len -= 1; }
}

// Linear scan; the alias-nesting depth is small in practice.
export fn bool stack_contains(ResolutionStack* st, ResolutionKey key) {
    for(u64 entry_index = 0; entry_index < st.entries.len; entry_index += 1) {
        if(st.entries[entry_index].mod == key.mod && st.entries[entry_index].name == key.name) { return true; }
    }
    return false;
}


// ============================================================================
// Decl helpers
// ============================================================================

// Vars, params, and fields are lvalues; fns, types, enum members are not.
export fn bool decl_is_lvalue(Decl* d) {
    if(d == null) { return false; }
    if(d.kind == (u16)DeclKind::Field || d.kind == (u16)DeclKind::Param) { return true; }
    return d.kind == (u16)DeclKind::Node && d.data.node != null && d.data.node.h.kind == ast::AstKind::VarDecl;
}

// const vars, enum members, and fns are compile-time-known.
export fn bool decl_is_const_expr(Decl* d) {
    if(d == null) { return false; }
    if(d.kind == (u16)DeclKind::EnumMember) { return true; }
    if(d.kind != (u16)DeclKind::Node || d.data.node == null) { return false; }
    ast::AstNode* node = d.data.node;
    if(node.h.kind == ast::AstKind::FnDecl) { return true; }
    return node.h.kind == ast::AstKind::VarDecl && ((ast::VarDeclNode*)node).is_const;
}

// Recover the decl node the typer keyed a struct/union/enum Type by.
export fn ast::AstNode* container_decl(types::Type* t) {
    if(t == null) { return null; }
    if(t.kind == types::TypeKind::Struct) { return (ast::AstNode*)t.data.struct_decl; }
    if(t.kind == types::TypeKind::Union)  { return (ast::AstNode*)t.data.union_decl; }
    if(t.kind == types::TypeKind::Enum)   { return (ast::AstNode*)t.data.enum_decl; }
    return null;
}

// Look up a field by symbol in a struct/union decl. Returns null if absent.
export fn ast::FieldDecl* find_field(ast::AstNode* decl, symbol::Symbol* name) {
    if(decl == null) { return null; }
    ast::FieldDecl[] fields = {null, 0};
    if(decl.h.kind == ast::AstKind::StructDecl) { fields = ((ast::StructDeclNode*)decl).fields; }
    else if(decl.h.kind == ast::AstKind::UnionDecl) { fields = ((ast::UnionDeclNode*)decl).fields; }
    else { return null; }
    for(u64 field_index = 0; field_index < fields.len; field_index += 1) {
        if(fields[field_index].name == name) { return &fields[field_index]; }
    }
    return null;
}

// Returns (u64)-1 on miss.
export fn u64 find_field_index(ast::StructDeclNode* decl, symbol::Symbol* name) {
    if(decl == null) { return 18446744073709551615; }
    for(u64 field_index = 0; field_index < decl.fields.len; field_index += 1) {
        if(decl.fields[field_index].name == name) { return field_index; }
    }
    return 18446744073709551615;
}

// Look up an enum member by symbol on an EnumDeclNode. Returns null on miss.
export fn ast::EnumMember* find_enum_member(ast::EnumDeclNode* decl, symbol::Symbol* name) {
    if(decl == null) { return null; }
    for(u64 member_index = 0; member_index < decl.members.len; member_index += 1) {
        if(decl.members[member_index].name == name) { return &decl.members[member_index]; }
    }
    return null;
}

export fn Decl* make_field_decl(Sema* s, ast::FieldDecl* f, types::Type* ty) {
    Decl* decl = (Decl*)arena::alloc(s.m.arena, sizeof(Decl));
    sys::memset(decl, 0, sizeof(Decl));
    decl.kind = (u16)DeclKind::Field;
    decl.name = f.name;
    decl.ty = ty;
    decl.data.field = f;
    return decl;
}

export fn Decl* make_enum_member_decl(Sema* s, ast::EnumMember* m, types::Type* enum_ty) {
    Decl* decl = (Decl*)arena::alloc(s.m.arena, sizeof(Decl));
    sys::memset(decl, 0, sizeof(Decl));
    decl.kind = (u16)DeclKind::EnumMember;
    decl.name = m.name;
    decl.ty = enum_ty;
    decl.data.member = m;
    return decl;
}
