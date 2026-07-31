import testing;
import io;
import arena;
import sys;

// Reads `path` via raw sys::fopen + sys::fread (no io.sl involvement) and
// asserts the content matches `expected`. Catches the case where io.sl's
// write and read are both no-ops yet round-trip.
fn bool verify_file_bytes(const u8[] path, const u8[] expected, arena::Arena* a, const u8[] m) {
    u8[4096] path_buf;
    u64 i = 0;
    while(i < path.len) {
        path_buf[i] = path.ptr[i];
        i += 1;
    }
    path_buf[path.len] = 0;
    sys::FILE* fp = sys::fopen((const i8*)&path_buf[0], "rb");
    if(!fp) {
        sys::printf("[____FAIL____] %.*s: file %.*s not openable for verify\n", (i32)m.len, m.ptr, (i32)path.len, path.ptr);
        return false;
    }
    u64 cap = expected.len + 16;
    if(cap < 16) { cap = 16; }
    u8* buf = arena::alloc(a, cap);
    if(!buf) {
        sys::fclose(fp);
        sys::printf("[____FAIL____] %.*s: arena alloc failed in verify\n", (i32)m.len, m.ptr);
        return false;
    }
    u64 n = sys::fread(buf, 1, cap, fp);
    sys::fclose(fp);
    u8[] got = {buf, n};
    if(!testing::expect_eq(got, expected, m)) {
        return false;
    }
    return true;
}

fn i32 open_nonexistent(arena::Arena* a, const u8[]m) {
    io::unlink("./io_t_nope.txt");
    io::File f = io::open("./io_t_nope.txt", "r");
    if(!testing::expect_null((void*)f.fp, m)) { return -1; }
    return 0;
}

fn i32 open_then_close(arena::Arena* a, const u8[]m) {
    const u8[] path = "./io_t_open.txt";
    io::unlink(path);
    io::File f = io::open(path, "w");
    if(!testing::expect_not_null((void*)f.fp, m)) { return -1; }
    if(!testing::expect_true(io::close(&f), m)) { return -2; }
    if(!testing::expect_null((void*)f.fp, m)) { return -3; }
    io::unlink(path);
    return 0;
}

fn i32 close_idempotent(arena::Arena* a, const u8[]m) {
    const u8[] path = "./io_t_close2.txt";
    io::unlink(path);
    io::File f = io::open(path, "w");
    if(!testing::expect_true(io::close(&f), m)) { return -1; }
    if(!testing::expect_false(io::close(&f), m)) { return -2; }
    io::unlink(path);
    return 0;
}

fn i32 write_then_read_raw(arena::Arena* a, const u8[]m) {
    const u8[] path = "./io_t_raw.txt";
    io::unlink(path);
    io::File w = io::open(path, "w");
    if(!testing::expect_not_null((void*)w.fp, m)) { return -1; }
    const u8[] payload = "hello bytes";
    if(!testing::expect_eq(io::write(&w, payload), payload.len, m)) { return -2; }
    io::close(&w);

    if(!verify_file_bytes(path, payload, a, m)) { return -6; }

    io::File r = io::open(path, "r");
    if(!testing::expect_not_null((void*)r.fp, m)) { return -3; }
    u8[64] buf;
    u8[] dst = {&buf[0], 64};
    u64 n = io::read(&r, dst);
    if(!testing::expect_eq(n, payload.len, m)) { return -4; }
    u8[] got = {&buf[0], n};
    if(!testing::expect_eq(got, payload, m)) { return -5; }
    io::close(&r);
    io::unlink(path);
    return 0;
}

fn i32 write_string_round_trip(arena::Arena* a, const u8[]m) {
    const u8[] path = "./io_t_ws.txt";
    io::unlink(path);
    io::File w = io::open(path, "w");
    if(!testing::expect_true(io::write_string(&w, "abc xyz"), m)) { return -1; }
    io::close(&w);

    if(!verify_file_bytes(path, "abc xyz", a, m)) { return -3; }

    io::File r = io::open(path, "r");
    u8[] all = io::read_all(&r, a);
    if(!testing::expect_eq(all, "abc xyz", m)) { return -2; }
    io::close(&r);
    io::unlink(path);
    return 0;
}

