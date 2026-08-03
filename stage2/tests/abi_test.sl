import testing;
import test_util;
import abi;
import types;
import ast;
import lower;
import codegen;
import sapir;
import module;
import arena;
import sys;

// Every classification below is pinned to what clang emits for the same C shape, since matching
// clang is the whole point: a divergence here is an ABI break against every C library we link.

fn ast::StructDeclNode* struct_decl(arena::Arena* a, types::Ty*[] field_types) {
    ast::StructDeclNode* d = (ast::StructDeclNode*)arena::alloc(a, sizeof(ast::StructDeclNode));
    sys::memset(d, 0, sizeof(ast::StructDeclNode));
    if(field_types.len == 0) {
        d.fields = {null, 0};
        return d;
    }
    ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, field_types.len * sizeof(ast::FieldDecl));
    sys::memset(fields, 0, field_types.len * sizeof(ast::FieldDecl));
    for(u64 i = 0; i < field_types.len; i += 1) { fields[i].resolved_type = (void*)field_types[i]; }
    d.fields = {fields, field_types.len};
    return d;
}

fn ast::UnionDeclNode* union_decl(arena::Arena* a, types::Ty*[] field_types) {
    ast::UnionDeclNode* d = (ast::UnionDeclNode*)arena::alloc(a, sizeof(ast::UnionDeclNode));
    sys::memset(d, 0, sizeof(ast::UnionDeclNode));
    ast::FieldDecl* fields = (ast::FieldDecl*)arena::alloc(a, field_types.len * sizeof(ast::FieldDecl));
    sys::memset(fields, 0, field_types.len * sizeof(ast::FieldDecl));
    for(u64 i = 0; i < field_types.len; i += 1) { fields[i].resolved_type = (void*)field_types[i]; }
    d.fields = {fields, field_types.len};
    return d;
}

fn ast::EnumDeclNode* enum_decl(arena::Arena* a, types::Ty* base) {
    ast::AstNode* base_node = (ast::AstNode*)arena::alloc(a, sizeof(ast::AstNode));
    sys::memset(base_node, 0, sizeof(ast::AstNode));
    base_node.h.ty = (void*)base;
    ast::EnumDeclNode* d = (ast::EnumDeclNode*)arena::alloc(a, sizeof(ast::EnumDeclNode));
    sys::memset(d, 0, sizeof(ast::EnumDeclNode));
    d.base_type = base_node;
    return d;
}

fn types::Ty*[] tys(arena::Arena* a, types::Ty* t0) {
    types::Ty** m = (types::Ty**)arena::alloc(a, sizeof(types::Ty*));
    m[0] = t0;
    types::Ty*[] out = {m, 1};
    return out;
}

fn types::Ty*[] tys(arena::Arena* a, types::Ty* t0, types::Ty* t1) {
    types::Ty** m = (types::Ty**)arena::alloc(a, 2 * sizeof(types::Ty*));
    m[0] = t0; m[1] = t1;
    types::Ty*[] out = {m, 2};
    return out;
}

fn types::Ty*[] tys(arena::Arena* a, types::Ty* t0, types::Ty* t1, types::Ty* t2) {
    types::Ty** m = (types::Ty**)arena::alloc(a, 3 * sizeof(types::Ty*));
    m[0] = t0; m[1] = t1; m[2] = t2;
    types::Ty*[] out = {m, 3};
    return out;
}

fn types::Ty*[] tys(arena::Arena* a, types::Ty* t0, types::Ty* t1, types::Ty* t2, types::Ty* t3) {
    types::Ty** m = (types::Ty**)arena::alloc(a, 4 * sizeof(types::Ty*));
    m[0] = t0; m[1] = t1; m[2] = t2; m[3] = t3;
    types::Ty*[] out = {m, 4};
    return out;
}

fn types::Ty*[] repeat(arena::Arena* a, types::Ty* t, u64 count) {
    types::Ty** m = (types::Ty**)arena::alloc(a, (count + 1) * sizeof(types::Ty*));
    for(u64 i = 0; i < count; i += 1) { m[i] = t; }
    types::Ty*[] out = {m, count};
    return out;
}

fn types::Ty* rec(arena::Arena* a, types::Ty*[] field_types) { return types::intern_struct((void*)struct_decl(a, field_types)); }
fn types::Ty* uni(arena::Arena* a, types::Ty*[] field_types) { return types::intern_union((void*)union_decl(a, field_types)); }

fn bool expect_coerce1(abi::ArgInfo* info, abi::EightbyteKind kind, u32 width, const u8[] m) {
    if(!testing::expect_eq((i32)info.kind, (i32)abi::ArgKind::Coerce, m)) { return false; }
    if(!testing::expect_eq((u32)info.count, 1, m)) { return false; }
    if(!testing::expect_eq((i32)info.eightbytes[0], (i32)kind, m)) { return false; }
    return testing::expect_eq((u32)info.widths[0], width, m);
}

