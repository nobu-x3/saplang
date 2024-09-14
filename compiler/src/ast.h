#pragma once

#include <memory>
#include <vector>

#include "lexer.h"
#include "utils.h"

namespace saplang {

// @TODO: string literals

struct Type {
  enum class Kind {
    Void,
    Bool,
    u8,
    u16,
    u32,
    u64,
    i8,
    i16,
    i32,
    i64,
    Pointer,
    f32,
    f64,
    Custom,
    INTEGERS_START = u8,
    INTEGERS_END = i64,
    SIGNED_INT_START = i8,
    SIGNED_INT_END = i64,
    UNSIGNED_INT_START = u8,
    UNSIGNED_INT_END = u64,
    FLOATS_START = f32,
    FLOATS_END = f64,
  };
  Kind kind;
  std::string name;

  Type(const Type &) = default;
  Type &operator=(const Type &) = default;
  Type(Type &&) noexcept = default;
  Type &operator=(Type &&) noexcept = default;

  static Type builtin_void() { return {Kind::Void, "void"}; }
  static Type builtin_pointer() { return {Kind::Pointer, "*"}; }
  static Type builtin_i8() { return {Kind::i8, "i8"}; }
  static Type builtin_i16() { return {Kind::i16, "i16"}; }
  static Type builtin_i32() { return {Kind::i32, "i32"}; }
  static Type builtin_i64() { return {Kind::i64, "i64"}; }
  static Type builtin_u8() { return {Kind::u8, "u8"}; }
  static Type builtin_u16() { return {Kind::u16, "u16"}; }
  static Type builtin_u32() { return {Kind::u32, "u32"}; }
  static Type builtin_u64() { return {Kind::u64, "u64"}; }
  static Type builtin_f32() { return {Kind::f32, "f32"}; }
  static Type builtin_f64() { return {Kind::f64, "f64"}; }
  static Type builtin_bool() { return {Kind::Bool, "bool"}; }
  static Type custom(std::string_view name) { return {Kind::Custom, name}; }

  static inline bool is_builtin_type(Kind kind) { return kind != Kind::Custom; }
  // static Type get_builtin_type(Kind kind);

private:
  Type(Kind kind, std::string_view name) : kind(kind), name(name){};
};

#define DUMP_IMPL                                                              \
public:                                                                        \
  void dump_to_stream(std::stringstream &stream, size_t indent = 0)            \
      const override;                                                          \
  inline void dump(size_t indent = 0) const override {                         \
    std::stringstream stream{};                                                \
    dump_to_stream(stream, indent);                                            \
    std::cerr << stream.str();                                                 \
  }

union Value {
  std::int8_t i8;
  std::int16_t i16;
  std::int32_t i32;
  std::int64_t i64;
  std::uint8_t u8;
  std::uint16_t u16;
  std::uint32_t u32;
  std::uint64_t u64;
  float f32;
  double f64;
  bool b8;
};

struct ConstexprResult {
  Value value;
  Type::Kind kind;
};
struct Decl : public IDumpable {
  SourceLocation location;
  std::string id;
  inline Decl(SourceLocation location, std::string id)
      : location(location), id(std::move(id)) {}
  virtual ~Decl() = default;
};

struct Stmt : public IDumpable {
  SourceLocation location;
  inline Stmt(SourceLocation loc) : location(loc) {}
  virtual ~Stmt() = default;
};

struct Expr : public Stmt {
  inline Expr(SourceLocation loc) : Stmt(loc) {}
};

struct VarDecl : public Decl {
  Type type;
  std::unique_ptr<Expr> initializer;
  bool is_const;

  inline VarDecl(SourceLocation loc, std::string id, Type type,
                 std::unique_ptr<Expr> init, bool is_const)
      : Decl(loc, id), type(type), initializer(std::move(init)),
        is_const(is_const) {}

  DUMP_IMPL
};

struct DeclStmt : public Stmt {
  std::unique_ptr<VarDecl> var_decl;
  inline DeclStmt(SourceLocation loc, std::unique_ptr<VarDecl> var)
      : Stmt(loc), var_decl(std::move(var)) {}

