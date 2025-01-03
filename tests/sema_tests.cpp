#include "test_utils.h"
#include <iterator>

#define TEST_SETUP(file_contents)                                                                                                                              \
  saplang::clear_error_stream();                                                                                                                               \
  std::stringstream buffer{file_contents};                                                                                                                     \
  std::stringstream output_buffer{};                                                                                                                           \
  saplang::SourceFile src_file{"sema_test", buffer.str()};                                                                                                     \
  saplang::Lexer lexer{src_file};                                                                                                                              \
  saplang::Parser parser(&lexer, {{}, false});                                                                                                                 \
  auto parse_result = parser.parse_source_file();                                                                                                              \
  saplang::Sema sema{std::move(parse_result.module->declarations)};                                                                                             \
  auto resolved_ast = sema.resolve_ast();                                                                                                                      \
  for (auto &&fn : resolved_ast) {                                                                                                                             \
    fn->dump_to_stream(output_buffer);                                                                                                                         \
  }                                                                                                                                                            \
  const auto &error_stream = saplang::get_error_stream();

#define TEST_SETUP_TYPE_INFO(file_contents)                                                                                                                    \
  saplang::clear_error_stream();                                                                                                                               \
  std::stringstream buffer{file_contents};                                                                                                                     \
  std::stringstream output_buffer{};                                                                                                                           \
  saplang::SourceFile src_file{"sema_test", buffer.str()};                                                                                                     \
  saplang::Lexer lexer{src_file};                                                                                                                              \
  saplang::Parser parser(&lexer, {{}, false});                                                                                                                 \
  auto parse_result = parser.parse_source_file();                                                                                                              \
  saplang::Sema sema{std::move(parse_result.module->declarations)};                                                                                             \
  auto resolved_ast = sema.resolve_ast();                                                                                                                      \
  sema.dump_type_infos_to_stream(output_buffer, 0);                                                                                                            \
  const auto &error_stream = saplang::get_error_stream();

#define TEST_SETUP_PARTIAL(file_contents)                                                                                                                      \
  saplang::clear_error_stream();                                                                                                                               \
  std::stringstream buffer{file_contents};                                                                                                                     \
  std::stringstream output_buffer{};                                                                                                                           \
  saplang::SourceFile src_file{"sema_test", buffer.str()};                                                                                                     \
  saplang::Lexer lexer{src_file};                                                                                                                              \
  saplang::Parser parser(&lexer, {{}, false});                                                                                                                 \
  auto parse_result = parser.parse_source_file();                                                                                                              \
  saplang::Sema sema{std::move(parse_result.module->declarations)};                                                                                             \
  auto resolved_ast = sema.resolve_ast(true);                                                                                                                  \
  for (auto &&fn : resolved_ast) {                                                                                                                             \
    fn->dump_to_stream(output_buffer);                                                                                                                         \
  }                                                                                                                                                            \
  const auto &error_stream = saplang::get_error_stream();

TEST_CASE("Undeclared type", "[sema]") {
  TEST_SETUP(R"(
fn CustomType foo(){}
)");
  REQUIRE(output_buffer.str().empty());
  REQUIRE(error_stream.str() == "sema_test:2:1 error: function 'foo' has invalid 'CustomType' type\n");
}

TEST_CASE("Function redeclared", "[sema]") {
  TEST_SETUP(R"(
fn void foo(){}

fn void foo(){}
)");
  REQUIRE(output_buffer.str().empty());
  REQUIRE(error_stream.str() == "sema_test:4:1 error: redeclaration of 'foo'.\n");
}

TEST_CASE("Function declarations", "[sema]") {
  SECTION("Undeclared functions") {
    TEST_SETUP(R"(
fn void main() {
    a();
}
)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() == "sema_test:3:5 error: symbol 'a' undefined.\n");
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
sema_test:9:7 error: unexpected type 'f32', expected 'i32'.
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
    REQUIRE(error_stream.str() == "sema_test:2:20 error: parameter 'b' has invalid 'CustomType' type\n");
    REQUIRE(output_buffer.str().empty());
  }
  SECTION("Invalid parameter 'void'") {
    TEST_SETUP(R"(
fn void foo(void a, u32 b){}
)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() == "sema_test:2:13 error: parameter 'a' has invalid 'void' type\n");
  }
  SECTION("Parameter redeclaration") {
    TEST_SETUP(R"(
fn void foo(i32 x, f32 x){}
)");
    REQUIRE(output_buffer.str().empty());
    REQUIRE(error_stream.str() == "sema_test:2:20 error: redeclaration of 'x'.\n");
  }
}

