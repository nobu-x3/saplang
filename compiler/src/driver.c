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

#define OBJ_DIRECTORY ".tmp"

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
	if (!da_init(result, 4))
		return result;

	char *cpy = strdup(s);
	char *tmp = cpy;
	char delim_str[2] = {delim, '\0'};
	char *found;
	while ((found = strsep(&cpy, delim_str)) != NULL) {
		char *found_cpy = strdup(found);
		if (!da_push(result, found_cpy)) {
			free(found_cpy);
			break;
		}
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
		} else if (strcmp(arg, "-string") == 0) {
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
	printf("ast_dump: %d\n", opt->ast_dump);
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

typedef enum {
	DG_IN_PROGRESS,
	DG_DONE,
} DGStatus;

// DependencyGraphNode is a linked list which contains a dynamic array of dependencies, parser instance and a string list of imports without extensions. Also contains module, which contains symbol table and AST for that module.
typedef struct DependencyGraphNode {
	char name[64];
	ImportList imports;
	Parser parser;
	DependencyGraphNodeList dependencies;
	DependencyGraphNode *next;
	Module *module;
	DGStatus status;

	// Diagnostics for the current phase are buffered here so that
	// concurrent workers don't interleave bytes on stderr. Opened by the
	// driver before each phase, drained (and freed) in graph order
	// after threadpool_wait_all.
	FILE *diag_sink;
	char *diag_buf;
	size_t diag_buf_size;
} DependencyGraphNode;

typedef struct {
	CompileOptions options;
	SourceList sources;
	DependencyGraphNode *dependency_graph;
	DependencyGraphNode *dependency_graph_tail;
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

void combine_object_paths(StringList *string_list, char *obj_dir) {
	DIR *dir = opendir(obj_dir);
	if (!dir) {
		fprintf(stderr, "could not open obj directory: %d", errno);
		return;
	}
	struct dirent *entry;
	while ((entry = readdir(dir)) != NULL) {
		// Skip current and parent directory entries
		if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
			continue;

		const char *filename = entry->d_name;
		char filepath[1024];
		snprintf(filepath, sizeof(filepath), "%s/%s", obj_dir, filename);
		char *filepath_cpy = strdup(filepath);
		if (!da_push(*string_list, filepath_cpy)) {
			free(filepath_cpy);
			break;
		}
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
		if (!full_path)
			continue;
		strncpy(src_file.name, file_name(name), sizeof(src_file.name));
		strncpy(src_file.path, full_path, sizeof(src_file.path));
		free(full_path);
		FILE *fp = fopen(src_file.path, "r");
		if (!fp) {
			fprintf(stderr, "could not open file with path %s.\n", src_file.path);
			return src_file;
		}
		fseek(fp, 0, SEEK_END);
		long file_size = ftell(fp);
		rewind(fp);
		if (file_size < 0) {
			fprintf(stderr, "failed to determine size of file %s.", src_file.path);
			fclose(fp);
			return src_file;
		}
		char *buffer = malloc((size_t)file_size + 1);
		if (!buffer) {
			fprintf(stderr, "failed to allocate memory when reading file %s.", src_file.path);
			fclose(fp);
			return src_file;
		}
		if (fread(buffer, 1, (size_t)file_size, fp) != (size_t)file_size) {
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

// Open a fresh memstream-backed sink on the node. The driver calls this
// before submitting tasks for a phase; tasks point their thread-local
// sink at node->diag_sink for the duration of their work.
static void dg_diag_open(DependencyGraphNode *node) {
	node->diag_buf = NULL;
	node->diag_buf_size = 0;
	node->diag_sink = open_memstream(&node->diag_buf, &node->diag_buf_size);
}

// Close the sink (which flushes the memstream into diag_buf), copy the
// buffered bytes to `out`, then free the buffer. Idempotent for nodes
// that were never opened or already drained.
static void dg_diag_drain(DependencyGraphNode *node, FILE *out) {
	if (!node->diag_sink)
		return;
	fclose(node->diag_sink);
	node->diag_sink = NULL;
	if (node->diag_buf && node->diag_buf_size > 0) {
		fwrite(node->diag_buf, 1, node->diag_buf_size, out);
	}
	free(node->diag_buf);
	node->diag_buf = NULL;
	node->diag_buf_size = 0;
}

void dg_clean(DependencyGraphNode *graph) {
	while (graph) {
		parser_deinit(&graph->parser);

		for (int i = 0; i < graph->imports.count; ++i) {
			free(graph->imports.data[i]);
		}
		da_deinit(graph->imports);

		if (graph->module)
			module_deinit(graph->module);

		da_deinit(graph->dependencies);

		dg_diag_drain(graph, stderr);

		DependencyGraphNode *next = graph->next;
		free(graph);
		graph = next;
	}
}

typedef struct DGFrame {
	DependencyGraphNode *node;
	struct DGFrame *prev;
} DGFrame;

// Print the cycle path: target -> ... -> current -> target. We walk
// the DFS stack from `current` up until we hit `target`, collecting
// the frames in between, then print forward in import order.
static void report_import_cycle(DGFrame *current, const DependencyGraphNode *target) {
	const DependencyGraphNode *path[256];
	int n = 0;
	int found_target = 0;
	for (DGFrame *f = current; f && n < 256; f = f->prev) {
		path[n++] = f->node;
		if (f->node == target) {
			found_target = 1;
			break;
		}
	}
	if (!found_target) {
		// shouldn't happen - target must be on the stack, just in case
		fprintf(stderr, "import cycle detected involving '%s'.\n", target->name);
		return;
	}
	fprintf(stderr, "import cycle detected:\n");
	// path[0] is `current`, path[n-1] is `target`. Print target first.
	for (int i = n - 1; i >= 0; --i) {
		fprintf(stderr, "  %s ->\n", path[i]->name);
	}
	fprintf(stderr, "  %s\n", target->name);
}

static void dg_chain_append(DependencyGraphNode *node) {
	if (!driver.dependency_graph || driver.dependency_graph == node) {
		driver.dependency_graph = node;
		driver.dependency_graph_tail = node;
		return;
	}
	driver.dependency_graph_tail->next = node;
	driver.dependency_graph_tail = node;
}

static CompilerResult build_dependency_graph_inner(SourceFile input_file, DependencyGraphNode **root, DGFrame *parent_frame) {
	++driver.module_count;

	*root = calloc(sizeof(DependencyGraphNode), 1);

	if (!*root)
		return RESULT_MEMORY_ERROR;

	strncpy((*root)->name, input_file.name, sizeof((*root)->name));
	(*root)->status = DG_IN_PROGRESS;

	if (!da_init((*root)->dependencies, 4))
		return RESULT_MEMORY_ERROR;

	// Register before any recursion so dg_find sees IN_PROGRESS
	// siblings. Cleanup of half-built nodes happens via the outer
	// wrapper's dg_clean across the whole chain; parser_deinit on a
	// calloc'd Parser is safe (frees a NULL scanner buffer).
	dg_chain_append(*root);

	Scanner scanner;
	CompilerResult res = scanner_init_from_src(&scanner, input_file);
	if (res != RESULT_SUCCESS)
		return res;

	res = parser_init(&(*root)->parser, scanner, NULL);
	if (res != RESULT_SUCCESS)
		return res;

	res = parse_import_list(&(*root)->parser, &(*root)->imports);
	if (res != RESULT_SUCCESS)
		return res;

	DGFrame frame = {*root, parent_frame};

	for (int i = 0; i < (*root)->imports.count; ++i) {
		char name[64] = "";
		sprintf(name, "%s.sl", (*root)->imports.data[i]);
		DependencyGraphNode *existing_node = dg_find(name, driver.dependency_graph);
		if (existing_node) {
			if (existing_node->status == DG_IN_PROGRESS) {
				report_import_cycle(&frame, existing_node);
				return RESULT_FAILURE;
			}
			if (!da_push((*root)->dependencies, existing_node))
				return RESULT_MEMORY_ERROR;
			continue;
		}
		SourceFile dep_src = driver_init_source(name);
		DependencyGraphNode *subgraph;
		res = build_dependency_graph_inner(dep_src, &subgraph, &frame);
		if (res != RESULT_SUCCESS)
			return res;

		if (!da_push((*root)->dependencies, subgraph))
			return RESULT_MEMORY_ERROR;
	}

	(*root)->status = DG_DONE;
	return RESULT_SUCCESS;
}

// Builds a dependency graph of the project starting from root. On
// failure, the wrapper drops the whole partially-built chain and clears
// driver.dependency_graph so callers see a clean slate.
CompilerResult build_dependency_graph(SourceFile input_file, DependencyGraphNode **root) {
	// Fresh slate — successive driver_runs (e.g. across test cases) must
	// not see leftover nodes from prior compiles.
	if (driver.dependency_graph) {
		dg_clean(driver.dependency_graph);
		driver.dependency_graph = NULL;
	}
	driver.dependency_graph_tail = NULL;
	driver.module_count = 0;

	CompilerResult res = build_dependency_graph_inner(input_file, root, NULL);
	if (res != RESULT_SUCCESS) {
		dg_clean(driver.dependency_graph);
		driver.dependency_graph = NULL;
		driver.dependency_graph_tail = NULL;
		*root = NULL;
	}
	return res;
}

void parsing_task(void *arg) {
	DependencyGraphNode *node = (DependencyGraphNode *)arg;
	if (!node)
		return;
	diag_set_sink(node->diag_sink);
	// parse_input creates the module and points the type arena at it.
	node->module = parse_input(&node->parser);
	type_arena_set(NULL);
	diag_set_sink(NULL);
}

void sema_task(void *arg) {
	DependencyGraphNode *node = (DependencyGraphNode *)arg;
	if (!node)
		return;

	diag_set_sink(node->diag_sink);
	type_arena_set(&node->module->type_arena);

	if (!node->module->ast) {
		type_arena_set(NULL);
		diag_set_sink(NULL);
		return;
	}

	symbol_table_set_type_info(node->module->symbol_table);

	for (ASTNode *ast_node = node->module->ast; ast_node; ast_node = ast_node->next) {
		int sema_failed = analyze_ast(node->module->symbol_table, ast_node, 0, "") != RESULT_SUCCESS;
		int type_resolution_failed = resolve_types(node->module->symbol_table, ast_node, ast_node == node->module->ast) != RESULT_SUCCESS;
		node->module->has_errors |= sema_failed || type_resolution_failed;
	}

	type_arena_set(NULL);
	diag_set_sink(NULL);
}

void codegen_task(void *arg) {
	DependencyGraphNode *node = (DependencyGraphNode *)arg;
	if (!node)
		return;
	diag_set_sink(node->diag_sink);
	type_arena_set(&node->module->type_arena);
	char source_file_path[PATH_MAX + 1] = "";
	strncpy(source_file_path, node->parser.scanner.source.path, sizeof(source_file_path));
	char *source_dir = dir_name(source_file_path);
	CodegenInitContext cg_init_ctx = {node->parser.module_name, node->parser.scanner.source.name, source_dir, 0};
	CodegenLLVM cg_ctx = codegen_init(&cg_init_ctx);
	codegen_run(&cg_ctx, node->module->ast, node->module->symbol_table);
	int res = make_dir(OBJ_DIRECTORY, 0777);
	if (res == -1 && errno != EEXIST) {
		fprintf(diag_stream(), "failed to create tmp dir for object files with code: %d", errno);
		codegen_deinit(&cg_ctx);
		type_arena_set(NULL);
		diag_set_sink(NULL);
		return;
	}
	char tmp_dir[512] = "";
	full_path(OBJ_DIRECTORY, tmp_dir);
	char obj_path[512] = "";
	snprintf(obj_path, sizeof(obj_path), "%s/tmp-%s.o", tmp_dir, node->parser.module_name);
	codegen_emit_object_file(&cg_ctx, obj_path);
	codegen_deinit(&cg_ctx);
	type_arena_set(NULL);
	diag_set_sink(NULL);
}

CompilerResult driver_run() {
	if (driver.options.display_help) {
		return RESULT_SUCCESS;
	}
	if (codegen_init_native_target() != RESULT_SUCCESS) {
		fprintf(stderr, "failed to initialize native LLVM target / asm printer.\n");
		return RESULT_FAILURE;
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
	if (res != RESULT_SUCCESS) {
		// build_dependency_graph_inner has already dg_clean'd the partial
		// graph (including the input source buffer the scanner claimed)
		// and NULL'd driver.dependency_graph.
		return res;
	}
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
	for (DependencyGraphNode *current = driver.dependency_graph; current != NULL; current = current->next) {
		dg_diag_open(current);
	}
	// Issue parsing tasks
	for (DependencyGraphNode *current = driver.dependency_graph; current != NULL; current = current->next) {
		threadpool_submit_task(thread_pool, parsing_task, current);
	}
	threadpool_wait_all(thread_pool);
	for (DependencyGraphNode *current = driver.dependency_graph; current != NULL; current = current->next) {
		dg_diag_drain(current, stderr);
	}
	for (DependencyGraphNode *current = driver.dependency_graph; current != NULL; current = current->next) {
		if (current->module->has_errors) {
			should_quit = 1;
		}
		if (!should_quit) {
			// symbol_table_merge -> symbol_table_copy -> copy_type, so
			// the copies of imported Types end up in this module's arena.
			type_arena_set(&current->module->type_arena);
			for (int i = 0; i < current->dependencies.count; ++i) {
				current->module->symbol_table = symbol_table_merge(current->dependencies.data[i]->module->exported_table, current->module->symbol_table);
			}
			type_arena_set(NULL);
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
		dg_diag_open(current);
	}
	for (DependencyGraphNode *current = driver.dependency_graph; current != NULL; current = current->next) {
		threadpool_submit_task(thread_pool, sema_task, current);
	}
	threadpool_wait_all(thread_pool);
	for (DependencyGraphNode *current = driver.dependency_graph; current != NULL; current = current->next) {
		dg_diag_drain(current, stderr);
	}
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
	for (DependencyGraphNode *current = driver.dependency_graph; current != NULL; current = current->next) {
		dg_diag_open(current);
	}
	// do codegen
	for (DependencyGraphNode *current = driver.dependency_graph; current != NULL; current = current->next) {
		threadpool_submit_task(thread_pool, codegen_task, current);
	}
	threadpool_wait_all(thread_pool);
	for (DependencyGraphNode *current = driver.dependency_graph; current != NULL; current = current->next) {
		dg_diag_drain(current, stderr);
	}
	StringList cmd;
	char output_file_path_cpy[512] = "";
	strncpy(output_file_path_cpy, driver.options.output_file_path, sizeof(output_file_path_cpy));
	char output_file_path_full[512] = "";
	full_path(output_file_path_cpy, output_file_path_full);
	if (!da_init(cmd, 4))
		return RESULT_MEMORY_ERROR;
	if (!da_push(cmd, strdup("clang")))
		return RESULT_MEMORY_ERROR;
	combine_object_paths(&cmd, OBJ_DIRECTORY);
	if (!da_push(cmd, strdup("-o")))
		return RESULT_MEMORY_ERROR;
	if (!da_push(cmd, strdup(output_file_path_full)))
		return RESULT_MEMORY_ERROR;
	char *final_cmd = flatten_stringlist(&cmd);
	for (int i = 0; i < cmd.count; ++i) {
		free(cmd.data[i]);
	}
	da_deinit(cmd);
	int clang_res = system(final_cmd);
	free(final_cmd);
	if (!driver.options.no_cleanup)
		rmrf(OBJ_DIRECTORY);
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
	if (!da_push(driver.options.import_paths, this_path)) {
		free(this_path);
		compile_options_deinit(&driver.options);
		return RESULT_MEMORY_ERROR;
	}

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
		(void)da_init(driver.options.import_paths, 1);
		(void)da_push(driver.options.import_paths, strdup("."));
	}
}

void driver_deinit() {
	compile_options_deinit(&driver.options);
	// free depdendency graph
	dg_clean(driver.dependency_graph);
}
