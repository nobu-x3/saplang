#!/bin/sh
rm -rf build/bin/module_tests

ruby build/_deps/unity-src/auto/generate_test_runner.rb rework_tests/parser_tests.c rework_tests/.runners/parser_tests_runners.c

cmake -B build -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTS=On && make -C build -j 32
build/bin/saplangc_tests

# build/bin/saplangc
# cp -r tests/module_tests build/bin/module_tests
# build/bin/saplang_tests
