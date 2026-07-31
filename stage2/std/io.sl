import sys;
import arena;
import mem;

// Byte constants for read_until / write_until delimiters.
export const u8 NEXT_LINE       = '\n';
export const u8 CARRIAGE_RETURN = '\r';
export const u8 TAB             = '\t';
export const u8 SPACE           = ' ';
export const u8 NULL_TERM       = 0;

// TODO: Stage 2 comprun to pick "\r\n" on Windows binary mode.
export const u8[] LINE_SEP = "\n";

export struct File {
    sys::FILE* fp;
}

export fn File open(const u8[] path, const u8[] mode) {
    File f = {null};
    u8[4096] path_buf;
    u8[16] mode_buf;
    if(!cstr_into(path, &path_buf[0], 4096)) {
        return f;
    }
    if(!cstr_into(mode, &mode_buf[0], 16)) {
        return f;
    }
    f.fp = sys::fopen((const i8*)&path_buf[0], (const i8*)&mode_buf[0]);
    return f;
}

export fn bool close(File* f) {
    if(!f || !f.fp) {
        return false;
    }
    i32 rc = sys::fclose(f.fp);
    f.fp = null;
    return rc == 0;
}

export fn bool flush(File* f) {
    if(!f || !f.fp) {
        return false;
    }
    return sys::fflush(f.fp) == 0;
}

export fn bool is_eof(File* f) {
    if(!f || !f.fp) {
        return true;
    }
    return sys::feof(f.fp) != 0;
}

export fn u64 read(File* f, u8[] dst) {
    if(!f || !f.fp || !dst.ptr) {
        return 0;
    }
    return sys::fread(dst.ptr, 1, dst.len, f.fp);
}

export fn u64 write(File* f, const u8[] src) {
    if(!f || !f.fp || !src.ptr) {
        return 0;
    }
    return sys::fwrite(src.ptr, 1, src.len, f.fp);
}

// {null, 0} = EOF before any byte; {ptr, 0} = delim was the next byte;
// {ptr, n} = n bytes then delim or EOF.
export fn u8[] read_until(File* f, arena::Arena* a, u8 delim) {
    return read_until(f, arena::allocator(a), delim);
}

export fn u8[] read_until(File* f, mem::Allocator a, u8 delim) {
    u8[] out = {null, 0};
    if(!f || !f.fp) {
        return out;
    }
    i32 first = sys::fgetc(f.fp);
    if(first < 0) {
        return out;
    }
    u64 cap = 64;
    u8* buf = mem::alloc(a, cap);
    if(!buf) {
        return out;
    }
    u64 len = 0;
    i32 c = first;
    while(c >= 0 && (u8)c != delim) {
        if(len >= cap) {
            u64 new_cap = cap * 2;
            buf = mem::realloc_grow(a, buf, cap, new_cap);
            if(!buf) {
                out.ptr = null;
                out.len = 0;
                return out;
            }
            cap = new_cap;
        }
        buf[len] = (u8)c;
        len += 1;
        c = sys::fgetc(f.fp);
    }
    out.ptr = buf;
    out.len = len;
    return out;
}

export fn u8[] read_line(File* f, arena::Arena* a) {
    return read_until(f, arena::allocator(a), NEXT_LINE);
}

export fn u8[] read_line(File* f, mem::Allocator a) {
    return read_until(f, a, NEXT_LINE);
}

export fn u8[] read_all(File* f, arena::Arena* a) {
    return read_all(f, arena::allocator(a));
}

// Falls back to chunked read when fseek/ftell isn't supported.
export fn u8[] read_all(File* f, mem::Allocator a) {
    u8[] out = {null, 0};
    if(!f || !f.fp) {
        return out;
    }
    if(sys::fseek(f.fp, 0, sys::SEEK_END) == 0) {
        i64 sz = sys::ftell(f.fp);
        sys::fseek(f.fp, 0, sys::SEEK_SET);
        if(sz < 0) {
            return out;
        }
        u8* buf = mem::alloc(a, (u64)sz + 1);
        if(!buf) {
            return out;
        }
        u64 nread = 0;
        if(sz > 0) {
            nread = sys::fread(buf, 1, (u64)sz, f.fp);
        }
        out.ptr = buf;
        out.len = nread;
        return out;
    }
    return read_growing(f, a);
}

export fn bool write_string(File* f, const u8[] src) {
    return write(f, src) == src.len;
}

