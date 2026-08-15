import types;
import ast;
import sys;

export enum ValueKind : u16 {
    Int,
    Float,
    Bool,
    Char,
    Bytes,
    TYPE,
    Struct,
    Union,
    Array,
    FnRef,
    GlobalRef,
    Null,
    Void,
    Error,
}

// Which member a union literal set, and what it set it to.
export struct UnionSlot {
    u64    index;
    Value* value;
}

export union ValueData {
    i64               i;
    f64               f;
    bool              b;
    const u8[]        bytes;
    types::Ty*      type_ref;
    Value[]           elems;
    UnionSlot         union_slot;
    ast::FnDeclNode*  fn_ref;
    ast::VarDeclNode* global_ref;
}

export struct Value {
    ValueKind    kind;
    types::Ty* ty;          // canonical type of this value; null for type/error values
    ValueData    data;
}

export fn Value val_int(i64 v, types::Ty* ty) {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::Int;
    r.ty = ty;
    r.data.i = v;
    return r;
}

export fn Value val_float(f64 v, types::Ty* ty) {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::Float;
    r.ty = ty;
    r.data.f = v;
    return r;
}

export fn Value val_bool(bool b) {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::Bool;
    r.ty = types::prim_bool();
    r.data.b = b;
    return r;
}

export fn Value val_bytes(const u8[] bytes, types::Ty* ty) {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::Bytes;
    r.ty = ty;
    r.data.bytes = bytes;
    return r;
}

export fn Value val_type(types::Ty* t) {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::TYPE;
    r.ty = null;
    r.data.type_ref = t;
    return r;
}

export fn Value val_struct(types::Ty* ty, Value[] fields) {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::Struct;
    r.ty = ty;
    r.data.elems = fields;
    return r;
}

export fn Value val_union(types::Ty* ty, u64 index, Value* value) {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::Union;
    r.ty = ty;
    r.data.union_slot.index = index;
    r.data.union_slot.value = value;
    return r;
}

export fn Value val_array(types::Ty* ty, Value[] elems) {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::Array;
    r.ty = ty;
    r.data.elems = elems;
    return r;
}

export fn Value val_fn(ast::FnDeclNode* func, types::Ty* ty) {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::FnRef;
    r.ty = ty;
    r.data.fn_ref = func;
    return r;
}

// &<module-level var>: a link-time address, not a foldable value.
export fn Value val_global_ref(ast::VarDeclNode* var_decl, types::Ty* ty) {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::GlobalRef;
    r.ty = ty;
    r.data.global_ref = var_decl;
    return r;
}

export fn Value val_null(types::Ty* ty) {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::Null;
    r.ty = ty;
    return r;
}

export fn Value val_void() {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::Void;
    r.ty = types::prim_void();
    return r;
}

export fn Value val_error() {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::Error;
    r.ty = null;
    return r;
}
