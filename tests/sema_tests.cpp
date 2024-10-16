#include "test_utils.h"

#define TEST_SETUP(file_contents)                                              \
  saplang::clear_error_stream();                                               \
  std::stringstream buffer{file_contents};                                     \
  std::stringstream output_buffer{};                                           \
  saplang::SourceFile src_file{"sema_test", buffer.str()};                     \
  saplang::Lexer lexer{src_file};                                              \
  saplang::Parser parser(&lexer);                                              \
  auto parse_result = parser.parse_source_file();                              \
  saplang::Sema sema{std::move(parse_result.declarations)};                    \
  auto resolved_ast = sema.resolve_ast();                                      \
  for (auto &&fn : resolved_ast) {                                             \
    fn->dump_to_stream(output_buffer);                                         \
  }                                                                            \
  const auto &error_stream = saplang::get_error_stream();

#define TEST_SETUP_PARTIAL(file_contents)                                      \
  saplang::clear_error_stream();                                               \
  std::stringstream buffer{file_contents};                                     \
  std::stringstream output_buffer{};                                           \
  saplang::SourceFile src_file{"sema_test", buffer.str()};                     \
  saplang::Lexer lexer{src_file};                                              \
  saplang::Parser parser(&lexer);                                              \
  auto parse_result = parser.parse_source_file();                              \
  saplang::Sema sema{std::move(parse_result.declarations)};                    \
  auto resolved_ast = sema.resolve_ast(true);                                  \
  for (auto &&fn : resolved_ast) {                                             \
    fn->dump_to_stream(output_buffer);                                         \
  }                                                                            \
  const auto &error_stream = saplang::get_error_stream();

TEST_CASE("Undeclared type", "[sema]") {
  TEST_SETUP(R"(
fn CustomType foo(){}
)");
  REQUIRE(output_buffer.str().empty());
  REQUIRE(
      error_stream.str() ==
      "sema_test:2:1 error: function 'foo' has invalid 'CustomType' type\n");
}

TEST_CASE("Function redeclared", "[sema]") {
  TEST_SETUP(R"(
fn void foo(){}

fn void foo(){}
)");
  REQUIRE(output_buffer.str().empty());
  REQUIRE(error_stream.str() ==
          "sema_test:4:1 error: redeclaration of 'foo'.\n");
}

TEST_CASE("Function declarations", "[sema]") {
  SECTION("Undeclared functions") {
    TEST_SETUP(R"(
fn void main() {
    a();
}
)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            "sema_test:3:5 error: symbol 'a' undefined.\n");
  }
  SECTION("Incorrect parameter types") {
    TEST_SETUP(R"(
fn void foo(){}

fn void bar(i32 a, i32 b){}

fn void main() {
  foo(1);
  bar(foo(), foo());
  bar(1.0, foo());
  bar();
  bar(1, 2, 3);
  bar(1, 2);
  bar(true, false);
  foo();
}
)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            R"(sema_test:7:6 error: argument count mismatch.
sema_test:8:10 error: unexpected type 'void', expected 'i32'.
sema_test:9:15 error: unexpected type 'void', expected 'i32'.
sema_test:10:6 error: argument count mismatch.
sema_test:11:6 error: argument count mismatch.
)");
  }
}

TEST_CASE("Declref", "[sema]") {
  SECTION("Using function as variable") {
    TEST_SETUP(R"(
fn void foo(){}

fn void main() {
  foo;
  y;
  foo();
}
)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            R"(sema_test:5:3 error: expected to call function 'foo'.
sema_test:6:3 error: symbol 'y' undefined.
)");
  }
}

TEST_CASE("Function parameters", "[sema]") {
  SECTION("Unknown paramatere type") {
    TEST_SETUP(R"(
fn void foo(u32 a, CustomType b) {}
)");
    REQUIRE(
        error_stream.str() ==
        "sema_test:2:20 error: parameter 'b' has invalid 'CustomType' type\n");
    REQUIRE(output_buffer.str().empty());
  }
  SECTION("Invalid parameter 'void'") {
    TEST_SETUP(R"(
fn void foo(void a, u32 b){}
)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            "sema_test:2:13 error: invalid paramater type 'void'.\n");
  }
  SECTION("Parameter redeclaration") {
    TEST_SETUP(R"(
fn void foo(i32 x, f32 x){}
)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() ==
            "sema_test:2:20 error: redeclaration of 'x'.\n");
  }
}

