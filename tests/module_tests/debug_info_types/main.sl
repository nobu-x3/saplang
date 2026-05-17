struct Point {
    i32 x;
    i32 y;
}

union Num {
    i32 i;
    f32 f;
}

enum Color : i32 {
    Red = 0,
    Green = 1,
    Blue = 2,
}

fn i32 add(i32 a, i32 b) {
    return a + b;
}

fn i32 main() {
    Point p = {10, 20};
    Num n;
    n.i = 7;
    Color c = Color::Green;
    return add(p.x, p.y) - 30 + n.i - 7 + c - 1;
}
