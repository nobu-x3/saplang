import arena;
import symbol;
import types;
import sys;

export const u32 INVALID_ID = 4294967295;

// LINKAGE + DECL TABLE ///////////////////////////////////////////////////////////

export enum SapirLinkage : u8 {
    Internal,
    Export,
    LinkOnceOdr,    // monomorphized clone — the linker dedupes across modules
    Foreign,        // defined elsewhere; declaration only
}

export enum SapirDeclKind : u8 {
    Fn,
    Global,
}

// Codegen declares this whole table up front; there is no lazy foreign-declaration path.
export struct SapirDecl {
    SapirDeclKind   kind;
    SapirLinkage    linkage;
    bool            is_variadic;    // meaningful only for extern C fns
    u8[]            link_name;      // final symbol bytes; mangling already applied
    types::Ty*    ty;             // fn-pointer type for fns; value type for globals
    u32             fn_index;       // into SapirModule.fns for a local fn, else INVALID_ID
    u32             global_index;   // into SapirModule.globals for a local global, else INVALID_ID
}

export struct SapirModule {
    symbol::Symbol* name;
    u8[]            src_path;
    u32[]           line_starts;    // copied so codegen resolves src_pos without importing module
    SapirDecl[]     decls;
    u64             decls_cap;
    SapirFn[]       fns;            // local fn bodies plus this module's instantiated clones
    u64             fns_cap;
    SapirGlobal[]   globals;
    u64             globals_cap;
    u8[]            literal_pool;   // ConstStr offsets index into this; aliases the source module's decoded pool
}

// CONSTANT INITIALIZERS //////////////////////////////////////////////////////////

export enum ConstInitKind : u8 {
    Zero,
    Int,
    Float,
    Bool,
    Null,
    Bytes,
    Struct,
    Array,
    FnRef,
    Slice,              // array-literal into a slice global: `elems` back a static array, the slice is {ptr, len}
}

export struct ConstInit {
    ConstInitKind   kind;
    types::Ty*    ty;
    i64             i;              // Int / Bool
    f64             f;              // Float
    u8[]            bytes;          // Bytes
    ConstInit[]     elems;          // Struct (field order) / Array
    u32             decl_index;     // FnRef — into SapirModule.decls
}

export struct SapirGlobal {
    u32         decl_index;
    bool        is_const;
    u32         src_pos;
    ConstInit   init;               // ConstInitKind::Zero when the decl has no initializer
}

// FUNCTIONS, BLOCKS, INSTRUCTIONS ////////////////////////////////////////////////

// params first (vars[i] is param i), then locals in encounter order; drives DWARF only.
export struct SapirVar {
    symbol::Symbol* name;
    types::Ty*    ty;
    u32             src_pos;
    u32             alloca_id;      // slot inst id for a memory var; INVALID_ID for an SSA var
    void*           decl;           // sema::Decl*; lets lower map an assignment target back to its var index
}

// A source-local SSA var took `value` in `block` — codegen emits a #dbg_value so a debugger can read it there.
export struct SapirDbgValue {
    u32             var;            // index into SapirFn.vars
    u32             value;          // inst id holding the var's value
    u32             block;          // block the assignment lives in
}

export struct SapirBlock {
    u32[]   phis;                   // a phi is reachable ONLY here, never by scanning the body range
    u64     phis_cap;
    u32     body_start;
    u32     body_end;               // one past the terminator
    u32[]   preds;
    u64     preds_cap;
}

export struct SapirFn {
    u32             decl_index;
    symbol::Symbol* name;
    u32             src_pos;
    u32             param_count;
    SapirVar[]      vars;
    u64             vars_cap;
    SapirDbgValue[] dbg_values;
    u64             dbg_values_cap;
    SapirBlock[]    blocks;
    u64             blocks_cap;
    u32             entry;
    Inst[]          insts;
    u64             insts_cap;
    u32[]           extra;          // variable-length payloads: call args, phi incomings, switch arms
    u64             extra_cap;
}

export enum InstFlags : u16 {
    None     = 0,
    Indirect = 1,                   // Call: operand a is a fn-pointer value id, not a decl id
}

