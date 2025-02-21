#pragma once

#include <map>
#include <memory>
#include <set>
#include <vector>

#include "lexer.h"
#include "utils.h"

#define uint unsigned int
#define PLATFORM_PTR_SIZE 8
#define PLATFORM_PTR_ALIGNMENT alignof(signed long)

namespace saplang {

struct ArrayData {
  int dimension_count = 0;
  std::vector<uint> dimensions{};
  inline bool operator==(const ArrayData &other) const {
    bool is_dim_count_same = dimension_count == other.dimension_count;
    if (!is_dim_count_same)
      return false;
    for (uint i = 0; i < dimension_count; ++i) {
      if (dimensions[i] != other.dimensions[i])
        return false;
    }
    return true;
  }
};

#define DUMP_IMPL                                                                                                                                              \
public:                                                                                                                                                        \
  void dump_to_stream(std::stringstream &stream, size_t indent = 0) const override;                                                                            \
  inline void dump(size_t indent = 0) const override {                                                                                                         \
    std::stringstream stream{};                                                                                                                                \
    dump_to_stream(stream, indent);                                                                                                                            \
    std::cerr << stream.str();                                                                                                                                 \
  }

struct Type;
using FunctionSignature = std::pair<std::vector<Type>, bool>;

struct TypeInfo {
  unsigned long total_size;
  unsigned long alignment;
  std::vector<unsigned long> field_sizes;
  std::vector<std::string> field_names;

  void dump_to_stream(std ::stringstream &stream, size_t indent = 0) const;
  inline void dump(size_t indent = 0) const {
    std ::stringstream stream{};
    dump_to_stream(stream, indent);
    std ::cerr << stream.str();
  }
};

struct Type : public IDumpable {
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
    f32,
    f64,
    Custom,
    FnPtr,
    Placeholder,
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
  uint pointer_depth;
  uint dereference_counts = 0;
  // If type has equal pointer_depth and array_data->dimension_count after
  // casting, it's array decay
  std::optional<ArrayData> array_data;
  std::optional<FunctionSignature> fn_ptr_signature;
  std::vector<Type> instance_types;
  Type(const Type &) = default;
  Type &operator=(const Type &) = default;
  Type(Type &&) noexcept = default;
  Type &operator=(Type &&) noexcept = default;

  std::string demangled_name() const {
    std::string demangled_name;
    if (instance_types.size()) {
      demangled_name = "__";
    }
    demangled_name += name;
    for (auto &&type : instance_types) {
      demangled_name += type.demangled_name();
    }
    return demangled_name;
  }

  std::string full_name() const {
    std::string full_name{name};
    if (instance_types.size()) {
      full_name += '<' + instance_types.front().name;
      for (int i = 1; i < instance_types.size(); ++i) {
        full_name += ',' + instance_types[i].name;
      }
      full_name += '>';
    }
    for (int i = 0; i < pointer_depth; ++i) {
      full_name += '*';
    }
    return full_name;
  }

  static Type builtin_void(uint pointer_depth) { return {Kind::Void, "void", pointer_depth}; }

  static Type builtin_i8(uint pointer_depth, std::optional<ArrayData> array_data = {}) { return {Kind::i8, "i8", pointer_depth, array_data}; }

  static Type builtin_i16(uint pointer_depth, std::optional<ArrayData> array_data = {}) { return {Kind::i16, "i16", pointer_depth, std::move(array_data)}; }

  static Type builtin_i32(uint pointer_depth, std::optional<ArrayData> array_data = {}) { return {Kind::i32, "i32", pointer_depth, std::move(array_data)}; }

  static Type builtin_i64(uint pointer_depth, std::optional<ArrayData> array_data = {}) { return {Kind::i64, "i64", pointer_depth, std::move(array_data)}; }

  static Type builtin_u8(uint pointer_depth, std::optional<ArrayData> array_data = {}) { return {Kind::u8, "u8", pointer_depth, std::move(array_data)}; }

  static Type builtin_u16(uint pointer_depth, std::optional<ArrayData> array_data = {}) { return {Kind::u16, "u16", pointer_depth, std::move(array_data)}; }

  static Type builtin_u32(uint pointer_depth, std::optional<ArrayData> array_data = {}) { return {Kind::u32, "u32", pointer_depth, std::move(array_data)}; }

  static Type builtin_u64(uint pointer_depth, std::optional<ArrayData> array_data = {}) { return {Kind::u64, "u64", pointer_depth, std::move(array_data)}; }

  static Type builtin_f32(uint pointer_depth, std::optional<ArrayData> array_data = {}) { return {Kind::f32, "f32", pointer_depth, std::move(array_data)}; }

  static Type builtin_f64(uint pointer_depth, std::optional<ArrayData> array_data = {}) { return {Kind::f64, "f64", pointer_depth, std::move(array_data)}; }

  static Type builtin_bool(uint pointer_depth, std::optional<ArrayData> array_data = {}) { return {Kind::Bool, "bool", pointer_depth, std::move(array_data)}; }

  static Type custom(std::string name, uint pointer_depth, std::optional<ArrayData> array_data = {}, std::vector<Type> instance_types = {}) {
    return {Kind::Custom, std::move(name), pointer_depth, std::move(array_data), std::nullopt, std::move(instance_types)};
  }

  static Type fn_ptr(uint pointer_depth, std::optional<FunctionSignature> fn_signature = {}) {
    return {Kind::FnPtr, "fn", pointer_depth, std::nullopt, std::move(fn_signature)};
  }

  static Type placeholder(std::string name, uint pointer_depth, std::optional<ArrayData> array_data = {}, std::optional<FunctionSignature> fn_signature = {}) {
    return {Kind::Placeholder, std::move(name), pointer_depth, std::move(array_data), std::move(fn_signature)};
  }

  static inline bool is_builtin_type(Kind kind) { return kind != Kind::Custom; }

  bool operator==(const Type &other) const;

  void replace_placeholders(const std::vector<std::string> &placeholders, const std::vector<Type> types);