fn bool expect_coerce2(abi::ArgInfo* info, abi::EightbyteKind kind0, u32 width0, abi::EightbyteKind kind1, u32 width1, const u8[] m) {
    if(!testing::expect_eq((i32)info.kind, (i32)abi::ArgKind::Coerce, m)) { return false; }
    if(!testing::expect_eq((u32)info.count, 2, m)) { return false; }
    if(!testing::expect_eq((i32)info.eightbytes[0], (i32)kind0, m)) { return false; }
    if(!testing::expect_eq((u32)info.widths[0], width0, m)) { return false; }
    if(!testing::expect_eq((i32)info.eightbytes[1], (i32)kind1, m)) { return false; }
    return testing::expect_eq((u32)info.widths[1], width1, m);
}

fn bool expect_kind(abi::ArgInfo* info, abi::ArgKind kind, const u8[] m) {
    return testing::expect_eq((i32)info.kind, (i32)kind, m);
}

// ===== classify: scalars pass through untouched =====

fn i32 scalars_are_direct(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    abi::ArgInfo i32_info = abi::classify(types::prim_i32());
    abi::ArgInfo f64_info = abi::classify(types::prim_f64());
    abi::ArgInfo bool_info = abi::classify(types::prim_bool());
    abi::ArgInfo ptr_info = abi::classify(types::intern_pointer(types::prim_i32(), false));
    abi::ArgInfo fnptr_info = abi::classify(types::intern_fn_ptr(types::prim_void(), repeat(a, types::prim_i32(), 0), false));
    abi::ArgInfo enum_info = abi::classify(types::intern_enum((void*)enum_decl(a, types::prim_u8())));
    if(!expect_kind(&i32_info, abi::ArgKind::Direct, m)) { return 1; }
    if(!expect_kind(&f64_info, abi::ArgKind::Direct, m)) { return 1; }
    if(!expect_kind(&bool_info, abi::ArgKind::Direct, m)) { return 1; }
    if(!expect_kind(&ptr_info, abi::ArgKind::Direct, m)) { return 1; }
    if(!expect_kind(&fnptr_info, abi::ArgKind::Direct, m)) { return 1; }
    if(!expect_kind(&enum_info, abi::ArgKind::Direct, m)) { return 1; }
    return 0;
}

fn i32 void_and_null_are_ignored(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    abi::ArgInfo void_info = abi::classify(types::prim_void());
    abi::ArgInfo null_info = abi::classify(null);
    if(!expect_kind(&void_info, abi::ArgKind::Ignore, m)) { return 1; }
    if(!expect_kind(&null_info, abi::ArgKind::Ignore, m)) { return 1; }
    return 0;
}

// A zero-sized aggregate places no bytes, but sapir still passes it around as a value.
fn i32 an_empty_aggregate_stays_a_direct_value(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    types::Ty* empty = rec(a, repeat(a, types::prim_i32(), 0));
    abi::ArgInfo info = abi::classify(empty);
    if(!expect_kind(&info, abi::ArgKind::Direct, m)) { return 1; }

    types::Ty* pair = rec(a, tys(a, types::prim_i32(), types::prim_i32()));
    types::Ty*[] params = repeat(a, empty, 7);
    params[6] = pair;
    abi::FnAbi* fn_abi = abi::classify_fn(types::intern_fn_ptr(types::prim_void(), params, false), arena::allocator(a));
    if(!testing::expect_eq(fn_abi.first_llvm_param[6], 6, m)) { return 1; }
    if(!expect_kind(&fn_abi.params[6], abi::ArgKind::Coerce, m)) { return 1; }   // empty params burn no registers
    return 0;
}

// ===== classify: SSE eightbytes =====

fn i32 two_floats_share_one_sse_eightbyte(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    abi::ArgInfo info = abi::classify(rec(a, tys(a, types::prim_f32(), types::prim_f32())));
    if(!expect_coerce1(&info, abi::EightbyteKind::Float2, 8, m)) { return 1; }
    return 0;
}

fn i32 three_floats_split_two_then_one(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    abi::ArgInfo info = abi::classify(rec(a, tys(a, types::prim_f32(), types::prim_f32(), types::prim_f32())));
    if(!expect_coerce2(&info, abi::EightbyteKind::Float2, 8, abi::EightbyteKind::Float, 4, m)) { return 1; }
    return 0;
}

fn i32 four_floats_fill_two_sse_eightbytes(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    abi::ArgInfo info = abi::classify(rec(a, tys(a, types::prim_f32(), types::prim_f32(), types::prim_f32(), types::prim_f32())));
    if(!expect_coerce2(&info, abi::EightbyteKind::Float2, 8, abi::EightbyteKind::Float2, 8, m)) { return 1; }
    return 0;
}

fn i32 single_double_is_one_sse_eightbyte(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    abi::ArgInfo one = abi::classify(rec(a, tys(a, types::prim_f64())));
    abi::ArgInfo two = abi::classify(rec(a, tys(a, types::prim_f64(), types::prim_f64())));
    if(!expect_coerce1(&one, abi::EightbyteKind::Double, 8, m)) { return 1; }
    if(!expect_coerce2(&two, abi::EightbyteKind::Double, 8, abi::EightbyteKind::Double, 8, m)) { return 1; }
    return 0;
}

fn i32 float_then_double_keeps_both_sse(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    abi::ArgInfo fd = abi::classify(rec(a, tys(a, types::prim_f32(), types::prim_f64())));
    abi::ArgInfo df = abi::classify(rec(a, tys(a, types::prim_f64(), types::prim_f32())));
    if(!expect_coerce2(&fd, abi::EightbyteKind::Float, 4, abi::EightbyteKind::Double, 8, m)) { return 1; }
    if(!expect_coerce2(&df, abi::EightbyteKind::Double, 8, abi::EightbyteKind::Float, 4, m)) { return 1; }
    return 0;
}

