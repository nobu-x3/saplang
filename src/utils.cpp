#include <cassert>
#include <iostream>

#include "utils.h"

namespace saplang {

std::nullptr_t report(SourceLocation location, std::string_view msg,
                      bool is_warning) {
  assert(!location.path.empty() && location.line != 0 && location.col != 0);
  std::cerr << location.path << ":" << location.line << ":" << location.col
            << (is_warning ? " warning: " : " error: ") << msg << '\n';
  return nullptr;
}
} // namespace saplang