  DUMP_IMPL
};

struct NumberLiteral : public Expr {
  enum class NumberType { Integer, Real, Bool };
  NumberType type;
  std::string value;
  inline NumberLiteral(SourceLocation loc, NumberType type, std::string value)
      : Expr(loc), type(type), value(std::move(value)) {}

  DUMP_IMPL
};

struct GroupingExpr : public Expr {
  std::unique_ptr<Expr> expr;
  inline explicit GroupingExpr(SourceLocation loc, std::unique_ptr<Expr> expr)
      : Expr(loc), expr(std::move(expr)) {}

  DUMP_IMPL
};

struct BinaryOperator : public Expr {
  std::unique_ptr<Expr> lhs;
  std::unique_ptr<Expr> rhs;
  TokenKind op;
  inline BinaryOperator(SourceLocation loc, std ::unique_ptr<Expr> lhs,
                        std::unique_ptr<Expr> rhs, TokenKind op)
      : Expr(loc), lhs(std::move(lhs)), rhs(std::move(rhs)), op(op) {}

  DUMP_IMPL
};

struct UnaryOperator : public Expr {
  std::unique_ptr<Expr> rhs;
  TokenKind op;
  inline UnaryOperator(SourceLocation loc, std::unique_ptr<Expr> rhs,
                       TokenKind op)
      : Expr(loc), rhs(std::move(rhs)), op(op) {}
  DUMP_IMPL
};

struct DeclRefExpr : public Expr {
  std::string id;
  inline DeclRefExpr(SourceLocation loc, std::string id)
      : Expr(loc), id(std::move(id)) {}

  DUMP_IMPL
};

struct Assignment : public Stmt {
  std::unique_ptr<DeclRefExpr> variable;
  std::unique_ptr<Expr> expr;

  inline Assignment(SourceLocation loc, std::unique_ptr<DeclRefExpr> var,
                    std::unique_ptr<Expr> expr)
      : Stmt(loc), variable(std::move(var)), expr(std::move(expr)) {}

  DUMP_IMPL
};

struct CallExpr : public Expr {
  std::unique_ptr<DeclRefExpr> id;
  std::vector<std::unique_ptr<Expr>> args;
  inline CallExpr(SourceLocation loc, std::unique_ptr<DeclRefExpr> &&id,
                  std::vector<std::unique_ptr<Expr>> &&args)
      : Expr(loc), id(std::move(id)), args(std::move(args)) {}

  DUMP_IMPL
};

struct ReturnStmt : public Stmt {
  std::unique_ptr<Expr> expr;

  inline ReturnStmt(SourceLocation loc, std::unique_ptr<Expr> &&expr = nullptr)
      : Stmt(loc), expr(std::move(expr)) {}

  DUMP_IMPL
};

struct Block : public IDumpable {
  SourceLocation location;
  std::vector<std::unique_ptr<Stmt>> statements;
  inline Block(SourceLocation location,
               std::vector<std::unique_ptr<Stmt>> &&statements)
      : location(location), statements(std::move(statements)) {}
  DUMP_IMPL
};

struct WhileStmt : public Stmt {
  std::unique_ptr<Expr> condition;
  std::unique_ptr<Block> body;

  inline WhileStmt(SourceLocation loc, std::unique_ptr<Expr> cond,
                   std::unique_ptr<Block> body)
      : Stmt(loc), condition(std::move(cond)), body(std::move(body)) {}

  DUMP_IMPL
};

struct IfStmt : public Stmt {
  std::unique_ptr<Expr> condition;
  std::unique_ptr<Block> true_block;
  std::unique_ptr<Block> false_block;

  inline IfStmt(SourceLocation location, std::unique_ptr<Expr> cond,
                std::unique_ptr<Block> true_block,
                std::unique_ptr<Block> false_block)
      : Stmt(location), condition(std::move(cond)),
        true_block(std::move(true_block)), false_block(std::move(false_block)) {
  }

