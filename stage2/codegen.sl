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
    i8*                 empty;          // "" reused as the name argument for unnamed values
    bool                failed;

    void**              decl_map;       // decl index -> LLVMValueRef (function / global)
    TypeMapEntry[]      type_map;       // Type* -> LLVMTypeRef
    u64                 type_map_cap;

    // Per-function, reset by emit_fn.
    sapir::SapirFn*     f;
    void*               current_fn;
    void*               current_block;  // LLVMBasicBlockRef currently being built
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
    cg.empty = cstr(a, "");
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
    case types::TypeKind::Struct: {
        out = llvm::LLVMStructCreateNamed(cg.ctx, cg.empty);
        type_map_insert(cg, t, out);        // install before the body so a T* field self-ref hits the cache
        fill_struct_body(cg, t, out);
        return out;
    }
    case types::TypeKind::Union:     { out = union_blob_type(cg, t); }
    else {
        sys::dprintf(2, "codegen: cannot map type kind %d\n", (i32)t.kind);
        cg.failed = true;
        out = llvm::LLVMInt8TypeInContext(cg.ctx);
    }
    }
    type_map_insert(cg, t, out);
    return out;
}

fn void fill_struct_body(CG* cg, types::Type* t, void* struct_ty) {
    types::Type*[] fields = types::struct_field_types(t, cg.arena);
    void** llvm_fields = (void**)arena::alloc(cg.arena, (fields.len + 1) * sizeof(void*));
    for(u64 i = 0; i < fields.len; i += 1) { llvm_fields[i] = map_type(cg, fields[i]); }
    llvm::LLVMStructSetBody(struct_ty, llvm_fields, (u32)fields.len, 0);
}

// A union lowers to a struct wrapping one [size x i8] payload; members are accessed through the base pointer.
fn void* union_blob_type(CG* cg, types::Type* t) {
    void*[1] fields;
    fields[0] = llvm::LLVMArrayType2(llvm::LLVMInt8TypeInContext(cg.ctx), (u64)t.size);
    return llvm::LLVMStructTypeInContext(cg.ctx, &fields[0], 1, 0);
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
    case sapir::ConstInitKind::Struct: {
        void** vals = (void**)arena::alloc(cg.arena, (ci.elems.len + 1) * sizeof(void*));
        for(u64 i = 0; i < ci.elems.len; i += 1) { vals[i] = const_value(cg, &ci.elems[i]); }
        return llvm::LLVMConstNamedStruct(map_type(cg, ci.ty), vals, (u32)ci.elems.len);
    }
    case sapir::ConstInitKind::Array: {
        void** vals = (void**)arena::alloc(cg.arena, (ci.elems.len + 1) * sizeof(void*));
        for(u64 i = 0; i < ci.elems.len; i += 1) { vals[i] = const_value(cg, &ci.elems[i]); }
        return llvm::LLVMConstArray2(map_type(cg, ci.ty.data.array.elem), vals, ci.elems.len);
    }
    else {
        sys::dprintf(2, "codegen: this constant initializer kind is not implemented yet\n");
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
        cg.block_map[i] = llvm::LLVMAppendBasicBlockInContext(cg.ctx, cg.current_fn, cg.empty);
    }
    for(u64 i = 0; i < f.blocks.len; i += 1) {
        sapir::SapirBlock* b = &f.blocks[i];
        cg.current_block = cg.block_map[i];
        llvm::LLVMPositionBuilderAtEnd(cg.builder, cg.current_block);
        for(u64 p = 0; p < b.phis.len; p += 1) {
            u32 phi_id = b.phis[p];
            cg.value_map[phi_id] = llvm::LLVMBuildPhi(cg.builder, map_type(cg, cg.f.insts[phi_id].ty), cg.empty);
        }
        for(u32 id = b.body_start; id < b.body_end; id += 1) {
            if(f.insts[id].op == sapir::Opcode::Phi) { continue; }
            emit_inst(cg, id);
        }
    }
    for(u64 i = 0; i < f.blocks.len; i += 1) {
        sapir::SapirBlock* b = &f.blocks[i];
        for(u64 p = 0; p < b.phis.len; p += 1) { fill_phi(cg, b.phis[p]); }
    }
}