TEST_CASE("Error recovery", "[sema]") {
  TEST_SETUP_PARTIAL(R"(
fn CustomType foo() {}

fn void main() {}
)");
  auto buf_str = output_buffer.str();
  REQUIRE(
      error_stream.str() ==
      "sema_test:2:1 error: function 'foo' has invalid 'CustomType' type\n");
  REQUIRE(!buf_str.empty());
  REQUIRE(buf_str.find("ResolvedFuncDecl:") == 0);
  REQUIRE(buf_str.find("main") == 36);
  REQUIRE(buf_str.find("ResolvedBlock:") == 44);
}

TEST_CASE("Number literal returns", "[sema]") {
  SECTION("Basic return") {
    TEST_SETUP(R"(
fn i32 foo() {
    return 1;
}

fn i32 main() {
    return 1;
}
)");
    REQUIRE(error_stream.str() == "");
  }
  SECTION("Function returning literal") {
    TEST_SETUP(R"(
  fn i32 foo() { return 1; }

  fn i32 main() { return foo(); }
)");
    REQUIRE(error_stream.str() == "");
  }
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
  SECTION("Unary on callexpr") {
    TEST_SETUP(R"(
fn i32 foo() {
    return -1;
}

fn i32 main() {
    return -foo();
}
)");
    REQUIRE(error_stream.str() == "");
  }
}

