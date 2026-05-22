import cmcg_lib;

fn i32 main() {
    if(cmcg_lib::MAX_LEN != 100) { return 1; }
    if(cmcg_lib::DELIM != ',') { return 2; }
    return 0;
}