fn i32 float_array_packs_like_float_fields(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    abi::ArgInfo info = abi::classify(rec(a, tys(a, types::intern_array(types::prim_f32(), 3))));
    if(!expect_coerce2(&info, abi::EightbyteKind::Float2, 8, abi::EightbyteKind::Float, 4, m)) { return 1; }
    return 0;
}

fn i32 nested_float_structs_flatten(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    types::Ty* pair = rec(a, tys(a, types::prim_f32(), types::prim_f32()));
    abi::ArgInfo nested = abi::classify(rec(a, tys(a, pair, types::prim_f32())));
    types::Ty* single = rec(a, tys(a, types::prim_f32()));
    abi::ArgInfo two_singles = abi::classify(rec(a, tys(a, single, single)));
    if(!expect_coerce2(&nested, abi::EightbyteKind::Float2, 8, abi::EightbyteKind::Float, 4, m)) { return 1; }
    if(!expect_coerce1(&two_singles, abi::EightbyteKind::Float2, 8, m)) { return 1; }
    return 0;
}

// ===== classify: INTEGER eightbytes =====

fn i32 two_ints_share_one_integer_eightbyte(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    abi::ArgInfo two = abi::classify(rec(a, tys(a, types::prim_i32(), types::prim_i32())));
    abi::ArgInfo one = abi::classify(rec(a, tys(a, types::prim_i32())));
    if(!expect_coerce1(&two, abi::EightbyteKind::Integer, 8, m)) { return 1; }
    if(!expect_coerce1(&one, abi::EightbyteKind::Integer, 4, m)) { return 1; }
    return 0;
}

fn i32 integer_wins_the_merge_over_sse(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    abi::ArgInfo int_float = abi::classify(rec(a, tys(a, types::prim_i32(), types::prim_f32())));
    abi::ArgInfo shorts_float = abi::classify(rec(a, tys(a, types::prim_i16(), types::prim_i16(), types::prim_f32())));
    if(!expect_coerce1(&int_float, abi::EightbyteKind::Integer, 8, m)) { return 1; }
    if(!expect_coerce1(&shorts_float, abi::EightbyteKind::Integer, 8, m)) { return 1; }
    return 0;
}

fn i32 narrow_integer_eightbytes_keep_their_width(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    abi::ArgInfo one_byte = abi::classify(rec(a, tys(a, types::prim_u8())));
    abi::ArgInfo three_bytes = abi::classify(rec(a, tys(a, types::intern_array(types::prim_u8(), 3))));
    abi::ArgInfo nine_bytes = abi::classify(rec(a, tys(a, types::intern_array(types::prim_u8(), 9))));
    abi::ArgInfo two_bools = abi::classify(rec(a, tys(a, types::prim_bool(), types::prim_bool())));
    if(!expect_coerce1(&one_byte, abi::EightbyteKind::Integer, 1, m)) { return 1; }
    if(!expect_coerce1(&three_bytes, abi::EightbyteKind::Integer, 3, m)) { return 1; }
    if(!expect_coerce2(&nine_bytes, abi::EightbyteKind::Integer, 8, abi::EightbyteKind::Integer, 1, m)) { return 1; }
    if(!expect_coerce1(&two_bools, abi::EightbyteKind::Integer, 2, m)) { return 1; }
    return 0;
}

fn i32 a_lone_pointer_eightbyte_stays_a_pointer(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    types::Ty* ptr = types::intern_pointer(types::prim_i32(), false);
    types::Ty* fnptr = types::intern_fn_ptr(types::prim_void(), repeat(a, types::prim_i32(), 0), false);
    abi::ArgInfo ptr_int = abi::classify(rec(a, tys(a, ptr, types::prim_i32())));
    abi::ArgInfo fnptr_int = abi::classify(rec(a, tys(a, fnptr, types::prim_i32())));
    abi::ArgInfo slice = abi::classify(types::intern_slice(types::prim_i32()));
    if(!expect_coerce2(&ptr_int, abi::EightbyteKind::Pointer, 8, abi::EightbyteKind::Integer, 4, m)) { return 1; }
    if(!expect_coerce2(&fnptr_int, abi::EightbyteKind::Pointer, 8, abi::EightbyteKind::Integer, 4, m)) { return 1; }
    if(!expect_coerce2(&slice, abi::EightbyteKind::Pointer, 8, abi::EightbyteKind::Integer, 8, m)) { return 1; }
    return 0;
}

fn i32 a_shared_eightbyte_is_not_a_lone_pointer(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    abi::ArgInfo long_float = abi::classify(rec(a, tys(a, types::prim_i64(), types::prim_f32())));
    abi::ArgInfo float_long = abi::classify(rec(a, tys(a, types::prim_f32(), types::prim_i64())));
    abi::ArgInfo byte_double = abi::classify(rec(a, tys(a, types::prim_u8(), types::prim_f64())));
    if(!expect_coerce2(&long_float, abi::EightbyteKind::Integer, 8, abi::EightbyteKind::Float, 4, m)) { return 1; }
    if(!expect_coerce2(&float_long, abi::EightbyteKind::Float, 4, abi::EightbyteKind::Integer, 8, m)) { return 1; }
    if(!expect_coerce2(&byte_double, abi::EightbyteKind::Integer, 1, abi::EightbyteKind::Double, 8, m)) { return 1; }
    return 0;
}

