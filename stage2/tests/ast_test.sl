import ast;
import arena;
import sys;
import symbol;
import testing;
import token;

// ----- header / node layout -----

fn i32 header_is_eight_bytes(arena::Arena* a, u8[] msg) {
    if(!testing::expect_eq(sizeof(ast::AstHeader), (u64)8, msg)) { return -1; }
    return 0;
}

fn i32 astnode_alias_matches_header(arena::Arena* a, u8[] msg) {
    if(!testing::expect_eq(sizeof(ast::AstNode), sizeof(ast::AstHeader), msg)) { return -1; }
    return 0;
}

fn i32 intlit_header_plus_u64(arena::Arena* a, u8[] msg) {
    if(!testing::expect_eq(sizeof(ast::IntLitNode), (u64)16, msg)) { return -1; }
    return 0;
}

fn i32 floatlit_header_plus_f64(arena::Arena* a, u8[] msg) {
    if(!testing::expect_eq(sizeof(ast::FloatLitNode), (u64)16, msg)) { return -1; }
    return 0;
}

fn i32 boollit_size(arena::Arena* a, u8[] msg) {
    // header (8) + bool (1) + 7 trailing pad = 16; or 12, depending on align.
    // We don't pin the exact value — just assert it can hold the header.
    if(!testing::expect_ge(sizeof(ast::BoolLitNode), sizeof(ast::AstHeader), msg)) { return -1; }
    return 0;
}

fn i32 binop_layout(arena::Arena* a, u8[] msg) {
    // header (8) + op u16 (2 + 6 pad) + ptr (8) + ptr (8) = 32.
    if(!testing::expect_eq(sizeof(ast::BinaryOpNode), (u64)32, msg)) { return -1; }
    return 0;
}

fn i32 fndecl_layout_nonzero(arena::Arena* a, u8[] msg) {
    // We don't pin the exact value; just sanity-check it includes the
    // header plus the ptr/slice fields.
    if(!testing::expect_ge(sizeof(ast::FnDeclNode), (u64)48, msg)) { return -1; }
    return 0;
}

fn i32 astflags_is_u16(arena::Arena* a, u8[] msg) {
    if(!testing::expect_eq(sizeof(ast::AstFlags), (u64)2, msg)) { return -1; }
    return 0;
}

fn i32 astkind_is_u16(arena::Arena* a, u8[] msg) {
    if(!testing::expect_eq(sizeof(ast::AstKind), (u64)2, msg)) { return -1; }
    return 0;
}

// ----- header roundtrip -----

fn i32 intlit_roundtrip(arena::Arena* a, u8[] msg) {
    ast::IntLitNode lit;
    lit.h.kind = ast::AstKind::IntLit;
    lit.h.flags = ast::AstFlags::ConstExpr;
    lit.h.src_pos = 42;
    lit.value = (u64)12345;
    if(!testing::expect_eq((u16)lit.h.kind, (u16)ast::AstKind::IntLit, msg)) { return -1; }
    if(!testing::expect_eq((u16)lit.h.flags, (u16)ast::AstFlags::ConstExpr, msg)) { return -2; }
    if(!testing::expect_eq(lit.h.src_pos, (u32)42, msg)) { return -3; }
    if(!testing::expect_eq(lit.value, (u64)12345, msg)) { return -4; }
    return 0;
}

fn i32 binop_roundtrip(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    ast::IntLitNode* l = arena::alloc(&local, sizeof(ast::IntLitNode));
    l.h.kind = ast::AstKind::IntLit;
    l.value = (u64)3;
    ast::IntLitNode* r = arena::alloc(&local, sizeof(ast::IntLitNode));
    r.h.kind = ast::AstKind::IntLit;
    r.value = (u64)4;
    ast::BinaryOpNode b;
    b.h.kind = ast::AstKind::BinaryOp;
    b.h.flags = (ast::AstFlags)0;
    b.h.src_pos = (u32)1;
    b.op = token::TokenKind::Plus;
    b.lhs = (ast::AstNode*)l;
    b.rhs = (ast::AstNode*)r;
    if(!testing::expect_eq((u16)b.op, (u16)token::TokenKind::Plus, msg)) { return -1; }
    ast::IntLitNode* l_back = (ast::IntLitNode*)b.lhs;
    ast::IntLitNode* r_back = (ast::IntLitNode*)b.rhs;
    if(!testing::expect_eq(l_back.value, (u64)3, msg)) { return -2; }
    if(!testing::expect_eq(r_back.value, (u64)4, msg)) { return -3; }
    return 0;
}

// ----- list builder -----

fn i32 list_init_starts_empty(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    ast::ListBuilder b;
    ast::list_init(&b, &local, (u32)4);
    if(!testing::expect_eq(b.items.len, (u64)0, msg)) { return -1; }
    if(!testing::expect_eq((u64)b.cap, (u64)4, msg)) { return -2; }
    return 0;
}

fn i32 list_push_one(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    ast::ListBuilder b;
    ast::list_init(&b, &local, (u32)4);
    ast::IntLitNode* lit = arena::alloc(&local, sizeof(ast::IntLitNode));
    lit.h.kind = ast::AstKind::IntLit;
    lit.value = (u64)7;
    ast::list_push(&b, &local, (ast::AstNode*)lit);
    if(!testing::expect_eq(b.items.len, (u64)1, msg)) { return -1; }
    if(!testing::expect_eq((void*)b.items[0], (void*)lit, msg)) { return -2; }
    return 0;
}

fn i32 list_push_many_within_cap(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    ast::ListBuilder b;
    ast::list_init(&b, &local, (u32)8);
    for(u64 i = 0; i < 5; i += 1) {
        ast::IntLitNode* lit = arena::alloc(&local, sizeof(ast::IntLitNode));
        lit.h.kind = ast::AstKind::IntLit;
        lit.value = i;
        ast::list_push(&b, &local, (ast::AstNode*)lit);
    }
    if(!testing::expect_eq(b.items.len, (u64)5, msg)) { return -1; }
    if(!testing::expect_eq((u64)b.cap, (u64)8, msg)) { return -2; }
    for(u64 i = 0; i < 5; i += 1) {
        ast::IntLitNode* got = (ast::IntLitNode*)b.items[i];
        if(!testing::expect_eq(got.value, i, msg)) { return -3; }
    }
    return 0;
}