  // @NOTE: does not insert '\n' when done
  DUMP_IMPL
private:
  inline Type(Kind kind, std::string name, uint pointer_depth, std::optional<ArrayData> array_data = std::nullopt,
              std::optional<FunctionSignature> fn_signature = std::nullopt, std::vector<Type> instance_types = {})
      : kind(kind), name(std::move(name)), pointer_depth(pointer_depth), array_data(std::move(array_data)), fn_ptr_signature(std::move(fn_signature)),
        instance_types(std::move(instance_types)) {}
};

// decreases array dimension by dearray_count, removes first dimension and
// returns it's value
int de_array_type(Type &type, int dearray_count);

inline bool is_same_array_decay(const Type &a, const Type &b) {
  if (a.kind != b.kind)
    return false;
  if (a.array_data && !b.array_data) {
    if (b.pointer_depth == a.array_data->dimension_count && b.pointer_depth == 1)
      return true;
    return false;
  }
  return false;
}

inline bool is_same_type(const Type &a, const Type &b) {
  return a.kind == b.kind &&
         ((a.pointer_depth - a.dereference_counts == b.pointer_depth - b.dereference_counts && a.array_data == b.array_data) || is_same_array_decay(a, b));
}

inline bool is_signed(Type::Kind kind) {
  if (kind >= Type::Kind::SIGNED_INT_START && kind <= Type::Kind::SIGNED_INT_END)
    return true;
  return false;
}

inline bool is_unsigned(Type::Kind kind) {
  if (kind >= Type::Kind::UNSIGNED_INT_START && kind <= Type::Kind::UNSIGNED_INT_END)
    return true;
  return false;
}

inline bool is_float(Type::Kind kind) {
  if (kind >= Type::Kind::FLOATS_START && kind <= Type::Kind::FLOATS_END)
    return true;
  return false;
}

size_t get_type_size(Type::Kind kind);

bool does_type_have_associated_size(Type::Kind kind);

size_t platform_array_index_size();

size_t platform_ptr_size();

Type platform_ptr_type();

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
  std::string module;
  std::string lib;
  std::string og_name;
  bool is_exported;
  inline Decl(SourceLocation location, std::string id, std::string module, std::string lib = "", std::string og_name = "", bool is_exported = false)
      : location(location), id(std::move(id)), module(std::move(module)), lib(std::move(lib)), og_name(std::move(og_name)), is_exported(is_exported) {}
  virtual ~Decl() = default;
  virtual bool replace_placeholders(const std::vector<std::string> &placeholders, const std::vector<Type> &instance_types) { return true; };
};

struct Stmt : public IDumpable {
  SourceLocation location;
  inline Stmt(SourceLocation loc) : location(loc) {}
  virtual ~Stmt() = default;
  virtual bool replace_placeholders(const std::vector<std::string> &placeholders, const std::vector<Type> &instance_types) { return true; }
  virtual std::unique_ptr<Stmt> clone() const = 0;
};

struct Expr : public Stmt {
  inline Expr(SourceLocation loc) : Stmt(loc) {}
};

struct Module : public IDumpable {
  std::string name;
  std::string path;
  std::vector<std::unique_ptr<Decl>> declarations;
  std::vector<std::string> imports;
  // Should not be used in further stages
  std::set<std::string> libraries;
  inline Module(std::string module_name, std::string path, std::vector<std::unique_ptr<Decl>> declarations, std::vector<std::string> imports,
                std::set<std::string> libraries)
      : name(std::move(module_name)), path(std::move(path)), declarations(std::move(declarations)), imports(std::move(imports)),
        libraries(std::move(libraries)) {}
  DUMP_IMPL;
};

struct SizeofExpr : public Expr {
  Type type;
  bool is_ptr;
  unsigned long array_element_count;
  inline explicit SizeofExpr(SourceLocation loc, Type type, bool is_ptr, unsigned long array_element_count)
      : Expr(loc), type(std::move(type)), is_ptr(is_ptr), array_element_count(array_element_count) {}
  DUMP_IMPL;
  std::unique_ptr<Stmt> clone() const override { return std::make_unique<SizeofExpr>(location, type, is_ptr, array_element_count); };
  bool replace_placeholders(const std::vector<std::string> &placeholders, const std::vector<Type> &instance_types) override;
};

struct AlignofExpr : public Expr {
  Type type;
  bool is_ptr;
  inline explicit AlignofExpr(SourceLocation loc, Type type, bool is_ptr) : Expr(loc), type(std::move(type)), is_ptr(is_ptr) {}
  DUMP_IMPL;
  std::unique_ptr<Stmt> clone() const override { return std::make_unique<AlignofExpr>(location, type, is_ptr); };
  bool replace_placeholders(const std::vector<std::string> &placeholders, const std::vector<Type> &instance_types) override;
};

struct NullExpr : public Expr {
  inline NullExpr(SourceLocation loc) : Expr(loc) {}
  DUMP_IMPL;
  std::unique_ptr<Stmt> clone() const override { return std::make_unique<NullExpr>(location); };
};

struct VarDecl : public Decl {
  Type type;
  std::unique_ptr<Expr> initializer;
  bool is_const;
  inline VarDecl(SourceLocation loc, std::string id, Type type, std::string module, std::unique_ptr<Expr> init, bool is_const, std::string lib = "",
                 std::string og_name = "", bool is_exported = false)
      : Decl(loc, std::move(id), std::move(module), std::move(lib), std::move(og_name), is_exported), type(type), initializer(std::move(init)),
        is_const(is_const) {}
  DUMP_IMPL;
  bool replace_placeholders(const std::vector<std::string> &placeholders, const std::vector<Type> &instance_types) override;
  std::unique_ptr<VarDecl> clone() const {
    std::unique_ptr<Stmt> stmt_copy = initializer->clone();
    std::unique_ptr<Expr> init_copy = std::unique_ptr<Expr>(static_cast<Expr *>(stmt_copy.release()));
    return std::make_unique<VarDecl>(location, id, type, module, std::move(init_copy), is_const, lib, og_name, is_exported);
  }
};

// I'm not adding replace_placeholders because I already handled it in sema... This is so cursed.......
struct StructDecl : public Decl {
  std::vector<std::pair<Type, std::string>> members;
  inline StructDecl(SourceLocation loc, const std::string &id, std::string module, std::vector<std::pair<Type, std::string>> types, std::string lib = "",
                    std::string og_name = "", bool is_exported = false)
      : Decl(loc, std::move(id), std::move(module), std::move(lib), std::move(og_name), is_exported), members(std::move(types)) {}
  DUMP_IMPL;
};