fn i32 enum_fields_classify_through_their_base(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    types::Ty* byte_enum = types::intern_enum((void*)enum_decl(a, types::prim_u8()));
    abi::ArgInfo info = abi::classify(rec(a, tys(a, byte_enum, types::prim_u8())));
    if(!expect_coerce1(&info, abi::EightbyteKind::Integer, 2, m)) { return 1; }
    return 0;
}

fn i32 unions_merge_every_member_at_offset_zero(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    abi::ArgInfo float_int = abi::classify(uni(a, tys(a, types::prim_f32(), types::prim_i32())));
    abi::ArgInfo double_long = abi::classify(uni(a, tys(a, types::prim_f64(), types::prim_i64())));
    abi::ArgInfo all_float = abi::classify(uni(a, tys(a, types::prim_f32(), types::prim_f32())));
    if(!expect_coerce1(&float_int, abi::EightbyteKind::Integer, 4, m)) { return 1; }
    if(!expect_coerce1(&double_long, abi::EightbyteKind::Integer, 8, m)) { return 1; }
    if(!expect_coerce1(&all_float, abi::EightbyteKind::Float, 4, m)) { return 1; }
    return 0;
}

// ===== classify: memory =====

fn i32 aggregates_over_sixteen_bytes_go_to_memory(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    abi::ArgInfo three_doubles = abi::classify(rec(a, tys(a, types::prim_f64(), types::prim_f64(), types::prim_f64())));
    abi::ArgInfo five_ints = abi::classify(rec(a, tys(a, types::intern_array(types::prim_i32(), 5))));
    abi::ArgInfo big_union = abi::classify(uni(a, tys(a, types::prim_i32(), types::intern_array(types::prim_u8(), 20))));
    abi::ArgInfo big_slice_pair = abi::classify(rec(a, tys(a, types::intern_slice(types::prim_i32()), types::prim_i32())));
    if(!expect_kind(&three_doubles, abi::ArgKind::Memory, m)) { return 1; }
    if(!expect_kind(&five_ints, abi::ArgKind::Memory, m)) { return 1; }
    if(!expect_kind(&big_union, abi::ArgKind::Memory, m)) { return 1; }
    if(!expect_kind(&big_slice_pair, abi::ArgKind::Memory, m)) { return 1; }
    return 0;
}

// ===== classify_fn =====

fn i32 plain_signature_spends_one_slot_per_param(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    types::Ty* fnty = types::intern_fn_ptr(types::prim_i32(), tys(a, types::prim_i32(), types::prim_f64()), false);
    abi::FnAbi* fn_abi = abi::classify_fn(fnty, arena::allocator(a));
    if(!testing::expect_false(fn_abi.sret, m)) { return 1; }
    if(!testing::expect_eq(fn_abi.llvm_param_count, 2, m)) { return 1; }
    if(!testing::expect_eq(fn_abi.first_llvm_param[0], 0, m)) { return 1; }
    if(!testing::expect_eq(fn_abi.first_llvm_param[1], 1, m)) { return 1; }
    return 0;
}

fn i32 a_coerced_param_spends_one_slot_per_eightbyte(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    types::Ty* pair = rec(a, tys(a, types::prim_f32(), types::prim_f32()));
    types::Ty* quad = rec(a, tys(a, types::prim_f32(), types::prim_f32(), types::prim_f32(), types::prim_f32()));
    types::Ty* fnty = types::intern_fn_ptr(types::prim_void(), tys(a, pair, quad, types::prim_i32()), false);
    abi::FnAbi* fn_abi = abi::classify_fn(fnty, arena::allocator(a));
    if(!testing::expect_eq(fn_abi.first_llvm_param[0], 0, m)) { return 1; }
    if(!testing::expect_eq(fn_abi.first_llvm_param[1], 1, m)) { return 1; }
    if(!testing::expect_eq(fn_abi.first_llvm_param[2], 3, m)) { return 1; }
    if(!testing::expect_eq(fn_abi.llvm_param_count, 4, m)) { return 1; }
    return 0;
}

fn i32 an_sret_return_shifts_every_param_slot(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    types::Ty* big = rec(a, tys(a, types::prim_f64(), types::prim_f64(), types::prim_f64()));
    types::Ty* fnty = types::intern_fn_ptr(big, tys(a, types::prim_i32(), types::prim_i32()), false);
    abi::FnAbi* fn_abi = abi::classify_fn(fnty, arena::allocator(a));
    if(!testing::expect_true(fn_abi.sret, m)) { return 1; }
    if(!testing::expect_eq(fn_abi.first_llvm_param[0], 1, m)) { return 1; }
    if(!testing::expect_eq(fn_abi.first_llvm_param[1], 2, m)) { return 1; }
    if(!testing::expect_eq(fn_abi.llvm_param_count, 3, m)) { return 1; }
    return 0;
}

