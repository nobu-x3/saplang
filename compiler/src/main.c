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
	CHK(driver_init(argc, argv), {});
	CHK(driver_run(), {});
	driver_deinit();
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
	return 0;
}
