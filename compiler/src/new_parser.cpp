#include "new_parser.h"
#include <cstdio>
#include <ctype.h>
#include <stdlib.h>
#include <string.h>

namespace saplang {

void print_symbol_table(Symbol *table, char *string) {
  for (Symbol *sym = table; sym; sym = sym->next) {
    if (sym->kind == SymbolKind::Var) {
      sprintf(string, "\tVariable: %s, Type: %s\n", sym->name, sym->type);
    } else if (sym->kind == SymbolKind::Struct) {
      sprintf(string, "\tStruct: %s:\n", sym->name);
      for (Field *field = sym->fields; field; field = field->next) {
        sprintf(string, "\t\tField: %s, type: %s\n", field->name, field->type);
      }
    } else if (sym->kind == SymbolKind::Func) {
      sprintf(string, "\tFn: %s:\n", sym->name);
      for (Parameter *param = sym->parameters; param; param = param->next) {
        sprintf(string, "\t\tParameter: %s, type: %s", param->name, param->type);
      }
    }
  }
}

void NewParser::add_var_symbol(const char *name, const char *type, Value value) {
  Symbol *sym = (Symbol *)malloc(sizeof(Symbol));
  if (!sym)
    return;
  strcpy(sym->name, name);
  sym->kind = SymbolKind::Var;
  strcpy(sym->type, type);
  sym->value = value;
  sym->fields = nullptr;
  sym->parameters = nullptr;
  sym->next = symbol_table;
  symbol_table = sym;
}

void NewParser::add_struct_symbol(const char *name, Field *fields) {
  Symbol *sym = (Symbol *)malloc(sizeof(Symbol));
  if (!sym)
    return;
  strcpy(sym->name, name);
  sym->kind = SymbolKind::Struct;
  sym->value = Value();
  strcpy(sym->type, "struct");
  sym->fields = fields;
  sym->parameters = nullptr;
  sym->next = symbol_table;
  symbol_table = sym;
}

void NewParser::add_fn_symbol(const char *name, const char *return_type, Parameter *params) {
  Symbol *sym = (Symbol *)malloc(sizeof(Symbol));
  if (!sym)
    return;
  strcpy(sym->name, name);
  sym->kind = SymbolKind::Struct;
  sym->value = Value();
  strcpy(sym->type, return_type);
  sym->fields = nullptr;
  sym->parameters = params;
  sym->next = symbol_table;
  symbol_table = sym;
}

// @TODO
void NewParser::free() {}

void NewParser::process() {}
} // namespace saplang