fn i32 list_push_grows_past_cap(arena::Arena* a, u8[] msg) {
    arena::Arena local = {16384, null};
    ast::ListBuilder b;
    ast::list_init(&b, &local, (u32)2);
    for(u64 i = 0; i < 5; i += 1) {
        ast::IntLitNode* lit = arena::alloc(&local, sizeof(ast::IntLitNode));
        lit.h.kind = ast::AstKind::IntLit;
        lit.value = i + 100;
        ast::list_push(&b, &local, (ast::AstNode*)lit);
    }
    if(!testing::expect_eq(b.items.len, (u64)5, msg)) { return -1; }
    if(!testing::expect_ge((u64)b.cap, (u64)5, msg)) { return -2; }
    // Every payload survives the reallocation.
    for(u64 i = 0; i < 5; i += 1) {
        ast::IntLitNode* got = (ast::IntLitNode*)b.items[i];
        if(!testing::expect_eq(got.value, i + 100, msg)) { return -3; }
    }
    return 0;
}

fn i32 list_push_a_thousand(arena::Arena* a, u8[] msg) {
    arena::Arena local = {1048576, null};
    ast::ListBuilder b;
    ast::list_init(&b, &local, (u32)4);
    for(u64 i = 0; i < 1000; i += 1) {
        ast::IntLitNode* lit = arena::alloc(&local, sizeof(ast::IntLitNode));
        lit.h.kind = ast::AstKind::IntLit;
        lit.value = i;
        ast::list_push(&b, &local, (ast::AstNode*)lit);
    }
    if(!testing::expect_eq(b.items.len, (u64)1000, msg)) { return -1; }
    // Spot-check first, middle, last.
    ast::IntLitNode* first = (ast::IntLitNode*)b.items[0];
    ast::IntLitNode* mid = (ast::IntLitNode*)b.items[500];
    ast::IntLitNode* last = (ast::IntLitNode*)b.items[999];
    if(!testing::expect_eq(first.value, (u64)0, msg)) { return -2; }
    if(!testing::expect_eq(mid.value, (u64)500, msg)) { return -3; }
    if(!testing::expect_eq(last.value, (u64)999, msg)) { return -4; }
    return 0;
}

fn i32 list_push_null_is_noop(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    ast::ListBuilder b;
    ast::list_init(&b, &local, (u32)4);
    ast::list_push(&b, &local, null);
    if(!testing::expect_eq(b.items.len, (u64)0, msg)) { return -1; }
    return 0;
}

fn i32 list_freeze_preserves_len_and_ptr(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    ast::ListBuilder b;
    ast::list_init(&b, &local, (u32)4);
    for(u64 i = 0; i < 3; i += 1) {
        ast::IntLitNode* lit = arena::alloc(&local, sizeof(ast::IntLitNode));
        lit.h.kind = ast::AstKind::IntLit;
        lit.value = i;
        ast::list_push(&b, &local, (ast::AstNode*)lit);
    }
    ast::AstNode*[] frozen = ast::list_freeze(&b);
    if(!testing::expect_eq(frozen.len, (u64)3, msg)) { return -1; }
    if(!testing::expect_eq((void*)frozen.ptr, (void*)b.items.ptr, msg)) { return -2; }
    return 0;
}

fn i32 list_freeze_indices_match(arena::Arena* a, u8[] msg) {
    arena::Arena local = {4096, null};
    ast::ListBuilder b;
    ast::list_init(&b, &local, (u32)4);
    for(u64 i = 0; i < 10; i += 1) {
        ast::IntLitNode* lit = arena::alloc(&local, sizeof(ast::IntLitNode));
        lit.h.kind = ast::AstKind::IntLit;
        lit.value = i * 11;
        ast::list_push(&b, &local, (ast::AstNode*)lit);
    }
    ast::AstNode*[] frozen = ast::list_freeze(&b);
    for(u64 i = 0; i < frozen.len; i += 1) {
        ast::IntLitNode* got = (ast::IntLitNode*)frozen[i];
        if(!testing::expect_eq(got.value, i * 11, msg)) { return -1; }
    }
    return 0;
}

// ----- kind range helpers -----

fn i32 is_decl_first(arena::Arena* a, u8[] msg) {
    if(!testing::expect_true(ast::is_decl((u16)ast::AstKind::ImportDecl), msg)) { return -1; }
    return 0;
}

fn i32 is_decl_last(arena::Arena* a, u8[] msg) {
    if(!testing::expect_true(ast::is_decl((u16)ast::AstKind::ExternUnionDecl), msg)) { return -1; }
    if(!testing::expect_true(ast::is_decl((u16)ast::AstKind::ExternFnDecl), msg)) { return -2; }
    if(!testing::expect_true(ast::is_decl((u16)ast::AstKind::ExternStructDecl), msg)) { return -3; }
    return 0;
}

fn i32 is_decl_middle(arena::Arena* a, u8[] msg) {
    if(!testing::expect_true(ast::is_decl((u16)ast::AstKind::FnDecl), msg)) { return -1; }
    if(!testing::expect_true(ast::is_decl((u16)ast::AstKind::StructDecl), msg)) { return -2; }
    if(!testing::expect_true(ast::is_decl((u16)ast::AstKind::EnumDecl), msg)) { return -3; }
    return 0;
}

fn i32 is_decl_rejects_sentinels(arena::Arena* a, u8[] msg) {
    if(!testing::expect_false(ast::is_decl((u16)ast::AstKind::INVALID), msg)) { return -1; }
    if(!testing::expect_false(ast::is_decl((u16)ast::AstKind::ERROR), msg)) { return -2; }
    return 0;
}

fn i32 is_decl_rejects_other_ranges(arena::Arena* a, u8[] msg) {
    if(!testing::expect_false(ast::is_decl((u16)ast::AstKind::BlockStmt), msg)) { return -1; }
    if(!testing::expect_false(ast::is_decl((u16)ast::AstKind::IntLit), msg)) { return -2; }
    if(!testing::expect_false(ast::is_decl((u16)ast::AstKind::PrimitiveType), msg)) { return -3; }
    return 0;
}

fn i32 is_stmt_first(arena::Arena* a, u8[] msg) {
    if(!testing::expect_true(ast::is_stmt((u16)ast::AstKind::BlockStmt), msg)) { return -1; }
    return 0;
}

fn i32 is_stmt_last(arena::Arena* a, u8[] msg) {
    if(!testing::expect_true(ast::is_stmt((u16)ast::AstKind::CompwarningStmt), msg)) { return -1; }
    return 0;
}