TEST_CASE("Error recovery", "[sema]") {
  TEST_SETUP_PARTIAL(R"(
fn CustomType foo() {}

fn void main() {}
)");
  auto buf_str = output_buffer.str();
  REQUIRE(error_stream.str() == "sema_test:2:1 error: function 'foo' has invalid 'CustomType' type\n");
  REQUIRE(!buf_str.empty());
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedFuncDecl:") != std::string::npos);
  REQUIRE(lines_it->find("main") != std::string::npos);
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
    REQUIRE(error_stream.str() == "sema_test:5:9 error: condition is expected to evaluate to bool.\n");
  }
  SECTION("non-bool else if condition") {
    TEST_SETUP(R"(
fn void foo() {}

fn i32 main(bool x) {
  if x {}
  else if foo() {}
}
)");
    REQUIRE(error_stream.str() == "sema_test:6:14 error: condition is expected to evaluate to bool.\n");
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
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos)
    REQUIRE(lines_it->find(") x:") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedIfBlock") != std::string::npos)
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBlock:") != std::string::npos)
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedElseBlock") != std::string::npos)
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBlock:") != std::string::npos)
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedIfStmt") != std::string::npos)
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedCallExpr: @(") != std::string::npos)
    REQUIRE(lines_it->find(") foo:") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos)
    REQUIRE(lines_it->find(") x:") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedIfBlock") != std::string::npos)
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBlock:") != std::string::npos)
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedElseBlock") != std::string::npos)
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBlock:") != std::string::npos)
  }
}

TEST_CASE("simple while failing", "[sema]") {
  TEST_SETUP(R"(
  fn void bar(bool x) {
    while bar(x) {}
  }
  )");
  REQUIRE(error_stream.str() == "sema_test:3:14 error: condition is expected to evaluate to bool.\n");
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
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBlock:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedUnaryOperator: '!'") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
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
    REQUIRE(error_stream.str() == "sema_test:3:9 error: variable 'x' has invalid 'CustomType' type.\n");
  }
  SECTION("type mismatch") {
    TEST_SETUP(R"(
  fn void foo() { }
  fn void bar() {
    var i32 x = foo();
  }
  )");
    REQUIRE(error_stream.str() == "sema_test:4:20 error: initializer type mismatch.\n");
  }
  SECTION("undeclared initializer symbol") {
    TEST_SETUP(R"(
  fn void bar() {
    var i32 x = y;
  }
  )");
    REQUIRE(error_stream.str() == "sema_test:3:17 error: symbol 'y' undefined.\n");
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
  REQUIRE(error_stream.str() == "sema_test:1:34 error: trying to assign to const variable.\n");
}

TEST_CASE("const assignment parameter", "[sema]") {
  TEST_SETUP("fn void foo(const i32 x){ x = 2; }");
  REQUIRE(error_stream.str() == "sema_test:1:27 error: trying to assign to const variable.\n");
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
  REQUIRE(error_stream.str() == "sema_test:5:3 error: expected to call function "
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
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
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

TEST_CASE("out of order struct literal field assignment with field names", "[sema]") {
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
  REQUIRE(error_stream.str() == "sema_test:4:3 error: i32 is not a struct type.\n");
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
  REQUIRE(error_stream.str() == "sema_test:10:3 error: no member named 'x' in struct type 'TestType'.\n");
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
  REQUIRE(error_stream.str() == "sema_test:2:1 error: could not resolve type 'TestType3'.\n");
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
  REQUIRE(error_stream.str() == "sema_test:2:5 error: global variable expected to have initializer.\n");
  REQUIRE(output_buffer.str() == "");
}

TEST_CASE("global const without initializer", "[sema]") {
  TEST_SETUP(R"(
const i32 test;
)");
  REQUIRE(error_stream.str() == "sema_test:2:7 error: const variable expected to have initializer.\n");
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

TEST_CASE("global custom type var with initializer access from function", "[sema]") {
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

TEST_CASE("global custom type const var with initializer access from function", "[sema]") {
  TEST_SETUP(R"(
struct TestType {
  i32 a;
}
const TestType test = .{0};
fn void foo() {
  test.a = 5;
}
)");
  REQUIRE(error_stream.str() == "sema_test:7:3 error: trying to assign to const variable.\n");
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
fn void main() {
    *test1 = 1;
    var i32** test3 = &test1;
    **test3 = 69;
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
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") test2:global i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '*'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") test1:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFuncDecl: @(");
  REQUIRE(lines_it->find(") main:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedAssignment:");
  CONTAINS_NEXT_REQUIRE(lines_it, "LhsDereferenceCount: 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") test1:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") test3:ptr ptr i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") test1:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedAssignment:");
  CONTAINS_NEXT_REQUIRE(lines_it, "LhsDereferenceCount: 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") test3:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(69)");
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
  REQUIRE(error_stream.str() == "sema_test:11:16 error: expected ')'.\nsema_test:12:26 error: "
                                "pointer depths must me equal.\n");
  REQUIRE(output_buffer.str() == "");
}

TEST_CASE("Array declarations no initializer", "[sema]") {
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
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") test:i32[8]") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") test2:i32[8][9]") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") test3:TestStruct[8][10]") != std::string::npos);
}

TEST_CASE("Array declarations with initializers", "[sema]") {
  TEST_SETUP(R"(
struct TestStruct { i32 a; }
fn void foo() {
    var i32[3] test = [0, 1, 2];
    var i32[3][2] test2 = [[0, 1], [2, 3], [4, 5]];
    var TestStruct[2][2] test3 = [[.{0}, .{1}], [.{2}, .{3}]];
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 3;
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") test:i32[3]") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayLiteralExpr: i32[3]");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") test2:i32[3][2]") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayLiteralExpr: i32[3][2]");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayLiteralExpr: i32[2]");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayLiteralExpr: i32[2]");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayLiteralExpr: i32[2]");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(5)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") test3:TestStruct[2][2]") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayLiteralExpr: TestStruct[2][2]");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayLiteralExpr: TestStruct[2]");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: TestStruct");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: TestStruct");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayLiteralExpr: TestStruct[2]");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: TestStruct");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: TestStruct");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(3)");
}

