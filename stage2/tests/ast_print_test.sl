import ast;
import ast_print;
import testing;
import arena;
import interner;
import io;
import symbol;
import sys;
import token;

const u64 BUCKET_COUNT = 64;

struct Ctx {
    arena::Arena*       arena;
    io::OutBuf          buf;
}

fn void setup(Ctx* c, arena::Arena* a) {
    interner::init(a, BUCKET_COUNT);
    c.arena = a;
    io::outbuf_init(&c.buf, a, 256);
}

fn bool check(Ctx* c, const u8[] expected, const u8[] msg) {
    return testing::expect_eq(io::outbuf_bytes(&c.buf), expected, msg);
}

// ---- node factories ----

fn ast::AstNode* bare(arena::Arena* a, ast::AstKind k) {
    ast::AstNode* n = arena::alloc(a, sizeof(ast::AstNode));
    n.h.kind = k;
    n.h.flags = (ast::AstFlags)0;
    n.h.src_pos = 0;
    return n;
}

fn ast::IntLitNode* int_lit(arena::Arena* a, u64 v) {
    ast::IntLitNode* n = arena::alloc(a, sizeof(ast::IntLitNode));
    n.h.kind = ast::AstKind::IntLit;
    n.h.flags = (ast::AstFlags)0;
    n.h.src_pos = 0;
    n.value = v;
    return n;
}

fn ast::FloatLitNode* float_lit(arena::Arena* a, f64 v) {
    ast::FloatLitNode* n = arena::alloc(a, sizeof(ast::FloatLitNode));
    n.h.kind = ast::AstKind::FloatLit;
    n.h.flags = (ast::AstFlags)0;
    n.h.src_pos = 0;
    n.value = v;
    return n;
}

fn ast::BoolLitNode* bool_lit(arena::Arena* a, bool v) {
    ast::BoolLitNode* n = arena::alloc(a, sizeof(ast::BoolLitNode));
    n.h.kind = ast::AstKind::BoolLit;
    n.h.flags = (ast::AstFlags)0;
    n.h.src_pos = 0;
    n.value = v;
    return n;
}

fn ast::CharLitNode* char_lit(arena::Arena* a, u8 v) {
    ast::CharLitNode* n = arena::alloc(a, sizeof(ast::CharLitNode));
    n.h.kind = ast::AstKind::CharLit;
    n.h.flags = (ast::AstFlags)0;
    n.h.src_pos = 0;
    n.value = v;
    return n;
}

fn ast::StringLitNode* string_lit(arena::Arena* a, u32 off, u32 len) {
    ast::StringLitNode* n = arena::alloc(a, sizeof(ast::StringLitNode));
    n.h.kind = ast::AstKind::StringLit;
    n.h.flags = (ast::AstFlags)0;
    n.h.src_pos = 0;
    n.pool_off = off;
    n.pool_len = len;
    return n;
}

fn ast::IdentNode* ident(arena::Arena* a, const u8[]name) {
    ast::IdentNode* n = arena::alloc(a, sizeof(ast::IdentNode));
    n.h.kind = ast::AstKind::Ident;
    n.h.flags = (ast::AstFlags)0;
    n.h.src_pos = 0;
    n.name = interner::intern(name);
    return n;
}

fn ast::TypePrimitiveNode* prim_type(arena::Arena* a, token::TokenKind k) {
    ast::TypePrimitiveNode* n = arena::alloc(a, sizeof(ast::TypePrimitiveNode));
    n.h.kind = ast::AstKind::PrimitiveType;
    n.h.flags = (ast::AstFlags)0;
    n.h.src_pos = 0;
    n.kind = k;
    return n;
}

fn ast::TypeNamedNode* named_type(arena::Arena* a, const u8[]ns, const u8[] name) {
    ast::TypeNamedNode* n = arena::alloc(a, sizeof(ast::TypeNamedNode));
    n.h.kind = ast::AstKind::NamedType;
    n.h.flags = (ast::AstFlags)0;
    n.h.src_pos = 0;
    if(ns.len > 0) { n.namespace = interner::intern(ns); }
    else           { n.namespace = null; }
    n.name = interner::intern(name);
    return n;
}

fn ast::BinaryOpNode* binop(arena::Arena* a, token::TokenKind op, ast::AstNode* l, ast::AstNode* r) {
    ast::BinaryOpNode* n = arena::alloc(a, sizeof(ast::BinaryOpNode));
    n.h.kind = ast::AstKind::BinaryOp;
    n.h.flags = (ast::AstFlags)0;
    n.h.src_pos = 0;
    n.op = op;
    n.lhs = l;
    n.rhs = r;
    return n;
}

fn ast::UnaryOpNode* unop(arena::Arena* a, token::TokenKind op, ast::AstNode* x) {
    ast::UnaryOpNode* n = arena::alloc(a, sizeof(ast::UnaryOpNode));
    n.h.kind = ast::AstKind::UnaryOp;
    n.h.flags = (ast::AstFlags)0;
    n.h.src_pos = 0;
    n.op = op;
    n.operand = x;
    return n;
}

fn ast::BlockNode* empty_block(arena::Arena* a) {
    ast::BlockNode* n = arena::alloc(a, sizeof(ast::BlockNode));
    n.h.kind = ast::AstKind::BlockStmt;
    n.h.flags = (ast::AstFlags)0;
    n.h.src_pos = 0;
    n.stmts = {null, 0};
    return n;
}

// ---- sentinel kinds ----

fn i32 print_invalid(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print(bare(&local, ast::AstKind::INVALID), 0, &c.buf);
    if(!check(&c, "Invalid\n", m)) { return -1; }
    return 0;
}

