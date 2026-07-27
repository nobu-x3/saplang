import arena;
import list;
import sys;

struct TestCase {
    u8[]      suite;
    u8[]      name;
    fn* i32(arena::Arena*, u8[]) body;
}

struct Runner {
    arena::Arena        arena;
    list::List(TestCase) cases;
}

Runner runner;

// state
export fn void init() {
    runner.arena = {0, null};
    runner.cases = {null, 0, 0};
}

export fn void add(u8[] suite, u8[] name, fn* i32(arena::Arena*, u8[]) body) {
    TestCase c;
    c.suite = suite;
    c.name = name;
    c.body = body;
    list::push(&runner.cases, &runner.arena, c);
}

// returns 0 on all-pass
export fn i32 run() {
    u64 failed_count = 0;
    u64 passed_count = 0;
    for(u64 i = 0; i < runner.cases.len; i += 1) {
        const TestCase* test_case = &runner.cases.ptr[i];
        if(!test_case) {
            sys::printf("Something went wrong with arena allocator in test setups. Case %d is null.\n", i);
            return -1;
        }
        if(!test_case.body) {
            sys::printf("Test case %d's body is null.\n", i);
            return -1;
        }
        u8[] msg = {null, 0};
        sys::printf("[__RUN_______] %.*s:%.*s\n", (i32)test_case.suite.len, test_case.suite.ptr, (i32)test_case.name.len, test_case.name.ptr);
        i32 res = test_case.body(&runner.arena, msg);
        if(res != 0) {
            failed_count += 1;
            sys::printf("[___FAILED___] %.*s:%.*s: %s\n", (i32)test_case.suite.len, test_case.suite.ptr, (i32)test_case.name.len, test_case.name.ptr, msg.ptr);
        } else {
            passed_count += 1;
            sys::printf("[___PASSED___] %.*s:%.*s\n", (i32)test_case.suite.len, test_case.suite.ptr, (i32)test_case.name.len, test_case.name.ptr);
        }
    }
    sys::printf("[============] Total: %d, Passed: %d, Failed: %d\n", runner.cases.len, passed_count, failed_count);
    return (i32)failed_count;
}

// expectations — overloaded per primitive type, all return bool (true = passed).
// On failure they print a one-line diagnostic; the bool lets the caller
// early-return via `if (!expect_*(...)) return -1;`.

// expect_eq
export fn bool expect_eq(i32 actual, i32 expected, u8[] msg) {
    if(actual == expected) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %d, got %d\n", (i32)msg.len, msg.ptr, expected, actual);
    return false;
}
export fn bool expect_eq(i64 actual, i64 expected, u8[] msg) {
    if(actual == expected) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %ld, got %ld\n", (i32)msg.len, msg.ptr, expected, actual);
    return false;
}
export fn bool expect_eq(u16 actual, u16 expected, u8[] msg) {
    if(actual == expected) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %u, got %u\n", (i32)msg.len, msg.ptr, (u32)expected, (u32)actual);
    return false;
}
export fn bool expect_eq(u32 actual, u32 expected, u8[] msg) {
    if(actual == expected) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %u, got %u\n", (i32)msg.len, msg.ptr, expected, actual);
    return false;
}
export fn bool expect_eq(u64 actual, u64 expected, u8[] msg) {
    if(actual == expected) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %lu, got %lu\n", (i32)msg.len, msg.ptr, expected, actual);
    return false;
}
export fn bool expect_eq(f64 actual, f64 expected, u8[] msg) {
    if(actual == expected) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %g, got %g\n", (i32)msg.len, msg.ptr, expected, actual);
    return false;
}
export fn bool expect_eq(bool actual, bool expected, u8[] msg) {
    if(actual == expected) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %d, got %d\n", (i32)msg.len, msg.ptr, (i32)expected, (i32)actual);
    return false;
}
export fn bool expect_eq(u8[] actual, u8[] expected, u8[] msg) {
    if(equal(actual, expected)) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected \"%.*s\", got \"%.*s\"\n", (i32)msg.len, msg.ptr, (i32)expected.len, expected.ptr, (i32)actual.len, actual.ptr);
    return false;
}
export fn bool expect_eq(void* actual, void* expected, u8[] msg) {
    if(actual == expected) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %p, got %p\n", (i32)msg.len, msg.ptr, expected, actual);
    return false;
}

// expect_ne
export fn bool expect_ne(i32 actual, i32 expected, u8[] msg) {
    if(actual != expected) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected != %d, got %d\n", (i32)msg.len, msg.ptr, expected, actual);
    return false;
}
export fn bool expect_ne(i64 actual, i64 expected, u8[] msg) {
    if(actual != expected) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected != %ld, got %ld\n", (i32)msg.len, msg.ptr, expected, actual);
    return false;
}
export fn bool expect_ne(u32 actual, u32 expected, u8[] msg) {
    if(actual != expected) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected != %u, got %u\n", (i32)msg.len, msg.ptr, expected, actual);
    return false;
}
export fn bool expect_ne(u64 actual, u64 expected, u8[] msg) {
    if(actual != expected) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected != %lu, got %lu\n", (i32)msg.len, msg.ptr, expected, actual);
    return false;
}
export fn bool expect_ne(f64 actual, f64 expected, u8[] msg) {
    if(actual != expected) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected != %g, got %g\n", (i32)msg.len, msg.ptr, expected, actual);
    return false;
}
export fn bool expect_ne(bool actual, bool expected, u8[] msg) {
    if(actual != expected) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected != %d, got %d\n", (i32)msg.len, msg.ptr, (i32)expected, (i32)actual);
    return false;
}
export fn bool expect_ne(u8[] actual, u8[] expected, u8[] msg) {
    if(!equal(actual, expected)) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected != \"%.*s\"\n", (i32)msg.len, msg.ptr, (i32)expected.len, expected.ptr);
    return false;
}
export fn bool expect_ne(void* actual, void* expected, u8[] msg) {
    if(actual != expected) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected != %p, got %p\n", (i32)msg.len, msg.ptr, expected, actual);
    return false;
}