fn i32 is_stmt_middle(arena::Arena* a, u8[] msg) {
    if(!testing::expect_true(ast::is_stmt((u16)ast::AstKind::IfStmt), msg)) { return -1; }
    if(!testing::expect_true(ast::is_stmt((u16)ast::AstKind::WhileStmt), msg)) { return -2; }
    if(!testing::expect_true(ast::is_stmt((u16)ast::AstKind::ReturnStmt), msg)) { return -3; }
    return 0;
}

fn i32 is_stmt_rejects_other_ranges(arena::Arena* a, u8[] msg) {
    if(!testing::expect_false(ast::is_stmt((u16)ast::AstKind::ExternFnDecl), msg)) { return -1; }
    if(!testing::expect_false(ast::is_stmt((u16)ast::AstKind::IntLit), msg)) { return -2; }
    if(!testing::expect_false(ast::is_stmt((u16)ast::AstKind::PrimitiveType), msg)) { return -3; }
    return 0;
}

fn i32 is_expr_first(arena::Arena* a, u8[] msg) {
    if(!testing::expect_true(ast::is_expr((u16)ast::AstKind::IntLit), msg)) { return -1; }
    return 0;
}

fn i32 is_expr_last(arena::Arena* a, u8[] msg) {
    if(!testing::expect_true(ast::is_expr((u16)ast::AstKind::Compcode), msg)) { return -1; }
    return 0;
}

fn i32 is_expr_middle(arena::Arena* a, u8[] msg) {
    if(!testing::expect_true(ast::is_expr((u16)ast::AstKind::Ident), msg)) { return -1; }
    if(!testing::expect_true(ast::is_expr((u16)ast::AstKind::Call), msg)) { return -2; }
    if(!testing::expect_true(ast::is_expr((u16)ast::AstKind::BinaryOp), msg)) { return -3; }
    return 0;
}

fn i32 is_expr_rejects_other_ranges(arena::Arena* a, u8[] msg) {
    if(!testing::expect_false(ast::is_expr((u16)ast::AstKind::CompwarningStmt), msg)) { return -1; }
    if(!testing::expect_false(ast::is_expr((u16)ast::AstKind::PrimitiveType), msg)) { return -2; }
    if(!testing::expect_false(ast::is_expr((u16)ast::AstKind::ImportDecl), msg)) { return -3; }
    return 0;
}

fn i32 is_type_first(arena::Arena* a, u8[] msg) {
    if(!testing::expect_true(ast::is_type((u16)ast::AstKind::PrimitiveType), msg)) { return -1; }
    return 0;
}

fn i32 is_type_last(arena::Arena* a, u8[] msg) {
    if(!testing::expect_true(ast::is_type((u16)ast::AstKind::UnionType), msg)) { return -1; }
    return 0;
}

fn i32 is_type_middle(arena::Arena* a, u8[] msg) {
    if(!testing::expect_true(ast::is_type((u16)ast::AstKind::PointerType), msg)) { return -1; }
    if(!testing::expect_true(ast::is_type((u16)ast::AstKind::SliceType), msg)) { return -2; }
    if(!testing::expect_true(ast::is_type((u16)ast::AstKind::FnPtrType), msg)) { return -3; }
    return 0;
}

fn i32 is_type_rejects_other_ranges(arena::Arena* a, u8[] msg) {
    if(!testing::expect_false(ast::is_type((u16)ast::AstKind::Compcode), msg)) { return -1; }
    if(!testing::expect_false(ast::is_type((u16)ast::AstKind::BlockStmt), msg)) { return -2; }
    if(!testing::expect_false(ast::is_type((u16)ast::AstKind::ExternFnDecl), msg)) { return -3; }
    return 0;
}

fn i32 ranges_partition(arena::Arena* a, u8[] msg) {
    // For every kind whose value is in [INVALID..UnionType], at most one
    // of is_{decl,stmt,expr,type} returns true. INVALID and ERROR sit
    // outside every range — false from all four.
    u16 zero_n = (u16)ast::AstKind::INVALID;
    if(!testing::expect_false(ast::is_decl(zero_n), msg)) { return -1; }
    if(!testing::expect_false(ast::is_stmt(zero_n), msg)) { return -2; }
    if(!testing::expect_false(ast::is_expr(zero_n), msg)) { return -3; }
    if(!testing::expect_false(ast::is_type(zero_n), msg)) { return -4; }

    u16 ident_n = (u16)ast::AstKind::Ident;
    if(!testing::expect_false(ast::is_decl(ident_n), msg)) { return -5; }
    if(!testing::expect_false(ast::is_stmt(ident_n), msg)) { return -6; }
    if(!testing::expect_true(ast::is_expr(ident_n), msg))  { return -7; }
    if(!testing::expect_false(ast::is_type(ident_n), msg)) { return -8; }
    return 0;
}

// ----- header-at-offset-zero for every concrete kind -----
// Casting a concrete node pointer to AstNode* and reading .h.kind round-trips
// only if AstHeader sits at offset 0 in each struct.

fn bool castback(void* p, ast::AstKind expected, u8[] m) {
    ast::AstNode* n = (ast::AstNode*)p;
    return testing::expect_eq((u16)n.h.kind, (u16)expected, m);
}

// decls
fn i32 hdr_import(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::ImportNode* n = arena::alloc(&lo, sizeof(ast::ImportNode));
    n.h.kind = ast::AstKind::ImportDecl;
    if(!castback(n, ast::AstKind::ImportDecl, m)) { return -1; }
    return 0;
}

fn i32 hdr_var_decl(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::VarDeclNode* n = arena::alloc(&lo, sizeof(ast::VarDeclNode));
    n.h.kind = ast::AstKind::VarDecl;
    if(!castback(n, ast::AstKind::VarDecl, m)) { return -1; }
    return 0;
}

fn i32 hdr_fn_decl(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::FnDeclNode* n = arena::alloc(&lo, sizeof(ast::FnDeclNode));
    n.h.kind = ast::AstKind::FnDecl;
    if(!castback(n, ast::AstKind::FnDecl, m)) { return -1; }
    return 0;
}

fn i32 hdr_struct_decl(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::StructDeclNode* n = arena::alloc(&lo, sizeof(ast::StructDeclNode));
    n.h.kind = ast::AstKind::StructDecl;
    if(!castback(n, ast::AstKind::StructDecl, m)) { return -1; }
    return 0;
}

fn i32 hdr_union_decl(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::UnionDeclNode* n = arena::alloc(&lo, sizeof(ast::UnionDeclNode));
    n.h.kind = ast::AstKind::UnionDecl;
    if(!castback(n, ast::AstKind::UnionDecl, m)) { return -1; }
    return 0;
}