fn i32 print_error(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print(bare(&local, ast::AstKind::ERROR), 0, &c.buf);
    if(!check(&c, "Error\n", m)) { return -1; }
    return 0;
}

fn i32 print_null_node(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print(null, 0, &c.buf);
    if(!check(&c, "<null>\n", m)) { return -1; }
    return 0;
}

// ---- expression literals ----

fn i32 print_intlit(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print((ast::AstNode*)int_lit(&local, (u64)42), 0, &c.buf);
    if(!check(&c, "IntLit 42\n", m)) { return -1; }
    return 0;
}

fn i32 print_intlit_indented(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print((ast::AstNode*)int_lit(&local, (u64)5), 2, &c.buf);
    if(!check(&c, "    IntLit 5\n", m)) { return -1; }
    return 0;
}

fn i32 print_floatlit(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print((ast::AstNode*)float_lit(&local, 1.5), 0, &c.buf);
    if(!check(&c, "FloatLit 1.5\n", m)) { return -1; }
    return 0;
}

fn i32 print_boollit_true(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print((ast::AstNode*)bool_lit(&local, true), 0, &c.buf);
    if(!check(&c, "BoolLit true\n", m)) { return -1; }
    return 0;
}

fn i32 print_boollit_false(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print((ast::AstNode*)bool_lit(&local, false), 0, &c.buf);
    if(!check(&c, "BoolLit false\n", m)) { return -1; }
    return 0;
}

fn i32 print_charlit(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print((ast::AstNode*)char_lit(&local, 'A'), 0, &c.buf);
    if(!check(&c, "CharLit 65\n", m)) { return -1; }
    return 0;
}

fn i32 print_stringlit(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print((ast::AstNode*)string_lit(&local, (u32)16, (u32)5), 0, &c.buf);
    if(!check(&c, "StringLit off=16 len=5\n", m)) { return -1; }
    return 0;
}

fn i32 print_nulllit(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print(bare(&local, ast::AstKind::NullLit), 0, &c.buf);
    if(!check(&c, "NullLit\n", m)) { return -1; }
    return 0;
}

fn i32 print_undefinedlit(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print(bare(&local, ast::AstKind::UndefinedLit), 0, &c.buf);
    if(!check(&c, "UndefinedLit\n", m)) { return -1; }
    return 0;
}

// ---- identifier-shaped expressions ----

fn i32 print_ident(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print((ast::AstNode*)ident(&local, "foo"), 0, &c.buf);
    if(!check(&c, "Ident foo\n", m)) { return -1; }
    return 0;
}

fn i32 print_namespace_access(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::IdentNode* base = arena::alloc(&local, sizeof(ast::IdentNode));
    base.h.kind = ast::AstKind::Ident;
    base.name = interner::intern("io");
    ast::NamespaceAccessNode* n = arena::alloc(&local, sizeof(ast::NamespaceAccessNode));
    n.h.kind = ast::AstKind::NamespaceAccess;
    n.base = (ast::AstNode*)base;
    n.name = interner::intern("write");
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "NamespaceAccess io::write\n", m)) { return -1; }
    return 0;
}

fn i32 print_member_access(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::MemberAccessNode* n = arena::alloc(&local, sizeof(ast::MemberAccessNode));
    n.h.kind = ast::AstKind::MemberAccess;
    n.base = (ast::AstNode*)ident(&local, "v");
    n.field = interner::intern("len");
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "MemberAccess .len\n  Ident v\n", m)) { return -1; }
    return 0;
}

// ---- index / range / call / cast ----

fn i32 print_array_index(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::ArrayIndexNode* n = arena::alloc(&local, sizeof(ast::ArrayIndexNode));
    n.h.kind = ast::AstKind::ArrayIndex;
    n.base = (ast::AstNode*)ident(&local, "arr");
    n.index = (ast::AstNode*)int_lit(&local, (u64)3);
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "ArrayIndex\n  base:\n    Ident arr\n  index:\n    IntLit 3\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_slice_range(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::SliceRangeNode* n = arena::alloc(&local, sizeof(ast::SliceRangeNode));
    n.h.kind = ast::AstKind::SliceRange;
    n.base = (ast::AstNode*)ident(&local, "s");
    n.lo = (ast::AstNode*)int_lit(&local, (u64)1);
    n.hi = (ast::AstNode*)int_lit(&local, (u64)4);
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "SliceRange\n  base:\n    Ident s\n  lo:\n    IntLit 1\n  hi:\n    IntLit 4\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_call_no_args(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::CallNode* n = arena::alloc(&local, sizeof(ast::CallNode));
    n.h.kind = ast::AstKind::Call;
    n.callee = (ast::AstNode*)ident(&local, "f");
    n.args = {null, 0};
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "Call\n  callee:\n    Ident f\n  args\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_call_with_args(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::AstNode** args = arena::alloc(&local, sizeof(ast::AstNode*) * 2);
    args[0] = (ast::AstNode*)int_lit(&local, (u64)1);
    args[1] = (ast::AstNode*)int_lit(&local, (u64)2);
    ast::CallNode* n = arena::alloc(&local, sizeof(ast::CallNode));
    n.h.kind = ast::AstKind::Call;
    n.callee = (ast::AstNode*)ident(&local, "g");
    n.args = {args, 2};
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "Call\n  callee:\n    Ident g\n  args\n    IntLit 1\n    IntLit 2\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_cast(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::CastNode* n = arena::alloc(&local, sizeof(ast::CastNode));
    n.h.kind = ast::AstKind::Cast;
    n.target_type = (ast::AstNode*)prim_type(&local, token::TokenKind::I64);
    n.expr = (ast::AstNode*)ident(&local, "x");
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "Cast\n  type:\n    PrimitiveType 'i64'\n  expr:\n    Ident x\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

// ---- unary / binary ----

fn i32 print_unary_minus(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::UnaryOpNode* n = unop(&local, token::TokenKind::Minus, (ast::AstNode*)int_lit(&local, (u64)7));
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "UnaryOp '-'\n  IntLit 7\n", m)) { return -1; }
    return 0;
}