TEST_CASE("Array pointer decay failing", "[sema]") {
  TEST_SETUP(R"(
struct TestStruct { i32 a; }
fn void foo() {
    var i32[3][2] test2 = [[0, 1], [2, 3], [4, 5]];
    var i32** p_t2 = test2;
    var TestStruct[2][2] test3 = [[.{0}, .{1}], [.{2}, .{3}]];
    var TestStruct** p_t3 = test3;
}
)");
  REQUIRE(error_stream.str() == "sema_test:5:22 error: initializer type mismatch.\nsema_test:7:29 "
                                "error: initializer type mismatch.\n");
}

TEST_CASE("Array pointer decay", "[sema]") {
  TEST_SETUP(R"(
fn void foo() {
    var i32[3] test = [0, 1, 2];
    var i32* p_t1 = test;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 1;
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") test:i32[3]") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayLiteralExpr: i32[3]");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") p_t1:ptr i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") test:") != std::string::npos);
}

TEST_CASE("Array type mismatch", "[sema]") {
  TEST_SETUP(R"(
fn void foo() {
    var i32[3] test = [0, 1, 2];
    var i32 p_t1 = test;
}
)");
  REQUIRE(error_stream.str() == "sema_test:4:20 error: initializer type mismatch.\n");
}

TEST_CASE("Array element access", "[sema]") {
  TEST_SETUP(R"(
struct TestStruct { i32 a; }
fn void foo() {
    var i32[3] test = [0, 1, 2];
    var i32 a = test[0];
    var TestStruct[2][2] test3 = [[.{0}, .{1}], [.{2}, .{3}]];
    var TestStruct b = test3[0][1];
    var i32 c = test[-1];
    var i32 d = test[c];
    var TestStruct* e = test3[0];
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 3;
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") test:i32[3]") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayLiteralExpr: i32[3]");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") a:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayElementAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") test:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "IndexAccess 0:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") test3:TestStruct[2][2]") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayLiteralExpr: TestStruct[2][2]");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayLiteralExpr: TestStruct[2]");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: TestStruct");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: TestStruct");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayLiteralExpr: TestStruct[2]");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: TestStruct");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: TestStruct");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: a");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") b:TestStruct") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayElementAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") test3:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "IndexAccess 0:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "IndexAccess 1:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") c:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayElementAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") test:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "IndexAccess 0:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '-'");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(-1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") d:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayElementAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") test:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "IndexAccess 0:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") c:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find("e:ptr TestStruct") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayElementAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") test3:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "IndexAccess 0:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(0)");
}

