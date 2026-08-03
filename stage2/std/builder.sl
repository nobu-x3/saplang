// The Saplang build system: a checked-in `build.sl` exports `fn void build(builder::Build* b)`
// that constructs a DAG of steps; `saplangc build [step] [-Dopt=val]` compiles this module plus
// build.sl into a runner and executes the requested step(s). Compile steps spawn `saplangc`.
import arena;
import mem;
import list;
import sys;
import io;
import hash;

export enum Optimize : u8 {
    Debug,
    Release,
    ReleaseDebug,
    AddressSanitizer,
}

export struct Target {
    const u8[] name;   // conditional-compilation infix passed as -target; empty selects the host default
}

export enum StepKind : u8 {
    Top,       // a named `saplangc build <name>` selector; work happens in its deps
    Compile,
    Run,
}

export struct Step {
    StepKind          kind;
    const u8[]        name;         // Top: the selector; Compile/Run: informational
    const u8[]        description;  // Top: shown in --help
    list::List(Step*) deps;
    bool              done;         // executed already; dedups shared subgraphs during make
    bool              queued;       // visited already; dedups shared subgraphs during the compile gather
    mem::Allocator    allocator;
}

export struct CompileStep {
    Step             step;          // must stay first: &c.step aliases the CompileStep
    const u8[]       artifact_name;
    const u8[]       root_source;
    list::List(const u8[]) import_paths;
    list::List(const u8[]) libs;
    list::List(const u8[]) lib_dirs;
    Target           target;
    Optimize         optimize;
    bool             installed;
    Build*           owner;
}

export struct RunStep {
    Step             step;          // must stay first
    CompileStep*     exe;
    list::List(u8[]) args;
    Build*           owner;
}

struct OptionInfo {
    const u8[] name;
    const u8[] description;
    const u8[] kind;      // "bool" | "string" | "enum"
}

struct CliArg {
    const u8[] key;
    const u8[] value;
    bool has_value;
}

export struct Build {
    mem::Allocator         allocator;
    const u8[]             compiler_path;    // resolved from $SAPLANGC; the exe compile steps spawn
    Step*                  install_step;     // default top step; install_artifact hangs deps off it
    list::List(Step*)      top_steps;
    list::List(OptionInfo) options;          // declared via standard_*_options / option_*, for --help
    list::List(CliArg)     cli_args;         // parsed -Dkey=value overrides
    list::List(u8[])       requested_steps;  // bare argv tokens: which top steps to run
    list::List(const u8[]) compiler_flags;   // other -flags, passed straight through to every compile
    bool                   want_help;
    Optimize               optimize;         // resolved by standard_optimize_options
    Target                 target;           // resolved by standard_target_options
}

// ---- graph construction API ----

export fn Build* new_build(arena::Arena* a) {
    Build* b = (Build*)arena::alloc(a, sizeof(Build));
    sys::memset(b, 0, sizeof(Build));
    b.allocator = arena::allocator(a);
    return b;
}

export fn Step* step(Build* b, const u8[] name, const u8[] description) {
    Step* s = (Step*)mem::alloc(b.allocator, sizeof(Step));
    sys::memset(s, 0, sizeof(Step));
    s.kind = StepKind::Top;
    s.name = name;
    s.description = description;
    s.allocator = b.allocator;
    list::push(&b.top_steps, b.allocator, s);
    return s;
}

export fn void depend_on(Step* s, Step* dep) {
    list::push(&s.deps, s.allocator, dep);
}

export fn CompileStep* add_executable(Build* b, const u8[] name, const u8[] root_source) {
    CompileStep* c = (CompileStep*)mem::alloc(b.allocator, sizeof(CompileStep));
    sys::memset(c, 0, sizeof(CompileStep));
    c.step.kind = StepKind::Compile;
    c.step.name = name;
    c.step.allocator = b.allocator;
    c.artifact_name = name;
    c.root_source = root_source;
    c.optimize = b.optimize;   // sensible defaults; set_optimize/set_target override
    c.target = b.target;
    c.owner = b;
    return c;
}

