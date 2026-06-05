import ast;
import interner;
import io;
import symbol;
import types;

export fn void print(types::Type* t, interner::Interner* names, io::OutBuf* out) {
    if(t == null) { io::outbuf_write(out, "<null>"); return; }
    switch(t.kind) {
        case types::TypeKind::Primitive: {
            io::outbuf_write(out, prim_name(t.prim));
        }
        case types::TypeKind::Pointer: {
            if(((u8)t.flags & (u8)types::LayoutFlags::Const) != 0) { io::outbuf_write(out, "const "); }
            print(t.data.pointee, names, out);
            io::outbuf_write_byte(out, '*');
        }
        case types::TypeKind::Array: {
            print(t.data.array.elem, names, out);
            io::outbuf_write_byte(out, '[');
            io::outbuf_write_u64(out, t.data.array.count);
            io::outbuf_write_byte(out, ']');
        }
        case types::TypeKind::Slice: {
            print(t.data.slice_elem, names, out);
            io::outbuf_write(out, "[]");
        }
        case types::TypeKind::FnPtr: {
            io::outbuf_write(out, "fn* ");
            print(t.data.fn_ptr.ret, names, out);
            io::outbuf_write_byte(out, '(');
            for(u64 i = 0; i < t.data.fn_ptr.params.len; i += 1) {
                if(i > 0) { io::outbuf_write(out, ", "); }
                print(t.data.fn_ptr.params[i], names, out);
            }
            if(t.data.fn_ptr.is_variadic) {
                if(t.data.fn_ptr.params.len > 0) { io::outbuf_write(out, ", "); }
                io::outbuf_write(out, "...");
            }
            io::outbuf_write_byte(out, ')');
        }
        case types::TypeKind::Struct: {
            print_decl_name(out, names, ((ast::StructDeclNode*)t.data.struct_decl).qualified_name);
        }
        case types::TypeKind::Union: {
            print_decl_name(out, names, ((ast::UnionDeclNode*)t.data.union_decl).qualified_name);
        }
        case types::TypeKind::Enum: {
            print_decl_name(out, names, ((ast::EnumDeclNode*)t.data.enum_decl).qualified_name);
        }
        case types::TypeKind::ComptimeType: {
            io::outbuf_write(out, "Type");
        }
        else { io::outbuf_write(out, "<unknown>"); }
    }
}

export fn u8[] print_to_arena(types::Type* t, interner::Interner* names, arena::Arena* a) {
    io::OutBuf b;
    io::outbuf_init(&b, a, 64);
    print(t, names, &b);
    return io::outbuf_bytes(&b);
}

fn u8[] prim_name(types::PrimitiveKind p) {
    switch(p) {
        case types::PrimitiveKind::I8:   { return "i8"; }
        case types::PrimitiveKind::I16:  { return "i16"; }
        case types::PrimitiveKind::I32:  { return "i32"; }
        case types::PrimitiveKind::I64:  { return "i64"; }
        case types::PrimitiveKind::U8:   { return "u8"; }
        case types::PrimitiveKind::U16:  { return "u16"; }
        case types::PrimitiveKind::U32:  { return "u32"; }
        case types::PrimitiveKind::U64:  { return "u64"; }
        case types::PrimitiveKind::F32:  { return "f32"; }
        case types::PrimitiveKind::F64:  { return "f64"; }
        case types::PrimitiveKind::BOOL: { return "bool"; }
        case types::PrimitiveKind::VOID: { return "void"; }
        else { return "<none>"; }
    }
    return "<none>";
}

fn void print_decl_name(io::OutBuf* out, interner::Interner* names, symbol::Symbol* name) {
    if(name == null || names == null) {
        io::outbuf_write(out, "<anon>");
        return;
    }
    io::outbuf_write(out, interner::symbol_str(name, names));
}
