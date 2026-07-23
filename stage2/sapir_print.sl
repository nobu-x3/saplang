import sapir;
import types;
import types_print;
import interner;
import symbol;
import io;
import arena;

export fn void print_module(sapir::SapirModule* m, io::OutBuf* out) {
    io::outbuf_write(out, "module ");
    write_sym(out, m.name);
    io::outbuf_write(out, "\n");
    for(u64 global_index = 0; global_index < m.globals.len; global_index += 1) {
        io::outbuf_write(out, "\n");
        print_global(m, &m.globals[global_index], out);
    }
    for(u64 fn_index = 0; fn_index < m.fns.len; fn_index += 1) {
        io::outbuf_write(out, "\n");
        print_fn(m, &m.fns[fn_index], out);
    }
}

export fn u8[] print_module_to_arena(sapir::SapirModule* m, arena::Arena* a) {
    io::OutBuf buf;
    io::outbuf_init(&buf, a, 256);
    print_module(m, &buf);
    return io::outbuf_bytes(&buf);
}

fn void print_global(sapir::SapirModule* m, sapir::SapirGlobal* global, io::OutBuf* out) {
    io::outbuf_write(out, "global ");
    io::outbuf_write(out, m.decls[global.decl_index].link_name);
    io::outbuf_write(out, ": ");
    types_print::print(m.decls[global.decl_index].ty, out);
    if(global.is_const) { io::outbuf_write(out, " const"); }
    io::outbuf_write(out, " = ");
    print_const_init(m, &global.init, out);
    io::outbuf_write(out, "\n");
}

fn void print_fn(sapir::SapirModule* m, sapir::SapirFn* func, io::OutBuf* out) {
    types::Type* fn_ty = m.decls[func.decl_index].ty;
    io::outbuf_write(out, "fn ");
    io::outbuf_write(out, m.decls[func.decl_index].link_name);
    io::outbuf_write(out, "(");
    for(u64 param_index = 0; param_index < fn_ty.data.fn_ptr.params.len; param_index += 1) {
        if(param_index > 0) { io::outbuf_write(out, ", "); }
        types_print::print(fn_ty.data.fn_ptr.params[param_index], out);
    }
    io::outbuf_write(out, ") -> ");
    types_print::print(fn_ty.data.fn_ptr.ret, out);
    io::outbuf_write(out, " {\n");

    for(u64 block_index = 0; block_index < func.blocks.len; block_index += 1) {
        sapir::SapirBlock* block = &func.blocks[block_index];
        io::outbuf_write(out, "b");
        io::outbuf_write_u64(out, block_index);
        io::outbuf_write(out, ":  ; preds:");
        for(u64 pred_index = 0; pred_index < block.preds.len; pred_index += 1) {
            if(pred_index > 0) { io::outbuf_write(out, ","); }
            io::outbuf_write(out, " b");
            io::outbuf_write_u64(out, (u64)block.preds[pred_index]);
        }
        io::outbuf_write(out, "\n");

        for(u64 phi_index = 0; phi_index < block.phis.len; phi_index += 1) {
            print_inst(m, func, block.phis[phi_index], out);
        }
        if(block.body_start == sapir::INVALID_ID) { continue; }
        for(u32 inst_id = block.body_start; inst_id < block.body_end; inst_id += 1) {
            if(func.insts[inst_id].op == sapir::Opcode::Phi) { continue; }   // a phi here belongs to another block's list
            print_inst(m, func, inst_id, out);
        }
    }
    io::outbuf_write(out, "}\n");
}

