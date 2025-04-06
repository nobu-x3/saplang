#include "util.h"
#include <stdio.h>

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