fn i32 print_binary_plus(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::BinaryOpNode* n = binop(&local, token::TokenKind::Plus,
        (ast::AstNode*)int_lit(&local, (u64)1),
        (ast::AstNode*)int_lit(&local, (u64)2));
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "BinaryOp '+'\n  IntLit 1\n  IntLit 2\n", m)) { return -1; }
    return 0;
}

fn i32 print_binary_eqeq(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::BinaryOpNode* n = binop(&local, token::TokenKind::EqEq,
        (ast::AstNode*)int_lit(&local, (u64)1),
        (ast::AstNode*)int_lit(&local, (u64)1));
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "BinaryOp '=='\n  IntLit 1\n  IntLit 1\n", m)) { return -1; }
    return 0;
}

// ---- struct / array literals ----

fn i32 print_struct_lit_positional(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::FieldInitializer* inits = arena::alloc(&local, sizeof(ast::FieldInitializer) * 1);
    inits[0].name = null;
    inits[0].value = (ast::AstNode*)int_lit(&local, (u64)9);
    inits[0].src_pos = 0;
    ast::StructLitNode* n = arena::alloc(&local, sizeof(ast::StructLitNode));
    n.h.kind = ast::AstKind::StructLit;
    n.inits = {inits, 1};
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "StructLit\n  positional\n    IntLit 9\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_struct_lit_named(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::FieldInitializer* inits = arena::alloc(&local, sizeof(ast::FieldInitializer) * 1);
    inits[0].name = interner::intern("x");
    inits[0].value = (ast::AstNode*)int_lit(&local, (u64)1);
    inits[0].src_pos = 0;
    ast::StructLitNode* n = arena::alloc(&local, sizeof(ast::StructLitNode));
    n.h.kind = ast::AstKind::StructLit;
    n.inits = {inits, 1};
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "StructLit\n  .x\n    IntLit 1\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_array_lit(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::AstNode** elems = arena::alloc(&local, sizeof(ast::AstNode*) * 2);
    elems[0] = (ast::AstNode*)int_lit(&local, (u64)1);
    elems[1] = (ast::AstNode*)int_lit(&local, (u64)2);
    ast::ArrayLitNode* n = arena::alloc(&local, sizeof(ast::ArrayLitNode));
    n.h.kind = ast::AstKind::ArrayLit;
    n.elems = {elems, 2};
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "ArrayLit\n  IntLit 1\n  IntLit 2\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

// ---- type-query operators ----

fn i32 print_sizeof(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::SizeofNode* n = arena::alloc(&local, sizeof(ast::SizeofNode));
    n.h.kind = ast::AstKind::Sizeof;
    n.arg = (ast::AstNode*)prim_type(&local, token::TokenKind::U64);
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "Sizeof\n  PrimitiveType 'u64'\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_alignof(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::AlignofNode* n = arena::alloc(&local, sizeof(ast::AlignofNode));
    n.h.kind = ast::AstKind::Alignof;
    n.arg = (ast::AstNode*)prim_type(&local, token::TokenKind::I32);
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "Alignof\n  PrimitiveType 'i32'\n", m)) { return -1; }
    return 0;
}

fn i32 print_typeof(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::TypeofNode* n = arena::alloc(&local, sizeof(ast::TypeofNode));
    n.h.kind = ast::AstKind::Typeof;
    n.expr = (ast::AstNode*)ident(&local, "x");
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "Typeof\n  Ident x\n", m)) { return -1; }
    return 0;
}

fn i32 print_type_info(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::TypeInfoNode* n = arena::alloc(&local, sizeof(ast::TypeInfoNode));
    n.h.kind = ast::AstKind::Type_info;
    n.arg = (ast::AstNode*)prim_type(&local, token::TokenKind::BOOL);
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "TypeInfo\n  PrimitiveType 'bool'\n", m)) { return -1; }
    return 0;
}

fn i32 print_compcode(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::CompCodeNode* n = arena::alloc(&local, sizeof(ast::CompCodeNode));
    n.h.kind = ast::AstKind::Compcode;
    n.body = (ast::AstNode*)empty_block(&local);
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "CompCode\n  Block\n", m)) { return -1; }
    return 0;
}

// ---- type expressions ----

fn i32 print_primitive_type(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print((ast::AstNode*)prim_type(&local, token::TokenKind::U32), 0, &c.buf);
    if(!check(&c, "PrimitiveType 'u32'\n", m)) { return -1; }
    return 0;
}

fn i32 print_named_type_unqualified(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print((ast::AstNode*)named_type(&local, "", "Foo"), 0, &c.buf);
    if(!check(&c, "NamedType Foo\n", m)) { return -1; }
    return 0;
}

fn i32 print_named_type_qualified(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print((ast::AstNode*)named_type(&local, "io", "File"), 0, &c.buf);
    if(!check(&c, "NamedType io::File\n", m)) { return -1; }
    return 0;
}

fn i32 print_pointer_type(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::TypePointerNode* n = arena::alloc(&local, sizeof(ast::TypePointerNode));
    n.h.kind = ast::AstKind::PointerType;
    n.pointee = (ast::AstNode*)prim_type(&local, token::TokenKind::I32);
    n.is_const = false;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "PointerType\n  PrimitiveType 'i32'\n", m)) { return -1; }
    return 0;
}

