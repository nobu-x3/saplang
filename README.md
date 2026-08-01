# Saplang

A small C-family language with modules, comptime, and a self-hosted compiler.

Please use the [Discord](https://discord.gg/peAgk5kBh2) to get in contact with me.

# !DISCLAIMER
This is not a C-KILLER. I have no aspirations for this language to become popular or even used by other people. I'm developing it for my own projects and according to my tastes and needs. USE AT YOUR OWN RISK!

# Status

The compiler is **self-hosted**: `saplangc` is written in Saplang, compiles its own source, and reaches a byte-identical fixpoint (the compiler it builds builds an identical compiler).

Working today:

* Structs, unions, enums, slices (`T[]`, `arr[1..4]`, `.ptr`, `.len`), function pointers, `defer`, `switch` with fallthrough and `else`.
* Modules with `::` qualification and circular imports.
* `extern` blocks for C interop, linked with `ld.lld`.
* Comptime: `comprun` blocks, `compinsert`, `comperror`, `sizeof` / `alignof` / `typeof` / `type_info` reflection.
* Generics via comptime — `fn Type List(comptime Type T)`, monomorphized and deduplicated by the linker.
* `alias` declarations, anonymous structs and unions at type position.
* Conditional compilation, both per-target files and in-line `comprun if (build::os == "linux")`.
* Pointee-`const`: `const u8*` is a pointer to bytes you cannot write through.
* A standard library: `sys`, `mem` (allocator interface), `arena`, `io`, `list`, `hash`, `testing`, `threads` / `mutex` / `condvar`.
* A build system written in Saplang — describe the build in `build.sl` and run `saplangc build`.
* Debug builds carry gdb-inspectable DWARF; `-config` selects Release, AddressSanitizer, or ThreadSanitizer.

Two stages live in this repo. **Stage 1** (`compiler/`, written in C) is the bootstrap compiler — feature-complete for its purpose and no longer developed. **Stage 2** (`stage2/`) is the real compiler, written in Saplang.

# Requirements

* `clang` (tested on 18.1.8) and **LLVM 19** — codegen links against the LLVM C API.
* `ld.lld` — the driver spawns it directly to link.
* Linux on x86-64. Windows is not currently a supported target.

# Building from source

```sh
cmake -B build -DBUILD_TESTS=On && make -C build   # Stage 1, the bootstrap compiler
./bootstrap.sh                                     # -> build/bin/saplangc2
```

Stage 1 cannot parse the current Stage 2 source, so `bootstrap.sh` chains tagged stages, each built by the previous stage's compiler, caching them under `bootstrap/`. `./bootstrap.sh verify` additionally proves the fixpoint.

# Hello world

```sap
import sys;

export fn i32 main() {
    sys::dprintf(1, "hello from saplang\n");
    return 0;
}
```

```sh
build/bin/saplangc2 main.sl -o hello -i stage2/std
./hello
```

`-i` is the module search path (`;`-separated). An installed compiler (below) finds its own `std/`, so `-i` is only needed for your own module directories. Run `saplangc --help` for the full flag list.

# Installing

```sh
./install.sh [DEST]      # default DEST=dist/saplang
```

This lays out `saplangc` with `std/` beside it, which is how the compiler finds the standard library. Put `DEST` on your `PATH`, or symlink `DEST/saplangc` somewhere already on it — the symlink resolves through `/proc/self/exe`, so `std/` is still found. `SAPLANG_STD` overrides the location.

# Testing

```sh
./run_tests.sh              # Stage 1 suite
./run_stage2_selfhost.sh    # builds saplangc2, then compiles + runs every stage2/tests/*.sl
./bootstrap.sh verify       # byte-identical self-host fixpoint
```

The Stage 2 runner also rebuilds each test under `-mt` to shake out concurrency regressions.

# Goal

After coding in C and C++ for some time, I've come to the conclusion that both of the languages are not perfect. I've been searching and trying out different 'C/C++-killers' for a while but I still have not found a language that satisfies me. So I decided to build my own.
Saplang is built on top of the foundation that is C with some features inspired by C++. The end-goal is to have a language with the following features and qualities:
* Minimal syntactic differences to C.
* Full C-interop.
* 'defer' keyword.
* Modules.
* Build system written in Saplang.
* Comptime.
* Reflection as a language feature.
