// The LLVM backend: translates a SapirModule into an LLVM module, then either
// emits an object file or JIT-runs it in-process. Imports sapir + types only
// (never ast/cfg/sema/module) — everything a backend needs is materialized in
// the SapirModule by lower.sl. Aggregate types and the full opcode set land
// with instruction translation; this shell covers scalars and terminators.

import sapir;
import types;
import interner;
import llvm;
import arena;
import sys;

struct TypeMapEntry {
    types::Type* ty;
    void*        llvm;
}

struct CG {
    sapir::SapirModule* sm;
    arena::Arena*       arena;
    void*               ctx;
    void*               llvm_module;
    void*               builder;
    bool                failed;

    void**              decl_map;       // decl index -> LLVMValueRef (function / global)
    TypeMapEntry[]      type_map;       // Type* -> LLVMTypeRef
    u64                 type_map_cap;

    // Per-function, reset by emit_fn.
    sapir::SapirFn*     f;
    void*               current_fn;
    void**              value_map;      // inst id -> LLVMValueRef
    void**              block_map;      // sapir block id -> LLVMBasicBlockRef
}

// Builds the LLVM module and emits it to obj_path as an object file. Returns 0 on success.
export fn i32 emit_object(sapir::SapirModule* sm, arena::Arena* a, i8* obj_path) {
    CG cg;
    cg_init(&cg, sm, a);
    if(!build_module(&cg)) { return 1; }

    llvm::LLVMInitializeX86TargetInfo();
    llvm::LLVMInitializeX86Target();
    llvm::LLVMInitializeX86TargetMC();
    llvm::LLVMInitializeX86AsmPrinter();

    i8* triple = llvm::LLVMGetDefaultTargetTriple();
    void* target = null;
    i8* err = null;
    if(llvm::LLVMGetTargetFromTriple(triple, &target, &err) != 0) {
        sys::dprintf(2, "codegen: no target for triple: %s\n", err);
        llvm::LLVMDisposeMessage(err);
        return 1;
    }
    void* tm = llvm::LLVMCreateTargetMachine(target, triple, "generic", "", llvm::CodeGenLevelDefault, llvm::RelocPIC, llvm::CodeModelDefault);
    i32 rc = 0;
    if(llvm::LLVMTargetMachineEmitToFile(tm, cg.llvm_module, obj_path, llvm::ObjectFile, &err) != 0) {
        sys::dprintf(2, "codegen: object emission failed: %s\n", err);
        llvm::LLVMDisposeMessage(err);
        rc = 1;
    }
    llvm::LLVMDisposeTargetMachine(tm);
    return rc;
}

// Builds the module and JIT-runs main() in-process (no external linker). Returns main's exit code, or -1 on failure.
export fn i32 jit_run_main(sapir::SapirModule* sm, arena::Arena* a) {
    CG cg;
    cg_init(&cg, sm, a);
    if(!build_module(&cg)) { return -1; }

    llvm::LLVMLinkInMCJIT();
    llvm::LLVMInitializeX86TargetInfo();
    llvm::LLVMInitializeX86Target();
    llvm::LLVMInitializeX86TargetMC();
    llvm::LLVMInitializeX86AsmPrinter();
    llvm::LLVMInitializeX86AsmParser();

    void* ee = null;
    i8* err = null;
    if(llvm::LLVMCreateExecutionEngineForModule(&ee, cg.llvm_module, &err) != 0) {
        sys::dprintf(2, "codegen: could not create execution engine: %s\n", err);
        llvm::LLVMDisposeMessage(err);
        return -1;
    }
    u64 addr = llvm::LLVMGetFunctionAddress(ee, "main");
    if(addr == 0) {
        sys::dprintf(2, "codegen: no main symbol to run\n");
        llvm::LLVMDisposeExecutionEngine(ee);
        return -1;
    }
    fn* i32() main_fn;
    sys::memcpy(&main_fn, &addr, sizeof(void*));
    i32 result = main_fn();
    llvm::LLVMDisposeExecutionEngine(ee);
    return result;
}

