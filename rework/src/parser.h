#pragma once
#include "scanner.h"

typedef enum {
  SYMB_VAR,
  SYMB_STRUCT,
  SYMB_FN,
} SymbolKind;

typedef struct Field {
  char name[64];
  char type[64];
  struct Field *next;
} Field;

typedef struct Parameter {
  char name[64];
  char type[64];
  struct Parameter *next;
} Parameter;

typedef struct Symbol {
  char name[64];
  SymbolKind kind;
  char type[64];
  unsigned long value;   // initial value
  Field *fields;         // for structs
  Parameter *parameters; // for fns
  struct Symbol *next;
} Symbol;

typedef struct Parser {
  Scanner *scanner;
  Symbol *symbol_table;
  Token current_token;
} Parser;

void add_var_symbol(Symbol *table, const char *name, const char *type, unsigned long value);
void add_struct_symbol(Symbol *table, const char *name, Field *fields);
void add_fn_symbol(Symbol *table, const char *name, const char *return_type, Parameter *params);
void free_parser(Parser *parser);

void print_symbol_table(Symbol *table, char* string);

typedef enum { AST_VAR_DECL, AST_STRUCT_DECL, AST_FUNC_DECL, AST_FIELD_DECL, AST_PARAM_DECL, AST_BLOCK, AST_EXPR_LITERAL, AST_EXPR_IDENT } ASTNodeType;

typedef struct ASTNode {
  ASTNodeType type;
  struct ASTNode *next; // For linked lists (e.g. global declarations, fields, params)
  union {
    // Variable declaration: <type> name = init;
    struct {
      char type_name[64];
      char name[64];
      struct ASTNode *init; // Expression node
    } varDecl;
    // Struct declaration: struct Name { fields }
    struct {
      char name[64];
      struct ASTNode *fields; // Linked list of field declarations
    } structDecl;
    // Function declaration: func name(params) { body }
    struct {
      char name[64];
      struct ASTNode *params; // Linked list of parameter declarations
      struct ASTNode *body;   // Block node
    } funcDecl;
    // Field declaration inside struct: <type> name;
    struct {
      char type_name[64];
      char name[64];
    } fieldDecl;
    // Parameter declaration: <type> name
    struct {
      char type_name[64];
      char name[64];
    } paramDecl;
    // Block: a list of statements
    struct {
      struct ASTNode **statements;
      int count;
    } block;
    // Literal expression: integer, float, or bool
    struct {
      long long_value;
      double float_value;
      int is_float;   // 1 if float literal
      int bool_value; // 1 for true, 0 for false
      int is_bool;    // 1 if bool literal
    } literal;
    // Identifier expression.
    struct {
      char name[64];
    } ident;
  } data;
} ASTNode;
