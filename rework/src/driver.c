#include "driver.h"
#include "timer.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__linux__) || defined(__unix__)
#include <unistd.h>
#endif

int get_num_of_cores() {
#if defined(__linux__) || defined(__unix__)
	return sysconf(_SC_NPROCESSORS_ONLN);
#endif
	// @TODO: do this for windows & mac
	return 1;
}
void driver_print_help() {
	printf("Usage:\n"
		   "compiler [options] <source_file>\n\n"
		   "Options:\n"
		   "\t-h                            display this message.\n"
		   "\t-j NUM                        use NUM threads for compilation. If NUM is more than available, will use all available instead.\n"
		   "\t-i \"IMP1;IMP2;...\"          import paths.\n"
		   "\t-L \"PATH1;PATH2\"            library directories.\n"
		   "\t-string <input_string>        use <input_string> instead of "
		   "<source_file>.\n"
		   "\t-o <file>                     write executable to <file>.\n"
		   "\t-config [Debug|Rel...]        optimization config that's fed to clang. Options: Debug | ReleaseWithDebugInfo | Release. Corresponds to -O0, "
		   "-O3 and -O3 with debug symbols.\n"
		   "\t-ast-dump                     print ast.\n"
		   "\t-res-dump                     print resolved syntax tree.\n"
		   "\t-cfg-dump                     print control flow graph.\n"
		   "\t-dbg                          output debug info.\n"
		   "\t-no-cleanup                   do not remove temporary LLVMIR-files after compilation.\n"
		   "\t-llvm-dump                    print the generated llvm module\n"
		   "\t-show-timings                 prints how long each compilation stage took");
}

StringList split(const char *s, char delim) {
	StringList result;
	da_init_unsafe(result, 4);
	if (!result.data)
		return result;

	char *cpy = strdup(s);
	char *ch = NULL;
	do {
		ch = strtok(cpy, &delim);
		if (ch) {
			da_push_unsafe(result, ch);
		}
		cpy = NULL;
	} while (ch);

	return result;
}

CompilerResult compile_options_get(int argc, const char **argv, CompileOptions *options) {
	if (!options)
		return RESULT_PASSED_NULL_PTR;

	int cpu_count = get_num_of_cores();
	options->threads = cpu_count;

	for (int idx = 1; idx < argc; ++idx) {
		const char *arg = argv[idx];
		if (arg[0] != '-') {
			if (options->input_file_path) {
				fprintf(stderr, "unexpected argument '%s.'\n", arg);
				compile_options_deinit(options);
				return RESULT_FAILURE;
			}
			options->input_file_path = strdup(arg);
		} else if (!strcmp(arg, "-h")) {
			options->display_help = 1;
			return RESULT_SUCCESS;
		} else if (!strcmp(arg, "-o")) {
			options->output_file_path = idx + 1 >= argc ? "" : strdup(argv[++idx]);
		}
		/* else if (arg == "-config") { */
		/*   std::string config = idx + 1 >= argc ? "" : argv[++idx]; */
		/*   if (config == "Debug") */
		/*     optimization_config = OptimizationConfig::Debug; */
		/*   else if (config == "Release") */
		/*     optimization_config = OptimizationConfig::Release; */
		/*   else if (config == "ReleaseWithDebugInfo") */
		/*     optimization_config = OptimizationConfig::ReleaseWithDebugInfo; */
		/*   else */
		/*     error("unexpected argument '" + std::string{arg} + ".'\n"); */
		else if (!strcmp(arg, "-string")) {
			if (options->input_file_path) {
				fprintf(stderr, "input file is already set, cannot additionally set an input string.\n");
				compile_options_deinit(options);
				return RESULT_FAILURE;
			}
			options->input_string = idx + 1 >= argc ? "" : strdup(argv[++idx]);
			options->input_file_path = strdup("input_string.sl");
		} else if (!strcmp(arg, "-ast-dump"))
			options->ast_dump = 1;
		else if (!strcmp(arg, "-res-dump"))
			options->res_dump = 1;
		else if (!strcmp(arg, "-show-timings"))
			options->show_timings = 1;
		else if (!strcmp(arg, "-cfg-dump"))
			options->cfg_dump = 1;
		else if (!strcmp(arg, "-llvm-dump"))
			options->llvm_dump = 1;
		else if (!strcmp(arg, "-dbg"))
			options->gen_debug = 1;
		else if (!strcmp(arg, "-no-cleanup"))
			options->no_cleanup = 1;
		else if (!strcmp(arg, "-j")) {
			int parsed = atoi(argv[++idx]);
			if (parsed < cpu_count)
				options->threads = parsed;
		} else if (!strcmp(arg, "-i"))
			options->import_paths = split(argv[++idx], ';');
		else if (!strcmp(arg, "-L"))
			options->library_paths = split(argv[++idx], ';');
		else if (!strcmp(arg, "-extra"))
			options->extra_flags = split(argv[++idx], ';');
	}
	return RESULT_SUCCESS;
}

