import testing;
import sapir;
import sapir_print;
import types;
import interner;
import io;
import arena;
import sys;

fn u32 emit(arena::Arena* a, sapir::SapirFn* func, u16 op, types::Type* ty, u32 operand_a, u32 operand_b) {
    sapir::Inst inst = sapir::new_inst(op, ty, 0);
    inst.a = operand_a;
    inst.b = operand_b;
    return sapir::add_inst(a, func, inst);
}

// Hand-assembles __demo_pick(bool, u64, u64) -> u64 with a diamond and a loop-free phi,
// then pins the rendered text so the printer's format is locked.
fn i32 golden_pick(arena::Arena* a, u8[] msg) {
    types::Type** param_mem = (types::Type**)arena::alloc(a, 3 * sizeof(types::Type*));
    param_mem[0] = types::prim_bool();
    param_mem[1] = types::prim_u64();
    param_mem[2] = types::prim_u64();
    types::Type*[] params = {param_mem, 3};
    types::Type* fn_ty = types::intern_fn_ptr(types::prim_u64(), params, false);

    sapir::SapirModule* m = sapir::new_module(a, interner::intern("demo"));

    sapir::SapirDecl fn_decl;
    sys::memset(&fn_decl, 0, sizeof(sapir::SapirDecl));
    fn_decl.kind = sapir::SapirDeclKind::Fn;
    fn_decl.linkage = sapir::SapirLinkage::Export;
    fn_decl.link_name = "__demo_pick";
    fn_decl.ty = fn_ty;
    fn_decl.fn_index = 0;
    fn_decl.global_index = sapir::INVALID_ID;
    u32 fn_decl_index = sapir::add_decl(a, m, fn_decl);

    sapir::SapirDecl global_decl;
    sys::memset(&global_decl, 0, sizeof(sapir::SapirDecl));
    global_decl.kind = sapir::SapirDeclKind::Global;
    global_decl.linkage = sapir::SapirLinkage::Internal;
    global_decl.link_name = "__demo_LIMIT";
    global_decl.ty = types::prim_u64();
    global_decl.fn_index = sapir::INVALID_ID;
    global_decl.global_index = 0;
    u32 global_decl_index = sapir::add_decl(a, m, global_decl);

    sapir::SapirGlobal global;
    sys::memset(&global, 0, sizeof(sapir::SapirGlobal));
    global.decl_index = global_decl_index;
    global.is_const = true;
    global.init.kind = sapir::ConstInitKind::Int;
    global.init.ty = types::prim_u64();
    global.init.i = 100;
    sapir::add_global(a, m, global);

    u32 fn_index = sapir::add_fn(a, m);
    sapir::SapirFn* func = &m.fns[fn_index];
    func.decl_index = fn_decl_index;
    func.name = interner::intern("pick");
    func.param_count = 3;
    func.entry = 0;

    u32 b0 = sapir::new_block(a, func);
    u32 b1 = sapir::new_block(a, func);
    u32 b2 = sapir::new_block(a, func);
    u32 b3 = sapir::new_block(a, func);

    emit(a, func, (u16)sapir::Opcode::Param, types::prim_bool(), 0, sapir::INVALID_ID);
    emit(a, func, (u16)sapir::Opcode::Param, types::prim_u64(), 1, sapir::INVALID_ID);
    emit(a, func, (u16)sapir::Opcode::Param, types::prim_u64(), 2, sapir::INVALID_ID);
    u32 cond_extra = sapir::add_extra(a, func, b1);
    sapir::add_extra(a, func, b2);
    emit(a, func, (u16)sapir::Opcode::CondBr, types::prim_void(), 0, cond_extra);
    func.blocks[b0].body_start = 0;
    func.blocks[b0].body_end = 4;

    emit(a, func, (u16)sapir::Opcode::Br, types::prim_void(), b3, sapir::INVALID_ID);
    func.blocks[b1].body_start = 4;
    func.blocks[b1].body_end = 5;
    sapir::add_pred(a, func, b1, b0);

    emit(a, func, (u16)sapir::Opcode::Br, types::prim_void(), b3, sapir::INVALID_ID);
    func.blocks[b2].body_start = 5;
    func.blocks[b2].body_end = 6;
    sapir::add_pred(a, func, b2, b0);

    u32 phi_extra = sapir::add_extra(a, func, 2);
    sapir::add_extra(a, func, b1);
    sapir::add_extra(a, func, 1);
    sapir::add_extra(a, func, b2);
    sapir::add_extra(a, func, 2);
    u32 phi_id = emit(a, func, (u16)sapir::Opcode::Phi, types::prim_u64(), sapir::INVALID_ID, phi_extra);
    sapir::add_phi_to_block(a, func, b3, phi_id);
    emit(a, func, (u16)sapir::Opcode::Ret, types::prim_void(), phi_id, sapir::INVALID_ID);
    func.blocks[b3].body_start = 6;
    func.blocks[b3].body_end = 8;
    sapir::add_pred(a, func, b3, b1);
    sapir::add_pred(a, func, b3, b2);

    u8[] got = sapir_print::print_module_to_arena(m, a);

    io::OutBuf want;
    io::outbuf_init(&want, a, 512);
    io::outbuf_write(&want, "module demo\n");
    io::outbuf_write(&want, "\n");
    io::outbuf_write(&want, "global __demo_LIMIT: u64 const = 100\n");
    io::outbuf_write(&want, "\n");
    io::outbuf_write(&want, "fn __demo_pick(bool, u64, u64) -> u64 {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = param.bool 0\n");
    io::outbuf_write(&want, "    %1 = param.u64 1\n");
    io::outbuf_write(&want, "    %2 = param.u64 2\n");
    io::outbuf_write(&want, "    condbr %0, b1, b2\n");
    io::outbuf_write(&want, "b1:  ; preds: b0\n");
    io::outbuf_write(&want, "    br b3\n");
    io::outbuf_write(&want, "b2:  ; preds: b0\n");
    io::outbuf_write(&want, "    br b3\n");
    io::outbuf_write(&want, "b3:  ; preds: b1, b2\n");
    io::outbuf_write(&want, "    %6 = phi.u64 [b1: %1, b2: %2]\n");
    io::outbuf_write(&want, "    ret %6\n");
    io::outbuf_write(&want, "}\n");

    if(!testing::expect_eq(got, io::outbuf_bytes(&want), msg)) { return -1; }
    return 0;
}

