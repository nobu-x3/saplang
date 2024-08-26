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
    i8,
    i16,
    i32,
    i64,
    u8,
    u16,
    u32,
    u64,
    Pointer,
    f32,
    f64,
    Custom,
    INTEGERS_START = i8,
    INTEGERS_END = u64,
    SIGNED_INT_START = i8,
    SIGNED_INT_END = i64,
    UNSIGNED_INT_START = u8,
    UNSIGNED_INT_END = u64,
    FLOATS_START = f32,
    FLOATS_END = f64,
  };
  Kind kind;
  std::string name;

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

private:
  Type(Kind kind, std::string_view name) : kind(kind), name(name) {};
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

struct ParamDecl : public Decl {
  Type type;
  inline ParamDecl(SourceLocation loc, std::string id, Type type)
      : Decl(loc, id), type(std::move(type)) {}

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

struct ResolvedExpr : public ResolvedStmt {
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

struct ResolvedDecl : public IDumpable {
  SourceLocation location;
  std::string id;
  Type type;
  inline ResolvedDecl(SourceLocation loc, std::string id, Type &&type)
      : location(loc), id(std::move(id)), type(std::move(type)) {}
  virtual ~ResolvedDecl() = default;
};

struct ResolvedNumberLiteral : public ResolvedExpr {
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
  inline ResolvedParamDecl(SourceLocation loc, std::string id, Type &&type)
      : ResolvedDecl(loc, std::move(id), std::move(type)) {}

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
} // namespace saplang
