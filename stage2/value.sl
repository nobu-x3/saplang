import types;
import ast;
import sys;

export enum ValueKind : u16 {
    Int,
    Float,
    Bool,
    Char,
    Bytes,
    Type,
    Struct,
    Array,
    FnRef,
    Null,
    Void,
    Error,
}

export union ValueData {
    i64               i;
    f64               f;
    bool              b;
    u8[]              bytes;
    types::Type*      type_ref;
    Value[]           elems;
    ast::FnDeclNode*  fn_ref;
}

export struct Value {
    ValueKind    kind;
    types::Type* ty;          // canonical type of this value; null for type/error values
    ValueData    data;
}

export fn Value val_int(i64 v, types::Type* ty) {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::Int;
    r.ty = ty;
    r.data.i = v;
    return r;
}

export fn Value val_float(f64 v, types::Type* ty) {
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

export fn Value val_bytes(u8[] bytes, types::Type* ty) {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::Bytes;
    r.ty = ty;
    r.data.bytes = bytes;
    return r;
}

export fn Value val_type(types::Type* t) {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::Type;
    r.ty = null;
    r.data.type_ref = t;
    return r;
}

export fn Value val_struct(types::Type* ty, Value[] fields) {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::Struct;
    r.ty = ty;
    r.data.elems = fields;
    return r;
}

export fn Value val_array(types::Type* ty, Value[] elems) {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::Array;
    r.ty = ty;
    r.data.elems = elems;
    return r;
}

export fn Value val_fn(ast::FnDeclNode* func, types::Type* ty) {
    Value r;
    sys::memset(&r, 0, sizeof(Value));
    r.kind = ValueKind::FnRef;
    r.ty = ty;
    r.data.fn_ref = func;
    return r;
}

export fn Value val_null(types::Type* ty) {
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