fn u32 fn_decl(arena::Arena* a, sapir::SapirModule* m, u8[] name, types::Type* ty, sapir::SapirLinkage linkage) {
    sapir::SapirDecl decl;
    sys::memset(&decl, 0, sizeof(sapir::SapirDecl));
    decl.kind = sapir::SapirDeclKind::Fn;
    decl.linkage = linkage;
    decl.link_name = name;
    decl.ty = ty;
    decl.fn_index = sapir::INVALID_ID;
    decl.global_index = sapir::INVALID_ID;
    return sapir::add_decl(a, m, decl);
}

fn u32 global_decl(arena::Arena* a, sapir::SapirModule* m, u8[] name, types::Type* ty) {
    sapir::SapirDecl decl;
    sys::memset(&decl, 0, sizeof(sapir::SapirDecl));
    decl.kind = sapir::SapirDeclKind::Global;
    decl.linkage = sapir::SapirLinkage::Internal;
    decl.link_name = name;
    decl.ty = ty;
    decl.fn_index = sapir::INVALID_ID;
    decl.global_index = sapir::INVALID_ID;
    return sapir::add_decl(a, m, decl);
}

// Straight-line body pinning the arithmetic / compare / call / cast / memory renderings.
fn i32 golden_ops(arena::Arena* a, u8[] msg) {
    types::Type** ops_params = (types::Type**)arena::alloc(a, 2 * sizeof(types::Type*));
    ops_params[0] = types::prim_i32();
    ops_params[1] = types::prim_i32();
    types::Type*[] ops_params_slice = {ops_params, 2};
    types::Type* ops_ty = types::intern_fn_ptr(types::prim_i64(), ops_params_slice, false);
    types::Type** helper_params = (types::Type**)arena::alloc(a, sizeof(types::Type*));
    helper_params[0] = types::prim_i32();
    types::Type*[] helper_params_slice = {helper_params, 1};
    types::Type* helper_ty = types::intern_fn_ptr(types::prim_i32(), helper_params_slice, false);
    types::Type* i64_ptr = types::intern_pointer(types::prim_i64(), false);

    sapir::SapirModule* m = sapir::new_module(a, interner::intern("ops"));
    u32 ops_index = fn_decl(a, m, "__ops_run", ops_ty, sapir::SapirLinkage::Export);
    u32 helper_index = fn_decl(a, m, "__ops_helper", helper_ty, sapir::SapirLinkage::Foreign);

    u32 fn_index = sapir::add_fn(a, m);
    sapir::SapirFn* func = &m.fns[fn_index];
    func.decl_index = ops_index;
    func.param_count = 2;
    u32 b0 = sapir::new_block(a, func);

    emit(a, func, (u16)sapir::Opcode::Param, types::prim_i32(), 0, sapir::INVALID_ID);
    emit(a, func, (u16)sapir::Opcode::Param, types::prim_i32(), 1, sapir::INVALID_ID);
    emit(a, func, (u16)sapir::Opcode::Add, types::prim_i32(), 0, 1);
    emit(a, func, (u16)sapir::Opcode::Sub, types::prim_i32(), 2, 1);
    emit(a, func, (u16)sapir::Opcode::Mul, types::prim_i32(), 3, 0);
    emit(a, func, (u16)sapir::Opcode::Div, types::prim_i32(), 4, 1);
    emit(a, func, (u16)sapir::Opcode::CmpLt, types::prim_bool(), 5, 0);
    u32 call_extra = sapir::add_extra(a, func, 1);
    sapir::add_extra(a, func, 0);
    emit(a, func, (u16)sapir::Opcode::Call, types::prim_i32(), helper_index, call_extra);
    emit(a, func, (u16)sapir::Opcode::Cast, types::prim_i64(), 5, sapir::INVALID_ID);
    emit(a, func, (u16)sapir::Opcode::Alloca, i64_ptr, sapir::INVALID_ID, sapir::INVALID_ID);
    emit(a, func, (u16)sapir::Opcode::Store, types::prim_void(), 9, 8);
    emit(a, func, (u16)sapir::Opcode::Load, types::prim_i64(), 9, sapir::INVALID_ID);
    emit(a, func, (u16)sapir::Opcode::Ret, types::prim_void(), 11, sapir::INVALID_ID);
    func.blocks[b0].body_start = 0;
    func.blocks[b0].body_end = 13;

    io::OutBuf want;
    io::outbuf_init(&want, a, 512);
    io::outbuf_write(&want, "module ops\n");
    io::outbuf_write(&want, "\n");
    io::outbuf_write(&want, "fn __ops_run(i32, i32) -> i64 {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = param.i32 0\n");
    io::outbuf_write(&want, "    %1 = param.i32 1\n");
    io::outbuf_write(&want, "    %2 = add.i32 %0, %1\n");
    io::outbuf_write(&want, "    %3 = sub.i32 %2, %1\n");
    io::outbuf_write(&want, "    %4 = mul.i32 %3, %0\n");
    io::outbuf_write(&want, "    %5 = div.i32 %4, %1\n");
    io::outbuf_write(&want, "    %6 = cmplt.i32 %5, %0\n");
    io::outbuf_write(&want, "    %7 = call.i32 __ops_helper(%0)\n");
    io::outbuf_write(&want, "    %8 = cast.i64 %5\n");
    io::outbuf_write(&want, "    %9 = alloca.i64*\n");
    io::outbuf_write(&want, "    store %9, %8\n");
    io::outbuf_write(&want, "    %11 = load.i64 %9\n");
    io::outbuf_write(&want, "    ret %11\n");
    io::outbuf_write(&want, "}\n");

    if(!testing::expect_eq(sapir_print::print_module_to_arena(m, a), io::outbuf_bytes(&want), msg)) { return -1; }
    return 0;
}

