#pragma once

#include <stddef.h>

// Linked list of pages; allocations bump within the head page, falling
// back to a fresh page when out of space. Individual allocations are not
// freeable — the whole arena is dropped at once via arena_deinit.
typedef struct ArenaPage {
	struct ArenaPage *next;
	size_t cap;
	size_t used;
	char data[];
} ArenaPage;

typedef struct {
	ArenaPage *head;
	size_t default_page_size;
} Arena;

// default_page_size of 0 picks an internal default (64 KiB).
void arena_init(Arena *arena, size_t default_page_size);

void arena_deinit(Arena *arena);

// Returns 8-byte aligned memory of at least `size` bytes, or NULL on
// allocation failure. Allocations larger than default_page_size get a
// dedicated page sized to fit.
void *arena_alloc(Arena *arena, size_t size);

// Allocates a new chunk of `new_size` bytes and copies the first
// `old_size` bytes of `old` into it. `old` is left in place inside the
// arena (no individual free), so callers should size their initial
// arrays sensibly to limit the wasted space across grows.
void *arena_realloc_grow(Arena *arena, void *old, size_t old_size, size_t new_size);

// Arena-backed analogues of util.h's da_init / da_push. The caller
// passes an Arena* — initial buffer comes from the arena, and grows
// allocate a fresh chunk in the arena (the old chunk is left behind,
// freed in bulk by arena_deinit). Returns NULL from the enclosing
// function if allocation fails — same convention as the heap variants.
#define da_init_arena(xs, cap, arena_ptr)                                                                                                                                                                                                      \
	do {                                                                                                                                                                                                                                       \
		(xs).count = 0;                                                                                                                                                                                                                        \
		(xs).capacity = (cap);                                                                                                                                                                                                                 \
		(xs).data = arena_alloc((arena_ptr), (size_t)(xs).capacity * sizeof(*(xs).data));                                                                                                                                                      \
		if (!(xs).data)                                                                                                                                                                                                                        \
			return NULL;                                                                                                                                                                                                                       \
	} while (0)

#define da_push_arena(xs, x, arena_ptr)                                                                                                                                                                                                        \
	do {                                                                                                                                                                                                                                       \
		if ((xs).count >= (xs).capacity) {                                                                                                                                                                                                     \
			size_t _da_old_bytes = (size_t)(xs).capacity * sizeof(*(xs).data);                                                                                                                                                                 \
			(xs).capacity *= 2;                                                                                                                                                                                                                \
			(xs).data = arena_realloc_grow((arena_ptr), (xs).data, _da_old_bytes, (size_t)(xs).capacity * sizeof(*(xs).data));                                                                                                                 \
			if (!(xs).data)                                                                                                                                                                                                                    \
				return NULL;                                                                                                                                                                                                                   \
		}                                                                                                                                                                                                                                      \
		(xs).data[(xs).count++] = (x);                                                                                                                                                                                                         \
	} while (0)

// _unsafe variants for callers that return void and don't propagate
// allocation failures (e.g., late-stage AST rewriting). Identical to the
// safe versions except they don't bail on a NULL return from the arena.
#define da_init_arena_unsafe(xs, cap, arena_ptr)                                                                                                                                                                                               \
	do {                                                                                                                                                                                                                                       \
		(xs).count = 0;                                                                                                                                                                                                                        \
		(xs).capacity = (cap);                                                                                                                                                                                                                 \
		(xs).data = arena_alloc((arena_ptr), (size_t)(xs).capacity * sizeof(*(xs).data));                                                                                                                                                      \
	} while (0)

#define da_push_arena_unsafe(xs, x, arena_ptr)                                                                                                                                                                                                 \
	do {                                                                                                                                                                                                                                       \
		if ((xs).count >= (xs).capacity) {                                                                                                                                                                                                     \
			size_t _da_old_bytes = (size_t)(xs).capacity * sizeof(*(xs).data);                                                                                                                                                                 \
			(xs).capacity *= 2;                                                                                                                                                                                                                \
			(xs).data = arena_realloc_grow((arena_ptr), (xs).data, _da_old_bytes, (size_t)(xs).capacity * sizeof(*(xs).data));                                                                                                                 \
		}                                                                                                                                                                                                                                      \
		(xs).data[(xs).count++] = (x);                                                                                                                                                                                                         \
	} while (0)