export struct Inst {
    Opcode          op;
    u16             flags;          // InstFlags bitmask
    u32             src_pos;
    types::Ty*    ty;             // result type; void-typed ops carry types::prim_void()
    u32             a;              // operand slot — meaning is per-opcode
    u32             b;              // operand slot / extra index — meaning is per-opcode
    u64             imm;            // const bits or byte count, per-opcode
}

export enum Opcode : u16 {
INVALID = 0,

// constants + definitions
ConstInt,
ConstFloat,
ConstBool,
ConstNull,
ConstStr,
Undef,
Param,

// memory
Alloca,
Zero,
Load,
Store,
Memcpy,
FieldAddr,
IndexAddr,
GlobalAddr,
FnAddr,

// slices
SliceMake,
SlicePtr,
SliceLen,

// arithmetic / bitwise / comparison
Add,
Sub,
Mul,
Div,
Rem,
And,
Or,
Xor,
Shl,
Shr,
CmpEq,
CmpNe,
CmpLt,
CmpLe,
CmpGt,
CmpGe,
Neg,
BitNot,
Not,

// conversion
Cast,

// calls / phis / debug
Call,
Phi,
DbgValue,

// terminators  [TERM_FIRST..TERM_LAST]
Br,
CondBr,
SwitchBr,
Ret,
Unreachable,
TERM_FIRST = Br,
TERM_LAST = Unreachable,
}

export fn bool is_terminator(Opcode op) {
    return op >= Opcode::TERM_FIRST && op <= Opcode::TERM_LAST;
}

// CAST DERIVATION ////////////////////////////////////////////////////////////////

export enum CastOp : u8 {
    Nop,
    Trunc,
    SExt,
    ZExt,
    SIToFP,
    UIToFP,
    FPToSI,
    FPToUI,
    FPExt,
    FPTrunc,
    PtrToInt,
    IntToPtr,
    ArrayToElemPtr,     // array -> pointer: address of element 0 (a GEP, realized by lower)
    ArrayToSlice,       // array -> slice:   {elem0 ptr, count}   (a SliceMake, realized by lower)
    NullToSlice,        // null  -> slice:   {null, 0}            (a ConstNull, realized by lower)
}

// Only ever called on an is_castable pair; a -> bool never is one (truthiness is cond_test).
export fn CastOp cast_op(types::Ty* src, types::Ty* dst) {
    types::Ty* source = cast_reduce(src);
    types::Ty* dest = cast_reduce(dst);

    if(types::is_slice(dest)) {
        if(types::is_array(source)) { return CastOp::ArrayToSlice; }
        if(types::is_slice(source)) { return CastOp::Nop; }
        return CastOp::NullToSlice;
    }
    if(types::is_array(source) && types::is_ptr(dest)) { return CastOp::ArrayToElemPtr; }

    bool source_is_int = types::is_int(source) || types::is_bool(source);
    bool dest_is_int = types::is_int(dest) || types::is_bool(dest);

    if(source_is_int && dest_is_int) {
        u32 source_width = int_width(source);
        u32 dest_width = int_width(dest);
        if(dest_width < source_width) { return CastOp::Trunc; }
        if(dest_width > source_width) {
            if(types::is_signed_int(source)) { return CastOp::SExt; }
            return CastOp::ZExt;
        }
        return CastOp::Nop;
    }
    if(source_is_int && types::is_float(dest)) {
        if(types::is_signed_int(source)) { return CastOp::SIToFP; }
        return CastOp::UIToFP;
    }
    if(types::is_float(source) && dest_is_int) {
        if(types::is_signed_int(dest)) { return CastOp::FPToSI; }
        return CastOp::FPToUI;
    }
    if(types::is_float(source) && types::is_float(dest)) {
        if(float_width(dest) > float_width(source)) { return CastOp::FPExt; }
        if(float_width(dest) < float_width(source)) { return CastOp::FPTrunc; }
        return CastOp::Nop;
    }

    bool source_is_ptr = types::is_ptr(source) || source.kind == types::TypeKind::FnPtr;
    bool dest_is_ptr = types::is_ptr(dest) || dest.kind == types::TypeKind::FnPtr;
    if(source_is_ptr && dest_is_ptr) { return CastOp::Nop; }
    if(source_is_ptr && dest_is_int) { return CastOp::PtrToInt; }
    if(source_is_int && dest_is_ptr) { return CastOp::IntToPtr; }
    return CastOp::Nop;
}