export fn bool write_line(File* f, const u8[] src) {
    if(write(f, src) != src.len) {
        return false;
    }
    u8 nl = NEXT_LINE;
    u8[] tail = {&nl, 1};
    return write(f, tail) == 1;
}

// Writes through and including the first delim; all of src if delim is absent.
export fn u64 write_until(File* f, const u8[] src, u8 delim) {
    if(!f || !f.fp || !src.ptr) {
        return 0;
    }
    u64 limit = src.len;
    for(u64 i = 0; i < src.len; i += 1) {
        if(src.ptr[i] == delim) {
            limit = i + 1;
            break;
        }
    }
    const u8[] cut = {src.ptr, limit};
    return write(f, cut);
}

export fn bool unlink(const u8[] path) {
    u8[4096] path_buf;
    if(!cstr_into(path, &path_buf[0], 4096)) {
        return false;
    }
    return sys::remove((const i8*)&path_buf[0]) == 0;
}

// Growable byte buffer. Append-only; the memory comes from the caller's
// allocator and lives as long as that allocator does.
export struct OutBuf {
    mem::Allocator allocator;
    u8[]           data;
    u64            cap;
}

export fn void outbuf_init(OutBuf* b, mem::Allocator a, u64 initial_cap) {
    b.allocator = a;
    b.data = {(u8*)mem::alloc(a, initial_cap), 0};
    b.cap = initial_cap;
}

export fn void outbuf_init(OutBuf* b, arena::Arena* a, u64 initial_cap) {
    outbuf_init(b, arena::allocator(a), initial_cap);
}

export fn void outbuf_reset(OutBuf* b) {
    b.data.len = 0;
}

export fn u8[] outbuf_bytes(OutBuf* b) {
    return b.data;
}

export fn void outbuf_write(OutBuf* b, const u8[] s) {
    if(s.len == 0) { return; }
    outbuf_ensure(b, s.len);
    sys::memcpy(&b.data[b.data.len], s.ptr, s.len);
    b.data.len += s.len;
}

export fn void outbuf_write_byte(OutBuf* b, u8 c) {
    outbuf_ensure(b, 1);
    b.data[b.data.len] = c;
    b.data.len += 1;
}

export fn void outbuf_write_u64(OutBuf* b, u64 v) {
    u8[32] scratch;
    i32 n = sys::snprintf((i8*)&scratch[0], 32, "%lu", v);
    if(n <= 0) { return; }
    u8[] tail = {&scratch[0], (u64)n};
    outbuf_write(b, tail);
}

export fn void outbuf_write_i64(OutBuf* b, i64 v) {
    u8[32] scratch;
    i32 n = sys::snprintf((i8*)&scratch[0], 32, "%ld", v);
    if(n <= 0) { return; }
    u8[] tail = {&scratch[0], (u64)n};
    outbuf_write(b, tail);
}

fn void outbuf_ensure(OutBuf* b, u64 add) {
    u64 need = b.data.len + add;
    if(need <= b.cap) { return; }
    u64 new_cap = b.cap * 2;
    if(new_cap == 0) { new_cap = 64; }
    while(new_cap < need) { new_cap *= 2; }
    b.data.ptr = (u8*)mem::realloc_grow(b.allocator, b.data.ptr, b.data.len, new_cap);
    b.cap = new_cap;
}

// PRIVATE
fn u8[] read_growing(File* f, mem::Allocator a) {
    u8[] out = {null, 0};
    u64 cap = 4096;
    u8* buf = mem::alloc(a, cap);
    if(!buf) {
        return out;
    }
    u64 len = 0;
    while(true) {
        if(len == cap) {
            u64 new_cap = cap * 2;
            buf = mem::realloc_grow(a, buf, cap, new_cap);
            if(!buf) {
                out.ptr = null;
                out.len = 0;
                return out;
            }
            cap = new_cap;
        }
        u64 n = sys::fread(buf + len, 1, cap - len, f.fp);
        len += n;
        if(n == 0) {
            break;
        }
    }
    out.ptr = buf;
    out.len = len;
    return out;
}

fn bool cstr_into(const u8[] src, u8* dst, u64 cap) {
    if(src.len + 1 > cap) {
        return false;
    }
    if(src.len > 0) {
        sys::memcpy(dst, src.ptr, src.len);
    }
    dst[src.len] = 0;
    return true;
}
