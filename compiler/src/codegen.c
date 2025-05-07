#include "codegen.h"
#include "hashmap.h"
#include "parser.h"
#include "sema.h"
#include "symbol_table.h"
#include "types.h"

#include <assert.h>
#include <llvm-c/Core.h>
#include <llvm-c/DebugInfo.h>
#include <llvm-c/Types.h>
#include <stdio.h>
#include <string.h>

#define PLATFORM_POINTER_SIZE 64

typedef enum DebugEncodingType {
	DW_ATE_address = 0x01,
	DW_ATE_boolean = 0x02,
	DW_ATE_complex_float = 0x03,
	DW_ATE_float = 0x04,
	DW_ATE_signed = 0x05,
	DW_ATE_signed_char = 0x06,
	DW_ATE_unsigned = 0x07,
	DW_ATE_unsigned_char = 0x08,
	DW_ATE_imaginary_float = 0x09,
	DW_ATE_packed_decimal = 0x0a,
	DW_ATE_numeric_string = 0x0b,
	DW_ATE_edited = 0x0c,
	DW_ATE_signed_fixed = 0x0d,
	DW_ATE_unsigned_fixed = 0x0e,
	DW_ATE_decimal_float = 0x0f,
	DW_ATE_UTF = 0x10,
	DW_ATE_lo_user = 0x80,
	DW_ATE_hi_user = 0xff
} DebugEncodingType;

CodegenLLVM codegen_init(CodegenInitContext *init_params) {
	CodegenLLVM cg = {init_params->should_build_debug, 0};
	cg.llvm_context = LLVMContextCreate();
	cg.module = LLVMModuleCreateWithNameInContext(init_params->module_name, cg.llvm_context);
	cg.builder = LLVMCreateBuilderInContext(cg.llvm_context);
	if (cg.should_build_debug) {
		cg.di_builder = LLVMCreateDIBuilder(cg.module);
		int filename_len = strlen(init_params->filename);
		int dirname_len = strlen(init_params->dir);
		cg.di_file = LLVMDIBuilderCreateFile(cg.di_builder, init_params->filename, filename_len, init_params->dir, dirname_len);
		cg.di_cu = LLVMDIBuilderCreateCompileUnit(cg.di_builder, LLVMDWARFSourceLanguageC, cg.di_file, "saplang", 7, 0, "", 0, 0, "", 0, LLVMDWARFEmissionFull, 0, 0, 0, "", 0, "", 0);
	}
	return cg;
}

void codegen_deinit(CodegenLLVM *cg) {
	if (cg->should_build_debug) {
		LLVMDisposeDIBuilder(cg->di_builder);
	}
	LLVMDisposeBuilder(cg->builder);
	LLVMDisposeModule(cg->module);
	LLVMContextDispose(cg->llvm_context);
}

