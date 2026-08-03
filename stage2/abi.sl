// SysV AMD64 argument classification. An aggregate of at most two eightbytes rides
// in registers with its fields packed together — {f32,f32} shares one XMM, {i32,i32}
// one GPR — so a backend cannot just hand LLVM the struct and let it split fields.
// Anything larger, or short of registers, travels through memory.

import types;
import mem;

export enum ArgKind : u8 {
    Ignore,     // void or zero-sized: no argument at all
    Direct,     // passed as its own type
    Coerce,     // passed as one or two eightbyte-sized scalars
    Memory,     // passed indirectly: byval pointer, or sret for a return
}

export enum EightbyteKind : u8 {
    None,
    Integer,    // iN, N = 8 * width
    Pointer,
    Float,
    Float2,     // <2 x float>
    Double,
}

export struct ArgInfo {
    ArgKind          kind;
    u8               count;         // eightbytes, when Coerce
    EightbyteKind[2] eightbytes;
    u8[2]            widths;        // bytes each eightbyte covers
}

export struct FnAbi {
    ArgInfo   ret;
    ArgInfo[] params;
    u32[]     first_llvm_param;     // per declared param: index of its first LLVM parameter
    u32       llvm_param_count;
    bool      sret;
}

export const u32 EIGHTBYTE = 8;

const u32 MAX_REGISTER_SIZE = 16;
const u32 INTEGER_REGISTERS = 6;
const u32 SSE_REGISTERS = 8;

enum LeafClass : u8 {
    None,
    Sse,
    Integer,
}

struct Eightbyte {
    LeafClass cls;
    u32       end;              // bytes covered, relative to the eightbyte
    u32       leaves;
    u32       f32_leaves;
    bool      sole_pointer;     // one pointer leaf filling the whole eightbyte
}

export fn ArgInfo classify(types::Ty* t) {
    ArgInfo info;
    info.kind = ArgKind::Direct;
    info.count = 0;
    info.eightbytes[0] = EightbyteKind::None;
    info.eightbytes[1] = EightbyteKind::None;
    info.widths[0] = 0;
    info.widths[1] = 0;
    if(t == null || types::is_void(t)) {
        info.kind = ArgKind::Ignore;
        return info;
    }
    if(!is_aggregate(t)) { return info; }
    u32 size = types::size_of(null, t);
    if(size == 0) { return info; }   // no bytes to place, but still a value sapir hands around
    if(size > MAX_REGISTER_SIZE) {
        info.kind = ArgKind::Memory;
        return info;
    }
    Eightbyte[2] eightbytes;
    for(u32 i = 0; i < 2; i += 1) {
        eightbytes[i].cls = LeafClass::None;
        eightbytes[i].end = 0;
        eightbytes[i].leaves = 0;
        eightbytes[i].f32_leaves = 0;
        eightbytes[i].sole_pointer = false;
    }
    if(!classify_leaves(&eightbytes[0], t, 0)) {
        info.kind = ArgKind::Memory;
        return info;
    }
    u32 count = (size + EIGHTBYTE - 1) / EIGHTBYTE;
    info.kind = ArgKind::Coerce;
    info.count = (u8)count;
    for(u32 i = 0; i < count; i += 1) {
        info.eightbytes[i] = eightbyte_kind(&eightbytes[i]);
        if(eightbytes[i].end == 0) { info.widths[i] = (u8)EIGHTBYTE; }
        else { info.widths[i] = (u8)eightbytes[i].end; }
    }
    return info;
}

fn bool is_sse(EightbyteKind kind) {
    return kind == EightbyteKind::Float || kind == EightbyteKind::Float2 || kind == EightbyteKind::Double;
}

// LLVM parameters this argument occupies; Coerce spends one per eightbyte.
fn u32 llvm_param_count(ArgInfo* info) {
    switch(info.kind) {
    case ArgKind::Ignore: { return 0; }
    case ArgKind::Coerce: { return (u32)info.count; }
    else { return 1; }
    }
    return 1;
}