void compile_options_deinit(CompileOptions *opt) {
	if (opt->input_file_path) {
		free(opt->input_file_path);
		opt->input_file_path = NULL;
	}
	if (opt->output_file_path) {
		free(opt->output_file_path);
		opt->output_file_path = NULL;
	}
	if (opt->input_string) {
		free(opt->input_string);
		opt->input_string = NULL;
	}
	da_deinit(opt->library_paths);
	da_deinit(opt->extra_flags);
	da_deinit(opt->import_paths);
	opt->threads = 0;
	opt->gen_debug = 0;
	opt->display_help = 0;
	opt->ast_dump = 0;
	opt->res_dump = 0;
	opt->cfg_dump = 0;
	opt->llvm_dump = 0;
	opt->no_cleanup = 0;
}

void compile_options_print(CompileOptions *opt) {
	printf("input_path: %s\n", opt->input_file_path);
	printf("output_path: %s\n", opt->output_file_path);
	printf("input_string: %s\n", opt->input_string);
	printf("library_paths: ");
	for (int i = 0; i < opt->library_paths.count; ++i) {
		printf("%s; ", opt->library_paths.data[i]);
	}
	printf("\n");
	printf("import_paths: ");
	for (int i = 0; i < opt->import_paths.count; ++i) {
		printf("%s; ", opt->import_paths.data[i]);
	}
	printf("\n");
	printf("extra_flags: ");
	for (int i = 0; i < opt->extra_flags.count; ++i) {
		printf("%s; ", opt->extra_flags.data[i]);
	}
	printf("\n");
	printf("threads: %d\n", opt->threads);
	printf("show_timings: %d\n", opt->show_timings);
	printf("gen_debug: %d\n", opt->gen_debug);
	printf("display_help: %d\n", opt->display_help);
	printf("ast_dump: %d\n", opt->display_help);
	printf("res_dump: %d\n", opt->res_dump);
	printf("cfg_dump: %d\n", opt->cfg_dump);
	printf("llvm_dump: %d\n", opt->llvm_dump);
	printf("no_cleanup: %d\n", opt->no_cleanup);
}

typedef struct {
	SourceFile **data;
	int capacity, count;
} SourceList;

typedef struct {
	CompileOptions options;
} Driver;

Driver driver = {0};

// @TODO: do windows & mac
#if defined(__linux__) || defined(__unix__)

#include <dirent.h>

int module_name_is_unique(const char *name) {
	int count = 0;
	for (int i = 0; i < driver.options.import_paths.count; ++i) {
		char filepath[256];
		snprintf(filepath, sizeof(filepath), "%s/%s", driver.options.import_paths.data[i], name);
		FILE *fp = fopen(filepath, "r");
		if (fp) {
			if (count > 0) {
				fclose(fp);
				return 0;
			}
			++count;
			fclose(fp);
		}
	}
	return count == 1;
}

CompilerResult driver_check_paths_for_uniqueness() {
	for (int i = 0; i < driver.options.import_paths.count; ++i) {
		DIR *dir = opendir(driver.options.import_paths.data[i]);
		if (!dir) {
			fprintf(stderr, "could not open directory '%s'.\n", driver.options.import_paths.data[i]);
			return RESULT_DIRECTORY_NOT_FOUND;
		}
		struct dirent *entry;
		while ((entry = readdir(dir)) != NULL) {
			// Skip current and parent directory entries
			if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
				continue;

			const char *filename = entry->d_name;
			size_t len = strlen(filename);

			if (len > 3 && !strcmp(filename + len - 3, ".sl")) {
				char filepath[1024];
				snprintf(filepath, sizeof(filepath), "%s/%s", driver.options.import_paths.data[i], filename);

				if (!module_name_is_unique(filename)) {
					closedir(dir);
					fprintf(stderr, "duplicate file on path %s.\n", filepath);
					return RESULT_FAILURE;
				}
			}
		}
		closedir(dir);
	}
	return RESULT_SUCCESS;
}