// SysV never splits an aggregate between a register and the stack: short of registers, all of it spills.
fn i32 an_aggregate_short_of_integer_registers_spills(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    types::Ty* pair = rec(a, tys(a, types::prim_i32(), types::prim_i32()));
    types::Ty* wide = rec(a, tys(a, types::prim_i64(), types::prim_i64()));

    types::Ty*[] five = repeat(a, types::prim_i64(), 6);
    five[5] = pair;
    abi::FnAbi* fits = abi::classify_fn(types::intern_fn_ptr(types::prim_void(), five, false), arena::allocator(a));
    if(!expect_kind(&fits.params[5], abi::ArgKind::Coerce, m)) { return 1; }

    types::Ty*[] six = repeat(a, types::prim_i64(), 7);
    six[6] = pair;
    abi::FnAbi* spills = abi::classify_fn(types::intern_fn_ptr(types::prim_void(), six, false), arena::allocator(a));
    if(!expect_kind(&spills.params[6], abi::ArgKind::Memory, m)) { return 1; }

    types::Ty*[] partial = repeat(a, types::prim_i64(), 6);
    partial[5] = wide;
    abi::FnAbi* halved = abi::classify_fn(types::intern_fn_ptr(types::prim_void(), partial, false), arena::allocator(a));
    if(!expect_kind(&halved.params[5], abi::ArgKind::Memory, m)) { return 1; }
    return 0;
}

fn i32 an_sret_pointer_consumes_an_integer_register(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    types::Ty* pair = rec(a, tys(a, types::prim_i32(), types::prim_i32()));
    types::Ty* big = rec(a, tys(a, types::prim_f64(), types::prim_f64(), types::prim_f64()));
    types::Ty*[] params = repeat(a, types::prim_i64(), 6);
    params[5] = pair;
    abi::FnAbi* direct = abi::classify_fn(types::intern_fn_ptr(types::prim_i32(), params, false), arena::allocator(a));
    abi::FnAbi* via_sret = abi::classify_fn(types::intern_fn_ptr(big, params, false), arena::allocator(a));
    if(!expect_kind(&direct.params[5], abi::ArgKind::Coerce, m)) { return 1; }
    if(!expect_kind(&via_sret.params[5], abi::ArgKind::Memory, m)) { return 1; }
    return 0;
}

fn i32 sse_and_integer_registers_run_out_separately(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    types::Ty* float_pair = rec(a, tys(a, types::prim_f32(), types::prim_f32()));

    types::Ty*[] integers_gone = repeat(a, types::prim_i64(), 7);
    integers_gone[6] = float_pair;
    abi::FnAbi* sse_free = abi::classify_fn(types::intern_fn_ptr(types::prim_void(), integers_gone, false), arena::allocator(a));
    if(!expect_kind(&sse_free.params[6], abi::ArgKind::Coerce, m)) { return 1; }

    types::Ty*[] sse_gone = repeat(a, types::prim_f64(), 9);
    sse_gone[8] = float_pair;
    abi::FnAbi* sse_spent = abi::classify_fn(types::intern_fn_ptr(types::prim_void(), sse_gone, false), arena::allocator(a));
    if(!expect_kind(&sse_spent.params[8], abi::ArgKind::Memory, m)) { return 1; }
    return 0;
}

fn i32 a_spilled_aggregate_leaves_registers_for_later_params(arena::Arena* a, const u8[] m) {
    test_util::boot(a);
    types::Ty* big = rec(a, tys(a, types::prim_f64(), types::prim_f64(), types::prim_f64()));
    types::Ty* pair = rec(a, tys(a, types::prim_i32(), types::prim_i32()));
    abi::FnAbi* fn_abi = abi::classify_fn(types::intern_fn_ptr(types::prim_void(), tys(a, big, pair), false), arena::allocator(a));
    if(!expect_kind(&fn_abi.params[0], abi::ArgKind::Memory, m)) { return 1; }
    if(!expect_kind(&fn_abi.params[1], abi::ArgKind::Coerce, m)) { return 1; }
    return 0;
}

// ===== emitted signatures =====
// Pinned to the declarations clang emits for the same C shapes. A round trip between two Saplang
// functions cannot catch an ABI break — both ends move the same wrong way — so the contract with a
// foreign caller is pinned here and, where libc offers a matching callee, exercised for real below.

const u8[] SHAPES = "struct V2 { f32 x; f32 y; } struct V3 { f32 x; f32 y; f32 z; } struct P { i32 a; i32 b; } struct DF { f64 a; f32 b; } struct Big { f64 a; f64 b; f64 c; } struct H { void* p; i32 n; } extern { fn void take_v2(V2 v); fn void take_p(P v); fn void take_df(DF v); fn void take_big(Big v); fn void take_h(H v); fn V2 make_v2(); fn V3 make_v3(); fn Big make_big(); } fn void main() { V2 v = {1.0, 2.0}; P p = {1, 2}; DF d = {1.0, 2.0}; Big b = {1.0, 2.0, 3.0}; H h = {null, 1}; take_v2(v); take_p(p); take_df(d); take_big(b); take_h(h); make_v2(); make_v3(); make_big(); }";

