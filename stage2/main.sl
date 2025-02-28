import scanner;

fn i32 main() {
    var Scanner scanner = .{"i32 hello = 0;\ni32 goodbye = 1;\n", 0};
    var Token token = next_token(&scanner);
    printf("%s\n", token.text);
    return 0;
}