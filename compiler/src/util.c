#include "util.h"
#include <stdio.h>
#include <string.h>

#if defined(__linux__) || defined(__unix__)
#include <libgen.h>
#include <limits.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/types.h>
#define __USE_XOPEN_EXTENDED
#include <ftw.h>
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
	if (list == NULL || list->count == 0)
		return strdup("");

	// First calculate the total length needed
	size_t total_length = 0;
	for (int i = 0; i < list->count; i++) {
		total_length += strlen(list->data[i]);
	}

	// Add space for the spaces and null terminator
	total_length += list->count - 1 + 1;

	char *result = malloc(total_length);
	if (!result)
		return NULL;

	result[0] = '\0';
	for (int i = 0; i < list->count; i++) {
		strcat(result, list->data[i]);
		if (i < list->count - 1)
			strcat(result, " ");
	}

	return result;
}

#if defined(__linux__) || defined(__unix__)

static const char *target_filename;
static char found_path[PATH_MAX];

int find_file_callback(const char *fpath, const struct stat *sb, int type_flag, struct FTW *ftwbuf) {
	if (type_flag == FTW_F) {
		const char *fname = strrchr(fpath, '/');
		if (fname)
			++fname;
		else
			fname = fpath;
		if (strcmp(fname, target_filename) == 0) {
			strncpy(found_path, fpath, sizeof(found_path) - 1);
			return 1; // stop traversal
		}
	}
	return 0; // continue
}
#endif

char *find_file_in_dir(const char *root_dir, const char *filename) {
#if defined(__linux__) || defined(__unix__)
	target_filename = filename;
	found_path[0] = '\0';
	if (nftw(root_dir, find_file_callback, 16, FTW_PHYS) == 1) {
		return strdup(found_path);
	} else {
		return NULL;
	}
#else
	printf("find_file_in_dir only implemented for linux\n");
	return NULL;
#endif
}

char *full_path(const char *restrict file_name, char *restrict resolved_name) {
#if defined(__linux__) || defined(__unix__)
	return realpath(file_name, resolved_name);
#else
	printf("full_path only implemented for linux\n");
	return NULL;
#endif
}

int make_dir(const char *pathname, int mode) {
#if defined(__linux__) || defined(__unix__)
	return mkdir(pathname, (mode_t)mode);
#else
	printf("mkdir only implemented for linux\n");
	return NULL;
#endif
}

char *dir_name(char *pathname) {
#if defined(__linux__) || defined(__unix__)
	return dirname(pathname);
#else
	printf("mkdir only implemented for linux\n");
	return NULL;
#endif
}

#if defined(__linux__) || defined(__unix__)
int unlink_cb(const char *fpath, const struct stat *sb, int typeflag, struct FTW *ftwbuf) {
	int rv = remove(fpath);

	if (rv)
		perror(fpath);

	return rv;
}
#endif

int rmrf(char *path) {
#if defined(__linux__) || defined(__unix__)
	return nftw(path, unlink_cb, 64, FTW_DEPTH | FTW_PHYS);
#else
	printf("mkdir only implemented for linux\n");
	return NULL;
#endif
}

char *file_name(const char *restrict file_name) {
#if defined(__linux__) || defined(__unix__)
	return basename(file_name);
#else
	printf("mkdir only implemented for linux\n");
	return NULL;
#endif
}
