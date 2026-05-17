#include "codegen.h"
#include "hashmap.h"
#include "parser.h"
#include "scanner.h"
#include "sema.h"
#include "symbol_table.h"
#include "types.h"

#include <assert.h>
#include <llvm-c/Core.h>
#include <llvm-c/DebugInfo.h>
#include <llvm-c/Target.h>
#include <llvm-c/TargetMachine.h>
#include <llvm-c/Types.h>
#include <stdio.h>
#include <string.h>

#define PLATFORM_POINTER_SIZE 64
#define BYTE_TO_BIT(x) x * 8

typedef enum DebugEncodingType {
	DW_ATE_address = 0x01,
	DW_ATE_boolean = 0x02,
	DW_ATE_complex_float = 0x03,
	DW_ATE_float = 0x04,
	DW_ATE_signed = 0x05,
	DW_ATE_signed_char = 0x06,
	DW_ATE_unsigned = 0x07,
	DW_ATE_unsigned_char = 0x08,
	DW_ATE_imaginary_float = 0x09,
	DW_ATE_packed_decimal = 0x0a,
	DW_ATE_numeric_string = 0x0b,
	DW_ATE_edited = 0x0c,
	DW_ATE_signed_fixed = 0x0d,
	DW_ATE_unsigned_fixed = 0x0e,
	DW_ATE_decimal_float = 0x0f,
	DW_ATE_UTF = 0x10,
	DW_ATE_lo_user = 0x80,
	DW_ATE_hi_user = 0xff
} DebugEncodingType;

// Identity hash for pointer keys in the DIType cache. Shift off the
// low alignment bits so the bucket selection actually varies.
static size_t ptr_hash(const void *key) {
	uintptr_t p = (uintptr_t)key;
	return (size_t)(p >> 3);
}

CodegenLLVM codegen_init(CodegenInitContext *init_params) {
	CodegenLLVM cg = {init_params->should_build_debug, 0};
	cg.llvm_context = LLVMContextCreate();
	cg.module = LLVMModuleCreateWithNameInContext(init_params->module_name, cg.llvm_context);
	cg.builder = LLVMCreateBuilderInContext(cg.llvm_context);
	if (cg.should_build_debug) {
		LLVMTypeRef i32 = LLVMInt32TypeInContext(cg.llvm_context);
		LLVMMetadataRef dwarf_ver = LLVMValueAsMetadata(LLVMConstInt(i32, 5, 0));
		LLVMAddModuleFlag(cg.module, LLVMModuleFlagBehaviorWarning, "Dwarf Version", strlen("Dwarf Version"), dwarf_ver);
		LLVMMetadataRef di_ver = LLVMValueAsMetadata(LLVMConstInt(i32, LLVMDebugMetadataVersion(), 0));
		LLVMAddModuleFlag(cg.module, LLVMModuleFlagBehaviorWarning, "Debug Info Version", strlen("Debug Info Version"), di_ver);
		cg.di_builder = LLVMCreateDIBuilder(cg.module);
		int filename_len = strlen(init_params->filename);
		int dirname_len = strlen(init_params->dir);
		cg.di_file = LLVMDIBuilderCreateFile(cg.di_builder, init_params->filename, filename_len, init_params->dir, dirname_len);
		cg.di_cu = LLVMDIBuilderCreateCompileUnit(cg.di_builder, LLVMDWARFSourceLanguageC, cg.di_file, "saplang", 7, 0, "", 0, 0, "", 0, LLVMDWARFEmissionFull, 0, 0, 0, "", 0, "", 0);
		cg.ditype_cache = hashmap_create(64, ptr_hash, ptr_equals);
	}
	return cg;
}

void codegen_deinit(CodegenLLVM *cg) {
	if (cg->should_build_debug) {
		if (cg->ditype_cache)
			hashmap_destroy(cg->ditype_cache, NULL, NULL);
		LLVMDisposeDIBuilder(cg->di_builder);
	}
	LLVMDisposeBuilder(cg->builder);
	LLVMDisposeModule(cg->module);
	LLVMContextDispose(cg->llvm_context);
}

LLVMTypeRef map_to_llvm(CodegenLLVM *cg, Type *type, Symbol *table) {
	assert(type);
	switch (type->type_kind) {
	case TYPE_PRIMITIVE:
		switch (type->prim) {
		case PRIM_I8:
		case PRIM_U8:
			return LLVMInt8TypeInContext(cg->llvm_context);
		case PRIM_I16:
		case PRIM_U16:
			return LLVMInt16TypeInContext(cg->llvm_context);
		case PRIM_I32:
		case PRIM_U32:
			return LLVMInt32TypeInContext(cg->llvm_context);
		case PRIM_I64:
		case PRIM_U64:
			return LLVMInt64TypeInContext(cg->llvm_context);
		case PRIM_BOOL:
			return LLVMInt1TypeInContext(cg->llvm_context);
		// TODO: add f16
		case PRIM_F32:
			return LLVMFloatTypeInContext(cg->llvm_context);
		case PRIM_F64:
			return LLVMDoubleTypeInContext(cg->llvm_context);
		case PRIM_VOID:
			return LLVMVoidTypeInContext(cg->llvm_context);
		case PRIM_NONE:
			break;
		}
		break;

	case TYPE_POINTER: {
		LLVMTypeRef elem = map_to_llvm(cg, type->pointee, table);
		return LLVMPointerType(elem, 0);
	} break;

	case TYPE_ARRAY: {
		LLVMTypeRef elem = map_to_llvm(cg, type->array.element_type, table);
		return LLVMArrayType(elem, type->array.size);
	} break;

	case TYPE_SLICE: {
		LLVMTypeRef elem = map_to_llvm(cg, type->slice.element_type, table);
		LLVMTypeRef fields[2] = {LLVMPointerType(elem, 0), LLVMInt64TypeInContext(cg->llvm_context)};
		return LLVMStructTypeInContext(cg->llvm_context, fields, 2, 0);
	} break;

	case TYPE_FUNCTION: {
		LLVMTypeRef ret_type = map_to_llvm(cg, type->function.return_type, table);
		LLVMTypeRef *param_types = alloca(sizeof(LLVMTypeRef) * (size_t)type->function.param_count);
		for (int i = 0; i < type->function.param_count; ++i) {
			param_types[i] = map_to_llvm(cg, type->function.param_types[i], table);
		}
		return LLVMFunctionType(ret_type, param_types, type->function.param_count, 0);
	}

	case TYPE_STRUCT: {
		return LLVMGetTypeByName2(cg->llvm_context, type->type_resolved_name);
	}

	case TYPE_UNION: {
		char name[512] = "";
		sprintf(name, "union.%s", type->type_resolved_name);
		return LLVMGetTypeByName2(cg->llvm_context, name);
	} break;

	case TYPE_ENUM: {
		Symbol *sym = lookup_symbol(table, type->type_resolved_name, 0);
		assert(sym && "unknown enum symbol.");
		assert(sym->kind == SYMB_ENUM && "symbol expected to be enum.");
		assert(sym->node && sym->node->type == AST_ENUM_DECL && sym->node->data.enum_decl.base_type);
		return map_to_llvm(cg, sym->node->data.enum_decl.base_type, table);
	} break;

	case TYPE_UNDECIDED:
		assert(0 && "should not be any undecided types in codegen.");
	}
	return NULL;
}

// DWARF tags we need from <dwarf.h> (LLVM doesn't expose them in the C API).
#define DW_TAG_structure_type 0x13
#define DW_TAG_union_type 0x17
#define DW_TAG_enumeration_type 0x04

