#include "codegen.h"
#include "symbol_table.h"
#include "types.h"

#include <assert.h>
#include <llvm-c/Core.h>
#include <llvm-c/DebugInfo.h>
#include <llvm-c/Types.h>
#include <stdio.h>
#include <string.h>

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

LLVMValueRef codegen_ast(CodegenLLVM *cg, ASTNode *node, Symbol *stable);

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
	LLVMTypeRef fn_ty = map_to_llvm(cg, sym->type, table);
	LLVMValueRef fn = LLVMAddFunction(cg->module, func_name, fn_ty);
	if (cg->should_build_debug) {
		LLVMMetadataRef di_fn = LLVMDIBuilderCreateFunction(cg->di_builder, (LLVMMetadataRef)cg->di_cu, func_name, func_name_len, linkage_name, linkage_name_len, cg->di_file, 0, NULL, 0, 1, 1, 0, 0);
		LLVMSetSubprogram(fn, di_fn);
	}
	LLVMBasicBlockRef entry = LLVMAppendBasicBlockInContext(cg->llvm_context, fn, "entry");
	LLVMPositionBuilderAtEnd(cg->builder, entry);
	codegen_ast(cg, node->data.func_decl.body, table);
	if (should_free_linkage_name)
		free(linkage_name);
	return fn;
}

LLVMValueRef codegen_ast(CodegenLLVM *cg, ASTNode *node, Symbol *table) {
	switch (node->type) {
	case AST_FN_DECL:
		return codegen_function(cg, node, table);
	default:
		return NULL;
	}
}

void codegen_run(CodegenLLVM *cg, ASTNode *root, Symbol *table) {
	ASTNode *current = root;
	while (current) {
		codegen_ast(cg, current, table);
		current = current->next;
	}
}

char *codegen_output_str(CodegenLLVM *cg) {
	if (cg->should_build_debug) {
		LLVMDIBuilderFinalize(cg->di_builder);
	}
	return LLVMPrintModuleToString(cg->module);
}
