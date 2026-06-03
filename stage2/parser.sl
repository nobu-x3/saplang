import module;
import ast;
import token;
import diag;
import arena;
import symbol;
import interner;
import sys;

export struct Parser {
    module::Module* m;
    u32 idx;
    bool in_extern;
    bool is_speculating;
}

export fn ast::AstNode* parse(module::Module* m) {
    Parser p = { m, 0, false, false };
    ast::ListBuilder decls;
    ast::list_init(&decls, m.arena, 32);
    while (peek(&p, 0).kind != token::TokenKind::EOF) {
        ast::AstNode* d = parse_top_decl(&p);
        if (d != null) { ast::list_push(&decls, m.arena, d); }
    }
    ast::BlockNode* root = arena::alloc(m.arena, sizeof(ast::BlockNode));
    root.h.kind = ast::AstKind::BlockStmt;
    root.h.flags = (ast::AstFlags)0;
    root.h.src_pos = 0;
    root.stmts = ast::list_freeze(&decls);
    return (ast::AstNode*)root;
}

// private stuff
// PARSING //////////////////////////////////////////////////////////////////////////////
fn ast::AstNode* parse_top_decl(Parser* p) {
    token::Token t = peek(p, 0);
    bool is_exported = false;
    if (t.kind == token::TokenKind::EXPORT) {
        consume(p);
        is_exported = true;
        t = peek(p, 0);
    }
    switch (t.kind) {
        case token::TokenKind::IMPORT:  { return parse_import(p); }              // export is illegal here
        case token::TokenKind::CONST:   { return parse_var_decl(p, is_exported); }
        case token::TokenKind::EXTERN:  { return parse_extern_block(p); }
        case token::TokenKind::COMPRUN: { return parse_comprun(p); }
        case token::TokenKind::FN: {
            if(peek(p, 1).kind == token::TokenKind::Star) { return parse_var_decl(p, is_exported); }
            return parse_fn_decl(p, is_exported);
        }
        case token::TokenKind::STRUCT:  { return parse_struct_decl(p, is_exported); }
        case token::TokenKind::UNION:   { return parse_union_decl(p, is_exported); }
        case token::TokenKind::ENUM:    { return parse_enum_decl(p, is_exported); }
        case token::TokenKind::ALIAS:   { return parse_alias_decl(p, is_exported); }
    else {
        if(looks_like_type_start(t.kind)) {
            return parse_var_decl(p, is_exported);
        }
        report_expected(p, t, token::TokenKind::IMPORT);
        return mk_error_node_and_consume(p, t.src_pos);
    }
    }
    return mk_error_node_and_consume(p, t.src_pos);
}

fn bool looks_like_type_start(token::TokenKind k) {
    if(token::is_type_keyword(k)) { return true; }
    if(k == token::TokenKind::Ident) { return true; }
    if(k == token::TokenKind::FN) { return true; }
    if(k == token::TokenKind::STRUCT) { return true; }
    if(k == token::TokenKind::UNION) { return true; }
    if(k == token::TokenKind::Dot) { return true; }
    return false;
}

fn ast::AstNode* parse_import(Parser* p) {
    token::Token import_tok = expect(p, token::TokenKind::IMPORT);
    if(import_tok.kind == token::TokenKind::ERROR) {
        return mk_error_node_and_consume(p, import_tok.src_pos);
    }
    token::Token module_name = expect(p, token::TokenKind::Ident);
    if(module_name.kind == token::TokenKind::ERROR) {
        return mk_error_node_and_consume(p, module_name.src_pos);
    }
    token::Token semi_colon = expect(p, token::TokenKind::Semi);
    if(semi_colon.kind == token::TokenKind::ERROR) {
        return mk_error_node_and_consume(p, semi_colon.src_pos);
    }
    ast::ImportNode* import_node = arena::alloc(p.m.arena, sizeof(ast::ImportNode));
    import_node.h.kind = ast::AstKind::ImportDecl;
    import_node.h.flags = (ast::AstFlags)0;
    import_node.h.src_pos = import_tok.src_pos;
    import_node.module_name = module_name.data.sym;
    return (ast::AstNode*)import_node;
}

