#pragma once

#include "hashmap.h"
#include "parser.h"
#include "util.h"
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
	LLVMContextRef llvm_context;
	LLVMModuleRef module;
	LLVMBuilderRef builder;
	LLVMDIBuilderRef di_builder;
	LLVMMetadataRef di_file;
	LLVMMetadataRef di_cu;
	// NULL when should_build_debug is 0.
	hashmap_t *ditype_cache;
} CodegenLLVM;

// Initialize the native LLVM target / asm printer. Call once on the
// main thread before any codegen_emit_object_file. Safe to call multiple
// times.
CompilerResult codegen_init_native_target(void);

CodegenLLVM codegen_init(CodegenInitContext *init_params);

void codegen_deinit(CodegenLLVM *cg);

void codegen_run(CodegenLLVM *cg, ASTNode *root, Symbol *table);

char *codegen_output_str(CodegenLLVM *cg);

// Emit a native object file for cg's module to `path`. On failure,
// reports through diag_stream() and returns RESULT_FAILURE.
CompilerResult codegen_emit_object_file(CodegenLLVM *cg, const char *path);
