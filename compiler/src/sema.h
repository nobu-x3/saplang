#pragma once

#include "parser.h"
#include "util.h"

int is_convertible(const char* source, const char* target);

char* get_type(ASTNode* node);

ASTNode* insert_implicit_cast(ASTNode* expr, const char* target_type);

CompilerResult analyze_ast(ASTNode*, int scope_level);
