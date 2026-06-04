#!/bin/sh
set -e

# CMake stages the module_tests fixtures next to the test binary and registers
# the suite with CTest, so there's no manual copy step anymore.
cmake -B build -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTS=On
make -C build -j 32
ctest --test-dir build --output-on-failure
