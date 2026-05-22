import sys;
import arena;

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

export fn File open(u8[] path, u8[] mode) {
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

export fn u64 write(File* f, u8[] src) {
    if(!f || !f.fp || !src.ptr) {
        return 0;
    }
    return sys::fwrite(src.ptr, 1, src.len, f.fp);
}

// {null, 0} = EOF before any byte; {ptr, 0} = delim was the next byte;
// {ptr, n} = n bytes then delim or EOF.
export fn u8[] read_until(File* f, arena::Arena* a, u8 delim) {
    u8[] out = {null, 0};
    if(!f || !f.fp || !a) {
        return out;
    }
    i32 first = sys::fgetc(f.fp);
    if(first < 0) {
        return out;
    }
    u64 cap = 64;
    u8* buf = arena::alloc(a, cap);
    if(!buf) {
        return out;
    }
    u64 len = 0;
    i32 c = first;
    while(c >= 0 && (u8)c != delim) {
        if(len >= cap) {
            u64 new_cap = cap * 2;
            buf = arena::realloc_grow(a, buf, cap, new_cap);
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
    return read_until(f, a, NEXT_LINE);
}

// Falls back to chunked read when fseek/ftell isn't supported.
export fn u8[] read_all(File* f, arena::Arena* a) {
    u8[] out = {null, 0};
    if(!f || !f.fp || !a) {
        return out;
    }
    if(sys::fseek(f.fp, 0, sys::SEEK_END) == 0) {
        i64 sz = sys::ftell(f.fp);
        sys::fseek(f.fp, 0, sys::SEEK_SET);
        if(sz < 0) {
            return out;
        }
        u8* buf = arena::alloc(a, (u64)sz + 1);
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

export fn bool write_string(File* f, u8[] src) {
    return write(f, src) == src.len;
}

export fn bool write_line(File* f, u8[] src) {
    if(write(f, src) != src.len) {
        return false;
    }
    u8 nl = NEXT_LINE;
    u8[] tail = {&nl, 1};
    return write(f, tail) == 1;
}

// Writes through and including the first delim; all of src if delim is absent.
export fn u64 write_until(File* f, u8[] src, u8 delim) {
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
    u8[] cut = {src.ptr, limit};
    return write(f, cut);
}

export fn bool unlink(u8[] path) {
    u8[4096] path_buf;
    if(!cstr_into(path, &path_buf[0], 4096)) {
        return false;
    }
    return sys::remove((const i8*)&path_buf[0]) == 0;
}

// PRIVATE
fn u8[] read_growing(File* f, arena::Arena* a) {
    u8[] out = {null, 0};
    u64 cap = 4096;
    u8* buf = arena::alloc(a, cap);
    if(!buf) {
        return out;
    }
    u64 len = 0;
    while(true) {
        if(len == cap) {
            u64 new_cap = cap * 2;
            buf = arena::realloc_grow(a, buf, cap, new_cap);
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

fn bool cstr_into(u8[] src, u8* dst, u64 cap) {
    if(src.len + 1 > cap) {
        return false;
    }
    if(src.len > 0) {
        sys::memcpy(dst, src.ptr, src.len);
    }
    dst[src.len] = 0;
    return true;
}
