#!/bin/sh

set -x
set -e

ARCH="$(uname -m)"
TARGET="$ARCH-linux-musl"
MCPU="baseline"
BUILD_TYPE=Debug
GENERATOR="Unix Makefiles"

git fetch --unshallow || true
git fetch --tags

git clean -fd

cmake -B build -G "$GENERATOR" -DCMAKE_BUILD_TYPE=$BUILD_TYPE -DBUILD_TESTS=On
make -C build
cd build
ctest -C $BUILD_TYPE