fn i32 write_line_then_read_line(arena::Arena* a, const u8[]m) {
    const u8[] path = "./io_t_wl.txt";
    io::unlink(path);
    io::File w = io::open(path, "w");
    if(!testing::expect_true(io::write_line(&w, "first line"), m)) { return -1; }
    io::close(&w);

    if(!verify_file_bytes(path, "first line\n", a, m)) { return -5; }

    io::File r = io::open(path, "r");
    u8[] line = io::read_line(&r, a);
    if(!testing::expect_eq(line, "first line", m)) { return -2; }
    u8[] past = io::read_line(&r, a);
    if(!testing::expect_null((void*)past.ptr, m)) { return -3; }
    if(!testing::expect_eq(past.len, 0, m)) { return -4; }
    io::close(&r);
    io::unlink(path);
    return 0;
}

fn i32 read_line_multiple(arena::Arena* a, const u8[]m) {
    const u8[] path = "./io_t_ml.txt";
    io::unlink(path);
    io::File w = io::open(path, "w");
    io::write_line(&w, "alpha");
    io::write_line(&w, "beta");
    io::write_line(&w, "gamma");
    io::close(&w);

    if(!verify_file_bytes(path, "alpha\nbeta\ngamma\n", a, m)) { return -5; }

    io::File r = io::open(path, "r");
    u8[] l1 = io::read_line(&r, a);
    u8[] l2 = io::read_line(&r, a);
    u8[] l3 = io::read_line(&r, a);
    u8[] l4 = io::read_line(&r, a);
    if(!testing::expect_eq(l1, "alpha", m)) { return -1; }
    if(!testing::expect_eq(l2, "beta", m)) { return -2; }
    if(!testing::expect_eq(l3, "gamma", m)) { return -3; }
    if(!testing::expect_null((void*)l4.ptr, m)) { return -4; }
    io::close(&r);
    io::unlink(path);
    return 0;
}

fn i32 read_line_empty(arena::Arena* a, const u8[]m) {
    const u8[] path = "./io_t_empty_line.txt";
    io::unlink(path);
    io::File w = io::open(path, "w");
    io::write_line(&w, "");
    io::write_line(&w, "after");
    io::close(&w);

    if(!verify_file_bytes(path, "\nafter\n", a, m)) { return -4; }

    io::File r = io::open(path, "r");
    u8[] l1 = io::read_line(&r, a);
    u8[] l2 = io::read_line(&r, a);
    if(!testing::expect_not_null((void*)l1.ptr, m)) { return -1; }
    if(!testing::expect_eq(l1.len, 0, m)) { return -2; }
    if(!testing::expect_eq(l2, "after", m)) { return -3; }
    io::close(&r);
    io::unlink(path);
    return 0;
}

fn i32 read_until_middle(arena::Arena* a, const u8[]m) {
    const u8[] path = "./io_t_ru_mid.txt";
    io::unlink(path);
    io::File w = io::open(path, "w");
    io::write_string(&w, "abc;def");
    io::close(&w);

    if(!verify_file_bytes(path, "abc;def", a, m)) { return -3; }

    io::File r = io::open(path, "r");
    u8[] head = io::read_until(&r, a, ';');
    if(!testing::expect_eq(head, "abc", m)) { return -1; }
    u8[] tail = io::read_until(&r, a, ';');
    if(!testing::expect_eq(tail, "def", m)) { return -2; }
    io::close(&r);
    io::unlink(path);
    return 0;
}

fn i32 read_until_absent_delim(arena::Arena* a, const u8[]m) {
    const u8[] path = "./io_t_ru_abs.txt";
    io::unlink(path);
    io::File w = io::open(path, "w");
    io::write_string(&w, "abc");
    io::close(&w);

    if(!verify_file_bytes(path, "abc", a, m)) { return -2; }

    io::File r = io::open(path, "r");
    u8[] got = io::read_until(&r, a, ';');
    if(!testing::expect_eq(got, "abc", m)) { return -1; }
    io::close(&r);
    io::unlink(path);
    return 0;
}

fn i32 read_until_immediate_delim(arena::Arena* a, const u8[]m) {
    const u8[] path = "./io_t_ru_im.txt";
    io::unlink(path);
    io::File w = io::open(path, "w");
    io::write_string(&w, ";rest");
    io::close(&w);

    if(!verify_file_bytes(path, ";rest", a, m)) { return -4; }

    io::File r = io::open(path, "r");
    u8[] hit = io::read_until(&r, a, ';');
    if(!testing::expect_not_null((void*)hit.ptr, m)) { return -1; }
    if(!testing::expect_eq(hit.len, 0, m)) { return -2; }
    u8[] rest = io::read_until(&r, a, ';');
    if(!testing::expect_eq(rest, "rest", m)) { return -3; }
    io::close(&r);
    io::unlink(path);
    return 0;
}

