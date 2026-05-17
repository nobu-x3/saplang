fn i32 sum_to(i32 n) {
    i32 total = 0;
    for (i32 i = 0; i < n; i += 1) {
        total += i;
    }
    return total;
}

fn i32 main() {
    i32 r = sum_to(10);
    if (r != 45) {
        return 1;
    }
    return 0;
}
