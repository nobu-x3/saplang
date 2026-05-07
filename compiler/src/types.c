#include "types.h"
#include "parser.h"
#include "symbol_table.h"
#include "util.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static __thread Arena *current_type_arena = NULL;

void type_arena_set(Arena *arena) { current_type_arena = arena; }

Arena *type_arena_get(void) { return current_type_arena; }

TypeInfo compute_struct_size_and_alignment(ASTNode *node);

TypeInfo get_type_info(Type *type, ASTNode *node) {
	TypeInfo info = {0, 1};
	if (!type || !node)
		return info;

	switch (type->type_kind) {
	case TYPE_PRIMITIVE: {
		char *type_name = type->type_name;
		if (strcmp(type_name, "i8") == 0) {
			info.size = 1;
			info.align = 1;
		} else if (strcmp(type_name, "u8") == 0) {
			info.size = 1;
			info.align = 1;
		} else if (strcmp(type_name, "i16") == 0) {
			info.size = 2;
			info.align = 2;
		} else if (strcmp(type_name, "u16") == 0) {
			info.size = 2;
			info.align = 2;
		} else if (strcmp(type_name, "i32") == 0) {
			info.size = 4;
			info.align = 4;
		} else if (strcmp(type_name, "u32") == 0) {
			info.size = 4;
			info.align = 4;
		} else if (strcmp(type_name, "i64") == 0) {
			info.size = 8;
			info.align = 8;
		} else if (strcmp(type_name, "u64") == 0) {
			info.size = 8;
			info.align = 8;
		} else if (strcmp(type_name, "f32") == 0) {
			info.size = 4;
			info.align = 4;
		} else if (strcmp(type_name, "f64") == 0) {
			info.size = 8;
			info.align = 8;
		} else if (strcmp(type_name, "bool") == 0) {
			info.size = 1;
			info.align = 1;
		}
		return info;
	};
	case TYPE_POINTER:
		info.size = sizeof(void *);
		info.align = sizeof(void *);
		return info;
	case TYPE_ARRAY: {
		TypeInfo elem_info = get_type_info(type->array.element_type, node);
		info.size = elem_info.size * type->array.size;
		info.align = elem_info.align;
		return info;
	}
	case TYPE_FUNCTION:
		return info;
	case TYPE_STRUCT:
		return compute_struct_size_and_alignment(node);
	case TYPE_ENUM: {
		if (node && node->type == AST_ENUM_DECL && node->data.enum_decl.base_type) {
			return get_type_info(node->data.enum_decl.base_type, node);
		}
		char *type_name = type->type_name;
		if (strcmp(type_name, "i8") == 0) {
			info.size = 1;
			info.align = 1;
		} else if (strcmp(type_name, "u8") == 0) {
			info.size = 1;
			info.align = 1;
		} else if (strcmp(type_name, "i16") == 0) {
			info.size = 2;
			info.align = 2;
		} else if (strcmp(type_name, "u16") == 0) {
			info.size = 2;
			info.align = 2;
		} else if (strcmp(type_name, "i32") == 0) {
			info.size = 4;
			info.align = 4;
		} else if (strcmp(type_name, "u32") == 0) {
			info.size = 4;
			info.align = 4;
		} else if (strcmp(type_name, "i64") == 0) {
			info.size = 8;
			info.align = 8;
		} else if (strcmp(type_name, "u64") == 0) {
			info.size = 8;
			info.align = 8;
		}
	} break;

	case TYPE_UNION: {
		info.size = 0;
		info.align = 1;
		if (!node || node->type != AST_UNION_DECL)
			return info;
		ASTNode *field = node->data.union_decl.fields;
		while (field) {
			if (field->type == AST_FIELD_DECL) {
				TypeInfo field_info = get_type_info(field->data.field_decl.type, field);
				if (field_info.size > info.size) {
					info.size = field_info.size;
				}
				if (field_info.align > info.align) {
					info.align = field_info.align;
				}
			}
			field = field->next;
		}
		return info;
	}
	case TYPE_UNDECIDED:
		break;
	}
	return info;
}

