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
	strncpy(t->type_name, name, sizeof(t->type_name) - 1);
	strncpy(t->type_namespace, namespace, sizeof(t->type_namespace) - 1);
	int written = snprintf(t->type_resolved_name, sizeof(t->type_resolved_name), "__%s_%s", t->type_namespace, t->type_name);
	if (written < 0 || (size_t)written >= sizeof(t->type_resolved_name)) {
		// Truncation would silently collide with another mangled name, so bail
		// rather than producing a Type with a non-unique resolved_name.
		fprintf(diag_stream(), "Error: mangled type name '__%s_%s' exceeds %zu-byte buffer.\n", t->type_namespace, t->type_name, sizeof(t->type_resolved_name));
		return NULL;
	}
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
	case TYPE_UNION:
	case TYPE_ENUM:
	case TYPE_UNDECIDED:
		return strcmp(a->type_resolved_name, b->type_resolved_name) == 0;
	}
	return 0;
}

typedef struct {
	char *buf;
	int to_stdout;
	size_t total;
} TypeWriter;

static void tw_write(TypeWriter *w, const char *s) {
	size_t n = strlen(s);
	if (w->buf) {
		memcpy(w->buf, s, n);
		w->buf += n;
		*w->buf = '\0';
	}
	if (w->to_stdout) {
		fputs(s, stdout);
	}
	w->total += n;
}

static void type_write(TypeWriter *w, const Type *type) {
	if (!type)
		return;
	char tmp[64];
	switch (type->type_kind) {
	case TYPE_PRIMITIVE:
		tw_write(w, type->type_name);
		break;
	case TYPE_POINTER:
		type_write(w, type->pointee);
		tw_write(w, "*");
		break;
	case TYPE_ARRAY:
		type_write(w, type->array.element_type);
		snprintf(tmp, sizeof(tmp), "[%d]", type->array.size);
		tw_write(w, tmp);
		break;
	case TYPE_FUNCTION:
		tw_write(w, "fn(");
		for (int i = 0; i < type->function.param_count; ++i) {
			type_write(w, type->function.param_types[i]);
			if (i != type->function.param_count - 1)
				tw_write(w, ", ");
		}
		tw_write(w, ")->");
		type_write(w, type->function.return_type);
		break;
	case TYPE_STRUCT:
		tw_write(w, "struct ");
		if (type->type_namespace[0] != '\0') {
			tw_write(w, type->type_namespace);
			tw_write(w, "::");
		}
		tw_write(w, type->type_name);
		break;
	case TYPE_ENUM:
		tw_write(w, "enum ");
		if (type->type_namespace[0] != '\0') {
			tw_write(w, type->type_namespace);
			tw_write(w, "::");
		}
		tw_write(w, type->type_name);
		break;
	case TYPE_UNDECIDED:
		if (type->type_namespace[0] != '\0') {
			tw_write(w, type->type_namespace);
			tw_write(w, "::");
		}
		tw_write(w, type->type_name);
		break;
	}
}