fn i32 print_pointer_type_const(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::TypePointerNode* n = arena::alloc(&local, sizeof(ast::TypePointerNode));
    n.h.kind = ast::AstKind::PointerType;
    n.pointee = (ast::AstNode*)prim_type(&local, token::TokenKind::U8);
    n.is_const = true;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "PointerType const\n  PrimitiveType 'u8'\n", m)) { return -1; }
    return 0;
}

fn i32 print_array_type(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::TypeArrayNode* n = arena::alloc(&local, sizeof(ast::TypeArrayNode));
    n.h.kind = ast::AstKind::ArrayType;
    n.element = (ast::AstNode*)prim_type(&local, token::TokenKind::I32);
    n.size_expr = (ast::AstNode*)int_lit(&local, (u64)8);
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "ArrayType\n  element:\n    PrimitiveType 'i32'\n  size:\n    IntLit 8\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_slice_type(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::TypeSliceNode* n = arena::alloc(&local, sizeof(ast::TypeSliceNode));
    n.h.kind = ast::AstKind::SliceType;
    n.element = (ast::AstNode*)prim_type(&local, token::TokenKind::U8);
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "SliceType\n  PrimitiveType 'u8'\n", m)) { return -1; }
    return 0;
}

fn i32 print_fnptr_type(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::AstNode** params = arena::alloc(&local, sizeof(ast::AstNode*) * 1);
    params[0] = (ast::AstNode*)prim_type(&local, token::TokenKind::I32);
    ast::TypeFnPtrNode* n = arena::alloc(&local, sizeof(ast::TypeFnPtrNode));
    n.h.kind = ast::AstKind::FnPtrType;
    n.return_type = (ast::AstNode*)prim_type(&local, token::TokenKind::VOID);
    n.param_types = {params, 1};
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "FnPtrType\n  return:\n    PrimitiveType 'void'\n  params\n    PrimitiveType 'i32'\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_struct_type(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::FieldDecl* fields = arena::alloc(&local, sizeof(ast::FieldDecl) * 1);
    fields[0].name = interner::intern("x");
    fields[0].type_expr = (ast::AstNode*)prim_type(&local, token::TokenKind::I32);
    fields[0].src_pos = 0;
    ast::TypeStructNode* n = arena::alloc(&local, sizeof(ast::TypeStructNode));
    n.h.kind = ast::AstKind::StructType;
    n.fields = {fields, 1};
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "StructType\n  Field x\n    PrimitiveType 'i32'\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_union_type(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::FieldDecl* fields = arena::alloc(&local, sizeof(ast::FieldDecl) * 1);
    fields[0].name = interner::intern("v");
    fields[0].type_expr = (ast::AstNode*)prim_type(&local, token::TokenKind::U64);
    fields[0].src_pos = 0;
    ast::TypeUnionNode* n = arena::alloc(&local, sizeof(ast::TypeUnionNode));
    n.h.kind = ast::AstKind::UnionType;
    n.fields = {fields, 1};
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "UnionType\n  Field v\n    PrimitiveType 'u64'\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

// ---- declarations ----

fn i32 print_import(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::ImportNode* n = arena::alloc(&local, sizeof(ast::ImportNode));
    n.h.kind = ast::AstKind::ImportDecl;
    n.module_name = interner::intern("io");
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "Import io\n", m)) { return -1; }
    return 0;
}

