#!/bin/sh

set -x
set -e

# Get latest
git fetch --unshallow || true
git fetch --tags

git clean -fd

mkdir build
mkdir bulid/nightly
mkdir build/nightly/ARM-linux

ARCH="$(uname -m)"
TARGET="$ARCH-linux-musl"
MCPU="baseline"
GENERATOR="Unix Makefiles"

# Build ARM
# # Debug
BUILD_TYPE=Debug
cmake -B build -G "$GENERATOR" -DCMAKE_BUILD_TYPE=$BUILD_TYPE -DBUILD_TESTS=Off
make -C build -j 3
mkdir build/nightly/ARM-linux/Debug
mv build/bin/compiler build/nightly/ARM-linux/Debug/saplangc
# # Release
BUILD_TYPE=Release
cmake -B build -G "$GENERATOR" -DCMAKE_BUILD_TYPE=$BUILD_TYPE -DBUILD_TESTS=Off
make -C build -j 3
mkdir build/nightly/ARM-linux/Release
mv build/bin/compiler build/nightly/ARM-linux/Release/saplangc