export fn FnAbi* classify_fn(types::Ty* fnty, mem::Allocator a) {
    types::Ty*[] declared = fnty.data.fn_ptr.params;
    FnAbi* abi = (FnAbi*)mem::alloc(a, sizeof(FnAbi));
    ArgInfo* infos = (ArgInfo*)mem::alloc(a, (declared.len + 1) * sizeof(ArgInfo));
    u32* firsts = (u32*)mem::alloc(a, (declared.len + 1) * sizeof(u32));
    abi.ret = classify(fnty.data.fn_ptr.ret);
    abi.sret = abi.ret.kind == ArgKind::Memory;

    u32 integer_left = INTEGER_REGISTERS;
    u32 sse_left = SSE_REGISTERS;
    u32 next = 0;
    if(abi.sret) {
        integer_left -= 1;
        next = 1;
    }
    for(u64 i = 0; i < declared.len; i += 1) {
        ArgInfo info = classify(declared[i]);
        if(info.kind == ArgKind::Coerce) {
            u32 need_integer = 0;
            u32 need_sse = 0;
            for(u32 k = 0; k < (u32)info.count; k += 1) {
                if(is_sse(info.eightbytes[k])) { need_sse += 1; } else { need_integer += 1; }
            }
            // SysV puts the whole aggregate on the stack rather than splitting it across a register and memory.
            if(need_integer > integer_left || need_sse > sse_left) {
                info.kind = ArgKind::Memory;
            } else {
                integer_left -= need_integer;
                sse_left -= need_sse;
            }
        } else if(info.kind == ArgKind::Direct && types::size_of(null, declared[i]) > 0) {
            if(types::is_float(declared[i])) {
                if(sse_left > 0) { sse_left -= 1; }
            } else {
                if(integer_left > 0) { integer_left -= 1; }
            }
        }
        infos[i] = info;
        firsts[i] = next;
        next += llvm_param_count(&infos[i]);
    }
    ArgInfo[] params = {infos, declared.len};
    u32[] first_llvm_param = {firsts, declared.len};
    abi.params = params;
    abi.first_llvm_param = first_llvm_param;
    abi.llvm_param_count = next;
    return abi;
}

fn bool is_aggregate(types::Ty* t) {
    return t.kind == types::TypeKind::Struct || t.kind == types::TypeKind::Union
        || t.kind == types::TypeKind::Array || t.kind == types::TypeKind::Slice;
}

fn EightbyteKind eightbyte_kind(Eightbyte* eb) {
    if(eb.cls == LeafClass::Sse) {
        if(eb.end <= 4) { return EightbyteKind::Float; }
        if(eb.leaves == 2 && eb.f32_leaves == 2) { return EightbyteKind::Float2; }
        return EightbyteKind::Double;
    }
    if(eb.sole_pointer) { return EightbyteKind::Pointer; }
    return EightbyteKind::Integer;
}

// Walks every scalar leaf at its byte offset. False means the type must go to memory.
fn bool classify_leaves(Eightbyte* eightbytes, types::Ty* t, u32 offset) {
    if(t == null) { return false; }
    switch(t.kind) {
    case types::TypeKind::Primitive: {
        if(types::is_void(t)) { return false; }
        u32 size = types::size_of(null, t);
        if(types::is_float(t)) { return add_leaf(eightbytes, offset, size, LeafClass::Sse, size == 4, false); }
        return add_leaf(eightbytes, offset, size, LeafClass::Integer, false, false);
    }
    case types::TypeKind::Pointer: { return add_leaf(eightbytes, offset, EIGHTBYTE, LeafClass::Integer, false, true); }
    case types::TypeKind::FnPtr:   { return add_leaf(eightbytes, offset, EIGHTBYTE, LeafClass::Integer, false, true); }
    case types::TypeKind::Enum:    { return classify_leaves(eightbytes, types::enum_base_type(t), offset); }
    case types::TypeKind::Slice: {
        if(!add_leaf(eightbytes, offset, EIGHTBYTE, LeafClass::Integer, false, true)) { return false; }
        return add_leaf(eightbytes, offset + EIGHTBYTE, EIGHTBYTE, LeafClass::Integer, false, false);
    }
    case types::TypeKind::Struct: {
        u64 count = types::field_count(t);
        for(u64 i = 0; i < count; i += 1) {
            if(!classify_leaves(eightbytes, types::field_type(t, i), offset + types::field_offset(t, i))) { return false; }
        }
        return true;
    }
    case types::TypeKind::Union: {
        u64 count = types::field_count(t);
        for(u64 i = 0; i < count; i += 1) {
            if(!classify_leaves(eightbytes, types::field_type(t, i), offset)) { return false; }
        }
        return true;
    }
    case types::TypeKind::Array: {
        types::Ty* elem = t.data.array.elem;
        if(elem == null) { return false; }
        u32 stride = types::size_of(null, elem);
        if(stride == 0) { return false; }
        for(u64 i = 0; i < t.data.array.count; i += 1) {
            if(!classify_leaves(eightbytes, elem, offset + (u32)i * stride)) { return false; }
        }
        return true;
    }
    else { return false; }
    }
    return false;
}

fn bool add_leaf(Eightbyte* eightbytes, u32 offset, u32 size, LeafClass cls, bool is_f32, bool is_pointer) {
    if(size == 0) { return true; }
    u32 index = offset / EIGHTBYTE;
    if(index > 1) { return false; }
    if((offset + size - 1) / EIGHTBYTE != index) { return false; }   // a straddling leaf is unaligned: SysV says memory
    Eightbyte* eb = &eightbytes[index];
    u32 end = offset - index * EIGHTBYTE + size;
    if(end > eb.end) { eb.end = end; }
    if(eb.cls != LeafClass::Integer) {                              // INTEGER wins the merge
        if(cls == LeafClass::Integer) { eb.cls = LeafClass::Integer; } else { eb.cls = LeafClass::Sse; }
    }
    eb.leaves += 1;
    if(is_f32) { eb.f32_leaves += 1; }
    eb.sole_pointer = is_pointer && eb.leaves == 1 && size == EIGHTBYTE;
    return true;
}
