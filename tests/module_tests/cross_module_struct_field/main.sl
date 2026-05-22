import cmsf_lib;

fn i32 main() {
    cmsf_lib::Container c;
    cmsf_lib::Node** raw = null;
    c.items = {raw, 0};
    if(c.items.len != 0) { return 1; }
    return 0;
}
