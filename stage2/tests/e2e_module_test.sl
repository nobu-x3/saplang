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

// ---- foreign enums and constants at comptime ----

// The reported shape: alias a foreign enum, then qualify a member through the alias as an array size.
fn i32 alias_to_foreign_enum_namespace(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nalias SomeEnum = b::SomeEnum;\nexport fn i32 f() { u32[SomeEnum::LENGTH] arr; arr[2] = 1; return (i32)arr[2]; }", "export enum SomeEnum { a, b, c, LENGTH }");
    test_util::frontend_modules(modules);
    if(!testing::expect_eq(test_util::errors_in(modules), (u64)0, m)) { return -1; }
    return 0;
}

fn i32 foreign_enum_member_as_array_size(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nexport fn i32 f() { u32[b::SomeEnum::LENGTH] arr; arr[2] = 1; return (i32)arr[2]; }", "export enum SomeEnum { a, b, c, LENGTH }");
    test_util::frontend_modules(modules);
    if(!testing::expect_eq(test_util::errors_in(modules), (u64)0, m)) { return -1; }
    return 0;
}

// An imported constant folds at comptime, including one derived from another of its module's constants.
fn i32 foreign_const_as_array_size(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nexport fn i32 f() { u32[b::SIZE] one; u32[b::DOUBLE] two; u32[b::SIZE * 2] three; one[3] = 1; two[7] = 1; three[7] = 1; return (i32)(one[3] + two[7] + three[7]); }", "export const u64 SIZE = 4;\nexport const u64 DOUBLE = SIZE * 2;");
    test_util::frontend_modules(modules);
    if(!testing::expect_eq(test_util::errors_in(modules), (u64)0, m)) { return -1; }
    return 0;
}

// A private enum cannot be aliased across the boundary, so the alias itself is what fails.
fn i32 err_alias_to_private_foreign_enum(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nalias H = b::Hidden;\nexport fn i32 f() { return (i32)H::x; }", "enum Hidden { x, y }");
    test_util::frontend_modules(modules);
    if(!testing::expect_true(test_util::errors_in(modules) >= (u64)1, m)) { return -1; }
    if(!testing::expect_eq(modules[0].diag.entries[0].msg, "unknown type b::Hidden", m)) { return -2; }
    return 0;
}

// ---- comptime type params across modules ----

// A generic passing its own comptime T on as a type argument: the call arg parses as an expression,
// so the clone only resolves if substitution rewrote that ident into the bound type.
fn i32 generic_forwards_type_param_across_modules(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nexport fn i32 f() { u32 v = 3; return (i32)b::outer(v); }", "export fn u64 width(comptime Type T) { return sizeof(T); }\nexport fn u64 outer(comptime Type T, T value) { return width(T); }");
    test_util::frontend_modules(modules);
    if(!testing::expect_eq(test_util::errors_in(modules), (u64)0, m)) { return -1; }
    return 0;
}

// The type argument names a private type of the generic's own module, so it resolves there, not at the call site.
fn i32 generic_type_arg_resolves_in_home_module(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nexport fn i32 f() { u32 v = 3; return (i32)b::outer(v); }", "struct Local { i32 x; i32 y; }\nexport fn u64 width(comptime Type T) { return sizeof(T); }\nexport fn u64 outer(comptime Type T, T value) { return width(Local); }");
    test_util::frontend_modules(modules);
    if(!testing::expect_eq(test_util::errors_in(modules), (u64)0, m)) { return -1; }
    return 0;
}

// ---- diagnostics from foreign source keep their own module ----

// A clone is checked in the instantiating module but its nodes are the template's, so the error carries
// b as its origin and the caller's note carries a; rendering both against a printed nonsense positions.
fn i32 err_clone_error_carries_the_generic_module(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nexport fn i32 f() { u32 v = 3; return (i32)b::outer(v); }", "export fn u64 outer(comptime Type T, T value) { return missing(value); }");
    test_util::frontend_modules(modules);
    if(!testing::expect_eq(test_util::errors_in(modules), (u64)2, m)) { return -1; }
    if(!testing::expect_eq(modules[0].diag.entries[0].msg, "undefined identifier missing", m)) { return -2; }
    if(!testing::expect_eq(modules[0].diag.entries[0].origin, (void*)modules[1], m)) { return -3; }
    if(!testing::expect_eq(modules[0].diag.entries[0].src_pos, (u32)55, m)) { return -4; }
    if(!testing::expect_eq(modules[0].diag.entries[1].msg, "in instantiation of outer requested here", m)) { return -5; }
    if(!testing::expect_eq(modules[0].diag.entries[1].origin, (void*)modules[0], m)) { return -6; }
    if(!testing::expect_eq(modules[0].diag.entries[1].src_pos, (u32)61, m)) { return -7; }
    return 0;
}