fn void fill_phi(CG* cg, u32 phi_id) {
    sapir::Inst* inst = &cg.f.insts[phi_id];
    u32 count = cg.f.extra[inst.b];
    void** values = (void**)arena::alloc(cg.arena, ((u64)count + 1) * sizeof(void*));
    void** blocks = (void**)arena::alloc(cg.arena, ((u64)count + 1) * sizeof(void*));
    for(u32 k = 0; k < count; k += 1) {
        u32 pair_base = inst.b + 1 + k * 2;
        blocks[k] = cg.block_map[cg.f.extra[pair_base]];
        values[k] = cg.value_map[cg.f.extra[pair_base + 1]];
    }
    llvm::LLVMAddIncoming(cg.value_map[phi_id], values, blocks, count);
}

fn void emit_inst(CG* cg, u32 id) {
    sapir::Inst* inst = &cg.f.insts[id];
    switch(inst.op) {
    case sapir::Opcode::ConstInt:   { cg.value_map[id] = llvm::LLVMConstInt(map_type(cg, inst.ty), inst.imm, 0); }
    case sapir::Opcode::ConstFloat: { cg.value_map[id] = llvm::LLVMConstReal(map_type(cg, inst.ty), *(f64*)&inst.imm); }
    case sapir::Opcode::ConstBool:  { cg.value_map[id] = llvm::LLVMConstInt(llvm::LLVMInt1TypeInContext(cg.ctx), inst.imm, 0); }
    case sapir::Opcode::ConstNull:  { cg.value_map[id] = llvm::LLVMConstNull(map_type(cg, inst.ty)); }
    case sapir::Opcode::ConstStr:   { cg.value_map[id] = emit_const_str(cg, inst); }
    case sapir::Opcode::Undef:      { cg.value_map[id] = llvm::LLVMGetUndef(map_type(cg, inst.ty)); }
    case sapir::Opcode::Param:      { cg.value_map[id] = llvm::LLVMGetParam(cg.current_fn, inst.a); }

    case sapir::Opcode::Alloca:     { cg.value_map[id] = emit_alloca(cg, inst); }
    case sapir::Opcode::Zero: {
        void* i8_zero = llvm::LLVMConstInt(llvm::LLVMInt8TypeInContext(cg.ctx), 0, 0);
        void* len = llvm::LLVMConstInt(llvm::LLVMInt64TypeInContext(cg.ctx), inst.imm, 0);
        llvm::LLVMBuildMemSet(cg.builder, cg.value_map[inst.a], i8_zero, len, 1);
    }
    case sapir::Opcode::Load:  { cg.value_map[id] = llvm::LLVMBuildLoad2(cg.builder, map_type(cg, inst.ty), cg.value_map[inst.a], cg.empty); }
    case sapir::Opcode::Store: { llvm::LLVMBuildStore(cg.builder, cg.value_map[inst.b], cg.value_map[inst.a]); }
    case sapir::Opcode::Memcpy: {
        void* len = llvm::LLVMConstInt(llvm::LLVMInt64TypeInContext(cg.ctx), inst.imm, 0);
        llvm::LLVMBuildMemCpy(cg.builder, cg.value_map[inst.a], 1, cg.value_map[inst.b], 1, len);
    }
    case sapir::Opcode::FieldAddr: {
        types::Type* container = cg.f.insts[inst.a].ty.data.pointee;
        if(container.kind == types::TypeKind::Union) { cg.value_map[id] = cg.value_map[inst.a]; }
        else { cg.value_map[id] = llvm::LLVMBuildStructGEP2(cg.builder, map_type(cg, container), cg.value_map[inst.a], inst.b, cg.empty); }
    }
    case sapir::Opcode::IndexAddr:  { cg.value_map[id] = emit_index_addr(cg, inst); }
    case sapir::Opcode::GlobalAddr: { cg.value_map[id] = cg.decl_map[inst.a]; }
    case sapir::Opcode::FnAddr:     { cg.value_map[id] = cg.decl_map[inst.a]; }

    case sapir::Opcode::SliceMake: {
        void* agg = llvm::LLVMGetUndef(map_type(cg, inst.ty));
        agg = llvm::LLVMBuildInsertValue(cg.builder, agg, cg.value_map[inst.a], 0, cg.empty);
        agg = llvm::LLVMBuildInsertValue(cg.builder, agg, cg.value_map[inst.b], 1, cg.empty);
        cg.value_map[id] = agg;
    }
    case sapir::Opcode::SlicePtr: { cg.value_map[id] = llvm::LLVMBuildExtractValue(cg.builder, cg.value_map[inst.a], 0, cg.empty); }
    case sapir::Opcode::SliceLen: { cg.value_map[id] = llvm::LLVMBuildExtractValue(cg.builder, cg.value_map[inst.a], 1, cg.empty); }

    case sapir::Opcode::Add:
    case sapir::Opcode::Sub:
    case sapir::Opcode::Mul:
    case sapir::Opcode::Div:
    case sapir::Opcode::Rem:
    case sapir::Opcode::And:
    case sapir::Opcode::Or:
    case sapir::Opcode::Xor:
    case sapir::Opcode::Shl:
    case sapir::Opcode::Shr:
    case sapir::Opcode::CmpEq:
    case sapir::Opcode::CmpNe:
    case sapir::Opcode::CmpLt:
    case sapir::Opcode::CmpLe:
    case sapir::Opcode::CmpGt:
    case sapir::Opcode::CmpGe: { cg.value_map[id] = emit_binop(cg, inst); }

    case sapir::Opcode::Neg: {
        if(types::is_float(inst.ty)) { cg.value_map[id] = llvm::LLVMBuildFNeg(cg.builder, cg.value_map[inst.a], cg.empty); }
        else { cg.value_map[id] = llvm::LLVMBuildNeg(cg.builder, cg.value_map[inst.a], cg.empty); }
    }
    case sapir::Opcode::BitNot: { cg.value_map[id] = llvm::LLVMBuildNot(cg.builder, cg.value_map[inst.a], cg.empty); }
    case sapir::Opcode::Not:    { cg.value_map[id] = llvm::LLVMBuildNot(cg.builder, cg.value_map[inst.a], cg.empty); }

    case sapir::Opcode::Cast: { cg.value_map[id] = emit_cast(cg, inst); }
    case sapir::Opcode::Call: { cg.value_map[id] = emit_call(cg, inst); }

    case sapir::Opcode::Ret: {
        if(inst.a == sapir::INVALID_ID) { llvm::LLVMBuildRetVoid(cg.builder); }
        else { llvm::LLVMBuildRet(cg.builder, cg.value_map[inst.a]); }
    }
    case sapir::Opcode::Br:          { llvm::LLVMBuildBr(cg.builder, cg.block_map[inst.a]); }
    case sapir::Opcode::CondBr:      { llvm::LLVMBuildCondBr(cg.builder, cg.value_map[inst.a], cg.block_map[cg.f.extra[inst.b]], cg.block_map[cg.f.extra[inst.b + 1]]); }
    case sapir::Opcode::SwitchBr:    { emit_switch(cg, inst); }
    case sapir::Opcode::Unreachable: { llvm::LLVMBuildUnreachable(cg.builder); }
    else {
        sys::dprintf(2, "codegen: opcode %d is not translated yet\n", (i32)inst.op);
        cg.failed = true;
    }
    }
}

