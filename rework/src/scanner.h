#pragma once
#include <stdlib.h>

typedef enum {
  TOK_STRUCT,     // "struct"
  TOK_FUNC,       // "func"
  TOK_IDENTIFIER, // e.g. variable, struct, or function names
  TOK_NUMBER,     // Numeric literals
  TOK_ASSIGN,     // '='
  TOK_SEMICOLON,  // ';'
  TOK_LCURLY,     // '{'
  TOK_RCURLY,     // '}'
  TOK_LPAREN,     // '('
  TOK_RPAREN,     // ')'
  TOK_COMMA,      // ','
  TOK_EOF,
  TOK_UNKNOWN,
  TOK_I8,
  TOK_I16,
  TOK_I32,
  TOK_I64,
  TOK_U8,
  TOK_U16,
  TOK_U32,
  TOK_U64,
  TOK_F32,
  TOK_F64,
  TOK_BOOL,
  TOK_TRUE,
  TOK_FALSE,
} TokenType;

typedef struct {
  TokenType type;
  char text[64];
} Token;

typedef struct {
  const char *path;
  const char *buffer;
} SourceFile;

typedef struct {
  const char *path;
  int line;
  int col;
  size_t id;
} SourceLocation;

typedef struct {
  SourceFile *source;
  size_t id;
  int line;
  int col;
} Scanner;

Token next_token(Scanner *scanner);
