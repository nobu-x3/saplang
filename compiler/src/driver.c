#include "driver.h"
#include "codegen.h"
#include "parser.h"
#include "sema.h"
#include "symbol_table.h"
#include "thread_pool.h"
#include "timer.h"
#include "util.h"
#include <errno.h>
#include <linux/limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__linux__) || defined(__unix__)
#include <asm-generic/errno-base.h>
#include <unistd.h>
#endif

#define LL_DIRECTORY ".tmp"

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
	char *tmp = cpy;
	char delim_str[2] = {delim, '\0'};
	char *found;
	while ((found = strsep(&cpy, delim_str)) != NULL) {
		char *found_cpy = strdup(found);
		da_push_unsafe(result, found_cpy);
	}

	free(tmp);

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
		} else if (strcmp(arg, "-h") == 0) {
			options->display_help = 1;
			return RESULT_SUCCESS;
		} else if (strcmp(arg, "-o") == 0) {
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
		else if (strcmp(arg, "-string") == 0) {
			if (options->input_file_path) {
				fprintf(stderr, "input file is already set, cannot additionally set an input string.\n");
				compile_options_deinit(options);
				return RESULT_FAILURE;
			}
			options->input_string = idx + 1 >= argc ? "" : strdup(argv[++idx]);
			options->input_file_path = strdup("input_string.sl");
		} else if (strcmp(arg, "-ast-dump") == 0)
			options->ast_dump = 1;
		else if (strcmp(arg, "-res-dump") == 0)
			options->res_dump = 1;
		else if (strcmp(arg, "-show-timings") == 0)
			options->show_timings = 1;
		else if (strcmp(arg, "-cfg-dump") == 0)
			options->cfg_dump = 1;
		else if (strcmp(arg, "-llvm-dump") == 0)
			options->llvm_dump = 1;
		else if (strcmp(arg, "-dbg") == 0)
			options->gen_debug = 1;
		else if (strcmp(arg, "-no-cleanup") == 0)
			options->no_cleanup = 1;
		else if (strcmp(arg, "-j") == 0) {
			int parsed = atoi(argv[++idx]);
			if (parsed < cpu_count)
				options->threads = parsed;
		} else if (strcmp(arg, "-i") == 0)
			options->import_paths = split(argv[++idx], ';');
		else if (strcmp(arg, "-L") == 0)
			options->library_paths = split(argv[++idx], ';');
		else if (strcmp(arg, "-extra") == 0)
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
	for (int i = 0; i < opt->library_paths.count; ++i) {
		free(opt->library_paths.data[i]);
	}
	da_deinit(opt->library_paths);

	for (int i = 0; i < opt->extra_flags.count; ++i) {
		free(opt->extra_flags.data[i]);
	}
	da_deinit(opt->extra_flags);

	for (int i = 0; i < opt->import_paths.count; ++i) {
		free(opt->import_paths.data[i]);
	}
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
	Module **data;
	int capacity, count;
} ModuleList;

typedef struct DependencyGraphNode DependencyGraphNode;

typedef struct DependencyGraphNodeList {
	DependencyGraphNode **data;
	int capacity, count;
} DependencyGraphNodeList;

// DependencyGraphNode is a linked list which contains a dynamic array of dependencies, parser instance and a string list of imports without extensions. Also contains module, which contains symbol table and AST for that module.
typedef struct DependencyGraphNode {
	char name[64];
	ImportList imports;
	Parser parser;
	DependencyGraphNodeList dependencies;
	DependencyGraphNode *next;
	Module *module;
} DependencyGraphNode;