fn const u8[] shapes_ir(arena::Arena* host) {
    arena::Arena* a = test_util::sub_arena(host);
    a.default_page_size = 1048576;
    module::Module* m = test_util::frontend(a, SHAPES);
    sapir::SapirModule* sm = lower::lower_module(m);
    return codegen::codegen_ir_string(sm, arena::allocator(a), codegen::BuildConfig::Debug);
}

fn i32 float_pairs_are_declared_as_a_float_vector(arena::Arena* a, const u8[] m) {
    const u8[] ir = shapes_ir(a);
    if(!testing::expect_substr(ir, "declare void @take_v2(<2 x float>)", m)) { return 1; }
    if(!testing::expect_substr(ir, "declare <2 x float> @make_v2()", m)) { return 1; }
    if(!testing::expect_substr(ir, "declare { <2 x float>, float } @make_v3()", m)) { return 1; }
    return 0;
}

fn i32 packed_integers_are_declared_as_one_word(arena::Arena* a, const u8[] m) {
    const u8[] ir = shapes_ir(a);
    if(!testing::expect_substr(ir, "declare void @take_p(i64)", m)) { return 1; }
    if(!testing::expect_substr(ir, "declare void @take_h(ptr, i32)", m)) { return 1; }
    if(!testing::expect_substr(ir, "declare void @take_df(double, float)", m)) { return 1; }
    return 0;
}

fn i32 oversized_aggregates_are_declared_byval_and_sret(arena::Arena* a, const u8[] m) {
    const u8[] ir = shapes_ir(a);
    if(!testing::expect_substr(ir, "declare void @take_big(ptr byval(", m)) { return 1; }
    if(!testing::expect_substr(ir, "declare void @make_big(ptr sret(", m)) { return 1; }
    return 0;
}

// ===== real C callees: the only checks here that a C implementation has to agree with =====

struct DivResult { i32 quot; i32 rem; }
struct LDivResult { i64 quot; i64 rem; }
struct Complex32 { f32 re; f32 im; }

extern {
    fn DivResult div(i32 numer, i32 denom);
    fn LDivResult ldiv(i64 numer, i64 denom);
    fn f32 cabsf(Complex32 z);
}

fn i32 libc_div_returns_a_packed_integer_eightbyte(arena::Arena* a, const u8[] m) {
    DivResult positive = div(17, 5);
    DivResult negative = div(-17, 5);
    if(!testing::expect_eq(positive.quot, 3, m)) { return 1; }
    if(!testing::expect_eq(positive.rem, 2, m)) { return 1; }
    if(!testing::expect_eq(negative.quot, -3, m)) { return 1; }
    if(!testing::expect_eq(negative.rem, -2, m)) { return 1; }
    return 0;
}

fn i32 libc_ldiv_returns_two_integer_eightbytes(arena::Arena* a, const u8[] m) {
    LDivResult r = ldiv(-17, 5);
    if(!testing::expect_eq(r.quot, (i64)-3, m)) { return 1; }
    if(!testing::expect_eq(r.rem, (i64)-2, m)) { return 1; }
    return 0;
}

// float _Complex is classified exactly like struct {f32,f32}: both floats in the low half of one XMM.
fn i32 libm_cabsf_takes_two_floats_in_one_register(arena::Arena* a, const u8[] m) {
    Complex32 z = {3.0, 4.0};
    Complex32 zero = {0.0, 0.0};
    if(!testing::expect_near((f64)cabsf(z), 5.0, 0.0001, m)) { return 1; }
    if(!testing::expect_near((f64)cabsf(zero), 0.0, 0.0001, m)) { return 1; }
    return 0;
}

// ===== round trips through the compiler's own calls =====

struct Vec2 { f32 x; f32 y; }
struct Vec4 { f32 x; f32 y; f32 z; f32 w; }
struct Mat3 { f64 a; f64 b; f64 c; }
struct Pair { i32 lo; i32 hi; }
struct Handle { void* ptr; i32 tag; }
struct Nested { Vec2 head; f32 tail; }
struct Boxed { i32[3] cells; }
union Bits { f32 as_float; i32 as_int; }

fn f32 sum_vec2(Vec2 v) { return v.x * 100.0 + v.y; }
fn f32 sum_vec4(Vec4 v) { return v.x * 1000.0 + v.y * 100.0 + v.z * 10.0 + v.w; }
fn f64 sum_mat3(Mat3 v) { return v.a * 100.0 + v.b * 10.0 + v.c; }
fn i32 sum_pair(Pair p) { return p.lo * 100 + p.hi; }
fn i32 tag_of(Handle h) { if(h.ptr == null) { return h.tag; } return -h.tag; }
fn f32 sum_nested(Nested n) { return n.head.x * 100.0 + n.head.y * 10.0 + n.tail; }
fn i32 sum_boxed(Boxed b) { return b.cells[0] * 100 + b.cells[1] * 10 + b.cells[2]; }
fn i32 int_of(Bits b) { return b.as_int; }
fn f32 mixed_around_vec2(i32 lead, Vec2 v, f32 trail) { return (f32)lead * 1000.0 + v.x * 100.0 + v.y * 10.0 + trail; }

fn Vec2 make_vec2(f32 x, f32 y) { Vec2 v = {x, y}; return v; }
fn Vec4 make_vec4() { Vec4 v = {1.0, 2.0, 3.0, 4.0}; return v; }
fn Mat3 make_mat3() { Mat3 v = {1.0, 2.0, 3.0}; return v; }
fn Pair make_pair(i32 lo, i32 hi) { Pair p = {lo, hi}; return p; }
fn Nested make_nested() { Vec2 head = {1.0, 2.0}; Nested n = {head, 3.0}; return n; }

