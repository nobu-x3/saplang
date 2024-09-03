#pragma once

#include <catch2/catch_test_macros.hpp>

#include <sstream>
#include <string>

#include <codegen.h>
#include <lexer.h>
#include <parser.h>
#include <sema.h>
#include <utils.h>

#include <llvm/Support/raw_ostream.h>

#define NEXT_REQUIRE(it, expr)                                                 \
  ++it;                                                                        \
  REQUIRE(expr);

inline std::string remove_whitespace(std::string_view input) {
  std::string output_string{input};
  output_string.erase(
      std::remove_if(output_string.begin(), output_string.end(), ::isspace),
      output_string.end());
  return output_string;
}

inline std::vector<std::string> break_by_line(const std::string &input) {
  std::stringstream buffer{input};
  std::vector<std::string> output{};
  output.reserve(32);
  std::string line;
  while (std::getline(buffer, line, '\n')) {
    if(!line.empty())
      output.push_back(line);
    line.clear();
  }
  return output;
}
