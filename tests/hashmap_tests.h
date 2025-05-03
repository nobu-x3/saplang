#pragma once

#include "unity.h"
#include <hashmap.h>
#include <stdlib.h>
#include <string.h>

static void destroy_str(void *s) {
    free(s);
}

// Test: creation, initial state
void test_hashmap_create_and_destroy(void) {
    hashmap_t *map = hashmap_create(4, NULL, NULL);
    TEST_ASSERT_NOT_NULL_MESSAGE(map, "Map should be created");
    TEST_ASSERT_EQUAL(0, hashmap_size(map));
    hashmap_destroy(map, NULL, NULL);
}

// Test: put & get basic functionality
void test_hashmap_put_and_get(void) {
    hashmap_t *map = hashmap_create(4, NULL, NULL);
    char *k1 = strdup("one");
    TEST_ASSERT_TRUE(hashmap_put(map, k1, (void *)"1"));
    TEST_ASSERT_EQUAL_STRING("1", hashmap_get(map, "one"));
    hashmap_destroy(map, destroy_str, NULL);
}

// Test: updating an existing key
void test_hashmap_update_existing_key(void) {
    hashmap_t *map = hashmap_create(2, NULL, NULL);
    hashmap_put(map, strdup("dup"), (void *)"first");
    TEST_ASSERT_FALSE(hashmap_put(map, strdup("dup"), (void *)"second"));
    TEST_ASSERT_EQUAL_STRING("second", hashmap_get(map, "dup"));
    hashmap_destroy(map, destroy_str, NULL);
}

// Test: contains / remove
void test_hashmap_remove_and_contains(void) {
    hashmap_t *map = hashmap_create(2, NULL, NULL);
    hashmap_put(map, strdup("a"), (void *)"A");
    TEST_ASSERT_TRUE(hashmap_contains(map, "a"));
    void *out_key, *out_val;
    TEST_ASSERT_TRUE(hashmap_remove(map, "a", &out_key, &out_val));
    TEST_ASSERT_EQUAL_STRING("a", (char*)out_key);
    TEST_ASSERT_EQUAL_STRING("A", (char*)out_val);
    free(out_key);
    TEST_ASSERT_FALSE(hashmap_contains(map, "a"));
    hashmap_destroy(map, NULL, NULL);
}

// Test: removal of non‐existent key
void test_hashmap_remove_missing_key(void) {
    hashmap_t *map = hashmap_create(2, NULL, NULL);
    TEST_ASSERT_FALSE(hashmap_remove(map, "nope", NULL, NULL));
    hashmap_destroy(map, NULL, NULL);
}

// Test: rehash on load‐factor threshold
void test_hashmap_rehash(void) {
    // With initial capacity 2 and load factor 0.75, inserting 2 keys triggers resize
    hashmap_t *map = hashmap_create(2, NULL, NULL);
    for (int i = 0; i < 3; ++i) {
        char *key = malloc(16);
        sprintf(key, "k%d", i);
        TEST_ASSERT_TRUE(hashmap_put(map, key, (void*)(long)i));
    }
    // Verify all values survive rehash
    for (int i = 0; i < 3; ++i) {
        char key[16];
        sprintf(key, "k%d", i);
        TEST_ASSERT_EQUAL_INT(i, (int)(long)hashmap_get(map, key));
    }
    hashmap_destroy(map, destroy_str, NULL);
}