fn i32 print_var_decl(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::VarDeclNode* n = arena::alloc(&local, sizeof(ast::VarDeclNode));
    n.h.kind = ast::AstKind::VarDecl;
    n.name = interner::intern("x");
    n.type_expr = (ast::AstNode*)prim_type(&local, token::TokenKind::I32);
    n.init = (ast::AstNode*)int_lit(&local, (u64)7);
    n.is_const = false;
    n.is_exported = false;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "VarDecl x\n  type:\n    PrimitiveType 'i32'\n  init:\n    IntLit 7\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_var_decl_const_exported(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::VarDeclNode* n = arena::alloc(&local, sizeof(ast::VarDeclNode));
    n.h.kind = ast::AstKind::VarDecl;
    n.name = interner::intern("K");
    n.type_expr = (ast::AstNode*)prim_type(&local, token::TokenKind::U32);
    n.init = (ast::AstNode*)int_lit(&local, (u64)42);
    n.is_const = true;
    n.is_exported = true;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "VarDecl K const exported\n  type:\n    PrimitiveType 'u32'\n  init:\n    IntLit 42\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_var_decl_no_init(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::VarDeclNode* n = arena::alloc(&local, sizeof(ast::VarDeclNode));
    n.h.kind = ast::AstKind::VarDecl;
    n.name = interner::intern("x");
    n.type_expr = (ast::AstNode*)prim_type(&local, token::TokenKind::I32);
    n.init = null;
    n.is_const = false;
    n.is_exported = false;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "VarDecl x\n  type:\n    PrimitiveType 'i32'\n  init: <null>\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_fn_decl(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::Param* params = arena::alloc(&local, sizeof(ast::Param) * 1);
    params[0].name = interner::intern("a");
    params[0].type_expr = (ast::AstNode*)prim_type(&local, token::TokenKind::I32);
    params[0].is_const = false;
    params[0].is_comptime = false;
    params[0].src_pos = 0;
    ast::FnDeclNode* n = arena::alloc(&local, sizeof(ast::FnDeclNode));
    n.h.kind = ast::AstKind::FnDecl;
    n.name = interner::intern("id");
    n.return_type = (ast::AstNode*)prim_type(&local, token::TokenKind::I32);
    n.params = {params, 1};
    n.body = (ast::AstNode*)empty_block(&local);
    n.comptime_safe = ast::CompSafe::Unchecked;
    n.is_exported = true;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "FnDecl id exported\n  return:\n    PrimitiveType 'i32'\n  Param a\n    PrimitiveType 'i32'\n  body:\n    Block\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_struct_decl(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::FieldDecl* fields = arena::alloc(&local, sizeof(ast::FieldDecl) * 1);
    fields[0].name = interner::intern("x");
    fields[0].type_expr = (ast::AstNode*)prim_type(&local, token::TokenKind::I32);
    fields[0].src_pos = 0;
    ast::StructDeclNode* n = arena::alloc(&local, sizeof(ast::StructDeclNode));
    n.h.kind = ast::AstKind::StructDecl;
    n.name = interner::intern("Point");
    n.fields = {fields, 1};
    n.is_exported = false;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "StructDecl Point\n  Field x\n    PrimitiveType 'i32'\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_union_decl(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::FieldDecl* fields = arena::alloc(&local, sizeof(ast::FieldDecl) * 1);
    fields[0].name = interner::intern("i");
    fields[0].type_expr = (ast::AstNode*)prim_type(&local, token::TokenKind::I64);
    fields[0].src_pos = 0;
    ast::UnionDeclNode* n = arena::alloc(&local, sizeof(ast::UnionDeclNode));
    n.h.kind = ast::AstKind::UnionDecl;
    n.name = interner::intern("U");
    n.fields = {fields, 1};
    n.is_exported = false;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "UnionDecl U\n  Field i\n    PrimitiveType 'i64'\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_enum_decl(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::EnumMember* members = arena::alloc(&local, sizeof(ast::EnumMember) * 2);
    members[0].name = interner::intern("A");
    members[0].value_expr = null;
    members[0].src_pos = 0;
    members[1].name = interner::intern("B");
    members[1].value_expr = (ast::AstNode*)int_lit(&local, (u64)5);
    members[1].src_pos = 0;
    ast::EnumDeclNode* n = arena::alloc(&local, sizeof(ast::EnumDeclNode));
    n.h.kind = ast::AstKind::EnumDecl;
    n.name = interner::intern("E");
    n.base_type = (ast::AstNode*)prim_type(&local, token::TokenKind::U8);
    n.members = {members, 2};
    n.is_exported = false;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "EnumDecl E\n  base:\n    PrimitiveType 'u8'\n  Member A\n  Member B\n    IntLit 5\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_alias_decl(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::AliasDeclNode* n = arena::alloc(&local, sizeof(ast::AliasDeclNode));
    n.h.kind = ast::AstKind::AliasDecl;
    n.name = interner::intern("Bytes");
    n.target = (ast::AstNode*)prim_type(&local, token::TokenKind::U8);
    n.is_exported = false;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "AliasDecl Bytes\n  target:\n    PrimitiveType 'u8'\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_extern_block(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::ExternBlockNode* n = arena::alloc(&local, sizeof(ast::ExternBlockNode));
    n.h.kind = ast::AstKind::ExternBlock;
    n.lib_name = null;
    n.items = {null, 0};
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "ExternBlock c\n", m)) { return -1; }
    return 0;
}

fn i32 print_extern_fn_decl(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::ExternFnDeclNode* n = arena::alloc(&local, sizeof(ast::ExternFnDeclNode));
    n.h.kind = ast::AstKind::ExternFnDecl;
    n.name = interner::intern("printf");
    n.return_type = (ast::AstNode*)prim_type(&local, token::TokenKind::I32);
    n.params = {null, 0};
    n.is_variadic = true;
    n.is_exported = true;
    n.comptime_safe = ast::CompSafe::Unsafe;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "ExternFnDecl printf variadic exported\n  return:\n    PrimitiveType 'i32'\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_extern_struct_decl_opaque(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::ExternStructDeclNode* n = arena::alloc(&local, sizeof(ast::ExternStructDeclNode));
    n.h.kind = ast::AstKind::ExternStructDecl;
    n.name = interner::intern("FILE");
    n.fields = {null, 0};
    n.is_opaque = true;
    n.is_exported = false;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "ExternStructDecl FILE opaque\n", m)) { return -1; }
    return 0;
}

fn i32 print_extern_struct_decl_opaque_exported(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::ExternStructDeclNode* n = arena::alloc(&local, sizeof(ast::ExternStructDeclNode));
    n.h.kind = ast::AstKind::ExternStructDecl;
    n.name = interner::intern("FILE");
    n.fields = {null, 0};
    n.is_opaque = true;
    n.is_exported = true;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "ExternStructDecl FILE opaque exported\n", m)) { return -1; }
    return 0;
}

fn i32 print_extern_struct_decl_full(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::FieldDecl* fields = arena::alloc(&local, sizeof(ast::FieldDecl) * 1);
    fields[0].name = interner::intern("x");
    fields[0].type_expr = (ast::AstNode*)prim_type(&local, token::TokenKind::I32);
    fields[0].src_pos = 0;
    ast::ExternStructDeclNode* n = arena::alloc(&local, sizeof(ast::ExternStructDeclNode));
    n.h.kind = ast::AstKind::ExternStructDecl;
    n.name = interner::intern("Point");
    n.fields = {fields, 1};
    n.is_opaque = false;
    n.is_exported = false;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "ExternStructDecl Point\n  Field x\n    PrimitiveType 'i32'\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_extern_struct_decl_full_exported(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::FieldDecl* fields = arena::alloc(&local, sizeof(ast::FieldDecl) * 1);
    fields[0].name = interner::intern("x");
    fields[0].type_expr = (ast::AstNode*)prim_type(&local, token::TokenKind::I32);
    fields[0].src_pos = 0;
    ast::ExternStructDeclNode* n = arena::alloc(&local, sizeof(ast::ExternStructDeclNode));
    n.h.kind = ast::AstKind::ExternStructDecl;
    n.name = interner::intern("Point");
    n.fields = {fields, 1};
    n.is_opaque = false;
    n.is_exported = true;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "ExternStructDecl Point exported\n  Field x\n    PrimitiveType 'i32'\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_extern_union_decl_opaque(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::ExternUnionDeclNode* n = arena::alloc(&local, sizeof(ast::ExternUnionDeclNode));
    n.h.kind = ast::AstKind::ExternUnionDecl;
    n.name = interner::intern("Variant");
    n.fields = {null, 0};
    n.is_opaque = true;
    n.is_exported = false;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "ExternUnionDecl Variant opaque\n", m)) { return -1; }
    return 0;
}

