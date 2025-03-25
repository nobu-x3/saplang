#include "sema.h"
#include <string.h>


int is_convertible(const char* source, const char* target) {
    // Allow identical types
    if(strcmp(source, target) == 0) return 1;

    //
    if(strstr(source, "[") != NULL) {
        int len = strlen(target);

    }
}

char* get_type(ASTNode* node) {

}

ASTNode* insert_implicit_cast(ASTNode* expr, const char* target_type) {

}

CompilerResult analyze_ast(ASTNode*, int scope_level) {

}
