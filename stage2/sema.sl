import module;
import symbol;
import arena;
import ast;
import diag;
import token;
import types;
import types_print;
import op;
import sys;
import interner;
import value;
import mutex;
import condvar;
import threads;

export struct Sema {
    module::Module*     m;
    module::Module*     lookup_module;      // module whose scope bare named types resolve against; null = m (differs for a clone body)
    Scope*              scope;              // current scope; module-scope at the top, pushed/popped through blocks
    ast::AstNode*       current_fn;         // FnDeclNode being analyzed during body checking; null at module scope
    types::Ty*        current_return;     // return type of current_fn; null at module scope
    i32                 loop_depth;         // for break/continue validity
    i32                 switch_depth;
    ResolutionStack     resolution_stack;   // alias / named-type cycle detection
    symbol::Symbol*[]   comptime_type_names; // comptime Type params of the generic whose signature is resolving
    bool                in_comprun;         // inside a comprun_node body: compinsert there is comptime-evaluated, not stmt-spliced
    arena::Arena*       body_arena;         // where body-check allocates; a cross-module on-demand check uses the requester's, keeping each module arena single-writer
    diag::DiagBuf*      body_diag;          // where body-check diagnostics go; the requester's, so a foreign check never writes the foreign module's diag buffer
}

// Body-check allocations go here so an on-demand foreign check writes the requester's arena, not the foreign module's.
fn arena::Arena* balloc(Sema* s) {
    if(s.body_arena != null) { return s.body_arena; }
    return s.m.arena;
}

fn diag::DiagBuf* bdiag(Sema* s) {
    if(s.body_diag != null) { return s.body_diag; }
    return &s.m.diag;
}

