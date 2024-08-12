cmake_minimum_required(VERSION 3.5)

project(saplang_tests LANGUAGES CXX)

Include(FetchContent)

FetchContent_Declare(
  Catch2
  GIT_REPOSITORY https://github.com/catchorg/Catch2.git
  GIT_TAG        v3.4.0 # or a later release
)

FetchContent_MakeAvailable(Catch2)

file(GLOB tests_src CONFIGURE_DEPENDS "*.cpp")

add_executable(saplang_tests ${tests_src})
target_link_libraries(saplang_tests PRIVATE Catch2::Catch2WithMain)

list(APPEND CMAKE_MODULE_PATH ${catch2_SOURCE_DIR}/extras)
include(CTest)
include(Catch)
catch_discover_tests(saplang_tests)
