import testing;
import sapir;
import types;
import ast;
import arena;
import sys;

fn i32 module_table(arena::Arena* a, u8[] msg) {
    sapir::SapirModule* m = sapir::new_module(a, null);
    if(!testing::expect_eq((void*)m.name, null, msg)) { return -1; }

    sapir::SapirDecl first;
    sys::memset(&first, 0, sizeof(sapir::SapirDecl));
    first.kind = sapir::SapirDeclKind::Fn;
    first.linkage = sapir::SapirLinkage::Export;
    first.link_name = "__math_add";
    u32 first_index = sapir::add_decl(a, m, first);
    if(!testing::expect_eq(first_index, (u32)0, msg)) { return -2; }

    sapir::SapirDecl second;
    sys::memset(&second, 0, sizeof(sapir::SapirDecl));
    second.kind = sapir::SapirDeclKind::Global;
    second.linkage = sapir::SapirLinkage::Internal;
    second.link_name = "__math_LIMIT";
    u32 second_index = sapir::add_decl(a, m, second);
    if(!testing::expect_eq(second_index, (u32)1, msg)) { return -3; }
    if(!testing::expect_eq(m.decls.len, (u64)2, msg)) { return -4; }
    if(!testing::expect_eq(m.decls[0].link_name, "__math_add", msg)) { return -5; }
    if(!testing::expect_eq((u16)m.decls[1].linkage, (u16)sapir::SapirLinkage::Internal, msg)) { return -6; }

    u32 fn_index = sapir::add_fn(a, m);
    if(!testing::expect_eq(fn_index, (u32)0, msg)) { return -7; }
    if(!testing::expect_eq(m.fns.len, (u64)1, msg)) { return -8; }

    sapir::SapirGlobal global;
    sys::memset(&global, 0, sizeof(sapir::SapirGlobal));
    global.decl_index = second_index;
    u32 global_index = sapir::add_global(a, m, global);
    if(!testing::expect_eq(global_index, (u32)0, msg)) { return -9; }
    return 0;
}

fn i32 inst_encoding(arena::Arena* a, u8[] msg) {
    sapir::SapirFn func;
    sys::memset(&func, 0, sizeof(sapir::SapirFn));

    sapir::Inst blank = sapir::new_inst((u16)sapir::Opcode::ConstInt, types::prim_i32(), 7);
    if(!testing::expect_eq(blank.a, sapir::INVALID_ID, msg)) { return -1; }
    if(!testing::expect_eq(blank.b, sapir::INVALID_ID, msg)) { return -2; }
    if(!testing::expect_eq(blank.op, (u16)sapir::Opcode::ConstInt, msg)) { return -3; }
    if(!testing::expect_eq((void*)blank.ty, (void*)types::prim_i32(), msg)) { return -4; }
    if(!testing::expect_eq(blank.src_pos, (u32)7, msg)) { return -5; }

    blank.imm = 42;
    u32 first_value = sapir::add_inst(a, &func, blank);
    sapir::Inst second = sapir::new_inst((u16)sapir::Opcode::ConstInt, types::prim_i32(), 8);
    u32 second_value = sapir::add_inst(a, &func, second);
    sapir::Inst add = sapir::new_inst((u16)sapir::Opcode::Add, types::prim_i32(), 9);
    add.a = first_value;
    add.b = second_value;
    u32 third_value = sapir::add_inst(a, &func, add);

    if(!testing::expect_eq(first_value, (u32)0, msg)) { return -6; }
    if(!testing::expect_eq(second_value, (u32)1, msg)) { return -7; }
    if(!testing::expect_eq(third_value, (u32)2, msg)) { return -8; }
    if(!testing::expect_eq(func.insts.len, (u64)3, msg)) { return -9; }
    if(!testing::expect_eq(func.insts[0].imm, (u64)42, msg)) { return -10; }
    if(!testing::expect_eq(func.insts[2].a, first_value, msg)) { return -11; }
    if(!testing::expect_eq(func.insts[2].b, second_value, msg)) { return -12; }
    return 0;
}