struct GenericStructDecl : public Decl {
  std::vector<std::string> placeholders;
  std::vector<std::pair<Type, std::string>> members;
  inline GenericStructDecl(SourceLocation loc, const std::string &id, std::string module, std::vector<std::string> placeholders,
                           std::vector<std::pair<Type, std::string>> types, std::string lib = "", std::string og_name = "", bool is_exported = false)
      : Decl(loc, std::move(id), std::move(module), std::move(lib), std::move(og_name), is_exported), placeholders(std::move(placeholders)),
        members(std::move(types)) {}
  DUMP_IMPL;
};

struct EnumDecl : public Decl {
  std::unordered_map<std::string, long> name_values_map;
  Type underlying_type;
  inline EnumDecl(SourceLocation loc, std::string id, Type underlying_type, std::string module, std::unordered_map<std::string, long> name_values_map,
                  std::string lib = "", std::string og_name = "", bool is_exported = false)
      : Decl(loc, std::move(id), std::move(module), std::move(lib), std::move(og_name), is_exported), underlying_type(underlying_type),
        name_values_map(std::move(name_values_map)) {}
  DUMP_IMPL;
};

struct DeclStmt : public Stmt {
  std::unique_ptr<VarDecl> var_decl;
  inline DeclStmt(SourceLocation loc, std::unique_ptr<VarDecl> var) : Stmt(loc), var_decl(std::move(var)) {}
  DUMP_IMPL;
  std::unique_ptr<Stmt> clone() const override { return std::make_unique<DeclStmt>(location, var_decl->clone()); }
  bool replace_placeholders(const std::vector<std::string> &placeholders, const std::vector<Type> &instance_types) override;
};

struct NumberLiteral : public Expr {
  enum class NumberType { Integer, Real, Bool };
  NumberType type;
  std::string value;
  inline NumberLiteral(SourceLocation loc, NumberType type, std::string value) : Expr(loc), type(type), value(std::move(value)) {}
  DUMP_IMPL;
  std::unique_ptr<Stmt> clone() const override { return std::make_unique<NumberLiteral>(location, type, value); };
};

struct EnumElementAccess : public Expr {
  std::string enum_id;
  std::string member_id;
  inline EnumElementAccess(SourceLocation loc, std::string enum_id, std::string member_id)
      : Expr(loc), enum_id(std::move(enum_id)), member_id(std::move(member_id)) {}
  DUMP_IMPL;
  std::unique_ptr<Stmt> clone() const override { return std::make_unique<EnumElementAccess>(location, enum_id, member_id); };
};

struct GroupingExpr : public Expr {
  std::unique_ptr<Expr> expr;
  inline explicit GroupingExpr(SourceLocation loc, std::unique_ptr<Expr> expr) : Expr(loc), expr(std::move(expr)) {}
  DUMP_IMPL;
  std::unique_ptr<Stmt> clone() const override {
    std::unique_ptr<Stmt> stmt_copy = expr->clone();
    std::unique_ptr<Expr> expr_copy = std::unique_ptr<Expr>(static_cast<Expr *>(stmt_copy.release()));
    return std::make_unique<GroupingExpr>(location, std::move(expr_copy));
  };
};

struct BinaryOperator : public Expr {
  std::unique_ptr<Expr> lhs;
  std::unique_ptr<Expr> rhs;
  TokenKind op;
  inline BinaryOperator(SourceLocation loc, std ::unique_ptr<Expr> lhs, std::unique_ptr<Expr> rhs, TokenKind op)
      : Expr(loc), lhs(std::move(lhs)), rhs(std::move(rhs)), op(op) {}
  DUMP_IMPL;
  std::unique_ptr<Stmt> clone() const override {
    std::unique_ptr<Stmt> lhs_stmt_copy = lhs->clone();
    std::unique_ptr<Expr> lhs_expr_copy = std::unique_ptr<Expr>(static_cast<Expr *>(lhs_stmt_copy.release()));
    std::unique_ptr<Stmt> rhs_stmt_copy = rhs->clone();
    std::unique_ptr<Expr> rhs_expr_copy = std::unique_ptr<Expr>(static_cast<Expr *>(rhs_stmt_copy.release()));
    return std::make_unique<BinaryOperator>(location, std::move(lhs_expr_copy), std::move(rhs_expr_copy), op);
  };
};

struct UnaryOperator : public Expr {
  std::unique_ptr<Expr> rhs;
  TokenKind op;
  inline UnaryOperator(SourceLocation loc, std::unique_ptr<Expr> rhs, TokenKind op) : Expr(loc), rhs(std::move(rhs)), op(op) {}
  DUMP_IMPL;
  std::unique_ptr<Stmt> clone() const override {
    std::unique_ptr<Stmt> rhs_stmt_copy = rhs->clone();
    std::unique_ptr<Expr> rhs_expr_copy = std::unique_ptr<Expr>(static_cast<Expr *>(rhs_stmt_copy.release()));
    return std::make_unique<UnaryOperator>(location, std::move(rhs_expr_copy), op);
  };
};

struct ExplicitCast : public Expr {
  Type type;
  std::unique_ptr<Expr> rhs;
  inline ExplicitCast(SourceLocation loc, Type type, std::unique_ptr<Expr> rhs) : Expr(loc), type(type), rhs(std::move(rhs)) {}
  DUMP_IMPL;
  bool replace_placeholders(const std::vector<std::string> &placeholders, const std::vector<Type> &instance_types) override;
  std::unique_ptr<Stmt> clone() const override {
    std::unique_ptr<Stmt> rhs_stmt_copy = rhs->clone();
    std::unique_ptr<Expr> rhs_expr_copy = std::unique_ptr<Expr>(static_cast<Expr *>(rhs_stmt_copy.release()));
    return std::make_unique<ExplicitCast>(location, type, std::move(rhs_expr_copy));
  };
};

struct DeclRefExpr : public Expr {
  std::string id;
  inline DeclRefExpr(SourceLocation loc, std::string id) : Expr(loc), id(std::move(id)) {}
  DUMP_IMPL;
  std::unique_ptr<Stmt> clone() const override { return std::make_unique<DeclRefExpr>(location, id); };
};

struct ParamDecl : public Decl {
  Type type;
  bool is_const;
  inline ParamDecl(SourceLocation loc, std::string id, Type type, bool is_const) : Decl(loc, id, ""), type(std::move(type)), is_const(is_const) {}
  DUMP_IMPL;
  bool replace_placeholders(const std::vector<std::string> &placeholders, const std::vector<Type> &instance_types) override;
};

// bool signifies whether there's a vla
using ParameterList = std::pair<std::vector<std::unique_ptr<ParamDecl>>, bool>;

