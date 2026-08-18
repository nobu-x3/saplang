import testing;
import algo;
import list;
import arena;

alias Str = const u8[];

struct Point { i32 x; i32 y; }
struct Wide { i64 a; i64 b; i64 c; i64 d; f64 e; }

fn bool less_i32(i32 a, i32 b) { return a < b; }
fn bool greater_i32(i32 a, i32 b) { return b < a; }
fn bool less_u64(u64 a, u64 b) { return a < b; }
fn bool less_f64(f64 a, f64 b) { return a < b; }
fn bool less_u8(u8 a, u8 b) { return a < b; }
fn bool less_point(Point a, Point b) { return a.x < b.x; }
fn bool less_wide(Wide a, Wide b) { return a.a < b.a; }
fn bool less_pointee(i32* a, i32* b) { return *a < *b; }

fn bool less_str(Str a, Str b) {
    u64 shared = a.len;
    if(b.len < shared) { shared = b.len; }
    for(u64 i = 0; i < shared; i += 1) {
        if(a[i] != b[i]) { return a[i] < b[i]; }
    }
    return a.len < b.len;
}

u64 compare_count = 0;
fn bool counting_less(i32 a, i32 b) { compare_count += 1; return a < b; }

fn bool is_sorted(i32[] xs) {
    for(u64 i = 1; i < xs.len; i += 1) {
        if(xs[i] < xs[i - 1]) { return false; }
    }
    return true;
}

// A sort that drops or duplicates an element can still leave the result sorted, so order is never checked alone.
fn bool same_multiset(i32[] a, i32[] b) {
    if(a.len != b.len) { return false; }
    for(u64 i = 0; i < a.len; i += 1) {
        u64 in_a = 0;
        u64 in_b = 0;
        for(u64 j = 0; j < a.len; j += 1) {
            if(a[j] == a[i]) { in_a += 1; }
            if(b[j] == a[i]) { in_b += 1; }
        }
        if(in_a != in_b) { return false; }
    }
    return true;
}

fn i32 swap_scalars(arena::Arena* a, const u8[]m) {
    i32 x = 3;
    i32 y = 9;
    algo::swap(&x, &y);
    if(!testing::expect_eq(x, 9, m)) { return -1; }
    if(!testing::expect_eq(y, 3, m)) { return -2; }
    return 0;
}

// Aliased operands: the temporary has to survive the first store or the value is lost.
fn i32 swap_aliased(arena::Arena* a, const u8[]m) {
    i32 x = 42;
    algo::swap(&x, &x);
    if(!testing::expect_eq(x, 42, m)) { return -1; }
    return 0;
}

fn i32 swap_struct_elem(arena::Arena* a, const u8[]m) {
    Point p = {1, 2};
    Point q = {3, 4};
    algo::swap(&p, &q);
    if(!testing::expect_eq(p.x, 3, m)) { return -1; }
    if(!testing::expect_eq(p.y, 4, m)) { return -2; }
    if(!testing::expect_eq(q.x, 1, m)) { return -3; }
    if(!testing::expect_eq(q.y, 2, m)) { return -4; }
    return 0;
}

fn i32 swap_pointer_elem(arena::Arena* a, const u8[]m) {
    i32 v0 = 7;
    i32 v1 = 8;
    i32* p = &v0;
    i32* q = &v1;
    algo::swap(&p, &q);
    if(!testing::expect_eq(*p, 8, m)) { return -1; }
    if(!testing::expect_eq(*q, 7, m)) { return -2; }
    return 0;
}

// Slice elements move both halves of the {ptr, len} pair.
fn i32 swap_slice_elem(arena::Arena* a, const u8[]m) {
    i32[4] buf;
    buf[0] = 1; buf[1] = 2; buf[2] = 3; buf[3] = 4;
    i32[] head = buf[0..1];
    i32[] tail = buf[1..4];
    algo::swap(&head, &tail);
    if(!testing::expect_eq(head.len, (u64)3, m)) { return -1; }
    if(!testing::expect_eq(tail.len, (u64)1, m)) { return -2; }
    if(!testing::expect_eq(head[0], 2, m)) { return -3; }
    if(!testing::expect_eq(tail[0], 1, m)) { return -4; }
    return 0;
}

fn i32 double_it(i32 x) { return x * 2; }
fn i32 negate_it(i32 x) { return 0 - x; }

