#include "util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <direct.h>
#include <windows.h>
#else
#include <libgen.h>
#include <limits.h>
#include <sys/stat.h>
#include <sys/types.h>
#define __USE_XOPEN_EXTENDED
#include <ftw.h>
#endif

static __thread FILE *thread_diag_sink = NULL;
static __thread const char *thread_src_path = NULL;
static __thread const char *thread_src_buf = NULL;
static __thread size_t thread_src_len = 0;

void diag_set_sink(FILE *sink) {
	thread_diag_sink = sink;
}

void diag_set_source(const char *path, const char *buf, size_t len) {
	thread_src_path = path;
	thread_src_buf = buf;
	thread_src_len = len;
}

FILE *diag_stream(void) {
	return thread_diag_sink ? thread_diag_sink : stderr;
}

void *report(SourceLocation location, const char *msg, int is_warning) {
	const char *verbosity = is_warning ? "Warning:" : "Error:";
	FILE *out = diag_stream();
	fprintf(out, "%s:%d:%d:%s %s\n", location.path, location.line, location.col, verbosity, msg);
	if (thread_src_buf && thread_src_path && strcmp(thread_src_path, location.path) == 0 && location.line > 0 && location.col > 0) {
		const char *p = thread_src_buf;
		const char *end = thread_src_buf + thread_src_len;
		int line = 1;
		while (p < end && line < location.line) {
			if (*p++ == '\n')
				++line;
		}
		if (p < end) {
			const char *line_start = p;
			while (p < end && *p != '\n')
				++p;
			size_t line_len = (size_t)(p - line_start);
			fwrite(line_start, 1, line_len, out);
			fputc('\n', out);
			int target = location.col - 1;
			for (int i = 0; i < target && (size_t)i < line_len; ++i)
				fputc(line_start[i] == '\t' ? '\t' : ' ', out);
			fputc('^', out);
			fputc('\n', out);
		}
	}
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

#if defined(_WIN32)
static int win_find_recursive(const char *dir, const char *target, char *out, size_t outsz) {
	char pattern[PATH_MAX];
	snprintf(pattern, sizeof(pattern), "%s\\*", dir);
	WIN32_FIND_DATAA fd;
	HANDLE h = FindFirstFileA(pattern, &fd);
	if (h == INVALID_HANDLE_VALUE)
		return 0;
	int found = 0;
	do {
		if (strcmp(fd.cFileName, ".") == 0 || strcmp(fd.cFileName, "..") == 0)
			continue;
		char child[PATH_MAX];
		snprintf(child, sizeof(child), "%s\\%s", dir, fd.cFileName);
		if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
			if (win_find_recursive(child, target, out, outsz)) {
				found = 1;
				break;
			}
		} else if (strcmp(fd.cFileName, target) == 0) {
			strncpy(out, child, outsz - 1);
			out[outsz - 1] = '\0';
			found = 1;
			break;
		}
	} while (FindNextFileA(h, &fd));
	FindClose(h);
	return found;
}

static int win_rmrf(const char *path) {
	char pattern[PATH_MAX];
	snprintf(pattern, sizeof(pattern), "%s\\*", path);
	WIN32_FIND_DATAA fd;
	HANDLE h = FindFirstFileA(pattern, &fd);
	if (h != INVALID_HANDLE_VALUE) {
		do {
			if (strcmp(fd.cFileName, ".") == 0 || strcmp(fd.cFileName, "..") == 0)
				continue;
			char child[PATH_MAX];
			snprintf(child, sizeof(child), "%s\\%s", path, fd.cFileName);
			if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
				win_rmrf(child);
			else
				DeleteFileA(child);
		} while (FindNextFileA(h, &fd));
		FindClose(h);
	}
	return RemoveDirectoryA(path) ? 0 : -1;
}
#else

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
#if defined(_WIN32)
	// Literal path first — explicit args must not get swept up by the fallback.
	DWORD attr = GetFileAttributesA(filename);
	if (attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY))
		return strdup(filename);
	char joined[PATH_MAX];
	int written = snprintf(joined, sizeof(joined), "%s/%s", root_dir, filename);
	if (written > 0 && written < (int)sizeof(joined)) {
		attr = GetFileAttributesA(joined);
		if (attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY))
			return strdup(joined);
	}
	// Basename-recursive fallback for bare names like "io.sl".
	char *filename_cpy = strdup(filename);
	char *base_name = filename_cpy;
	for (char *p = filename_cpy; *p; ++p)
		if (*p == '/' || *p == '\\')
			base_name = p + 1;
	char found[PATH_MAX] = "";
	int ok = win_find_recursive(root_dir, base_name, found, sizeof(found));
	free(filename_cpy);
	return ok ? strdup(found) : NULL;
#else
	// Literal path first — explicit args like `module_tests/foo/main.sl` must
	// not get swept up by the basename-recursive nftw fallback below.
	struct stat st;
	if (stat(filename, &st) == 0 && S_ISREG(st.st_mode)) {
		return strdup(filename);
	}
	char joined[PATH_MAX];
	int written = snprintf(joined, sizeof(joined), "%s/%s", root_dir, filename);
	if (written > 0 && written < (int)sizeof(joined)) {
		if (stat(joined, &st) == 0 && S_ISREG(st.st_mode)) {
			return strdup(joined);
		}
	}

	// Basename-recursive fallback for bare names like "io.sl".
	char *filename_cpy = strdup(filename);
	char *base_name = basename(filename_cpy);
	target_filename = base_name;
	found_path[0] = '\0';
	if (nftw(root_dir, find_file_callback, 16, FTW_PHYS) == 1) {
		free(filename_cpy);
		return strdup(found_path);
	} else {
		free(filename_cpy);
		return NULL;
	}
#endif
}

char *full_path(const char *restrict file_name, char *restrict resolved_name) {
#if defined(_WIN32)
	return _fullpath(resolved_name, file_name, PATH_MAX);
#else
	return realpath(file_name, resolved_name);
#endif
}

int make_dir(const char *pathname, int mode) {
#if defined(_WIN32)
	(void)mode;
	return _mkdir(pathname);
#else
	return mkdir(pathname, (mode_t)mode);
#endif
}

char *dir_name(char *pathname) {
#if defined(_WIN32)
	if (!pathname || !*pathname)
		return ".";
	char *last = NULL;
	for (char *p = pathname; *p; ++p)
		if (*p == '/' || *p == '\\')
			last = p;
	if (!last)
		return ".";
	if (last == pathname)
		last[1] = '\0';
	else
		*last = '\0';
	return pathname;
#else
	return dirname(pathname);
#endif
}

#if !defined(_WIN32)
int unlink_cb(const char *fpath, const struct stat *sb, int typeflag, struct FTW *ftwbuf) {
	int rv = remove(fpath);

	if (rv)
		perror(fpath);

	return rv;
}
#endif

int rmrf(char *path) {
#if defined(_WIN32)
	return win_rmrf(path);
#else
	return nftw(path, unlink_cb, 64, FTW_DEPTH | FTW_PHYS);
#endif
}

char *file_name(const char *restrict file_name) {
#if defined(_WIN32)
	const char *base = file_name;
	for (const char *p = file_name; *p; ++p)
		if (*p == '/' || *p == '\\')
			base = p + 1;
	return (char *)base;
#else
	return basename(file_name);
#endif
}