export fn void add_import_path(CompileStep* c, const u8[] path) {
    list::push(&c.import_paths, c.owner.allocator, path);
}

export fn void link_lib(CompileStep* c, const u8[] name) {
    list::push(&c.libs, c.owner.allocator, name);
}

export fn void link_lib_dir(CompileStep* c, const u8[] path) {
    list::push(&c.lib_dirs, c.owner.allocator, path);
}

export fn void set_target(CompileStep* c, Target t) {
    c.target = t;
}

export fn void set_optimize(CompileStep* c, Optimize o) {
    c.optimize = o;
}

export fn void install_artifact(Build* b, CompileStep* c) {
    c.installed = true;
    list::push(&b.install_step.deps, b.allocator, &c.step);
}

export fn RunStep* add_run_artifact(Build* b, CompileStep* c) {
    RunStep* r = (RunStep*)mem::alloc(b.allocator, sizeof(RunStep));
    sys::memset(r, 0, sizeof(RunStep));
    r.step.kind = StepKind::Run;
    r.step.name = c.artifact_name;
    r.step.allocator = b.allocator;
    r.exe = c;
    r.owner = b;
    list::push(&r.step.deps, b.allocator, &c.step);
    return r;
}

export fn void run_arg(RunStep* r, u8[] arg) {
    list::push(&r.args, r.owner.allocator, arg);
}

// ---- options ----

fn void declare_option(Build* b, const u8[] name, const u8[] description, const u8[] kind) {
    OptionInfo o;
    o.name = name;
    o.description = description;
    o.kind = kind;
    list::push(&b.options, b.allocator, o);
}

// Records a parsed CLI override; the runner calls this while scanning argv.
export fn void define(Build* b, const u8[] key, const u8[] value, bool has_value) {
    CliArg a;
    a.key = key;
    a.value = value;
    a.has_value = has_value;
    list::push(&b.cli_args, b.allocator, a);
}

fn CliArg* find_cli(Build* b, const u8[] key) {
    for(u64 arg_index = 0; arg_index < b.cli_args.len; arg_index += 1) {
        if(slice_eq(b.cli_args.ptr[arg_index].key, key)) { return &b.cli_args.ptr[arg_index]; }
    }
    return null;
}

export fn Optimize standard_optimize_options(Build* b) {
    declare_option(b, "optimize", "Optimization/instrumentation: Debug|Release|ReleaseDebug|AddressSanitizer", "enum");
    Optimize o = Optimize::Debug;
    CliArg* a = find_cli(b, "optimize");
    if(a != null && a.has_value) { o = parse_optimize(a.value); }
    b.optimize = o;
    return o;
}

export fn Target standard_target_options(Build* b) {
    declare_option(b, "target", "Target platform infix for conditional compilation", "string");
    Target t;
    t.name = empty_slice();
    CliArg* a = find_cli(b, "target");
    if(a != null && a.has_value) { t.name = a.value; }
    b.target = t;
    return t;
}

export fn bool option_bool(Build* b, const u8[] name, const u8[] description) {
    declare_option(b, name, description, "bool");
    CliArg* a = find_cli(b, name);
    if(a == null) { return false; }
    if(!a.has_value) { return true; }   // bare -Dflag means true
    return slice_eq(a.value, "true") || slice_eq(a.value, "1");
}

export fn const u8[] option_string(Build* b, const u8[] name, const u8[] description) {
    declare_option(b, name, description, "string");
    CliArg* a = find_cli(b, name);
    if(a != null && a.has_value) { return a.value; }
    return empty_slice();
}

