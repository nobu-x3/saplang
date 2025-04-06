#pragma once

#include "parser.h"
#include "util.h"

int is_convertible(const Type *source, const Type *target);

Type *get_type(Symbol *table, ASTNode *node, int scope_level, const char* scope_specifier);

/* ASTNode *insert_implicit_cast(ASTNode *expr, const char *target_type); */

/*
 * @params:
 * table - pointer to the symbol table
 * node - pointer to node to analyze
 * scope_level - minimum scope depth to look at
 * scope_specifier - optional parameter that is the function name if we're using this on nodes in body of a function, otherwise empty string (!!! not NULL)
 * */
CompilerResult analyze_ast(Symbol *table, ASTNode *node, int scope_level, const char *scope_specifier);
