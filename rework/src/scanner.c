#include "scanner.h"
#include <ctype.h>
#include <string.h>

Token next_token(Scanner *scanner) {
  const char *input = scanner->source->buffer;
  Token current_token = {};
  // Skip whitespace.
  while (*input && isspace(*input))
    input++;

  if (*input == '\0') {
    current_token.type = TOK_EOF;
    return current_token;
  }

  // If letter: read identifier/keyword.
  if (isalpha(*input)) {
    int i = 0;
    while (*input && (isalnum(*input) || *input == '_')) {
      current_token.text[i++] = *input;
      input++;
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
    else {
      current_token.type = TOK_IDENTIFIER;
    }
    return current_token;
  }

  // If digit: read a number (supporting potential decimal point).
  if (isdigit(*input)) {
    int i = 0;
    int hasDot = 0;
    while (*input && (isdigit(*input) || (*input == '.' && !hasDot))) {
      if (*input == '.') {
        hasDot = 1;
      }
      current_token.text[i++] = *input;
      input++;
    }
    current_token.text[i] = '\0';
    current_token.type = TOK_NUMBER;
    return current_token;
  }

  // Single-character tokens.
  switch (*input) {
  case '=':
    current_token.type = TOK_ASSIGN;
    strcpy(current_token.text, "=");
    input++;
    break;
  case ';':
    current_token.type = TOK_SEMICOLON;
    strcpy(current_token.text, ";");
    input++;
    break;
  case '{':
    current_token.type = TOK_LCURLY;
    strcpy(current_token.text, "{");
    input++;
    break;
  case '}':
    current_token.type = TOK_RCURLY;
    strcpy(current_token.text, "}");
    input++;
    break;
  case '(':
    current_token.type = TOK_LPAREN;
    strcpy(current_token.text, "(");
    input++;
    break;
  case ')':
    current_token.type = TOK_RPAREN;
    strcpy(current_token.text, ")");
    input++;
    break;
  case ',':
    current_token.type = TOK_COMMA;
    strcpy(current_token.text, ",");
    input++;
    break;
  default:
    current_token.type = TOK_UNKNOWN;
    current_token.text[0] = *input;
    current_token.text[1] = '\0';
    input++;
    break;
  }
  return current_token;
}