LLVMMetadataRef map_to_ditype(CodegenLLVM *cg, Type *type, Symbol *table) {
	assert(cg->should_build_debug);
	if (!type)
		return NULL;

	LLVMMetadataRef cached = (LLVMMetadataRef)hashmap_get(cg->ditype_cache, type);
	if (cached)
		return cached;

	LLVMMetadataRef result = NULL;

	switch (type->type_kind) {
	case TYPE_PRIMITIVE: {
		// void to NULL: DWARF represents void by the absence of a type entry.
		// Pointer and subroutine constructors both accept NULL with that meaning.
		if (type->prim == PRIM_VOID)
			return NULL;
		const char *name = type->type_name;
		size_t name_len = strlen(name);
		size_t size = 0;
		size_t align = 0;
		prim_size_align(type->prim, &size, &align);
		LLVMDWARFTypeEncoding enc;
		switch (type->prim) {
		case PRIM_I8:
		case PRIM_I16:
		case PRIM_I32:
		case PRIM_I64:
			enc = DW_ATE_signed;
			break;
		case PRIM_U8:
		case PRIM_U16:
		case PRIM_U32:
		case PRIM_U64:
			enc = DW_ATE_unsigned;
			break;
		case PRIM_F32:
		case PRIM_F64:
			enc = DW_ATE_float;
			break;
		case PRIM_BOOL:
			enc = DW_ATE_boolean;
			break;
		default:
			assert(0 && "unknown primitive kind in DI lowering");
			return NULL;
		}
		result = LLVMDIBuilderCreateBasicType(cg->di_builder, name, name_len, BYTE_TO_BIT(size), enc, 0);
	} break;

	case TYPE_POINTER: {
		LLVMMetadataRef pointee_di = map_to_ditype(cg, type->pointee, table);
		result = LLVMDIBuilderCreatePointerType(cg->di_builder, pointee_di, PLATFORM_POINTER_SIZE, 0, 0, "", 0);
	} break;

	case TYPE_ARRAY: {
		LLVMMetadataRef elem_di = map_to_ditype(cg, type->array.element_type, table);
		size_t elem_size = 0;
		size_t elem_align = 0;
		if (type->array.element_type->type_kind == TYPE_PRIMITIVE) {
			prim_size_align(type->array.element_type->prim, &elem_size, &elem_align);
		} else if (type->array.element_type->type_kind == TYPE_POINTER) {
			elem_size = sizeof(void *);
			elem_align = sizeof(void *);
		}
		uint64_t total_size_bits = BYTE_TO_BIT((uint64_t)elem_size * (uint64_t)type->array.size);
		LLVMMetadataRef subrange = LLVMDIBuilderGetOrCreateSubrange(cg->di_builder, 0, type->array.size);
		result = LLVMDIBuilderCreateArrayType(cg->di_builder, total_size_bits, BYTE_TO_BIT(elem_align), elem_di, &subrange, 1);
	} break;

	case TYPE_SLICE: {
		// Layout matches map_to_llvm above: { ptr, i64 }. 16 bytes on a 64-bit target.
		LLVMMetadataRef elem_di = map_to_ditype(cg, type->slice.element_type, table);
		LLVMMetadataRef ptr_di = LLVMDIBuilderCreatePointerType(cg->di_builder, elem_di, PLATFORM_POINTER_SIZE, 0, 0, "", 0);
		LLVMMetadataRef u64_di = LLVMDIBuilderCreateBasicType(cg->di_builder, "u64", 3, 64, DW_ATE_unsigned, 0);
		LLVMMetadataRef members[2];
		members[0] = LLVMDIBuilderCreateMemberType(cg->di_builder, cg->di_cu, "ptr", 3, cg->di_file, 0, PLATFORM_POINTER_SIZE, PLATFORM_POINTER_SIZE, 0, 0, ptr_di);
		members[1] = LLVMDIBuilderCreateMemberType(cg->di_builder, cg->di_cu, "len", 3, cg->di_file, 0, 64, 64, PLATFORM_POINTER_SIZE, 0, u64_di);
		const char *name = "slice";
		result = LLVMDIBuilderCreateStructType(cg->di_builder, cg->di_cu, name, strlen(name), cg->di_file, 0, PLATFORM_POINTER_SIZE + 64, PLATFORM_POINTER_SIZE, 0, NULL, members, 2, 0, NULL, "", 0);
	} break;

	case TYPE_STRUCT: {
		Symbol *sym = lookup_symbol(table, type->type_resolved_name, 0);
		assert(sym && "unknown struct symbol for DI lowering.");
		ASTNode *struct_decl = sym->node;
		assert(struct_decl && struct_decl->type == AST_STRUCT_DECL);
		TypeInfo info = get_type_info(type, struct_decl);
		const char *name = struct_decl->data.struct_decl.name;
		size_t name_len = strlen(name);
		unsigned line = struct_decl->location.line;

		// Forward-decl placeholder so a self-reference through a pointer
		// resolves to *this* type during member-type construction.
		LLVMMetadataRef placeholder = LLVMDIBuilderCreateReplaceableCompositeType(cg->di_builder, DW_TAG_structure_type, name, name_len, cg->di_cu, cg->di_file, line, 0, BYTE_TO_BIT(info.size),
																				  BYTE_TO_BIT(info.align), 0, NULL, 0);
		hashmap_put(cg->ditype_cache, type, placeholder);

		int field_count = struct_decl->data.struct_decl.field_count;
		LLVMMetadataRef *members = NULL;
		if (field_count > 0)
			members = alloca(sizeof(LLVMMetadataRef) * (size_t)field_count);
		uint64_t cur_offset_bits = 0;
		for (int i = 0; i < field_count; ++i) {
			ASTNode *field = struct_decl->data.struct_decl.fields[i];
			assert(field && field->type == AST_FIELD_DECL);
			TypeInfo field_info = get_type_info(field->data.field_decl.type, field);
			uint64_t field_align_bits = BYTE_TO_BIT(field_info.align);
			if (field_align_bits)
				cur_offset_bits = (cur_offset_bits + field_align_bits - 1) & ~(field_align_bits - 1);
			LLVMMetadataRef field_di = map_to_ditype(cg, field->data.field_decl.type, table);
			members[i] = LLVMDIBuilderCreateMemberType(cg->di_builder, cg->di_cu, field->data.field_decl.name, strlen(field->data.field_decl.name), cg->di_file, field->location.line,
													   BYTE_TO_BIT(field_info.size), field_align_bits, cur_offset_bits, 0, field_di);
			cur_offset_bits += BYTE_TO_BIT(field_info.size);
		}

		result =
			LLVMDIBuilderCreateStructType(cg->di_builder, cg->di_cu, name, name_len, cg->di_file, line, BYTE_TO_BIT(info.size), BYTE_TO_BIT(info.align), 0, NULL, members, field_count, 0, NULL, "", 0);
		LLVMMetadataReplaceAllUsesWith(placeholder, result);
		hashmap_put(cg->ditype_cache, type, result);
		return result;
	} break;

	case TYPE_UNION: {
		Symbol *sym = lookup_symbol(table, type->type_resolved_name, 0);
		assert(sym && "unknown union symbol for DI lowering.");
		ASTNode *union_decl = sym->node;
		assert(union_decl && union_decl->type == AST_UNION_DECL);
		TypeInfo info = get_type_info(type, union_decl);
		const char *name = union_decl->data.union_decl.name;
		size_t name_len = strlen(name);
		unsigned line = union_decl->location.line;

		LLVMMetadataRef placeholder =
			LLVMDIBuilderCreateReplaceableCompositeType(cg->di_builder, DW_TAG_union_type, name, name_len, cg->di_cu, cg->di_file, line, 0, BYTE_TO_BIT(info.size), BYTE_TO_BIT(info.align), 0, NULL, 0);
		hashmap_put(cg->ditype_cache, type, placeholder);

		int field_count = 0;
		for (ASTNode *f = union_decl->data.union_decl.fields; f; f = f->next)
			if (f->type == AST_FIELD_DECL)
				++field_count;

		LLVMMetadataRef *members = NULL;
		if (field_count > 0)
			members = alloca(sizeof(LLVMMetadataRef) * (size_t)field_count);
		int i = 0;
		for (ASTNode *f = union_decl->data.union_decl.fields; f; f = f->next) {
			if (f->type != AST_FIELD_DECL)
				continue;
			TypeInfo field_info = get_type_info(f->data.field_decl.type, f);
			LLVMMetadataRef field_di = map_to_ditype(cg, f->data.field_decl.type, table);
			members[i++] = LLVMDIBuilderCreateMemberType(cg->di_builder, cg->di_cu, f->data.field_decl.name, strlen(f->data.field_decl.name), cg->di_file, f->location.line,
														 BYTE_TO_BIT(field_info.size), BYTE_TO_BIT(field_info.align), 0, 0, field_di);
		}

		result = LLVMDIBuilderCreateUnionType(cg->di_builder, cg->di_cu, name, name_len, cg->di_file, line, BYTE_TO_BIT(info.size), BYTE_TO_BIT(info.align), 0, members, field_count, 0, "", 0);
		LLVMMetadataReplaceAllUsesWith(placeholder, result);
		hashmap_put(cg->ditype_cache, type, result);
		return result;
	} break;

	case TYPE_ENUM: {
		Symbol *sym = lookup_symbol(table, type->type_resolved_name, 0);
		assert(sym && "unknown enum symbol for DI lowering.");
		ASTNode *enum_decl = sym->node;
		assert(enum_decl && enum_decl->type == AST_ENUM_DECL && enum_decl->data.enum_decl.base_type);
		Type *base = enum_decl->data.enum_decl.base_type;
		TypeInfo base_info = get_type_info(base, enum_decl);
		LLVMDWARFTypeEncoding base_enc = (base->type_name[0] == 'u') ? DW_ATE_unsigned : DW_ATE_signed;
		int is_unsigned = base->type_name[0] == 'u';
		LLVMMetadataRef base_di = LLVMDIBuilderCreateBasicType(cg->di_builder, base->type_name, strlen(base->type_name), BYTE_TO_BIT(base_info.size), base_enc, 0);

		int n = enum_decl->data.enum_decl.member_count;
		LLVMMetadataRef *enumerators = NULL;
		if (n > 0)
			enumerators = alloca(sizeof(LLVMMetadataRef) * (size_t)n);
		for (int i = 0; i < n; ++i) {
			EnumMember *m = enum_decl->data.enum_decl.members[i];
			enumerators[i] = LLVMDIBuilderCreateEnumerator(cg->di_builder, m->name, strlen(m->name), m->value, is_unsigned);
		}
		const char *name = enum_decl->data.enum_decl.name;
		result = LLVMDIBuilderCreateEnumerationType(cg->di_builder, cg->di_cu, name, strlen(name), cg->di_file, enum_decl->location.line, BYTE_TO_BIT(base_info.size), BYTE_TO_BIT(base_info.align),
													enumerators, n, base_di);
	} break;

	case TYPE_FUNCTION: {
		// Subroutine type wants [ret_di, param0_di, ...]. Element 0 == NULL means void.
		int n = type->function.param_count + 1;
		LLVMMetadataRef *params = alloca(sizeof(LLVMMetadataRef) * (size_t)n);
		params[0] = map_to_ditype(cg, type->function.return_type, table);
		for (int i = 0; i < type->function.param_count; ++i)
			params[i + 1] = map_to_ditype(cg, type->function.param_types[i], table);
		result = LLVMDIBuilderCreateSubroutineType(cg->di_builder, cg->di_file, params, n, 0);
	} break;

	case TYPE_UNDECIDED:
		assert(0 && "undecided type should not reach DI lowering.");
		return NULL;
	}

	if (result)
		hashmap_put(cg->ditype_cache, type, result);
	return result;
}

typedef enum { PI_NONE, PI_LOAD_PTR, PI_LOAD_VAL, PI_STORE_VAL, PI_STORE_PTR } PassIntention;

typedef struct {
	int current_scope;
	Type *expected_type;
	hashmap_t *loaded_values;
	ASTNode *auxiliary_node;
	ASTNode *current_function_node;
	PassIntention intention;
	LLVMValueRef passed_value;
	LLVMBasicBlockRef end_block;
	LLVMBasicBlockRef loop_beg_block;
	LLVMBasicBlockRef if_cont_block;
} PassContext;

LLVMValueRef codegen_ast(CodegenLLVM *cg, ASTNode *node, Symbol *stable, PassContext ctx);

static LLVMValueRef codegen_cond_to_bool(CodegenLLVM *cg, ASTNode *cond, Symbol *table, PassContext ctx) {
	Type *natural = get_type(table, cond, ctx.current_scope, "");
	PassContext c = ctx;
	c.intention = PI_LOAD_VAL;
	c.expected_type = natural;
	LLVMValueRef val = codegen_ast(cg, cond, table, c);

	LLVMTypeRef val_ty = LLVMTypeOf(val);
	if (val_ty == LLVMInt1TypeInContext(cg->llvm_context))
		return val;

	LLVMTypeKind kind = LLVMGetTypeKind(val_ty);
	if (kind == LLVMIntegerTypeKind)
		return LLVMBuildICmp(cg->builder, LLVMIntNE, val, LLVMConstInt(val_ty, 0, 0), "tobool");
	if (kind == LLVMFloatTypeKind || kind == LLVMDoubleTypeKind || kind == LLVMHalfTypeKind)
		return LLVMBuildFCmp(cg->builder, LLVMRealONE, val, LLVMConstReal(val_ty, 0.0), "tobool");
	if (kind == LLVMPointerTypeKind)
		return LLVMBuildICmp(cg->builder, LLVMIntNE, val, LLVMConstPointerNull(val_ty), "tobool");
	return val;
}

