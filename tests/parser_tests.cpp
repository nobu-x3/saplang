#include "catch2/catch_test_macros.hpp"
#include "test_utils.h"

#define TEST_SETUP(file_contents)                                                                                                                              \
  saplang::clear_error_stream();                                                                                                                               \
  std::stringstream buffer{file_contents};                                                                                                                     \
  std::stringstream output_buffer{};                                                                                                                           \
  saplang::SourceFile src_file{"test", buffer.str()};                                                                                                          \
  saplang::Lexer lexer{src_file};                                                                                                                              \
  saplang::Parser parser(&lexer, {{}, false});                                                                                                                 \
  auto parse_result = parser.parse_source_file();                                                                                                              \
  for (auto &&fn : parse_result.module->declarations) {                                                                                                        \
    fn->dump_to_stream(output_buffer);                                                                                                                         \
  }                                                                                                                                                            \
  const auto &error_stream = saplang::get_error_stream();

#define TEST_SETUP_MODULE_SINGLE(module_name, file_contents)                                                                                                   \
  saplang::clear_error_stream();                                                                                                                               \
  std::stringstream buffer{file_contents};                                                                                                                     \
  std::stringstream output_buffer{};                                                                                                                           \
  saplang::SourceFile src_file{module_name, buffer.str()};                                                                                                     \
  saplang::Lexer lexer{src_file};                                                                                                                              \
  saplang::Parser parser(&lexer, {{}, false});                                                                                                                 \
  auto parse_result = parser.parse_source_file();                                                                                                              \
  parse_result.module->dump_to_stream(output_buffer);                                                                                                          \
  const auto &error_stream = saplang::get_error_stream();

