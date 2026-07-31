#!/usr/bin/env sh
# Multi-stage self-host bootstrap.
#
# Stage 1 (build/bin/saplangc, C) can only build the Stage-1 language subset. Each later stage adds
# features used in the compiler's own source, so it must be built by the previous stage's compiler:
#
#   Stage 1 (C)              --builds-->  stage2-v0               (source = Stage-1 subset)
#   stage2-v0 compiler       --builds-->  stage2-generic-structs  (source uses generic functions)
#   stage2-generic-structs   --builds-->  stage2-v1               (source uses generic structs, List(T), alias)
#   stage2-v1 compiler       --builds-->  stage2-v2               (source uses comprun + reflection)
#   stage2-v2 compiler       --builds-->  current source          (uses positional const, List(const u8[]))
#
# Each stage's compiler is built once (in a detached worktree of its tag) and cached under bootstrap/.
# The last stage's compiler is the seed that builds the current working tree.
#
# Usage:
#   ./bootstrap.sh            build the current compiler at build/bin/saplangc2
#   ./bootstrap.sh verify     also prove it self-hosts to a byte-identical fixpoint
set -e

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

STAGE1=build/bin/saplangc
OUT=build/bin/saplangc2
INCLUDES="stage2/std;stage2"
STAGES="stage2-v0 stage2-generic-structs stage2-v1 stage2-v2"   # ordered; each built by the previous stage's compiler

mkdir -p bootstrap build/bin

# Build tag $1 with compiler $2 (extra flags $3) into $4, from a detached worktree of the tag.
build_stage() {
    tag=$1; cc=$2; flags=$3; out=$4
    wt=$(mktemp -d)
    git worktree add --quiet --detach "$wt" "$tag"
    ( cd "$wt" && rm -rf .tmp && "$ROOT/$cc" stage2/saplangc.sl -o "$ROOT/$out" -i "$INCLUDES" -l "LLVM-19" -target linux $flags )
    git worktree remove --force "$wt"
}

prev="$STAGE1"
prev_flags="-j 1"   # Stage 1's parallel driver has an intermittent segfault race
for tag in $STAGES; do
    seed="bootstrap/seed-$tag"
    if [ ! -x "$seed" ]; then
        if [ ! -x "$STAGE1" ] && [ "$prev" = "$STAGE1" ]; then
            echo "Stage 1 compiler not found at $STAGE1."
            echo "Build it first:  cmake -B build -DBUILD_TESTS=On && make -C build"
            exit 1
        fi
        echo "Building $tag via $(basename "$prev")..."
        build_stage "$tag" "$prev" "$prev_flags" "$seed"
    fi
    prev="$seed"
    prev_flags=""   # stage-2 compilers are single-threaded by default (no race)
done
SEED="$prev"

echo "Building the current compiler with the seed ($(basename "$SEED"))..."
"$SEED" stage2/saplangc.sl -o "$OUT" -i "$INCLUDES" -l "LLVM-19" -target linux
echo "Compiler: $OUT"

if [ "$1" = "verify" ]; then
    echo "Verifying self-host fixpoint..."
    "$OUT" stage2/saplangc.sl -o build/bin/saplangc2.b -i "$INCLUDES" -l "LLVM-19" -target linux
    build/bin/saplangc2.b stage2/saplangc.sl -o build/bin/saplangc2.c -i "$INCLUDES" -l "LLVM-19" -target linux
    if cmp build/bin/saplangc2.b build/bin/saplangc2.c; then
        echo "OK: b == c (byte-identical fixpoint)"
    else
        echo "FAIL: fixpoint not reached (b != c)"
        exit 1
    fi
fi