LLVMTypeRef map_to_llvm(CodegenLLVM *cg, Type *type, Symbol *table) {
	assert(type);
	switch (type->kind) {
	case TYPE_PRIMITIVE:
		if (strcmp(type->type_name, "i8") == 0) {
			return LLVMInt8TypeInContext(cg->llvm_context);
		}
		if (strcmp(type->type_name, "i16") == 0) {
			return LLVMInt16TypeInContext(cg->llvm_context);
		}
		if (strcmp(type->type_name, "i32") == 0) {
			return LLVMInt32TypeInContext(cg->llvm_context);
		}
		if (strcmp(type->type_name, "i64") == 0) {
			return LLVMInt64TypeInContext(cg->llvm_context);
		}
		if (strcmp(type->type_name, "u8") == 0) {
			return LLVMInt8TypeInContext(cg->llvm_context);
		}
		if (strcmp(type->type_name, "u16") == 0) {
			return LLVMInt16TypeInContext(cg->llvm_context);
		}
		if (strcmp(type->type_name, "u32") == 0) {
			return LLVMInt32TypeInContext(cg->llvm_context);
		}
		if (strcmp(type->type_name, "u64") == 0) {
			return LLVMInt64TypeInContext(cg->llvm_context);
		}
		if (strcmp(type->type_name, "bool") == 0) {
			return LLVMInt1TypeInContext(cg->llvm_context);
		}
		// TODO: add f16
		if (strcmp(type->type_name, "f32") == 0) {
			return LLVMFloatTypeInContext(cg->llvm_context);
		}
		if (strcmp(type->type_name, "f64") == 0) {
			return LLVMDoubleTypeInContext(cg->llvm_context);
		}
		if (strcmp(type->type_name, "void") == 0) {
			return LLVMVoidTypeInContext(cg->llvm_context);
		}
		break;
	case TYPE_POINTER: {
		LLVMTypeRef elem = map_to_llvm(cg, type->pointee, table);
		return LLVMPointerType(elem, 0);
	} break;
	case TYPE_ARRAY: {
		LLVMTypeRef elem = map_to_llvm(cg, type->array.element_type, table);
		return LLVMArrayType(elem, type->array.size);
	} break;
	case TYPE_FUNCTION: {
		LLVMTypeRef ret_type = map_to_llvm(cg, type->function.return_type, table);
		LLVMTypeRef *param_types = alloca(sizeof(LLVMTypeRef) * (size_t)type->function.param_count);
		for (int i = 0; i < type->function.param_count; ++i) {
			param_types[i] = map_to_llvm(cg, type->function.param_types[i], table);
		}
		return LLVMFunctionType(ret_type, param_types, type->function.param_count, 0);
	}
	case TYPE_STRUCT:
		return LLVMGetTypeByName2(cg->llvm_context, type->type_name);
	case TYPE_ENUM: {
		Symbol *sym = lookup_symbol(table, type->type_name, 0);
		assert(sym && "unknown enum symbol.");
		assert(sym->kind == SYMB_ENUM && "symbol expected to be enum.");
		return map_to_llvm(cg, sym->type, table);
	}
	case TYPE_UNDECIDED:
		assert(0 && "should not be any undecided types in codegen.");
	}
	return NULL;
}

typedef enum { PI_NONE, PI_LOAD_PTR, PI_LOAD_VAL, PI_STORE_VAL, PI_STORE_PTR } PassIntention;

typedef struct {
	int current_scope;
	Type *expected_type;
	hashmap_t *loaded_values;
	ASTNode *auxiliary_node;
	ASTNode *current_function_node;
	PassIntention intention;
} PassContext;

LLVMValueRef codegen_ast(CodegenLLVM *cg, ASTNode *node, Symbol *stable, PassContext ctx);

LLVMValueRef codegen_assignment(CodegenLLVM *cg, ASTNode *node, Symbol *table, PassContext ctx) {
	ASTNode *lvalue = node->data.assignment.lvalue;
	assert(lvalue->type == AST_EXPR_IDENT || lvalue->type == AST_MEMBER_ACCESS);
	if (lvalue->type == AST_EXPR_IDENT) {
		Symbol *sym = lookup_symbol(table, lvalue->data.ident.resolved_name, ctx.current_scope);
		assert(sym);
		ctx.expected_type = sym->type;
		ctx.auxiliary_node = sym->node;
	} else if (lvalue->type == AST_MEMBER_ACCESS) {
		Type *type = get_type(table, node, ctx.current_scope, "");
		assert(type);
		ctx.expected_type = type;
		ctx.auxiliary_node = node->data.member_access.base;
	}
	ASTNode *rvalue = node->data.assignment.rvalue;
	LLVMValueRef lhs = codegen_ast(cg, lvalue, table, ctx);
    ctx.intention = PI_LOAD_VAL;
	LLVMValueRef rhs = codegen_ast(cg, rvalue, table, ctx);
	// There is no need for store here since struct literal assignment is already handled
	if (lvalue->type == AST_EXPR_IDENT && rvalue->type == AST_STRUCT_LITERAL)
		return NULL;
	return LLVMBuildStore(cg->builder, rhs, lhs);
}

