// x86-64 Linux glibc link configuration for the ld.lld step. v0 hardcodes
// these paths; per-target link_paths_<triple>.sl and a -link-config override
// arrive with the build system. Values are NUL-terminated C strings ready for
// the linker argv.

export fn i8* dynamic_linker() { return "/lib64/ld-linux-x86-64.so.2"; }
export fn i8* crt_start()      { return "/usr/lib/Scrt1.o"; }
export fn i8* crt_init()       { return "/usr/lib/crti.o"; }
export fn i8* crt_fini()       { return "/usr/lib/crtn.o"; }
export fn i8* lib_search_dir() { return "-L/usr/lib"; }