fn Optimize parse_optimize(const u8[] name) {
    if(slice_eq(name, "Debug"))            { return Optimize::Debug; }
    if(slice_eq(name, "Release"))          { return Optimize::Release; }
    if(slice_eq(name, "ReleaseDebug"))     { return Optimize::ReleaseDebug; }
    if(slice_eq(name, "AddressSanitizer")) { return Optimize::AddressSanitizer; }
    sys::dprintf(2, "warning: unknown -Doptimize=%.*s, using Debug\n", (i32)name.len, (i8*)name.ptr);
    return Optimize::Debug;
}

fn const u8[] optimize_name(Optimize o) {
    switch(o) {
    case Optimize::Debug:            { return "Debug"; }
    case Optimize::Release:          { return "Release"; }
    case Optimize::ReleaseDebug:     { return "ReleaseDebug"; }
    case Optimize::AddressSanitizer: { return "AddressSanitizer"; }
    else                             { return "Debug"; }
    }
}

// ---- path resolution ----

// Installed artifacts land in sap-out/bin/; transient ones (run-only) in .sap-cache/.
export fn u8[] artifact_path(Build* b, CompileStep* c) {
    if(c.installed) { return join(b.allocator, "sap-out/bin/", c.artifact_name); }
    return join(b.allocator, ".sap-cache/", c.artifact_name);
}

fn void ensure_output_dir(Build* b, CompileStep* c) {
    if(c.installed) {
        sys::mkdir(cstr(b.allocator, "sap-out"), 493);
        sys::mkdir(cstr(b.allocator, "sap-out/bin"), 493);
    } else {
        sys::mkdir(cstr(b.allocator, ".sap-cache"), 493);
    }
}

// ---- content-hash caching ----
//
// A compile is skipped when its output still exists and the stamp matches a fresh hash over the
// command flags plus the contents of every source the last compile actually read (the `-deps`
// depfile). Editing the root or any imported module changes that hash and forces a rebuild.

fn u8[] cache_sidecar(Build* b, const u8[] name, const u8[] ext) {
    io::OutBuf buf;
    io::outbuf_init(&buf, b.allocator, 32);
    io::outbuf_write(&buf, ".sap-cache/");
    io::outbuf_write(&buf, name);
    io::outbuf_write(&buf, ext);
    return io::outbuf_bytes(&buf);
}

fn bool file_exists(const u8[] path) {
    io::File f = io::open(path, "r");
    if(f.fp == null) { return false; }
    io::close(&f);
    return true;
}

// The stamp for the current on-disk inputs, or empty if the depfile is missing or a listed
// source has since vanished (either case means "not fresh, must rebuild").
fn const u8[] compute_stamp(Build* b, CompileStep* c) {
    io::File df = io::open(cache_sidecar(b, c.artifact_name, ".dep"), "r");
    if(df.fp == null) { return empty_slice(); }
    u8[] listing = io::read_all(&df, b.allocator);
    io::close(&df);

    io::OutBuf buf;
    io::outbuf_init(&buf, b.allocator, 4096);
    io::outbuf_write(&buf, compile_command_string(b, c));
    io::outbuf_write_byte(&buf, '\n');
    u64 start = 0;
    for(u64 char_index = 0; char_index <= listing.len; char_index += 1) {
        if(char_index == listing.len || listing[char_index] == '\n') {
            if(char_index > start) {
                u8[] path = {&listing.ptr[start], char_index - start};
                io::File sf = io::open(path, "r");
                if(sf.fp == null) { return empty_slice(); }
                io::outbuf_write(&buf, io::read_all(&sf, b.allocator));
                io::close(&sf);
            }
            start = char_index + 1;
        }
    }
    u64 h = hash::fnv1a_64(io::outbuf_bytes(&buf));
    io::OutBuf hb;
    io::outbuf_init(&hb, b.allocator, 24);
    io::outbuf_write_u64(&hb, h);
    return io::outbuf_bytes(&hb);
}

