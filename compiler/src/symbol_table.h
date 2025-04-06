#pragma once

#include "types.h"
#include "util.h"

typedef enum {
	SYMB_VAR,
	SYMB_STRUCT,
	SYMB_FN,
	SYMB_ENUM,
	SYMB_UNION,
} SymbolKind;

typedef struct Symbol {
	char name[64];
	char resolved_name[128];
	Type *type;
	int scope_level;
	SymbolKind kind;
	int is_const;
	struct ASTNode *node; // not owning
	size_t size;
	size_t alignment;
	struct Symbol *next;
} Symbol;

CompilerResult symbol_table_print(Symbol *table, char *string);

CompilerResult add_symbol(Symbol **table, struct ASTNode *node, const char *name, const char *resolved_name, int is_const, SymbolKind kind, Type *type, int scope_level);

CompilerResult deinit_symbol_table(Symbol *table);

Symbol *lookup_symbol(Symbol *table, const char *name, int current_scope);

Symbol *lookup_symbol_weak(Symbol *table, const char *name, int current_scope);

Symbol *symbol_table_copy(Symbol *table);

void symbol_table_set_type_info(Symbol *table);

Symbol* symbol_table_merge(Symbol *external, Symbol *internal);
