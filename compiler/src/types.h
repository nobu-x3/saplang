#pragma once

#include <stddef.h>

typedef struct {
	size_t size;
	size_t align;
} TypeInfo;

typedef enum { TYPE_PRIMITIVE, TYPE_POINTER, TYPE_ARRAY, TYPE_FUNCTION, TYPE_STRUCT, TYPE_ENUM, TYPE_UNDECIDED } TypeKind;

typedef struct Type {
	TypeKind kind;
	char type_name[64];
	char namespace[64];
	union {
		// For pointer types
		struct Type *pointee;

		struct {
			struct Type *element_type;
			int size; // -1 for VLA
		} array;

		struct {
			int param_count;
			struct Type *return_type;
			struct Type **param_types;
		} function;
	};

} Type;

Type *copy_type(Type *type);
void type_deinit(Type *type);
Type *new_primitive_type(const char *name);
Type get_primitive_type(const char* name);
Type *new_pointer_type(Type *pointee);
Type *new_array_type(Type *element_type, int size);
Type *new_function_type(Type *return_type, Type **param_types, int param_count);
Type *new_named_type(const char *name, const char *namespace, TypeKind kind); // structs/enums
int type_equals(const Type *a, const Type *b);
void type_print(char *string, Type *type);
int is_builtin(const Type *type);

// Used for printing symbol table
int type_get_string_len(Type *type, int initial);

struct ASTNode;
TypeInfo get_type_info(Type *type, struct ASTNode *node);
