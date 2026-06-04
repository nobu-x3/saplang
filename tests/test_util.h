#pragma once
#include "platform.h"
#include <parser.h>
#include <stdio.h>
#include <stdlib.h>
#include <unity.h>

// stdout/stderr are non-assignable macros on Windows, so capture by
// redirecting the underlying fd to a tmpfile rather than swapping the FILE*.
static int _redirect_begin(FILE *stream, FILE **out_temp) {
	fflush(stream);
	FILE *temp = tmpfile();
	if (!temp) {
		TEST_FAIL_MESSAGE("Failed to create temporary file for output capture");
	}
	int saved = SL_DUP(SL_FILENO(stream));
	SL_DUP2(SL_FILENO(temp), SL_FILENO(stream));
	*out_temp = temp;
	return saved;
}

static char *_redirect_end(FILE *stream, int saved, FILE *temp) {
	fflush(stream);
	SL_DUP2(saved, SL_FILENO(stream));
	SL_CLOSE(saved);

	fseek(temp, 0, SEEK_END);
	long size = ftell(temp);
	fseek(temp, 0, SEEK_SET);

	char *buffer = malloc(size + 1);
	if (!buffer) {
		fclose(temp);
		TEST_FAIL_MESSAGE("Memory allocation failed in output capture");
	}

	fread(buffer, 1, size, temp);
	buffer[size] = '\0';

	fclose(temp);
	return buffer;
}

static int _cap_stdout_saved = -1;
static FILE *_cap_stdout_temp = NULL;
static int _cap_stderr_saved = -1;
static FILE *_cap_stderr_temp = NULL;

static char *capture_ast_output(ASTNode *ast) {
	FILE *temp = NULL;
	int saved = _redirect_begin(stdout, &temp);
	ast_print(ast, 0, NULL);
	return _redirect_end(stdout, saved, temp);
}

static FILE *capture_error_begin() {
	_cap_stderr_saved = _redirect_begin(stderr, &_cap_stderr_temp);
	return NULL;
}

static char *capture_error_end(FILE *old_stderr) {
	(void)old_stderr;
	return _redirect_end(stderr, _cap_stderr_saved, _cap_stderr_temp);
}

static FILE *capture_begin() {
	_cap_stdout_saved = _redirect_begin(stdout, &_cap_stdout_temp);
	return NULL;
}

static char *capture_end(FILE *old_stdout) {
	(void)old_stdout;
	return _redirect_end(stdout, _cap_stdout_saved, _cap_stdout_temp);
}
