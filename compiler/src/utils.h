#pragma once

#include <iostream>
#include <sstream>
#include <string>

namespace saplang {

#if defined(BUILD_TESTS)
const std::stringstream &get_error_stream();
void clear_error_stream();
#endif

struct SourceFile {
  std::string_view path;
  std::string buffer;
};

struct SourceLocation {
  std::string_view path;
  int line;
  int col;
};

class IDumpable {
public:
  virtual ~IDumpable() = default;
  virtual void dump_to_stream(std::stringstream &stream,
                              size_t indent = 0) const = 0;
  virtual void dump(size_t indent = 0) const = 0;
};

inline std::string indent(size_t level) { return std::string(level * 2, ' '); }

std::nullptr_t report(SourceLocation location, std::string_view msg,
                      bool is_warning = false);
} // namespace saplang