fn i32 read_until_grows_buffer(arena::Arena* a, const u8[]m) {
    const u8[] path = "./io_t_ru_grow.txt";
    io::unlink(path);
    io::File w = io::open(path, "w");
    u64 payload_len = 500;
    u8* big = arena::alloc(a, payload_len);
    for(u64 i = 0; i < payload_len; i += 1) {
        big[i] = (u8)('A' + (u8)(i % 26));
    }
    u8[] payload = {big, payload_len};
    io::write(&w, payload);
    u8 stop = '!';
    u8[] tail = {&stop, 1};
    io::write(&w, tail);
    io::close(&w);

    u8* expected_buf = arena::alloc(a, payload_len + 1);
    sys::memcpy(expected_buf, big, payload_len);
    expected_buf[payload_len] = '!';
    u8[] expected = {expected_buf, payload_len + 1};
    if(!verify_file_bytes(path, expected, a, m)) { return -2; }

    io::File r = io::open(path, "r");
    u8[] got = io::read_until(&r, a, '!');
    if(!testing::expect_eq(got, payload, m)) { return -1; }
    io::close(&r);
    io::unlink(path);
    return 0;
}

fn i32 read_all_empty(arena::Arena* a, const u8[]m) {
    const u8[] path = "./io_t_all_empty.txt";
    io::unlink(path);
    io::File w = io::open(path, "w");
    io::close(&w);

    io::File r = io::open(path, "r");
    u8[] got = io::read_all(&r, a);
    if(!testing::expect_not_null((void*)got.ptr, m)) { return -1; }
    if(!testing::expect_eq(got.len, 0, m)) { return -2; }
    io::close(&r);
    io::unlink(path);
    return 0;
}

fn i32 read_all_contents(arena::Arena* a, const u8[]m) {
    const u8[] path = "./io_t_all.txt";
    io::unlink(path);
    io::File w = io::open(path, "w");
    io::write_string(&w, "the quick brown fox\nover the lazy dog\n");
    io::close(&w);

    if(!verify_file_bytes(path, "the quick brown fox\nover the lazy dog\n", a, m)) { return -2; }

    io::File r = io::open(path, "r");
    u8[] got = io::read_all(&r, a);
    if(!testing::expect_eq(got, "the quick brown fox\nover the lazy dog\n", m)) { return -1; }
    io::close(&r);
    io::unlink(path);
    return 0;
}

fn i32 write_until_delim_present(arena::Arena* a, const u8[]m) {
    const u8[] path = "./io_t_wu_present.txt";
    io::unlink(path);
    io::File w = io::open(path, "w");
    u64 n = io::write_until(&w, "abc;def", ';');
    if(!testing::expect_eq(n, 4, m)) { return -1; }
    io::close(&w);

    if(!verify_file_bytes(path, "abc;", a, m)) { return -3; }

    io::File r = io::open(path, "r");
    u8[] got = io::read_all(&r, a);
    if(!testing::expect_eq(got, "abc;", m)) { return -2; }
    io::close(&r);
    io::unlink(path);
    return 0;
}

fn i32 write_until_delim_absent(arena::Arena* a, const u8[]m) {
    const u8[] path = "./io_t_wu_absent.txt";
    io::unlink(path);
    io::File w = io::open(path, "w");
    u64 n = io::write_until(&w, "abc", ';');
    if(!testing::expect_eq(n, 3, m)) { return -1; }
    io::close(&w);

    if(!verify_file_bytes(path, "abc", a, m)) { return -3; }

    io::File r = io::open(path, "r");
    u8[] got = io::read_all(&r, a);
    if(!testing::expect_eq(got, "abc", m)) { return -2; }
    io::close(&r);
    io::unlink(path);
    return 0;
}

fn i32 flush_persists_data(arena::Arena* a, const u8[]m) {
    const u8[] path = "./io_t_flush.txt";
    io::unlink(path);
    io::File w = io::open(path, "w");
    io::write_string(&w, "buffered");
    if(!testing::expect_true(io::flush(&w), m)) { return -1; }

    if(!verify_file_bytes(path, "buffered", a, m)) { return -3; }

    io::File r = io::open(path, "r");
    u8[] got = io::read_all(&r, a);
    if(!testing::expect_eq(got, "buffered", m)) { return -2; }
    io::close(&r);
    io::close(&w);
    io::unlink(path);
    return 0;
}