fn bool is_fresh(Build* b, CompileStep* c, const u8[] out) {
    if(!file_exists(out)) { return false; }
    io::File sf = io::open(cache_sidecar(b, c.artifact_name, ".stamp"), "r");
    if(sf.fp == null) { return false; }
    u8[] stored = io::read_all(&sf, b.allocator);
    io::close(&sf);
    const u8[] current = compute_stamp(b, c);
    if(current.len == 0) { return false; }
    return slice_eq(stored, current);
}

fn void write_stamp(Build* b, CompileStep* c) {
    const u8[] current = compute_stamp(b, c);
    if(current.len == 0) { return; }
    io::File f = io::open(cache_sidecar(b, c.artifact_name, ".stamp"), "w");
    if(f.fp == null) { return; }
    io::write_string(&f, current);
    io::close(&f);
}

// The exact `saplangc` invocation a compile step runs, space-joined; also used by --help/tests.
export fn u8[] compile_command_string(Build* b, CompileStep* c) {
    io::OutBuf buf;
    io::outbuf_init(&buf, b.allocator, 128);
    io::outbuf_write(&buf, b.compiler_path);
    io::outbuf_write_byte(&buf, ' ');
    io::outbuf_write(&buf, c.root_source);
    io::outbuf_write(&buf, " -o ");
    io::outbuf_write(&buf, artifact_path(b, c));
    if(c.import_paths.len > 0) {
        io::outbuf_write(&buf, " -i ");
        io::outbuf_write(&buf, join_semicolons(b.allocator, &c.import_paths));
    }
    for(u64 lib_index = 0; lib_index < c.libs.len; lib_index += 1) {
        io::outbuf_write(&buf, " -l ");
        io::outbuf_write(&buf, c.libs.ptr[lib_index]);
    }
    for(u64 dir_index = 0; dir_index < c.lib_dirs.len; dir_index += 1) {
        io::outbuf_write(&buf, " -L ");
        io::outbuf_write(&buf, c.lib_dirs.ptr[dir_index]);
    }
    if(c.target.name.len > 0) {
        io::outbuf_write(&buf, " -target ");
        io::outbuf_write(&buf, c.target.name);
    }
    io::outbuf_write(&buf, " -config ");
    io::outbuf_write(&buf, optimize_name(c.optimize));
    for(u64 cli_index = 0; cli_index < b.cli_args.len; cli_index += 1) {
        CliArg* a = &b.cli_args.ptr[cli_index];
        if(is_forwarded_define(a)) {
            io::outbuf_write_byte(&buf, ' ');
            io::outbuf_write(&buf, define_arg(b, a));
        }
    }
    for(u64 flag_index = 0; flag_index < b.compiler_flags.len; flag_index += 1) {
        io::outbuf_write_byte(&buf, ' ');
        io::outbuf_write(&buf, b.compiler_flags.ptr[flag_index]);
    }
    return io::outbuf_bytes(&buf);
}

// `optimize` and `target` already reach the compiler as -config/-target.
fn bool is_forwarded_define(CliArg* a) {
    return !slice_eq(a.key, "optimize") && !slice_eq(a.key, "target");
}

// These the build graph decides per step; taking one from argv would silently fight build.sl.
// -config / -target are reachable as -Doptimize= / -Dtarget=.
fn bool is_build_owned_flag(const u8[] arg) {
    return slice_eq(arg, "-o") || slice_eq(arg, "-i") || slice_eq(arg, "-l") || slice_eq(arg, "-L")
        || slice_eq(arg, "-c") || slice_eq(arg, "-deps") || slice_eq(arg, "-config") || slice_eq(arg, "-target");
}

fn u8[] define_arg(Build* b, CliArg* a) {
    io::OutBuf buf;
    io::outbuf_init(&buf, b.allocator, 32);
    io::outbuf_write(&buf, "-D");
    io::outbuf_write(&buf, a.key);
    if(a.has_value) {
        io::outbuf_write_byte(&buf, '=');
        io::outbuf_write(&buf, a.value);
    }
    return io::outbuf_bytes(&buf);
}

