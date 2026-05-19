#include "sema.h"
#include "parser.h"
#include "symbol_table.h"
#include "types.h"
#include "util.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

CompilerResult analyze_expr_literal(Symbol *table, Type *lvalue_type, ASTNode *node, int scope_level, const char *scope_specifier);
CompilerResult analyze_switch_stmt(Symbol *table, ASTNode *node, int scope_level, const char *scope_specifier);

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
		if (node->data.literal.is_null) {
			return get_null_type();
		} else if (node->data.literal.is_bool) {
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
				char resolved_name[512] = "";
				int written;
				if (node->data.ident.namespace[0] != '\0') {
					written = snprintf(resolved_name, sizeof(resolved_name), "__%s_%s", node->data.ident.namespace, node->data.ident.name);
				} else if (scope_specifier[0] != '\0') {
					written = snprintf(resolved_name, sizeof(resolved_name), "%s_%s", scope_specifier, node->data.ident.name);
				} else {
					written = snprintf(resolved_name, sizeof(resolved_name), "%s", node->data.ident.name);
				}
				if (written < 0 || (size_t)written >= sizeof(resolved_name)) {
					report(node->location, "resolved identifier name exceeds buffer size.", 0);
					return NULL;
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
		switch (node->data.binary_op.op) {
		case TOK_LESSTHAN:
		case TOK_GREATERTHAN:
		case TOK_LTOE:
		case TOK_GTOE:
		case TOK_EQUAL:
		case TOK_NOTEQUAL:
		case TOK_OR:
		case TOK_AND:
			return get_primitive_bool();
		default:
			return get_type(table, node->data.binary_op.left, scope_level, scope_specifier);
		}

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
		if ((base_type->type_kind == TYPE_SLICE || base_type->type_kind == TYPE_ARRAY) && strcmp(node->data.member_access.member, "len") == 0)
			return get_primitive_u64();
		if (base_type->type_kind == TYPE_POINTER && base_type->pointee)
			base_type = base_type->pointee;
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
		if (!base_type)
			return NULL;
		if (base_type->type_kind == TYPE_ARRAY)
			return base_type->array.element_type;
		if (base_type->type_kind == TYPE_SLICE)
			return base_type->slice.element_type;
		return NULL;
	} break;

	case AST_SLICE_RANGE: {
		Type *base_type = get_type(table, node->data.slice_range.base, scope_level, scope_specifier);
		if (!base_type)
			return NULL;
		Type *elem = base_type->type_kind == TYPE_ARRAY ? base_type->array.element_type : base_type->type_kind == TYPE_SLICE ? base_type->slice.element_type : NULL;
		if (!elem)
			return NULL;
		return new_slice_type(elem);
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

	case '~':
		if (op_ty->type_kind != TYPE_PRIMITIVE ||
			(op_ty->prim != PRIM_I8 && op_ty->prim != PRIM_I16 && op_ty->prim != PRIM_I32 && op_ty->prim != PRIM_I64 &&
			 op_ty->prim != PRIM_U8 && op_ty->prim != PRIM_U16 && op_ty->prim != PRIM_U32 && op_ty->prim != PRIM_U64)) {
			report(node->location, "unary '~' requires integer operand", 0);
			return RESULT_FAILURE;
		}
		break;

	case '!': // !x
		// must convert to bool — permissive so numeric / pointer operands
		// are accepted (codegen lowers the load + compare against zero).
		{
			Type bool_type = get_primitive_type("bool");
			if (!is_convertible(op_ty, &bool_type, 1, table)) {
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
		node->data.unary_op.result_type = new_pointer_type(expr_type_cpy);
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

// `T[] s = {ptr, len}` / `{.ptr = p, .len = n}`: analyzed like a struct
// literal against an implicit `{ T* ptr; u64 len; }` record. Positional
// form fills ptr then len; designated form only accepts those two field
// names. Returns 1 if `node was a slice literal and was analyzed, 0 if expected_type isn't a
// slice so the caller should fall through to the struct path.
static int try_analyze_slice_literal(Symbol *table, Type *expected_type, ASTNode *node, int scope_level, const char *scope_specifier, CompilerResult *out_result) {
	if (!expected_type || expected_type->type_kind != TYPE_SLICE)
		return 0;
	int init_count = node->data.struct_literal.count;
	if (init_count != 2) {
		char msg[128] = "";
		snprintf(msg, sizeof(msg), "slice literal needs exactly 2 fields (ptr, len), got %d.", init_count);
		report(node->location, msg, 0);
		*out_result = RESULT_FAILURE;
		return 1;
	}
	Type *elem = expected_type->slice.element_type;
	Type *expected_ptr = new_pointer_type(elem);
	Type *expected_len = get_primitive_u64();
	// 0 = ptr slot, 1 = len slot
	int seen[2] = {0, 0};
	int positional_index = 0;
	for (int i = 0; i < init_count; ++i) {
		FieldInitializer *init = node->data.struct_literal.inits[i];
		int slot;
		if (init->is_designated) {
			if (strcmp(init->field, "ptr") == 0)
				slot = 0;
			else if (strcmp(init->field, "len") == 0)
				slot = 1;
			else {
				char msg[160] = "";
				snprintf(msg, sizeof(msg), "slice literal: unknown field '%s', expected 'ptr' or 'len'.", init->field);
				report(node->location, msg, 0);
				*out_result = RESULT_FAILURE;
				return 1;
			}
		} else {
			slot = positional_index++;
		}
		if (slot < 0 || slot > 1 || seen[slot]) {
			report(node->location, "slice literal: too many or duplicate field initializers.", 0);
			*out_result = RESULT_FAILURE;
			return 1;
		}
		seen[slot] = 1;
		Type *expected_field_ty = slot == 0 ? expected_ptr : expected_len;
		ASTNode *expr = init->expr;
		CompilerResult r;
		if (expr->type == AST_EXPR_LITERAL) {
			r = analyze_expr_literal(table, expected_field_ty, expr, scope_level, scope_specifier);
		} else {
			r = analyze_ast(table, expr, scope_level, scope_specifier);
			if (r == RESULT_SUCCESS) {
				Type *expr_ty = get_type(table, expr, scope_level, scope_specifier);
				// The ptr slot demands exact element-type match
				int ok;
				if (slot == 0)
					ok = expr_ty && expr_ty->type_kind == TYPE_POINTER && type_equals(expr_ty->pointee, elem);
				else
					ok = expr_ty && is_convertible(expr_ty, expected_field_ty, 0, table);
				if (!ok) {
					char want[64] = "", got[64] = "";
					type_print(want, expected_field_ty);
					if (expr_ty)
						type_print(got, expr_ty);
					else
						strcpy(got, "(unknown)");
					char msg[256] = "";
					snprintf(msg, sizeof(msg), "slice literal: field %s expects %s, got %s.", slot == 0 ? "ptr" : "len", want, got);
					report(expr->location, msg, 0);
					r = RESULT_FAILURE;
				}
			}
		}
		if (r != RESULT_SUCCESS) {
			*out_result = r;
			return 1;
		}
	}
	if (!seen[0] || !seen[1]) {
		report(node->location, "slice literal: missing field initializer.", 0);
		*out_result = RESULT_FAILURE;
		return 1;
	}
	*out_result = RESULT_SUCCESS;
	return 1;
}

CompilerResult analyze_struct_literal(Symbol *table, Type *expected_type, ASTNode *node, int scope_level, const char *scope_specifier) {
	assert(node->type == AST_STRUCT_LITERAL);
	CompilerResult slice_result;
	if (try_analyze_slice_literal(table, expected_type, node, scope_level, scope_specifier, &slice_result))
		return slice_result;
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
		// Bounds-check after the designator (designators can move the
		// cursor backward, so the check has to run on the final index).
		if (current_field_index >= decl_node->data.struct_decl.field_count) {
			char msg[256] = "";
			sprintf(msg, "struct '%s' has %d fields, check initialization.", expected_type->type_name, decl_node->data.struct_decl.field_count);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}

		ASTNode *field_decl = decl_node->data.struct_decl.fields[current_field_index];
		Type *field_type = field_decl->data.field_decl.type;
		ASTNode *expr = init->expr;

		CompilerResult init_result = RESULT_SUCCESS;
		if (expr->type == AST_EXPR_LITERAL) {
			init_result = analyze_expr_literal(table, field_type, expr, scope_level, scope_specifier);
		} else if (expr->type == AST_STRUCT_LITERAL) {
			init_result = analyze_struct_literal(table, field_type, expr, scope_level, scope_specifier);
		} else if (expr->type == AST_CHAR_LIT) {
			if (field_type->type_kind != TYPE_PRIMITIVE || (field_type->prim != PRIM_U8 && field_type->prim != PRIM_I8)) {
				char type_str[128] = "";
				type_print(type_str, field_type);
				char msg[256] = "";
				sprintf(msg, "cannot initialize field '%s' of type %s with a char literal.", field_decl->data.field_decl.name, type_str);
				report(expr->location, msg, 0);
				init_result = RESULT_FAILURE;
			}
		} else {
			init_result = analyze_ast(table, expr, scope_level, scope_specifier);
			if (init_result == RESULT_SUCCESS) {
				Type *expr_type = get_type(table, expr, scope_level, scope_specifier);
				if (!expr_type || !is_convertible(expr_type, field_type, 0, table)) {
					char field_ty_str[128] = "";
					char expr_ty_str[128] = "";
					type_print(field_ty_str, field_type);
					if (expr_type)
						type_print(expr_ty_str, expr_type);
					else
						strcpy(expr_ty_str, "(unknown)");
					char msg[256] = "";
					sprintf(msg, "type mismatch initializing field '%s': cannot implicitly convert %s to %s.", field_decl->data.field_decl.name, expr_ty_str, field_ty_str);
					report(expr->location, msg, 0);
					init_result = RESULT_FAILURE;
				}
			}
		}
		if (init_result != RESULT_SUCCESS)
			return init_result;

		++current_field_index;
	}
	return RESULT_SUCCESS;
}

// Literals are conceptually untyped in Stage 1: an integer literal adapts
// to any int target, a float literal to any float target, a bool literal to
// bool, a null literal to any pointer. Saves the user from writing
// `u8 a = (u8)0;` everywhere until proper comptime-int support lands.
int literal_fits_type(ASTNode *node, Type *target) {
	if (!node || !target || node->type != AST_EXPR_LITERAL)
		return 0;
	if (node->data.literal.is_null)
		return target->type_kind == TYPE_POINTER || target->type_kind == TYPE_SLICE;
	if (target->type_kind != TYPE_PRIMITIVE)
		return 0;
	if (node->data.literal.is_bool)
		return target->prim == PRIM_BOOL;
	if (node->data.literal.is_float)
		return is_float(target);
	return is_int(target) && target->prim != PRIM_BOOL;
}

CompilerResult analyze_expr_literal(Symbol *table, Type *lvalue_type, ASTNode *node, int scope_level, const char *scope_specifier) {
	if (literal_fits_type(node, lvalue_type))
		return RESULT_SUCCESS;

	Type *rtype = get_type(table, node, scope_level, scope_specifier);
	if (rtype) {
		char left_str[128] = "";
		char right_str[128] = "";
		type_print(left_str, lvalue_type);
		type_print(right_str, rtype);
		char msg[256] = "";
		sprintf(msg, "assignment type mismatch: cannot implicitly convert %s to %s.", right_str, left_str);
		report(node->location, msg, 0);
	} else {
		char msg[256] = "";
		sprintf(msg, "Could not determine the type of rvalue in variable initialization.");
		report(node->location, msg, 0);
	}
	return RESULT_FAILURE;
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

// Extract the constant integer value of a switch case value AST node. Returns 1 on success.
static int switch_case_value_const(Symbol *table, ASTNode *node, int scope_level, long *out_value) {
	if (!node)
		return 0;
	if (node->type == AST_EXPR_LITERAL) {
		if (node->data.literal.is_float || node->data.literal.is_bool || node->data.literal.is_null)
			return 0;
		*out_value = node->data.literal.long_value;
		return 1;
	}
	if (node->type == AST_ENUM_VALUE) {
		Symbol *sym = lookup_symbol(table, node->data.enum_value.enum_type->type_resolved_name, scope_level);
		if (!sym || sym->kind != SYMB_ENUM)
			return 0;
		for (int i = 0; i < sym->node->data.enum_decl.member_count; ++i) {
			if (strcmp(sym->node->data.enum_decl.members[i]->name, node->data.enum_value.member) == 0) {
				*out_value = sym->node->data.enum_decl.members[i]->value;
				return 1;
			}
		}
	}
	return 0;
}

CompilerResult analyze_switch_stmt(Symbol *table, ASTNode *node, int scope_level, const char *scope_specifier) {
	CompilerResult result = analyze_ast(table, node->data.switch_stmt.subject, scope_level, scope_specifier);
	if (result != RESULT_SUCCESS)
		return result;
	Type *subject_type = get_type(table, node->data.switch_stmt.subject, scope_level, scope_specifier);
	if (!subject_type) {
		report(node->data.switch_stmt.subject->location, "could not determine type of switch subject.", 0);
		return RESULT_FAILURE;
	}
	if (subject_type->type_kind == TYPE_UNDECIDED)
		resolve_type(table, subject_type, node->data.switch_stmt.subject->location);
	int subject_is_enum = subject_type->type_kind == TYPE_ENUM;
	int subject_is_int = is_int(subject_type) && subject_type->prim != PRIM_BOOL;
	if (!subject_is_enum && !subject_is_int) {
		char type_msg[128] = "";
		type_print(type_msg, subject_type);
		char msg[256] = "";
		sprintf(msg, "switch subject must be an integer or enum type, got %s.", type_msg);
		report(node->data.switch_stmt.subject->location, msg, 0);
		return RESULT_FAILURE;
	}
	int total_values = 0;
	for (int c = 0; c < node->data.switch_stmt.case_count; ++c)
		total_values += node->data.switch_stmt.cases[c].value_count;
	long stack_seen[256];
	if (total_values > 256) {
		report(node->location, "switch has too many case values (limit 256 in Stage 1).", 0);
		return RESULT_FAILURE;
	}
	long *seen = stack_seen;
	int seen_count = 0;
	for (int c = 0; c < node->data.switch_stmt.case_count; ++c) {
		for (int v = 0; v < node->data.switch_stmt.cases[c].value_count; ++v) {
			ASTNode *val = node->data.switch_stmt.cases[c].values[v];
			result = analyze_ast(table, val, scope_level, scope_specifier);
			if (result != RESULT_SUCCESS)
				return result;
			if (subject_is_enum) {
				if (val->type != AST_ENUM_VALUE) {
					report(val->location, "case value for an enum switch must be an enum member (e.g. EnumT::Member).", 0);
					return RESULT_FAILURE;
				}
				if (strcmp(val->data.enum_value.enum_type->type_resolved_name, subject_type->type_resolved_name) != 0) {
					char msg[256] = "";
					sprintf(msg, "case value belongs to enum %s but switch subject is of enum %s.", val->data.enum_value.enum_type->type_name, subject_type->type_name);
					report(val->location, msg, 0);
					return RESULT_FAILURE;
				}
			} else {
				if (val->type != AST_EXPR_LITERAL || !literal_fits_type(val, subject_type)) {
					char type_msg[128] = "";
					type_print(type_msg, subject_type);
					char msg[256] = "";
					sprintf(msg, "case value must be an integer literal compatible with switch subject type %s.", type_msg);
					report(val->location, msg, 0);
					return RESULT_FAILURE;
				}
			}
			long const_val = 0;
			if (!switch_case_value_const(table, val, scope_level, &const_val)) {
				report(val->location, "case value must be a constant.", 0);
				return RESULT_FAILURE;
			}
			for (int i = 0; i < seen_count; ++i) {
				if (seen[i] == const_val) {
					char msg[128] = "";
					sprintf(msg, "duplicate case value %ld in switch.", const_val);
					report(val->location, msg, 0);
					return RESULT_FAILURE;
				}
			}
			seen[seen_count++] = const_val;
		}
		result = analyze_ast(table, node->data.switch_stmt.cases[c].body, scope_level + 1, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;
	}
	if (node->data.switch_stmt.else_body) {
		result = analyze_ast(table, node->data.switch_stmt.else_body, scope_level + 1, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;
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
				if (type->prim != PRIM_U8 && type->prim != PRIM_I8)
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
					ASTNode *elem = array_literal->data.array_literal.elements[i];
					// This if is a hack that essentially prevents type checking in nested array literals
					if (elem->type != AST_ARRAY_LITERAL) {
						Type *element_type = get_type(table, elem, scope_level, scope_specifier);
						Type *expected_elem = node->data.var_decl.type->array.element_type;
						if (!literal_fits_type(elem, expected_elem) && !is_convertible(element_type, expected_elem, 1, table)) {
							char type_str[128] = "";
							type_print(type_str, expected_elem);
							char msg[256] = "";
							sprintf(msg, "array initialization mistype, expected type %s.", type_str);
							report(elem->location, msg, 0);
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
					Type *elem = lhs_type->array.element_type;
					if (elem->type_kind != TYPE_PRIMITIVE || (elem->prim != PRIM_I8 && elem->prim != PRIM_U8)) {
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
					Type *pointee = lhs_type->pointee;
					if (pointee->type_kind != TYPE_PRIMITIVE || (pointee->prim != PRIM_I8 && pointee->prim != PRIM_U8)) {
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
				// pick the foo overload whose signature matches the declared fn pointer type so the right resolved_name
				// flows through to codegen.
				if (node->data.var_decl.type->type_kind == TYPE_FUNCTION && node->data.var_decl.init->type == AST_UNARY_EXPR && node->data.var_decl.init->data.unary_op.op == '&' &&
					node->data.var_decl.init->data.unary_op.operand && node->data.var_decl.init->data.unary_op.operand->type == AST_EXPR_IDENT) {
					ASTNode *ident = node->data.var_decl.init->data.unary_op.operand;
					Type *target = node->data.var_decl.type;
					Symbol *match = NULL;
					for (Symbol *s = table; s != NULL; s = s->next) {
						if (s->kind != SYMB_FN)
							continue;
						if (strcmp(s->name, ident->data.ident.name) != 0)
							continue;
						if (!s->type || s->type->type_kind != TYPE_FUNCTION)
							continue;
						if (type_equals(s->type, target)) {
							match = s;
							break;
						}
					}
					if (match)
						strncpy(ident->data.ident.resolved_name, match->resolved_name, sizeof(ident->data.ident.resolved_name));
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
			// Per-overload params can collide on short name; prefer the scoped match.
			if (scope_specifier[0] != '\0') {
				char scoped[512];
				int n = snprintf(scoped, sizeof(scoped), "%s_%s", scope_specifier, node->data.ident.name);
				if (n > 0 && (size_t)n < sizeof(scoped)) {
					Symbol *scoped_sym = lookup_symbol(table, scoped, scope_level);
					if (scoped_sym) {
						strncpy(node->data.ident.resolved_name, scoped_sym->resolved_name, sizeof(node->data.ident.resolved_name));
						return RESULT_SUCCESS;
					}
				}
			}
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
		char resolved_name[512] = "";
		int written;
		if (scope_specifier[0] != '\0')
			written = snprintf(resolved_name, sizeof(resolved_name), "%s_%s", scope_specifier, node->data.ident.name);
		else
			written = snprintf(resolved_name, sizeof(resolved_name), "%s", node->data.ident.name);
		if (written < 0 || (size_t)written >= sizeof(resolved_name)) {
			report(node->location, "resolved identifier name exceeds buffer size.", 0);
			return RESULT_FAILURE;
		}
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
		strncpy(node->data.ident.resolved_name, resolved_name, sizeof(node->data.ident.resolved_name));
	} break;

	case AST_RETURN: {
		CompilerResult result = analyze_ast(table, node->data.ret.return_expr, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;
		Symbol *sym = lookup_symbol(table, scope_specifier, scope_level);
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
		// `&&` / `||` accept anything bool-convertible on either side
		// independently — the generic mutual-convertibility check below
		// would wrongly reject e.g. `ptr && (a < b)`.
		if (node->data.binary_op.op == TOK_AND || node->data.binary_op.op == TOK_OR) {
			Type bool_type = get_primitive_type("bool");
			if (!is_convertible(ltype, &bool_type, 1, table)) {
				char type_str[128] = "";
				type_print(type_str, ltype);
				char msg[256] = "";
				sprintf(msg, "logical '%s' requires a boolean-convertible left operand, got %s.", node->data.binary_op.op == TOK_AND ? "&&" : "||", type_str);
				report(node->location, msg, 0);
				return RESULT_FAILURE;
			}
			if (!is_convertible(rtype, &bool_type, 1, table)) {
				char type_str[128] = "";
				type_print(type_str, rtype);
				char msg[256] = "";
				sprintf(msg, "logical '%s' requires a boolean-convertible right operand, got %s.", node->data.binary_op.op == TOK_AND ? "&&" : "||", type_str);
				report(node->location, msg, 0);
				return RESULT_FAILURE;
			}
			break;
		}
		// Integer / float / null literals take on the other side's primitive type at use-site
		int literal_match = literal_fits_type(node->data.binary_op.right, ltype) || literal_fits_type(node->data.binary_op.left, rtype);
		if (!literal_match && !is_convertible(rtype, ltype, 1, table)) {
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
			char resolved_name[512] = "";
			ASTNode *lvalue = node->data.assignment.lvalue;
			if (analyze_expr_ident(table, lvalue, scope_level) == RESULT_SUCCESS) {
				strncpy(resolved_name, lvalue->data.ident.resolved_name, sizeof(resolved_name));
			} else {
				int written;
				if (scope_specifier[0] != '\0')
					written = snprintf(resolved_name, sizeof(resolved_name), "%s_%s", scope_specifier, lvalue->data.ident.name);
				else
					written = snprintf(resolved_name, sizeof(resolved_name), "%s", lvalue->data.ident.name);
				if (written < 0 || (size_t)written >= sizeof(resolved_name)) {
					report(node->location, "resolved identifier name exceeds buffer size.", 0);
					return RESULT_FAILURE;
				}
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
			if (ltype->prim != PRIM_U8 && ltype->prim != PRIM_I8)
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
				ASTNode *elem = array_literal->data.array_literal.elements[i];
				Type *element_type = get_type(table, elem, scope_level, scope_specifier);
				if (!literal_fits_type(elem, ltype->array.element_type) && !is_convertible(element_type, ltype, 1, table)) {
					char type_str[128] = "";
					type_print(type_str, ltype->array.element_type);
					char msg[256] = "";
					sprintf(msg, "array initialization mistype, expected type %s.", type_str);
					report(elem->location, msg, 0);
					return RESULT_FAILURE;
				}
				result = analyze_ast(table, array_literal->data.array_literal.elements[i], scope_level, scope_specifier);
				if (result != RESULT_SUCCESS) {
					return result;
				}
			}
		} else if (node->data.assignment.lvalue->type == AST_STRING_LIT) {
			if (ltype->type_kind == TYPE_ARRAY) {
				Type *elem = ltype->array.element_type;
				if (elem->type_kind != TYPE_PRIMITIVE || (elem->prim != PRIM_I8 && elem->prim != PRIM_U8)) {
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
				Type *pointee = ltype->pointee;
				if (pointee->type_kind != TYPE_PRIMITIVE || (pointee->prim != PRIM_I8 && pointee->prim != PRIM_U8)) {
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
		ASTNode *callee = node->data.func_call.callee;
		// Args must be analyzed before overload resolution can read their types.
		for (int i = 0; i < node->data.func_call.arg_count; ++i) {
			CompilerResult r = analyze_ast(table, node->data.func_call.args[i], scope_level, scope_specifier);
			if (r != RESULT_SUCCESS)
				return r;
		}
		// Overload pick by exact type-match. Single-candidate (e.g. extern decls)
		// falls through to the legacy is_convertible-based check below. Any
		// resolved_name the parser pre-set is overridden - it just grabs the
		// first matching overload.
		if (callee->type == AST_EXPR_IDENT) {
			int candidate_count = 0;
			for (Symbol *s = table; s != NULL; s = s->next) {
				if (s->kind == SYMB_FN && strcmp(s->name, callee->data.ident.name) == 0)
					++candidate_count;
			}
			if (candidate_count > 1) {
				Symbol *match = NULL;
				int ambiguous = 0;
				for (Symbol *s = table; s != NULL; s = s->next) {
					if (s->kind != SYMB_FN)
						continue;
					if (strcmp(s->name, callee->data.ident.name) != 0)
						continue;
					int has_va = 0;
					int non_va = 0;
					for (ASTNode *p = s->node->data.func_decl.params; p; p = p->next) {
						if (p->data.param_decl.is_va) {
							has_va = 1;
							break;
						}
						++non_va;
					}
					if (!has_va && non_va != node->data.func_call.arg_count)
						continue;
					if (has_va && non_va > node->data.func_call.arg_count)
						continue;
					int ok = 1;
					ASTNode *p = s->node->data.func_decl.params;
					for (int i = 0; i < non_va && p; ++i, p = p->next) {
						Type *arg_type = get_type(table, node->data.func_call.args[i], scope_level, scope_specifier);
						if (!arg_type) {
							ok = 0;
							break;
						}
						// resolve_types runs after analyze_ast, so types here may still be UNDECIDED.
						resolve_type(table, arg_type, node->location);
						resolve_type(table, p->data.param_decl.type, node->location);
						if (!type_equals(arg_type, p->data.param_decl.type)) {
							ok = 0;
							break;
						}
					}
					if (!ok)
						continue;
					if (match && match != s)
						ambiguous = 1;
					match = s;
				}
				if (ambiguous) {
					char msg[256] = "";
					snprintf(msg, sizeof(msg), "ambiguous call to %s.", callee->data.ident.name);
					report(node->location, msg, 0);
					return RESULT_FAILURE;
				}
				if (match) {
					strncpy(callee->data.ident.resolved_name, match->resolved_name, sizeof(callee->data.ident.resolved_name));
				} else {
					char msg[256] = "";
					snprintf(msg, sizeof(msg), "no overload of %s matches the call signature.", callee->data.ident.name);
					report(node->location, msg, 0);
					return RESULT_FAILURE;
				}
			}
		}
		CompilerResult result = analyze_ast(table, callee, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;
		// Previous call to analyze_ast would fail if the symbol didn't exist.
		// Try module scope first (regular fns); fall back to current scope for fn-ptr locals.
		Symbol *sym = NULL;
		const char *key = callee->data.ident.resolved_name[0] != '\0' ? callee->data.ident.resolved_name : callee->data.ident.name;
		sym = lookup_symbol(table, key, 0);
		if (!sym)
			sym = lookup_symbol(table, key, scope_level);
		assert(sym);
		// Function pointers are stored as SYMB_VAR with a TYPE_FUNCTION, treat them as callable.
		int is_fn_ptr = sym->kind == SYMB_VAR && sym->type && sym->type->type_kind == TYPE_FUNCTION;
		if (!is_fn_ptr && ((sym->node->type != AST_FN_DECL && sym->node->type != AST_EXTERN_FUNC_DECL) || sym->kind != SYMB_FN)) {
			char msg[256] = "";
			sprintf(msg, "symbol %s is not a function but used as a function.", node->data.func_call.callee->data.ident.name);
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		// @TODO: cache this probably
		int non_va_param_count = 0;
		ASTNode *param = is_fn_ptr ? NULL : sym->node->data.func_decl.params;
		if (is_fn_ptr) {
			non_va_param_count = sym->type->function.param_count;
		} else {
			while (param) {
				if (param->data.param_decl.is_va)
					break;
				++non_va_param_count;
				param = param->next;
			}
		}
		if (non_va_param_count > node->data.func_call.arg_count) {
			char msg[256] = "";
			sprintf(msg, "argument count mismatch.");
			report(node->location, msg, 0);
			return RESULT_FAILURE;
		}
		// Args already analyzed above; re-analyzing would clobber unary result_types.
		param = is_fn_ptr ? NULL : sym->node->data.func_decl.params;
		for (int i = 0; i < node->data.func_call.arg_count; ++i) {
			if (i < non_va_param_count) {
				Type *param_type = is_fn_ptr ? sym->type->function.param_types[i] : param->data.param_decl.type;
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
				if (!is_fn_ptr)
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
				result = analyze_ast(table, param, scope_level + 1, node->data.func_decl.resolved_name);
				param = param->next;
			}
			if (result != RESULT_SUCCESS)
				return result;
		}
		if (node->data.func_decl.body) {
			CompilerResult result = analyze_ast(table, node->data.func_decl.body, scope_level + 1, node->data.func_decl.resolved_name);
			if (result != RESULT_SUCCESS)
				return result;

			if (node->data.func_decl.body->data.block.count) {
				ASTNode *last_stmt = node->data.func_decl.body->data.block.statements[node->data.func_decl.body->data.block.count - 1];
				if ((fn_type->function.return_type->type_kind != TYPE_PRIMITIVE || fn_type->function.return_type->prim != PRIM_VOID) && (!last_stmt || last_stmt->type != AST_RETURN)) {
					char msg[256] = "";
					sprintf(msg, "the last statement in a non-void function must be a return statement.");
					report(last_stmt->location, msg, 0);
					return RESULT_FAILURE;
				}
				if (last_stmt && last_stmt->type == AST_RETURN) {
					Type *stmt_type = get_type(table, last_stmt, scope_level + 1, node->data.func_decl.resolved_name);
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
		break;

	case AST_SLICE_RANGE: {
		CompilerResult r = analyze_ast(table, node->data.slice_range.base, scope_level, scope_specifier);
		if (r != RESULT_SUCCESS)
			return r;
		r = analyze_ast(table, node->data.slice_range.lo, scope_level, scope_specifier);
		if (r != RESULT_SUCCESS)
			return r;
		r = analyze_ast(table, node->data.slice_range.hi, scope_level, scope_specifier);
		if (r != RESULT_SUCCESS)
			return r;
		Type *base_ty = get_type(table, node->data.slice_range.base, scope_level, scope_specifier);
		if (!base_ty || (base_ty->type_kind != TYPE_ARRAY && base_ty->type_kind != TYPE_SLICE)) {
			report(node->location, "slice range can only be applied to arrays or slices.", 0);
			return RESULT_FAILURE;
		}
		Type *lo_ty = get_type(table, node->data.slice_range.lo, scope_level, scope_specifier);
		Type *hi_ty = get_type(table, node->data.slice_range.hi, scope_level, scope_specifier);
		if (!lo_ty || !is_int(lo_ty) || !hi_ty || !is_int(hi_ty)) {
			report(node->location, "slice range bounds must be integers.", 0);
			return RESULT_FAILURE;
		}
		return RESULT_SUCCESS;
	}

	case AST_CAST: {
		CompilerResult result = resolve_type(table, node->data.cast.target_type, node->location);
		if (result != RESULT_SUCCESS)
			return result;
		result = analyze_ast(table, node->data.cast.expr, scope_level, scope_specifier);
		if (result != RESULT_SUCCESS)
			return result;
		Type *expr_type = get_type(table, node->data.cast.expr, scope_level, scope_specifier);
		assert(expr_type);
		// Param-typed exprs are still UNDECIDED until resolve_types runs.
		if (expr_type->type_kind == TYPE_UNDECIDED)
			resolve_type(table, expr_type, node->location);
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
		if (!is_convertible(condition_type, &bool_type, 1, table)) {
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
		CompilerResult result = RESULT_SUCCESS;
		if (node->data.for_loop.init) {
			result = analyze_ast(table, node->data.for_loop.init, scope_level, scope_specifier);
			if (result != RESULT_SUCCESS)
				return result;
		}

		if (node->data.for_loop.condition) {
			result = analyze_ast(table, node->data.for_loop.condition, scope_level, scope_specifier);
			if (result != RESULT_SUCCESS)
				return result;

			Type bool_type = get_primitive_type("bool");
			Type *condition_type = get_type(table, node->data.for_loop.condition, scope_level, scope_specifier);
			if (!is_convertible(condition_type, &bool_type, 1, table)) {
				char condition_type_str[128] = "";
				type_print(condition_type_str, condition_type);
				char msg[128] = "";
				sprintf(msg, "for loop condition must convert to bool but is of type %s .", condition_type_str);
				report(node->data.for_loop.condition->location, msg, 0);
				return RESULT_FAILURE;
			}
		}

		if (node->data.for_loop.post) {
			result = analyze_ast(table, node->data.for_loop.post, scope_level, scope_specifier);
			if (result != RESULT_SUCCESS)
				return result;
		}

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
		// .len is the only member that slices and arrays expose, so reject
		// any other member name with a targeted diagnostic so we don't
		// fall through to "can only access members of structs or unions
		// which would be confusing here.
		if (base_type->type_kind == TYPE_SLICE || base_type->type_kind == TYPE_ARRAY) {
			if (strcmp(node->data.member_access.member, "len") != 0) {
				char msg[128] = "";
				snprintf(msg, sizeof(msg), "%s only exposes the 'len' member.", base_type->type_kind == TYPE_SLICE ? "slice" : "array");
				report(base_node->location, msg, 0);
				return RESULT_FAILURE;
			}
			return RESULT_SUCCESS;
		}
		if (base_type->type_kind == TYPE_POINTER && base_type->pointee)
			base_type = base_type->pointee;
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
		// Must be an array, slice, or pointer
		if (base_ty->type_kind != TYPE_ARRAY && base_ty->type_kind != TYPE_POINTER && base_ty->type_kind != TYPE_SLICE) {
			report(node->location, "subscripted value is not an array, slice, or pointer", 0);
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

	case AST_SWITCH_STMT:
		return analyze_switch_stmt(table, node, scope_level, scope_specifier);

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
	} else if (type->type_kind == TYPE_SLICE) {
		return resolve_type(table, type->slice.element_type, loc);
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
    return RESULT_SUCCESS;
}

CompilerResult resolve_types(Symbol *table, ASTNode *root, int should_traverse_symbols) {
	if (should_traverse_symbols) {
		Symbol *sym = table;
		int result = 1;
		while (sym) {
			result &= resolve_type(table, sym->type, sym->node->location) == RESULT_SUCCESS;
			if (sym->kind == SYMB_STRUCT || sym->kind == SYMB_ENUM || sym->kind == SYMB_UNION) {
				if (sym->type->type_resolved_name[0] == '\0') {
					strncpy(sym->type->type_resolved_name, sym->resolved_name, sizeof(sym->type->type_resolved_name));
				}
			}
			sym = sym->next;
		}
		if (!result) {
			return RESULT_FAILURE;
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
