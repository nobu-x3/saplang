#include "parser.h"
#include "scanner.h"
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

#define print(string, format, ...)                                                                                                                                                                                                             \
	if (string) {                                                                                                                                                                                                                              \
		sprintf(string, format, ##__VA_ARGS__);                                                                                                                                                                                                \
	} else {                                                                                                                                                                                                                                   \
		printf(format, ##__VA_ARGS__);                                                                                                                                                                                                         \
	}

CompilerResult symbol_table_print(Symbol *table, char *string) {
	if (!table)
		return RESULT_PASSED_NULL_PTR;
	for (Symbol *sym = table; sym; sym = sym->next) {
		if (sym->kind == SYMB_VAR) {
			print(string, "\tVariable: %s, Type: %s\n", sym->name, sym->type);
		} else if (sym->kind == SYMB_STRUCT) {
			print(string, "\tStruct: %s\n", sym->name);
		} else if (sym->kind == SYMB_FN) {
			print(string, "\tFn: %s\n", sym->name);
		}
	}
	return RESULT_SUCCESS;
}

CompilerResult add_symbol(Symbol **table, const char *name, SymbolKind kind, const char *type) {
	if (!table)
		return RESULT_PASSED_NULL_PTR;

	Symbol *symb = malloc(sizeof(Symbol));
	if (!symb)
		return RESULT_MEMORY_ERROR;

	strncpy(symb->name, name, sizeof(symb->name));
	strncpy(symb->type, type, sizeof(symb->type));
	symb->kind = kind;
	symb->next = *table;
	*table = symb;
	return RESULT_SUCCESS;
}

CompilerResult deinit_symbol_table(Symbol *table) {
	for (Symbol *sym = table; sym != NULL;) {
		Symbol *next = sym->next;
		free(sym);
		sym = next;
	}
	return RESULT_SUCCESS;
}

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
	deinit_symbol_table(parser->symbol_table);
	deinit_symbol_table(parser->exported_table);
	return RESULT_SUCCESS;
}

CompilerResult ast_print(ASTNode *node, int indent, char *string) {
	if (!node)
		return RESULT_PASSED_NULL_PTR;
	while (node) {
		for (int i = 0; i < indent; ++i) {
			print(string, "  ");
		}
		switch (node->type) {
		case AST_VAR_DECL: {
			print(string, "VarDecl: %s%s%s %s", node->data.var_decl.is_exported ? "exported " : "", node->data.var_decl.is_const ? "const " : "", node->data.var_decl.type_name, node->data.var_decl.name);
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
		case AST_FUNC_DECL:
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
		case AST_FIELD_DECL:
			print(string, "FieldDecl: %s %s\n", node->data.field_decl.type_name, node->data.field_decl.name);
			break;
		case AST_PARAM_DECL:
			if (node->data.param_decl.is_va) {
				print(string, "ParamDecl: ...\n");
			} else {
				print(string, "ParamDecl: %s%s %s\n", node->data.param_decl.is_const ? "const " : "", node->data.param_decl.type_name, node->data.param_decl.name);
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
		case AST_FUNC_CALL:
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
		case AST_ENUM_DECL:
			print(string, "EnumDecl with %d member(s) - %s%s : %s:\n", node->data.enum_decl.member_count, node->data.enum_decl.is_exported ? "exported " : "", node->data.enum_decl.name, node->data.enum_decl.base_type);
			for (int i = 0; i < node->data.enum_decl.member_count; ++i) {
				for (int i = 0; i < indent + 1; ++i) {
					print(string, "  ");
				}
				char prefix[128] = "";
				sprintf(prefix, "%s : %ld", node->data.enum_decl.members[i]->name, node->data.enum_decl.members[i]->value);
				print(string, "%s\n", prefix);
			}
			break;
		case AST_ENUM_VALUE:
			print(string, "EnumValue: %s::%s", node->data.enum_value.enum_type, node->data.enum_value.member);
			break;
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
			print(string, "Condiiton:\n");
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

ASTNode *new_ast_node(ASTNodeType type) {
	ASTNode *node = malloc(sizeof(ASTNode));
	if (!node) {
		return NULL;
	}

	node->type = type;
	node->next = NULL;
	return node;
}

ASTNode *new_for_loop_node(ASTNode *init, ASTNode *condition, ASTNode *post, ASTNode *body) {
	ASTNode *node = new_ast_node(AST_FOR_LOOP);
	if (!node)
		return NULL;

	node->data.for_loop.init = init;
	node->data.for_loop.condition = condition;
	node->data.for_loop.post = post;
	node->data.for_loop.body = body;
	return node;
}

ASTNode *new_enum_decl_node(const char *name, const char *base_type, EnumMember **members, int member_count) {
	ASTNode *node = new_ast_node(AST_ENUM_DECL);
	if (!node)
		return NULL;
	strncpy(node->data.enum_decl.name, name, sizeof(node->data.enum_decl.name));
	strncpy(node->data.enum_decl.base_type, base_type, sizeof(node->data.enum_decl.base_type));
	node->data.enum_decl.members = members;
	node->data.enum_decl.member_count = member_count;
	return node;
}

ASTNode *new_enum_value_node(const char *namespace, const char *enum_type, const char *member) {
	ASTNode *node = new_ast_node(AST_ENUM_VALUE);
	if (!node)
		return NULL;
	if (namespace) {
		strncpy(node->data.enum_value.namespace, namespace, sizeof(node->data.enum_value.namespace));
	} else {
		node->data.enum_value.namespace[0] = '\0';
	}
	strncpy(node->data.enum_value.enum_type, enum_type, sizeof(node->data.enum_value.enum_type));
	strncpy(node->data.enum_value.member, member, sizeof(node->data.enum_value.member));
	return node;
}

ASTNode *new_struct_literal_node(FieldInitializer **inits, int count) {
	ASTNode *node = new_ast_node(AST_STRUCT_LITERAL);
	if (!node)
		return NULL;
	node->data.struct_literal.inits = inits;
	node->data.struct_literal.count = count;
	return node;
}

ASTNode *new_member_access_node(ASTNode *base, const char *member_name) {
	ASTNode *node = new_ast_node(AST_MEMBER_ACCESS);
	if (!node)
		return NULL;
	node->data.member_access.base = base;
	strncpy(node->data.member_access.member, member_name, sizeof(node->data.member_access.member));
	return node;
}

ASTNode *new_function_call(ASTNode *callee, ASTNode **args, int arg_count) {
	ASTNode *node = new_ast_node(AST_FUNC_CALL);
	if (!node)
		return NULL;
	node->data.func_call.callee = callee;
	node->data.func_call.args = args;
	node->data.func_call.arg_count = arg_count;
	return node;
}

ASTNode *new_assignment_node(ASTNode *lvalue, ASTNode *rvalue) {
	ASTNode *node = new_ast_node(AST_ASSIGNMENT);
	if (!node)
		return NULL;
	node->data.assignment.lvalue = lvalue;
	node->data.assignment.rvalue = rvalue;
	return node;
}

ASTNode *new_binary_expr_node(TokenType op, ASTNode *left, ASTNode *right) {
	ASTNode *node = new_ast_node(AST_BINARY_EXPR);
	if (!node)
		return NULL;
	node->data.binary_op.op = op;
	node->data.binary_op.left = left;
	node->data.binary_op.right = right;
	return node;
}

ASTNode *new_unary_expr_node(char op, ASTNode *operand) {
	ASTNode *node = new_ast_node(AST_UNARY_EXPR);
	if (!node)
		return NULL;
	node->data.unary_op.op = op;
	node->data.unary_op.operand = operand;
	return node;
}

ASTNode *new_return_node(ASTNode *expr) {
	ASTNode *node = new_ast_node(AST_RETURN);
	if (!node)
		return NULL;
	node->data.ret.return_expr = expr;
	return node;
}

ASTNode *new_field_decl_node(const char *type_name, const char *name) {
	ASTNode *node = new_ast_node(AST_FIELD_DECL);
	if (!node)
		return NULL;
	strncpy(node->data.field_decl.type_name, type_name, sizeof(node->data.field_decl.type_name));
	strncpy(node->data.field_decl.name, name, sizeof(node->data.field_decl.name));
	return node;
}

ASTNode *new_struct_decl_node(const char *name, ASTNode *fields) {
	ASTNode *node = new_ast_node(AST_STRUCT_DECL);
	strncpy(node->data.struct_decl.name, name, sizeof(node->data.struct_decl.name));
	node->data.struct_decl.fields = fields;
	return node;
}

ASTNode *new_var_decl_node(const char *type_name, const char *name, int is_const, ASTNode *initializer) {
	ASTNode *node = new_ast_node(AST_VAR_DECL);
	if (!node)
		return NULL;
	strncpy(node->data.var_decl.name, name, sizeof(node->data.var_decl.name));
	strncpy(node->data.var_decl.type_name, type_name, sizeof(node->data.var_decl.type_name));
	node->data.var_decl.init = initializer;
	node->data.var_decl.is_const = is_const;
	return node;
}

ASTNode *new_block_node(ASTNode **stmts, int count) {
	ASTNode *node = new_ast_node(AST_BLOCK);
	if (!node)
		return NULL;
	node->data.block.statements = stmts;
	node->data.block.count = count;
	return node;
}

ASTNode *new_param_decl_node(const char *type_name, const char *name, int is_const, int is_va) {
	ASTNode *node = new_ast_node(AST_PARAM_DECL);
	if (!node)
		return NULL;
	strncpy(node->data.param_decl.type_name, type_name, sizeof(node->data.param_decl.type_name));
	strncpy(node->data.param_decl.name, name, sizeof(node->data.param_decl.name));
	node->data.param_decl.is_const = is_const;
	node->data.param_decl.is_va = is_va;
	return node;
}

ASTNode *new_func_decl_node(const char *name, ASTNode *params, ASTNode *body) {
	ASTNode *node = new_ast_node(AST_FUNC_DECL);
	if (!node)
		return NULL;
	strncpy(node->data.func_decl.name, name, sizeof(node->data.func_decl.name));
	node->data.func_decl.params = params;
	node->data.func_decl.body = body;
	return node;
}

ASTNode *new_extern_func_decl_node(const char *name, ASTNode *params) {
	ASTNode *node = new_ast_node(AST_EXTERN_FUNC_DECL);
	if (!node)
		return NULL;
	strncpy(node->data.extern_func.name, name, sizeof(node->data.extern_func.name));
	node->data.extern_func.params = params;
	return node;
}

ASTNode *new_extern_block_node(const char *libname, ASTNode **decls, int count) {
	ASTNode *node = new_ast_node(AST_EXTERN_BLOCK);
	if (!node)
		return NULL;
	strncpy(node->data.extern_block.lib_name, libname, sizeof(node->data.extern_block.lib_name));
	node->data.extern_block.block = decls;
	node->data.extern_block.count = count;
	return node;
}

ASTNode *new_literal_node_long(long value) {
	ASTNode *node = new_ast_node(AST_EXPR_LITERAL);
	if (!node)
		return NULL;
	node->data.literal.long_value = value;
	node->data.literal.is_bool = 0;
	node->data.literal.is_float = 0;
	return node;
}

ASTNode *new_literal_node_float(double value) {
	ASTNode *node = new_ast_node(AST_EXPR_LITERAL);
	if (!node)
		return NULL;
	node->data.literal.float_value = value;
	node->data.literal.is_bool = 0;
	node->data.literal.is_float = 1;
	return node;
}

ASTNode *new_literal_node_bool(int value) {
	ASTNode *node = new_ast_node(AST_EXPR_LITERAL);
	if (!node)
		return NULL;
	node->data.literal.bool_value = value;
	node->data.literal.is_bool = 1;
	node->data.literal.is_float = 0;
	return node;
}

ASTNode *new_array_access_node(ASTNode *base, ASTNode *index) {
	ASTNode *node = new_ast_node(AST_ARRAY_ACCESS);
	if (!node)
		return NULL;
	node->data.array_access.base = base;
	node->data.array_access.index = index;
	return node;
}

ASTNode *new_ident_node(const char *namespace, const char *name) {
	ASTNode *node = new_ast_node(AST_EXPR_IDENT);
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

ASTNode *new_array_literal_node(ASTNode **elements, int count) {
	ASTNode *node = new_ast_node(AST_ARRAY_LITERAL);
	if (!node)
		return NULL;
	node->data.array_literal.elements = elements;
	node->data.array_literal.count = count;
	return node;
}

ASTNode *new_if_stmt_node(ASTNode *condition, ASTNode *then_branch, ASTNode *else_branch) {
	ASTNode *node = new_ast_node(AST_IF_STMT);
	if (!node)
		return NULL;

	node->data.if_stmt.condition = condition;
	node->data.if_stmt.then_branch = then_branch;
	node->data.if_stmt.else_branch = else_branch;

	return node;
}

///////////////////////////////////////////////////////////////////////////////

CompilerResult parse_type_name(Parser *parser, char *buffer) {
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
		break;
	default: {
		char msg[128];
		sprintf(msg, "expected type name, got '%s'.", parser->current_token.text);
		report(parser->current_token.location, msg, 0);
		return RESULT_PARSING_ERROR;
	}
	}

	char ptr_prefix[64] = "";
	while (parser->current_token.type == TOK_ASTERISK) {
		strcat(ptr_prefix, "*");
		parser->current_token = next_token(&parser->scanner);
	}

	char array_suffix[64] = "";
	while (parser->current_token.type == TOK_LBRACKET) {
		parser->current_token = next_token(&parser->scanner); // consume '['

		if (parser->current_token.type != TOK_NUMBER) {
			char msg[128];
			sprintf(msg, "expected array size number, got '%s'.", parser->current_token.text);
			report(parser->current_token.location, msg, 0);
			return RESULT_PARSING_ERROR;
		}

		char size_text[32];
		strncpy(size_text, parser->current_token.text, sizeof(size_text));
		parser->current_token = next_token(&parser->scanner); // consume number

		if (parser->current_token.type != TOK_RBRACKET) {
			char msg[128];
			sprintf(msg, "expected ']' after array size, got '%s'.", parser->current_token.text);
			report(parser->current_token.location, msg, 0);
			return RESULT_PARSING_ERROR;
		}

		parser->current_token = next_token(&parser->scanner); // consume ']'
		strcat(array_suffix, "[");
		strcat(array_suffix, size_text);
		strcat(array_suffix, "]");
	}

	char prefix[64] = "";
	if (*namespace) {
		sprintf(prefix, "%s::", namespace);
	}
	snprintf(buffer, 64, "%s%s%s%s", array_suffix, ptr_prefix, prefix, base_type);
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
	return new_ident_node(namespace, name);
}

ASTNode *parse_assignment(Parser *parser) {
	ASTNode *node = parse_expr(parser);
	if (!node)
		return NULL;

	if (parser->current_token.type == TOK_ASSIGN) {
		parser->current_token = next_token(&parser->scanner);
		// Right-associative
		ASTNode *right = parse_assignment(parser);
		node = new_assignment_node(node, right);
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

	char enum_name[64];
	strncpy(enum_name, parser->current_token.text, sizeof(enum_name));
	parser->current_token = next_token(&parser->scanner); // consume enum name

	char base_type[64] = "";
	if (parser->current_token.type == TOK_COLON) {
		parser->current_token = next_token(&parser->scanner); // consume ':'
		parse_type_name(parser, base_type);
	} else {
		strncpy(base_type, "i32", sizeof(base_type));
	}

	if (parser->current_token.type != TOK_LCURLY) {
		char msg[128];
		sprintf(msg, "expected '{' in enum declaration, got '%s'.", parser->current_token.text);
		return report(parser->current_token.location, msg, 0);
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
			return report(parser->current_token.location, msg, 0);
		}
		EnumMember *member = malloc(sizeof(EnumMember));
		if (!member) // @TODO: leaks
			return NULL;
		strncpy(member->name, parser->current_token.text, sizeof(member->name));
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
					return report(parser->current_token.location, msg, 0);
				}
			} else {
				char msg[128];
				sprintf(msg, "expected number or identifier after '=' in enum member declaration, got '%s'.", parser->current_token.text);
				return report(parser->current_token.location, msg, 0);
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
	}
	parser->current_token = next_token(&parser->scanner); // consume '}'
	add_symbol(&parser->symbol_table, enum_name, SYMB_ENUM, base_type);
	if (is_exported) {
		add_symbol(&parser->exported_table, enum_name, SYMB_ENUM, base_type);
	}
	return new_enum_decl_node(enum_name, base_type, members.data, members.count);
}

ASTNode *parse_struct_literal(Parser *parser) {
	typedef struct {
		FieldInitializer **data;
		int capacity;
		int count;
	} field_init_list;

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

	return new_struct_literal_node(inits.data, inits.count);
}

ASTNode *parse_postfix(Parser *parser) {
	ASTNode *node = parse_primary(parser);
	while (parser->current_token.type == TOK_LPAREN || parser->current_token.type == TOK_LBRACKET || parser->current_token.type == TOK_DOT) {

		if (parser->current_token.type == TOK_LPAREN) {

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
			node = new_function_call(node, args.data, args.count);

		} else if (parser->current_token.type == TOK_LBRACKET) {
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

			node = new_array_access_node(node, index_expr);

		} else if (parser->current_token.type == TOK_DOT) {
			parser->current_token = next_token(&parser->scanner);

			if (parser->current_token.type != TOK_IDENTIFIER) {
				char msg[128];
				sprintf(msg, "expected identifier after '.', got '%s'.", parser->current_token.text);
				return report(parser->current_token.location, msg, 0);
			}

			char member_name[64];
			strncpy(member_name, parser->current_token.text, sizeof(member_name));

			parser->current_token = next_token(&parser->scanner);

			node = new_member_access_node(node, member_name);
		}
	}
	return node;
}

// <arrayLiteral>
// ::= '[' (<expression>)* (',')* ']'
ASTNode *parse_array_literal(Parser *parser) {
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
	return new_array_literal_node(elements.data, elements.count);
}

ASTNode *parse_term(Parser *parser) {
	ASTNode *node = parse_unary(parser);
	while (parser->current_token.type == TOK_ASTERISK || parser->current_token.type == TOK_SLASH || parser->current_token.type == TOK_LESSTHAN || parser->current_token.type == TOK_GREATERTHAN || parser->current_token.type == TOK_LTOE ||
		   parser->current_token.type == TOK_GTOE) {
		TokenType op = parser->current_token.type;
		parser->current_token = next_token(&parser->scanner);
		ASTNode *right = parse_unary(parser);
		node = new_binary_expr_node(op, node, right);
	}
	return node;
}

ASTNode *parse_expr(Parser *parser) {
	// I split it like that because of operator precedence
	ASTNode *node = parse_term(parser);
	while (parser->current_token.type == TOK_MINUS || parser->current_token.type == TOK_PLUS) {
		TokenType op = parser->current_token.type;
		parser->current_token = next_token(&parser->scanner);
		ASTNode *right = parse_term(parser);
		node = new_binary_expr_node(op, node, right);
	}
	return node;
}

ASTNode *parse_return_stmt(Parser *parser) {
	parser->current_token = next_token(&parser->scanner); // consume 'return'
	ASTNode *expr = parse_expr(parser);

	if (parser->current_token.type != TOK_SEMICOLON) {
		report(parser->current_token.location, "expected ';' after return statement.", 0);
	}

	parser->current_token = next_token(&parser->scanner); // consume ';'

	return new_return_node(expr);
}

// numbers, bools, identifiers, grouping expressions
// <primaryExpr>
// ::= <number>
//  | <bool>
//  | <identifier>
//  | <groupingExpr>
//  | <arrayLiteral>
//  | <structLiteral>
ASTNode *parse_primary(Parser *parser) {
	// @TODO: add array and struct literals
	if (parser->current_token.type == TOK_NUMBER) {
		if (strchr(parser->current_token.text, '.') != NULL) {
			double value = atof(parser->current_token.text);
			parser->current_token = next_token(&parser->scanner);
			return new_literal_node_float(value);
		} else {
			long value = atol(parser->current_token.text);
			parser->current_token = next_token(&parser->scanner);
			return new_literal_node_long(value);
		}
	} else if (parser->current_token.type == TOK_TRUE) {
		parser->current_token = next_token(&parser->scanner);
		return new_literal_node_bool(1);
	} else if (parser->current_token.type == TOK_FALSE) {
		parser->current_token = next_token(&parser->scanner);
		return new_literal_node_bool(0);
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
		ASTNode *expr = parse_expr(parser);
		if (!expr)
			return NULL;
		if (parser->current_token.type != TOK_RPAREN)
			return report(parser->current_token.location, "expected ')'.", 0);
		parser->current_token = next_token(&parser->scanner);
		return expr;
	} else if (parser->current_token.type == TOK_LBRACKET) {
		return parse_array_literal(parser);
	} else if (parser->current_token.type == TOK_LCURLY) {
		return parse_struct_literal(parser);
	} else {
		char expr[128];
		sprintf(expr, "unexpected token in expression: %s", parser->current_token.text);
		return report(parser->current_token.location, expr, 0);
	}
}

// <unaryExpr>
// ::= ('*' | '!' | '&') <expr>
ASTNode *parse_unary(Parser *parser) {
	TokenType type = parser->current_token.type;
	if (type == TOK_EXCLAMATION || type == TOK_AMPERSAND || type == TOK_ASTERISK) {
		char op = parser->current_token.text[0];
		parser->current_token = next_token(&parser->scanner);
		ASTNode *operand = parse_unary(parser);
		return new_unary_expr_node(op, operand);
	}
	return parse_postfix(parser);
}

// <varDecl>
// ::= ('const')? <type> <identifier> ('=' <expression>)? ';'
ASTNode *parse_var_decl(Parser *parser, int is_exported) {
	int is_const = 0;
	if (parser->current_token.type == TOK_CONST) {
		is_const = 1;
		parser->current_token = next_token(&parser->scanner); // consume 'const'
	}

	char type_name[64];
	parse_type_name(parser, type_name);

	if (parser->current_token.type != TOK_IDENTIFIER) {
		return report(parser->current_token.location, "expected identifier in variable declaration.", 0);
	}

	char var_name[64];
	strncpy(var_name, parser->current_token.text, sizeof(var_name));
	parser->current_token = next_token(&parser->scanner); // consume identifier

	ASTNode *init_expr = NULL;
	if (parser->current_token.type == TOK_ASSIGN) {
		parser->current_token = next_token(&parser->scanner); // consume '='
		init_expr = parse_expr(parser);
	}

	if (parser->current_token.type != TOK_SEMICOLON)
		return report(parser->current_token.location, "expected ';' after variable declaration.", 0);

	parser->current_token = next_token(&parser->scanner); // consume ';'

	add_symbol(&parser->symbol_table, var_name, SYMB_VAR, type_name);
	if (is_exported) {
		add_symbol(&parser->exported_table, var_name, SYMB_VAR, type_name);
	}
	return new_var_decl_node(type_name, var_name, is_const, init_expr);
}

ASTNode *parse_if_stmt(Parser *parser);
ASTNode *parse_for_loop(Parser *parser);

ASTNode *parse_stmt(Parser *parser) {
	if (parser->current_token.type == TOK_IF) {
		return parse_if_stmt(parser);
	}
	if (parser->current_token.type == TOK_FOR) {
		return parse_for_loop(parser);
	}
	if (parser->current_token.type == TOK_RETURN) {
		return parse_return_stmt(parser);
	}

	if (parser->current_token.type == TOK_I8 || parser->current_token.type == TOK_I16 || parser->current_token.type == TOK_I32 || parser->current_token.type == TOK_I64 || parser->current_token.type == TOK_U8 ||
		parser->current_token.type == TOK_U16 || parser->current_token.type == TOK_U32 || parser->current_token.type == TOK_U64 || parser->current_token.type == TOK_F32 || parser->current_token.type == TOK_F64 ||
		parser->current_token.type == TOK_BOOL || parser->current_token.type == TOK_VOID || parser->current_token.type == TOK_IDENTIFIER) {
		// peek ahead
		// @TODO: redo this when reworking scanner to work with indices
		int save = parser->scanner.id;
		Token temp = parser->current_token;
		char type_name[64];
		parse_type_name(parser, type_name);
		if (parser->current_token.type == TOK_IDENTIFIER) {
			// most likely var decl, restore state and reparse
			parser->scanner.id = save;
			parser->current_token = temp;
			return parse_var_decl(parser, 0);
		}
		// restore and parse expression
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
	char type_name[64];
	parse_type_name(parser, type_name);

	if (parser->current_token.type != TOK_IDENTIFIER) {
		return report(parser->current_token.location, "expected identifier in struct field declaration.", 0);
	}

	char field_name[64];
	strncpy(field_name, parser->current_token.text, sizeof(field_name));

	parser->current_token = next_token(&parser->scanner); // consume field name

	if (parser->current_token.type != TOK_SEMICOLON) {
		return report(parser->current_token.location, "expected ';' after struct field declaration.", 0);
	}

	parser->current_token = next_token(&parser->scanner); // consume ';'
	return new_field_decl_node(type_name, field_name);
}

// <structDecl>
// ::= 'struct' <identifier> '{' (<fieldDecl>)* '}'
ASTNode *parse_struct_decl(Parser *parser, int is_exported) {
	parser->current_token = next_token(&parser->scanner); // consume 'struct'
	// @TODO: generic structs
	if (parser->current_token.type != TOK_IDENTIFIER) {
		return report(parser->current_token.location, "expected identifier after 'struct'.", 0);
	}

	char struct_name[64];
	strncpy(struct_name, parser->current_token.text, sizeof(struct_name));

	parser->current_token = next_token(&parser->scanner); // consume struct name

	if (parser->current_token.type != TOK_LCURLY) {
		return report(parser->current_token.location, "expected '{' in struct declaration.", 0);
	}

	parser->current_token = next_token(&parser->scanner); // consume '{'

	ASTNode *field_list = NULL, *last_field = NULL;
	while (parser->current_token.type != TOK_RCURLY && parser->current_token.type != TOK_EOF) {
		ASTNode *field = parse_field_declaration(parser);

		if (!field_list) {
			field_list = last_field = field;
		} else {
			last_field->next = field;
			last_field = field;
		}
	}

	if (parser->current_token.type != TOK_RCURLY) {
		return report(parser->current_token.location, "expected '}' at the end of struct declaration.", 0);
	}
	parser->current_token = next_token(&parser->scanner); // consume '{'

	add_symbol(&parser->symbol_table, struct_name, SYMB_STRUCT, "struct");
	if (is_exported) {
		add_symbol(&parser->exported_table, struct_name, SYMB_STRUCT, "struct");
	}
	return new_struct_decl_node(struct_name, field_list);
}

// <parameterDecl>
// ::= (<type> <identifier>)*
ASTNode *parse_parameter_declaration(Parser *parser) {
	if (parser->current_token.type == TOK_DOTDOTDOT) {
		parser->current_token = next_token(&parser->scanner); // consume name
		return new_param_decl_node("", "", 0, 1);
	}
	int is_const = 0;
	if (parser->current_token.type == TOK_CONST) {
		is_const = 1;
		parser->current_token = next_token(&parser->scanner); // consume name
	}
	char type_name[64];
	if (parse_type_name(parser, type_name) != RESULT_SUCCESS)
		return NULL;
	if (parser->current_token.type != TOK_IDENTIFIER) {
		char msg[128];
		sprintf(msg, "expected identifier in parameter declaration, got %s.", parser->current_token.text);
		return report(parser->current_token.location, msg, 0);
	}
	char param_name[64];
	strncpy(param_name, parser->current_token.text, sizeof(param_name));
	parser->current_token = next_token(&parser->scanner); // consume name
	return new_param_decl_node(type_name, param_name, is_const, 0);
}

ASTNode *parse_parameter_list(Parser *parser) {
	ASTNode *param_list = NULL, *last_param = NULL;

	// empty param list
	if (parser->current_token.type == TOK_RPAREN)
		return NULL;

	ASTNode *param = parse_parameter_declaration(parser);
	param_list = last_param = param;

	while (parser->current_token.type == TOK_COMMA) {
		parser->current_token = next_token(&parser->scanner); // consume comma
		param = parse_parameter_declaration(parser);
		last_param->next = param;
		last_param = param;
	}

	return param_list;
}

// <block>
// ::= '{' (<statement>)* '}'
ASTNode *parse_block(Parser *parser) {
	if (parser->current_token.type != TOK_LCURLY) {
		return report(parser->current_token.location, "expected '{' to start block.", 0);
	}
	parser->current_token = next_token(&parser->scanner); // consume '{'

	NodeList stmts;
	da_init(stmts, 4);

	while (parser->current_token.type != TOK_RCURLY && parser->current_token.type != TOK_EOF) {
		ASTNode *stmt = parse_stmt(parser);
		da_push(stmts, stmt);
	}

	if (parser->current_token.type != TOK_RCURLY) {
		/* for (int i = 0; i < capacity; ++i) { */
		/* 	free(stmts[i]); */
		/* } */
		/* free(stmts); */
		return report(parser->current_token.location, "expected '}' to end the block.", 0);
	}

	parser->current_token = next_token(&parser->scanner);
	return new_block_node(stmts.data, stmts.count);
}

// <forLoop>
// ::= 'for' '(' <init> ';' <condition> ';' <post> ')' '{' <body> '}'
ASTNode *parse_for_loop(Parser *parser) {
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
		init = parse_var_decl(parser, 0); // this also consumes ';' and adds to symtable
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

	ASTNode *body = parse_block(parser);

	return new_for_loop_node(init, condition, post, body);
}

// <ifStmt>
// ::= "if" '(' <expression> ')' <statement> ("else" <statement>)*
ASTNode *parse_if_stmt(Parser *parser) {
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

	ASTNode *then_branch = parse_block(parser);
	if (!then_branch) {
		free_ast_node(condition);
		return NULL;
	}

	ASTNode *else_branch = NULL;
	if (parser->current_token.type == TOK_ELSE) {
		parser->current_token = next_token(&parser->scanner);
		if (parser->current_token.type == TOK_IF)
			else_branch = parse_stmt(parser);
		else
			else_branch = parse_block(parser);
	}
	return new_if_stmt_node(condition, then_branch, else_branch);
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

	char type[64];
	parse_type_name(parser, type);

	if (parser->current_token.type != TOK_IDENTIFIER)
		return report(parser->current_token.location, "expected function identifier.", 0);

	char func_name[64];
	strncpy(func_name, parser->current_token.text, sizeof(func_name));
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

	add_symbol(&parser->symbol_table, func_name, SYMB_FN, type);
	if (is_exported)
		add_symbol(&parser->exported_table, func_name, SYMB_FN, type);

	ASTNode *body = parse_block(parser);
	return new_func_decl_node(func_name, params, body);
}

ASTNode *parse_extern_func_decl(Parser *parser, int is_exported) {
	parser->current_token = next_token(&parser->scanner); // consume 'fn'
	if ((parser->current_token.type < TOKENS_BUILTIN_TYPE_BEGIN || parser->current_token.type > TOKENS_BUILTIN_TYPE_END) && parser->current_token.type != TOK_IDENTIFIER)
		return report(parser->current_token.location, "expected return type.", 0);

	char type[64];
	parse_type_name(parser, type);

	if (parser->current_token.type != TOK_IDENTIFIER)
		return report(parser->current_token.location, "expected function identifier.", 0);

	char func_name[64];
	strncpy(func_name, parser->current_token.text, sizeof(func_name));
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

	add_symbol(&parser->symbol_table, func_name, SYMB_FN, type);
	if (is_exported) {
		add_symbol(&parser->exported_table, func_name, SYMB_FN, type);
	}
	return new_extern_func_decl_node(func_name, params);
}

ASTNode *parse_extern_block(Parser *parser) {
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
			decl->data.struct_decl.is_exported = is_exported;
		} else if (parser->current_token.type == TOK_FUNC) {
			decl = parse_extern_func_decl(parser, is_exported);
			decl->data.extern_func.is_exported = is_exported;
		} else if (parser->current_token.type == TOK_ENUM) {
			decl = parse_enum_decl(parser, is_exported);
			decl->data.enum_decl.is_exported = is_exported;
		} else {
			decl = parse_var_decl(parser, is_exported);
			decl->data.var_decl.is_exported = is_exported;
		}
		assert(decl);
		da_push(decls, decl);
	}
	parser->current_token = next_token(&parser->scanner); // consume '}'
	return new_extern_block_node(lib_name, decls.data, decls.count);
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
		decl->data.struct_decl.is_exported = is_exported;
	} else if (parser->current_token.type == TOK_FUNC) {
		decl = parse_function_decl(parser, is_exported);
		decl->data.func_decl.is_exported = is_exported;
	} else if (parser->current_token.type == TOK_ENUM) {
		decl = parse_enum_decl(parser, is_exported);
		decl->data.enum_decl.is_exported = is_exported;
	} else if (parser->current_token.type == TOK_EXTERN) {
		decl = parse_extern_block(parser);
	} else {
		decl = parse_var_decl(parser, is_exported);
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
		if (!decl)
			return NULL;
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
	return module;
}

void free_ast_node(ASTNode *node) {
	if (!node)
		return;

	switch (node->type) {
	case AST_VAR_DECL:
		free_ast_node(node->data.var_decl.init);
		break;
	case AST_STRUCT_DECL: {
		ASTNode *current_field = node->data.struct_decl.fields;
		while (current_field) {
			ASTNode *next = current_field->next;
			free_ast_node(current_field);
			current_field = next;
		}
	} break;
	case AST_FUNC_DECL: {
		ASTNode *curr_param = node->data.func_decl.params;
		while (curr_param) {
			ASTNode *next = curr_param->next;
			free_ast_node(curr_param);
			curr_param = next;
		}
		ASTNode *body = node->data.func_decl.body;
		free_ast_node(body);
	} break;
	case AST_BLOCK: {
		for (int i = 0; i < node->data.block.count; ++i) {
			free_ast_node(node->data.block.statements[i]);
		}
		free(node->data.block.statements);
	} break;
	case AST_RETURN:
		free_ast_node(node->data.ret.return_expr);
		break;
	case AST_BINARY_EXPR:
		free_ast_node(node->data.binary_op.left);
		free_ast_node(node->data.binary_op.right);
		break;
	case AST_UNARY_EXPR:
		free_ast_node(node->data.unary_op.operand);
		break;
	case AST_ARRAY_LITERAL:
		for (int i = 0; i < node->data.array_literal.count; ++i) {
			free_ast_node(node->data.array_literal.elements[i]);
		}
		free(node->data.array_literal.elements);
		break;
	case AST_ARRAY_ACCESS:
		free_ast_node(node->data.array_access.base);
		free_ast_node(node->data.array_access.index);
		break;
	case AST_ASSIGNMENT:
		free_ast_node(node->data.assignment.lvalue);
		free_ast_node(node->data.assignment.rvalue);
		break;
	case AST_FUNC_CALL:
		free_ast_node(node->data.func_call.callee);
		for (int i = 0; i < node->data.func_call.arg_count; ++i) {
			free_ast_node(node->data.func_call.args[i]);
		}
		free(node->data.func_call.args);
		break;
	case AST_MEMBER_ACCESS:
		free_ast_node(node->data.member_access.base);
		break;
	case AST_STRUCT_LITERAL:
		for (int i = 0; i < node->data.struct_literal.count; ++i) {
			free_ast_node(node->data.struct_literal.inits[i]->expr);
		}
		free(node->data.struct_literal.inits);
		break;
	case AST_ENUM_DECL:
		for (int i = 0; i < node->data.enum_decl.member_count; ++i) {
			free(node->data.enum_decl.members[i]);
		}
		free(node->data.enum_decl.members);
		break;
	case AST_EXTERN_BLOCK:
		for (int i = 0; i < node->data.extern_block.count; ++i) {
			free_ast_node(node->data.extern_block.block[i]);
		}
		free(node->data.extern_block.block);
		break;
	case AST_EXTERN_FUNC_DECL: {
		ASTNode *curr_param = node->data.extern_func.params;
		while (curr_param) {
			ASTNode *next = curr_param->next;
			free_ast_node(curr_param);
			curr_param = next;
		}
	} break;
	case AST_IF_STMT:
		free_ast_node(node->data.if_stmt.condition);
		free_ast_node(node->data.if_stmt.then_branch);
		free_ast_node(node->data.if_stmt.else_branch);
		break;
	case AST_FOR_LOOP:
		free_ast_node(node->data.for_loop.init);
		free_ast_node(node->data.for_loop.condition);
		free_ast_node(node->data.for_loop.post);
		free_ast_node(node->data.for_loop.body);
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
