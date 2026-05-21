struct Inner {
    i32 x;
    i32 y;
}

struct Outer {
    Inner inner;
    i64 tag;
}

i32 g_count;
Outer g_outer;

fn i32 main() {
    g_count = 7;
    g_outer.inner.x = 3;
    g_outer.inner.y = 4;
    g_outer.tag = 11;
    return g_count - 7;
}