fn i8** build_compile_argv(Build* b, CompileStep* c, u8[] out) {
    u64 cap = 12 + c.libs.len * 2 + c.lib_dirs.len * 2 + b.cli_args.len + b.compiler_flags.len;
    i8** argv = (i8**)mem::alloc(b.allocator, (cap + 1) * sizeof(i8*));
    u64 n = 0;
    argv[n] = cstr(b.allocator, b.compiler_path); n += 1;
    argv[n] = cstr(b.allocator, c.root_source);   n += 1;
    argv[n] = cstr(b.allocator, "-o");            n += 1;
    argv[n] = cstr(b.allocator, out);             n += 1;
    if(c.import_paths.len > 0) {
        argv[n] = cstr(b.allocator, "-i");                                n += 1;
        argv[n] = cstr(b.allocator, join_semicolons(b.allocator, &c.import_paths)); n += 1;
    }
    for(u64 lib_index = 0; lib_index < c.libs.len; lib_index += 1) {
        argv[n] = cstr(b.allocator, "-l");                   n += 1;
        argv[n] = cstr(b.allocator, c.libs.ptr[lib_index]);  n += 1;
    }
    for(u64 dir_index = 0; dir_index < c.lib_dirs.len; dir_index += 1) {
        argv[n] = cstr(b.allocator, "-L");                       n += 1;
        argv[n] = cstr(b.allocator, c.lib_dirs.ptr[dir_index]);  n += 1;
    }
    if(c.target.name.len > 0) {
        argv[n] = cstr(b.allocator, "-target");       n += 1;
        argv[n] = cstr(b.allocator, c.target.name);   n += 1;
    }
    argv[n] = cstr(b.allocator, "-deps");                              n += 1;
    argv[n] = cstr(b.allocator, cache_sidecar(b, c.artifact_name, ".dep")); n += 1;
    argv[n] = cstr(b.allocator, "-config");                  n += 1;
    argv[n] = cstr(b.allocator, optimize_name(c.optimize));  n += 1;
    for(u64 cli_index = 0; cli_index < b.cli_args.len; cli_index += 1) {
        CliArg* a = &b.cli_args.ptr[cli_index];
        if(is_forwarded_define(a)) { argv[n] = cstr(b.allocator, define_arg(b, a)); n += 1; }
    }
    for(u64 flag_index = 0; flag_index < b.compiler_flags.len; flag_index += 1) {
        argv[n] = cstr(b.allocator, b.compiler_flags.ptr[flag_index]); n += 1;
    }
    argv[n] = null;
    return argv;
}

// ---- execution ----

