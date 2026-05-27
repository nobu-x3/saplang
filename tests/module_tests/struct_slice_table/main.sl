struct Entry { u8[] bytes; i32 val; }

const Entry[] TABLE = [
    { "i8", 1 },
    { "alpha", 7 },
    { "", 99 },
];

fn i32 main() {
    if (TABLE.len != 3) { return 1; }
    if (TABLE[0].bytes.len != 2) { return 2; }
    if (TABLE[0].bytes.ptr[0] != 'i') { return 3; }
    if (TABLE[0].bytes.ptr[1] != '8') { return 4; }
    if (TABLE[0].val != 1) { return 5; }
    if (TABLE[1].bytes.len != 5) { return 6; }
    if (TABLE[1].bytes.ptr[0] != 'a') { return 7; }
    if (TABLE[1].val != 7) { return 8; }
    if (TABLE[2].bytes.len != 0) { return 9; }
    if (TABLE[2].val != 99) { return 10; }
    return 0;
}
