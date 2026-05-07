#include "arena.h"
#include <stdlib.h>
#include <string.h>

#define ARENA_ALIGN 8
#define ARENA_DEFAULT_PAGE_SIZE (64u * 1024u)

static size_t round_up(size_t v, size_t a) {
	return (v + a - 1) & ~(a - 1);
}

static ArenaPage *new_page(size_t cap) {
	ArenaPage *p = malloc(sizeof(ArenaPage) + cap);
	if (!p)
		return NULL;
	p->next = NULL;
	p->cap = cap;
	p->used = 0;
	return p;
}

void arena_init(Arena *arena, size_t default_page_size) {
	arena->head = NULL;
	arena->default_page_size = default_page_size ? default_page_size : ARENA_DEFAULT_PAGE_SIZE;
}

void arena_deinit(Arena *arena) {
	ArenaPage *p = arena->head;
	while (p) {
		ArenaPage *next = p->next;
		free(p);
		p = next;
	}
	arena->head = NULL;
}

void *arena_alloc(Arena *arena, size_t size) {
	if (size == 0)
		return NULL;
	size = round_up(size, ARENA_ALIGN);

	if (arena->head && arena->head->used + size <= arena->head->cap) {
		char *ptr = arena->head->data + arena->head->used;
		arena->head->used += size;
		return ptr;
	}

	size_t page_cap = size > arena->default_page_size ? size : arena->default_page_size;
	ArenaPage *p = new_page(page_cap);
	if (!p)
		return NULL;
	p->next = arena->head;
	arena->head = p;
	p->used = size;
	return p->data;
}

void *arena_realloc_grow(Arena *arena, void *old, size_t old_size, size_t new_size) {
	void *fresh = arena_alloc(arena, new_size);
	if (!fresh)
		return NULL;
	if (old_size > 0 && old)
		memcpy(fresh, old, old_size);
	return fresh;
}