struct MemberAccess : public DeclRefExpr {
  std::string field;
  std::unique_ptr<DeclRefExpr> inner_decl_ref_expr;
  std::optional<std::vector<std::unique_ptr<Expr>>> params; // in case we're calling a function pointer
  inline explicit MemberAccess(SourceLocation loc, std::string var_id, std::string field, std::unique_ptr<DeclRefExpr> inner_decl_ref_expr,
                               std::optional<std::vector<std::unique_ptr<Expr>>> params)
      : DeclRefExpr(loc, std::move(var_id)), field(std::move(field)), params(std::move(params)), inner_decl_ref_expr(std::move(inner_decl_ref_expr)) {}
  DUMP_IMPL;
  std::unique_ptr<Stmt> clone() const override {
    std::optional<std::vector<std::unique_ptr<Expr>>> params_copy;
    if (params) {
      params_copy->reserve(params->size());
      for (auto &&param : *params) {
        auto param_stmt_copy = param->clone();
        auto param_expr_copy = std::unique_ptr<Expr>(static_cast<Expr *>(param_stmt_copy.release()));
        params_copy->push_back(std::move(param_expr_copy));
      }
    }
    auto inner_decl_stmt = inner_decl_ref_expr ? inner_decl_ref_expr->clone() : nullptr;
    auto inner_decl_expr = inner_decl_stmt ? std::unique_ptr<DeclRefExpr>(static_cast<DeclRefExpr *>(inner_decl_stmt.release())) : nullptr;
    return std::make_unique<MemberAccess>(location, id, field, std::move(inner_decl_expr), std::move(params_copy));
  };
};

struct ArrayElementAccess : public DeclRefExpr {
  std::vector<std::unique_ptr<Expr>> indices;
  inline explicit ArrayElementAccess(SourceLocation loc, std::string var_id, std::vector<std::unique_ptr<Expr>> indices)
      : DeclRefExpr(loc, std::move(var_id)), indices(std::move(indices)) {}
  DUMP_IMPL;
  std::unique_ptr<Stmt> clone() const override {
    std::vector<std::unique_ptr<Expr>> indices_copy;
    indices_copy.reserve(indices.size());
    for (auto &&index : indices) {
      auto index_stmt_copy = index->clone();
      auto index_expr_copy = std::unique_ptr<Expr>(static_cast<Expr *>(index_stmt_copy.release()));
      indices_copy.push_back(std::move(index_expr_copy));
    }
    return std::make_unique<ArrayElementAccess>(location, id, std::move(indices_copy));
  };
};

using FieldInitializer = std::pair<std::string, std::unique_ptr<Expr>>;
struct StructLiteralExpr : public Expr {
  std::vector<FieldInitializer> field_initializers;
  inline StructLiteralExpr(SourceLocation loc, std::vector<FieldInitializer> initializers) : Expr(loc), field_initializers(std::move(initializers)) {}
  DUMP_IMPL;
  std::unique_ptr<Stmt> clone() const override {
    std::vector<FieldInitializer> init_copy;
    init_copy.reserve(field_initializers.size());
    for (auto &&[str, expr] : field_initializers) {
      auto expr_stmt_copy = expr->clone();
      auto expr_copy = std::unique_ptr<Expr>(static_cast<Expr *>(expr_stmt_copy.release()));
      init_copy.push_back(std::make_pair(str, std::move(expr_copy)));
    }
    return std::make_unique<StructLiteralExpr>(location, std::move(init_copy));
  };
};

struct ArrayLiteralExpr : public Expr {
  std::vector<std::unique_ptr<Expr>> element_initializers;
  inline ArrayLiteralExpr(SourceLocation loc, std::vector<std::unique_ptr<Expr>> el_initializers)
      : Expr(loc), element_initializers(std::move(el_initializers)) {}
  DUMP_IMPL;
  std::unique_ptr<Stmt> clone() const override {
    std::vector<std::unique_ptr<Expr>> init_copy;
    init_copy.reserve(element_initializers.size());
    for (auto &&init : element_initializers) {
      auto init_stmt_copy = init->clone();
      auto init_expr_copy = std::unique_ptr<Expr>(static_cast<Expr *>(init_stmt_copy.release()));
      init_copy.push_back(std::move(init_expr_copy));
    }
    return std::make_unique<ArrayLiteralExpr>(location, std::move(init_copy));
  };
};

struct StringLiteralExpr : public Expr {
  std::string val;
  inline StringLiteralExpr(SourceLocation loc, std::string val) : Expr(loc), val(std::move(val)) {}
  DUMP_IMPL;
  std::unique_ptr<Stmt> clone() const override { return std::make_unique<StringLiteralExpr>(location, val); }
};

struct Assignment : public Stmt {
  std::unique_ptr<DeclRefExpr> variable;
  std::unique_ptr<Expr> expr;
  int lhs_deref_count;
  inline Assignment(SourceLocation loc, std::unique_ptr<DeclRefExpr> var, std::unique_ptr<Expr> expr, int lhs_deref_count)
      : Stmt(loc), variable(std::move(var)), expr(std::move(expr)), lhs_deref_count(lhs_deref_count) {}
  DUMP_IMPL;
  std::unique_ptr<Stmt> clone() const override {
    auto var_stmt = variable->clone();
    auto var_expr = std::unique_ptr<DeclRefExpr>(static_cast<DeclRefExpr *>(var_stmt.release()));
    auto expr_stmt = expr->clone();
    auto expr_expr = std::unique_ptr<Expr>(static_cast<Expr *>(expr_stmt.release()));
    return std::make_unique<Assignment>(location, std::move(var_expr), std::move(expr_expr), lhs_deref_count);
  }
  bool replace_placeholders(const std::vector<std::string> &placeholders, const std::vector<Type> &instance_types) override;
};

struct CallExpr : public Expr {
  std::unique_ptr<DeclRefExpr> id;
  std::vector<std::unique_ptr<Expr>> args;
  std::vector<Type> instance_types;
  inline CallExpr(SourceLocation loc, std::unique_ptr<DeclRefExpr> &&id, std::vector<std::unique_ptr<Expr>> &&args, std::vector<Type> &&instance_types)
      : Expr(loc), id(std::move(id)), args(std::move(args)), instance_types(std::move(instance_types)) {}
  DUMP_IMPL;
  bool replace_placeholders(const std::vector<std::string> &placeholders, const std::vector<Type> &instance_types) override;
  std::unique_ptr<Stmt> clone() const override {
    auto id_stmt = id->clone();
    auto id_expr = std::unique_ptr<DeclRefExpr>(static_cast<DeclRefExpr *>(id_stmt.release()));
    std::vector<std::unique_ptr<Expr>> args_copy;
    args_copy.reserve(args.size());
    for (auto &&arg : args) {
      auto expr_stmt = arg->clone();
      auto expr_expr = std::unique_ptr<Expr>(static_cast<Expr *>(expr_stmt.release()));
      args_copy.push_back(std::move(expr_expr));
    }
    auto instance_types_copy = instance_types;
    return std::make_unique<CallExpr>(location, std::move(id_expr), std::move(args_copy), std::move(instance_types_copy));
  }
};