fn i32 small_float_aggregates_round_trip(arena::Arena* a, const u8[] m) {
    Vec2 v2 = {1.0, 2.0};
    if(!testing::expect_near((f64)sum_vec2(v2), 102.0, 0.0001, m)) { return 1; }
    if(!testing::expect_near((f64)sum_vec4(make_vec4()), 1234.0, 0.0001, m)) { return 1; }
    Vec2 built = make_vec2(7.0, 8.0);
    if(!testing::expect_near((f64)built.x, 7.0, 0.0001, m)) { return 1; }
    if(!testing::expect_near((f64)built.y, 8.0, 0.0001, m)) { return 1; }
    return 0;
}

fn i32 small_integer_aggregates_round_trip(arena::Arena* a, const u8[] m) {
    Pair p = {1, 2};
    Handle null_handle = {null, 7};
    if(!testing::expect_eq(sum_pair(p), 102, m)) { return 1; }
    if(!testing::expect_eq(tag_of(null_handle), 7, m)) { return 1; }
    Pair built = make_pair(4, 5);
    if(!testing::expect_eq(built.lo, 4, m)) { return 1; }
    if(!testing::expect_eq(built.hi, 5, m)) { return 1; }
    return 0;
}

fn i32 oversized_aggregates_round_trip_through_memory(arena::Arena* a, const u8[] m) {
    Mat3 v = {1.0, 2.0, 3.0};
    if(!testing::expect_near(sum_mat3(v), 123.0, 0.0001, m)) { return 1; }
    Mat3 built = make_mat3();
    if(!testing::expect_near(built.a, 1.0, 0.0001, m)) { return 1; }
    if(!testing::expect_near(built.b, 2.0, 0.0001, m)) { return 1; }
    if(!testing::expect_near(built.c, 3.0, 0.0001, m)) { return 1; }
    return 0;
}

fn i32 aggregates_interleave_with_scalar_params(arena::Arena* a, const u8[] m) {
    Vec2 v = {1.0, 2.0};
    if(!testing::expect_near((f64)mixed_around_vec2(5, v, 7.0), 5127.0, 0.0001, m)) { return 1; }
    return 0;
}

fn i32 nested_and_array_aggregates_round_trip(arena::Arena* a, const u8[] m) {
    Boxed b;
    b.cells[0] = 1; b.cells[1] = 2; b.cells[2] = 3;
    Bits bits;
    bits.as_int = 42;
    Nested n = make_nested();
    if(!testing::expect_near((f64)sum_nested(n), 123.0, 0.0001, m)) { return 1; }
    if(!testing::expect_eq(sum_boxed(b), 123, m)) { return 1; }
    if(!testing::expect_eq(int_of(bits), 42, m)) { return 1; }
    return 0;
}

fn i32 aggregates_survive_an_indirect_call(arena::Arena* a, const u8[] m) {
    fn* f32(Vec2) via_pointer = &sum_vec2;
    fn* Mat3() make_via_pointer = &make_mat3;
    Vec2 v = {1.0, 2.0};
    Mat3 built = make_via_pointer();
    if(!testing::expect_near((f64)via_pointer(v), 102.0, 0.0001, m)) { return 1; }
    if(!testing::expect_near(built.c, 3.0, 0.0001, m)) { return 1; }
    return 0;
}

fn f32 many_then_vec2(i64 p0, i64 p1, i64 p2, i64 p3, i64 p4, i64 p5, Vec2 spilled) {
    return (f32)(p0 + p1 + p2 + p3 + p4 + p5) * 100.0 + spilled.x * 10.0 + spilled.y;
}

fn i32 an_aggregate_out_of_registers_still_arrives(arena::Arena* a, const u8[] m) {
    Vec2 v = {1.0, 2.0};
    if(!testing::expect_near((f64)many_then_vec2(1, 1, 1, 1, 1, 1, v), 612.0, 0.0001, m)) { return 1; }
    return 0;
}

fn i32 slices_still_cross_call_boundaries(arena::Arena* a, const u8[] m) {
    const u8[] text = "abcd";
    Vec2 v = {1.0, 2.0};
    if(!testing::expect_eq(slice_len_plus_vec2(text, v), 7, m)) { return 1; }
    return 0;
}

fn i32 slice_len_plus_vec2(const u8[] text, Vec2 v) { return (i32)text.len + (i32)v.x + (i32)v.y; }

struct Marker { }

fn Marker make_marker() { Marker marker; return marker; }
fn i32 count_past_marker(Marker marker, i32 n) { return n; }

fn i32 empty_aggregates_still_pass_and_return(arena::Arena* a, const u8[] m) {
    Marker marker = make_marker();
    if(!testing::expect_eq(count_past_marker(marker, 7), 7, m)) { return 1; }
    return 0;
}