fn i32 print_extern_union_decl_opaque_exported(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::ExternUnionDeclNode* n = arena::alloc(&local, sizeof(ast::ExternUnionDeclNode));
    n.h.kind = ast::AstKind::ExternUnionDecl;
    n.name = interner::intern("Variant");
    n.fields = {null, 0};
    n.is_opaque = true;
    n.is_exported = true;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "ExternUnionDecl Variant opaque exported\n", m)) { return -1; }
    return 0;
}

fn i32 print_extern_union_decl_full(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::FieldDecl* fields = arena::alloc(&local, sizeof(ast::FieldDecl) * 1);
    fields[0].name = interner::intern("i");
    fields[0].type_expr = (ast::AstNode*)prim_type(&local, token::TokenKind::I64);
    fields[0].src_pos = 0;
    ast::ExternUnionDeclNode* n = arena::alloc(&local, sizeof(ast::ExternUnionDeclNode));
    n.h.kind = ast::AstKind::ExternUnionDecl;
    n.name = interner::intern("U");
    n.fields = {fields, 1};
    n.is_opaque = false;
    n.is_exported = false;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "ExternUnionDecl U\n  Field i\n    PrimitiveType 'i64'\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_extern_union_decl_full_exported(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::FieldDecl* fields = arena::alloc(&local, sizeof(ast::FieldDecl) * 1);
    fields[0].name = interner::intern("i");
    fields[0].type_expr = (ast::AstNode*)prim_type(&local, token::TokenKind::I64);
    fields[0].src_pos = 0;
    ast::ExternUnionDeclNode* n = arena::alloc(&local, sizeof(ast::ExternUnionDeclNode));
    n.h.kind = ast::AstKind::ExternUnionDecl;
    n.name = interner::intern("U");
    n.fields = {fields, 1};
    n.is_opaque = false;
    n.is_exported = true;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "ExternUnionDecl U exported\n  Field i\n    PrimitiveType 'i64'\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

// ---- statements ----

fn i32 print_empty_block(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print((ast::AstNode*)empty_block(&local), 0, &c.buf);
    if(!check(&c, "Block\n", m)) { return -1; }
    return 0;
}

fn i32 print_block_with_stmts(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::AstNode** stmts = arena::alloc(&local, sizeof(ast::AstNode*) * 2);
    stmts[0] = (ast::AstNode*)int_lit(&local, (u64)1);
    stmts[1] = (ast::AstNode*)int_lit(&local, (u64)2);
    ast::BlockNode* n = arena::alloc(&local, sizeof(ast::BlockNode));
    n.h.kind = ast::AstKind::BlockStmt;
    n.stmts = {stmts, 2};
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "Block\n  IntLit 1\n  IntLit 2\n", m)) { return -1; }
    return 0;
}

fn i32 print_if_no_else(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::IfNode* n = arena::alloc(&local, sizeof(ast::IfNode));
    n.h.kind = ast::AstKind::IfStmt;
    n.cond = (ast::AstNode*)bool_lit(&local, true);
    n.then_block = (ast::AstNode*)empty_block(&local);
    n.else_block = null;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "If\n  cond:\n    BoolLit true\n  then:\n    Block\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_if_with_else(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::IfNode* n = arena::alloc(&local, sizeof(ast::IfNode));
    n.h.kind = ast::AstKind::IfStmt;
    n.cond = (ast::AstNode*)bool_lit(&local, false);
    n.then_block = (ast::AstNode*)empty_block(&local);
    n.else_block = (ast::AstNode*)empty_block(&local);
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "If\n  cond:\n    BoolLit false\n  then:\n    Block\n  else:\n    Block\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_while(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::WhileNode* n = arena::alloc(&local, sizeof(ast::WhileNode));
    n.h.kind = ast::AstKind::WhileStmt;
    n.cond = (ast::AstNode*)bool_lit(&local, true);
    n.body = (ast::AstNode*)empty_block(&local);
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "While\n  cond:\n    BoolLit true\n  body:\n    Block\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_for(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::ForNode* n = arena::alloc(&local, sizeof(ast::ForNode));
    n.h.kind = ast::AstKind::ForStmt;
    n.init = null;
    n.cond = (ast::AstNode*)bool_lit(&local, true);
    n.post = null;
    n.body = (ast::AstNode*)empty_block(&local);
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "For\n  init: <null>\n  cond:\n    BoolLit true\n  post: <null>\n  body:\n    Block\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_switch(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::SwitchArm* arms = arena::alloc(&local, sizeof(ast::SwitchArm) * 1);
    ast::AstNode** labels = arena::alloc(&local, sizeof(ast::AstNode*) * 1);
    labels[0] = (ast::AstNode*)int_lit(&local, (u64)1);
    arms[0].labels = {labels, 1};
    arms[0].body = (ast::AstNode*)empty_block(&local);
    arms[0].src_pos = 0;
    ast::SwitchNode* n = arena::alloc(&local, sizeof(ast::SwitchNode));
    n.h.kind = ast::AstKind::SwitchStmt;
    n.discriminant = (ast::AstNode*)ident(&local, "x");
    n.arms = {arms, 1};
    n.else_block = null;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    const u8[] e = "Switch\n  discriminant:\n    Ident x\n  Arm\n    labels\n      IntLit 1\n    body:\n      Block\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 print_return_with_expr(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::ReturnNode* n = arena::alloc(&local, sizeof(ast::ReturnNode));
    n.h.kind = ast::AstKind::ReturnStmt;
    n.expr = (ast::AstNode*)int_lit(&local, (u64)0);
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "Return\n  IntLit 0\n", m)) { return -1; }
    return 0;
}

