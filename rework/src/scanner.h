#pragma once
#include "util.h"
#include <stdlib.h>

typedef enum {
	TOK_STRUCT,		// "struct"
	TOK_FN,		// "func"
	TOK_IDENTIFIER, // e.g. variable, struct, or function names
	TOK_NUMBER,		// Numeric literals
	TOK_ASSIGN,		// '='
	TOK_SEMICOLON,	// ';'
	TOK_LCURLY,		// '{'
	TOK_RCURLY,		// '}'
	TOK_LPAREN,		// '('
	TOK_RPAREN,		// ')'
	TOK_LBRACKET,	// '['
	TOK_RBRACKET,	// ']'
	TOK_COMMA,		// ','
	TOK_CONST,		// 'const'
	TOK_RETURN,		// 'return'
	TOK_PLUS,
	TOK_DOT,
	TOK_MINUS,
	TOK_ASTERISK,
	TOK_SLASH,
	TOK_AMPERSAND,
	TOK_EXCLAMATION,
    TOK_LESSTHAN,
    TOK_GREATERTHAN,
    TOK_EQUAL,
    TOK_NOTEQUAL,
    TOK_LTOE,
    TOK_GTOE,
    TOK_SELFADD,
    TOK_SELFSUB,
    TOK_SELFMUL,
    TOK_SELFDIV,
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
	TOK_VOID,
	TOK_BOOL,
	TOK_TRUE,
	TOK_FALSE,
	TOK_ENUM,
	TOK_COLON,
	TOK_COLONCOLON,
	TOK_EXTERN,
	TOK_EXPORT,
	TOK_IMPORT,
	TOK_DOTDOTDOT,
    TOK_IF,
    TOK_ELSE,
    TOK_FOR,
    TOK_WHILE,
    TOK_DEFER,
    TOK_FN_PTR,
	TOKENS_BUILTIN_TYPE_BEGIN = TOK_I8,
	TOKENS_BUILTIN_TYPE_END = TOK_BOOL,
} TokenType;

typedef struct {
	TokenType type;
	char text[64];
	SourceLocation location;
} Token;

typedef struct {
	SourceFile source;
	size_t id;
	int line;
	int col;
	int is_reading_string;
} Scanner;

CompilerResult scanner_init_from_string(Scanner *scanner, const char *path, const char *input);

CompilerResult scanner_init_from_src(Scanner *scanner, SourceFile file);

CompilerResult scanner_deinit(Scanner *scanner);

Token next_token(Scanner *scanner);
