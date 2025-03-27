#include "sema.h"
#include "parser.h"
#include "symbol_table.h"
#include "types.h"
#include "util.h"
#include <stdio.h>
#include <string.h>

int is_convertible(const Type *source, const Type *target) {
	if (!source || !target)
		return 0;

	// Allow identical types
	if (type_equals(source, target))
		return 1;

	// Allow array decay
	if (source->kind == TYPE_ARRAY && target->kind == TYPE_POINTER) {
		// Could call for is_convertible on underlying types but easier to debug non-recursive code
		int decay_count = 1;
		Type *underlying_array_type = source->array.element_type;
		while (underlying_array_type && underlying_array_type->kind == TYPE_ARRAY) {
			++decay_count;
			underlying_array_type = underlying_array_type->array.element_type;
		}

		int pointer_count = 1;
		Type *underlying_pointer_type = target->pointee;
		while (underlying_pointer_type && underlying_pointer_type->kind == TYPE_POINTER) {
			++pointer_count;
			underlying_pointer_type = underlying_pointer_type->pointee;
		}

		return pointer_count == decay_count && type_equals(underlying_array_type, underlying_pointer_type);
	}
	return 0;
}

Type *get_type(Symbol *table, ASTNode *node, int scope_level) {
	if (!node)
		return NULL;
	switch (node->type) {
	case AST_EXPR_LITERAL:
		break;
	case AST_EXPR_IDENT: {
		char full_name[128] = "";
		if (node->data.ident.namespace[0] != '\0') {
			sprintf(full_name, "%s::%s", node->data.ident.namespace, node->data.ident.name);
		} else {
			sprintf(full_name, "%s", node->data.ident.name);
		}
		Symbol *sym = lookup_symbol(table, full_name, scope_level);
		if (!sym) {
			return NULL;
		}
		return sym->type;
	}
	case AST_BINARY_EXPR:
		return get_type(table, node->data.binary_op.left, scope_level);
	case AST_ASSIGNMENT:
		return get_type(table, node->data.assignment.lvalue, scope_level);
	default:
		return NULL;
	}
	return NULL;
}

/* ASTNode *insert_implicit_cast(ASTNode *expr, const char *target_type) {} */

CompilerResult analyze_ast(Symbol *table, ASTNode *node, int scope_level) {
	if (!node)
		return RESULT_PASSED_NULL_PTR;

	switch (node->type) {
	case AST_VAR_DECL:
		if (node->data.var_decl.init) {
			CompilerResult result = analyze_ast(table, node->data.var_decl.init, scope_level);
			if (result != RESULT_SUCCESS) {
				return result;
			}

			Type *init_type = get_type(table, node->data.var_decl.init, scope_level);
			if (!init_type) {
				return RESULT_FAILURE;
			}

			if (!is_convertible(init_type, node->data.var_decl.type)) {
				report(node->data.var_decl.init->location, "type mismatch in initializer.", 0);
				return RESULT_FAILURE;
			}
		}
		return RESULT_SUCCESS;
	case AST_BLOCK: {
		CompilerResult result;
		for (int i = 0; i < node->data.block.count; ++i) {
			result = analyze_ast(table, node->data.block.statements[i], scope_level);
			if (result != RESULT_SUCCESS)
				return result;
		}
	} break;
	case AST_EXPR_IDENT: {
		Symbol *sym = lookup_symbol(table, node->data.ident.name, scope_level);
		if (!sym) {
			char msg[64] = "";
			sprintf(msg, "undeclared identifier %s.", node->data.ident.name);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
	} break;
	case AST_RETURN: {
		CompilerResult result = RESULT_SUCCESS;
		if (node->data.ret.return_expr)
			result = analyze_ast(table, node, scope_level);
		return result;
	}
	case AST_BINARY_EXPR: {
		CompilerResult result = analyze_ast(table, node->data.binary_op.left, scope_level);
		if (result != RESULT_SUCCESS)
			return result;

		result = analyze_ast(table, node->data.binary_op.right, scope_level);
		if (result != RESULT_SUCCESS)
			return result;

		Type *ltype = get_type(table, node->data.binary_op.left, scope_level);
		Type *rtype = get_type(table, node->data.binary_op.right, scope_level);
		if (!is_convertible(rtype, ltype)) {
			char left_str[128] = "";
			char right_str[128] = "";
			type_print(left_str, ltype);
			type_print(right_str, rtype);
			char msg[256] = "";
			sprintf(msg, "binary operator type mismatch: cannot implicitly convert %s to %s.", right_str, left_str);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
	} break;
	case AST_ASSIGNMENT: {
		CompilerResult result = analyze_ast(table, node->data.assignment.lvalue, scope_level);
		if (result != RESULT_SUCCESS)
			return result;

		result = analyze_ast(table, node->data.assignment.rvalue, scope_level);
		if (result != RESULT_SUCCESS)
			return result;

		Type *ltype = get_type(table, node->data.assignment.lvalue, scope_level);
		Type *rtype = get_type(table, node->data.assignment.rvalue, scope_level);
		if (!is_convertible(rtype, ltype)) {
			char left_str[128] = "";
			char right_str[128] = "";
			type_print(left_str, ltype);
			type_print(right_str, rtype);
			char msg[256] = "";
			sprintf(msg, "assignment type mismatch: cannot implicitly convert %s to %s.", right_str, left_str);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		return RESULT_SUCCESS;
	} break;
	case AST_FN_CALL: {
		CompilerResult result = analyze_ast(table, node->data.func_call.callee, scope_level);
		if (result != RESULT_SUCCESS)
			return result;

		for (int i = 0; i < node->data.func_call.arg_count; ++i) {
			result = analyze_ast(table, node->data.func_call.args[i], scope_level);
		}
	} break;

	case AST_FN_DECL:
		if (!lookup_symbol(table, node->data.func_decl.name, scope_level)) {
			char msg[256] = "";
			sprintf(msg, "function %s undefined.", node->data.func_decl.name);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		if (node->data.func_decl.params) {
			CompilerResult result = analyze_ast(table, node->data.func_decl.params, scope_level + 1);
			if (result != RESULT_SUCCESS)
				return result;
		}
		if (node->data.func_decl.body) {
			CompilerResult result = analyze_ast(table, node->data.func_decl.body, scope_level + 1);
			if (result != RESULT_SUCCESS)
				return result;
		}
		break;

	case AST_STRUCT_DECL:
		if (!lookup_symbol(table, node->data.struct_decl.name, scope_level)) {
			char msg[256] = "";
			sprintf(msg, "struct %s undefined.", node->data.struct_decl.name);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		break;
	case AST_ENUM_DECL:
		if (!lookup_symbol(table, node->data.enum_decl.name, scope_level)) {
			char msg[256] = "";
			sprintf(msg, "enum %s undefined.", node->data.enum_decl.name);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		break;
	default:
		report(node->location, "sema: unsupported node type.", 1);
		break;
	}
	return RESULT_SUCCESS;
}

void merge_tables(Symbol *external, Symbol *internal) {
	if (!external)
		return;

	Symbol *current_ext = external;
	while (current_ext->next) {
		current_ext = current_ext->next;
	}
	current_ext->next = internal;
}