int type_get_string_len(Type *type, int initial) {
	TypeWriter w = {0};
	type_write(&w, type);
	return initial + (int)w.total;
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

int type_mangle_append(Type *type, char *name, size_t cap) {
	assert(type);
	if (cap == 0)
		return 1;
	size_t len = strlen(name);
	if (len >= cap - 1)
		return 1;
	int written;
	if (type->type_kind == TYPE_PRIMITIVE || type->type_kind == TYPE_STRUCT || type->type_kind == TYPE_UNION || type->type_kind == TYPE_ENUM) {
		written = snprintf(name + len, cap - len, "_%s", type->type_name);
		return written < 0 || (size_t)written >= cap - len;
	}
	if (type->type_kind == TYPE_POINTER) {
		int overflow = type_mangle_append(type->pointee, name, cap);
		len = strlen(name);
		if (len >= cap - 1)
			return 1;
		written = snprintf(name + len, cap - len, "*");
		return overflow || written < 0 || (size_t)written >= cap - len;
	}
	if (type->type_kind == TYPE_UNDECIDED) {
		written = snprintf(name + len, cap - len, "_%s", type->type_resolved_name);
		return written < 0 || (size_t)written >= cap - len;
	}
	// TYPE_ARRAY / TYPE_FUNCTION can't appear as a param type today.
	assert(0 && "type_mangle_append: unsupported Type kind for overload mangling");
	return 1;
}

void type_print(char *string, Type *type) {
	TypeWriter w = {0};
	if (string) {
		// Match the existing append-via-strcat semantic: write at the
		// end of whatever the caller has accumulated.
		w.buf = string + strlen(string);
	} else {
		w.to_stdout = 1;
	}
	type_write(&w, type);
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

Type *get_null_type() {
	static Type primitive_void_type = {TYPE_PRIMITIVE, "void", ""};
	static Type null_type = {TYPE_POINTER, "", "", .pointee = &primitive_void_type};
	return &null_type;
}

int is_int(const Type *type) {
	return type->type_kind == TYPE_PRIMITIVE &&
		   (strcmp(type->type_name, "i8") == 0 || strcmp(type->type_name, "i16") == 0 || strcmp(type->type_name, "i32") == 0 || strcmp(type->type_name, "i64") == 0 || strcmp(type->type_name, "u8") == 0 ||
			strcmp(type->type_name, "u16") == 0 || strcmp(type->type_name, "u32") == 0 || strcmp(type->type_name, "u64") == 0 || strcmp(type->type_name, "bool") == 0);
}

int is_float(const Type *type) { return type->type_kind == TYPE_PRIMITIVE && (strcmp(type->type_name, "f32") == 0 || strcmp(type->type_name, "f64") == 0); }

static int is_bool_type(const Type *t) { return t && t->type_kind == TYPE_PRIMITIVE && strcmp(t->type_name, "bool") == 0; }

static int is_signed_int_type(const Type *t) {
	if (!t || t->type_kind != TYPE_PRIMITIVE)
		return 0;
	return strcmp(t->type_name, "i8") == 0 || strcmp(t->type_name, "i16") == 0 || strcmp(t->type_name, "i32") == 0 || strcmp(t->type_name, "i64") == 0;
}

static int is_unsigned_int_type(const Type *t) {
	if (!t || t->type_kind != TYPE_PRIMITIVE)
		return 0;
	return strcmp(t->type_name, "u8") == 0 || strcmp(t->type_name, "u16") == 0 || strcmp(t->type_name, "u32") == 0 || strcmp(t->type_name, "u64") == 0;
}

static int int_bit_width(const Type *t) {
	if (!t || t->type_kind != TYPE_PRIMITIVE)
		return 0;
	if (strcmp(t->type_name, "i8") == 0 || strcmp(t->type_name, "u8") == 0)
		return 8;
	if (strcmp(t->type_name, "i16") == 0 || strcmp(t->type_name, "u16") == 0)
		return 16;
	if (strcmp(t->type_name, "i32") == 0 || strcmp(t->type_name, "u32") == 0)
		return 32;
	if (strcmp(t->type_name, "i64") == 0 || strcmp(t->type_name, "u64") == 0)
		return 64;
	return 0;
}

static int float_bit_width(const Type *t) {
	if (!t || t->type_kind != TYPE_PRIMITIVE)
		return 0;
	if (strcmp(t->type_name, "f32") == 0)
		return 32;
	if (strcmp(t->type_name, "f64") == 0)
		return 64;
	return 0;
}

int is_widening_int_conversion(const Type *src, const Type *tgt) {
	if ((is_signed_int_type(src) && is_signed_int_type(tgt)) || (is_unsigned_int_type(src) && is_unsigned_int_type(tgt))) {
		return int_bit_width(src) <= int_bit_width(tgt);
	}
	return 0;
}

int is_widening_float_conversion(const Type *src, const Type *tgt) {
	int src_w = float_bit_width(src);
	int tgt_w = float_bit_width(tgt);
	return src_w > 0 && tgt_w > 0 && src_w <= tgt_w;
}

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
		if (is_bool_type(target)) {
			// Numeric primitives are "truthy"
			// in condition contexts (if/while/for/!) — those callers pass
			// permissive=1 and codegen lowers the load + icmp/fcmp against zero.
			// Assignment, argument passing, and return paths use permissive=0,
			// so `bool x = some_int;` still requires an explicit cast.
			if (source->type_kind == TYPE_POINTER)
				return 1;
			if (permissive && source->type_kind == TYPE_PRIMITIVE)
				return 1;
			return 0;
		}

		if (source->type_kind == TYPE_ENUM) {
			Symbol *enum_sym = lookup_symbol(table, source->type_resolved_name, 0);
			if (!enum_sym)
				return 0;
			return type_equals(enum_sym->node->data.enum_decl.base_type, target);
		}

		if (permissive && source->type_kind == TYPE_PRIMITIVE) {
			// Same-signedness widening only — narrowing and cross-signedness
			// conversions must be spelled out with an explicit `(T)` cast.
			return is_widening_int_conversion(source, target) || is_widening_float_conversion(source, target);
		}

		return 0;
	}

	if (source->type_kind == TYPE_POINTER) {
		return target->type_kind == TYPE_POINTER;
	}

	if (source->type_kind != TYPE_POINTER && target->type_kind == TYPE_POINTER) {
		return 0;
	}

	return 0;
}