// A pointer condition is PtrNonNull (compare != null), never a truncation to its low bit.
export enum CondTest : u8 {
    AsBool,
    IntNonZero,
    PtrNonNull,
    SliceNonEmpty,
}

export fn CondTest cond_test(types::Ty* t) {
    types::Ty* reduced = cast_reduce(t);
    if(types::is_bool(reduced)) { return CondTest::AsBool; }
    if(types::is_slice(reduced)) { return CondTest::SliceNonEmpty; }
    if(types::is_ptr(reduced) || reduced.kind == types::TypeKind::FnPtr) { return CondTest::PtrNonNull; }
    return CondTest::IntNonZero;
}

fn types::Ty* cast_reduce(types::Ty* t) {
    if(t.kind == types::TypeKind::Enum) { return types::enum_base_type(t); }
    return t;
}

fn u32 int_width(types::Ty* t) {
    if(types::is_bool(t)) { return 1; }
    switch(t.prim) {
    case types::PrimitiveKind::I8:
    case types::PrimitiveKind::U8:  { return 8; }
    case types::PrimitiveKind::I16:
    case types::PrimitiveKind::U16: { return 16; }
    case types::PrimitiveKind::I32:
    case types::PrimitiveKind::U32: { return 32; }
    case types::PrimitiveKind::I64:
    case types::PrimitiveKind::U64: { return 64; }
    else { return 0; }
    }
    return 0;
}

fn u32 float_width(types::Ty* t) {
    if(t.prim == types::PrimitiveKind::F32) { return 32; }
    return 64;
}

// MODULE + FUNCTION CONSTRUCTION //////////////////////////////////////////////////

export fn SapirModule* new_module(arena::Arena* a, symbol::Symbol* name) {
    SapirModule* m = (SapirModule*)arena::alloc(a, sizeof(SapirModule));
    sys::memset(m, 0, sizeof(SapirModule));
    m.name = name;
    return m;
}

export fn u32 add_decl(arena::Arena* a, SapirModule* m, SapirDecl decl) {
    if(m.decls.len == m.decls_cap) {
        u64 new_cap = 8;
        if(m.decls_cap > 0) { new_cap = m.decls_cap * 2; }
        m.decls.ptr = (SapirDecl*)arena::realloc_grow(a, (void*)m.decls.ptr, m.decls.len * sizeof(SapirDecl), new_cap * sizeof(SapirDecl));
        m.decls_cap = new_cap;
    }
    u32 index = (u32)m.decls.len;
    m.decls[index] = decl;
    m.decls.len += 1;
    return index;
}

// Returns an index rather than a pointer because the backing array may reallocate.
export fn u32 add_fn(arena::Arena* a, SapirModule* m) {
    if(m.fns.len == m.fns_cap) {
        u64 new_cap = 8;
        if(m.fns_cap > 0) { new_cap = m.fns_cap * 2; }
        m.fns.ptr = (SapirFn*)arena::realloc_grow(a, (void*)m.fns.ptr, m.fns.len * sizeof(SapirFn), new_cap * sizeof(SapirFn));
        m.fns_cap = new_cap;
    }
    u32 index = (u32)m.fns.len;
    sys::memset(&m.fns[index], 0, sizeof(SapirFn));
    m.fns.len += 1;
    return index;
}

export fn u32 add_global(arena::Arena* a, SapirModule* m, SapirGlobal global) {
    if(m.globals.len == m.globals_cap) {
        u64 new_cap = 8;
        if(m.globals_cap > 0) { new_cap = m.globals_cap * 2; }
        m.globals.ptr = (SapirGlobal*)arena::realloc_grow(a, (void*)m.globals.ptr, m.globals.len * sizeof(SapirGlobal), new_cap * sizeof(SapirGlobal));
        m.globals_cap = new_cap;
    }
    u32 index = (u32)m.globals.len;
    m.globals[index] = global;
    m.globals.len += 1;
    return index;
}