TEST_CASE("Function declarations", "[parser]") {
  SECTION("Undeclared function name") {
    TEST_SETUP(R"(fn{}))");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() == "test:1:3 error: expected type specifier.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("expected function identifier") {
    TEST_SETUP(R"(fn int{}))");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() == "test:1:7 error: expected function identifier.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("expected '('") {
    TEST_SETUP(R"(fn int f{}))");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() == "test:1:9 error: expected '('.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("expected parameter declaration") {
    TEST_SETUP(R"(fn int f({})");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() == "test:1:10 error: expected type specifier.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("expected parameter identifier") {
    TEST_SETUP(R"(fn int f(int{})");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() == "test:1:13 error: expected ')'.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("Expected '{'") {
    TEST_SETUP(R"(fn int f(int a)})");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            R"(test:1:16 error: expected '{' at the beginning of a block.
test:1:16 error: failed to parse function block.
)");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("Expected '}'") {
    TEST_SETUP(R"(fn int f(int a){)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            R"(test:1:17 error: expected '}' at the end of a block.
test:1:17 error: failed to parse function block.
)");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("Forward decl attempt") {
    TEST_SETUP(R"(fn int f(int a);)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            R"(test:1:16 error: expected '{' at the beginning of a block.
test:1:16 error: failed to parse function block.
)");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("Correct function declaration") {
    TEST_SETUP(R"(fn int f(int a){})");
    REQUIRE(output_buffer.str() == R"(FunctionDecl: f:int
  ParamDecl: a:int
  Block
)");
    REQUIRE(error_stream.str().empty());
    REQUIRE(parser.is_complete_ast());
  }
  SECTION("Multiple function declarations") {
    TEST_SETUP(R"(
fn int f(int a){}
fn void foo(){}
fn void bar(){}
)");
    REQUIRE(output_buffer.str() ==
            R"(FunctionDecl: f:int
  ParamDecl: a:int
  Block
FunctionDecl: foo:void
  Block
FunctionDecl: bar:void
  Block
)");
    REQUIRE(error_stream.str().empty());
    REQUIRE(parser.is_complete_ast());
  }
}

TEST_CASE("Blocks", "[parser]") {
  SECTION("Expected '}' at the end of block") {
    TEST_SETUP(R"(
fn void bar(){
fn void main(){
)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            R"(test:3:1 error: expected '}' at the end of a block.
test:3:1 error: failed to parse function block.
test:4:1 error: expected '}' at the end of a block.
test:4:1 error: failed to parse function block.
)");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("Proper syntax") {
    TEST_SETUP("fn void f(){}");
    auto lines = break_by_line(output_buffer.str());
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("FunctionDecl: f:void") != std::string::npos);
    CONTAINS_NEXT_REQUIRE(lines_it, "Block");
    REQUIRE(error_stream.str().empty());
    REQUIRE(parser.is_complete_ast());
  }
}

TEST_CASE("Primary", "[parser]") {
  SECTION("Incorrect number literals") {
    TEST_SETUP(
        R"(
fn void main() {
    .0;
    0.;
}
)");
    REQUIRE(error_stream.str() == "test:3:6 error: expected '{' in struct literal initialization.\ntest:4:5 error: expected '}' at the end of a "
                                  "block.\ntest:4:5 error: failed to parse function block.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("Correct number literals") {
    TEST_SETUP(R"(
fn void main(){
    1;
    1.0;
    true;
    false;
}
)");
    REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    NumberLiteral: integer(1)
    NumberLiteral: real(1.0)
    NumberLiteral: bool(true)
    NumberLiteral: bool(false)
)");
    REQUIRE(error_stream.str().empty());
    REQUIRE(parser.is_complete_ast());
  }
  SECTION("Incorrect function calls") {
    TEST_SETUP(
        R"(
fn void main() {
    a(;
    a(x;
    a(x,;
}
)");
    REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
)");
    REQUIRE(error_stream.str() == R"(test:3:7 error: expected expression.
test:4:8 error: expected ')'.
test:5:9 error: expected expression.
)");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("Correct function calls") {
    TEST_SETUP(R"(
fn void main() {
    a;
    a();
    a(1.0, 2);
    a(true);
    a(false);
}
)");
    REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    DeclRefExpr: a
    CallExpr:
      DeclRefExpr: a
    CallExpr:
      DeclRefExpr: a
      NumberLiteral: real(1.0)
      NumberLiteral: integer(2)
    CallExpr:
      DeclRefExpr: a
      NumberLiteral: bool(true)
    CallExpr:
      DeclRefExpr: a
      NumberLiteral: bool(false)
)");
    REQUIRE(error_stream.str().empty());
    REQUIRE(parser.is_complete_ast());
  }
}

TEST_CASE("Missing semicolon", "[parser]") {
  TEST_SETUP(R"(
fn void main() {
    a(1.0, 2)
}
)");
  REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
)");
  REQUIRE(error_stream.str() ==
          R"(test:4:1 error: expected ';' at the end of expression.
)");
  REQUIRE(!parser.is_complete_ast());
}

TEST_CASE("Parameter list", "[parser]") {
  SECTION("fn void f({}") {
    TEST_SETUP(R"(
fn void f({}
)");
    REQUIRE(output_buffer.str().size() == 0);
    REQUIRE(error_stream.str() ==
            R"(test:2:11 error: expected type specifier.
)");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("fn void f(x){}") {
    TEST_SETUP(R"(
fn void f(x){}
)");
    REQUIRE(!output_buffer.str().empty());
    REQUIRE(error_stream.str() == "");
    REQUIRE(parser.is_complete_ast());
  }
  SECTION("fn void f(1.0 x){}") {
    TEST_SETUP("fn void f(1.0 x){}");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            R"(test:1:11 error: expected type specifier.
)");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("fn void f(int a{}") {
    TEST_SETUP("fn void f(int a{}");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() == "test:1:16 error: expected ')'.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("fn void f(int a,){}") {
    TEST_SETUP("fn void f(int a,){}");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() == "test:1:17 error: expected type specifier.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("fn void foo(i32 a, i32 b){}") {
    TEST_SETUP("fn void foo(i32 a, i32 b){}");
    REQUIRE(output_buffer.str() == R"(FunctionDecl: foo:void
  ParamDecl: a:i32
  ParamDecl: b:i32
  Block
)");
    REQUIRE(error_stream.str().empty());
    REQUIRE(parser.is_complete_ast());
  }
}

TEST_CASE("Return statement", "[parser]") {
  SECTION("return |;") {
    TEST_SETUP("fn void foo(){return |;}");
    REQUIRE(output_buffer.str() == R"(FunctionDecl: foo:void
  Block
)");
    REQUIRE(error_stream.str() == "test:1:22 error: expected expression.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("return 0 |;") {
    TEST_SETUP("fn void foo(){return 0 |;}");
    REQUIRE(output_buffer.str() == R"(FunctionDecl: foo:void
  Block
)");
    REQUIRE(error_stream.str() == "test:1:25 error: expected expression.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("return 1;") {
    TEST_SETUP("fn void foo() {return 1;}");
    REQUIRE(output_buffer.str() ==
            R"(FunctionDecl: foo:void
  Block
    ReturnStmt
      NumberLiteral: integer(1)
)");
    REQUIRE(error_stream.str().empty());
    REQUIRE(parser.is_complete_ast());
  }
  SECTION("return bool;") {
    TEST_SETUP(R"(
fn bool foo() {return true;}
fn bool bar() {return false;}
)");
    REQUIRE(output_buffer.str() == R"(FunctionDecl: foo:bool
  Block
    ReturnStmt
      NumberLiteral: bool(true)
FunctionDecl: bar:bool
  Block
    ReturnStmt
      NumberLiteral: bool(false)
)");
    REQUIRE(error_stream.str().empty());
    REQUIRE(parser.is_complete_ast());
  }
  SECTION("return;") {
    TEST_SETUP("fn void foo() {return;}");
    REQUIRE(output_buffer.str() == R"(FunctionDecl: foo:void
  Block
    ReturnStmt
)");
    REQUIRE(error_stream.str().empty());
    REQUIRE(parser.is_complete_ast());
  }
}

TEST_CASE("Error recovery functions", "[parser]") {
  TEST_SETUP(R"(
fn error() {
    int number = 1 + 2;
}

fn int main() {
    return 1;
}

fn int error2({
  return 1;
}

fn void error3(){
  return;

fn int pass() {
  return 2;
}
)");
  REQUIRE(error_stream.str() ==
          R"(test:2:9 error: expected function identifier.
test:10:15 error: expected type specifier.
test:17:1 error: expected '}' at the end of a block.
test:17:1 error: failed to parse function block.
)");
  REQUIRE(output_buffer.str() == R"(FunctionDecl: main:int
  Block
    ReturnStmt
      NumberLiteral: integer(1)
FunctionDecl: pass:int
  Block
    ReturnStmt
      NumberLiteral: integer(2)
)");
  REQUIRE(!parser.is_complete_ast());
}

TEST_CASE("Error recovery semicolon", "[parser]") {
  TEST_SETUP(R"(
fn void error(){
i32 x = ;

1.0;

f32 z =;
}
)");
  REQUIRE(output_buffer.str() ==
          R"(FunctionDecl: error:void
  Block
    NumberLiteral: real(1.0)
)");
  REQUIRE(error_stream.str() ==
          R"(test:3:5 error: expected ';' at the end of expression.
test:7:5 error: expected ';' at the end of expression.
)");
  REQUIRE(!parser.is_complete_ast());
}

TEST_CASE("Unary operations", "[parser]") {
  SECTION("Function returning with unary ops") {
    TEST_SETUP(R"(
fn i32 foo() {
    return -1;
}

fn i32 main() {
    return -1;
}
)");
    REQUIRE(error_stream.str() == "");
  }
}

TEST_CASE("Binary operators", "[parser]") {
  SECTION("Number literal and symbol") {
    TEST_SETUP(R"(
fn void main() {
  1 + |;
  1 +;
  1 + 1.0 + |;
  1 + 1.0 * |;
}
)");
    REQUIRE(error_stream.str() == R"(test:3:7 error: expected expression.
test:4:6 error: expected expression.
test:5:13 error: expected expression.
test:6:13 error: expected expression.
)");
  }
  SECTION("Grouping") {
    SECTION("Pure *") {
      TEST_SETUP(R"(
fn void main() {
  1 * 1.0 * 2;
}
)");
      REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    BinaryOperator: '*'
      BinaryOperator: '*'
        NumberLiteral: integer(1)
        NumberLiteral: real(1.0)
      NumberLiteral: integer(2)
)");
      REQUIRE(error_stream.str() == "");
    }
    SECTION("Pure /") {
      TEST_SETUP(R"(
fn void main() {
  1 / 1.0 / 2;
}
)");
      REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    BinaryOperator: '/'
      BinaryOperator: '/'
        NumberLiteral: integer(1)
        NumberLiteral: real(1.0)
      NumberLiteral: integer(2)
)");
      REQUIRE(error_stream.str() == "");
    }
    SECTION("Pure +") {
      TEST_SETUP(R"(
fn void main() {
  1 + 1.0 + 2;
}
)");
      REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    BinaryOperator: '+'
      BinaryOperator: '+'
        NumberLiteral: integer(1)
        NumberLiteral: real(1.0)
      NumberLiteral: integer(2)
)");
      REQUIRE(error_stream.str() == "");
    }
    SECTION("Pure -") {
      TEST_SETUP(R"(
fn void main() {
  1 - 1.0 - 2;
}
)");
      REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    BinaryOperator: '-'
      BinaryOperator: '-'
        NumberLiteral: integer(1)
        NumberLiteral: real(1.0)
      NumberLiteral: integer(2)
)");
      REQUIRE(error_stream.str() == "");
    }
    SECTION("Mixed * /") {
      TEST_SETUP(R"(
fn void main() {
  1 * 1.0 / 2;
}
)");
      REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    BinaryOperator: '/'
      BinaryOperator: '*'
        NumberLiteral: integer(1)
        NumberLiteral: real(1.0)
      NumberLiteral: integer(2)
)");
      REQUIRE(error_stream.str() == "");
    }
    SECTION("Mixed + -") {
      TEST_SETUP(R"(
fn void main() {
  1 + 1.0 - 2;
}
)");
      REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    BinaryOperator: '-'
      BinaryOperator: '+'
        NumberLiteral: integer(1)
        NumberLiteral: real(1.0)
      NumberLiteral: integer(2)
)");
      REQUIRE(error_stream.str() == "");
    }
    SECTION("Mixed + * +") {
      TEST_SETUP(R"(
fn void main() {
  1 + 2 * 3 + 4;
}
)");
      REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    BinaryOperator: '+'
      BinaryOperator: '+'
        NumberLiteral: integer(1)
        BinaryOperator: '*'
          NumberLiteral: integer(2)
          NumberLiteral: integer(3)
      NumberLiteral: integer(4)
)");
      REQUIRE(error_stream.str() == "");
    }
    SECTION("Mixed + / +") {
      TEST_SETUP(R"(
fn void main() {
  1 + 2 / 3 - 4;
}
)");
      REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    BinaryOperator: '-'
      BinaryOperator: '+'
        NumberLiteral: integer(1)
        BinaryOperator: '/'
          NumberLiteral: integer(2)
          NumberLiteral: integer(3)
      NumberLiteral: integer(4)
)");
      REQUIRE(error_stream.str() == "");
    }
    SECTION("Pure < <") {
      TEST_SETUP(R"(
fn void main() {
  1 < 2 < 3;
}
)");
      REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    BinaryOperator: '<'
      BinaryOperator: '<'
        NumberLiteral: integer(1)
        NumberLiteral: integer(2)
      NumberLiteral: integer(3)
)");
      REQUIRE(error_stream.str() == "");
    }
    SECTION("Pure > >") {
      TEST_SETUP(R"(
fn void main() {
  1 > 2 > 3;
}
)");
      REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    BinaryOperator: '>'
      BinaryOperator: '>'
        NumberLiteral: integer(1)
        NumberLiteral: integer(2)
      NumberLiteral: integer(3)
)");
      REQUIRE(error_stream.str() == "");
    }
    SECTION("Pure == ==") {
      TEST_SETUP(R"(
fn void main() {
  1 == 2 == 3;
}
)");
      REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    BinaryOperator: '=='
      BinaryOperator: '=='
        NumberLiteral: integer(1)
        NumberLiteral: integer(2)
      NumberLiteral: integer(3)
)");
      REQUIRE(error_stream.str() == "");
    }
    SECTION("Pure != !=") {
      TEST_SETUP(R"(
fn void main() {
  1 != 2 != 3;
}
)");
      REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    BinaryOperator: '!='
      BinaryOperator: '!='
        NumberLiteral: integer(1)
        NumberLiteral: integer(2)
      NumberLiteral: integer(3)
)");
      REQUIRE(error_stream.str() == "");
    }
    SECTION("Pure <= <=") {
      TEST_SETUP(R"(
fn void main() {
  1 <= 2 <= 3;
}
)");
      REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    BinaryOperator: '<='
      BinaryOperator: '<='
        NumberLiteral: integer(1)
        NumberLiteral: integer(2)
      NumberLiteral: integer(3)
)");
      REQUIRE(error_stream.str() == "");
    }
    SECTION("Pure >= >=") {
      TEST_SETUP(R"(
fn void main() {
  1 >= 2 >= 3;
}
)");
      REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    BinaryOperator: '>='
      BinaryOperator: '>='
        NumberLiteral: integer(1)
        NumberLiteral: integer(2)
      NumberLiteral: integer(3)
)");
      REQUIRE(error_stream.str() == "");
    }
    SECTION("Pure && &&") {
      TEST_SETUP(R"(
fn void main() {
  1 && 2 && 3;
}
)");
      REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    BinaryOperator: '&&'
      BinaryOperator: '&&'
        NumberLiteral: integer(1)
        NumberLiteral: integer(2)
      NumberLiteral: integer(3)
)");
      REQUIRE(error_stream.str() == "");
    }
    SECTION("Pure || ||") {
      TEST_SETUP(R"(
fn void main() {
  1 || 2 || 3;
}
)");
      REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    BinaryOperator: '||'
      BinaryOperator: '||'
        NumberLiteral: integer(1)
        NumberLiteral: integer(2)
      NumberLiteral: integer(3)
)");
      REQUIRE(error_stream.str() == "");
    }
    SECTION("Mixed || && && (||)") {
      TEST_SETUP(R"(
fn void main() {
  1 || 2 && 3 && (4 || 5);
}
)");
      REQUIRE(error_stream.str() == "");
      REQUIRE(output_buffer.str() == R"(FunctionDecl: main:void
  Block
    BinaryOperator: '||'
      NumberLiteral: integer(1)
      BinaryOperator: '&&'
        BinaryOperator: '&&'
          NumberLiteral: integer(2)
          NumberLiteral: integer(3)
        GroupingExpr:
          BinaryOperator: '||'
            NumberLiteral: integer(4)
            NumberLiteral: integer(5)
)");
      REQUIRE(error_stream.str() == "");
    }
  }
}