fn i32 print_return_bare(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::ReturnNode* n = arena::alloc(&local, sizeof(ast::ReturnNode));
    n.h.kind = ast::AstKind::ReturnStmt;
    n.expr = null;
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "Return\n", m)) { return -1; }
    return 0;
}

fn i32 print_break(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print(bare(&local, ast::AstKind::BreakStmt), 0, &c.buf);
    if(!check(&c, "Break\n", m)) { return -1; }
    return 0;
}

fn i32 print_continue(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast_print::print(bare(&local, ast::AstKind::ContinueStmt), 0, &c.buf);
    if(!check(&c, "Continue\n", m)) { return -1; }
    return 0;
}

fn i32 print_defer(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::DeferNode* n = arena::alloc(&local, sizeof(ast::DeferNode));
    n.h.kind = ast::AstKind::DeferStmt;
    n.body = (ast::AstNode*)empty_block(&local);
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "Defer\n  Block\n", m)) { return -1; }
    return 0;
}

fn i32 print_assignment(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::AssignmentNode* n = arena::alloc(&local, sizeof(ast::AssignmentNode));
    n.h.kind = ast::AstKind::AssignmentStmt;
    n.op = token::TokenKind::PlusEq;
    n.lhs = (ast::AstNode*)ident(&local, "x");
    n.rhs = (ast::AstNode*)int_lit(&local, (u64)1);
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "Assign '+='\n  Ident x\n  IntLit 1\n", m)) { return -1; }
    return 0;
}

fn i32 print_expr_stmt(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::ExprStmtNode* n = arena::alloc(&local, sizeof(ast::ExprStmtNode));
    n.h.kind = ast::AstKind::ExprStmt;
    n.expr = (ast::AstNode*)int_lit(&local, (u64)1);
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "ExprStmt\n  IntLit 1\n", m)) { return -1; }
    return 0;
}

fn i32 print_comprun(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::CompRunNode* n = arena::alloc(&local, sizeof(ast::CompRunNode));
    n.h.kind = ast::AstKind::ComprunStmt;
    n.body = (ast::AstNode*)empty_block(&local);
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "Comprun\n  Block\n", m)) { return -1; }
    return 0;
}

fn i32 print_compinsert(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::CompInsertNode* n = arena::alloc(&local, sizeof(ast::CompInsertNode));
    n.h.kind = ast::AstKind::CompinsertStmt;
    n.source_expr = (ast::AstNode*)ident(&local, "code");
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "Compinsert\n  Ident code\n", m)) { return -1; }
    return 0;
}

fn i32 print_compsplice(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::CompSpliceNode* n = arena::alloc(&local, sizeof(ast::CompSpliceNode));
    n.h.kind = ast::AstKind::CompspliceStmt;
    n.code_expr = (ast::AstNode*)ident(&local, "code");
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "Compsplice\n  Ident code\n", m)) { return -1; }
    return 0;
}

fn i32 print_comperror(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::CompErrorNode* n = arena::alloc(&local, sizeof(ast::CompErrorNode));
    n.h.kind = ast::AstKind::ComperrorStmt;
    n.msg_expr = (ast::AstNode*)int_lit(&local, (u64)1);
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "Comperror\n  IntLit 1\n", m)) { return -1; }
    return 0;
}

fn i32 print_compwarning(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::CompWarningNode* n = arena::alloc(&local, sizeof(ast::CompWarningNode));
    n.h.kind = ast::AstKind::CompwarningStmt;
    n.msg_expr = (ast::AstNode*)int_lit(&local, (u64)1);
    ast_print::print((ast::AstNode*)n, 0, &c.buf);
    if(!check(&c, "Compwarning\n  IntLit 1\n", m)) { return -1; }
    return 0;
}

// ---- nesting / indent ----

fn i32 print_nested_binop(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    Ctx c; setup(&c, &local);
    ast::BinaryOpNode* inner = binop(&local, token::TokenKind::Star,
        (ast::AstNode*)int_lit(&local, (u64)2),
        (ast::AstNode*)int_lit(&local, (u64)3));
    ast::BinaryOpNode* outer = binop(&local, token::TokenKind::Plus,
        (ast::AstNode*)int_lit(&local, (u64)1),
        (ast::AstNode*)inner);
    ast_print::print((ast::AstNode*)outer, 0, &c.buf);
    const u8[] e = "BinaryOp '+'\n  IntLit 1\n  BinaryOp '*'\n    IntLit 2\n    IntLit 3\n";
    if(!check(&c, e, m)) { return -1; }
    return 0;
}

