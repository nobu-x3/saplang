// Microsoft x64 argument classification. Simpler than SysV: an aggregate of exactly 1, 2, 4 or 8
// bytes rides in one integer register as if it were an integer of that size — a struct of two
// floats included, since only scalar floats reach XMM — and every other aggregate goes by reference.

import types;
import mem;

export enum ArgKind : u8 {
    Ignore,     // void or zero-sized: no argument at all
    Direct,     // passed as its own type
    Coerce,     // passed as one eightbyte-sized scalar
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
    if(size != 1 && size != 2 && size != 4 && size != 8) {
        info.kind = ArgKind::Memory;
        return info;
    }
    if(size == EIGHTBYTE && is_sole_pointer(t)) {
        info.kind = ArgKind::Coerce;
        info.count = 1;
        info.eightbytes[0] = EightbyteKind::Pointer;
        info.widths[0] = (u8)EIGHTBYTE;
        return info;
    }
    info.kind = ArgKind::Coerce;
    info.count = 1;
    info.eightbytes[0] = EightbyteKind::Integer;
    info.widths[0] = (u8)size;
    return info;
}

export fn FnAbi* classify_fn(types::Ty* fnty, mem::Allocator a) {
    types::Ty*[] declared = fnty.data.fn_ptr.params;
    FnAbi* abi = (FnAbi*)mem::alloc_bytes(a, sizeof(FnAbi));
    ArgInfo* infos = (ArgInfo*)mem::alloc_bytes(a, (declared.len + 1) * sizeof(ArgInfo));
    u32* firsts = (u32*)mem::alloc_bytes(a, (declared.len + 1) * sizeof(u32));
    abi.ret = classify(fnty.data.fn_ptr.ret);
    abi.sret = abi.ret.kind == ArgKind::Memory;

    u32 next = 0;
    if(abi.sret) { next = 1; }
    // No register accounting: an argument's class here does not depend on how many precede it.
    for(u64 i = 0; i < declared.len; i += 1) {
        infos[i] = classify(declared[i]);
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

fn u32 llvm_param_count(ArgInfo* info) {
    switch(info.kind) {
    case ArgKind::Ignore: { return 0; }
    case ArgKind::Coerce: { return (u32)info.count; }
    else { return 1; }
    }
    return 1;
}

fn bool is_aggregate(types::Ty* t) {
    return t.kind == types::TypeKind::Struct || t.kind == types::TypeKind::Union
        || t.kind == types::TypeKind::Array || t.kind == types::TypeKind::Slice;
}

// A struct that bottoms out in one pointer keeps its type, so LLVM still sees a pointer.
fn bool is_sole_pointer(types::Ty* t) {
    if(t == null) { return false; }
    switch(t.kind) {
    case types::TypeKind::Pointer: { return true; }
    case types::TypeKind::FnPtr:   { return true; }
    case types::TypeKind::Struct: {
        if(types::field_count(t) != 1) { return false; }
        return is_sole_pointer(types::field_type(t, 0));
    }
    case types::TypeKind::Array: {
        if(t.data.array.count != 1) { return false; }
        return is_sole_pointer(t.data.array.elem);
    }
    else { return false; }
    }
    return false;
}