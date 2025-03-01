#!/bin/sh
rm -rf build/bin/module_tests
cmake -B build -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTS=On && make -C build -j 32
build/bin/saplangc
# cp -r tests/module_tests build/bin/module_tests
# build/bin/saplang_tests