size_t align_to(size_t offset, size_t alignment) { return (offset + alignment - 1) & ~(alignment - 1); }

TypeInfo compute_struct_size_and_alignment(ASTNode *node) {
	TypeInfo info = {0, 1};
	if (!node)
		return info;

	assert(node->type == AST_STRUCT_DECL);

	size_t offset = 0;
	size_t max_align = 1;

	for (int i = 0; i < node->data.struct_decl.field_count; ++i) {
		ASTNode *current_field = node->data.struct_decl.fields[i];
		assert(current_field->type == AST_FIELD_DECL);
		TypeInfo field_info = get_type_info(current_field->data.field_decl.type, current_field);

		if (field_info.align > max_align)
			max_align = field_info.align;

		offset = align_to(offset, field_info.align);
		offset += field_info.size;
	}

	size_t final_padding = (max_align - (offset % max_align)) % max_align;
	info.size = offset + final_padding;
	info.align = max_align;
	return info;
}

Type *copy_type(Type *type) {
	Type *t = arena_alloc(current_type_arena, sizeof(Type));
	if (!t)
		return NULL;

	t->type_kind = type->type_kind;

	strncpy(t->type_name, type->type_name, sizeof(t->type_name));
	strncpy(t->type_namespace, type->type_namespace, sizeof(t->type_namespace));
	strncpy(t->type_resolved_name, type->type_resolved_name, sizeof(t->type_resolved_name));

	switch (t->type_kind) {
	case TYPE_PRIMITIVE:
	case TYPE_STRUCT:
	case TYPE_UNDECIDED:
	case TYPE_ENUM:
		break;
	case TYPE_POINTER:
		t->pointee = copy_type(type->pointee);
		assert(t->pointee);
		break;
	case TYPE_ARRAY:
		t->array.size = type->array.size;
		t->array.element_type = copy_type(type->array.element_type);
		assert(t->array.element_type);
		break;
	case TYPE_FUNCTION:
		t->function.return_type = copy_type(type->function.return_type);
		assert(t->function.return_type);
		t->function.param_count = type->function.param_count;
		if (t->function.param_count > 0) {
			t->function.param_types = arena_alloc(current_type_arena, sizeof(Type *) * (size_t)t->function.param_count);
			assert(t->function.param_types);
			for (int i = 0; i < t->function.param_count; ++i) {
				t->function.param_types[i] = copy_type(type->function.param_types[i]);
				assert(t->function.param_types[i]);
			}
		} else {
			t->function.param_types = NULL;
		}
		break;
	}
	return t;
}

void type_deinit(Type *type) {
	(void)type;
	// no-op: Types live in the active module's type_arena and are
	// dropped in bulk by module_deinit.
}

Type *new_primitive_type(const char *name) {
	Type *t = arena_alloc(current_type_arena, sizeof(Type));
	if (!t)
		return NULL;
	memset(t, 0, sizeof(Type));
	t->type_kind = TYPE_PRIMITIVE;
	strncpy(t->type_name, name, sizeof(t->type_name));
	return t;
}

Type get_primitive_type(const char *name) {
	Type t = {TYPE_PRIMITIVE};

	strncpy(t.type_name, name, sizeof(t.type_name));
	memset(t.type_namespace, 0, sizeof(t.type_namespace));

	return t;
}

Type *new_pointer_type(Type *pointee) {
	Type *t = arena_alloc(current_type_arena, sizeof(Type));
	if (!t)
		return NULL;
	memset(t, 0, sizeof(Type));
	t->type_kind = TYPE_POINTER;
	t->pointee = pointee;
	return t;
}