LLVMTypeRef codegen_struct_decl(CodegenLLVM *cg, ASTNode *node, Symbol *table) {
	LLVMTypeRef element_types[256];
	assert(node->data.struct_decl.field_count < 257 && "can only have 256 fields max.");
	for (int i = 0; i < node->data.struct_decl.field_count; ++i) {
		ASTNode *current_field = node->data.struct_decl.fields[i];
		element_types[i] = map_to_llvm(cg, current_field->data.field_decl.type, table);
	}
	LLVMTypeRef struct_type = LLVMStructCreateNamed(cg->llvm_context, node->data.struct_decl.name);
	// NOTE: not sure if packed
	LLVMStructSetBody(struct_type, element_types, node->data.struct_decl.field_count, 0);
	return struct_type;
}

LLVMValueRef codegen_member_access(CodegenLLVM *cg, ASTNode *node, Symbol *table, PassContext ctx) {
    PassIntention tmp_intention = ctx.intention;
    ctx.intention = PI_LOAD_PTR;
	LLVMValueRef base_value = codegen_ast(cg, node->data.member_access.base, table, ctx);
	assert(base_value);
    ctx.intention = tmp_intention;
	Type *base_type = get_type(table, node->data.member_access.base, ctx.current_scope, "");
	assert(base_type);
	assert(base_type->kind == TYPE_STRUCT);
	LLVMTypeRef struct_ty = map_to_llvm(cg, base_type, table);
	assert(struct_ty);
	Symbol *decl_sym = lookup_symbol(table, base_type->type_name, ctx.current_scope);
	int field_index = find_field_index(decl_sym->node, node->data.member_access.member);
	assert(field_index > -1);
	LLVMTypeRef index_type = LLVMIntType(PLATFORM_POINTER_SIZE);
	LLVMValueRef index = LLVMConstInt(index_type, field_index, 0);
	LLVMValueRef field_gep = LLVMBuildStructGEP2(cg->builder, struct_ty, base_value, field_index, node->data.member_access.member);
	assert(field_gep);
	if (ctx.intention != PI_LOAD_VAL) {
		return field_gep;
	}
	LLVMTypeRef field_ty = LLVMStructGetTypeAtIndex(struct_ty, field_index);
	return LLVMBuildLoad2(cg->builder, field_ty, field_gep, "");
}

LLVMValueRef codegen_return(CodegenLLVM *cg, ASTNode *node, Symbol *table, PassContext ctx) {
	// NOTE: this is copy pasted from codegen_function
	// TODO: cache this probably
	char *func_name = ctx.current_function_node->data.func_decl.name;
	size_t func_name_len = strlen(func_name);
	char *linkage_name = func_name;
	size_t linkage_name_len = func_name_len;
	int should_free_linkage_name = 0;
	if (node->data.func_decl.is_exported) {
		size_t len = 0;
		const char *mod_name = LLVMGetModuleIdentifier(cg->module, &len);
		linkage_name_len = len + func_name_len + 4; // underscores in the beginning and middle, \0
		linkage_name = malloc(sizeof(char) * linkage_name_len);
		sprintf(linkage_name, "__%s_%s", mod_name, func_name);
		int should_free_linkage_name = 1;
	}
	Symbol *sym = lookup_symbol_weak(table, linkage_name, 0);
	assert(sym);
	assert(sym->type);
	assert(sym->kind == SYMB_FN && sym->type->kind == TYPE_FUNCTION);
	if (should_free_linkage_name)
		free(linkage_name);
	ctx.expected_type = sym->type->function.return_type;
	ctx.intention = PI_LOAD_VAL;
	ASTNodeType ret_expr_type = node->data.ret.return_expr->type;
	LLVMValueRef expr = codegen_ast(cg, node->data.ret.return_expr, table, ctx);
	assert(expr);
	return LLVMBuildRet(cg->builder, expr);
}

