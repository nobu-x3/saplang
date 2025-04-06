#include "parser.h"
#include "scanner.h"
#include "symbol_table.h"
#include "types.h"
#include "util.h"
#include <assert.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// @TODO: fix memleaks on return NULL

void free_ast_node(ASTNode *node);

typedef struct {
	ASTNode **data;
	int capacity;
	int count;
} NodeList;

CompilerResult parser_init(Parser *parser, Scanner scanner, SymbolTableWrapper *optional_table_wrapper) {
	if (!parser)
		return RESULT_PASSED_NULL_PTR;

	if (!memset(parser, 0, sizeof(Parser)))
		return RESULT_MEMORY_ERROR;

	parser->scanner = scanner;

	if (optional_table_wrapper) {
		parser->symbol_table = optional_table_wrapper->internal_table;
		parser->exported_table = optional_table_wrapper->exported_table;
	}

	char *cpy = strdup(scanner.source.name);
	char *tmp = cpy;
	char *ch = strtok(cpy, ".");
	strncpy(parser->module_name, ch, sizeof(parser->module_name));
	free(tmp);
	return RESULT_SUCCESS;
}

CompilerResult parser_deinit(Parser *parser) {
	if (!parser)
		return RESULT_PASSED_NULL_PTR;

	scanner_deinit(&parser->scanner);
	return RESULT_SUCCESS;
}

CompilerResult ast_print(ASTNode *node, int indent, char *string) {
	if (!node)
		return RESULT_PASSED_NULL_PTR;
	while (node) {
		if (node->type != AST_DEFERRED_SEQUENCE) {
			for (int i = 0; i < indent; ++i) {
				print(string, "  ");
			}
		}
		switch (node->type) {
		case AST_VAR_DECL: {
			print(string, "VarDecl: %s%s", node->data.var_decl.is_exported ? "exported " : "", node->data.var_decl.is_const ? "const " : "");
			type_print(string, node->data.var_decl.type);
			print(string, " %s", node->data.var_decl.name);
			if (node->data.var_decl.init) {
				print(string, ":\n");
				ast_print(node->data.var_decl.init, indent + 1, string);
			} else {
				print(string, "\n");
			}
			break;
		}
		case AST_STRUCT_DECL:
			print(string, "StructDecl: %s%s\n", node->data.struct_decl.is_exported ? "exported " : "", node->data.struct_decl.name);
			ast_print(node->data.struct_decl.fields, indent + 1, string);
			break;
		case AST_UNION_DECL:
			print(string, "UnionDecl: %s%s\n", node->data.struct_decl.is_exported ? "exported " : "", node->data.union_decl.name);
			ast_print(node->data.union_decl.fields, indent + 1, string);
			break;
		case AST_FN_DECL:
			print(string, "FuncDecl: %s%s\n", node->data.func_decl.is_exported ? "exported " : "", node->data.func_decl.name);
			for (int i = 0; i < indent + 1; i++) {
				print(string, "  ");
			}
			print(string, "Params:\n");
			ast_print(node->data.func_decl.params, indent + 2, string);
			for (int i = 0; i < indent + 1; i++)
				print(string, "  ");
			print(string, "Body:\n");
			ast_print(node->data.func_decl.body, indent + 2, string);
			break;
		case AST_FIELD_DECL: {
			print(string, "FieldDecl: ");
			type_print(string, node->data.field_decl.type);
			print(string, " %s\n", node->data.field_decl.name)
		} break;
		case AST_PARAM_DECL:
			if (node->data.param_decl.is_va) {
				print(string, "ParamDecl: ...\n");
			} else {
				print(string, "ParamDecl: %s", node->data.param_decl.is_const ? "const " : "");
				type_print(string, node->data.param_decl.type);
				print(string, " %s\n", node->data.param_decl.name)
			}
			break;
		case AST_BLOCK:
			print(string, "Block with %d statement(s):\n", node->data.block.count);
			for (int i = 0; i < node->data.block.count; i++) {
				ast_print(node->data.block.statements[i], indent + 1, string);
			}
			break;
		case AST_EXPR_LITERAL:
			if (node->data.literal.is_bool) {
				print(string, "Literal Bool: %s\n", node->data.literal.bool_value ? "true" : "false");
			} else if (node->data.literal.is_float) {
				print(string, "Literal Float: %f\n", node->data.literal.float_value);
			} else {
				print(string, "Literal Int: %ld\n", node->data.literal.long_value);
			}
			break;
		case AST_EXPR_IDENT: {
			char prefix[64] = "";
			if (*node->data.ident.namespace) {
				sprintf(prefix, "%s::", node->data.ident.namespace);
			}
			print(string, "Ident: %s%s\n", prefix, node->data.ident.name);
		} break;
		case AST_RETURN:
			print(string, "Return:\n");
			ast_print(node->data.ret.return_expr, indent + 1, string);
			break;
		case AST_BINARY_EXPR:
			switch (node->data.binary_op.op) {
			case TOK_OR:
				print(string, "Binary Expression: ||\n");
				break;
			case TOK_SELFOR:
				print(string, "Binary Expression: |=\n");
				break;
			case TOK_AND:
				print(string, "Binary Expression: &&\n");
				break;
			case TOK_SELFAND:
				print(string, "Binary Expression: &=\n");
				break;
			case TOK_PLUS:
				print(string, "Binary Expression: +\n");
				break;
			case TOK_MINUS:
				print(string, "Binary Expression: -\n");
				break;
			case TOK_ASTERISK:
				print(string, "Binary Expression: *\n");
				break;
			case TOK_SLASH:
				print(string, "Binary Expression: /\n");
				break;
			case TOK_LESSTHAN:
				print(string, "Binary Expression: <\n");
				break;
			case TOK_GREATERTHAN:
				print(string, "Binary Expression: >\n");
				break;
			case TOK_EQUAL:
				print(string, "Binary Expression: ==\n");
				break;
			case TOK_NOTEQUAL:
				print(string, "Binary Expression: !=\n");
				break;
			case TOK_LTOE:
				print(string, "Binary Expression: <=\n");
				break;
			case TOK_GTOE:
				print(string, "Binary Expression: >=\n");
				break;
			case TOK_SELFADD:
				print(string, "Binary Expression: +=\n");
				break;
			case TOK_SELFSUB:
				print(string, "Binary Expression: -=\n");
				break;
			case TOK_SELFMUL:
				print(string, "Binary Expression: *=\n");
				break;
			case TOK_SELFDIV:
				print(string, "Binary Expression: /=\n");
				break;
			case TOK_BITWISE_XOR:
				print(string, "Binary Expression: ^\n");
				break;
			case TOK_BITWISE_NEG:
				print(string, "Binary Expression: ~\n");
				break;
			case TOK_BITWISE_OR:
				print(string, "Binary Expression: |\n");
				break;
			case TOK_BITWISE_LSHIFT:
				print(string, "Binary Expression: <<\n");
				break;
			case TOK_BITWISE_RSHIFT:
				print(string, "Binary Expression: >>\n");
				break;
			case TOK_AMPERSAND:
				print(string, "Binary Expression: &\n");
				break;
			case TOK_MODULO:
				print(string, "Binary Expression: %\n");
				break;
			default:
				break;
			}
			ast_print(node->data.binary_op.left, indent + 1, string);
			ast_print(node->data.binary_op.right, indent + 1, string);
			break;
		case AST_UNARY_EXPR:
			print(string, "Unary Expression: %c\n", node->data.unary_op.op);
			ast_print(node->data.unary_op.operand, indent + 1, string);
			break;
		case AST_ARRAY_LITERAL:
			print(string, "Array literal of size %d:\n", node->data.array_literal.count);
			for (int i = 0; i < node->data.array_literal.count; ++i) {
				ast_print(node->data.array_literal.elements[i], indent + 1, string);
			}
			break;
		case AST_ARRAY_ACCESS:
			print(string, "Array access:\n");
			ast_print(node->data.array_access.base, indent + 1, string);
			ast_print(node->data.array_access.index, indent + 1, string);
			break;
		case AST_ASSIGNMENT:
			print(string, "Assignment:\n");
			ast_print(node->data.assignment.lvalue, indent + 1, string);
			ast_print(node->data.assignment.rvalue, indent + 1, string);
			break;
		case AST_FN_CALL:
			print(string, "Function call with %d args:\n", node->data.func_call.arg_count);
			ast_print(node->data.func_call.callee, indent + 1, string);
			for (int i = 0; i < node->data.func_call.arg_count; ++i) {
				ast_print(node->data.func_call.args[i], indent + 1, string);
			}
			break;
		case AST_MEMBER_ACCESS:
			print(string, "Member access: %s\n", node->data.member_access.member);
			ast_print(node->data.member_access.base, indent + 1, string);
			break;
		case AST_STRUCT_LITERAL:
			print(string, "StructLiteral with %d initializer(s):\n", node->data.struct_literal.count);
			for (int i = 0; i < node->data.struct_literal.count; ++i) {
				if (node->data.struct_literal.inits[i]->is_designated) {
					for (int i = 0; i < indent + 1; ++i) {
						print(string, "  ");
					}
					char prefix[128] = "";
					sprintf(prefix, "Designated, field '%s':", node->data.struct_literal.inits[i]->field);
					print(string, "%s\n", prefix);
				}
				ast_print(node->data.struct_literal.inits[i]->expr, indent + 1 + node->data.struct_literal.inits[i]->is_designated, string);
			}
			break;
		case AST_ENUM_DECL: {
			print(string, "EnumDecl with %d member(s) - %s%s : ", node->data.enum_decl.member_count, node->data.enum_decl.is_exported ? "exported " : "", node->data.enum_decl.name);
			type_print(string, node->data.enum_decl.base_type);
			print(string, ":\n");
			for (int i = 0; i < node->data.enum_decl.member_count; ++i) {
				for (int i = 0; i < indent + 1; ++i) {
					print(string, "  ");
				}
				char prefix[128] = "";
				sprintf(prefix, "%s : %ld", node->data.enum_decl.members[i]->name, node->data.enum_decl.members[i]->value);
				print(string, "%s\n", prefix);
			}
		} break;
		case AST_ENUM_VALUE: {
			print(string, "EnumValue: ");
			type_print(string, node->data.enum_value.enum_type);
			print(string, "::%s", node->data.enum_value.member)
		} break;
		case AST_EXTERN_BLOCK:
			print(string, "ExternBlock from lib %s:\n", node->data.extern_block.lib_name);
			for (int i = 0; i < node->data.extern_block.count; ++i) {
				ast_print(node->data.extern_block.block[i], indent + 1, string);
			}
			break;
		case AST_EXTERN_FUNC_DECL:
			print(string, "Extern FuncDecl %s%s:\n", node->data.extern_func.is_exported ? "exported " : "", node->data.extern_func.name);
			for (int i = 0; i < indent + 1; i++)
				print(string, "  ");
			print(string, "Params:\n");
			ast_print(node->data.extern_func.params, indent + 2, string);
			break;
		case AST_IF_STMT:
			print(string, "IfElseStmt:\n");
			for (int i = 0; i < indent + 1; i++)
				print(string, "  ");
			print(string, "Condition:\n");
			ast_print(node->data.if_stmt.condition, indent + 2, string);
			for (int i = 0; i < indent + 1; i++)
				print(string, "  ");
			print(string, "Then:\n");
			ast_print(node->data.if_stmt.then_branch, indent + 2, string);
			for (int i = 0; i < indent + 1; i++)
				print(string, "  ");
			print(string, "Else:\n");
			ast_print(node->data.if_stmt.else_branch, indent + 2, string);
			break;

		case AST_FOR_LOOP:
			print(string, "ForLoop:\n");
			for (int i = 0; i < indent + 1; i++)
				print(string, "  ");
			print(string, "Init:\n");
			ast_print(node->data.for_loop.init, indent + 2, string);
			for (int i = 0; i < indent + 1; i++)
				print(string, "  ");
			print(string, "Condition:\n");
			ast_print(node->data.for_loop.condition, indent + 2, string);
			for (int i = 0; i < indent + 1; i++)
				print(string, "  ");
			print(string, "Post:\n");
			ast_print(node->data.for_loop.post, indent + 2, string);
			for (int i = 0; i < indent + 1; i++)
				print(string, "  ");
			print(string, "Body:\n");
			ast_print(node->data.for_loop.body, indent + 2, string);
			break;
		case AST_WHILE_LOOP:
			print(string, "WhileLoop:\n");
			for (int i = 0; i < indent + 1; i++)
				print(string, "  ");
			print(string, "Condition:\n");
			ast_print(node->data.while_loop.condition, indent + 2, string);
			for (int i = 0; i < indent + 1; i++)
				print(string, "  ");
			print(string, "Body:\n");
			ast_print(node->data.while_loop.body, indent + 2, string);
			break;
		case AST_DEFER_BLOCK:
			break;
		case AST_DEFERRED_SEQUENCE:
			for (int i = 0; i < node->data.block.count; ++i) {
				ast_print(node->data.block.statements[i], indent, string);
			}
			break;
		case AST_STRING_LIT:
			print(string, "String Literal: \"%s\"\n", node->data.string_literal.text);
			break;
		case AST_CHAR_LIT:
			print(string, "Char Literal: '%c'\n", node->data.char_literal.literal);
			break;
		case AST_CONTINUE:
			print(string, "continue\n");
			break;
		case AST_BREAK:
			print(string, "break\n");
			break;
		case AST_CAST: {
			char type_str[128] = "";
			type_print(type_str, node->data.cast.target_type);
			print(string, "Explicit cast to %s:\n", type_str);
			ast_print(node->data.cast.expr, indent + 1, string);
		} break;
		default: {
			print(string, "Unknown AST Node\n");
		} break;
		}
		node = node->next;
	}
	return RESULT_SUCCESS;
}

