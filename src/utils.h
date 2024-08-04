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
}
