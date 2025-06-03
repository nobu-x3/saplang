import io;

fn i32 main() {
    io::FILE* f = io::fopen("imports_test_file.txt", "w");
    defer { io::fclose(f); }
    if(f) {
        io::fprintf(f, "hello friend\n");
    }
    return 0;
}
