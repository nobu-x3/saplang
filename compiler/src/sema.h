#pragma once

#include "parser.h"
#include "util.h"

int is_convertible(const Type *source, const Type *target);

Type *get_type(Symbol *table, ASTNode *node, int scope_level);

/* ASTNode *insert_implicit_cast(ASTNode *expr, const char *target_type); */

CompilerResult analyze_ast(Symbol *table, ASTNode *node, int scope_level);