fn i32 hdr_enum_decl(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::EnumDeclNode* n = arena::alloc(&lo, sizeof(ast::EnumDeclNode));
    n.h.kind = ast::AstKind::EnumDecl;
    if(!castback(n, ast::AstKind::EnumDecl, m)) { return -1; }
    return 0;
}

fn i32 hdr_alias_decl(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::AliasDeclNode* n = arena::alloc(&lo, sizeof(ast::AliasDeclNode));
    n.h.kind = ast::AstKind::AliasDecl;
    if(!castback(n, ast::AstKind::AliasDecl, m)) { return -1; }
    return 0;
}

fn i32 hdr_extern_block(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::ExternBlockNode* n = arena::alloc(&lo, sizeof(ast::ExternBlockNode));
    n.h.kind = ast::AstKind::ExternBlock;
    if(!castback(n, ast::AstKind::ExternBlock, m)) { return -1; }
    return 0;
}

fn i32 hdr_extern_fn_decl(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::ExternFnDeclNode* n = arena::alloc(&lo, sizeof(ast::ExternFnDeclNode));
    n.h.kind = ast::AstKind::ExternFnDecl;
    if(!castback(n, ast::AstKind::ExternFnDecl, m)) { return -1; }
    return 0;
}

fn i32 hdr_extern_struct_decl(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::ExternStructDeclNode* n = arena::alloc(&lo, sizeof(ast::ExternStructDeclNode));
    n.h.kind = ast::AstKind::ExternStructDecl;
    if(!castback(n, ast::AstKind::ExternStructDecl, m)) { return -1; }
    return 0;
}

fn i32 hdr_extern_union_decl(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::ExternUnionDeclNode* n = arena::alloc(&lo, sizeof(ast::ExternUnionDeclNode));
    n.h.kind = ast::AstKind::ExternUnionDecl;
    if(!castback(n, ast::AstKind::ExternUnionDecl, m)) { return -1; }
    return 0;
}

// stmts
fn i32 hdr_block(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::BlockNode* n = arena::alloc(&lo, sizeof(ast::BlockNode));
    n.h.kind = ast::AstKind::BlockStmt;
    if(!castback(n, ast::AstKind::BlockStmt, m)) { return -1; }
    return 0;
}

fn i32 hdr_if(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::IfNode* n = arena::alloc(&lo, sizeof(ast::IfNode));
    n.h.kind = ast::AstKind::IfStmt;
    if(!castback(n, ast::AstKind::IfStmt, m)) { return -1; }
    return 0;
}

fn i32 hdr_while(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::WhileNode* n = arena::alloc(&lo, sizeof(ast::WhileNode));
    n.h.kind = ast::AstKind::WhileStmt;
    if(!castback(n, ast::AstKind::WhileStmt, m)) { return -1; }
    return 0;
}

fn i32 hdr_for(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::ForNode* n = arena::alloc(&lo, sizeof(ast::ForNode));
    n.h.kind = ast::AstKind::ForStmt;
    if(!castback(n, ast::AstKind::ForStmt, m)) { return -1; }
    return 0;
}

fn i32 hdr_switch(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::SwitchNode* n = arena::alloc(&lo, sizeof(ast::SwitchNode));
    n.h.kind = ast::AstKind::SwitchStmt;
    if(!castback(n, ast::AstKind::SwitchStmt, m)) { return -1; }
    return 0;
}

fn i32 hdr_return(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::ReturnNode* n = arena::alloc(&lo, sizeof(ast::ReturnNode));
    n.h.kind = ast::AstKind::ReturnStmt;
    if(!castback(n, ast::AstKind::ReturnStmt, m)) { return -1; }
    return 0;
}

fn i32 hdr_break(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::BreakNode* n = arena::alloc(&lo, sizeof(ast::BreakNode));
    n.h.kind = ast::AstKind::BreakStmt;
    if(!castback(n, ast::AstKind::BreakStmt, m)) { return -1; }
    // Trivial nodes are header-only.
    if(!testing::expect_eq(sizeof(ast::BreakNode), sizeof(ast::AstHeader), m)) { return -2; }
    return 0;
}

fn i32 hdr_continue(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::ContinueNode* n = arena::alloc(&lo, sizeof(ast::ContinueNode));
    n.h.kind = ast::AstKind::ContinueStmt;
    if(!castback(n, ast::AstKind::ContinueStmt, m)) { return -1; }
    if(!testing::expect_eq(sizeof(ast::ContinueNode), sizeof(ast::AstHeader), m)) { return -2; }
    return 0;
}

fn i32 hdr_defer(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::DeferNode* n = arena::alloc(&lo, sizeof(ast::DeferNode));
    n.h.kind = ast::AstKind::DeferStmt;
    if(!castback(n, ast::AstKind::DeferStmt, m)) { return -1; }
    return 0;
}

fn i32 hdr_assignment(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::AssignmentNode* n = arena::alloc(&lo, sizeof(ast::AssignmentNode));
    n.h.kind = ast::AstKind::AssignmentStmt;
    if(!castback(n, ast::AstKind::AssignmentStmt, m)) { return -1; }
    return 0;
}

fn i32 hdr_expr_stmt(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::ExprStmtNode* n = arena::alloc(&lo, sizeof(ast::ExprStmtNode));
    n.h.kind = ast::AstKind::ExprStmt;
    if(!castback(n, ast::AstKind::ExprStmt, m)) { return -1; }
    return 0;
}

fn i32 hdr_comprun(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::CompRunNode* n = arena::alloc(&lo, sizeof(ast::CompRunNode));
    n.h.kind = ast::AstKind::ComprunStmt;
    if(!castback(n, ast::AstKind::ComprunStmt, m)) { return -1; }
    return 0;
}

fn i32 hdr_compinsert(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::CompInsertNode* n = arena::alloc(&lo, sizeof(ast::CompInsertNode));
    n.h.kind = ast::AstKind::CompinsertStmt;
    if(!castback(n, ast::AstKind::CompinsertStmt, m)) { return -1; }
    return 0;
}

fn i32 hdr_compsplice(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::CompSpliceNode* n = arena::alloc(&lo, sizeof(ast::CompSpliceNode));
    n.h.kind = ast::AstKind::CompspliceStmt;
    if(!castback(n, ast::AstKind::CompspliceStmt, m)) { return -1; }
    return 0;
}

