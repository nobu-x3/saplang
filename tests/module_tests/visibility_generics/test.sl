import defs;

extern {
    fn void printf(const u8*, ...);
}

fn i32 main() {
    var GenericStruct<i32> gen_struct = gen_fun<i32>();
    printf("%d\n", gen_struct.first);
    init<i32>(&gen_struct);
    printf("%d\n", gen_struct.first);
    return 0;
}