TEST_CASE("if statements", "[parser]") {
  SECTION("missing condition") {
    TEST_SETUP(R"(
fn i32 main() {
  if {}
}
)");
    REQUIRE(error_stream.str() == "test:3:6 error: expected expression.\n");
  }
  SECTION("missing body") {
    TEST_SETUP(R"(
fn i32 main() {
  if (false) ({}

  if(false) {}
  else ({}

  if false {}
  else if {}
  else {}
}
)");
    REQUIRE(error_stream.str() ==
            R"(test:3:14 error: expected '{' at the beginning of a block.
test:5:3 error: expected 'else' block.
test:9:11 error: expected expression.
test:10:3 error: expected expression.
)");
  }
  SECTION("single if") {
    TEST_SETUP(R"(
fn i32 main() {
  if (false) {}

  if false {}
}
)");
    REQUIRE(error_stream.str() == "");
    REQUIRE(output_buffer.str() == R"(FunctionDecl: main:i32
  Block
    IfStmt
      GroupingExpr:
        NumberLiteral: bool(false)
      IfBlock
        Block
    IfStmt
      NumberLiteral: bool(false)
      IfBlock
        Block
)");
  }
  SECTION("single if else") {
    TEST_SETUP(R"(
fn i32 main() {
  if (false) {}
  else {}

  if false {}
  else {}
}
)");
    REQUIRE(error_stream.str() == "");
    REQUIRE(output_buffer.str() == R"(FunctionDecl: main:i32
  Block
    IfStmt
      GroupingExpr:
        NumberLiteral: bool(false)
      IfBlock
        Block
      ElseBlock
        Block
    IfStmt
      NumberLiteral: bool(false)
      IfBlock
        Block
      ElseBlock
        Block
)");
  }
  SECTION("if else if") {
    TEST_SETUP(R"(
fn i32 main() {
  if (false) {}
  else if (true) {}
  else if(false) {}
  else {}

  if false {}
  else if true {}
  else if false {}
  else {}
}
)");
    REQUIRE(error_stream.str() == "");
    REQUIRE(output_buffer.str() == R"(FunctionDecl: main:i32
  Block
    IfStmt
      GroupingExpr:
        NumberLiteral: bool(false)
      IfBlock
        Block
      ElseBlock
        Block
          IfStmt
            GroupingExpr:
              NumberLiteral: bool(true)
            IfBlock
              Block
            ElseBlock
              Block
                IfStmt
                  GroupingExpr:
                    NumberLiteral: bool(false)
                  IfBlock
                    Block
                  ElseBlock
                    Block
    IfStmt
      NumberLiteral: bool(false)
      IfBlock
        Block
      ElseBlock
        Block
          IfStmt
            NumberLiteral: bool(true)
            IfBlock
              Block
            ElseBlock
              Block
                IfStmt
                  NumberLiteral: bool(false)
                  IfBlock
                    Block
                  ElseBlock
                    Block
)");
  }
}

TEST_CASE("while statements", "[parser]") {
  TEST_SETUP(R"(
  fn void foo(bool x) {
    while & {};
    while (false) ;
    while x {
    !x;
    }
  }
  )");
  REQUIRE(error_stream.str() == R"(test:3:13 error: expected expression.
test:3:15 error: expected expression.
test:4:19 error: expected 'while' body.
)");
  REQUIRE(output_buffer.str() == R"(FunctionDecl: foo:void
  ParamDecl: x:bool
  Block
    WhileStmt
      DeclRefExpr: x
      Block
        UnaryOperator: '!'
          DeclRefExpr: x
)");
}

TEST_CASE("var decl passing", "[parser]") {
  TEST_SETUP(R"(
fn void foo() {
    var i32 variable = 0;
    const i32 const_var = 0;
}
    )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("FunctionDecl: foo:void") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "Block");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: variable:i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: const_var:const i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
}

TEST_CASE("var decl no init", "[parser]") {
  TEST_SETUP(R"(
fn void foo() {
    var i32 variable;
    const i32 const_var;
}
    )");
  REQUIRE(error_stream.str() == "test:4:11 error: const variable expected to have initializer.\n");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("FunctionDecl: foo:void") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "Block");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: variable:i32");
}