// expect_lt
export fn bool expect_lt(i32 a, i32 b, u8[] msg) {
    if(a < b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %d < %d\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}
export fn bool expect_lt(i64 a, i64 b, u8[] msg) {
    if(a < b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %ld < %ld\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}
export fn bool expect_lt(u32 a, u32 b, u8[] msg) {
    if(a < b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %u < %u\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}
export fn bool expect_lt(u64 a, u64 b, u8[] msg) {
    if(a < b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %lu < %lu\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}
export fn bool expect_lt(f64 a, f64 b, u8[] msg) {
    if(a < b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %g < %g\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}

// expect_le
export fn bool expect_le(i32 a, i32 b, u8[] msg) {
    if(a <= b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %d <= %d\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}
export fn bool expect_le(i64 a, i64 b, u8[] msg) {
    if(a <= b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %ld <= %ld\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}
export fn bool expect_le(u32 a, u32 b, u8[] msg) {
    if(a <= b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %u <= %u\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}
export fn bool expect_le(u64 a, u64 b, u8[] msg) {
    if(a <= b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %lu <= %lu\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}
export fn bool expect_le(f64 a, f64 b, u8[] msg) {
    if(a <= b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %g <= %g\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}

// expect_gt
export fn bool expect_gt(i32 a, i32 b, u8[] msg) {
    if(a > b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %d > %d\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}
export fn bool expect_gt(i64 a, i64 b, u8[] msg) {
    if(a > b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %ld > %ld\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}
export fn bool expect_gt(u32 a, u32 b, u8[] msg) {
    if(a > b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %u > %u\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}
export fn bool expect_gt(u64 a, u64 b, u8[] msg) {
    if(a > b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %lu > %lu\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}
export fn bool expect_gt(f64 a, f64 b, u8[] msg) {
    if(a > b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %g > %g\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}

// expect_ge
export fn bool expect_ge(i32 a, i32 b, u8[] msg) {
    if(a >= b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %d >= %d\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}
export fn bool expect_ge(i64 a, i64 b, u8[] msg) {
    if(a >= b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %ld >= %ld\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}
export fn bool expect_ge(u32 a, u32 b, u8[] msg) {
    if(a >= b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %u >= %u\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}
export fn bool expect_ge(u64 a, u64 b, u8[] msg) {
    if(a >= b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %lu >= %lu\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}
export fn bool expect_ge(f64 a, f64 b, u8[] msg) {
    if(a >= b) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected %g >= %g\n", (i32)msg.len, msg.ptr, a, b);
    return false;
}

export fn bool expect_near(f64 actual, f64 expected, f64 tol, u8[] msg) {
    f64 d = f_abs(actual - expected);
    if(d <= tol) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: |%g - %g| = %g > tol %g\n", (i32)msg.len, msg.ptr, actual, expected, d, tol);
    return false;
}

export fn bool expect_true(bool cond, u8[] msg) {
    if(cond) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected true\n", (i32)msg.len, msg.ptr);
    return false;
}

export fn bool expect_false(bool cond, u8[] msg) {
    if(!cond) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected false\n", (i32)msg.len, msg.ptr);
    return false;
}

export fn bool expect_null(void* p, u8[] msg) {
    if(!p) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected null, got %p\n", (i32)msg.len, msg.ptr, p);
    return false;
}

export fn bool expect_not_null(void* p, u8[] msg) {
    if(p) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: expected non-null\n", (i32)msg.len, msg.ptr);
    return false;
}

export fn bool expect_substr(u8[] haystack, u8[] needle, u8[] msg) {
    if(find(haystack, needle)) {
        return true;
    }
    sys::printf("[____FAIL____] %.*s: \"%.*s\" not found in \"%.*s\"\n", (i32)msg.len, msg.ptr, (i32)needle.len, needle.ptr, (i32)haystack.len, haystack.ptr);
    return false;
}

fn bool equal(u8[] a, u8[] b) {
    if(a.len != b.len) {
        return false;
    }
    for(u64 i = 0; i < a.len; i += 1) {
        if(a.ptr[i] != b.ptr[i]) {
            return false;
        }
    }
    return true;
}

fn bool find(u8[] hay, u8[] needle) {
    if(needle.len == 0) {
        return true;
    }
    if(needle.len > hay.len) {
        return false;
    }
    u64 limit = hay.len - needle.len + 1;
    for(u64 i = 0; i < limit; i += 1) {
        bool ok = true;
        for(u64 j = 0; j < needle.len; j += 1) {
            if(hay.ptr[i + j] != needle.ptr[j]) {
                ok = false;
                break;
            }
        }
        if(ok) {
            return true;
        }
    }
    return false;
}

fn f64 f_abs(f64 v) {
    if(v < 0.0) {
        return -v;
    }
    return v;
}