//////////////////// HELPER FUNCTIONS /////////////////////////////////////////
FieldInitializer *new_field_initializer(const char *field_name, int is_designated, ASTNode *expr) {
	FieldInitializer *init = malloc(sizeof(FieldInitializer));
	if (!init)
		return NULL;

	if (is_designated && field_name) {
		strncpy(init->field, field_name, sizeof(init->field));
	} else {
		init->field[0] = '\0';
	}
	init->is_designated = is_designated;
	init->expr = expr;
	return init;
}

ASTNode *new_ast_node(ASTNodeType type, SourceLocation location) {
	ASTNode *node = malloc(sizeof(ASTNode));
	if (!node) {
		return NULL;
	}

	node->location = location;
	node->type = type;
	node->next = NULL;
	return node;
}

ASTNode *copy_ast_node(ASTNode *node) {
	if (!node)
		return NULL;

	ASTNode *new_node = new_ast_node(node->type, node->location);

	switch (node->type) {
	case AST_VAR_DECL:
		strncpy(new_node->data.var_decl.name, node->data.var_decl.name, sizeof(new_node->data.var_decl.name));
		strncpy(new_node->data.var_decl.resolved_name, node->data.var_decl.resolved_name, sizeof(new_node->data.var_decl.resolved_name));
		new_node->data.var_decl.type = copy_type(node->data.var_decl.type);
		new_node->data.var_decl.is_exported = node->data.var_decl.is_exported;
		new_node->data.var_decl.is_const = node->data.var_decl.is_const;
		new_node->data.var_decl.init = copy_ast_node(node->data.var_decl.init);
		break;
	case AST_STRUCT_DECL: {
		strncpy(new_node->data.struct_decl.name, node->data.struct_decl.name, sizeof(new_node->data.struct_decl.name));
		new_node->data.struct_decl.is_exported = node->data.struct_decl.is_exported;
		ASTNode *current_field = node->data.struct_decl.fields;
		while (current_field) {
			ASTNode *next = current_field->next;
			copy_ast_node(current_field);
			current_field = next;
		}
	} break;
	case AST_FN_DECL: {
		strncpy(new_node->data.func_decl.name, node->data.func_decl.name, sizeof(new_node->data.func_decl.name));
		new_node->data.func_decl.is_exported = node->data.func_decl.is_exported;
		ASTNode *curr_param = node->data.func_decl.params;
		ASTNode *curr_new_param = new_node->data.func_decl.params;
		while (curr_param) {
			ASTNode *next = curr_param->next;
			curr_new_param = copy_ast_node(curr_param);
			curr_param = next;
			curr_new_param = curr_new_param->next;
		}
		new_node->data.func_decl.body = copy_ast_node(node->data.func_decl.body);
	} break;
	case AST_BLOCK: {
		new_node->data.block.statements = malloc(sizeof(*new_node->data.block.statements) * node->data.block.count);
		for (int i = 0; i < node->data.block.count; ++i) {
			new_node->data.block.statements[i] = copy_ast_node(node->data.block.statements[i]);
		}
		new_node->data.block.count = node->data.block.count;
	} break;
	case AST_RETURN:
		node->data.ret.return_expr = copy_ast_node(node->data.ret.return_expr);
		break;
	case AST_EXPR_IDENT:
		strncpy(new_node->data.ident.name, node->data.ident.name, sizeof(new_node->data.ident.name));
		strncpy(new_node->data.ident.namespace, node->data.ident.namespace, sizeof(new_node->data.ident.namespace));
		break;
	case AST_BINARY_EXPR:
		new_node->data.binary_op.op = node->data.binary_op.op;
		new_node->data.binary_op.left = copy_ast_node(node->data.binary_op.left);
		new_node->data.binary_op.right = copy_ast_node(node->data.binary_op.right);
		break;
	case AST_UNARY_EXPR:
		new_node->data.unary_op.op = node->data.unary_op.op;
		new_node->data.unary_op.operand = copy_ast_node(node->data.unary_op.operand);
		break;
	case AST_ARRAY_LITERAL:
		new_node->data.array_literal.elements = malloc(sizeof(*node->data.array_literal.elements) * node->data.array_literal.count);
		for (int i = 0; i < node->data.array_literal.count; ++i) {
			new_node->data.array_literal.elements[i] = copy_ast_node(node->data.array_literal.elements[i]);
		}
		new_node->data.array_literal.count = node->data.array_literal.count;
		break;
	case AST_ARRAY_ACCESS:
		new_node->data.array_access.base = copy_ast_node(node->data.array_access.base);
		new_node->data.array_access.index = copy_ast_node(node->data.array_access.index);
		break;
	case AST_ASSIGNMENT:
		new_node->data.assignment.lvalue = copy_ast_node(node->data.assignment.lvalue);
		new_node->data.assignment.rvalue = copy_ast_node(node->data.assignment.rvalue);
		break;
	case AST_FN_CALL:
		new_node->data.func_call.callee = copy_ast_node(node->data.func_call.callee);
		new_node->data.func_call.args = malloc(sizeof(*new_node->data.func_call.args) * node->data.func_call.arg_count);
		for (int i = 0; i < node->data.func_call.arg_count; ++i) {
			new_node->data.func_call.args[i] = copy_ast_node(node->data.func_call.args[i]);
		}
		new_node->data.func_call.arg_count = node->data.func_call.arg_count;
		break;
	case AST_MEMBER_ACCESS:
		strncpy(new_node->data.member_access.member, node->data.member_access.member, sizeof(new_node->data.member_access.member));
		new_node->data.member_access.base = copy_ast_node(node->data.member_access.base);
		break;
	case AST_STRUCT_LITERAL:
		new_node->data.struct_literal.inits = malloc(sizeof(*new_node->data.struct_literal.inits) * node->data.struct_literal.count);
		for (int i = 0; i < node->data.struct_literal.count; ++i) {
			new_node->data.struct_literal.inits[i] = malloc(sizeof(FieldInitializer));
			strncpy(new_node->data.struct_literal.inits[i]->field, node->data.struct_literal.inits[i]->field, sizeof(new_node->data.struct_literal.inits[i]->field));
			new_node->data.struct_literal.inits[i]->is_designated = node->data.struct_literal.inits[i]->is_designated;
			new_node->data.struct_literal.inits[i]->expr = copy_ast_node(node->data.struct_literal.inits[i]->expr);
		}
		new_node->data.struct_literal.count = node->data.struct_literal.count;
		break;
	case AST_ENUM_DECL:
		strncpy(new_node->data.enum_decl.name, node->data.enum_decl.name, sizeof(new_node->data.enum_decl.name));
		new_node->data.enum_decl.base_type = copy_type(node->data.enum_decl.base_type);
		new_node->data.enum_decl.member_count = node->data.enum_decl.member_count;
		new_node->data.enum_decl.is_exported = node->data.enum_decl.is_exported;
		new_node->data.enum_decl.members = malloc(sizeof(*new_node->data.enum_decl.members) * node->data.enum_decl.member_count);
		for (int i = 0; i < node->data.enum_decl.member_count; ++i) {
			new_node->data.enum_decl.members[i] = malloc(sizeof(EnumMember));
			new_node->data.enum_decl.members[i]->value = node->data.enum_decl.members[i]->value;
			strncpy(new_node->data.enum_decl.members[i]->name, node->data.enum_decl.members[i]->name, sizeof(new_node->data.enum_decl.members[i]->name));
		}
		break;
	case AST_EXTERN_BLOCK:
		strncpy(new_node->data.extern_block.lib_name, node->data.extern_block.lib_name, sizeof(new_node->data.extern_block.lib_name));
		new_node->data.extern_block.count = node->data.extern_block.count;
		new_node->data.extern_block.block = malloc(sizeof(*new_node->data.extern_block.block) * new_node->data.extern_block.count);
		for (int i = 0; i < node->data.extern_block.count; ++i) {
			new_node->data.extern_block.block[i] = copy_ast_node(node->data.extern_block.block[i]);
		}
		break;
	case AST_EXTERN_FUNC_DECL: {
		strncpy(new_node->data.extern_func.name, node->data.extern_func.name, sizeof(new_node->data.extern_func.name));
		new_node->data.extern_func.is_exported = node->data.extern_func.is_exported;
		ASTNode *curr_new_param = new_node->data.extern_func.params;
		ASTNode *curr_param = node->data.extern_func.params;
		while (curr_param) {
			ASTNode *next = curr_param->next;
			curr_new_param = copy_ast_node(curr_param);
			curr_param = next;
			curr_new_param = curr_new_param->next;
		}
	} break;
	case AST_IF_STMT:
		new_node->data.if_stmt.condition = copy_ast_node(node->data.if_stmt.condition);
		new_node->data.if_stmt.then_branch = copy_ast_node(node->data.if_stmt.then_branch);
		new_node->data.if_stmt.else_branch = copy_ast_node(node->data.if_stmt.else_branch);
		break;
	case AST_FOR_LOOP:
		new_node->data.for_loop.init = copy_ast_node(node->data.for_loop.init);
		new_node->data.for_loop.condition = copy_ast_node(node->data.for_loop.condition);
		new_node->data.for_loop.post = copy_ast_node(node->data.for_loop.post);
		new_node->data.for_loop.body = copy_ast_node(node->data.for_loop.body);
		break;
	case AST_WHILE_LOOP:
		new_node->data.while_loop.condition = copy_ast_node(node->data.while_loop.condition);
		new_node->data.while_loop.body = copy_ast_node(node->data.while_loop.body);
		break;
	case AST_DEFER_BLOCK:
		new_node->data.defer.defer_block = copy_ast_node(node->data.defer.defer_block);
	case AST_DEFERRED_SEQUENCE:
		new_node->data.block.statements = malloc(sizeof(*new_node->data.block.statements) * node->data.block.count);
		for (int i = 0; i < node->data.block.count; ++i) {
			new_node->data.block.statements[i] = copy_ast_node(node->data.block.statements[i]);
		}
		new_node->data.block.count = node->data.block.count;
		break;
	// In continue and break we don't really need to copy anything but node type which is already done
	case AST_CONTINUE:
	case AST_BREAK:
	default:
		break;
	}
	if (node->next)
		new_node->next = copy_ast_node(node->next);

	return new_node;
}

ASTNode *new_char_lit_node(char lit, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_CHAR_LIT, loc);
	if (!node) {
		return NULL;
	}

	node->data.char_literal.literal = lit;
	return node;
}

ASTNode *new_string_lit_node(const char *text, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_STRING_LIT, loc);
	if (!node) {
		return NULL;
	}

	strncpy(node->data.string_literal.text, text, sizeof(node->data.string_literal.text));
	return node;
}

ASTNode *new_defer_block_node(ASTNode *inner_block, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_DEFER_BLOCK, loc);
	if (!node)
		return NULL;

	node->data.defer.defer_block = inner_block;
	return node;
}

ASTNode *new_while_loop_node(ASTNode *condition, ASTNode *body, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_WHILE_LOOP, loc);
	if (!node)
		return NULL;

	node->data.while_loop.condition = condition;
	node->data.while_loop.body = body;
	return node;
}

ASTNode *new_for_loop_node(ASTNode *init, ASTNode *condition, ASTNode *post, ASTNode *body, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_FOR_LOOP, loc);
	if (!node)
		return NULL;

	node->data.for_loop.init = init;
	node->data.for_loop.condition = condition;
	node->data.for_loop.post = post;
	node->data.for_loop.body = body;
	return node;
}

ASTNode *new_enum_decl_node(const char *name, Type *base_type, EnumMember **members, int member_count, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_ENUM_DECL, loc);
	if (!node)
		return NULL;
	strncpy(node->data.enum_decl.name, name, sizeof(node->data.enum_decl.name));
	node->data.enum_decl.base_type = base_type;
	node->data.enum_decl.members = members;
	node->data.enum_decl.member_count = member_count;
	return node;
}

ASTNode *new_enum_value_node(const char *namespace, Type *enum_type, const char *member, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_ENUM_VALUE, loc);
	if (!node)
		return NULL;
	if (namespace) {
		strncpy(node->data.enum_value.namespace, namespace, sizeof(node->data.enum_value.namespace));
	} else {
		node->data.enum_value.namespace[0] = '\0';
	}
	node->data.enum_value.enum_type = enum_type;
	strncpy(node->data.enum_value.member, member, sizeof(node->data.enum_value.member));
	return node;
}

ASTNode *new_struct_literal_node(FieldInitializer **inits, int count, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_STRUCT_LITERAL, loc);
	if (!node)
		return NULL;
	node->data.struct_literal.inits = inits;
	node->data.struct_literal.count = count;
	return node;
}

