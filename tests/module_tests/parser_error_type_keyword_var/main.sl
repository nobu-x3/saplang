struct S { i32 x; }

fn S* mk() {
    S s = {0};
    return &s;
}

fn i32 main() {
    S* i32 = mk();
    return 0;
}