fn i32 main() {
    testing::init();
    const u8[] suite = "AST Print Tests";

    // sentinels
    testing::add(suite, "print_invalid", &print_invalid);
    testing::add(suite, "print_error", &print_error);
    testing::add(suite, "print_null_node", &print_null_node);

    // expression literals
    testing::add(suite, "print_intlit", &print_intlit);
    testing::add(suite, "print_intlit_indented", &print_intlit_indented);
    testing::add(suite, "print_floatlit", &print_floatlit);
    testing::add(suite, "print_boollit_true", &print_boollit_true);
    testing::add(suite, "print_boollit_false", &print_boollit_false);
    testing::add(suite, "print_charlit", &print_charlit);
    testing::add(suite, "print_stringlit", &print_stringlit);
    testing::add(suite, "print_nulllit", &print_nulllit);
    testing::add(suite, "print_undefinedlit", &print_undefinedlit);

    // identifier-shaped
    testing::add(suite, "print_ident", &print_ident);
    testing::add(suite, "print_namespace_access", &print_namespace_access);
    testing::add(suite, "print_member_access", &print_member_access);

    // index / range / call / cast
    testing::add(suite, "print_array_index", &print_array_index);
    testing::add(suite, "print_slice_range", &print_slice_range);
    testing::add(suite, "print_call_no_args", &print_call_no_args);
    testing::add(suite, "print_call_with_args", &print_call_with_args);
    testing::add(suite, "print_cast", &print_cast);

    // unary / binary
    testing::add(suite, "print_unary_minus", &print_unary_minus);
    testing::add(suite, "print_binary_plus", &print_binary_plus);
    testing::add(suite, "print_binary_eqeq", &print_binary_eqeq);

    // struct / array literals
    testing::add(suite, "print_struct_lit_positional", &print_struct_lit_positional);
    testing::add(suite, "print_struct_lit_named", &print_struct_lit_named);
    testing::add(suite, "print_array_lit", &print_array_lit);

    // type queries
    testing::add(suite, "print_sizeof", &print_sizeof);
    testing::add(suite, "print_alignof", &print_alignof);
    testing::add(suite, "print_typeof", &print_typeof);
    testing::add(suite, "print_type_info", &print_type_info);
    testing::add(suite, "print_compcode", &print_compcode);

    // type expressions
    testing::add(suite, "print_primitive_type", &print_primitive_type);
    testing::add(suite, "print_named_type_unqualified", &print_named_type_unqualified);
    testing::add(suite, "print_named_type_qualified", &print_named_type_qualified);
    testing::add(suite, "print_pointer_type", &print_pointer_type);
    testing::add(suite, "print_pointer_type_const", &print_pointer_type_const);
    testing::add(suite, "print_array_type", &print_array_type);
    testing::add(suite, "print_slice_type", &print_slice_type);
    testing::add(suite, "print_fnptr_type", &print_fnptr_type);
    testing::add(suite, "print_struct_type", &print_struct_type);
    testing::add(suite, "print_union_type", &print_union_type);

    // declarations
    testing::add(suite, "print_import", &print_import);
    testing::add(suite, "print_var_decl", &print_var_decl);
    testing::add(suite, "print_var_decl_const_exported", &print_var_decl_const_exported);
    testing::add(suite, "print_var_decl_no_init", &print_var_decl_no_init);
    testing::add(suite, "print_fn_decl", &print_fn_decl);
    testing::add(suite, "print_struct_decl", &print_struct_decl);
    testing::add(suite, "print_union_decl", &print_union_decl);
    testing::add(suite, "print_enum_decl", &print_enum_decl);
    testing::add(suite, "print_alias_decl", &print_alias_decl);
    testing::add(suite, "print_extern_block", &print_extern_block);
    testing::add(suite, "print_extern_fn_decl", &print_extern_fn_decl);
    testing::add(suite, "print_extern_struct_decl_opaque", &print_extern_struct_decl_opaque);
    testing::add(suite, "print_extern_struct_decl_opaque_exported", &print_extern_struct_decl_opaque_exported);
    testing::add(suite, "print_extern_struct_decl_full", &print_extern_struct_decl_full);
    testing::add(suite, "print_extern_struct_decl_full_exported", &print_extern_struct_decl_full_exported);
    testing::add(suite, "print_extern_union_decl_opaque", &print_extern_union_decl_opaque);
    testing::add(suite, "print_extern_union_decl_opaque_exported", &print_extern_union_decl_opaque_exported);
    testing::add(suite, "print_extern_union_decl_full", &print_extern_union_decl_full);
    testing::add(suite, "print_extern_union_decl_full_exported", &print_extern_union_decl_full_exported);

    // statements
    testing::add(suite, "print_empty_block", &print_empty_block);
    testing::add(suite, "print_block_with_stmts", &print_block_with_stmts);
    testing::add(suite, "print_if_no_else", &print_if_no_else);
    testing::add(suite, "print_if_with_else", &print_if_with_else);
    testing::add(suite, "print_while", &print_while);
    testing::add(suite, "print_for", &print_for);
    testing::add(suite, "print_switch", &print_switch);
    testing::add(suite, "print_return_with_expr", &print_return_with_expr);
    testing::add(suite, "print_return_bare", &print_return_bare);
    testing::add(suite, "print_break", &print_break);
    testing::add(suite, "print_continue", &print_continue);
    testing::add(suite, "print_defer", &print_defer);
    testing::add(suite, "print_assignment", &print_assignment);
    testing::add(suite, "print_expr_stmt", &print_expr_stmt);
    testing::add(suite, "print_comprun", &print_comprun);
    testing::add(suite, "print_compinsert", &print_compinsert);
    testing::add(suite, "print_compsplice", &print_compsplice);
    testing::add(suite, "print_comperror", &print_comperror);
    testing::add(suite, "print_compwarning", &print_compwarning);

    // nesting
    testing::add(suite, "print_nested_binop", &print_nested_binop);

    return testing::run();
}
