#pragma once
#include "scanner.h"
#include "util.h"

typedef enum {
	SYMB_VAR,
	SYMB_STRUCT,
	SYMB_FN,
} SymbolKind;

typedef struct {
	char field[64]; // if designated, holds field name, otherwise empty
	int is_designated;
	struct ASTNode *expr;
} FieldInitializer;

typedef struct {
	char name[64];
	long value;
} EnumMember;

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

typedef struct {
	char **data;
	int capacity, count;
} ImportList;

typedef enum {
	AST_VAR_DECL,
	AST_STRUCT_DECL,
	AST_FUNC_DECL,
	AST_FIELD_DECL,
	AST_PARAM_DECL,
	AST_BLOCK,
	AST_EXPR_LITERAL,
	AST_EXPR_IDENT,
	AST_RETURN,
	AST_BINARY_EXPR,
	AST_UNARY_EXPR,
	AST_ARRAY_LITERAL,
	AST_ARRAY_ACCESS,
	AST_ASSIGNMENT,
	AST_FUNC_CALL,
	AST_MEMBER_ACCESS,
	AST_STRUCT_LITERAL,
	AST_ENUM_DECL,
	AST_ENUM_VALUE,
	AST_EXTERN_BLOCK,
	AST_EXTERN_FUNC_DECL,
} ASTNodeType;

typedef struct ASTNode {
	ASTNodeType type;
	ImportList import_list;
	struct ASTNode *next; // For linked lists (e.g. global declarations, fields, params)
	union {
		// Variable declaration: <type> name = init;
		struct {
			char type_name[64];
			char name[64];
			int is_const;
			int is_exported;
			struct ASTNode *init; // Expression node
		} var_decl;
		// Struct declaration: struct Name { fields }
		struct {
			char name[64];
			int is_exported;
			struct ASTNode *fields; // Linked list of field declarations
		} struct_decl;
		// Function declaration: func name(params) { body }
		struct {
			char name[64];
			int is_exported;
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
			int is_const;
			int is_va;
			char type_name[64];
			char name[64];
		} param_decl;
		// Block: a list of statements
		struct {
			struct ASTNode **statements;
			int count;
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
		struct {
			char op;
			struct ASTNode *operand;
		} unary_op;
		struct {
			struct ASTNode **elements;
			int count;
		} array_literal;
		struct {
			struct ASTNode *base;
			struct ASTNode *index;
		} array_access;
		struct {
			struct ASTNode *lvalue;
			struct ASTNode *rvalue;
		} assignment;
		struct {
			struct ASTNode *callee;
			struct ASTNode **args;
			int arg_count;
		} func_call;
		struct {
			struct ASTNode *base;
			char member[64];
		} member_access;
		struct {
			FieldInitializer **inits;
			int count;
		} struct_literal;
		struct {
			char name[64];
			char base_type[64];	  // i32 by default
			EnumMember **members; // Dynamic array of members
			int is_exported;
			int member_count;
		} enum_decl;
		struct {
			char enum_type[64];
			char member[64];
		} enum_value;
		struct {
			char lib_name[64];
			struct ASTNode **block;
			int count;
		} extern_block;
		struct {
			char name[64];
			int is_exported;
			struct ASTNode *params; // Linked list of parameter declarations
		} extern_func;
	} data;
} ASTNode;

CompilerResult parser_init(Parser *parser, Scanner scanner, Symbol *optional_table);

CompilerResult parser_deinit(Parser *parser);

CompilerResult symbol_table_print(Symbol *table, char *string);

ASTNode *parse_input();

CompilerResult ast_print(ASTNode *node, int indent, char *string);