SourceFile driver_init_source(const char *name) {
	SourceFile src_file = {0};
	for (int i = 0; i < driver.options.import_paths.count; ++i) {
		DIR *dir = opendir(driver.options.import_paths.data[i]);
		if (!dir) {
			fprintf(stderr, "could not open directory '%s'.\n", driver.options.import_paths.data[i]);
			return src_file;
		}
		struct dirent *entry;
		while ((entry = readdir(dir)) != NULL) {
			strncpy(src_file.name, entry->d_name, sizeof(src_file.name));

			size_t len = strlen(src_file.name);

			if (len > 3 && !strcmp(src_file.name + len - 3, ".sl")) {
				snprintf(src_file.path, sizeof(src_file.path), "%s/%s", driver.options.import_paths.data[i], src_file.name);

				FILE *fp = fopen(src_file.path, "r");
				if (!fp) {
					fprintf(stderr, "could not open file with path %s.\n", src_file.path);
					return src_file;
				}

				fseek(fp, 0, SEEK_END);
				long file_size = ftell(fp);
				rewind(fp);

				char *buffer = malloc(file_size + 1);
				if (!buffer) {
					fprintf(stderr, "failed to allocate memory when reading file %s.", src_file.path);
					fclose(fp);
					return src_file;
				}

				if (fread(buffer, 1, file_size, fp) != file_size) {
					fprintf(stderr, "failed to read file %s.", src_file.path);
					free(buffer);
					fclose(fp);
					return src_file;
				}
				buffer[file_size] = '\0';
				src_file.buffer = buffer;
				fclose(fp);
			}
		}
		closedir(dir);
	}
	return src_file;
}
#endif

CompilerResult driver_run() {
    if(driver.options.display_help) {
        return RESULT_SUCCESS;
    }

	double time_prep, time_comp, time_sema, time_cfg, time_gen = 0;

	////////////////////////// PREP
	double before = get_time();
	SourceFile test_file = driver_init_source("test.sl");

	if (!test_file.buffer) {
		driver_deinit();
		return 1;
	}

	printf("%s\n", test_file.buffer);

	free(test_file.buffer);

	if (driver.options.show_timings) {
		time_prep = (get_time() - before);
	}
	////////////////////////////////////////////////////////
	////////////////////////// PARSING
	before = get_time();

	if (driver.options.show_timings) {
		time_comp = (get_time() - before);
	}
	///////////////////////////////////////////////////////
	////////////////////////// SEMA
	before = get_time();
	// do sema
	if (driver.options.show_timings) {
		time_sema = (get_time() - before);
	}
	//////////////////////////////////////////////////////
	//////////////////////// CFG
	before = get_time();
	// do cfg
	if (driver.options.show_timings) {
		time_cfg = (get_time() - before);
	}
	/////////////////////////////////////////////////////
	////////////////////// CODEGEN
	before = get_time();
	// do codegen
	if (driver.options.show_timings) {
		time_gen = (get_time() - before);
		double total_comp = time_prep + time_comp + time_sema + time_cfg + time_gen;
		printf("Total compilation: %f sec.\nPrep: %f sec. \nParsing: %f sec.\nSemantic analysis: %f sec.\nControl flow graph optimizations: %f sec.\nCode generation: %f sec.\n", total_comp, time_prep, time_comp, time_sema, time_cfg,
			   time_gen);
	}
	/////////////////////////////////////////////////////

	return RESULT_SUCCESS;
}

CompilerResult driver_init(int argc, const char **argv) {
	CHK(compile_options_get(argc, argv, &driver.options), { compile_options_deinit(&driver.options); });
	if (driver.options.display_help) {
		driver_print_help();
		return RESULT_SUCCESS;
	}

	CHK(driver_check_paths_for_uniqueness(), { driver_deinit(); });

	return RESULT_SUCCESS;
}

void driver_set_compiler_options(CompileOptions opts) { driver.options = opts; }

void driver_deinit() { compile_options_deinit(&driver.options); }
