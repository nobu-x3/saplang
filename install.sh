#!/usr/bin/env sh
# Lays out a self-contained install: the binary with std/ beside it, the way saplangc discovers it.
#
#   ./install.sh [DEST]     default DEST=dist/saplang
#
# Put DEST on your PATH, or symlink DEST/saplangc somewhere already on it — the symlink resolves
# through /proc/self/exe, so std/ is still found.
set -e

ROOT=$(cd "$(dirname "$0")" && pwd)
DEST=${1:-$ROOT/dist/saplang}
COMPILER=$ROOT/build/bin/saplangc2

if [ ! -x "$COMPILER" ]; then
    echo "error: $COMPILER not found; run ./bootstrap.sh first" >&2
    exit 1
fi

mkdir -p "$DEST/std"
cp "$COMPILER" "$DEST/saplangc"
cp "$ROOT"/stage2/std/*.sl "$DEST/std/"

echo "installed to $DEST"
echo "  $DEST/saplangc"
echo "  $DEST/std/  ($(ls "$DEST"/std/*.sl | wc -l) modules)"
echo
echo "add it to PATH:  export PATH=\"$DEST:\$PATH\""