// Arithmetic / bitwise / comparison — the signed/unsigned/float variant is chosen from the operand type.
fn void* emit_binop(CG* cg, sapir::Inst* inst) {
    void* l = cg.value_map[inst.a];
    void* r = cg.value_map[inst.b];
    types::Type* ot = cg.f.insts[inst.a].ty;
    bool f = types::is_float(ot);
    bool s = types::is_signed_int(ot);
    switch(inst.op) {
    case sapir::Opcode::Add: { if(f) { return llvm::LLVMBuildFAdd(cg.builder, l, r, cg.empty); } return llvm::LLVMBuildAdd(cg.builder, l, r, cg.empty); }
    case sapir::Opcode::Sub: { if(f) { return llvm::LLVMBuildFSub(cg.builder, l, r, cg.empty); } return llvm::LLVMBuildSub(cg.builder, l, r, cg.empty); }
    case sapir::Opcode::Mul: { if(f) { return llvm::LLVMBuildFMul(cg.builder, l, r, cg.empty); } return llvm::LLVMBuildMul(cg.builder, l, r, cg.empty); }
    case sapir::Opcode::Div: { if(f) { return llvm::LLVMBuildFDiv(cg.builder, l, r, cg.empty); } if(s) { return llvm::LLVMBuildSDiv(cg.builder, l, r, cg.empty); } return llvm::LLVMBuildUDiv(cg.builder, l, r, cg.empty); }
    case sapir::Opcode::Rem: { if(f) { return llvm::LLVMBuildFRem(cg.builder, l, r, cg.empty); } if(s) { return llvm::LLVMBuildSRem(cg.builder, l, r, cg.empty); } return llvm::LLVMBuildURem(cg.builder, l, r, cg.empty); }
    case sapir::Opcode::And: { return llvm::LLVMBuildAnd(cg.builder, l, r, cg.empty); }
    case sapir::Opcode::Or:  { return llvm::LLVMBuildOr(cg.builder, l, r, cg.empty); }
    case sapir::Opcode::Xor: { return llvm::LLVMBuildXor(cg.builder, l, r, cg.empty); }
    case sapir::Opcode::Shl: { return llvm::LLVMBuildShl(cg.builder, l, r, cg.empty); }
    case sapir::Opcode::Shr: { if(s) { return llvm::LLVMBuildAShr(cg.builder, l, r, cg.empty); } return llvm::LLVMBuildLShr(cg.builder, l, r, cg.empty); }
    case sapir::Opcode::CmpEq: { if(f) { return llvm::LLVMBuildFCmp(cg.builder, llvm::RealOEQ, l, r, cg.empty); } return llvm::LLVMBuildICmp(cg.builder, llvm::IntEQ, l, r, cg.empty); }
    case sapir::Opcode::CmpNe: { if(f) { return llvm::LLVMBuildFCmp(cg.builder, llvm::RealONE, l, r, cg.empty); } return llvm::LLVMBuildICmp(cg.builder, llvm::IntNE, l, r, cg.empty); }
    case sapir::Opcode::CmpLt: { if(f) { return llvm::LLVMBuildFCmp(cg.builder, llvm::RealOLT, l, r, cg.empty); } if(s) { return llvm::LLVMBuildICmp(cg.builder, llvm::IntSLT, l, r, cg.empty); } return llvm::LLVMBuildICmp(cg.builder, llvm::IntULT, l, r, cg.empty); }
    case sapir::Opcode::CmpLe: { if(f) { return llvm::LLVMBuildFCmp(cg.builder, llvm::RealOLE, l, r, cg.empty); } if(s) { return llvm::LLVMBuildICmp(cg.builder, llvm::IntSLE, l, r, cg.empty); } return llvm::LLVMBuildICmp(cg.builder, llvm::IntULE, l, r, cg.empty); }
    case sapir::Opcode::CmpGt: { if(f) { return llvm::LLVMBuildFCmp(cg.builder, llvm::RealOGT, l, r, cg.empty); } if(s) { return llvm::LLVMBuildICmp(cg.builder, llvm::IntSGT, l, r, cg.empty); } return llvm::LLVMBuildICmp(cg.builder, llvm::IntUGT, l, r, cg.empty); }
    case sapir::Opcode::CmpGe: { if(f) { return llvm::LLVMBuildFCmp(cg.builder, llvm::RealOGE, l, r, cg.empty); } if(s) { return llvm::LLVMBuildICmp(cg.builder, llvm::IntSGE, l, r, cg.empty); } return llvm::LLVMBuildICmp(cg.builder, llvm::IntUGE, l, r, cg.empty); }
    else { return llvm::LLVMGetUndef(map_type(cg, inst.ty)); }
    }
    return llvm::LLVMGetUndef(map_type(cg, inst.ty));
}

