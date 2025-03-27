#include "types.h"
#include "util.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