export fn i32 run(i32 argc, u8** argv, fn* void(Build*) build_fn) {
    arena::Arena arena;
    sys::memset(&arena, 0, sizeof(arena::Arena));
    arena.default_page_size = 262144;

    Build* b = new_build(&arena);
    b.compiler_path = resolve_compiler_path(b.allocator);
    b.install_step = step(b, "install", "Copy build artifacts into sap-out/");

    for(i32 arg_index = 1; arg_index < argc; arg_index += 1) {
        u8[] arg = cstr_slice(argv[arg_index]);
        if(slice_eq(arg, "--help") || slice_eq(arg, "-h")) {
            b.want_help = true;
        } else if(starts_with(arg, "-D")) {
            parse_define_arg(b, arg);
        } else if(starts_with(arg, "-")) {
            if(is_build_owned_flag(arg)) {
                sys::dprintf(2, "error: %.*s is set by build.sl, not on the command line\n", (i32)arg.len, (i8*)arg.ptr);
                return 1;
            }
            const u8[] flag = arg;   // List(const u8[]) cannot infer its element from a u8[] argument
            list::push(&b.compiler_flags, b.allocator, flag);
        } else {
            list::push(&b.requested_steps, b.allocator, arg);
        }
    }

    build_fn(b);

    if(b.want_help) { print_help(b); return 0; }

    list::List(Step*) roots;
    roots.ptr = null; roots.len = 0; roots.cap = 0;
    if(b.requested_steps.len == 0) {
        list::push(&roots, b.allocator, b.install_step);
    } else {
        for(u64 step_index = 0; step_index < b.requested_steps.len; step_index += 1) {
            u8[] name = b.requested_steps.ptr[step_index];
            Step* s = resolve_step(b, name);
            if(s == null) {
                sys::dprintf(2, "error: no step named '%.*s' (run `saplangc build --help`)\n", (i32)name.len, (i8*)name.ptr);
                return 1;
            }
            list::push(&roots, b.allocator, s);
        }
    }

    // Compile steps are mutually independent, so build them all concurrently up front; only then
    // does the sequential make phase run the dependent run/install steps (compiles already done).
    list::List(CompileStep*) compiles;
    compiles.ptr = null; compiles.len = 0; compiles.cap = 0;
    for(u64 root_index = 0; root_index < roots.len; root_index += 1) {
        collect_compiles(roots.ptr[root_index], &compiles, b.allocator);
    }
    i32 crc = run_compiles_parallel(b, &compiles);
    if(crc != 0) { return crc; }

    for(u64 root_index = 0; root_index < roots.len; root_index += 1) {
        i32 rc = make(b, roots.ptr[root_index]);
        if(rc != 0) { return rc; }
    }
    return 0;
}

// Gathers every reachable Compile step once (queued dedups shared subgraphs).
export fn void collect_compiles(Step* s, list::List(CompileStep*)* out, mem::Allocator a) {
    if(s.queued) { return; }
    s.queued = true;
    for(u64 dep_index = 0; dep_index < s.deps.len; dep_index += 1) {
        collect_compiles(s.deps.ptr[dep_index], out, a);
    }
    if(s.kind == StepKind::Compile) { list::push(out, a, (CompileStep*)s); }
}

// Bounded-parallel compile: up to cpu_count subprocesses in flight; a fresh cache entry skips one.
fn i32 run_compiles_parallel(Build* b, list::List(CompileStep*)* compiles) {
    u64 workers = (u64)sys::cpu_count();
    if(workers == 0) { workers = 1; }
    i32* pids = (i32*)mem::alloc(b.allocator, workers * sizeof(i32));
    CompileStep** running = (CompileStep**)mem::alloc(b.allocator, workers * sizeof(CompileStep*));
    for(u64 slot = 0; slot < workers; slot += 1) { pids[slot] = 0; running[slot] = null; }

    u64 next = 0;
    u64 inflight = 0;
    i32 first_err = 0;
    while(true) {
        while(first_err == 0 && inflight < workers && next < compiles.len) {
            CompileStep* c = compiles.ptr[next];
            next += 1;
            u8[] out = artifact_path(b, c);
            ensure_output_dir(b, c);
            sys::mkdir(cstr(b.allocator, ".sap-cache"), 493);
            if(is_fresh(b, c, out)) {
                sys::dprintf(1, "  CACHED %.*s\n", (i32)c.artifact_name.len, (i8*)c.artifact_name.ptr);
                c.step.done = true;
                continue;
            }
            sys::dprintf(1, "  CC   %.*s -> %.*s\n", (i32)c.root_source.len, (i8*)c.root_source.ptr, (i32)out.len, (i8*)out.ptr);
            i32 pid = fork_compile(b, c, out);
            if(pid < 0) {
                sys::dprintf(2, "error: fork failed for '%.*s'\n", (i32)c.artifact_name.len, (i8*)c.artifact_name.ptr);
                if(first_err == 0) { first_err = -1; }
                continue;
            }
            u64 slot = 0;
            while(slot < workers && pids[slot] != 0) { slot += 1; }
            pids[slot] = pid;
            running[slot] = c;
            inflight += 1;
        }
        if(inflight == 0) { break; }
        i32 status = 0;
        i32 done_pid = sys::waitpid(-1, &status, 0);
        i32 rc = (status >> 8) & 255;
        u64 slot = 0;
        while(slot < workers && pids[slot] != done_pid) { slot += 1; }
        if(slot < workers) {
            CompileStep* c = running[slot];
            pids[slot] = 0;
            running[slot] = null;
            inflight -= 1;
            if(rc != 0) {
                sys::dprintf(2, "error: compiling '%.*s' failed\n", (i32)c.artifact_name.len, (i8*)c.artifact_name.ptr);
                if(first_err == 0) { first_err = rc; }
            } else {
                write_stamp(b, c);
                c.step.done = true;
            }
        }
    }
    return first_err;
}

