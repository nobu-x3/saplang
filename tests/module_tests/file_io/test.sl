import io;

fn i32 main() {
    {
        var FILE* file = fopen("tmp.txt", "w");
        defer fclose(file);
        fputs(file, "8");
    }
    {
        var FILE* file = fopen("tmp.txt", "r");
        defer fclose(file);
        var i8 char = (i8)fgetc(file);
        printf("%d\n", char);
    }

    return 0;
}