ASTNode *new_member_access_node(ASTNode *base, const char *member_name, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_MEMBER_ACCESS, loc);
	if (!node)
		return NULL;
	node->data.member_access.base = base;
	strncpy(node->data.member_access.member, member_name, sizeof(node->data.member_access.member));
	return node;
}

ASTNode *new_function_call(ASTNode *callee, ASTNode **args, int arg_count, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_FN_CALL, loc);
	if (!node)
		return NULL;
	node->data.func_call.callee = callee;
	node->data.func_call.args = args;
	node->data.func_call.arg_count = arg_count;
	return node;
}

ASTNode *new_assignment_node(ASTNode *lvalue, ASTNode *rvalue, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_ASSIGNMENT, loc);
	if (!node)
		return NULL;
	node->data.assignment.lvalue = lvalue;
	node->data.assignment.rvalue = rvalue;
	return node;
}

ASTNode *new_binary_expr_node(TokenType op, ASTNode *left, ASTNode *right, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_BINARY_EXPR, loc);
	if (!node)
		return NULL;
	node->data.binary_op.op = op;
	node->data.binary_op.left = left;
	node->data.binary_op.right = right;
	return node;
}

ASTNode *new_unary_expr_node(char op, ASTNode *operand, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_UNARY_EXPR, loc);
	if (!node)
		return NULL;
	node->data.unary_op.op = op;
	node->data.unary_op.operand = operand;
	return node;
}

ASTNode *new_cast_node(Type *target_type, ASTNode *expr, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_CAST, loc);
	if (!node)
		return NULL;

	node->data.cast.target_type = target_type;
	node->data.cast.expr = expr;

	return node;
}

ASTNode *new_return_node(ASTNode *expr, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_RETURN, loc);
	if (!node)
		return NULL;
	node->data.ret.return_expr = expr;
	return node;
}

ASTNode *new_field_decl_node(Type *field_type, const char *name, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_FIELD_DECL, loc);
	if (!node)
		return NULL;
	node->data.field_decl.type = field_type;
	strncpy(node->data.field_decl.name, name, sizeof(node->data.field_decl.name));
	return node;
}

ASTNode *new_union_decl_node(const char *name, ASTNode *fields, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_UNION_DECL, loc);
	if (!node)
		return NULL;
	strncpy(node->data.union_decl.name, name, sizeof(node->data.union_decl.name));
	node->data.union_decl.fields = fields;
	return node;
}

ASTNode *new_struct_decl_node(const char *name, ASTNode *fields, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_STRUCT_DECL, loc);
	if (!node)
		return NULL;
	strncpy(node->data.struct_decl.name, name, sizeof(node->data.struct_decl.name));
	node->data.struct_decl.fields = fields;
	return node;
}

ASTNode *new_var_decl_node(Type *type, const char *name, const char *resolved_name, int is_exported, int is_const, ASTNode *initializer, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_VAR_DECL, loc);
	if (!node)
		return NULL;
	strncpy(node->data.var_decl.name, name, sizeof(node->data.var_decl.name));
	strncpy(node->data.var_decl.resolved_name, resolved_name, sizeof(node->data.var_decl.resolved_name));
	node->data.var_decl.type = type;
	node->data.var_decl.init = initializer;
	node->data.var_decl.is_const = is_const;
	node->data.var_decl.is_exported = is_exported;
	return node;
}

ASTNode *new_block_node(ASTNode **stmts, int count, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_BLOCK, loc);
	if (!node)
		return NULL;
	node->data.block.statements = stmts;
	node->data.block.count = count;
	return node;
}

ASTNode *new_param_decl_node(Type *type, const char *name, int is_const, int is_va, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_PARAM_DECL, loc);
	if (!node)
		return NULL;
	node->data.param_decl.type = type;
	strncpy(node->data.param_decl.name, name, sizeof(node->data.param_decl.name));
	node->data.param_decl.is_const = is_const;
	node->data.param_decl.is_va = is_va;
	return node;
}

ASTNode *new_func_decl_node(const char *name, ASTNode *params, ASTNode *body, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_FN_DECL, loc);
	if (!node)
		return NULL;
	strncpy(node->data.func_decl.name, name, sizeof(node->data.func_decl.name));
	node->data.func_decl.params = params;
	node->data.func_decl.body = body;
	return node;
}

ASTNode *new_extern_func_decl_node(const char *name, ASTNode *params, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_EXTERN_FUNC_DECL, loc);
	if (!node)
		return NULL;
	strncpy(node->data.extern_func.name, name, sizeof(node->data.extern_func.name));
	node->data.extern_func.params = params;
	return node;
}

ASTNode *new_extern_block_node(const char *libname, ASTNode **decls, int count, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_EXTERN_BLOCK, loc);
	if (!node)
		return NULL;
	strncpy(node->data.extern_block.lib_name, libname, sizeof(node->data.extern_block.lib_name));
	node->data.extern_block.block = decls;
	node->data.extern_block.count = count;
	return node;
}

ASTNode *new_literal_node_long(long value, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_EXPR_LITERAL, loc);
	if (!node)
		return NULL;
	node->data.literal.long_value = value;
	node->data.literal.is_bool = 0;
	node->data.literal.is_float = 0;
	return node;
}

ASTNode *new_literal_node_float(double value, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_EXPR_LITERAL, loc);
	if (!node)
		return NULL;
	node->data.literal.float_value = value;
	node->data.literal.is_bool = 0;
	node->data.literal.is_float = 1;
	return node;
}

ASTNode *new_literal_node_bool(int value, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_EXPR_LITERAL, loc);
	if (!node)
		return NULL;
	node->data.literal.bool_value = value;
	node->data.literal.is_bool = 1;
	node->data.literal.is_float = 0;
	return node;
}

ASTNode *new_array_access_node(ASTNode *base, ASTNode *index, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_ARRAY_ACCESS, loc);
	if (!node)
		return NULL;
	node->data.array_access.base = base;
	node->data.array_access.index = index;
	return node;
}

ASTNode *new_ident_node(const char *namespace, const char *name, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_EXPR_IDENT, loc);
	if (!node)
		return NULL;
	strncpy(node->data.ident.name, name, sizeof(node->data.ident.name));
	if (namespace) {
		strncpy(node->data.ident.namespace, namespace, sizeof(node->data.ident.namespace));
	} else {
		node->data.ident.namespace[0] = '\0';
	}
	return node;
}

ASTNode *new_array_literal_node(ASTNode **elements, int count, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_ARRAY_LITERAL, loc);
	if (!node)
		return NULL;
	node->data.array_literal.elements = elements;
	node->data.array_literal.count = count;
	return node;
}

ASTNode *new_if_stmt_node(ASTNode *condition, ASTNode *then_branch, ASTNode *else_branch, SourceLocation loc) {
	ASTNode *node = new_ast_node(AST_IF_STMT, loc);
	if (!node)
		return NULL;

	node->data.if_stmt.condition = condition;
	node->data.if_stmt.then_branch = then_branch;
	node->data.if_stmt.else_branch = else_branch;

	return node;
}

///////////////////////////////////////////////////////////////////////////////

CompilerResult parse_type(Parser *parser, Type **out_type) {
	{ // fn ptr parsing
		if (parser->current_token.type == TOK_FN_PTR) {
			parser->current_token = next_token(&parser->scanner); // consume 'fn*'

			SourceLocation loc = parser->current_token.location;

			Type *ret_type = NULL;
			parse_type(parser, &ret_type);
			if (!ret_type) {
				report(loc, "failed to parse type.", 0);
				return RESULT_PARSING_ERROR;
			}

			if (parser->current_token.type != TOK_LPAREN) {
				char msg[128];
				sprintf(msg, "expected '(' in function pointer argument list, got '%s'.", parser->current_token.text);
				report(parser->current_token.location, msg, 0);
				return RESULT_PARSING_ERROR;
			}

			parser->current_token = next_token(&parser->scanner); // consume '('

			struct {
				Type **data;
				int capacity, count;
			} params;

			da_init_result(params, 4);

			while (parser->current_token.type != TOK_RPAREN) {
				Type *param_type = NULL;

				SourceLocation loc = parser->current_token.location;

				parse_type(parser, &param_type);
				if (!param_type) {
					report(loc, "failed to parse type.", 0);
					return RESULT_PARSING_ERROR;
				}

				da_push_result(params, param_type);

				if (parser->current_token.type == TOK_COMMA) {
					parser->current_token = next_token(&parser->scanner); // consume ','
				}
			}

			parser->current_token = next_token(&parser->scanner); // consume ')'

			*out_type = new_function_type(ret_type, params.data, params.count);

			return RESULT_SUCCESS;
		}
	}
	char base_type[64];
	char namespace[64] = "";
	switch (parser->current_token.type) {
	case TOK_I8:
	case TOK_I16:
	case TOK_I32:
	case TOK_I64:
	case TOK_U8:
	case TOK_U16:
	case TOK_U32:
	case TOK_U64:
	case TOK_F32:
	case TOK_F64:
	case TOK_VOID:
	case TOK_BOOL:
		strncpy(base_type, parser->current_token.text, sizeof(base_type));
		parser->current_token = next_token(&parser->scanner);
		*out_type = new_primitive_type(base_type);
		break;
	case TOK_IDENTIFIER:
		strncpy(base_type, parser->current_token.text, sizeof(base_type));
		parser->current_token = next_token(&parser->scanner);
		if (parser->current_token.type == TOK_COLONCOLON) {
			parser->current_token = next_token(&parser->scanner);
			if (parser->current_token.type != TOK_IDENTIFIER) {
				char msg[128];
				sprintf(msg, "expected identifier after '::' in imported type, got '%s'.", parser->current_token.text);
				report(parser->current_token.location, msg, 0);
			}
			strncpy(namespace, base_type, sizeof(namespace));
			strncpy(base_type, parser->current_token.text, sizeof(base_type));
			parser->current_token = next_token(&parser->scanner);
		}
		*out_type = new_named_type(base_type, namespace, TYPE_UNDECIDED);
		if (!*out_type) {
			report(parser->current_token.location, "failed to parse struct type.", 0);
			return RESULT_PARSING_ERROR;
		}
		break;
	default: {
		char msg[128];
		sprintf(msg, "expected type name, got '%s'.", parser->current_token.text);
		report(parser->current_token.location, msg, 0);
		return RESULT_PARSING_ERROR;
	}
	}

	while (parser->current_token.type == TOK_ASTERISK) {
		parser->current_token = next_token(&parser->scanner);
		*out_type = new_pointer_type(*out_type);
		assert(*out_type);
	}

	while (parser->current_token.type == TOK_LBRACKET) {
		parser->current_token = next_token(&parser->scanner); // consume '['

		if (parser->current_token.type != TOK_NUMBER) {
			char msg[128];
			sprintf(msg, "expected array size number, got '%s'.", parser->current_token.text);
			report(parser->current_token.location, msg, 0);
			return RESULT_PARSING_ERROR;
		}

		int size = atoi(parser->current_token.text);
		parser->current_token = next_token(&parser->scanner); // consume number

		if (parser->current_token.type != TOK_RBRACKET) {
			char msg[128];
			sprintf(msg, "expected ']' after array size, got '%s'.", parser->current_token.text);
			report(parser->current_token.location, msg, 0);
			return RESULT_PARSING_ERROR;
		}

		parser->current_token = next_token(&parser->scanner); // consume ']'
		*out_type = new_array_type(*out_type, size);
	}

	return RESULT_SUCCESS;
}

ASTNode *parse_primary(Parser *parser);
ASTNode *parse_unary(Parser *parser);
ASTNode *parse_expr(Parser *parser);

ASTNode *parse_qualified_identifier(Parser *parser) {
	char namespace[64] = "";
	char name[64] = "";
	if (parser->current_token.type != TOK_IDENTIFIER) {
		char msg[128];
		sprintf(msg, "expected identifier, got '%s'.", parser->current_token.text);
		return report(parser->current_token.location, msg, 0);
	}
	SourceLocation loc = parser->current_token.location;
	strncpy(name, parser->current_token.text, sizeof(name));
	parser->current_token = next_token(&parser->scanner);

	if (parser->current_token.type == TOK_COLONCOLON) {
		parser->current_token = next_token(&parser->scanner);
		strncpy(namespace, name, sizeof(namespace));
		if (parser->current_token.type != TOK_IDENTIFIER) {
			char msg[128];
			sprintf(msg, "expected identifier after '::', got '%s'.", parser->current_token.text);
			return report(parser->current_token.location, msg, 0);
		}
		strncpy(name, parser->current_token.text, sizeof(name));
		parser->current_token = next_token(&parser->scanner);
	}
	return new_ident_node(namespace, name, loc);
}

ASTNode *parse_logical_or(Parser *);

TokenType get_underlying_op(TokenType type, SourceLocation *loc) {
	switch (type) {
	case TOK_SELFOR:
		return TOK_BITWISE_OR;
	case TOK_SELFAND:
		return TOK_AMPERSAND;
	case TOK_SELFADD:
		return TOK_PLUS;
	case TOK_SELFSUB:
		return TOK_MINUS;
	case TOK_SELFMUL:
		return TOK_ASTERISK;
	case TOK_SELFDIV:
		return TOK_SLASH;
	default:
		report(*loc, "unrecognized compound assignment operator.", 0);
		return TOK_SELFOR;
	}
}