fn i32 hdr_comperror(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::CompErrorNode* n = arena::alloc(&lo, sizeof(ast::CompErrorNode));
    n.h.kind = ast::AstKind::ComperrorStmt;
    if(!castback(n, ast::AstKind::ComperrorStmt, m)) { return -1; }
    return 0;
}

fn i32 hdr_compwarning(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::CompWarningNode* n = arena::alloc(&lo, sizeof(ast::CompWarningNode));
    n.h.kind = ast::AstKind::CompwarningStmt;
    if(!castback(n, ast::AstKind::CompwarningStmt, m)) { return -1; }
    return 0;
}

// exprs
fn i32 hdr_intlit(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::IntLitNode* n = arena::alloc(&lo, sizeof(ast::IntLitNode));
    n.h.kind = ast::AstKind::IntLit;
    if(!castback(n, ast::AstKind::IntLit, m)) { return -1; }
    return 0;
}

fn i32 hdr_floatlit(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::FloatLitNode* n = arena::alloc(&lo, sizeof(ast::FloatLitNode));
    n.h.kind = ast::AstKind::FloatLit;
    if(!castback(n, ast::AstKind::FloatLit, m)) { return -1; }
    return 0;
}

fn i32 hdr_boollit(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::BoolLitNode* n = arena::alloc(&lo, sizeof(ast::BoolLitNode));
    n.h.kind = ast::AstKind::BoolLit;
    if(!castback(n, ast::AstKind::BoolLit, m)) { return -1; }
    return 0;
}

fn i32 hdr_charlit(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::CharLitNode* n = arena::alloc(&lo, sizeof(ast::CharLitNode));
    n.h.kind = ast::AstKind::CharLit;
    if(!castback(n, ast::AstKind::CharLit, m)) { return -1; }
    return 0;
}

fn i32 hdr_stringlit(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::StringLitNode* n = arena::alloc(&lo, sizeof(ast::StringLitNode));
    n.h.kind = ast::AstKind::StringLit;
    if(!castback(n, ast::AstKind::StringLit, m)) { return -1; }
    return 0;
}

fn i32 hdr_nulllit(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::NullLitNode* n = arena::alloc(&lo, sizeof(ast::NullLitNode));
    n.h.kind = ast::AstKind::NullLit;
    if(!castback(n, ast::AstKind::NullLit, m)) { return -1; }
    if(!testing::expect_eq(sizeof(ast::NullLitNode), sizeof(ast::AstHeader), m)) { return -2; }
    return 0;
}

fn i32 hdr_undefinedlit(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::UndefinedLitNode* n = arena::alloc(&lo, sizeof(ast::UndefinedLitNode));
    n.h.kind = ast::AstKind::UndefinedLit;
    if(!castback(n, ast::AstKind::UndefinedLit, m)) { return -1; }
    if(!testing::expect_eq(sizeof(ast::UndefinedLitNode), sizeof(ast::AstHeader), m)) { return -2; }
    return 0;
}

fn i32 hdr_ident(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::IdentNode* n = arena::alloc(&lo, sizeof(ast::IdentNode));
    n.h.kind = ast::AstKind::Ident;
    if(!castback(n, ast::AstKind::Ident, m)) { return -1; }
    return 0;
}

fn i32 hdr_namespace_access(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::NamespaceAccessNode* n = arena::alloc(&lo, sizeof(ast::NamespaceAccessNode));
    n.h.kind = ast::AstKind::NamespaceAccess;
    if(!castback(n, ast::AstKind::NamespaceAccess, m)) { return -1; }
    return 0;
}

fn i32 hdr_member_access(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::MemberAccessNode* n = arena::alloc(&lo, sizeof(ast::MemberAccessNode));
    n.h.kind = ast::AstKind::MemberAccess;
    if(!castback(n, ast::AstKind::MemberAccess, m)) { return -1; }
    return 0;
}

fn i32 hdr_array_index(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::ArrayIndexNode* n = arena::alloc(&lo, sizeof(ast::ArrayIndexNode));
    n.h.kind = ast::AstKind::ArrayIndex;
    if(!castback(n, ast::AstKind::ArrayIndex, m)) { return -1; }
    return 0;
}

fn i32 hdr_slice_range(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::SliceRangeNode* n = arena::alloc(&lo, sizeof(ast::SliceRangeNode));
    n.h.kind = ast::AstKind::SliceRange;
    if(!castback(n, ast::AstKind::SliceRange, m)) { return -1; }
    return 0;
}

fn i32 hdr_call(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::CallNode* n = arena::alloc(&lo, sizeof(ast::CallNode));
    n.h.kind = ast::AstKind::Call;
    if(!castback(n, ast::AstKind::Call, m)) { return -1; }
    return 0;
}

fn i32 hdr_cast(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::CastNode* n = arena::alloc(&lo, sizeof(ast::CastNode));
    n.h.kind = ast::AstKind::Cast;
    if(!castback(n, ast::AstKind::Cast, m)) { return -1; }
    return 0;
}

fn i32 hdr_unary_op(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::UnaryOpNode* n = arena::alloc(&lo, sizeof(ast::UnaryOpNode));
    n.h.kind = ast::AstKind::UnaryOp;
    if(!castback(n, ast::AstKind::UnaryOp, m)) { return -1; }
    return 0;
}

fn i32 hdr_binary_op(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::BinaryOpNode* n = arena::alloc(&lo, sizeof(ast::BinaryOpNode));
    n.h.kind = ast::AstKind::BinaryOp;
    if(!castback(n, ast::AstKind::BinaryOp, m)) { return -1; }
    return 0;
}

fn i32 hdr_struct_lit(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::StructLitNode* n = arena::alloc(&lo, sizeof(ast::StructLitNode));
    n.h.kind = ast::AstKind::StructLit;
    if(!castback(n, ast::AstKind::StructLit, m)) { return -1; }
    return 0;
}

fn i32 hdr_array_lit(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::ArrayLitNode* n = arena::alloc(&lo, sizeof(ast::ArrayLitNode));
    n.h.kind = ast::AstKind::ArrayLit;
    if(!castback(n, ast::AstKind::ArrayLit, m)) { return -1; }
    return 0;
}

fn i32 hdr_sizeof(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::SizeofNode* n = arena::alloc(&lo, sizeof(ast::SizeofNode));
    n.h.kind = ast::AstKind::Sizeof;
    if(!castback(n, ast::AstKind::Sizeof, m)) { return -1; }
    return 0;
}