fn i32 golden_switch(arena::Arena* a, u8[] msg) {
    types::Type** sw_params = (types::Type**)arena::alloc(a, sizeof(types::Type*));
    sw_params[0] = types::prim_i32();
    types::Type*[] sw_params_slice = {sw_params, 1};
    types::Type* sw_ty = types::intern_fn_ptr(types::prim_void(), sw_params_slice, false);

    sapir::SapirModule* m = sapir::new_module(a, interner::intern("sw"));
    u32 sw_index = fn_decl(a, m, "__sw_pick", sw_ty, sapir::SapirLinkage::Export);
    u32 fn_index = sapir::add_fn(a, m);
    sapir::SapirFn* func = &m.fns[fn_index];
    func.decl_index = sw_index;
    func.param_count = 1;

    u32 b0 = sapir::new_block(a, func);
    u32 b1 = sapir::new_block(a, func);
    u32 b2 = sapir::new_block(a, func);

    emit(a, func, (u16)sapir::Opcode::Param, types::prim_i32(), 0, sapir::INVALID_ID);
    u32 sw_extra = sapir::add_extra(a, func, b2);
    sapir::add_extra(a, func, 2);
    sapir::add_extra(a, func, 10);
    sapir::add_extra(a, func, 0);
    sapir::add_extra(a, func, b1);
    sapir::add_extra(a, func, 20);
    sapir::add_extra(a, func, 0);
    sapir::add_extra(a, func, b1);
    emit(a, func, (u16)sapir::Opcode::SwitchBr, types::prim_void(), 0, sw_extra);
    func.blocks[b0].body_start = 0;
    func.blocks[b0].body_end = 2;

    emit(a, func, (u16)sapir::Opcode::Ret, types::prim_void(), sapir::INVALID_ID, sapir::INVALID_ID);
    func.blocks[b1].body_start = 2;
    func.blocks[b1].body_end = 3;
    sapir::add_pred(a, func, b1, b0);

    emit(a, func, (u16)sapir::Opcode::Ret, types::prim_void(), sapir::INVALID_ID, sapir::INVALID_ID);
    func.blocks[b2].body_start = 3;
    func.blocks[b2].body_end = 4;
    sapir::add_pred(a, func, b2, b0);

    io::OutBuf want;
    io::outbuf_init(&want, a, 512);
    io::outbuf_write(&want, "module sw\n");
    io::outbuf_write(&want, "\n");
    io::outbuf_write(&want, "fn __sw_pick(i32) -> void {\n");
    io::outbuf_write(&want, "b0:  ; preds:\n");
    io::outbuf_write(&want, "    %0 = param.i32 0\n");
    io::outbuf_write(&want, "    switchbr %0, default b2 [10: b1, 20: b1]\n");
    io::outbuf_write(&want, "b1:  ; preds: b0\n");
    io::outbuf_write(&want, "    ret\n");
    io::outbuf_write(&want, "b2:  ; preds: b0\n");
    io::outbuf_write(&want, "    ret\n");
    io::outbuf_write(&want, "}\n");

    if(!testing::expect_eq(sapir_print::print_module_to_arena(m, a), io::outbuf_bytes(&want), msg)) { return -1; }
    return 0;
}