ASTNode *parse_assignment(Parser *parser) {
	ASTNode *node = parse_logical_or(parser);
	if (!node)
		return NULL;

	if (parser->current_token.type == TOK_ASSIGN || parser->current_token.type == TOK_SELFADD || parser->current_token.type == TOK_SELFSUB || parser->current_token.type == TOK_SELFMUL || parser->current_token.type == TOK_SELFDIV ||
		parser->current_token.type == TOK_SELFAND || parser->current_token.type == TOK_SELFOR) {
		TokenType op = parser->current_token.type;
		SourceLocation loc = parser->current_token.location;
		parser->current_token = next_token(&parser->scanner);
		// Right-associative
		ASTNode *right = parse_assignment(parser);
		if (op == TOK_ASSIGN)
			node = new_assignment_node(node, right, loc);
		else {
			TokenType underlying_op = get_underlying_op(op, &loc);
			ASTNode *compound_expr = new_binary_expr_node(underlying_op, copy_ast_node(node), right, loc);
			node = new_assignment_node(node, compound_expr, loc);
		}
	}
	return node;
}

ASTNode *parse_enum_decl(Parser *parser, int is_exported) {
	parser->current_token = next_token(&parser->scanner); // consume 'enum'
	if (parser->current_token.type != TOK_IDENTIFIER) {
		char msg[128];
		sprintf(msg, "expected enum name after 'enum', got '%s'.", parser->current_token.text);
		return report(parser->current_token.location, msg, 0);
	}

	SourceLocation loc = parser->current_token.location;
	char enum_name[64];
	strncpy(enum_name, parser->current_token.text, sizeof(enum_name));
	int is_error = 0;
	if (lookup_symbol(parser->symbol_table, enum_name, parser->current_scope)) {
		char msg[128];
		sprintf(msg, "enum redeclaration.");
		report(parser->current_token.location, msg, 0);
		is_error = 1;
	}
	parser->current_token = next_token(&parser->scanner); // consume enum name

	Type *base_type = NULL;
	if (parser->current_token.type == TOK_COLON) {
		parser->current_token = next_token(&parser->scanner); // consume ':'
		if (parse_type(parser, &base_type) != RESULT_SUCCESS)
			is_error = 1;
		if (!is_error)
			base_type->kind = TYPE_ENUM;
	} else {
		base_type = new_primitive_type("i32");
		base_type->kind = TYPE_ENUM;
	}

	if (parser->current_token.type != TOK_LCURLY) {
		char msg[128];
		sprintf(msg, "expected '{' in enum declaration, got '%s'.", parser->current_token.text);
		report(parser->current_token.location, msg, 0);
		is_error = 1;
	}

	parser->current_token = next_token(&parser->scanner); // consume '{'
	typedef struct {
		EnumMember **data;
		int count;
		int capacity;
	} enum_member_list;

	enum_member_list members;
	da_init(members, 4);

	int next_value = 0;
	while (parser->current_token.type != TOK_RCURLY) {
		if (parser->current_token.type != TOK_IDENTIFIER) {
			char msg[128];
			sprintf(msg, "expected identifier in enum member declaration, got '%s'.", parser->current_token.text);
			report(parser->current_token.location, msg, 0);
			is_error = 1;
		}
		EnumMember *member = malloc(sizeof(EnumMember));
		if (!member) // @TODO: leaks
			return NULL;
		strncpy(member->name, parser->current_token.text, sizeof(member->name));
		for (int i = 0; i < members.count; ++i) {
			if (strcmp(member->name, members.data[i]->name) == 0) {
				report(parser->current_token.location, "enum member redeclaration.", 0);
				is_error = 1;
			}
		}
		parser->current_token = next_token(&parser->scanner); // consume identifier

		if (parser->current_token.type == TOK_ASSIGN) {
			parser->current_token = next_token(&parser->scanner); // consume '='
			if (parser->current_token.type == TOK_NUMBER) {
				member->value = atoi(parser->current_token.text);
				next_value = member->value + 1;
				parser->current_token = next_token(&parser->scanner); // consume number
			} else if (parser->current_token.type == TOK_IDENTIFIER) {
				int found = 0;
				for (int i = 0; i < members.count; ++i) {
					if (strcmp(members.data[i]->name, parser->current_token.text) == 0) {
						member->value = members.data[i]->value;
						next_value = member->value + 1;
						found = 1;
						parser->current_token = next_token(&parser->scanner); // consume identifier
						break;
					}
				}
				if (!found) {
					char msg[128];
					sprintf(msg, "enum member '%s' not found for initializer.", parser->current_token.text);
					report(parser->current_token.location, msg, 0);
					is_error = 1;
				}
			} else {
				char msg[128];
				sprintf(msg, "expected number or identifier after '=' in enum member declaration, got '%s'.", parser->current_token.text);
				report(parser->current_token.location, msg, 0);
				is_error = 1;
			}
		} else {
			member->value = next_value++;
		}

		da_push(members, member);

		if (parser->current_token.type == TOK_COMMA) {
			parser->current_token = next_token(&parser->scanner); // consume ','
		} else {
			break;
		}
	}

	if (parser->current_token.type != TOK_RCURLY) {
		char msg[128];
		sprintf(msg, "expected '}' at the end of enum declaration, got '%s'.", parser->current_token.text);
		report(parser->current_token.location, msg, 0);
		is_error = 1;
	}
	parser->current_token = next_token(&parser->scanner); // consume '}'

	if (!is_error) {
		ASTNode *decl_node = new_enum_decl_node(enum_name, base_type, members.data, members.count, loc);
		add_symbol(&parser->symbol_table, decl_node, enum_name, enum_name, 1, SYMB_ENUM, base_type, parser->current_scope);
		if (is_exported) {
			add_symbol(&parser->exported_table, decl_node, enum_name, enum_name, 1, SYMB_ENUM, base_type, parser->current_scope);
		}
		return decl_node;
	}
	return NULL;
}

ASTNode *parse_struct_literal(Parser *parser) {
	typedef struct {
		FieldInitializer **data;
		int capacity;
		int count;
	} field_init_list;

	SourceLocation loc = parser->current_token.location;
	parser->current_token = next_token(&parser->scanner); // consume '{'
	field_init_list inits;
	da_init(inits, 4);

	while (parser->current_token.type != TOK_RCURLY) {
		FieldInitializer *init = NULL;

		if (parser->current_token.type == TOK_DOT) {
			parser->current_token = next_token(&parser->scanner); // consume '.'

			if (parser->current_token.type != TOK_IDENTIFIER) {
				char msg[128];
				sprintf(msg, "expected named field after '.' in named struct initialization, got '%s'.", parser->current_token.text);
				return report(parser->current_token.location, msg, 0);
			}

			char field_name[64];
			strncpy(field_name, parser->current_token.text, sizeof(field_name));

			parser->current_token = next_token(&parser->scanner); // consume '.'
			if (parser->current_token.type != TOK_ASSIGN) {
				char msg[128];
				sprintf(msg, "expected '=' after field name in named struct initialization, got '%s'.", parser->current_token.text);
				return report(parser->current_token.location, msg, 0);
			}

			parser->current_token = next_token(&parser->scanner); // consume '='

			ASTNode *expr = parse_assignment(parser);
			init = new_field_initializer(field_name, 1, expr);
		} else {
			ASTNode *expr = parse_assignment(parser);
			init = new_field_initializer("", 0, expr);
		}

		da_push(inits, init);

		if (parser->current_token.type == TOK_COMMA) {
			parser->current_token = next_token(&parser->scanner); // consume ','

			if (parser->current_token.type == TOK_RCURLY)
				break; // allowing trailing commas
		} else {
			break;
		}
	}

	if (parser->current_token.type != TOK_RCURLY) {
		char msg[128];
		sprintf(msg, "expected '}' at the end of struct initialization, got '%s'.", parser->current_token.text);
		return report(parser->current_token.location, msg, 0);
	}
	parser->current_token = next_token(&parser->scanner); // consume '}'

	return new_struct_literal_node(inits.data, inits.count, loc);
}

ASTNode *parse_postfix(Parser *parser) {
	ASTNode *node = parse_primary(parser);
	while (parser->current_token.type == TOK_LPAREN || parser->current_token.type == TOK_LBRACKET || parser->current_token.type == TOK_DOT) {

		if (parser->current_token.type == TOK_LPAREN) {
			SourceLocation loc = parser->current_token.location;

			parser->current_token = next_token(&parser->scanner);

			NodeList args;
			da_init(args, 4);
			if (parser->current_token.type != TOK_RPAREN) {
				while (1) {
					ASTNode *arg = parse_assignment(parser);
					da_push(args, arg);

					if (parser->current_token.type == TOK_COMMA) {
						parser->current_token = next_token(&parser->scanner);
					} else
						break;
				}
			}

			if (parser->current_token.type != TOK_RPAREN) {
				char msg[128];
				sprintf(msg, "expected ')' in function call, got '%s'.", parser->current_token.text);
				return report(parser->current_token.location, msg, 0);
			}

			parser->current_token = next_token(&parser->scanner);
			node = new_function_call(node, args.data, args.count, loc);

		} else if (parser->current_token.type == TOK_LBRACKET) {
			SourceLocation loc = parser->current_token.location;
			parser->current_token = next_token(&parser->scanner);

			ASTNode *index_expr = parse_expr(parser);
			if (!index_expr)
				return NULL;

			if (parser->current_token.type != TOK_RBRACKET) {
				char msg[128];
				sprintf(msg, "expected ']' after array size, got '%s'.", parser->current_token.text);
				return report(parser->current_token.location, msg, 0);
			}
			parser->current_token = next_token(&parser->scanner);

			node = new_array_access_node(node, index_expr, loc);

		} else if (parser->current_token.type == TOK_DOT) {
			SourceLocation loc = parser->current_token.location;
			parser->current_token = next_token(&parser->scanner);

			if (parser->current_token.type != TOK_IDENTIFIER) {
				char msg[128];
				sprintf(msg, "expected identifier after '.', got '%s'.", parser->current_token.text);
				return report(parser->current_token.location, msg, 0);
			}

			char member_name[64];
			strncpy(member_name, parser->current_token.text, sizeof(member_name));

			parser->current_token = next_token(&parser->scanner);

			node = new_member_access_node(node, member_name, loc);
		}
	}
	return node;
}

// <arrayLiteral>
// ::= '[' (<expression>)* (',')* ']'
ASTNode *parse_array_literal(Parser *parser) {
	SourceLocation loc = parser->current_token.location;
	parser->current_token = next_token(&parser->scanner); // consume '['

	NodeList elements;
	da_init(elements, 4);

	if (parser->current_token.type != TOK_RBRACKET) {
		while (1) {
			ASTNode *expr = parse_expr(parser);
			if (!expr)
				return NULL;

			da_push(elements, expr);

			if (parser->current_token.type == TOK_COMMA) {
				parser->current_token = next_token(&parser->scanner); // consume ','
				if (parser->current_token.type == TOK_RBRACKET)
					break;
			} else
				break;
		}
	}

	if (parser->current_token.type != TOK_RBRACKET) {
		char msg[128];
		sprintf(msg, "expected ']' after array size, got '%s'.", parser->current_token.text);
		return report(parser->current_token.location, msg, 0);
	}

	parser->current_token = next_token(&parser->scanner); // consume ']'
	return new_array_literal_node(elements.data, elements.count, loc);
}

ASTNode *parse_expr(Parser *parser) { return parse_logical_or(parser); }

ASTNode *parse_return_stmt(Parser *parser) {
	SourceLocation loc = parser->current_token.location;
	parser->current_token = next_token(&parser->scanner); // consume 'return'
	ASTNode *expr = NULL;

	if (parser->current_token.type != TOK_SEMICOLON)
		expr = parse_expr(parser);

	if (parser->current_token.type != TOK_SEMICOLON) {
		report(parser->current_token.location, "expected ';' after return statement.", 0);
	}

	parser->current_token = next_token(&parser->scanner); // consume ';'

	return new_return_node(expr, loc);
}

int is_type_spec(Parser *parser) {
	switch (parser->current_token.type) {
	case TOK_I8:
	case TOK_I16:
	case TOK_I32:
	case TOK_I64:
	case TOK_U8:
	case TOK_U16:
	case TOK_U32:
	case TOK_U64:
	case TOK_F32:
	case TOK_F64:
	case TOK_VOID:
	case TOK_BOOL:
	case TOK_IDENTIFIER:
		return 1;
	default:
		return 0;
	}
}