// If `expected` is a slice and `expr` evaluates to something that decays
// to a slice (a fixed-size array, or a typed-null literal), construct the
// fat-pointer { ptr, u64 } value and return it. Otherwise return the
// already-computed `computed_val` unchanged.
//
// The array case has to re-enter codegen with PI_LOAD_PTR because the
// caller already produced a by-value load — we want the *address* of the
// array, not its contents.
static LLVMValueRef maybe_decay_to_slice(CodegenLLVM *cg, ASTNode *expr, LLVMValueRef computed_val, Type *expected, Symbol *table, PassContext ctx) {
	if (!expected || expected->type_kind != TYPE_SLICE)
		return computed_val;
	Type *actual = get_type(table, expr, ctx.current_scope, "");
	if (!actual)
		return computed_val;

	LLVMTypeRef slice_ty = map_to_llvm(cg, expected, table);
	LLVMTypeRef i64_ty = LLVMInt64TypeInContext(cg->llvm_context);

	if (actual->type_kind == TYPE_POINTER && actual->pointee && actual->pointee->type_kind == TYPE_PRIMITIVE && actual->pointee->prim == PRIM_VOID) {
		LLVMTypeRef elem_ptr_ty = LLVMPointerType(map_to_llvm(cg, expected->slice.element_type, table), 0);
		LLVMValueRef slice = LLVMGetUndef(slice_ty);
		slice = LLVMBuildInsertValue(cg->builder, slice, LLVMConstPointerNull(elem_ptr_ty), 0, "slice.ptr");
		slice = LLVMBuildInsertValue(cg->builder, slice, LLVMConstInt(i64_ty, 0, 0), 1, "slice.len");
		return slice;
	}

	if (actual->type_kind != TYPE_ARRAY)
		return computed_val;

	PassContext ptr_ctx = ctx;
	ptr_ctx.intention = PI_LOAD_PTR;
	ptr_ctx.expected_type = actual;
	LLVMValueRef arr_ptr = codegen_ast(cg, expr, table, ptr_ctx);

	int len = actual->array.size;
	LLVMValueRef slice = LLVMGetUndef(slice_ty);
	slice = LLVMBuildInsertValue(cg->builder, slice, arr_ptr, 0, "slice.ptr");
	slice = LLVMBuildInsertValue(cg->builder, slice, LLVMConstInt(i64_ty, len, 0), 1, "slice.len");
	return slice;
}

LLVMValueRef codegen_assignment(CodegenLLVM *cg, ASTNode *node, Symbol *table, PassContext ctx) {
	ASTNode *lvalue = node->data.assignment.lvalue;
	assert(lvalue->type == AST_EXPR_IDENT || lvalue->type == AST_MEMBER_ACCESS || lvalue->type == AST_ARRAY_ACCESS);
	if (lvalue->type == AST_EXPR_IDENT) {
		Symbol *sym = lookup_symbol(table, lvalue->data.ident.resolved_name, ctx.current_scope);
		assert(sym);
		ctx.expected_type = sym->type;
		ctx.auxiliary_node = sym->node;
	} else if (lvalue->type == AST_MEMBER_ACCESS) {
		Type *type = get_type(table, node, ctx.current_scope, "");
		assert(type);
		ctx.expected_type = type;
		ctx.auxiliary_node = node->data.member_access.base;
	} else if (lvalue->type == AST_ARRAY_ACCESS) {
		// `a[i] = v` — the lvalue codegen produces the element pointer
		// (PI_LOAD_PTR falls through the array/slice cases as `gep`), and
		// the rvalue needs to be loaded as the element type so the store
		// width is right.
		Type *type = get_type(table, lvalue, ctx.current_scope, "");
		assert(type);
		ctx.expected_type = type;
		ctx.auxiliary_node = lvalue->data.array_access.base;
	}
	ASTNode *rvalue = node->data.assignment.rvalue;
	LLVMValueRef lhs = codegen_ast(cg, lvalue, table, ctx);
	Type *target_type = ctx.expected_type;
	ctx.intention = PI_LOAD_VAL;
	LLVMValueRef rhs = codegen_ast(cg, rvalue, table, ctx);
	// There is no need for store here since struct literal assignment is already handled
	if (lvalue->type == AST_EXPR_IDENT && rvalue->type == AST_STRUCT_LITERAL)
		return NULL;
	rhs = maybe_decay_to_slice(cg, rvalue, rhs, target_type, table, ctx);
	return LLVMBuildStore(cg->builder, rhs, lhs);
}

LLVMTypeRef codegen_struct_decl(CodegenLLVM *cg, ASTNode *node, Symbol *table) {
	LLVMTypeRef element_types[256];
	assert(node->data.struct_decl.field_count < 257 && "can only have 256 fields max.");
	// Pre-register the named LLVM type before resolving fields so a
	// self-referential field (`Self*`) finds the opaque named type via
	// LLVMGetTypeByName2 in map_to_llvm instead of wrapping NULL.
	LLVMTypeRef struct_type = LLVMGetTypeByName2(cg->llvm_context, node->data.struct_decl.resolved_name);
	if (!struct_type)
		struct_type = LLVMStructCreateNamed(cg->llvm_context, node->data.struct_decl.resolved_name);
	assert(struct_type);
	for (int i = 0; i < node->data.struct_decl.field_count; ++i) {
		ASTNode *current_field = node->data.struct_decl.fields[i];
		element_types[i] = map_to_llvm(cg, current_field->data.field_decl.type, table);
	}
	LLVMStructSetBody(struct_type, element_types, node->data.struct_decl.field_count, 0);
	return struct_type;
}

LLVMTypeRef codegen_union_decl(CodegenLLVM *cg, ASTNode *node, Symbol *table) {
	char union_name[512] = "";
	sprintf(union_name, "union.%s", node->data.union_decl.resolved_name);
	LLVMTypeRef struct_type = LLVMGetTypeByName2(cg->llvm_context, union_name);
	if (!struct_type)
		struct_type = LLVMStructCreateNamed(cg->llvm_context, union_name);
	assert(struct_type);
	LLVMTypeRef max_type_ref = NULL;
	int max_size = 0;
	for (ASTNode *field = node->data.union_decl.fields; field; field = field->next) {
		TypeInfo ti = get_type_info(field->data.field_decl.type, field);
		if (ti.size > max_size) {
			max_type_ref = map_to_llvm(cg, field->data.field_decl.type, table);
			max_size = ti.size;
		}
	}
	assert(max_type_ref);
	LLVMStructSetBody(struct_type, &max_type_ref, 1, 0);
	return struct_type;
}

LLVMValueRef codegen_member_access(CodegenLLVM *cg, ASTNode *node, Symbol *table, PassContext ctx) {
	PassIntention tmp_intention = ctx.intention;
	ctx.intention = PI_LOAD_PTR;
	LLVMValueRef base_value = codegen_ast(cg, node->data.member_access.base, table, ctx);
	assert(base_value);
	ctx.intention = tmp_intention;
	Type *base_type = get_type(table, node->data.member_access.base, ctx.current_scope, "");
	assert(base_type);
	LLVMTypeRef i64_ty = LLVMInt64TypeInContext(cg->llvm_context);
	if (base_type->type_kind == TYPE_ARRAY) {
		// `arr.len` folds to the compile-time constant size.
		assert(strcmp(node->data.member_access.member, "len") == 0);
		return LLVMConstInt(i64_ty, (unsigned long long)base_type->array.size, 0);
	}
	if (base_type->type_kind == TYPE_SLICE) {
		// `s.len` reads field 1 of the fat pointer. base_value is a pointer
		// to the slice header alloca; GEP to the len field and load (or
		// hand back the field pointer if the caller wants an lvalue).
		assert(strcmp(node->data.member_access.member, "len") == 0);
		LLVMTypeRef slice_ty = map_to_llvm(cg, base_type, table);
		LLVMValueRef len_ptr = LLVMBuildStructGEP2(cg->builder, slice_ty, base_value, 1, "slice.len.ptr");
		if (ctx.intention != PI_LOAD_VAL)
			return len_ptr;
		return LLVMBuildLoad2(cg->builder, i64_ty, len_ptr, "slice.len");
	}
	assert(base_type->type_kind == TYPE_STRUCT || base_type->type_kind == TYPE_UNION);
	LLVMTypeRef struct_ty = map_to_llvm(cg, base_type, table);
	assert(struct_ty);
	Symbol *decl_sym = lookup_symbol(table, base_type->type_resolved_name, ctx.current_scope);
	if (base_type->type_kind == TYPE_UNION) {
		int field_index = find_union_field_index(decl_sym->node->data.union_decl.fields, node->data.member_access.member);
		assert(field_index > -1);
		ASTNode *field = decl_sym->node->data.union_decl.fields;
		for (int i = 0; i < field_index || !field; ++i) {
			field = field->next;
		}
		LLVMTypeRef field_type = map_to_llvm(cg, field->data.field_decl.type, table);
		assert(field_type);
		if (ctx.intention != PI_LOAD_VAL) {
			return base_value;
		}
		return LLVMBuildLoad2(cg->builder, field_type, base_value, "");
	} else if (base_type->type_kind == TYPE_STRUCT) {
		int field_index = find_struct_field_index(decl_sym->node, node->data.member_access.member);
		assert(field_index > -1);
		LLVMTypeRef index_type = LLVMIntType(PLATFORM_POINTER_SIZE);
		LLVMValueRef index = LLVMConstInt(index_type, 0, 0);
		LLVMValueRef field_gep = LLVMBuildStructGEP2(cg->builder, struct_ty, base_value, field_index, node->data.member_access.member);
		assert(field_gep);
		if (ctx.intention != PI_LOAD_VAL) {
			return field_gep;
		}
		LLVMTypeRef field_ty = LLVMStructGetTypeAtIndex(struct_ty, field_index);
		return LLVMBuildLoad2(cg->builder, field_ty, field_gep, "");
	}
	return NULL;
}