fn i32 block_and_extra(arena::Arena* a, u8[] msg) {
    sapir::SapirFn func;
    sys::memset(&func, 0, sizeof(sapir::SapirFn));

    u32 entry = sapir::new_block(a, &func);
    u32 exit = sapir::new_block(a, &func);
    if(!testing::expect_eq(entry, (u32)0, msg)) { return -1; }
    if(!testing::expect_eq(exit, (u32)1, msg)) { return -2; }
    if(!testing::expect_eq(func.blocks[0].body_start, sapir::INVALID_ID, msg)) { return -3; }
    if(!testing::expect_eq(func.blocks[0].body_end, sapir::INVALID_ID, msg)) { return -4; }

    u32 zero = sapir::add_extra(a, &func, 100);
    u32 one = sapir::add_extra(a, &func, 200);
    if(!testing::expect_eq(zero, (u32)0, msg)) { return -5; }
    if(!testing::expect_eq(one, (u32)1, msg)) { return -6; }
    if(!testing::expect_eq(func.extra[0], (u32)100, msg)) { return -7; }
    if(!testing::expect_eq(func.extra[1], (u32)200, msg)) { return -8; }

    sapir::add_pred(a, &func, exit, entry);
    if(!testing::expect_eq(func.blocks[1].preds.len, (u64)1, msg)) { return -9; }
    if(!testing::expect_eq(func.blocks[1].preds[0], entry, msg)) { return -10; }

    sapir::add_phi_to_block(a, &func, exit, 5);
    if(!testing::expect_eq(func.blocks[1].phis.len, (u64)1, msg)) { return -11; }
    if(!testing::expect_eq(func.blocks[1].phis[0], (u32)5, msg)) { return -12; }

    sapir::SapirVar var;
    sys::memset(&var, 0, sizeof(sapir::SapirVar));
    var.ty = types::prim_i32();
    var.alloca_id = sapir::INVALID_ID;
    u32 var_index = sapir::add_var(a, &func, var);
    if(!testing::expect_eq(var_index, (u32)0, msg)) { return -13; }
    if(!testing::expect_eq(func.vars.len, (u64)1, msg)) { return -14; }
    return 0;
}

fn i32 terminator_classification(arena::Arena* a, u8[] msg) {
    if(!testing::expect_eq(sapir::is_terminator((u16)sapir::Opcode::Br), true, msg)) { return -1; }
    if(!testing::expect_eq(sapir::is_terminator((u16)sapir::Opcode::CondBr), true, msg)) { return -2; }
    if(!testing::expect_eq(sapir::is_terminator((u16)sapir::Opcode::SwitchBr), true, msg)) { return -3; }
    if(!testing::expect_eq(sapir::is_terminator((u16)sapir::Opcode::Ret), true, msg)) { return -4; }
    if(!testing::expect_eq(sapir::is_terminator((u16)sapir::Opcode::Unreachable), true, msg)) { return -5; }
    if(!testing::expect_eq(sapir::is_terminator((u16)sapir::Opcode::Add), false, msg)) { return -6; }
    if(!testing::expect_eq(sapir::is_terminator((u16)sapir::Opcode::Call), false, msg)) { return -7; }
    if(!testing::expect_eq(sapir::is_terminator((u16)sapir::Opcode::Phi), false, msg)) { return -8; }
    return 0;
}

fn i32 cast_int_matrix(arena::Arena* a, u8[] msg) {
    if(!testing::expect_eq((u32)sapir::cast_op(types::prim_i32(), types::prim_i8()), (u32)sapir::CastOp::Trunc, msg)) { return -1; }
    if(!testing::expect_eq((u32)sapir::cast_op(types::prim_i8(), types::prim_i32()), (u32)sapir::CastOp::SExt, msg)) { return -2; }
    if(!testing::expect_eq((u32)sapir::cast_op(types::prim_u8(), types::prim_u32()), (u32)sapir::CastOp::ZExt, msg)) { return -3; }
    if(!testing::expect_eq((u32)sapir::cast_op(types::prim_i32(), types::prim_u32()), (u32)sapir::CastOp::Nop, msg)) { return -4; }
    if(!testing::expect_eq((u32)sapir::cast_op(types::prim_bool(), types::prim_i32()), (u32)sapir::CastOp::ZExt, msg)) { return -5; }
    if(!testing::expect_eq((u32)sapir::cast_op(types::prim_u64(), types::prim_i16()), (u32)sapir::CastOp::Trunc, msg)) { return -6; }
    return 0;
}