// numbers, bools, identifiers, grouping expressions
// <primaryExpr>
// ::= <number>
//  | <bool>
//  | <identifier>
//  | <groupingExpr>
//  | <arrayLiteral>
//  | <structLiteral>
//  | <stringLiteral>
ASTNode *parse_primary(Parser *parser) {
	// @TODO: add array and struct literals
	if (parser->current_token.type == TOK_NUMBER) {
		if (strchr(parser->current_token.text, '.') != NULL) {
			double value = atof(parser->current_token.text);
			SourceLocation loc = parser->current_token.location;
			parser->current_token = next_token(&parser->scanner);
			return new_literal_node_float(value, loc);
		} else {
			int base = 10;
			int offset = 0;
			SourceLocation loc = parser->current_token.location;
			if (parser->current_token.text[0] == '0' && (parser->current_token.text[1] == 'b' || parser->current_token.text[1] == 'B')) {
				base = 2;
				offset = 2;
			} else if (parser->current_token.text[0] == '0' && (parser->current_token.text[1] == 'x' || parser->current_token.text[1] == 'X')) {
				base = 16;
			}
			long value = strtol(parser->current_token.text + offset, NULL, base);
			parser->current_token = next_token(&parser->scanner);
			return new_literal_node_long(value, loc);
		}
	} else if (parser->current_token.type == TOK_TRUE) {
		SourceLocation loc = parser->current_token.location;
		parser->current_token = next_token(&parser->scanner);
		return new_literal_node_bool(1, loc);
	} else if (parser->current_token.type == TOK_FALSE) {
		SourceLocation loc = parser->current_token.location;
		parser->current_token = next_token(&parser->scanner);
		return new_literal_node_bool(0, loc);
	} else if (parser->current_token.type == TOK_IDENTIFIER) {
		// @TODO: this is deferred until sema.
		// In the semantic analysis phase, when resolving a qualified identifier, look up the namespace string in your symbol table.
		// - Case A: Module Namespace.
		// If the namespace matches one of the imported modules (or the current module’s name if unqualified), then resolve the name as a member of that module.
		// - Case B: Enum Type.
		// If the namespace matches an enum type declared in the current module (or an imported module), then resolve the identifier as an enum value.
		// For example, if SomeEnum is an enum type in the current scope, then SomeEnum::Value should be resolved by:
		//      - Looking up the enum declaration for SomeEnum.
		//      - Searching the enumerators for one with the name Value.
		//      - If found, retrieving the corresponding integer value.
		//

		return parse_qualified_identifier(parser);
		/* char ident_name[64]; */
		/* strncpy(ident_name, parser->current_token.text, sizeof(ident_name)); */
		/* parser->current_token = next_token(&parser->scanner); // consume identifier */
		/* if (parser->current_token.type == TOK_COLONCOLON) { */
		/* 	parser->current_token = next_token(&parser->scanner); // consume '::' */
		/* 	if (parser->current_token.type != TOK_IDENTIFIER) { */
		/* 		char msg[128]; */
		/* 		sprintf(msg, "expected identifier after '::', got '%s'.", parser->current_token.text); */
		/* 		return report(parser->current_token.location, msg, 0); */
		/* 	} */
		/* 	char member_name[64]; */
		/* 	strncpy(member_name, parser->current_token.text, sizeof(member_name)); */
		/* 	parser->current_token = next_token(&parser->scanner); // consume identifier */
		/* 	return new_enum_value_node(ident_name, member_name); */
		/* } */
		/* return new_ident_node(ident_name); */
	} else if (parser->current_token.type == TOK_LPAREN) {
		parser->current_token = next_token(&parser->scanner);
		if (is_type_spec(parser)) {
			SourceLocation loc = parser->current_token.location;
			Type *target_type = NULL;
			int is_error = 0;
			if (parse_type(parser, &target_type) != RESULT_SUCCESS) {
				is_error = 1;
			}
			if (parser->current_token.type != TOK_RPAREN) {
				char msg[128] = "";
				sprintf(msg, "expected ')' after cast type, got %s", parser->current_token.text);
				report(parser->current_token.location, msg, 0);
				is_error = 1;
			}

			parser->current_token = next_token(&parser->scanner);
			ASTNode *expr = parse_expr(parser);
			if (!expr) {
				is_error = 1;
			}

			if (is_error)
				return NULL;

			return new_cast_node(target_type, expr, loc);
		} else {
			ASTNode *expr = parse_expr(parser);
			if (!expr)
				return NULL;
			if (parser->current_token.type != TOK_RPAREN)
				return report(parser->current_token.location, "expected ')'.", 0);
			parser->current_token = next_token(&parser->scanner);
			return expr;
		}
	} else if (parser->current_token.type == TOK_LBRACKET) {
		return parse_array_literal(parser);
	} else if (parser->current_token.type == TOK_LCURLY) {
		return parse_struct_literal(parser);
	} else if (parser->current_token.type == TOK_STRINGLIT) {
		SourceLocation loc = parser->current_token.location;
		ASTNode *string_lit_node = new_string_lit_node(parser->current_token.text, loc);
		parser->current_token = next_token(&parser->scanner);
		return string_lit_node;
	} else if (parser->current_token.type == TOK_CHARLIT) {
		SourceLocation loc = parser->current_token.location;
		ASTNode *char_lit_node = new_char_lit_node(parser->current_token.text[0], loc);
		parser->current_token = next_token(&parser->scanner);
		return char_lit_node;
	} else {
		char expr[128];
		sprintf(expr, "unexpected token in expression: %s", parser->current_token.text);
		return report(parser->current_token.location, expr, 0);
	}
}

ASTNode *parse_multiplicative(Parser *parser) {
	ASTNode *node = parse_unary(parser);
	while (parser->current_token.type == TOK_ASTERISK || parser->current_token.type == TOK_SLASH || parser->current_token.type == TOK_MODULO) {
		SourceLocation loc = parser->current_token.location;
		TokenType op = parser->current_token.type;
		parser->current_token = next_token(&parser->scanner);
		ASTNode *right = parse_unary(parser);
		node = new_binary_expr_node(op, node, right, loc);
	}
	return node;
}

ASTNode *parse_additive(Parser *parser) {
	ASTNode *node = parse_multiplicative(parser);
	while (parser->current_token.type == TOK_PLUS || parser->current_token.type == TOK_MINUS) {
		SourceLocation loc = parser->current_token.location;
		TokenType op = parser->current_token.type;
		parser->current_token = next_token(&parser->scanner);
		ASTNode *right = parse_multiplicative(parser);
		node = new_binary_expr_node(op, node, right, loc);
	}
	return node;
}

ASTNode *parse_bitwise_shift(Parser *parser) {
	ASTNode *node = parse_additive(parser);
	while (parser->current_token.type == TOK_BITWISE_LSHIFT || parser->current_token.type == TOK_BITWISE_RSHIFT) {
		SourceLocation loc = parser->current_token.location;
		TokenType op = parser->current_token.type;
		parser->current_token = next_token(&parser->scanner);
		ASTNode *right = parse_additive(parser);
		node = new_binary_expr_node(op, node, right, loc);
	}
	return node;
}

ASTNode *parse_relational(Parser *parser) {
	ASTNode *node = parse_bitwise_shift(parser);
	while (parser->current_token.type == TOK_LESSTHAN || parser->current_token.type == TOK_LTOE || parser->current_token.type == TOK_GREATERTHAN || parser->current_token.type == TOK_GTOE) {
		SourceLocation loc = parser->current_token.location;
		TokenType op = parser->current_token.type;
		parser->current_token = next_token(&parser->scanner);
		ASTNode *right = parse_bitwise_shift(parser);
		node = new_binary_expr_node(op, node, right, loc);
	}
	return node;
}

ASTNode *parse_equality(Parser *parser) {
	ASTNode *node = parse_relational(parser);
	while (parser->current_token.type == TOK_EQUAL || parser->current_token.type == TOK_NOTEQUAL) {
		SourceLocation loc = parser->current_token.location;
		TokenType op = parser->current_token.type;
		parser->current_token = next_token(&parser->scanner);
		ASTNode *right = parse_bitwise_shift(parser);
		node = new_binary_expr_node(op, node, right, loc);
	}
	return node;
}

ASTNode *parse_bitwise_and(Parser *parser) {
	ASTNode *node = parse_equality(parser);
	while (parser->current_token.type == TOK_AMPERSAND) {
		SourceLocation loc = parser->current_token.location;
		TokenType op = parser->current_token.type;
		parser->current_token = next_token(&parser->scanner);
		ASTNode *right = parse_additive(parser);
		node = new_binary_expr_node(op, node, right, loc);
	}
	return node;
}

ASTNode *parse_bitwise_xor(Parser *parser) {
	ASTNode *node = parse_bitwise_and(parser);
	while (parser->current_token.type == TOK_BITWISE_XOR) {
		SourceLocation loc = parser->current_token.location;
		TokenType op = parser->current_token.type;
		parser->current_token = next_token(&parser->scanner);
		ASTNode *right = parse_bitwise_and(parser);
		node = new_binary_expr_node(op, node, right, loc);
	}
	return node;
}

ASTNode *parse_bitwise_or(Parser *parser) {
	ASTNode *node = parse_bitwise_xor(parser);
	while (parser->current_token.type == TOK_BITWISE_OR) {
		SourceLocation loc = parser->current_token.location;
		TokenType op = parser->current_token.type;
		parser->current_token = next_token(&parser->scanner);
		ASTNode *right = parse_bitwise_xor(parser);
		node = new_binary_expr_node(op, node, right, loc);
	}
	return node;
}

ASTNode *parse_logical_and(Parser *parser) {
	ASTNode *node = parse_bitwise_or(parser);
	while (parser->current_token.type == TOK_AND) {
		SourceLocation loc = parser->current_token.location;
		TokenType op = parser->current_token.type;
		parser->current_token = next_token(&parser->scanner);
		ASTNode *right = parse_bitwise_or(parser);
		node = new_binary_expr_node(op, node, right, loc);
	}
	return node;
}

ASTNode *parse_logical_or(Parser *parser) {
	ASTNode *node = parse_logical_and(parser);
	while (parser->current_token.type == TOK_OR) {
		SourceLocation loc = parser->current_token.location;
		TokenType op = parser->current_token.type;
		parser->current_token = next_token(&parser->scanner);
		ASTNode *right = parse_logical_and(parser);
		node = new_binary_expr_node(op, node, right, loc);
	}
	return node;
}

// <unaryExpr>
// ::= ('*' | '!' | '&') <expr>
ASTNode *parse_unary(Parser *parser) {
	TokenType type = parser->current_token.type;
	if (type == TOK_EXCLAMATION || type == TOK_AMPERSAND || type == TOK_ASTERISK) {
		SourceLocation loc = parser->current_token.location;
		char op = parser->current_token.text[0];
		parser->current_token = next_token(&parser->scanner);
		ASTNode *operand = parse_unary(parser);
		return new_unary_expr_node(op, operand, loc);
	}
	return parse_postfix(parser);
}

// <varDecl>
// ::= ('const')? <type> <identifier> ('=' <expression>)? ';'
ASTNode *parse_var_decl(Parser *parser, const char *prefix_name, int is_exported) {
	int is_const = 0;
	if (parser->current_token.type == TOK_CONST) {
		is_const = 1;
		parser->current_token = next_token(&parser->scanner); // consume 'const'
	}

	Type *var_type = NULL;
	if (parse_type(parser, &var_type) != RESULT_SUCCESS)
		return NULL;

	if (parser->current_token.type != TOK_IDENTIFIER) {
		return report(parser->current_token.location, "expected identifier in variable declaration.", 0);
	}

	char var_name[64];
	strncpy(var_name, parser->current_token.text, sizeof(var_name));

	SourceLocation decl_location = parser->current_token.location;

	int is_error = 0;

	char resolved_name[128] = "";
	if (prefix_name[0] != '\0') {
		sprintf(resolved_name, "__%s_%s", prefix_name, var_name);
	} else {
		strncpy(resolved_name, var_name, sizeof(resolved_name));
	}

	if (lookup_symbol(parser->symbol_table, resolved_name, parser->current_scope)) {
		char msg[128] = "";
		sprintf(msg, "variable %s already declared in this scope.", var_name);
		report(decl_location, msg, 0);
		is_error = 1;
	}

	parser->current_token = next_token(&parser->scanner); // consume identifier

	ASTNode *init_expr = NULL;
	if (parser->current_token.type == TOK_ASSIGN) {
		parser->current_token = next_token(&parser->scanner); // consume '='
		init_expr = parse_expr(parser);
	}

	if (parser->current_token.type != TOK_SEMICOLON)
		return report(parser->current_token.location, "expected ';' after variable declaration.", 0);

	parser->current_token = next_token(&parser->scanner); // consume ';'

	if (!is_error) {
		char resolved_name[128] = "";
		if (prefix_name[0] != '\0') {
			sprintf(resolved_name, "__%s_%s", prefix_name, var_name);
		} else {
			strncpy(resolved_name, var_name, sizeof(resolved_name));
		}
		ASTNode *decl_node = new_var_decl_node(var_type, var_name, resolved_name, is_exported, is_const, init_expr, decl_location);
		add_symbol(&parser->symbol_table, decl_node, var_name, resolved_name, is_const, SYMB_VAR, var_type, parser->current_scope);
		if (is_exported) {
			add_symbol(&parser->exported_table, decl_node, var_name, resolved_name, is_const, SYMB_VAR, var_type, parser->current_scope);
		}
		return decl_node;
	} else {
		return NULL;
	}
}

typedef struct {
	ASTNode **data;
	int capacity, count;
} DeferStack;