TEST_CASE("More array accesses than dimensions", "[sema]") {
  TEST_SETUP(R"(
struct TestStruct { i32 a; }
fn void foo() {
    var i32[3] test = [0, 1, 2];
    var i32 a = test[0][0];
    var TestStruct[2][2] test3 = [[.{0}, .{1}], [.{2}, .{3}]];
    var TestStruct b = test3[0][1][0];
}
)");
  REQUIRE(error_stream.str() == "sema_test:5:21 error: more array accesses than there are "
                                "dimensions.\nsema_test:7:29 error: more array accesses than there "
                                "are dimensions.\n");
}

TEST_CASE("non-array type array index access", "[sema]") {
  TEST_SETUP(R"(
struct TestStruct { i32 a; }
fn void foo() {
    var i32 test = 0;
    var i32 a = test[0][0];
}
)");
  REQUIRE(error_stream.str() == "sema_test:5:21 error: trying to access an array element of a "
                                "variable that is not an array or pointer: test.\n");
}

TEST_CASE("dereferencing pointer array decay", "[sema]") {
  TEST_SETUP(R"(
fn i32 bar(i32* arr) { return *(arr + 0); }
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 3;
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '*'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedGroupingExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedArrayElementAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") arr:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "IndexAccess 0:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(0)");
}

TEST_CASE("String literals", "[sema]") {
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
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") string:ptr u8") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStringLiteralExpr: \"hello\"");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") string2:ptr u8") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStringLiteralExpr: \"h.e.l.l.o.\"");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") string3:ptr u8") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStringLiteralExpr: \"\"");
}