fn i32 decl_growth(arena::Arena* a, u8[] msg) {
    sapir::SapirModule* m = sapir::new_module(a, null);
    const u32 count = 40;
    for(u32 entry_index = 0; entry_index < count; entry_index += 1) {
        sapir::SapirDecl decl;
        sys::memset(&decl, 0, sizeof(sapir::SapirDecl));
        decl.fn_index = entry_index;
        u32 returned = sapir::add_decl(a, m, decl);
        if(!testing::expect_eq(returned, entry_index, msg)) { return -1; }
    }
    if(!testing::expect_eq(m.decls.len, (u64)count, msg)) { return -2; }
    if(!testing::expect_eq(m.decls[0].fn_index, (u32)0, msg)) { return -3; }
    if(!testing::expect_eq(m.decls[17].fn_index, (u32)17, msg)) { return -4; }
    if(!testing::expect_eq(m.decls[39].fn_index, (u32)39, msg)) { return -5; }
    return 0;
}

fn i32 inst_and_extra_growth(arena::Arena* a, u8[] msg) {
    sapir::SapirFn func;
    sys::memset(&func, 0, sizeof(sapir::SapirFn));
    const u32 count = 50;
    for(u32 step = 0; step < count; step += 1) {
        sapir::Inst inst = sapir::new_inst((u16)sapir::Opcode::ConstInt, types::prim_u64(), step);
        inst.imm = (u64)step;
        u32 value_id = sapir::add_inst(a, &func, inst);
        if(!testing::expect_eq(value_id, step, msg)) { return -1; }
        u32 extra_index = sapir::add_extra(a, &func, step * 10);
        if(!testing::expect_eq(extra_index, step, msg)) { return -2; }
    }
    if(!testing::expect_eq(func.insts.len, (u64)count, msg)) { return -3; }
    if(!testing::expect_eq(func.insts[0].imm, (u64)0, msg)) { return -4; }
    if(!testing::expect_eq(func.insts[49].imm, (u64)49, msg)) { return -5; }
    if(!testing::expect_eq(func.insts[49].src_pos, (u32)49, msg)) { return -6; }
    if(!testing::expect_eq(func.extra.len, (u64)count, msg)) { return -7; }
    if(!testing::expect_eq(func.extra[0], (u32)0, msg)) { return -8; }
    if(!testing::expect_eq(func.extra[49], (u32)490, msg)) { return -9; }
    return 0;
}

fn i32 cast_enum_reduce(arena::Arena* a, u8[] msg) {
    ast::AstNode base_node;
    sys::memset(&base_node, 0, sizeof(ast::AstNode));
    base_node.h.ty = (void*)types::prim_u8();
    ast::EnumDeclNode enum_decl;
    sys::memset(&enum_decl, 0, sizeof(ast::EnumDeclNode));
    enum_decl.base_type = &base_node;
    types::Type* enum_ty = types::intern_enum(&enum_decl);

    if(!testing::expect_eq((u32)sapir::cast_op(enum_ty, types::prim_i32()), (u32)sapir::CastOp::ZExt, msg)) { return -1; }
    if(!testing::expect_eq((u32)sapir::cast_op(types::prim_i32(), enum_ty), (u32)sapir::CastOp::Trunc, msg)) { return -2; }
    if(!testing::expect_eq((u32)sapir::cond_test(enum_ty), (u32)sapir::CondTest::IntNonZero, msg)) { return -3; }
    return 0;
}

fn i32 cast_structural(arena::Arena* a, u8[] msg) {
    types::Type* int_array = types::intern_array(types::prim_i32(), 4);
    types::Type* int_slice = types::intern_slice(types::prim_i32());
    types::Type* int_ptr = types::intern_pointer(types::prim_i32(), false);

    if(!testing::expect_eq((u32)sapir::cast_op(int_array, int_ptr), (u32)sapir::CastOp::ArrayToElemPtr, msg)) { return -1; }
    if(!testing::expect_eq((u32)sapir::cast_op(int_array, int_slice), (u32)sapir::CastOp::ArrayToSlice, msg)) { return -2; }
    if(!testing::expect_eq((u32)sapir::cast_op(types::prim_null_ptr(), int_slice), (u32)sapir::CastOp::NullToSlice, msg)) { return -3; }
    if(!testing::expect_eq((u32)sapir::cast_op(types::prim_null_ptr(), int_ptr), (u32)sapir::CastOp::Nop, msg)) { return -4; }
    return 0;
}