ASTNode *parse_if_stmt(Parser *parser, const char *prefix_name, DeferStack *dstack);
ASTNode *parse_for_loop(Parser *parse, const char *prefix_name, DeferStack *dstackr);
ASTNode *parse_while_loop(Parser *parse, const char *prefix_name, DeferStack *dstackr);
ASTNode *parse_defer_block(Parser *parse, const char *prefix_name, DeferStack *dstackr);

ASTNode *parse_stmt(Parser *parser, const char *prefix_name, DeferStack *dstack) {
	if (parser->current_token.type == TOK_BREAK) {
		SourceLocation loc = parser->current_token.location;
		parser->current_token = next_token(&parser->scanner); // consume 'break'
		if (parser->current_token.type != TOK_SEMICOLON) {
			return report(parser->current_token.location, "expected ';' after 'break'.", 0);
		}
		parser->current_token = next_token(&parser->scanner);
		return new_ast_node(AST_BREAK, loc);
	}
	if (parser->current_token.type == TOK_CONTINUE) {
		SourceLocation loc = parser->current_token.location;
		parser->current_token = next_token(&parser->scanner); // consume 'continue'
		if (parser->current_token.type != TOK_SEMICOLON) {
			return report(parser->current_token.location, "expected ';' after 'continue'.", 0);
		}
		parser->current_token = next_token(&parser->scanner);
		return new_ast_node(AST_CONTINUE, loc);
	}
	if (parser->current_token.type == TOK_DEFER) {
		return parse_defer_block(parser, prefix_name, dstack);
	}
	if (parser->current_token.type == TOK_IF) {
		return parse_if_stmt(parser, prefix_name, dstack);
	}
	if (parser->current_token.type == TOK_FOR) {
		return parse_for_loop(parser, prefix_name, dstack);
	}
	if (parser->current_token.type == TOK_WHILE) {
		return parse_while_loop(parser, prefix_name, dstack);
	}
	if (parser->current_token.type == TOK_RETURN) {
		return parse_return_stmt(parser);
	}

	if (parser->current_token.type == TOK_I8 || parser->current_token.type == TOK_I16 || parser->current_token.type == TOK_I32 || parser->current_token.type == TOK_I64 || parser->current_token.type == TOK_U8 ||
		parser->current_token.type == TOK_U16 || parser->current_token.type == TOK_U32 || parser->current_token.type == TOK_U64 || parser->current_token.type == TOK_F32 || parser->current_token.type == TOK_F64 ||
		parser->current_token.type == TOK_BOOL || parser->current_token.type == TOK_VOID || parser->current_token.type == TOK_IDENTIFIER || parser->current_token.type == TOK_CONST) {
		if (parser->current_token.type == TOK_CONST) {
			return parse_var_decl(parser, prefix_name, 0);
		}
		// peek ahead
		int save = parser->scanner.id;
		Token temp = parser->current_token;
		Type *type = NULL;
		parse_type(parser, &type);
		if (parser->current_token.type == TOK_IDENTIFIER) {
			// most likely var decl, restore state and reparse
			if (type) {
				type_deinit(type);
				free(type);
			}
			parser->scanner.id = save;
			parser->current_token = temp;
			return parse_var_decl(parser, prefix_name, 0);
		}
		// restore and parse expression
		if (type) {
			type_deinit(type);
			free(type);
		}
		parser->scanner.id = save;
		parser->current_token = temp;
	}

	ASTNode *expr = parse_assignment(parser);
	if (parser->current_token.type != TOK_SEMICOLON) {
		return report(parser->current_token.location, "expected ';' after expression statement.", 0);
	}
	parser->current_token = next_token(&parser->scanner);
	return expr;
}

// <fieldDecl>
// ::= <type> <identifier> ;
ASTNode *parse_field_declaration(Parser *parser) {
	Type *type = NULL;
	if (parse_type(parser, &type) != RESULT_SUCCESS) {
		return NULL;
	}

	if (parser->current_token.type != TOK_IDENTIFIER) {
		return report(parser->current_token.location, "expected identifier in struct field declaration.", 0);
	}

	SourceLocation loc = parser->current_token.location;
	char field_name[64];
	strncpy(field_name, parser->current_token.text, sizeof(field_name));

	parser->current_token = next_token(&parser->scanner); // consume field name

	if (parser->current_token.type != TOK_SEMICOLON) {
		return report(parser->current_token.location, "expected ';' after struct field declaration.", 0);
	}

	parser->current_token = next_token(&parser->scanner); // consume ';'
	return new_field_decl_node(type, field_name, loc);
}

ASTNode *parse_union_decl(Parser *parser, int is_exported) {
	parser->current_token = next_token(&parser->scanner); // consume 'struct'
	if (parser->current_token.type != TOK_IDENTIFIER) {
		return report(parser->current_token.location, "expected identifier after 'union'.", 0);
	}

	SourceLocation loc = parser->current_token.location;
	char union_name[64];
	strncpy(union_name, parser->current_token.text, sizeof(union_name));

	int is_error = 0;
	if (lookup_symbol(parser->symbol_table, union_name, parser->current_scope)) {
		report(parser->current_token.location, "union redeclaration.", 0);
		is_error = 1;
	}

	parser->current_token = next_token(&parser->scanner); // consume struct name

	if (parser->current_token.type != TOK_LCURLY) {
		report(parser->current_token.location, "expected '{' in union declaration.", 0);
		is_error = 1;
	}

	parser->current_token = next_token(&parser->scanner); // consume '{'

	ASTNode *field_list = NULL, *last_field = NULL;
	while (parser->current_token.type != TOK_RCURLY && parser->current_token.type != TOK_EOF) {
		ASTNode *field = parse_field_declaration(parser);
		for (ASTNode *field_it = field_list; field_it != NULL; field_it = field_it->next) {
			if (strcmp(field_it->data.field_decl.name, field->data.field_decl.name) == 0) {
				report(field->location, "field redeclaration.", 0);
				is_error = 1;
			}
		}

		if (!field_list) {
			field_list = last_field = field;
		} else {
			last_field->next = field;
			last_field = field;
		}
	}

	if (parser->current_token.type != TOK_RCURLY) {
		report(parser->current_token.location, "expected '}' at the end of struct declaration.", 0);
		is_error = 1;
	}
	parser->current_token = next_token(&parser->scanner); // consume '{'

	if (!is_error) {
		Type *union_type = new_named_type(union_name, "", TYPE_STRUCT);
		ASTNode *node = new_union_decl_node(union_name, field_list, loc);
		add_symbol(&parser->symbol_table, node, union_name, union_name, 1, SYMB_UNION, union_type, parser->current_scope);
		if (is_exported) {
			add_symbol(&parser->exported_table, node, union_name, union_name, 1, SYMB_UNION, union_type, parser->current_scope);
		}
		type_deinit(union_type);
		free(union_type);
		return node;
	}

	return NULL;
}
// <structDecl>
// ::= 'struct' <identifier> '{' (<fieldDecl>)* '}'
ASTNode *parse_struct_decl(Parser *parser, int is_exported) {
	parser->current_token = next_token(&parser->scanner); // consume 'struct'
	// @TODO: generic structs
	if (parser->current_token.type != TOK_IDENTIFIER) {
		return report(parser->current_token.location, "expected identifier after 'struct'.", 0);
	}

	SourceLocation loc = parser->current_token.location;
	char struct_name[64];
	strncpy(struct_name, parser->current_token.text, sizeof(struct_name));

	int is_error = 0;
	if (lookup_symbol(parser->symbol_table, struct_name, parser->current_scope)) {
		report(parser->current_token.location, "struct redeclaration.", 0);
		is_error = 1;
	}

	parser->current_token = next_token(&parser->scanner); // consume struct name

	if (parser->current_token.type != TOK_LCURLY) {
		report(parser->current_token.location, "expected '{' in struct declaration.", 0);
		is_error = 1;
	}

	parser->current_token = next_token(&parser->scanner); // consume '{'

	ASTNode *field_list = NULL, *last_field = NULL;
	while (parser->current_token.type != TOK_RCURLY && parser->current_token.type != TOK_EOF) {
		ASTNode *field = parse_field_declaration(parser);
		for (ASTNode *field_it = field_list; field_it != NULL; field_it = field_it->next) {
			if (strcmp(field_it->data.field_decl.name, field->data.field_decl.name) == 0) {
				report(field->location, "field redeclaration.", 0);
				is_error = 1;
			}
		}

		if (!field_list) {
			field_list = last_field = field;
		} else {
			last_field->next = field;
			last_field = field;
		}
	}

	if (parser->current_token.type != TOK_RCURLY) {
		report(parser->current_token.location, "expected '}' at the end of struct declaration.", 0);
		is_error = 1;
	}
	parser->current_token = next_token(&parser->scanner); // consume '{'

	if (!is_error) {
		Type *struct_type = new_named_type(struct_name, "", TYPE_STRUCT);
		ASTNode *node = new_struct_decl_node(struct_name, field_list, loc);
		add_symbol(&parser->symbol_table, node, struct_name, struct_name, 1, SYMB_STRUCT, struct_type, parser->current_scope);
		if (is_exported) {
			add_symbol(&parser->exported_table, node, struct_name, struct_name, 1, SYMB_STRUCT, struct_type, parser->current_scope);
		}
		type_deinit(struct_type);
		free(struct_type);
		return node;
	}

	return NULL;
}

// <parameterDecl>
// ::= (<type> <identifier>)*
ASTNode *parse_parameter_declaration(Parser *parser) {
	if (parser->current_token.type == TOK_DOTDOTDOT) {
		SourceLocation loc = parser->current_token.location;
		parser->current_token = next_token(&parser->scanner); // consume name
		return new_param_decl_node(NULL, "", 0, 1, loc);
	}
	int is_const = 0;
	if (parser->current_token.type == TOK_CONST) {
		is_const = 1;
		parser->current_token = next_token(&parser->scanner); // consume name
	}
	Type *type = NULL;
	if (parse_type(parser, &type) != RESULT_SUCCESS)
		return NULL;

	if (parser->current_token.type != TOK_IDENTIFIER) {
		char msg[128];
		sprintf(msg, "expected identifier in parameter declaration, got %s.", parser->current_token.text);
		return report(parser->current_token.location, msg, 0);
	}
	char param_name[64];
	strncpy(param_name, parser->current_token.text, sizeof(param_name));
	SourceLocation loc = parser->current_token.location;
	parser->current_token = next_token(&parser->scanner); // consume name
	return new_param_decl_node(type, param_name, is_const, 0, loc);
}

ASTNode *parse_parameter_list(Parser *parser) {
	ASTNode *param_list = NULL, *last_param = NULL;

	// empty param list
	if (parser->current_token.type == TOK_RPAREN)
		return NULL;

	ASTNode *param = parse_parameter_declaration(parser);
	param_list = last_param = param;

	int is_error = 0;
	while (parser->current_token.type == TOK_COMMA) {
		parser->current_token = next_token(&parser->scanner); // consume comma
		param = parse_parameter_declaration(parser);
		for (ASTNode *param_it = param_list; param_it != NULL; param_it = param_it->next) {
			if (strcmp(param->data.param_decl.name, param_it->data.param_decl.name) == 0) {
				char msg[128];
				sprintf(msg, "parameter redeclaration: %s.", param->data.param_decl.name);
				report(parser->current_token.location, msg, 0);
				is_error = 1;
			}
		}
		last_param->next = param;
		last_param = param;
	}
	if (!is_error)
		return param_list;
	return NULL;
}

DeferStack copy_defer_stack(DeferStack *stack) {
	DeferStack copy;
	da_init_unsafe(copy, stack->capacity);
	for (int i = 0; i < stack->count; ++i) {
		da_push_unsafe(copy, stack->data[i]);
	}
	return copy;
}

void push_stmt(ASTNode *block, ASTNode *stmt, CompilerResult *success) {
	if (block->type != AST_BLOCK && block->type != AST_DEFERRED_SEQUENCE) {
		*success = RESULT_PASSED_NULL_PTR;
		return;
	}

	int new_count = block->data.block.count + 1;
	block->data.block.statements = realloc(block->data.block.statements, new_count * sizeof(ASTNode *));
	if (!block->data.block.statements) {
		*success = RESULT_MEMORY_ERROR;
		return;
	}
	block->data.block.statements[block->data.block.count] = stmt;
	block->data.block.count = new_count;
	*success = RESULT_SUCCESS;
}

