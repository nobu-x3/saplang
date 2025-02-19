import io;

fn i32 main() {
    var FILE* file = fopen("tmp.txt", "w");
    defer fclose(file);
    fputs(file, "test string bla bla");
    return 0;
}