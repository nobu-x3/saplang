import symbol;
import token;
import sys;
import arena;

export struct AstHeader {
    AstKind     kind;                   // AstKind enum value
    AstFlags    flags;                  // sema-populated bitfield; see below
    u32         src_pos;                // byte offset into Module.source — line/col derived
    void*       ty;                     // types::Type*; void* breaks the ast<->types cycle
}

// abstract handle
// should cast like AstNode* n; if(n.h.kind == AstKind::BinaryOp) { BinaryOpNode* b = (BinaryOpNode*)n; }
export struct AstNode { AstHeader h; }

// LIST BUILDER ////////////////////////////////////////////////////////////////////////
export struct ListBuilder {
    AstNode*[]  items;
    u32         cap;
}

export fn void list_init(ListBuilder* b, arena::Arena* a, u32 initial_cap) {
    sys::memset(b, 0, sizeof(ListBuilder));
    b.items = {(AstNode**)arena::alloc(a, sizeof(AstNode*) * initial_cap), 0};
    b.cap = initial_cap;
}

export fn void list_push(ListBuilder* b, arena::Arena* a, AstNode* node) {
    if(!b || !a || !node) { return; }
    if(b.items.len + 1 > b.cap) {
        u64 new_cap = (u64)b.cap * 2;
        const u64 elem_size = sizeof(AstNode*);
        b.items = {(AstNode**)arena::realloc_grow(a, b.items.ptr, (u64)b.cap * elem_size, new_cap * elem_size), b.items.len};
        b.cap = (u32)new_cap;
    }
    b.items[b.items.len] = node;
    b.items.len += 1;
}

// Freezes to a slice for attachment to an AST node. The builder is dead after this.
export fn AstNode*[] list_freeze(ListBuilder* b) {
    AstNode*[] out;
    out.ptr = b.items.ptr;
    out.len = (u64)b.items.len;
    return out;
}

// decls /////////////////////////////////////////////////////////////////////////////////
export struct ImportNode {
    AstHeader h;
    symbol::Symbol*   module_name;
    bool      is_reexport;              // `export import foo;` — re-exports foo's exported symbols
}

export struct VarDeclNode {
    AstHeader           h;
    symbol::Symbol*     name;
    AstNode*            type_expr;                // AstKind::*Type
    AstNode*            init;                     // expression or AstKind::UndefinedLit or null
    bool                is_const;
    bool                is_exported;              // only meaningful at top-level
}

export struct FnDeclNode {
    AstHeader h;
    symbol::Symbol*   name;
    AstNode*  return_type;              // AstKind::*Type
    Param[]   params;
    AstNode*  body;                     // AstKind::BlockStmt
    // Cfg*      cfg;                   // cfg::Cfg* — null until CFG construction runs
    i8        comptime_safe;            // 0 = unchecked, 1 = safe, -1 = unsafe; set lazily by comptime
    bool      is_exported;
}

export struct StructDeclNode {
    AstHeader h;
    symbol::Symbol*   name;
    FieldDecl[] fields;
    bool      is_exported;
    // Provenance for monomorphization-produced anonymous structs
    // Null for source-declared structs; set when sema/comptime synthesizes a struct
    // from a comptime function returning Type.
    //FnDeclNode* synth_callee;
    //Value[]     synth_args;
}

export struct UnionDeclNode {
    AstHeader h;
    symbol::Symbol*   name;
    FieldDecl[] fields;
    bool      is_exported;
}

export struct EnumDeclNode {
    AstHeader h;
    symbol::Symbol*   name;
    AstNode*  base_type;                // AstKind::PrimitiveType, null = i32 default
    EnumMember[] members;
    bool      is_exported;
}

export struct AliasDeclNode {
    AstHeader h;
    symbol::Symbol*   name;
    AstNode*  target;                   // AstKind::*Type or any expression resolving to Type
    bool      is_exported;
}

export struct ExternBlockNode {
    AstHeader h;
    symbol::Symbol*   lib_name;         // null = "c" default
    AstNode*[] items;                   // ExternFnDeclNode / VarDeclNode / StructDeclNode / ...
}

export struct ExternFnDeclNode {
    AstHeader h;
    symbol::Symbol*   name;
    AstNode*  return_type;
    Param[]   params;
    bool      is_variadic;
    bool      is_exported;
    i8        comptime_safe;            // always -1 for extern; pre-set at sema time
}

export struct ExternStructDeclNode {
    AstHeader h;
    symbol::Symbol*   name;
    FieldDecl[] fields;                 // empty when is_opaque
    bool      is_opaque;
    bool      is_exported;
}

export struct ExternUnionDeclNode {
    AstHeader h;
    symbol::Symbol*   name;
    FieldDecl[] fields;                 // empty when is_opaque
    bool      is_opaque;
    bool      is_exported;
}

// stmts ///////////////////////////////////////////////////////////////////////////
export struct BlockNode {
    AstHeader h;
    AstNode*[] stmts;
}

export struct IfNode {
    AstHeader h;
    AstNode*  cond;
    AstNode*  then_block;               // AstKind::BlockStmt
    AstNode*  else_block;               // AstKind::BlockStmt or AstKind::IfStmt for else-if chain, or null
}