fn ast::AstNode* parse_var_decl(Parser* p, bool is_exported) {
    u32 start = peek(p, 0).src_pos;
    bool is_const = peek(p, 0).kind == token::TokenKind::CONST;
    if(is_const) { consume(p); }
    ast::AstNode* type_expr = parse_type(p);
    bool had_err = !type_expr || had_error(type_expr);
    token::Token ident = expect(p, token::TokenKind::Ident);
    if(ident.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::AstNode* init_expr = null;
    if(peek(p, 0).kind == token::TokenKind::Eq) {
        consume(p);
        init_expr = parse_expr(p, 0);
        if(!init_expr || had_error(init_expr)) { had_err = true; }
    }
    token::Token semi = expect(p, token::TokenKind::Semi);
    if(semi.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::VarDeclNode* var_decl_node = arena::alloc(p.m.arena, sizeof(ast::VarDeclNode));
    sys::memset(var_decl_node, 0, sizeof(ast::VarDeclNode));
    var_decl_node.h.kind = ast::AstKind::VarDecl;
    var_decl_node.h.flags = (ast::AstFlags)0;
    if(had_err) { var_decl_node.h.flags = ast::AstFlags::HadError; }
    var_decl_node.h.src_pos = start;
    var_decl_node.name = ident.data.sym;
    var_decl_node.type_expr = type_expr;
    var_decl_node.init = init_expr;
    var_decl_node.is_const = is_const;
    var_decl_node.is_exported = is_exported;
    return (ast::AstNode*)var_decl_node;
}

fn ast::AstNode* parse_fn_decl(Parser* p, bool is_exported) {
    u32 start = peek(p, 0).src_pos;
    token::Token fn_tok = expect(p, token::TokenKind::FN);
    if(fn_tok.kind == token::TokenKind::ERROR) {
        return mk_error_node_and_consume(p, fn_tok.src_pos);
    }
    bool is_const = peek(p, 0).kind == token::TokenKind::CONST;
    if(is_const) { consume(p); }
    ast::AstNode* type_expr = parse_type(p);
    bool had_err = !type_expr || had_error(type_expr);
    token::Token ident = expect(p, token::TokenKind::Ident);
    if(ident.kind == token::TokenKind::ERROR) { had_err = true; }
    token::Token lparen = expect(p, token::TokenKind::LParen);
    if(lparen.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::Param[] params = parse_params(p, &had_err);
    token::Token rparen = expect(p, token::TokenKind::RParen);
    if(rparen.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::AstNode* body = parse_block(p);
    if(had_error(body)) { had_err = true; }
    ast::FnDeclNode* fn_decl_node = arena::alloc(p.m.arena, sizeof(ast::FnDeclNode));
    sys::memset(fn_decl_node, 0, sizeof(ast::FnDeclNode));
    fn_decl_node.h.kind = ast::AstKind::FnDecl;
    fn_decl_node.h.flags = (ast::AstFlags)0;
    if(had_err) { fn_decl_node.h.flags = ast::AstFlags::HadError; }
    fn_decl_node.h.src_pos = start;
    fn_decl_node.name = ident.data.sym;
    fn_decl_node.return_type = type_expr;
    fn_decl_node.params = params;
    fn_decl_node.body = body;
    fn_decl_node.comptime_safe = 0;
    fn_decl_node.is_exported = is_exported;
    return (ast::AstNode*)fn_decl_node;
}
fn ast::Param[] parse_params(Parser* p, bool* had_err) {
    ast::Param[] arr;
    arr.ptr = null;
    arr.len = 0;
    u64 cap = 0;
    while(peek(p, 0).kind != token::TokenKind::RParen && peek(p, 0).kind != token::TokenKind::EOF) {
        if(p.in_extern && peek(p, 0).kind == token::TokenKind::DotDotDot) { break; }
        u32 start = peek(p, 0).src_pos;
        bool is_const = false;
        bool is_comptime = false;
        if(peek(p, 0).kind == token::TokenKind::CONST) {
            consume(p);
            is_const = true;
        }
        if(peek(p, 0).kind == token::TokenKind::COMPTIME) {
            consume(p);
            is_comptime = true;
        }
        ast::AstNode* type_expr = parse_type(p);
        if(!type_expr || had_error(type_expr)) { *had_err = true; }
        token::Token name = expect(p, token::TokenKind::Ident);
        if(name.kind == token::TokenKind::ERROR) { *had_err = true; }
        if(arr.len + 1 > cap) {
            u64 new_cap = 4;
            if(cap > 0) { new_cap = cap * 2; }
            arr.ptr = arena::realloc_grow(p.m.arena, arr.ptr,
                    cap * sizeof(ast::Param),
                    new_cap * sizeof(ast::Param));
            cap = new_cap;
        }
        ast::Param* prm = &arr[arr.len];
        prm.name = name.data.sym;
        prm.type_expr = type_expr;
        prm.is_const = is_const;
        prm.is_comptime = is_comptime;
        prm.src_pos = start;
        arr.len += 1;
        if(!match(p, token::TokenKind::Comma)) { break; }
    }
    return arr;
}

// STATEMENTS ///////////////////////////////////////////////////////////////////////////
fn ast::AstNode* parse_stmt(Parser* p) {
    token::Token t = peek(p, 0);
    switch(t.kind) {
        case token::TokenKind::LBrace:       { return parse_block(p); }
        case token::TokenKind::IF:           { return parse_if(p); }
        case token::TokenKind::WHILE:        { return parse_while(p); }
        case token::TokenKind::FOR:          { return parse_for(p); }
        case token::TokenKind::SWITCH:       { return parse_switch(p); }
        case token::TokenKind::RETURN:       { return parse_return(p); }
        case token::TokenKind::BREAK:        { return parse_break(p); }
        case token::TokenKind::CONTINUE:     { return parse_continue(p); }
        case token::TokenKind::DEFER:        { return parse_defer(p); }
        case token::TokenKind::COMPRUN:      { return parse_comprun(p); }
        case token::TokenKind::COMPINSERT:   { return parse_compinsert(p); }
        case token::TokenKind::COMPSPLICE:   { return parse_compsplice(p); }
        case token::TokenKind::COMPERROR:    { return parse_comperror(p); }
        case token::TokenKind::COMPWARNING:  { return parse_compwarning(p); }
        case token::TokenKind::CONST:        { return parse_local_var_decl(p); }
    else {
        if(looks_like_type_start(t.kind) && looks_like_var_decl(p)) {
            return parse_local_var_decl(p);
        }
        //return parse_assignment_or_expr_stmt(p);
        report_expected(p, t, token::TokenKind::Semi);
        return mk_error_node_and_consume(p, t.src_pos);
    }
    }
    return mk_error_node_and_consume(p, t.src_pos);
}

fn ast::AstNode* parse_local_var_decl(Parser* p) { return parse_var_decl(p, false); }

fn ast::AstNode* parse_return(Parser* p) {
    u32 start = peek(p, 0).src_pos;
    token::Token ret = expect(p, token::TokenKind::RETURN);
    if(ret.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    ast::AstNode* expr = null;
    if(peek(p, 0).kind != token::TokenKind::Semi) {
        expr = parse_expr(p, 0);
        if(!expr || had_error(expr)) { had_err = true; }
    }
    token::Token semi = expect(p, token::TokenKind::Semi);
    if(semi.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::ReturnNode* n = arena::alloc(p.m.arena, sizeof(ast::ReturnNode));
    n.h.kind = ast::AstKind::ReturnStmt;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.expr = expr;
    return (ast::AstNode*)n;
}

fn ast::AstNode* parse_break(Parser* p) {
    u32 start = peek(p, 0).src_pos;
    token::Token brk = expect(p, token::TokenKind::BREAK);
    if(brk.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    token::Token semi = expect(p, token::TokenKind::Semi);
    if(semi.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::BreakNode* n = arena::alloc(p.m.arena, sizeof(ast::BreakNode));
    n.h.kind = ast::AstKind::BreakStmt;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    return (ast::AstNode*)n;
}

fn ast::AstNode* parse_continue(Parser* p) {
    u32 start = peek(p, 0).src_pos;
    token::Token cont = expect(p, token::TokenKind::CONTINUE);
    if(cont.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    token::Token semi = expect(p, token::TokenKind::Semi);
    if(semi.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::ContinueNode* n = arena::alloc(p.m.arena, sizeof(ast::ContinueNode));
    n.h.kind = ast::AstKind::ContinueStmt;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    return (ast::AstNode*)n;
}

fn ast::AstNode* parse_comprun(Parser* p) {
    u32 start = peek(p, 0).src_pos;
    token::Token kw = expect(p, token::TokenKind::COMPRUN);
    if(kw.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    ast::AstNode* body = parse_block(p);
    if(had_error(body)) { had_err = true; }
    ast::CompRunNode* n = arena::alloc(p.m.arena, sizeof(ast::CompRunNode));
    n.h.kind = ast::AstKind::ComprunStmt;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.body = body;
    return (ast::AstNode*)n;
}

fn ast::FieldDecl[] parse_fields(Parser* p, bool* had_err) {
    ast::FieldDecl[] arr;
    arr.ptr = null;
    arr.len = 0;
    u64 cap = 0;
    while(peek(p, 0).kind != token::TokenKind::RBrace && peek(p, 0).kind != token::TokenKind::EOF) {
        u32 prev_idx = p.idx;
        u32 start = peek(p, 0).src_pos;
        ast::AstNode* type_expr = parse_type(p);
        if(!type_expr || had_error(type_expr)) { *had_err = true; }
        token::Token name = expect(p, token::TokenKind::Ident);
        if(name.kind == token::TokenKind::ERROR) { *had_err = true; }
        token::Token semi = expect(p, token::TokenKind::Semi);
        if(semi.kind == token::TokenKind::ERROR) { *had_err = true; }
        if(arr.len + 1 > cap) {
            u64 new_cap = 4;
            if(cap > 0) { new_cap = cap * 2; }
            arr.ptr = arena::realloc_grow(p.m.arena, arr.ptr,
                    cap * sizeof(ast::FieldDecl),
                    new_cap * sizeof(ast::FieldDecl));
            cap = new_cap;
        }
        ast::FieldDecl* fd = &arr[arr.len];
        fd.name = name.data.sym;
        fd.type_expr = type_expr;
        fd.src_pos = start;
        arr.len += 1;
        if(p.idx == prev_idx) { consume(p); *had_err = true; }
    }
    return arr;
}

fn ast::AstNode* parse_struct_decl(Parser* p, bool is_exported) {
    u32 start = peek(p, 0).src_pos;
    token::Token kw = expect(p, token::TokenKind::STRUCT);
    if(kw.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    token::Token name = expect(p, token::TokenKind::Ident);
    if(name.kind == token::TokenKind::ERROR) { had_err = true; }
    token::Token lbrace = expect(p, token::TokenKind::LBrace);
    if(lbrace.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::FieldDecl[] fields = parse_fields(p, &had_err);
    token::Token rbrace = expect(p, token::TokenKind::RBrace);
    if(rbrace.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::StructDeclNode* n = arena::alloc(p.m.arena, sizeof(ast::StructDeclNode));
    sys::memset(n, 0, sizeof(ast::StructDeclNode));
    n.h.kind = ast::AstKind::StructDecl;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.name = name.data.sym;
    n.fields = fields;
    n.is_exported = is_exported;
    return (ast::AstNode*)n;
}

fn ast::AstNode* parse_union_decl(Parser* p, bool is_exported) {
    u32 start = peek(p, 0).src_pos;
    token::Token kw = expect(p, token::TokenKind::UNION);
    if(kw.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    token::Token name = expect(p, token::TokenKind::Ident);
    if(name.kind == token::TokenKind::ERROR) { had_err = true; }
    token::Token lbrace = expect(p, token::TokenKind::LBrace);
    if(lbrace.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::FieldDecl[] fields = parse_fields(p, &had_err);
    token::Token rbrace = expect(p, token::TokenKind::RBrace);
    if(rbrace.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::UnionDeclNode* n = arena::alloc(p.m.arena, sizeof(ast::UnionDeclNode));
    sys::memset(n, 0, sizeof(ast::UnionDeclNode));
    n.h.kind = ast::AstKind::UnionDecl;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.name = name.data.sym;
    n.fields = fields;
    n.is_exported = is_exported;
    return (ast::AstNode*)n;
}

fn ast::AstNode* parse_extern_fn_decl(Parser* p, bool is_exported, u32 start) {
    token::Token fn_tok = expect(p, token::TokenKind::FN);
    if(fn_tok.kind == token::TokenKind::ERROR) {
        return mk_error_node_and_consume(p, fn_tok.src_pos);
    }
    ast::AstNode* type_expr = parse_type(p);
    bool had_err = !type_expr || had_error(type_expr);
    token::Token ident = expect(p, token::TokenKind::Ident);
    if(ident.kind == token::TokenKind::ERROR) { had_err = true; }
    token::Token lparen = expect(p, token::TokenKind::LParen);
    if(lparen.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::Param[] params = parse_params(p, &had_err);
    bool is_variadic = false;
    if(peek(p, 0).kind == token::TokenKind::DotDotDot) {
        consume(p);
        is_variadic = true;
    }
    token::Token rparen = expect(p, token::TokenKind::RParen);
    if(rparen.kind == token::TokenKind::ERROR) { had_err = true; }
    token::Token semi = expect(p, token::TokenKind::Semi);
    if(semi.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::ExternFnDeclNode* n = arena::alloc(p.m.arena, sizeof(ast::ExternFnDeclNode));
    sys::memset(n, 0, sizeof(ast::ExternFnDeclNode));
    n.h.kind = ast::AstKind::ExternFnDecl;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.name = ident.data.sym;
    n.return_type = type_expr;
    n.params = params;
    n.is_variadic = is_variadic;
    n.is_exported = is_exported;
    n.comptime_safe = (i8)-1;
    return (ast::AstNode*)n;
}

fn ast::AstNode* parse_extern_struct_decl(Parser* p, bool is_exported, u32 start, bool is_opaque, u32 opaque_pos) {
    token::Token kw = expect(p, token::TokenKind::STRUCT);
    if(kw.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    token::Token name = expect(p, token::TokenKind::Ident);
    if(name.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::FieldDecl[] fields;
    fields.ptr = null;
    fields.len = 0;
    token::TokenKind nk = peek(p, 0).kind;
    if(is_opaque) {
        if(nk == token::TokenKind::LBrace) {
            had_err = true;
            u8[128] sb;
            i32 sl = sys::snprintf((i8*)&sb[0], 128, "opaque extern type cannot have a body");
            if(sl > 0 && !p.is_speculating) {
                u64 ml = (u64)sl; if(ml > 127) { ml = 127; }
                u8[] mb = {&sb[0], ml};
                diag::report(&p.m.diag, p.m.arena, peek(p, 0).src_pos, mb);
            }
            consume(p);
            fields = parse_fields(p, &had_err);
            token::Token rb = expect(p, token::TokenKind::RBrace);
            if(rb.kind == token::TokenKind::ERROR) { had_err = true; }
            token::Token sc = expect(p, token::TokenKind::Semi);
            if(sc.kind == token::TokenKind::ERROR) { had_err = true; }
        } else {
            token::Token sc = expect(p, token::TokenKind::Semi);
            if(sc.kind == token::TokenKind::ERROR) { had_err = true; }
        }
    } else {
        if(nk == token::TokenKind::Semi) {
            had_err = true;
            u8[128] sb;
            i32 sl = sys::snprintf((i8*)&sb[0], 128, "extern struct without body must be marked 'opaque'");
            if(sl > 0 && !p.is_speculating) {
                u64 ml = (u64)sl; if(ml > 127) { ml = 127; }
                u8[] mb = {&sb[0], ml};
                diag::report(&p.m.diag, p.m.arena, peek(p, 0).src_pos, mb);
            }
            consume(p);
        } else {
            token::Token lb = expect(p, token::TokenKind::LBrace);
            if(lb.kind == token::TokenKind::ERROR) { had_err = true; }
            fields = parse_fields(p, &had_err);
            token::Token rb = expect(p, token::TokenKind::RBrace);
            if(rb.kind == token::TokenKind::ERROR) { had_err = true; }
            token::Token sc = expect(p, token::TokenKind::Semi);
            if(sc.kind == token::TokenKind::ERROR) { had_err = true; }
        }
    }
    ast::ExternStructDeclNode* n = arena::alloc(p.m.arena, sizeof(ast::ExternStructDeclNode));
    sys::memset(n, 0, sizeof(ast::ExternStructDeclNode));
    n.h.kind = ast::AstKind::ExternStructDecl;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.name = name.data.sym;
    n.fields = fields;
    n.is_opaque = is_opaque;
    n.is_exported = is_exported;
    return (ast::AstNode*)n;
}

fn ast::AstNode* parse_extern_union_decl(Parser* p, bool is_exported, u32 start, bool is_opaque, u32 opaque_pos) {
    token::Token kw = expect(p, token::TokenKind::UNION);
    if(kw.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    token::Token name = expect(p, token::TokenKind::Ident);
    if(name.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::FieldDecl[] fields;
    fields.ptr = null;
    fields.len = 0;
    token::TokenKind nk = peek(p, 0).kind;
    if(is_opaque) {
        if(nk == token::TokenKind::LBrace) {
            had_err = true;
            u8[128] sb;
            i32 sl = sys::snprintf((i8*)&sb[0], 128, "opaque extern type cannot have a body");
            if(sl > 0 && !p.is_speculating) {
                u64 ml = (u64)sl; if(ml > 127) { ml = 127; }
                u8[] mb = {&sb[0], ml};
                diag::report(&p.m.diag, p.m.arena, peek(p, 0).src_pos, mb);
            }
            consume(p);
            fields = parse_fields(p, &had_err);
            token::Token rb = expect(p, token::TokenKind::RBrace);
            if(rb.kind == token::TokenKind::ERROR) { had_err = true; }
            token::Token sc = expect(p, token::TokenKind::Semi);
            if(sc.kind == token::TokenKind::ERROR) { had_err = true; }
        } else {
            token::Token sc = expect(p, token::TokenKind::Semi);
            if(sc.kind == token::TokenKind::ERROR) { had_err = true; }
        }
    } else {
        if(nk == token::TokenKind::Semi) {
            had_err = true;
            u8[128] sb;
            i32 sl = sys::snprintf((i8*)&sb[0], 128, "extern union without body must be marked 'opaque'");
            if(sl > 0 && !p.is_speculating) {
                u64 ml = (u64)sl; if(ml > 127) { ml = 127; }
                u8[] mb = {&sb[0], ml};
                diag::report(&p.m.diag, p.m.arena, peek(p, 0).src_pos, mb);
            }
            consume(p);
        } else {
            token::Token lb = expect(p, token::TokenKind::LBrace);
            if(lb.kind == token::TokenKind::ERROR) { had_err = true; }
            fields = parse_fields(p, &had_err);
            token::Token rb = expect(p, token::TokenKind::RBrace);
            if(rb.kind == token::TokenKind::ERROR) { had_err = true; }
            token::Token sc = expect(p, token::TokenKind::Semi);
            if(sc.kind == token::TokenKind::ERROR) { had_err = true; }
        }
    }
    ast::ExternUnionDeclNode* n = arena::alloc(p.m.arena, sizeof(ast::ExternUnionDeclNode));
    sys::memset(n, 0, sizeof(ast::ExternUnionDeclNode));
    n.h.kind = ast::AstKind::ExternUnionDecl;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.name = name.data.sym;
    n.fields = fields;
    n.is_opaque = is_opaque;
    n.is_exported = is_exported;
    return (ast::AstNode*)n;
}

fn ast::AstNode* parse_extern_item(Parser* p) {
    u32 start = peek(p, 0).src_pos;
    bool is_exported = false;
    if(peek(p, 0).kind == token::TokenKind::EXPORT) {
        consume(p);
        is_exported = true;
    }
    bool is_opaque = false;
    u32 opaque_pos = 0;
    if(peek(p, 0).kind == token::TokenKind::OPAQUE) {
        opaque_pos = peek(p, 0).src_pos;
        consume(p);
        is_opaque = true;
    }
    token::TokenKind k = peek(p, 0).kind;
    if(k == token::TokenKind::FN) {
        if(is_opaque) {
            u8[128] sb;
            i32 sl = sys::snprintf((i8*)&sb[0], 128, "'opaque' is only valid on struct or union");
            if(sl > 0 && !p.is_speculating) {
                u64 ml = (u64)sl; if(ml > 127) { ml = 127; }
                u8[] mb = {&sb[0], ml};
                diag::report(&p.m.diag, p.m.arena, opaque_pos, mb);
            }
        }
        ast::AstNode* fnode = parse_extern_fn_decl(p, is_exported, start);
        if(is_opaque) { fnode.h.flags = ast::AstFlags::HadError; }
        return fnode;
    }
    if(k == token::TokenKind::STRUCT) {
        return parse_extern_struct_decl(p, is_exported, start, is_opaque, opaque_pos);
    }
    if(k == token::TokenKind::UNION) {
        return parse_extern_union_decl(p, is_exported, start, is_opaque, opaque_pos);
    }
    report_expected(p, peek(p, 0), token::TokenKind::FN);
    return mk_error_node_and_consume(p, start);
}

fn ast::AstNode* parse_extern_block(Parser* p) {
    u32 start = peek(p, 0).src_pos;
    token::Token kw = expect(p, token::TokenKind::EXTERN);
    if(kw.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    symbol::Symbol* lib_name = null;
    if(peek(p, 0).kind == token::TokenKind::StringLit) {
        token::Token s = consume(p);
        u8[] bytes;
        bytes.ptr = &p.m.literal_pool.ptr[s.data.bytes.off];
        bytes.len = (u64)s.data.bytes.len;
        lib_name = interner::intern(p.m.interner, bytes);
    }
    token::Token lbrace = expect(p, token::TokenKind::LBrace);
    if(lbrace.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::ListBuilder items;
    ast::list_init(&items, p.m.arena, 4);
    bool saved_in_extern = p.in_extern;
    p.in_extern = true;
    while(peek(p, 0).kind != token::TokenKind::RBrace && peek(p, 0).kind != token::TokenKind::EOF) {
        u32 prev = p.idx;
        ast::AstNode* item = parse_extern_item(p);
        if(item) {
            if(had_error(item)) { had_err = true; }
            ast::list_push(&items, p.m.arena, item);
        }
        if(p.idx == prev) { consume(p); had_err = true; }
    }
    p.in_extern = saved_in_extern;
    token::Token rbrace = expect(p, token::TokenKind::RBrace);
    if(rbrace.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::ExternBlockNode* n = arena::alloc(p.m.arena, sizeof(ast::ExternBlockNode));
    sys::memset(n, 0, sizeof(ast::ExternBlockNode));
    n.h.kind = ast::AstKind::ExternBlock;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.lib_name = lib_name;
    n.items = ast::list_freeze(&items);
    return (ast::AstNode*)n;
}

fn ast::AstNode* parse_alias_decl(Parser* p, bool is_exported) {
    u32 start = peek(p, 0).src_pos;
    token::Token kw = expect(p, token::TokenKind::ALIAS);
    if(kw.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    token::Token name = expect(p, token::TokenKind::Ident);
    if(name.kind == token::TokenKind::ERROR) { had_err = true; }
    token::Token eq = expect(p, token::TokenKind::Eq);
    if(eq.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::AstNode* target = parse_type(p);
    if(!target || had_error(target)) { had_err = true; }
    token::Token semi = expect(p, token::TokenKind::Semi);
    if(semi.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::AliasDeclNode* n = arena::alloc(p.m.arena, sizeof(ast::AliasDeclNode));
    sys::memset(n, 0, sizeof(ast::AliasDeclNode));
    n.h.kind = ast::AstKind::AliasDecl;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.name = name.data.sym;
    n.target = target;
    n.is_exported = is_exported;
    return (ast::AstNode*)n;
}

fn ast::EnumMember[] parse_enum_members(Parser* p, bool* had_err) {
    ast::EnumMember[] arr;
    arr.ptr = null;
    arr.len = 0;
    u64 cap = 0;
    while(peek(p, 0).kind != token::TokenKind::RBrace && peek(p, 0).kind != token::TokenKind::EOF) {
        u32 prev = p.idx;
        u32 start = peek(p, 0).src_pos;
        token::Token name = expect(p, token::TokenKind::Ident);
        if(name.kind == token::TokenKind::ERROR) { *had_err = true; }
        ast::AstNode* value_expr = null;
        if(peek(p, 0).kind == token::TokenKind::Eq) {
            consume(p);
            value_expr = parse_expr(p, 0);
            if(!value_expr || had_error(value_expr)) { *had_err = true; }
        }
        if(arr.len + 1 > cap) {
            u64 new_cap = 4;
            if(cap > 0) { new_cap = cap * 2; }
            arr.ptr = arena::realloc_grow(p.m.arena, arr.ptr,
                    cap * sizeof(ast::EnumMember),
                    new_cap * sizeof(ast::EnumMember));
            cap = new_cap;
        }
        ast::EnumMember* em = &arr[arr.len];
        em.name = name.data.sym;
        em.value_expr = value_expr;
        em.src_pos = start;
        arr.len += 1;
        if(!match(p, token::TokenKind::Comma)) { break; }
        if(p.idx == prev) { consume(p); *had_err = true; }
    }
    return arr;
}

fn ast::AstNode* parse_enum_decl(Parser* p, bool is_exported) {
    u32 start = peek(p, 0).src_pos;
    token::Token kw = expect(p, token::TokenKind::ENUM);
    if(kw.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    token::Token name = expect(p, token::TokenKind::Ident);
    if(name.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::AstNode* base_type = null;
    if(peek(p, 0).kind == token::TokenKind::Colon) {
        consume(p);
        base_type = parse_type(p);
        if(!base_type || had_error(base_type)) { had_err = true; }
    }
    token::Token lbrace = expect(p, token::TokenKind::LBrace);
    if(lbrace.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::EnumMember[] members = parse_enum_members(p, &had_err);
    token::Token rbrace = expect(p, token::TokenKind::RBrace);
    if(rbrace.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::EnumDeclNode* n = arena::alloc(p.m.arena, sizeof(ast::EnumDeclNode));
    sys::memset(n, 0, sizeof(ast::EnumDeclNode));
    n.h.kind = ast::AstKind::EnumDecl;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.name = name.data.sym;
    n.base_type = base_type;
    n.members = members;
    n.is_exported = is_exported;
    return (ast::AstNode*)n;
}

fn ast::AstNode* parse_compcode(Parser* p) {
    u32 start = peek(p, 0).src_pos;
    token::Token kw = expect(p, token::TokenKind::COMPCODE);
    if(kw.kind == token::TokenKind::ERROR) { return mk_error_node(p, start); }
    bool had_err = false;
    ast::AstNode* body = parse_block(p);
    if(had_error(body)) { had_err = true; }
    ast::CompCodeNode* n = arena::alloc(p.m.arena, sizeof(ast::CompCodeNode));
    n.h.kind = ast::AstKind::Compcode;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.body = body;
    return (ast::AstNode*)n;
}

fn ast::AstNode* parse_compsplice(Parser* p) {
    u32 start = peek(p, 0).src_pos;
    token::Token kw = expect(p, token::TokenKind::COMPSPLICE);
    if(kw.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    ast::AstNode* code = parse_expr(p, 0);
    if(!code || had_error(code)) { had_err = true; }
    token::Token semi = expect(p, token::TokenKind::Semi);
    if(semi.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::CompSpliceNode* n = arena::alloc(p.m.arena, sizeof(ast::CompSpliceNode));
    n.h.kind = ast::AstKind::CompspliceStmt;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.code_expr = code;
    return (ast::AstNode*)n;
}

fn ast::AstNode* parse_compinsert(Parser* p) {
    u32 start = peek(p, 0).src_pos;
    token::Token kw = expect(p, token::TokenKind::COMPINSERT);
    if(kw.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    token::Token lparen = expect(p, token::TokenKind::LParen);
    if(lparen.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::AstNode* src = parse_expr(p, 0);
    if(!src || had_error(src)) { had_err = true; }
    token::Token rparen = expect(p, token::TokenKind::RParen);
    if(rparen.kind == token::TokenKind::ERROR) { had_err = true; }
    token::Token semi = expect(p, token::TokenKind::Semi);
    if(semi.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::CompInsertNode* n = arena::alloc(p.m.arena, sizeof(ast::CompInsertNode));
    n.h.kind = ast::AstKind::CompinsertStmt;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.source_expr = src;
    return (ast::AstNode*)n;
}

fn ast::AstNode* parse_comperror(Parser* p) {
    u32 start = peek(p, 0).src_pos;
    token::Token kw = expect(p, token::TokenKind::COMPERROR);
    if(kw.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    token::Token lparen = expect(p, token::TokenKind::LParen);
    if(lparen.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::AstNode* msg = parse_expr(p, 0);
    if(!msg || had_error(msg)) { had_err = true; }
    token::Token rparen = expect(p, token::TokenKind::RParen);
    if(rparen.kind == token::TokenKind::ERROR) { had_err = true; }
    token::Token semi = expect(p, token::TokenKind::Semi);
    if(semi.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::CompErrorNode* n = arena::alloc(p.m.arena, sizeof(ast::CompErrorNode));
    n.h.kind = ast::AstKind::ComperrorStmt;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.msg_expr = msg;
    return (ast::AstNode*)n;
}

fn ast::AstNode* parse_compwarning(Parser* p) {
    u32 start = peek(p, 0).src_pos;
    token::Token kw = expect(p, token::TokenKind::COMPWARNING);
    if(kw.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    token::Token lparen = expect(p, token::TokenKind::LParen);
    if(lparen.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::AstNode* msg = parse_expr(p, 0);
    if(!msg || had_error(msg)) { had_err = true; }
    token::Token rparen = expect(p, token::TokenKind::RParen);
    if(rparen.kind == token::TokenKind::ERROR) { had_err = true; }
    token::Token semi = expect(p, token::TokenKind::Semi);
    if(semi.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::CompWarningNode* n = arena::alloc(p.m.arena, sizeof(ast::CompWarningNode));
    n.h.kind = ast::AstKind::CompwarningStmt;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.msg_expr = msg;
    return (ast::AstNode*)n;
}

fn ast::AstNode* parse_defer(Parser* p) {
    u32 start = peek(p, 0).src_pos;
    token::Token def = expect(p, token::TokenKind::DEFER);
    if(def.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    ast::AstNode* body;
    if(peek(p, 0).kind == token::TokenKind::LBrace) {
        body = parse_block(p);
    } else {
        u32 stmt_pos = peek(p, 0).src_pos;
        ast::AstNode* inner = parse_stmt(p);
        bool inner_err = had_error(inner);
        if(inner_err) { had_err = true; }
        ast::ListBuilder b;
        ast::list_init(&b, p.m.arena, 1);
        ast::list_push(&b, p.m.arena, inner);
        ast::BlockNode* blk = arena::alloc(p.m.arena, sizeof(ast::BlockNode));
        blk.h.kind = ast::AstKind::BlockStmt;
        blk.h.flags = (ast::AstFlags)0;
        if(inner_err) { blk.h.flags = ast::AstFlags::HadError; }
        blk.h.src_pos = stmt_pos;
        blk.stmts = ast::list_freeze(&b);
        body = (ast::AstNode*)blk;
    }
    if(had_error(body)) { had_err = true; }

    ast::DeferNode* n = arena::alloc(p.m.arena, sizeof(ast::DeferNode));
    n.h.kind = ast::AstKind::DeferStmt;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.body = body;
    return (ast::AstNode*)n;
}

fn bool is_assignment_op(token::TokenKind k) {
    switch(k) {
    case token::TokenKind::Eq:        { return true; }
    case token::TokenKind::PlusEq:    { return true; }
    case token::TokenKind::MinusEq:   { return true; }
    case token::TokenKind::StarEq:    { return true; }
    case token::TokenKind::SlashEq:   { return true; }
    case token::TokenKind::PercentEq: { return true; }
    case token::TokenKind::AmpEq:     { return true; }
    case token::TokenKind::PipeEq:    { return true; }
    case token::TokenKind::CaretEq:   { return true; }
    else { return false; }
    }
    return false;
}

// Parses an expression and, if followed by an assignment op, wraps it in an
// AssignmentNode. Used inside for-loop init/post — does not consume a trailing ';'.
fn ast::AstNode* parse_assign_or_expr(Parser* p, bool* had_err) {
    u32 start = peek(p, 0).src_pos;
    ast::AstNode* lhs = parse_expr(p, 0);
    if(!lhs || had_error(lhs)) { *had_err = true; }
    token::Token t = peek(p, 0);
    if(is_assignment_op(t.kind)) {
        consume(p);
        ast::AstNode* rhs = parse_expr(p, 0);
        if(!rhs || had_error(rhs)) { *had_err = true; }
        ast::AssignmentNode* a = arena::alloc(p.m.arena, sizeof(ast::AssignmentNode));
        a.h.kind = ast::AstKind::AssignmentStmt;
        a.h.flags = (ast::AstFlags)0;
        a.h.src_pos = start;
        a.op = t.kind;
        a.lhs = lhs;
        a.rhs = rhs;
        return (ast::AstNode*)a;
    }
    return lhs;
}

fn ast::AstNode* parse_for(Parser* p) {
    u32 start = peek(p, 0).src_pos;
    token::Token for_tok = expect(p, token::TokenKind::FOR);
    if(for_tok.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    token::Token lparen = expect(p, token::TokenKind::LParen);
    if(lparen.kind == token::TokenKind::ERROR) { had_err = true; }

    ast::AstNode* init = null;
    token::TokenKind init_first = peek(p, 0).kind;
    if(init_first == token::TokenKind::Semi) {
        consume(p);
    } else if(init_first == token::TokenKind::CONST) {
        init = parse_local_var_decl(p);
        if(had_error(init)) { had_err = true; }
    } else if(looks_like_type_start(init_first) && looks_like_var_decl(p)) {
        init = parse_local_var_decl(p);
        if(had_error(init)) { had_err = true; }
    } else {
        init = parse_assign_or_expr(p, &had_err);
        token::Token semi = expect(p, token::TokenKind::Semi);
        if(semi.kind == token::TokenKind::ERROR) { had_err = true; }
    }

    ast::AstNode* cond = null;
    if(peek(p, 0).kind != token::TokenKind::Semi) {
        cond = parse_expr(p, 0);
        if(!cond || had_error(cond)) { had_err = true; }
    }
    token::Token semi2 = expect(p, token::TokenKind::Semi);
    if(semi2.kind == token::TokenKind::ERROR) { had_err = true; }

    ast::AstNode* post = null;
    if(peek(p, 0).kind != token::TokenKind::RParen) {
        post = parse_assign_or_expr(p, &had_err);
    }

    token::Token rparen = expect(p, token::TokenKind::RParen);
    if(rparen.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::AstNode* body = parse_block(p);
    if(had_error(body)) { had_err = true; }

    ast::ForNode* n = arena::alloc(p.m.arena, sizeof(ast::ForNode));
    n.h.kind = ast::AstKind::ForStmt;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.init = init;
    n.cond = cond;
    n.post = post;
    n.body = body;
    return (ast::AstNode*)n;
}

fn ast::AstNode* parse_while(Parser* p) {
    u32 start = peek(p, 0).src_pos;
    token::Token while_tok = expect(p, token::TokenKind::WHILE);
    if(while_tok.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    token::Token lparen = expect(p, token::TokenKind::LParen);
    if(lparen.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::AstNode* cond = parse_expr(p, 0);
    if(!cond || had_error(cond)) { had_err = true; }
    token::Token rparen = expect(p, token::TokenKind::RParen);
    if(rparen.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::AstNode* body = parse_block(p);
    if(had_error(body)) { had_err = true; }
    ast::WhileNode* n = arena::alloc(p.m.arena, sizeof(ast::WhileNode));
    n.h.kind = ast::AstKind::WhileStmt;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.cond = cond;
    n.body = body;
    return (ast::AstNode*)n;
}

fn ast::AstNode* parse_if(Parser* p) {
    u32 start = peek(p, 0).src_pos;
    token::Token if_tok = expect(p, token::TokenKind::IF);
    if(if_tok.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    token::Token lparen = expect(p, token::TokenKind::LParen);
    if(lparen.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::AstNode* cond = parse_expr(p, 0);
    if(!cond || had_error(cond)) { had_err = true; }
    token::Token rparen = expect(p, token::TokenKind::RParen);
    if(rparen.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::AstNode* then_block = parse_block(p);
    if(had_error(then_block)) { had_err = true; }
    ast::AstNode* else_block = null;
    if(peek(p, 0).kind == token::TokenKind::ELSE) {
        consume(p);
        if(peek(p, 0).kind == token::TokenKind::IF) {
            else_block = parse_if(p);
        } else {
            else_block = parse_block(p);
        }
        if(had_error(else_block)) { had_err = true; }
    }
    ast::IfNode* n = arena::alloc(p.m.arena, sizeof(ast::IfNode));
    n.h.kind = ast::AstKind::IfStmt;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.cond = cond;
    n.then_block = then_block;
    n.else_block = else_block;
    return (ast::AstNode*)n;
}

// body = null encodes fallthrough to the next arm.
fn ast::AstNode* parse_switch(Parser* p) {
    u32 start = peek(p, 0).src_pos;
    token::Token sw = expect(p, token::TokenKind::SWITCH);
    if(sw.kind == token::TokenKind::ERROR) { return mk_error_node_and_consume(p, start); }
    bool had_err = false;
    token::Token lparen = expect(p, token::TokenKind::LParen);
    if(lparen.kind == token::TokenKind::ERROR) { had_err = true; }
    ast::AstNode* disc = parse_expr(p, 0);
    if(!disc || had_error(disc)) { had_err = true; }
    token::Token rparen = expect(p, token::TokenKind::RParen);
    if(rparen.kind == token::TokenKind::ERROR) { had_err = true; }
    token::Token lbrace = expect(p, token::TokenKind::LBrace);
    if(lbrace.kind == token::TokenKind::ERROR) { had_err = true; }

    ast::SwitchArm[] arms;
    arms.ptr = null;
    arms.len = 0;
    u64 arms_cap = 0;
    ast::AstNode* else_block = null;

    while(peek(p, 0).kind != token::TokenKind::RBrace && peek(p, 0).kind != token::TokenKind::EOF) {
        token::TokenKind k = peek(p, 0).kind;
        if(k == token::TokenKind::CASE) {
            consume(p);
            u32 label_pos = peek(p, 0).src_pos;
            ast::AstNode* label = parse_expr(p, 0);
            if(!label || had_error(label)) { had_err = true; }
            token::Token colon = expect(p, token::TokenKind::Colon);
            if(colon.kind == token::TokenKind::ERROR) { had_err = true; }
            ast::AstNode* body = null;
            if(peek(p, 0).kind == token::TokenKind::LBrace) {
                body = parse_block(p);
                if(had_error(body)) { had_err = true; }
            }
            if(arms.len + 1 > arms_cap) {
                u64 new_cap = 4;
                if(arms_cap > 0) { new_cap = arms_cap * 2; }
                arms.ptr = arena::realloc_grow(p.m.arena, arms.ptr,
                        arms_cap * sizeof(ast::SwitchArm),
                        new_cap * sizeof(ast::SwitchArm));
                arms_cap = new_cap;
            }
            ast::ListBuilder labels_b;
            ast::list_init(&labels_b, p.m.arena, 1);
            ast::list_push(&labels_b, p.m.arena, label);
            ast::SwitchArm* arm = &arms[arms.len];
            arm.labels = ast::list_freeze(&labels_b);
            arm.body = body;
            arm.src_pos = label_pos;
            arms.len += 1;
        } else if(k == token::TokenKind::ELSE) {
            u32 else_pos = peek(p, 0).src_pos;
            consume(p);
            ast::AstNode* eb = parse_block(p);
            if(had_error(eb)) { had_err = true; }
            if(else_block) {
                had_err = true;
                u8[256] scratch;
                i32 n = sys::snprintf((i8*)&scratch[0], 256, "duplicate 'else' in switch");
                if(n > 0) {
                    u64 len = (u64)n;
                    if(len > 255) { len = 255; }
                    u8[] dup_msg = {&scratch[0], len};
                    if(!p.is_speculating) { diag::report(&p.m.diag, p.m.arena, else_pos, dup_msg); }
                }
            } else {
                else_block = eb;
            }
        } else {
            report_expected(p, peek(p, 0), token::TokenKind::CASE);
            had_err = true;
            while(peek(p, 0).kind != token::TokenKind::CASE
                  && peek(p, 0).kind != token::TokenKind::ELSE
                  && peek(p, 0).kind != token::TokenKind::RBrace
                  && peek(p, 0).kind != token::TokenKind::EOF) {
                consume(p);
            }
        }
    }
    token::Token rbrace = expect(p, token::TokenKind::RBrace);
    if(rbrace.kind == token::TokenKind::ERROR) { had_err = true; }

    ast::SwitchNode* n = arena::alloc(p.m.arena, sizeof(ast::SwitchNode));
    n.h.kind = ast::AstKind::SwitchStmt;
    n.h.flags = (ast::AstFlags)0;
    if(had_err) { n.h.flags = ast::AstFlags::HadError; }
    n.h.src_pos = start;
    n.discriminant = disc;
    n.arms = arms;
    n.else_block = else_block;
    return (ast::AstNode*)n;
}

// Speculative: try parse_type then check next is Ident. Rewind either way.
fn bool looks_like_var_decl(Parser* p) {
    ParserSnapshot s = snap(p);
    bool prev_spec = p.is_speculating;
    p.is_speculating = true;
    ast::AstNode* ty = parse_type(p);
    bool ok = ty && !had_error(ty) && peek(p, 0).kind == token::TokenKind::Ident;
    p.is_speculating = prev_spec;
    rewind(p, s);
    return ok;
}

fn ast::AstNode* parse_block(Parser* p) {
    u32 start = peek(p, 0).src_pos;
    bool local_err = false;
    token::Token open = expect(p, token::TokenKind::LBrace);
    if(open.kind == token::TokenKind::ERROR) { return mk_error_node(p, start); }
    ast::ListBuilder stmts;
    ast::list_init(&stmts, p.m.arena, 8);
    while(peek(p, 0).kind != token::TokenKind::RBrace && peek(p, 0).kind != token::TokenKind::EOF) {
        ast::AstNode* s = parse_stmt(p);
        if(s) {
            ast::list_push(&stmts, p.m.arena, s);
            if(had_error(s)) { local_err = true; }
        }
    }
    token::Token close = expect(p, token::TokenKind::RBrace);
    if(close.kind == token::TokenKind::ERROR) { local_err = true; }
    ast::BlockNode* blk = arena::alloc(p.m.arena, sizeof(ast::BlockNode));
    blk.h.kind = ast::AstKind::BlockStmt;
    blk.h.flags = (ast::AstFlags)0;
    if(local_err) { blk.h.flags = ast::AstFlags::HadError; }
    blk.h.src_pos = start;
    blk.stmts = ast::list_freeze(&stmts);
    return (ast::AstNode*)blk;
}

// TYPES ////////////////////////////////////////////////////////////////////////////////
fn ast::AstNode* parse_type(Parser* p) {
    ast::AstNode* base = parse_base_type(p);
    if(!base) {
        if(!p.is_speculating) {
            report_expected(p, peek(p, 0), token::TokenKind::Ident);
        }
        return mk_error_node(p, peek(p, 0).src_pos);
    }
    return parse_type_suffix(p, base);
}

fn ast::AstNode* parse_base_type(Parser* p) {
    token::Token t = peek(p, 0);
    if(token::is_type_keyword(t.kind)) {
        consume(p);
        ast::TypePrimitiveNode* n = arena::alloc(p.m.arena, sizeof(ast::TypePrimitiveNode));
        n.h.kind = ast::AstKind::PrimitiveType;
        n.h.flags = (ast::AstFlags)0;
        n.h.src_pos = t.src_pos;
        n.kind = t.kind;
        return (ast::AstNode*)n;
    }
    switch(t.kind) {
    case token::TokenKind::FN: {
        consume(p);
        token::Token star = expect(p, token::TokenKind::Star);
        if(star.kind == token::TokenKind::ERROR) { return mk_error_node(p, t.src_pos); }
        ast::AstNode* ret = parse_type(p);
        token::Token lparen = expect(p, token::TokenKind::LParen);
        if(lparen.kind == token::TokenKind::ERROR) { return mk_error_node(p, t.src_pos); }
        ast::ListBuilder pb;
        ast::list_init(&pb, p.m.arena, 4);
        while(peek(p, 0).kind != token::TokenKind::RParen && peek(p, 0).kind != token::TokenKind::EOF) {
            ast::list_push(&pb, p.m.arena, parse_type(p));
            if(!match(p, token::TokenKind::Comma)) { break; }
        }
        expect(p, token::TokenKind::RParen);
        ast::TypeFnPtrNode* n = arena::alloc(p.m.arena, sizeof(ast::TypeFnPtrNode));
        n.h.kind = ast::AstKind::FnPtrType;
        n.h.flags = (ast::AstFlags)0;
        n.h.src_pos = t.src_pos;
        n.return_type = ret;
        n.param_types = ast::list_freeze(&pb);
        return (ast::AstNode*)n;
    }
    case token::TokenKind::STRUCT: {
        consume(p);
        token::Token lbrace = expect(p, token::TokenKind::LBrace);
        if(lbrace.kind == token::TokenKind::ERROR) { return mk_error_node(p, t.src_pos); }
        bool dummy = false;
        ast::FieldDecl[] fields = parse_fields(p, &dummy);
        expect(p, token::TokenKind::RBrace);
        ast::TypeStructNode* n = arena::alloc(p.m.arena, sizeof(ast::TypeStructNode));
        n.h.kind = ast::AstKind::StructType;
        n.h.flags = (ast::AstFlags)0;
        n.h.src_pos = t.src_pos;
        n.fields = fields;
        return (ast::AstNode*)n;
    }
    case token::TokenKind::Dot: {
        consume(p);
        token::Token lbrace = expect(p, token::TokenKind::LBrace);
        if(lbrace.kind == token::TokenKind::ERROR) { return mk_error_node(p, t.src_pos); }
        bool dummy = false;
        ast::FieldDecl[] fields = parse_fields(p, &dummy);
        expect(p, token::TokenKind::RBrace);
        ast::TypeStructNode* n = arena::alloc(p.m.arena, sizeof(ast::TypeStructNode));
        n.h.kind = ast::AstKind::StructType;
        n.h.flags = (ast::AstFlags)0;
        n.h.src_pos = t.src_pos;
        n.fields = fields;
        return (ast::AstNode*)n;
    }
    case token::TokenKind::UNION: {
        consume(p);
        token::Token lbrace = expect(p, token::TokenKind::LBrace);
        if(lbrace.kind == token::TokenKind::ERROR) { return mk_error_node(p, t.src_pos); }
        bool dummy = false;
        ast::FieldDecl[] fields = parse_fields(p, &dummy);
        expect(p, token::TokenKind::RBrace);
        ast::TypeUnionNode* n = arena::alloc(p.m.arena, sizeof(ast::TypeUnionNode));
        n.h.kind = ast::AstKind::UnionType;
        n.h.flags = (ast::AstFlags)0;
        n.h.src_pos = t.src_pos;
        n.fields = fields;
        return (ast::AstNode*)n;
    }
    case token::TokenKind::Ident: {
        consume(p);
        symbol::Symbol* ns = null;
        symbol::Symbol* name = t.data.sym;
        if(peek(p, 0).kind == token::TokenKind::ColonColon) {
            consume(p);
            token::Token n2 = expect(p, token::TokenKind::Ident);
            if(n2.kind == token::TokenKind::ERROR) { return mk_error_node(p, t.src_pos); }
            ns = name;
            name = n2.data.sym;
        }
        ast::TypeNamedNode* n = arena::alloc(p.m.arena, sizeof(ast::TypeNamedNode));
        n.h.kind = ast::AstKind::NamedType;
        n.h.flags = (ast::AstFlags)0;
        n.h.src_pos = t.src_pos;
        n.namespace = ns;
        n.name = name;
        return (ast::AstNode*)n;
    }
    else { return null; }
    }
    return null;
}

fn ast::AstNode* parse_type_suffix(Parser* p, ast::AstNode* inner) {
    while(true) {
        token::Token t = peek(p, 0);
        if(t.kind == token::TokenKind::Star) {
            consume(p);
            ast::TypePointerNode* n = arena::alloc(p.m.arena, sizeof(ast::TypePointerNode));
            n.h.kind = ast::AstKind::PointerType;
            n.h.flags = (ast::AstFlags)0;
            n.h.src_pos = t.src_pos;
            n.pointee = inner;
            n.is_const = false;
            inner = (ast::AstNode*)n;
        } else if(t.kind == token::TokenKind::LBracket) {
            consume(p);
            if(peek(p, 0).kind == token::TokenKind::RBracket) {
                consume(p);
                ast::TypeSliceNode* n = arena::alloc(p.m.arena, sizeof(ast::TypeSliceNode));
                n.h.kind = ast::AstKind::SliceType;
                n.h.flags = (ast::AstFlags)0;
                n.h.src_pos = t.src_pos;
                n.element = inner;
                inner = (ast::AstNode*)n;
            } else {
                ast::AstNode* sz = parse_expr(p, 0);
                expect(p, token::TokenKind::RBracket);
                ast::TypeArrayNode* n = arena::alloc(p.m.arena, sizeof(ast::TypeArrayNode));
                n.h.kind = ast::AstKind::ArrayType;
                n.h.flags = (ast::AstFlags)0;
                n.h.src_pos = t.src_pos;
                n.element = inner;
                n.size_expr = sz;
                inner = (ast::AstNode*)n;
            }
        } else {
            return inner;
        }
    }
    return inner;
}

// EXPRESSIONS (Pratt) //////////////////////////////////////////////////////////////////
// Returns precedence for binary operators; 0 means "not a binary op". All
// saplang binary ops are left-associative
fn i16 binary_op_prec(token::TokenKind k) {
    switch(k) {
    case token::TokenKind::PipePipe: { return 1; }
    case token::TokenKind::AmpAmp:   { return 2; }
    case token::TokenKind::Pipe:     { return 3; }
    case token::TokenKind::Caret:    { return 4; }
    case token::TokenKind::Amp:      { return 5; }
    case token::TokenKind::EqEq:     { return 6; }
    case token::TokenKind::BangEq:   { return 6; }
    case token::TokenKind::LT:       { return 7; }
    case token::TokenKind::LTEQ:     { return 7; }
    case token::TokenKind::GT:       { return 7; }
    case token::TokenKind::GTEQ:     { return 7; }
    case token::TokenKind::LShift:   { return 8; }
    case token::TokenKind::RShift:   { return 8; }
    case token::TokenKind::Plus:     { return 9; }
    case token::TokenKind::Minus:    { return 9; }
    case token::TokenKind::Star:     { return 10; }
    case token::TokenKind::Slash:    { return 10; }
    case token::TokenKind::Percent:  { return 10; }
    else { return 0; }
    }
    return 0;
}

fn ast::AstNode* parse_expr(Parser* p, i16 min_prec) {
    ast::AstNode* lhs = parse_unary(p);
    while(true) {
        token::Token tok = peek(p, 0);
        i16 prec = binary_op_prec(tok.kind);
        if(prec == 0 || prec < min_prec) { break; }
        consume(p);
        ast::AstNode* rhs = parse_expr(p, prec + 1);
        ast::BinaryOpNode* b = arena::alloc(p.m.arena, sizeof(ast::BinaryOpNode));
        b.h.kind = ast::AstKind::BinaryOp;
        b.h.flags = (ast::AstFlags)0;
        b.h.src_pos = tok.src_pos;
        b.op = tok.kind;
        b.lhs = lhs;
        b.rhs = rhs;
        lhs = (ast::AstNode*)b;
    }
    return lhs;
}

fn ast::AstNode* parse_unary(Parser* p) {
    token::Token t = peek(p, 0);
    if(t.kind == token::TokenKind::Minus
       || t.kind == token::TokenKind::Bang
       || t.kind == token::TokenKind::Tilde
       || t.kind == token::TokenKind::Amp
       || t.kind == token::TokenKind::Star) {
        consume(p);
        ast::AstNode* operand = parse_unary(p);
        ast::UnaryOpNode* u = arena::alloc(p.m.arena, sizeof(ast::UnaryOpNode));
        u.h.kind = ast::AstKind::UnaryOp;
        u.h.flags = (ast::AstFlags)0;
        u.h.src_pos = t.src_pos;
        u.op = t.kind;
        u.operand = operand;
        return (ast::AstNode*)u;
    }
    return parse_postfix(p);
}

fn ast::AstNode* parse_postfix(Parser* p) {
    ast::AstNode* e = parse_primary(p);
    while(true) {
        token::Token t = peek(p, 0);
        if(t.kind == token::TokenKind::LParen) {
            consume(p);
            ast::ListBuilder b;
            ast::list_init(&b, p.m.arena, 4);
            while(peek(p, 0).kind != token::TokenKind::RParen && peek(p, 0).kind != token::TokenKind::EOF) {
                ast::list_push(&b, p.m.arena, parse_expr(p, 0));
                if(!match(p, token::TokenKind::Comma)) { break; }
            }
            expect(p, token::TokenKind::RParen);
            ast::CallNode* n = arena::alloc(p.m.arena, sizeof(ast::CallNode));
            n.h.kind = ast::AstKind::Call;
            n.h.flags = (ast::AstFlags)0;
            n.h.src_pos = t.src_pos;
            n.callee = e;
            n.args = ast::list_freeze(&b);
            e = (ast::AstNode*)n;
        } else if(t.kind == token::TokenKind::LBracket) {
            consume(p);
            ast::AstNode* first = parse_expr(p, 0);
            if(peek(p, 0).kind == token::TokenKind::DotDot) {
                consume(p);
                ast::AstNode* hi = parse_expr(p, 0);
                expect(p, token::TokenKind::RBracket);
                ast::SliceRangeNode* n = arena::alloc(p.m.arena, sizeof(ast::SliceRangeNode));
                n.h.kind = ast::AstKind::SliceRange;
                n.h.flags = (ast::AstFlags)0;
                n.h.src_pos = t.src_pos;
                n.base = e;
                n.lo = first;
                n.hi = hi;
                e = (ast::AstNode*)n;
            } else {
                expect(p, token::TokenKind::RBracket);
                ast::ArrayIndexNode* n = arena::alloc(p.m.arena, sizeof(ast::ArrayIndexNode));
                n.h.kind = ast::AstKind::ArrayIndex;
                n.h.flags = (ast::AstFlags)0;
                n.h.src_pos = t.src_pos;
                n.base = e;
                n.index = first;
                e = (ast::AstNode*)n;
            }
        } else if(t.kind == token::TokenKind::Dot) {
            consume(p);
            token::Token name = expect(p, token::TokenKind::Ident);
            if(name.kind == token::TokenKind::ERROR) { return mk_error_node(p, t.src_pos); }
            ast::MemberAccessNode* n = arena::alloc(p.m.arena, sizeof(ast::MemberAccessNode));
            n.h.kind = ast::AstKind::MemberAccess;
            n.h.flags = (ast::AstFlags)0;
            n.h.src_pos = t.src_pos;
            n.base = e;
            n.field = name.data.sym;
            e = (ast::AstNode*)n;
        } else {
            return e;
        }
    }
    return e;
}

fn ast::AstNode* parse_primary(Parser* p) {
    token::Token t = peek(p, 0);
    switch(t.kind) {
    case token::TokenKind::IntLit: {
        consume(p);
        ast::IntLitNode* n = arena::alloc(p.m.arena, sizeof(ast::IntLitNode));
        n.h.kind = ast::AstKind::IntLit;
        n.h.flags = (ast::AstFlags)0;
        n.h.src_pos = t.src_pos;
        n.value = t.data.ival;
        return (ast::AstNode*)n;
    }
    case token::TokenKind::FloatLit: {
        consume(p);
        ast::FloatLitNode* n = arena::alloc(p.m.arena, sizeof(ast::FloatLitNode));
        n.h.kind = ast::AstKind::FloatLit;
        n.h.flags = (ast::AstFlags)0;
        n.h.src_pos = t.src_pos;
        n.value = t.data.fval;
        return (ast::AstNode*)n;
    }
    case token::TokenKind::CharLit: {
        consume(p);
        ast::CharLitNode* n = arena::alloc(p.m.arena, sizeof(ast::CharLitNode));
        n.h.kind = ast::AstKind::CharLit;
        n.h.flags = (ast::AstFlags)0;
        n.h.src_pos = t.src_pos;
        n.value = (u8)t.data.ival;
        return (ast::AstNode*)n;
    }
    case token::TokenKind::StringLit: {
        consume(p);
        ast::StringLitNode* n = arena::alloc(p.m.arena, sizeof(ast::StringLitNode));
        n.h.kind = ast::AstKind::StringLit;
        n.h.flags = (ast::AstFlags)0;
        n.h.src_pos = t.src_pos;
        n.pool_off = t.data.bytes.off;
        n.pool_len = t.data.bytes.len;
        return (ast::AstNode*)n;
    }
    case token::TokenKind::TRUE: {
        consume(p);
        ast::BoolLitNode* n = arena::alloc(p.m.arena, sizeof(ast::BoolLitNode));
        n.h.kind = ast::AstKind::BoolLit;
        n.h.flags = (ast::AstFlags)0;
        n.h.src_pos = t.src_pos;
        n.value = true;
        return (ast::AstNode*)n;
    }
    case token::TokenKind::FALSE: {
        consume(p);
        ast::BoolLitNode* n = arena::alloc(p.m.arena, sizeof(ast::BoolLitNode));
        n.h.kind = ast::AstKind::BoolLit;
        n.h.flags = (ast::AstFlags)0;
        n.h.src_pos = t.src_pos;
        n.value = false;
        return (ast::AstNode*)n;
    }
    case token::TokenKind::NULL: {
        consume(p);
        ast::NullLitNode* n = arena::alloc(p.m.arena, sizeof(ast::NullLitNode));
        n.h.kind = ast::AstKind::NullLit;
        n.h.flags = (ast::AstFlags)0;
        n.h.src_pos = t.src_pos;
        return (ast::AstNode*)n;
    }
    case token::TokenKind::UNDEFINED: {
        consume(p);
        ast::UndefinedLitNode* n = arena::alloc(p.m.arena, sizeof(ast::UndefinedLitNode));
        n.h.kind = ast::AstKind::UndefinedLit;
        n.h.flags = (ast::AstFlags)0;
        n.h.src_pos = t.src_pos;
        return (ast::AstNode*)n;
    }
    case token::TokenKind::Ident:    { return parse_ident_or_ns(p); }
    case token::TokenKind::LParen:   { return parse_paren_or_cast(p); }
    case token::TokenKind::LBrace:   { return parse_struct_lit(p); }
    case token::TokenKind::LBracket: { return parse_array_lit(p); }
    case token::TokenKind::COMPCODE: { return parse_compcode(p); }
    else {
        if(!p.is_speculating) { report_expected(p, t, token::TokenKind::Ident); }
        return mk_error_node_and_consume(p, t.src_pos);
    }
    }
    return mk_error_node(p, t.src_pos);
}

fn ast::AstNode* parse_ident_or_ns(Parser* p) {
    token::Token t = consume(p);
    if(peek(p, 0).kind == token::TokenKind::ColonColon) {
        consume(p);
        token::Token n2 = expect(p, token::TokenKind::Ident);
        if(n2.kind == token::TokenKind::ERROR) { return mk_error_node(p, t.src_pos); }
        ast::NamespaceAccessNode* na = arena::alloc(p.m.arena, sizeof(ast::NamespaceAccessNode));
        na.h.kind = ast::AstKind::NamespaceAccess;
        na.h.flags = (ast::AstFlags)0;
        na.h.src_pos = t.src_pos;
        na.namespace = t.data.sym;
        na.name = n2.data.sym;
        return (ast::AstNode*)na;
    }
    ast::IdentNode* id = arena::alloc(p.m.arena, sizeof(ast::IdentNode));
    id.h.kind = ast::AstKind::Ident;
    id.h.flags = (ast::AstFlags)0;
    id.h.src_pos = t.src_pos;
    id.name = t.data.sym;
    return (ast::AstNode*)id;
}

// (T)expr cast vs (expr) parenthesized: try parse_type speculatively. If it
// commits and the next token is ')', it's a cast. Otherwise rewind and parse
// as an expression.
fn ast::AstNode* parse_paren_or_cast(Parser* p) {
    token::Token open = consume(p);
    ParserSnapshot s = snap(p);
    bool prev_spec = p.is_speculating;
    p.is_speculating = true;
    ast::AstNode* ty = parse_type(p);
    p.is_speculating = prev_spec;

    if(ty && !had_error(ty) && peek(p, 0).kind == token::TokenKind::RParen) {
        consume(p);
        ast::AstNode* operand = parse_unary(p);
        ast::CastNode* c = arena::alloc(p.m.arena, sizeof(ast::CastNode));
        c.h.kind = ast::AstKind::Cast;
        c.h.flags = (ast::AstFlags)0;
        c.h.src_pos = open.src_pos;
        c.target_type = ty;
        c.expr = operand;
        return (ast::AstNode*)c;
    }
    rewind(p, s);

    ast::AstNode* e = parse_expr(p, 0);
    expect(p, token::TokenKind::RParen);
    if(e) {
        e.h.flags = (ast::AstFlags)((u16)e.h.flags | (u16)ast::AstFlags::Parenthesized);
    }
    return e;
}

fn ast::AstNode* parse_struct_lit(Parser* p) {
    token::Token open = consume(p);
    ast::FieldInitializer[] inits_arr;
    inits_arr.ptr = null;
    inits_arr.len = 0;
    u64 cap = 0;
    while(peek(p, 0).kind != token::TokenKind::RBrace && peek(p, 0).kind != token::TokenKind::EOF) {
        u32 fi_pos = peek(p, 0).src_pos;
        symbol::Symbol* fi_name = null;
        if(peek(p, 0).kind == token::TokenKind::Dot && peek(p, 1).kind == token::TokenKind::Ident) {
            consume(p);
            token::Token name = consume(p);
            expect(p, token::TokenKind::Eq);
            fi_name = name.data.sym;
        }
        ast::AstNode* val = parse_expr(p, 0);
        if(inits_arr.len + 1 > cap) {
            u64 new_cap = 4;
            if(cap > 0) { new_cap = cap * 2; }
            inits_arr.ptr = arena::realloc_grow(p.m.arena, inits_arr.ptr,
                    cap * sizeof(ast::FieldInitializer),
                    new_cap * sizeof(ast::FieldInitializer));
            cap = new_cap;
        }
        ast::FieldInitializer* fi = &inits_arr[inits_arr.len];
        fi.name = fi_name;
        fi.value = val;
        fi.src_pos = fi_pos;
        inits_arr.len += 1;
        if(!match(p, token::TokenKind::Comma)) { break; }
    }
    expect(p, token::TokenKind::RBrace);
    ast::StructLitNode* n = arena::alloc(p.m.arena, sizeof(ast::StructLitNode));
    n.h.kind = ast::AstKind::StructLit;
    n.h.flags = (ast::AstFlags)0;
    n.h.src_pos = open.src_pos;
    n.inits = inits_arr;
    return (ast::AstNode*)n;
}

fn ast::AstNode* parse_array_lit(Parser* p) {
    token::Token open = consume(p);
    ast::ListBuilder b;
    ast::list_init(&b, p.m.arena, 4);
    while(peek(p, 0).kind != token::TokenKind::RBracket && peek(p, 0).kind != token::TokenKind::EOF) {
        ast::list_push(&b, p.m.arena, parse_expr(p, 0));
        if(!match(p, token::TokenKind::Comma)) { break; }
    }
    expect(p, token::TokenKind::RBracket);
    ast::ArrayLitNode* n = arena::alloc(p.m.arena, sizeof(ast::ArrayLitNode));
    n.h.kind = ast::AstKind::ArrayLit;
    n.h.flags = (ast::AstFlags)0;
    n.h.src_pos = open.src_pos;
    n.elems = ast::list_freeze(&b);
    return (ast::AstNode*)n;
}

// HELPERS //////////////////////////////////////////////////////////////////////////////
fn token::Token peek(Parser* p, u32 ahead) {
    u32 i = p.idx + ahead;
    if (i >= (u32)p.m.tokens.len) { return p.m.tokens.ptr[p.m.tokens.len - 1]; }  // EOF
    return p.m.tokens.ptr[i];
}

fn token::Token consume(Parser* p) {
    token::Token t = peek(p, 0);
    if (p.idx < (u32)p.m.tokens.len) { p.idx += 1; }
    return t;
}

fn bool match(Parser* p, token::TokenKind kind) {
    if (peek(p, 0).kind != kind) { return false; }
    consume(p);
    return true;
}

fn token::Token expect(Parser* p, token::TokenKind kind) {
    token::Token t = peek(p, 0);
    if (t.kind != kind) {
        report_expected(p, t, kind);
        return mk_error_token(t.src_pos);
    }
    consume(p);
    return t;
}

fn void report_expected(Parser* p, token::Token tok, token::TokenKind kind_expected) {
    if(p.is_speculating) { return; }
    u8[] expected_name = token::kind_name(kind_expected);
    u8[] got_name = token::kind_name(tok.kind);
    u8[256] scratch;
    i32 n = sys::snprintf((i8*)&scratch[0], 256, "expected %.*s, got %.*s",
                          (i32)expected_name.len, (i8*)expected_name.ptr,
                          (i32)got_name.len, (i8*)got_name.ptr);
    if(n <= 0) { return; }
    u64 len = (u64)n;
    if(len > 255) { len = 255; }
    u8[] msg = {&scratch[0], len};
    diag::report(&p.m.diag, p.m.arena, tok.src_pos, msg);
}

fn u32 save_pos(Parser* p) { return p.idx; }

fn void restore_pos(Parser* p, u32 saved) { p.idx = saved; }

fn token::Token mk_error_token(u32 pos) {
    token::TokenData data;
    data.none = 4;
    return {token::TokenKind::ERROR, 0, pos, data};
}

fn ast::AstNode* mk_error_node_and_consume(Parser* p, u32 pos) {
    ast::AstNode* error_node = arena::alloc(p.m.arena, sizeof(ast::AstNode));
    error_node.h.kind = ast::AstKind::ERROR;
    error_node.h.flags = ast::AstFlags::HadError;
    error_node.h.src_pos = pos;
    p.idx += 1;
    return error_node;
}

fn ast::AstNode* mk_error_node(Parser* p, u32 pos) {
    ast::AstNode* error_node = arena::alloc(p.m.arena, sizeof(ast::AstNode));
    error_node.h.kind = ast::AstKind::ERROR;
    error_node.h.flags = ast::AstFlags::HadError;
    error_node.h.src_pos = pos;
    return error_node;
}

fn bool had_error(ast::AstNode* n) {
    if(!n) { return true; }
    return ((u16)n.h.flags & (u16)ast::AstFlags::HadError) != 0;
}

struct ParserSnapshot { u32 idx; u64 diag_entries_len; }

fn ParserSnapshot snap(Parser* p) {
    ParserSnapshot s;
    s.idx = p.idx;
    s.diag_entries_len = p.m.diag.entries.len;
    return s;
}

fn void rewind(Parser* p, ParserSnapshot s) {
    p.idx = s.idx;
    p.m.diag.entries.len = s.diag_entries_len;     // drop any diagnostics emitted during trial
}
