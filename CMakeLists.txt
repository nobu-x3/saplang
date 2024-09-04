cmake_minimum_required(VERSION 3.5)

project(saplang)

find_package(LLVM REQUIRED CONFIG)
include_directories(compiler/src "${LLVM_INCLUDE_DIR}")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

if(BUILD_TESTS)
  enable_testing()
	add_compile_definitions(BUILD_TESTS)
endif(BUILD_TESTS)

add_subdirectory(compiler)
if(BUILD_TESTS)
  add_subdirectory(tests)
endif(BUILD_TESTS)