TEST_CASE("var decl failing", "[parser]") {
  SECTION("missing ;") {
    TEST_SETUP(R"(
    fn void foo() {
      var i32 x = 0 |;
    }
    )");
    REQUIRE(error_stream.str() == "test:3:22 error: expected expression.\n");
  }
  SECTION("missing identifier") {
    TEST_SETUP(R"(
    fn void foo() {
      var i32;
    }
    )");
    REQUIRE(error_stream.str() == "test:3:14 error: expected identifier after type.\n");
  }
  SECTION("missing identifier 2") {
    TEST_SETUP(R"(
    fn void foo() {
      var;
    }
    )");
    REQUIRE(error_stream.str() == "test:3:10 error: expected identifier.\n");
  }
  SECTION("missing initializer expression") {
    TEST_SETUP(R"(
    fn void foo() {
      var i32 x =;
    }
    )");
    REQUIRE(error_stream.str() == "test:3:18 error: expected expression.\n");
  }
}

TEST_CASE("assignment", "[parser]") {
  TEST_SETUP(R"(fn void foo() { a = 1; })");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  REQUIRE(lines_it->find("Assignment:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(1)");
}

TEST_CASE("not allowing multiple assignments", "[parser]") {
  TEST_SETUP("fn void foo() { a = b = 1; }")
  REQUIRE(error_stream.str() == "test:1:23 error: expected ';' at the end of assignment.\n");
}

TEST_CASE("assignment's lhs must be rvalue", "[parser]") {
  TEST_SETUP(R"(
fn i32 bar() { return 1; }
fn void foo() { bar() = 2; }
)");
  REQUIRE(error_stream.str() == "test:3:20 error: expected variable on the LHS of assignment.\n");
}

TEST_CASE("const parameter", "[parser]") {
  TEST_SETUP(R"(fn void foo (const i32 x){})");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("FunctionDecl: foo:void") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ParamDecl: x:const i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "Block");
}

