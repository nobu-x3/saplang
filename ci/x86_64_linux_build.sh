#!/bin/sh

set -x
set -e

# Get latest
git fetch --unshallow || true
git fetch --tags

git clean -fd

mkdir build
mkdir bulid/nightly
mkdir build/nightly/x86_64-linux

ARCH="$(uname -m)"
TARGET="$ARCH-linux-musl"
MCPU="baseline"
GENERATOR="Unix Makefiles"

# Build x86
# # Debug
BUILD_TYPE=Debug
cmake -B build -G "$GENERATOR" -DCMAKE_BUILD_TYPE=$BUILD_TYPE -DBUILD_TESTS=Off
make -C build
mkdir build/nightly/x86_64-linux/Debug
mv build/bin/compiler build/nightly/x86_64-linux/Debug/saplangc

# # Release
BUILD_TYPE=Release
cmake -B build -G "$GENERATOR" -DCMAKE_BUILD_TYPE=$BUILD_TYPE -DBUILD_TESTS=Off
make -C build
mkdir build/nightly/x86_64-linux/Release
mv build/bin/compiler build/nightly/x86_64-linux/Release/saplangc