fn i32 is_eof_after_read_all(arena::Arena* a, const u8[]m) {
    const u8[] path = "./io_t_eof.txt";
    io::unlink(path);
    io::File w = io::open(path, "w");
    io::write_string(&w, "tiny");
    io::close(&w);

    if(!verify_file_bytes(path, "tiny", a, m)) { return -4; }

    io::File r = io::open(path, "r");
    if(!testing::expect_false(io::is_eof(&r), m)) { return -1; }
    u8[] got = io::read_all(&r, a);
    if(!testing::expect_eq(got, "tiny", m)) { return -5; }
    i32 probe = sys::fgetc(r.fp);
    if(!testing::expect_lt(probe, 0, m)) { return -2; }
    if(!testing::expect_true(io::is_eof(&r), m)) { return -3; }
    io::close(&r);
    io::unlink(path);
    return 0;
}

fn i32 is_eof_on_closed(arena::Arena* a, const u8[]m) {
    io::File f = {null};
    if(!testing::expect_true(io::is_eof(&f), m)) { return -1; }
    return 0;
}

fn i32 unlink_existing(arena::Arena* a, const u8[]m) {
    const u8[] path = "./io_t_unlink.txt";
    io::unlink(path);
    io::File w = io::open(path, "w");
    if(!testing::expect_not_null((void*)w.fp, m)) { return -1; }
    io::close(&w);
    if(!testing::expect_true(io::unlink(path), m)) { return -2; }
    io::File r = io::open(path, "r");
    if(!testing::expect_null((void*)r.fp, m)) { return -3; }
    return 0;
}

fn i32 unlink_missing_returns_false(arena::Arena* a, const u8[]m) {
    io::unlink("./io_t_missing.txt");
    if(!testing::expect_false(io::unlink("./io_t_missing.txt"), m)) { return -1; }
    return 0;
}

fn i32 write_ops_on_closed(arena::Arena* a, const u8[]m) {
    io::File f = {null};
    if(!testing::expect_eq(io::write(&f, "x"), 0, m)) { return -1; }
    if(!testing::expect_false(io::write_string(&f, "x"), m)) { return -2; }
    if(!testing::expect_false(io::write_line(&f, "x"), m)) { return -3; }
    if(!testing::expect_eq(io::write_until(&f, "x", '!'), 0, m)) { return -4; }
    if(!testing::expect_false(io::flush(&f), m)) { return -5; }
    return 0;
}

fn i32 read_ops_on_closed(arena::Arena* a, const u8[]m) {
    io::File f = {null};
    u8[16] tmp;
    u8[] dst = {&tmp[0], 16};
    if(!testing::expect_eq(io::read(&f, dst), 0, m)) { return -1; }
    u8[] line = io::read_line(&f, a);
    if(!testing::expect_null((void*)line.ptr, m)) { return -2; }
    u8[] all = io::read_all(&f, a);
    if(!testing::expect_null((void*)all.ptr, m)) { return -3; }
    return 0;
}

fn i32 main() {
    testing::init();
    const u8[] suite = "IO Tests";
    testing::add(suite, "open_nonexistent", &open_nonexistent);
    testing::add(suite, "open_then_close", &open_then_close);
    testing::add(suite, "close_idempotent", &close_idempotent);
    testing::add(suite, "write_then_read_raw", &write_then_read_raw);
    testing::add(suite, "write_string_round_trip", &write_string_round_trip);
    testing::add(suite, "write_line_then_read_line", &write_line_then_read_line);
    testing::add(suite, "read_line_multiple", &read_line_multiple);
    testing::add(suite, "read_line_empty", &read_line_empty);
    testing::add(suite, "read_until_middle", &read_until_middle);
    testing::add(suite, "read_until_absent_delim", &read_until_absent_delim);
    testing::add(suite, "read_until_immediate_delim", &read_until_immediate_delim);
    testing::add(suite, "read_until_grows_buffer", &read_until_grows_buffer);
    testing::add(suite, "read_all_empty", &read_all_empty);
    testing::add(suite, "read_all_contents", &read_all_contents);
    testing::add(suite, "write_until_delim_present", &write_until_delim_present);
    testing::add(suite, "write_until_delim_absent", &write_until_delim_absent);
    testing::add(suite, "flush_persists_data", &flush_persists_data);
    testing::add(suite, "is_eof_after_read_all", &is_eof_after_read_all);
    testing::add(suite, "is_eof_on_closed", &is_eof_on_closed);
    testing::add(suite, "unlink_existing", &unlink_existing);
    testing::add(suite, "unlink_missing_returns_false", &unlink_missing_returns_false);
    testing::add(suite, "write_ops_on_closed", &write_ops_on_closed);
    testing::add(suite, "read_ops_on_closed", &read_ops_on_closed);
    return testing::run();
}
