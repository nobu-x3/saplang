extern {
    export fn void* memset(void* p, i32 v, u64 n);
}

enum Flags : u8 {
    A = 1,
    B = 2,
    C = 4,
}

fn i32 main() {
    Flags f = (Flags)((u8)Flags::A | (u8)Flags::C);
    if ((u32)f != 5) { return 1; }

    Flags g = (Flags)2;
    if (g != Flags::B) { return 2; }

    u64 lo = 'A';
    u64 hi = 'Z';
    if (hi - lo != 25) { return 3; }

    u8[8] buf;
    memset(buf, 0, 8);
    if (buf[0] != 0) { return 4; }

    return 0;
}
