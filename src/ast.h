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
  enum class Kind { Void, Pointer, Custom };
  Kind kind;
  std::string name;

  static Type builtin_void() { return {Kind::Void, "void"}; }
  static Type builtin_pointer() { return {Kind::Pointer, "*"}; }
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
