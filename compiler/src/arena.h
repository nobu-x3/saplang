#pragma once

#include <stdbool.h>
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

// Arena-backed analogues of util.h's da_init / da_push. The initial
// buffer comes from `arena_ptr`, and grows allocate a fresh chunk in the
// arena (the old chunk is left behind, freed in bulk by arena_deinit).
// Both macros yield a bool — true on success, false on arena exhaustion
// — so callers translate to whatever error code their function returns:
//   if (!da_init_arena(xs, 4, a))  return RESULT_MEMORY_ERROR;
//   if (!da_push_arena(xs, x, a))  return NULL;
#define da_init_arena(xs, cap, arena_ptr)                                                                                                                                                                                                      \
	({                                                                                                                                                                                                                                         \
		(xs).count = 0;                                                                                                                                                                                                                        \
		(xs).capacity = (cap);                                                                                                                                                                                                                 \
		(xs).data = (xs).capacity ? arena_alloc((arena_ptr), (size_t)(xs).capacity * sizeof(*(xs).data)) : NULL;                                                                                                                               \
		(xs).capacity == 0 || (xs).data != NULL;                                                                                                                                                                                               \
	})

#define da_push_arena(xs, x, arena_ptr)                                                                                                                                                                                                        \
	({                                                                                                                                                                                                                                         \
		bool _da_ok = true;                                                                                                                                                                                                                    \
		if ((xs).count >= (xs).capacity) {                                                                                                                                                                                                     \
			size_t _da_old_bytes = (size_t)(xs).capacity * sizeof(*(xs).data);                                                                                                                                                                 \
			int _da_new_cap = (xs).capacity ? (xs).capacity * 2 : 4;                                                                                                                                                                           \
			void *_da_new_data = arena_realloc_grow((arena_ptr), (xs).data, _da_old_bytes, (size_t)_da_new_cap * sizeof(*(xs).data));                                                                                                          \
			if (!_da_new_data) {                                                                                                                                                                                                               \
				_da_ok = false;                                                                                                                                                                                                                \
			} else {                                                                                                                                                                                                                           \
				(xs).capacity = _da_new_cap;                                                                                                                                                                                                   \
				(xs).data = _da_new_data;                                                                                                                                                                                                      \
			}                                                                                                                                                                                                                                  \
		}                                                                                                                                                                                                                                      \
		if (_da_ok)                                                                                                                                                                                                                            \
			(xs).data[(xs).count++] = (x);                                                                                                                                                                                                     \
	    _da_ok;                                                                                                                                                                                                                                \
	})
