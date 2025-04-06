#include "types.h"
#include "parser.h"
#include "util.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

TypeInfo compute_struct_size_and_alignment(ASTNode *node);

TypeInfo get_type_info(Type *type, ASTNode *node) {
	TypeInfo info = {0, 1};
	if (!type || !node)
		return info;

	switch (type->kind) {
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
	}
	case TYPE_UNDECIDED:
		break;
	}
	return info;
}

TypeInfo compute_struct_size_and_alignment(ASTNode *node) {
	TypeInfo info = {0, 1};
	if (!node)
		return info;

	assert(node->type == AST_STRUCT_DECL);

	size_t offset = 0;
	size_t max_align = 1;

	ASTNode *current_field = node->data.struct_decl.fields;
	while (current_field) {
		assert(current_field->type == AST_FIELD_DECL);
		TypeInfo field_info = get_type_info(current_field->data.field_decl.type, current_field);

		if (field_info.align > max_align)
			max_align = field_info.align;

		size_t padding = (info.align - (offset % info.align)) % info.align;
		offset += padding;
		offset += info.size;

		current_field = current_field->next;
	}

	size_t final_padding = (max_align - (offset % max_align) % max_align);
	info.size = offset + final_padding;
	info.align = max_align;
	return info;
}

size_t align_to(size_t offset, size_t alignment) { return (offset + alignment - 1) & ~(alignment - 1); }

Type *copy_type(Type *type) {
	Type *t = malloc(sizeof(Type));
	if (!t)
		return NULL;

	t->kind = type->kind;

	strncpy(t->type_name, type->type_name, sizeof(t->type_name));
	strncpy(t->namespace, type->namespace, sizeof(t->namespace));

	switch (t->kind) {
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
		t->function.param_types = malloc(sizeof(Type) * t->function.param_count);
		assert(t->function.param_types);
		for (int i = 0; i < t->function.param_count; ++i) {
			t->function.param_types[i] = copy_type(type->function.param_types[i]);
			assert(t->function.param_types[i]);
		}
		break;
	}
	return t;
}

void type_deinit(Type *type) {
	if (!type)
		return;

	memset(type->type_name, 0, sizeof(type->type_name));
	memset(type->namespace, 0, sizeof(type->namespace));

	switch (type->kind) {
	case TYPE_STRUCT:
	case TYPE_ENUM:
	case TYPE_UNDECIDED:
	case TYPE_PRIMITIVE:
		break;
	case TYPE_POINTER:
		type_deinit(type->pointee);
		free(type->pointee);
		type->pointee = NULL;
		break;
	case TYPE_ARRAY:
		type_deinit(type->array.element_type);
		free(type->array.element_type);
		type->array.element_type = NULL;
		break;
	case TYPE_FUNCTION:
		type_deinit(type->function.return_type);
		for (int i = 0; i < type->function.param_count; ++i) {
			type_deinit(type->function.param_types[i]);
			free(type->function.param_types[i]);
			type->function.param_types[i] = NULL;
		}
		free(type->function.param_types);
		type->function.param_types = NULL;
		break;
	}
}

Type *new_primitive_type(const char *name) {
	Type *t = malloc(sizeof(Type));
	if (!t)
		return NULL;
	t->kind = TYPE_PRIMITIVE;
	strncpy(t->type_name, name, sizeof(t->type_name));
	memset(t->namespace, 0, sizeof(t->namespace));
	return t;
}

Type get_primitive_type(const char *name) {
	Type t = {TYPE_PRIMITIVE};

	strncpy(t.type_name, name, sizeof(t.type_name));
	memset(t.namespace, 0, sizeof(t.namespace));

	return t;
}

Type *new_pointer_type(Type *pointee) {
	Type *t = malloc(sizeof(Type));
	if (!t)
		return NULL;
	memset(t->type_name, 0, sizeof(t->type_name));
	memset(t->namespace, 0, sizeof(t->namespace));
	t->kind = TYPE_POINTER;
	t->pointee = pointee;
	return t;
}

Type *new_array_type(Type *element_type, int size) {
	Type *t = malloc(sizeof(Type));
	if (!t)
		return NULL;
	memset(t->type_name, 0, sizeof(t->type_name));
	memset(t->namespace, 0, sizeof(t->namespace));
	t->kind = TYPE_ARRAY;
	t->array.element_type = element_type;
	t->array.size = size;
	return t;
}

Type *new_function_type(Type *return_type, Type **param_types, int param_count) {
	Type *t = malloc(sizeof(Type));
	if (!t)
		return NULL;
	t->kind = TYPE_FUNCTION;
	memset(t->type_name, 0, sizeof(t->type_name));
	memset(t->namespace, 0, sizeof(t->namespace));
	t->function.return_type = return_type;
	t->function.param_types = param_types;
	t->function.param_count = param_count;
	return t;
}

Type *new_named_type(const char *name, const char *namespace, TypeKind kind) { // structs/enums
	Type *t = malloc(sizeof(Type));
	if (!t)
		return NULL;

	t->kind = kind;
	strncpy(t->type_name, name, sizeof(t->type_name));
	strncpy(t->namespace, namespace, sizeof(t->namespace));
	return t;
}

int type_equals(const Type *a, const Type *b) {
	if (!a && !b)
		return 0;
	if (a->kind != b->kind)
		return 0;
	switch (a->kind) {
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
	case TYPE_UNDECIDED:
	case TYPE_ENUM:
		return strcmp(a->namespace, b->namespace) == 0 == 0 && strcmp(a->type_name, b->type_name);
	}
}

int type_get_string_len(Type *type, int initial) {
	if (!type)
		return initial;

	switch (type->kind) {
	case TYPE_PRIMITIVE:
		if (type->namespace[0] != 0)
			// 2 comes from '::'
			return initial + strlen(type->namespace) + 2 + strlen(type->type_name);
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
		if (type->namespace[0] != 0)
			// 2 comes from '::'
			return initial + strlen(type->namespace) + 2 + strlen(type->type_name);
		return initial + strlen(type->type_name);
	case TYPE_ENUM:
		initial += 5; // "enum ";
		if (type->namespace[0] != 0)
			// 2 comes from '::'
			return initial + strlen(type->namespace) + 2 + strlen(type->type_name);
		return initial + strlen(type->type_name);
	case TYPE_UNDECIDED:
		if (type->namespace[0] != 0)
			// 2 comes from '::'
			return initial + strlen(type->namespace) + 2 + strlen(type->type_name);
		return initial + strlen(type->type_name);
	}
}

int is_builtin(const Type *type) {
	switch (type->kind) {
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
	switch (type->kind) {
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
		if (type->namespace[0] != '\0') {
			print(string, "struct %s::%s", type->namespace, type->type_name);
		} else {
			print(string, "struct %s", type->type_name);
		}
		break;
	case TYPE_ENUM:
		if (type->namespace[0] != '\0') {
			print(string, "enum %s::%s", type->namespace, type->type_name);
		} else {
			print(string, "enum %s", type->type_name);
		}
		break;
	case TYPE_UNDECIDED:
		if (type->namespace[0] != '\0') {
			print(string, "%s::%s", type->namespace, type->type_name);
		} else {
			print(string, "%s", type->type_name);
		}
	}
}