struct ReturnStmt : public Stmt {
  std::unique_ptr<Expr> expr;
  inline ReturnStmt(SourceLocation loc, std::unique_ptr<Expr> &&expr = nullptr) : Stmt(loc), expr(std::move(expr)) {}
  DUMP_IMPL;
  std::unique_ptr<Stmt> clone() const override {
    auto expr_stmt = expr ? expr->clone() : nullptr;
    auto expr_expr = expr_stmt ? std::unique_ptr<Expr>(static_cast<Expr *>(expr_stmt.release())) : nullptr;
    return std::make_unique<ReturnStmt>(location, std::move(expr_expr));
  }
};

struct Block : public Stmt {
  SourceLocation location;
  std::vector<std::unique_ptr<Stmt>> statements;
  inline Block(SourceLocation location, std::vector<std::unique_ptr<Stmt>> &&statements) : Stmt(location), statements(std::move(statements)) {}
  DUMP_IMPL;
  bool replace_placeholders(const std::vector<std::string> &placeholders, const std::vector<Type> &instance_types) override;
  std::unique_ptr<Stmt> clone() const override { return std::make_unique<Block>(*this); }
  Block(const Block &other) : Stmt(other.location) {
    statements.reserve(other.statements.size());
    for (auto &&stmt : other.statements) {
      statements.push_back(stmt->clone());
    }
  }
};

struct WhileStmt : public Stmt {
  std::unique_ptr<Expr> condition;
  std::unique_ptr<Block> body;
  inline WhileStmt(SourceLocation loc, std::unique_ptr<Expr> cond, std::unique_ptr<Block> body)
      : Stmt(loc), condition(std::move(cond)), body(std::move(body)) {}
  DUMP_IMPL
  std::unique_ptr<Stmt> clone() const override {
    auto cond_st = condition->clone();
    auto cond_ex = std::unique_ptr<Expr>(static_cast<Expr *>(cond_st.release()));
    return std::make_unique<WhileStmt>(location, std::move(cond_ex), std::make_unique<Block>(*body));
  }
};

struct ForStmt : public Stmt {
  std::unique_ptr<DeclStmt> counter_variable;
  std::unique_ptr<Expr> condition;
  std::unique_ptr<Stmt> increment_expr;
  std::unique_ptr<Block> body;
  inline ForStmt(SourceLocation loc, std::unique_ptr<DeclStmt> var, std::unique_ptr<Expr> condition, std::unique_ptr<Stmt> increment,
                 std::unique_ptr<Block> body)
      : Stmt(loc), counter_variable(std::move(var)), condition(std::move(condition)), increment_expr(std::move(increment)), body(std::move(body)) {}
  DUMP_IMPL
  std::unique_ptr<Stmt> clone() const override {
    auto cond_st = condition->clone();
    auto cond_ex = std::unique_ptr<Expr>(static_cast<Expr *>(cond_st.release()));
    auto counter_copy = std::unique_ptr<DeclStmt>(static_cast<DeclStmt *>(counter_variable->clone().release()));
    return std::make_unique<ForStmt>(location, std::move(counter_copy), std::move(cond_ex), std::move(increment_expr->clone()), std::make_unique<Block>(*body));
  }
};

struct IfStmt : public Stmt {
  std::unique_ptr<Expr> condition;
  std::unique_ptr<Block> true_block;
  std::unique_ptr<Block> false_block;
  inline IfStmt(SourceLocation location, std::unique_ptr<Expr> cond, std::unique_ptr<Block> true_block, std::unique_ptr<Block> false_block)
      : Stmt(location), condition(std::move(cond)), true_block(std::move(true_block)), false_block(std::move(false_block)) {}
  DUMP_IMPL
  std::unique_ptr<Stmt> clone() const override {
    auto cond_st = condition->clone();
    auto cond_ex = std::unique_ptr<Expr>(static_cast<Expr *>(cond_st.release()));
    return std::make_unique<IfStmt>(location, std::move(cond_ex), std::make_unique<Block>(*true_block), std::make_unique<Block>(*false_block));
  }
};

#define SWITCH_DEFAULT_BLOCK_INDEX -1
#define SWITCH_FALLTHROUGH_INDEX -2
using CaseBlock = std::vector<std::pair<std::unique_ptr<Expr>, int>>;
struct SwitchStmt : public Stmt {
  std::unique_ptr<DeclRefExpr> eval_expr;
  std::vector<std::unique_ptr<Block>> blocks;
  CaseBlock cases;
  int default_block_index;
  inline SwitchStmt(SourceLocation location, std::unique_ptr<DeclRefExpr> eval_expr, CaseBlock cases, std::vector<std::unique_ptr<Block>> blocks,
                    int default_block_index)
      : Stmt(location), eval_expr(std::move(eval_expr)), cases(std::move(cases)), blocks(std::move(blocks)), default_block_index(default_block_index) {}
  DUMP_IMPL;
  std::unique_ptr<Stmt> clone() const override {
    auto eval_stmt = eval_expr->clone();
    auto ev_expr = std::unique_ptr<DeclRefExpr>(static_cast<DeclRefExpr *>(eval_stmt.release()));
    CaseBlock _cases;
    _cases.reserve(cases.size());
    std::vector<std::unique_ptr<Block>> _blocks;
    _blocks.reserve(blocks.size());
    for (auto &&[expr, index] : cases) {
      auto expr_stmt = expr->clone();
      _cases.emplace_back(std::make_pair(std::unique_ptr<Expr>(static_cast<Expr *>(expr_stmt.release())), index));
    }
    for (auto &&block : blocks) {
      auto block_clone = std::make_unique<Block>(*block);
      _blocks.emplace_back(std::move(block_clone));
    }
    return std::make_unique<SwitchStmt>(location, std::move(ev_expr), std::move(_cases), std::move(_blocks), default_block_index);
  }
};