Type *new_array_type(Type *element_type, int size) {
	Type *t = arena_alloc(current_type_arena, sizeof(Type));
	if (!t)
		return NULL;
	memset(t, 0, sizeof(Type));
	t->type_kind = TYPE_ARRAY;
	t->array.element_type = element_type;
	t->array.size = size;
	return t;
}

Type *new_function_type(Type *return_type, Type **param_types, int param_count) {
	Type *t = arena_alloc(current_type_arena, sizeof(Type));
	if (!t)
		return NULL;
	memset(t, 0, sizeof(Type));
	t->type_kind = TYPE_FUNCTION;
	t->function.return_type = return_type;
	t->function.param_types = param_types;
	t->function.param_count = param_count;
	return t;
}

Type *new_named_type(const char *name, const char *namespace, TypeKind kind) { // structs/enums
	Type *t = arena_alloc(current_type_arena, sizeof(Type));
	if (!t)
		return NULL;
	memset(t, 0, sizeof(Type));
	t->type_kind = kind;
	strncpy(t->type_name, name, sizeof(t->type_name));
	strncpy(t->type_namespace, namespace, sizeof(t->type_namespace));
	sprintf(t->type_resolved_name, "__%s_%s", t->type_namespace, t->type_name);
	return t;
}

int type_equals(const Type *a, const Type *b) {
	if (!a && !b)
		return 0;
	if (a->type_kind != b->type_kind)
		return 0;
	switch (a->type_kind) {
	case TYPE_PRIMITIVE:
		return strcmp(a->type_name, b->type_name) == 0;
	case TYPE_POINTER:
		return type_equals(a->pointee, b->pointee);
	case TYPE_ARRAY:
		return type_equals(a->array.element_type, b->array.element_type) && a->array.size == b->array.size;
	case TYPE_FUNCTION:
		if (!type_equals(a->function.return_type, b->function.return_type) || a->function.param_count != b->function.param_count)
			return 0;
		for (int i = 0; i < a->function.param_count; ++i) {
			if (!type_equals(a->function.param_types[i], b->function.param_types[i]))
				return 0;
		}
		return 1;
	case TYPE_STRUCT:
		return a->type_kind == TYPE_STRUCT && b->type_kind == TYPE_STRUCT && strcmp(a->type_resolved_name, b->type_resolved_name) == 0;
	case TYPE_UNDECIDED:
	case TYPE_ENUM:
		return a->type_kind == TYPE_ENUM && b->type_kind == TYPE_ENUM && strcmp(a->type_resolved_name, b->type_resolved_name) == 0;
	}
}

int type_get_string_len(Type *type, int initial) {
	if (!type)
		return initial;

	switch (type->type_kind) {
	case TYPE_PRIMITIVE:
		if (type->type_namespace[0] != 0)
			// 2 comes from '::'
			return initial + strlen(type->type_namespace) + 2 + strlen(type->type_name);
		return initial + strlen(type->type_name);
	case TYPE_POINTER:
		// 1 comes from '*'
		return type_get_string_len(type->pointee, initial + 1);
	case TYPE_ARRAY:
		initial += type_get_string_len(type->array.element_type, initial);
		char size_str[64] = "";
		sprintf(size_str, "[%d]", type->array.size);
		return initial + strlen(size_str);
	case TYPE_FUNCTION:
		initial += 3; // "fn("
		for (int i = 0; i < type->function.param_count; ++i) {
			initial += type_get_string_len(type->function.param_types[i], initial);
			if (i != type->function.param_count - 1) {
				initial += 2; // ", "
			}
		}
		initial += 3; // ")->"
		return initial + type_get_string_len(type->function.return_type, initial);
	case TYPE_STRUCT:
		initial += 7; // "struct ";
		if (type->type_namespace[0] != 0)
			// 2 comes from '::'
			return initial + strlen(type->type_namespace) + 2 + strlen(type->type_name);
		return initial + strlen(type->type_name);
	case TYPE_ENUM:
		initial += 5; // "enum ";
		if (type->type_namespace[0] != 0)
			// 2 comes from '::'
			return initial + strlen(type->type_namespace) + 2 + strlen(type->type_name);
		return initial + strlen(type->type_name);
	case TYPE_UNDECIDED:
		if (type->type_namespace[0] != 0)
			// 2 comes from '::'
			return initial + strlen(type->type_namespace) + 2 + strlen(type->type_name);
		return initial + strlen(type->type_name);
	}
}