fn void cg_init(CG* cg, sapir::SapirModule* sm, arena::Arena* a) {
    sys::memset(cg, 0, sizeof(CG));
    cg.sm = sm;
    cg.arena = a;
    cg.ctx = llvm::LLVMContextCreate();
    cg.llvm_module = llvm::LLVMModuleCreateWithNameInContext(cstr(a, interner::symbol_str(sm.name)), cg.ctx);
    cg.builder = llvm::LLVMCreateBuilderInContext(cg.ctx);
    cg.decl_map = (void**)arena::alloc(a, (sm.decls.len + 1) * sizeof(void*));
}

fn bool build_module(CG* cg) {
    for(u64 i = 0; i < cg.sm.decls.len; i += 1) { declare_decl(cg, (u32)i); }
    for(u64 i = 0; i < cg.sm.globals.len; i += 1) { init_global(cg, &cg.sm.globals[i]); }
    for(u64 i = 0; i < cg.sm.fns.len; i += 1) { emit_fn(cg, &cg.sm.fns[i]); }
    if(cg.failed) { return false; }
    i8* err = null;
    if(llvm::LLVMVerifyModule(cg.llvm_module, llvm::ReturnStatusAction, &err) != 0) {
        sys::dprintf(2, "codegen: LLVM verification failed:\n%s\n", err);
        llvm::LLVMDisposeMessage(err);
        return false;
    }
    return true;
}

// TYPES ///////////////////////////////////////////////////////////////////////////

fn void* map_type(CG* cg, types::Type* t) {
    void* hit = type_map_lookup(cg, t);
    if(hit != null) { return hit; }
    void* out;
    switch(t.kind) {
    case types::TypeKind::Primitive: { out = map_primitive(cg, t.prim); }
    case types::TypeKind::Pointer:   { out = llvm::LLVMPointerTypeInContext(cg.ctx, 0); }
    case types::TypeKind::FnPtr:     { out = llvm::LLVMPointerTypeInContext(cg.ctx, 0); }
    case types::TypeKind::Array:     { out = llvm::LLVMArrayType2(map_type(cg, t.data.array.elem), t.data.array.count); }
    case types::TypeKind::Slice:     { out = slice_struct_type(cg); }
    case types::TypeKind::Enum:      { out = map_type(cg, types::enum_base_type(t)); }
    else {
        sys::dprintf(2, "codegen: aggregate type codegen is not implemented yet (instruction-translation milestone)\n");
        cg.failed = true;
        out = llvm::LLVMInt8TypeInContext(cg.ctx);
    }
    }
    type_map_insert(cg, t, out);
    return out;
}

fn void* map_primitive(CG* cg, types::PrimitiveKind p) {
    switch(p) {
    case types::PrimitiveKind::I8:   { return llvm::LLVMInt8TypeInContext(cg.ctx); }
    case types::PrimitiveKind::U8:   { return llvm::LLVMInt8TypeInContext(cg.ctx); }
    case types::PrimitiveKind::I16:  { return llvm::LLVMInt16TypeInContext(cg.ctx); }
    case types::PrimitiveKind::U16:  { return llvm::LLVMInt16TypeInContext(cg.ctx); }
    case types::PrimitiveKind::I32:  { return llvm::LLVMInt32TypeInContext(cg.ctx); }
    case types::PrimitiveKind::U32:  { return llvm::LLVMInt32TypeInContext(cg.ctx); }
    case types::PrimitiveKind::I64:  { return llvm::LLVMInt64TypeInContext(cg.ctx); }
    case types::PrimitiveKind::U64:  { return llvm::LLVMInt64TypeInContext(cg.ctx); }
    case types::PrimitiveKind::F32:  { return llvm::LLVMFloatTypeInContext(cg.ctx); }
    case types::PrimitiveKind::F64:  { return llvm::LLVMDoubleTypeInContext(cg.ctx); }
    case types::PrimitiveKind::BOOL: { return llvm::LLVMInt1TypeInContext(cg.ctx); }
    case types::PrimitiveKind::VOID: { return llvm::LLVMVoidTypeInContext(cg.ctx); }
    else { return llvm::LLVMVoidTypeInContext(cg.ctx); }
    }
    return llvm::LLVMVoidTypeInContext(cg.ctx);
}