LLVMValueRef codegen_return(CodegenLLVM *cg, ASTNode *node, Symbol *table, PassContext ctx) {
	// NOTE: this is copy pasted from codegen_function
	// TODO: cache this probably
	char *func_name = ctx.current_function_node->data.func_decl.resolved_name;
	size_t func_name_len = strlen(func_name);
	char *linkage_name = func_name;
	size_t linkage_name_len = func_name_len;
	Symbol *sym = lookup_symbol(table, linkage_name, 0);
	assert(sym);
	assert(sym->type);
	assert(sym->kind == SYMB_FN && sym->type->type_kind == TYPE_FUNCTION);
	ctx.expected_type = sym->type->function.return_type;
	ctx.intention = PI_LOAD_VAL;
	ASTNodeType ret_expr_type = node->data.ret.return_expr->type;
	LLVMValueRef expr = codegen_ast(cg, node->data.ret.return_expr, table, ctx);
	assert(expr);
	expr = maybe_decay_to_slice(cg, node->data.ret.return_expr, expr, ctx.expected_type, table, ctx);
	return LLVMBuildRet(cg->builder, expr);
}

// This can only be assignment
LLVMValueRef codegen_literal(CodegenLLVM *cg, ASTNode *node, Symbol *table, PassContext ctx) {
	LLVMTypeRef ty = map_to_llvm(cg, ctx.expected_type, table);
	switch (node->type) {
	case AST_EXPR_LITERAL:
		if (node->data.literal.is_null) {
			// Use the expected pointer type so `null` takes the shape of
			// its surrounding context (`Foo* p = null` allocates as Foo*,
			// not void*). If sema let a non-pointer expected_type through,
			// fall back to a generic null pointer.
			if (ctx.expected_type && ctx.expected_type->type_kind == TYPE_POINTER)
				return LLVMConstPointerNull(ty);
			return LLVMConstPointerNull(LLVMPointerType(LLVMInt8TypeInContext(cg->llvm_context), 0));
		}
		if (node->data.literal.is_bool) {
			return LLVMConstInt(ty, node->data.literal.bool_value, 0);
		} else if (node->data.literal.is_float) {
			return LLVMConstReal(ty, node->data.literal.float_value);
		}
		return LLVMConstInt(ty, node->data.literal.long_value, 1);
		break;
	case AST_STRUCT_LITERAL: {
		if (ctx.expected_type && ctx.expected_type->type_kind == TYPE_SLICE) {
			// Slice literal: `{ptr, len}` or `{.ptr=p, .len=n}`. Build the
			// fat-pointer aggregate directly via insertvalue. Sema has
			// already validated arity, types, and field names.
			Type *elem = ctx.expected_type->slice.element_type;
			LLVMTypeRef slice_ty = map_to_llvm(cg, ctx.expected_type, table);
			LLVMTypeRef i64_ty = LLVMInt64TypeInContext(cg->llvm_context);
			LLVMTypeRef elem_ptr_ty = LLVMPointerType(map_to_llvm(cg, elem, table), 0);
			Type *ptr_type_ast = new_pointer_type(elem);
			Type *u64_ty_ast = get_primitive_u64();
			ASTNode *ptr_expr = NULL, *len_expr = NULL;
			int pos_index = 0;
			for (int i = 0; i < node->data.struct_literal.count; ++i) {
				FieldInitializer *init = node->data.struct_literal.inits[i];
				int slot;
				if (init->is_designated)
					slot = strcmp(init->field, "ptr") == 0 ? 0 : 1;
				else
					slot = pos_index++;
				if (slot == 0)
					ptr_expr = init->expr;
				else
					len_expr = init->expr;
			}
			PassContext sub = ctx;
			sub.intention = PI_LOAD_VAL;
			sub.expected_type = ptr_type_ast;
			LLVMValueRef ptr_val = ptr_expr->type == AST_EXPR_LITERAL ? LLVMConstPointerNull(elem_ptr_ty) : codegen_ast(cg, ptr_expr, table, sub);
			sub.expected_type = u64_ty_ast;
			LLVMValueRef len_val_raw = codegen_ast(cg, len_expr, table, sub);
			LLVMValueRef len_val = LLVMBuildSExtOrBitCast(cg->builder, len_val_raw, i64_ty, "slice.lit.len");
			LLVMValueRef slice = LLVMGetUndef(slice_ty);
			slice = LLVMBuildInsertValue(cg->builder, slice, ptr_val, 0, "slice.lit.ptr");
			slice = LLVMBuildInsertValue(cg->builder, slice, len_val, 1, "slice.lit");
			LLVMValueRef var_ptr = ctx.passed_value ? ctx.passed_value : (ctx.auxiliary_node ? hashmap_get(ctx.loaded_values, ctx.auxiliary_node->data.var_decl.resolved_name) : NULL);
			if (var_ptr)
				LLVMBuildStore(cg->builder, slice, var_ptr);
			return slice;
		}
		int init_count = node->data.struct_literal.count;
		Symbol *decl_sym = lookup_named_type(table, ctx.expected_type, ctx.current_scope);
		assert(decl_sym);
		ASTNode *decl_node = decl_sym->node;
		assert(decl_node); // sanity
		int field_count = decl_node->data.struct_decl.field_count;
		LLVMValueRef *generated_values = alloca(sizeof(LLVMValueRef) * field_count);
		// TODO: maybe make default field initialization opt-in?
		for (int i = 0; i < field_count; ++i) {
			ASTNode *curr_field = decl_node->data.struct_decl.fields[i];
			LLVMTypeRef field_type = map_to_llvm(cg, curr_field->data.field_decl.type, table);
			generated_values[i] = LLVMConstNull(field_type);
			curr_field = curr_field->next;
		}
		int current_field_index = 0;
		for (int i = 0; i < init_count; ++i) {
			FieldInitializer *init = node->data.struct_literal.inits[i];
			if (init->is_designated) {
				current_field_index = find_struct_field_index(decl_node, init->field);
				assert(current_field_index != -1);
			}
			LLVMValueRef generated_value = NULL;
			ASTNode *curr_field = decl_node->data.struct_decl.fields[current_field_index];
			ctx.expected_type = curr_field->data.field_decl.type;
			if (init->expr->type == AST_STRUCT_LITERAL) {
				LLVMTypeRef inner_ty = map_to_llvm(cg, ctx.expected_type, table);
				LLVMValueRef tmp = LLVMBuildAlloca(cg->builder, inner_ty, "tmp_inner_str");
				PassContext inner_ctx = ctx;
				inner_ctx.intention = PI_STORE_PTR;
				inner_ctx.auxiliary_node = node;
				inner_ctx.passed_value = tmp;
				codegen_literal(cg, init->expr, table, inner_ctx);
				generated_value = LLVMBuildLoad2(cg->builder, inner_ty, tmp, "inner_struct_val");
			} else {
				generated_value = codegen_ast(cg, init->expr, table, ctx);
			}
			generated_values[current_field_index] = generated_value;
			++current_field_index;
		}
		// If global scope
		if (ctx.current_scope == 0) {
			return LLVMConstNamedStruct(ty, generated_values, field_count);
		}
		LLVMValueRef var_ptr = ctx.passed_value ? ctx.passed_value : hashmap_get(ctx.loaded_values, ctx.auxiliary_node->data.var_decl.resolved_name);
		assert(var_ptr);
		for (int i = 0; i < field_count; ++i) {
			ASTNode *curr_field = decl_node->data.struct_decl.fields[i];
			LLVMTypeRef field_type = LLVMStructGetTypeAtIndex(ty, i);
			LLVMTypeRef index_type = LLVMIntType(PLATFORM_POINTER_SIZE);
			LLVMValueRef index = LLVMConstInt(index_type, i, 0);
			char gep_name[512] = "";
			if (ctx.auxiliary_node->type == AST_VAR_DECL) {
				snprintf(gep_name, sizeof(gep_name), "gep_%d%s", i, ctx.auxiliary_node->data.var_decl.resolved_name);
			} else {
				snprintf(gep_name, sizeof(gep_name), "gep_%d", i);
			}
			LLVMValueRef field_gep = LLVMBuildStructGEP2(cg->builder, ty, var_ptr, i, gep_name);
			LLVMBuildStore(cg->builder, generated_values[i], field_gep);
		}
		return var_ptr;
	} break;
	case AST_ARRAY_LITERAL: {
		int count = node->data.array_literal.count;
		LLVMTypeRef elem_ty = map_to_llvm(cg, ctx.expected_type->array.element_type, table);
		assert(elem_ty);
		LLVMTypeRef arr_ty = map_to_llvm(cg, ctx.expected_type, table);
		assert(arr_ty);
		// If global scope, build a constant array
		if (ctx.current_scope == 0) {
			LLVMValueRef *elems = alloca(sizeof(LLVMValueRef) * count);
			for (int i = 0; i < count; i++) {
				ctx.expected_type = ctx.expected_type->array.element_type;
				elems[i] = codegen_literal(cg, node->data.array_literal.elements[i], table, ctx);
				assert(elems[i]);
			}
			return LLVMConstArray(arr_ty, elems, count);
		}
		// Get pointer to first element
		LLVMValueRef ptr =
			LLVMBuildInBoundsGEP2(cg->builder, arr_ty, ctx.passed_value, (LLVMValueRef[]){LLVMConstInt(LLVMInt64TypeInContext(cg->llvm_context), 0, 0), LLVMConstInt(LLVMInt64TypeInContext(cg->llvm_context), 0, 0)}, 2, "arrayinit.begin");
		assert(ptr);
		LLVMValueRef begin_ptr = ptr;
		for (int i = 0; i < count; i++) {
			if (i > 0)
				ptr = LLVMBuildInBoundsGEP2(cg->builder, elem_ty, ptr, (LLVMValueRef[]){LLVMConstInt(LLVMInt64TypeInContext(cg->llvm_context), 1, 0)}, 1, "arrayinit.element");
			else
				ptr = begin_ptr;
			PassContext elem_ctx = ctx;
			elem_ctx.passed_value = ptr;
			elem_ctx.expected_type = ctx.expected_type->array.element_type;
			elem_ctx.intention = PI_LOAD_VAL;
			LLVMValueRef val = codegen_ast(cg, node->data.array_literal.elements[i], table, elem_ctx);
			if (node->data.array_literal.elements[i]->type != AST_ARRAY_LITERAL)
				LLVMBuildStore(cg->builder, val, ptr);
		}
		return ctx.passed_value;
	} break;
	}
	return NULL;
}