int is_builtin(const Type *type) {
	switch (type->type_kind) {
	case TYPE_PRIMITIVE: {
		int is_builtin = 0;
		const char *type_name = type->type_name;
		if (strcmp(type_name, "i8") == 0) {
			is_builtin = 1;
		} else if (strcmp(type_name, "u8") == 0) {
			is_builtin = 1;
		} else if (strcmp(type_name, "i16") == 0) {
			is_builtin = 1;
		} else if (strcmp(type_name, "u16") == 0) {
			is_builtin = 1;
		} else if (strcmp(type_name, "i32") == 0) {
			is_builtin = 1;
		} else if (strcmp(type_name, "u32") == 0) {
			is_builtin = 1;
		} else if (strcmp(type_name, "i64") == 0) {
			is_builtin = 1;
		} else if (strcmp(type_name, "u64") == 0) {
			is_builtin = 1;
		} else if (strcmp(type_name, "f32") == 0) {
			is_builtin = 1;
		} else if (strcmp(type_name, "f64") == 0) {
			is_builtin = 1;
		} else if (strcmp(type_name, "bool") == 0) {
			is_builtin = 1;
		}
		return is_builtin;
	} break;
	case TYPE_POINTER:
		return is_builtin(type->pointee);
		break;
	case TYPE_ARRAY:
		return is_builtin(type->array.element_type);
		break;
	case TYPE_FUNCTION:
		return 1;
	case TYPE_STRUCT:
		return 0;
	case TYPE_ENUM:
		return 0;
	case TYPE_UNDECIDED:
		return 0;
	}
}

void type_print(char *string, Type *type) {
	if (!type)
		return;
	switch (type->type_kind) {
	case TYPE_PRIMITIVE:
		print(string, "%s", type->type_name);
		break;
	case TYPE_POINTER:
		type_print(string, type->pointee);
		print(string, "*");
		break;
	case TYPE_ARRAY:
		type_print(string, type->array.element_type);
		print(string, "[%d]", type->array.size);
		break;
	case TYPE_FUNCTION:
		print(string, "fn(");
		for (int i = 0; i < type->function.param_count; ++i) {
			type_print(string, type->function.param_types[i]);
			if (i != type->function.param_count - 1) {
				print(string, ", ");
			}
		}
		print(string, ")->");
		type_print(string, type->function.return_type);
		break;
	case TYPE_STRUCT:
		if (type->type_namespace[0] != '\0') {
			print(string, "struct %s::%s", type->type_namespace, type->type_name);
		} else {
			print(string, "struct %s", type->type_name);
		}
		break;
	case TYPE_ENUM:
		if (type->type_namespace[0] != '\0') {
			print(string, "enum %s::%s", type->type_namespace, type->type_name);
		} else {
			print(string, "enum %s", type->type_name);
		}
		break;
	case TYPE_UNDECIDED:
		if (type->type_namespace[0] != '\0') {
			print(string, "%s::%s", type->type_namespace, type->type_name);
		} else {
			print(string, "%s", type->type_name);
		}
	}
}

int find_struct_field_index(struct ASTNode *struct_decl, const char *field_name) {
	for (int i = 0; i < struct_decl->data.struct_decl.field_count; ++i) {
		ASTNode *curr_field = struct_decl->data.struct_decl.fields[i];
		if (strcmp(curr_field->data.field_decl.name, field_name) == 0)
			return i;
	}
	return -1;
}