fn i32 swap_fn_ptr_elem(arena::Arena* a, const u8[]m) {
    fn* i32(i32) f = &double_it;
    fn* i32(i32) g = &negate_it;
    algo::swap(&f, &g);
    if(!testing::expect_eq(f(5), -5, m)) { return -1; }
    if(!testing::expect_eq(g(5), 10, m)) { return -2; }
    return 0;
}

// A T wider than a register pair moves by copy; the halves must not shear apart.
fn i32 swap_wide_struct_elem(arena::Arena* a, const u8[]m) {
    Wide p = {1, 2, 3, 4, 5.5};
    Wide q = {10, 20, 30, 40, 50.5};
    algo::swap(&p, &q);
    if(!testing::expect_eq(p.a, (i64)10, m)) { return -1; }
    if(!testing::expect_eq(p.d, (i64)40, m)) { return -2; }
    if(!testing::expect_eq(p.e, 50.5, m)) { return -3; }
    if(!testing::expect_eq(q.a, (i64)1, m)) { return -4; }
    if(!testing::expect_eq(q.d, (i64)4, m)) { return -5; }
    if(!testing::expect_eq(q.e, 5.5, m)) { return -6; }
    return 0;
}

fn i32 swap_float_and_bool(arena::Arena* a, const u8[]m) {
    f64 lo = 1.5;
    f64 hi = 2.5;
    algo::swap(&lo, &hi);
    if(!testing::expect_eq(lo, 2.5, m)) { return -1; }
    if(!testing::expect_eq(hi, 1.5, m)) { return -2; }
    bool t = true;
    bool f = false;
    algo::swap(&t, &f);
    if(!testing::expect_eq(t, false, m)) { return -3; }
    if(!testing::expect_eq(f, true, m)) { return -4; }
    return 0;
}

// Zero and one element never reach the partition, which would read data[len - 1] and wrap.
fn i32 sort_empty_and_single(arena::Arena* a, const u8[]m) {
    i32[] nothing = {null, 0};
    algo::sort(nothing, &less_i32);
    if(!testing::expect_eq(nothing.len, (u64)0, m)) { return -1; }
    i32[1] one;
    one[0] = 5;
    i32[] single = one[0..1];
    algo::sort(single, &less_i32);
    if(!testing::expect_eq(single[0], 5, m)) { return -2; }
    return 0;
}

// A non-null slice of length zero reaches sort by a different route than the {null, 0} one.
fn i32 sort_empty_subslice(arena::Arena* a, const u8[]m) {
    i32[4] buf;
    buf[0] = 4; buf[1] = 3; buf[2] = 2; buf[3] = 1;
    algo::sort(buf[2..2], &less_i32);
    if(!testing::expect_eq(buf[0], 4, m)) { return -1; }
    if(!testing::expect_eq(buf[1], 3, m)) { return -2; }
    if(!testing::expect_eq(buf[2], 2, m)) { return -3; }
    if(!testing::expect_eq(buf[3], 1, m)) { return -4; }
    return 0;
}

// Length two is where a partition that returns the whole range recurses forever.
fn i32 sort_pairs(arena::Arena* a, const u8[]m) {
    i32[2] buf;
    buf[0] = 1; buf[1] = 2;
    algo::sort(buf[0..2], &less_i32);
    if(!testing::expect_eq(buf[0], 1, m)) { return -1; }
    if(!testing::expect_eq(buf[1], 2, m)) { return -2; }
    buf[0] = 2; buf[1] = 1;
    algo::sort(buf[0..2], &less_i32);
    if(!testing::expect_eq(buf[0], 1, m)) { return -3; }
    if(!testing::expect_eq(buf[1], 2, m)) { return -4; }
    buf[0] = 7; buf[1] = 7;
    algo::sort(buf[0..2], &less_i32);
    if(!testing::expect_eq(buf[0], 7, m)) { return -5; }
    if(!testing::expect_eq(buf[1], 7, m)) { return -6; }
    return 0;
}