fn void* slice_struct_type(CG* cg) {
    void*[2] fields;
    fields[0] = llvm::LLVMPointerTypeInContext(cg.ctx, 0);
    fields[1] = llvm::LLVMInt64TypeInContext(cg.ctx);
    return llvm::LLVMStructTypeInContext(cg.ctx, &fields[0], 2, 0);
}

fn void* map_fn_type(CG* cg, types::Type* fnty) {
    types::Type*[] params = fnty.data.fn_ptr.params;
    void** llvm_params = (void**)arena::alloc(cg.arena, (params.len + 1) * sizeof(void*));
    for(u64 i = 0; i < params.len; i += 1) { llvm_params[i] = map_type(cg, params[i]); }
    void* ret = map_type(cg, fnty.data.fn_ptr.ret);
    i32 variadic = 0;
    if(fnty.data.fn_ptr.is_variadic) { variadic = 1; }
    return llvm::LLVMFunctionType(ret, llvm_params, (u32)params.len, variadic);
}

fn void* type_map_lookup(CG* cg, types::Type* t) {
    for(u64 i = 0; i < cg.type_map.len; i += 1) {
        if(cg.type_map[i].ty == t) { return cg.type_map[i].llvm; }
    }
    return null;
}

fn void type_map_insert(CG* cg, types::Type* t, void* llvm_ty) {
    if(cg.type_map.len == cg.type_map_cap) {
        u64 new_cap = 16;
        if(cg.type_map_cap > 0) { new_cap = cg.type_map_cap * 2; }
        cg.type_map.ptr = (TypeMapEntry*)arena::realloc_grow(cg.arena, (void*)cg.type_map.ptr, cg.type_map.len * sizeof(TypeMapEntry), new_cap * sizeof(TypeMapEntry));
        cg.type_map_cap = new_cap;
    }
    cg.type_map[cg.type_map.len].ty = t;
    cg.type_map[cg.type_map.len].llvm = llvm_ty;
    cg.type_map.len += 1;
}

// DECLS + GLOBALS ///////////////////////////////////////////////////////////////////

fn void declare_decl(CG* cg, u32 index) {
    sapir::SapirDecl* d = &cg.sm.decls[index];
    if(d.kind == sapir::SapirDeclKind::Fn) {
        void* fn_ty = map_fn_type(cg, d.ty);
        void* val = llvm::LLVMAddFunction(cg.llvm_module, cstr(cg.arena, d.link_name), fn_ty);
        llvm::LLVMSetLinkage(val, decl_linkage(d));
        cg.decl_map[index] = val;
    } else {
        void* ty = map_type(cg, d.ty);
        void* val = llvm::LLVMAddGlobal(cg.llvm_module, ty, cstr(cg.arena, d.link_name));
        llvm::LLVMSetLinkage(val, decl_linkage(d));
        cg.decl_map[index] = val;
    }
}

// main is the program entry: it must be externally visible regardless of its Saplang linkage.
fn i32 decl_linkage(sapir::SapirDecl* d) {
    if(slice_eq(d.link_name, "main")) { return llvm::ExternalLinkage; }
    switch(d.linkage) {
    case sapir::SapirLinkage::Export:      { return llvm::ExternalLinkage; }
    case sapir::SapirLinkage::Internal:    { return llvm::InternalLinkage; }
    case sapir::SapirLinkage::LinkOnceOdr: { return llvm::LinkOnceODRLinkage; }
    case sapir::SapirLinkage::Foreign:     { return llvm::ExternalLinkage; }
    else { return llvm::ExternalLinkage; }
    }
    return llvm::ExternalLinkage;
}

fn void init_global(CG* cg, sapir::SapirGlobal* g) {
    void* gv = cg.decl_map[g.decl_index];
    llvm::LLVMSetInitializer(gv, const_value(cg, &g.init));
    if(g.is_const) { llvm::LLVMSetGlobalConstant(gv, 1); }
}