LLVMValueRef codegen_global_var_decl(CodegenLLVM *cg, ASTNode *node, Symbol *table, int is_extern) {
	LLVMTypeRef ty = map_to_llvm(cg, node->data.var_decl.type, table);
	LLVMValueRef global_var = LLVMAddGlobal(cg->module, ty, node->data.var_decl.resolved_name);
	PassContext ctx = {0, node->data.var_decl.type, NULL, NULL, NULL, PI_NONE, NULL, NULL, NULL, NULL};
	LLVMValueRef init_value = node->data.var_decl.init ? codegen_literal(cg, node->data.var_decl.init, table, ctx) : LLVMConstNull(ty);
	LLVMSetGlobalConstant(global_var, node->data.var_decl.is_const);
	LLVMSetInitializer(global_var, init_value);
	LLVMSetLinkage(global_var, LLVMExternalLinkage);
	// LLVMSetThreadLocal(global_var, 0);
	// LLVMSetThreadLocalMode(global_var, LLVMNotThreadLocal);
	return global_var;
}

LLVMValueRef codegen_var_decl(CodegenLLVM *cg, ASTNode *node, Symbol *table, PassContext ctx) {
	Symbol *sym = lookup_symbol(table, node->data.var_decl.resolved_name, ctx.current_scope);
	assert(sym);
	LLVMTypeRef ty = map_to_llvm(cg, node->data.var_decl.type, table);
	if (node->data.var_decl.type->type_kind == TYPE_FUNCTION)
		ty = LLVMPointerType(ty, 0);
	LLVMValueRef ptr = LLVMBuildAlloca(cg->builder, ty, sym->resolved_name);
	char *resolved_name = strdup(sym->resolved_name);
	hashmap_put(ctx.loaded_values, resolved_name, ptr);
	if (node->data.var_decl.init) {
		++ctx.current_scope;
		ctx.expected_type = node->data.var_decl.type;
		ctx.auxiliary_node = node;
		ctx.passed_value = ptr;
		LLVMValueRef val = codegen_ast(cg, node->data.var_decl.init, table, ctx);
		if (node->data.var_decl.init->type != AST_STRUCT_LITERAL && node->data.var_decl.init->type != AST_ARRAY_LITERAL) {
			assert(val);
			val = maybe_decay_to_slice(cg, node->data.var_decl.init, val, node->data.var_decl.type, table, ctx);
			LLVMBuildStore(cg->builder, val, ptr);
		}
	}
	return ptr;
}

void free_str(void *str) { free(str); }

LLVMValueRef codegen_function(CodegenLLVM *cg, ASTNode *node, Symbol *table) {
	char *func_name = node->data.func_decl.resolved_name;
	size_t func_name_len = strlen(func_name);
	char *linkage_name = func_name;
	size_t linkage_name_len = func_name_len;
	Symbol *sym = lookup_symbol(table, linkage_name, 0);
	assert(sym);
	assert(sym->type);
	Type *ret_type = sym->type->function.return_type;
	LLVMTypeRef fn_ty = map_to_llvm(cg, sym->type, table);
	LLVMValueRef fn = LLVMAddFunction(cg->module, func_name, fn_ty);
	if (cg->should_build_debug) {
		LLVMMetadataRef sub_ty = map_to_ditype(cg, sym->type, table);
		unsigned line = node->location.line;
		LLVMMetadataRef di_fn = LLVMDIBuilderCreateFunction(cg->di_builder, (LLVMMetadataRef)cg->di_cu, func_name, func_name_len, linkage_name, linkage_name_len, cg->di_file, line, sub_ty, 0, 1, line, 0, 0);
		LLVMSetSubprogram(fn, di_fn);
	}
	LLVMBasicBlockRef entry = LLVMAppendBasicBlockInContext(cg->llvm_context, fn, "entry");
	LLVMPositionBuilderAtEnd(cg->builder, entry);
	hashmap_t *values_map = hashmap_create(64, NULL, NULL);
	// function parameters
	{
		LLVMValueRef *args = alloca(sizeof(LLVMValueRef) * sym->type->function.param_count);
		LLVMGetParams(fn, args);
		LLVMTypeRef *args_types = alloca(sizeof(LLVMTypeRef) * sym->type->function.param_count);
		LLVMGetParamTypes(fn_ty, args_types);
		ASTNode *curr_param = node->data.func_decl.params;
		size_t index = 0;
		while (curr_param) {
			assert(args_types[index]);
			assert(args[index]);
			LLVMTypeRef ty = args_types[index];
			LLVMValueRef ptr = LLVMBuildAlloca(cg->builder, ty, curr_param->data.param_decl.resolved_name);
			char *param_name = strdup(curr_param->data.param_decl.resolved_name);
			hashmap_put(values_map, param_name, ptr);
			LLVMBuildStore(cg->builder, args[index], ptr);
			curr_param = curr_param->next;
			++index;
		}
	}
	PassContext ctx = {1, NULL, values_map, NULL, node, PI_NONE, NULL, NULL, NULL, NULL};
	codegen_ast(cg, node->data.func_decl.body, table, ctx);
	if (hashmap_size(values_map))
		hashmap_destroy(values_map, free_str, NULL);
	if (ret_type->type_kind == TYPE_PRIMITIVE && ret_type->prim == PRIM_VOID) {
		LLVMBuildRetVoid(cg->builder);
	}
	return fn;
}

LLVMValueRef codegen_unary(CodegenLLVM *cg, ASTNode *node, Symbol *table, PassContext ctx) {
	switch (node->data.unary_op.op) {
	case '*': {
		ctx.intention = PI_LOAD_PTR;
		LLVMValueRef ptr = codegen_ast(cg, node->data.unary_op.operand, table, ctx);
		Type *type = get_type(table, node->data.unary_op.operand, ctx.current_scope, "");
		assert(type);
		assert(type->type_kind == TYPE_POINTER);
		LLVMTypeRef val_type = map_to_llvm(cg, type->pointee, table);
		assert(val_type);
		LLVMTypeRef ptr_type = LLVMTypeOf(ptr);
		assert(ptr_type);
		LLVMValueRef ptr_load = LLVMBuildLoad2(cg->builder, ptr_type, ptr, "");
		assert(ptr_load);
		return LLVMBuildLoad2(cg->builder, val_type, ptr_load, "deref");
	} break;
	case '&':
		ctx.intention = PI_LOAD_PTR;
		return codegen_ast(cg, node->data.unary_op.operand, table, ctx);
		break;
	case '!': {
		// Logical not. Route the operand through codegen_cond_to_bool so
		// any scalar (int / float / pointer / bool) gets normalized to
		// an i1 first; this is what makes `!p` for a pointer p work
		// alongside the existing `if (p)` truthy lowering. The bitwise
		// counterpart is `~`.
		LLVMValueRef val = codegen_cond_to_bool(cg, node->data.unary_op.operand, table, ctx);
		return LLVMBuildNot(cg->builder, val, "nottmp");
	} break;
	case '-': {
		ctx.intention = PI_LOAD_VAL;
		LLVMValueRef val = codegen_ast(cg, node->data.unary_op.operand, table, ctx);
		return LLVMBuildNeg(cg->builder, val, "negtmp");
	} break;
	case '~': {
		ctx.intention = PI_LOAD_VAL;
		LLVMValueRef val = codegen_ast(cg, node->data.unary_op.operand, table, ctx);
		return LLVMBuildXor(cg->builder, val, LLVMConstInt(LLVMTypeOf(val), -1, 0), "lnot");
	}
	default:
		assert(0 && "unknown unary op");
		return NULL;
	}
}

LLVMValueRef codegen_binary(CodegenLLVM *cg, ASTNode *node, Symbol *table, PassContext ctx) {
	Type *l_type = get_type(table, node->data.binary_op.left, ctx.current_scope, "");
	assert(l_type);
	PassContext lhs_ctx = ctx;
	lhs_ctx.expected_type = l_type;
	LLVMValueRef L = codegen_ast(cg, node->data.binary_op.left, table, lhs_ctx);
	PassContext rhs_ctx = ctx;
	rhs_ctx.expected_type = l_type;
	LLVMValueRef R = codegen_ast(cg, node->data.binary_op.right, table, rhs_ctx);
	switch (node->data.binary_op.op) {
	case TOK_EQUAL:
		return LLVMBuildICmp(cg->builder, LLVMIntEQ, L, R, "");
	case TOK_NOTEQUAL:
		return LLVMBuildICmp(cg->builder, LLVMIntNE, L, R, "");
	case TOK_LESSTHAN:
		return LLVMBuildICmp(cg->builder, LLVMIntSLT, L, R, "cmplt");
	case TOK_LTOE:
		return LLVMBuildICmp(cg->builder, LLVMIntSLE, L, R, "cmple");
	case TOK_GREATERTHAN:
		return LLVMBuildICmp(cg->builder, LLVMIntSGT, L, R, "cmpgt");
	case TOK_GTOE:
		return LLVMBuildICmp(cg->builder, LLVMIntSGE, L, R, "cmpge");
	case TOK_PLUS:
		return LLVMBuildAdd(cg->builder, L, R, "add");
	case TOK_MINUS:
		return LLVMBuildSub(cg->builder, L, R, "sub");
	case TOK_ASTERISK:
		return LLVMBuildMul(cg->builder, L, R, "mul");
	case TOK_SLASH:
		return LLVMBuildSDiv(cg->builder, L, R, "div");
	case TOK_MODULO:
		return LLVMBuildSRem(cg->builder, L, R, "rem");
	case TOK_AMPERSAND:
		return LLVMBuildAnd(cg->builder, L, R, "and");
	case TOK_BITWISE_OR:
		return LLVMBuildOr(cg->builder, L, R, "or");
	case TOK_BITWISE_XOR:
		return LLVMBuildXor(cg->builder, L, R, "xor");
	case TOK_BITWISE_LSHIFT:
		return LLVMBuildShl(cg->builder, L, R, "shl");
	case TOK_BITWISE_RSHIFT:
		return LLVMBuildAShr(cg->builder, L, R, "shr");
	case TOK_SELFADD: {
		LLVMValueRef add = LLVMBuildAdd(cg->builder, L, R, "add");
		return LLVMBuildStore(cg->builder, add, L);
	}
	case TOK_SELFSUB: {
		LLVMValueRef sub = LLVMBuildSub(cg->builder, L, R, "sub");
		return LLVMBuildStore(cg->builder, sub, L);
	}
	case TOK_SELFDIV: {
		LLVMValueRef div = LLVMBuildSDiv(cg->builder, L, R, "div");
		return LLVMBuildStore(cg->builder, div, L);
	}
	case TOK_SELFMUL: {
		LLVMValueRef mul = LLVMBuildMul(cg->builder, L, R, "mul");
		return LLVMBuildStore(cg->builder, mul, L);
	}
	case TOK_SELFOR: {
		LLVMValueRef or = LLVMBuildOr(cg->builder, L, R, "or");
		return LLVMBuildStore(cg->builder, or, L);
	}
	case TOK_SELFAND: {
		LLVMValueRef and = LLVMBuildAnd(cg->builder, L, R, "and");
		return LLVMBuildStore(cg->builder, and, L);
	}
	default:
		assert(0 && "Unknown binary op");
	}
}

