#include "catch2/catch_test_macros.hpp"
#include "test_utils.h"

#define TEST_SETUP(file_contents)                                              \
  saplang::clear_error_stream();                                               \
  std::stringstream buffer{file_contents};                                     \
  std::stringstream output_buffer{};                                           \
  saplang::SourceFile src_file{"test", buffer.str()};                          \
  saplang::Lexer lexer{src_file};                                              \
  saplang::Parser parser(&lexer);                                              \
  auto parse_result = parser.parse_source_file();                              \
  for (auto &&fn : parse_result.functions) {                                   \
    fn->dump_to_stream(output_buffer);                                         \
  }                                                                            \
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
    REQUIRE(error_stream.str() ==
            "test:1:7 error: expected function identifier.\n");
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
    REQUIRE(error_stream.str() ==
            "test:1:10 error: expected parameter declaration.\n");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("expected parameter identifier") {
    TEST_SETUP(R"(fn int f(int{})");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() == "test:1:10 error: expected identifier.\n");
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
    REQUIRE(output_buffer.str() ==
            R"(FunctionDecl: f:void
  Block
)");
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
    REQUIRE(output_buffer.str() ==
            R"(FunctionDecl: main:void
  Block
)");
    REQUIRE(error_stream.str() ==
            R"(test:3:5 error: expected expression.
test:4:5 error: expected expression.
)");
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
            R"(test:2:11 error: expected parameter declaration.
)");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("fn void f(x){}") {
    TEST_SETUP(R"(
fn void f(x){}
)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() == R"(test:2:11 error: expected identifier.
)");
    REQUIRE(!parser.is_complete_ast());
  }
  SECTION("fn void f(1.0 x){}") {
    TEST_SETUP("fn void f(1.0 x){}");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            R"(test:1:11 error: expected parameter declaration.
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
    REQUIRE(error_stream.str() ==
            "test:1:17 error: expected parameter declaration.\n");
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
    REQUIRE(error_stream.str() ==
            "test:1:24 error: expected ';' at the end of a statement.\n");
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
  REQUIRE(output_buffer.str() == R"(FunctionDecl: main:int
  Block
    ReturnStmt
      NumberLiteral: integer(1)
FunctionDecl: pass:int
  Block
    ReturnStmt
      NumberLiteral: integer(2)
)");
  REQUIRE(error_stream.str() ==
          R"(test:2:9 error: expected function identifier.
test:10:15 error: expected parameter declaration.
test:17:1 error: expected '}' at the end of a block.
test:17:1 error: failed to parse function block.
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
  REQUIRE(error_stream.str() == R"(test:3:11 error: expected expression.
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
  REQUIRE(error_stream.str() ==
          "test:4:11 error: const variable expected to have initializer.\n");
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
    REQUIRE(error_stream.str() ==
            "test:3:21 error: expected ';' at the end of declaration.\n");
  }
  SECTION("missing identifier") {
    TEST_SETUP(R"(
    fn void foo() {
      var i32;
    }
    )");
    REQUIRE(error_stream.str() ==
            "test:3:14 error: expected identifier after type.\n");
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
  REQUIRE(error_stream.str() ==
          "test:1:23 error: expected ';' at the end of assignment.\n");
}

TEST_CASE("assignment's lhs must be rvalue", "[parser]") {
  TEST_SETUP(R"(
fn i32 bar() { return 1; }
fn void foo() { bar() = 2; }
)");
  REQUIRE(error_stream.str() ==
          "test:3:20 error: expected variable on the LHS of assignment.\n");
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
