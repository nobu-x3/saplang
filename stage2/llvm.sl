// Bindings against LLVM 19's C API (libLLVM-19). Opaque handles are void*.
// This is the subset the codegen shell needs: types, decls, terminators,
// target machine + object emission, and module-to-string for tests. The
// full instruction surface arrives with instruction translation.

extern {
    // context / module / builder
    export fn void* LLVMContextCreate();
    export fn void  LLVMContextDispose(void* ctx);
    export fn void* LLVMModuleCreateWithNameInContext(const i8* module_id, void* ctx);
    export fn void  LLVMDisposeModule(void* m);
    export fn void* LLVMCreateBuilderInContext(void* ctx);
    export fn void  LLVMDisposeBuilder(void* b);
    export fn i8*   LLVMPrintModuleToString(void* m);
    export fn i32   LLVMPrintModuleToFile(void* m, const i8* filename, i8** err);

    // types
    export fn void* LLVMInt1TypeInContext(void* ctx);
    export fn void* LLVMInt8TypeInContext(void* ctx);
    export fn void* LLVMInt16TypeInContext(void* ctx);
    export fn void* LLVMInt32TypeInContext(void* ctx);
    export fn void* LLVMInt64TypeInContext(void* ctx);
    export fn void* LLVMFloatTypeInContext(void* ctx);
    export fn void* LLVMDoubleTypeInContext(void* ctx);
    export fn void* LLVMVoidTypeInContext(void* ctx);
    export fn void* LLVMPointerTypeInContext(void* ctx, u32 address_space);
    export fn void* LLVMArrayType2(void* element, u64 count);
    export fn void* LLVMStructTypeInContext(void* ctx, void** element_types, u32 count, i32 packed);
    export fn void* LLVMStructCreateNamed(void* ctx, const i8* name);
    export fn void  LLVMStructSetBody(void* struct_ty, void** element_types, u32 count, i32 packed);
    export fn void* LLVMFunctionType(void* ret, void** param_types, u32 param_count, i32 is_var_arg);

    // values / globals / constants
    export fn void* LLVMAddFunction(void* m, const i8* name, void* fn_ty);
    export fn void* LLVMAddGlobal(void* m, void* ty, const i8* name);
    export fn void* LLVMGetParam(void* fn_val, u32 index);
    export fn void* LLVMConstInt(void* int_ty, u64 value, i32 sign_extend);
    export fn void* LLVMConstReal(void* real_ty, f64 value);
    export fn void* LLVMConstNull(void* ty);
    export fn void* LLVMGetUndef(void* ty);
    export fn void  LLVMSetInitializer(void* global, void* const_val);
    export fn void  LLVMSetLinkage(void* global, i32 linkage);
    export fn void  LLVMSetGlobalConstant(void* global, i32 is_const);

    // basic blocks + terminators (the rest of the builders land with step 9)
    export fn void* LLVMAppendBasicBlockInContext(void* ctx, void* fn_val, const i8* name);
    export fn void  LLVMPositionBuilderAtEnd(void* b, void* block);
    export fn void* LLVMBuildRet(void* b, void* v);
    export fn void* LLVMBuildRetVoid(void* b);
    export fn void* LLVMBuildBr(void* b, void* dest);
    export fn void* LLVMBuildUnreachable(void* b);

    // target / emission
    export fn void  LLVMInitializeX86TargetInfo();
    export fn void  LLVMInitializeX86Target();
    export fn void  LLVMInitializeX86TargetMC();
    export fn void  LLVMInitializeX86AsmPrinter();
    export fn i8*   LLVMGetDefaultTargetTriple();
    export fn i32   LLVMGetTargetFromTriple(const i8* triple, void** target_out, i8** err);
    export fn void* LLVMCreateTargetMachine(void* target, const i8* triple, const i8* cpu, const i8* features, i32 opt_level, i32 reloc, i32 code_model);
    export fn void  LLVMDisposeTargetMachine(void* tm);
    export fn i32   LLVMTargetMachineEmitToFile(void* tm, void* m, const i8* filename, i32 file_type, i8** err);
    export fn i32   LLVMVerifyModule(void* m, i32 action, i8** err);
    export fn void  LLVMDisposeMessage(i8* msg);

    // in-process execution (MCJIT) — runs a module without an external linker
    export fn void  LLVMLinkInMCJIT();
    export fn i32   LLVMCreateExecutionEngineForModule(void** ee_out, void* m, i8** err);
    export fn void  LLVMDisposeExecutionEngine(void* ee);
    export fn u64   LLVMGetFunctionAddress(void* ee, const i8* name);
    export fn void  LLVMInitializeX86AsmParser();
}

// LLVMLinkage
export const i32 ExternalLinkage    = 0;
export const i32 LinkOnceODRLinkage = 3;
export const i32 InternalLinkage    = 8;

// LLVMVerifierFailureAction
export const i32 ReturnStatusAction = 2;

// LLVMCodeGenFileType
export const i32 ObjectFile = 1;

// LLVMCodeGenOptLevel
export const i32 CodeGenLevelNone = 0;
export const i32 CodeGenLevelDefault = 2;

// LLVMRelocMode
export const i32 RelocPIC = 2;

// LLVMCodeModel
export const i32 CodeModelDefault = 0;
