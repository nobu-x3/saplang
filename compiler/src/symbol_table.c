#include "symbol_table.h"
#include "parser.h"
#include "types.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

CompilerResult symbol_table_print(Symbol *table, char *string) {
	if (!table)
		return RESULT_PASSED_NULL_PTR;

	int max_name_len = 0;
	int max_type_len = 0;
	for (Symbol *sym = table; sym; sym = sym->next) {
		int name_len = strlen(sym->name);
		max_name_len = name_len > max_name_len ? name_len : max_name_len;
		int type_len = type_get_string_len(sym->type, 0);
		max_type_len = type_len > max_type_len ? type_len : max_type_len;
	}

	print(string, "Symbol Type\tName");
	for (int i = 0; i <= max_name_len - 4 - 1; ++i) {
		print(string, " ");
	}

	print(string, "\tConst");

	print(string, "\tType");

	for (int i = 0; i <= max_type_len - 4 - 1; ++i) {
		print(string, " ");
	}

	print(string, "\tScope\tSize\tAlignment\n");

	for (Symbol *sym = table; sym; sym = sym->next) {
		if (sym->kind == SYMB_VAR) {
			print(string, "Variable    \t%s", sym->name);
		} else if (sym->kind == SYMB_STRUCT) {
			print(string, "Struct     \t%s", sym->name);
		} else if (sym->kind == SYMB_FN) {
			print(string, "Fn         \t%s", sym->name);
		} else if (sym->kind == SYMB_ENUM) {
			print(string, "Enum       \t%s", sym->name);
		}

		int cur_name_len = strlen(sym->name);
		for (int i = 0; i <= max_name_len - cur_name_len - 1; ++i) {
			print(string, " ");
		}

		print(string, "\t%d\t", sym->is_const);

		type_print(string, sym->type);

		int type_len = type_get_string_len(sym->type, 0);
		for (int i = 0; i <= max_type_len - type_len - 1; ++i) {
			print(string, " ");
		}

		print(string, "\t%d\t%zu\t%zu\n", sym->scope_level, sym->size, sym->alignment);
	}
	return RESULT_SUCCESS;
}

CompilerResult add_symbol(Symbol **table, ASTNode *node, const char *name, const char *resolved_name, int is_const, SymbolKind kind, Type *type, int scope_level) {
	if (!table)
		return RESULT_PASSED_NULL_PTR;

	Symbol *symb = malloc(sizeof(Symbol));
	if (!symb)
		return RESULT_MEMORY_ERROR;

	strncpy(symb->name, name, sizeof(symb->name));
	strncpy(symb->resolved_name, resolved_name, sizeof(symb->resolved_name));
	symb->type = copy_type(type);
	symb->kind = kind;
	symb->scope_level = scope_level;
	symb->is_const = is_const;
	symb->size = 0;
	symb->alignment = 0;
	symb->node = node;
	symb->next = *table;
	*table = symb;
	return RESULT_SUCCESS;
}

CompilerResult add_symbol_with_type_info(Symbol **table, ASTNode *node, const char *name, const char *resolved_name, int is_const, SymbolKind kind, Type *type, int scope_level, size_t size, size_t align) {
	if (!table)
		return RESULT_PASSED_NULL_PTR;

	Symbol *symb = malloc(sizeof(Symbol));
	if (!symb)
		return RESULT_MEMORY_ERROR;

	strncpy(symb->name, name, sizeof(symb->name));
	strncpy(symb->resolved_name, resolved_name, sizeof(symb->resolved_name));
	symb->type = type;
	symb->kind = kind;
	symb->scope_level = scope_level;
	symb->is_const = is_const;
	symb->size = size;
	symb->alignment = align;
	symb->node = node;
	symb->next = *table;
	*table = symb;
	return RESULT_SUCCESS;
}

CompilerResult deinit_symbol_table(Symbol *table) {
	for (Symbol *sym = table; sym != NULL;) {
		Symbol *next = sym->next;
		type_deinit(sym->type);
		free(sym->type);
		free(sym);
		sym = next;
	}
	return RESULT_SUCCESS;
}

Symbol *lookup_symbol(Symbol *table, const char *resolved_name, int current_scope) {
	for (Symbol *s = table; s != NULL; s = s->next) {
		if (strcmp(s->resolved_name, resolved_name) == 0 && s->scope_level <= current_scope)
			return s;
	}
	return NULL;
}

Symbol *lookup_symbol_weak(Symbol *table, const char *name, int current_scope) {
	for (Symbol *s = table; s != NULL; s = s->next) {
		if (strcmp(s->name, name) == 0 && s->scope_level <= current_scope && s->type != SYMB_VAR)
			return s;
	}
	return NULL;
}

Symbol *symbol_table_copy(Symbol *table) {
	Symbol *new_table = malloc(sizeof(Symbol));

	new_table->type = copy_type(table->type);
	new_table->node = table->node;
	new_table->is_const = table->is_const;
	new_table->kind = table->kind;
	new_table->alignment = table->alignment;
	new_table->size = table->size;
	new_table->scope_level = table->scope_level;
	new_table->next = NULL;
	strncpy(new_table->name, table->name, sizeof(new_table->name));
	strncpy(new_table->resolved_name, table->resolved_name, sizeof(new_table->resolved_name));

	Symbol *current = table->next;
	while (current) {
		Type *type_copy = copy_type(current->type);
		ASTNode *node = current->node;
		add_symbol_with_type_info(&new_table, node, current->name, current->resolved_name, current->is_const, current->kind, type_copy, current->scope_level, current->size, current->alignment);
		current = current->next;
	}

	return new_table;
}

Symbol *symbol_table_merge(Symbol *external, Symbol *internal) {
	if (!external)
		return internal;

	Symbol *new_root = symbol_table_copy(external);
	Symbol *current_ext = new_root;
	while (current_ext->next) {
		current_ext = current_ext->next;
	}
	current_ext->next = internal;
	return new_root;
}

void set_size(Symbol *symbol) {
	if (!symbol)
		return;

	Type *type = symbol->type;
	if (!type)
		return;

	TypeInfo info = get_type_info(type, symbol->node);
	symbol->size = info.size;
	symbol->alignment = info.align;
}

void symbol_table_set_type_info(Symbol *table) {
	Symbol *current = table;
	while (current) {
		set_size(current);
		current = current->next;
	}
}