struct DeferStmt : public Stmt {
  std::unique_ptr<Block> block;
  inline explicit DeferStmt(SourceLocation loc, std::unique_ptr<Block> block) : Stmt(loc), block(std::move(block)) {}
  DUMP_IMPL
  std::unique_ptr<Stmt> clone() const override { return std::make_unique<DeferStmt>(location, std::make_unique<Block>(*block)); }
};

struct FunctionDecl : public Decl {
  Type return_type;
  std::vector<std::unique_ptr<ParamDecl>> params;
  std::unique_ptr<Block> body;
  bool is_vla;
  inline FunctionDecl(SourceLocation location, std::string id, Type type, std::string module, std::vector<std::unique_ptr<ParamDecl>> &&params,
                      std::unique_ptr<Block> &&body, bool is_vla = false, std::string lib = "", std::string og_name = "", bool is_exported = false)
      : Decl(location, std::move(id), std::move(module), std::move(lib), std::move(og_name), is_exported), return_type(std::move(type)),
        params(std::move(params)), body(std::move(body)), is_vla(is_vla) {}
  DUMP_IMPL;
  bool replace_placeholders(const std::vector<std::string> &placeholders, const std::vector<Type> &instance_types) override;
};

struct GenericFunctionDecl : public Decl {
  Type return_type;
  std::vector<std::unique_ptr<ParamDecl>> params;
  std::unique_ptr<Block> body;
  bool is_vla;
  std::vector<std::string> placeholders;
  inline GenericFunctionDecl(SourceLocation location, std::string id, Type type, std::string module, std::vector<std::string> placeholders,
                             std::vector<std::unique_ptr<ParamDecl>> &&params, std::unique_ptr<Block> &&body, bool is_vla = false, std::string lib = "",
                             std::string og_name = "", bool is_exported = false)
      : Decl(location, std::move(id), std::move(module), std::move(lib), std::move(og_name), is_exported), return_type(std::move(type)),
        params(std::move(params)), body(std::move(body)), is_vla(is_vla), placeholders(std::move(placeholders)) {}
  DUMP_IMPL;
};

struct ResolvedStmt : public IDumpable {
  SourceLocation location;
  int scope_line;
  inline ResolvedStmt(SourceLocation location) : location(location) {}
  virtual ~ResolvedStmt() = default;
};

struct ResolvedExpr : public ConstantValueContainer<ResolvedExpr, ConstexprResult>, public ResolvedStmt {
  Type type;
  inline ResolvedExpr(SourceLocation loc, Type type) : ResolvedStmt(loc), type(std::move(type)) {}
  virtual ~ResolvedExpr() = default;
};

using ResolvedFieldInitializer = std::pair<std::string, std::unique_ptr<ResolvedExpr>>;
struct ResolvedStructLiteralExpr : public ResolvedExpr {
  std::vector<ResolvedFieldInitializer> field_initializers;
  inline ResolvedStructLiteralExpr(SourceLocation loc, Type type, std::vector<ResolvedFieldInitializer> initializers)
      : ResolvedExpr(loc, std::move(type)), field_initializers(std::move(initializers)) {}
  DUMP_IMPL
};

struct ResolvedArrayLiteralExpr : public ResolvedExpr {
  std::vector<std::unique_ptr<ResolvedExpr>> expressions;
  inline ResolvedArrayLiteralExpr(SourceLocation loc, Type type, std::vector<std::unique_ptr<ResolvedExpr>> exprs)
      : ResolvedExpr(loc, type), expressions(std::move(exprs)) {}
  DUMP_IMPL
};

struct ResolvedStringLiteralExpr : public ResolvedExpr {
  std::string val;
  inline ResolvedStringLiteralExpr(SourceLocation loc, std::string val) : ResolvedExpr(loc, Type::builtin_u8(1)), val(std::move(val)) {}
  DUMP_IMPL
};

struct ResolvedBlock : public IDumpable {
  SourceLocation location;
  std::vector<std::unique_ptr<ResolvedStmt>> statements;
  inline ResolvedBlock(SourceLocation loc, std::vector<std::unique_ptr<ResolvedStmt>> &&statements) : location(loc), statements(std::move(statements)) {}
  virtual ~ResolvedBlock() = default;
  DUMP_IMPL
};

struct ResolvedDecl : public IDumpable {
  SourceLocation location;
  std::string id;
  std::string module;
  Type type;
  std::string lib;
  std::string og_name;
  bool is_exported;
  int scope_line;
  inline ResolvedDecl(SourceLocation loc, std::string id, Type &&type, std::string module, bool is_exported, std::string lib = "", std::string og_name = "")
      : location(loc), id(std::move(id)), type(std::move(type)), module(std::move(module)), lib(std::move(lib)), og_name(std::move(og_name)),
        is_exported(is_exported) {}
  virtual ~ResolvedDecl() = default;
};

struct ResolvedStructDecl : public ResolvedDecl {
  std::vector<std::pair<Type, std::string>> members;
  bool is_leaf{false};
  inline ResolvedStructDecl(SourceLocation loc, const std::string &id, Type type, std::string module, bool is_exported,
                            std::vector<std::pair<Type, std::string>> types, std::string lib = "", std::string og_name = "")
      : ResolvedDecl(loc, id, std::move(type), std::move(module), is_exported, std::move(lib), std::move(og_name)), members(std::move(types)) {}
  DUMP_IMPL
};

struct ResolvedGenericStructDecl : public ResolvedDecl {
  std::vector<std::string> placeholders;
  std::vector<std::pair<Type, std::string>> members;
  bool is_leaf{false};
  inline ResolvedGenericStructDecl(SourceLocation loc, const std::string &id, Type type, std::string module, bool is_exported,
                                   std::vector<std::string> placeholders, std::vector<std::pair<Type, std::string>> types, std::string lib = "",
                                   std::string og_name = "")
      : ResolvedDecl(loc, id, std::move(type), std::move(module), is_exported, std::move(lib), std::move(og_name)), placeholders(std::move(placeholders)),
        members(std::move(types)) {}
  DUMP_IMPL
};

using GenericStructVec = std::vector<std::unique_ptr<ResolvedGenericStructDecl>>;

struct ResolvedModule : public IDumpable {
  std::string name;
  std::string path;
  std::vector<std::unique_ptr<ResolvedDecl>> declarations;
  inline ResolvedModule(std::string module_name, std::string path, std::vector<std::unique_ptr<ResolvedDecl>> decls)
      : name(std::move(module_name)), path(std::move(path)), declarations(std::move(decls)) {}
  DUMP_IMPL
};

