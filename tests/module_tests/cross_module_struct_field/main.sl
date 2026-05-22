import lib;

fn i32 main() {
    lib::Container c;
    lib::Node** raw = null;
    c.items = {raw, 0};
    if(c.items.len != 0) { return 1; }
    return 0;
}
