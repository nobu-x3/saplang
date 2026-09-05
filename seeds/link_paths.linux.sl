// Probing link configuration for the stage2-v0 and stage2-generic-structs seeds, whose own
// link_paths.linux.sl hardcodes a flat /usr/lib layout and so cannot link on a multiarch
// distribution. bootstrap.sh copies this over the worktree copy when building those tags;
// stage2-v1 onwards probe for themselves and are left alone.
//
// Those seeds predate the allocator-passing stdlib, so the five entry points take no arguments
// and cannot build a path at run time. Every candidate is therefore spelled out as a literal and
// selected by probing, which keeps the returned strings NUL-terminated and ready for the linker
// argv. Candidates match the order the current tree probes in.
import io;

export fn i8* dynamic_linker() {
    if(file_exists("/lib64/ld-linux-x86-64.so.2"))            { return "/lib64/ld-linux-x86-64.so.2"; }
    if(file_exists("/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2")) { return "/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"; }
    return "/usr/lib/ld-linux-x86-64.so.2";
}

export fn i8* crt_start() {
    u64 dir = crt_dir();
    if(dir == 1) { return "/usr/lib/x86_64-linux-gnu/Scrt1.o"; }
    if(dir == 2) { return "/usr/lib64/Scrt1.o"; }
    if(dir == 3) { return "/lib/x86_64-linux-gnu/Scrt1.o"; }
    return "/usr/lib/Scrt1.o";
}

export fn i8* crt_init() {
    u64 dir = crt_dir();
    if(dir == 1) { return "/usr/lib/x86_64-linux-gnu/crti.o"; }
    if(dir == 2) { return "/usr/lib64/crti.o"; }
    if(dir == 3) { return "/lib/x86_64-linux-gnu/crti.o"; }
    return "/usr/lib/crti.o";
}

export fn i8* crt_fini() {
    u64 dir = crt_dir();
    if(dir == 1) { return "/usr/lib/x86_64-linux-gnu/crtn.o"; }
    if(dir == 2) { return "/usr/lib64/crtn.o"; }
    if(dir == 3) { return "/lib/x86_64-linux-gnu/crtn.o"; }
    return "/usr/lib/crtn.o";
}

// The C runtime directory also holds libc and the LLVM shared library the compiler links against.
export fn i8* lib_search_dir() {
    u64 dir = crt_dir();
    if(dir == 1) { return "-L/usr/lib/x86_64-linux-gnu"; }
    if(dir == 2) { return "-L/usr/lib64"; }
    if(dir == 3) { return "-L/lib/x86_64-linux-gnu"; }
    return "-L/usr/lib";
}

// Scrt1.o, crti.o and crtn.o ship together, so one probe locates all three.
fn u64 crt_dir() {
    if(file_exists("/usr/lib/Scrt1.o"))                  { return 0; }
    if(file_exists("/usr/lib/x86_64-linux-gnu/Scrt1.o")) { return 1; }
    if(file_exists("/usr/lib64/Scrt1.o"))                { return 2; }
    if(file_exists("/lib/x86_64-linux-gnu/Scrt1.o"))     { return 3; }
    return 0;
}

fn bool file_exists(u8[] path) {
    io::File probe = io::open(path, "r");
    if(probe.fp == null) { return false; }
    io::close(&probe);
    return true;
}
