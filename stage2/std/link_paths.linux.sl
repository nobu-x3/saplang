// x86-64 Linux glibc link configuration for the ld.lld step. v0 hardcodes
// these paths; per-target link_paths_<triple>.sl and a -link-config override
// arrive with the build system. Values are NUL-terminated C strings ready for
// the linker argv.

export fn i8* dynamic_linker() { return "/lib64/ld-linux-x86-64.so.2"; }
export fn i8* crt_start()      { return "/usr/lib/Scrt1.o"; }
export fn i8* crt_init()       { return "/usr/lib/crti.o"; }
export fn i8* crt_fini()       { return "/usr/lib/crtn.o"; }
export fn i8* lib_search_dir() { return "-L/usr/lib"; }

// The clang ASan runtime matching the LLVM pass codegen instruments with; GCC's -lasan is a
// different runtime and dies at startup. libgcc_s.so.1 is named directly because /usr/lib/libgcc_s.so
// is an ld script pulling -lgcc from outside our search path.
export fn i8* asan_runtime()        { return "/usr/lib/clang/22/lib/linux/libclang_rt.asan-x86_64.a"; }
export fn i8* asan_runtime_static() { return "/usr/lib/clang/22/lib/linux/libclang_rt.asan_static-x86_64.a"; }
export fn i8* asan_dynamic_list()   { return "--dynamic-list=/usr/lib/clang/22/lib/linux/libclang_rt.asan-x86_64.a.syms"; }
export fn i8* unwind_runtime()      { return "/usr/lib/libgcc_s.so.1"; }