// This can only be assignment
LLVMValueRef codegen_literal(CodegenLLVM *cg, ASTNode *node, Symbol *table, PassContext ctx) {
	LLVMTypeRef ty = map_to_llvm(cg, ctx.expected_type, table);
	switch (node->type) {
	case AST_EXPR_LITERAL:
		if (node->data.literal.is_bool) {
			return LLVMConstInt(ty, node->data.literal.bool_value, 0);
		} else if (node->data.literal.is_float) {
			return LLVMConstReal(ty, node->data.literal.float_value);
		}
		return LLVMConstInt(ty, node->data.literal.long_value, 1);
		break;
	case AST_STRUCT_LITERAL: {
		int init_count = node->data.struct_literal.count;
		Symbol *decl_sym = lookup_symbol(table, ctx.expected_type->type_name, ctx.current_scope);
		assert(decl_sym);
		ASTNode *decl_node = decl_sym->node;
		assert(decl_node); // sanity
		int field_count = decl_node->data.struct_decl.field_count;
		LLVMValueRef *generated_values = alloca(sizeof(LLVMValueRef) * field_count);
		// TODO: maybe make default field initialization opt-in?
		for (int i = 0; i < field_count; ++i) {
			ASTNode *curr_field = decl_node->data.struct_decl.fields[i];
			LLVMTypeRef field_type = map_to_llvm(cg, curr_field->data.field_decl.type, table);
			generated_values[i] = LLVMConstNull(field_type);
			curr_field = curr_field->next;
		}
		// If global scope
		int current_field_index = 0;
		for (int i = 0; i < init_count; ++i) {
			FieldInitializer *init = node->data.struct_literal.inits[i];
			if (init->is_designated) {
				current_field_index = find_field_index(decl_node, init->field);
				assert(current_field_index != -1);
			}
			ASTNode *curr_field = decl_node->data.struct_decl.fields[current_field_index];
			ctx.expected_type = curr_field->data.field_decl.type;
			LLVMValueRef generated_value = codegen_ast(cg, init->expr, table, ctx);
			generated_values[current_field_index] = generated_value;
			++current_field_index;
		}
		if (ctx.current_scope == 0) {
			return LLVMConstNamedStruct(ty, generated_values, field_count);
		}
		LLVMValueRef var_ptr = hashmap_get(ctx.loaded_values, ctx.auxiliary_node->data.var_decl.resolved_name);
		assert(var_ptr);
		for (int i = 0; i < field_count; ++i) {
			ASTNode *curr_field = decl_node->data.struct_decl.fields[i];
			LLVMTypeRef field_type = LLVMStructGetTypeAtIndex(ty, i);
			LLVMTypeRef index_type = LLVMIntType(PLATFORM_POINTER_SIZE);
			LLVMValueRef index = LLVMConstInt(index_type, i, 0);
			char gep_name[512] = "";
			snprintf(gep_name, sizeof(gep_name), "gep_%d%s", i, ctx.auxiliary_node->data.var_decl.resolved_name);
			LLVMValueRef field_gep = LLVMBuildStructGEP2(cg->builder, ty, var_ptr, i, gep_name);
			LLVMBuildStore(cg->builder, generated_values[i], field_gep);
		}
		return var_ptr;
	} break;
	case AST_ARRAY_LITERAL:
		break;
	}
	return NULL;
}

LLVMValueRef codegen_global_var_decl(CodegenLLVM *cg, ASTNode *node, Symbol *table, int is_extern) {
	LLVMTypeRef ty = map_to_llvm(cg, node->data.var_decl.type, table);
	LLVMValueRef global_var = LLVMAddGlobal(cg->module, ty, node->data.var_decl.resolved_name);
	PassContext ctx = {0, node->data.var_decl.type, NULL, NULL, NULL, PI_NONE};
	LLVMValueRef init_value = node->data.var_decl.init ? codegen_literal(cg, node->data.var_decl.init, table, ctx) : LLVMConstNull(ty);
	LLVMSetGlobalConstant(global_var, node->data.var_decl.is_const);
	LLVMSetInitializer(global_var, init_value);
	LLVMSetLinkage(global_var, LLVMExternalLinkage);
	// LLVMSetThreadLocal(global_var, 0);
	// LLVMSetThreadLocalMode(global_var, LLVMNotThreadLocal);
	return global_var;
}