  DUMP_IMPL
};

struct ParamDecl : public Decl {
  Type type;
  bool is_const;
  inline ParamDecl(SourceLocation loc, std::string id, Type type, bool is_const)
      : Decl(loc, id), type(std::move(type)), is_const(is_const) {}

  DUMP_IMPL
};

struct FunctionDecl : public Decl {
  Type type;
  std::vector<std::unique_ptr<ParamDecl>> params;
  std::unique_ptr<Block> body;

  inline FunctionDecl(SourceLocation location, std::string id, Type type,
                      std::vector<std::unique_ptr<ParamDecl>> &&params,
                      std::unique_ptr<Block> &&body)
      : Decl(location, std::move(id)), type(std::move(type)),
        params(std::move(params)), body(std::move(body)) {}
  DUMP_IMPL
};

struct ResolvedStmt : public IDumpable {
  SourceLocation location;
  inline ResolvedStmt(SourceLocation location) : location(location) {}
  virtual ~ResolvedStmt() = default;
};

struct ResolvedExpr
    : public ConstantValueContainer<ResolvedExpr, ConstexprResult>,
      public ResolvedStmt {
  Type type;
  inline ResolvedExpr(SourceLocation loc, Type type)
      : ResolvedStmt(loc), type(std::move(type)) {}
  virtual ~ResolvedExpr() = default;
};

struct ResolvedBlock : public IDumpable {
  SourceLocation location;
  std::vector<std::unique_ptr<ResolvedStmt>> statements;

  inline ResolvedBlock(SourceLocation loc,
                       std::vector<std::unique_ptr<ResolvedStmt>> &&statements)
      : location(loc), statements(std::move(statements)) {}

  virtual ~ResolvedBlock() = default;

  DUMP_IMPL
};

struct ResolvedWhileStmt : public ResolvedStmt {
  std::unique_ptr<ResolvedExpr> condition;
  std::unique_ptr<ResolvedBlock> body;

  inline ResolvedWhileStmt(SourceLocation location,
                           std::unique_ptr<ResolvedExpr> cond,
                           std::unique_ptr<ResolvedBlock> body)
      : ResolvedStmt(location), condition(std::move(cond)),
        body(std::move(body)) {}

  DUMP_IMPL
};

struct ResolvedIfStmt : public ResolvedStmt {
  std::unique_ptr<ResolvedExpr> condition;
  std::unique_ptr<ResolvedBlock> true_block;
  std::unique_ptr<ResolvedBlock> false_block;

  inline ResolvedIfStmt(SourceLocation loc,
                        std::unique_ptr<ResolvedExpr> condition,
                        std::unique_ptr<ResolvedBlock> true_block,
                        std::unique_ptr<ResolvedBlock> false_block)
      : ResolvedStmt(loc), condition(std::move(condition)),
        true_block(std::move(true_block)), false_block(std::move(false_block)) {
  }

  DUMP_IMPL
};

struct ResolvedDecl : public IDumpable {
  SourceLocation location;
  std::string id;
  Type type;
  inline ResolvedDecl(SourceLocation loc, std::string id, Type &&type)
      : location(loc), id(std::move(id)), type(std::move(type)) {}
  virtual ~ResolvedDecl() = default;
};

struct ResolvedVarDecl : public ResolvedDecl {
  std::unique_ptr<ResolvedExpr> initializer;
  bool is_const;
  inline ResolvedVarDecl(SourceLocation loc, std::string id, Type type,
                         std::unique_ptr<ResolvedExpr> init, bool is_const)
      : ResolvedDecl(loc, id, std::move(type)), initializer(std::move(init)),
        is_const(is_const) {}

  DUMP_IMPL
};

struct ResolvedDeclStmt : public ResolvedStmt {
  std::unique_ptr<ResolvedVarDecl> var_decl;
  inline ResolvedDeclStmt(SourceLocation loc,
                          std::unique_ptr<ResolvedVarDecl> decl)
      : ResolvedStmt(loc), var_decl(std::move(decl)) {}

  DUMP_IMPL
};

struct ResolvedNumberLiteral : public ResolvedExpr {
  Value value;

