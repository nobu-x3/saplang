
cmake_minimum_required(VERSION 3.15)

project(saplangc_tests LANGUAGES CXX)

Include(FetchContent)

FetchContent_Declare(
  unity
  GIT_REPOSITORY https://github.com/ThrowTheSwitch/Unity.git
  GIT_TAG        v2.6.1 # or a later release
)

FetchContent_MakeAvailable(unity)

# Enables `-n <name>` so a single test can be run by name. PUBLIC so runner.c
# (which links unity) sees it too.
target_compile_definitions(unity PUBLIC UNITY_USE_COMMAND_LINE_ARGS)

file(GLOB tests_src CONFIGURE_DEPENDS "*.c")
# file(GLOB tests_runners CONFIGURE_DEPENDS ".runner/runner.c")
# list(APPEND tests_src ${tests_runners})

add_executable(saplangc_tests ${tests_src})
target_link_libraries(saplangc_tests PRIVATE unity saplangc_lib)

# Stage the module fixtures next to the test binary so the E2E tests find them
# (replaces the manual copy step the run scripts do).
add_custom_command(TARGET saplangc_tests POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_SOURCE_DIR}/tests/module_tests"
            "$<TARGET_FILE_DIR:saplangc_tests>/module_tests")

# Register one CTest test per RUN_TEST(...) in runner.c so each is individually
# discoverable (e.g. in VS Test Explorer). Each runs the binary with `-n <name>`
# from the binary dir, with the toolchain bin dir on PATH for the E2E tests'
# clang / llvm-dwarfdump calls.
get_filename_component(SL_TOOLCHAIN_BIN "${CMAKE_C_COMPILER}" DIRECTORY)
file(TO_NATIVE_PATH "${SL_TOOLCHAIN_BIN}" SL_TOOLCHAIN_BIN_NATIVE)

file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/runner.c" _run_test_lines REGEX "^[ \t]*RUN_TEST\\(")
foreach(_line IN LISTS _run_test_lines)
    string(REGEX MATCH "RUN_TEST\\(([A-Za-z0-9_]+)\\)" _ "${_line}")
    set(_tname "${CMAKE_MATCH_1}")
    if(_tname)
        add_test(NAME ${_tname}
                 COMMAND saplangc_tests -n ${_tname}
                 WORKING_DIRECTORY $<TARGET_FILE_DIR:saplangc_tests>)
        if(SL_TOOLCHAIN_BIN)
            set_tests_properties(${_tname} PROPERTIES
                ENVIRONMENT_MODIFICATION "PATH=path_list_prepend:${SL_TOOLCHAIN_BIN_NATIVE}")
        endif()
    endif()
endforeach()