fn i32 hdr_alignof(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::AlignofNode* n = arena::alloc(&lo, sizeof(ast::AlignofNode));
    n.h.kind = ast::AstKind::Alignof;
    if(!castback(n, ast::AstKind::Alignof, m)) { return -1; }
    return 0;
}

fn i32 hdr_typeof(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::TypeofNode* n = arena::alloc(&lo, sizeof(ast::TypeofNode));
    n.h.kind = ast::AstKind::Typeof;
    if(!castback(n, ast::AstKind::Typeof, m)) { return -1; }
    return 0;
}

fn i32 hdr_typeinfo(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::TypeInfoNode* n = arena::alloc(&lo, sizeof(ast::TypeInfoNode));
    n.h.kind = ast::AstKind::Type_info;
    if(!castback(n, ast::AstKind::Type_info, m)) { return -1; }
    return 0;
}

fn i32 hdr_compcode(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::CompCodeNode* n = arena::alloc(&lo, sizeof(ast::CompCodeNode));
    n.h.kind = ast::AstKind::Compcode;
    if(!castback(n, ast::AstKind::Compcode, m)) { return -1; }
    return 0;
}

// types
fn i32 hdr_primitive_type(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::TypePrimitiveNode* n = arena::alloc(&lo, sizeof(ast::TypePrimitiveNode));
    n.h.kind = ast::AstKind::PrimitiveType;
    if(!castback(n, ast::AstKind::PrimitiveType, m)) { return -1; }
    return 0;
}

fn i32 hdr_named_type(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::TypeNamedNode* n = arena::alloc(&lo, sizeof(ast::TypeNamedNode));
    n.h.kind = ast::AstKind::NamedType;
    if(!castback(n, ast::AstKind::NamedType, m)) { return -1; }
    return 0;
}

fn i32 hdr_pointer_type(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::TypePointerNode* n = arena::alloc(&lo, sizeof(ast::TypePointerNode));
    n.h.kind = ast::AstKind::PointerType;
    if(!castback(n, ast::AstKind::PointerType, m)) { return -1; }
    return 0;
}

fn i32 hdr_array_type(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::TypeArrayNode* n = arena::alloc(&lo, sizeof(ast::TypeArrayNode));
    n.h.kind = ast::AstKind::ArrayType;
    if(!castback(n, ast::AstKind::ArrayType, m)) { return -1; }
    return 0;
}

fn i32 hdr_slice_type(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::TypeSliceNode* n = arena::alloc(&lo, sizeof(ast::TypeSliceNode));
    n.h.kind = ast::AstKind::SliceType;
    if(!castback(n, ast::AstKind::SliceType, m)) { return -1; }
    return 0;
}

fn i32 hdr_fnptr_type(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::TypeFnPtrNode* n = arena::alloc(&lo, sizeof(ast::TypeFnPtrNode));
    n.h.kind = ast::AstKind::FnPtrType;
    if(!castback(n, ast::AstKind::FnPtrType, m)) { return -1; }
    return 0;
}

fn i32 hdr_struct_type(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::TypeStructNode* n = arena::alloc(&lo, sizeof(ast::TypeStructNode));
    n.h.kind = ast::AstKind::StructType;
    if(!castback(n, ast::AstKind::StructType, m)) { return -1; }
    return 0;
}

fn i32 hdr_union_type(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::TypeUnionNode* n = arena::alloc(&lo, sizeof(ast::TypeUnionNode));
    n.h.kind = ast::AstKind::UnionType;
    if(!castback(n, ast::AstKind::UnionType, m)) { return -1; }
    return 0;
}

// ----- field roundtrip for non-trivial node shapes -----

fn i32 boollit_value_roundtrip(arena::Arena* a, u8[] m) {
    ast::BoolLitNode n;
    n.h.kind = ast::AstKind::BoolLit;
    n.value = true;
    if(!testing::expect_true(n.value, m)) { return -1; }
    n.value = false;
    if(!testing::expect_false(n.value, m)) { return -2; }
    return 0;
}

fn i32 charlit_value_roundtrip(arena::Arena* a, u8[] m) {
    ast::CharLitNode n;
    n.h.kind = ast::AstKind::CharLit;
    n.value = 'Z';
    if(!testing::expect_eq((u64)n.value, (u64)'Z', m)) { return -1; }
    return 0;
}

fn i32 stringlit_fields_roundtrip(arena::Arena* a, u8[] m) {
    ast::StringLitNode n;
    n.h.kind = ast::AstKind::StringLit;
    n.pool_off = (u32)100;
    n.pool_len = (u32)5;
    if(!testing::expect_eq(n.pool_off, (u32)100, m)) { return -1; }
    if(!testing::expect_eq(n.pool_len, (u32)5, m)) { return -2; }
    return 0;
}

fn i32 floatlit_value_roundtrip(arena::Arena* a, u8[] m) {
    ast::FloatLitNode n;
    n.h.kind = ast::AstKind::FloatLit;
    n.value = 3.14;
    if(!testing::expect_near(n.value, 3.14, 0.0001, m)) { return -1; }
    return 0;
}

fn i32 ifnode_else_branch_can_be_null(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::IfNode* n = arena::alloc(&lo, sizeof(ast::IfNode));
    n.h.kind = ast::AstKind::IfStmt;
    n.cond = null;
    n.then_block = null;
    n.else_block = null;
    if(!testing::expect_null((void*)n.else_block, m)) { return -1; }
    return 0;
}

fn i32 fornode_fields_can_be_null(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::ForNode* n = arena::alloc(&lo, sizeof(ast::ForNode));
    n.h.kind = ast::AstKind::ForStmt;
    n.init = null;
    n.cond = null;
    n.post = null;
    n.body = null;
    if(!testing::expect_null((void*)n.init, m)) { return -1; }
    if(!testing::expect_null((void*)n.cond, m)) { return -2; }
    if(!testing::expect_null((void*)n.post, m)) { return -3; }
    return 0;
}

fn i32 ptrtype_const_flag_roundtrip(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::TypePointerNode* n = arena::alloc(&lo, sizeof(ast::TypePointerNode));
    n.h.kind = ast::AstKind::PointerType;
    n.is_const = false;
    if(!testing::expect_false(n.is_const, m)) { return -1; }
    n.is_const = true;
    if(!testing::expect_true(n.is_const, m)) { return -2; }
    return 0;
}