export struct WhileNode {
    AstHeader h;
    AstNode*  cond;
    AstNode*  body;                     // AstKind::BlockStmt
}

export struct ForNode {
    AstHeader h;
    AstNode*  init;                     // VarDecl or AssignmentNode or null
    AstNode*  cond;                     // expression or null
    AstNode*  post;                     // expression or assignment or null
    AstNode*  body;                     // AstKind::BlockStmt
}

export struct SwitchNode {
    AstHeader h;
    AstNode*  discriminant;
    SwitchArm[] arms;
    AstNode*  else_block;               // AstKind::BlockStmt or null
}

export struct ReturnNode {
    AstHeader h;
    AstNode*  expr;                     // null for "return;"
}

export struct BreakNode    { AstHeader h; }

export struct ContinueNode { AstHeader h; }

export struct DeferNode {
    AstHeader h;
    AstNode*  body;                     // AstKind::BlockStmt
}

export struct AssignmentNode {
    AstHeader           h;
    token::TokenKind    op;             // TokenKind::Eq | TokenKind::PlusEq | TokenKind::MinusEq | ...
    AstNode*            lhs;
    AstNode*            rhs;
}

export struct ExprStmtNode {
    AstHeader h;
    AstNode*  expr;
}

export struct CompRunNode {
    AstHeader h;
    AstNode*  body;                     // AstKind::BlockStmt
}

export struct CompInsertNode {
    AstHeader h;
    AstNode*  source_expr;              // evaluates to u8[] at comptime
}

export struct CompSpliceNode {
    AstHeader h;
    AstNode*  code_expr;                // evaluates to a Code value at comptime
}

export struct CompErrorNode {
    AstHeader h;
    AstNode*  msg_expr;
}

export struct CompWarningNode {
    AstHeader h;
    AstNode*  msg_expr;
}

// expressions /////////////////////////////////////////////////////////////////
export struct IntLitNode    { AstHeader h; u64 value; }

export struct FloatLitNode  { AstHeader h; f64 value; }

export struct BoolLitNode   { AstHeader h; bool value; }

export struct CharLitNode   { AstHeader h; u8  value; }

export struct StringLitNode {
    AstHeader h;
    u32 pool_off;                       // index into Module.literal_pool
    u32 pool_len;
}

export struct NullLitNode      { AstHeader h; }

export struct UndefinedLitNode { AstHeader h; }

export struct IdentNode {
    AstHeader h;
    symbol::Symbol*   name;
    //Decl*     resolved;                 // sema::Decl* — null until sema pass C
}

export struct NamespaceAccessNode {
    AstHeader h;
    AstNode*  base;                     // Ident or another NamespaceAccess
    symbol::Symbol*   name;
    //Decl*     resolved;                 // sema::Decl* — null until sema pass C
}

export struct MemberAccessNode {
    AstHeader h;
    AstNode*  base;
    symbol::Symbol*   field;
    //Decl*     resolved;                 // sema::Decl* (DECL_FIELD) — null until sema pass C
}

export struct ArrayIndexNode {
    AstHeader h;
    AstNode*  base;
    AstNode*  index;
}

export struct SliceRangeNode {
    AstHeader h;
    AstNode*  base;
    AstNode*  lo;
    AstNode*  hi;
}

export struct CallNode {
    AstHeader h;
    AstNode*  callee;
    AstNode*[] args;
}

export struct CastNode {
    AstHeader h;
    AstNode*  target_type;              // AstKind::*Type
    AstNode*  expr;
}

export struct UnaryOpNode {
    AstHeader           h;
    token::TokenKind    op;             // TokenKind::Minus | TokenKind::Bang | TokenKind::Tilde | TokenKind::Amp | TokenKind::Star
    AstNode*            operand;
}

export struct BinaryOpNode {
    AstHeader           h;
    token::TokenKind    op;             // TokenKind::Plus | TokenKind::Minus | TokenKind::Star | ... | TokenKind::AmpAmp
    AstNode*            lhs;
    AstNode*            rhs;
}

export struct StructLitNode {
    AstHeader h;
    FieldInitializer[] inits;
}

export struct ArrayLitNode {
    AstHeader h;
    AstNode*[] elems;
}

export struct SizeofNode {
    AstHeader h;
    AstNode*  arg;                      // AstKind::*Type or any expression (typeof'd internally)
}

export struct AlignofNode {
    AstHeader h;
    AstNode*  arg;
}

export struct TypeofNode {
    AstHeader h;
    AstNode*  expr;
}

export struct TypeInfoNode {
    AstHeader h;
    AstNode*  arg;                      // AstKind::*Type
}

export struct CompCodeNode {
    AstHeader h;
    AstNode*  body;                     // AstKind::BlockStmt
}

// type expressions /////////////////////////////////////////////////////////////
export struct TypePrimitiveNode {
    AstHeader           h;
    token::TokenKind    kind;           // TokenKind::I32 | TokenKind::BOOL | TokenKind::TYPE | ... (TokenKind reused)
}

