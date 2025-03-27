#pragma once
#include <parser.h>
#include <stdio.h>
#include <unity.h>

static char *capture_ast_output(ASTNode *ast) {
	// Create a temporary file.
	FILE *temp = tmpfile();
	if (!temp) {
		TEST_FAIL_MESSAGE("Failed to create temporary file for output capture");
	}

	// Save the current stdout pointer.
	FILE *old_stdout = stdout;
	stdout = temp;

	// Print the AST.
	ast_print(ast, 0, NULL);
	fflush(stdout);

	// Restore stdout.
	stdout = old_stdout;

	// Determine the size of the output.
	fseek(temp, 0, SEEK_END);
	long size = ftell(temp);
	fseek(temp, 0, SEEK_SET);

	char *buffer = malloc(size + 1);
	if (!buffer) {
		fclose(temp);
		TEST_FAIL_MESSAGE("Memory allocation failed in captureASTOutput");
	}

	fread(buffer, 1, size, temp);
	buffer[size] = '\0';

	fclose(temp);
	return buffer;
}

static FILE *capture_error_begin() {
	FILE *temp = tmpfile();
	if (!temp) {
		TEST_FAIL_MESSAGE("Failed to create temporary file for output capture");
	}

	// Save the current stdout pointer.
	FILE *old_stdout = stderr;
	stderr = temp;
	return old_stdout;
}

static char *capture_error_end(FILE *old_stderr) {
	fflush(stderr);
	FILE *temp = stderr;
	stderr = old_stderr;
	fseek(temp, 0, SEEK_END);
	long size = ftell(temp);
	fseek(temp, 0, SEEK_SET);

	char *buffer = malloc(size + 1);
	if (!buffer) {
		fclose(temp);
		TEST_FAIL_MESSAGE("Memory allocation failed in captureASTOutput");
	}

	fread(buffer, 1, size, temp);
	buffer[size] = '\0';

	fclose(temp);
	return buffer;
}

static FILE *capture_begin() {
	FILE *temp = tmpfile();
	if (!temp) {
		TEST_FAIL_MESSAGE("Failed to create temporary file for output capture");
	}

	// Save the current stdout pointer.
	FILE *old_stdout = stdout;
	stdout = temp;
	return old_stdout;
}

static char *capture_end(FILE *old_stdout) {
	fflush(stdout);
	FILE *temp = stdout;
	stdout = old_stdout;
	fseek(temp, 0, SEEK_END);
	long size = ftell(temp);
	fseek(temp, 0, SEEK_SET);

	char *buffer = malloc(size + 1);
	if (!buffer) {
		fclose(temp);
		TEST_FAIL_MESSAGE("Memory allocation failed in captureASTOutput");
	}

	fread(buffer, 1, size, temp);
	buffer[size] = '\0';

	fclose(temp);
	return buffer;
}
