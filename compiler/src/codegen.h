#pragma once

#include "parser.h"
#include <llvm-c/Core.h>
#include <llvm-c/Types.h>

typedef struct {
	const char *module_name;
	const char *filename;
	const char *dir;
	int should_build_debug;
} CodegenInitContext;

typedef struct {
	int should_build_debug;
	int current_scope;
	LLVMContextRef llvm_context;
	LLVMModuleRef module;
	LLVMBuilderRef builder;
	LLVMDIBuilderRef di_builder;
	LLVMMetadataRef di_file;
	LLVMMetadataRef di_cu;
} CodegenLLVM;

CodegenLLVM codegen_init(CodegenInitContext *init_params);

void codegen_deinit(CodegenLLVM *cg);

void codegen_run(CodegenLLVM* cg, ASTNode* root, Symbol* table);

char* codegen_output_str(CodegenLLVM* cg);