export struct TypeNamedNode {
    AstHeader h;
    symbol::Symbol*   namespace;        // null if unqualified
    symbol::Symbol*   name;
}

export struct TypePointerNode {
    AstHeader h;
    AstNode*  pointee;
    bool      is_const;
}

export struct TypeArrayNode {
    AstHeader h;
    AstNode*  element;
    AstNode*  size_expr;                // any expression evaluating to comptime u64
}

export struct TypeSliceNode {
    AstHeader h;
    AstNode*  element;
}

export struct TypeFnPtrNode {
    AstHeader h;
    AstNode*  return_type;
    AstNode*[] param_types;
}

export struct TypeStructNode {          // anonymous struct { ... } at type position
    AstHeader h;
    FieldDecl[] fields;
}

export struct TypeUnionNode {           // anonymous union { ... } at type position
    AstHeader h;
    FieldDecl[] fields;
}

// auxiliary ///////////////////////////////////////////////////////////////////
export struct Param {
    symbol::Symbol*   name;
    AstNode*  type_expr;                // AstKind::*Type
    void*     resolved_type;            // types::Type*; filled by sema
    bool      is_const;
    bool      is_comptime;
    u32       src_pos;
}

export struct FieldDecl {
    symbol::Symbol*   name;
    AstNode*  type_expr;                // AstKind::*Type
    void*     resolved_type;            // types::Type*; filled by sema
    u32       src_pos;
}

export struct EnumMember {
    symbol::Symbol*   name;
    AstNode*  value_expr;               // optional explicit value (literal, identifier, or null)
    u32       src_pos;
}

export struct FieldInitializer {
    symbol::Symbol*   name;             // null = positional, non-null = .name = expr
    AstNode*  value;
    u32       src_pos;
}

export struct SwitchArm {
    AstNode*[] labels;                  // case label expressions; multiple = fallthrough chain
    AstNode*   body;                    // AstKind::BlockStmt or null for chained case (next arm's body runs)
    u32        src_pos;
}

export enum AstFlags : u16 {
    LValue = 1,
    ConstExpr = 2,
    HadError = 4,
    Parenthesized = 8
}

export enum AstKind : u16 {
// sentinels at range boundaries — bumped automatically if a range grows
INVALID = 0,
ERROR,       // placeholder for any failed parse; carries only a header

// declarations  [DECL_FIRST..DECL_LAST]
ImportDecl,
VarDecl,                // also legal as a statement
FnDecl,
StructDecl,
UnionDecl,
EnumDecl,
AliasDecl,
ExternBlock,
ExternFnDecl,           // fn decl inside extern { ... } with no body
ExternStructDecl,       // struct decl inside extern { ... }: opaque or full
ExternUnionDecl,        // union decl inside extern { ... }: opaque or full
DECL_FIRST = ImportDecl,
DECL_LAST = ExternUnionDecl,

// statements   [STMT_FIRST..STMT_LAST]
BlockStmt,
IfStmt,
WhileStmt,
ForStmt,
SwitchStmt,
ReturnStmt,
BreakStmt,
ContinueStmt,
DeferStmt,
AssignmentStmt,
ExprStmt,
ComprunStmt,
CompinsertStmt,
CompspliceStmt,
ComperrorStmt,
CompwarningStmt,
STMT_FIRST = BlockStmt,
STMT_LAST = CompwarningStmt,

// expressions  [EXPR_FIRST..EXPR_LAST]
IntLit,
FloatLit,
BoolLit,
CharLit,
StringLit,
NullLit,
UndefinedLit,
Ident,
NamespaceAccess,        // a::b — left-associative chain (base may be NamespaceAccess for a::b::c)
MemberAccess,           // x.field
ArrayIndex,             // a[i]
SliceRange,             // a[lo..hi]
Call,
Cast,
UnaryOp,
BinaryOp,
StructLit,              // also used for slice literal { .ptr=, .len= }
ArrayLit,
Sizeof,
Alignof,
Typeof,
Type_info,
Compcode,               // { ... } block captured as a Code value
EXPR_FIRST = IntLit,
EXPR_LAST = Compcode,

// type expressions  [TYPE_FIRST..TYPE_LAST]
PrimitiveType,          // i32, bool, void, Type, ...
NamedType,              // qualified name resolving to a user type or alias
PointerType,            // T*
ArrayType,              // T[N]
SliceType,              // T[]
FnPtrType,              // fn* T(args)
StructType,             // anonymous struct { ... } at type position
UnionType,              // anonymous union { ... } at type position
TYPE_FIRST = PrimitiveType,
TYPE_LAST = UnionType,
}

export fn bool is_decl(u16 k) { return k >= AstKind::DECL_FIRST && k <= AstKind::DECL_LAST; }
export fn bool is_stmt(u16 k) { return k >= AstKind::STMT_FIRST && k <= AstKind::STMT_LAST; }
export fn bool is_expr(u16 k) { return k >= AstKind::EXPR_FIRST && k <= AstKind::EXPR_LAST; }
export fn bool is_type(u16 k) { return k >= AstKind::TYPE_FIRST && k <= AstKind::TYPE_LAST; }
