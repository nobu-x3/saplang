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

Type *get_type(Symbol *table, ASTNode *node, int scope_level, const char *scope_specifier) {
	if (!node)
		return NULL;
	switch (node->type) {
	case AST_EXPR_LITERAL:
		if (node->data.literal.is_bool) {
			return get_primitive_bool();
		} else if (node->data.literal.is_float) {
			return get_primitive_f32();
		} else {
			return get_primitive_i32();
		}
		break;

	case AST_EXPR_IDENT: {
		Symbol *sym = lookup_symbol(table, node->data.ident.resolved_name, scope_level);
		if (!sym) {
			if (node->data.ident.resolved_name[0] == '\0') {
				char resolved_name[128] = "";
				if (scope_specifier[0] != '\0') {
					sprintf(resolved_name, "__%s", scope_specifier);
					if (node->data.ident.namespace[0] != '\0') {
						sprintf(resolved_name, "__%s_%s", node->data.ident.namespace, node->data.ident.name);
					} else {
						sprintf(resolved_name, "%s_%s", resolved_name, node->data.ident.name);
					}
				} else {
					strncpy(resolved_name, node->data.ident.name, sizeof(resolved_name));
				}
				sym = lookup_symbol(table, resolved_name, scope_level);
				if (!sym)
					return NULL;
			} else {
				sym = lookup_symbol(table, node->data.ident.resolved_name, scope_level);
				if (!sym)
					return NULL;
			}
		}
		if (sym->kind == SYMB_FN)
			return sym->type->function.return_type;
		return sym->type;
	}

	case AST_BINARY_EXPR:
		return get_type(table, node->data.binary_op.left, scope_level, scope_specifier);

	case AST_ASSIGNMENT:
		return get_type(table, node->data.assignment.lvalue, scope_level, scope_specifier);

	case AST_FN_DECL: {
		Symbol *sym = lookup_symbol(table, node->data.func_decl.resolved_name, scope_level);
		if (!sym) {
			return NULL;
		}
		return sym->type->function.return_type;
	}

	case AST_FN_CALL:
		return get_type(table, node->data.func_call.callee, scope_level, scope_specifier);

	case AST_CAST:
		return node->data.cast.target_type;

	case AST_MEMBER_ACCESS: {
		ASTNode *base_node = node->data.member_access.base;
		Type *base_type = get_type(table, base_node, scope_level, scope_specifier);
		if (!base_type) {
			return NULL;
		}
		Symbol *decl_sym = lookup_named_type(table, base_type, scope_level);
		if (!decl_sym)
			return NULL;
		ASTNode *decl_node = decl_sym->node;
		if (decl_sym->kind == SYMB_STRUCT) {
			int field_index = find_struct_field_index(decl_node, node->data.member_access.member);
			if (field_index == -1)
				return NULL;
			return decl_node->data.struct_decl.fields[field_index]->data.field_decl.type;
		} else if (decl_sym->kind == SYMB_UNION) {
			int field_index = find_union_field_index(decl_node->data.union_decl.fields, node->data.member_access.member);
			if (field_index == -1) {
				return NULL;
			}
			ASTNode *field = decl_node->data.union_decl.fields;
			while (field_index && field) {
				field = field->next;
				--field_index;
			}
			return field->data.field_decl.type;
		}
	} break;

	case AST_RETURN:
		return get_type(table, node->data.ret.return_expr, scope_level, scope_specifier);

	case AST_UNARY_EXPR: {
		return node->data.unary_op.result_type;
	}

	case AST_ARRAY_ACCESS: {
		Type *base_type = get_type(table, node->data.array_access.base, scope_level, scope_specifier);
		if (!base_type || base_type->type_kind != TYPE_ARRAY)
			return NULL;
		return base_type->array.element_type;
	} break;

	case AST_ENUM_VALUE:
		return node->data.enum_value.enum_type;

	case AST_STRING_LIT:
		return get_string_type();

	case AST_EXTERN_FUNC_DECL: {
		Symbol *sym = lookup_symbol(table, node->data.extern_func.name, scope_level);
		if (!sym) {
			return NULL;
		}
		return sym->type->function.return_type;
	}

	default:
		return NULL;
	}
	return NULL;
}

CompilerResult resolve_type(Symbol *table, Type *type, SourceLocation loc);

CompilerResult analyze_expr_ident(Symbol *table, ASTNode *node, int scope_level) {
	// This should never be NULL at this point because we passed the analyze_ast call above
	if (node->data.ident.resolved_name[0] != '\0') {
		// We've either already done this or it's a global we don't want to touch
		Symbol *var_sym = lookup_symbol(table, node->data.ident.resolved_name, scope_level);
		if (var_sym) {
			return RESULT_SUCCESS;
		}
	}
	Symbol *global_sym_resolved = lookup_symbol(table, node->data.ident.resolved_name, 0);
	if (global_sym_resolved)
		return RESULT_SUCCESS;
	return RESULT_FAILURE;
}

