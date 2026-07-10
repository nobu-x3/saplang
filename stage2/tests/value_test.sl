import testing;
import value;
import types;
import arena;

fn i32 scalar_values(arena::Arena* a, u8[] m) {
    value::Value i = value::val_int(42, types::prim_i32());
    if(!testing::expect_eq((u64)i.kind, (u64)value::ValueKind::Int, m)) { return -1; }
    if(!testing::expect_eq((u64)i.data.i, (u64)42, m)) { return -2; }
    if(!testing::expect_eq((void*)i.ty, (void*)types::prim_i32(), m)) { return -3; }

    value::Value f = value::val_float(3.5, types::prim_f64());
    if(!testing::expect_eq((u64)f.kind, (u64)value::ValueKind::Float, m)) { return -4; }
    if(f.data.f != 3.5) { return -5; }

    value::Value b = value::val_bool(true);
    if(!testing::expect_eq((u64)b.kind, (u64)value::ValueKind::Bool, m)) { return -6; }
    if(!b.data.b) { return -7; }
    if(!testing::expect_eq((void*)b.ty, (void*)types::prim_bool(), m)) { return -8; }
    return 0;
}

fn i32 ref_values(arena::Arena* a, u8[] m) {
    value::Value t = value::val_type(types::prim_u32());
    if(!testing::expect_eq((u64)t.kind, (u64)value::ValueKind::Type, m)) { return -1; }
    if(!testing::expect_eq((void*)t.data.type_ref, (void*)types::prim_u32(), m)) { return -2; }

    u8[] hi = "hi";
    value::Value by = value::val_bytes(hi, null);
    if(!testing::expect_eq((u64)by.kind, (u64)value::ValueKind::Bytes, m)) { return -3; }
    if(!testing::expect_eq(by.data.bytes.len, (u64)2, m)) { return -4; }

    value::Value fref = value::val_fn(null, null);
    if(!testing::expect_eq((u64)fref.kind, (u64)value::ValueKind::FnRef, m)) { return -5; }
    if(!testing::expect_eq((void*)fref.data.fn_ref, null, m)) { return -6; }

    value::Value n = value::val_null(types::prim_i32());
    if(!testing::expect_eq((u64)n.kind, (u64)value::ValueKind::Null, m)) { return -7; }
    if(!testing::expect_eq((void*)n.ty, (void*)types::prim_i32(), m)) { return -8; }
    return 0;
}

fn i32 composite_values(arena::Arena* a, u8[] m) {
    value::Value[2] fields;
    fields[0] = value::val_int(1, types::prim_i32());
    fields[1] = value::val_int(2, types::prim_i32());
    value::Value[] slice = {&fields[0], 2};

    value::Value s = value::val_struct(null, slice);
    if(!testing::expect_eq((u64)s.kind, (u64)value::ValueKind::Struct, m)) { return -1; }
    if(!testing::expect_eq(s.data.elems.len, (u64)2, m)) { return -2; }
    if(!testing::expect_eq((u64)s.data.elems[1].data.i, (u64)2, m)) { return -3; }

    value::Value ar = value::val_array(null, slice);
    if(!testing::expect_eq((u64)ar.kind, (u64)value::ValueKind::Array, m)) { return -4; }
    if(!testing::expect_eq(ar.data.elems.len, (u64)2, m)) { return -5; }
    return 0;
}

fn i32 void_and_error(arena::Arena* a, u8[] m) {
    value::Value v = value::val_void();
    if(!testing::expect_eq((u64)v.kind, (u64)value::ValueKind::Void, m)) { return -1; }
    value::Value e = value::val_error();
    if(!testing::expect_eq((u64)e.kind, (u64)value::ValueKind::Error, m)) { return -2; }
    return 0;
}

fn i32 main() {
    testing::init();
    u8[] suite = "Value Tests";
    testing::add(suite, "scalar_values",    &scalar_values);
    testing::add(suite, "ref_values",       &ref_values);
    testing::add(suite, "composite_values", &composite_values);
    testing::add(suite, "void_and_error",   &void_and_error);
    return testing::run();
}
