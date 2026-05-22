import lib;

fn i32 main() {
    if(lib::MAX_LEN != 100) { return 1; }
    if(lib::DELIM != ',') { return 2; }
    return 0;
}
