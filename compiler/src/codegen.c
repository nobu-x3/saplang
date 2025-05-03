#include "codegen.h"
#include "parser.h"
#include "symbol_table.h"
#include "types.h"
#include "util.h"

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
			return LLVMBFloatTypeInContext(cg->llvm_context);
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
		Symbol *sym = lookup_symbol(table, type->type_name, cg->current_scope);
		assert(sym && "unknown enum symbol.");
		assert(sym->kind == SYMB_ENUM && "symbol expected to be enum.");
		return map_to_llvm(cg, sym->type, table);
	}
	case TYPE_UNDECIDED:
		assert(0 && "should not be any undecided types in codegen.");
	}
	return NULL;
}

typedef struct {
	int is_global;
	Type *expected_type;
} PassContext;

LLVMValueRef codegen_ast(CodegenLLVM *cg, ASTNode *node, Symbol *stable, PassContext ctx);

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

// return -1 if field not present
int find_field_index(ASTNode *struct_decl, const char *field_name) {
	for (int i = 0; i < struct_decl->data.struct_decl.field_count; ++i) {
		ASTNode *curr_field = struct_decl->data.struct_decl.fields[i];
		if (strcmp(curr_field->data.field_decl.name, field_name) == 0)
			return i;
	}
	return -1;
}

LLVMValueRef codegen_literal(CodegenLLVM *cg, ASTNode *node, Type *expected_type, Symbol *table, int is_global) {
	LLVMTypeRef ty = map_to_llvm(cg, expected_type, table);
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
		Symbol *decl_sym = lookup_symbol(table, expected_type->type_name, 0);
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
		if (is_global) {
			int current_field_index = 0;
			for (int i = 0; i < init_count; ++i) {
				FieldInitializer *init = node->data.struct_literal.inits[i];
				if (init->is_designated) {
					current_field_index = find_field_index(decl_node, init->field);
					if (current_field_index == -1) {
						char msg[256] = "";
						sprintf(msg, "cannot find a field with name %s in the definition of struct %s", init->field, expected_type->type_name);
						report(node->location, msg, 0);
						return NULL;
					}
				}
				ASTNode *curr_field = decl_node->data.struct_decl.fields[current_field_index];
				PassContext ctx = {is_global, curr_field->data.field_decl.type};
				LLVMValueRef generated_value = codegen_ast(cg, init->expr, table, ctx);
				generated_values[current_field_index] = generated_value;
				++current_field_index;
			}
			return LLVMConstNamedStruct(ty, generated_values, field_count);
		}
	} break;
	case AST_ARRAY_LITERAL:
		break;
	}
	return NULL;
}

LLVMValueRef codegen_global_var_decl(CodegenLLVM *cg, ASTNode *node, Symbol *table, int is_extern) {
	LLVMTypeRef ty = map_to_llvm(cg, node->data.var_decl.type, table);
	LLVMValueRef global_var = LLVMAddGlobal(cg->module, ty, node->data.var_decl.name);
	LLVMValueRef init_value = node->data.var_decl.init ? codegen_literal(cg, node->data.var_decl.init, node->data.var_decl.type, table, 1) : LLVMConstNull(ty);
	LLVMSetGlobalConstant(global_var, node->data.var_decl.is_const);
	LLVMSetInitializer(global_var, init_value);
	LLVMSetLinkage(global_var, LLVMExternalLinkage);
	// LLVMSetThreadLocal(global_var, 0);
	// LLVMSetThreadLocalMode(global_var, LLVMNotThreadLocal);
	return global_var;
}

LLVMValueRef codegen_var_decl(CodegenLLVM *cg, ASTNode *node, Symbol *table) {
	LLVMTypeRef ty = map_to_llvm(cg, node->data.var_decl.type, table);
	LLVMValueRef ptr = LLVMBuildAlloca(cg->builder, ty, node->data.var_decl.resolved_name);
	if (node->data.var_decl.init) {
		PassContext ctx = {0};
		LLVMValueRef val = codegen_ast(cg, node->data.var_decl.init, table, ctx);
		LLVMBuildStore(cg->builder, val, ptr);
	}
	return ptr;
}

LLVMValueRef codegen_function(CodegenLLVM *cg, ASTNode *node, Symbol *table) {
	const char *func_name = node->data.func_decl.name;
	size_t func_name_len = strlen(func_name);
	const char *linkage_name = func_name;
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
			LLVMValueRef ptr = LLVMBuildAlloca(cg->builder, ty, curr_param->data.param_decl.name);
			LLVMBuildStore(cg->builder, args[index], ptr);
			// if (cg->should_build_debug) {
			// 	int name_len = strlen(curr_param->data.param_decl.name);
			// 	LLVMDIBuilderCreateParameterVariable(cg->di_builder, (LLVMMetadataRef)cg->di_cu, curr_param->data.param_decl.name, name_len, index, cg->di_file, curr_param->location.line, args_types[index], 1, 0);
			// }
			curr_param = curr_param->next;
			++index;
		}
	}
	PassContext ctx = {0};
	codegen_ast(cg, node->data.func_decl.body, table, ctx);
	if (should_free_linkage_name)
		free(linkage_name);
	return fn;
}

LLVMValueRef codegen_ast(CodegenLLVM *cg, ASTNode *node, Symbol *table, PassContext ctx) {
	switch (node->type) {
	case AST_FN_DECL:
		return codegen_function(cg, node, table);
	case AST_VAR_DECL:
		return codegen_var_decl(cg, node, table);
		break;
	case AST_STRUCT_DECL: {
		LLVMTypeRef type = codegen_struct_decl(cg, node, table);
		break;
	}
	case AST_ARRAY_LITERAL:
	case AST_STRUCT_LITERAL:
	case AST_STRING_LIT:
	case AST_CHAR_LIT:
	case AST_EXPR_LITERAL:
		return codegen_literal(cg, node, ctx.expected_type, table, ctx.is_global);
	case AST_FIELD_DECL:
	case AST_BLOCK:
	case AST_EXPR_IDENT:
	case AST_RETURN:
	case AST_BINARY_EXPR:
	case AST_UNARY_EXPR:
	case AST_ARRAY_ACCESS:
	case AST_ASSIGNMENT:
	case AST_FN_CALL:
	case AST_MEMBER_ACCESS:
	case AST_ENUM_DECL:
	case AST_ENUM_VALUE:
	case AST_EXTERN_BLOCK:
	case AST_EXTERN_FUNC_DECL:
	case AST_IF_STMT:
	case AST_FOR_LOOP:
	case AST_WHILE_LOOP:
	case AST_DEFER_BLOCK:
	case AST_DEFERRED_SEQUENCE:
	case AST_FN_PTR:
	case AST_CONTINUE:
	case AST_BREAK:
	case AST_CAST:
	case AST_UNION_DECL:
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
			PassContext ctx = {1};
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
