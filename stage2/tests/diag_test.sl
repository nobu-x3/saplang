import testing;
import arena;
import diag;
import sys;

fn diag::DiagBuf make_empty_buf() {
    diag::DiagBuf d;
    d.entries = {null, 0};
    d.entries_cap = 0;
    return d;
}

fn i32 empty_buf_zero_state(arena::Arena* a, const u8[]m) {
    diag::DiagBuf d = make_empty_buf();
    if(!testing::expect_eq(d.entries.len, (u64)0, m)) { return -1; }
    if(!testing::expect_eq(d.entries_cap, (u64)0, m)) { return -2; }
    if(!testing::expect_null((void*)d.entries.ptr, m)) { return -3; }
    return 0;
}

fn i32 report_single_appends_one_entry(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    diag::report(&d, &local, 42, "boom");
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -1; }
    return 0;
}

fn i32 report_first_push_allocates_buffer(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    diag::report(&d, &local, 0, "x");
    if(!testing::expect_not_null((void*)d.entries.ptr, m)) { return -1; }
    if(!testing::expect_eq(d.entries_cap, (u64)8, m)) { return -2; }
    return 0;
}

fn i32 report_stores_src_pos(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    diag::report(&d, &local, 42, "boom");
    if(!testing::expect_eq((u32)d.entries[0].src_pos, (u32)42, m)) { return -1; }
    return 0;
}

fn i32 report_stores_msg(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    diag::report(&d, &local, 0, "hello world");
    if(!testing::expect_eq(d.entries[0].msg, "hello world", m)) { return -1; }
    return 0;
}

fn i32 report_marks_error_not_warning(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    diag::report(&d, &local, 0, "err");
    if(!testing::expect_false(d.entries[0].is_warning, m)) { return -1; }
    return 0;
}

fn i32 report_warning_marks_warning(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    diag::report_warning(&d, &local, 0, "warn");
    if(!testing::expect_true(d.entries[0].is_warning, m)) { return -1; }
    return 0;
}

fn i32 report_warning_stores_src_pos_and_msg(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    diag::report_warning(&d, &local, 99, "careful");
    if(!testing::expect_eq((u32)d.entries[0].src_pos, (u32)99, m)) { return -1; }
    if(!testing::expect_eq(d.entries[0].msg, "careful", m)) { return -2; }
    return 0;
}

fn i32 multiple_reports_preserve_order(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    diag::report(&d, &local, 1, "a");
    diag::report(&d, &local, 2, "b");
    diag::report(&d, &local, 3, "c");
    if(!testing::expect_eq(d.entries.len, (u64)3, m)) { return -1; }
    if(!testing::expect_eq((u32)d.entries[0].src_pos, (u32)1, m)) { return -2; }
    if(!testing::expect_eq((u32)d.entries[1].src_pos, (u32)2, m)) { return -3; }
    if(!testing::expect_eq((u32)d.entries[2].src_pos, (u32)3, m)) { return -4; }
    return 0;
}

fn i32 multiple_reports_preserve_msgs(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    diag::report(&d, &local, 1, "alpha");
    diag::report(&d, &local, 2, "beta");
    diag::report(&d, &local, 3, "gamma");
    if(!testing::expect_eq(d.entries[0].msg, "alpha", m)) { return -1; }
    if(!testing::expect_eq(d.entries[1].msg, "beta", m)) { return -2; }
    if(!testing::expect_eq(d.entries[2].msg, "gamma", m)) { return -3; }
    return 0;
}

fn i32 growth_doubles_when_full(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    for(u32 i = 0; i < 8; i += 1) {
        diag::report(&d, &local, i, "x");
    }
    if(!testing::expect_eq(d.entries_cap, (u64)8, m)) { return -1; }
    if(!testing::expect_eq(d.entries.len, (u64)8, m)) { return -2; }
    diag::report(&d, &local, 8, "x");
    if(!testing::expect_eq(d.entries_cap, (u64)16, m)) { return -3; }
    if(!testing::expect_eq(d.entries.len, (u64)9, m)) { return -4; }
    return 0;
}

