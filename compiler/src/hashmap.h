#pragma once
#include <string.h>

// Opaque hashmap type
typedef struct hashmap hashmap_t;

size_t fnv1a_hash(const void *key);

//////////// Comparison Functions ////////////////////

// Default string
int string_equals(const void *a, const void *b);

// Pointer comparison
int ptr_equals(const void *a, const void *b);

//////////////////////////////////////////////////////

// Function pointer types for hashing and key comparison
typedef size_t (*hash_func)(const void *key);
typedef int   (*equals_func)(const void *a, const void *b);

// Create a new hashmap.
//   init_capacity: initial number of buckets (will be rounded up to a power of two)
//   hf:             hash function for keys
//   eq:             equality function for keys
hashmap_t *hashmap_create(size_t init_capacity,
                          hash_func hf,
                          equals_func eq);

// Destroy the hashmap, freeing all memory.
//   destroy_key:   optional; if non-NULL, called on each stored key before freeing.
//   destroy_val:   optional; if non-NULL, called on each stored value before freeing.
void hashmap_destroy(hashmap_t *map,
                     void (*destroy_key)(void *),
                     void (*destroy_val)(void *));

// Insert or update a key/value pair.
// Returns true if a new entry was inserted; false if an existing entry was updated.
//   key, val: user‐owned pointers.
// Note: the map takes ownership of key and val pointers.
int hashmap_put(hashmap_t *map, void *key, void *val);

// Retrieve the value for a given key, or NULL if not found.
// (If NULL values are valid in your use case, use hashmap_contains first.)
void *hashmap_get(const hashmap_t *map, const void *key);

// Remove a key/value pair.
// Returns true if the key was found and removed; false otherwise.
//   out_key, out_val: if non-NULL, are set to the removed pointers.
int hashmap_remove(hashmap_t *map, const void *key,
                    void **out_key, void **out_val);

// Check if a key is present.
int hashmap_contains(const hashmap_t *map, const void *key);

// Number of entries currently stored.
size_t hashmap_size(const hashmap_t *map);
