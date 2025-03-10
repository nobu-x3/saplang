#pragma once

#include "util.h"

typedef struct {
	char *input_file_path;
	char *output_file_path;
	char *input_string;
	StringList library_paths;
	StringList extra_flags;
	StringList import_paths;
	int threads;
	int show_timings;
	int gen_debug;
	int display_help;
	int ast_dump;
	int res_dump;
	int cfg_dump;
	int llvm_dump;
	int no_cleanup;
} CompileOptions;

CompilerResult compile_options_get(int argc, const char **argv, CompileOptions *options);

void compile_options_deinit(CompileOptions *opt);

void compile_options_print(CompileOptions *opt);

void driver_print_help();

CompilerResult driver_init(int argc, const char **argv);

CompilerResult driver_run();

void driver_deinit();

// will keep for tests
void driver_set_compiler_options(CompileOptions opts);
