#include "catch2/catch_test_macros.hpp"
#include "test_utils.h"
#include <ostream>
#include <sstream>

#define TEST_SETUP(test_name, include_string)                                                                                                                  \
  saplang::clear_error_stream();                                                                                                                               \
  std::ostringstream compile_output_stream;                                                                                                                    \
  saplang::CompilerOptions compiler_options{"build/bin/module_tests/" + std::string(test_name) + "/test.sl",                                                   \
                                            "build/bin/module_tests/" + std::string(test_name) + "/test"};                                                     \
  if (std::string(include_string).size() > 0)                                                                                                                  \
    compiler_options.import_paths = saplang::split(include_string, ';');                                                                                       \
  saplang::Driver driver{compiler_options};                                                                                                                    \
  int compile_result = driver.run(compile_output_stream);                                                                                                      \
  std::string compile_output = compile_output_stream.str();

#define REQUIRE_COMPILE_SUCCESS                                                                                                                                \
  REQUIRE(compile_output == "");                                                                                                                               \
  REQUIRE(compile_result == 0);

#define EXEC_COMPILED(test_name)                                                                                                                               \
  std::string command = "touch build/bin/module_tests/" + std::string(test_name) + "/test_output.txt && build/bin/module_tests/" + std::string(test_name) +    \
                        "/test >>build/bin/module_tests/" + std::string(test_name) + "/test_output.txt 2>&1";                                                  \
  int exec_result = std::system(command.c_str());                                                                                                              \
  REQUIRE(exec_result == 0);                                                                                                                                   \
  std::ifstream fstream{"build/bin/module_tests/" + std::string(test_name) + "/test_output.txt", std::ios::in | std::ios::ate};                                \
  REQUIRE(fstream.is_open());                                                                                                                                  \
  auto len = fstream.tellg();                                                                                                                                  \
  std::string stdout_string(len, '\n');                                                                                                                        \
  fstream.seekg(0);                                                                                                                                            \
  fstream.read(&stdout_string[0], len);

TEST_CASE("visibility_same_dir", "[modules]") {
  TEST_SETUP("visibility_same_dir", "");
  REQUIRE_COMPILE_SUCCESS;
  EXEC_COMPILED("visibility_same_dir")
  REQUIRE(stdout_string == "hello world\n");
}

TEST_CASE("visibility_other_dir", "[modules]") {
  TEST_SETUP("visibility_other_dir", "build/bin/module_tests/visibility_other_dir/incl");
  REQUIRE_COMPILE_SUCCESS;
  EXEC_COMPILED("visibility_other_dir")
  REQUIRE(stdout_string == "hello world\n");
}

TEST_CASE("visibility_structs_and_enums", "[modules]") {
  TEST_SETUP("visibility_structs_and_enums", "");
  REQUIRE_COMPILE_SUCCESS;
  EXEC_COMPILED("visibility_structs_and_enums")
  REQUIRE(stdout_string == "TestStruct value: 32\nTestEnum value: 0\nTestEnum value: 0\n");
}

TEST_CASE("visibility_extern", "[modules]") {
  TEST_SETUP("visibility_extern", "");
  REQUIRE_COMPILE_SUCCESS;
  EXEC_COMPILED("visibility_extern")
  REQUIRE(stdout_string == "hello world\n");
}

TEST_CASE("visibility_generics", "[modules]") {
  TEST_SETUP("visibility_generics", "");
  REQUIRE_COMPILE_SUCCESS;
  EXEC_COMPILED("visibility_generics");
  REQUIRE(stdout_string == "69\n0\n");
}

TEST_CASE("pointer_to_generic_arg", "[modules]") {
  TEST_SETUP("pointer_to_generic_arg", "");
  REQUIRE_COMPILE_SUCCESS;
  EXEC_COMPILED("pointer_to_generic_arg");
  REQUIRE(stdout_string == "69\n0\n");
}

TEST_CASE("file_io", "[modules]") {
  TEST_SETUP("file_io", "");
  REQUIRE_COMPILE_SUCCESS;
  EXEC_COMPILED("file_io");
  REQUIRE(stdout_string == "69\n0\n");
}