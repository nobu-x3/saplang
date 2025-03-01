#include "parser.h"
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void print_symbol_table(Symbol *table, char *string) {
  for (Symbol *sym = table; sym; sym = sym->next) {
    if (sym->kind == SYMB_VAR) {
      sprintf(string, "\tVariable: %s, Type: %s\n", sym->name, sym->type);
    } else if (sym->kind == SYMB_STRUCT) {
      sprintf(string, "\tStruct: %s:\n", sym->name);
      for (Field *field = sym->fields; field; field = field->next) {
        sprintf(string, "\t\tField: %s, type: %s\n", field->name, field->type);
      }
    } else if (sym->kind == SYMB_FN) {
      sprintf(string, "\tFn: %s:\n", sym->name);
      for (Parameter *param = sym->parameters; param; param = param->next) {
        sprintf(string, "\t\tParameter: %s, type: %s", param->name, param->type);
      }
    }
  }
}

void add_var_symbol(Symbol *table, const char *name, const char *type, unsigned long value) {
  Symbol *sym = (Symbol *)malloc(sizeof(Symbol));
  if (!sym)
    return;
  strcpy(sym->name, name);
  sym->kind = SYMB_VAR;
  strcpy(sym->type, type);
  sym->value = value;
  sym->fields = NULL;
  sym->parameters = NULL;
  sym->next = table;
  *table = *sym;
}

void add_struct_symbol(Symbol *table, const char *name, Field *fields) {
  Symbol *sym = (Symbol *)malloc(sizeof(Symbol));
  if (!sym)
    return;
  strcpy(sym->name, name);
  sym->kind = SYMB_STRUCT;
  sym->value = 0;
  strcpy(sym->type, "struct");
  sym->fields = fields;
  sym->parameters = NULL;
  sym->next = table;
  *table = *sym;
}

void add_fn_symbol(Symbol *table, const char *name, const char *return_type, Parameter *params) {
  Symbol *sym = (Symbol *)malloc(sizeof(Symbol));
  if (!sym)
    return;
  strcpy(sym->name, name);
  sym->kind = SYMB_FN;
  sym->value = 0;
  strcpy(sym->type, return_type);
  sym->fields = NULL;
  sym->parameters = params;
  sym->next = table;
  *table = *sym;
}

// @TODO
void free_parser(Parser *parser) {}

void process();