void codegen_imported_symbol(CodegenLLVM *cg, Symbol *sym, Symbol *table) {
	ASTNode *node = sym->node;
	switch (node->type) {
	case AST_VAR_DECL: {
		LLVMTypeRef ty = map_to_llvm(cg, node->data.var_decl.type, table);
		LLVMValueRef global_var = LLVMAddGlobal(cg->module, ty, node->data.var_decl.resolved_name);
		assert(global_var);
		LLVMSetGlobalConstant(global_var, node->data.var_decl.is_const);
		LLVMSetLinkage(global_var, LLVMExternalLinkage);
		LLVMSetExternallyInitialized(global_var, 1);
	} break;
	case AST_UNION_DECL: {
		char union_name[512] = "";
		sprintf(union_name, "union.%s", node->data.union_decl.name);
		LLVMTypeRef struct_type = LLVMStructCreateNamed(cg->llvm_context, union_name);
		assert(struct_type);
	} break;
	case AST_STRUCT_DECL: {
		LLVMTypeRef struct_type = LLVMStructCreateNamed(cg->llvm_context, sym->resolved_name);
		assert(struct_type);
	} break;
	case AST_FN_DECL:
	case AST_EXTERN_FUNC_DECL: {
		char *func_name = node->data.func_decl.resolved_name;
		LLVMTypeRef fn_ty = map_to_llvm(cg, sym->type, table);
		LLVMValueRef fn = LLVMAddFunction(cg->module, func_name, fn_ty);
		LLVMSetLinkage(fn, LLVMExternalLinkage);
	} break;
	case AST_ENUM_DECL:
		break;

	default:
		assert(0 && "Unknown symbol type.");
	}
}