fn i32 growth_doubles_multiple_times(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    for(u32 i = 0; i < 50; i += 1) {
        diag::report(&d, &local, i, "x");
    }
    if(!testing::expect_eq(d.entries.len, (u64)50, m)) { return -1; }
    // 0 -> 8 -> 16 -> 32 -> 64
    if(!testing::expect_eq(d.entries_cap, (u64)64, m)) { return -2; }
    return 0;
}

fn i32 entries_intact_across_growth(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    for(u32 i = 0; i < 20; i += 1) {
        diag::report(&d, &local, i * 10, "x");
    }
    for(u32 i = 0; i < 20; i += 1) {
        if(!testing::expect_eq((u32)d.entries[i].src_pos, i * 10, m)) { return -1; }
    }
    return 0;
}

fn i32 msgs_intact_across_growth(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    diag::report(&d, &local, 0, "first");
    for(u32 i = 1; i < 20; i += 1) {
        diag::report(&d, &local, i, "filler");
    }
    diag::report(&d, &local, 100, "last");
    if(!testing::expect_eq(d.entries[0].msg, "first", m)) { return -1; }
    if(!testing::expect_eq(d.entries[20].msg, "last", m)) { return -2; }
    return 0;
}

fn i32 is_warning_intact_across_growth(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    for(u32 i = 0; i < 20; i += 1) {
        if(i % 2 == 0) {
            diag::report(&d, &local, i, "e");
        } else {
            diag::report_warning(&d, &local, i, "w");
        }
    }
    for(u32 i = 0; i < 20; i += 1) {
        bool want = (i % 2 == 1);
        if(!testing::expect_eq(d.entries[i].is_warning, want, m)) { return -1; }
    }
    return 0;
}

fn i32 mixed_error_and_warning_no_growth(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    diag::report(&d, &local, 0, "e0");
    diag::report_warning(&d, &local, 1, "w1");
    diag::report(&d, &local, 2, "e2");
    diag::report_warning(&d, &local, 3, "w3");
    if(!testing::expect_false(d.entries[0].is_warning, m)) { return -1; }
    if(!testing::expect_true(d.entries[1].is_warning, m)) { return -2; }
    if(!testing::expect_false(d.entries[2].is_warning, m)) { return -3; }
    if(!testing::expect_true(d.entries[3].is_warning, m)) { return -4; }
    return 0;
}

fn i32 reset_clears_len(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    diag::report(&d, &local, 0, "x");
    diag::report(&d, &local, 1, "y");
    diag::report(&d, &local, 2, "z");
    diag::reset(&d);
    if(!testing::expect_eq(d.entries.len, (u64)0, m)) { return -1; }
    return 0;
}

fn i32 reset_preserves_cap(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    diag::report(&d, &local, 0, "x");
    diag::report(&d, &local, 1, "y");
    u64 cap_before = d.entries_cap;
    diag::reset(&d);
    if(!testing::expect_eq(d.entries_cap, cap_before, m)) { return -1; }
    return 0;
}

fn i32 reset_preserves_ptr(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    diag::report(&d, &local, 0, "x");
    void* ptr_before = (void*)d.entries.ptr;
    diag::reset(&d);
    if(!testing::expect_eq((void*)d.entries.ptr, ptr_before, m)) { return -1; }
    return 0;
}

fn i32 reset_then_report_appends_at_zero(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    diag::report(&d, &local, 100, "before");
    diag::reset(&d);
    diag::report(&d, &local, 200, "after");
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -1; }
    if(!testing::expect_eq((u32)d.entries[0].src_pos, (u32)200, m)) { return -2; }
    if(!testing::expect_eq(d.entries[0].msg, "after", m)) { return -3; }
    return 0;
}

fn i32 reset_then_refill_within_cap(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    for(u32 i = 0; i < 12; i += 1) {
        diag::report(&d, &local, i, "x");
    }
    u64 cap_before = d.entries_cap;
    diag::reset(&d);
    for(u32 i = 0; i < 12; i += 1) {
        diag::report(&d, &local, 1000 + i, "y");
    }
    if(!testing::expect_eq(d.entries.len, (u64)12, m)) { return -1; }
    if(!testing::expect_eq(d.entries_cap, cap_before, m)) { return -2; }
    if(!testing::expect_eq((u32)d.entries[0].src_pos, (u32)1000, m)) { return -3; }
    if(!testing::expect_eq((u32)d.entries[11].src_pos, (u32)1011, m)) { return -4; }
    return 0;
}