fn i32 fork_compile(Build* b, CompileStep* c, u8[] out) {
    i8** argv = build_compile_argv(b, c, out);
    i32 pid = sys::fork();
    if(pid == 0) {
        sys::execvp(argv[0], argv);
        sys::_exit(127);
    }
    return pid;
}

export fn Step* resolve_step(Build* b, const u8[] name) {
    for(u64 step_index = 0; step_index < b.top_steps.len; step_index += 1) {
        if(slice_eq(b.top_steps.ptr[step_index].name, name)) { return b.top_steps.ptr[step_index]; }
    }
    return null;
}

fn i32 make(Build* b, Step* s) {
    if(s.done) { return 0; }
    s.done = true;
    for(u64 dep_index = 0; dep_index < s.deps.len; dep_index += 1) {
        i32 rc = make(b, s.deps.ptr[dep_index]);
        if(rc != 0) { return rc; }
    }
    switch(s.kind) {
    case StepKind::Compile: { return make_compile(b, (CompileStep*)s); }
    case StepKind::Run:     { return make_run(b, (RunStep*)s); }
    else                    { return 0; }   // Top: its deps did the work
    }
}

fn i32 make_compile(Build* b, CompileStep* c) {
    u8[] out = artifact_path(b, c);
    ensure_output_dir(b, c);
    sys::mkdir(cstr(b.allocator, ".sap-cache"), 493);
    if(is_fresh(b, c, out)) {
        sys::dprintf(1, "  CACHED %.*s\n", (i32)c.artifact_name.len, (i8*)c.artifact_name.ptr);
        return 0;
    }
    sys::dprintf(1, "  CC   %.*s -> %.*s\n", (i32)c.root_source.len, (i8*)c.root_source.ptr, (i32)out.len, (i8*)out.ptr);
    i8** argv = build_compile_argv(b, c, out);
    i32 rc = spawn_and_wait(argv);
    if(rc != 0) {
        sys::dprintf(2, "error: compiling '%.*s' failed\n", (i32)c.artifact_name.len, (i8*)c.artifact_name.ptr);
        return rc;
    }
    write_stamp(b, c);
    return 0;
}

fn i32 make_run(Build* b, RunStep* r) {
    u8[] path = artifact_path(b, r.exe);
    i8** argv = (i8**)mem::alloc(b.allocator, (r.args.len + 2) * sizeof(i8*));
    u64 n = 0;
    argv[n] = cstr(b.allocator, path); n += 1;
    for(u64 arg_index = 0; arg_index < r.args.len; arg_index += 1) { argv[n] = cstr(b.allocator, r.args.ptr[arg_index]); n += 1; }
    argv[n] = null;
    sys::dprintf(1, "  RUN  %.*s\n", (i32)path.len, (i8*)path.ptr);
    return spawn_and_wait(argv);
}