fn i32 main() {
    testing::init();
    const u8[] classify_suite = "ABI Classification Tests";
    const u8[] signature_suite = "ABI Signature Tests";
    const u8[] runtime_suite = "ABI Call Tests";

    testing::add(classify_suite, "scalars_are_direct",                          &scalars_are_direct);
    testing::add(classify_suite, "void_and_null_are_ignored",                   &void_and_null_are_ignored);
    testing::add(classify_suite, "two_floats_share_one_sse_eightbyte",          &two_floats_share_one_sse_eightbyte);
    testing::add(classify_suite, "three_floats_split_two_then_one",             &three_floats_split_two_then_one);
    testing::add(classify_suite, "four_floats_fill_two_sse_eightbytes",         &four_floats_fill_two_sse_eightbytes);
    testing::add(classify_suite, "single_double_is_one_sse_eightbyte",          &single_double_is_one_sse_eightbyte);
    testing::add(classify_suite, "float_then_double_keeps_both_sse",            &float_then_double_keeps_both_sse);
    testing::add(classify_suite, "float_array_packs_like_float_fields",         &float_array_packs_like_float_fields);
    testing::add(classify_suite, "nested_float_structs_flatten",                &nested_float_structs_flatten);
    testing::add(classify_suite, "two_ints_share_one_integer_eightbyte",        &two_ints_share_one_integer_eightbyte);
    testing::add(classify_suite, "integer_wins_the_merge_over_sse",             &integer_wins_the_merge_over_sse);
    testing::add(classify_suite, "narrow_integer_eightbytes_keep_their_width",  &narrow_integer_eightbytes_keep_their_width);
    testing::add(classify_suite, "a_lone_pointer_eightbyte_stays_a_pointer",    &a_lone_pointer_eightbyte_stays_a_pointer);
    testing::add(classify_suite, "a_shared_eightbyte_is_not_a_lone_pointer",    &a_shared_eightbyte_is_not_a_lone_pointer);
    testing::add(classify_suite, "enum_fields_classify_through_their_base",     &enum_fields_classify_through_their_base);
    testing::add(classify_suite, "unions_merge_every_member_at_offset_zero",    &unions_merge_every_member_at_offset_zero);
    testing::add(classify_suite, "aggregates_over_sixteen_bytes_go_to_memory",  &aggregates_over_sixteen_bytes_go_to_memory);

    testing::add(signature_suite, "plain_signature_spends_one_slot_per_param",          &plain_signature_spends_one_slot_per_param);
    testing::add(signature_suite, "a_coerced_param_spends_one_slot_per_eightbyte",      &a_coerced_param_spends_one_slot_per_eightbyte);
    testing::add(signature_suite, "an_sret_return_shifts_every_param_slot",             &an_sret_return_shifts_every_param_slot);
    testing::add(signature_suite, "an_empty_aggregate_stays_a_direct_value",            &an_empty_aggregate_stays_a_direct_value);
    testing::add(signature_suite, "an_aggregate_short_of_integer_registers_spills",     &an_aggregate_short_of_integer_registers_spills);
    testing::add(signature_suite, "an_sret_pointer_consumes_an_integer_register",       &an_sret_pointer_consumes_an_integer_register);
    testing::add(signature_suite, "sse_and_integer_registers_run_out_separately",       &sse_and_integer_registers_run_out_separately);
    testing::add(signature_suite, "a_spilled_aggregate_leaves_registers_for_later_params", &a_spilled_aggregate_leaves_registers_for_later_params);

    testing::add(signature_suite, "float_pairs_are_declared_as_a_float_vector",         &float_pairs_are_declared_as_a_float_vector);
    testing::add(signature_suite, "packed_integers_are_declared_as_one_word",           &packed_integers_are_declared_as_one_word);
    testing::add(signature_suite, "oversized_aggregates_are_declared_byval_and_sret",   &oversized_aggregates_are_declared_byval_and_sret);

    testing::add(runtime_suite, "libc_div_returns_a_packed_integer_eightbyte",  &libc_div_returns_a_packed_integer_eightbyte);
    testing::add(runtime_suite, "libc_ldiv_returns_two_integer_eightbytes",     &libc_ldiv_returns_two_integer_eightbytes);
    testing::add(runtime_suite, "libm_cabsf_takes_two_floats_in_one_register",  &libm_cabsf_takes_two_floats_in_one_register);
    testing::add(runtime_suite, "small_float_aggregates_round_trip",            &small_float_aggregates_round_trip);
    testing::add(runtime_suite, "small_integer_aggregates_round_trip",          &small_integer_aggregates_round_trip);
    testing::add(runtime_suite, "oversized_aggregates_round_trip_through_memory", &oversized_aggregates_round_trip_through_memory);
    testing::add(runtime_suite, "aggregates_interleave_with_scalar_params",     &aggregates_interleave_with_scalar_params);
    testing::add(runtime_suite, "nested_and_array_aggregates_round_trip",       &nested_and_array_aggregates_round_trip);
    testing::add(runtime_suite, "aggregates_survive_an_indirect_call",          &aggregates_survive_an_indirect_call);
    testing::add(runtime_suite, "an_aggregate_out_of_registers_still_arrives",  &an_aggregate_out_of_registers_still_arrives);
    testing::add(runtime_suite, "slices_still_cross_call_boundaries",           &slices_still_cross_call_boundaries);
    testing::add(runtime_suite, "empty_aggregates_still_pass_and_return",       &empty_aggregates_still_pass_and_return);

    return testing::run();
}