fn i32 reset_then_grow_past_cap(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    for(u32 i = 0; i < 8; i += 1) {
        diag::report(&d, &local, i, "x");
    }
    diag::reset(&d);
    for(u32 i = 0; i < 30; i += 1) {
        diag::report(&d, &local, 1000 + i, "y");
    }
    if(!testing::expect_eq(d.entries.len, (u64)30, m)) { return -1; }
    if(!testing::expect_eq(d.entries_cap, (u64)32, m)) { return -2; }
    if(!testing::expect_eq((u32)d.entries[29].src_pos, (u32)1029, m)) { return -3; }
    return 0;
}

fn i32 reset_on_empty_is_noop(arena::Arena* a, const u8[]m) {
    diag::DiagBuf d = make_empty_buf();
    diag::reset(&d);
    if(!testing::expect_eq(d.entries.len, (u64)0, m)) { return -1; }
    if(!testing::expect_eq(d.entries_cap, (u64)0, m)) { return -2; }
    if(!testing::expect_null((void*)d.entries.ptr, m)) { return -3; }
    return 0;
}

fn i32 empty_msg_handled(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    u8[] empty = {null, 0};
    diag::report(&d, &local, 5, empty);
    if(!testing::expect_eq(d.entries[0].msg.len, (u64)0, m)) { return -1; }
    if(!testing::expect_eq((u32)d.entries[0].src_pos, (u32)5, m)) { return -2; }
    if(!testing::expect_eq(d.entries.len, (u64)1, m)) { return -3; }
    return 0;
}

fn i32 src_pos_zero(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    diag::report(&d, &local, 0, "at start");
    if(!testing::expect_eq((u32)d.entries[0].src_pos, (u32)0, m)) { return -1; }
    return 0;
}

fn i32 src_pos_max_u32(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    u32 huge = (u32)0xFFFFFFFF;
    diag::report(&d, &local, huge, "edge");
    if(!testing::expect_eq((u32)d.entries[0].src_pos, huge, m)) { return -1; }
    return 0;
}

fn i32 duplicate_src_pos_appends_twice(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    diag::report(&d, &local, 7, "first");
    diag::report(&d, &local, 7, "second");
    if(!testing::expect_eq(d.entries.len, (u64)2, m)) { return -1; }
    if(!testing::expect_eq((u32)d.entries[0].src_pos, (u32)7, m)) { return -2; }
    if(!testing::expect_eq((u32)d.entries[1].src_pos, (u32)7, m)) { return -3; }
    if(!testing::expect_eq(d.entries[0].msg, "first", m)) { return -4; }
    if(!testing::expect_eq(d.entries[1].msg, "second", m)) { return -5; }
    return 0;
}

fn i32 duplicate_msg_appends_twice(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    diag::report(&d, &local, 1, "same");
    diag::report(&d, &local, 2, "same");
    if(!testing::expect_eq(d.entries.len, (u64)2, m)) { return -1; }
    if(!testing::expect_eq(d.entries[0].msg, "same", m)) { return -2; }
    if(!testing::expect_eq(d.entries[1].msg, "same", m)) { return -3; }
    return 0;
}

fn i32 long_msg_handled(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    const u8[] long_msg = "the quick brown fox jumps over the lazy dog 0123456789 the quick brown fox jumps over the lazy dog";
    diag::report(&d, &local, 1, long_msg);
    if(!testing::expect_eq(d.entries[0].msg, long_msg, m)) { return -1; }
    if(!testing::expect_eq(d.entries[0].msg.len, long_msg.len, m)) { return -2; }
    return 0;
}

fn i32 msg_bytes_copied_into_arena(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d = make_empty_buf();
    const u8[] src = "shared";
    diag::report(&d, &local, 0, src);
    if(!testing::expect_ne((void*)d.entries[0].msg.ptr, (void*)src.ptr, m)) { return -1; }
    if(!testing::expect_eq(d.entries[0].msg.len, src.len, m)) { return -2; }
    if(!testing::expect_eq(d.entries[0].msg, src, m)) { return -3; }
    return 0;
}