fn i32 err_clone_cfg_diagnostic_carries_the_generic_module(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nexport fn i32 f() { u32 v = 3; return (i32)b::pick(v); }", "export fn u64 pick(comptime Type T, T value) { if(sizeof(T) > 2) { return 1; } }");
    test_util::frontend_modules(modules);
    if(!testing::expect_eq(modules[0].diag.entries[0].msg, "function may exit without a return statement", m)) { return -1; }
    if(!testing::expect_eq(modules[0].diag.entries[0].origin, (void*)modules[1], m)) { return -2; }
    if(!testing::expect_eq(modules[0].diag.entries[0].src_pos, (u32)7, m)) { return -3; }
    return 0;
}

// Warnings travel the same way as errors; a clone's dead code is dead in b's source.
fn i32 clone_warning_carries_the_generic_module(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\nexport fn i32 f() { u32 v = 3; return (i32)b::early(v); }", "export fn u64 early(comptime Type T, T value) { return sizeof(T); u64 dead = 1; return dead; }");
    test_util::frontend_modules(modules);
    if(!testing::expect_eq(test_util::errors_in(modules), (u64)0, m)) { return -1; }
    if(!testing::expect_eq(test_util::warning_count(modules[0]), (u64)1, m)) { return -2; }
    if(!testing::expect_eq(modules[0].diag.entries[0].msg, "unreachable code", m)) { return -3; }
    if(!testing::expect_eq(modules[0].diag.entries[0].origin, (void*)modules[1], m)) { return -4; }
    if(!testing::expect_eq(modules[0].diag.entries[0].src_pos, (u32)66, m)) { return -5; }
    return 0;
}

// A body checked on demand for a comptime call reports into the requester's buffer, still pointing at b.
fn i32 err_on_demand_body_check_carries_the_callee_module(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\ncomprun { u64 v = b::bad(1); }\nexport fn i32 f() { return 0; }", "export fn u64 bad(u64 x) { return nope; }");
    test_util::frontend_modules(modules);
    if(!testing::expect_true(test_util::errors_in(modules) >= (u64)1, m)) { return -1; }
    if(!testing::expect_eq(modules[0].diag.entries[0].msg, "undefined identifier nope", m)) { return -2; }
    if(!testing::expect_eq(modules[0].diag.entries[0].origin, (void*)modules[1], m)) { return -3; }
    if(!testing::expect_eq(modules[0].diag.entries[0].src_pos, (u32)34, m)) { return -4; }
    return 0;
}

// The interpreter runs a foreign body on the caller's thread; the fault is at b's division, not in a.
fn i32 err_foreign_comptime_diagnostic_carries_the_callee_module(arena::Arena* a, const u8[]m) {
    test_util::boot(a);
    module::Module*[] modules = pair(a, "import b;\ncomprun { u64 v = b::half(0); }\nexport fn i32 f() { return 0; }", "export fn u64 half(u64 x) { return 100 / x; }");
    test_util::frontend_modules(modules);
    if(!testing::expect_true(test_util::errors_in(modules) >= (u64)1, m)) { return -1; }
    if(!testing::expect_eq(modules[0].diag.entries[0].msg, "division by zero at comptime", m)) { return -2; }
    if(!testing::expect_eq(modules[0].diag.entries[0].origin, (void*)modules[1], m)) { return -3; }
    if(!testing::expect_eq(modules[0].diag.entries[0].src_pos, (u32)39, m)) { return -4; }
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
    testing::add(suite, "alias_to_foreign_enum_namespace",       &alias_to_foreign_enum_namespace);
    testing::add(suite, "foreign_enum_member_as_array_size",     &foreign_enum_member_as_array_size);
    testing::add(suite, "foreign_const_as_array_size",           &foreign_const_as_array_size);
    testing::add(suite, "err_alias_to_private_foreign_enum",     &err_alias_to_private_foreign_enum);
    testing::add(suite, "generic_forwards_type_param_across_modules", &generic_forwards_type_param_across_modules);
    testing::add(suite, "generic_type_arg_resolves_in_home_module", &generic_type_arg_resolves_in_home_module);
    testing::add(suite, "err_clone_error_carries_the_generic_module", &err_clone_error_carries_the_generic_module);
    testing::add(suite, "err_clone_cfg_diagnostic_carries_the_generic_module", &err_clone_cfg_diagnostic_carries_the_generic_module);
    testing::add(suite, "clone_warning_carries_the_generic_module", &clone_warning_carries_the_generic_module);
    testing::add(suite, "err_on_demand_body_check_carries_the_callee_module", &err_on_demand_body_check_carries_the_callee_module);
    testing::add(suite, "err_foreign_comptime_diagnostic_carries_the_callee_module", &err_foreign_comptime_diagnostic_carries_the_callee_module);
    testing::add(suite, "err_private_fn_not_visible",            &err_private_fn_not_visible);
    testing::add(suite, "err_private_struct_not_visible",        &err_private_struct_not_visible);
    testing::add(suite, "err_private_const_not_visible",         &err_private_const_not_visible);
    testing::add(suite, "err_private_alias_not_visible",         &err_private_alias_not_visible);
    testing::add(suite, "private_decls_visible_at_home",         &private_decls_visible_at_home);
    return testing::run();
}