void unroll_defers(ASTNode *node, DeferStack *stack) {
	if (node->type != AST_BLOCK)
		return;

	struct {
		ASTNode **data;
		int capacity, count;
	} new_statements;

	da_init_unsafe(new_statements, node->data.block.count);

	for (int i = 0; i < node->data.block.count; ++i) {
		ASTNode *stmt = node->data.block.statements[i];

		if (stmt->type == AST_RETURN) {
			ASTNode *seq = new_ast_node(AST_DEFERRED_SEQUENCE, stmt->location);
			seq->data.block.count = 0;
			for (int j = stack->count - 1; j >= 0; --j) {
				CompilerResult res;
				push_stmt(seq, stack->data[j], &res);
				assert(res == RESULT_SUCCESS);
			}

			if (seq->data.block.count > 0) {
				da_push_unsafe(new_statements, seq);
			} else {
				free(seq);
			}

			da_push_unsafe(new_statements, stmt);
		} else if (stmt->type == AST_BLOCK) {
			DeferStack nested = copy_defer_stack(stack);
			unroll_defers(stmt, &nested);
			da_deinit(nested);
			da_push_unsafe(new_statements, stmt);
		} else {
			da_push_unsafe(new_statements, stmt);
		}
	}

	if (stack->count > 0 && new_statements.count > 0 && new_statements.data[new_statements.count - 1]->type != AST_DEFERRED_SEQUENCE && new_statements.data[new_statements.count - 1]->type != AST_RETURN) {
		ASTNode *tail = new_ast_node(AST_DEFERRED_SEQUENCE, stack->data[stack->count - 1]->location);
		for (int i = stack->count - 1; i >= 0; --i) {
			if (stack->data[i]->type != AST_DEFER_BLOCK) {
				CompilerResult res;
				push_stmt(tail, stack->data[i], &res);
				assert(res == RESULT_SUCCESS);
			}
		}
		da_push_unsafe(new_statements, tail);
	}

	free(node->data.block.statements);
	node->data.block.statements = new_statements.data;
	node->data.block.count = new_statements.count;
}

// <block>
// ::= '{' (<statement>)* '}'
ASTNode *parse_block(Parser *parser, const char *prefix_name, DeferStack *dstack) {
	SourceLocation loc = parser->current_token.location;
	int is_error = 0;
	if (parser->current_token.type != TOK_LCURLY) {
		report(parser->current_token.location, "expected '{' to start block.", 0);
		is_error = 1;
	}
	parser->current_token = next_token(&parser->scanner); // consume '{'

	NodeList stmts;
	da_init(stmts, 4);

	DeferStack dstack_local = copy_defer_stack(dstack);
	while (parser->current_token.type != TOK_RCURLY && parser->current_token.type != TOK_EOF) {
		ASTNode *stmt = parse_stmt(parser, prefix_name, &dstack_local);
		if (!stmt)
			continue;

		if (stmt->type == AST_DEFER_BLOCK) {
			for (int j = 0; j < stmt->data.defer.defer_block->data.block.count; ++j) {
				da_push_unsafe(dstack_local, stmt->data.defer.defer_block->data.block.statements[j]);
			}
			free(stmt);
			continue;
		}
		da_push(stmts, stmt);
	}

	if (parser->current_token.type != TOK_RCURLY) {
		is_error = 1;
		report(parser->current_token.location, "expected '}' to end the block.", 0);
	}

	if (!is_error) {
		parser->current_token = next_token(&parser->scanner);
		ASTNode *block = new_block_node(stmts.data, stmts.count, loc);
		unroll_defers(block, &dstack_local);
		da_deinit(dstack_local);
		return block;
	}
	da_deinit(dstack_local);
	return NULL;
}

// <deferBlock>
// ::= 'defer' <block>
ASTNode *parse_defer_block(Parser *parser, const char *prefix_name, DeferStack *dstack) {
	SourceLocation loc = parser->current_token.location;
	parser->current_token = next_token(&parser->scanner); // consume 'defer'

	if (parser->current_token.type != TOK_LCURLY) {
		char msg[128];
		sprintf(msg, "expected '{' after 'defer', got %s.", parser->current_token.text);
		return report(parser->current_token.location, msg, 0);
	}

	ASTNode *inner_block = parse_block(parser, prefix_name, dstack);

	return new_defer_block_node(inner_block, loc);
}

// <whileLoop>
// ::= 'while' '(' <condition> ')' <block>
ASTNode *parse_while_loop(Parser *parser, const char *prefix_name, DeferStack *dstack) {

	SourceLocation loc = parser->current_token.location;
	parser->current_token = next_token(&parser->scanner);

	if (parser->current_token.type != TOK_LPAREN) {
		char msg[128];
		sprintf(msg, "expected '(' after 'while', got '%s'.", parser->current_token.text);
		return report(parser->current_token.location, msg, 0);
	}

	parser->current_token = next_token(&parser->scanner); // consume '('

	ASTNode *condition = parse_assignment(parser);

	if (parser->current_token.type != TOK_RPAREN) {
		char msg[128];
		sprintf(msg, "expected ')' after while loop condition, got '%s'.", parser->current_token.text);
		return report(parser->current_token.location, msg, 0);
	}

	parser->current_token = next_token(&parser->scanner); // consume ')'

	ASTNode *body = parse_block(parser, prefix_name, dstack);

	return new_while_loop_node(condition, body, loc);
}

// <forLoop>
// ::= 'for' '(' <init> ';' <condition> ';' <post> ')' <block>
ASTNode *parse_for_loop(Parser *parser, const char *prefix_name, DeferStack *dstack) {
	SourceLocation loc = parser->current_token.location;
	parser->current_token = next_token(&parser->scanner); // consume 'if'
	if (parser->current_token.type != TOK_LPAREN) {
		char msg[128];
		sprintf(msg, "expected '(' after 'for', got '%s'.", parser->current_token.text);
		return report(parser->current_token.location, msg, 0);
	}

	parser->current_token = next_token(&parser->scanner); // consume '('

	// All of these are optional technically
	ASTNode *init = NULL;
	if (parser->current_token.type != TOK_SEMICOLON) {
		init = parse_var_decl(parser, prefix_name, 0); // this also consumes ';' and adds to symtable
	} else {
		parser->current_token = next_token(&parser->scanner);
	}

	ASTNode *condition = NULL;
	if (parser->current_token.type != TOK_SEMICOLON) {
		condition = parse_assignment(parser);
	}

	if (parser->current_token.type != TOK_SEMICOLON) {
		char msg[128];
		sprintf(msg, "expected ';' after for loop condition, got '%s'.", parser->current_token.text);
		return report(parser->current_token.location, msg, 0);
	}

	parser->current_token = next_token(&parser->scanner); // consume ';'

	ASTNode *post = NULL;
	if (parser->current_token.type != TOK_RPAREN) {
		post = parse_assignment(parser);
	}

	if (parser->current_token.type != TOK_RPAREN) {
		char msg[128];
		sprintf(msg, "expected ';' after for loop post-expression, got '%s'.", parser->current_token.text);
		return report(parser->current_token.location, msg, 0);
	}

	parser->current_token = next_token(&parser->scanner); // consume ')'

	ASTNode *body = parse_block(parser, prefix_name, dstack);

	return new_for_loop_node(init, condition, post, body, loc);
}

// <ifStmt>
// ::= "if" '(' <expression> ')' <statement> ("else" <statement>)*
ASTNode *parse_if_stmt(Parser *parser, const char *prefix_name, DeferStack *dstack) {
	SourceLocation loc = parser->current_token.location;
	parser->current_token = next_token(&parser->scanner); // consume 'if'
	if (parser->current_token.type != TOK_LPAREN) {
		char msg[128];
		sprintf(msg, "expected '(' after 'if', got %s.", parser->current_token.text);
		return report(parser->current_token.location, msg, 0);
	}

	parser->current_token = next_token(&parser->scanner); // consume '('

	ASTNode *condition = parse_assignment(parser); // highest precedence expr
	if (!condition)
		return NULL;

	if (parser->current_token.type != TOK_RPAREN) {
		char msg[128];
		sprintf(msg, "expected ')' after condition in if statement, got %s.", parser->current_token.text);
		return report(parser->current_token.location, msg, 0);
	}

	parser->current_token = next_token(&parser->scanner); // consume '('

	ASTNode *then_branch = parse_block(parser, prefix_name, dstack);
	if (!then_branch) {
		free_ast_node(condition);
		return NULL;
	}

	ASTNode *else_branch = NULL;
	if (parser->current_token.type == TOK_ELSE) {
		parser->current_token = next_token(&parser->scanner);
		if (parser->current_token.type == TOK_IF)
			else_branch = parse_stmt(parser, prefix_name, dstack);
		else
			else_branch = parse_block(parser, prefix_name, dstack);
	}
	return new_if_stmt_node(condition, then_branch, else_branch, loc);
}

// <functionDecl>
// ::= <genericFuncDecl>
// | <basicFuncDecl>
//
// <basicFuncDecl>
// ::= 'fn' <type> <identifier> '(' <parameterList> ')' <block>
// @TODO: implement generic functions
ASTNode *parse_function_decl(Parser *parser, int is_exported) {
	parser->current_token = next_token(&parser->scanner); // consume 'fn'
	if ((parser->current_token.type < TOKENS_BUILTIN_TYPE_BEGIN || parser->current_token.type > TOKENS_BUILTIN_TYPE_END) && parser->current_token.type == TOK_IDENTIFIER)
		return report(parser->current_token.location, "expected return type.", 0);

	Type *type = NULL;
	if (parse_type(parser, &type) != RESULT_SUCCESS) {
		return NULL;
	}

	if (parser->current_token.type != TOK_IDENTIFIER)
		return report(parser->current_token.location, "expected function identifier.", 0);

	char func_name[64];
	strncpy(func_name, parser->current_token.text, sizeof(func_name));
	SourceLocation loc = parser->current_token.location;
	parser->current_token = next_token(&parser->scanner); // consume function name

	int is_error = 0;
	if (lookup_symbol(parser->symbol_table, func_name, parser->current_scope)) {
		char msg[128] = "";
		sprintf(msg, "variable %s already declared in this scope.", func_name);
		report(loc, msg, 0);
		is_error = 1;
	}

	if (parser->current_token.type != TOK_LPAREN) {
		report(parser->current_token.location, "expected '(' after function name.", 0);
		is_error = 1;
	}
	parser->current_token = next_token(&parser->scanner); // consume '('

	ASTNode *params = parse_parameter_list(parser);
	if (parser->current_token.type != TOK_RPAREN) {
		report(parser->current_token.location, "expected ')' after parameter list.", 0);
		is_error = 1;
	}
	parser->current_token = next_token(&parser->scanner); // consume ')'

	++parser->current_scope;
	DeferStack defer_stack;
	da_init(defer_stack, 4);
	ASTNode *body = parse_block(parser, func_name, &defer_stack);
	da_deinit(defer_stack);
	--parser->current_scope;
	if (!is_error && body) {
		ASTNode *decl_node = new_func_decl_node(func_name, params, body, loc);
		add_symbol(&parser->symbol_table, decl_node, func_name, func_name, 1, SYMB_FN, type, parser->current_scope);
		if (is_exported)
			add_symbol(&parser->exported_table, decl_node, func_name, func_name, 1, SYMB_FN, type, parser->current_scope);

		type_deinit(type);
		free(type);
		return decl_node;
	}
	return NULL;
}

ASTNode *parse_extern_func_decl(Parser *parser, int is_exported) {
	parser->current_token = next_token(&parser->scanner); // consume 'fn'
	if ((parser->current_token.type < TOKENS_BUILTIN_TYPE_BEGIN || parser->current_token.type > TOKENS_BUILTIN_TYPE_END) && parser->current_token.type != TOK_IDENTIFIER)
		return report(parser->current_token.location, "expected return type.", 0);

	Type *type = NULL;
	if (parse_type(parser, &type) != RESULT_SUCCESS) {
		return NULL;
	}

	if (parser->current_token.type != TOK_IDENTIFIER)
		return report(parser->current_token.location, "expected function identifier.", 0);

	char func_name[64];
	strncpy(func_name, parser->current_token.text, sizeof(func_name));
	SourceLocation loc = parser->current_token.location;
	parser->current_token = next_token(&parser->scanner); // consume function name

	if (parser->current_token.type != TOK_LPAREN) {
		return report(parser->current_token.location, "expected '(' after function name.", 0);
	}
	parser->current_token = next_token(&parser->scanner); // consume '('

	ASTNode *params = parse_parameter_list(parser);
	if (parser->current_token.type != TOK_RPAREN) {
		return report(parser->current_token.location, "expected ')' after parameter list.", 0);
	}
	parser->current_token = next_token(&parser->scanner); // consume ')'

	if (parser->current_token.type != TOK_SEMICOLON) {
		char msg[128];
		sprintf(msg, "expected ';' after extern function declaration, got '%s'.", parser->current_token.text);
		return report(parser->current_token.location, msg, 0);
	}
	parser->current_token = next_token(&parser->scanner); // consume ')'

	ASTNode *decl_node = new_extern_func_decl_node(func_name, params, loc);
	add_symbol(&parser->symbol_table, decl_node, func_name, func_name, 1, SYMB_FN, type, parser->current_scope);
	if (is_exported) {
		add_symbol(&parser->exported_table, decl_node, func_name, func_name, 1, SYMB_FN, type, parser->current_scope);
	}
	type_deinit(type);
	free(type);
	return decl_node;
}

