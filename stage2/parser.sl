import module;
import ast;
import token;
import diag;
import arena;
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
        //case token::TokenKind::EXTERN:  { return parse_extern_block(p); }
        //case token::TokenKind::COMPRUN: { return parse_comprun(p); }
        //case token::TokenKind::FN:      { return parse_fn_decl(p, is_exported); }
        //case token::TokenKind::STRUCT:  { return parse_struct_decl(p, is_exported); }
        //case token::TokenKind::UNION:   { return parse_union_decl(p, is_exported); }
        //case token::TokenKind::ENUM:    { return parse_enum_decl(p, is_exported); }
        //case token::TokenKind::ALIAS:   { return parse_alias_decl(p, is_exported); }
        //case token::TokenKind::CONST:   { return parse_var_decl(p, is_exported); }
        //                 else {
        //                     if (looks_like_type_start(t.kind)) { return parse_var_decl(p, is_exported); }
        //                     report_expected_decl(p, t);
        //                     sync_to_top_decl(p);
        //                     return null;
        //                 }
    else {
        // No matching top-level keyword. Report and advance past the offending
        // token so the outer loop makes progress.
        report_expected(p, t, token::TokenKind::IMPORT);
        return mk_error_node_and_consume(p, t.src_pos);
    }
    }
    return mk_error_node_and_consume(p, t.src_pos);
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
