
cmake_minimum_required(VERSION 3.5)

project(saplangc_tests LANGUAGES CXX)

Include(FetchContent)

FetchContent_Declare(
  unity
  GIT_REPOSITORY https://github.com/ThrowTheSwitch/Unity.git
  GIT_TAG        v2.6.1 # or a later release
)

FetchContent_MakeAvailable(unity)

file(GLOB tests_src CONFIGURE_DEPENDS "*.c")
# file(GLOB tests_runners CONFIGURE_DEPENDS ".runner/runner.c")
# list(APPEND tests_src ${tests_runners})

add_executable(saplangc_tests ${tests_src})
target_link_libraries(saplangc_tests PRIVATE unity saplangc_lib)

include(CTest)