LLVMValueRef codegen_ast(CodegenLLVM *cg, ASTNode *node, Symbol *table, PassContext ctx) {
	switch (node->type) {
	case AST_FN_DECL:
		return codegen_function(cg, node, table);

	case AST_VAR_DECL: {
		LLVMValueRef value = codegen_var_decl(cg, node, table, ctx);
		return value;
	} break;

	case AST_STRUCT_DECL: {
		LLVMTypeRef type = codegen_struct_decl(cg, node, table);
	} break;

	case AST_UNION_DECL: {
		codegen_union_decl(cg, node, table);
	} break;

	case AST_EXPR_IDENT: {
		if (hashmap_contains(ctx.loaded_values, node->data.ident.resolved_name)) {
			LLVMValueRef ptr = hashmap_get(ctx.loaded_values, node->data.ident.resolved_name);
			if (ctx.intention == PI_LOAD_VAL) {
				assert(ctx.expected_type && "Must give expected type with PI_LOAD_VAL");
				LLVMTypeRef ty = map_to_llvm(cg, ctx.expected_type, table);
				return LLVMBuildLoad2(cg->builder, ty, ptr, "");
			}
			return ptr;
		}
		// `&foo` for a function: return the LLVM function value directly so the
		// surrounding store/call can take its address.
		LLVMValueRef named_fn = LLVMGetNamedFunction(cg->module, node->data.ident.resolved_name);
		if (named_fn)
			return named_fn;
		LLVMValueRef named_global = LLVMGetNamedGlobal(cg->module, node->data.ident.resolved_name);
		assert(named_global); // @NOTE: I think that's the only option here - can only be global var
		if (ctx.intention == PI_LOAD_VAL) {
			assert(ctx.expected_type && "Must give expected type with PI_LOAD_VAL");
			LLVMTypeRef ty = map_to_llvm(cg, ctx.expected_type, table);
			return LLVMBuildLoad2(cg->builder, ty, named_global, "");
		}
		return named_global;
	}

	case AST_STRUCT_LITERAL:
	case AST_EXPR_LITERAL:
	case AST_ARRAY_LITERAL:
		return codegen_literal(cg, node, table, ctx);

	case AST_ASSIGNMENT:
		return codegen_assignment(cg, node, table, ctx);

	case AST_DEFERRED_SEQUENCE:
	case AST_BLOCK: {
		for (int i = 0; i < node->data.block.count; ++i) {
			ASTNode *stmt = node->data.block.statements[i];
			codegen_ast(cg, stmt, table, ctx);
		}
	} break;

	case AST_SLICE_RANGE: {
		// `base[lo..hi]` — produces a `T[]`. For an array base we GEP from
		// its alloca; for a slice base we first load the data pointer out
		// of the slice header. Length is `hi - lo` as i64.
		PassContext base_ctx = ctx;
		base_ctx.intention = PI_LOAD_PTR;
		base_ctx.expected_type = get_type(table, node->data.slice_range.base, ctx.current_scope, "");
		assert(base_ctx.expected_type);
		LLVMValueRef base_ptr = codegen_ast(cg, node->data.slice_range.base, table, base_ctx);

		LLVMTypeRef i64_ty = LLVMInt64TypeInContext(cg->llvm_context);
		Type *elem_ast = base_ctx.expected_type->type_kind == TYPE_SLICE ? base_ctx.expected_type->slice.element_type : base_ctx.expected_type->array.element_type;
		LLVMTypeRef elem_ty = map_to_llvm(cg, elem_ast, table);

		PassContext idx_ctx = ctx;
		idx_ctx.intention = PI_LOAD_VAL;
		LLVMValueRef lo = codegen_ast(cg, node->data.slice_range.lo, table, idx_ctx);
		LLVMValueRef hi = codegen_ast(cg, node->data.slice_range.hi, table, idx_ctx);
		LLVMValueRef lo64 = LLVMBuildSExtOrBitCast(cg->builder, lo, i64_ty, "range.lo");
		LLVMValueRef hi64 = LLVMBuildSExtOrBitCast(cg->builder, hi, i64_ty, "range.hi");
		LLVMValueRef len = LLVMBuildSub(cg->builder, hi64, lo64, "range.len");

		LLVMValueRef data_ptr;
		if (base_ctx.expected_type->type_kind == TYPE_SLICE) {
			LLVMTypeRef slice_ty_ref = map_to_llvm(cg, base_ctx.expected_type, table);
			LLVMValueRef data_field = LLVMBuildStructGEP2(cg->builder, slice_ty_ref, base_ptr, 0, "range.data.ptr");
			data_ptr = LLVMBuildLoad2(cg->builder, LLVMPointerType(elem_ty, 0), data_field, "range.data");
		} else {
			LLVMTypeRef arr_ty = map_to_llvm(cg, base_ctx.expected_type, table);
			data_ptr = LLVMBuildInBoundsGEP2(cg->builder, arr_ty, base_ptr, (LLVMValueRef[]){LLVMConstInt(i64_ty, 0, 0), LLVMConstInt(i64_ty, 0, 0)}, 2, "range.arr.base");
		}
		LLVMValueRef sub_ptr = LLVMBuildInBoundsGEP2(cg->builder, elem_ty, data_ptr, &lo64, 1, "range.sub.ptr");

		Type *result_ast = new_slice_type(elem_ast);
		LLVMTypeRef result_ty = map_to_llvm(cg, result_ast, table);
		LLVMValueRef slice = LLVMGetUndef(result_ty);
		slice = LLVMBuildInsertValue(cg->builder, slice, sub_ptr, 0, "range.slice.ptr");
		slice = LLVMBuildInsertValue(cg->builder, slice, len, 1, "range.slice");
		return slice;
	}

	case AST_MEMBER_ACCESS:
		return codegen_member_access(cg, node, table, ctx);

	case AST_RETURN:
		return codegen_return(cg, node, table, ctx);

	case AST_UNARY_EXPR:
		return codegen_unary(cg, node, table, ctx);

	case AST_BINARY_EXPR:
		return codegen_binary(cg, node, table, ctx);

	case AST_CHAR_LIT: {
		LLVMTypeRef u8_type = LLVMInt8TypeInContext(cg->llvm_context);
		return LLVMConstInt(u8_type, node->data.char_literal.literal, 0);
	}

	case AST_ARRAY_ACCESS: {
		PassContext base_ctx = ctx;
		base_ctx.intention = PI_LOAD_PTR;
		base_ctx.expected_type = get_type(table, node->data.array_access.base, ctx.current_scope, "");
		LLVMValueRef base_ptr = codegen_ast(cg, node->data.array_access.base, table, base_ctx);
		PassContext idx_ctx = ctx;
		idx_ctx.intention = PI_LOAD_VAL;
		// Index is always an integer. For literal indices, pin expected_type
		// to u64 so the literal isn't materialized as a constant of the
		// outer context's type (which for `&arr[2]` is i32* — that would
		// produce a zero index and silently break the access). For non-
		// literal indices, leave expected_type alone so loads respect the
		// variable's declared type.
		if (node->data.array_access.index->type == AST_EXPR_LITERAL)
			idx_ctx.expected_type = get_primitive_u64();
		LLVMValueRef idx = codegen_ast(cg, node->data.array_access.index, table, idx_ctx);
		LLVMTypeRef i64_ty = LLVMInt64TypeInContext(cg->llvm_context);
		LLVMValueRef idx64 = LLVMBuildSExtOrBitCast(cg->builder, idx, i64_ty, "idx64");

		if (base_ctx.expected_type->type_kind == TYPE_SLICE) {
			// Pull the data pointer out of the slice header (field 0), then
			// single-index GEP into it. Different shape from the array case
			// because the slice points at a flat run of T, not at [N x T].
			LLVMTypeRef slice_ty = map_to_llvm(cg, base_ctx.expected_type, table);
			LLVMValueRef data_ptr_field = LLVMBuildStructGEP2(cg->builder, slice_ty, base_ptr, 0, "slice.data.ptr");
			LLVMTypeRef elem_ty = map_to_llvm(cg, base_ctx.expected_type->slice.element_type, table);
			LLVMValueRef data_ptr = LLVMBuildLoad2(cg->builder, LLVMPointerType(elem_ty, 0), data_ptr_field, "slice.data");
			LLVMValueRef gep = LLVMBuildInBoundsGEP2(cg->builder, elem_ty, data_ptr, &idx64, 1, "slicegep");
			if (ctx.intention == PI_LOAD_VAL)
				return LLVMBuildLoad2(cg->builder, elem_ty, gep, "sliceload");
			return gep;
		}

		LLVMTypeRef arr_ty = map_to_llvm(cg, base_ctx.expected_type, table);
		LLVMValueRef gep = LLVMBuildInBoundsGEP2(cg->builder, arr_ty, base_ptr, (LLVMValueRef[]){LLVMConstInt(i64_ty, 0, 0), idx64}, 2, "arrgep");
		if (ctx.intention == PI_LOAD_VAL) {
			LLVMTypeRef elem_ty = map_to_llvm(cg, ctx.expected_type, table);
			return LLVMBuildLoad2(cg->builder, elem_ty, gep, "arrload");
		}
		return gep;
	}

	case AST_FN_CALL: {
		Symbol *fn_sym = lookup_symbol(table, node->data.func_call.callee->data.ident.resolved_name, ctx.current_scope);
		assert(fn_sym);
		LLVMTypeRef fn_type = map_to_llvm(cg, fn_sym->type, table);
		assert(fn_type);
		LLVMValueRef callee;
		int is_fn_ptr = fn_sym->kind == SYMB_VAR && fn_sym->type->type_kind == TYPE_FUNCTION;
		if (is_fn_ptr) {
			// Function pointer: load the pointer value out of the variable's alloca.
			LLVMValueRef ptr = hashmap_get(ctx.loaded_values, fn_sym->resolved_name);
			assert(ptr);
			callee = LLVMBuildLoad2(cg->builder, LLVMPointerType(fn_type, 0), ptr, "");
		} else {
			callee = LLVMGetNamedFunction(cg->module, fn_sym->resolved_name);
		}
		assert(callee);
		LLVMValueRef *args = alloca(sizeof(LLVMValueRef) * node->data.func_call.arg_count);
		for (int i = 0; i < node->data.func_call.arg_count; i++) {
			PassContext param_ctx = ctx;
			param_ctx.intention = PI_LOAD_VAL;
			ASTNode *param = node->data.func_call.args[i];
			Type *declared_param_ty = i < fn_sym->type->function.param_count ? fn_sym->type->function.param_types[i] : NULL;
			if (param->type == AST_EXPR_IDENT) {
				Symbol *param_sym = lookup_symbol(table, param->data.ident.resolved_name, ctx.current_scope);
				assert(param_sym);
				param_ctx.expected_type = param_sym->type;
			} else if (declared_param_ty) {
				// Literals and other expressions need the declared param type to
				// pick the right LLVM constant width / kind.
				param_ctx.expected_type = declared_param_ty;
			}
			args[i] = codegen_ast(cg, param, table, param_ctx);
			args[i] = maybe_decay_to_slice(cg, param, args[i], declared_param_ty, table, ctx);
		}
		int is_void = fn_sym->type->function.return_type->type_kind == TYPE_PRIMITIVE && fn_sym->type->function.return_type->prim == PRIM_VOID;
		return LLVMBuildCall2(cg->builder, fn_type, callee, args, node->data.func_call.arg_count, is_void ? "" : "calltmp");
	} break;

	case AST_STRING_LIT: {
		const char *s = node->data.string_literal.text;
		size_t len = strlen(s) + 1;
		LLVMValueRef gv = LLVMAddGlobal(cg->module, LLVMArrayType(LLVMInt8TypeInContext(cg->llvm_context), len), ".str");
		LLVMSetGlobalConstant(gv, 1);
		LLVMValueRef constStr = LLVMConstStringInContext(cg->llvm_context, s, len, 1);
		LLVMSetInitializer(gv, constStr);
		LLVMSetAlignment(gv, 1);
		// decay to i8*
		return LLVMBuildBitCast(cg->builder, gv, LLVMPointerType(LLVMInt8TypeInContext(cg->llvm_context), 0), "strptr");
	} break;

	case AST_ENUM_DECL: {
	} break;

	case AST_ENUM_VALUE: {
		LLVMTypeRef base_ty = map_to_llvm(cg, node->data.enum_value.enum_type, table);
		Symbol *sym = lookup_symbol(table, node->data.enum_value.enum_type->type_resolved_name, ctx.current_scope);
		assert(sym);
		for (int i = 0; i < sym->node->data.enum_decl.member_count; ++i) {
			if (strcmp(sym->node->data.enum_decl.members[i]->name, node->data.enum_value.member) == 0) {
				return LLVMConstInt(base_ty, sym->node->data.enum_decl.members[i]->value, 0);
			}
		}
		assert(0);
	} break;
	case AST_EXTERN_BLOCK: {
		for (int i = 0; i < node->data.extern_block.count; ++i) {
			if (node->data.extern_block.block[i]->type == AST_VAR_DECL) {
				codegen_global_var_decl(cg, node->data.extern_block.block[i], table, 0);
				continue;
			}
			codegen_ast(cg, node->data.extern_block.block[i], table, ctx);
		}
	} break;

	case AST_EXTERN_FUNC_DECL: {
		Symbol *sym = lookup_symbol(table, node->data.extern_func.resolved_name, ctx.current_scope);
		assert(sym);
		LLVMTypeRef fn_ty = map_to_llvm(cg, sym->type, table);
		assert(fn_ty);
		LLVMValueRef fn = LLVMAddFunction(cg->module, sym->resolved_name, fn_ty);
		assert(fn);
		LLVMSetLinkage(fn, LLVMExternalLinkage);
		return fn;
	} break;

	case AST_FOR_LOOP: {
		// init
		LLVMValueRef fn = LLVMGetNamedFunction(cg->module, ctx.current_function_node->data.func_decl.resolved_name);
		codegen_ast(cg, node->data.for_loop.init, table, ctx);
		LLVMBasicBlockRef condBB = LLVMAppendBasicBlockInContext(cg->llvm_context, fn, "forcond");
		LLVMBasicBlockRef bodyBB = LLVMAppendBasicBlockInContext(cg->llvm_context, fn, "forbody");
		LLVMBasicBlockRef stepBB = LLVMAppendBasicBlockInContext(cg->llvm_context, fn, "forstep");
		LLVMBasicBlockRef endBB = LLVMAppendBasicBlockInContext(cg->llvm_context, fn, "forend");
		LLVMBuildBr(cg->builder, condBB);
		// cond
		LLVMPositionBuilderAtEnd(cg->builder, condBB);
		if (node->data.for_loop.condition) {
			LLVMValueRef condition = codegen_cond_to_bool(cg, node->data.for_loop.condition, table, ctx);
			LLVMBuildCondBr(cg->builder, condition, bodyBB, endBB);
		} else {
			LLVMBuildBr(cg->builder, bodyBB);
		}
		// body
		LLVMPositionBuilderAtEnd(cg->builder, bodyBB);
		PassContext for_ctx = ctx;
		for_ctx.loop_beg_block = stepBB;
		for_ctx.end_block = endBB;
		codegen_ast(cg, node->data.for_loop.body, table, for_ctx);
		LLVMBuildBr(cg->builder, stepBB);
		// step
		LLVMPositionBuilderAtEnd(cg->builder, stepBB);
		if (node->data.for_loop.post)
			codegen_ast(cg, node->data.for_loop.post, table, ctx);
		LLVMBuildBr(cg->builder, condBB);
		// end
		LLVMPositionBuilderAtEnd(cg->builder, endBB);
		return NULL;
	} break;

	case AST_WHILE_LOOP: {
		LLVMValueRef fn = LLVMGetNamedFunction(cg->module, ctx.current_function_node->data.func_decl.resolved_name);
		LLVMBasicBlockRef condBB = LLVMAppendBasicBlockInContext(cg->llvm_context, fn, "whilecond");
		LLVMBasicBlockRef bodyBB = LLVMAppendBasicBlockInContext(cg->llvm_context, fn, "whilebody");
		LLVMBasicBlockRef endBB = LLVMAppendBasicBlockInContext(cg->llvm_context, fn, "whileend");
		LLVMBuildBr(cg->builder, condBB);
		// cond
		LLVMPositionBuilderAtEnd(cg->builder, condBB);
		LLVMValueRef cond = codegen_cond_to_bool(cg, node->data.while_loop.condition, table, ctx);
		LLVMBuildCondBr(cg->builder, cond, bodyBB, endBB);
		// body
		LLVMPositionBuilderAtEnd(cg->builder, bodyBB);
		PassContext body_ctx = ctx;
		body_ctx.end_block = endBB;
		body_ctx.loop_beg_block = condBB;
		codegen_ast(cg, node->data.while_loop.body, table, body_ctx);
		LLVMBuildBr(cg->builder, condBB);
		// end
		LLVMPositionBuilderAtEnd(cg->builder, endBB);
		return NULL;
	} break;

	case AST_IF_STMT: {
		LLVMValueRef fn = LLVMGetNamedFunction(cg->module, ctx.current_function_node->data.func_decl.resolved_name);
		LLVMValueRef cond = codegen_cond_to_bool(cg, node->data.if_stmt.condition, table, ctx);
		LLVMBasicBlockRef thenBB = LLVMAppendBasicBlockInContext(cg->llvm_context, fn, "then");
		LLVMBasicBlockRef elseBB = node->data.if_stmt.else_branch ? LLVMAppendBasicBlockInContext(cg->llvm_context, fn, "else") : NULL;
		LLVMBasicBlockRef mergeBB = ctx.if_cont_block ? ctx.if_cont_block : LLVMAppendBasicBlockInContext(cg->llvm_context, fn, "ifcont");
		LLVMBuildCondBr(cg->builder, cond, thenBB, elseBB ? elseBB : mergeBB);
		// then
		LLVMPositionBuilderAtEnd(cg->builder, thenBB);
		PassContext then_ctx = ctx;
		then_ctx.if_cont_block = mergeBB;
		codegen_ast(cg, node->data.if_stmt.then_branch, table, then_ctx);
		LLVMValueRef last_inst = LLVMGetLastInstruction(thenBB);
		if (!last_inst || (LLVMGetInstructionOpcode(last_inst) != LLVMBr && LLVMGetInstructionOpcode(last_inst) != LLVMRet))
			LLVMBuildBr(cg->builder, mergeBB);
		// else
		if (elseBB) {
			LLVMPositionBuilderAtEnd(cg->builder, elseBB);
			PassContext else_ctx = ctx;
			else_ctx.if_cont_block = mergeBB;
			codegen_ast(cg, node->data.if_stmt.else_branch, table, else_ctx);
			last_inst = LLVMGetLastInstruction(elseBB);
			if (!last_inst || (LLVMGetInstructionOpcode(last_inst) != LLVMBr && LLVMGetInstructionOpcode(last_inst) != LLVMRet))
				LLVMBuildBr(cg->builder, mergeBB);
		}
		// merge
		LLVMPositionBuilderAtEnd(cg->builder, mergeBB);
		return NULL;
	} break;

	case AST_CAST: {
		Type *exp_val_type = get_type(table, node->data.cast.expr, ctx.current_scope, "");
		PassContext val_ctx = ctx;
		val_ctx.expected_type = exp_val_type;
		val_ctx.intention = PI_LOAD_VAL;
		LLVMValueRef v = codegen_ast(cg, node->data.cast.expr, table, val_ctx);
		LLVMTypeRef target_ty = map_to_llvm(cg, node->data.cast.target_type, table);
		// integer<->integer
		if (is_int(node->data.cast.target_type) && is_int(exp_val_type)) {
			return LLVMBuildIntCast(cg->builder, v, target_ty, "casttmp");
		}
		// float<->float
		if (LLVMGetTypeKind(LLVMTypeOf(v)) == LLVMFloatTypeKind && LLVMGetTypeKind(target_ty) == LLVMDoubleTypeKind) {
			return LLVMBuildFPExt(cg->builder, v, target_ty, "fpext");
		}
		if (LLVMGetTypeKind(LLVMTypeOf(v)) == LLVMDoubleTypeKind && LLVMGetTypeKind(target_ty) == LLVMFloatTypeKind) {
			return LLVMBuildFPTrunc(cg->builder, v, target_ty, "fptrunc");
		}
		// int<->float
		if (is_int(exp_val_type) && is_float(node->data.cast.target_type)) {
			if (exp_val_type->type_name[0] == 'u') {
				return LLVMBuildUIToFP(cg->builder, v, target_ty, "uitofp");
			} else if (exp_val_type->type_name[0] == 'i') {
				return LLVMBuildSIToFP(cg->builder, v, target_ty, "sitofp");
			}
		}
		if (is_int(node->data.cast.target_type) && is_float(exp_val_type)) {
			if (node->data.cast.target_type->type_name[0] == 'u') {
				return LLVMBuildFPToUI(cg->builder, v, target_ty, "fptoui");
			} else if (node->data.cast.target_type->type_name[0] == 'i') {
				return LLVMBuildFPToSI(cg->builder, v, target_ty, "fptosi");
			}
		}
		// int<->ptr
		if (exp_val_type->type_kind == TYPE_POINTER && is_int(node->data.cast.target_type))
			return LLVMBuildPtrToInt(cg->builder, v, target_ty, "inttoptr");
		if (node->data.cast.target_type->type_kind == TYPE_POINTER && is_int(exp_val_type))
			return LLVMBuildIntToPtr(cg->builder, v, target_ty, "ptrtoint");
		// pointer casts
		if (LLVMGetTypeKind(LLVMTypeOf(v)) == LLVMPointerTypeKind && LLVMGetTypeKind(target_ty) == LLVMPointerTypeKind) {
			return LLVMBuildBitCast(cg->builder, v, target_ty, "bitcast");
		}
		// fallback
		return LLVMBuildBitCast(cg->builder, v, target_ty, "casttmp");
	} break;

	case AST_CONTINUE: {
		assert(ctx.loop_beg_block);
		LLVMBuildBr(cg->builder, ctx.loop_beg_block);
	} break;

	case AST_BREAK: {
		assert(ctx.end_block);
		LLVMBuildBr(cg->builder, ctx.end_block);
	} break;

	case AST_SWITCH_STMT: {
		LLVMValueRef fn = LLVMGetNamedFunction(cg->module, ctx.current_function_node->data.func_decl.resolved_name);
		Type *subject_type = get_type(table, node->data.switch_stmt.subject, ctx.current_scope, "");
		PassContext subject_ctx = ctx;
		subject_ctx.intention = PI_LOAD_VAL;
		subject_ctx.expected_type = subject_type;
		LLVMValueRef subject = codegen_ast(cg, node->data.switch_stmt.subject, table, subject_ctx);
		LLVMBasicBlockRef endBB = LLVMAppendBasicBlockInContext(cg->llvm_context, fn, "switchend");
		LLVMBasicBlockRef elseBB = node->data.switch_stmt.else_body ? LLVMAppendBasicBlockInContext(cg->llvm_context, fn, "switchelse") : NULL;
		LLVMBasicBlockRef defaultBB = elseBB ? elseBB : endBB;
		int total_values = 0;
		for (int c = 0; c < node->data.switch_stmt.case_count; ++c)
			total_values += node->data.switch_stmt.cases[c].value_count;
		LLVMBasicBlockRef *group_bbs = malloc(sizeof(LLVMBasicBlockRef) * (size_t)node->data.switch_stmt.case_count);
		for (int c = 0; c < node->data.switch_stmt.case_count; ++c)
			group_bbs[c] = LLVMAppendBasicBlockInContext(cg->llvm_context, fn, "switchcase");
		LLVMValueRef switch_inst = LLVMBuildSwitch(cg->builder, subject, defaultBB, (unsigned)total_values);
		for (int c = 0; c < node->data.switch_stmt.case_count; ++c) {
			for (int v = 0; v < node->data.switch_stmt.cases[c].value_count; ++v) {
				ASTNode *val_node = node->data.switch_stmt.cases[c].values[v];
				PassContext val_ctx = ctx;
				val_ctx.expected_type = subject_type;
				val_ctx.intention = PI_LOAD_VAL;
				LLVMValueRef val = codegen_ast(cg, val_node, table, val_ctx);
				LLVMAddCase(switch_inst, val, group_bbs[c]);
			}
		}
		for (int c = 0; c < node->data.switch_stmt.case_count; ++c) {
			LLVMPositionBuilderAtEnd(cg->builder, group_bbs[c]);
			codegen_ast(cg, node->data.switch_stmt.cases[c].body, table, ctx);
			LLVMValueRef last_inst = LLVMGetLastInstruction(group_bbs[c]);
			if (!last_inst) {
				LLVMBuildBr(cg->builder, endBB);
			} else {
				LLVMOpcode last_opcode = LLVMGetInstructionOpcode(last_inst);
				if (last_opcode != LLVMBr && last_opcode != LLVMRet)
					LLVMBuildBr(cg->builder, endBB);
			}
		}
		if (elseBB) {
			LLVMPositionBuilderAtEnd(cg->builder, elseBB);
			codegen_ast(cg, node->data.switch_stmt.else_body, table, ctx);
			LLVMValueRef last_inst = LLVMGetLastInstruction(elseBB);
			if (!last_inst) {
				LLVMBuildBr(cg->builder, endBB);
			} else {
				LLVMOpcode last_opcode = LLVMGetInstructionOpcode(last_inst);
				if (last_opcode != LLVMBr && last_opcode != LLVMRet)
					LLVMBuildBr(cg->builder, endBB);
			}
		}
		free(group_bbs);
		LLVMPositionBuilderAtEnd(cg->builder, endBB);
		return NULL;
	} break;

	case AST_FIELD_DECL:
	case AST_DEFER_BLOCK:
		break;
	}
	return NULL;
}