fn void print_help(Build* b) {
    sys::dprintf(1, "Usage: saplangc build [step]... [-Doption=value]... [compiler flag]...\n");
    sys::dprintf(1, "Any other -flag (e.g. -show-timings, -mt) is passed to every compile.\n\n");
    sys::dprintf(1, "Steps:\n");
    for(u64 step_index = 0; step_index < b.top_steps.len; step_index += 1) {
        Step* s = b.top_steps.ptr[step_index];
        sys::dprintf(1, "  %.*s  -  %.*s\n", (i32)s.name.len, (i8*)s.name.ptr, (i32)s.description.len, (i8*)s.description.ptr);
    }
    sys::dprintf(1, "\nProject options:\n");
    for(u64 option_index = 0; option_index < b.options.len; option_index += 1) {
        OptionInfo* o = &b.options.ptr[option_index];
        sys::dprintf(1, "  -D%.*s  -  %.*s\n", (i32)o.name.len, (i8*)o.name.ptr, (i32)o.description.len, (i8*)o.description.ptr);
    }
}

// ---- small helpers ----

fn void parse_define_arg(Build* b, const u8[] arg) {
    u8[] body = {&arg.ptr[2], arg.len - 2};   // strip -D
    u64 eq = body.len;
    for(u64 char_index = 0; char_index < body.len; char_index += 1) {
        if(body[char_index] == '=') { eq = char_index; break; }
    }
    if(eq == body.len) {
        define(b, body, empty_slice(), false);
        return;
    }
    u8[] key = {body.ptr, eq};
    u8[] value = {&body.ptr[eq + 1], body.len - eq - 1};
    define(b, key, value, true);
}

fn const u8[] resolve_compiler_path(mem::Allocator a) {
    i8* raw = sys::getenv(cstr(a, "SAPLANGC"));
    if(raw == null) { return "saplangc"; }
    return cstr_slice((u8*)raw);
}

fn i32 spawn_and_wait(i8** argv) {
    i32 pid = sys::fork();
    if(pid < 0) { return -1; }
    if(pid == 0) {
        sys::execvp(argv[0], argv);
        sys::_exit(127);
        return 127;
    }
    i32 status = 0;
    sys::waitpid(pid, &status, 0);
    return (status >> 8) & 255;
}

fn u8[] join_semicolons(mem::Allocator a, list::List(const u8[])* parts) {
    io::OutBuf buf;
    io::outbuf_init(&buf, a, 64);
    for(u64 part_index = 0; part_index < parts.len; part_index += 1) {
        if(part_index > 0) { io::outbuf_write_byte(&buf, ';'); }
        io::outbuf_write(&buf, parts.ptr[part_index]);
    }
    return io::outbuf_bytes(&buf);
}

fn u8[] join(mem::Allocator a, const u8[] prefix, const u8[] name) {
    io::OutBuf buf;
    io::outbuf_init(&buf, a, prefix.len + name.len + 1);
    io::outbuf_write(&buf, prefix);
    io::outbuf_write(&buf, name);
    return io::outbuf_bytes(&buf);
}

fn i8* cstr(mem::Allocator a, const u8[] bytes) {
    i8* out = (i8*)mem::alloc(a, bytes.len + 1);
    for(u64 char_index = 0; char_index < bytes.len; char_index += 1) { out[char_index] = (i8)bytes[char_index]; }
    out[bytes.len] = 0;
    return out;
}

fn u8[] cstr_slice(u8* s) {
    u64 len = 0;
    while(s[len] != 0) { len += 1; }
    u8[] out = {s, len};
    return out;
}

fn const u8[] empty_slice() {
    u8[] e = {null, 0};
    return e;
}

fn bool slice_eq(const u8[] a, const u8[] b) {
    if(a.len != b.len) { return false; }
    for(u64 char_index = 0; char_index < a.len; char_index += 1) {
        if(a[char_index] != b[char_index]) { return false; }
    }
    return true;
}

fn bool starts_with(const u8[] s, const u8[] prefix) {
    if(prefix.len > s.len) { return false; }
    for(u64 char_index = 0; char_index < prefix.len; char_index += 1) {
        if(s[char_index] != prefix[char_index]) { return false; }
    }
    return true;
}
