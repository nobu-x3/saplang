#include "hashmap.h"

#include <stdlib.h>
#include <stdint.h>

#define INITIAL_LOAD_FACTOR 0.75

// Entry in a bucket's linked list
typedef struct entry {
    void             *key;
    void             *val;
    struct entry     *next;
} entry_t;

// Hashmap structure
struct hashmap {
    entry_t    **buckets;      // array of bucket heads
    size_t       capacity;     // number of buckets (always power of two)
    size_t       size;         // number of key/value pairs
    hash_func    hf;           // user-supplied hash function
    equals_func  eq;           // user-supplied equality function
};

// FNV-1a 64-bit hash for byte sequences (useful for strings)
size_t fnv1a_hash(const void *key) {
    const unsigned char *data = (const unsigned char *)key;
    size_t hash = 14695981039346656037ULL;
    while (*data) {
        hash ^= (size_t)(*data++);
        hash *= 1099511628211ULL;
    }
    return hash;
}

int string_equals(const void *a, const void *b) {
    return strcmp((const char *)a, (const char *)b) == 0;
}

int ptr_equals(const void *a, const void *b) {
    return a == b;
}

// Round up to next power of two
static size_t round_up_pow2(size_t x) {
    if (x == 0) return 1;
    --x;
    for (size_t shift = 1; shift < sizeof(size_t)*8; shift <<= 1)
        x |= x >> shift;
    return x + 1;
}

// Create hashmap
hashmap_t *hashmap_create(size_t init_capacity,
                          hash_func hf,
                          equals_func eq) {
    hashmap_t *map = malloc(sizeof(hashmap_t));
    map->capacity = round_up_pow2(init_capacity);
    map->size     = 0;
    map->buckets  = calloc(map->capacity, sizeof(entry_t *));
    map->hf       = hf ? hf : fnv1a_hash;
    map->eq       = eq ? eq : string_equals;
    return map;
}

// Free one bucket chain
static void free_bucket(entry_t *e,
                        void (*destroy_key)(void *),
                        void (*destroy_val)(void *)) {
    while (e) {
        entry_t *next = e->next;
        if (destroy_key) destroy_key(e->key);
        if (destroy_val) destroy_val(e->val);
        free(e);
        e = next;
    }
}

// Destroy hashmap
void hashmap_destroy(hashmap_t *map,
                     void (*destroy_key)(void *),
                     void (*destroy_val)(void *)) {
    for (size_t i = 0; i < map->capacity; i++) {
        free_bucket(map->buckets[i], destroy_key, destroy_val);
    }
    free(map->buckets);
    free(map);
}

// Internal: rehash to new capacity
static void rehash(hashmap_t *map, size_t new_capacity) {
    new_capacity = round_up_pow2(new_capacity);
    entry_t **new_buckets = calloc(new_capacity, sizeof(entry_t *));
    // move entries
    for (size_t i = 0; i < map->capacity; i++) {
        entry_t *e = map->buckets[i];
        while (e) {
            entry_t *next = e->next;
            size_t idx = map->hf(e->key) & (new_capacity - 1);
            e->next = new_buckets[idx];
            new_buckets[idx] = e;
            e = next;
        }
    }
    free(map->buckets);
    map->buckets  = new_buckets;
    map->capacity = new_capacity;
}

// Insert or update
int hashmap_put(hashmap_t *map, void *key, void *val) {
    if ((double)(map->size + 1) / map->capacity > INITIAL_LOAD_FACTOR) {
        rehash(map, map->capacity * 2);
    }
    size_t idx = map->hf(key) & (map->capacity - 1);
    entry_t **pp = &map->buckets[idx];
    // search for existing
    while (*pp) {
        if (map->eq((*pp)->key, key)) {
            // update
            (*pp)->val = val;
            // optionally free old key? here we drop the new key pointer
            return 0;
        }
        pp = &(*pp)->next;
    }
    // insert new
    entry_t *e = malloc(sizeof(entry_t));
    e->key   = key;
    e->val   = val;
    e->next  = map->buckets[idx];
    map->buckets[idx] = e;
    map->size++;
    return 1;
}

// Retrieve
void *hashmap_get(const hashmap_t *map, const void *key) {
    size_t idx = map->hf(key) & (map->capacity - 1);
    entry_t *e = map->buckets[idx];
    while (e) {
        if (map->eq(e->key, key))
            return e->val;
        e = e->next;
    }
    return NULL;
}

// Check existence
int hashmap_contains(const hashmap_t *map, const void *key) {
    return hashmap_get(map, key) != NULL;
}

// Remove
int hashmap_remove(hashmap_t *map, const void *key,
                    void **out_key, void **out_val) {
    size_t idx = map->hf(key) & (map->capacity - 1);
    entry_t **pp = &map->buckets[idx];
    while (*pp) {
        if (map->eq((*pp)->key, key)) {
            entry_t *victim = *pp;
            *pp = victim->next;
            if (out_key) *out_key = victim->key;
            if (out_val) *out_val = victim->val;
            free(victim);
            map->size--;
            return 1;
        }
        pp = &(*pp)->next;
    }
    return 0;
}

// Size
size_t hashmap_size(const hashmap_t *map) {
    return map->size;
}
