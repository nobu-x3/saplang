#include "util.h"
#include <stdio.h>
#include <string.h>

#if defined(__linux__) || defined(__unix__)
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <libgen.h>
#endif

void *report(SourceLocation location, const char *msg, int is_warning) {
	const char *verbosity = is_warning ? "Warning:" : "Error:";
	fprintf(stderr, "%s:%d:%d:%s %s\n", location.path, location.line, location.col, verbosity, msg);
	return NULL;
}

unsigned long djb2(const char *str) {
	unsigned long hash = 5381;
	int c;

	while ((c = *str++)) {
		// hash * 33 + c
		hash = ((hash << 5) + hash) + c;
	}

	return hash;
}

char *flatten_stringlist(const StringList *list) {
	if (list == NULL || list->count == 0) return strdup("");

	// First calculate the total length needed
	size_t total_length = 0;
	for (int i = 0; i < list->count; i++) {
		total_length += strlen(list->data[i]);
	}

	// Add space for the spaces and null terminator
	total_length += list->count - 1 + 1;

	char *result = malloc(total_length);
	if (!result) return NULL;

	result[0] = '\0';
	for (int i = 0; i < list->count; i++) {
		strcat(result, list->data[i]);
		if (i < list->count - 1) strcat(result, " ");
	}

	return result;
}

char *full_path(const char *restrict file_name, char *restrict resolved_name) {
#if defined(__linux__) || defined(__unix__)
	return realpath(file_name, resolved_name);
#else
	printf("full_path only implemented for linux\n");
	return NULL;
#endif
}

int make_dir(const char* pathname, int mode) {
	#if defined(__linux__) || defined(__unix__)
	return mkdir(pathname, (mode_t)mode);
#else
	printf("mkdir only implemented for linux\n");
	return NULL;
#endif
}

char* dir_name(char* pathname) {
	#if defined(__linux__) || defined(__unix__)
	return dirname(pathname);
#else
	printf("mkdir only implemented for linux\n");
	return NULL;
#endif
}