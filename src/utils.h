#pragma once

#include <string>

namespace saplang {
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
  virtual void dump(size_t indent = 0) const = 0;
};

inline std::string indent(size_t level) { return std::string(level * 2, ' '); }

std::nullptr_t report(SourceLocation location, std::string_view msg,
            bool is_warning = false);

} // namespace saplang
