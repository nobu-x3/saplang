#include "symbol_table.h"
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

	print(string, "\tScope\n");

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

		print("\t", "%d", sym->is_const);

		print(string, "\t");
		type_print(string, sym->type);

		int type_len = type_get_string_len(sym->type, 0);
		for (int i = 0; i <= max_type_len - type_len - 1; ++i) {
			print(string, " ");
		}

		print(string, "\t%d\n", sym->scope_level)
	}
	return RESULT_SUCCESS;
}

CompilerResult add_symbol(Symbol **table, const char *name, int is_const, SymbolKind kind, Type *type, int scope_level) {
	if (!table)
		return RESULT_PASSED_NULL_PTR;

	Symbol *symb = malloc(sizeof(Symbol));
	if (!symb)
		return RESULT_MEMORY_ERROR;

	strncpy(symb->name, name, sizeof(symb->name));
	symb->type = copy_type(type);
	symb->kind = kind;
	symb->scope_level = scope_level;
    symb->is_const = is_const;
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

Symbol *lookup_symbol(Symbol *table, const char *name, int current_scope) {
	for (Symbol *s = table; s != NULL; s = s->next) {
		if (strcmp(s->name, name) == 0 && s->scope_level <= current_scope)
			return s;
	}
	return NULL;
}

Symbol *symbol_table_copy(Symbol *table) {
	Symbol *new_table = malloc(sizeof(Symbol));

	Symbol *current = table;
	while (current) {
		Type *type_copy = copy_type(current->type);
		add_symbol(&new_table, current->name, current->is_const, current->kind, type_copy, current->scope_level);
		current = current->next;
	}

	return new_table;
}