ASTNode *parse_extern_block(Parser *parser, const char *prefix_name) {
	SourceLocation loc = parser->current_token.location;
	parser->current_token = next_token(&parser->scanner); // consume 'extern'
	char lib_name[64] = "c";

	if (parser->current_token.type == TOK_IDENTIFIER) {
		strncpy(lib_name, parser->current_token.text, sizeof(lib_name));
		parser->current_token = next_token(&parser->scanner); // consume libname
	}
	if (parser->current_token.type != TOK_LCURLY) {
		char msg[128];
		sprintf(msg, "expected '{' in the beginning of extern block, got '%s'.", parser->current_token.text);
		return report(parser->current_token.location, msg, 0);
	}
	parser->current_token = next_token(&parser->scanner); // consume '{'
	NodeList decls;
	da_init(decls, 4);
	while (parser->current_token.type != TOK_RCURLY) {
		ASTNode *decl = NULL;
		int is_exported = 0;
		if (parser->current_token.type == TOK_EXPORT) {
			is_exported = 1;
			parser->current_token = next_token(&parser->scanner);
		}
		if (parser->current_token.type == TOK_STRUCT) {
			decl = parse_struct_decl(parser, is_exported);
			if (!decl)
				return NULL;
			decl->data.struct_decl.is_exported = is_exported;
		} else if (parser->current_token.type == TOK_UNION) {
			decl = parse_union_decl(parser, is_exported);
			if (!decl)
				return NULL;
			decl->data.struct_decl.is_exported = is_exported;
		} else if (parser->current_token.type == TOK_FN) {
			decl = parse_extern_func_decl(parser, is_exported);
			if (!decl)
				return NULL;
			decl->data.extern_func.is_exported = is_exported;
		} else if (parser->current_token.type == TOK_ENUM) {
			decl = parse_enum_decl(parser, is_exported);
			if (!decl)
				return NULL;
			decl->data.enum_decl.is_exported = is_exported;
		} else {
			decl = parse_var_decl(parser, prefix_name, is_exported);
			if (!decl)
				return NULL;
			decl->data.var_decl.is_exported = is_exported;
		}
		assert(decl);
		da_push(decls, decl);
	}
	parser->current_token = next_token(&parser->scanner); // consume '}'
	return new_extern_block_node(lib_name, decls.data, decls.count, loc);
}

// <globalDecl>
// ::= <varDecl>
//  | <funcDecl>
//  | <structDecl>
//  | <enumDecl>
//  | <externBlock>
ASTNode *parse_global_decl(Parser *parser) {
	int is_exported = 0;
	if (parser->current_token.type == TOK_EXPORT) {
		is_exported = 1;
		parser->current_token = next_token(&parser->scanner);
	}
	ASTNode *decl = NULL;
	if (parser->current_token.type == TOK_STRUCT) {
		decl = parse_struct_decl(parser, is_exported);
		if (!decl)
			return NULL;
		decl->data.struct_decl.is_exported = is_exported;
	} else if (parser->current_token.type == TOK_UNION) {
		decl = parse_union_decl(parser, is_exported);
		if (!decl)
			return NULL;
		decl->data.struct_decl.is_exported = is_exported;
	} else if (parser->current_token.type == TOK_FN) {
		decl = parse_function_decl(parser, is_exported);
		if (!decl)
			return NULL;
		decl->data.func_decl.is_exported = is_exported;
	} else if (parser->current_token.type == TOK_ENUM) {
		decl = parse_enum_decl(parser, is_exported);
		if (!decl)
			return NULL;
		decl->data.enum_decl.is_exported = is_exported;
	} else if (parser->current_token.type == TOK_EXTERN) {
		decl = parse_extern_block(parser, "");
	} else {
		decl = parse_var_decl(parser, "", is_exported);
		if (!decl)
			return NULL;
		decl->data.var_decl.is_exported = is_exported;
	}
	return decl;
}

char *parse_import(Parser *parser) {
	parser->current_token = next_token(&parser->scanner); // consume 'import'
	if (parser->current_token.type != TOK_IDENTIFIER) {
		char msg[128];
		sprintf(msg, "expected identifier in import, got %s", parser->current_token.text);
		return report(parser->current_token.location, msg, 0);
	}
	char *import_name = strdup(parser->current_token.text);
	parser->current_token = next_token(&parser->scanner); // consume import name
	if (parser->current_token.type != TOK_SEMICOLON) {
		char msg[128];
		sprintf(msg, "expected ';' after import's identifier, got %s", parser->current_token.text);
		free(import_name);
		return report(parser->current_token.location, msg, 0);
	}
	parser->current_token = next_token(&parser->scanner); // consume ';'
	return import_name;
}

CompilerResult parse_import_list(Parser *parser, ImportList *out_import_list) {
	ImportList import_list;
	da_init_result(import_list, 4);

	parser->current_token = next_token(&parser->scanner);

	while (parser->current_token.type != TOK_EOF) {
		if (parser->current_token.type == TOK_IMPORT) {
			char *import_name = parse_import(parser);
			if (!import_name) {
				free(import_list.data);
				return RESULT_FAILURE;
			}
			da_push_result(import_list, import_name);
		} else {
			parser->current_token = next_token(&parser->scanner);
		}
	}

	*out_import_list = import_list;

	// Reset scanner to the beginning
	parser->scanner.id = 0;
	parser->scanner.col = 0;
	parser->scanner.line = 0;
	parser->scanner.is_reading_string = 0;
	return RESULT_SUCCESS;
}

// <globalDecl>* <EOF>
Module *parse_input(Parser *parser) {
	ASTNode *global_list = NULL, *last = NULL;

	parser->current_token = next_token(&parser->scanner);

	int has_errors = 0;
	while (parser->current_token.type != TOK_EOF) {
		if (parser->current_token.type == TOK_IMPORT) {
			parser->current_token = next_token(&parser->scanner); // consume 'import'
			if (parser->current_token.type != TOK_IDENTIFIER) {
				char msg[128];
				sprintf(msg, "expected identifier in import, got %s", parser->current_token.text);
				return report(parser->current_token.location, msg, 0);
			}
			parser->current_token = next_token(&parser->scanner); // consume import name
			if (parser->current_token.type != TOK_SEMICOLON) {
				char msg[128];
				sprintf(msg, "expected ';' after import's identifier, got %s", parser->current_token.text);
				return report(parser->current_token.location, msg, 0);
			}
			parser->current_token = next_token(&parser->scanner); // consume ';'
			continue;
		}

		ASTNode *decl = parse_global_decl(parser);
		if (!decl) {
			has_errors = 1;
			continue;
		}
		if (!global_list) {
			global_list = last = decl;
		} else {
			last->next = decl;
			last = decl;
		}
	}
	Module *module = malloc(sizeof(Module));
	module->ast = global_list;
	module->symbol_table = parser->symbol_table;
	module->exported_table = parser->exported_table;
	module->has_errors = has_errors;
	return module;
}

void free_ast_node(ASTNode *node) {
	if (!node)
		return;

	switch (node->type) {
	case AST_VAR_DECL:
		free_ast_node(node->data.var_decl.init);
		node->data.var_decl.init = NULL;

		type_deinit(node->data.var_decl.type);
		free(node->data.var_decl.type);
		node->data.var_decl.type = NULL;

		break;
	case AST_STRUCT_DECL: {
		ASTNode *current_field = node->data.struct_decl.fields;
		while (current_field) {
			ASTNode *next = current_field->next;
			free_ast_node(current_field);
			current_field = next;
		}
		node->data.struct_decl.fields = NULL;
	} break;
	case AST_FIELD_DECL:
		type_deinit(node->data.field_decl.type);
		free(node->data.field_decl.type);
		node->data.field_decl.type = NULL;
		break;
	case AST_PARAM_DECL:
		type_deinit(node->data.param_decl.type);
		free(node->data.param_decl.type);
		node->data.param_decl.type = NULL;
		break;
	case AST_FN_DECL: {
		ASTNode *curr_param = node->data.func_decl.params;
		while (curr_param) {
			ASTNode *next = curr_param->next;
			free_ast_node(curr_param);
			curr_param = next;
		}
		node->data.func_decl.params = NULL;
		ASTNode *body = node->data.func_decl.body;
		free_ast_node(body);
		node->data.func_decl.body = NULL;
	} break;
	case AST_BLOCK: {
		for (int i = 0; i < node->data.block.count; ++i) {
			free_ast_node(node->data.block.statements[i]);
			node->data.block.statements[i] = NULL;
		}
		free(node->data.block.statements);
		node->data.block.statements = NULL;
	} break;
	case AST_RETURN:
		free_ast_node(node->data.ret.return_expr);
		node->data.ret.return_expr = NULL;
		break;
	case AST_BINARY_EXPR:
		free_ast_node(node->data.binary_op.left);
		node->data.binary_op.left = NULL;
		free_ast_node(node->data.binary_op.right);
		node->data.binary_op.right = NULL;
		break;
	case AST_UNARY_EXPR:
		free_ast_node(node->data.unary_op.operand);
		node->data.unary_op.operand = NULL;
		break;
	case AST_ARRAY_LITERAL:
		for (int i = 0; i < node->data.array_literal.count; ++i) {
			free_ast_node(node->data.array_literal.elements[i]);
			node->data.array_literal.elements[i] = NULL;
		}
		free(node->data.array_literal.elements);
		node->data.array_literal.elements = NULL;
		break;
	case AST_ARRAY_ACCESS:
		free_ast_node(node->data.array_access.base);
		node->data.array_access.base = NULL;
		free_ast_node(node->data.array_access.index);
		node->data.array_access.index = NULL;
		break;
	case AST_ASSIGNMENT:
		free_ast_node(node->data.assignment.lvalue);
		node->data.assignment.lvalue = NULL;
		free_ast_node(node->data.assignment.rvalue);
		node->data.assignment.rvalue = NULL;
		break;
	case AST_FN_CALL:
		free_ast_node(node->data.func_call.callee);
		node->data.func_call.callee = NULL;
		for (int i = 0; i < node->data.func_call.arg_count; ++i) {
			free_ast_node(node->data.func_call.args[i]);
			node->data.func_call.args[i] = NULL;
		}
		free(node->data.func_call.args);
		node->data.func_call.args = NULL;
		break;
	case AST_MEMBER_ACCESS:
		free_ast_node(node->data.member_access.base);
		node->data.member_access.base = NULL;
		break;
	case AST_STRUCT_LITERAL:
		for (int i = 0; i < node->data.struct_literal.count; ++i) {
			free_ast_node(node->data.struct_literal.inits[i]->expr);
			node->data.struct_literal.inits[i]->expr = NULL;
		}
		free(node->data.struct_literal.inits);
		node->data.struct_literal.inits = NULL;
		break;
	case AST_ENUM_DECL:
		for (int i = 0; i < node->data.enum_decl.member_count; ++i) {
			free(node->data.enum_decl.members[i]);
			node->data.enum_decl.members[i] = NULL;
		}
		free(node->data.enum_decl.members);
		node->data.enum_decl.members = NULL;
		type_deinit(node->data.enum_decl.base_type);
		free(node->data.enum_decl.base_type);
		node->data.enum_decl.base_type = NULL;
		break;
	case AST_ENUM_VALUE:
		type_deinit(node->data.enum_value.enum_type);
		free(node->data.enum_value.enum_type);
		node->data.enum_value.enum_type = NULL;
		break;
	case AST_EXTERN_BLOCK:
		for (int i = 0; i < node->data.extern_block.count; ++i) {
			free_ast_node(node->data.extern_block.block[i]);
			node->data.extern_block.block[i] = NULL;
		}
		free(node->data.extern_block.block);
		node->data.extern_block.block = NULL;
		break;
	case AST_EXTERN_FUNC_DECL: {
		ASTNode *curr_param = node->data.extern_func.params;
		while (curr_param) {
			ASTNode *next = curr_param->next;
			free_ast_node(curr_param);
			curr_param = next;
		}
		node->data.extern_func.params = NULL;
	} break;
	case AST_IF_STMT:
		free_ast_node(node->data.if_stmt.condition);
		node->data.if_stmt.condition = NULL;
		free_ast_node(node->data.if_stmt.then_branch);
		node->data.if_stmt.then_branch = NULL;
		free_ast_node(node->data.if_stmt.else_branch);
		node->data.if_stmt.else_branch = NULL;
		break;
	case AST_FOR_LOOP:
		free_ast_node(node->data.for_loop.init);
		node->data.for_loop.init = NULL;
		free_ast_node(node->data.for_loop.condition);
		node->data.for_loop.condition = NULL;
		free_ast_node(node->data.for_loop.post);
		node->data.for_loop.post = NULL;
		free_ast_node(node->data.for_loop.body);
		node->data.for_loop.body = NULL;
		break;
	case AST_WHILE_LOOP:
		free_ast_node(node->data.while_loop.condition);
		node->data.while_loop.condition = NULL;
		free_ast_node(node->data.while_loop.body);
		node->data.while_loop.body = NULL;
		break;
	case AST_DEFER_BLOCK:
		break;
	case AST_DEFERRED_SEQUENCE:
		for (int i = 0; i < node->data.block.count; ++i) {
			free_ast_node(node->data.block.statements[i]);
			node->data.block.statements[i] = NULL;
		}
		free(node->data.block.statements);
		node->data.block.statements = NULL;
	case AST_CAST:
		type_deinit(node->data.cast.target_type);
		free(node->data.cast.target_type);
		node->data.cast.target_type = NULL;
		free_ast_node(node->data.cast.expr);
		node->data.cast.expr = NULL;
		break;
	default:
		break;
	}
	free(node);
}

void ast_deinit(ASTNode *node) {
	if (!node)
		return;

	ASTNode *current_node = node;
	while (current_node != NULL) {
		ASTNode *next = current_node->next;
		free_ast_node(current_node);
		current_node = next;
	}
}