struct ResolvedVarDecl : public ResolvedDecl {
  std::unique_ptr<ResolvedExpr> initializer;
  bool is_const;
  bool is_global;
  inline ResolvedVarDecl(SourceLocation loc, std::string id, Type type, std::string module, bool is_exported, std::unique_ptr<ResolvedExpr> init, bool is_const,
                         bool is_global = false, std::string lib = "", std::string og_name = "")
      : ResolvedDecl(loc, id, std::move(type), std::move(module), is_exported, std::move(lib), std::move(og_name)), initializer(std::move(init)),
        is_const(is_const), is_global(is_global) {}
  DUMP_IMPL
};

struct ResolvedEnumDecl : public ResolvedDecl {
  std::unordered_map<std::string, long> name_values_map;
  inline ResolvedEnumDecl(SourceLocation loc, std::string id, Type underlying_type, std::string module, bool is_exported,
                          std::unordered_map<std::string, long> name_values_map, std::string lib = "", std::string og_name = "")
      : ResolvedDecl(loc, std::move(id), std::move(underlying_type), std::move(module), is_exported, std::move(lib), std::move(og_name)),
        name_values_map(std::move(name_values_map)) {}
  DUMP_IMPL
};

struct ResolvedDeclStmt : public ResolvedStmt {
  std::unique_ptr<ResolvedVarDecl> var_decl;
  inline ResolvedDeclStmt(SourceLocation loc, std::unique_ptr<ResolvedVarDecl> decl) : ResolvedStmt(loc), var_decl(std::move(decl)) {}
  DUMP_IMPL
};

struct ResolvedForStmt : public ResolvedStmt {
  std::unique_ptr<ResolvedDeclStmt> counter_variable;
  std::unique_ptr<ResolvedExpr> condition;
  std::unique_ptr<ResolvedStmt> increment_expr;
  std::unique_ptr<ResolvedBlock> body;
  inline ResolvedForStmt(SourceLocation loc, std::unique_ptr<ResolvedDeclStmt> var, std::unique_ptr<ResolvedExpr> condition,
                         std::unique_ptr<ResolvedStmt> increment, std::unique_ptr<ResolvedBlock> body)
      : ResolvedStmt(loc), counter_variable(std::move(var)), condition(std::move(condition)), increment_expr(std::move(increment)), body(std::move(body)) {}
  DUMP_IMPL
};

struct ResolvedWhileStmt : public ResolvedStmt {
  std::unique_ptr<ResolvedExpr> condition;
  std::unique_ptr<ResolvedBlock> body;
  inline ResolvedWhileStmt(SourceLocation location, std::unique_ptr<ResolvedExpr> cond, std::unique_ptr<ResolvedBlock> body)
      : ResolvedStmt(location), condition(std::move(cond)), body(std::move(body)) {}
  DUMP_IMPL
};

struct ResolvedIfStmt : public ResolvedStmt {
  std::unique_ptr<ResolvedExpr> condition;
  std::unique_ptr<ResolvedBlock> true_block;
  std::unique_ptr<ResolvedBlock> false_block;
  inline ResolvedIfStmt(SourceLocation loc, std::unique_ptr<ResolvedExpr> condition, std::unique_ptr<ResolvedBlock> true_block,
                        std::unique_ptr<ResolvedBlock> false_block)
      : ResolvedStmt(loc), condition(std::move(condition)), true_block(std::move(true_block)), false_block(std::move(false_block)) {}
  DUMP_IMPL
};

struct ResolvedDeferStmt : public ResolvedStmt {
  std::unique_ptr<ResolvedBlock> block;
  inline explicit ResolvedDeferStmt(SourceLocation loc, std::unique_ptr<ResolvedBlock> block) : ResolvedStmt(loc), block(std::move(block)) {}
  DUMP_IMPL
};

struct ResolvedNumberLiteral : public ResolvedExpr {
  Value value;
  explicit ResolvedNumberLiteral(SourceLocation loc, NumberLiteral::NumberType type, const std::string &value);
  explicit ResolvedNumberLiteral(SourceLocation loc, Type type, const Value &val) : ResolvedExpr(loc, std::move(type)), value(val) {}
  DUMP_IMPL
};

struct ResolvedGroupingExpr : public ResolvedExpr {
  std::unique_ptr<ResolvedExpr> expr;
  inline explicit ResolvedGroupingExpr(SourceLocation loc, std::unique_ptr<ResolvedExpr> expr) : ResolvedExpr(loc, expr->type), expr(std::move(expr)) {}
  DUMP_IMPL
};

struct ResolvedBinaryOperator : public ResolvedExpr {
  std::unique_ptr<ResolvedExpr> lhs;
  std::unique_ptr<ResolvedExpr> rhs;
  TokenKind op;
  inline explicit ResolvedBinaryOperator(SourceLocation loc, std::unique_ptr<ResolvedExpr> lhs, std::unique_ptr<ResolvedExpr> rhs, TokenKind op)
      : ResolvedExpr(loc, lhs->type), lhs(std::move(lhs)), rhs(std::move(rhs)), op(op) {}
  DUMP_IMPL
};

struct ResolvedUnaryOperator : public ResolvedExpr {
  std::unique_ptr<ResolvedExpr> rhs;
  TokenKind op;
  inline explicit ResolvedUnaryOperator(SourceLocation loc, std::unique_ptr<ResolvedExpr> rhs, TokenKind op)
      : ResolvedExpr(loc, rhs->type), rhs(std::move(rhs)), op(op) {}
  DUMP_IMPL
};

struct ResolvedParamDecl : public ResolvedDecl {
  bool is_const;
  inline ResolvedParamDecl(SourceLocation loc, std::string id, Type &&type, bool is_const)
      : ResolvedDecl(loc, std::move(id), std::move(type), "", "", ""), is_const(is_const) {}
  DUMP_IMPL
};

struct ResolvedFuncDecl : public ResolvedDecl {
  std::vector<std::unique_ptr<ResolvedParamDecl>> params;
  std::unique_ptr<ResolvedBlock> body;
  bool is_vla;
  inline ResolvedFuncDecl(SourceLocation loc, std::string id, Type type, std::string module, bool is_exported,
                          std::vector<std::unique_ptr<ResolvedParamDecl>> &&params, std::unique_ptr<ResolvedBlock> body, bool is_vla, std::string lib = "",
                          std::string og_name = "")
      : ResolvedDecl(loc, std::move(id), std::move(type), std::move(module), is_exported, std::move(lib), std::move(og_name)), params(std::move(params)),
        body(std::move(body)), is_vla(is_vla) {}
  DUMP_IMPL
};