// Every array of length `len` over values [0, radix): all permutations and all duplicate patterns.
fn i32 exhaustive_over(u64 len, u64 radix, const u8[]m) {
    i32[6] original_buf;
    i32[6] work_buf;
    u64 total = 1;
    for(u64 p = 0; p < len; p += 1) { total = total * radix; }
    for(u64 code = 0; code < total; code += 1) {
        u64 rest = code;
        for(u64 i = 0; i < len; i += 1) {
            original_buf[i] = (i32)(rest % radix);
            work_buf[i] = original_buf[i];
            rest = rest / radix;
        }
        i32[] original = original_buf[0..len];
        i32[] work = work_buf[0..len];
        algo::sort(work, &less_i32);
        if(!testing::expect_true(is_sorted(work), m)) { return -1; }
        if(!testing::expect_true(same_multiset(original, work), m)) { return -2; }
    }
    return 0;
}

fn i32 sort_all_arrays_up_to_three(arena::Arena* a, const u8[]m) {
    for(u64 len = 1; len <= 3; len += 1) {
        if(exhaustive_over(len, 3, m) != 0) { return -1; }
    }
    return 0;
}

fn i32 sort_all_arrays_of_four(arena::Arena* a, const u8[]m) {
    return exhaustive_over(4, 4, m);
}

fn i32 sort_all_arrays_of_five(arena::Arena* a, const u8[]m) {
    return exhaustive_over(5, 5, m);
}

// Two-valued input drives the scans into each other repeatedly; six slots covers every crossing.
fn i32 sort_all_binary_arrays_of_six(arena::Arena* a, const u8[]m) {
    return exhaustive_over(6, 2, m);
}

const u64 PATTERN_LEN = 1000;
const u64 HISTOGRAM_SIZE = 1024;

// Comparing sums would accept a 1 and a 3 in place of two 2s, so every value is counted separately.
fn i32 check_pattern(i32[] work, i32[] original, const u8[]m) {
    algo::sort(work, &less_i32);
    if(!testing::expect_true(is_sorted(work), m)) { return -1; }
    i64[1024] histogram;
    for(u64 v = 0; v < HISTOGRAM_SIZE; v += 1) { histogram[v] = 0; }
    for(u64 i = 0; i < work.len; i += 1) {
        histogram[(u64)original[i]] = histogram[(u64)original[i]] + 1;
        histogram[(u64)work[i]] = histogram[(u64)work[i]] - 1;
    }
    bool balanced = true;
    for(u64 v = 0; v < HISTOGRAM_SIZE; v += 1) {
        if(histogram[v] != 0) { balanced = false; }
    }
    if(!testing::expect_true(balanced, m)) { return -2; }
    return 0;
}

fn i32 sort_structured_patterns(arena::Arena* a, const u8[]m) {
    i32[1000] original;
    i32[1000] work;
    for(u64 shape = 0; shape < 8; shape += 1) {
        u64 seed = 12345;
        for(u64 i = 0; i < PATTERN_LEN; i += 1) {
            i32 v = 0;
            if(shape == 0) { v = (i32)i; }
            if(shape == 1) { v = (i32)(PATTERN_LEN - i); }
            if(shape == 2) { v = 4; }
            if(shape == 3) { v = (i32)(i % 2); }
            if(shape == 4) { v = (i32)(i % 7); }
            if(shape == 5) {
                v = (i32)i;
                if(i >= PATTERN_LEN / 2) { v = (i32)(PATTERN_LEN - i); }
            }
            if(shape == 6) { v = (i32)(i % 32); }
            if(shape == 7) {
                seed = seed * 1103515245 + 12345;
                v = (i32)((seed >> 16) % 1000);
            }
            original[i] = v;
            work[i] = v;
        }
        if(check_pattern(work[0..PATTERN_LEN], original[0..PATTERN_LEN], m) != 0) { return -1; }
    }
    return 0;
}

// All-equal input stops both scans on every element; bounding the comparisons pins the split, not just order.
fn i32 sort_all_equal_is_not_quadratic(arena::Arena* a, const u8[]m) {
    i32[4096] buf;
    for(u64 i = 0; i < 4096; i += 1) { buf[i] = 3; }
    compare_count = 0;
    algo::sort(buf[0..4096], &counting_less);
    if(!testing::expect_true(is_sorted(buf[0..4096]), m)) { return -1; }
    if(!testing::expect_lt(compare_count, (u64)4096 * 40, m)) { return -2; }
    return 0;
}