LLVMValueRef codegen_var_decl(CodegenLLVM *cg, ASTNode *node, Symbol *table, PassContext ctx) {
	LLVMTypeRef ty = map_to_llvm(cg, node->data.var_decl.type, table);
	LLVMValueRef ptr = LLVMBuildAlloca(cg->builder, ty, node->data.var_decl.resolved_name);
	char *resolved_name = strdup(node->data.var_decl.resolved_name);
	hashmap_put(ctx.loaded_values, resolved_name, ptr);
	if (node->data.var_decl.init) {
		++ctx.current_scope;
		ctx.expected_type = node->data.var_decl.type;
		ctx.auxiliary_node = node;
		LLVMValueRef val = codegen_ast(cg, node->data.var_decl.init, table, ctx);
		if (node->data.var_decl.init->type != AST_STRUCT_LITERAL) {
			assert(val);
			LLVMBuildStore(cg->builder, val, ptr);
		}
	}
	return ptr;
}

void free_str(void *str) { free(str); }

LLVMValueRef codegen_function(CodegenLLVM *cg, ASTNode *node, Symbol *table) {
	char *func_name = node->data.func_decl.name;
	size_t func_name_len = strlen(func_name);
	char *linkage_name = func_name;
	size_t linkage_name_len = func_name_len;
	int should_free_linkage_name = 0;
	if (node->data.func_decl.is_exported) {
		size_t len = 0;
		const char *mod_name = LLVMGetModuleIdentifier(cg->module, &len);
		linkage_name_len = len + func_name_len + 4; // underscores in the beginning and middle, \0
		linkage_name = malloc(sizeof(char) * linkage_name_len);
		sprintf(linkage_name, "__%s_%s", mod_name, func_name);
		int should_free_linkage_name = 1;
	}
	Symbol *sym = lookup_symbol_weak(table, linkage_name, 0);
	assert(sym);
	assert(sym->type);
	LLVMTypeRef fn_ty = map_to_llvm(cg, sym->type, table);
	LLVMValueRef fn = LLVMAddFunction(cg->module, func_name, fn_ty);
	if (cg->should_build_debug) {
		LLVMMetadataRef di_fn = LLVMDIBuilderCreateFunction(cg->di_builder, (LLVMMetadataRef)cg->di_cu, func_name, func_name_len, linkage_name, linkage_name_len, cg->di_file, 0, NULL, 0, 1, 1, 0, 0);
		LLVMSetSubprogram(fn, di_fn);
	}
	LLVMBasicBlockRef entry = LLVMAppendBasicBlockInContext(cg->llvm_context, fn, "entry");
	LLVMPositionBuilderAtEnd(cg->builder, entry);
	hashmap_t *values_map = hashmap_create(64, NULL, NULL);
	// function parameters
	{
		LLVMValueRef *args = alloca(sizeof(LLVMValueRef) * sym->type->function.param_count);
		LLVMGetParams(fn, args);
		LLVMTypeRef *args_types = alloca(sizeof(LLVMTypeRef) * sym->type->function.param_count);
		LLVMGetParamTypes(fn_ty, args_types);
		ASTNode *curr_param = node->data.func_decl.params;
		size_t index = 0;
		while (curr_param) {
			assert(args_types[index]);
			assert(args[index]);
			LLVMTypeRef ty = args_types[index];
			LLVMValueRef ptr = LLVMBuildAlloca(cg->builder, ty, curr_param->data.param_decl.resolved_name);
			char *param_name = strdup(curr_param->data.param_decl.resolved_name);
			hashmap_put(values_map, param_name, ptr);
			LLVMBuildStore(cg->builder, args[index], ptr);
			// if (cg->should_build_debug) {
			// 	int name_len = strlen(curr_param->data.param_decl.name);
			// 	LLVMDIBuilderCreateParameterVariable(cg->di_builder, (LLVMMetadataRef)cg->di_cu, curr_param->data.param_decl.name, name_len, index, cg->di_file, curr_param->location.line, args_types[index], 1, 0);
			// }
			curr_param = curr_param->next;
			++index;
		}
	}
	PassContext ctx = {1, NULL, values_map, NULL, node, PI_NONE};
	codegen_ast(cg, node->data.func_decl.body, table, ctx);
	if (should_free_linkage_name)
		free(linkage_name);
	if (hashmap_size(values_map))
		hashmap_destroy(values_map, free_str, NULL);
	return fn;
}

