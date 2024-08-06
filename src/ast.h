#pragma once

#include <memory>

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

struct Block : public IDumpable {
  SourceLocation location;
  inline Block(SourceLocation location) : location(location) {}
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
  static Type builtin_bool() { return {Kind::Bool, "bool"}; }
  static Type custom(std::string_view name) { return {Kind::Custom, name}; }

private:
  Type(Kind kind, std::string_view name) : kind(kind), name(name) {};
};

struct FunctionDecl : public Decl {
  Type type;
  std::unique_ptr<Block> body;

  inline FunctionDecl(SourceLocation location, std::string_view id, Type type,
                      std::unique_ptr<Block> body)
      : Decl(location, id), type(std::move(type)), body(std::move(body)) {}
  void dump(size_t indent) const override;
};
} // namespace saplang
