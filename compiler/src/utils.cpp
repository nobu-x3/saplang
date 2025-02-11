#include <algorithm>
#include <cassert>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iostream>

#include "utils.h"

namespace saplang {

#if defined(BUILD_TESTS)

static std::stringstream error_stream{};

const std::stringstream &get_error_stream() { return error_stream; }

void clear_error_stream() { error_stream.str(std::string()); }
#endif

std::nullptr_t report(SourceLocation location, std::string_view msg, bool is_warning) {
  assert(!location.path.empty() && location.line != 0 && location.col != 0);
  std::cout << location.path << ":" << location.line << ":" << location.col << (is_warning ? " warning: " : " error: ") << msg << '\n';
  std::ifstream source_file;
  std::filesystem::path path_to_source{std::filesystem::absolute(location.path)};
  source_file.open(path_to_source.c_str());
  if (source_file.is_open()) {
    std::string line;
    int counter = 0;
    while (counter < location.line && std::getline(source_file, line)) {
      ++counter;
    }
    /* auto cleared = line.find_first_not_of(" \t"); */
    /* if (cleared != std::string::npos) { */
    /*   line.replace(0, cleared, ""); */
    /* } */
    std::cout << line << '\n';
    for (int i = 0; i < location.col; ++i) {
      std::cout << " ";
    }
    std::cout << "^\n";
    source_file.close();
  }
#if defined(BUILD_TESTS)
  error_stream << location.path << ":" << location.line << ":" << location.col << (is_warning ? " warning: " : " error: ") << msg << '\n';
#endif
  return nullptr;
}
} // namespace saplang