struct ResolvedGenericFunctionDecl : public ResolvedDecl {
  std::vector<std::unique_ptr<ResolvedParamDecl>> params;
  const Block *generic_block;
  bool is_vla;
  std::vector<std::string> placeholders;
  inline ResolvedGenericFunctionDecl(SourceLocation location, std::string id, Type type, std::string module, bool is_exported,
                                     std::vector<std::string> placeholders, std::vector<std::unique_ptr<ResolvedParamDecl>> &&params,
                                     const Block *generic_block, bool is_vla = false, std::string lib = "", std::string og_name = "")
      : ResolvedDecl(location, std::move(id), std::move(type), std::move(module), is_exported, std::move(lib), std::move(og_name)), params(std::move(params)),
        generic_block(generic_block), is_vla(is_vla), placeholders(std::move(placeholders)) {}
  DUMP_IMPL
};

struct ResolvedDeclRefExpr : public ResolvedExpr {
  const ResolvedDecl *decl;
  inline ResolvedDeclRefExpr(SourceLocation loc, const ResolvedDecl *decl) : ResolvedExpr(loc, decl->type), decl(decl) {}
  DUMP_IMPL
};

using ResolvedCaseBlocks = std::vector<std::pair<std::unique_ptr<ResolvedNumberLiteral>, int>>;
struct ResolvedSwitchStmt : public ResolvedStmt {
  std::unique_ptr<ResolvedDeclRefExpr> eval_expr;
  std::vector<std::unique_ptr<ResolvedBlock>> blocks;
  ResolvedCaseBlocks cases;
  int default_block_index;
  inline ResolvedSwitchStmt(SourceLocation location, std::unique_ptr<ResolvedDeclRefExpr> eval_expr, ResolvedCaseBlocks cases,
                            std::vector<std::unique_ptr<ResolvedBlock>> blocks, int default_block_index)
      : ResolvedStmt(location), eval_expr(std::move(eval_expr)), cases(std::move(cases)), blocks(std::move(blocks)), default_block_index(default_block_index) {}
  DUMP_IMPL;
};

struct ResolvedNullExpr : public ResolvedExpr {
  inline ResolvedNullExpr(SourceLocation loc, Type type) : ResolvedExpr(loc, type) { type.pointer_depth = 1; }
  DUMP_IMPL
};

struct ResolvedExplicitCastExpr : public ResolvedExpr {
  enum class CastType { Nop, Extend, Truncate, Ptr, IntToPtr, PtrToInt, IntToFloat, FloatToInt };
  CastType cast_type;
  std::unique_ptr<ResolvedExpr> rhs;
  inline ResolvedExplicitCastExpr(SourceLocation loc, Type type, CastType cast_type, std::unique_ptr<ResolvedExpr> rhs)
      : ResolvedExpr(loc, type), cast_type(cast_type), rhs(std::move(rhs)) {}
  DUMP_IMPL
};

struct ResolvedCallExpr : public ResolvedExpr {
  const ResolvedDecl *decl;
  std::vector<std::unique_ptr<ResolvedExpr>> args;
  inline ResolvedCallExpr(SourceLocation loc, const ResolvedDecl *callee, std::vector<std::unique_ptr<ResolvedExpr>> &&args)
      : ResolvedExpr(loc, callee->type), decl(callee), args(std::move(args)) {}
  DUMP_IMPL
};

using FnPtrCallParams = std::vector<std::unique_ptr<ResolvedExpr>>;
struct InnerMemberAccess : public IDumpable {
  int member_index;
  std::string member_id;
  Type type;
  std::unique_ptr<InnerMemberAccess> inner_member_access;
  // in case function pointer call, contains arguments for the call of
  // inner_member_access
  std::optional<FnPtrCallParams> params;
  inline InnerMemberAccess(int index, std::string id, Type type, std::unique_ptr<InnerMemberAccess> inner_access, std::optional<FnPtrCallParams> params)
      : member_index(index), member_id(std::move(id)), type(type), inner_member_access(std::move(inner_access)), params(std::move(params)) {}
  DUMP_IMPL
};

struct ResolvedStructMemberAccess : public ResolvedDeclRefExpr {
  std::unique_ptr<InnerMemberAccess> inner_member_access;
  // in case function pointer call, contains arguments for the call of
  // inner_member_access
  std::optional<FnPtrCallParams> params;
  inline ResolvedStructMemberAccess(SourceLocation loc, const ResolvedDecl *decl, std::unique_ptr<InnerMemberAccess> inner_access,
                                    std::optional<FnPtrCallParams> params)
      : ResolvedDeclRefExpr(loc, decl), inner_member_access(std::move(inner_access)), params(std::move(params)) {}
  DUMP_IMPL
};

struct ResolvedArrayElementAccess : public ResolvedDeclRefExpr {
  std::vector<std::unique_ptr<ResolvedExpr>> indices;
  inline ResolvedArrayElementAccess(SourceLocation loc, const ResolvedDecl *decl, std::vector<std::unique_ptr<ResolvedExpr>> indices)
      : ResolvedDeclRefExpr(loc, decl), indices(std::move(indices)) {}
  DUMP_IMPL
};

struct ResolvedReturnStmt : public ResolvedStmt {
  std::unique_ptr<ResolvedExpr> expr;
  inline ResolvedReturnStmt(SourceLocation loc, std::unique_ptr<ResolvedExpr> expr) : ResolvedStmt(loc), expr(std::move(expr)) {}
  DUMP_IMPL
};

struct ResolvedAssignment : public ResolvedStmt {
  std::unique_ptr<ResolvedDeclRefExpr> variable;
  std::unique_ptr<ResolvedExpr> expr;
  int lhs_deref_count;
  inline ResolvedAssignment(SourceLocation loc, std::unique_ptr<ResolvedDeclRefExpr> var, std::unique_ptr<ResolvedExpr> expr, int lhs_deref_count)
      : ResolvedStmt(loc), variable(std::move(var)), expr(std::move(expr)), lhs_deref_count(lhs_deref_count) {}
  DUMP_IMPL
};
} // namespace saplang
