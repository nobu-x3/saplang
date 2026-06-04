#!/bin/sh
rm -rf build/*
set -e

mkdir -p build/bin
cp -r tests/module_tests build/bin/module_tests

cmake -B build -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTS=On -DLLVM_DIR=/usr/lib/llvm19/lib/cmake/llvm -Wall && make -C build -j 32
ctest --test-dir build --output-on-failure
#(cd build/bin && rm -rf .tmp &&./saplangc_tests)

# build/bin/saplangc
# cp -r tests/module_tests build/bin/module_tests
# build/bin/saplang_tests