TEST_CASE("if statements", "[sema]") {
  SECTION("non-bool if condition") {
    TEST_SETUP(R"(
fn void foo() {}

fn i32 main() {
  if foo() {}
}
)");
    REQUIRE(
        error_stream.str() ==
        "sema_test:5:9 error: condition is expected to evaluate to bool.\n");
  }
  SECTION("non-bool else if condition") {
    TEST_SETUP(R"(
fn void foo() {}

fn i32 main(bool x) {
  if x {}
  else if foo() {}
}
)");
    REQUIRE(
        error_stream.str() ==
        "sema_test:6:14 error: condition is expected to evaluate to bool.\n");
  }
  SECTION("valid if else if statement") {
    TEST_SETUP(R"(
fn bool foo(bool x) { return x; }

fn i32 main(bool x) {
  if x {}
  else if foo(x) {}
  else {}
}
)");
    REQUIRE(error_stream.str() == "");
    auto lines = break_by_line(output_buffer.str());
    auto lines_it = lines.begin() + 8;
    REQUIRE(lines_it->find("ResolvedIfStmt") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos)
    REQUIRE(lines_it->find(") x:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedIfBlock") != std::string::npos)
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedBlock:") != std::string::npos)
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedElseBlock") != std::string::npos)
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedBlock:") != std::string::npos)
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedIfStmt") != std::string::npos)
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedCallExpr: @(") != std::string::npos)
    REQUIRE(lines_it->find(") foo:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos)
    REQUIRE(lines_it->find(") x:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedIfBlock") != std::string::npos)
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedBlock:") != std::string::npos)
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedElseBlock") != std::string::npos)
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedBlock:") != std::string::npos)
  }
}

TEST_CASE("simple while failing", "[sema]") {
  TEST_SETUP(R"(
  fn void bar(bool x) {
    while bar(x) {}
  }
  )");
  REQUIRE(error_stream.str() ==
          "sema_test:3:14 error: condition is expected to evaluate to bool.\n");
  REQUIRE(output_buffer.str() == "");
}

TEST_CASE("simple while passing", "[sema]") {
  TEST_SETUP(R"(
  fn bool foo() { return true; }
  fn void bar(bool x) {
    while foo() {
      !x;
    }
  }
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 8;
  REQUIRE(lines_it->find("ResolvedWhileStmt") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBlock:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedUnaryOperator: '!'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
}

TEST_CASE("sema var decl passing", "[sema]") {
  TEST_SETUP(R"(
  fn i32 foo() { return 1; }
  fn void bar() {
    var i32 x;
    var i32 x2 = 1;
    var i32 x3 = foo();
  }
  )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 7;
  REQUIRE(lines_it->find("ResolvedDeclStmt:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") x:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") x2:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") x3:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(");
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
}

TEST_CASE("sema var decl failing", "[sema]") {
  SECTION("undeclared type") {
    TEST_SETUP(R"(
  fn void bar() {
    var CustomType x;
  }
  )");
    REQUIRE(
        error_stream.str() ==
        "sema_test:3:9 error: variable 'x' has invalid 'CustomType' type.\n");
  }
  SECTION("type mismatch") {
    TEST_SETUP(R"(
  fn void foo() { }
  fn void bar() {
    var i32 x = foo();
  }
  )");
    REQUIRE(error_stream.str() ==
            "sema_test:4:20 error: initializer type mismatch.\n");
  }
  SECTION("undeclared initializer symbol") {
    TEST_SETUP(R"(
  fn void bar() {
    var i32 x = y;
  }
  )");
    REQUIRE(error_stream.str() ==
            "sema_test:3:17 error: symbol 'y' undefined.\n");
  }
}

TEST_CASE("assignment simple", "[sema]") {
  TEST_SETUP("fn void foo() { var i32 x; x = 1; }");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 4;
  REQUIRE(lines_it->find("ResolvedAssignment:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
}

TEST_CASE("const assignment variable", "[sema]") {
  TEST_SETUP("fn void foo() { const i32 x = 1; x = 2; }");
  REQUIRE(error_stream.str() ==
          "sema_test:1:34 error: trying to assign to const variable.\n");
}

TEST_CASE("const assignment parameter", "[sema]") {
  TEST_SETUP("fn void foo(const i32 x){ x = 2; }");
  REQUIRE(error_stream.str() ==
          "sema_test:1:27 error: trying to assign to const variable.\n");
}

TEST_CASE("uncastable type mismatch", "[sema]") {
  TEST_SETUP(R"(
fn void foo() {}
fn void bar() {
  var i32 x = 0;
  x = foo();
}
)");
  REQUIRE(error_stream.str() == "sema_test:5:10 error: assigned value type of "
                                "'void' does not match variable type 'i32'.\n");
}

TEST_CASE("assignment implicit casting", "[sema]") {
  TEST_SETUP(R"(
fn i8 foo() { return 1; }
fn void bar() {
  var i32 x;
  x = foo();
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 9;
  REQUIRE(lines_it->find("ResolvedAssignment:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(");
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
}

TEST_CASE("function lhs assignment", "[sema]") {
  TEST_SETUP(R"(
fn void foo() {}
fn i32 bar() {}
fn void baz() {
  foo = 1;
  baz = 1;
}
)");
  REQUIRE(error_stream.str() ==
          "sema_test:5:3 error: expected to call function "
          "'foo'.\nsema_test:6:3 error: expected to call function 'baz'.\n");
}

TEST_CASE("mutable parameter assignment", "[sema]") {
  TEST_SETUP(R"(
fn void foo(i32 x) {
  x = 12;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 3;
  REQUIRE(lines_it->find("ResolvedAssignment:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(12)");
}

TEST_CASE("for stmt", "[sema]") {
  TEST_SETUP(R"(
fn void foo() {
  for(var i32 i = 0; i < 10; i = i + 1){}
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  REQUIRE(lines_it->find("ResolvedForStmt:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") i:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '<'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") i:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(10)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedAssignment:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") i:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '+'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") i:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
}

TEST_CASE("struct decl", "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
  u32 b;
  f32 c;
  bool d;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedStructDecl: TestType") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "0. ResolvedMemberField: i32(a)");
  CONTAINS_NEXT_REQUIRE(lines_it, "1. ResolvedMemberField: u32(b)");
  CONTAINS_NEXT_REQUIRE(lines_it, "2. ResolvedMemberField: f32(c)");
  CONTAINS_NEXT_REQUIRE(lines_it, "3. ResolvedMemberField: bool(d)");
}

TEST_CASE("struct decl global scope resolution", "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
  u32 b;
  f32 c;
  bool d;
}
fn void foo() {
  var TestType test_var;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedStructDecl: TestType") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "0. ResolvedMemberField: i32(a)");
  CONTAINS_NEXT_REQUIRE(lines_it, "1. ResolvedMemberField: u32(b)");
  CONTAINS_NEXT_REQUIRE(lines_it, "2. ResolvedMemberField: f32(c)");
  CONTAINS_NEXT_REQUIRE(lines_it, "3. ResolvedMemberField: bool(d)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFuncDecl: @(");
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find("test_var:TestType") != std::string::npos);
}

TEST_CASE("Struct literal assignment", "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
  u32 b;
  f32 c;
  bool d;
}
fn void foo() {
  var TestType test_var = .{.a = 1, .b = 2, .c = 3.0, .d = true};
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 7;
  REQUIRE(lines_it->find("ResolvedDeclStmt:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, " ResolvedVarDecl: @(");
  REQUIRE(lines_it->find("test_var:TestType") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: b");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: c");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "f32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: d");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
}

TEST_CASE("struct literal member assignment from call", "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
  u32 b;
  f32 c;
  bool d;
}
fn i32 foo() { return 1; }
fn u32 bar() { return 2; }
fn f32 baz() { return 3.0; }
fn bool fish() { return true; }

fn void biz() {
  var TestType test_var = .{.a = foo(), .b = bar(), .c = baz(), .d = fish()};
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 27;
  REQUIRE(lines_it->find("ResolvedDeclStmt:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, " ResolvedVarDecl: @(");
  REQUIRE(lines_it->find("test_var:TestType") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(");
  REQUIRE(lines_it->find(") foo") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: b");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(");
  REQUIRE(lines_it->find(") bar") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: c");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(");
  REQUIRE(lines_it->find(") baz") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: d");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(");
  REQUIRE(lines_it->find(") fish") != std::string::npos);
}

TEST_CASE("out of order struct literal field assignment with field names",
          "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
  u32 b;
  f32 c;
  bool d;
}
fn void foo() {
  var TestType test_var = .{.b = 2, .d = true, .a = 1, .c = 3.0};
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 7;
  REQUIRE(lines_it->find("ResolvedDeclStmt:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, " ResolvedVarDecl: @(");
  REQUIRE(lines_it->find("test_var:TestType") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: b");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: c");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "f32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: d");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
}

TEST_CASE("out of order assignment not all field names", "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
  u32 b;
  f32 c;
  bool d;
}
fn void foo() {
  var TestType test_var = .{.b = 2, 3.0, true, .a = 1};
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 7;
  REQUIRE(lines_it->find("ResolvedDeclStmt:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, " ResolvedVarDecl: @(");
  REQUIRE(lines_it->find("test_var:TestType") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: b");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: c");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "f32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: d");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
}

TEST_CASE("unnamed field initialization", "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
  u32 b;
  f32 c;
  bool d;
}
fn void foo() {
  var TestType test_var = .{1, 2, 3.0, true};
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 7;
  REQUIRE(lines_it->find("ResolvedDeclStmt:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, " ResolvedVarDecl: @(");
  REQUIRE(lines_it->find("test_var:TestType") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: b");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: c");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "f32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: d");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
}

TEST_CASE("uninitialized fields", "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
  u32 b;
  f32 c;
  bool d;
}
fn void foo() {
  var TestType test_var = .{.b = 2, .c = 3.0};
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 7;
  REQUIRE(lines_it->find("ResolvedDeclStmt:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, " ResolvedVarDecl: @(");
  REQUIRE(lines_it->find("test_var:TestType") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "Uninitialized");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: b");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: c");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "f32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: d");
  CONTAINS_NEXT_REQUIRE(lines_it, "Uninitialized");
}

TEST_CASE("returning struct literal", "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
  u32 b;
  f32 c;
  bool d;
}
fn TestType foo() {
  return .{.b = 2, 3.0, true, .a = 1};
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 7;
  REQUIRE(lines_it->find("ResolvedReturnStmt:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: TestType");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: b");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: c");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "f32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: d");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
}

TEST_CASE("struct member", "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
  u32 b;
  f32 c;
  bool d;
}
struct TestType2 {
  TestType test_var;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedStructDecl: TestType") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "0. ResolvedMemberField: i32(a)");
  CONTAINS_NEXT_REQUIRE(lines_it, "1. ResolvedMemberField: u32(b)");
  CONTAINS_NEXT_REQUIRE(lines_it, "2. ResolvedMemberField: f32(c)");
  CONTAINS_NEXT_REQUIRE(lines_it, "3. ResolvedMemberField: bool(d)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructDecl: TestType2");
  CONTAINS_NEXT_REQUIRE(lines_it, "0. ResolvedMemberField: TestType(test_var)");
}

TEST_CASE("inline struct literal assignment", "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
  u32 b;
  f32 c;
  bool d;
}
struct TestType2 {
  TestType testvar;
}
fn void foo() {
  var TestType2 a = .{.{1, 2, 3.0, true},};
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 9;
  REQUIRE(lines_it->find("ResolvedDeclStmt:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, " ResolvedVarDecl: @(");
  REQUIRE(lines_it->find("a:TestType2") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: TestType2");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: testvar");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: TestType");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: b");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: c");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "f32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: d");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
}

TEST_CASE("struct in function parameters", "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
  u32 b;
  f32 c;
  bool d;
}
fn void foo(TestType a) {}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 5;
  REQUIRE(lines_it->find("ResolvedFuncDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedParamDecl: @(");
  REQUIRE(lines_it->find(") a:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
}

TEST_CASE("struct member access", "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
  u32 b;
  f32 c;
  bool d;
}
fn void foo() {
  var TestType var_type = .{.b = 2, 3.0, true, .a = 1};
  var_type.a = 2;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 7;
  REQUIRE(lines_it->find("ResolvedDeclStmt:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, " ResolvedVarDecl: @(");
  REQUIRE(lines_it->find("var_type:TestType") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: TestType");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: b");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: c");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "f32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: d");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedAssignment:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructMemberAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") var_type:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberIndex: 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberID:i32(a)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(2)");
}

TEST_CASE("struct member access return", "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
  u32 b;
  f32 c;
  bool d;
}
fn i32 foo() {
  var TestType var_type = .{.b = 2, 3.0, true, .a = 1};
  return var_type.a;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 7;
  REQUIRE(lines_it->find("ResolvedDeclStmt:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, " ResolvedVarDecl: @(");
  REQUIRE(lines_it->find("var_type:TestType") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: TestType");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: b");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: c");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "f32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: d");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedReturnStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructMemberAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") var_type:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberIndex: 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberID:i32(a)");
}

TEST_CASE("non-struct member access", "[sema]") {
  TEST_SETUP(R"(
fn void foo() {
  var i32 test = 0;
  test.a = 2;
}
)");
  REQUIRE(error_stream.str() ==
          "sema_test:4:3 error: i32 is not a struct type.\n");
}

TEST_CASE("struct non-existing member access", "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
  u32 b;
  f32 c;
  bool d;
}
fn void foo() {
  var TestType var_type = .{.b = 2, 3.0, true, .a = 1};
  var_type.x = 2;
}
)");
  REQUIRE(
      error_stream.str() ==
      "sema_test:10:3 error: no member named 'x' in struct type 'TestType'.\n");
}

TEST_CASE("struct literal in function parameter", "[sema]") {
  TEST_SETUP(R"(
  struct TestType {
    i32 a;
    f32 b;
    bool c;
    i32 d;
  }
fn i32 foo(TestType variable) {
  variable.d = 15;
  return variable.d;
}
fn i32 bar() {
  var TestType t = .{.a = -1, .b = 2.0, .c = true, .d = 250};
  return foo(t);
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 5;
  REQUIRE(lines_it->find("ResolvedFuncDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, " ResolvedParamDecl: @(");
  REQUIRE(lines_it->find(") variable:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedAssignment:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructMemberAccess");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") variable:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberIndex: 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberID:i32(d)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(15)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedReturnStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructMemberAccess");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") variable:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberIndex: 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberID:i32(d)");
}

TEST_CASE("passing struct literal to function parameters", "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
  u32 b;
  f32 c;
  bool d;
}
fn i32 foo(TestType a) {
  return a.b;
}
fn i32 bar() {
  foo(.{.b = 2, 3.0, true, .a = 1});
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 5;
  REQUIRE(lines_it->find("ResolvedFuncDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedParamDecl: @(");
  REQUIRE(lines_it->find(") a:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedReturnStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructMemberAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") a:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberIndex: 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberID:u32(b)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFuncDecl: @(");
  REQUIRE(lines_it->find(") bar:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(");
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: TestType");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: b");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: c");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "f32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: d");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
}

TEST_CASE("out of order struct decls", "[sema]") {
  TEST_SETUP(R"(
struct TestType2 {
  TestType variable;
}
struct TestType{
  i32 a;
  bool b;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedStructDecl: TestType") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "0. ResolvedMemberField: i32(a)");
  CONTAINS_NEXT_REQUIRE(lines_it, "1. ResolvedMemberField: bool(b)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructDecl: TestType2");
  CONTAINS_NEXT_REQUIRE(lines_it, "0. ResolvedMemberField: TestType(variable)");
}

TEST_CASE("out of order struct decls, unknown struct", "[sema]") {
  TEST_SETUP(R"(
struct TestType2 {
  TestType variable;
  TestType3 unknown;
}
struct TestType{
  i32 a;
  bool b;
}
)");
  REQUIRE(error_stream.str() ==
          "sema_test:2:1 error: could not resolve type 'TestType3'.\n");
}

TEST_CASE("member access chains", "[sema]") {
  TEST_SETUP(R"(
struct TestType2 {
  TestType variable;
}
struct TestType{
  i32 a;
  bool b;
}
fn void foo() {
  var TestType2 t;
  t.variable.b = true;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 10;
  REQUIRE(lines_it->find("ResolvedStructMemberAccess:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") t:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberIndex: 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberID:TestType(variable)");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberIndex: 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberID:bool(b)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
}

TEST_CASE("global var with initializer", "[sema]") {
  TEST_SETUP(R"(
var i32 test = 0;
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedVarDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") test:global i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(0)");
}

TEST_CASE("global const with initializer", "[sema]") {
  TEST_SETUP(R"(
const i32 test = 0;
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedVarDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") test:global const i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(0)");
}

TEST_CASE("global var without initializer", "[sema]") {
  TEST_SETUP(R"(
var i32 test;
)");
  REQUIRE(
      error_stream.str() ==
      "sema_test:2:5 error: global variable expected to have initializer.\n");
  REQUIRE(output_buffer.str() == "");
}

TEST_CASE("global const without initializer", "[sema]") {
  TEST_SETUP(R"(
const i32 test;
)");
  REQUIRE(
      error_stream.str() ==
      "sema_test:2:7 error: const variable expected to have initializer.\n");
  REQUIRE(output_buffer.str() == "");
}

TEST_CASE("global custom type var with initializer", "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
}
var TestType test = .{0};
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedStructDecl: TestType") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "0. ResolvedMemberField: i32(a)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") test:global TestType") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: TestType");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(0)");
}

TEST_CASE("global custom type var with initializer access from function",
          "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
}
var TestType test = .{0};
fn void foo() {
  test.a = 5;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 1;
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") test:global TestType") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: TestType");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFuncDecl: @(");
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedAssignment:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructMemberAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") test:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberIndex: 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberID:i32(a)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(5)");
}

TEST_CASE("global custom type const var with initializer access from function",
          "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
}
const TestType test = .{0};
fn void foo() {
  test.a = 5;
}
)");
  REQUIRE(error_stream.str() ==
          "sema_test:7:3 error: trying to assign to const variable.\n");
}

TEST_CASE("variable pointer decl null initialization", "[sema]") {
  TEST_SETUP(R"(
var i32* test = null;
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedVarDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") test:global ptr i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "Null");
}

TEST_CASE("struct pointer decl null initialization", "[sema]") {
  TEST_SETUP(R"(
struct TestStruct { i32 a; }
var TestStruct* test = null;
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  REQUIRE(lines_it->find("ResolvedVarDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") test:global ptr TestStruct") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "Null");
}

TEST_CASE("address of operator", "[sema]") {
  TEST_SETUP(R"(
var i32 test = 0;
var i32* test1 = &test;
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedVarDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") test:global i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") test1:global ptr i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") test:") != std::string::npos);
}

TEST_CASE("derefence operator", "[sema]") {
  TEST_SETUP(R"(
var i32 test = 0;
var i32* test1 = &test;
var i32 test2 = *test1;
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedVarDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") test:global i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") test1:global ptr i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") test:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") test2:global i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '*'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") test1:") != std::string::npos);
}

TEST_CASE("dereferencing non-pointer type", "[sema]") {
  TEST_SETUP(R"(
var i32 test = 0;
var i32 test1 = *test;
)");
  REQUIRE(error_stream.str() == "sema_test:3:18 error: cannot dereference non-pointer type.\n");
}

TEST_CASE("derefence operator function parameter", "[sema]") {
  TEST_SETUP(R"(
var i32 test = 0;
var i32* test1 = &test;
fn void foo(i32 a) {}
fn void main() {
foo(*test1);
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedVarDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") test:global i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") test1:global ptr i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") test:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFuncDecl: @(");
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedParamDecl: @(");
  REQUIRE(lines_it->find(") a:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFuncDecl: @(");
  REQUIRE(lines_it->find(") main:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(");
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '*'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") test1:") != std::string::npos);
}

TEST_CASE("multidepth pointer", "[sema]") {
  TEST_SETUP(R"(
fn i32 main() {
  var i32 a = 69;
  var i32* pa = &a;
  var i32** ppa = &pa;
  return **ppa;
}
    )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedFuncDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") main:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") a:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(69)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") pa:ptr i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") a:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") ppa:ptr ptr i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") pa:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedReturnStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '*'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '*'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") ppa:") != std::string::npos);
}

TEST_CASE("Explicit casting correct", "[sema]") {
  TEST_SETUP(R"(
struct Type1 {
  i32 a;
}
struct Type2 {
  i32 a;
}
fn i32 main() {
  var i32 a = 69;
  var Type1 t = .{a};
  var Type2* t2 = (Type2*)&t;
  var i64 long = (i64)a;
  var i8 short = (i8)a;
  var Type1* t3 = (Type1*)a;
  var i32 ptr_addr = (i32)t3;
  var i32 nop = (i32)a;
  var f64 f = (f64)a;
  a = (i32)f;
  return a;
}
    )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 6;
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") a:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(69)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") t:Type1") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: Type1");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") a:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") t2:ptr Type2") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedExplicitCast: ptr Type2");
  CONTAINS_NEXT_REQUIRE(lines_it, "CastType: Ptr");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") t:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") long:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedExplicitCast: i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "CastType: Extend");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") a:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") short:i8") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedExplicitCast: i8");
  CONTAINS_NEXT_REQUIRE(lines_it, "CastType: Truncate");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") a:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") t3:ptr Type1") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedExplicitCast: ptr Type1");
  CONTAINS_NEXT_REQUIRE(lines_it, "CastType: IntToPtr");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") a:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") ptr_addr:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedExplicitCast: i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "CastType: PtrToInt");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") t3:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") nop:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedExplicitCast: i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "CastType: Nop");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") a:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") f:f64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedExplicitCast: f64");
  CONTAINS_NEXT_REQUIRE(lines_it, "CastType: IntToFloat");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") a:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedAssignment:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") a:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedExplicitCast: i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "CastType: FloatToInt");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") f:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedReturnStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") a:") != std::string::npos);
}

TEST_CASE("Explicit casting incorrect", "[sema]") {
  TEST_SETUP(R"(
struct Type1 {
  i32 a;
}
struct Type2 {
  i32 a;
}
fn i32 main() {
  var i32 a = 69;
  var Type1 t = .{a};
  var Type2 t2 = (Type2)t;
  var Type2* t2 = (Type2*)t;
  return a;
}
    )");
  REQUIRE(error_stream.str() == "sema_test:11:16 error: expected expression.\nsema_test:12:26 error: pointer depths must me equal.\n");
  REQUIRE(output_buffer.str() == "");
}
// @TODO: global and local redeclaration