// Temp allocas appear mid-stream; hoist every alloca to the top of the entry block so loop bodies don't leak stack.
fn void* emit_alloca(CG* cg, sapir::Inst* inst) {
    void* slot_ty = map_type(cg, inst.ty.data.pointee);
    void* entry = cg.block_map[cg.f.entry];
    void* first = llvm::LLVMGetFirstInstruction(entry);
    if(first != null) { llvm::LLVMPositionBuilder(cg.builder, entry, first); }
    else { llvm::LLVMPositionBuilderAtEnd(cg.builder, entry); }
    void* slot = llvm::LLVMBuildAlloca(cg.builder, slot_ty, cg.empty);
    llvm::LLVMPositionBuilderAtEnd(cg.builder, cg.current_block);
    return slot;
}

fn void* emit_index_addr(CG* cg, sapir::Inst* inst) {
    types::Type* base_pointee = cg.f.insts[inst.a].ty.data.pointee;
    if(base_pointee.kind == types::TypeKind::Array) {
        void*[2] indices;
        indices[0] = llvm::LLVMConstInt(llvm::LLVMInt64TypeInContext(cg.ctx), 0, 0);
        indices[1] = cg.value_map[inst.b];
        return llvm::LLVMBuildGEP2(cg.builder, map_type(cg, base_pointee), cg.value_map[inst.a], &indices[0], 2, cg.empty);
    }
    void*[1] indices;
    indices[0] = cg.value_map[inst.b];
    return llvm::LLVMBuildGEP2(cg.builder, map_type(cg, base_pointee), cg.value_map[inst.a], &indices[0], 1, cg.empty);
}