fn void* const_value(CG* cg, sapir::ConstInit* ci) {
    switch(ci.kind) {
    case sapir::ConstInitKind::Zero:  { return llvm::LLVMConstNull(map_type(cg, ci.ty)); }
    case sapir::ConstInitKind::Int:   { return llvm::LLVMConstInt(map_type(cg, ci.ty), (u64)ci.i, 0); }
    case sapir::ConstInitKind::Bool:  { return llvm::LLVMConstInt(llvm::LLVMInt1TypeInContext(cg.ctx), (u64)ci.i, 0); }
    case sapir::ConstInitKind::Float: { return llvm::LLVMConstReal(map_type(cg, ci.ty), ci.f); }
    case sapir::ConstInitKind::Null:  { return llvm::LLVMConstNull(map_type(cg, ci.ty)); }
    case sapir::ConstInitKind::FnRef: { return cg.decl_map[ci.decl_index]; }
    else {
        sys::dprintf(2, "codegen: aggregate/string constant initializers are not implemented yet\n");
        cg.failed = true;
        return llvm::LLVMConstNull(map_type(cg, ci.ty));
    }
    }
    return llvm::LLVMConstNull(map_type(cg, ci.ty));
}

// FUNCTIONS + INSTRUCTIONS ///////////////////////////////////////////////////////////

fn void emit_fn(CG* cg, sapir::SapirFn* f) {
    cg.f = f;
    cg.current_fn = cg.decl_map[f.decl_index];
    cg.value_map = (void**)arena::alloc(cg.arena, (f.insts.len + 1) * sizeof(void*));
    cg.block_map = (void**)arena::alloc(cg.arena, (f.blocks.len + 1) * sizeof(void*));
    for(u64 i = 0; i < f.blocks.len; i += 1) {
        cg.block_map[i] = llvm::LLVMAppendBasicBlockInContext(cg.ctx, cg.current_fn, "");
    }
    for(u64 i = 0; i < f.blocks.len; i += 1) {
        sapir::SapirBlock* b = &f.blocks[i];
        llvm::LLVMPositionBuilderAtEnd(cg.builder, cg.block_map[i]);
        for(u32 id = b.body_start; id < b.body_end; id += 1) {
            if(f.insts[id].op == sapir::Opcode::Phi) { continue; }
            emit_inst(cg, id);
        }
    }
}

fn void emit_inst(CG* cg, u32 id) {
    sapir::Inst* inst = &cg.f.insts[id];
    switch(inst.op) {
    case sapir::Opcode::ConstInt:  { cg.value_map[id] = llvm::LLVMConstInt(map_type(cg, inst.ty), inst.imm, 0); }
    case sapir::Opcode::ConstBool: { cg.value_map[id] = llvm::LLVMConstInt(llvm::LLVMInt1TypeInContext(cg.ctx), inst.imm, 0); }
    case sapir::Opcode::ConstNull: { cg.value_map[id] = llvm::LLVMConstNull(map_type(cg, inst.ty)); }
    case sapir::Opcode::Undef:     { cg.value_map[id] = llvm::LLVMGetUndef(map_type(cg, inst.ty)); }
    case sapir::Opcode::Param:     { cg.value_map[id] = llvm::LLVMGetParam(cg.current_fn, inst.a); }
    case sapir::Opcode::Ret: {
        if(inst.a == sapir::INVALID_ID) { llvm::LLVMBuildRetVoid(cg.builder); }
        else { llvm::LLVMBuildRet(cg.builder, cg.value_map[inst.a]); }
    }
    case sapir::Opcode::Br:          { llvm::LLVMBuildBr(cg.builder, cg.block_map[inst.a]); }
    case sapir::Opcode::Unreachable: { llvm::LLVMBuildUnreachable(cg.builder); }
    else {
        sys::dprintf(2, "codegen: opcode %d is not translated yet (instruction-translation milestone)\n", (i32)inst.op);
        cg.failed = true;
    }
    }
}

// HELPERS ////////////////////////////////////////////////////////////////////////////

fn i8* cstr(arena::Arena* a, u8[] bytes) {
    i8* out = (i8*)arena::alloc(a, bytes.len + 1);
    for(u64 i = 0; i < bytes.len; i += 1) { out[i] = (i8)bytes[i]; }
    out[bytes.len] = 0;
    return out;
}

fn bool slice_eq(u8[] a, u8[] b) {
    if(a.len != b.len) { return false; }
    for(u64 i = 0; i < a.len; i += 1) {
        if(a[i] != b[i]) { return false; }
    }
    return true;
}