fn i32 golden_const_inits(arena::Arena* a, u8[] msg) {
    types::Type* int_ptr = types::intern_pointer(types::prim_i32(), false);
    types::Type* int_array = types::intern_array(types::prim_i32(), 2);
    types::Type*[] no_params = {null, 0};
    types::Type* void_fn = types::intern_fn_ptr(types::prim_void(), no_params, false);

    sapir::SapirModule* m = sapir::new_module(a, interner::intern("c"));
    u32 fn_ref_index = fn_decl(a, m, "__c_fn", void_fn, sapir::SapirLinkage::Export);
    u32 zero_index = global_decl(a, m, "__c_zero", types::prim_u64());
    u32 bool_index = global_decl(a, m, "__c_flag", types::prim_bool());
    u32 null_index = global_decl(a, m, "__c_ptr", int_ptr);
    u32 array_index = global_decl(a, m, "__c_arr", int_array);
    u32 fnref_index = global_decl(a, m, "__c_cb", void_fn);

    sapir::SapirGlobal zero_global;
    sys::memset(&zero_global, 0, sizeof(sapir::SapirGlobal));
    zero_global.decl_index = zero_index;
    zero_global.init.kind = sapir::ConstInitKind::Zero;
    sapir::add_global(a, m, zero_global);

    sapir::SapirGlobal bool_global;
    sys::memset(&bool_global, 0, sizeof(sapir::SapirGlobal));
    bool_global.decl_index = bool_index;
    bool_global.init.kind = sapir::ConstInitKind::Bool;
    bool_global.init.i = 1;
    sapir::add_global(a, m, bool_global);

    sapir::SapirGlobal null_global;
    sys::memset(&null_global, 0, sizeof(sapir::SapirGlobal));
    null_global.decl_index = null_index;
    null_global.init.kind = sapir::ConstInitKind::Null;
    sapir::add_global(a, m, null_global);

    sapir::ConstInit* elems = (sapir::ConstInit*)arena::alloc(a, 2 * sizeof(sapir::ConstInit));
    sys::memset(elems, 0, 2 * sizeof(sapir::ConstInit));
    elems[0].kind = sapir::ConstInitKind::Int;
    elems[0].ty = types::prim_i32();
    elems[0].i = 1;
    elems[1].kind = sapir::ConstInitKind::Int;
    elems[1].ty = types::prim_i32();
    elems[1].i = 2;
    sapir::SapirGlobal array_global;
    sys::memset(&array_global, 0, sizeof(sapir::SapirGlobal));
    array_global.decl_index = array_index;
    array_global.init.kind = sapir::ConstInitKind::Array;
    array_global.init.ty = int_array;
    array_global.init.elems = {elems, 2};
    sapir::add_global(a, m, array_global);

    sapir::SapirGlobal fnref_global;
    sys::memset(&fnref_global, 0, sizeof(sapir::SapirGlobal));
    fnref_global.decl_index = fnref_index;
    fnref_global.init.kind = sapir::ConstInitKind::FnRef;
    fnref_global.init.decl_index = fn_ref_index;
    sapir::add_global(a, m, fnref_global);

    io::OutBuf want;
    io::outbuf_init(&want, a, 512);
    io::outbuf_write(&want, "module c\n");
    io::outbuf_write(&want, "\n");
    io::outbuf_write(&want, "global __c_zero: u64 = zero\n");
    io::outbuf_write(&want, "\n");
    io::outbuf_write(&want, "global __c_flag: bool = 1\n");
    io::outbuf_write(&want, "\n");
    io::outbuf_write(&want, "global __c_ptr: i32* = null\n");
    io::outbuf_write(&want, "\n");
    io::outbuf_write(&want, "global __c_arr: i32[2] = [ 1, 2 ]\n");
    io::outbuf_write(&want, "\n");
    io::outbuf_write(&want, "global __c_cb: fn* void() = &__c_fn\n");

    if(!testing::expect_eq(sapir_print::print_module_to_arena(m, a), io::outbuf_bytes(&want), msg)) { return -1; }
    return 0;
}

fn i32 main() {
    testing::init();
    arena::Arena setup_arena;
    sys::memset(&setup_arena, 0, sizeof(arena::Arena));
    setup_arena.default_page_size = 65536;
    interner::init(&setup_arena, 64);
    types::typer_init(&setup_arena, 64);

    u8[] suite = "Sapir Print Tests";
    testing::add(suite, "golden_pick",        &golden_pick);
    testing::add(suite, "golden_ops",         &golden_ops);
    testing::add(suite, "golden_switch",      &golden_switch);
    testing::add(suite, "golden_const_inits", &golden_const_inits);
    return testing::run();
}