fn void* emit_cast(CG* cg, sapir::Inst* inst) {
    types::Type* src = cg.f.insts[inst.a].ty;
    void* v = cg.value_map[inst.a];
    void* dst = map_type(cg, inst.ty);
    switch(sapir::cast_op(src, inst.ty)) {
    case sapir::CastOp::Nop:      { return v; }
    case sapir::CastOp::Trunc:    { return llvm::LLVMBuildTrunc(cg.builder, v, dst, cg.empty); }
    case sapir::CastOp::SExt:     { return llvm::LLVMBuildSExt(cg.builder, v, dst, cg.empty); }
    case sapir::CastOp::ZExt:     { return llvm::LLVMBuildZExt(cg.builder, v, dst, cg.empty); }
    case sapir::CastOp::SIToFP:   { return llvm::LLVMBuildSIToFP(cg.builder, v, dst, cg.empty); }
    case sapir::CastOp::UIToFP:   { return llvm::LLVMBuildUIToFP(cg.builder, v, dst, cg.empty); }
    case sapir::CastOp::FPToSI:   { return llvm::LLVMBuildFPToSI(cg.builder, v, dst, cg.empty); }
    case sapir::CastOp::FPToUI:   { return llvm::LLVMBuildFPToUI(cg.builder, v, dst, cg.empty); }
    case sapir::CastOp::FPExt:    { return llvm::LLVMBuildFPExt(cg.builder, v, dst, cg.empty); }
    case sapir::CastOp::FPTrunc:  { return llvm::LLVMBuildFPTrunc(cg.builder, v, dst, cg.empty); }
    case sapir::CastOp::PtrToInt: { return llvm::LLVMBuildPtrToInt(cg.builder, v, dst, cg.empty); }
    case sapir::CastOp::IntToPtr: { return llvm::LLVMBuildIntToPtr(cg.builder, v, dst, cg.empty); }
    else { return v; }
    }
    return v;
}