int find_union_field_index(struct ASTNode *fields, const char *field_name) {
	ASTNode *field = fields;
	int index = 0;
	while (field) {
		if (strcmp(field_name, field->data.field_decl.name) == 0)
			return index;
		++index;
		field = field->next;
	}
	return -1;
}

Type *get_primitive_bool() {
	static Type primitive_bool_type = {TYPE_PRIMITIVE, "bool", ""};
	return &primitive_bool_type;
}

Type *get_primitive_i32() {
	static Type primitive_i32_type = {TYPE_PRIMITIVE, "i32", ""};
	return &primitive_i32_type;
}

Type *get_primitive_f32() {
	static Type primitive_f32_type = {TYPE_PRIMITIVE, "f32", ""};
	return &primitive_f32_type;
}

Type *get_primitive_u8() {
	static Type primitive_u8_type = {TYPE_PRIMITIVE, "u8", ""};
	return &primitive_u8_type;
}

Type *get_string_type() {
	static Type primitive_u8_type = {TYPE_PRIMITIVE, "u8", ""};
	static Type string_literal_type = {TYPE_POINTER, "", "", .pointee = &primitive_u8_type};
	return &string_literal_type;
}

int is_int(const Type *type) {
	return type->type_kind == TYPE_PRIMITIVE &&
		   (strcmp(type->type_name, "i8") == 0 || strcmp(type->type_name, "i16") == 0 || strcmp(type->type_name, "i32") == 0 || strcmp(type->type_name, "i64") == 0 || strcmp(type->type_name, "u8") == 0 ||
			strcmp(type->type_name, "u16") == 0 || strcmp(type->type_name, "u32") == 0 || strcmp(type->type_name, "u64") == 0 || strcmp(type->type_name, "bool") == 0);
}

int is_float(const Type *type) { return type->type_kind == TYPE_PRIMITIVE && (strcmp(type->type_name, "f32") == 0 || strcmp(type->type_name, "f64") == 0); }

int is_convertible(const Type *source, const Type *target, int permissive, Symbol *table) {
	if (!source || !target)
		return 0;

	// Allow identical types
	if (type_equals(source, target))
		return 1;

	// Allow array decay
	if (source->type_kind == TYPE_ARRAY && target->type_kind == TYPE_POINTER) {
		// Could call for is_convertible on underlying types but easier to debug non-recursive code
		int decay_count = 1;
		Type *underlying_array_type = source->array.element_type;
		while (underlying_array_type && underlying_array_type->type_kind == TYPE_ARRAY) {
			++decay_count;
			underlying_array_type = underlying_array_type->array.element_type;
		}

		int pointer_count = 1;
		Type *underlying_pointer_type = target->pointee;
		while (underlying_pointer_type && underlying_pointer_type->type_kind == TYPE_POINTER) {
			++pointer_count;
			underlying_pointer_type = underlying_pointer_type->pointee;
		}

		return pointer_count == decay_count && type_equals(underlying_array_type, underlying_pointer_type);
	}
	if (target->type_kind == TYPE_PRIMITIVE) {
		if (strcmp(target->type_name, "bool") == 0) {
			if (source->type_kind == TYPE_POINTER)
				return 1;

			if (source->type_kind == TYPE_PRIMITIVE)
				return 1;
		}

		if (source->type_kind == TYPE_ENUM) {
			Symbol *enum_sym = lookup_symbol(table, source->type_resolved_name, 0);
			if (!enum_sym)
				return 0;
			return type_equals(enum_sym->node->data.enum_decl.base_type, target);
		}

		if (permissive) {
			if (source->type_kind == TYPE_PRIMITIVE) {
				return (is_int(target) && is_int(source)) || (is_float(target) && is_float(source));
			}
			return 0;
		}
	}

	if (source->type_kind == TYPE_POINTER) {
		return target->type_kind == TYPE_POINTER;
	}

	if (source->type_kind != TYPE_POINTER && target->type_kind == TYPE_POINTER) {
		return 0;
	}

	return 0;
}