TEST_CASE("Enum decls", "[sema]") {
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
  REQUIRE(lines_it->find("ResolvedEnumDecl: i32(Enum)") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "FIVE: 5");
  CONTAINS_NEXT_REQUIRE(lines_it, "FOUR: 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ONE: 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "ZERO: 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedEnumDecl: u8(Enum2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ONE: 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "TWO: 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "ZERO: 0");
}

TEST_CASE("Enum access", "[sema]") {
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
fn i32 main() {
    var Enum enum_1 = Enum::FIVE;
    var Enum2 enum_2 = Enum2::TWO;
    return enum_1;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedEnumDecl: i32(Enum)") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "FIVE: 5");
  CONTAINS_NEXT_REQUIRE(lines_it, "FOUR: 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ONE: 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "ZERO: 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedEnumDecl: u8(Enum2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ONE: 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "TWO: 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "ZERO: 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFuncDecl: @(");
  REQUIRE(lines_it->find(") main:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") enum_1:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(5)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") enum_2:u8") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u8(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedReturnStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") enum_1:") != std::string::npos);
}
// @TODO: prohibit array operations on const vars
// @TODO: prohibit struct ops on const vars
// @TODO: slices
// @TODO: global and local redeclaration

TEST_CASE("Extern function no VLL", "[sema]") {
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
  REQUIRE(lines_it->find("ResolvedFuncDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") alias c::malloc allocate:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedParamDecl: @(");
  REQUIRE(lines_it->find(") lenght:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedParamDecl: @(");
  REQUIRE(lines_it->find(") size:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFuncDecl: @(");
  REQUIRE(lines_it->find(") alias sapfire::render_frame render:") != std::string::npos);
}

TEST_CASE("Extern function VLL", "[sema]") {
  TEST_SETUP(R"(
extern {
    fn void print(u8* fmt, ...) alias printf;
}
fn void main() {
    print("hello %d, %d, %d.\n", 1, 2, 3);
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedFuncDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") VLL alias c::printf print:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedParamDecl: @(");
  REQUIRE(lines_it->find(") fmt:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFuncDecl: @(");
  REQUIRE(lines_it->find(") main:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(");
  REQUIRE(lines_it->find(") print:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStringLiteralExpr:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "8(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
}

TEST_CASE("Bitwise operators", "[sema]") {
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
  auto lines_it = lines.begin() + 1;
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") a:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '|'");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") b:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") a:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") c:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '^'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") a:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") b:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") d:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '~'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") b:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") e:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '%'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") d:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") f:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '<<'");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(16)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") g:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '>>'");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(10)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(3)");
}

TEST_CASE("Binary number literal", "[sema]") {
  TEST_SETUP(R"(
fn void main() {
    var i32 a = 0b01011;
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
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(11)");
}

TEST_CASE("Function pointers", "[sema]") {
  TEST_SETUP(R"(
fn void* foo(i32, f32){}
fn void main() {
    var fn* void*(i32, f32) p_foo = &foo;
    var fn* void*(i32 i, f32 f) p_foo1 = &foo;
    p_foo(1, 1.0);
    var Type t = .{&foo};
    t.p_foo(1, 1.0);
    t.p_foo = &foo;
}
struct Type {
    fn* void*(i32, f32) p_foo;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedStructDecl: Type") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "0. ResolvedMemberField: ptr fn(ptr void)(i32, f32)(p_foo)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFuncDecl: @(");
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedParamDecl: @(");
  REQUIRE(lines_it->find(") __param_foo0:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedParamDecl: @(");
  REQUIRE(lines_it->find(") __param_foo1:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFuncDecl: @(");
  REQUIRE(lines_it->find(") main:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") p_foo:ptr fn(ptr void)(i32, f32)") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") p_foo1:ptr fn(ptr void)(i32, f32)") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(");
  REQUIRE(lines_it->find(") p_foo:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "f32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") t:Type") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: Type");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: p_foo");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructMemberAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") t:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberIndex: 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberID:ptr fn(ptr void)(i32, f32)(p_foo)");
  CONTAINS_NEXT_REQUIRE(lines_it, "CallParameters:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "f32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedAssignment:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructMemberAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") t:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberIndex: 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberID:ptr fn(ptr void)(i32, f32)(p_foo)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
}

TEST_CASE("Function pointer chaining in structs", "[sema]") {
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
  REQUIRE(lines_it->find("ResolvedStructDecl: Type") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "0. ResolvedMemberField: ptr fn(ptr Type)(i32, f32)(p_foo)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFuncDecl: @(");
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedParamDecl: @(");
  REQUIRE(lines_it->find(") __param_foo0:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedParamDecl: @(");
  REQUIRE(lines_it->find(") __param_foo1:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFuncDecl: @(");
  REQUIRE(lines_it->find(") main:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") t:Type") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructLiteralExpr: Type");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFieldInitializer: p_foo");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedStructMemberAccess:");
  CONTAINS_NEXT_REQUIRE(lines_it, "esolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") t:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberIndex: 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberID:ptr fn(ptr Type)(i32, f32)(p_foo)");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberIndex: 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "MemberID:ptr fn(ptr Type)(i32, f32)(p_foo)");
  CONTAINS_NEXT_REQUIRE(lines_it, "CallParameters:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "f32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "CallParameters:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "f32(1)");
}

TEST_CASE("address of assignment as a separate instruction", "[sema]") {
  TEST_SETUP(R"(
fn void main() {
    var i32 i = 0;
    var i32* p_i;
    p_i = &i;
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
  REQUIRE(lines_it->find(") i:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") p_i:ptr i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedAssignment:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") p_i:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedUnaryOperator: '&'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") i:") != std::string::npos);
}

TEST_CASE("Type info", "[sema]") {
  TEST_SETUP_TYPE_INFO(R"(
struct Type {
    u8 *p;
    u8 c;
    i32 x;
}
struct Type1 {
    u8* p;
    u8 c;
    u16 x;
}
struct Type2 {
    u8* p;
    u8 c;
    u64 x;
}
struct Type3 {
    Type type;
    Type1 type1;
    Type2 type3;
}
struct Type4 {
    Type2 type2;
    Type type;
    Type1 type1;
}
fn void main() {
    var i32 i = 0;
    var i32* p_i;
    var Type t;
    var Type1 t1;
    var Type2 t2;
    var Type3 t3;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("Type info - Type2:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignment: 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "Total Size: 24");
  CONTAINS_NEXT_REQUIRE(lines_it, "[8 1 8 ]");
  CONTAINS_NEXT_REQUIRE(lines_it, "Type info - Type3:");
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignment: 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "Total Size: 56");
  CONTAINS_NEXT_REQUIRE(lines_it, "[16 16 24 ]");
  CONTAINS_NEXT_REQUIRE(lines_it, "Type info - Type1:");
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignment: 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "Total Size: 16");
  CONTAINS_NEXT_REQUIRE(lines_it, "[8 1 2 ]");
  CONTAINS_NEXT_REQUIRE(lines_it, "Type info - Type4:");
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignment: 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "Total Size: 56");
  CONTAINS_NEXT_REQUIRE(lines_it, "[24 16 16 ]");
  CONTAINS_NEXT_REQUIRE(lines_it, "Type info - Type:");
  CONTAINS_NEXT_REQUIRE(lines_it, "Alignment: 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "Total Size: 16");
  CONTAINS_NEXT_REQUIRE(lines_it, "[8 1 4 ]");
}

// TODO: support constexprs
TEST_CASE("custom type sizeof()", "[sema]") {
  TEST_SETUP(R"(
struct Type {
    u8 *p;
    u8 c;
    i32 x;
}
struct Type1 {
    u8* p;
    u8 c;
    u16 x;
}
struct Type2 {
    u8* p;
    u8 c;
    u64 x;
}
struct Type3 {
    Type type;
    Type1 type1;
    Type2 type3;
}
struct Type4 {
    Type2 type2;
    Type type;
    Type1 type1;
}
fn void main() {
    var i64 size_t = sizeof(Type);
    var i64 size_t1 = sizeof(Type1);
    var i64 size_t2 = sizeof(Type2);
    var i64 size_t3 = sizeof(Type3);
    var i64 size_t4 = sizeof(Type4);
    var i64 size_t4_p = sizeof(Type4*);
    var i64 size_arr_t4 = sizeof(Type4[12]);
    var i64 size_arr_t4_p = sizeof(Type4*[399]);
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 19;
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFuncDecl: @(");
  REQUIRE(lines_it->find(") main:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_t:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(16)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_t1:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(16)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_t2:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(24)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_t3:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(56)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_t4:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(56)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_t4_p:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_arr_t4:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(672)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_arr_t4_p:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(3192)");
}

TEST_CASE("builtin types sizeof()", "[sema]") {
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
    var i64 size_arr = sizeof(u32[4]);
    var i64 size_p_arr = sizeof(u32*[4]);
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
  REQUIRE(lines_it->find(") size_i8:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_i16:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_i32:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_i64:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_u8:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_u16:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_u32:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_u64:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_f32:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_f64:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_bool:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_ptr:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_arr:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(16)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") size_p_arr:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(32)");
}

TEST_CASE("builtin alignof()", "[sema]") {
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
  REQUIRE(lines_it->find("ResolvedFuncDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") main:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_i8:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_i16:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_i32:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_i64:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_u8:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_u16:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_u32:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_u64:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_f32:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_f64:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_bool:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_ptr:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_arr:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_p_arr:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(8)");
}

TEST_CASE("custom type alignof()", "[sema]") {
  TEST_SETUP(R"(
struct Type {
    u8 *p;
    u8 c;
    i32 x;
}
struct Type1 {
    u8* p;
    u8 c;
    u16 x;
}
struct Type2 {
    u8* p;
    u8 c;
    u64 x;
}
struct Type3 {
    Type type;
    Type1 type1;
    Type2 type3;
}
struct Type4 {
    Type2 type2;
    Type type;
    Type1 type1;
}
fn void main() {
    var i64 align_t = alignof(Type);
    var i64 align_t1 = alignof(Type1);
    var i64 align_t2 = alignof(Type2);
    var i64 align_t3 = alignof(Type3);
    var i64 align_t4 = alignof(Type4);
    var i64 align_t4_p = alignof(Type4*);
    var i64 align_arr_t4 = alignof(Type4[12]);
    var i64 align_arr_t4_p = alignof(Type4*[399]);
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 19;
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedFuncDecl: @(");
  REQUIRE(lines_it->find(") main:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_t:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_t1:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_t2:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_t3:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_t4:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_t4_p:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_arr_t4:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") align_arr_t4_p:i64") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i64(8)");
}

TEST_CASE("defer stmts", "[sema]") {
  TEST_SETUP(R"(
extern {
  fn void* malloc(u64 size);
  fn void free(void* ptr);
}
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
  auto lines_it = lines.begin() + 5;
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") ptr:ptr i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(");
  REQUIRE(lines_it->find(") malloc:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u64(4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeferStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(");
  REQUIRE(lines_it->find(") free:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") ptr:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") ptr2:ptr i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(");
  REQUIRE(lines_it->find(") malloc:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u64(4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeferStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(");
  REQUIRE(lines_it->find(") free:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") ptr2:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") ptr3:ptr i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(");
  REQUIRE(lines_it->find(") malloc:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u64(4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") ptr4:ptr i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(");
  REQUIRE(lines_it->find(") malloc:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u64(4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeferStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(");
  REQUIRE(lines_it->find(") free:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") ptr3:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(");
  REQUIRE(lines_it->find(") free:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") ptr4:") != std::string::npos);
}
