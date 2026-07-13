import compiler;
import arena;
import interner;
import types;
import token;
import sys;

fn u8[] cstr_slice(u8* cstr) {
    u64 len = 0;
    while(cstr[len] != 0) { len += 1; }
    u8[] out = {cstr, len};
    return out;
}

fn i32 main(i32 argc, u8** argv) {
    arena::Arena symbol_arena;
    arena::Arena type_arena;
    arena::Arena arena;
    sys::memset(&symbol_arena, 0, sizeof(arena::Arena));
    sys::memset(&type_arena, 0, sizeof(arena::Arena));
    sys::memset(&arena, 0, sizeof(arena::Arena));
    symbol_arena.default_page_size = 1048576;
    type_arena.default_page_size = 1048576;
    arena.default_page_size = 1048576;
    interner::init(&symbol_arena, 1024);
    types::typer_init(&type_arena, 1024);
    token::load_keywords();

    compiler::Compiler* c = compiler::new(&arena);

    u8[][] args = {null, 0};
    if(argc > 1) {
        args.len = (u64)(argc - 1);
        args.ptr = arena::alloc(&arena, args.len * sizeof(u8[]));
        for(i32 arg_index = 1; arg_index < argc; arg_index += 1) {
            args[arg_index - 1] = cstr_slice(argv[arg_index]);
        }
    }
    if(!compiler::parse_argv(c, args)) { return 1; }
    return compiler::run(c);
}