CompilerResult analyze_unary_op(Symbol *table, ASTNode *node, int scope_level, const char *scope_specifier) {
	// First, analyze the sub-expression
	CompilerResult res = analyze_ast(table, node->data.unary_op.operand, scope_level, scope_specifier);
	if (res != RESULT_SUCCESS)
		return res;
	// Determine operand type
	Type *op_ty = get_type(table, node->data.unary_op.operand, scope_level, scope_specifier);
	if (!op_ty) {
		report(node->location, "cannot determine type of unary operand", 0);
		return RESULT_FAILURE;
	}
	switch (node->data.unary_op.op) {
	case '-': // -x
		if (op_ty->type_kind != TYPE_PRIMITIVE) {
			report(node->location, "unary '-' requires built-in operand", 0);
			return RESULT_FAILURE;
		}
		break;

	case '~': // ~x
		// only integer types allowed
		if (op_ty->type_kind != TYPE_PRIMITIVE || strcmp(op_ty->type_name, "i8") && strcmp(op_ty->type_name, "i16") && strcmp(op_ty->type_name, "i32") && strcmp(op_ty->type_name, "i64")) {
			report(node->location, "unary '~' requires integer operand", 0);
			return RESULT_FAILURE;
		}
		break;

	case '!': // !x
		// must convert to bool
		{
			Type bool_type = get_primitive_type("bool");
			if (!is_convertible(op_ty, &bool_type, 0, table)) {
				report(node->location, "unary '!' requires a boolean-convertible operand", 0);
				return RESULT_FAILURE;
			}
		}
		break;

	case '&': // &x
		// operand must be an l-value: identifier, member, or array access
		if (node->data.unary_op.operand->type != AST_EXPR_IDENT && node->data.unary_op.operand->type != AST_MEMBER_ACCESS && node->data.unary_op.operand->type != AST_ARRAY_ACCESS) {
			report(node->location, "unary '&' requires an l-value operand", 0);
			return RESULT_FAILURE;
		}
		break;

	case '*': // *p
		// operand must be pointer
		if (op_ty->type_kind != TYPE_POINTER) {
			report(node->location, "unary '*' requires a pointer operand", 0);
			return RESULT_FAILURE;
		}
		break;

	default:
		report(node->location, "unknown unary operator", 0);
		return RESULT_FAILURE;
	}
	if (node->data.unary_op.op == '&') {
		Type *expr_type_cpy = copy_type(op_ty);
		node->data.unary_op.result_type = calloc(1, sizeof(Type));
		node->data.unary_op.result_type->type_kind = TYPE_POINTER;
		node->data.unary_op.result_type->pointee = expr_type_cpy;
	} else if (node->data.unary_op.op == '*') {
		if (op_ty->type_kind != TYPE_POINTER) {
			char type_str[128] = "";
			type_print(type_str, op_ty);
			char msg[256] = "";
			sprintf(msg, "cannot dereference a non-pointer type: %s", type_str);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		node->data.unary_op.result_type = copy_type(op_ty->pointee);
	} else {
		node->data.unary_op.result_type = copy_type(op_ty);
	}
	return RESULT_SUCCESS;
}

CompilerResult analyze_struct_literal(Symbol *table, Type *expected_type, ASTNode *node, int scope_level, const char *scope_specifier) {
	assert(node->type == AST_STRUCT_LITERAL);
	int init_count = node->data.struct_literal.count;
	Symbol *decl_sym = lookup_named_type(table, expected_type, scope_level);
	if (!decl_sym) {
		char msg[256] = "";
		sprintf(msg, "unknown struct type %s.", expected_type->type_name);
		report(node->location, msg, 0);
		return RESULT_FAILURE;
	}
	if (decl_sym->kind != SYMB_STRUCT) {
		char msg[256] = "";
		sprintf(msg, "%s is not a struct type.", expected_type->type_name);
		report(node->location, msg, 0);
		return RESULT_FAILURE;
	}
	ASTNode *decl_node = decl_sym->node;
	assert(decl_node); // sanity
	int current_field_index = 0;
	for (int i = 0; i < init_count; ++i) {
		if (current_field_index >= decl_node->data.struct_decl.field_count) {
			char msg[256] = "";
			sprintf(msg, "struct '%s' has %d fields, check initialization.", expected_type->type_name, decl_node->data.struct_decl.field_count);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		FieldInitializer *init = node->data.struct_literal.inits[i];
		if (init->is_designated) {
			current_field_index = find_struct_field_index(decl_node, init->field);
			if (current_field_index == -1) {
				char msg[256] = "";
				sprintf(msg, "cannot find a field with name '%s' in the definition of struct '%s'.", init->field, expected_type->type_name);
				report(node->location, msg, 0);
				return RESULT_FAILURE;
			}
		}
		// TODO: add struct literal's field type checks
		++current_field_index;
	}
	return RESULT_SUCCESS;
}

CompilerResult analyze_expr_literal(Symbol *table, Type *lvalue_type, ASTNode *node, int scope_level, const char *scope_specifier) {
	Type *rtype = get_type(table, node, scope_level, scope_specifier);
	if (!is_convertible(rtype, lvalue_type, 1, table)) {
		if (rtype) {
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
	}
	return RESULT_SUCCESS;
}

CompilerResult analyze_union_decl(Symbol *table, ASTNode *node, int scope_level, const char *scope_specifier) {
	assert(node && node->type == AST_UNION_DECL);
	const char *union_name = node->data.union_decl.name;
	ASTNode *field = node->data.union_decl.fields;
	int field_count = 0;
	while (field) {
		if (field->type != AST_FIELD_DECL) {
			char msg[128] = "";
			sprintf(msg, "expected field declaration.");
			report(field->location, msg, 0);
			return RESULT_FAILURE;
		}
		// check duplicates
		int index = find_union_field_index(node->data.union_decl.fields, field->data.field_decl.name);
		if (index != field_count) {
			report(field->location, "duplicate field declaration.", 0);
			return RESULT_FAILURE;
		}
		++field_count;
		field = field->next;
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
		if (node->data.var_decl.type->type_kind == TYPE_UNDECIDED) {
			Symbol *sym = lookup_named_type(table, node->data.var_decl.type, 0);
			if (!sym) {
				char type_str[128] = "";
				type_print(type_str, node->data.var_decl.type);
				char msg[128] = "";
				sprintf(msg, "declaring variable of unknown type %s.", type_str);
				report(node->location, msg, 0);
				return RESULT_FAILURE;
			}
			node->data.var_decl.type->type_kind = sym->type->type_kind;
			Symbol *var_sym = lookup_symbol(table, node->data.var_decl.resolved_name, scope_level);
			assert(var_sym);
			var_sym->type->type_kind = sym->type->type_kind;
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
			} else if (node->data.var_decl.init->type == AST_STRUCT_LITERAL) {
				result = analyze_struct_literal(table, node->data.var_decl.type, node->data.var_decl.init, scope_level, scope_specifier);
			} else if (node->data.var_decl.init->type == AST_CHAR_LIT) {
				Type *type = node->data.var_decl.type;
				if (type->type_kind != TYPE_PRIMITIVE)
					return RESULT_FAILURE;
				int is_u8 = strcmp(type->type_name, "u8") == 0;
				int is_i8 = strcmp(type->type_name, "i8") == 0;
				if (!is_u8 && !is_i8)
					return RESULT_FAILURE;
				result = RESULT_SUCCESS;
			} else if (node->data.var_decl.init->type == AST_ARRAY_LITERAL) {
				ASTNode *array_literal = node->data.var_decl.init;
				if (node->data.var_decl.type->type_kind != TYPE_ARRAY) {
					char msg[256] = "";
					sprintf(msg, "lvalue is not an array.");
					report(node->location, msg, 0);
					return RESULT_FAILURE;
				}
				if (node->data.var_decl.type->array.size != array_literal->data.array_literal.count) {
					report(node->location, "array element count mismatch. Arrays cannot be initialized with partial initializers.", 0);
					return RESULT_FAILURE;
				}
				for (int i = 0; i < array_literal->data.array_literal.count; ++i) {
					// This if is a hack that essentially prevents type checking in nested array literals
					if (array_literal->data.array_literal.elements[i]->type != AST_ARRAY_LITERAL) {
						Type *element_type = get_type(table, array_literal->data.array_literal.elements[i], scope_level, scope_specifier);
						if (!is_convertible(element_type, node->data.var_decl.type->array.element_type, 1, table)) {
							char type_str[128] = "";
							type_print(type_str, node->data.var_decl.type->array.element_type);
							char msg[256] = "";
							sprintf(msg, "array initialization mistype, expected type %s.", type_str);
							report(array_literal->data.array_literal.elements[i]->location, msg, 0);
							return RESULT_FAILURE;
						}
					}
					result = analyze_ast(table, array_literal->data.array_literal.elements[i], scope_level, scope_specifier);
					if (result != RESULT_SUCCESS) {
						return result;
					}
				}
			} else if (node->data.var_decl.init->type == AST_STRING_LIT) {
				Type *lhs_type = node->data.var_decl.type;
				if (lhs_type->type_kind == TYPE_ARRAY) {
					if (lhs_type->array.element_type->type_kind != TYPE_PRIMITIVE || (strcmp(lhs_type->array.element_type->type_name, "i8") != 0 && strcmp(lhs_type->array.element_type->type_name, "u8") != 0)) {
						char msg[128] = "string literal can only be assigned to (const) u8 or i8 arrays or pointers.";
						report(node->location, msg, 0);
						return RESULT_FAILURE;
					}
					size_t str_len = strlen(node->data.var_decl.init->data.string_literal.text) + 1;
					if (lhs_type->array.size < str_len) {
						char msg[128] = "";
						sprintf(msg, "\"%s\" is %zu symbols long, while the array is of size %d.", node->data.var_decl.init->data.string_literal.text, str_len, lhs_type->array.size);
						report(node->location, msg, 0);
						return RESULT_FAILURE;
					}
				} else if (lhs_type->type_kind == TYPE_POINTER) {
					if (lhs_type->pointee->type_kind != TYPE_PRIMITIVE || (strcmp(lhs_type->pointee->type_name, "i8") != 0 && strcmp(lhs_type->pointee->type_name, "u8") != 0)) {
						char msg[128] = "string literal can only be assigned to (const) u8 or i8 arrays or pointers.";
						report(node->location, msg, 0);
						return RESULT_FAILURE;
					}
				}
			} else {
				// Disallow global variable initialization with other global variables
				if (node->data.var_decl.init->type == AST_EXPR_IDENT && scope_level == 0) {
					char msg[128] = "global variables cannot be initialized with other global variables.";
					report(node->location, msg, 0);
					return RESULT_FAILURE;
				}
				result = analyze_ast(table, node->data.var_decl.init, scope_level, scope_specifier);
			}
			if (result != RESULT_SUCCESS) {
				return result;
			}
			// Struct literals and unary exprs have already been handled, and it's really difficult to find the type of the struct literal this way
			ASTNodeType init_node_type = node->data.var_decl.init->type;
			if (init_node_type != AST_STRUCT_LITERAL && init_node_type != AST_STRING_LIT && init_node_type != AST_EXPR_LITERAL && init_node_type != AST_UNARY_EXPR && init_node_type != AST_CHAR_LIT && init_node_type != AST_ARRAY_LITERAL) {
				Type *init_type = get_type(table, node->data.var_decl.init, scope_level, scope_specifier);
				if (!init_type) {
					return RESULT_FAILURE;
				}
				if (!is_convertible(init_type, node->data.var_decl.type, 0, table)) {
					report(node->data.var_decl.init->location, "type mismatch in initializer.", 0);
					return RESULT_FAILURE;
				}
			}
		}
		return RESULT_SUCCESS;
	} break;

	case AST_DEFERRED_SEQUENCE:
	case AST_BLOCK: {
		CompilerResult result;
		for (int i = 0; i < node->data.block.count; ++i) {
			result = analyze_ast(table, node->data.block.statements[i], scope_level, scope_specifier);
			if (result != RESULT_SUCCESS)
				return result;
		}
	} break;

	case AST_EXPR_IDENT: {
		if (node->data.ident.resolved_name[0] == '\0') {
			Symbol *sym = lookup_symbol_weak(table, node->data.ident.name, scope_level);
			if (sym) {
				strncpy(node->data.ident.resolved_name, sym->resolved_name, sizeof(node->data.ident.resolved_name));
				return RESULT_SUCCESS;
			}
			Symbol *enum_symbol = lookup_symbol_weak(table, node->data.ident.namespace, scope_level);
			if (enum_symbol && enum_symbol->kind == SYMB_ENUM) {
				node->type = AST_ENUM_VALUE;
				strncpy(node->data.enum_value.member, node->data.ident.name, sizeof(node->data.enum_value.member));
				node->data.enum_value.enum_type = copy_type(enum_symbol->type);
				CompilerResult result = analyze_ast(table, node, scope_level, scope_specifier);
				return result;
			}
		}
		// We've either already done this or it's a global we don't want to touch
		Symbol *var_sym = lookup_symbol(table, node->data.ident.resolved_name, scope_level);
		if (var_sym) {
			return RESULT_SUCCESS;
		}
		Symbol *global_sym_resolved = lookup_symbol(table, node->data.ident.resolved_name, 0);
		if (global_sym_resolved)
			return RESULT_SUCCESS;
		Symbol *global_sym = lookup_symbol(table, node->data.ident.name, 0);
		if (global_sym) {
			// This is for codegen compatability
			strncpy(node->data.ident.resolved_name, node->data.ident.name, sizeof(node->data.ident.resolved_name));
			return RESULT_SUCCESS;
		}
		if (node->data.ident.namespace[0] != '\0') {
			Symbol *maybe_enum = lookup_symbol(table, node->data.ident.namespace, 0);
			if (maybe_enum && maybe_enum->kind == SYMB_ENUM) {
			}
		}
		char resolved_name[256] = "";
		if (scope_specifier[0] != '\0')
			sprintf(resolved_name, "__%s_%s", scope_specifier, node->data.ident.name);
		else
			strncpy(resolved_name, node->data.ident.name, sizeof(resolved_name));
		var_sym = lookup_symbol(table, resolved_name, scope_level);
		if (!var_sym) {
			char msg[64] = "";
			sprintf(msg, "undeclared identifier %s.", node->data.ident.name);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		CompilerResult result = resolve_type(table, var_sym->type, var_sym->node->location);
		if (result != RESULT_SUCCESS)
			return result;
		strncpy(node->data.ident.resolved_name, resolved_name, sizeof(resolved_name));
	} break;

	case AST_RETURN: {
		CompilerResult result = analyze_ast(table, node->data.ret.return_expr, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;
		// This is a gamble
		Symbol *sym = lookup_symbol_weak(table, scope_specifier, scope_level);
		if (!sym || sym->kind != SYMB_FN || sym->type->type_kind != TYPE_FUNCTION) {
			char msg[128] = "";
			sprintf(msg, "%s is not a function.", scope_specifier);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		Type *expr_type = get_type(table, node, scope_level, scope_specifier);
		if (expr_type->type_kind == TYPE_ENUM) {
			Symbol *enum_decl = lookup_named_type(table, expr_type, scope_level);
			if (!enum_decl) {
				char msg[128] = "";
				sprintf(msg, "undeclared enum %s.", expr_type->type_name);
				report(node->location, msg, 0);
				return RESULT_FAILURE;
			}
			expr_type = enum_decl->node->data.enum_decl.base_type;
			expr_type->type_kind = TYPE_PRIMITIVE;
		}
		if (!is_convertible(expr_type, sym->type->function.return_type, 0, table)) {
			char msg[128] = "";
			char src_type[128] = "";
			char trg_type[128] = "";
			type_print(src_type, expr_type);
			type_print(trg_type, sym->type->function.return_type);
			sprintf(msg, "cannot implicitly convert from %s to %s.", src_type, trg_type);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		return RESULT_SUCCESS;
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
		if (!is_convertible(rtype, ltype, 1, table)) {
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
			char resolved_name[256] = "";
			ASTNode *lvalue = node->data.assignment.lvalue;
			if (analyze_expr_ident(table, lvalue, scope_level) == RESULT_SUCCESS) {
				strncpy(resolved_name, lvalue->data.ident.resolved_name, sizeof(resolved_name));
			} else {
				if (scope_specifier[0] != '\0')
					sprintf(resolved_name, "__%s_%s", scope_specifier, lvalue->data.ident.name);
				else
					strncpy(resolved_name, lvalue->data.ident.name, sizeof(resolved_name));
				strncpy(lvalue->data.ident.resolved_name, resolved_name, sizeof(lvalue->data.ident.resolved_name));
			}
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
		} else if (node->data.assignment.rvalue->type == AST_STRUCT_LITERAL) {
			result = analyze_struct_literal(table, ltype, node->data.assignment.rvalue, scope_level, scope_specifier);
		} else if (node->data.assignment.rvalue->type == AST_CHAR_LIT) {
			if (ltype->type_kind != TYPE_PRIMITIVE)
				return RESULT_FAILURE;
			int is_u8 = strcmp(ltype->type_name, "u8") == 0;
			int is_i8 = strcmp(ltype->type_name, "i8") == 0;
			if (!is_u8 && !is_i8)
				return RESULT_FAILURE;
			result = RESULT_SUCCESS;
		} else if (node->data.assignment.rvalue->type == AST_ARRAY_LITERAL) {
			ASTNode *array_literal = node->data.assignment.rvalue;
			if (ltype->type_kind != TYPE_ARRAY) {
				char msg[256] = "";
				sprintf(msg, "lvalue is not an array.");
				report(node->location, msg, 0);
				return RESULT_FAILURE;
			}
			for (int i = 0; i < array_literal->data.array_literal.count; ++i) {
				Type *element_type = get_type(table, array_literal->data.array_literal.elements[i], scope_level, scope_specifier);
				if (!is_convertible(element_type, ltype, 1, table)) {
					char type_str[128] = "";
					type_print(type_str, ltype->array.element_type);
					char msg[256] = "";
					sprintf(msg, "array initialization mistype, expected type %s.", type_str);
					report(array_literal->data.array_literal.elements[i]->location, msg, 0);
					return RESULT_FAILURE;
				}
				result = analyze_ast(table, array_literal->data.array_literal.elements[i], scope_level, scope_specifier);
				if (result != RESULT_SUCCESS) {
					return result;
				}
			}
		} else if (node->data.assignment.lvalue->type == AST_STRING_LIT) {
			if (ltype->type_kind == TYPE_ARRAY) {
				if (ltype->array.element_type->type_kind != TYPE_PRIMITIVE || (strcmp(ltype->array.element_type->type_name, "i8") != 0 && strcmp(ltype->array.element_type->type_name, "u8") != 0)) {
					char msg[128] = "string literal can only be assigned to (const) u8 or i8 arrays or pointers.";
					report(node->location, msg, 0);
					return RESULT_FAILURE;
				}
				size_t str_len = strlen(node->data.assignment.rvalue->data.string_literal.text) + 1;
				if (ltype->array.size < str_len) {
					char msg[128] = "";
					sprintf(msg, "\"%s\" is %zu symbols long, while the array is of size %d.", node->data.assignment.rvalue->data.string_literal.text, str_len, ltype->array.size);
					report(node->location, msg, 0);
					return RESULT_FAILURE;
				}
			} else if (ltype->type_kind == TYPE_ARRAY) {
				if (ltype->pointee->type_kind != TYPE_PRIMITIVE || (strcmp(ltype->pointee->type_name, "i8") != 0 && strcmp(ltype->pointee->type_name, "u8") != 0)) {
					char msg[128] = "string literal can only be assigned to (const) u8 or i8 arrays or pointers.";
					report(node->location, msg, 0);
					return RESULT_FAILURE;
				}
			}
		} else {
			result = analyze_ast(table, node->data.assignment.rvalue, scope_level, scope_specifier);
		}
		if (result != RESULT_SUCCESS)
			return result;
		ASTNodeType rvalue_node_type = node->data.assignment.rvalue->type;
		if (rvalue_node_type != AST_STRUCT_LITERAL && rvalue_node_type != AST_STRING_LIT && rvalue_node_type != AST_EXPR_LITERAL && rvalue_node_type != AST_CHAR_LIT && rvalue_node_type != AST_UNARY_EXPR &&
			rvalue_node_type != AST_ARRAY_LITERAL) {
			Type *rtype = get_type(table, node->data.assignment.rvalue, scope_level, scope_specifier);
			if (!is_convertible(rtype, ltype, 0, table)) {
				char left_str[128] = "";
				char right_str[128] = "";
				type_print(left_str, ltype);
				type_print(right_str, rtype);
				char msg[256] = "";
				sprintf(msg, "assignment type mismatch: cannot implicitly convert %s to %s.", right_str, left_str);
				report(node->location, msg, 0);
				return RESULT_FAILURE;
			}
		}
		return RESULT_SUCCESS;
	} break;

	case AST_FN_CALL: {
		CompilerResult result = analyze_ast(table, node->data.func_call.callee, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;
		// Previous call to analyze_ast would fail if the symbol didn't exist
		Symbol *sym = NULL;
		if (node->data.func_call.callee->data.ident.resolved_name[0] != '\0') {
			sym = lookup_symbol(table, node->data.func_call.callee->data.ident.resolved_name, 0);
		} else {
			sym = lookup_symbol(table, node->data.func_call.callee->data.ident.name, 0);
		}
		assert(sym);
		if ((sym->node->type != AST_FN_DECL && sym->node->type != AST_EXTERN_FUNC_DECL) || sym->kind != SYMB_FN) {
			char msg[256] = "";
			sprintf(msg, "symbol %s is not a function but used as a function.", node->data.func_call.callee->data.ident.name);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		// @TODO: cache this probably
		int non_va_param_count = 0;
		ASTNode *param = sym->node->data.func_decl.params;
		while (param) {
			if (param->data.param_decl.is_va)
				break;
			++non_va_param_count;
			param = param->next;
		}
		if (non_va_param_count > node->data.func_call.arg_count) {
			char msg[256] = "";
			sprintf(msg, "argument count mismatch.");
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		param = sym->node->data.func_decl.params;
		for (int i = 0; i < node->data.func_call.arg_count; ++i) {
			result = analyze_ast(table, node->data.func_call.args[i], scope_level, scope_specifier);
			if (result != RESULT_SUCCESS)
				return result;
			if (i < non_va_param_count) {
				Type *param_type = param->data.param_decl.type;
				Type *arg_type = get_type(table, node->data.func_call.args[i], sym->scope_level + 1, scope_specifier);
				if (!is_convertible(arg_type, param_type, 0, table)) {
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
		}
		return result;
	} break;

	case AST_FN_DECL: {
		Symbol *sym = lookup_symbol(table, node->data.func_decl.resolved_name, scope_level);
		if (!sym) {
			char msg[256] = "";
			sprintf(msg, "function %s undefined.", node->data.func_decl.name);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		Type *fn_type = sym->type;
		if (!fn_type) {
			char msg[256] = "";
			sprintf(msg, "function %s's type registered to symbol table with errors. Check syntax.", node->data.func_decl.name);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		if (sym->kind != SYMB_FN || fn_type->type_kind != TYPE_FUNCTION) {
			char msg[256] = "";
			sprintf(msg, "function %s is not registered as a function. Check syntax.", node->data.func_decl.name);
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
				if ((fn_type->function.return_type->type_kind != TYPE_PRIMITIVE || strcmp(fn_type->function.return_type->type_name, "void") != 0) && (!last_stmt || last_stmt->type != AST_RETURN)) {
					char msg[256] = "";
					sprintf(msg, "the last statement in a non-void function must be a return statement.");
					report(last_stmt->location, msg, 0);
					return RESULT_FAILURE;
				}
				if (last_stmt && last_stmt->type == AST_RETURN) {
					Type *stmt_type = get_type(table, last_stmt, scope_level + 1, scope_specifier);
					if (!stmt_type) {
						char msg[256] = "";
						sprintf(msg, "in function %s, the last return statement is typeless.", node->data.func_decl.name);
						report(last_stmt->location, msg, 0);
						return RESULT_FAILURE;
					}
					if (!is_convertible(stmt_type, fn_type->function.return_type, 0, table)) {
						char actual_type_str[128] = "";
						type_print(actual_type_str, stmt_type);
						char expected_type_str[128] = "";
						type_print(expected_type_str, fn_type->function.return_type);
						char msg[256] = "";
						sprintf(msg, "cannot convert type %s into expected type %s in function return statement.", actual_type_str, expected_type_str);
						report(last_stmt->location, msg, 0);
						return RESULT_FAILURE;
					}
				}
				for (int i = 0; i < node->data.func_decl.body->data.block.count; ++i) {
					if (node->data.func_decl.body->data.block.statements[i]->type == AST_CONTINUE) {
						report(node->data.func_decl.body->data.block.statements[i]->location, "'continue' out of loop context.", 0);
						return RESULT_FAILURE;
					}
					if (node->data.func_decl.body->data.block.statements[i]->type == AST_BREAK) {
						report(node->data.func_decl.body->data.block.statements[i]->location, "'break' out of loop context.", 0);
						return RESULT_FAILURE;
					}
				}
			}
		}
	} break;

	case AST_STRUCT_DECL: {
		Symbol *sym = lookup_symbol(table, node->data.struct_decl.resolved_name, scope_level);
		if (!sym) {
			char msg[256] = "";
			sprintf(msg, "struct %s undefined.", node->data.struct_decl.name);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		sym->kind = SYMB_STRUCT;
		sym->type->type_kind = TYPE_STRUCT;
	} break;

	case AST_ENUM_DECL: {
		Symbol *sym = lookup_symbol(table, node->data.enum_decl.resolved_name, scope_level);
		if (!sym) {
			char msg[256] = "";
			sprintf(msg, "enum %s undefined.", node->data.enum_decl.name);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		if (sym->type->type_kind == TYPE_UNDECIDED) {
			sym->type->type_kind = TYPE_ENUM;
		}
	} break;

	// Want to handle these where they are used
	case AST_EXPR_LITERAL:
	case AST_STRUCT_LITERAL:
	case AST_ARRAY_LITERAL:
	case AST_CHAR_LIT:
	case AST_STRING_LIT:
	case AST_CONTINUE:
	case AST_BREAK:
		break;

	case AST_PARAM_DECL:
		if (scope_specifier[0] != '\0' && !node->data.param_decl.is_va) {
			snprintf(node->data.param_decl.resolved_name, sizeof(node->data.param_decl.resolved_name), "__%s_%s", scope_specifier, node->data.param_decl.name);
		}
		break;

	case AST_CAST: {
		CompilerResult result = resolve_type(table, node->data.cast.target_type, node->location);
		if (result != RESULT_SUCCESS)
			return result;
		result = analyze_ast(table, node->data.cast.expr, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;
		Type *expr_type = get_type(table, node->data.cast.expr, scope_level, scope_specifier);
		assert(expr_type);
		if (expr_type->type_kind == TYPE_PRIMITIVE && node->data.cast.target_type->type_kind == TYPE_PRIMITIVE)
			return RESULT_SUCCESS;
		if ((is_int(expr_type) && expr_type->type_name[1] == '6' && expr_type->type_name[2] == '4' && node->data.cast.target_type->type_kind == TYPE_POINTER) ||
			(is_int(node->data.cast.target_type) && node->data.cast.target_type->type_name[1] == '6' && node->data.cast.target_type->type_name[2] == '4' && expr_type->type_kind == TYPE_POINTER)) {
			return RESULT_SUCCESS;
		}
		if (!is_convertible(expr_type, node->data.cast.target_type, 0, table)) {
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
		if (!is_convertible(condition_type, &bool_type, 0, table)) {
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
		if (!is_convertible(condition_type, &bool_type, 0, table)) {
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

	case AST_MEMBER_ACCESS: {
		ASTNode *base_node = node->data.member_access.base;
		CompilerResult result = analyze_ast(table, base_node, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;
		Type *base_type = get_type(table, base_node, scope_level, scope_specifier);
		if (!base_type) {
			report(base_node->location, "cannot determine type", 0);
			return RESULT_FAILURE;
		}
		Symbol *decl_sym = lookup_named_type(table, base_type, scope_level);
		if (!decl_sym) {
			char msg[128] = "";
			sprintf(msg, "unknown type %s.", base_type->type_name);
			report(base_node->location, msg, 0);
			return RESULT_FAILURE;
		}
		if (decl_sym->kind != SYMB_STRUCT && decl_sym->kind != SYMB_UNION) {
			report(base_node->location, "can only access members of structs or unions.", 0);
			return RESULT_FAILURE;
		}
		if (decl_sym->kind == SYMB_STRUCT) {
			int field_index = find_struct_field_index(decl_sym->node, node->data.member_access.member);
			if (field_index == -1) {
				char msg[128] = "";
				sprintf(msg, "%s does not have a member named %s.", base_type->type_name, node->data.member_access.member);
				report(base_node->location, msg, 0);
				return RESULT_FAILURE;
			}
		} else if (decl_sym->kind == SYMB_UNION) {
			int field_index = find_union_field_index(decl_sym->node->data.union_decl.fields, node->data.member_access.member);
			if (field_index == -1) {
				char msg[128] = "";
				sprintf(msg, "%s does not have a member named %s.", base_type->type_name, node->data.member_access.member);
				report(base_node->location, msg, 0);
				return RESULT_FAILURE;
			}
		}
		Type *field_type = get_type(table, node, scope_level, scope_specifier);
		if (!field_type)
			return RESULT_FAILURE;
		return RESULT_SUCCESS;
	} break;

	case AST_ARRAY_ACCESS: {
		CompilerResult res = analyze_ast(table, node->data.array_access.base, scope_level, scope_specifier);
		if (res != RESULT_SUCCESS)
			return res;
		res = analyze_ast(table, node->data.array_access.index, scope_level, scope_specifier);
		if (res != RESULT_SUCCESS)
			return res;
		// Fetch the base’s type
		Type *base_ty = get_type(table, node->data.array_access.base, scope_level, scope_specifier);
		if (!base_ty) {
			report(node->location, "cannot determine type of array base", 0);
			return RESULT_FAILURE;
		}
		// Must be an array or pointer
		if (base_ty->type_kind != TYPE_ARRAY && base_ty->type_kind != TYPE_POINTER) {
			report(node->location, "subscripted value is not an array or pointer", 0);
			return RESULT_FAILURE;
		}
		// Check index is integer
		Type *idx_ty = get_type(table, node->data.array_access.index, scope_level, scope_specifier);
		if (!idx_ty || idx_ty->type_kind != TYPE_PRIMITIVE || strchr("iu", idx_ty->type_name[0]) == NULL) {
			report(node->data.array_access.index->location, "array index must be an integer type", 0);
			return RESULT_FAILURE;
		}
		return RESULT_SUCCESS;
	} break;

	case AST_UNARY_EXPR:
		return analyze_unary_op(table, node, scope_level, scope_specifier);

	case AST_ENUM_VALUE: {
		Symbol *sym = lookup_symbol(table, node->data.enum_value.enum_type->type_resolved_name, scope_level);
		if (!sym) {
			char msg[128] = "";
			sprintf(msg, "Unknown enum %s.", node->data.enum_value.enum_type->type_name);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		if (sym->kind != SYMB_ENUM) {
			char msg[128] = "";
			sprintf(msg, "%s is not an enum.", sym->name);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		for (int i = 0; i < sym->node->data.enum_decl.member_count; ++i) {
			if (strcmp(sym->node->data.enum_decl.members[i]->name, node->data.enum_value.member) == 0) {
				return RESULT_SUCCESS;
			}
		}
		char msg[128] = "";
		sprintf(msg, "Enum %s does not contain a member %s.", sym->name, node->data.enum_value.member);
		report(node->location, msg, 0);
		return RESULT_FAILURE;
	} break;

	case AST_EXTERN_BLOCK: {
		CompilerResult result = RESULT_SUCCESS;
		for (int i = 0; i < node->data.extern_block.count; ++i) {
			result = analyze_ast(table, node->data.extern_block.block[i], scope_level, scope_specifier);
			if (result != RESULT_SUCCESS) {
				return result;
			}
		}
	} break;

	case AST_EXTERN_FUNC_DECL: {
		if (node->data.extern_func.params) {
			CompilerResult result = RESULT_SUCCESS;
			ASTNode *param = node->data.extern_func.params;
			while (param) {
				result = analyze_ast(table, param, scope_level + 1, node->data.extern_func.name);
				param = param->next;
			}
			if (result != RESULT_SUCCESS)
				return result;
		}
	} break;

	case AST_IF_STMT: {
		CompilerResult result = analyze_ast(table, node->data.if_stmt.condition, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;
		Type *cond_type = get_type(table, node->data.if_stmt.condition, scope_level, scope_specifier);
		assert(cond_type);
		if (!is_convertible(cond_type, get_primitive_bool(), 1, table)) {
			char msg[256] = "";
			char type_msg[128] = "";
			type_print(type_msg, cond_type);
			sprintf(msg, "condition expression of type %s cannot be converted to bool.", type_msg);
			report(node->data.if_stmt.condition->location, msg, 0);
			return RESULT_FAILURE;
		}
		result = analyze_ast(table, node->data.if_stmt.then_branch, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;
		if (node->data.if_stmt.else_branch) {
			result = analyze_ast(table, node->data.if_stmt.else_branch, scope_level, scope_specifier);
			if (result != RESULT_SUCCESS)
				return result;
		}
	} break;

	case AST_UNION_DECL:
		return analyze_union_decl(table, node, scope_level, scope_specifier);
		break;

	default:
		report(node->location, "sema: unsupported node type.", 1);
		break;
	}
	return RESULT_SUCCESS;
}

CompilerResult resolve_type(Symbol *table, Type *type, SourceLocation loc) {
	if (type->type_kind == TYPE_UNDECIDED) {
		Symbol *type_def = lookup_named_type(table, type, 0);
		if (!type_def) {
			char msg[128] = "";
			sprintf(msg, "unknown type %s.", type->type_name);
			report(loc, msg, 0);
			return RESULT_FAILURE;
		}
		type->type_kind = type_def->type->type_kind;
		strncpy(type->type_resolved_name, type_def->resolved_name, sizeof(type->type_resolved_name));
	} else if (type->type_kind == TYPE_POINTER) {
		Type *pointee_type = type->pointee;
		while (pointee_type->type_kind == TYPE_POINTER) {
			pointee_type = pointee_type->pointee;
		}
		return resolve_type(table, pointee_type, loc);
	} else if (type->type_kind == TYPE_ARRAY) {
		Type *arr_type = type->array.element_type;
		while (arr_type->type_kind == TYPE_ARRAY) {
			arr_type = arr_type->array.element_type;
		}
		return resolve_type(table, arr_type, loc);
	} else if (type->type_kind == TYPE_FUNCTION) {
		CompilerResult result = resolve_type(table, type->function.return_type, loc);
		if (result != RESULT_SUCCESS)
			return result;
		for (int i = 0; i < type->function.param_count; ++i) {
			result = resolve_type(table, type->function.param_types[i], loc);
			if (result != RESULT_SUCCESS)
				return result;
		}
		return result;
	}
	// others are basically handled
	return RESULT_SUCCESS;
}

CompilerResult resolve_types(Symbol *table, ASTNode *root, int should_traverse_symbols) {
	if (should_traverse_symbols) {
		Symbol *sym = table;
		while (sym) {
			CompilerResult result = resolve_type(table, sym->type, sym->node->location);
			if (sym->kind == SYMB_STRUCT || sym->kind == SYMB_ENUM || sym->kind == SYMB_UNION) {
				if (sym->type->type_resolved_name[0] == '\0') {
					strncpy(sym->type->type_resolved_name, sym->resolved_name, sizeof(sym->type->type_resolved_name));
				}
			}
			sym = sym->next;
		}
	}
	for (ASTNode *node = root; node != NULL; node = node->next) {
		switch (node->type) {
		case AST_STRUCT_DECL: {
			for (int i = 0; i < node->data.struct_decl.field_count; ++i) {
				ASTNode *field = node->data.struct_decl.fields[i];
				CompilerResult result = resolve_type(table, field->data.field_decl.type, field->location);
				if (result != RESULT_SUCCESS)
					return result;
			}
		} break;

		case AST_FN_DECL: {
			for (ASTNode *param = node->data.func_decl.params; param; param = param->next) {
				CompilerResult result = resolve_types(table, param, 0);
				if (result != RESULT_SUCCESS)
					return result;
			}
			CompilerResult result = resolve_types(table, node->data.func_decl.body, 0);
			if (result != RESULT_SUCCESS)
				return result;
		} break;

		case AST_VAR_DECL:
		case AST_PARAM_DECL:
		case AST_CAST: {
			Type *type = NULL;
			if (node->type == AST_VAR_DECL) {
				type = node->data.var_decl.type;
			} else if (node->type == AST_PARAM_DECL) {
				type = node->data.param_decl.type;
			} else if (node->type == AST_CAST) {
				type = node->data.cast.target_type;
			}
			CompilerResult result = resolve_type(table, type, node->location);
			if (result != RESULT_SUCCESS)
				return result;
		} break;

		case AST_DEFERRED_SEQUENCE:
		case AST_BLOCK:
			for (int i = 0; i < node->data.block.count; ++i) {
				CompilerResult result = resolve_types(table, node->data.block.statements[i], 0);
				if (result != RESULT_SUCCESS)
					return result;
			}
			break;
		}

		// TODO: finish this
	}
	return RESULT_SUCCESS;
}