fn void print_inst(sapir::SapirModule* m, sapir::SapirFn* func, u32 inst_id, io::OutBuf* out) {
    sapir::Inst* inst = &func.insts[inst_id];
    io::outbuf_write(out, "    ");
    if(produces_value(inst)) {
        io::outbuf_write(out, "%");
        io::outbuf_write_u64(out, (u64)inst_id);
        io::outbuf_write(out, " = ");
    }
    io::outbuf_write(out, opcode_name(inst.op));

    switch(inst.op) {
    case sapir::Opcode::ConstInt: {
        write_ty_suffix(inst.ty, out);
        io::outbuf_write(out, " ");
        if(types::is_signed_int(inst.ty)) { io::outbuf_write_i64(out, (i64)inst.imm); }
        else { io::outbuf_write_u64(out, inst.imm); }
    }
    case sapir::Opcode::ConstFloat: {
        write_ty_suffix(inst.ty, out);
        io::outbuf_write(out, " 0f");
        io::outbuf_write_u64(out, inst.imm);
    }
    case sapir::Opcode::ConstBool: {
        io::outbuf_write(out, " ");
        io::outbuf_write_u64(out, inst.imm);
    }
    case sapir::Opcode::ConstNull: { write_ty_suffix(inst.ty, out); }
    case sapir::Opcode::ConstStr: {
        io::outbuf_write(out, " @");
        io::outbuf_write_u64(out, (u64)inst.a);
        io::outbuf_write(out, "+");
        io::outbuf_write_u64(out, (u64)inst.b);
    }
    case sapir::Opcode::Undef:  { write_ty_suffix(inst.ty, out); }
    case sapir::Opcode::Param: {
        write_ty_suffix(inst.ty, out);
        io::outbuf_write(out, " ");
        io::outbuf_write_u64(out, (u64)inst.a);
    }
    case sapir::Opcode::Alloca: { write_ty_suffix(inst.ty, out); }
    case sapir::Opcode::Zero: {
        write_operand(out, inst.a);
        io::outbuf_write(out, ", ");
        io::outbuf_write_u64(out, inst.imm);
    }
    case sapir::Opcode::Load: { write_ty_suffix(inst.ty, out); write_operand(out, inst.a); }
    case sapir::Opcode::Store: { write_operand(out, inst.a); io::outbuf_write(out, ","); write_operand(out, inst.b); }
    case sapir::Opcode::Memcpy: {
        write_operand(out, inst.a);
        io::outbuf_write(out, ",");
        write_operand(out, inst.b);
        io::outbuf_write(out, ", ");
        io::outbuf_write_u64(out, inst.imm);
    }
    case sapir::Opcode::FieldAddr: {
        write_operand(out, inst.a);
        io::outbuf_write(out, ", ");
        io::outbuf_write_u64(out, (u64)inst.b);
    }
    case sapir::Opcode::IndexAddr: { write_operand(out, inst.a); io::outbuf_write(out, ","); write_operand(out, inst.b); }
    case sapir::Opcode::GlobalAddr: {
        io::outbuf_write(out, ".");
        io::outbuf_write(out, m.decls[inst.a].link_name);
    }
    case sapir::Opcode::FnAddr: {
        io::outbuf_write(out, ".");
        io::outbuf_write(out, m.decls[inst.a].link_name);
    }
    case sapir::Opcode::SliceMake: { write_operand(out, inst.a); io::outbuf_write(out, ","); write_operand(out, inst.b); }
    case sapir::Opcode::SlicePtr: { write_ty_suffix(inst.ty, out); write_operand(out, inst.a); }
    case sapir::Opcode::SliceLen: { write_ty_suffix(inst.ty, out); write_operand(out, inst.a); }
    case sapir::Opcode::Add:
    case sapir::Opcode::Sub:
    case sapir::Opcode::Mul:
    case sapir::Opcode::Div:
    case sapir::Opcode::Rem:
    case sapir::Opcode::And:
    case sapir::Opcode::Or:
    case sapir::Opcode::Xor:
    case sapir::Opcode::Shl:
    case sapir::Opcode::Shr: {
        write_ty_suffix(inst.ty, out);
        write_operand(out, inst.a);
        io::outbuf_write(out, ",");
        write_operand(out, inst.b);
    }
    case sapir::Opcode::CmpEq:
    case sapir::Opcode::CmpNe:
    case sapir::Opcode::CmpLt:
    case sapir::Opcode::CmpLe:
    case sapir::Opcode::CmpGt:
    case sapir::Opcode::CmpGe: {
        write_ty_suffix(func.insts[inst.a].ty, out);       // result is bool; the operand type is what disambiguates
        write_operand(out, inst.a);
        io::outbuf_write(out, ",");
        write_operand(out, inst.b);
    }
    case sapir::Opcode::Cast: { write_ty_suffix(inst.ty, out); write_operand(out, inst.a); }
    case sapir::Opcode::Neg:
    case sapir::Opcode::BitNot:
    case sapir::Opcode::Not: { write_ty_suffix(inst.ty, out); write_operand(out, inst.a); }
    case sapir::Opcode::Call:      { print_call(m, func, inst, out); }
    case sapir::Opcode::Phi:       { write_ty_suffix(inst.ty, out); print_phi(func, inst, out); }
    case sapir::Opcode::DbgValue: {
        io::outbuf_write(out, " ");
        io::outbuf_write_u64(out, (u64)inst.a);
        io::outbuf_write(out, ",");
        write_operand(out, inst.b);
    }
    case sapir::Opcode::Br: { io::outbuf_write(out, " b"); io::outbuf_write_u64(out, (u64)inst.a); }
    case sapir::Opcode::CondBr:    { print_cond_br(func, inst, out); }
    case sapir::Opcode::SwitchBr:  { print_switch_br(func, inst, out); }
    case sapir::Opcode::Ret: {
        if(inst.a != sapir::INVALID_ID) { write_operand(out, inst.a); }
    }
    case sapir::Opcode::Unreachable: { }
    else {
        write_ty_suffix(inst.ty, out);
        if(inst.a != sapir::INVALID_ID) { write_operand(out, inst.a); }
        if(inst.b != sapir::INVALID_ID) { io::outbuf_write(out, ","); write_operand(out, inst.b); }
    }
    }
    io::outbuf_write(out, "\n");
}