TEST_CASE("for statement", "[parser]") {
  TEST_SETUP(R"(
fn void foo() {
  for(var i32 i = 0; i < 10; i = i + 1){}
  for var i32 i = 0; i < 10; i = i + 1 {}
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  REQUIRE(lines_it->find("ForStmt") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: i:i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "BinaryOperator: '<'");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: i");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(10)");
  CONTAINS_NEXT_REQUIRE(lines_it, "Assignment:");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: i");
  CONTAINS_NEXT_REQUIRE(lines_it, "BinaryOperator: '+'");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: i");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "Block");
  CONTAINS_NEXT_REQUIRE(lines_it, "ForStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: i:i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "BinaryOperator: '<'");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: i");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(10)");
  CONTAINS_NEXT_REQUIRE(lines_it, "Assignment:");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: i");
  CONTAINS_NEXT_REQUIRE(lines_it, "BinaryOperator: '+'");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: i");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "Block");
}

TEST_CASE("file-scope struct decl", "[parser]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
  i32 b;
  f32 c;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("StructDecl: TestType") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberField: i32(a)");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberField: i32(b)");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberField: f32(c)");
}

TEST_CASE("struct literals", "[parser]") {
  TEST_SETUP(R"(
fn void foo() {
  var TestType var_struct = .{.a = 0, .b = false};
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  REQUIRE(lines_it->find("DeclStmt:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: var_struct:TestType");
  CONTAINS_NEXT_REQUIRE(lines_it, "StructLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "FieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "FieldInitializer: b");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: bool(false)");
}

TEST_CASE("member access", "[parser]") {
  TEST_SETUP(R"(fn void foo() { var_struct.a; })");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  REQUIRE(lines_it->find("MemberAccess:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: var_struct");
  CONTAINS_NEXT_REQUIRE(lines_it, "Field: a");
}

TEST_CASE("struct member assignment", "[parser]") {
  TEST_SETUP(R"(
fn void bar() {
  var_type.a = 2;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  REQUIRE(lines_it->find("Assignment:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: var_type");
  CONTAINS_NEXT_REQUIRE(lines_it, "Field: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(2)");
}

TEST_CASE("member access chain", "[parser]") {
  TEST_SETUP(R"(
fn void foo() {
  var_type.first.second.third = 3;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  REQUIRE(lines_it->find("Assignment:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: var_type");
  CONTAINS_NEXT_REQUIRE(lines_it, "Field: first");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: first");
  CONTAINS_NEXT_REQUIRE(lines_it, "Field: second");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: second");
  CONTAINS_NEXT_REQUIRE(lines_it, "Field: third");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(3)");
}

TEST_CASE("global var with initializer", "[parser]") {
  TEST_SETUP(R"(
var i32 test = 0;
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("VarDecl: test:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
}

TEST_CASE("global const with initializer", "[parser]") {
  TEST_SETUP(R"(
const i32 test = 0;
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("VarDecl: test:const i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
}

TEST_CASE("global var without initializer", "[parser]") {
  TEST_SETUP(R"(
var i32 test;
)");
  REQUIRE(error_stream.str() == "test:2:5 error: global variable expected to have initializer.\n");
  REQUIRE(output_buffer.str() == "");
}

TEST_CASE("global const without initializer", "[parser]") {
  TEST_SETUP(R"(
const i32 test;
)");
  REQUIRE(error_stream.str() == "test:2:7 error: const variable expected to have initializer.\n");
  REQUIRE(output_buffer.str() == "");
}

TEST_CASE("global custom type var with initializer", "[parser]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
}
var TestType test = .{0};
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("StructDecl: TestType") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberField: i32(a)");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test:TestType");
  CONTAINS_NEXT_REQUIRE(lines_it, "StructLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "FieldInitializer:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
}

TEST_CASE("variable pointer decl", "[parser]") {
  TEST_SETUP(R"(
var i32* test = 0;
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("VarDecl: test:ptr i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
}

TEST_CASE("variable pointer decl, null init", "[parser]") {
  TEST_SETUP(R"(
var i32* test = null;
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("VarDecl: test:ptr i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "Null");
}

TEST_CASE("pointer chain decl", "[parser]") {
  TEST_SETUP(R"(
var i32* test = null;
var i32** test1 = null;
var i32*** test2 = null;
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("VarDecl: test:ptr i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "Null");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test1:ptr ptr i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "Null");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test2:ptr ptr ptr i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "Null");
}

TEST_CASE("address of operator", "[parser]") {
  TEST_SETUP(R"(
var i32 test = 0;
var i32* test1 = &test;
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("VarDecl: test:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test1:ptr i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "UnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: test");
}

TEST_CASE("dereference operator", "[parser]") {
  TEST_SETUP(R"(
var i32 test = 0;
var i32* test1 = &test;
var i32 test2 = *test1;
fn void main() {
    *test1 = 1;
    var i32** test3 = &test1;
    **test3 = 69;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("VarDecl: test:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test1:ptr i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "UnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: test");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test2:i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "UnaryOperator: '*'");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: test1");
  CONTAINS_NEXT_REQUIRE(lines_it, "FunctionDecl: main:void");
  CONTAINS_NEXT_REQUIRE(lines_it, "Block");
  CONTAINS_NEXT_REQUIRE(lines_it, "Assignment:");
  CONTAINS_NEXT_REQUIRE(lines_it, "LhsDereferenceCount: 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: test1");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test3:ptr ptr i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "UnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: test1");
  CONTAINS_NEXT_REQUIRE(lines_it, "Assignment:");
  CONTAINS_NEXT_REQUIRE(lines_it, "LhsDereferenceCount: 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: test3");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(69)");
}

TEST_CASE("Explicit casting", "[parser]") {
  TEST_SETUP(R"(
struct TestType1 { i32 a; }
struct TestType2 { i32 a; }
fn void foo() {
    var i32 test = 0;
    var i64 test1 = (i64)test;
    var i16 test2 = (i16)test;
    var i64* ptest3 = (i64*)&test;
    var TestType1 tt1 = .{0};
    var TestType2* ptt2 = (TestType2*)&tt1;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 9;
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test1:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "ExplicitCast: i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: test");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test2:i16");
  CONTAINS_NEXT_REQUIRE(lines_it, "ExplicitCast: i16");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: test");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: ptest3:ptr i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "ExplicitCast: ptr i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "UnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: test");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: tt1:TestType1");
  CONTAINS_NEXT_REQUIRE(lines_it, "StructLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "FieldInitializer:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: ptt2:ptr TestType2");
  CONTAINS_NEXT_REQUIRE(lines_it, "ExplicitCast: ptr TestType2");
  CONTAINS_NEXT_REQUIRE(lines_it, "UnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: tt1");
}

TEST_CASE("Array declarations no initializer", "[parser]") {
  TEST_SETUP(R"(
struct TestStruct { i32 a; }
fn void foo() {
    var i32[8] test;
    var i32[8][9] test2;
    var TestStruct[8][10] test3;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 3;
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test:i32[8]");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test2:i32[8][9]");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test3:TestStruct[8][10]");
}

TEST_CASE("Array declarations with initializers", "[parser]") {
  TEST_SETUP(R"(
struct TestStruct { i32 a; }
fn void foo() {
    var i32[3] test = [0, 1, 2];
    var i32[2][2] test2 = [[0, 1], [2, 3]];
    var TestStruct[2][2] test3 = [[.{0}, .{1}], [.{2}, .{3}]];
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 3;
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test:i32[3]");
  CONTAINS_NEXT_REQUIRE(lines_it, "ArrayLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test2:i32[2][2]");
  CONTAINS_NEXT_REQUIRE(lines_it, "ArrayLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ArrayLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ArrayLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test3:TestStruct[2][2]");
  CONTAINS_NEXT_REQUIRE(lines_it, "ArrayLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ArrayLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "StructLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "FieldInitializer:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "StructLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "FieldInitializer:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ArrayLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "StructLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "FieldInitializer:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "StructLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "FieldInitializer:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(3)");
}

TEST_CASE("Array element access", "[parser]") {
  TEST_SETUP(R"(
struct TestStruct { i32 a; }
fn void foo() {
    var i32[3] test = [0, 1, 2];
    var i32 a = test[0];
    var TestStruct[2][2] test3 = [[.{0}, .{1}], [.{2}, .{3}]];
    var TestStruct b = test3[0][1];
    var i32 c = test[-1];
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 3;
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test:i32[3]");
  CONTAINS_NEXT_REQUIRE(lines_it, "ArrayLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: a:i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "ArrayElementAccess: test");
  CONTAINS_NEXT_REQUIRE(lines_it, "ElementNo 0:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test3:TestStruct[2][2]");
  CONTAINS_NEXT_REQUIRE(lines_it, "ArrayLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ArrayLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "StructLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "FieldInitializer:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "StructLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "FieldInitializer:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ArrayLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "StructLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "FieldInitializer:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "StructLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "FieldInitializer:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: b:TestStruct");
  CONTAINS_NEXT_REQUIRE(lines_it, "ArrayElementAccess: test3");
  CONTAINS_NEXT_REQUIRE(lines_it, "ElementNo 0:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ElementNo 1:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: c:i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "ArrayElementAccess: test");
  CONTAINS_NEXT_REQUIRE(lines_it, "ElementNo 0:");
  CONTAINS_NEXT_REQUIRE(lines_it, "UnaryOperator: '-'");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(1)");
}

TEST_CASE("Pointer decay alternative access", "[parser]") {
  TEST_SETUP(R"(
fn i32 bar(i32* arr) { return *(arr + 0); }
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 3;
  CONTAINS_NEXT_REQUIRE(lines_it, "UnaryOperator: '*'");
  CONTAINS_NEXT_REQUIRE(lines_it, "GroupingExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "BinaryOperator: '+'");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: arr");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(0)");
}

TEST_CASE("String literals", "[parser]") {
  TEST_SETUP(R"(
fn i32 main() {
var u8* string = "hello";
var u8* string2 = "h.e.l.l.o.";
var u8* string3 = "";
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 1;
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: string:ptr u8");
  CONTAINS_NEXT_REQUIRE(lines_it, "StringLiteralExpr: \"hello\"");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: string2:ptr u8");
  CONTAINS_NEXT_REQUIRE(lines_it, "StringLiteralExpr: \"h.e.l.l.o.\"");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: string3:ptr u8");
  CONTAINS_NEXT_REQUIRE(lines_it, "StringLiteralExpr: \"\"");
}

TEST_CASE("Enum decls", "[parser]") {
  TEST_SETUP(R"(
enum Enum {
    ZERO,
    ONE,
    FOUR = 4,
    FIVE
}
enum Enum2 : u8 {
    ZERO,
    ONE,
    TWO
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("EnumDecl: i32(Enum)") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "FIVE: 5");
  CONTAINS_NEXT_REQUIRE(lines_it, "FOUR: 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ONE: 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "ZERO: 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "EnumDecl: u8(Enum2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ONE: 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "TWO: 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "ZERO: 0");
}

TEST_CASE("Enum member access", "[parser]") {
  TEST_SETUP(R"(
fn i32 main() {
    const Enum variable = Enum::ONE;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 1;
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: variable:const Enum");
  CONTAINS_NEXT_REQUIRE(lines_it, "EnumElementAccess: Enum::ONE");
}

TEST_CASE("Failing enum member access", "[parser]") {
  TEST_SETUP(R"(
fn i32 main() {
    const Enum variable1 = Enum::;
}
)");
  REQUIRE(error_stream.str() == "test:3:34 error: expected identifier in enum field access.\n");
}

TEST_CASE("Extern function no vla", "[parser]") {
  TEST_SETUP(R"(
extern {
    fn void* allocate(i32 lenght, i32 size) alias malloc;
}
extern sapfire {
    fn void render() alias render_frame;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("FunctionDecl: alias c::malloc allocate:ptr void") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ParamDecl: lenght:i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "ParamDecl: size:i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "FunctionDecl: alias sapfire::render_frame render:void");
}

TEST_CASE("Extern function vla", "[parser]") {
  TEST_SETUP(R"(
extern {
    fn void print(char* fmt, ...) alias printf;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("FunctionDecl: vla alias c::printf print:void") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ParamDecl: fmt:ptr char");
}

TEST_CASE("Bitwise operators", "[parser]") {
  TEST_SETUP(R"(
fn void main() {
    var i32 a = 1 | 2;
    var i32 b = a & 2;
    var i32 c = a ^ b;
    var i32 d = ~b;
    var i32 e = d % 2;
    var i32 f = 1 << 4;
    var i32 g = 10 >> 3;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("FunctionDecl: main:void") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "Block");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: a:i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "BinaryOperator: '|'");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: b:i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "BinaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: c:i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "BinaryOperator: '^'");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: b");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: d:i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "UnaryOperator: '~'");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: b");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: e:i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "BinaryOperator: '%'");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: d");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: f:i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "BinaryOperator: '<<'");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: g:i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "BinaryOperator: '>>'");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(10)");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(3)");
}

TEST_CASE("Binary number literal", "[parser]") {
  TEST_SETUP(R"(
fn void main() {
    var i32 a = 0b01011;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("FunctionDecl: main:void") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "Block");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: a:i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(11)");
}

TEST_CASE("Function pointers", "[parser]") {
  TEST_SETUP(R"(
fn void* foo(i32, f32){}
fn void main() {
    var fn* void*(i32, f32) p_foo = &foo;
    var fn* void*(i32 i, f32 f) p_foo1 = &foo;
    p_foo(1, 1.0);
}
struct Type {
    fn* void*(i32, f32) p_foo;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("FunctionDecl: foo:ptr void") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ParamDecl: :i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "ParamDecl: :f32");
  CONTAINS_NEXT_REQUIRE(lines_it, "Block");
  CONTAINS_NEXT_REQUIRE(lines_it, "FunctionDecl: main:void");
  CONTAINS_NEXT_REQUIRE(lines_it, "Block");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: p_foo:ptr fn(ptr void)(i32, f32)");
  CONTAINS_NEXT_REQUIRE(lines_it, "UnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: foo");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: p_foo1:ptr fn(ptr void)(i32, f32)");
  CONTAINS_NEXT_REQUIRE(lines_it, "UnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: foo");
  CONTAINS_NEXT_REQUIRE(lines_it, "CallExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: p_foo");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: real(1.0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "StructDecl: Type");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberField: ptr fn(ptr void)(i32, f32)(p_foo)");
}

TEST_CASE("Function pointer chaining in structs", "[parser]") {
  TEST_SETUP(R"(
fn Type* foo(i32, f32){}
fn void main() {
    var Type t = .{&foo};
    t.p_foo(1, 1.0).p_foo(1, 1.0);
}
struct Type {
    fn* Type*(i32, f32) p_foo;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("FunctionDecl: foo:ptr Type") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ParamDecl: :i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "ParamDecl: :f32");
  CONTAINS_NEXT_REQUIRE(lines_it, "Block");
  CONTAINS_NEXT_REQUIRE(lines_it, "FunctionDecl: main:void");
  CONTAINS_NEXT_REQUIRE(lines_it, "Block");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: t:Type");
  CONTAINS_NEXT_REQUIRE(lines_it, "StructLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "FieldInitializer:");
  CONTAINS_NEXT_REQUIRE(lines_it, "UnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: foo");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: t");
  CONTAINS_NEXT_REQUIRE(lines_it, "Field: p_foo");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: p_foo");
  CONTAINS_NEXT_REQUIRE(lines_it, "Field: p_foo");
  CONTAINS_NEXT_REQUIRE(lines_it, "CallParameters:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: real(1.0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "CallParameters:");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: integer(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "NumberLiteral: real(1.0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "StructDecl: Type");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberField: ptr fn(ptr Type)(i32, f32)(p_foo)");
}

TEST_CASE("builtin sizeof()", "[parser]") {
  TEST_SETUP(R"(
fn void main() {
    var i64 size_i8 = sizeof(i8);
    var i64 size_i16 = sizeof(i16);
    var i64 size_i32 = sizeof(i32);
    var i64 size_i64 = sizeof(i64);
    var i64 size_u8 = sizeof(u8);
    var i64 size_u16 = sizeof(u16);
    var i64 size_u32 = sizeof(u32);
    var i64 size_u64 = sizeof(u64);
    var i64 size_f32 = sizeof(f32);
    var i64 size_f64 = sizeof(f64);
    var i64 size_bool = sizeof(bool);
    var i64 size_ptr = sizeof(bool*);
    var i64 size_arr = sizeof(bool[4]);
    var i64 size_p_arr = sizeof(bool*[4]);
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("FunctionDecl: main:void") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "Block");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: size_i8:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Sizeof(i8 x1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: size_i16:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Sizeof(i16 x1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: size_i32:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Sizeof(i32 x1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: size_i64:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Sizeof(i64 x1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: size_u8:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Sizeof(u8 x1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: size_u16:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Sizeof(u16 x1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: size_u32:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Sizeof(u32 x1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: size_u64:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Sizeof(u64 x1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: size_f32:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Sizeof(f32 x1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: size_f64:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Sizeof(f64 x1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: size_bool:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Sizeof(bool x1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: size_ptr:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Sizeof(bool* x1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: size_arr:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Sizeof(bool x4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: size_p_arr:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Sizeof(bool* x4)");
}

TEST_CASE("builtin alignof()", "[parser]") {
  TEST_SETUP(R"(
fn void main() {
    var i64 align_i8 = alignof(i8);
    var i64 align_i16 = alignof(i16);
    var i64 align_i32 = alignof(i32);
    var i64 align_i64 = alignof(i64);
    var i64 align_u8 = alignof(u8);
    var i64 align_u16 = alignof(u16);
    var i64 align_u32 = alignof(u32);
    var i64 align_u64 = alignof(u64);
    var i64 align_f32 = alignof(f32);
    var i64 align_f64 = alignof(f64);
    var i64 align_bool = alignof(bool);
    var i64 align_ptr = alignof(bool*);
    var i64 align_arr = alignof(bool[4]);
    var i64 align_p_arr = alignof(bool*[4]);
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("FunctionDecl: main:void") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "Block");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: align_i8:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignof(i8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: align_i16:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignof(i16)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: align_i32:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignof(i32)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: align_i64:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignof(i64)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: align_u8:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignof(u8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: align_u16:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignof(u16)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: align_u32:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignof(u32)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: align_u64:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignof(u64)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: align_f32:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignof(f32)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: align_f64:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignof(f64)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: align_bool:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignof(bool)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: align_ptr:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignof(bool*)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: align_arr:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignof(bool)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: align_p_arr:i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignof(bool*)");
}

TEST_CASE("defer stmts", "[parser]") {
  TEST_SETUP(R"(
fn void main() {
  var i32* ptr = malloc(sizeof(i32));
  defer free(ptr);
  var i32* ptr2 = malloc(sizeof(i32));
  defer {
    free(ptr2);
  }
  var i32* ptr3 = malloc(sizeof(i32));
  var i32* ptr4 = malloc(sizeof(i32));
  defer {
    free(ptr3);
    free(ptr4);
  }
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("FunctionDecl: main:void") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "Block");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: ptr:ptr i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "CallExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: malloc");
  CONTAINS_NEXT_REQUIRE(lines_it, "Sizeof(i32 x1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeferStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "Block");
  CONTAINS_NEXT_REQUIRE(lines_it, "CallExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: free");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: ptr");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: ptr2:ptr i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "CallExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: malloc");
  CONTAINS_NEXT_REQUIRE(lines_it, "Sizeof(i32 x1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeferStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "Block");
  CONTAINS_NEXT_REQUIRE(lines_it, "CallExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: free");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: ptr2");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: ptr3:ptr i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "CallExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: malloc");
  CONTAINS_NEXT_REQUIRE(lines_it, "Sizeof(i32 x1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: ptr4:ptr i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "CallExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: malloc");
  CONTAINS_NEXT_REQUIRE(lines_it, "Sizeof(i32 x1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeferStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "Block");
  CONTAINS_NEXT_REQUIRE(lines_it, "CallExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: free");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: ptr3");
  CONTAINS_NEXT_REQUIRE(lines_it, "CallExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: free");
  CONTAINS_NEXT_REQUIRE(lines_it, "DeclRefExpr: ptr4");
}

TEST_CASE("Module parsing", "[parser]") {
  {
    TEST_SETUP_MODULE_SINGLE("test", R"(
        import std;
        import renderer;
        fn void main() {}
        )");
    REQUIRE(error_stream.str() == "");
    auto lines = break_by_line(output_buffer.str());
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("Module(test):") != std::string::npos);
    CONTAINS_NEXT_REQUIRE(lines_it, "Imports: std renderer");
    CONTAINS_NEXT_REQUIRE(lines_it, "FunctionDecl: main:void");
    CONTAINS_NEXT_REQUIRE(lines_it, "Block");
  }
}

TEST_CASE("exported decls", "[parser]") {
  {
    TEST_SETUP_MODULE_SINGLE("test", R"(
        export fn void main() {}
        export struct Test {}
        export enum TestEnum {}
        )");
    REQUIRE(error_stream.str() == "");
    auto lines = break_by_line(output_buffer.str());
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("Module(test):") != std::string::npos);
    CONTAINS_NEXT_REQUIRE(lines_it, "Imports:");
    CONTAINS_NEXT_REQUIRE(lines_it, "exported FunctionDecl: main:void");
    CONTAINS_NEXT_REQUIRE(lines_it, "Block");
    CONTAINS_NEXT_REQUIRE(lines_it, "exported StructDecl: Test");
    CONTAINS_NEXT_REQUIRE(lines_it, "exported EnumDecl: i32(TestEnum)");
  }
}

TEST_CASE("generic struct declarations", "[parser]") {
  SECTION("Single generic") {
    TEST_SETUP(R"(
        struct<T> GenericType {
            T first;
            T* next;
        }
        )");
    REQUIRE(error_stream.str() == "");
    auto lines = break_by_line(output_buffer.str());
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("GenericStructDecl: GenericType<T>") != std::string::npos);
    CONTAINS_NEXT_REQUIRE(lines_it, "MemberField: T(first)");
    CONTAINS_NEXT_REQUIRE(lines_it, "MemberField: ptr T(next)");
  }
  SECTION("Two generics") {
    TEST_SETUP(R"(
        struct<T, K> GenericType {
            T first;
            K second;
            T* t_next;
            K* k_next;
        }
        )");
    REQUIRE(error_stream.str() == "");
    auto lines = break_by_line(output_buffer.str());
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("GenericStructDecl: GenericType<T, K>") != std::string::npos);
    CONTAINS_NEXT_REQUIRE(lines_it, "MemberField: T(first)");
    CONTAINS_NEXT_REQUIRE(lines_it, "MemberField: K(second)");
    CONTAINS_NEXT_REQUIRE(lines_it, "MemberField: ptr T(t_next)");
    CONTAINS_NEXT_REQUIRE(lines_it, "MemberField: ptr K(k_next)");
  }
}

TEST_CASE("generic type variable declaration", "[parser]") {
  SECTION("Single generic, no init") {
    TEST_SETUP(R"(
        struct<T> GenericType {
            T first;
            T* next;
        }
        fn void foo() {
            var GenericType<i32> test;
        }
        )");
    REQUIRE(error_stream.str() == "");
    auto lines = break_by_line(output_buffer.str());
    auto lines_it = lines.begin() + 5;
    CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test:GenericType<i32>");
  }
  SECTION("Two generics, no init") {
    TEST_SETUP(R"(
        struct<T, K> GenericType {
            T first;
            K second;
            T* t_next;
            K* k_next;
        }
        fn void foo() {
            var GenericType<i32, f32> test;
        }
        )");
    REQUIRE(error_stream.str() == "");
    auto lines = break_by_line(output_buffer.str());
    auto lines_it = lines.begin() + 7;
    CONTAINS_NEXT_REQUIRE(lines_it, "VarDecl: test:GenericType<i32, f32>");
  }
}
