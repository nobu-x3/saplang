import module;
import ast;
import token;
import diag;
import arena;
import symbol;
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
        //case token::TokenKind::EXTERN:  { return parse_extern_block(p); }
        //case token::TokenKind::COMPRUN: { return parse_comprun(p); }
        case token::TokenKind::FN: {
            if(peek(p, 1).kind == token::TokenKind::Star) { return parse_var_decl(p, is_exported); }
            return parse_fn_decl(p, is_exported);
        }
        //case token::TokenKind::STRUCT:  { return parse_struct_decl(p, is_exported); }
        //case token::TokenKind::UNION:   { return parse_union_decl(p, is_exported); }
        //case token::TokenKind::ENUM:    { return parse_enum_decl(p, is_exported); }
        //case token::TokenKind::ALIAS:   { return parse_alias_decl(p, is_exported); }
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
    ast::AstNode* body = parse_block(p, &had_err);
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
        //case token::TokenKind::LBrace:       { return parse_block(p); }
        //case token::TokenKind::IF:           { return parse_if(p); }
        //case token::TokenKind::WHILE:        { return parse_while(p); }
        //case token::TokenKind::FOR:          { return parse_for(p); }
        //case token::TokenKind::SWITCH:       { return parse_switch(p); }
        //case token::TokenKind::RETURN:       { return parse_return(p); }
        //case token::TokenKind::BREAK:        { return parse_break(p); }
        //case token::TokenKind::CONTINUE:     { return parse_continue(p); }
        //case token::TokenKind::DEFER:        { return parse_defer(p); }
        //case token::TokenKind::COMPRUN:      { return parse_comprun(p); }
        //case token::TokenKind::COMPINSERT:   { return parse_compinsert(p); }
        //case token::TokenKind::COMPSPLICE:   { return parse_compsplice(p); }
        //case token::TokenKind::COMPERROR:    { return parse_comperror(p); }
        //case token::TokenKind::COMPWARNING:  { return parse_compwarning(p); }
        //case token::TokenKind::CONST:        { return parse_local_var_decl(p); }
    else {
        //if(looks_like_type_start(t.kind) && looks_like_var_decl(p)) {
        //    return parse_local_var_decl(p);
        //}
        //return parse_assignment_or_expr_stmt(p);
        report_expected(p, t, token::TokenKind::Semi);
        return mk_error_node_and_consume(p, t.src_pos);
    }
    }
    return mk_error_node_and_consume(p, t.src_pos);
}

fn ast::AstNode* parse_block(Parser* p, bool* had_err) {
    u32 start = peek(p, 0).src_pos;
    bool local_err = false;
    token::Token open = expect(p, token::TokenKind::LBrace);
    if(open.kind == token::TokenKind::ERROR) {
        *had_err = true;
        return mk_error_node(p, start);
    }
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
    if(local_err) { *had_err = true; }
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