export fn u32 new_block(arena::Arena* a, SapirFn* func) {
    if(func.blocks.len == func.blocks_cap) {
        u64 new_cap = 8;
        if(func.blocks_cap > 0) { new_cap = func.blocks_cap * 2; }
        func.blocks.ptr = (SapirBlock*)arena::realloc_grow(a, (void*)func.blocks.ptr, func.blocks.len * sizeof(SapirBlock), new_cap * sizeof(SapirBlock));
        func.blocks_cap = new_cap;
    }
    u32 block_id = (u32)func.blocks.len;
    sys::memset(&func.blocks[block_id], 0, sizeof(SapirBlock));
    func.blocks[block_id].body_start = INVALID_ID;
    func.blocks[block_id].body_end = INVALID_ID;
    func.blocks.len += 1;
    return block_id;
}

export fn u32 add_inst(arena::Arena* a, SapirFn* func, Inst inst) {
    if(func.insts.len == func.insts_cap) {
        u64 new_cap = 16;
        if(func.insts_cap > 0) { new_cap = func.insts_cap * 2; }
        func.insts.ptr = (Inst*)arena::realloc_grow(a, (void*)func.insts.ptr, func.insts.len * sizeof(Inst), new_cap * sizeof(Inst));
        func.insts_cap = new_cap;
    }
    u32 value_id = (u32)func.insts.len;
    func.insts[value_id] = inst;
    func.insts.len += 1;
    return value_id;
}

export fn u32 add_extra(arena::Arena* a, SapirFn* func, u32 value) {
    if(func.extra.len == func.extra_cap) {
        u64 new_cap = 16;
        if(func.extra_cap > 0) { new_cap = func.extra_cap * 2; }
        func.extra.ptr = (u32*)arena::realloc_grow(a, (void*)func.extra.ptr, func.extra.len * sizeof(u32), new_cap * sizeof(u32));
        func.extra_cap = new_cap;
    }
    u32 index = (u32)func.extra.len;
    func.extra[index] = value;
    func.extra.len += 1;
    return index;
}

export fn u32 add_var(arena::Arena* a, SapirFn* func, SapirVar var) {
    if(func.vars.len == func.vars_cap) {
        u64 new_cap = 8;
        if(func.vars_cap > 0) { new_cap = func.vars_cap * 2; }
        func.vars.ptr = (SapirVar*)arena::realloc_grow(a, (void*)func.vars.ptr, func.vars.len * sizeof(SapirVar), new_cap * sizeof(SapirVar));
        func.vars_cap = new_cap;
    }
    u32 index = (u32)func.vars.len;
    func.vars[index] = var;
    func.vars.len += 1;
    return index;
}

// Pred order must stay stable: phi incomings line up positionally with the pred list.
export fn void add_pred(arena::Arena* a, SapirFn* func, u32 block, u32 pred) {
    SapirBlock* target = &func.blocks[block];
    if(target.preds.len == target.preds_cap) {
        u64 new_cap = 4;
        if(target.preds_cap > 0) { new_cap = target.preds_cap * 2; }
        target.preds.ptr = (u32*)arena::realloc_grow(a, (void*)target.preds.ptr, target.preds.len * sizeof(u32), new_cap * sizeof(u32));
        target.preds_cap = new_cap;
    }
    target.preds[target.preds.len] = pred;
    target.preds.len += 1;
}

export fn void add_phi_to_block(arena::Arena* a, SapirFn* func, u32 block, u32 phi_id) {
    SapirBlock* target = &func.blocks[block];
    if(target.phis.len == target.phis_cap) {
        u64 new_cap = 4;
        if(target.phis_cap > 0) { new_cap = target.phis_cap * 2; }
        target.phis.ptr = (u32*)arena::realloc_grow(a, (void*)target.phis.ptr, target.phis.len * sizeof(u32), new_cap * sizeof(u32));
        target.phis_cap = new_cap;
    }
    target.phis[target.phis.len] = phi_id;
    target.phis.len += 1;
}

// Seeds a/b to INVALID_ID so callers only set the operand slots their opcode uses.
export fn Inst new_inst(Opcode op, types::Ty* ty, u32 src_pos) {
    Inst inst;
    sys::memset(&inst, 0, sizeof(Inst));
    inst.op = op;
    inst.ty = ty;
    inst.src_pos = src_pos;
    inst.a = INVALID_ID;
    inst.b = INVALID_ID;
    return inst;
}