typedef struct {
	CompileOptions options;
	SourceList sources;
	DependencyGraphNode *dependency_graph;
	int module_count;
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

void combine_ir_paths(StringList *string_list, char *ll_dir) {
	DIR *dir = opendir(ll_dir);
	if (!dir) {
		fprintf(stderr, "could not open ll directory: %d", errno);
		return;
	}
	struct dirent *entry;
	while ((entry = readdir(dir)) != NULL) {
		// Skip current and parent directory entries
		if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
			continue;

		const char *filename = entry->d_name;
		char filepath[1024];
		snprintf(filepath, sizeof(filepath), "%s/%s", ll_dir, filename);
		char *filepath_cpy = strdup(filepath);
		da_push_unsafe_ptr(string_list, filepath_cpy);
	}
	closedir(dir);
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

			if (len > 3 && strcmp(filename + len - 3, ".sl") == 0) {
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
	/* char input_fullpath[PATH_MAX + 1] = ""; */
	/* char *input_ptr = full_path(name, input_fullpath); */
	/* int input_path_len = strlen(input_fullpath); */
	/* if (!input_path_len) { */
	/* 	fprintf(stderr, "could not find input file '%s'.\n", name); */
	/* 	return src_file; */
	/* } */
	for (int i = 0; i < driver.options.import_paths.count; ++i) {
		char *full_path = find_file_in_dir(driver.options.import_paths.data[i], name);
		if (full_path) {
			strncpy(src_file.name, file_name(name), sizeof(src_file.name));
			strncpy(src_file.path, full_path, sizeof(src_file.path));
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
			src_file.len = file_size;
			fclose(fp);
			return src_file;
		}
	}
	return src_file;
}
#endif

DependencyGraphNode *dg_find(const char *name, DependencyGraphNode *root) {
	for (DependencyGraphNode *current = root; current != NULL; current = current->next) {
		if (strcmp(current->name, name) == 0)
			return current;
	}
	return NULL;
}

void dg_clean(DependencyGraphNode *graph) {
	if (!graph)
		return;

	parser_deinit(&graph->parser);

	for (int i = 0; i < graph->imports.count; ++i) {
		free(graph->imports.data[i]);
	}
	da_deinit(graph->imports);

	if (graph->module->ast)
		ast_deinit(graph->module->ast);

	if (graph->module)
		free(graph->module);

	da_deinit(graph->dependencies);

	DependencyGraphNode *next = graph->next;

	free(graph);

	if (next) {
		dg_clean(next);
	}
}

// Builds a dependency graph of the project starting from root. 'DependencyGraphNode::module' field remains untouched.
CompilerResult build_dependency_graph(SourceFile input_file, DependencyGraphNode **root) {
	++driver.module_count;

	*root = calloc(sizeof(DependencyGraphNode), 1);

	if (!*root)
		return RESULT_MEMORY_ERROR;

	strncpy((*root)->name, input_file.name, sizeof((*root)->name));

	da_init_result((*root)->dependencies, 4);

	Scanner scanner;
	CompilerResult res = scanner_init_from_src(&scanner, input_file);
	if (res != RESULT_SUCCESS) {
		dg_clean((*root));
		return res;
	}

	res = parser_init(&(*root)->parser, scanner, NULL);
	if (res != RESULT_SUCCESS) {
		dg_clean((*root));
		return res;
	}

	res = parse_import_list(&(*root)->parser, &(*root)->imports);
	if (res != RESULT_SUCCESS) {
		dg_clean((*root));
		return res;
	}

	DependencyGraphNode *graph_tail = *root;
	for (int i = 0; i < (*root)->imports.count; ++i) {
		// if the node already exists in the (*graph) it must have already been proccessed but we still want to add it to dependencies of the module that is currently being processed.
		char name[64] = "";
		sprintf(name, "%s.sl", (*root)->imports.data[i]);
		DependencyGraphNode *existing_node = dg_find(name, driver.dependency_graph);
		if (existing_node) {
			da_push_safe_result((*root)->dependencies, existing_node, { dg_clean(*root); });
			continue;
		}
		SourceFile dep_src = driver_init_source(name);
		DependencyGraphNode *subgraph;

		if (build_dependency_graph(dep_src, &subgraph) != RESULT_SUCCESS) {
			free(dep_src.buffer);
			dg_clean(*root);
			return RESULT_FAILURE;
		}

		da_push_safe_result((*root)->dependencies, subgraph, {
			free(dep_src.buffer);
			dg_clean(*root);
		});

		while (graph_tail->next) {
			graph_tail = graph_tail->next;
		}
		graph_tail->next = subgraph;
		graph_tail = subgraph;
	}

	return RESULT_SUCCESS;
}

void parsing_task(void *arg) {
	DependencyGraphNode *node = (DependencyGraphNode *)arg;
	// @TODO: make this thread safe
	/* fprintf(stderr, "incorrect argument int parse_task - could not cast to DependencyGraphNode*.\n"); */
	if (!node)
		return;
	// Assume scanner is in 0 pos.
	node->module = parse_input(&node->parser);
}

void sema_task(void *arg) {
	DependencyGraphNode *node = (DependencyGraphNode *)arg;
	if (!node)
		return;

	// @TODO: print error in a thread safe manner
	if (!node->module->ast)
		return;

	symbol_table_set_type_info(node->module->symbol_table);

	for (ASTNode *ast_node = node->module->ast; ast_node; ast_node = ast_node->next) {
		int sema_failed = analyze_ast(node->module->symbol_table, ast_node, 0, "") != RESULT_SUCCESS;
		int type_resolution_failed = resolve_types(node->module->symbol_table, ast_node, ast_node == node->module->ast) != RESULT_SUCCESS;
		node->module->has_errors |= sema_failed || type_resolution_failed;
	}
}

void codegen_task(void *arg) {
	DependencyGraphNode *node = (DependencyGraphNode *)arg;
	if (!node)
		return;
	char source_file_path[PATH_MAX + 1] = "";
	strncpy(source_file_path, node->parser.scanner.source.path, sizeof(source_file_path));
	char *source_dir = dir_name(source_file_path);
	CodegenInitContext cg_init_ctx = {node->parser.module_name, node->parser.scanner.source.name, source_dir, 0};
	CodegenLLVM cg_ctx = codegen_init(&cg_init_ctx);
	codegen_run(&cg_ctx, node->module->ast, node->module->symbol_table);
	char *output = codegen_output_str(&cg_ctx);
	codegen_deinit(&cg_ctx);
	int res = make_dir(LL_DIRECTORY, 0777);
	if (res == -1 && errno != EEXIST) {
		fprintf(stderr, "failed to create tmp dir for LLVM IR with code: %d", errno);
		free(output);
		return;
	}
	char tmp_dir[512] = "";
	char *ptr = full_path(LL_DIRECTORY, tmp_dir);
	char ll_path[512] = "";
	sprintf(ll_path, "%s/tmp-%s.ll", tmp_dir, node->parser.module_name);
	FILE *f = fopen(ll_path, "w");
	if (!f) {
		fprintf(stderr, "failed to create tmp file for LLVM IR at path %s with code: %d", ll_path, errno);
		free(output);
		return;
	}
	fprintf(f, "%s", output);
	fclose(f);
	free(output);
}

CompilerResult driver_run() {
	if (driver.options.display_help) {
		return RESULT_SUCCESS;
	}
	double time_prep, time_comp, time_sema, time_cfg, time_gen = 0;
	double before = get_time();
	////////////////////////// PREP
	SourceFile input_src_file = driver_init_source(driver.options.input_file_path);
	if (!input_src_file.buffer) {
		driver_deinit();
		return 1;
	}
	CompilerResult res = build_dependency_graph(input_src_file, &driver.dependency_graph);
	int available_cores = get_num_of_cores();
	available_cores = driver.module_count > available_cores ? available_cores : driver.module_count;
	ThreadPool *thread_pool = threadpool_create(driver.options.threads ? driver.options.threads : available_cores);
	if (driver.options.show_timings) {
		time_prep = (get_time() - before);
	}
	int should_quit = 0;
	////////////////////////////////////////////////////////
	////////////////////////// PARSING
	before = get_time();
	// Issue parsing tasks
	for (DependencyGraphNode *current = driver.dependency_graph; current != NULL; current = current->next) {
		threadpool_submit_task(thread_pool, parsing_task, current);
	}
	threadpool_wait_all(thread_pool);
	for (DependencyGraphNode *current = driver.dependency_graph; current != NULL; current = current->next) {
		if (current->module->has_errors) {
			should_quit = 1;
		}
		if (!should_quit) {
			for (int i = 0; i < current->dependencies.count; ++i) {
				current->module->symbol_table = symbol_table_merge(current->dependencies.data[i]->module->exported_table, current->module->symbol_table);
			}
		}
	}
	if (driver.options.show_timings) {
		time_comp = (get_time() - before);
	}
	if (driver.options.ast_dump) {
		printf("Parsed tree dump:\n");
		for (DependencyGraphNode *current = driver.dependency_graph; current != NULL; current = current->next) {
			printf("%s:\n", current->name);
			ast_print(current->module->ast, 0, NULL);
			printf("Symbol table:\n");
			symbol_table_print(current->module->symbol_table, NULL);
			printf("External symbol table:\n");
			symbol_table_print(current->module->exported_table, NULL);
			printf("\n");
		}
	}
	if (should_quit)
		return RESULT_FAILURE;
	///////////////////////////////////////////////////////
	////////////////////////// SEMA
	before = get_time();
	for (DependencyGraphNode *current = driver.dependency_graph; current != NULL; current = current->next) {
		threadpool_submit_task(thread_pool, sema_task, current);
	}
	threadpool_wait_all(thread_pool);
	for (DependencyGraphNode *current = driver.dependency_graph; current != NULL; current = current->next) {
		if (current->module->has_errors) {
			fprintf(stderr, "%s failed semantic analysis.\n", current->name);
			printf("%s failed semantic analysis.\n", current->name);
			should_quit = 1;
		}
	}
	if (driver.options.show_timings) {
		time_sema = (get_time() - before);
	}
	if (driver.options.res_dump) {
		printf("Resolved tree dump:\n");
		for (DependencyGraphNode *current = driver.dependency_graph; current != NULL; current = current->next) {
			printf("%s:\n", current->name);
			ast_print(current->module->ast, 0, NULL);
			printf("Symbol table:\n");
			symbol_table_print(current->module->symbol_table, NULL);
			printf("External symbol table:\n");
			symbol_table_print(current->module->exported_table, NULL);
			printf("\n");
		}
	}
	if (should_quit)
		return RESULT_FAILURE;
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
	for (DependencyGraphNode *current = driver.dependency_graph; current != NULL; current = current->next) {
		threadpool_submit_task(thread_pool, codegen_task, current);
	}
	threadpool_wait_all(thread_pool);
	StringList cmd;
	char output_file_path_cpy[512] = "";
	strncpy(output_file_path_cpy, driver.options.output_file_path, sizeof(output_file_path_cpy));
	char output_file_path_full[512] = "";
	char *ptr = full_path(output_file_path_cpy, output_file_path_full);
	da_init_result(cmd, 4);
	da_push_result(cmd, strdup("clang"));
	combine_ir_paths(&cmd, LL_DIRECTORY);
	da_push_result(cmd, strdup("-o"));
	da_push_result(cmd, strdup(output_file_path_full));
	char *final_cmd = flatten_stringlist(&cmd);
	for (int i = 0; i < cmd.count; ++i) {
		free(cmd.data[i]);
	}
	da_deinit(cmd);
	int clang_res = system(final_cmd);
	free(final_cmd);
	if (!driver.options.no_cleanup)
		rmrf(LL_DIRECTORY);
	if (driver.options.show_timings) {
		time_gen = (get_time() - before);
		double total_comp = time_prep + time_comp + time_sema + time_cfg + time_gen;
		printf("Total compilation: %f sec.\nPrep: %f sec. \nParsing: %f sec.\nSemantic analysis: %f sec.\nControl flow graph optimizations: %f sec.\nCode generation: %f sec.\n", total_comp, time_prep, time_comp, time_sema, time_cfg,
			   time_gen);
	}
	/////////////////////////////////////////////////////
	for (DependencyGraphNode *current = driver.dependency_graph; current != NULL; current = current->next) {
		if (current->module->symbol_table)
			deinit_symbol_table(current->module->symbol_table);
		if (current->module->exported_table)
			deinit_symbol_table(current->module->exported_table);
	}
	threadpool_destroy(thread_pool);
	if (clang_res != 0) {
		return RESULT_FAILURE;
	}

	return RESULT_SUCCESS;
}

CompilerResult driver_init(int argc, const char **argv) {
	CHK(compile_options_get(argc, argv, &driver.options), { compile_options_deinit(&driver.options); });
	char *this_path = strdup(".");
	da_push_safe_result(driver.options.import_paths, this_path, { compile_options_deinit(&driver.options); });

	if (driver.options.display_help) {
		driver_print_help();
		return RESULT_SUCCESS;
	}

	CHK(driver_check_paths_for_uniqueness(), { driver_deinit(); });

	return RESULT_SUCCESS;
}

void driver_set_compiler_options(CompileOptions opts) {
	driver.options = opts;
	if (!driver.options.import_paths.count) {
		da_init_unsafe(driver.options.import_paths, 1);
		da_push_unsafe(driver.options.import_paths, strdup("."));
	}
}

void driver_deinit() {
	compile_options_deinit(&driver.options);
	// free depdendency graph
	dg_clean(driver.dependency_graph);
}
