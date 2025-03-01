#include "scanner.h"
#include "parser.h"

int main() {
  const char *input = "i32 x = 42; "
                      "f64 y = 3.14; "
                      "bool flag = true; "
                      "struct Point { i32 x; i32 y; }; "
                      "fn i32 add(i32 a, i32 b) {"
                      " i32 result = a + b;"
                      " return result;"
                      "}";

}
