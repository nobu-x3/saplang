#!/usr/bin/env sh
# Mutation fuzzer for the front end. Seeds from real sources, mutates bytes, and compiles each case
# under a timeout — any signal (not a diagnostic) or a hang is a finding, kept in fuzz-out/.
#
#   ./fuzz.sh [ITERATIONS] [COMPILER]
set -u

ROOT=$(cd "$(dirname "$0")" && pwd)
ITERATIONS=${1:-300}
COMPILER=${2:-$ROOT/build/bin/saplangc2}
OUT=$ROOT/fuzz-out
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if [ ! -x "$COMPILER" ]; then
    echo "error: $COMPILER not found; run ./bootstrap.sh first" >&2
    exit 1
fi

mkdir -p "$OUT"
SEEDS=$(ls "$ROOT"/stage2/tests/*.sl "$ROOT"/stage2/std/*.sl "$ROOT"/stage2/*.sl 2>/dev/null)
SEED_COUNT=$(echo "$SEEDS" | wc -l)

crashes=0
hangs=0
run=0

iteration=0
while [ "$iteration" -lt "$ITERATIONS" ]; do
    iteration=$((iteration + 1))
    seed=$(echo "$SEEDS" | sed -n "$(( (RANDOM % SEED_COUNT) + 1 ))p")
    [ -n "$seed" ] || continue
    case_file=$WORK/case.sl

    # Truncate, byte-flip, or splice in raw garbage; each exercises a different recovery path.
    size=$(wc -c < "$seed")
    [ "$size" -gt 32 ] || continue
    mode=$((RANDOM % 3))
    if [ "$mode" -eq 0 ]; then
        head -c $(( (RANDOM % size) + 1 )) "$seed" > "$case_file"
    elif [ "$mode" -eq 1 ]; then
        offset=$((RANDOM % size))
        head -c "$offset" "$seed" > "$case_file"
        printf '%s' "$(awk -v n=$((RANDOM % 90 + 33)) 'BEGIN{printf "%c", n}')" >> "$case_file"
        tail -c "+$((offset + 2))" "$seed" >> "$case_file"
    else
        head -c $(( (RANDOM % size) + 1 )) "$seed" > "$case_file"
        printf '\000\001\377{{[[((;;fn struct comprun **&&' >> "$case_file"
    fi

    run=$((run + 1))
    timeout 20 "$COMPILER" "$case_file" -o "$WORK/out" -i "$ROOT/stage2/std" -target linux >/dev/null 2>&1
    status=$?
    # 0 and 1 are compile success / clean diagnostics; 124 is the timeout; anything else is a signal.
    if [ "$status" -eq 124 ]; then
        hangs=$((hangs + 1))
        cp "$case_file" "$OUT/hang-$(date +%s)-$iteration.sl"
    elif [ "$status" -gt 1 ]; then
        crashes=$((crashes + 1))
        cp "$case_file" "$OUT/crash-$status-$(date +%s)-$iteration.sl"
    fi
done

echo "fuzz: $run cases, $crashes crashes, $hangs hangs"
[ "$crashes" -eq 0 ] && [ "$hangs" -eq 0 ]