fn i32 cond_classification(arena::Arena* a, u8[] msg) {
    types::Type* int_ptr = types::intern_pointer(types::prim_i32(), false);
    types::Type* int_slice = types::intern_slice(types::prim_i32());
    types::Type*[] no_params = {null, 0};
    types::Type* fn_ptr = types::intern_fn_ptr(types::prim_void(), no_params, false);

    if(!testing::expect_eq((u32)sapir::cond_test(types::prim_bool()), (u32)sapir::CondTest::AsBool, msg)) { return -1; }
    if(!testing::expect_eq((u32)sapir::cond_test(types::prim_i32()), (u32)sapir::CondTest::IntNonZero, msg)) { return -2; }
    if(!testing::expect_eq((u32)sapir::cond_test(int_ptr), (u32)sapir::CondTest::PtrNonNull, msg)) { return -3; }
    if(!testing::expect_eq((u32)sapir::cond_test(fn_ptr), (u32)sapir::CondTest::PtrNonNull, msg)) { return -4; }
    if(!testing::expect_eq((u32)sapir::cond_test(int_slice), (u32)sapir::CondTest::SliceNonEmpty, msg)) { return -5; }
    return 0;
}

fn i32 cast_float_and_ptr(arena::Arena* a, u8[] msg) {
    if(!testing::expect_eq((u32)sapir::cast_op(types::prim_i32(), types::prim_f64()), (u32)sapir::CastOp::SIToFP, msg)) { return -1; }
    if(!testing::expect_eq((u32)sapir::cast_op(types::prim_u32(), types::prim_f32()), (u32)sapir::CastOp::UIToFP, msg)) { return -2; }
    if(!testing::expect_eq((u32)sapir::cast_op(types::prim_f64(), types::prim_i32()), (u32)sapir::CastOp::FPToSI, msg)) { return -3; }
    if(!testing::expect_eq((u32)sapir::cast_op(types::prim_f32(), types::prim_u32()), (u32)sapir::CastOp::FPToUI, msg)) { return -4; }
    if(!testing::expect_eq((u32)sapir::cast_op(types::prim_f32(), types::prim_f64()), (u32)sapir::CastOp::FPExt, msg)) { return -5; }
    if(!testing::expect_eq((u32)sapir::cast_op(types::prim_f64(), types::prim_f32()), (u32)sapir::CastOp::FPTrunc, msg)) { return -6; }

    types::Type* int_ptr = types::intern_pointer(types::prim_i32(), false);
    types::Type* byte_ptr = types::intern_pointer(types::prim_u8(), false);
    if(!testing::expect_eq((u32)sapir::cast_op(int_ptr, byte_ptr), (u32)sapir::CastOp::Nop, msg)) { return -7; }
    if(!testing::expect_eq((u32)sapir::cast_op(int_ptr, types::prim_u64()), (u32)sapir::CastOp::PtrToInt, msg)) { return -8; }
    if(!testing::expect_eq((u32)sapir::cast_op(types::prim_u64(), int_ptr), (u32)sapir::CastOp::IntToPtr, msg)) { return -9; }
    return 0;
}

fn i32 main() {
    testing::init();
    arena::Arena setup_arena;
    sys::memset(&setup_arena, 0, sizeof(arena::Arena));
    setup_arena.default_page_size = 65536;
    types::typer_init(&setup_arena, 64);

    u8[] suite = "Sapir Tests";
    testing::add(suite, "module_table",               &module_table);
    testing::add(suite, "inst_encoding",              &inst_encoding);
    testing::add(suite, "block_and_extra",            &block_and_extra);
    testing::add(suite, "terminator_classification",  &terminator_classification);
    testing::add(suite, "cast_int_matrix",            &cast_int_matrix);
    testing::add(suite, "cast_float_and_ptr",         &cast_float_and_ptr);
    testing::add(suite, "decl_growth",                &decl_growth);
    testing::add(suite, "inst_and_extra_growth",      &inst_and_extra_growth);
    testing::add(suite, "cast_enum_reduce",           &cast_enum_reduce);
    testing::add(suite, "cast_structural",            &cast_structural);
    testing::add(suite, "cond_classification",        &cond_classification);
    return testing::run();
}