fn void print_call(sapir::SapirModule* m, sapir::SapirFn* func, sapir::Inst* inst, io::OutBuf* out) {
    write_ty_suffix(inst.ty, out);
    io::outbuf_write(out, " ");
    bool is_indirect = ((u16)inst.flags & (u16)sapir::InstFlags::Indirect) != 0;
    if(is_indirect) {
        io::outbuf_write(out, "%");
        io::outbuf_write_u64(out, (u64)inst.a);
    } else {
        io::outbuf_write(out, m.decls[inst.a].link_name);
    }
    io::outbuf_write(out, "(");
    u32 arg_count = func.extra[inst.b];
    for(u32 arg_index = 0; arg_index < arg_count; arg_index += 1) {
        if(arg_index > 0) { io::outbuf_write(out, ", "); }
        io::outbuf_write(out, "%");
        io::outbuf_write_u64(out, (u64)func.extra[inst.b + 1 + arg_index]);
    }
    io::outbuf_write(out, ")");
}

fn void print_phi(sapir::SapirFn* func, sapir::Inst* inst, io::OutBuf* out) {
    io::outbuf_write(out, " [");
    u32 incoming_count = func.extra[inst.b];
    for(u32 incoming_index = 0; incoming_index < incoming_count; incoming_index += 1) {
        if(incoming_index > 0) { io::outbuf_write(out, ", "); }
        u32 pair_base = inst.b + 1 + incoming_index * 2;
        io::outbuf_write(out, "b");
        io::outbuf_write_u64(out, (u64)func.extra[pair_base]);
        io::outbuf_write(out, ": %");
        io::outbuf_write_u64(out, (u64)func.extra[pair_base + 1]);
    }
    io::outbuf_write(out, "]");
}

