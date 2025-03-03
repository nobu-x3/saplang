#include "util.h"
#include <stdio.h>

void *report(SourceLocation location, const char *msg, int is_warning) {
	const char *verbosity = is_warning ? "Warning:" : "Error:";
	fprintf(stderr, "%s:%d:%d:%s %s\n", location.path, location.line, location.col, verbosity, msg);
	return NULL;
}
