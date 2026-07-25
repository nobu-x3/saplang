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
    if "$SC" "$f" -o "$TMP/$base" -i "$INC" -l "LLVM-19" -target linux > "$TMP/$base.log" 2>&1; then
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
[ "$bfail" -eq 0 ] && [ "$rfail" -eq 0 ]
