#include "parser.h"
#include "scanner.h"
#include "util.h"
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
    case AST_VAR_DECL:
      print(string, "VarDecl: %s %s = ...\n", node->data.var_decl.type_name, node->data.var_decl.name);
      break;
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
    sprintf(msg, "expected type name, get '%s'.", parser->current_token.text);
    report(parser->current_token.location, msg, 0);
    return RESULT_PARSING_ERROR;
  }
  }
  return RESULT_SUCCESS;
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
ASTNode *parse_block(Parser *parser) { return NULL; }

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
  /* else { */
  /*   return parse_var_decl(parser); */
  /* } */
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