fn void print_cond_br(sapir::SapirFn* func, sapir::Inst* inst, io::OutBuf* out) {
    write_operand(out, inst.a);
    io::outbuf_write(out, ", b");
    io::outbuf_write_u64(out, (u64)func.extra[inst.b]);
    io::outbuf_write(out, ", b");
    io::outbuf_write_u64(out, (u64)func.extra[inst.b + 1]);
}

fn void print_switch_br(sapir::SapirFn* func, sapir::Inst* inst, io::OutBuf* out) {
    write_operand(out, inst.a);
    io::outbuf_write(out, ", default b");
    io::outbuf_write_u64(out, (u64)func.extra[inst.b]);
    u32 arm_count = func.extra[inst.b + 1];
    io::outbuf_write(out, " [");
    for(u32 arm_index = 0; arm_index < arm_count; arm_index += 1) {
        if(arm_index > 0) { io::outbuf_write(out, ", "); }
        u32 arm_base = inst.b + 2 + arm_index * 3;
        u64 low = (u64)func.extra[arm_base];
        u64 high = (u64)func.extra[arm_base + 1];
        io::outbuf_write_u64(out, (high << 32) | low);
        io::outbuf_write(out, ": b");
        io::outbuf_write_u64(out, (u64)func.extra[arm_base + 2]);
    }
    io::outbuf_write(out, "]");
}

fn void print_const_init(sapir::SapirModule* m, sapir::ConstInit* init, io::OutBuf* out) {
    switch(init.kind) {
    case sapir::ConstInitKind::Zero:  { io::outbuf_write(out, "zero"); }
    case sapir::ConstInitKind::Int: {
        if(types::is_signed_int(init.ty)) { io::outbuf_write_i64(out, init.i); }
        else { io::outbuf_write_u64(out, (u64)init.i); }
    }
    case sapir::ConstInitKind::Float: { io::outbuf_write(out, "0f"); io::outbuf_write_u64(out, *(u64*)&init.f); }
    case sapir::ConstInitKind::Bool:  { io::outbuf_write_u64(out, (u64)init.i); }
    case sapir::ConstInitKind::Null:  { io::outbuf_write(out, "null"); }
    case sapir::ConstInitKind::Bytes: {
        io::outbuf_write(out, "bytes[");
        io::outbuf_write_u64(out, init.bytes.len);
        io::outbuf_write(out, "]");
    }
    case sapir::ConstInitKind::Struct: {
        io::outbuf_write(out, "{ ");
        for(u64 elem_index = 0; elem_index < init.elems.len; elem_index += 1) {
            if(elem_index > 0) { io::outbuf_write(out, ", "); }
            print_const_init(m, &init.elems[elem_index], out);
        }
        io::outbuf_write(out, " }");
    }
    case sapir::ConstInitKind::Array: {
        io::outbuf_write(out, "[ ");
        for(u64 elem_index = 0; elem_index < init.elems.len; elem_index += 1) {
            if(elem_index > 0) { io::outbuf_write(out, ", "); }
            print_const_init(m, &init.elems[elem_index], out);
        }
        io::outbuf_write(out, " ]");
    }
    case sapir::ConstInitKind::Slice: {
        io::outbuf_write(out, "slice[ ");
        for(u64 elem_index = 0; elem_index < init.elems.len; elem_index += 1) {
            if(elem_index > 0) { io::outbuf_write(out, ", "); }
            print_const_init(m, &init.elems[elem_index], out);
        }
        io::outbuf_write(out, " ]");
    }
    case sapir::ConstInitKind::FnRef: {
        io::outbuf_write(out, "&");
        io::outbuf_write(out, m.decls[init.decl_index].link_name);
    }
    else { io::outbuf_write(out, "?"); }
    }
}

fn bool produces_value(sapir::Inst* inst) {
    if(sapir::is_terminator(inst.op)) { return false; }
    if(types::is_void(inst.ty)) { return false; }
    return true;
}