fn i32 externfn_variadic_flag_roundtrip(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::ExternFnDeclNode* n = arena::alloc(&lo, sizeof(ast::ExternFnDeclNode));
    n.h.kind = ast::AstKind::ExternFnDecl;
    n.is_variadic = true;
    n.comptime_safe = (i8)-1;
    if(!testing::expect_true(n.is_variadic, m)) { return -1; }
    return 0;
}

fn i32 externstruct_opaque_flag_roundtrip(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::ExternStructDeclNode* n = arena::alloc(&lo, sizeof(ast::ExternStructDeclNode));
    n.h.kind = ast::AstKind::ExternStructDecl;
    n.is_opaque = false;
    if(!testing::expect_false(n.is_opaque, m)) { return -1; }
    n.is_opaque = true;
    if(!testing::expect_true(n.is_opaque, m)) { return -2; }
    n.is_exported = true;
    if(!testing::expect_true(n.is_exported, m)) { return -3; }
    return 0;
}

fn i32 externunion_opaque_flag_roundtrip(arena::Arena* a, u8[] m) {
    arena::Arena lo = {1024, null};
    ast::ExternUnionDeclNode* n = arena::alloc(&lo, sizeof(ast::ExternUnionDeclNode));
    n.h.kind = ast::AstKind::ExternUnionDecl;
    n.is_opaque = false;
    if(!testing::expect_false(n.is_opaque, m)) { return -1; }
    n.is_opaque = true;
    if(!testing::expect_true(n.is_opaque, m)) { return -2; }
    n.is_exported = true;
    if(!testing::expect_true(n.is_exported, m)) { return -3; }
    return 0;
}

// ----- auxiliary structs -----

fn i32 param_field_roundtrip(arena::Arena* a, u8[] m) {
    ast::Param p;
    p.name = null;
    p.type_expr = null;
    p.is_const = true;
    p.is_comptime = false;
    p.src_pos = (u32)123;
    if(!testing::expect_true(p.is_const, m)) { return -1; }
    if(!testing::expect_false(p.is_comptime, m)) { return -2; }
    if(!testing::expect_eq(p.src_pos, (u32)123, m)) { return -3; }
    return 0;
}

fn i32 fielddecl_field_roundtrip(arena::Arena* a, u8[] m) {
    ast::FieldDecl f;
    f.name = null;
    f.type_expr = null;
    f.src_pos = (u32)7;
    if(!testing::expect_eq(f.src_pos, (u32)7, m)) { return -1; }
    return 0;
}

fn i32 enummember_value_expr_optional(arena::Arena* a, u8[] m) {
    ast::EnumMember em;
    em.name = null;
    em.value_expr = null;
    em.src_pos = (u32)0;
    if(!testing::expect_null((void*)em.value_expr, m)) { return -1; }
    return 0;
}

fn i32 fieldinitializer_name_optional(arena::Arena* a, u8[] m) {
    ast::FieldInitializer fi;
    fi.name = null;
    fi.value = null;
    fi.src_pos = (u32)0;
    if(!testing::expect_null((void*)fi.name, m)) { return -1; }
    return 0;
}

fn i32 switcharm_layout(arena::Arena* a, u8[] m) {
    ast::SwitchArm sa;
    sa.labels = {null, 0};
    sa.body = null;
    sa.src_pos = (u32)42;
    if(!testing::expect_eq(sa.labels.len, (u64)0, m)) { return -1; }
    if(!testing::expect_null((void*)sa.body, m)) { return -2; }
    if(!testing::expect_eq(sa.src_pos, (u32)42, m)) { return -3; }
    return 0;
}

// ----- AstFlags bit values -----

fn i32 astflags_are_distinct_bits(arena::Arena* a, u8[] m) {
    if(!testing::expect_eq((u16)ast::AstFlags::LValue,        (u16)1, m)) { return -1; }
    if(!testing::expect_eq((u16)ast::AstFlags::ConstExpr,     (u16)2, m)) { return -2; }
    if(!testing::expect_eq((u16)ast::AstFlags::HadError,      (u16)4, m)) { return -3; }
    if(!testing::expect_eq((u16)ast::AstFlags::Parenthesized, (u16)8, m)) { return -4; }
    return 0;
}

// ----- main -----

