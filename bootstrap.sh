#!/usr/bin/env sh
# Two-stage self-host bootstrap.
#
#   Stage 1 (build/bin/saplangc, C)  --builds-->  v0 seed (from the stage2-v0 tag)
#   v0 seed                          --builds-->  the current compiler (may use v1 features)
#
# Stage 1 can only build the v0 source (Stage-1 language subset). The current source may use
# v1 features (comptime/generics/alias) that Stage 1 can't read, so the seed is built once from
# the frozen `stage2-v0` tag and cached in bootstrap/saplangc2; the seed then builds current.
#
# Usage:
#   ./bootstrap.sh            build the current compiler at build/bin/saplangc2
#   ./bootstrap.sh verify     also prove it self-hosts to a byte-identical fixpoint
set -e

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

STAGE1=build/bin/saplangc
SEED=bootstrap/saplangc2
OUT=build/bin/saplangc2
INCLUDES="stage2/std;stage2"
V0_TAG=stage2-v0

mkdir -p bootstrap build/bin

# 1. Seed: Stage 1 compiles the frozen v0 tag, once. Cached in bootstrap/saplangc2.
if [ ! -x "$SEED" ]; then
    if [ ! -x "$STAGE1" ]; then
        echo "Stage 1 compiler not found at $STAGE1."
        echo "Build it first:  cmake -B build -DBUILD_TESTS=On && make -C build"
        exit 1
    fi
    echo "Building v0 seed from tag $V0_TAG via Stage 1..."
    WT=$(mktemp -d)
    git worktree add --quiet --detach "$WT" "$V0_TAG"
    ( cd "$WT" && rm -rf .tmp && "$ROOT/$STAGE1" stage2/saplangc.sl -o "$ROOT/$SEED" -i "$INCLUDES" -l "LLVM-19" -j 1 )
    git worktree remove --force "$WT"
    echo "Seed: $SEED"
fi

# 2. The seed builds the current compiler (self-hosted; single-threaded by default, no race).
echo "Building the current compiler with the seed..."
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
