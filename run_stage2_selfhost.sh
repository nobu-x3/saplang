#!/usr/bin/env sh
# Build the self-hosted compiler, then compile + run every stage2 test through it.
# The v1 replacement for run_stage2_tests.sh (which builds tests with Stage 1 and can no
# longer read v1 source). A fully green run reports `build: N ok, 0 failed` / `run: N ok, 0 failed`.
set -e

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

./bootstrap.sh

SC=build/bin/saplangc2
INC="stage2/std;stage2;stage2/tests"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

bok=0; bfail=0; rok=0; rfail=0
for f in stage2/tests/*.sl; do
    base=$(basename "$f" .sl)
    [ "$base" = "test_util" ] && continue
    if "$SC" "$f" -o "$TMP/$base" -i "$INC" -l "LLVM-19" -l "m" -target linux > "$TMP/$base.log" 2>&1; then
        bok=$((bok + 1))
        if "$TMP/$base" > /dev/null 2>&1; then
            rok=$((rok + 1))
        else
            rfail=$((rfail + 1)); echo "  RUN-FAIL: $base"
        fi
    else
        bfail=$((bfail + 1)); echo "  BUILD-FAIL: $base :: $(head -1 "$TMP/$base.log")"
    fi
done

echo "build: $bok ok, $bfail failed"
echo "run: $rok ok, $rfail failed"

# Second pass through -mt: the parallel path is otherwise untested, and its bugs are races that a
# single run can miss, so each build is repeated.
MT_REPEATS=${MT_REPEATS:-2}
mtfail=0
for f in stage2/tests/*.sl; do
    base=$(basename "$f" .sl)
    [ "$base" = "test_util" ] && continue
    attempt=1
    while [ "$attempt" -le "$MT_REPEATS" ]; do
        if "$SC" "$f" -o "$TMP/mt-$base" -i "$INC" -l "LLVM-19" -l "m" -target linux -mt > "$TMP/mt-$base.log" 2>&1; then
            "$TMP/mt-$base" > /dev/null 2>&1 || { mtfail=$((mtfail + 1)); echo "  MT-RUN-FAIL: $base (attempt $attempt)"; }
        else
            mtfail=$((mtfail + 1)); echo "  MT-BUILD-FAIL: $base (attempt $attempt) :: $(head -1 "$TMP/mt-$base.log")"
        fi
        attempt=$((attempt + 1))
    done
done
echo "mt: $mtfail failed (x$MT_REPEATS each)"

[ "$bfail" -eq 0 ] && [ "$rfail" -eq 0 ] && [ "$mtfail" -eq 0 ]
