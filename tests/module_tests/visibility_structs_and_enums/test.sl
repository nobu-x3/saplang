import defs;

extern {
    fn void printf(const u8*, ...);
}

fn i32 main() {
    var TestStruct t = .{32};
    printf("TestStruct value: %d\n", t.int);
    printf("TestEnum value: %d\n", TestEnum::First);
    var TestEnum e = TestEnum::First;
    printf("TestEnum value: %d\n", e);
    return 0;
}
