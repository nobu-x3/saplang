#include "test_utils.h"

#define TEST_SETUP(file_contents)                                              \
  saplang::clear_error_stream();                                               \
  std::stringstream buffer{file_contents};                                     \
  std::stringstream output_buffer{};                                           \
  saplang::SourceFile src_file{"sema_test", buffer.str()};                     \
  saplang::Lexer lexer{src_file};                                              \
  saplang::Parser parser(&lexer);                                              \
  auto parse_result = parser.parse_source_file();                              \
  saplang::Sema sema{std::move(parse_result.functions)};                       \
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
  saplang::Sema sema{std::move(parse_result.functions)};                       \
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
            R"(sema_test:5:3 error: expected to call function 'foo',
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