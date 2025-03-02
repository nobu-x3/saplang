#include "scanner.h"
#include "util.h"
#include <ctype.h>
#include <string.h>

Token next_token(Scanner *scanner) {
  Token current_token = {};
  // Skip whitespace.
  while (*scanner->source.buffer && isspace(*scanner->source.buffer))
    scanner->source.buffer++;

  if (*scanner->source.buffer == '\0') {
    current_token.type = TOK_EOF;
    return current_token;
  }

  // If letter: read identifier/keyword.
  if (isalpha(*scanner->source.buffer)) {
    int i = 0;
    while (*scanner->source.buffer && (isalnum(*scanner->source.buffer) || *scanner->source.buffer == '_')) {
      current_token.text[i++] = *scanner->source.buffer;
      scanner->source.buffer++;
    }
    current_token.text[i] = '\0';

    // Check for built-in type keywords and other reserved words.
    if (strcmp(current_token.text, "i8") == 0)
      current_token.type = TOK_I8;
    else if (strcmp(current_token.text, "i16") == 0)
      current_token.type = TOK_I16;
    else if (strcmp(current_token.text, "i32") == 0)
      current_token.type = TOK_I32;
    else if (strcmp(current_token.text, "i64") == 0)
      current_token.type = TOK_I64;
    else if (strcmp(current_token.text, "u8") == 0)
      current_token.type = TOK_U8;
    else if (strcmp(current_token.text, "u16") == 0)
      current_token.type = TOK_U16;
    else if (strcmp(current_token.text, "u32") == 0)
      current_token.type = TOK_U32;
    else if (strcmp(current_token.text, "u64") == 0)
      current_token.type = TOK_U64;
    else if (strcmp(current_token.text, "f32") == 0)
      current_token.type = TOK_F32;
    else if (strcmp(current_token.text, "f64") == 0)
      current_token.type = TOK_F64;
    else if (strcmp(current_token.text, "bool") == 0)
      current_token.type = TOK_BOOL;
    else if (strcmp(current_token.text, "struct") == 0)
      current_token.type = TOK_STRUCT;
    else if (strcmp(current_token.text, "func") == 0)
      current_token.type = TOK_FUNC;
    else if (strcmp(current_token.text, "true") == 0)
      current_token.type = TOK_TRUE;
    else if (strcmp(current_token.text, "false") == 0)
      current_token.type = TOK_FALSE;
    else if (strcmp(current_token.text, "const") == 0)
      current_token.type = TOK_CONST;
    else {
      current_token.type = TOK_IDENTIFIER;
    }
    return current_token;
  }

  // If digit: read a number (supporting potential decimal point).
  if (isdigit(*scanner->source.buffer)) {
    int i = 0;
    int hasDot = 0;
    while (*scanner->source.buffer && (isdigit(*scanner->source.buffer) || (*scanner->source.buffer == '.' && !hasDot))) {
      if (*scanner->source.buffer == '.') {
        hasDot = 1;
      }
      current_token.text[i++] = *scanner->source.buffer;
      scanner->source.buffer++;
    }
    current_token.text[i] = '\0';
    current_token.type = TOK_NUMBER;
    return current_token;
  }

  // Single-character tokens.
  switch (*scanner->source.buffer) {
  case '=':
    current_token.type = TOK_ASSIGN;
    strcpy(current_token.text, "=");
    scanner->source.buffer++;
    break;
  case ';':
    current_token.type = TOK_SEMICOLON;
    strcpy(current_token.text, ";");
    scanner->source.buffer++;
    break;
  case '{':
    current_token.type = TOK_LCURLY;
    strcpy(current_token.text, "{");
    scanner->source.buffer++;
    break;
  case '}':
    current_token.type = TOK_RCURLY;
    strcpy(current_token.text, "}");
    scanner->source.buffer++;
    break;
  case '(':
    current_token.type = TOK_LPAREN;
    strcpy(current_token.text, "(");
    scanner->source.buffer++;
    break;
  case ')':
    current_token.type = TOK_RPAREN;
    strcpy(current_token.text, ")");
    scanner->source.buffer++;
    break;
  case ',':
    current_token.type = TOK_COMMA;
    strcpy(current_token.text, ",");
    scanner->source.buffer++;
    break;
  default:
    current_token.type = TOK_UNKNOWN;
    current_token.text[0] = *scanner->source.buffer;
    current_token.text[1] = '\0';
    scanner->source.buffer++;
    break;
  }
  return current_token;
}

CompilerResult scanner_init(Scanner *scanner, const char *path, const char *input) {
  if (!scanner)
    return RESULT_PASSED_NULL_PTR;

  memset(scanner, 0, sizeof(Scanner));

  SourceFile src_file = {0};

  int path_len = strlen(path);
  src_file.path = malloc(path_len);
  if (!src_file.path)
    return RESULT_MEMORY_ERROR;
  strcpy(src_file.path, path);

  int input_lenght = strlen(input);
  src_file.buffer = malloc(input_lenght);
  if (!src_file.buffer)
    return RESULT_MEMORY_ERROR;
  strcpy(src_file.buffer, input);

  scanner->source = src_file;

  return RESULT_SUCCESS;
}

CompilerResult scanner_deinit(Scanner *scanner) {
    if(!scanner)
        return RESULT_PASSED_NULL_PTR;

    // @TODO: instead of moving the buffer ptr when getting tokens, increment the index, otherwise leaking memory
    /* free(scanner->source.buffer); */
    free(scanner->source.path);

    return RESULT_SUCCESS;
}