fn i32 sort_sorted_input_is_not_quadratic(arena::Arena* a, const u8[]m) {
    i32[4096] buf;
    for(u64 i = 0; i < 4096; i += 1) { buf[i] = (i32)i; }
    compare_count = 0;
    algo::sort(buf[0..4096], &counting_less);
    if(!testing::expect_true(is_sorted(buf[0..4096]), m)) { return -1; }
    if(!testing::expect_lt(compare_count, (u64)4096 * 40, m)) { return -2; }
    return 0;
}

fn i32 sort_large_all_equal_terminates(arena::Arena* a, const u8[]m) {
    i32[20000] buf;
    for(u64 i = 0; i < 20000; i += 1) { buf[i] = 1; }
    algo::sort(buf[0..20000], &less_i32);
    if(!testing::expect_true(is_sorted(buf[0..20000]), m)) { return -1; }
    if(!testing::expect_eq(buf[19999], 1, m)) { return -2; }
    return 0;
}

fn i32 sort_u64_elements(arena::Arena* a, const u8[]m) {
    u64[5] buf;
    buf[0] = 30; buf[1] = 10; buf[2] = 50; buf[3] = 20; buf[4] = 40;
    algo::sort(buf[0..5], &less_u64);
    if(!testing::expect_eq(buf[0], (u64)10, m)) { return -1; }
    if(!testing::expect_eq(buf[4], (u64)50, m)) { return -2; }
    return 0;
}

fn i32 sort_f64_elements(arena::Arena* a, const u8[]m) {
    f64[5] buf;
    buf[0] = 2.5; buf[1] = -1.5; buf[2] = 0.0; buf[3] = 9.25; buf[4] = -0.5;
    algo::sort(buf[0..5], &less_f64);
    if(!testing::expect_eq(buf[0], -1.5, m)) { return -1; }
    if(!testing::expect_eq(buf[1], -0.5, m)) { return -2; }
    if(!testing::expect_eq(buf[4], 9.25, m)) { return -3; }
    return 0;
}

fn i32 sort_u8_elements(arena::Arena* a, const u8[]m) {
    u8[6] buf;
    buf[0] = 'f'; buf[1] = 'a'; buf[2] = 'd'; buf[3] = 'c'; buf[4] = 'b'; buf[5] = 'e';
    algo::sort(buf[0..6], &less_u8);
    if(!testing::expect_eq(buf[0..6], "abcdef", m)) { return -1; }
    return 0;
}

// Ordering on one field: the payload field has to ride along with the key it was paired with.
fn i32 sort_struct_by_field(arena::Arena* a, const u8[]m) {
    Point[5] buf;
    buf[0] = {5, 50}; buf[1] = {1, 10}; buf[2] = {4, 40}; buf[3] = {2, 20}; buf[4] = {3, 30};
    algo::sort(buf[0..5], &less_point);
    for(u64 i = 0; i < 5; i += 1) {
        if(!testing::expect_eq(buf[i].x, (i32)i + 1, m)) { return -1; }
        if(!testing::expect_eq(buf[i].y, ((i32)i + 1) * 10, m)) { return -2; }
    }
    return 0;
}

// Keys that compare equal may come out in any order, but no payload may be lost or duplicated;
// powers of two make each group's sum a unique witness for its multiset.
fn i32 sort_equal_keys_keep_all_payloads(arena::Arena* a, const u8[]m) {
    Point[6] buf;
    buf[0] = {2, 1}; buf[1] = {1, 2}; buf[2] = {2, 4};
    buf[3] = {1, 8}; buf[4] = {2, 16}; buf[5] = {1, 32};
    algo::sort(buf[0..6], &less_point);
    i32 low_payloads = 0;
    i32 high_payloads = 0;
    for(u64 i = 0; i < 3; i += 1) {
        if(!testing::expect_eq(buf[i].x, 1, m)) { return -1; }
        low_payloads += buf[i].y;
    }
    for(u64 i = 3; i < 6; i += 1) {
        if(!testing::expect_eq(buf[i].x, 2, m)) { return -2; }
        high_payloads += buf[i].y;
    }
    if(!testing::expect_eq(low_payloads, 42, m)) { return -3; }
    if(!testing::expect_eq(high_payloads, 21, m)) { return -4; }
    return 0;
}