fn void write_operand(io::OutBuf* out, u32 value_id) {
    io::outbuf_write(out, " %");
    io::outbuf_write_u64(out, (u64)value_id);
}

fn void write_ty_suffix(types::Type* ty, io::OutBuf* out) {
    io::outbuf_write(out, ".");
    types_print::print(ty, out);
}

fn void write_sym(io::OutBuf* out, symbol::Symbol* s) {
    if(!s) { io::outbuf_write(out, "<null>"); return; }
    io::outbuf_write(out, interner::symbol_str(s));
}

fn u8[] opcode_name(sapir::Opcode op) {
    switch(op) {
    case sapir::Opcode::ConstInt:    { return "const"; }
    case sapir::Opcode::ConstFloat:  { return "const"; }
    case sapir::Opcode::ConstBool:   { return "const.bool"; }
    case sapir::Opcode::ConstNull:   { return "constnull"; }
    case sapir::Opcode::ConstStr:    { return "conststr"; }
    case sapir::Opcode::Undef:       { return "undef"; }
    case sapir::Opcode::Param:       { return "param"; }
    case sapir::Opcode::Alloca:      { return "alloca"; }
    case sapir::Opcode::Zero:        { return "zero"; }
    case sapir::Opcode::Load:        { return "load"; }
    case sapir::Opcode::Store:       { return "store"; }
    case sapir::Opcode::Memcpy:      { return "memcpy"; }
    case sapir::Opcode::FieldAddr:   { return "fieldaddr"; }
    case sapir::Opcode::IndexAddr:   { return "indexaddr"; }
    case sapir::Opcode::GlobalAddr:  { return "globaladdr"; }
    case sapir::Opcode::FnAddr:      { return "fnaddr"; }
    case sapir::Opcode::SliceMake:   { return "slicemake"; }
    case sapir::Opcode::SlicePtr:    { return "sliceptr"; }
    case sapir::Opcode::SliceLen:    { return "slicelen"; }
    case sapir::Opcode::Add:         { return "add"; }
    case sapir::Opcode::Sub:         { return "sub"; }
    case sapir::Opcode::Mul:         { return "mul"; }
    case sapir::Opcode::Div:         { return "div"; }
    case sapir::Opcode::Rem:         { return "rem"; }
    case sapir::Opcode::And:         { return "and"; }
    case sapir::Opcode::Or:          { return "or"; }
    case sapir::Opcode::Xor:         { return "xor"; }
    case sapir::Opcode::Shl:         { return "shl"; }
    case sapir::Opcode::Shr:         { return "shr"; }
    case sapir::Opcode::CmpEq:       { return "cmpeq"; }
    case sapir::Opcode::CmpNe:       { return "cmpne"; }
    case sapir::Opcode::CmpLt:       { return "cmplt"; }
    case sapir::Opcode::CmpLe:       { return "cmple"; }
    case sapir::Opcode::CmpGt:       { return "cmpgt"; }
    case sapir::Opcode::CmpGe:       { return "cmpge"; }
    case sapir::Opcode::Neg:         { return "neg"; }
    case sapir::Opcode::BitNot:      { return "bitnot"; }
    case sapir::Opcode::Not:         { return "not"; }
    case sapir::Opcode::Cast:        { return "cast"; }
    case sapir::Opcode::Call:        { return "call"; }
    case sapir::Opcode::Phi:         { return "phi"; }
    case sapir::Opcode::DbgValue:    { return "dbgvalue"; }
    case sapir::Opcode::Br:          { return "br"; }
    case sapir::Opcode::CondBr:      { return "condbr"; }
    case sapir::Opcode::SwitchBr:    { return "switchbr"; }
    case sapir::Opcode::Ret:         { return "ret"; }
    case sapir::Opcode::Unreachable: { return "unreachable"; }
    else { return "???"; }
    }
    return "???";
}
