#pragma once

#include "arena.h"
#include <stddef.h>

typedef struct {
	size_t size;
	size_t align;
} TypeInfo;

typedef enum { TYPE_PRIMITIVE, TYPE_POINTER, TYPE_ARRAY, TYPE_FUNCTION, TYPE_STRUCT, TYPE_ENUM, TYPE_UNION, TYPE_UNDECIDED } TypeKind;

typedef struct Type {
	TypeKind type_kind;
	char type_name[64];
	char type_namespace[64];
    char type_resolved_name[128];
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

// Per-thread arena pointer used by every Type constructor below
// (new_*_type and copy_type). Callers must point this at the active
// module's type_arena before allocating Types — parser, sema task,
// codegen task, and the symbol-table merge step in the driver each
// take responsibility for setting it.
void type_arena_set(Arena *arena);
Arena *type_arena_get(void);

Type *copy_type(Type *type);
// Kept as an empty function so existing call sites compile, but Types
// now live in module-scoped arenas and are dropped in bulk by
// module_deinit. Per-Type free is no longer required (or correct).
void type_deinit(Type *type);
Type *new_primitive_type(const char *name);
Type get_primitive_type(const char *name);
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

// return -1 if field not present
int find_struct_field_index(struct ASTNode *struct_decl, const char *field_name);
int find_union_field_index(struct ASTNode *fields, const char *field_name);

Type *get_primitive_bool();
Type *get_primitive_i32();
Type *get_primitive_f32();
Type *get_primitive_u8();
Type *get_string_type();
// Type of the `null` literal: pointer-to-void. Convertible to any
// pointer type via the existing pointer→pointer rule in is_convertible.
Type *get_null_type();

int is_builtin(const Type *type);
int is_int(const Type *type);
int is_float(const Type *type);

struct Symbol;

int is_convertible(const Type *source, const Type *target, int permissive, struct Symbol *table);