  explicit ResolvedNumberLiteral(SourceLocation loc,
                                 NumberLiteral::NumberType type,
                                 const std::string &value);
  DUMP_IMPL
};

struct ResolvedGroupingExpr : public ResolvedExpr {
  std::unique_ptr<ResolvedExpr> expr;
  inline explicit ResolvedGroupingExpr(SourceLocation loc,
                                       std::unique_ptr<ResolvedExpr> expr)
      : ResolvedExpr(loc, expr->type), expr(std::move(expr)) {}

  DUMP_IMPL
};

struct ResolvedBinaryOperator : public ResolvedExpr {
  std::unique_ptr<ResolvedExpr> lhs;
  std::unique_ptr<ResolvedExpr> rhs;
  TokenKind op;
  inline explicit ResolvedBinaryOperator(SourceLocation loc,
                                         std::unique_ptr<ResolvedExpr> lhs,
                                         std::unique_ptr<ResolvedExpr> rhs,
                                         TokenKind op)
      : ResolvedExpr(loc, lhs->type), lhs(std::move(lhs)), rhs(std::move(rhs)),
        op(op) {}

  DUMP_IMPL
};

struct ResolvedUnaryOperator : public ResolvedExpr {
  std::unique_ptr<ResolvedExpr> rhs;
  TokenKind op;
  inline explicit ResolvedUnaryOperator(SourceLocation loc,
                                        std::unique_ptr<ResolvedExpr> rhs,
                                        TokenKind op)
      : ResolvedExpr(loc, rhs->type), rhs(std::move(rhs)), op(op) {}
  DUMP_IMPL
};

struct ResolvedParamDecl : public ResolvedDecl {
  bool is_const;
  inline ResolvedParamDecl(SourceLocation loc, std::string id, Type &&type, bool is_const)
      : ResolvedDecl(loc, std::move(id), std::move(type)), is_const(is_const) {}

  DUMP_IMPL
};

struct ResolvedFuncDecl : public ResolvedDecl {
  std::vector<std::unique_ptr<ResolvedParamDecl>> params;
  std::unique_ptr<ResolvedBlock> body;

  inline ResolvedFuncDecl(
      SourceLocation loc, std::string id, Type type,
      std::vector<std::unique_ptr<ResolvedParamDecl>> &&params,
      std::unique_ptr<ResolvedBlock> body)
      : ResolvedDecl(loc, std::move(id), std::move(type)),
        params(std::move(params)), body(std::move(body)) {}

  DUMP_IMPL
};

struct ResolvedDeclRefExpr : public ResolvedExpr {
  const ResolvedDecl *decl;

  inline ResolvedDeclRefExpr(SourceLocation loc, const ResolvedDecl *decl)
      : ResolvedExpr(loc, decl->type), decl(decl) {}

  DUMP_IMPL
};

struct ResolvedCallExpr : public ResolvedExpr {
  const ResolvedFuncDecl *func_decl;
  std::vector<std::unique_ptr<ResolvedExpr>> args;

  inline ResolvedCallExpr(SourceLocation loc, const ResolvedFuncDecl *callee,
                          std::vector<std::unique_ptr<ResolvedExpr>> &&args)
      : ResolvedExpr(loc, callee->type), func_decl(callee),
        args(std::move(args)) {}

  DUMP_IMPL
};

struct ResolvedReturnStmt : public ResolvedStmt {
  std::unique_ptr<ResolvedExpr> expr;

  inline ResolvedReturnStmt(SourceLocation loc,
                            std::unique_ptr<ResolvedExpr> expr)
      : ResolvedStmt(loc), expr(std::move(expr)) {}

  DUMP_IMPL
};

struct ResolvedAssignment : public ResolvedStmt {
  std::unique_ptr<ResolvedDeclRefExpr> variable;
  std::unique_ptr<ResolvedExpr> expr;
  inline ResolvedAssignment(SourceLocation loc,
                            std::unique_ptr<ResolvedDeclRefExpr> var,
                            std::unique_ptr<ResolvedExpr> expr)
      : ResolvedStmt(loc), variable(std::move(var)), expr(std::move(expr)) {}

    DUMP_IMPL
};
} // namespace saplang
