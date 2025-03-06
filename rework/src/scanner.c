#include "scanner.h"
#include "util.h"
#include <ctype.h>
#include <string.h>

#define _INPUT scanner->source.buffer

#define _INDEX scanner->id

char eat_next_char(Scanner *scanner) {
	++scanner->col;
	if (_INPUT[_INDEX] == '\n' && !scanner->is_reading_string) {
		++scanner->line;
		scanner->col = 0;
	}
	return _INPUT[_INDEX++];
}

Token next_token(Scanner *scanner) {
	Token current_token = {0};
	current_token.location.path = scanner->source.path;
	// Skip whitespace.
	while (_INPUT[_INDEX] && isspace(_INPUT[_INDEX])) {
		eat_next_char(scanner);
	}

	if (_INPUT[_INDEX] == '\0') {
		current_token.type = TOK_EOF;
		return current_token;
	}

	// If letter: read identifier/keyword.
	if (isalpha(_INPUT[_INDEX])) {
		int i = 0;
		while (_INPUT[_INDEX] && (isalnum(_INPUT[_INDEX]) || _INPUT[_INDEX] == '_')) {
			current_token.text[i++] = _INPUT[_INDEX];
			eat_next_char(scanner);
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
		else if (strcmp(current_token.text, "void") == 0)
			current_token.type = TOK_VOID;
		else if (strcmp(current_token.text, "struct") == 0)
			current_token.type = TOK_STRUCT;
		else if (strcmp(current_token.text, "fn") == 0)
			current_token.type = TOK_FUNC;
		else if (strcmp(current_token.text, "true") == 0)
			current_token.type = TOK_TRUE;
		else if (strcmp(current_token.text, "false") == 0)
			current_token.type = TOK_FALSE;
		else if (strcmp(current_token.text, "const") == 0)
			current_token.type = TOK_CONST;
		else if (strcmp(current_token.text, "return") == 0)
			current_token.type = TOK_RETURN;
		else if (strcmp(current_token.text, "enum") == 0)
			current_token.type = TOK_ENUM;
		else {
			current_token.type = TOK_IDENTIFIER;
		}
		current_token.location.id = _INDEX;
		current_token.location.col = scanner->col;
		current_token.location.line = scanner->line;
		return current_token;
	}

	// If digit: read a number (supporting potential decimal point).
	if (isdigit(_INPUT[_INDEX])) {
		int i = 0;
		int hasDot = 0;
		while (_INPUT[_INDEX] && (isdigit(_INPUT[_INDEX]) || (_INPUT[_INDEX] == '.' && !hasDot))) {
			if (_INPUT[_INDEX] == '.') {
				hasDot = 1;
			}
			current_token.text[i++] = _INPUT[_INDEX];
			eat_next_char(scanner);
		}
		current_token.text[i] = '\0';
		current_token.type = TOK_NUMBER;
		current_token.location.id = _INDEX;
		current_token.location.col = scanner->col;
		current_token.location.line = scanner->line;
		return current_token;
	}

	// Single-character tokens.
	switch (_INPUT[_INDEX]) {
	case '=':
		current_token.type = TOK_ASSIGN;
		strncpy(current_token.text, "=", sizeof(current_token.text));
		eat_next_char(scanner);

		break;
	case ';':
		current_token.type = TOK_SEMICOLON;
		strncpy(current_token.text, ";", sizeof(current_token.text));
		eat_next_char(scanner);

		break;
	case ':':
		current_token.type = TOK_COLON;
		strncpy(current_token.text, ":", sizeof(current_token.text));
		eat_next_char(scanner);
		if (_INPUT[_INDEX] == ':') {
			current_token.type = TOK_COLONCOLON;
			strncpy(current_token.text, "::", sizeof(current_token.text));
			eat_next_char(scanner);
		}

		break;
	case '{':
		current_token.type = TOK_LCURLY;
		strncpy(current_token.text, "{", sizeof(current_token.text));
		eat_next_char(scanner);

		break;
	case '}':
		current_token.type = TOK_RCURLY;
		strncpy(current_token.text, "}", sizeof(current_token.text));
		eat_next_char(scanner);

		break;
	case '(':
		current_token.type = TOK_LPAREN;
		strncpy(current_token.text, "(", sizeof(current_token.text));
		eat_next_char(scanner);

		break;
	case ')':
		current_token.type = TOK_RPAREN;
		strncpy(current_token.text, ")", sizeof(current_token.text));
		eat_next_char(scanner);

		break;
	case ',':
		current_token.type = TOK_COMMA;
		strncpy(current_token.text, ",", sizeof(current_token.text));
		eat_next_char(scanner);

		break;
	case '+':
		current_token.type = TOK_PLUS;
		strncpy(current_token.text, "+", sizeof(current_token.text));
		eat_next_char(scanner);

		break;
	case '-':
		current_token.type = TOK_MINUS;
		strncpy(current_token.text, "-", sizeof(current_token.text));
		eat_next_char(scanner);

		break;
	case '*':
		current_token.type = TOK_ASTERISK;
		strncpy(current_token.text, "*", sizeof(current_token.text));
		eat_next_char(scanner);

		break;
	case '/':
		current_token.type = TOK_SLASH;
		strncpy(current_token.text, "/", sizeof(current_token.text));
		eat_next_char(scanner);

		break;
	case '&':
		current_token.type = TOK_AMPERSAND;
		strncpy(current_token.text, "&", sizeof(current_token.text));
		eat_next_char(scanner);

		break;
	case '!':
		current_token.type = TOK_EXCLAMATION;
		strncpy(current_token.text, "!", sizeof(current_token.text));
		eat_next_char(scanner);

		break;
	case '[':
		current_token.type = TOK_LBRACKET;
		strncpy(current_token.text, "[", sizeof(current_token.text));
		eat_next_char(scanner);

		break;
	case ']':
		current_token.type = TOK_RBRACKET;
		strncpy(current_token.text, "]", sizeof(current_token.text));
		eat_next_char(scanner);

		break;
	case '.':
		current_token.type = TOK_DOT;
		strncpy(current_token.text, ".", sizeof(current_token.text));
		eat_next_char(scanner);

		break;
	default:
		current_token.type = TOK_UNKNOWN;
		current_token.text[0] = _INPUT[_INDEX];
		current_token.text[1] = '\0';
		eat_next_char(scanner);

		break;
	}
	current_token.location.id = _INDEX;
	current_token.location.col = scanner->col;
	current_token.location.line = scanner->line;
	return current_token;
}

CompilerResult scanner_init(Scanner *scanner, const char *path, const char *input) {
	if (!scanner)
		return RESULT_PASSED_NULL_PTR;

	memset(scanner, 0, sizeof(Scanner));

	scanner->source.path = strdup(path);
	if (!scanner->source.path)
		return RESULT_MEMORY_ERROR;

	scanner->source.buffer = strdup(input);
	if (!scanner->source.buffer)
		return RESULT_MEMORY_ERROR;

	scanner->source = scanner->source;

	return RESULT_SUCCESS;
}

CompilerResult scanner_deinit(Scanner *scanner) {
	if (!scanner)
		return RESULT_PASSED_NULL_PTR;

	free(scanner->source.buffer);
	free(scanner->source.path);

	return RESULT_SUCCESS;
}
