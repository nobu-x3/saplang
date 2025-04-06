#include "sema.h"
#include "parser.h"
#include "symbol_table.h"
#include "types.h"
#include "util.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int is_known_type(Symbol *table, const Type *source, int current_scope) {
	if (is_builtin(source))
		return 1;

	Symbol *sym = lookup_symbol(table, source->type_name, current_scope);
	if (!sym)
		return 0;

	return 1;
}

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
	if (source->kind == TYPE_POINTER) {
		return target->kind == TYPE_POINTER;
	}

	if (source->kind != TYPE_POINTER && target->kind == TYPE_POINTER) {
		return 0;
	}

	if (target->kind == TYPE_PRIMITIVE) {
		if (strcmp(target->type_name, "bool") == 0) {
			if (source->kind == TYPE_POINTER)
				return 1;

			if (source->kind == TYPE_PRIMITIVE)
				return 1;
		}
	}
	return 0;
}

Type *get_type(Symbol *table, ASTNode *node, int scope_level, const char *scope_specifier) {
	if (!node)
		return NULL;
	switch (node->type) {
	case AST_EXPR_LITERAL:
		if (node->data.literal.is_bool) {
			return new_primitive_type("bool");
		} else if (node->data.literal.is_float) {
			return new_primitive_type("f32");
		} else {
			return new_primitive_type("i32");
		}
		break;
	case AST_EXPR_IDENT: {
		char name_with_namespace[128] = "";
		if (node->data.ident.namespace[0] != '\0') {
			sprintf(name_with_namespace, "%s::%s", node->data.ident.namespace, node->data.ident.name);
		} else {
			sprintf(name_with_namespace, "%s", node->data.ident.name);
		}

		Symbol *sym = lookup_symbol_weak(table, name_with_namespace, scope_level);
		if (!sym) {
			if (scope_specifier[0] != '\0') {
				char resolved_same[128] = "";
				sprintf(resolved_same, "__%s", scope_specifier);
				if (node->data.ident.namespace[0] != '\0') {
					sprintf(resolved_same, "%s::%s_%s", node->data.ident.namespace, resolved_same, node->data.ident.name);
				} else {
					sprintf(resolved_same, "%s_%s", resolved_same, node->data.ident.name);
				}
				sym = lookup_symbol(table, resolved_same, scope_level);
				if (!sym)
					return NULL;
			}
		}
		return sym->type;
	}
	case AST_BINARY_EXPR:
		return get_type(table, node->data.binary_op.left, scope_level, scope_specifier);
	case AST_ASSIGNMENT:
		return get_type(table, node->data.assignment.lvalue, scope_level, scope_specifier);
	case AST_FN_DECL: {
		Symbol *sym = lookup_symbol(table, node->data.func_decl.name, scope_level);
		if (!sym) {
			return NULL;
		}
		return sym->type;
	}
	case AST_FN_CALL:
		return get_type(table, node->data.func_call.callee, scope_level, scope_specifier);
	case AST_CAST:
		return node->data.cast.target_type;
	case AST_RETURN:
		return get_type(table, node->data.ret.return_expr, scope_level, scope_specifier);
	default:
		return NULL;
	}
	return NULL;
}

CompilerResult analyze_expr_literal(Symbol *table, Type *lvalue_type, ASTNode *node, int scope_level, const char *scope_specifier) {
	Type *rtype = get_type(table, node, scope_level, scope_specifier);
	if (is_convertible(rtype, lvalue_type))
		rtype = copy_type(lvalue_type);
	else if (rtype) {
		char left_str[128] = "";
		char right_str[128] = "";
		type_print(left_str, node->data.var_decl.type);
		type_print(right_str, rtype);
		char msg[256] = "";
		sprintf(msg, "assignment type mismatch: cannot implicitly convert %s to %s.", right_str, left_str);
		report(node->location, msg, 0);
		return RESULT_FAILURE;
	} else {
		if (!rtype) {
			char msg[256] = "";
			sprintf(msg, "Could not determine the type of rvalue in variable initialization.");
			report(node->location, msg, 0);
		}
		return RESULT_FAILURE;
	}
	return RESULT_SUCCESS;
}

