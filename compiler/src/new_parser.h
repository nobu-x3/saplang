#include "ast.h"

namespace saplang {
enum class SymbolKind {
  Var,
  Struct,
  Func,
};

struct Field {
  char name[64];
  char type[64];
  Field *next;
};

struct Parameter {
  char name[64];
  char type[64];
  Parameter *next;
};

struct Symbol {
  char name[64];
  SymbolKind kind;
  char type[64];
  Value value;           // initial value
  Field *fields;         // for structs
  Parameter *parameters; // for fns
  Symbol *next;
};

struct NewParser {
  Lexer *lexer;
  Symbol *symbol_table;
  Token current_token;
  void process();
  void free();
  void add_var_symbol(const char *name, const char *type, Value value);
  void add_struct_symbol(const char *name, Field *fields);
  void add_fn_symbol(const char *name, const char *return_type, Parameter *params);
};

void print_symbol_table(Symbol *table);
} // namespace saplang
