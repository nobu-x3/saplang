#include "driver.h"
#include "parser.h"
#include "scanner.h"
#include "timer.h"
#include "util.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, const char **argv) {
	CompileOptions options = {0};
	CHK(compile_options_get(argc, argv, &options));
	if (options.display_help) {
		driver_print_help();
		compile_options_deinit(&options);
		return 0;
	}
	double time_comp, time_sema, time_cfg, time_gen = 0;

	double before = get_time();
	// do parsing
	if (options.show_timings) {
		time_comp = (get_time() - before);
	}

	before = get_time();
	// do sema
	if (options.show_timings) {
		time_sema = (get_time() - before);
	}

	before = get_time();
	// do cfg
	if (options.show_timings) {
		time_cfg = (get_time() - before);
	}

	before = get_time();
	// do codegen
	if (options.show_timings) {
		time_gen = (get_time() - before);
		double total_comp = time_comp + time_sema + time_cfg + time_gen;
		printf("Total compilation: %f sec.\nParsing: %f sec.\nSemantic analysis: %f sec.\nControl flow graph optimizations: %f sec.\nCode generation: %f sec.\n", total_comp, time_comp, time_sema, time_cfg, time_gen);
		/* printf("Total compilation: %d sec (%d msec)\nParsing: %d sec (%d msec)\nSemantic analysis: %d sec (%d msec)\nControl flow graph optimizations: %d sec (%d msec)\nCode generation: %d sec (%d msec)\n", total_comp / 1000, */
		/* 	   total_comp % 1000, time_comp / 1000, time_comp % 1000, time_sema / 1000, time_sema % 1000, time_cfg / 1000, time_cfg % 1000, time_gen / 1000, time_gen % 1000); */
	}

	compile_options_print(&options);
#if 0
	{
		const char *input = "i32 x = 42; "
							"const f64 y = 3.14; "
							"bool flag = true; "
							"i32 a;"
							"struct Point { i32 x; i32 y; } "
							"fn i32 add(i32 a, i32 b) {"
							" i32 result = a + b * 2;"
							" return result - 1;"
							"}";
		const char *path = "test";

		Scanner scanner;
		CHK(scanner_init(&scanner, path, input));

		Parser parser;
		CHK(parser_init(&parser, scanner, NULL));

		ASTNode *ast = parse_input(&parser);
		if (!ast)
			return -1;

		printf("\n --- AST ---\n");
		CHK(ast_print(ast, 0, NULL));

		printf("\n --- Symbol Table ---\n");
		CHK(symbol_table_print(parser.symbol_table, NULL));

		CHK(parser_deinit(&parser));
	}
#endif
	compile_options_deinit(&options);
	return 0;
}
