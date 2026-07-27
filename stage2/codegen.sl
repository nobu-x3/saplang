// The LLVM backend: translates a SapirModule into an LLVM module, then either
// emits an object file or JIT-runs it in-process. Imports sapir + types only
// (never ast/cfg/sema/module) — everything a backend needs is materialized in
// the SapirModule by lower.sl. Aggregate types and the full opcode set land
// with instruction translation; this shell covers scalars and terminators.

import sapir;
import types;
import interner;
import symbol;
import llvm;
import arena;
import list;
import sys;

// Build configuration selecting the optimization/instrumentation pipeline.
export enum BuildConfig : u8 {
    Debug,              // -O0, no passes
    Release,            // -O2
    ReleaseDebug,       // -O2 with debug info (DWARF lands with the debug-info milestone)
    AddressSanitizer,   // -O1 + AddressSanitizer instrumentation, linked against the asan runtime
}

struct TypeMapEntry {
    types::Ty* ty;
    void*        llvm;
}

struct CG {
    sapir::SapirModule* sm;
    arena::Arena*       arena;
    BuildConfig         config;
    void*               ctx;
    void*               llvm_module;
    void*               builder;
    i8*                 empty;          // "" reused as the name argument for unnamed values
    bool                failed;

    void**              decl_map;       // decl index -> LLVMValueRef (function / global)
    list::List(TypeMapEntry) type_map;   // Type* -> LLVMTypeRef

    // Debug info; di_builder is null unless the config wants DWARF.
    void*               di_builder;
    void*               di_file;
    void*               di_compile_unit;
    void*               di_subprogram;  // the current function's DISubprogram

    // Per-function, reset by emit_fn.
    sapir::SapirFn*     f;
    void*               current_fn;
    void*               current_block;  // LLVMBasicBlockRef currently being built
    void**              value_map;      // inst id -> LLVMValueRef
    void**              block_map;      // sapir block id -> LLVMBasicBlockRef
}

// Builds the LLVM module, runs the config's pass pipeline, and emits obj_path. Returns 0 on success.
export fn i32 emit_object(sapir::SapirModule* sm, arena::Arena* a, i8* obj_path, BuildConfig config) {
    CG cg;
    cg_init(&cg, sm, a, config);
    if(!build_module(&cg)) { return 1; }
    void* tm = make_target_machine();
    if(tm == null) { return 1; }
    if(!run_passes(&cg, tm)) { llvm::LLVMDisposeTargetMachine(tm); return 1; }
    i32 rc = 0;
    i8* err = null;
    if(llvm::LLVMTargetMachineEmitToFile(tm, cg.llvm_module, obj_path, llvm::ObjectFile, &err) != 0) {
        sys::dprintf(2, "codegen: object emission failed: %s\n", err);
        llvm::LLVMDisposeMessage(err);
        rc = 1;
    }
    llvm::LLVMDisposeTargetMachine(tm);
    return rc;
}

fn void* make_target_machine() {
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
        return null;
    }
    return llvm::LLVMCreateTargetMachine(target, triple, "generic", "", llvm::CodeGenLevelDefault, llvm::RelocPIC, llvm::CodeModelDefault);
}

fn bool run_passes(CG* cg, void* tm) {
    u8[] pipeline = pipeline_for(cg.config);
    if(pipeline.len == 0) { return true; }
    void* opts = llvm::LLVMCreatePassBuilderOptions();
    void* err = llvm::LLVMRunPasses(cg.llvm_module, cstr(cg.arena, pipeline), tm, opts);
    llvm::LLVMDisposePassBuilderOptions(opts);
    if(err != null) {
        sys::dprintf(2, "codegen: optimization pipeline failed\n");
        llvm::LLVMConsumeError(err);
        return false;
    }
    return true;
}

fn u8[] pipeline_for(BuildConfig config) {
    switch(config) {
    case BuildConfig::Debug:            { return ""; }
    case BuildConfig::Release:          { return "default<O2>"; }
    case BuildConfig::ReleaseDebug:     { return "default<O2>"; }
    case BuildConfig::AddressSanitizer: { return "default<O1>,asan"; }
    else { return ""; }
    }
    return "";
}

