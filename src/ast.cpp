#include "ast.h"

#include <iostream>

namespace saplang {

    void Block::dump(size_t indent_level) const {
        std::cerr << indent(indent_level) << "Block\n";
    }

    void FunctionDecl::dump(size_t indent_level) const {
        std::cerr << indent(indent_level) << "FunctionDecl: " << id << ":" << type.name << '\n';
        body->dump(indent_level + 1);
    }
}