fn void sema_report(Sema* s, u32 pos, u8[] msg) {
    diag::report(bdiag(s), balloc(s), pos, msg);
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

// Driver-installed (comptime imports sema, not vice versa): infers comptime args from runtime arg types → clone.
export fn* ast::FnDeclNode*(module::Module*, ast::FnDeclNode*, types::Ty*[]) resolve_generic_call_hook;

// Explicit form: the caller passes the comptime args as values (val_type / val_int); monomorphize on them.
export fn* ast::FnDeclNode*(module::Module*, ast::FnDeclNode*, value::Value[]) resolve_generic_explicit_hook;

// Evaluates a comprun_node block through the interpreter; side effects are diagnostics / compinsert mutations.
export fn* void(module::Module*, ast::CompRunNode*) run_comprun_hook;

// Evaluates an in-function compinsert and returns the generated statements for the block walk to splice in.
export fn* ast::AstNode*[](module::Module*, ast::CompInsertNode*) run_compinsert_stmts_hook;

// Quiet fold to i64 (no diagnostics); each caller decides what a failed fold means.
export fn* bool(module::Module*, ast::AstNode*, i64*) eval_const_i64_hook;

// Evaluates a comptime expression that must yield a Type (e.g. `pick()` / `Vec(i32)` in type position); null if it isn't a Type.
export fn* types::Ty*(module::Module*, ast::AstNode*) eval_comptime_type_hook;


export union DeclData {
    ast::AstNode*       node;
    ast::Param*         param;
    ast::FieldDecl*     field;
    ast::EnumMember*    member;
    module::Module*     module;
}

export struct Decl {
    DeclKind            kind;
    bool                is_exported;    // top-level decl marked `export`; used by cross-module lookup to filter
    symbol::Symbol*     name;           // mirrors the key under which the Decl is registered
    types::Ty*        ty;             // resolved type; for fns the fn-pointer type; for type-decls the canonical Type*
    DeclData            data;
    Decl*               next_overload;  // same-name function overloads, chained off the scope-registered head
    module::Module*     home;           // module that registered this decl; lets comptime body-check a cross-module callee
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
// Driver-scheduled sub-pass: registers every top-level decl in m.global_scope.
export fn void collect_names(module::Module* m) {
    Sema sema;
    sys::memset(&sema, 0, sizeof(Sema));
    sema.m = m;
    Sema* s = &sema;
    if((s.m.sema_phase & (u16)SemaPhase::Names) != 0) {
        s.scope = (Scope*)s.m.global_scope;     // re-entry: reattach the existing module scope
        return;
    }
    Scope* module_scope = scope_new(balloc(s), null, 16);
    s.m.global_scope = (void*)module_scope;
    s.scope = module_scope;
    if(s.m.root_node == null) {
        register_reflection_names(s, module_scope);
        s.m.sema_phase |= SemaPhase::Names;
        return;
    }
    ast::BlockNode* global_block = (ast::BlockNode*)s.m.root_node;
    for(u64 stmt_index = 0; stmt_index < global_block.stmts.len; stmt_index += 1) {
        collect_name_for_decl(s, global_block.stmts[stmt_index]);
    }
    register_reflection_names(s, module_scope);
    s.m.sema_phase |= SemaPhase::Names;
}

// Shared by the name pass and compinsert splicing.
fn void collect_name_for_decl(Sema* s, ast::AstNode* top_level_node) {
    Scope* module_scope = s.scope;
    switch(top_level_node.h.kind) {
    case ast::AstKind::ImportDecl: {
        ast::ImportNode* import_node = (ast::ImportNode*)top_level_node;
        Decl* decl = register_sym(s, module_scope, import_node.module_name, false, DeclKind::Import, import_node.h.src_pos);
        if(decl != null) { decl.data.module = find_import_module(s, import_node.module_name); }
    }
    case ast::AstKind::VarDecl: {
        ast::VarDeclNode* var_decl = (ast::VarDeclNode*)top_level_node;
        var_decl.qualified_name = qualify_decl_name(s, var_decl.name);
        Decl* decl = register_sym(s, module_scope, var_decl.name, var_decl.is_exported, DeclKind::Node, var_decl.h.src_pos);
        if(decl != null) { decl.data.node = top_level_node; var_decl.decl = (void*)decl; }
    }
    case ast::AstKind::FnDecl: {
        ast::FnDeclNode* fn_decl = (ast::FnDeclNode*)top_level_node;
        fn_decl.qualified_name = qualify_decl_name(s, fn_decl.name);
        Decl* decl = register_fn(s, module_scope, fn_decl, fn_decl.is_exported);
        if(decl != null) { decl.data.node = top_level_node; fn_decl.decl = (void*)decl; }
    }
    case ast::AstKind::StructDecl: {
        ast::StructDeclNode* struct_decl = (ast::StructDeclNode*)top_level_node;
        struct_decl.qualified_name = qualify_decl_name(s, struct_decl.name);
        Decl* decl = register_sym(s, module_scope, struct_decl.name, struct_decl.is_exported, DeclKind::Node, struct_decl.h.src_pos);
        if(decl != null) { decl.data.node = top_level_node; }
    }
    case ast::AstKind::UnionDecl: {
        ast::UnionDeclNode* union_decl = (ast::UnionDeclNode*)top_level_node;
        union_decl.qualified_name = qualify_decl_name(s, union_decl.name);
        Decl* decl = register_sym(s, module_scope, union_decl.name, union_decl.is_exported, DeclKind::Node, union_decl.h.src_pos);
        if(decl != null) { decl.data.node = top_level_node; }
    }
    case ast::AstKind::EnumDecl: {
        ast::EnumDeclNode* enum_decl = (ast::EnumDeclNode*)top_level_node;
        enum_decl.qualified_name = qualify_decl_name(s, enum_decl.name);
        Decl* decl = register_sym(s, module_scope, enum_decl.name, enum_decl.is_exported, DeclKind::Node, enum_decl.h.src_pos);
        if(decl != null) { decl.data.node = top_level_node; }
    }
    case ast::AstKind::AliasDecl: {
        ast::AliasDeclNode* alias_decl = (ast::AliasDeclNode*)top_level_node;
        alias_decl.qualified_name = qualify_decl_name(s, alias_decl.name);
        Decl* decl = register_sym(s, module_scope, alias_decl.name, alias_decl.is_exported, DeclKind::Node, alias_decl.h.src_pos);
        if(decl != null) { decl.data.node = top_level_node; }
    }
    case ast::AstKind::ExternBlock: {
        ast::ExternBlockNode* extern_block = (ast::ExternBlockNode*)top_level_node;
        for(u64 item_index = 0; item_index < extern_block.items.len; item_index += 1) {
            ast::AstNode* extern_item = extern_block.items[item_index];
            switch(extern_item.h.kind) {
            case ast::AstKind::ExternFnDecl: {
                ast::ExternFnDeclNode* extern_fn = (ast::ExternFnDeclNode*)extern_item;
                Decl* decl = register_sym(s, module_scope, extern_fn.name, extern_fn.is_exported, DeclKind::Node, extern_fn.h.src_pos);
                if(decl != null) { decl.data.node = extern_item; }
            }
            case ast::AstKind::ExternStructDecl: {
                ast::ExternStructDeclNode* extern_struct = (ast::ExternStructDeclNode*)extern_item;
                Decl* decl = register_sym(s, module_scope, extern_struct.name, extern_struct.is_exported, DeclKind::Node, extern_struct.h.src_pos);
                if(decl != null) { decl.data.node = (ast::AstNode*)materialize_extern_struct(s, extern_struct); }
            }
            case ast::AstKind::ExternUnionDecl: {
                ast::ExternUnionDeclNode* extern_union = (ast::ExternUnionDeclNode*)extern_item;
                Decl* decl = register_sym(s, module_scope, extern_union.name, extern_union.is_exported, DeclKind::Node, extern_union.h.src_pos);
                if(decl != null) { decl.data.node = (ast::AstNode*)materialize_extern_union(s, extern_union); }
            }
            case ast::AstKind::VarDecl: {
                ast::VarDeclNode* extern_var = (ast::VarDeclNode*)extern_item;
                extern_var.qualified_name = qualify_decl_name(s, extern_var.name);
                Decl* decl = register_sym(s, module_scope, extern_var.name, extern_var.is_exported, DeclKind::Node, extern_var.h.src_pos);
                if(decl != null) { decl.data.node = extern_item; extern_var.decl = (void*)decl; }
            }
            case ast::AstKind::EnumDecl: {
                ast::EnumDeclNode* extern_enum = (ast::EnumDeclNode*)extern_item;
                extern_enum.qualified_name = qualify_decl_name(s, extern_enum.name);
                Decl* decl = register_sym(s, module_scope, extern_enum.name, extern_enum.is_exported, DeclKind::Node, extern_enum.h.src_pos);
                if(decl != null) { decl.data.node = extern_item; }
            }
            else { }
            }
        }
    }
    else { }
    }
}

// Register `name` in `scope`; on a duplicate, diagnose and return null. Caller fills data.*.
fn Decl* register_sym(Sema* s, Scope* scope, symbol::Symbol* name, bool is_exported, DeclKind decl_kind, u32 src_pos) {
    if(name == null) { return null; }
    if(scope_lookup_local(scope, name) != null) {
        u8[] name_bytes = interner::symbol_str(name);
        u8[256] scratch;
        i32 written = sys::snprintf((i8*)&scratch[0], 256, "duplicate declaration of %.*s", (i32)name_bytes.len, (i8*)name_bytes.ptr);
        if(written > 0) {
            u64 message_len = (u64)written;
            if(message_len > 255) { message_len = 255; }
            u8[] message = {&scratch[0], message_len};
            sema_report(s, src_pos, message);
        }
        return null;
    }
    Decl* decl = arena::alloc(balloc(s), sizeof(Decl));
    sys::memset(decl, 0, sizeof(Decl));
    decl.kind = decl_kind;
    decl.name = name;
    decl.is_exported = is_exported;
    decl.home = s.m;
    scope_add(scope, name, decl);
    return decl;
}

fn bool decl_is_fn(Decl* d) {
    if(d.kind != DeclKind::Node || d.data.node == null) { return false; }
    return d.data.node.h.kind == ast::AstKind::FnDecl || d.data.node.h.kind == ast::AstKind::ExternFnDecl;
}

// A same-name existing function chains the new one as an overload; any other collision re-emits the duplicate error.
fn bool chain_has_generic(Decl* head) {
    Decl* d = head;
    while(d != null) {
        if(d.kind == DeclKind::Node && d.data.node != null && d.data.node.h.kind == ast::AstKind::FnDecl && is_generic_fn((ast::FnDeclNode*)d.data.node)) { return true; }
        d = d.next_overload;
    }
    return false;
}

fn bool chain_has_extern(Decl* head) {
    Decl* d = head;
    while(d != null) {
        if(d.kind == DeclKind::Node && d.data.node != null && d.data.node.h.kind == ast::AstKind::ExternFnDecl) { return true; }
        d = d.next_overload;
    }
    return false;
}

fn Decl* register_fn(Sema* s, Scope* scope, ast::FnDeclNode* fn_decl, bool is_exported) {
    symbol::Symbol* name = fn_decl.name;
    Decl* existing = scope_lookup_local(scope, name);
    if(existing == null || !decl_is_fn(existing)) {
        return register_sym(s, scope, name, is_exported, DeclKind::Node, fn_decl.h.src_pos);
    }
    if(is_generic_fn(fn_decl) || chain_has_generic(existing)) {
        u8[] msg = "generic functions cannot be overloaded";
        sema_report(s, fn_decl.h.src_pos, msg);
        return null;
    }
    if(chain_has_extern(existing)) {
        u8[] msg = "extern functions cannot be overloaded";
        sema_report(s, fn_decl.h.src_pos, msg);
        return null;
    }
    Decl* overload = new_decl(s, DeclKind::Node, name, null);
    overload.is_exported = is_exported;
    Decl* tail = existing;
    while(tail.next_overload != null) { tail = tail.next_overload; }
    tail.next_overload = overload;
    return overload;
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

// Driver-scheduled sub-pass: resolves every top-level decl's signature.
export fn void resolve_signatures(module::Module* m) {
    Sema sema;
    sys::memset(&sema, 0, sizeof(Sema));
    sema.m = m;
    Sema* s = &sema;
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

// An enum value expression may reference sibling members by name; bind those idents to their member decls so comptime folds them.
fn void resolve_enum_value_refs(ast::EnumDeclNode* ed, ast::AstNode* expr) {
    if(expr == null) { return; }
    if(expr.h.kind == ast::AstKind::Ident) {
        ast::EnumMember* mem = find_enum_member(ed, ((ast::IdentNode*)expr).name);
        if(mem != null) { ((ast::IdentNode*)expr).resolved = mem.decl; }
        return;
    }
    if(expr.h.kind == ast::AstKind::BinaryOp) {
        resolve_enum_value_refs(ed, ((ast::BinaryOpNode*)expr).lhs);
        resolve_enum_value_refs(ed, ((ast::BinaryOpNode*)expr).rhs);
        return;
    }
    if(expr.h.kind == ast::AstKind::UnaryOp) {
        resolve_enum_value_refs(ed, ((ast::UnaryOpNode*)expr).operand);
        return;
    }
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
        types::Ty* enum_ty = types::intern_enum((void*)enum_decl);
        set_decl_ty(s, enum_decl.name, enum_ty);
        for(u64 member_index = 0; member_index < enum_decl.members.len; member_index += 1) {
            Decl* member_decl = new_decl(s, DeclKind::EnumMember, enum_decl.members[member_index].name, enum_ty);
            member_decl.data.member = &enum_decl.members[member_index];
            enum_decl.members[member_index].decl = (void*)member_decl;
        }
        for(u64 member_index = 0; member_index < enum_decl.members.len; member_index += 1) {
            resolve_enum_value_refs(enum_decl, enum_decl.members[member_index].value_expr);
        }
    }
    case ast::AstKind::AliasDecl: {
        ast::AliasDeclNode* alias_decl = (ast::AliasDeclNode*)decl_node;
        set_decl_ty(s, alias_decl.name, resolve_type(s, alias_decl.target));
    }
    case ast::AstKind::ExternBlock: {
        ast::ExternBlockNode* extern_block = (ast::ExternBlockNode*)decl_node;
        for(u64 item_index = 0; item_index < extern_block.items.len; item_index += 1) {
            resolve_extern_item_signature(s, extern_block.items[item_index]);
        }
    }
    else { }
    }
}

fn void resolve_extern_item_signature(Sema* s, ast::AstNode* item) {
    switch(item.h.kind) {
    case ast::AstKind::ExternFnDecl: {
        ast::ExternFnDeclNode* extern_fn = (ast::ExternFnDeclNode*)item;
        types::Ty* return_type = types::prim_void();
        if(extern_fn.return_type != null) {
            types::Ty* resolved_return = resolve_type(s, extern_fn.return_type);
            if(resolved_return != null) { return_type = resolved_return; }
        }
        types::Ty*[] param_types = {null, 0};
        if(extern_fn.params.len > 0) {
            types::Ty** param_type_mem = (types::Ty**)arena::alloc(balloc(s), extern_fn.params.len * sizeof(types::Ty*));
            for(u64 param_index = 0; param_index < extern_fn.params.len; param_index += 1) {
                types::Ty* param_type = resolve_type(s, extern_fn.params[param_index].type_expr);
                extern_fn.params[param_index].resolved_type = (void*)param_type;
                param_type_mem[param_index] = param_type;
            }
            param_types = {param_type_mem, extern_fn.params.len};
        }
        set_decl_ty(s, extern_fn.name, types::intern_fn_ptr(return_type, param_types, extern_fn.is_variadic));
    }
    case ast::AstKind::ExternStructDecl: {
        ast::ExternStructDeclNode* extern_struct = (ast::ExternStructDeclNode*)item;
        Decl* decl = scope_lookup_local(s.scope, extern_struct.name);
        if(decl == null || decl.data.node == null) { return; }
        ast::StructDeclNode* materialized = (ast::StructDeclNode*)decl.data.node;
        resolve_fields(s, materialized.fields);
        decl.ty = types::intern_struct((void*)materialized);
    }
    case ast::AstKind::ExternUnionDecl: {
        ast::ExternUnionDeclNode* extern_union = (ast::ExternUnionDeclNode*)item;
        Decl* decl = scope_lookup_local(s.scope, extern_union.name);
        if(decl == null || decl.data.node == null) { return; }
        ast::UnionDeclNode* materialized = (ast::UnionDeclNode*)decl.data.node;
        resolve_fields(s, materialized.fields);
        decl.ty = types::intern_union((void*)materialized);
    }
    // extern var/const and enum items resolve exactly like their top-level forms.
    case ast::AstKind::VarDecl:  { resolve_decl_signature(s, item); }
    case ast::AstKind::EnumDecl: { resolve_decl_signature(s, item); }
    else { }
    }
}

fn void resolve_fields(Sema* s, ast::FieldDecl[] fields) {
    for(u64 field_index = 0; field_index < fields.len; field_index += 1) {
        types::Ty* field_ty = resolve_type(s, fields[field_index].type_expr);
        fields[field_index].resolved_type = (void*)field_ty;
        Decl* field_decl = new_decl(s, DeclKind::Field, fields[field_index].name, field_ty);
        field_decl.data.field = &fields[field_index];
        fields[field_index].decl = (void*)field_decl;
    }
}

fn bool is_type_kw(ast::AstNode* type_expr) {
    return type_expr != null && type_expr.h.kind == ast::AstKind::PrimitiveType && ((ast::TypePrimitiveNode*)type_expr).kind == token::TokenKind::TYPE;
}

fn symbol::Symbol*[] collect_comptime_type_names(Sema* s, ast::FnDeclNode* fn_decl) {
    u64 count = 0;
    for(u64 i = 0; i < fn_decl.params.len; i += 1) {
        if(fn_decl.params[i].is_comptime && is_type_kw(fn_decl.params[i].type_expr)) { count += 1; }
    }
    if(count == 0) {
        symbol::Symbol*[] empty = {null, 0};
        return empty;
    }
    symbol::Symbol** names_mem = (symbol::Symbol**)arena::alloc(balloc(s), count * sizeof(symbol::Symbol*));
    symbol::Symbol*[] names = {names_mem, 0};
    for(u64 i = 0; i < fn_decl.params.len; i += 1) {
        if(fn_decl.params[i].is_comptime && is_type_kw(fn_decl.params[i].type_expr)) {
            names[names.len] = fn_decl.params[i].name;
            names.len += 1;
        }
    }
    return names;
}

// A Type has no runtime representation; pointers stop the walk since an address is representable.
fn bool type_has_comptime_part(types::Ty* t) {
    if(t == null) { return false; }
    if(t.kind == types::TypeKind::ComptimeType) { return true; }
    if(t.kind == types::TypeKind::Array) { return type_has_comptime_part(t.data.array.elem); }
    ast::FieldDecl[] fields = {null, 0};
    if(t.kind == types::TypeKind::Struct) { fields = ((ast::StructDeclNode*)t.data.struct_decl).fields; }
    else if(t.kind == types::TypeKind::Union) { fields = ((ast::UnionDeclNode*)t.data.union_decl).fields; }
    for(u64 field_index = 0; field_index < fields.len; field_index += 1) {
        if(type_has_comptime_part((types::Ty*)fields[field_index].resolved_type)) { return true; }
    }
    return false;
}

fn void diag_comptime_only_type(Sema* s, u32 src_pos, types::Ty* t) {
    u8[] type_str = types_print::print_to_arena(t, balloc(s));
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "%.*s is comptime-only and has no runtime representation", (i32)type_str.len, (i8*)type_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

fn void resolve_fn_signature(Sema* s, ast::FnDeclNode* fn_decl) {
    symbol::Symbol*[] saved_type_names = s.comptime_type_names;
    s.comptime_type_names = collect_comptime_type_names(s, fn_decl);
    types::Ty* return_type = types::prim_void();
    if(fn_decl.return_type != null) {
        types::Ty* resolved_return = resolve_type(s, fn_decl.return_type);
        if(resolved_return != null) { return_type = resolved_return; }
    }
    types::Ty*[] param_types = {null, 0};
    if(fn_decl.params.len > 0) {
        types::Ty** param_type_mem = (types::Ty**)arena::alloc(balloc(s), fn_decl.params.len * sizeof(types::Ty*));
        for(u64 param_index = 0; param_index < fn_decl.params.len; param_index += 1) {
            types::Ty* param_type = resolve_type(s, fn_decl.params[param_index].type_expr);
            fn_decl.params[param_index].resolved_type = (void*)param_type;
            param_type_mem[param_index] = param_type;
        }
        param_types = {param_type_mem, fn_decl.params.len};
    }
    // A template's `T value` param is still the Type placeholder; only its clones are lowered.
    if(return_type.kind != types::TypeKind::ComptimeType && !is_generic_fn(fn_decl)) {
        if(type_has_comptime_part(return_type)) { diag_comptime_only_type(s, fn_decl.h.src_pos, return_type); }
        for(u64 param_index = 0; param_index < fn_decl.params.len; param_index += 1) {
            if(fn_decl.params[param_index].is_comptime) { continue; }
            types::Ty* pt = (types::Ty*)fn_decl.params[param_index].resolved_type;
            if(type_has_comptime_part(pt)) { diag_comptime_only_type(s, fn_decl.params[param_index].src_pos, pt); }
        }
    }
    Decl* own = (Decl*)fn_decl.decl;
    if(own != null) { own.ty = types::intern_fn_ptr(return_type, param_types, false); }
    Decl* head = scope_lookup_local(s.scope, fn_decl.name);
    if(head != null && own != null && head != own && head.ty != null && head.ty.kind == types::TypeKind::FnPtr) {
        if(head.ty.data.fn_ptr.ret != return_type) { diag_overload_return_mismatch(s, fn_decl.h.src_pos, fn_decl.name); }
        // Types are interned, so an identical signature is the identical Ty*; report at the later decl.
        Decl* prior = head;
        while(prior != null) {
            if(prior != own && prior.ty == own.ty) {
                diag_overload_duplicate(s, fn_decl.h.src_pos, fn_decl.name);
                break;
            }
            prior = prior.next_overload;
        }
    }
    s.comptime_type_names = saved_type_names;
}

// Look up a top-level decl by name in the module scope and record its resolved type.
fn void set_decl_ty(Sema* s, symbol::Symbol* name, types::Ty* ty) {
    Decl* decl = scope_lookup_local(s.scope, name);
    if(decl != null) { decl.ty = ty; }
}

// Driver-scheduled sub-pass: bidirectional type-checks every function body.
export fn void check_bodies(module::Module* m) {
    Sema sema;
    sys::memset(&sema, 0, sizeof(Sema));
    sema.m = m;
    Sema* s = &sema;
    if((s.m.sema_phase & (u16)SemaPhase::Bodies) != 0) { return; }
    s.scope = (Scope*)s.m.global_scope;
    if(s.m.root_node != null) {
        ast::BlockNode* global_block = (ast::BlockNode*)s.m.root_node;
        for(u64 i = 0; i < global_block.stmts.len; i += 1) {
            ast::AstNode* node = global_block.stmts[i];
            if(node.h.kind == ast::AstKind::FnDecl && !is_generic_fn((ast::FnDeclNode*)node)) {
                ensure_body_checked(s.m, (ast::FnDeclNode*)node, s.m);
            }
            else if(node.h.kind == ast::AstKind::VarDecl) {
                ensure_var_init_checked(s.m, (ast::VarDeclNode*)node);
            }
            else if(node.h.kind == ast::AstKind::ComprunStmt) {
                ast::CompRunNode* comprun_node = (ast::CompRunNode*)node;
                s.in_comprun = true;
                stmt(s, comprun_node.body);
                s.in_comprun = false;
                if(run_comprun_hook != null) { run_comprun_hook(s.m, comprun_node); }
            }
        }
    }
    s.m.sema_phase |= SemaPhase::Bodies;
}

// A generic template can't be body-checked in the abstract; only its instantiations (clones) are.
export fn bool is_generic_fn(ast::FnDeclNode* func) {
    for(u64 i = 0; i < func.params.len; i += 1) {
        if(func.params[i].is_comptime) { return true; }
    }
    return false;
}

fn bool is_spliceable_decl(ast::AstNode* node) {
    ast::AstKind kind = node.h.kind;
    return kind == ast::AstKind::FnDecl || kind == ast::AstKind::StructDecl || kind == ast::AstKind::UnionDecl || kind == ast::AstKind::EnumDecl || kind == ast::AstKind::VarDecl || kind == ast::AstKind::AliasDecl;
}

fn bool decl_is_exported(ast::AstNode* node) {
    switch(node.h.kind) {
    case ast::AstKind::FnDecl:     { return ((ast::FnDeclNode*)node).is_exported; }
    case ast::AstKind::StructDecl: { return ((ast::StructDeclNode*)node).is_exported; }
    case ast::AstKind::UnionDecl:  { return ((ast::UnionDeclNode*)node).is_exported; }
    case ast::AstKind::EnumDecl:   { return ((ast::EnumDeclNode*)node).is_exported; }
    case ast::AstKind::VarDecl:    { return ((ast::VarDeclNode*)node).is_exported; }
    case ast::AstKind::AliasDecl:  { return ((ast::AliasDeclNode*)node).is_exported; }
    else { return false; }
    }
    return false;
}

// Generated decls may not be `export`: an importer's exported surface is fixed when name collection runs.
export fn void splice_top_decl(module::Module* m, ast::AstNode* node, u32 generator_pos) {
    if(!is_spliceable_decl(node)) {
        diag::report(&m.diag, m.arena, generator_pos, "compinsert can only generate fn / struct / union / enum / const / alias declarations");
        return;
    }
    if(decl_is_exported(node)) {
        diag::report(&m.diag, m.arena, generator_pos, "compinsert-generated declarations may not be `export`");
        return;
    }
    Sema sema;
    sys::memset(&sema, 0, sizeof(Sema));
    sema.m = m;
    Sema* s = &sema;
    s.scope = (Scope*)m.global_scope;
    s.resolution_stack.arena = m.arena;
    collect_name_for_decl(s, node);
    resolve_decl_signature(s, node);
    if(node.h.kind == ast::AstKind::FnDecl) { ensure_body_checked(m, (ast::FnDeclNode*)node, m); }
    else if(node.h.kind == ast::AstKind::VarDecl) { ensure_var_init_checked(m, (ast::VarDeclNode*)node); }
    append_top_decl(m, node);
}

fn void append_top_decl(module::Module* m, ast::AstNode* node) {
    ast::BlockNode* block = (ast::BlockNode*)m.root_node;
    u64 count = block.stmts.len;
    block.stmts.ptr = (ast::AstNode**)arena::realloc_grow(m.arena, (void*)block.stmts.ptr, count * sizeof(ast::AstNode*), (count + 1) * sizeof(ast::AstNode*));
    block.stmts.ptr[count] = node;
    block.stmts.len = count + 1;
}

// Replace block.stmts[at] with `generated` (0+ stmts), keeping the rest in order.
fn void block_splice(module::Module* m, ast::BlockNode* block, u64 at, ast::AstNode*[] generated) {
    u64 old_len = block.stmts.len;
    u64 new_len = old_len - 1 + generated.len;
    ast::AstNode** buf = (ast::AstNode**)arena::alloc(m.arena, new_len * sizeof(ast::AstNode*));
    u64 write = 0;
    for(u64 i = 0; i < at; i += 1) { buf[write] = block.stmts[i]; write += 1; }
    for(u64 i = 0; i < generated.len; i += 1) { buf[write] = generated[i]; write += 1; }
    for(u64 i = at + 1; i < old_len; i += 1) { buf[write] = block.stmts[i]; write += 1; }
    block.stmts.ptr = buf;
    block.stmts.len = new_len;
}

// Sema-check a top-level var/const initializer, on demand or in the body pass; needed before comptime folds a const.
export fn void ensure_var_init_checked(module::Module* m, ast::VarDeclNode* vd) {
    if(vd.init_checked) { return; }
    vd.init_checked = true;
    if(vd.init == null) { return; }
    Sema sema;
    sys::memset(&sema, 0, sizeof(Sema));
    sema.m = m;
    Sema* s = &sema;
    s.scope = (Scope*)m.global_scope;
    s.resolution_stack.arena = m.arena;
    types::Ty* declared = resolve_type(s, vd.type_expr);
    if(declared != null) { check(s, vd.init, declared); } else { synth(s, vd.init); }
}

mutex::Mutex     g_body_lock;
condvar::Condvar g_body_cv;
bool             g_body_sync_ready;

// Called once, single-threaded, before parallel body checking.
export fn void init_body_sync() {
    if(g_body_sync_ready) { return; }
    mutex::create(&g_body_lock);
    condvar::create(&g_body_cv);
    g_body_sync_ready = true;
}

// Exactly one thread checks a given fn; others wait for Checked. body_owner lets a comptime call recursing into the
// fn being checked (same thread) proceed instead of self-waiting. check_fn_body runs unlocked, so N fns check at once.
export fn void ensure_body_checked(module::Module* m, ast::FnDeclNode* func, module::Module* requester) {
    if(!g_body_sync_ready) { init_body_sync(); }
    u64 me = threads::self();
    mutex::lock(&g_body_lock);
    while(func.body_state == ast::BodyState::InProgress && func.body_owner != me) {
        condvar::wait(&g_body_cv, &g_body_lock);
    }
    if(func.body_state == ast::BodyState::Checked || func.body_state == ast::BodyState::InProgress) {
        mutex::unlock(&g_body_lock);
        return;
    }
    func.body_state = ast::BodyState::InProgress;
    func.body_owner = me;
    mutex::unlock(&g_body_lock);
    Sema sema;
    sys::memset(&sema, 0, sizeof(Sema));
    sema.m = m;
    Sema* s = &sema;
    s.scope = (Scope*)m.global_scope;
    s.body_arena = requester.arena;
    s.body_diag = &requester.diag;
    s.resolution_stack.arena = requester.arena;
    check_fn_body(s, func);
    mutex::lock(&g_body_lock);
    func.body_state = ast::BodyState::Checked;
    condvar::broadcast(&g_body_cv);
    mutex::unlock(&g_body_lock);
}

fn void check_fn_body(Sema* s, ast::FnDeclNode* func) {
    if(func.body == null) { return; }
    Scope* fn_scope = scope_new(balloc(s), (Scope*)s.m.global_scope, 16);
    for(u64 i = 0; i < func.params.len; i += 1) {
        Decl* param_decl = register_sym(s, fn_scope, func.params[i].name, false, DeclKind::Param, func.params[i].src_pos);
        if(param_decl != null) {
            param_decl.ty = (types::Ty*)func.params[i].resolved_type;
            param_decl.data.param = &func.params[i];
            func.params[i].decl = (void*)param_decl;
        }
    }
    Scope* saved_scope = s.scope;
    ast::AstNode* saved_fn = s.current_fn;
    types::Ty* saved_return = s.current_return;
    s.scope = fn_scope;
    s.current_fn = (ast::AstNode*)func;
    s.current_return = fn_return_type(s, func);
    check_block_stmts(s, (ast::BlockNode*)func.body);
    s.scope = saved_scope;
    s.current_fn = saved_fn;
    s.current_return = saved_return;
}

// Full body-check of a substituted clone; the clone isn't in global_scope, so its return type comes from its own node.
export fn void sema_check_clone(module::Module* caller, module::Module* defining, ast::FnDeclNode* clone) {
    Sema sema;
    sys::memset(&sema, 0, sizeof(Sema));
    sema.m = caller;
    Sema* s = &sema;
    s.lookup_module = defining;
    s.scope = (Scope*)defining.global_scope;
    s.resolution_stack.arena = caller.arena;

    types::Ty* return_type = types::prim_void();
    if(clone.return_type != null) {
        types::Ty* resolved = resolve_type(s, clone.return_type);
        if(resolved != null) { return_type = resolved; }
    }
    Scope* fn_scope = scope_new(caller.arena, (Scope*)defining.global_scope, 16);
    for(u64 i = 0; i < clone.params.len; i += 1) {
        types::Ty* param_type = resolve_type(s, clone.params[i].type_expr);
        clone.params[i].resolved_type = (void*)param_type;
        Decl* param_decl = register_sym(s, fn_scope, clone.params[i].name, false, DeclKind::Param, clone.params[i].src_pos);
        if(param_decl != null) {
            param_decl.ty = param_type;
            param_decl.data.param = &clone.params[i];
            clone.params[i].decl = (void*)param_decl;
        }
    }
    if(clone.body != null) {
        s.scope = fn_scope;
        s.current_fn = (ast::AstNode*)clone;
        s.current_return = return_type;
        check_block_stmts(s, (ast::BlockNode*)clone.body);
    }
    clone.body_state = ast::BodyState::Checked;
}

fn types::Ty* fn_return_type(Sema* s, ast::FnDeclNode* func) {
    Decl* fn_decl = scope_lookup_local((Scope*)s.m.global_scope, func.name);
    if(fn_decl != null && fn_decl.ty != null && fn_decl.ty.kind == types::TypeKind::FnPtr) {
        return fn_decl.ty.data.fn_ptr.ret;
    }
    return types::prim_void();
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
// Signature resolution
// ============================================================================

// Aliases are dissolved here; the returned Type* is never an alias wrapper.
export fn types::Ty* resolve_type(Sema* s, ast::AstNode* texpr) {
    if(texpr == null) { return null; }
    switch(texpr.h.kind) {
    case ast::AstKind::PrimitiveType: {
        if(texpr.h.ty != null) { return (types::Ty*)texpr.h.ty; }
        ast::TypePrimitiveNode* primitive_node = (ast::TypePrimitiveNode*)texpr;
        types::Ty* resolved = types::primitive(types::get_primitive_kind_from_token(primitive_node.kind));
        if(primitive_node.kind == token::TokenKind::TYPE) { resolved = types::prim_type(); }
        texpr.h.ty = (void*)resolved;
        return resolved;
    }
    case ast::AstKind::PointerType: {
        ast::TypePointerNode* pointer_node = (ast::TypePointerNode*)texpr;
        types::Ty* pointee = resolve_type(s, pointer_node.pointee);
        if(pointee == null) { return null; }
        types::Ty* resolved = types::intern_pointer(pointee, pointer_node.is_const);
        texpr.h.ty = (void*)resolved;
        return resolved;
    }
    case ast::AstKind::ArrayType: {
        ast::TypeArrayNode* array_node = (ast::TypeArrayNode*)texpr;
        types::Ty* element_type = resolve_type(s, array_node.element);
        if(element_type == null) { return null; }
        u64 count = eval_const_u64(s, array_node.size_expr);
        types::Ty* resolved = types::intern_array(element_type, count);
        texpr.h.ty = (void*)resolved;
        return resolved;
    }
    case ast::AstKind::SliceType: {
        ast::TypeSliceNode* slice_node = (ast::TypeSliceNode*)texpr;
        types::Ty* element_type = resolve_type(s, slice_node.element);
        if(element_type == null) { return null; }
        types::Ty* resolved = types::intern_slice(element_type);
        texpr.h.ty = (void*)resolved;
        return resolved;
    }
    case ast::AstKind::FnPtrType: {
        ast::TypeFnPtrNode* fnptr_node = (ast::TypeFnPtrNode*)texpr;
        types::Ty* return_type = resolve_type(s, fnptr_node.return_type);
        if(return_type == null) { return null; }
        types::Ty*[] param_types = resolve_type_list(s, fnptr_node.param_types);
        types::Ty* resolved = types::intern_fn_ptr(return_type, param_types, false);
        texpr.h.ty = (void*)resolved;
        return resolved;
    }
    case ast::AstKind::NamedType: {
        types::Ty* resolved = resolve_named_type(s, (ast::TypeNamedNode*)texpr);
        texpr.h.ty = (void*)resolved;
        return resolved;
    }
    case ast::AstKind::StructType: {
        if(texpr.h.ty != null) { return (types::Ty*)texpr.h.ty; }
        ast::StructDeclNode* anon_decl = synth_anon_struct_decl(s, (ast::TypeStructNode*)texpr);
        if(anon_decl == null) { return null; }
        types::Ty* resolved = types::intern_struct((void*)anon_decl);
        texpr.h.ty = (void*)resolved;
        return resolved;
    }
    case ast::AstKind::UnionType: {
        if(texpr.h.ty != null) { return (types::Ty*)texpr.h.ty; }
        ast::UnionDeclNode* anon_decl = synth_anon_union_decl(s, (ast::TypeUnionNode*)texpr);
        if(anon_decl == null) { return null; }
        types::Ty* resolved = types::intern_union((void*)anon_decl);
        texpr.h.ty = (void*)resolved;
        return resolved;
    }
    case ast::AstKind::Typeof: {
        types::Ty* operand = synth(s, ((ast::TypeofNode*)texpr).expr);
        texpr.h.ty = (void*)operand;
        return operand;
    }
    case ast::AstKind::Call: {
        if(eval_comptime_type_hook == null) { return null; }
        if(synth(s, texpr) == null) { return null; }   // resolve callee + args before the interpreter runs
        types::Ty* resolved = eval_comptime_type_hook(s.m, texpr);
        if(resolved == null) {
            u8[] msg = "expression does not evaluate to a type";
            emit_diag(s, texpr.h.src_pos, msg.ptr, (i32)msg.len);
            return null;
        }
        texpr.h.ty = (void*)resolved;
        return resolved;
    }
    else { return null; }
    }
    return null;
}

export fn types::Ty*[] resolve_type_list(Sema* s, ast::AstNode*[] type_exprs) {
    if(type_exprs.len == 0) {
        types::Ty*[] empty = {null, 0};
        return empty;
    }
    types::Ty** resolved_types = (types::Ty**)arena::alloc(balloc(s), type_exprs.len * sizeof(types::Ty*));
    for(u64 type_index = 0; type_index < type_exprs.len; type_index += 1) {
        resolved_types[type_index] = resolve_type(s, type_exprs[type_index]);
    }
    types::Ty*[] out = {resolved_types, type_exprs.len};
    return out;
}

// Crosses a module boundary when n.namespace names an import.
fn types::Ty* resolve_named_type(Sema* s, ast::TypeNamedNode* n) {
    if(n.h.ty != null) { return (types::Ty*)n.h.ty; }   // pre-bound by comptime type-param substitution
    if(n.namespace == null) {
        for(u64 i = 0; i < s.comptime_type_names.len; i += 1) {
            if(n.name == s.comptime_type_names[i]) { return types::prim_type(); }
        }
        // Bare name resolves in the lookup module's own scope (the defining module for a clone body), no export filter.
        module::Module* home = s.m;
        if(s.lookup_module != null) { home = s.lookup_module; }
        Decl* decl = scope_lookup_local((Scope*)home.global_scope, n.name);
        if(decl == null) {
            diag_unknown_type(s, n.h.src_pos, n.name);
            return null;
        }
        return decl_to_type(s, home, decl);
    }
    Decl* namespace_decl = scope_lookup(s.scope, n.namespace);
    if(namespace_decl == null || namespace_decl.kind != DeclKind::Import) {
        Decl* q = resolve_qualifier(s, n.namespace);
        if(q != null) { namespace_decl = q; }
    }
    if(namespace_decl == null || namespace_decl.kind != DeclKind::Import || namespace_decl.data.module == null) {
        diag_unknown_type(s, n.h.src_pos, n.name);
        return null;
    }
    module::Module* target = namespace_decl.data.module;
    Decl* decl = scope_lookup_local((Scope*)target.global_scope, n.name);
    if(decl == null || (!decl.is_exported && target != s.m)) {
        diag_unknown_type(s, n.h.src_pos, n.name);
        return null;
    }
    return decl_to_type(s, target, decl);
}

fn ast::StructDeclNode* synth_anon_struct_decl(Sema* s, ast::TypeStructNode* n) {
    ast::StructDeclNode* decl = (ast::StructDeclNode*)arena::alloc(balloc(s), sizeof(ast::StructDeclNode));
    sys::memset(decl, 0, sizeof(ast::StructDeclNode));
    decl.h.kind = ast::AstKind::StructDecl;
    decl.h.src_pos = n.h.src_pos;
    decl.fields = n.fields;
    resolve_fields(s, decl.fields);
    return decl;
}

fn ast::UnionDeclNode* synth_anon_union_decl(Sema* s, ast::TypeUnionNode* n) {
    ast::UnionDeclNode* decl = (ast::UnionDeclNode*)arena::alloc(balloc(s), sizeof(ast::UnionDeclNode));
    sys::memset(decl, 0, sizeof(ast::UnionDeclNode));
    decl.h.kind = ast::AstKind::UnionDecl;
    decl.h.src_pos = n.h.src_pos;
    decl.fields = n.fields;
    resolve_fields(s, decl.fields);
    return decl;
}

// Extern struct/union AST nodes lack the qualified_name slot, so they can't be interned as-is; mirror into a real decl node.
fn ast::StructDeclNode* materialize_extern_struct(Sema* s, ast::ExternStructDeclNode* es) {
    ast::StructDeclNode* sd = (ast::StructDeclNode*)arena::alloc(balloc(s), sizeof(ast::StructDeclNode));
    sys::memset(sd, 0, sizeof(ast::StructDeclNode));
    sd.h.kind = ast::AstKind::StructDecl;
    sd.h.src_pos = es.h.src_pos;
    sd.name = es.name;
    sd.qualified_name = qualify_decl_name(s, es.name);
    sd.fields = es.fields;
    sd.is_exported = es.is_exported;
    return sd;
}

fn ast::UnionDeclNode* materialize_extern_union(Sema* s, ast::ExternUnionDeclNode* eu) {
    ast::UnionDeclNode* ud = (ast::UnionDeclNode*)arena::alloc(balloc(s), sizeof(ast::UnionDeclNode));
    sys::memset(ud, 0, sizeof(ast::UnionDeclNode));
    ud.h.kind = ast::AstKind::UnionDecl;
    ud.h.src_pos = eu.h.src_pos;
    ud.name = eu.name;
    ud.qualified_name = qualify_decl_name(s, eu.name);
    ud.fields = eu.fields;
    ud.is_exported = eu.is_exported;
    return ud;
}

// An int literal folds directly; any other size expression is synthesized and, if constant, folded through the interpreter.
export fn u64 eval_const_u64(Sema* s, ast::AstNode* expr) {
    if(expr == null) { return 0; }
    if(expr.h.kind == ast::AstKind::IntLit) {
        return ((ast::IntLitNode*)expr).value;
    }
    if(eval_const_i64_hook == null) { return 0; }
    types::Ty* t = synth(s, expr);
    if(t == null) { return 0; }
    if(!expr_has_flag(expr, ast::AstFlags::ConstExpr)) {
        diag_array_size_not_const(s, expr.h.src_pos);
        return 0;
    }
    i64 out = 0;
    if(!eval_const_i64_hook(s.m, expr, &out)) {
        diag_array_size_not_int(s, expr.h.src_pos);
        return 0;
    }
    if(out < 0) {
        diag_array_size_negative(s, expr.h.src_pos);
        return 0;
    }
    return (u64)out;
}

fn types::Ty* decl_to_type(Sema* s, module::Module* target, Decl* d) {
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
        types::Ty* resolved = resolve_type(s, ((ast::AliasDeclNode*)node).target);
        stack_pop(&s.resolution_stack);
        d.ty = resolved;
        return resolved;
    }
    diag_unknown_type(s, node.h.src_pos, d.name);
    return null;
}


// ============================================================================
// Body checking: bidirectional type checking
// ============================================================================

// StructLit / ArrayLit / UndefinedLit are not synth-able — they need check-mode.
export fn types::Ty* synth(Sema* s, ast::AstNode* e) {
    if(e == null) { return null; }
    // A type node in value position is a `Type` value; resolve_type records the represented type in h.ty (read back by the interpreter).
    if(ast::is_type(e.h.kind)) {
        if(resolve_type(s, e) == null) { return null; }
        e.h.flags = (ast::AstFlags)((u16)e.h.flags | (u16)ast::AstFlags::ConstExpr);
        return types::prim_type();
    }
    switch(e.h.kind) {
    case ast::AstKind::IntLit: {
        ast::IntLitNode* lit = (ast::IntLitNode*)e;
        types::Ty* t = types::prim_i32();
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
        types::Ty* t = types::intern_pointer(types::prim_u8(), false);
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

fn void set_expr(ast::AstNode* e, types::Ty* ty, u16 add_flags) {
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
export fn bool check(Sema* s, ast::AstNode* e, types::Ty* expected) {
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
        if(unary.op == token::TokenKind::Minus && unary.operand != null && unary.operand.h.kind == ast::AstKind::FloatLit && types::is_float(expected)) {
            set_expr(unary.operand, expected, (u16)ast::AstFlags::ConstExpr);
            set_expr(e, expected, (u16)ast::AstFlags::ConstExpr);
            return true;
        }
    }
    switch(e.h.kind) {
    case ast::AstKind::IntLit: {
        return check_int_lit(s, (ast::IntLitNode*)e, expected);
    }
    case ast::AstKind::FloatLit: {
        if(types::is_float(expected)) {
            set_expr(e, expected, (u16)ast::AstFlags::ConstExpr);
            return true;
        }
        diag_type_mismatch(s, e.h.src_pos, types::prim_f64(), expected);
        mark_error(e);
        return false;
    }
    case ast::AstKind::NullLit: {
        if(types::is_ptr(expected) || types::is_slice(expected) || types::is_fnptr(expected)) {
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
        types::Ty* got = synth(s, e);
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

export fn types::Ty* synth_ident(Sema* s, ast::IdentNode* n) {
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
fn bool is_namespace_decl(Decl* d) {
    if(d == null) { return false; }
    if(d.kind == DeclKind::Import) { return true; }
    return d.kind == DeclKind::Node && d.data.node != null && d.data.node.h.kind == ast::AstKind::EnumDecl;
}

fn Decl* self_import(Sema* s) {
    Decl* d = (Decl*)arena::alloc(s.m.arena, sizeof(Decl));
    sys::memset(d, 0, sizeof(Decl));
    d.kind = DeclKind::Import;
    d.name = s.m.name;
    d.data.module = s.m;
    return d;
}

// The left of `::` names a module or enum, never a value: a shadowing local must not win, and a module may name itself.
fn Decl* resolve_qualifier(Sema* s, symbol::Symbol* name) {
    if(name == s.m.name) { return self_import(s); }
    Decl* g = scope_lookup_local((Scope*)s.m.global_scope, name);
    if(is_namespace_decl(g)) { return g; }
    return null;
}

fn Decl* resolve_namespace_decl(Sema* s, ast::AstNode* base) {
    if(base == null) { return null; }
    if(base.h.kind == ast::AstKind::Ident) {
        symbol::Symbol* name = ((ast::IdentNode*)base).name;
        Decl* d = scope_lookup(s.scope, name);
        if(is_namespace_decl(d)) { return d; }
        Decl* q = resolve_qualifier(s, name);
        if(q != null) { return q; }
        return d;
    }
    if(base.h.kind == ast::AstKind::NamespaceAccess) {
        ast::NamespaceAccessNode* na = (ast::NamespaceAccessNode*)base;
        Decl* outer = resolve_namespace_decl(s, na.base);
        if(outer == null || outer.kind != DeclKind::Import || outer.data.module == null) { return null; }
        return scope_lookup_local((Scope*)outer.data.module.global_scope, na.name);
    }
    return null;
}

fn types::Ty* synth_ns_access(Sema* s, ast::NamespaceAccessNode* n) {
    Decl* ns = resolve_namespace_decl(s, n.base);
    if(ns == null) {
        diag_not_namespace(s, n.h.src_pos);
        mark_error((ast::AstNode*)n);
        return null;
    }
    if(ns.kind == DeclKind::Import) {
        module::Module* target = ns.data.module;
        Decl* found = scope_lookup_local((Scope*)target.global_scope, n.name);
        if(found == null || (!found.is_exported && target != s.m)) {
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
    if(ns.kind == DeclKind::Node && ns.data.node != null && ns.data.node.h.kind == ast::AstKind::EnumDecl) {
        ast::EnumDeclNode* edecl = (ast::EnumDeclNode*)ns.data.node;
        ast::EnumMember* mem = find_enum_member(edecl, n.name);
        if(mem == null) {
            diag_unknown_member(s, n.h.src_pos, n.name);
            mark_error((ast::AstNode*)n);
            return null;
        }
        n.resolved = mem.decl;
        set_expr((ast::AstNode*)n, ns.ty, (u16)ast::AstFlags::ConstExpr);
        return ns.ty;
    }
    diag_not_namespace(s, n.h.src_pos);
    mark_error((ast::AstNode*)n);
    return null;
}

// Auto-derefs one pointer level; slices expose the magic .ptr / .len fields.
fn types::Ty* synth_member_access(Sema* s, ast::MemberAccessNode* n) {
    types::Ty* base = synth(s, n.base);
    if(base == null) { return null; }
    types::Ty* container = base;
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
            types::Ty* elem_ptr = types::intern_pointer(container.data.slice_elem, false);
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
    types::Ty* field_ty = (types::Ty*)field.resolved_type;
    n.resolved = field.decl;
    set_expr((ast::AstNode*)n, field_ty, field_flags);
    return field_ty;
}

fn bool check_index(Sema* s, ast::AstNode* index) {
    types::Ty* index_type = synth(s, index);
    if(index_type == null) { return false; }
    if(types::is_int(index_type)) { return true; }
    diag_index_not_int(s, index.h.src_pos, index_type);
    return false;
}

fn types::Ty* synth_array_index(Sema* s, ast::ArrayIndexNode* n) {
    types::Ty* base = synth(s, n.base);
    if(base == null) { return null; }
    types::Ty* elem = null;
    bool base_is_array = false;
    if(base.kind == types::TypeKind::Array)   { elem = base.data.array.elem; base_is_array = true; }
    else if(base.kind == types::TypeKind::Slice)   { elem = base.data.slice_elem; }
    else if(base.kind == types::TypeKind::Pointer) { elem = base.data.pointee; }
    else {
        diag_not_indexable(s, n.h.src_pos, base);
        mark_error((ast::AstNode*)n);
        return null;
    }
    if(!check_index(s, n.index)) {
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

fn types::Ty* synth_slice_range(Sema* s, ast::SliceRangeNode* n) {
    types::Ty* base = synth(s, n.base);
    if(base == null) { return null; }
    types::Ty* elem = null;
    if(base.kind == types::TypeKind::Array)   { elem = base.data.array.elem; }
    else if(base.kind == types::TypeKind::Slice)   { elem = base.data.slice_elem; }
    else if(base.kind == types::TypeKind::Pointer) { elem = base.data.pointee; }
    else {
        diag_not_indexable(s, n.h.src_pos, base);
        mark_error((ast::AstNode*)n);
        return null;
    }
    if(base.kind == types::TypeKind::Pointer && n.hi == null) {
        diag_ptr_slice_needs_hi(s, n.h.src_pos);
        mark_error((ast::AstNode*)n);
        return null;
    }
    if(n.lo != null && !check_index(s, n.lo)) { mark_error((ast::AstNode*)n); return null; }
    if(n.hi != null && !check_index(s, n.hi)) { mark_error((ast::AstNode*)n); return null; }
    types::Ty* result = types::intern_slice(elem);
    set_expr((ast::AstNode*)n, result, 0);
    return result;
}

fn Decl* callee_overload_head(Sema* s, ast::AstNode* callee) {
    if(callee == null) { return null; }
    if(callee.h.kind == ast::AstKind::Ident) {
        Decl* d = scope_lookup(s.scope, ((ast::IdentNode*)callee).name);
        if(d != null && decl_is_fn(d)) { return d; }
        return null;
    }
    if(callee.h.kind == ast::AstKind::NamespaceAccess) {
        ast::NamespaceAccessNode* na = (ast::NamespaceAccessNode*)callee;
        Decl* ns = resolve_namespace_decl(s, na.base);
        if(ns != null && ns.kind == DeclKind::Import && ns.data.module != null) {
            Decl* d = scope_lookup_local((Scope*)ns.data.module.global_scope, na.name);
            if(d != null && decl_is_fn(d) && d.is_exported) { return d; }
        }
        return null;
    }
    return null;
}

fn bool arg_compatible(ast::AstNode* arg, types::Ty* arg_type, types::Ty* param_type) {
    if(arg_type == param_type) { return true; }
    if(arg.h.kind == ast::AstKind::IntLit) { return types::is_int(param_type); }
    if(arg.h.kind == ast::AstKind::FloatLit) { return types::is_float(param_type); }
    if(arg.h.kind == ast::AstKind::StringLit) { return is_byte(string_lit_elem(param_type)); }   // a string literal targets any byte pointer/slice/array
    return types::is_convertible(arg_type, param_type);
}

fn types::Ty* string_lit_elem(types::Ty* target) {
    if(target.kind == types::TypeKind::Pointer) { return target.data.pointee; }
    if(target.kind == types::TypeKind::Slice)   { return target.data.slice_elem; }
    if(target.kind == types::TypeKind::Array)   { return target.data.array.elem; }
    return null;
}

// -1 = not a candidate; otherwise the count of exact-type args, so the closest overload wins.
fn i32 overload_score(Decl* cand, ast::AstNode*[] args, types::Ty*[] arg_types) {
    if(cand.ty == null || cand.ty.kind != types::TypeKind::FnPtr) { return -1; }
    types::Ty*[] params = cand.ty.data.fn_ptr.params;
    bool variadic = cand.ty.data.fn_ptr.is_variadic;
    if(!variadic && args.len != params.len) { return -1; }
    if(variadic && args.len < params.len) { return -1; }
    i32 score = 0;
    for(u64 i = 0; i < params.len; i += 1) {
        if(!arg_compatible(args[i], arg_types[i], params[i])) { return -1; }
        if(arg_types[i] == params[i]) { score += 1; }
    }
    return score;
}

fn void set_callee_resolved(ast::AstNode* callee, Decl* chosen) {
    if(callee.h.kind == ast::AstKind::Ident) { ((ast::IdentNode*)callee).resolved = (void*)chosen; }
    else if(callee.h.kind == ast::AstKind::NamespaceAccess) { ((ast::NamespaceAccessNode*)callee).resolved = (void*)chosen; }
    set_expr(callee, chosen.ty, 0);
}

fn types::Ty* synth_overloaded_call(Sema* s, ast::CallNode* n, Decl* head) {
    types::Ty** arg_type_mem = (types::Ty**)arena::alloc(balloc(s), n.args.len * sizeof(types::Ty*));
    types::Ty*[] arg_types = {arg_type_mem, n.args.len};
    bool args_ok = true;
    for(u64 i = 0; i < n.args.len; i += 1) {
        arg_types[i] = synth(s, n.args[i]);
        if(arg_types[i] == null) { args_ok = false; }
    }
    if(!args_ok) { mark_error((ast::AstNode*)n); return null; }
    Decl* best = null;
    i32 best_score = -1;
    bool ambiguous = false;
    Decl* cand = head;
    while(cand != null) {
        i32 score = overload_score(cand, n.args, arg_types);
        if(score > best_score) { best = cand; best_score = score; ambiguous = false; }
        else if(score == best_score && score >= 0) { ambiguous = true; }
        cand = cand.next_overload;
    }
    if(best == null || best_score < 0) {
        diag_no_overload(s, n.h.src_pos, head.name);
        mark_error((ast::AstNode*)n);
        return null;
    }
    if(ambiguous) {
        diag_ambiguous_overload(s, n.h.src_pos, head.name);
        mark_error((ast::AstNode*)n);
        return null;
    }
    types::Ty*[] params = best.ty.data.fn_ptr.params;
    for(u64 i = 0; i < params.len; i += 1) { check(s, n.args[i], params[i]); }
    for(u64 j = params.len; j < n.args.len; j += 1) { synth(s, n.args[j]); }
    set_callee_resolved(n.callee, best);
    types::Ty* ret = best.ty.data.fn_ptr.ret;
    set_expr((ast::AstNode*)n, ret, 0);
    return ret;
}

fn ast::FnDeclNode* as_generic_fn(Decl* d) {
    if(d.kind != DeclKind::Node || d.data.node == null) { return null; }
    if(d.data.node.h.kind != ast::AstKind::FnDecl) { return null; }
    ast::FnDeclNode* fnd = (ast::FnDeclNode*)d.data.node;
    if(!is_generic_fn(fnd)) { return null; }
    return fnd;
}

fn types::Ty* clone_return_type(ast::FnDeclNode* clone) {
    if(clone.return_type != null && clone.return_type.h.ty != null) { return (types::Ty*)clone.return_type.h.ty; }
    return types::prim_void();
}

// Generic callee: sema synths runtime args, the hook infers comptime args + monomorphizes, then sema checks args vs the clone.
fn types::Ty* synth_generic_call(Sema* s, ast::CallNode* n, ast::FnDeclNode* generic) {
    if(resolve_generic_call_hook == null) {
        u8[] msg = "generic calls require the comptime interpreter";
        sema_report(s, n.h.src_pos, msg);
        mark_error((ast::AstNode*)n);
        return null;
    }
    u64 n_runtime = 0;
    for(u64 i = 0; i < generic.params.len; i += 1) {
        if(!generic.params[i].is_comptime) { n_runtime += 1; }
    }
    if(n.args.len != n_runtime) {
        u8[] msg = "generic call: pass exactly the runtime arguments (explicit comptime args not yet supported)";
        sema_report(s, n.h.src_pos, msg);
        mark_error((ast::AstNode*)n);
        return null;
    }
    types::Ty** arg_type_mem = (types::Ty**)arena::alloc(balloc(s), n.args.len * sizeof(types::Ty*));
    types::Ty*[] arg_types = {arg_type_mem, n.args.len};
    bool args_ok = true;
    for(u64 i = 0; i < n.args.len; i += 1) {
        if(ast::is_type(n.args[i].h.kind)) {
            u8[] msg = "type argument passed to a runtime parameter";
            sema_report(s, n.args[i].h.src_pos, msg);
            mark_error((ast::AstNode*)n);
            return null;
        }
        arg_types[i] = synth(s, n.args[i]);
        if(arg_types[i] == null) { args_ok = false; }
    }
    if(!args_ok) { mark_error((ast::AstNode*)n); return null; }
    ast::FnDeclNode* clone = resolve_generic_call_hook(s.m, generic, arg_types);
    if(clone == null) {
        diag_infer_failure(s, n.h.src_pos, generic.name);
        mark_error((ast::AstNode*)n);
        return null;
    }
    u64 runtime_index = 0;
    for(u64 i = 0; i < clone.params.len; i += 1) {
        if(clone.params[i].is_comptime) { continue; }
        types::Ty* param_type = (types::Ty*)clone.params[i].resolved_type;
        if(runtime_index < n.args.len && param_type != null) { check(s, n.args[runtime_index], param_type); }
        runtime_index += 1;
    }
    n.resolved_fn = (void*)clone;
    types::Ty* ret = clone_return_type(clone);
    set_expr((ast::AstNode*)n, ret, 0);
    return ret;
}

// An explicit type argument is a type expression, or a bare name / mod::name that resolves to a nominal type.
fn types::Ty* resolve_type_arg(Sema* s, ast::AstNode* arg) {
    if(ast::is_type(arg.h.kind)) { return resolve_type(s, arg); }
    if(arg.h.kind == ast::AstKind::Ident) {
        symbol::Symbol* name = ((ast::IdentNode*)arg).name;
        Decl* decl = scope_lookup_local((Scope*)s.m.global_scope, name);
        if(decl == null) { diag_unknown_type(s, arg.h.src_pos, name); return null; }
        return decl_to_type(s, s.m, decl);
    }
    if(arg.h.kind == ast::AstKind::NamespaceAccess) {
        ast::NamespaceAccessNode* na = (ast::NamespaceAccessNode*)arg;
        Decl* ns = resolve_namespace_decl(s, na.base);
        if(ns != null && ns.kind == DeclKind::Import && ns.data.module != null) {
            Decl* decl = scope_lookup_local((Scope*)ns.data.module.global_scope, na.name);
            if(decl != null && decl.is_exported) { return decl_to_type(s, ns.data.module, decl); }
        }
        diag_unknown_type(s, arg.h.src_pos, na.name);
        return null;
    }
    u8[] msg = "expected a type argument for the comptime parameter";
    sema_report(s, arg.h.src_pos, msg);
    return null;
}

// Explicit form: comptime-Type-param positions hold type-expression args; resolve them and monomorphize.
fn types::Ty* synth_generic_call_explicit(Sema* s, ast::CallNode* n, ast::FnDeclNode* generic) {
    if(resolve_generic_explicit_hook == null) {
        u8[] msg = "generic calls require the comptime interpreter";
        sema_report(s, n.h.src_pos, msg);
        mark_error((ast::AstNode*)n);
        return null;
    }
    u64 n_comptime = 0;
    for(u64 i = 0; i < generic.params.len; i += 1) {
        if(generic.params[i].is_comptime) { n_comptime += 1; }
    }
    value::Value* carg_mem = (value::Value*)arena::alloc(balloc(s), n_comptime * sizeof(value::Value));
    value::Value[] cargs = {carg_mem, 0};
    for(u64 i = 0; i < generic.params.len; i += 1) {
        if(!generic.params[i].is_comptime) { continue; }
        if(is_type_kw(generic.params[i].type_expr)) {
            types::Ty* t = resolve_type_arg(s, n.args[i]);
            if(t == null) { mark_error((ast::AstNode*)n); return null; }
            cargs[cargs.len] = value::val_type(t);
        } else {
            ast::AstNode* varg = n.args[i];
            i64 v = 0;
            bool is_const = false;
            if(varg.h.kind == ast::AstKind::IntLit) {
                v = (i64)((ast::IntLitNode*)varg).value;
                is_const = true;
            } else if(varg.h.kind == ast::AstKind::UnaryOp) {
                ast::UnaryOpNode* u = (ast::UnaryOpNode*)varg;
                if(u.op == token::TokenKind::Minus && u.operand != null && u.operand.h.kind == ast::AstKind::IntLit) {
                    v = -(i64)((ast::IntLitNode*)u.operand).value;
                    is_const = true;
                }
            }
            if(!is_const) {
                u8[] msg = "comptime value argument must be an integer literal";
                sema_report(s, varg.h.src_pos, msg);
                mark_error((ast::AstNode*)n);
                return null;
            }
            types::Ty* pt = resolve_type(s, generic.params[i].type_expr);
            cargs[cargs.len] = value::val_int(v, pt);
        }
        cargs.len += 1;
    }
    ast::FnDeclNode* clone = resolve_generic_explicit_hook(s.m, generic, cargs);
    if(clone == null) { diag_infer_failure(s, n.h.src_pos, generic.name); mark_error((ast::AstNode*)n); return null; }
    for(u64 i = 0; i < clone.params.len; i += 1) {
        if(clone.params[i].is_comptime) { continue; }
        types::Ty* param_type = (types::Ty*)clone.params[i].resolved_type;
        if(i < n.args.len && param_type != null) { check(s, n.args[i], param_type); }
    }
    n.resolved_fn = (void*)clone;
    types::Ty* ret = clone_return_type(clone);
    set_expr((ast::AstNode*)n, ret, 0);
    return ret;
}

fn types::Ty* synth_call(Sema* s, ast::CallNode* n) {
    Decl* callee_decl = callee_overload_head(s, n.callee);
    if(callee_decl != null && callee_decl.next_overload == null) {
        ast::FnDeclNode* generic = as_generic_fn(callee_decl);
        if(generic != null) {
            u64 n_runtime = 0;
            for(u64 i = 0; i < generic.params.len; i += 1) {
                if(!generic.params[i].is_comptime) { n_runtime += 1; }
            }
            // Inference form (runtime args only) vs explicit all-args form.
            if(n.args.len == n_runtime) { return synth_generic_call(s, n, generic); }
            if(n.args.len == generic.params.len) {
                return synth_generic_call_explicit(s, n, generic);
            }
        }
    }
    if(callee_decl != null && callee_decl.next_overload != null) {
        return synth_overloaded_call(s, n, callee_decl);
    }
    types::Ty* callee = synth(s, n.callee);
    if(callee == null) { return null; }
    if(callee.kind != types::TypeKind::FnPtr) {
        diag_not_callable(s, n.h.src_pos, callee);
        mark_error((ast::AstNode*)n);
        return null;
    }
    types::Ty*[] params = callee.data.fn_ptr.params;
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
    types::Ty* ret = callee.data.fn_ptr.ret;
    set_expr((ast::AstNode*)n, ret, 0);
    return ret;
}

fn types::Ty* synth_cast(Sema* s, ast::CastNode* n) {
    types::Ty* target = resolve_type(s, n.target_type);
    types::Ty* src = synth(s, n.expr);
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

fn types::Ty* synth_unary(Sema* s, ast::UnaryOpNode* n) {
    types::Ty* operand = synth(s, n.operand);
    if(operand == null) { return null; }
    // A function name is not an l-value, but `&fn` is the function pointer itself, like bare `fn`.
    if(n.op == token::TokenKind::Amp && operand.kind == types::TypeKind::FnPtr && !expr_has_flag(n.operand, ast::AstFlags::LValue)) {
        u16 fn_flags = 0;
        if(expr_has_flag(n.operand, ast::AstFlags::ConstExpr)) { fn_flags = (u16)ast::AstFlags::ConstExpr; }
        set_expr((ast::AstNode*)n, operand, fn_flags);
        return operand;
    }
    if(n.op == token::TokenKind::Amp && !expr_has_flag(n.operand, ast::AstFlags::LValue)) {
        diag_not_lvalue(s, n.operand.h.src_pos);
        mark_error((ast::AstNode*)n);
        return null;
    }
    types::Ty* result = op::unaryop_result_type(n.op, operand);
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

fn bool is_numeric_literal_operand(ast::AstNode* e) {
    if(e == null) { return false; }
    if(e.h.kind == ast::AstKind::IntLit || e.h.kind == ast::AstKind::FloatLit) { return true; }
    if(e.h.kind == ast::AstKind::UnaryOp) {
        ast::UnaryOpNode* u = (ast::UnaryOpNode*)e;
        if(u.op != token::TokenKind::Minus || u.operand == null) { return false; }
        return u.operand.h.kind == ast::AstKind::IntLit || u.operand.h.kind == ast::AstKind::FloatLit;
    }
    return false;
}

fn bool retype_numeric_literal(ast::AstNode* e, types::Ty* target) {
    if(target == null) { return false; }
    if(e.h.kind == ast::AstKind::IntLit) {
        if(types::is_int(target) && types::int_lit_fits(((ast::IntLitNode*)e).value, false, target)) { e.h.ty = (void*)target; return true; }
        return false;
    }
    if(e.h.kind == ast::AstKind::FloatLit) {
        if(types::is_float(target)) { e.h.ty = (void*)target; return true; }
        return false;
    }
    ast::UnaryOpNode* u = (ast::UnaryOpNode*)e;
    if(u.operand.h.kind == ast::AstKind::IntLit) {
        if(types::is_int(target) && types::int_lit_fits(((ast::IntLitNode*)u.operand).value, true, target)) { u.operand.h.ty = (void*)target; e.h.ty = (void*)target; return true; }
        return false;
    }
    if(types::is_float(target)) { u.operand.h.ty = (void*)target; e.h.ty = (void*)target; return true; }
    return false;
}

// A lone literal operand takes the other operand's concrete numeric type; both-or-neither literal is left alone.
fn void adapt_binop_operands(ast::AstNode* lhs, types::Ty** lt, ast::AstNode* rhs, types::Ty** rt) {
    bool lhs_lit = is_numeric_literal_operand(lhs);
    bool rhs_lit = is_numeric_literal_operand(rhs);
    if(lhs_lit == rhs_lit) { return; }
    // A literal paired with an enum adapts to the enum's base int (the enum acts as its base in arithmetic/bitwise).
    if(rhs_lit) {
        types::Ty* target = *lt;
        if(target.kind == types::TypeKind::Enum) { target = types::enum_base_type(target); }
        if(retype_numeric_literal(rhs, target)) { *rt = target; }
    } else {
        types::Ty* target = *rt;
        if(target.kind == types::TypeKind::Enum) { target = types::enum_base_type(target); }
        if(retype_numeric_literal(lhs, target)) { *lt = target; }
    }
}

fn types::Ty* synth_binary(Sema* s, ast::BinaryOpNode* n) {
    types::Ty* lt = synth(s, n.lhs);
    if(lt == null) { return null; }
    types::Ty* rt = synth(s, n.rhs);
    if(rt == null) { return null; }
    adapt_binop_operands(n.lhs, &lt, n.rhs, &rt);
    types::Ty* result = op::binop_result_type(n.op, lt, rt);
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

fn types::Ty* synth_sizeof(Sema* s, ast::SizeofNode* n) {
    types::Ty* target = sizeof_operand_type(s, n.arg);
    if(target == null) { return null; }
    types::size_of(bdiag(s), target);
    set_expr((ast::AstNode*)n, types::prim_u64(), (u16)ast::AstFlags::ConstExpr);
    return types::prim_u64();
}

fn types::Ty* synth_alignof(Sema* s, ast::AlignofNode* n) {
    types::Ty* target = sizeof_operand_type(s, n.arg);
    if(target == null) { return null; }
    types::align_of(bdiag(s), target);
    set_expr((ast::AstNode*)n, types::prim_u64(), (u16)ast::AstFlags::ConstExpr);
    return types::prim_u64();
}

// The argument is either a type expression or a value expression to take the type of.
fn types::Ty* sizeof_operand_type(Sema* s, ast::AstNode* arg) {
    if(arg == null) { return null; }
    // The parser speculatively types a bare name as a NamedType; sizeof(value) resolves it as an expression instead.
    // A pre-bound h.ty means comptime substitution already fixed the type (e.g. sizeof(T) in a generic) — leave it.
    if(arg.h.kind == ast::AstKind::NamedType && arg.h.ty == null && ((ast::TypeNamedNode*)arg).namespace == null) {
        Decl* d = scope_lookup(s.scope, ((ast::TypeNamedNode*)arg).name);
        if(d != null && (decl_is_lvalue(d) || decl_is_const_expr(d))) {
            arg.h.ty = (void*)d.ty;
            return d.ty;
        }
    }
    if(ast::is_type(arg.h.kind) || arg.h.kind == ast::AstKind::Typeof) { return resolve_type(s, arg); }
    return synth(s, arg);
}

fn types::Ty* synth_typeof(Sema* s, ast::TypeofNode* n) {
    types::Ty* operand = synth(s, n.expr);
    if(operand == null) { mark_error((ast::AstNode*)n); return null; }
    set_expr((ast::AstNode*)n, types::prim_type(), (u16)ast::AstFlags::ConstExpr);
    return types::prim_type();
}

fn void reflect_set_field(ast::FieldDecl* f, u8[] name, types::Ty* ty) {
    sys::memset(f, 0, sizeof(ast::FieldDecl));
    f.name = interner::intern(name);
    f.resolved_type = (void*)ty;
}

// TypeInfo / FieldInfo / TypeKind are spelled like ordinary types, so every module scope carries them.
// A module declaring one of those names keeps its own (types.sl has its own TypeKind).
fn void register_reflection_names(Sema* s, Scope* module_scope) {
    types::Ty* ti = reflection_typeinfo_type(s.m);
    types::Ty* fi = reflection_fieldinfo_type(s.m);
    types::Ty* tk = reflection_typekind_type(s.m);

    register_builtin_type(s, module_scope, "TypeInfo", ti, (ast::AstNode*)ti.data.struct_decl);
    register_builtin_type(s, module_scope, "FieldInfo", fi, (ast::AstNode*)fi.data.struct_decl);
    if(register_builtin_type(s, module_scope, "TypeKind", tk, (ast::AstNode*)g_reflect_typekind_decl)) {
        ast::EnumDeclNode* enum_decl = (ast::EnumDeclNode*)g_reflect_typekind_decl;
        for(u64 member_index = 0; member_index < enum_decl.members.len; member_index += 1) {
            if(enum_decl.members[member_index].decl != null) { continue; }
            Decl* member_decl = new_decl(s, DeclKind::EnumMember, enum_decl.members[member_index].name, tk);
            member_decl.data.member = &enum_decl.members[member_index];
            enum_decl.members[member_index].decl = (void*)member_decl;
        }
    }
}

fn bool register_builtin_type(Sema* s, Scope* module_scope, u8[] name, types::Ty* ty, ast::AstNode* node) {
    symbol::Symbol* sym = interner::intern(name);
    if(scope_lookup_local(module_scope, sym) != null) { return false; }
    Decl* decl = new_decl(s, DeclKind::Node, sym, ty);
    decl.data.node = node;
    _scope_insert(module_scope, sym, decl);
    return true;
}

mutex::Mutex g_reflect_lock;
bool         g_reflect_lock_ready;
types::Ty*   g_reflect_fieldinfo;
types::Ty*   g_reflect_typeinfo;
types::Ty*   g_reflect_typekind;
void*        g_reflect_typekind_decl;   // ast::EnumDeclNode*, for TypeKind::<member> lookups
u64          g_reflect_generation;      // typer generation the cache was built against

// Cached types belong to one typer generation; a re-init (tests) invalidates them along with the interner.
fn void reflect_lock() {
    if(!g_reflect_lock_ready) {
        mutex::create(&g_reflect_lock);
        g_reflect_lock_ready = true;
    }
    mutex::lock(&g_reflect_lock);
    if(g_reflect_generation != types::generation()) {
        g_reflect_generation = types::generation();
        g_reflect_fieldinfo = null;
        g_reflect_typeinfo = null;
        g_reflect_typekind = null;
        g_reflect_typekind_decl = null;
    }
}

// The reflection types are process-global so a TypeInfo built in one module is the same Ty* in another.
export fn types::Ty* reflection_fieldinfo_type(module::Module* m) {
    reflect_lock();
    if(g_reflect_fieldinfo == null) {
        arena::Arena* a = types::global_arena();
        ast::StructDeclNode* sd = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
        sys::memset(sd, 0, sizeof(ast::StructDeclNode));
        sd.h.kind = ast::AstKind::StructDecl;
        sd.name = interner::intern("FieldInfo");
        sd.qualified_name = sd.name;
        ast::FieldDecl* flds = (ast::FieldDecl*)arena::alloc(a, 3 * sizeof(ast::FieldDecl));
        reflect_set_field(&flds[0], "name", types::intern_slice(types::prim_u8()));
        reflect_set_field(&flds[1], "ty", types::prim_type());
        reflect_set_field(&flds[2], "offset", types::prim_u64());
        sd.fields = {flds, 3};
        g_reflect_fieldinfo = types::intern_struct((void*)sd);
    }
    types::Ty* result = g_reflect_fieldinfo;
    mutex::unlock(&g_reflect_lock);
    return result;
}

export fn types::Ty* reflection_typeinfo_type(module::Module* m) {
    types::Ty* fi = reflection_fieldinfo_type(m);
    reflect_lock();
    if(g_reflect_typeinfo == null) {
        arena::Arena* a = types::global_arena();
        ast::StructDeclNode* sd = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
        sys::memset(sd, 0, sizeof(ast::StructDeclNode));
        sd.h.kind = ast::AstKind::StructDecl;
        sd.name = interner::intern("TypeInfo");
        sd.qualified_name = sd.name;
        ast::FieldDecl* flds = (ast::FieldDecl*)arena::alloc(a, 8 * sizeof(ast::FieldDecl));
        reflect_set_field(&flds[0], "kind", reflection_typekind_type_locked());
        reflect_set_field(&flds[1], "name", types::intern_slice(types::prim_u8()));
        reflect_set_field(&flds[2], "size", types::prim_u64());
        reflect_set_field(&flds[3], "align", types::prim_u64());
        reflect_set_field(&flds[4], "fields", types::intern_slice(fi));
        reflect_set_field(&flds[5], "pointee", types::prim_type());
        reflect_set_field(&flds[6], "elem", types::prim_type());
        reflect_set_field(&flds[7], "array_count", types::prim_u64());
        sd.fields = {flds, 8};
        g_reflect_typeinfo = types::intern_struct((void*)sd);
    }
    types::Ty* result = g_reflect_typeinfo;
    mutex::unlock(&g_reflect_lock);
    return result;
}

export fn types::Ty* reflection_typekind_type(module::Module* m) {
    reflect_lock();
    types::Ty* result = reflection_typekind_type_locked();
    mutex::unlock(&g_reflect_lock);
    return result;
}

// Members mirror types::TypeKind's order, so TypeInfo.kind is that ordinal with no mapping table.
fn types::Ty* reflection_typekind_type_locked() {
    if(g_reflect_typekind != null) { return g_reflect_typekind; }
    arena::Arena* a = types::global_arena();
    ast::EnumDeclNode* ed = (ast::EnumDeclNode*)arena::alloc(a, sizeof(ast::EnumDeclNode));
    sys::memset(ed, 0, sizeof(ast::EnumDeclNode));
    ed.h.kind = ast::AstKind::EnumDecl;
    ed.name = interner::intern("TypeKind");
    ed.qualified_name = ed.name;
    u8[][8] names;
    names[0] = "Primitive";
    names[1] = "Pointer";
    names[2] = "Array";
    names[3] = "Slice";
    names[4] = "FnPtr";
    names[5] = "Struct";
    names[6] = "Union";
    names[7] = "Enum";
    ast::EnumMember* members = (ast::EnumMember*)arena::alloc(a, 8 * sizeof(ast::EnumMember));
    sys::memset(members, 0, 8 * sizeof(ast::EnumMember));
    for(u64 member_index = 0; member_index < 8; member_index += 1) {
        members[member_index].name = interner::intern(names[member_index]);
    }
    ed.members = {members, 8};
    g_reflect_typekind = types::intern_enum((void*)ed);
    g_reflect_typekind_decl = (void*)ed;
    return g_reflect_typekind;
}

// A comprun body, a module-scope initializer (always constant-folded), or a `fn Type ...` body.
fn bool in_comptime_context(Sema* s) {
    if(s.in_comprun) { return true; }
    if(s.current_fn == null) { return true; }
    ast::FnDeclNode* func = (ast::FnDeclNode*)s.current_fn;
    if(func.return_type == null) { return false; }
    types::Ty* ret = (types::Ty*)func.return_type.h.ty;
    return ret != null && ret.kind == types::TypeKind::ComptimeType;
}

// TypeInfo carries a Type field, which has no runtime representation; without this the leak surfaces as an internal codegen error.
fn types::Ty* synth_type_info(Sema* s, ast::TypeInfoNode* n) {
    if(!in_comptime_context(s)) {
        u8[] msg = "type_info is only available at comptime";
        sema_report(s, n.h.src_pos, msg);
        mark_error((ast::AstNode*)n);
        return null;
    }
    types::Ty* arg = resolve_type(s, n.arg);
    if(arg == null) { mark_error((ast::AstNode*)n); return null; }
    n.arg.h.ty = (void*)arg;
    types::Ty* ti = reflection_typeinfo_type(s.m);
    set_expr((ast::AstNode*)n, ti, (u16)ast::AstFlags::ConstExpr);
    return ti;
}

fn types::Ty* synth_compcode(Sema* s, ast::CompCodeNode* n) {
    u8[] msg = "compcode is not yet supported";
    sema_report(s, n.h.src_pos, msg);
    mark_error((ast::AstNode*)n);
    return null;
}


// ----------------------------------------------------------------------------
// Per-AstKind check helpers (only kinds that need explicit context)
// ----------------------------------------------------------------------------

// An int literal fits any int type whose range holds it.
export fn bool check_int_lit(Sema* s, ast::IntLitNode* n, types::Ty* expected) {
    return check_int_lit_signed(s, n, expected, false);
}

fn types::Ty* int_lit_natural_type(u64 value, bool negative) {
    types::Ty* t = types::prim_i32();
    if(!types::int_lit_fits(value, negative, t)) { t = types::prim_i64(); }
    if(!negative && !types::int_lit_fits(value, false, t)) { t = types::prim_u64(); }
    return t;
}

fn bool check_int_lit_signed(Sema* s, ast::IntLitNode* n, types::Ty* expected, bool negative) {
    if(types::is_int(expected)) {
        if(types::int_lit_fits(n.value, negative, expected)) {
            set_expr((ast::AstNode*)n, expected, (u16)ast::AstFlags::ConstExpr);
            return true;
        }
        diag_lit_overflow(s, n.h.src_pos, n.value, expected);
        mark_error((ast::AstNode*)n);
        return false;
    }
    diag_type_mismatch(s, n.h.src_pos, int_lit_natural_type(n.value, negative), expected);
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

fn bool check_struct_lit(Sema* s, ast::StructLitNode* n, types::Ty* expected) {
    if(expected.kind == types::TypeKind::Slice) { return check_slice_lit(s, n, expected); }
    if(expected.kind != types::TypeKind::Struct && expected.kind != types::TypeKind::Union) {
        diag_lit_wrong_target(s, n.h.src_pos, "struct", expected);
        mark_error((ast::AstNode*)n);
        return false;
    }
    ast::FieldDecl[] fields = decl_fields(container_decl(expected));
    bool* seen = (bool*)arena::alloc(balloc(s), fields.len + 1);
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
        if(!check(s, fi.value, (types::Ty*)fields[field_idx].resolved_type)) { ok = false; }
    }
    set_expr((ast::AstNode*)n, expected, 0);
    if(!ok) { mark_error((ast::AstNode*)n); }
    return ok;
}

fn bool check_array_lit(Sema* s, ast::ArrayLitNode* n, types::Ty* expected) {
    types::Ty* elem = null;
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

fn bool is_byte(types::Ty* t) {
    if(t == null || t.kind != types::TypeKind::Primitive) { return false; }
    return t.prim == types::PrimitiveKind::U8 || t.prim == types::PrimitiveKind::I8;
}

// A string literal targets a `u8`/`i8` pointer, slice, or array.
fn bool check_string_lit(Sema* s, ast::StringLitNode* n, types::Ty* expected) {
    types::Ty* elem = string_lit_elem(expected);
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
fn bool check_slice_lit(Sema* s, ast::StructLitNode* n, types::Ty* expected) {
    types::Ty* ptr_ty = types::intern_pointer(expected.data.slice_elem, false);
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
// Statement checking
// ============================================================================

// Owns no scope, so the fn body reuses the param scope (a top-level local can't shadow a parameter).
fn void check_block_stmts(Sema* s, ast::BlockNode* block) {
    for(u64 i = 0; i < block.stmts.len; i += 1) {
        ast::AstNode* inner = block.stmts[i];
        if(inner.h.kind == ast::AstKind::CompinsertStmt && !s.in_comprun && run_compinsert_stmts_hook != null) {
            ast::AstNode*[] generated = run_compinsert_stmts_hook(s.m, (ast::CompInsertNode*)inner);
            block_splice(s.m, block, i, generated);
            i -= 1;                     // re-walk from the first spliced stmt (or the next stmt if none)
        } else {
            stmt(s, inner);
        }
    }
}

// Folds a constant case label and flags it if a prior label shared the value; non-constant labels are skipped.
fn void check_duplicate_case(Sema* s, ast::AstNode* label, i64* seen, u64* seen_count) {
    if(eval_const_i64_hook == null || !expr_has_flag(label, ast::AstFlags::ConstExpr)) { return; }
    i64 value = 0;
    if(!eval_const_i64_hook(s.m, label, &value)) { return; }
    for(u64 i = 0; i < *seen_count; i += 1) {
        if(seen[i] == value) { diag_duplicate_case(s, label.h.src_pos); return; }
    }
    seen[*seen_count] = value;
    *seen_count += 1;
}

fn void stmt(Sema* s, ast::AstNode* st) {
    if(st == null) { return; }
    switch(st.h.kind) {
    case ast::AstKind::BlockStmt: {
        ast::BlockNode* block = (ast::BlockNode*)st;
        Scope* block_scope = scope_new(balloc(s), s.scope, 8);
        Scope* saved = s.scope;
        s.scope = block_scope;
        check_block_stmts(s, block);
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
        Scope* for_scope = scope_new(balloc(s), s.scope, 8);
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
        types::Ty* disc = synth(s, switch_node.discriminant);
        if(disc != null && !types::is_int(disc) && disc.kind != types::TypeKind::Enum) {
            diag_switch_discriminant(s, switch_node.discriminant.h.src_pos, disc);
        }
        s.switch_depth += 1;
        u64 label_total = 0;
        for(u64 arm_index = 0; arm_index < switch_node.arms.len; arm_index += 1) { label_total += switch_node.arms[arm_index].labels.len; }
        i64* seen = null;
        u64 seen_count = 0;
        if(label_total > 0) { seen = (i64*)arena::alloc(balloc(s), label_total * sizeof(i64)); }
        for(u64 arm_index = 0; arm_index < switch_node.arms.len; arm_index += 1) {
            ast::SwitchArm* arm = &switch_node.arms[arm_index];
            for(u64 label_index = 0; label_index < arm.labels.len; label_index += 1) {
                ast::AstNode* label = arm.labels[label_index];
                if(disc != null) { check(s, label, disc); }
                else { synth(s, label); }
                check_duplicate_case(s, label, seen, &seen_count);
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
    case ast::AstKind::ComprunStmt: {
        ast::CompRunNode* comprun_node = (ast::CompRunNode*)st;
        bool saved_in_comprun = s.in_comprun;
        s.in_comprun = true;
        stmt(s, comprun_node.body);                  // resolve local decls / idents so eval can read them
        s.in_comprun = saved_in_comprun;
        if(run_comprun_hook != null) { run_comprun_hook(s.m, comprun_node); }
    }
    case ast::AstKind::ComperrorStmt: {
        synth(s, ((ast::CompErrorNode*)st).msg_expr);
    }
    case ast::AstKind::CompwarningStmt: {
        synth(s, ((ast::CompWarningNode*)st).msg_expr);
    }
    case ast::AstKind::CompinsertStmt: {
        synth(s, ((ast::CompInsertNode*)st).source_expr);   // in a comprun_node; resolve the arg so eval_compinsert can read it
    }
    case ast::AstKind::CompspliceStmt: {
        u8[] msg = "compsplice is not yet supported";
        sema_report(s, st.h.src_pos, msg);
        mark_error(st);
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
    types::Ty* declared = resolve_type(s, var.type_expr);
    if(var.init != null) {
        if(declared != null) { check(s, var.init, declared); }
        else { synth(s, var.init); }
    }
    Decl* decl = register_sym(s, s.scope, var.name, false, DeclKind::Node, var.h.src_pos);
    if(decl != null) {
        decl.ty = declared;
        decl.data.node = (ast::AstNode*)var;
        var.decl = (void*)decl;
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
    types::Ty* lt = synth(s, assign.lhs);
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
    types::Ty* rt = synth(s, assign.rhs);
    if(rt == null) { return; }
    adapt_binop_operands(assign.lhs, &lt, assign.rhs, &rt);
    types::Ty* result = op::binop_result_type(compound_binop(assign.op), lt, rt);
    if(result == null) {
        diag_binop_mismatch(s, assign.h.src_pos, assign.op, lt, rt);
        return;
    }
    if(!types::is_convertible(result, lt)) {
        diag_type_mismatch(s, assign.rhs.h.src_pos, result, lt);
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
    types::Ty* t = synth(s, e);
    if(t == null) { return false; }
    if(types::is_convertible_in_cond(t)) { return true; }
    diag_not_bool_convertible(s, e.h.src_pos, t);
    mark_error(e);
    return false;
}


// ============================================================================
// Diagnostic helpers
// ============================================================================

// Report a snprintf result (a stack buffer + its return code) as an error.
fn void emit_diag(Sema* s, u32 src_pos, u8* buf, i32 written) {
    if(written <= 0) { return; }
    u64 len = (u64)written;
    if(len > 255) { len = 255; }
    u8[] msg = {buf, len};
    sema_report(s, src_pos, msg);
}

// "expected `<expected>`, found `<got>`" — the canonical conversion-failure diagnostic.
export fn void diag_type_mismatch(Sema* s, u32 src_pos, types::Ty* got, types::Ty* expected) {
    u8[] expected_str = types_print::print_to_arena(expected, balloc(s));
    u8[] got_str = types_print::print_to_arena(got, balloc(s));
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "expected %.*s, found %.*s", (i32)expected_str.len, (i8*)expected_str.ptr, (i32)got_str.len, (i8*)got_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "literal `<value>` does not fit in `<expected>`". Used by check_int_lit.
export fn void diag_lit_overflow(Sema* s, u32 src_pos, u64 value, types::Ty* expected) {
    u8[] expected_str = types_print::print_to_arena(expected, balloc(s));
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "literal %lu does not fit in %.*s", value, (i32)expected_str.len, (i8*)expected_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// Emitted when synth is called on a StructLit or ArrayLit with no expected type.
export fn void diag_needs_context(Sema* s, ast::AstNode* e) {
    u8[] msg = "literal requires an expected type";
    sema_report(s, e.h.src_pos, msg);
}

// "cannot use `<type>` in condition; expected bool, integer, pointer, or slice".
export fn void diag_not_bool_convertible(Sema* s, u32 src_pos, types::Ty* got) {
    u8[] got_str = types_print::print_to_arena(got, balloc(s));
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "cannot use %.*s in condition; expected bool, integer, pointer, or slice", (i32)got_str.len, (i8*)got_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "operator is not defined for `<lhs>` and `<rhs>`".
export fn void diag_binop_mismatch(Sema* s, u32 src_pos, token::TokenKind op, types::Ty* lt, types::Ty* rt) {
    u8[] lt_str = types_print::print_to_arena(lt, balloc(s));
    u8[] rt_str = types_print::print_to_arena(rt, balloc(s));
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "operator is not defined for %.*s and %.*s", (i32)lt_str.len, (i8*)lt_str.ptr, (i32)rt_str.len, (i8*)rt_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "operator `<op>` is not defined for `<type>`". Used by synth_unary.
export fn void diag_unary_mismatch(Sema* s, u32 src_pos, token::TokenKind op, types::Ty* operand) {
    u8[] op_str = token::kind_name(op);
    u8[] operand_str = types_print::print_to_arena(operand, balloc(s));
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "operator %.*s is not defined for %.*s", (i32)op_str.len, (i8*)op_str.ptr, (i32)operand_str.len, (i8*)operand_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "cannot take the address of a non-lvalue". Used by synth_unary for `&x`.
export fn void diag_not_lvalue(Sema* s, u32 src_pos) {
    u8[] msg = "cannot take the address of a non-lvalue";
    sema_report(s, src_pos, msg);
}

// "type `<T>` has no field `<name>`". Used by synth_member_access.
export fn void diag_unknown_field(Sema* s, u32 src_pos, symbol::Symbol* field, types::Ty* container) {
    u8[] container_str = types_print::print_to_arena(container, balloc(s));
    u8[] field_str = interner::symbol_str(field);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "type %.*s has no field %.*s", (i32)container_str.len, (i8*)container_str.ptr, (i32)field_str.len, (i8*)field_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "cannot access field of %T". Used by synth_member_access on a non-aggregate.
export fn void diag_not_aggregate(Sema* s, u32 src_pos, types::Ty* got) {
    u8[] got_str = types_print::print_to_arena(got, balloc(s));
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "cannot access field of %.*s", (i32)got_str.len, (i8*)got_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "cannot index %T". Used by synth_array_index / synth_slice_range.
export fn void diag_not_indexable(Sema* s, u32 src_pos, types::Ty* got) {
    u8[] got_str = types_print::print_to_arena(got, balloc(s));
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "cannot index %.*s", (i32)got_str.len, (i8*)got_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "slicing a pointer requires an upper bound". Used by synth_slice_range.
export fn void diag_ptr_slice_needs_hi(Sema* s, u32 src_pos) {
    u8[] msg = "slicing a pointer requires an upper bound";
    sema_report(s, src_pos, msg);
}

// "index must be an integer type, found %T". Used by check_index.
export fn void diag_index_not_int(Sema* s, u32 src_pos, types::Ty* got) {
    u8[] got_str = types_print::print_to_arena(got, balloc(s));
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "index must be an integer type, found %.*s", (i32)got_str.len, (i8*)got_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "array size must be a compile-time constant". Used by eval_const_u64.
export fn void diag_array_size_not_const(Sema* s, u32 src_pos) {
    u8[] msg = "array size must be a compile-time constant";
    sema_report(s, src_pos, msg);
}

export fn void diag_array_size_not_int(Sema* s, u32 src_pos) {
    u8[] msg = "array size must be a compile-time integer";
    sema_report(s, src_pos, msg);
}

export fn void diag_array_size_negative(Sema* s, u32 src_pos) {
    u8[] msg = "array size cannot be negative";
    sema_report(s, src_pos, msg);
}

// "cannot call value of type %T". Used by synth_call on a non-function callee.
export fn void diag_not_callable(Sema* s, u32 src_pos, types::Ty* got) {
    u8[] got_str = types_print::print_to_arena(got, balloc(s));
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "cannot call value of type %.*s", (i32)got_str.len, (i8*)got_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "call expects N arguments but got M". Used by synth_call on arity mismatch.
export fn void diag_no_overload(Sema* s, u32 src_pos, symbol::Symbol* name) {
    if(name == null) { return; }
    u8[] name_str = interner::symbol_str(name);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "no matching overload for %.*s", (i32)name_str.len, (i8*)name_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

export fn void diag_ambiguous_overload(Sema* s, u32 src_pos, symbol::Symbol* name) {
    if(name == null) { return; }
    u8[] name_str = interner::symbol_str(name);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "ambiguous call to %.*s", (i32)name_str.len, (i8*)name_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

export fn void diag_overload_duplicate(Sema* s, u32 src_pos, symbol::Symbol* name) {
    if(name == null) { return; }
    u8[] name_str = interner::symbol_str(name);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "duplicate definition of %.*s with the same parameter types", (i32)name_str.len, (i8*)name_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

export fn void diag_overload_return_mismatch(Sema* s, u32 src_pos, symbol::Symbol* name) {
    if(name == null) { return; }
    u8[] name_str = interner::symbol_str(name);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "overloads of %.*s must have the same return type", (i32)name_str.len, (i8*)name_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

export fn void diag_infer_failure(Sema* s, u32 src_pos, symbol::Symbol* name) {
    if(name == null) { return; }
    u8[] name_str = interner::symbol_str(name);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "cannot infer comptime arguments for %.*s", (i32)name_str.len, (i8*)name_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

export fn void diag_arity(Sema* s, u32 src_pos, u64 expected, u64 got) {
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "call expects %lu arguments but got %lu", expected, got);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "left of '::' is not a module or enum". Used by synth_ns_access.
export fn void diag_not_namespace(Sema* s, u32 src_pos) {
    u8[] msg = "left of '::' is not a module or enum";
    sema_report(s, src_pos, msg);
}

// "no member named `<name>`". Used by synth_ns_access.
export fn void diag_unknown_member(Sema* s, u32 src_pos, symbol::Symbol* name) {
    u8[] name_str = interner::symbol_str(name);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "no member named %.*s", (i32)name_str.len, (i8*)name_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "cannot use `<kind>` literal as `<T>`". Used by the literal-check helpers.
export fn void diag_lit_wrong_target(Sema* s, u32 src_pos, u8[] kind, types::Ty* expected) {
    u8[] expected_str = types_print::print_to_arena(expected, balloc(s));
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
    sema_report(s, src_pos, msg);
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
    sema_report(s, src_pos, msg);
}

// "cannot assign to a constant". Used by stmt_assignment.
export fn void diag_assign_to_const(Sema* s, u32 src_pos) {
    u8[] msg = "cannot assign to a constant";
    sema_report(s, src_pos, msg);
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
    sema_report(s, src_pos, msg);
}

// "switch value must be an integer or enum, found %T". Used by the switch statement.
export fn void diag_switch_discriminant(Sema* s, u32 src_pos, types::Ty* got) {
    u8[] got_str = types_print::print_to_arena(got, balloc(s));
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "switch value must be an integer or enum, found %.*s", (i32)got_str.len, (i8*)got_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

export fn void diag_duplicate_case(Sema* s, u32 src_pos) {
    u8[] msg = "duplicate case label";
    sema_report(s, src_pos, msg);
}

// "continue outside loop". Used by stmt.
export fn void diag_continue_outside(Sema* s, u32 src_pos) {
    u8[] msg = "continue outside loop";
    sema_report(s, src_pos, msg);
}

// "cannot return a value from a void function". Used by stmt_return.
export fn void diag_return_value_in_void(Sema* s, u32 src_pos) {
    u8[] msg = "cannot return a value from a void function";
    sema_report(s, src_pos, msg);
}

// "missing return value; function returns `<T>`". Used by stmt_return.
export fn void diag_return_missing_value(Sema* s, u32 src_pos, types::Ty* expected) {
    u8[] expected_str = types_print::print_to_arena(expected, balloc(s));
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "missing return value; function returns %.*s", (i32)expected_str.len, (i8*)expected_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "cannot cast `<src>` to `<target>`". Used by synth_cast on is_castable fail.
export fn void diag_cast_invalid(Sema* s, u32 src_pos, types::Ty* src, types::Ty* target) {
    u8[] src_str = types_print::print_to_arena(src, balloc(s));
    u8[] target_str = types_print::print_to_arena(target, balloc(s));
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
    if(name == null) { return; }
    u8[] name_str = interner::symbol_str(name);
    u8[256] scratch;
    i32 written = sys::snprintf((i8*)&scratch[0], 256, "unknown type %.*s", (i32)name_str.len, (i8*)name_str.ptr);
    emit_diag(s, src_pos, &scratch[0], written);
}

// "undefined identifier `<name>`". Used by synth_ident on a scope miss.
export fn void diag_undefined_ident(Sema* s, u32 src_pos, symbol::Symbol* name) {
    if(name == null) { return; }
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
    if(d.kind == DeclKind::Field || d.kind == DeclKind::Param) { return true; }
    return d.kind == DeclKind::Node && d.data.node != null && d.data.node.h.kind == ast::AstKind::VarDecl;
}

// const vars, enum members, and fns are compile-time-known.
export fn bool decl_is_const_expr(Decl* d) {
    if(d == null) { return false; }
    if(d.kind == DeclKind::EnumMember) { return true; }
    if(d.kind != DeclKind::Node || d.data.node == null) { return false; }
    ast::AstNode* node = d.data.node;
    if(node.h.kind == ast::AstKind::FnDecl) { return true; }
    return node.h.kind == ast::AstKind::VarDecl && ((ast::VarDeclNode*)node).is_const;
}

// Recover the decl node the typer keyed a struct/union/enum Type by.
export fn ast::AstNode* container_decl(types::Ty* t) {
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

export fn Decl* new_decl(Sema* s, DeclKind kind, symbol::Symbol* name, types::Ty* ty) {
    Decl* decl = (Decl*)arena::alloc(balloc(s), sizeof(Decl));
    sys::memset(decl, 0, sizeof(Decl));
    decl.kind = kind;
    decl.name = name;
    decl.ty = ty;
    decl.home = s.m;
    return decl;
}
