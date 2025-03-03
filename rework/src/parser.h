#pragma once
#include "scanner.h"
#include "util.h"

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
	struct Symbol *next;
} Symbol;

typedef struct Parser {
	Scanner scanner;
	Symbol *symbol_table;
	Token current_token;
} Parser;

typedef enum { AST_VAR_DECL, AST_STRUCT_DECL, AST_FUNC_DECL, AST_FIELD_DECL, AST_PARAM_DECL, AST_BLOCK, AST_EXPR_LITERAL, AST_EXPR_IDENT, AST_RETURN, AST_BINARY_EXPR } ASTNodeType;

typedef struct ASTNode {
	ASTNodeType type;
	struct ASTNode *next; // For linked lists (e.g. global declarations, fields, params)
	union {
		// Variable declaration: <type> name = init;
		struct {
			char type_name[64];
			char name[64];
			struct ASTNode *init; // Expression node
			int is_const;
		} var_decl;
		// Struct declaration: struct Name { fields }
		struct {
			char name[64];
			struct ASTNode *fields; // Linked list of field declarations
		} struct_decl;
		// Function declaration: func name(params) { body }
		struct {
			char name[64];
			struct ASTNode *params; // Linked list of parameter declarations
			struct ASTNode *body;	// Block node
		} func_decl;
		// Field declaration inside struct: <type> name;
		struct {
			char type_name[64];
			char name[64];
		} field_decl;
		// Parameter declaration: <type> name
		struct {
			char type_name[64];
			char name[64];
		} paramDecl;
		// Block: a list of statements
		struct {
			struct ASTNode **statements;
			int count;
			int capacity;
		} block;
		// Literal expression: integer, float, or bool
		struct {
			long long_value;
			double float_value;
			int is_float;	// 1 if float literal
			int bool_value; // 1 for true, 0 for false
			int is_bool;	// 1 if bool literal
		} literal;
		// Identifier expression.
		struct {
			char name[64];
		} ident;
		// Return statement
		struct {
			struct ASTNode *return_expr;
		} ret;
		// Binary expression
		struct {
			char op;
			struct ASTNode *left;
			struct ASTNode *right;
		} binary_op;
	} data;
} ASTNode;

CompilerResult parser_init(Parser *parser, Scanner scanner, Symbol *optional_table);

CompilerResult parser_deinit(Parser *parser);

CompilerResult symbol_table_print(Symbol *table, char *string);

ASTNode *parse_input();

CompilerResult ast_print(ASTNode *node, int indent, char *string);
