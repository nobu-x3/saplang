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

rm -rf build/tests/build
cmake -B build -G "$GENERATOR" -DCMAKE_BUILD_TYPE=$BUILD_TYPE -DBUILD_TESTS=On
make -C build -j 2
mkdir build/tests/build
mkdir build/tests/build/bin
cp -r tests/module_tests build/tests/build/bin/module_tests
# cd build
ctest -C $BUILD_TYPE --output-on-failure --progress --test-dir build
