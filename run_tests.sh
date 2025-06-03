#!/bin/sh
rm -rf build/bin/module_tests

# cp rework_tests/*.h rework_tests/.runners/
# ruby build/_deps/unity-src/auto/generate_test_runner.rb rework_tests/runner.c rework_tests/.runners/runner.c

cp -r tests/module_tests build/bin/module_tests

cmake -B build -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTS=On -Wall && make -C build -j 32
(cd build/bin && rm -rf .tmp &&./saplangc_tests)

# build/bin/saplangc
# cp -r tests/module_tests build/bin/module_tests
# build/bin/saplang_tests