fn i32 sort_wide_struct_elements(arena::Arena* a, const u8[]m) {
    Wide[5] buf;
    buf[0] = {5, 50, 500, 5000, 5.5};
    buf[1] = {1, 10, 100, 1000, 1.5};
    buf[2] = {4, 40, 400, 4000, 4.5};
    buf[3] = {2, 20, 200, 2000, 2.5};
    buf[4] = {3, 30, 300, 3000, 3.5};
    algo::sort(buf[0..5], &less_wide);
    for(u64 i = 0; i < 5; i += 1) {
        i64 rank = (i64)i + 1;
        if(!testing::expect_eq(buf[i].a, rank, m)) { return -1; }
        if(!testing::expect_eq(buf[i].b, rank * 10, m)) { return -2; }
        if(!testing::expect_eq(buf[i].c, rank * 100, m)) { return -3; }
        if(!testing::expect_eq(buf[i].d, rank * 1000, m)) { return -4; }
    }
    return 0;
}

fn i32 sort_negative_values(arena::Arena* a, const u8[]m) {
    i32[7] buf;
    buf[0] = 0; buf[1] = -2000000000; buf[2] = 2000000000; buf[3] = -1;
    buf[4] = 1; buf[5] = -2000000000; buf[6] = -100;
    algo::sort(buf[0..7], &less_i32);
    if(!testing::expect_eq(buf[0], -2000000000, m)) { return -1; }
    if(!testing::expect_eq(buf[1], -2000000000, m)) { return -2; }
    if(!testing::expect_eq(buf[2], -100, m)) { return -3; }
    if(!testing::expect_eq(buf[3], -1, m)) { return -4; }
    if(!testing::expect_eq(buf[4], 0, m)) { return -5; }
    if(!testing::expect_eq(buf[5], 1, m)) { return -6; }
    if(!testing::expect_eq(buf[6], 2000000000, m)) { return -7; }
    return 0;
}

fn i32 sort_pointer_elements(arena::Arena* a, const u8[]m) {
    i32 v0 = 9; i32 v1 = 4; i32 v2 = 7;
    i32*[3] buf;
    buf[0] = &v0; buf[1] = &v1; buf[2] = &v2;
    algo::sort(buf[0..3], &less_pointee);
    if(!testing::expect_eq(*buf[0], 4, m)) { return -1; }
    if(!testing::expect_eq(*buf[1], 7, m)) { return -2; }
    if(!testing::expect_eq(*buf[2], 9, m)) { return -3; }
    return 0;
}

// Slice elements through an alias: the comparator reads the pointee bytes, the sort moves {ptr, len}.
fn i32 sort_slice_elements(arena::Arena* a, const u8[]m) {
    Str[4] buf;
    buf[0] = "pear"; buf[1] = "apple"; buf[2] = "fig"; buf[3] = "apricot";
    algo::sort(buf[0..4], &less_str);
    if(!testing::expect_eq(buf[0], "apple", m)) { return -1; }
    if(!testing::expect_eq(buf[1], "apricot", m)) { return -2; }
    if(!testing::expect_eq(buf[2], "fig", m)) { return -3; }
    if(!testing::expect_eq(buf[3], "pear", m)) { return -4; }
    return 0;
}

fn i32 sort_descending_comparator(arena::Arena* a, const u8[]m) {
    i32[5] buf;
    buf[0] = 3; buf[1] = 1; buf[2] = 5; buf[3] = 2; buf[4] = 4;
    algo::sort(buf[0..5], &greater_i32);
    for(u64 i = 0; i < 5; i += 1) {
        if(!testing::expect_eq(buf[i], 5 - (i32)i, m)) { return -1; }
    }
    return 0;
}

// `data` is the live elements, so sorting the slice sorts the list in place.
fn i32 sort_list_data_in_place(arena::Arena* a, const u8[]m) {
    list::List(i32) xs = {{null, 0}, 0};
    for(i32 i = 0; i < 10; i += 1) { list::push(&xs, arena::allocator(a), (i * 7) % 10); }
    algo::sort(xs.data, &less_i32);
    if(!testing::expect_eq(xs.data.len, (u64)10, m)) { return -1; }
    for(u64 i = 0; i < 10; i += 1) {
        if(!testing::expect_eq(xs.data[i], (i32)i, m)) { return -2; }
    }
    return 0;
}