LLVMValueRef codegen_ast(CodegenLLVM *cg, ASTNode *node, Symbol *table, PassContext ctx) {
	switch (node->type) {
	case AST_FN_DECL:
		return codegen_function(cg, node, table);
	case AST_VAR_DECL: {
		LLVMValueRef value = codegen_var_decl(cg, node, table, ctx);
		return value;
	} break;
	case AST_STRUCT_DECL: {
		LLVMTypeRef type = codegen_struct_decl(cg, node, table);
		break;
	}
	case AST_EXPR_IDENT: {
		if (hashmap_contains(ctx.loaded_values, node->data.ident.resolved_name)) {
			LLVMValueRef ptr = hashmap_get(ctx.loaded_values, node->data.ident.resolved_name);
			if (ctx.intention == PI_LOAD_VAL && ctx.expected_type) {
				LLVMTypeRef ty = map_to_llvm(cg, ctx.expected_type, table);
				return LLVMBuildLoad2(cg->builder, ty, ptr, "");
			}
			return ptr;
		}
		LLVMValueRef named_global = LLVMGetNamedGlobal(cg->module, node->data.ident.resolved_name);
		assert(named_global); // @NOTE: I think that's the only option here - can only be global var
		return named_global;
	}

	case AST_STRUCT_LITERAL:
	case AST_EXPR_LITERAL:
		return codegen_literal(cg, node, table, ctx);
	case AST_ASSIGNMENT:
		return codegen_assignment(cg, node, table, ctx);
	case AST_DEFERRED_SEQUENCE:
	case AST_BLOCK: {
		for (int i = 0; i < node->data.block.count; ++i) {
			ASTNode *stmt = node->data.block.statements[i];
			codegen_ast(cg, stmt, table, ctx);
		}
	} break;
	case AST_MEMBER_ACCESS:
		return codegen_member_access(cg, node, table, ctx);
	case AST_RETURN:
		return codegen_return(cg, node, table, ctx);
	case AST_ARRAY_LITERAL:
	case AST_STRING_LIT:
	case AST_CHAR_LIT:
	case AST_FIELD_DECL:
	case AST_BINARY_EXPR:
	case AST_UNARY_EXPR:
	case AST_ARRAY_ACCESS:
	case AST_FN_CALL:
	case AST_ENUM_DECL:
	case AST_ENUM_VALUE:
	case AST_EXTERN_BLOCK:
	case AST_EXTERN_FUNC_DECL:
	case AST_IF_STMT:
	case AST_FOR_LOOP:
	case AST_WHILE_LOOP:
	case AST_FN_PTR:
	case AST_CONTINUE:
	case AST_BREAK:
	case AST_CAST:
	case AST_UNION_DECL:
	case AST_DEFER_BLOCK:
		break;
	}
	return NULL;
}

void codegen_run(CodegenLLVM *cg, ASTNode *root, Symbol *table) {
	ASTNode *current = root;
	while (current) {
		// TODO: quick hack
		if (current->type == AST_VAR_DECL) {
			codegen_global_var_decl(cg, current, table, 0);
		} else {
			PassContext ctx = {0, NULL, NULL, NULL, NULL, PI_NONE};
			codegen_ast(cg, current, table, ctx);
		}
		current = current->next;
	}
}

char *codegen_output_str(CodegenLLVM *cg) {
	if (cg->should_build_debug) {
		LLVMDIBuilderFinalize(cg->di_builder);
	}
	return LLVMPrintModuleToString(cg->module);
}
