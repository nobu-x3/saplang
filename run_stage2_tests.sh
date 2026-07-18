#!/bin/sh
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
SAPLANGC="$ROOT/build/bin/saplangc"
SRC_DIR="$ROOT/stage2/tests"
OUT_DIR="$ROOT/build/bin/stage2_tests"

rm -rf "$OUT_DIR"

if [ ! -x "$SAPLANGC" ]; then
	echo "error: $SAPLANGC not found or not executable" >&2
	exit 1
fi

mkdir -p "$OUT_DIR"

build_fail=0
build_ok=0
for src in "$SRC_DIR"/*_test.sl; do
	[ -e "$src" ] || continue
	name="$(basename "$src" .sl)"
	out="$OUT_DIR/$name"
	echo "==> building $name"
	extra=""
	# codegen (and the compiler library that drives it) link the LLVM C API.
	case "$name" in codegen_test|compiler_test) extra="-l LLVM-19 -L /usr/lib" ;; esac
	if timeout 20 "$SAPLANGC" "$src" -o "$out" -i "stage2/std;stage2;stage2/tests" -dbg $extra; then
		build_ok=$((build_ok + 1))
	else
		echo "    BUILD FAILED ($name)"
		build_fail=$((build_fail + 1))
	fi
done

echo
echo "build: $build_ok ok, $build_fail failed"
echo

run_fail=0
run_ok=0
# Only the built test binaries end in _test; skip executables that a test itself produced (e.g. the e2e link test's output).
for exe in "$OUT_DIR"/*_test; do
	[ -f "$exe" ] && [ -x "$exe" ] || continue
	name="$(basename "$exe")"
	echo "==> running $name"
	if ( cd "$OUT_DIR" && timeout 10 "./$name" ); then
		run_ok=$((run_ok + 1))
	else
		rc=$?
		echo "    RUN FAILED ($name) rc=$rc"
		run_fail=$((run_fail + 1))
	fi
done

echo
echo "run: $run_ok ok, $run_fail failed"

[ "$build_fail" -eq 0 ] && [ "$run_fail" -eq 0 ]
