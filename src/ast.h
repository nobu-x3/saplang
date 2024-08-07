#pragma once

#include <memory>
#include <vector>

#include "utils.h"

namespace saplang {
struct Decl : public IDumpable {
  SourceLocation location;
  std::string id;
  inline Decl(SourceLocation location, std::string_view id)
      : location(location), id(std::move(id)) {}
  virtual ~Decl() = default;
  void dump(size_t indent) const = 0;
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
  enum class NumberType { Integer, Real };
  NumberType type;
  std::string value;
  inline NumberLiteral(SourceLocation loc, NumberType type,
                       std::string_view value)
      : Expr(loc), type(type), value(value) {}

  void dump(size_t indent_level) const override;
};

struct DeclRefExpr : public Expr {
  std::string id;
  inline DeclRefExpr(SourceLocation loc, std::string_view id)
      : Expr(loc), id(id) {}

  void dump(size_t indent_level) const override;
};

struct CallExpr : public Expr {
  std::unique_ptr<DeclRefExpr> id;
  std::vector<std::unique_ptr<Expr>> args;
  inline CallExpr(SourceLocation loc, std::unique_ptr<DeclRefExpr>&& id,
                  std::vector<std::unique_ptr<Expr>>&& args)
      : Expr(loc), id(std::move(id)), args(std::move(args)) {}

  void dump(size_t indent_level) const override;
};

struct ReturnStmt : public Stmt {
  std::unique_ptr<Expr> expr;

  inline ReturnStmt(SourceLocation loc, std::unique_ptr<Expr>&& expr = nullptr)
      : Stmt(loc), expr(std::move(expr)) {}

  void dump(size_t indent_level) const override;
};

struct Block : public IDumpable {
  SourceLocation location;
  std::vector<std::unique_ptr<Stmt>> statements;
  inline Block(SourceLocation location,
               std::vector<std::unique_ptr<Stmt>>&& statements)
      : location(location), statements(std::move(statements)) {}
  void dump(size_t indent) const override;
};

struct Type {
  enum class Kind {
    Void,
    Pointer,
    i8,
    i16,
    i32,
    i64,
    u8,
    u16,
    u32,
    u64,
    f8,
    f16,
    f32,
    f64,
    Bool,
    Custom
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
  static Type builtin_f8() { return {Kind::f8, "f8"}; }
  static Type builtin_f16() { return {Kind::f16, "f16"}; }
  static Type builtin_f32() { return {Kind::f32, "f32"}; }
  static Type builtin_f64() { return {Kind::f64, "f64"}; }
  static Type builtin_bool() { return {Kind::Bool, "bool"}; }
  static Type custom(std::string_view name) { return {Kind::Custom, name}; }

private:
  Type(Kind kind, std::string_view name) : kind(kind), name(name) {};
};

struct ParamDecl : public Decl {
  Type type;
  inline ParamDecl(SourceLocation loc, std::string_view id, Type type)
      : Decl(loc, id), type(std::move(type)) {}

  void dump(size_t indent_level) const override;
};

struct FunctionDecl : public Decl {
  Type type;
  std::vector<std::unique_ptr<ParamDecl>> params;
  std::unique_ptr<Block> body;

  inline FunctionDecl(SourceLocation location, std::string_view id, Type type,
                      std::vector<std::unique_ptr<ParamDecl>>&& params,
                      std::unique_ptr<Block>&& body)
      : Decl(location, id), type(std::move(type)), params(std::move(params)),
        body(std::move(body)) {}

  void dump(size_t indent) const override;
};
} // namespace saplang
