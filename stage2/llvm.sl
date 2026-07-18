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

    // optimization (new pass manager)
    export fn void* LLVMCreatePassBuilderOptions();
    export fn void  LLVMDisposePassBuilderOptions(void* options);
    export fn void* LLVMRunPasses(void* m, const i8* passes, void* tm, void* options);
    export fn void  LLVMConsumeError(void* err);

    // attributes (for sanitize_address instrumentation)
    export fn u32   LLVMGetEnumAttributeKindForName(const i8* name, u64 len);
    export fn void* LLVMCreateEnumAttribute(void* ctx, u32 kind_id, u64 val);
    export fn void  LLVMAddAttributeAtIndex(void* fn_val, u32 idx, void* attr);

    // in-process execution (MCJIT) — runs a module without an external linker
    export fn void  LLVMLinkInMCJIT();
    export fn i32   LLVMCreateExecutionEngineForModule(void** ee_out, void* m, i8** err);
    export fn void  LLVMDisposeExecutionEngine(void* ee);
    export fn u64   LLVMGetFunctionAddress(void* ee, const i8* name);
    export fn void  LLVMInitializeX86AsmParser();

    // arithmetic / bitwise
    export fn void* LLVMBuildAdd(void* b, void* l, void* r, const i8* name);
    export fn void* LLVMBuildSub(void* b, void* l, void* r, const i8* name);
    export fn void* LLVMBuildMul(void* b, void* l, void* r, const i8* name);
    export fn void* LLVMBuildSDiv(void* b, void* l, void* r, const i8* name);
    export fn void* LLVMBuildUDiv(void* b, void* l, void* r, const i8* name);
    export fn void* LLVMBuildSRem(void* b, void* l, void* r, const i8* name);
    export fn void* LLVMBuildURem(void* b, void* l, void* r, const i8* name);
    export fn void* LLVMBuildFAdd(void* b, void* l, void* r, const i8* name);
    export fn void* LLVMBuildFSub(void* b, void* l, void* r, const i8* name);
    export fn void* LLVMBuildFMul(void* b, void* l, void* r, const i8* name);
    export fn void* LLVMBuildFDiv(void* b, void* l, void* r, const i8* name);
    export fn void* LLVMBuildFRem(void* b, void* l, void* r, const i8* name);
    export fn void* LLVMBuildAnd(void* b, void* l, void* r, const i8* name);
    export fn void* LLVMBuildOr(void* b, void* l, void* r, const i8* name);
    export fn void* LLVMBuildXor(void* b, void* l, void* r, const i8* name);
    export fn void* LLVMBuildShl(void* b, void* l, void* r, const i8* name);
    export fn void* LLVMBuildLShr(void* b, void* l, void* r, const i8* name);
    export fn void* LLVMBuildAShr(void* b, void* l, void* r, const i8* name);
    export fn void* LLVMBuildNeg(void* b, void* v, const i8* name);
    export fn void* LLVMBuildFNeg(void* b, void* v, const i8* name);
    export fn void* LLVMBuildNot(void* b, void* v, const i8* name);
    export fn void* LLVMBuildICmp(void* b, i32 predicate, void* l, void* r, const i8* name);
    export fn void* LLVMBuildFCmp(void* b, i32 predicate, void* l, void* r, const i8* name);

    // memory
    export fn void* LLVMBuildAlloca(void* b, void* ty, const i8* name);
    export fn void* LLVMBuildLoad2(void* b, void* ty, void* ptr, const i8* name);
    export fn void* LLVMBuildStore(void* b, void* val, void* ptr);
    export fn void* LLVMBuildMemCpy(void* b, void* dst, u32 dst_align, void* src, u32 src_align, void* size);
    export fn void* LLVMBuildMemSet(void* b, void* ptr, void* val, void* len, u32 align);
    export fn void* LLVMBuildGEP2(void* b, void* ty, void* ptr, void** indices, u32 num_indices, const i8* name);
    export fn void* LLVMBuildStructGEP2(void* b, void* ty, void* ptr, u32 idx, const i8* name);
    export fn void* LLVMBuildExtractValue(void* b, void* agg, u32 index, const i8* name);
    export fn void* LLVMBuildInsertValue(void* b, void* agg, void* elt, u32 index, const i8* name);

    // conversions
    export fn void* LLVMBuildTrunc(void* b, void* v, void* dst_ty, const i8* name);
    export fn void* LLVMBuildZExt(void* b, void* v, void* dst_ty, const i8* name);
    export fn void* LLVMBuildSExt(void* b, void* v, void* dst_ty, const i8* name);
    export fn void* LLVMBuildFPToUI(void* b, void* v, void* dst_ty, const i8* name);
    export fn void* LLVMBuildFPToSI(void* b, void* v, void* dst_ty, const i8* name);
    export fn void* LLVMBuildUIToFP(void* b, void* v, void* dst_ty, const i8* name);
    export fn void* LLVMBuildSIToFP(void* b, void* v, void* dst_ty, const i8* name);
    export fn void* LLVMBuildFPTrunc(void* b, void* v, void* dst_ty, const i8* name);
    export fn void* LLVMBuildFPExt(void* b, void* v, void* dst_ty, const i8* name);
    export fn void* LLVMBuildPtrToInt(void* b, void* v, void* dst_ty, const i8* name);
    export fn void* LLVMBuildIntToPtr(void* b, void* v, void* dst_ty, const i8* name);
    export fn void* LLVMBuildBitCast(void* b, void* v, void* dst_ty, const i8* name);

    // calls / phis / branches / string constants
    export fn void* LLVMBuildCall2(void* b, void* fn_ty, void* fn_val, void** args, u32 num_args, const i8* name);
    export fn void* LLVMBuildPhi(void* b, void* ty, const i8* name);
    export fn void  LLVMAddIncoming(void* phi, void** values, void** blocks, u32 count);
    export fn void* LLVMBuildCondBr(void* b, void* cond, void* then_bb, void* else_bb);
    export fn void* LLVMBuildSwitch(void* b, void* v, void* else_bb, u32 num_cases);
    export fn void  LLVMAddCase(void* switch_inst, void* on_val, void* dest);
    export fn void* LLVMConstStringInContext2(void* ctx, const i8* str, u64 length, i32 dont_null_terminate);
    export fn void  LLVMSetUnnamedAddress(void* global, i32 unnamed_addr);
    export fn void* LLVMTypeOf(void* val);
    export fn void* LLVMGetFirstInstruction(void* bb);
    export fn void  LLVMPositionBuilder(void* b, void* bb, void* instr);
    export fn void* LLVMConstNamedStruct(void* struct_ty, void** vals, u32 count);
    export fn void* LLVMConstArray2(void* elem_ty, void** vals, u64 length);

    // debug info (DWARF via DIBuilder)
    export fn void* LLVMCreateDIBuilder(void* m);
    export fn void  LLVMDIBuilderFinalize(void* builder);
    export fn void* LLVMDIBuilderCreateFile(void* builder, const i8* filename, u64 filename_len, const i8* dir, u64 dir_len);
    export fn void* LLVMDIBuilderCreateCompileUnit(void* builder, i32 lang, void* file, const i8* producer, u64 producer_len, i32 is_optimized, const i8* flags, u64 flags_len, u32 runtime_ver, const i8* split_name, u64 split_name_len, i32 kind, u32 dwo_id, i32 split_debug_inlining, i32 debug_info_for_profiling, const i8* sysroot, u64 sysroot_len, const i8* sdk, u64 sdk_len);
    export fn void* LLVMDIBuilderCreateFunction(void* builder, void* scope, const i8* name, u64 name_len, const i8* linkage, u64 linkage_len, void* file, u32 line, void* ty, i32 is_local, i32 is_definition, u32 scope_line, i32 flags, i32 is_optimized);
    export fn void* LLVMDIBuilderCreateSubroutineType(void* builder, void* file, void** param_types, u32 num_params, i32 flags);
    export fn void* LLVMDIBuilderCreateBasicType(void* builder, const i8* name, u64 name_len, u64 size_bits, u32 encoding, i32 flags);
    export fn void* LLVMDIBuilderCreatePointerType(void* builder, void* pointee, u64 size_bits, u32 align_bits, u32 address_space, const i8* name, u64 name_len);
    export fn void* LLVMDIBuilderCreateDebugLocation(void* ctx, u32 line, u32 col, void* scope, void* inlined_at);
    export fn void  LLVMSetSubprogram(void* fn_val, void* sp);
    export fn void  LLVMSetCurrentDebugLocation2(void* builder, void* loc);
    export fn void  LLVMAddModuleFlag(void* m, i32 behavior, const i8* key, u64 key_len, void* val);
    export fn void* LLVMValueAsMetadata(void* val);
}

// DWARF constants
export const i32 DWARFSourceLanguageC = 1;
export const i32 DWARFEmissionFull = 1;
export const i32 ModuleFlagBehaviorWarning = 1;
export const u32 DW_ATE_boolean = 2;
export const u32 DW_ATE_float = 4;
export const u32 DW_ATE_signed = 5;
export const u32 DW_ATE_unsigned = 7;

// LLVMIntPredicate
export const i32 IntEQ = 32;
export const i32 IntNE = 33;
export const i32 IntUGT = 34;
export const i32 IntUGE = 35;
export const i32 IntULT = 36;
export const i32 IntULE = 37;
export const i32 IntSGT = 38;
export const i32 IntSGE = 39;
export const i32 IntSLT = 40;
export const i32 IntSLE = 41;

// LLVMRealPredicate (ordered)
export const i32 RealOEQ = 1;
export const i32 RealOGT = 2;
export const i32 RealOGE = 3;
export const i32 RealOLT = 4;
export const i32 RealOLE = 5;
export const i32 RealONE = 6;

// LLVMUnnamedAddr
export const i32 GlobalUnnamedAddr = 2;

// LLVMAttributeFunctionIndex (-1 as u32)
export const u32 AttributeFunctionIndex = 4294967295;

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
