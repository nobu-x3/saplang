import lib;

union Slot {
    lib::Item* item;
    u64 raw;
}

fn i32 main() {
    Slot s;
    s.raw = 0;
    if(s.raw != 0) { return 1; }
    return 0;
}
