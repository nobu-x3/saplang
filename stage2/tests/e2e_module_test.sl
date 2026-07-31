import testing;
import test_util;
import module;
import arena;

// Cross-module resolution end to end: alias chains, circular imports, and export enforcement.
// Diagnostics stay in each module's diag, so negatives pin the message and src_pos.

fn module::Module*[] pair(arena::Arena* a, const u8[]a_src, const u8[] b_src) {
    module::Module* first = test_util::mk_module(a, "a", a_src);
    module::Module* second = test_util::mk_module(a, "b", b_src);
    module::Module** both = (module::Module**)arena::alloc(a, 2 * sizeof(module::Module*));
    both[0] = first;
    both[1] = second;
    module::Module*[] modules = {both, 2};
    test_util::wire_imports(a, first, {&both[1], 1});
    return modules;
}

// ---- alias resolution across modules ----

fn i32 alias_to_foreign_struct(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nalias Point = b::P;\nexport fn i32 f() { Point p = {2, 3}; return p.x + p.y; }", "export struct P { i32 x; i32 y; }");
    test_util::frontend_modules(modules);
    if(!testing::expect_eq(test_util::errors_in(modules), (u64)0, m)) { return -1; }
    return 0;
}

// b aliases a primitive, a aliases b's alias: the chain has to resolve through both modules.
fn i32 alias_chain_across_modules(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nalias Local = b::Wide;\nexport fn Local f(Local v) { return v + (Local)1; }", "export alias Wide = i64;");
    test_util::frontend_modules(modules);
    if(!testing::expect_eq(test_util::errors_in(modules), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 alias_to_foreign_generic_instantiation(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nalias Boxed = b::Box(i32);\nexport fn i32 f() { Boxed x = {7}; return x.value; }", "export fn Type Box(comptime Type T) { return struct { T value; }; }");
    test_util::frontend_modules(modules);
    if(!testing::expect_eq(test_util::errors_in(modules), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 alias_to_foreign_fn_pointer(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nalias Op = b::BinOp;\nexport fn i32 f() { Op op = &b::add; return op(2, 3); }", "export alias BinOp = fn* i32(i32, i32);\nexport fn i32 add(i32 x, i32 y) { return x + y; }");
    test_util::frontend_modules(modules);
    if(!testing::expect_eq(test_util::errors_in(modules), (u64)0, m)) { return -1; }
    return 0;
}

// ---- circular imports ----

fn i32 circular_type_references(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module* first = test_util::mk_module(a, "a", "import b;\nexport struct A { i32 tag; b::B* peer; }\nexport fn i32 f(A* self) { return self.tag; }");
    module::Module* second = test_util::mk_module(a, "b", "import a;\nexport struct B { i32 tag; a::A* peer; }\nexport fn i32 g(B* self) { return self.tag; }");
    module::Module** both = (module::Module**)arena::alloc(a, 2 * sizeof(module::Module*));
    both[0] = first; both[1] = second;
    module::Module*[] modules = {both, 2};
    test_util::wire_imports(a, first, {&both[1], 1});
    test_util::wire_imports(a, second, {&both[0], 1});
    test_util::frontend_modules(modules);
    if(!testing::expect_eq(test_util::errors_in(modules), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 circular_alias_resolution(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module* first = test_util::mk_module(a, "a", "import b;\nexport struct A { i32 tag; }\nalias Peer = b::B;\nexport fn i32 f(Peer* p) { return p.tag; }");
    module::Module* second = test_util::mk_module(a, "b", "import a;\nexport struct B { i32 tag; }\nalias Peer = a::A;\nexport fn i32 g(Peer* p) { return p.tag; }");
    module::Module** both = (module::Module**)arena::alloc(a, 2 * sizeof(module::Module*));
    both[0] = first; both[1] = second;
    module::Module*[] modules = {both, 2};
    test_util::wire_imports(a, first, {&both[1], 1});
    test_util::wire_imports(a, second, {&both[0], 1});
    test_util::frontend_modules(modules);
    if(!testing::expect_eq(test_util::errors_in(modules), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 circular_const_read(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module* first = test_util::mk_module(a, "a", "import b;\nexport const i32 BASE = 10;\nexport fn i32 f() { return b::STEP + BASE; }");
    module::Module* second = test_util::mk_module(a, "b", "import a;\nexport const i32 STEP = 5;\nexport fn i32 g() { return a::BASE + STEP; }");
    module::Module** both = (module::Module**)arena::alloc(a, 2 * sizeof(module::Module*));
    both[0] = first; both[1] = second;
    module::Module*[] modules = {both, 2};
    test_util::wire_imports(a, first, {&both[1], 1});
    test_util::wire_imports(a, second, {&both[0], 1});
    test_util::frontend_modules(modules);
    if(!testing::expect_eq(test_util::errors_in(modules), (u64)0, m)) { return -1; }
    return 0;
}

// Aliases that define each other have no fixpoint; resolution must report rather than recurse forever.
fn i32 err_circular_alias_definition(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module* first = test_util::mk_module(a, "a", "import b;\nexport alias X = b::Y;\nexport fn i32 f() { X v = 1; return v; }");
    module::Module* second = test_util::mk_module(a, "b", "import a;\nexport alias Y = a::X;");
    module::Module** both = (module::Module**)arena::alloc(a, 2 * sizeof(module::Module*));
    both[0] = first; both[1] = second;
    module::Module*[] modules = {both, 2};
    test_util::wire_imports(a, first, {&both[1], 1});
    test_util::wire_imports(a, second, {&both[0], 1});
    test_util::frontend_modules(modules);
    if(!testing::expect_true(test_util::errors_in(modules) >= (u64)1, m)) { return -1; }
    if(!testing::expect_eq(modules[0].diag.entries[0].msg, "circular type resolution: Y", m)) { return -2; }
    if(!testing::expect_eq(modules[0].diag.entries[0].src_pos, (u32)17, m)) { return -3; }
    return 0;
}

// A field instantiates b::Box(i32) during a's signature phase, before b has resolved Box's return type.
// Deciding "is this a type constructor?" from the resolved type there sent it caller-side, minting a
// second, distinct struct type for the same written type; only the permissive pointer rule hid it.
fn i32 instantiation_identity_across_phases(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nstruct Holder { b::Box(i32) boxed; }\nfn i32 unwrap(b::Box(i32)* p) { return p.value; }\nexport fn i32 f() {\n  Holder h;\n  h.boxed.value = 1;\n  b::Box(i32) local;\n  local.value = 2;\n  return unwrap(&h.boxed) + unwrap(&local);\n}", "export fn Type Box(comptime Type T) { return struct { T value; }; }");
    test_util::frontend_modules(modules);
    if(!testing::expect_eq(test_util::errors_in(modules), (u64)0, m)) { return -1; }
    return 0;
}

// A qualified constructor pattern resolves through the generic's own imports, not the caller's.
fn i32 infers_through_qualified_constructor(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nfn T unwrap(comptime Type T, b::Box(T)* boxed) { return boxed.value; }\nexport fn i32 f() { b::Box(i32) boxed = {9}; return unwrap(&boxed); }", "export fn Type Box(comptime Type T) { return struct { T value; }; }");
    test_util::frontend_modules(modules);
    if(!testing::expect_eq(test_util::errors_in(modules), (u64)0, m)) { return -1; }
    return 0;
}

// Two modules can both export a `fn Type Box`. Matching a pattern on the trailing name alone bound T
// from the wrong constructor, and pointer-to-pointer conversion then hid it: the callee read the wrong field.
fn i32 err_same_named_constructors_do_not_unify(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module* user = test_util::mk_module(a, "a", "import b;\nimport c;\nfn T unwrap(comptime Type T, b::Box(T)* boxed) { return boxed.value; }\nexport fn i32 f() { c::Box(i32) from_c; from_c.value = 7; return unwrap(&from_c); }");
    module::Module* owner = test_util::mk_module(a, "b", "export fn Type Box(comptime Type T) { return struct { T value; }; }");
    module::Module* impostor = test_util::mk_module(a, "c", "export fn Type Box(comptime Type T) { return struct { u64 tag; T value; }; }");
    module::Module** all = (module::Module**)arena::alloc(a, 3 * sizeof(module::Module*));
    all[0] = user; all[1] = owner; all[2] = impostor;
    module::Module*[] modules = {all, 3};
    test_util::wire_imports(a, user, {&all[1], 2});
    test_util::frontend_modules(modules);
    if(!testing::expect_true(test_util::errors_in(modules) >= (u64)1, m)) { return -1; }
    if(!testing::expect_eq(modules[0].diag.entries[0].msg, "cannot infer comptime arguments for unwrap", m)) { return -2; }
    return 0;
}

// ---- export enforcement ----

fn i32 err_private_fn_not_visible(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nexport fn i32 f() { return b::hidden(); }", "fn i32 hidden() { return 5; }");
    test_util::frontend_modules(modules);
    if(!testing::expect_true(test_util::errors_in(modules) >= (u64)1, m)) { return -1; }
    if(!testing::expect_eq(modules[0].diag.entries[0].msg, "no member named hidden", m)) { return -2; }
    if(!testing::expect_eq(modules[0].diag.entries[0].src_pos, (u32)37, m)) { return -3; }
    return 0;
}

fn i32 err_private_struct_not_visible(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nexport fn i32 f(b::Hidden* p) { return 0; }", "struct Hidden { i32 x; }");
    test_util::frontend_modules(modules);
    if(!testing::expect_true(test_util::errors_in(modules) >= (u64)1, m)) { return -1; }
    if(!testing::expect_eq(modules[0].diag.entries[0].msg, "unknown type b::Hidden", m)) { return -2; }
    return 0;
}

fn i32 err_private_const_not_visible(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nexport fn i32 f() { return b::LIMIT; }", "const i32 LIMIT = 3;");
    test_util::frontend_modules(modules);
    if(!testing::expect_true(test_util::errors_in(modules) >= (u64)1, m)) { return -1; }
    if(!testing::expect_eq(modules[0].diag.entries[0].msg, "no member named LIMIT", m)) { return -2; }
    return 0;
}

fn i32 err_private_alias_not_visible(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nalias Local = b::Secret;\nexport fn i32 f(Local v) { return v; }", "alias Secret = i32;");
    test_util::frontend_modules(modules);
    if(!testing::expect_true(test_util::errors_in(modules) >= (u64)1, m)) { return -1; }
    if(!testing::expect_eq(modules[0].diag.entries[0].msg, "unknown type b::Secret", m)) { return -2; }
    return 0;
}

// A module's own private declarations stay reachable from inside it; export only governs the outside.
fn i32 private_decls_visible_at_home(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nexport fn i32 f() { return b::visible(); }", "const i32 LIMIT = 3;\nstruct Hidden { i32 x; }\nfn i32 hidden() { return LIMIT; }\nexport fn i32 visible() { Hidden h = {1}; return hidden() + h.x; }");
    test_util::frontend_modules(modules);
    if(!testing::expect_eq(test_util::errors_in(modules), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 main() {
    testing::init();
    const u8[] suite = "E2E Module Tests";
    testing::add(suite, "alias_to_foreign_struct",               &alias_to_foreign_struct);
    testing::add(suite, "alias_chain_across_modules",            &alias_chain_across_modules);
    testing::add(suite, "alias_to_foreign_generic_instantiation", &alias_to_foreign_generic_instantiation);
    testing::add(suite, "alias_to_foreign_fn_pointer",           &alias_to_foreign_fn_pointer);
    testing::add(suite, "circular_type_references",              &circular_type_references);
    testing::add(suite, "circular_alias_resolution",             &circular_alias_resolution);
    testing::add(suite, "circular_const_read",                   &circular_const_read);
    testing::add(suite, "err_circular_alias_definition",         &err_circular_alias_definition);
    testing::add(suite, "instantiation_identity_across_phases",  &instantiation_identity_across_phases);
    testing::add(suite, "infers_through_qualified_constructor",  &infers_through_qualified_constructor);
    testing::add(suite, "err_same_named_constructors_do_not_unify", &err_same_named_constructors_do_not_unify);
    testing::add(suite, "err_private_fn_not_visible",            &err_private_fn_not_visible);
    testing::add(suite, "err_private_struct_not_visible",        &err_private_struct_not_visible);
    testing::add(suite, "err_private_const_not_visible",         &err_private_const_not_visible);
    testing::add(suite, "err_private_alias_not_visible",         &err_private_alias_not_visible);
    testing::add(suite, "private_decls_visible_at_home",         &private_decls_visible_at_home);
    return testing::run();
}
