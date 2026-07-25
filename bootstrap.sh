#!/usr/bin/env sh
# Bootstrap the Stage 2 self-hosted compiler from source using Stage 1.
#
# Stage 1 (build/bin/saplangc, the C compiler) is the only foreign compiler in the
# chain. It can build the v0 source (Stage-1 language subset). Once stage2/*.sl adopts
# v1 features (comptime/generics/alias) Stage 1 can no longer read it — from then on
# bootstrap from a binary produced off the `stage2-v0` tag:
#
#     git worktree add ../saplang-v0 stage2-v0
#     (cd ../saplang-v0 && cmake -B build -DBUILD_TESTS=On && make -C build && ./bootstrap.sh)
#     # ../saplang-v0/bootstrap/saplangc2 then compiles the v1 source on main.
#
# Usage:
#   ./bootstrap.sh            build the seed compiler at bootstrap/saplangc2
#   ./bootstrap.sh verify     also prove it self-hosts to a byte-identical fixpoint
set -e

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

STAGE1=build/bin/saplangc
OUT=bootstrap/saplangc2
INCLUDES="stage2/std;stage2"

if [ ! -x "$STAGE1" ]; then
    echo "Stage 1 compiler not found at $STAGE1."
    echo "Build it first:  cmake -B build -DBUILD_TESTS=On && make -C build"
    exit 1
fi

mkdir -p bootstrap
rm -rf .tmp   # Stage 1 links every .tmp/*.o; a stale object from a prior run collides
echo "Building Stage 2 saplangc from source via Stage 1..."
"$STAGE1" stage2/saplangc.sl -o "$OUT" -i "$INCLUDES" -l "LLVM-19" -j 1   # single-threaded: the parallel driver has an intermittent segfault race
echo "Seed compiler: $OUT"

if [ "$1" = "verify" ]; then
    echo "Verifying self-host fixpoint..."
    "$OUT" stage2/saplangc.sl -o bootstrap/stage_b -i "$INCLUDES" -l "LLVM-19" -target linux
    bootstrap/stage_b stage2/saplangc.sl -o bootstrap/stage_c -i "$INCLUDES" -l "LLVM-19" -target linux
    if cmp bootstrap/stage_b bootstrap/stage_c; then
        echo "OK: stage_b == stage_c (byte-identical fixpoint)"
    else
        echo "FAIL: fixpoint not reached (stage_b != stage_c)"
        exit 1
    fi
fi