fn void* emit_call(CG* cg, sapir::Inst* inst) {
    u32 argc = cg.f.extra[inst.b];
    void** args = (void**)arena::alloc(cg.arena, ((u64)argc + 1) * sizeof(void*));
    for(u32 k = 0; k < argc; k += 1) { args[k] = cg.value_map[cg.f.extra[inst.b + 1 + k]]; }
    bool indirect = ((u16)inst.flags & (u16)sapir::InstFlags::Indirect) != 0;
    void* callee;
    void* fn_ty;
    if(indirect) {
        callee = cg.value_map[inst.a];
        fn_ty = map_fn_type(cg, cg.f.insts[inst.a].ty);
    } else {
        callee = cg.decl_map[inst.a];
        fn_ty = map_fn_type(cg, cg.sm.decls[inst.a].ty);
    }
    return llvm::LLVMBuildCall2(cg.builder, fn_ty, callee, args, argc, cg.empty);
}

fn void emit_switch(CG* cg, sapir::Inst* inst) {
    u32 default_block = cg.f.extra[inst.b];
    u32 arm_count = cg.f.extra[inst.b + 1];
    void* sw = llvm::LLVMBuildSwitch(cg.builder, cg.value_map[inst.a], cg.block_map[default_block], arm_count);
    types::Type* disc_ty = cg.f.insts[inst.a].ty;
    void* case_ty = map_type(cg, disc_ty);
    for(u32 k = 0; k < arm_count; k += 1) {
        u32 arm_base = inst.b + 2 + k * 3;
        u64 low = (u64)cg.f.extra[arm_base];
        u64 high = (u64)cg.f.extra[arm_base + 1];
        u64 label = low | (high << 32);
        void* on_val = llvm::LLVMConstInt(case_ty, label, 0);
        llvm::LLVMAddCase(sw, on_val, cg.block_map[cg.f.extra[arm_base + 2]]);
    }
}

// A ConstStr materializes an internal, constant, unnamed string global; the result is a pointer or a {ptr,len} slice.
fn void* emit_const_str(CG* cg, sapir::Inst* inst) {
    i8* bytes = (i8*)&cg.sm.literal_pool[inst.a];
    void* str_const = llvm::LLVMConstStringInContext2(cg.ctx, bytes, (u64)inst.b, 0);
    // An array-typed string is the constant array itself (its length already equals the byte count + NUL); ptr/slice forms need a global to point at.
    if(types::is_array(inst.ty)) { return str_const; }
    void* gv = llvm::LLVMAddGlobal(cg.llvm_module, llvm::LLVMTypeOf(str_const), cg.empty);
    llvm::LLVMSetInitializer(gv, str_const);
    llvm::LLVMSetLinkage(gv, llvm::InternalLinkage);
    llvm::LLVMSetGlobalConstant(gv, 1);
    llvm::LLVMSetUnnamedAddress(gv, llvm::GlobalUnnamedAddr);
    if(types::is_slice(inst.ty)) {
        void* len = llvm::LLVMConstInt(llvm::LLVMInt64TypeInContext(cg.ctx), (u64)inst.b, 0);
        void* agg = llvm::LLVMGetUndef(map_type(cg, inst.ty));
        agg = llvm::LLVMBuildInsertValue(cg.builder, agg, gv, 0, cg.empty);
        agg = llvm::LLVMBuildInsertValue(cg.builder, agg, len, 1, cg.empty);
        return agg;
    }
    return gv;
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
