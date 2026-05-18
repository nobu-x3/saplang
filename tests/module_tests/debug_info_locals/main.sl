struct Point {
    i32 x;
    i32 y;
}

fn i32 mul_add(i32 a, i32 b, i32 c) {
    i32 prod = a * b;
    i32 result = prod + c;
    return result;
}

fn i32 main() {
    Point p = {3, 4};
    i32 v = mul_add(p.x, p.y, 5);
    return v - 17;
}
