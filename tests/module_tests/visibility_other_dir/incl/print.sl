extern {
    fn void printf(const u8*, ...);
}

export fn void print_hello() {
    printf("hello world\n");
}
