#!/bin/sh
cmake -B build -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTS=On && make -C build -j 32 && build/bin/saplang_tests
