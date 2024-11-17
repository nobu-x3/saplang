#include <cassert>
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
  std::cerr << location.path << ":" << location.line << ":" << location.col << (is_warning ? " warning: " : " error: ") << msg << '\n';
#if defined(BUILD_TESTS)
  error_stream << location.path << ":" << location.line << ":" << location.col << (is_warning ? " warning: " : " error: ") << msg << '\n';
#endif
  return nullptr;
}
} // namespace saplang