CompilerResult analyze_ast(Symbol *table, ASTNode *node, int scope_level, const char *scope_specifier) {
	if (!node)
		return RESULT_PASSED_NULL_PTR;

	switch (node->type) {
	case AST_VAR_DECL: {
		if (node->data.var_decl.is_const && !node->data.var_decl.init) {
			report(node->location, "const variable must have an initializer.", 0);
			return RESULT_FAILURE;
		}
		if (node->data.var_decl.init) {
			CompilerResult result;
			if (node->data.var_decl.init->type == AST_EXPR_LITERAL) {
				// TODO: type matching and implicit conversions
				assert(node->data.var_decl.type);
				if (!is_known_type(table, node->data.var_decl.type, scope_level)) {
					char type_str[128] = "";
					type_print(type_str, node->data.var_decl.type);
					char msg[128] = "";
					sprintf(msg, "unknown type %s.", type_str);
					report(node->location, msg, 0);
					return RESULT_FAILURE;
				}
				result = analyze_expr_literal(table, node->data.var_decl.type, node->data.var_decl.init, scope_level, scope_specifier);
			} else {
				result = analyze_ast(table, node->data.var_decl.init, scope_level, scope_specifier);
			}

			if (result != RESULT_SUCCESS) {
				return result;
			}

			Type *init_type = get_type(table, node->data.var_decl.init, scope_level, scope_specifier);
			if (!init_type) {
				return RESULT_FAILURE;
			}

			if (!is_convertible(init_type, node->data.var_decl.type)) {
				report(node->data.var_decl.init->location, "type mismatch in initializer.", 0);
				return RESULT_FAILURE;
			}
		}
		return RESULT_SUCCESS;
	} break;
	case AST_BLOCK: {
		CompilerResult result;
		for (int i = 0; i < node->data.block.count; ++i) {
			result = analyze_ast(table, node->data.block.statements[i], scope_level, scope_specifier);
			if (result != RESULT_SUCCESS)
				return result;
		}
	} break;
	case AST_EXPR_IDENT: {
		Symbol *non_var_sym = lookup_symbol_weak(table, node->data.ident.name, scope_level);
		if (!non_var_sym) {

			char resolved_name[128] = "";
			if (scope_specifier[0] != '\0')
				sprintf(resolved_name, "__%s_%s", scope_specifier, node->data.ident.name);
			else
				strncpy(resolved_name, node->data.ident.name, sizeof(resolved_name));

			Symbol *var_sym = lookup_symbol(table, resolved_name, scope_level);
			char msg[64] = "";
			sprintf(msg, "undeclared identifier %s.", node->data.ident.name);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
	} break;
	case AST_RETURN: {
		break;
	}
	case AST_BINARY_EXPR: {
		CompilerResult result = analyze_ast(table, node->data.binary_op.left, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;

		result = analyze_ast(table, node->data.binary_op.right, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;

		Type *ltype = get_type(table, node->data.binary_op.left, scope_level, scope_specifier);
		Type *rtype = get_type(table, node->data.binary_op.right, scope_level, scope_specifier);
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
		CompilerResult result = analyze_ast(table, node->data.assignment.lvalue, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;

		if (node->data.assignment.lvalue->type == AST_EXPR_IDENT) {
			// This should never be NULL at this point because we passed the analyze_ast call above
			char resolved_name[128] = "";
			if (scope_specifier[0] != '\0')
				sprintf(resolved_name, "__%s_%s", scope_specifier, node->data.assignment.lvalue->data.ident.name);
			else
				strncpy(resolved_name, node->data.assignment.lvalue->data.ident.name, sizeof(resolved_name));

			Symbol *sym = lookup_symbol(table, resolved_name, scope_level);
			if (sym->is_const) {
				char msg[256] = "";
				sprintf(msg, "cannot assign a value to a const variable %s.", node->data.assignment.lvalue->data.ident.name);
				report(node->location, msg, 0);
				return RESULT_FAILURE;
			}
		} else if (node->data.assignment.lvalue->type == AST_EXPR_LITERAL) {
			char msg[256] = "";
			sprintf(msg, "cannot assign a value to a literal.");
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}

		Type *ltype = get_type(table, node->data.assignment.lvalue, scope_level, scope_specifier);
		if (node->data.assignment.rvalue->type == AST_EXPR_LITERAL) {
			// TODO: type matching and implicit conversions
			result = analyze_expr_literal(table, ltype, node->data.assignment.rvalue, scope_level, scope_specifier);
		} else {
			result = analyze_ast(table, node->data.assignment.rvalue, scope_level, scope_specifier);
		}

		if (result != RESULT_SUCCESS)
			return result;

		Type *rtype = get_type(table, node->data.assignment.rvalue, scope_level, scope_specifier);
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
		CompilerResult result = analyze_ast(table, node->data.func_call.callee, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;

		// Previous call to analyze_ast would fail if the symbol didn't exist
		Symbol *sym = lookup_symbol(table, node->data.func_call.callee->data.ident.name, 0);
		if (sym->node->type != AST_FN_DECL || sym->kind != SYMB_FN) {
			char msg[256] = "";
			sprintf(msg, "symbol %s is not a function but used as a function.", node->data.func_call.callee->data.ident.name);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}

		// @TODO: cache this probably
		int param_count = 0;
		ASTNode *param = sym->node->data.func_decl.params;
		while (param) {
			++param_count;
			param = param->next;
		}

		if (param_count != node->data.func_call.arg_count) {
			char msg[256] = "";
			sprintf(msg, "argument count mismatch.");
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}

		param = sym->node->data.func_decl.params;
		for (int i = 0; i < node->data.func_call.arg_count; ++i) {
			result = analyze_ast(table, node->data.func_call.args[i], scope_level, scope_specifier);
			Type *param_type = param->data.param_decl.type;
			Type *arg_type = get_type(table, node->data.func_call.args[i], sym->scope_level + 1, scope_specifier);
			if (!is_convertible(arg_type, param_type)) {
				char left_str[128] = "";
				char right_str[128] = "";
				type_print(left_str, param_type);
				type_print(right_str, arg_type);
				char msg[256] = "";
				sprintf(msg, "cannot implicitly convert from type %s to type %s in function call %s.", right_str, left_str, sym->name);
				report(node->location, msg, 0);
				result = RESULT_FAILURE;
			}
			param = param->next;
		}
		return result;
	} break;

	case AST_FN_DECL: {
		Symbol *sym = lookup_symbol(table, node->data.func_decl.name, scope_level);
		if (!sym) {
			char msg[256] = "";
			sprintf(msg, "function %s undefined.", node->data.func_decl.name);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}

		if (node->data.func_decl.params) {
			CompilerResult result;
			ASTNode *param = node->data.func_decl.params;
			while (param) {
				result = analyze_ast(table, param, scope_level + 1, node->data.func_decl.name);
				param = param->next;
			}
			if (result != RESULT_SUCCESS)
				return result;
		}

		if (node->data.func_decl.body) {
			CompilerResult result = analyze_ast(table, node->data.func_decl.body, scope_level + 1, node->data.func_decl.name);
			if (result != RESULT_SUCCESS)
				return result;

			if (node->data.func_decl.body->data.block.count) {
				ASTNode *last_stmt = node->data.func_decl.body->data.block.statements[node->data.func_decl.body->data.block.count - 1];
				if (last_stmt && last_stmt->type == AST_RETURN) {
					Type *ret_type = get_type(table, last_stmt, scope_level + 1, scope_specifier);
					if (!ret_type) {
						return RESULT_FAILURE;
					}
					if (!is_convertible(ret_type, sym->type)) {
						char msg[256] = "";
						char expr_type_str[64] = "";
						type_print(expr_type_str, ret_type);
						char decl_type_str[64] = "";
						type_print(decl_type_str, sym->type);
						sprintf(msg, "function return type is %s but returned value is of type %s.", decl_type_str, expr_type_str);
						report(last_stmt->location, msg, 0);
						return RESULT_FAILURE;
					}
				}
			}
		}
	} break;

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
	// Want to handle these where they are used
	case AST_EXPR_LITERAL:
		break;
	case AST_PARAM_DECL:
		break;
	case AST_CAST: {
		CompilerResult result = analyze_ast(table, node->data.cast.expr, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS) {
			return result;
		}
		Type *expr_type = get_type(table, node->data.cast.expr, scope_level, scope_specifier);
		if (!is_convertible(expr_type, node->data.cast.target_type)) {
			char msg[256] = "";
			char src_type[64] = "";
			type_print(src_type, expr_type);
			char target_type[64] = "";
			type_print(target_type, node->data.cast.target_type);
			sprintf(msg, "cannot convert type %s into type %s.", src_type, target_type);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		return RESULT_SUCCESS;
	}
	case AST_WHILE_LOOP: {
		CompilerResult result = analyze_ast(table, node->data.while_loop.condition, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;

		Type bool_type = get_primitive_type("bool");
		Type *condition_type = get_type(table, node->data.while_loop.condition, scope_level, scope_specifier);
		if (!is_convertible(condition_type, &bool_type)) {
			char condition_type_str[128] = "";
			type_print(condition_type_str, condition_type);
			char msg[128] = "";
			sprintf(msg, "while loop condition must convert to bool but is of type %s .", condition_type_str);
			report(node->data.while_loop.condition->location, msg, 0);
			return RESULT_FAILURE;
		}

		result = analyze_ast(table, node->data.while_loop.body, scope_level + 1, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;

	} break;
	case AST_FOR_LOOP: {
		CompilerResult result = analyze_ast(table, node->data.for_loop.init, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;

		result = analyze_ast(table, node->data.for_loop.condition, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;

		Type bool_type = get_primitive_type("bool");
		Type *condition_type = get_type(table, node->data.for_loop.condition, scope_level, scope_specifier);
		if (!is_convertible(condition_type, &bool_type)) {
			char condition_type_str[128] = "";
			type_print(condition_type_str, condition_type);
			char msg[128] = "";
			sprintf(msg, "for loop condition must convert to bool but is of type %s .", condition_type_str);
			report(node->data.while_loop.condition->location, msg, 0);
			return RESULT_FAILURE;
		}

		result = analyze_ast(table, node->data.for_loop.post, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;

		result = analyze_ast(table, node->data.for_loop.body, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;

	} break;
	default:
		report(node->location, "sema: unsupported node type.", 1);
		break;
	}
	return RESULT_SUCCESS;
}