// Builds the module, runs the config's pipeline, and returns its LLVM IR as text; used by tests.
export fn u8[] codegen_ir_string(sapir::SapirModule* sm, arena::Arena* a, BuildConfig config) {
    CG cg;
    cg_init(&cg, sm, a, config);
    if(!build_module(&cg)) { return "<codegen failed>"; }
    void* tm = make_target_machine();
    if(tm != null) { run_passes(&cg, tm); llvm::LLVMDisposeTargetMachine(tm); }
    i8* s = llvm::LLVMPrintModuleToString(cg.llvm_module);
    u8[] out = copy_cstr(a, s);
    llvm::LLVMDisposeMessage(s);
    return out;
}

fn u8[] copy_cstr(arena::Arena* a, i8* s) {
    u64 len = 0;
    while(s[len] != 0) { len += 1; }
    u8* out = (u8*)arena::alloc(a, len + 1);
    for(u64 i = 0; i < len; i += 1) { out[i] = (u8)s[i]; }
    u8[] result = {out, len};
    return result;
}

// Builds the module and JIT-runs main() in-process (no external linker). Returns main's exit code, or -1 on failure.
export fn i32 jit_run_main(sapir::SapirModule* sm, arena::Arena* a) {
    CG cg;
    cg_init(&cg, sm, a, BuildConfig::Debug);
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

fn void cg_init(CG* cg, sapir::SapirModule* sm, arena::Arena* a, BuildConfig config) {
    sys::memset(cg, 0, sizeof(CG));
    cg.sm = sm;
    cg.arena = a;
    cg.config = config;
    cg.ctx = llvm::LLVMContextCreate();
    cg.llvm_module = llvm::LLVMModuleCreateWithNameInContext(cstr(a, interner::symbol_str(sm.name)), cg.ctx);
    cg.builder = llvm::LLVMCreateBuilderInContext(cg.ctx);
    cg.empty = cstr(a, "");
    cg.decl_map = (void**)arena::alloc(a, (sm.decls.len + 1) * sizeof(void*));
}

fn bool build_module(CG* cg) {
    if(wants_debug_info(cg.config)) { debug_info_init(cg); }
    for(u64 i = 0; i < cg.sm.decls.len; i += 1) { declare_decl(cg, (u32)i); }
    for(u64 i = 0; i < cg.sm.globals.len; i += 1) { init_global(cg, &cg.sm.globals[i]); }
    for(u64 i = 0; i < cg.sm.fns.len; i += 1) { emit_fn(cg, &cg.sm.fns[i]); }
    if(cg.di_builder != null) {
        add_debug_module_flags(cg);
        llvm::LLVMDIBuilderFinalize(cg.di_builder);
    }
    if(cg.failed) { return false; }
    i8* err = null;
    if(llvm::LLVMVerifyModule(cg.llvm_module, llvm::ReturnStatusAction, &err) != 0) {
        sys::dprintf(2, "codegen: LLVM verification failed:\n%s\n", err);
        llvm::LLVMDisposeMessage(err);
        return false;
    }
    return true;
}

fn bool wants_debug_info(BuildConfig config) {
    if(config == BuildConfig::Release) { return false; }
    return true;
}

// DEBUG INFO (DWARF) //////////////////////////////////////////////////////////////

fn void debug_info_init(CG* cg) {
    cg.di_builder = llvm::LLVMCreateDIBuilder(cg.llvm_module);
    u8[] path = cg.sm.src_path;
    if(path.len == 0) { path = interner::symbol_str(cg.sm.name); }
    cg.di_file = llvm::LLVMDIBuilderCreateFile(cg.di_builder, cstr(cg.arena, path), path.len, cstr(cg.arena, "."), 1);
    bool optimized = cg.config != BuildConfig::Debug;
    i32 opt = 0;
    if(optimized) { opt = 1; }
    cg.di_compile_unit = llvm::LLVMDIBuilderCreateCompileUnit(cg.di_builder, llvm::DWARFSourceLanguageC, cg.di_file, cstr(cg.arena, "saplangc"), 8, opt, cstr(cg.arena, ""), 0, 0, cstr(cg.arena, ""), 0, llvm::DWARFEmissionFull, 0, 0, 0, cstr(cg.arena, ""), 0, cstr(cg.arena, ""), 0);
}

fn void add_debug_module_flags(CG* cg) {
    void* three = llvm::LLVMConstInt(llvm::LLVMInt32TypeInContext(cg.ctx), 3, 0);
    llvm::LLVMAddModuleFlag(cg.llvm_module, llvm::ModuleFlagBehaviorWarning, cstr(cg.arena, "Debug Info Version"), 18, llvm::LLVMValueAsMetadata(three));
}

fn void emit_di_subprogram(CG* cg, sapir::SapirFn* f) {
    types::Ty* fnty = cg.sm.decls[f.decl_index].ty;
    types::Ty*[] params = fnty.data.fn_ptr.params;
    void** di_params = (void**)arena::alloc(cg.arena, (params.len + 2) * sizeof(void*));
    di_params[0] = build_di_type(cg, fnty.data.fn_ptr.ret);
    for(u64 i = 0; i < params.len; i += 1) { di_params[i + 1] = build_di_type(cg, params[i]); }
    void* sub_ty = llvm::LLVMDIBuilderCreateSubroutineType(cg.di_builder, cg.di_file, di_params, (u32)params.len + 1, 0);
    u32 line = 0;
    u32 col = 0;
    src_pos_to_line_col(cg.sm, f.src_pos, &line, &col);
    u8[] name = interner::symbol_str(f.name);
    u8[] link_name = cg.sm.decls[f.decl_index].link_name;
    i32 opt = 0;
    if(cg.config != BuildConfig::Debug) { opt = 1; }
    void* sp = llvm::LLVMDIBuilderCreateFunction(cg.di_builder, cg.di_file, name.ptr, name.len, link_name.ptr, link_name.len, cg.di_file, line, sub_ty, 0, 1, line, 0, opt);
    llvm::LLVMSetSubprogram(cg.current_fn, sp);
    cg.di_subprogram = sp;
}

// A DIType for the function-signature subroutine type. Scalars are exact; aggregates are left unspecified (locals are not emitted in v0).
fn void* build_di_type(CG* cg, types::Ty* t) {
    if(t == null) { return null; }
    switch(t.kind) {
    case types::TypeKind::Primitive: { return di_basic_type(cg, t.prim); }
    case types::TypeKind::Pointer:
    case types::TypeKind::FnPtr:     { return llvm::LLVMDIBuilderCreatePointerType(cg.di_builder, null, 64, 0, 0, cg.empty, 0); }
    case types::TypeKind::Enum:      { return build_di_type(cg, types::enum_base_type(t)); }
    case types::TypeKind::Struct:    { return build_di_composite(cg, t, false); }
    case types::TypeKind::Union:     { return build_di_composite(cg, t, true); }
    case types::TypeKind::Array:     { return build_di_array(cg, t); }
    case types::TypeKind::Slice:     { return build_di_slice(cg, t); }
    else { return null; }
    }
    return null;
}

fn u8[] sym_str_or_empty(symbol::Symbol* s) {
    if(s == null) { u8[] e = {null, 0}; return e; }
    return interner::symbol_str(s);
}

fn void* di_member(CG* cg, u8[] name, types::Ty* ft, u64 offset_bits) {
    u64 fbits = (u64)types::size_of(null, ft) * 8;
    u32 falign = types::align_of(null, ft) * 8;
    return llvm::LLVMDIBuilderCreateMemberType(cg.di_builder, cg.di_file, name.ptr, name.len, cg.di_file, 0, fbits, falign, offset_bits, 0, build_di_type(cg, ft));
}

fn void* build_di_composite(CG* cg, types::Ty* t, bool is_union) {
    u64 count = types::field_count(t);
    void** members = (void**)arena::alloc(cg.arena, (count + 1) * sizeof(void*));
    for(u64 i = 0; i < count; i += 1) {
        u8[] fname = sym_str_or_empty(types::field_name_sym(t, i));
        members[i] = di_member(cg, fname, types::field_type(t, i), (u64)types::field_offset(t, i) * 8);
    }
    u64 size = (u64)types::size_of(null, t) * 8;
    u32 align = types::align_of(null, t) * 8;
    u8[] name = sym_str_or_empty(types::type_name_sym(t));
    if(is_union) {
        return llvm::LLVMDIBuilderCreateUnionType(cg.di_builder, cg.di_file, name.ptr, name.len, cg.di_file, 0, size, align, 0, members, (u32)count, 0, cg.empty, 0);
    }
    return llvm::LLVMDIBuilderCreateStructType(cg.di_builder, cg.di_file, name.ptr, name.len, cg.di_file, 0, size, align, 0, null, members, (u32)count, 0, null, cg.empty, 0);
}

fn void* build_di_array(CG* cg, types::Ty* t) {
    void* elem_di = build_di_type(cg, t.data.array.elem);
    void* subrange = llvm::LLVMDIBuilderGetOrCreateSubrange(cg.di_builder, 0, (i64)t.data.array.count);
    void*[1] subs;
    subs[0] = subrange;
    u64 size = (u64)types::size_of(null, t) * 8;
    u32 align = types::align_of(null, t) * 8;
    return llvm::LLVMDIBuilderCreateArrayType(cg.di_builder, size, align, elem_di, &subs[0], 1);
}

// A slice is a {ptr, len} pair: an elem-pointer at offset 0 and a u64 length at offset 8.
fn void* build_di_slice(CG* cg, types::Ty* t) {
    void*[2] members;
    members[0] = di_member(cg, "ptr", types::intern_pointer(t.data.slice_elem, false), 0);
    members[1] = di_member(cg, "len", types::prim_u64(), 64);
    return llvm::LLVMDIBuilderCreateStructType(cg.di_builder, cg.di_file, cg.empty, 0, cg.di_file, 0, 128, 64, 0, null, &members[0], 2, 0, null, cg.empty, 0);
}

fn void* di_basic_type(CG* cg, types::PrimitiveKind p) {
    if(p == types::PrimitiveKind::VOID) { return null; }
    u64 bits = 32;
    u32 enc = llvm::DW_ATE_signed;
    switch(p) {
    case types::PrimitiveKind::I8:   { bits = 8; enc = llvm::DW_ATE_signed; }
    case types::PrimitiveKind::U8:   { bits = 8; enc = llvm::DW_ATE_unsigned; }
    case types::PrimitiveKind::I16:  { bits = 16; enc = llvm::DW_ATE_signed; }
    case types::PrimitiveKind::U16:  { bits = 16; enc = llvm::DW_ATE_unsigned; }
    case types::PrimitiveKind::I32:  { bits = 32; enc = llvm::DW_ATE_signed; }
    case types::PrimitiveKind::U32:  { bits = 32; enc = llvm::DW_ATE_unsigned; }
    case types::PrimitiveKind::I64:  { bits = 64; enc = llvm::DW_ATE_signed; }
    case types::PrimitiveKind::U64:  { bits = 64; enc = llvm::DW_ATE_unsigned; }
    case types::PrimitiveKind::F32:  { bits = 32; enc = llvm::DW_ATE_float; }
    case types::PrimitiveKind::F64:  { bits = 64; enc = llvm::DW_ATE_float; }
    case types::PrimitiveKind::BOOL: { bits = 8; enc = llvm::DW_ATE_boolean; }
    else { bits = 32; enc = llvm::DW_ATE_signed; }
    }
    u8[] name = prim_name(p);
    return llvm::LLVMDIBuilderCreateBasicType(cg.di_builder, name.ptr, name.len, bits, enc, 0);
}

fn u8[] prim_name(types::PrimitiveKind p) {
    switch(p) {
    case types::PrimitiveKind::I8:   { return "i8"; }
    case types::PrimitiveKind::U8:   { return "u8"; }
    case types::PrimitiveKind::I16:  { return "i16"; }
    case types::PrimitiveKind::U16:  { return "u16"; }
    case types::PrimitiveKind::I32:  { return "i32"; }
    case types::PrimitiveKind::U32:  { return "u32"; }
    case types::PrimitiveKind::I64:  { return "i64"; }
    case types::PrimitiveKind::U64:  { return "u64"; }
    case types::PrimitiveKind::F32:  { return "f32"; }
    case types::PrimitiveKind::F64:  { return "f64"; }
    case types::PrimitiveKind::BOOL: { return "bool"; }
    else { return "int"; }
    }
    return "int";
}

fn void set_debug_loc(CG* cg, u32 src_pos) {
    if(cg.di_builder == null) { return; }
    u32 line = 0;
    u32 col = 0;
    src_pos_to_line_col(cg.sm, src_pos, &line, &col);
    void* loc = llvm::LLVMDIBuilderCreateDebugLocation(cg.ctx, line, col, cg.di_subprogram, null);
    llvm::LLVMSetCurrentDebugLocation2(cg.builder, loc);
}

fn void src_pos_to_line_col(sapir::SapirModule* sm, u32 src_pos, u32* line, u32* col) {
    u32 found = 0;
    for(u64 i = 0; i < sm.line_starts.len; i += 1) {
        if(sm.line_starts[i] <= src_pos) { found = (u32)i; } else { break; }
    }
    *line = found + 1;
    *col = src_pos - sm.line_starts[found] + 1;
}

// TYPES ///////////////////////////////////////////////////////////////////////////

fn void* map_type(CG* cg, types::Ty* t) {
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

fn void fill_struct_body(CG* cg, types::Ty* t, void* struct_ty) {
    types::Ty*[] fields = types::struct_field_types(t, cg.arena);
    void** llvm_fields = (void**)arena::alloc(cg.arena, (fields.len + 1) * sizeof(void*));
    for(u64 i = 0; i < fields.len; i += 1) { llvm_fields[i] = map_type(cg, fields[i]); }
    llvm::LLVMStructSetBody(struct_ty, llvm_fields, (u32)fields.len, 0);
}

// A union lowers to a struct wrapping one [size x i8] payload; members are accessed through the base pointer.
fn void* union_blob_type(CG* cg, types::Ty* t) {
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

fn void* map_fn_type(CG* cg, types::Ty* fnty) {
    types::Ty*[] params = fnty.data.fn_ptr.params;
    void** llvm_params = (void**)arena::alloc(cg.arena, (params.len + 1) * sizeof(void*));
    for(u64 i = 0; i < params.len; i += 1) { llvm_params[i] = map_type(cg, params[i]); }
    void* ret = map_type(cg, fnty.data.fn_ptr.ret);
    i32 variadic = 0;
    if(fnty.data.fn_ptr.is_variadic) { variadic = 1; }
    return llvm::LLVMFunctionType(ret, llvm_params, (u32)params.len, variadic);
}

fn void* type_map_lookup(CG* cg, types::Ty* t) {
    for(u64 i = 0; i < cg.type_map.len; i += 1) {
        if(cg.type_map.ptr[i].ty == t) { return cg.type_map.ptr[i].llvm; }
    }
    return null;
}

fn void type_map_insert(CG* cg, types::Ty* t, void* llvm_ty) {
    TypeMapEntry e;
    e.ty = t;
    e.llvm = llvm_ty;
    list::push(&cg.type_map, cg.arena, e);
}

// DECLS + GLOBALS ///////////////////////////////////////////////////////////////////

fn void declare_decl(CG* cg, u32 index) {
    sapir::SapirDecl* d = &cg.sm.decls[index];
    if(d.kind == sapir::SapirDeclKind::Fn) {
        void* fn_ty = map_fn_type(cg, d.ty);
        void* val = llvm::LLVMAddFunction(cg.llvm_module, cstr(cg.arena, d.link_name), fn_ty);
        llvm::LLVMSetLinkage(val, decl_linkage(d));
        if(cg.config == BuildConfig::AddressSanitizer && d.linkage != sapir::SapirLinkage::Foreign) { add_sanitize_address(cg, val); }
        cg.decl_map[index] = val;
    } else {
        void* ty = map_type(cg, d.ty);
        void* val = llvm::LLVMAddGlobal(cg.llvm_module, ty, cstr(cg.arena, d.link_name));
        llvm::LLVMSetLinkage(val, decl_linkage(d));
        cg.decl_map[index] = val;
    }
}

fn void add_sanitize_address(CG* cg, void* fn_val) {
    u32 kind = llvm::LLVMGetEnumAttributeKindForName(cstr(cg.arena, "sanitize_address"), 16);
    void* attr = llvm::LLVMCreateEnumAttribute(cg.ctx, kind, 0);
    llvm::LLVMAddAttributeAtIndex(fn_val, llvm::AttributeFunctionIndex, attr);
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
    case sapir::ConstInitKind::Bytes: { return const_bytes(cg, ci); }
    case sapir::ConstInitKind::Slice: { return const_slice(cg, ci); }
    else {
        sys::dprintf(2, "codegen: this constant initializer kind is not implemented yet\n");
        cg.failed = true;
        return llvm::LLVMConstNull(map_type(cg, ci.ty));
    }
    }
    return llvm::LLVMConstNull(map_type(cg, ci.ty));
}

// A string-literal constant: an internal NUL-terminated [N+1 x i8] global, yielded as a {ptr,len} slice, a bare pointer, or (array target) the inline bytes.
fn void* const_bytes(CG* cg, sapir::ConstInit* ci) {
    void* str_const = llvm::LLVMConstStringInContext2(cg.ctx, (i8*)ci.bytes.ptr, ci.bytes.len, 0);
    if(types::is_array(ci.ty)) { return str_const; }
    void* gv = llvm::LLVMAddGlobal(cg.llvm_module, llvm::LLVMTypeOf(str_const), cg.empty);
    llvm::LLVMSetInitializer(gv, str_const);
    llvm::LLVMSetLinkage(gv, llvm::InternalLinkage);
    llvm::LLVMSetGlobalConstant(gv, 1);
    llvm::LLVMSetUnnamedAddress(gv, llvm::GlobalUnnamedAddr);
    if(types::is_slice(ci.ty)) {
        void*[2] fields;
        fields[0] = gv;
        fields[1] = llvm::LLVMConstInt(llvm::LLVMInt64TypeInContext(cg.ctx), ci.bytes.len, 0);
        return llvm::LLVMConstNamedStruct(map_type(cg, ci.ty), &fields[0], 2);
    }
    return gv;
}

// An array-literal into a slice global: the elements back an internal constant array; the slice is {ptr, len}.
fn void* const_slice(CG* cg, sapir::ConstInit* ci) {
    void** vals = (void**)arena::alloc(cg.arena, (ci.elems.len + 1) * sizeof(void*));
    for(u64 i = 0; i < ci.elems.len; i += 1) { vals[i] = const_value(cg, &ci.elems[i]); }
    void* arr_const = llvm::LLVMConstArray2(map_type(cg, ci.ty.data.slice_elem), vals, ci.elems.len);
    void* gv = llvm::LLVMAddGlobal(cg.llvm_module, llvm::LLVMTypeOf(arr_const), cg.empty);
    llvm::LLVMSetInitializer(gv, arr_const);
    llvm::LLVMSetLinkage(gv, llvm::InternalLinkage);
    llvm::LLVMSetGlobalConstant(gv, 1);
    llvm::LLVMSetUnnamedAddress(gv, llvm::GlobalUnnamedAddr);
    void*[2] fields;
    fields[0] = gv;
    fields[1] = llvm::LLVMConstInt(llvm::LLVMInt64TypeInContext(cg.ctx), ci.elems.len, 0);
    return llvm::LLVMConstNamedStruct(map_type(cg, ci.ty), &fields[0], 2);
}

// FUNCTIONS + INSTRUCTIONS ///////////////////////////////////////////////////////////

fn void emit_fn(CG* cg, sapir::SapirFn* f) {
    cg.f = f;
    cg.current_fn = cg.decl_map[f.decl_index];
    cg.di_subprogram = null;
    if(cg.di_builder != null) { emit_di_subprogram(cg, f); }
    cg.value_map = (void**)arena::alloc(cg.arena, (f.insts.len + 1) * sizeof(void*));
    sys::memset(cg.value_map, 0, (f.insts.len + 1) * sizeof(void*));   // un-materialized inst slots must read null so the dbg-value guard holds
    cg.block_map = (void**)arena::alloc(cg.arena, (f.blocks.len + 1) * sizeof(void*));
    for(u64 i = 0; i < f.blocks.len; i += 1) {
        cg.block_map[i] = llvm::LLVMAppendBasicBlockInContext(cg.ctx, cg.current_fn, cg.empty);
    }
    // All phi nodes across all blocks first: a back-edge phi can be used by an instruction in an earlier-emitted block.
    for(u64 i = 0; i < f.blocks.len; i += 1) {
        sapir::SapirBlock* b = &f.blocks[i];
        llvm::LLVMPositionBuilderAtEnd(cg.builder, cg.block_map[i]);
        for(u64 p = 0; p < b.phis.len; p += 1) {
            u32 phi_id = b.phis[p];
            set_debug_loc(cg, cg.f.insts[phi_id].src_pos);
            cg.value_map[phi_id] = llvm::LLVMBuildPhi(cg.builder, map_type(cg, cg.f.insts[phi_id].ty), cg.empty);
        }
    }
    for(u64 i = 0; i < f.blocks.len; i += 1) {
        sapir::SapirBlock* b = &f.blocks[i];
        cg.current_block = cg.block_map[i];
        llvm::LLVMPositionBuilderAtEnd(cg.builder, cg.current_block);
        for(u32 id = b.body_start; id < b.body_end; id += 1) {
            if(f.insts[id].op == sapir::Opcode::Phi) { continue; }
            emit_inst(cg, id);
        }
    }
    for(u64 i = 0; i < f.blocks.len; i += 1) {
        sapir::SapirBlock* b = &f.blocks[i];
        for(u64 p = 0; p < b.phis.len; p += 1) { fill_phi(cg, b.phis[p]); }
    }
    if(cg.di_builder != null) { emit_di_variables(cg, f); }
}

// Params and memory-var locals get DWARF variables; scalar SSA locals (no recoverable storage) are left out for now.
fn void emit_di_variables(CG* cg, sapir::SapirFn* f) {
    void* entry_bb = cg.block_map[f.entry];
    void* entry_term = llvm::LLVMGetBasicBlockTerminator(entry_bb);
    if(entry_term == null) { return; }
    void* empty_expr = llvm::LLVMDIBuilderCreateExpression(cg.di_builder, null, 0);
    void** di_vars = (void**)arena::alloc(cg.arena, (f.vars.len + 1) * sizeof(void*));
    void** di_locs = (void**)arena::alloc(cg.arena, (f.vars.len + 1) * sizeof(void*));
    for(u64 i = 0; i < f.vars.len; i += 1) {
        di_vars[i] = null;
        sapir::SapirVar* v = &f.vars[i];
        void* di_ty = build_di_type(cg, v.ty);
        if(di_ty == null) { continue; }
        u32 line = 0;
        u32 col = 0;
        src_pos_to_line_col(cg.sm, v.src_pos, &line, &col);
        u8[] name = interner::symbol_str(v.name);
        void* loc = llvm::LLVMDIBuilderCreateDebugLocation(cg.ctx, line, col, cg.di_subprogram, null);
        bool is_param = i < (u64)f.param_count;
        void* di_var;
        if(is_param) {
            di_var = llvm::LLVMDIBuilderCreateParameterVariable(cg.di_builder, cg.di_subprogram, name.ptr, name.len, (u32)i + 1, cg.di_file, line, di_ty, 1, 0);
        } else {
            di_var = llvm::LLVMDIBuilderCreateAutoVariable(cg.di_builder, cg.di_subprogram, name.ptr, name.len, cg.di_file, line, di_ty, 1, 0, 0);
        }
        di_vars[i] = di_var;
        di_locs[i] = loc;
        if(v.alloca_id != sapir::INVALID_ID) {
            llvm::LLVMDIBuilderInsertDeclareRecordBefore(cg.di_builder, cg.value_map[v.alloca_id], di_var, empty_expr, loc, entry_term);
        } else if(is_param) {
            llvm::LLVMDIBuilderInsertDbgValueRecordBefore(cg.di_builder, llvm::LLVMGetParam(cg.current_fn, (u32)i), di_var, empty_expr, loc, entry_term);
        }
    }
    // Each recorded SSA-local write becomes a #dbg_value at the end of its block, so a debugger can read the value there.
    for(u64 i = 0; i < f.dbg_values.len; i += 1) {
        sapir::SapirDbgValue* rec = &f.dbg_values[i];
        if(di_vars[rec.var] == null) { continue; }
        if(cg.value_map[rec.value] == null) { continue; }   // a value codegen never materialized (e.g. a phi in dead code)
        void* block = cg.block_map[rec.block];
        void* term = llvm::LLVMGetBasicBlockTerminator(block);
        if(term != null) {
            llvm::LLVMDIBuilderInsertDbgValueRecordBefore(cg.di_builder, cg.value_map[rec.value], di_vars[rec.var], empty_expr, di_locs[rec.var], term);
        } else {
            llvm::LLVMDIBuilderInsertDbgValueRecordAtEnd(cg.di_builder, cg.value_map[rec.value], di_vars[rec.var], empty_expr, di_locs[rec.var], block);
        }
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
    set_debug_loc(cg, inst.src_pos);
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
        types::Ty* container = cg.f.insts[inst.a].ty.data.pointee;
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
    types::Ty* ot = cg.f.insts[inst.a].ty;
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
    types::Ty* base_pointee = cg.f.insts[inst.a].ty.data.pointee;
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
    types::Ty* src = cg.f.insts[inst.a].ty;
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
    types::Ty* disc_ty = cg.f.insts[inst.a].ty;
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