void codegen_run(CodegenLLVM *cg, ASTNode *root, Symbol *table) {
	for (Symbol *sym = table; sym; sym = sym->next) {
		if (sym->is_imported) {
			codegen_imported_symbol(cg, sym, table);
		}
	}
	for (ASTNode *current = root; current; current = current->next) {
		if (current->type == AST_VAR_DECL) {
			codegen_global_var_decl(cg, current, table, 0);
		} else {
			PassContext ctx = {0, NULL, NULL, NULL, NULL, PI_NONE, NULL, NULL, NULL, NULL};
			codegen_ast(cg, current, table, ctx);
		}
	}
}

char *codegen_output_str(CodegenLLVM *cg) {
	if (cg->should_build_debug) {
		LLVMDIBuilderFinalize(cg->di_builder);
	}
	return LLVMPrintModuleToString(cg->module);
}

CompilerResult codegen_init_native_target(void) {
	if (LLVMInitializeNativeTarget())
		return RESULT_FAILURE;
	if (LLVMInitializeNativeAsmPrinter())
		return RESULT_FAILURE;
	return RESULT_SUCCESS;
}

CompilerResult codegen_emit_object_file(CodegenLLVM *cg, const char *path) {
	if (cg->should_build_debug) {
		LLVMDIBuilderFinalize(cg->di_builder);
	}

	char *triple = LLVMGetDefaultTargetTriple();
	LLVMTargetRef target = NULL;
	char *err = NULL;
	if (LLVMGetTargetFromTriple(triple, &target, &err)) {
		fprintf(diag_stream(), "could not get LLVM target for triple '%s': %s\n", triple, err ? err : "(no message)");
		if (err)
			LLVMDisposeMessage(err);
		LLVMDisposeMessage(triple);
		return RESULT_FAILURE;
	}

	char *cpu = LLVMGetHostCPUName();
	char *features = LLVMGetHostCPUFeatures();
	LLVMTargetMachineRef tm = LLVMCreateTargetMachine(target, triple, cpu, features, LLVMCodeGenLevelDefault, LLVMRelocPIC, LLVMCodeModelDefault);
	LLVMDisposeMessage(cpu);
	LLVMDisposeMessage(features);

	LLVMTargetDataRef data_layout = LLVMCreateTargetDataLayout(tm);
	LLVMSetModuleDataLayout(cg->module, data_layout);
	LLVMSetTarget(cg->module, triple);
	LLVMDisposeTargetData(data_layout);
	LLVMDisposeMessage(triple);

	err = NULL;
	// LLVMTargetMachineEmitToFile takes a non-const char *Filename in some
	// historical headers; cast away const defensively. In 19.x it's const.
	if (LLVMTargetMachineEmitToFile(tm, cg->module, (char *)path, LLVMObjectFile, &err)) {
		fprintf(diag_stream(), "failed to emit object file '%s': %s\n", path, err ? err : "(no message)");
		if (err)
			LLVMDisposeMessage(err);
		LLVMDisposeTargetMachine(tm);
		return RESULT_FAILURE;
	}

	LLVMDisposeTargetMachine(tm);
	return RESULT_SUCCESS;
}