fn i32 independent_buffers_are_independent(arena::Arena* a, const u8[]m) {
    arena::Arena local = {4096, null};
    diag::DiagBuf d1 = make_empty_buf();
    diag::DiagBuf d2 = make_empty_buf();
    diag::report(&d1, &local, 1, "in d1");
    diag::report(&d2, &local, 2, "in d2");
    diag::report(&d2, &local, 3, "also d2");
    if(!testing::expect_eq(d1.entries.len, (u64)1, m)) { return -1; }
    if(!testing::expect_eq(d2.entries.len, (u64)2, m)) { return -2; }
    if(!testing::expect_eq((u32)d1.entries[0].src_pos, (u32)1, m)) { return -3; }
    if(!testing::expect_eq((u32)d2.entries[0].src_pos, (u32)2, m)) { return -4; }
    if(!testing::expect_eq((u32)d2.entries[1].src_pos, (u32)3, m)) { return -5; }
    return 0;
}

fn i32 main() {
    testing::init();
    const u8[] suite = "Diag Tests";
    testing::add(suite, "empty_buf_zero_state", &empty_buf_zero_state);
    testing::add(suite, "report_single_appends_one_entry", &report_single_appends_one_entry);
    testing::add(suite, "report_first_push_allocates_buffer", &report_first_push_allocates_buffer);
    testing::add(suite, "report_stores_src_pos", &report_stores_src_pos);
    testing::add(suite, "report_stores_msg", &report_stores_msg);
    testing::add(suite, "report_marks_error_not_warning", &report_marks_error_not_warning);
    testing::add(suite, "report_warning_marks_warning", &report_warning_marks_warning);
    testing::add(suite, "report_warning_stores_src_pos_and_msg", &report_warning_stores_src_pos_and_msg);
    testing::add(suite, "multiple_reports_preserve_order", &multiple_reports_preserve_order);
    testing::add(suite, "multiple_reports_preserve_msgs", &multiple_reports_preserve_msgs);
    testing::add(suite, "growth_doubles_when_full", &growth_doubles_when_full);
    testing::add(suite, "growth_doubles_multiple_times", &growth_doubles_multiple_times);
    testing::add(suite, "entries_intact_across_growth", &entries_intact_across_growth);
    testing::add(suite, "msgs_intact_across_growth", &msgs_intact_across_growth);
    testing::add(suite, "is_warning_intact_across_growth", &is_warning_intact_across_growth);
    testing::add(suite, "mixed_error_and_warning_no_growth", &mixed_error_and_warning_no_growth);
    testing::add(suite, "reset_clears_len", &reset_clears_len);
    testing::add(suite, "reset_preserves_cap", &reset_preserves_cap);
    testing::add(suite, "reset_preserves_ptr", &reset_preserves_ptr);
    testing::add(suite, "reset_then_report_appends_at_zero", &reset_then_report_appends_at_zero);
    testing::add(suite, "reset_then_refill_within_cap", &reset_then_refill_within_cap);
    testing::add(suite, "reset_then_grow_past_cap", &reset_then_grow_past_cap);
    testing::add(suite, "reset_on_empty_is_noop", &reset_on_empty_is_noop);
    testing::add(suite, "empty_msg_handled", &empty_msg_handled);
    testing::add(suite, "src_pos_zero", &src_pos_zero);
    testing::add(suite, "src_pos_max_u32", &src_pos_max_u32);
    testing::add(suite, "duplicate_src_pos_appends_twice", &duplicate_src_pos_appends_twice);
    testing::add(suite, "duplicate_msg_appends_twice", &duplicate_msg_appends_twice);
    testing::add(suite, "long_msg_handled", &long_msg_handled);
    testing::add(suite, "msg_bytes_copied_into_arena", &msg_bytes_copied_into_arena);
    testing::add(suite, "independent_buffers_are_independent", &independent_buffers_are_independent);
    return testing::run();
}