// A sub-slice sort must not reach outside its own bounds.
fn i32 sort_subslice_leaves_rest_untouched(arena::Arena* a, const u8[]m) {
    i32[8] buf;
    buf[0] = 99; buf[1] = 98;
    buf[2] = 5; buf[3] = 1; buf[4] = 4; buf[5] = 2;
    buf[6] = 97; buf[7] = 96;
    algo::sort(buf[2..6], &less_i32);
    if(!testing::expect_eq(buf[0], 99, m)) { return -1; }
    if(!testing::expect_eq(buf[1], 98, m)) { return -2; }
    if(!testing::expect_eq(buf[2], 1, m)) { return -3; }
    if(!testing::expect_eq(buf[3], 2, m)) { return -4; }
    if(!testing::expect_eq(buf[4], 4, m)) { return -5; }
    if(!testing::expect_eq(buf[5], 5, m)) { return -6; }
    if(!testing::expect_eq(buf[6], 97, m)) { return -7; }
    if(!testing::expect_eq(buf[7], 96, m)) { return -8; }
    return 0;
}

fn i32 sort_is_idempotent(arena::Arena* a, const u8[]m) {
    i32[9] buf;
    buf[0] = 4; buf[1] = 4; buf[2] = 1; buf[3] = 9; buf[4] = 2;
    buf[5] = 2; buf[6] = 7; buf[7] = 1; buf[8] = 4;
    algo::sort(buf[0..9], &less_i32);
    i32[9] once;
    for(u64 i = 0; i < 9; i += 1) { once[i] = buf[i]; }
    algo::sort(buf[0..9], &less_i32);
    for(u64 i = 0; i < 9; i += 1) {
        if(!testing::expect_eq(buf[i], once[i], m)) { return -1; }
    }
    return 0;
}

fn i32 main() {
    testing::init();
    const u8[] suite = "Algo Tests";
    testing::add(suite, "swap_scalars", &swap_scalars);
    testing::add(suite, "swap_aliased", &swap_aliased);
    testing::add(suite, "swap_struct_elem", &swap_struct_elem);
    testing::add(suite, "swap_pointer_elem", &swap_pointer_elem);
    testing::add(suite, "swap_slice_elem", &swap_slice_elem);
    testing::add(suite, "swap_fn_ptr_elem", &swap_fn_ptr_elem);
    testing::add(suite, "swap_wide_struct_elem", &swap_wide_struct_elem);
    testing::add(suite, "swap_float_and_bool", &swap_float_and_bool);
    testing::add(suite, "sort_empty_and_single", &sort_empty_and_single);
    testing::add(suite, "sort_empty_subslice", &sort_empty_subslice);
    testing::add(suite, "sort_pairs", &sort_pairs);
    testing::add(suite, "sort_all_arrays_up_to_three", &sort_all_arrays_up_to_three);
    testing::add(suite, "sort_all_arrays_of_four", &sort_all_arrays_of_four);
    testing::add(suite, "sort_all_arrays_of_five", &sort_all_arrays_of_five);
    testing::add(suite, "sort_all_binary_arrays_of_six", &sort_all_binary_arrays_of_six);
    testing::add(suite, "sort_structured_patterns", &sort_structured_patterns);
    testing::add(suite, "sort_all_equal_is_not_quadratic", &sort_all_equal_is_not_quadratic);
    testing::add(suite, "sort_sorted_input_is_not_quadratic", &sort_sorted_input_is_not_quadratic);
    testing::add(suite, "sort_large_all_equal_terminates", &sort_large_all_equal_terminates);
    testing::add(suite, "sort_u64_elements", &sort_u64_elements);
    testing::add(suite, "sort_f64_elements", &sort_f64_elements);
    testing::add(suite, "sort_u8_elements", &sort_u8_elements);
    testing::add(suite, "sort_struct_by_field", &sort_struct_by_field);
    testing::add(suite, "sort_equal_keys_keep_all_payloads", &sort_equal_keys_keep_all_payloads);
    testing::add(suite, "sort_wide_struct_elements", &sort_wide_struct_elements);
    testing::add(suite, "sort_negative_values", &sort_negative_values);
    testing::add(suite, "sort_pointer_elements", &sort_pointer_elements);
    testing::add(suite, "sort_slice_elements", &sort_slice_elements);
    testing::add(suite, "sort_descending_comparator", &sort_descending_comparator);
    testing::add(suite, "sort_list_data_in_place", &sort_list_data_in_place);
    testing::add(suite, "sort_subslice_leaves_rest_untouched", &sort_subslice_leaves_rest_untouched);
    testing::add(suite, "sort_is_idempotent", &sort_is_idempotent);
    return testing::run();
}
