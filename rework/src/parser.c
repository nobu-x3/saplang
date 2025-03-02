#include "parser.h"
#include "scanner.h"
#include "util.h"
#include <assert.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define print(string, format, ...)                                                                                                                             \
  if (string) {                                                                                                                                                \
    sprintf(string, format, ##__VA_ARGS__);                                                                                                                    \
  } else {                                                                                                                                                     \
    printf(format, ##__VA_ARGS__);                                                                                                                             \
  }

CompilerResult symbol_table_print(Symbol *table, char *string) {
  if (!table)
    return RESULT_PASSED_NULL_PTR;
  for (Symbol *sym = table; sym; sym = sym->next) {
    if (sym->kind == SYMB_VAR) {
      print(string, "\tVariable: %s, Type: %s\n", sym->name, sym->type);
    } else if (sym->kind == SYMB_STRUCT) {
      print(string, "\tStruct: %s\n", sym->name);
    } else if (sym->kind == SYMB_FN) {
      print(string, "\tFn: %s\n", sym->name);
    }
  }
  return RESULT_SUCCESS;
}

CompilerResult add_symbol(Symbol **table, const char *name, SymbolKind kind, const char *type) {
  if (!table)
    return RESULT_PASSED_NULL_PTR;

  Symbol *symb = malloc(sizeof(Symbol));
  if (!symb)
    return RESULT_MEMORY_ERROR;

  strncpy(symb->name, name, sizeof(symb->name));
  strncpy(symb->type, type, sizeof(symb->type));
  symb->kind = kind;
  symb->next = *table;
  *table = symb;
  return RESULT_SUCCESS;
}

CompilerResult parser_init(Parser *parser, Scanner scanner, Symbol *optional_table) {
  if (!parser)
    return RESULT_PASSED_NULL_PTR;

  if (!memset(parser, 0, sizeof(Parser)))
    return RESULT_MEMORY_ERROR;

  parser->scanner = scanner;
  parser->symbol_table = optional_table;
  return RESULT_SUCCESS;
}

CompilerResult parser_deinit(Parser *parser) {
  if (!parser)
    return RESULT_PASSED_NULL_PTR;

  scanner_deinit(&parser->scanner);
  // @TODO: free symbol table
  return RESULT_SUCCESS;
}

CompilerResult ast_print(ASTNode *node, int indent, char *string) {
  if (!node)
    return RESULT_PASSED_NULL_PTR;
  while (node) {
    for (int i = 0; i < indent; i++) {
      print(string, "  ");
    }
    switch (node->type) {
    case AST_VAR_DECL: {
      char is_const[6] = {0};
      if (node->data.var_decl.is_const) {
        strncpy(is_const, "const", sizeof(is_const));
      }
      print(string, "VarDecl: %s %s %s", is_const, node->data.var_decl.type_name, node->data.var_decl.name);
      if (node->data.var_decl.init) {
        print(string, ":\n");
        ast_print(node->data.var_decl.init, indent + 1, string);
      } else {
        print(string, "\n");
      }
      break;
    }
    case AST_STRUCT_DECL:
      print(string, "StructDecl: %s\n", node->data.struct_decl.name);
      ast_print(node->data.struct_decl.fields, indent + 1, string);
      break;
    case AST_FUNC_DECL:
      print(string, "FuncDecl: %s\n", node->data.func_decl.name);
      for (int i = 0; i < indent + 1; i++) {
        print(string, "  ");
      }
      print(string, "Params:\n");
      ast_print(node->data.func_decl.params, indent + 2, string);
      for (int i = 0; i < indent + 1; i++)
        print(string, "  ");
      print(string, "Body:\n");
      ast_print(node->data.func_decl.body, indent + 2, string);
      break;
    case AST_FIELD_DECL:
      print(string, "FieldDecl: %s %s\n", node->data.field_decl.type_name, node->data.field_decl.name);
      break;
    case AST_PARAM_DECL:
      print(string, "ParamDecl: %s %s\n", node->data.paramDecl.type_name, node->data.paramDecl.name);
      break;
    case AST_BLOCK:
      print(string, "Block with %d statement(s):\n", node->data.block.count);
      for (int i = 0; i < node->data.block.count; i++) {
        ast_print(node->data.block.statements[i], indent + 1, string);
      }
      break;
    case AST_EXPR_LITERAL:
      if (node->data.literal.is_bool) {
        print(string, "Literal Bool: %s\n", node->data.literal.bool_value ? "true" : "false");
      } else if (node->data.literal.is_float) {
        print(string, "Literal Float: %f\n", node->data.literal.float_value);
      } else {
        print(string, "Literal Int: %ld\n", node->data.literal.long_value);
      }
      break;
    case AST_EXPR_IDENT:
      print(string, "Ident: %s\n", node->data.ident.name);
      break;
    case AST_RETURN:
      print(string, "Return:\n");
      ast_print(node->data.ret.return_expr, indent + 1, string);
      break;
    case AST_BINARY_EXPR:
      print(string, "Binary Expression: %c\n", node->data.binary_op.op);
      ast_print(node->data.binary_op.left, indent + 1, string);
      ast_print(node->data.binary_op.right, indent + 1, string);
      break;
    default: {
      print(string, "Unknown AST Node\n");
    } break;
    }
    node = node->next;
  }
  return RESULT_SUCCESS;
}

ASTNode *new_ast_node(ASTNodeType type) {
  ASTNode *node = malloc(sizeof(ASTNode));
  if (!node) {
    return NULL;
  }
  node->type = type;
  node->next = NULL;
  return node;
}

ASTNode *new_binary_expr_node(char op, ASTNode *left, ASTNode *right) {
  ASTNode *node = new_ast_node(AST_BINARY_EXPR);
  if (!node)
    return NULL;
  node->data.binary_op.op = op;
  node->data.binary_op.left = left;
  node->data.binary_op.right = right;
  return node;
}

ASTNode *new_return_node(ASTNode *expr) {
  ASTNode *node = new_ast_node(AST_RETURN);
  if (!node)
    return NULL;
  node->data.ret.return_expr = expr;
  return node;
}

ASTNode *new_field_decl_node(const char *type_name, const char *name) {
  ASTNode *node = new_ast_node(AST_FIELD_DECL);
  if (!node)
    return NULL;
  strncpy(node->data.field_decl.type_name, type_name, sizeof(node->data.field_decl.type_name));
  strncpy(node->data.field_decl.name, name, sizeof(node->data.field_decl.name));
  return node;
}

ASTNode *new_struct_decl_node(const char *name, ASTNode *fields) {
  ASTNode *node = new_ast_node(AST_STRUCT_DECL);
  strncpy(node->data.struct_decl.name, name, sizeof(node->data.struct_decl.name));
  node->data.struct_decl.fields = fields;
  return node;
}

ASTNode *new_var_decl_node(const char *type_name, const char *name, int is_const, ASTNode *initializer) {
  ASTNode *node = new_ast_node(AST_VAR_DECL);
  if (!node)
    return NULL;
  strncpy(node->data.var_decl.name, name, sizeof(node->data.var_decl.name));
  strncpy(node->data.var_decl.type_name, type_name, sizeof(node->data.var_decl.type_name));
  node->data.var_decl.init = initializer;
  node->data.var_decl.is_const = is_const;
  return node;
}

ASTNode *new_block_node(ASTNode **stmts, int count, int capacity) {
  ASTNode *node = new_ast_node(AST_BLOCK);
  if (!node)
    return NULL;
  node->data.block.statements = stmts;
  node->data.block.count = count;
  node->data.block.capacity = capacity;
  return node;
}

ASTNode *new_param_decl_node(const char *type_name, const char *name) {
  ASTNode *node = new_ast_node(AST_PARAM_DECL);
  if (!node)
    return NULL;
  strncpy(node->data.paramDecl.type_name, type_name, sizeof(node->data.paramDecl.type_name));
  strncpy(node->data.paramDecl.name, name, sizeof(node->data.paramDecl.name));
  return node;
}

ASTNode *new_func_decl_node(const char *name, ASTNode *params, ASTNode *body) {
  ASTNode *node = new_ast_node(AST_FUNC_DECL);
  if (!node)
    return NULL;
  strncpy(node->data.func_decl.name, name, sizeof(node->data.func_decl.name));
  node->data.func_decl.params = params;
  node->data.func_decl.body = body;
  return node;
}

ASTNode *new_literal_node_long(long value) {
  ASTNode *node = new_ast_node(AST_EXPR_LITERAL);
  if (!node)
    return NULL;
  node->data.literal.long_value = value;
  node->data.literal.is_bool = 0;
  node->data.literal.is_float = 0;
  return node;
}

ASTNode *new_literal_node_float(double value) {
  ASTNode *node = new_ast_node(AST_EXPR_LITERAL);
  if (!node)
    return NULL;
  node->data.literal.float_value = value;
  node->data.literal.is_bool = 0;
  node->data.literal.is_float = 1;
  return node;
}

ASTNode *new_literal_node_bool(int value) {
  ASTNode *node = new_ast_node(AST_EXPR_LITERAL);
  if (!node)
    return NULL;
  node->data.literal.bool_value = value;
  node->data.literal.is_bool = 1;
  node->data.literal.is_float = 0;
  return node;
}

ASTNode *new_ident_node(const char *name) {
  ASTNode *node = new_ast_node(AST_EXPR_IDENT);
  if (!node)
    return NULL;
  strncpy(node->data.ident.name, name, sizeof(node->data.ident.name));
  return node;
}

CompilerResult parse_type_name(Parser *parser, char *buffer) {
  switch (parser->current_token.type) {
  case TOK_I8:
  case TOK_I16:
  case TOK_I32:
  case TOK_I64:
  case TOK_U8:
  case TOK_U16:
  case TOK_U32:
  case TOK_U64:
  case TOK_F32:
  case TOK_F64:
  case TOK_BOOL:
    strncpy(buffer, parser->current_token.text, 64);
    parser->current_token = next_token(&parser->scanner);
    break;
  case TOK_IDENTIFIER:
    strncpy(buffer, parser->current_token.text, 64);
    parser->current_token = next_token(&parser->scanner);
    break;
  default: {
    char msg[128];
    sprintf(msg, "expected type name, got '%s'.", parser->current_token.text);
    report(parser->current_token.location, msg, 0);
    return RESULT_PARSING_ERROR;
  }
  }
  return RESULT_SUCCESS;
}

ASTNode *parse_primary(Parser *parser);

ASTNode *parse_term(Parser *parser) {
  ASTNode *node = parse_primary(parser);
  while (parser->current_token.type == TOK_ASTERISK || parser->current_token.type == TOK_SLASH) {
    char op = parser->current_token.text[0];
    parser->current_token = next_token(&parser->scanner);
    ASTNode *right = parse_primary(parser);
    node = new_binary_expr_node(op, node, right);
  }
  return node;
}

ASTNode *parse_expr(Parser *parser) {
  // I split it like that because of operator precedence
  ASTNode *node = parse_term(parser);
  while (parser->current_token.type == TOK_MINUS || parser->current_token.type == TOK_PLUS) {
    char op = parser->current_token.text[0];
    parser->current_token = next_token(&parser->scanner);
    ASTNode *right = parse_term(parser);
    node = new_binary_expr_node(op, node, right);
  }
  return node;
}

ASTNode *parse_return_stmt(Parser *parser) {
  parser->current_token = next_token(&parser->scanner); // consume 'return'
  ASTNode *expr = parse_expr(parser);

  if (parser->current_token.type != TOK_SEMICOLON) {
    report(parser->current_token.location, "expected ';' after return statement.", 0);
  }

  parser->current_token = next_token(&parser->scanner); // consume ';'

  return new_return_node(expr);
}

ASTNode *parse_primary(Parser *parser) {
  // @TODO: add array and struct literals
  if (parser->current_token.type == TOK_NUMBER) {
    if (strchr(parser->current_token.text, '.') != NULL) {
      double value = atof(parser->current_token.text);
      parser->current_token = next_token(&parser->scanner);
      return new_literal_node_float(value);
    } else {
      long value = atol(parser->current_token.text);
      parser->current_token = next_token(&parser->scanner);
      return new_literal_node_long(value);
    }
  } else if (parser->current_token.type == TOK_TRUE) {
    parser->current_token = next_token(&parser->scanner);
    return new_literal_node_bool(1);
  } else if (parser->current_token.type == TOK_FALSE) {
    parser->current_token = next_token(&parser->scanner);
    return new_literal_node_bool(0);
  } else if (parser->current_token.type == TOK_IDENTIFIER) {
    char ident_name[64];
    strncpy(ident_name, parser->current_token.text, sizeof(ident_name));
    parser->current_token = next_token(&parser->scanner);
    return new_ident_node(ident_name);
  } else if (parser->current_token.type == TOK_LPAREN) {
    parser->current_token = next_token(&parser->scanner);
    ASTNode *expr = parse_expr(parser);
    if (!expr)
      return NULL;
    if (parser->current_token.type != TOK_RPAREN)
      return report(parser->current_token.location, "expected ')'.", 0);
    parser->current_token = next_token(&parser->scanner);
    return expr;
  } else {
    char expr[128];
    sprintf(expr, "unexpected token in expression: %s", parser->current_token.text);
    return report(parser->current_token.location, expr, 0);
  }
}

// <varDecl>
// ::= ('const')? <type> <identifier> ('=' <expression>)? ';'
ASTNode *parse_var_decl(Parser *parser) {
  int is_const = 0;
  if (parser->current_token.type == TOK_CONST) {
    is_const = 1;
    parser->current_token = next_token(&parser->scanner); // consume 'const'
  }

  char type_name[64];
  parse_type_name(parser, type_name);

  if (parser->current_token.type != TOK_IDENTIFIER) {
    return report(parser->current_token.location, "expected identifier in variable declaration.", 0);
  }

  char var_name[64];
  strncpy(var_name, parser->current_token.text, sizeof(var_name));
  parser->current_token = next_token(&parser->scanner); // consume identifier

  ASTNode *init_expr = NULL;
  if (parser->current_token.type == TOK_ASSIGN) {
    parser->current_token = next_token(&parser->scanner); // consume '='
    init_expr = parse_expr(parser);
  }

  if (parser->current_token.type != TOK_SEMICOLON)
    return report(parser->current_token.location, "expected ';' after variable declaration.", 0);

  parser->current_token = next_token(&parser->scanner); // consume ';'

  add_symbol(&parser->symbol_table, var_name, SYMB_VAR, type_name);
  return new_var_decl_node(type_name, var_name, is_const, init_expr);
}

ASTNode *parse_stmt(Parser *parser) {
  if (parser->current_token.type == TOK_RETURN) {
    return parse_return_stmt(parser);
  }

  if (parser->current_token.type == TOK_I8 || parser->current_token.type == TOK_I16 || parser->current_token.type == TOK_I32 ||
      parser->current_token.type == TOK_I64 || parser->current_token.type == TOK_U8 || parser->current_token.type == TOK_U16 ||
      parser->current_token.type == TOK_U32 || parser->current_token.type == TOK_U64 || parser->current_token.type == TOK_F32 ||
      parser->current_token.type == TOK_F64 || parser->current_token.type == TOK_BOOL || parser->current_token.type == TOK_IDENTIFIER) {
    // peek ahead
    // @TODO: redo this when reworking scanner to work with indices
    char *save = parser->scanner.source.buffer;
    Token temp = parser->current_token;
    char type_name[64];
    parse_type_name(parser, type_name);
    if (parser->current_token.type == TOK_IDENTIFIER) {
      // most likely var decl, restore state and reparse
      parser->scanner.source.buffer = save;
      parser->current_token = temp;
      return parse_var_decl(parser);
    }
    // restore and parse expression
    parser->scanner.source.buffer = save;
    parser->current_token = temp;
  }

  ASTNode *expr = parse_expr(parser);
  if (parser->current_token.type != TOK_SEMICOLON) {
    return report(parser->current_token.location, "expected ';' after expression statement.", 0);
  }
  parser->current_token = next_token(&parser->scanner);
  return expr;
}

// <fieldDecl>
// ::= <type> <identifier> ;
ASTNode *parse_field_declaration(Parser *parser) {
  char type_name[64];
  parse_type_name(parser, type_name);

  if (parser->current_token.type != TOK_IDENTIFIER) {
    return report(parser->current_token.location, "expected identifier in struct field declaration.", 0);
  }

  char field_name[64];
  strncpy(field_name, parser->current_token.text, sizeof(field_name));

  parser->current_token = next_token(&parser->scanner); // consume field name

  if (parser->current_token.type != TOK_SEMICOLON) {
    return report(parser->current_token.location, "expected ';' after struct field declaration.", 0);
  }

  parser->current_token = next_token(&parser->scanner); // consume ';'
  return new_field_decl_node(type_name, field_name);
}

// <structDecl>
// ::= 'struct' <identifier> '{' (<fieldDecl>)* '}'
ASTNode *parse_struct_decl(Parser *parser) {
  parser->current_token = next_token(&parser->scanner); // consume 'struct'
  // @TODO: generic structs
  if (parser->current_token.type != TOK_IDENTIFIER) {
    return report(parser->current_token.location, "expected identifier after 'struct'.", 0);
  }

  char struct_name[64];
  strncpy(struct_name, parser->current_token.text, sizeof(struct_name));

  parser->current_token = next_token(&parser->scanner); // consume struct name

  if (parser->current_token.type != TOK_LCURLY) {
    return report(parser->current_token.location, "expected '{' in struct declaration.", 0);
  }

  parser->current_token = next_token(&parser->scanner); // consume '{'

  ASTNode *field_list = NULL, *last_field = NULL;
  while (parser->current_token.type != TOK_RCURLY && parser->current_token.type != TOK_EOF) {
    ASTNode *field = parse_field_declaration(parser);

    if (!field_list) {
      field_list = last_field = field;
    } else {
      last_field->next = field;
      last_field = field;
    }
  }

  if (parser->current_token.type != TOK_RCURLY) {
    return report(parser->current_token.location, "expected '}' at the end of struct declaration.", 0);
  }
  parser->current_token = next_token(&parser->scanner); // consume '{'

  add_symbol(&parser->symbol_table, struct_name, SYMB_STRUCT, "struct");
  return new_struct_decl_node(struct_name, field_list);
}

// <parameterDecl>
// ::= (<type> <identifier>)*
ASTNode *parse_parameter_declaration(Parser *parser) {
  char type_name[64];
  if (parse_type_name(parser, type_name) != RESULT_SUCCESS)
    return NULL;
  if (parser->current_token.type != TOK_IDENTIFIER) {
    return report(parser->current_token.location, "expected identifier in parameter declaration.", 0);
  }
  char param_name[64];
  strncpy(param_name, parser->current_token.text, sizeof(param_name));
  parser->current_token = next_token(&parser->scanner); // consume name
  return new_param_decl_node(type_name, param_name);
}

ASTNode *parse_parameter_list(Parser *parser) {
  ASTNode *param_list = NULL, *last_param = NULL;

  // empty param list
  if (parser->current_token.type == TOK_RPAREN)
    return NULL;

  ASTNode *param = parse_parameter_declaration(parser);
  param_list = last_param = param;

  while (parser->current_token.type == TOK_COMMA) {
    parser->current_token = next_token(&parser->scanner); // consume comma
    param = parse_parameter_declaration(parser);
    last_param->next = param;
    last_param = param;
  }

  return param_list;
}

// @TODO: implement
// <block>
// ::= '{' (<statement>)* '}'
ASTNode *parse_block(Parser *parser) {
  if (parser->current_token.type != TOK_LCURLY) {
    return report(parser->current_token.location, "expected '{' to start block.", 0);
  }
  parser->current_token = next_token(&parser->scanner); // consume '{'

  int capacity = 8, count = 0;
  ASTNode **stmts = malloc(capacity * sizeof(ASTNode *));
  assert(stmts);

  while (parser->current_token.type != TOK_RCURLY && parser->current_token.type != TOK_EOF) {
    ASTNode *stmt = parse_stmt(parser);
    if (!stmt) {
      for (int i = 0; i < capacity; ++i) {
        free(stmts[i]);
      }
      free(stmts);
      return NULL;
    }
    if (count >= capacity) {
      capacity *= 2;
      stmts = realloc(stmts, capacity * sizeof(ASTNode *));
      assert(stmts);
    }
    stmts[count++] = stmt;
  }

  if (parser->current_token.type != TOK_RCURLY) {
    for (int i = 0; i < capacity; ++i) {
      free(stmts[i]);
    }
    free(stmts);
    return report(parser->current_token.location, "expected '}' to end the block.", 0);
  }

  parser->current_token = next_token(&parser->scanner);
  return new_block_node(stmts, count, capacity);
}

// <functionDecl>
// ::= <genericFuncDecl>
// | <basicFuncDecl>
//
// <basicFuncDecl>
// ::= 'fn' <type> <identifier> '(' <parameterList> ')' <block>
// @TODO: implement generic functions
ASTNode *parse_function_decl(Parser *parser) {
  parser->current_token = next_token(&parser->scanner); // consume 'fn'
  if ((parser->current_token.type < TOKENS_BUILTIN_TYPE_BEGIN || parser->current_token.type > TOKENS_BUILTIN_TYPE_END) &&
      parser->current_token.type == TOK_IDENTIFIER)
    return report(parser->current_token.location, "expected return type.", 0);

  char type[64];
  strncpy(type, parser->current_token.text, sizeof(type));
  parser->current_token = next_token(&parser->scanner); // consume return type

  if (parser->current_token.type != TOK_IDENTIFIER)
    return report(parser->current_token.location, "expected function identifier.", 0);

  char func_name[64];
  strncpy(func_name, parser->current_token.text, sizeof(func_name));
  parser->current_token = next_token(&parser->scanner); // consume function name

  if (parser->current_token.type != TOK_LPAREN) {
    return report(parser->current_token.location, "expected '(' after function name.", 0);
  }
  parser->current_token = next_token(&parser->scanner); // consume '('

  ASTNode *params = parse_parameter_list(parser);
  if (parser->current_token.type != TOK_RPAREN) {
    return report(parser->current_token.location, "expected ')' after parameter list.", 0);
  }
  parser->current_token = next_token(&parser->scanner); // consume ')'

  add_symbol(&parser->symbol_table, func_name, SYMB_FN, type);
  ASTNode *body = parse_block(parser);
  return new_func_decl_node(func_name, params, body);
}

// <globalDecl>
// ::= <varDecl>
//  | <funcDecl>
//  | <structDecl>
//  | <enumDecl>
//  | <externBlock>
ASTNode *parse_global_decl(Parser *parser) {
  if (parser->current_token.type == TOK_STRUCT) {
    return parse_struct_decl(parser);
  } else if (parser->current_token.type == TOK_FUNC) {
    return parse_function_decl(parser);
  } // @TODO: extern blocks, enums
  else {
    return parse_var_decl(parser);
  }
  return NULL;
}

// <globalDecl>* <EOF>
ASTNode *parse_input(Parser *parser) {
  ASTNode *global_list = NULL, *last = NULL;
  parser->current_token = next_token(&parser->scanner);
  while (parser->current_token.type != TOK_EOF) {
    ASTNode *decl = parse_global_decl(parser);
    if (!global_list) {
      global_list = last = decl;
    } else {
      last->next = decl;
      last = decl;
    }
  }
  return global_list;
}