fn i32 main() {
    testing::init();
    u8[] suite = "AST Tests";

    // header / node layout
    testing::add(suite, "header_is_eight_bytes", &header_is_eight_bytes);
    testing::add(suite, "astnode_alias_matches_header", &astnode_alias_matches_header);
    testing::add(suite, "intlit_header_plus_u64", &intlit_header_plus_u64);
    testing::add(suite, "floatlit_header_plus_f64", &floatlit_header_plus_f64);
    testing::add(suite, "boollit_size", &boollit_size);
    testing::add(suite, "binop_layout", &binop_layout);
    testing::add(suite, "fndecl_layout_nonzero", &fndecl_layout_nonzero);
    testing::add(suite, "astflags_is_u16", &astflags_is_u16);
    testing::add(suite, "astkind_is_u16", &astkind_is_u16);

    // header roundtrip
    testing::add(suite, "intlit_roundtrip", &intlit_roundtrip);
    testing::add(suite, "binop_roundtrip", &binop_roundtrip);

    // list builder
    testing::add(suite, "list_init_starts_empty", &list_init_starts_empty);
    testing::add(suite, "list_push_one", &list_push_one);
    testing::add(suite, "list_push_many_within_cap", &list_push_many_within_cap);
    testing::add(suite, "list_push_grows_past_cap", &list_push_grows_past_cap);
    testing::add(suite, "list_push_a_thousand", &list_push_a_thousand);
    testing::add(suite, "list_push_null_is_noop", &list_push_null_is_noop);
    testing::add(suite, "list_freeze_preserves_len_and_ptr", &list_freeze_preserves_len_and_ptr);
    testing::add(suite, "list_freeze_indices_match", &list_freeze_indices_match);

    // kind range helpers
    testing::add(suite, "is_decl_first", &is_decl_first);
    testing::add(suite, "is_decl_last", &is_decl_last);
    testing::add(suite, "is_decl_middle", &is_decl_middle);
    testing::add(suite, "is_decl_rejects_sentinels", &is_decl_rejects_sentinels);
    testing::add(suite, "is_decl_rejects_other_ranges", &is_decl_rejects_other_ranges);
    testing::add(suite, "is_stmt_first", &is_stmt_first);
    testing::add(suite, "is_stmt_last", &is_stmt_last);
    testing::add(suite, "is_stmt_middle", &is_stmt_middle);
    testing::add(suite, "is_stmt_rejects_other_ranges", &is_stmt_rejects_other_ranges);
    testing::add(suite, "is_expr_first", &is_expr_first);
    testing::add(suite, "is_expr_last", &is_expr_last);
    testing::add(suite, "is_expr_middle", &is_expr_middle);
    testing::add(suite, "is_expr_rejects_other_ranges", &is_expr_rejects_other_ranges);
    testing::add(suite, "is_type_first", &is_type_first);
    testing::add(suite, "is_type_last", &is_type_last);
    testing::add(suite, "is_type_middle", &is_type_middle);
    testing::add(suite, "is_type_rejects_other_ranges", &is_type_rejects_other_ranges);
    testing::add(suite, "ranges_partition", &ranges_partition);

    testing::add(suite, "hdr_import", &hdr_import);
    testing::add(suite, "hdr_var_decl", &hdr_var_decl);
    testing::add(suite, "hdr_fn_decl", &hdr_fn_decl);
    testing::add(suite, "hdr_struct_decl", &hdr_struct_decl);
    testing::add(suite, "hdr_union_decl", &hdr_union_decl);
    testing::add(suite, "hdr_enum_decl", &hdr_enum_decl);
    testing::add(suite, "hdr_alias_decl", &hdr_alias_decl);
    testing::add(suite, "hdr_extern_block", &hdr_extern_block);
    testing::add(suite, "hdr_extern_fn_decl", &hdr_extern_fn_decl);
    testing::add(suite, "hdr_extern_struct_decl", &hdr_extern_struct_decl);
    testing::add(suite, "hdr_extern_union_decl", &hdr_extern_union_decl);
    testing::add(suite, "hdr_block", &hdr_block);
    testing::add(suite, "hdr_if", &hdr_if);
    testing::add(suite, "hdr_while", &hdr_while);
    testing::add(suite, "hdr_for", &hdr_for);
    testing::add(suite, "hdr_switch", &hdr_switch);
    testing::add(suite, "hdr_return", &hdr_return);
    testing::add(suite, "hdr_break", &hdr_break);
    testing::add(suite, "hdr_continue", &hdr_continue);
    testing::add(suite, "hdr_defer", &hdr_defer);
    testing::add(suite, "hdr_assignment", &hdr_assignment);
    testing::add(suite, "hdr_expr_stmt", &hdr_expr_stmt);
    testing::add(suite, "hdr_comprun", &hdr_comprun);
    testing::add(suite, "hdr_compinsert", &hdr_compinsert);
    testing::add(suite, "hdr_compsplice", &hdr_compsplice);
    testing::add(suite, "hdr_comperror", &hdr_comperror);
    testing::add(suite, "hdr_compwarning", &hdr_compwarning);
    testing::add(suite, "hdr_intlit", &hdr_intlit);
    testing::add(suite, "hdr_floatlit", &hdr_floatlit);
    testing::add(suite, "hdr_boollit", &hdr_boollit);
    testing::add(suite, "hdr_charlit", &hdr_charlit);
    testing::add(suite, "hdr_stringlit", &hdr_stringlit);
    testing::add(suite, "hdr_nulllit", &hdr_nulllit);
    testing::add(suite, "hdr_undefinedlit", &hdr_undefinedlit);
    testing::add(suite, "hdr_ident", &hdr_ident);
    testing::add(suite, "hdr_namespace_access", &hdr_namespace_access);
    testing::add(suite, "hdr_member_access", &hdr_member_access);
    testing::add(suite, "hdr_array_index", &hdr_array_index);
    testing::add(suite, "hdr_slice_range", &hdr_slice_range);
    testing::add(suite, "hdr_call", &hdr_call);
    testing::add(suite, "hdr_cast", &hdr_cast);
    testing::add(suite, "hdr_unary_op", &hdr_unary_op);
    testing::add(suite, "hdr_binary_op", &hdr_binary_op);
    testing::add(suite, "hdr_struct_lit", &hdr_struct_lit);
    testing::add(suite, "hdr_array_lit", &hdr_array_lit);
    testing::add(suite, "hdr_sizeof", &hdr_sizeof);
    testing::add(suite, "hdr_alignof", &hdr_alignof);
    testing::add(suite, "hdr_typeof", &hdr_typeof);
    testing::add(suite, "hdr_typeinfo", &hdr_typeinfo);
    testing::add(suite, "hdr_compcode", &hdr_compcode);
    testing::add(suite, "hdr_primitive_type", &hdr_primitive_type);
    testing::add(suite, "hdr_named_type", &hdr_named_type);
    testing::add(suite, "hdr_pointer_type", &hdr_pointer_type);
    testing::add(suite, "hdr_array_type", &hdr_array_type);
    testing::add(suite, "hdr_slice_type", &hdr_slice_type);
    testing::add(suite, "hdr_fnptr_type", &hdr_fnptr_type);
    testing::add(suite, "hdr_struct_type", &hdr_struct_type);
    testing::add(suite, "hdr_union_type", &hdr_union_type);

    testing::add(suite, "boollit_value_roundtrip", &boollit_value_roundtrip);
    testing::add(suite, "charlit_value_roundtrip", &charlit_value_roundtrip);
    testing::add(suite, "stringlit_fields_roundtrip", &stringlit_fields_roundtrip);
    testing::add(suite, "floatlit_value_roundtrip", &floatlit_value_roundtrip);
    testing::add(suite, "ifnode_else_branch_can_be_null", &ifnode_else_branch_can_be_null);
    testing::add(suite, "fornode_fields_can_be_null", &fornode_fields_can_be_null);
    testing::add(suite, "ptrtype_const_flag_roundtrip", &ptrtype_const_flag_roundtrip);
    testing::add(suite, "externfn_variadic_flag_roundtrip", &externfn_variadic_flag_roundtrip);
    testing::add(suite, "externstruct_opaque_flag_roundtrip", &externstruct_opaque_flag_roundtrip);
    testing::add(suite, "externunion_opaque_flag_roundtrip", &externunion_opaque_flag_roundtrip);

    testing::add(suite, "param_field_roundtrip", &param_field_roundtrip);
    testing::add(suite, "fielddecl_field_roundtrip", &fielddecl_field_roundtrip);
    testing::add(suite, "enummember_value_expr_optional", &enummember_value_expr_optional);
    testing::add(suite, "fieldinitializer_name_optional", &fieldinitializer_name_optional);
    testing::add(suite, "switcharm_layout", &switcharm_layout);

    testing::add(suite, "astflags_are_distinct_bits", &astflags_are_distinct_bits);

    return testing::run();
}
