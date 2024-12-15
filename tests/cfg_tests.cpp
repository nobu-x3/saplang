#include "test_utils.h"

#define TEST_SETUP(file_contents)                                                                                                                              \
  saplang::clear_error_stream();                                                                                                                               \
  std::stringstream buffer{file_contents};                                                                                                                     \
  std::stringstream output_buffer{};                                                                                                                           \
  saplang::SourceFile src_file{"cfg_test", buffer.str()};                                                                                                      \
  saplang::Lexer lexer{src_file};                                                                                                                              \
  saplang::Parser parser(&lexer, {{}, false});                                                                                                                 \
  auto parse_result = parser.parse_source_file();                                                                                                              \
  saplang::Sema sema{std::move(parse_result.module->declarations), true};                                                                                       \
  auto resolved_ast = sema.resolve_ast();                                                                                                                      \
  for (auto &&decl : resolved_ast) {                                                                                                                           \
    if (const auto *fn = dynamic_cast<const saplang::ResolvedFuncDecl *>(decl.get())) {                                                                        \
      output_buffer << decl->id << ":\n";                                                                                                                      \
      saplang::CFGBuilder().build(*fn).dump_to_stream(output_buffer, 1);                                                                                       \
    }                                                                                                                                                          \
  }                                                                                                                                                            \
  std::string output_string = output_buffer.str();                                                                                                             \
  auto lines = break_by_line(output_string);                                                                                                                   \
  const auto &error_stream = saplang::get_error_stream();

TEST_CASE("empty function", "[cfg]") {
  TEST_SETUP("fn void foo() {}");
  REQUIRE(error_stream.str() == "");
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("foo:") != std::string::npos);
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1 (entry)]");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
}

TEST_CASE("args", "[cfg]") {
  TEST_SETUP(R"(
    fn void foo(i32 x, i32 y) {}

    fn void bar() {
        foo(1 + 2, 3 + 4);
    }
    )");
  REQUIRE(error_stream.str() == "");
  auto lines_it = lines.begin() + 6;
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "bar:");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2 (entry)]");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '+");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '+");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(7)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedCallExpr: @(")
  REQUIRE(lines_it->find(" foo:") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '+'")
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(3)")
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '+");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(7)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(4)");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
}

TEST_CASE("return", "[cfg]") {
  TEST_SETUP(R"(
    fn i32 foo() {
        3;
        return 3;
        2;
        return 2;
        return 1;
    }
    )");
  REQUIRE(error_stream.str() == "cfg_test:5:9 warning: unreachable statement.\n");
  // REQUIRE(output_string == "");
  auto lines_it = lines.begin();
  REQUIRE(lines_it->find("foo:") != std::string::npos);
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "[4 (entry)]");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 3 ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "[3]");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 4 ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedReturnStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(3)");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2]");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u8(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedReturnStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(2)");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedReturnStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(1)");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 2 3 ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
}

TEST_CASE("conditions", "[cfg]") {
  SECTION("simple or") {
    TEST_SETUP(R"(
    fn void foo() {
      3 || 4.0;
      1;
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("foo:") != std::string::npos);
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "f32(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '||'");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "f32(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("simple and") {
    TEST_SETUP(R"(
    fn void foo() {
      3 && 4.0;
      1;
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("foo:") != std::string::npos);
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "f32(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&&'");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "f32(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("multiple or") {
    TEST_SETUP(R"(
    fn void foo() {
      3 || 4.0 || 5;
      1;
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("foo:") != std::string::npos);
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "f32(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '||'");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "f32(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '||'");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '||'");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "f32(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("multiple and") {
    TEST_SETUP(R"(
    fn void foo() {
      3 && 4.0 && 5;
      1;
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("foo:") != std::string::npos);
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "f32(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&&'");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "f32(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&&'");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&&'");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "f32(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("and or") {
    TEST_SETUP(R"(
    fn void foo() {
      3 && 4.0 || 5;
      1;
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("foo:") != std::string::npos);
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "f32(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&&'");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "f32(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '||'");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&&'");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "f32(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("or and") {
    TEST_SETUP(R"(
    fn void foo() {
      3 || 4.0 && 5;
      1;
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("foo:") != std::string::npos);
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "f32(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&&'");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "f32(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '||'");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&&'");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "f32(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
}

TEST_CASE("while loops", "[cfg]") {
  SECTION("empty while loop") {
    TEST_SETUP(R"(
    fn void foo(){
      while true {}
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("foo:") != std::string::npos);
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[3 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 2 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 1 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedWhileStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 2 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("simple while loop") {
    TEST_SETUP(R"(
    fn void foo() {
      5;
      while 4 {
        3;
      }
      1;
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("foo:") != std::string::npos);
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[6 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[5]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 6 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 4 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[4]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 3 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedWhileStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[3]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 4 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 2 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 4 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 4 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("or condition") {
    TEST_SETUP(R"(
    fn void foo() {
      5;
      while 4 || 4 || 4 {
        3;
      }
      1;
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("foo:") != std::string::npos);
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[6 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[5]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 6 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 4 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[4]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 3 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '||'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '||'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '||'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedWhileStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '||'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '||'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[3]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 4 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 2 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 4 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 4 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("and condition") {
    TEST_SETUP(R"(
    fn void foo() {
      5;
      while 4 && 4 && 4 {
        3;
      }
      1;
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("foo:") != std::string::npos);
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[6 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[5]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 6 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 4 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[4]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 3 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&&'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&&'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&&'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedWhileStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&&'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&&'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[3]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 4 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 2 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 4 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 4 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("while after while") {
    TEST_SETUP(R"(
    fn void foo() {
      while 5 {}
      while 3 {}
      1;
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[6 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[5]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 4 6 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 3 4 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedWhileStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[4]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[3]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 2 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedWhileStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("while after if") {
    TEST_SETUP(R"(
    fn void foo() {
      if 5 {
        4;
      }
      while 3 {}
      1;
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[6 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[5]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 6 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 3(U) 4 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[4]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 3 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[3]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 4 5(U) ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 2 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedWhileStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("while after return") {
    TEST_SETUP(R"(
    fn void foo() {
      4;
      return;
      while 3 {}
      1;
    }
    )");
    REQUIRE(error_stream.str() == "cfg_test:5:7 warning: unreachable statement.\n");
    auto lines_it = lines.begin();
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[5 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 4 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[4]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedReturnStmt");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[3]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 2 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedWhileStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 4 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("nested while loops") {
    TEST_SETUP(R"(
    fn void foo() {
      8;
      while 7 {
        6;
        while 5 {
          4;
        }
      }
      1;
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[9 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 8 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[8]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 9 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 7 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(8)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[7]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 8 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 6 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedWhileStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(6)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedWhileStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[6]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 7 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 5 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(6)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[5]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 3 6 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 2 4 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedWhileStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[4]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 3 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[3]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 4 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 7 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 7 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("return mid while loop") {
    TEST_SETUP(R"(
    fn void foo() {
      8;
      while 7 {
        6;
        if 6 {
          5;
          return;
          4;
        }
        3;
      }
      1;
    }
    )");
    REQUIRE(error_stream.str() == "cfg_test:9:11 warning: unreachable statement.\n");
    auto lines_it = lines.begin();
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[9 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 8 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[8]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 9 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 7 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(8)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[7]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 8 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 6 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedWhileStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(6)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedReturnStmt:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[6]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 7 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 3(U) 5 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(6)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedReturnStmt:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[5]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 6 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedReturnStmt:");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[4]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 3 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[3]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 4 6(U) ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 2 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 7 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 7 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
}

TEST_CASE("if statements", "[cfg]") {
  SECTION("empty body") {
    TEST_SETUP(R"(
    fn void foo() {
      if false {}
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("foo:") != std::string::npos);
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0(U) 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(0)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(0)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1(U) 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("body") {
    TEST_SETUP(R"(
    fn void foo() {
      if false {
        1;
      }
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("foo:") != std::string::npos);
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[3 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 2 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 1(U) ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(0)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(0)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2(U) ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 2 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("block after if") {
    TEST_SETUP(R"(
    fn void foo() {
      if false {
        1;
      }
      2;
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("foo:") != std::string::npos);
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[4 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[3]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 4 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 2(U) ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(0)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(0)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 3(U) ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(2)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("or condition") {
    TEST_SETUP(R"(
    fn void foo() {
      5;
      if 5 || 4 || 3 {
        2;
      }
      1;
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("foo:") != std::string::npos);
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[4 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[3]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 4 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1(U) 2 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '||'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '||'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '||'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '||'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '||'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(2)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(2)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 3(U) ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("and condition") {
    TEST_SETUP(R"(
    fn void foo() {
      5;
      if 5 && 4 && 3 {
        2;
      }
      1;
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    REQUIRE(lines_it->find("foo:") != std::string::npos);
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[4 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[3]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 4 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1(U) 2 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&&'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&&'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&&'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&&'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '&&'");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(2)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 3 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(2)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 3(U) ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("multiple branches") {
    TEST_SETUP(R"(
    fn void foo() {
      if 8 { 7; }
      else if 6 { 5; }
      else if 4 { 3; }
      else { 2; }
      1;
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[9 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 8 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[8]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 9 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 6(U) 7 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(7)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedElseBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedElseBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedElseBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(2)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[7]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 8 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(7)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[6]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 8(U) ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 4(U) 5 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedElseBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedElseBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(2)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[5]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 6 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(5)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[4]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 6(U) ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 2(U) 3 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedElseBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(2)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[3]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 4 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 4(U) ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(2)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 3 5 7 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
  SECTION("nested if stmts") {
    TEST_SETUP(R"(
    fn void foo() {
      if 5 {
        if 4 {
          3;
        } else {
          2;
        }
      }
      1;
    }
    )");
    REQUIRE(error_stream.str() == "");
    auto lines_it = lines.begin();
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[6 (entry)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[5]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 6 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1(U) 4 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedElseBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(2)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[4]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 5 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 2(U) 3 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfStmt");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "bool(1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedElseBlock");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(2)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[3]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 4 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(3)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 4(U) ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(2)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 3 5(U) ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
    CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
    CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
    EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
  }
}

TEST_CASE("return in if stmt", "[cfg]") {
  TEST_SETUP(R"(
  fn i8 foo() {
    if false {}
    else { return 2; }
  }
  )");
  REQUIRE(error_stream.str() == "");
  auto lines_it = lines.begin();
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "[3 (entry)]");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 2 ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2]");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 3 ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0(U) 1 ");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "bool(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfStmt");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "bool(0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedIfBlock");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedElseBlock");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBlock:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedReturnStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i8(2)");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i8(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedReturnStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i8(2)");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 2(U) ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
}

TEST_CASE("non-void fn not returning on all paths", "[cfg]") {
  TEST_SETUP(R"(
  fn i8 foo() {
    if true {}
    else { return 2; }
  }
  )");
  REQUIRE(error_stream.str() == "cfg_test:2:3 error: non-void function does not have a return value.\n");
}

TEST_CASE("assignment, reassignment, self reassignment", "[cfg]") {
  TEST_SETUP(R"(
fn void foo() {
    var i32 x;
    x = 2;
    x = 3;
    x = x + 1;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines_it = lines.begin();
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "[2 (entry)]");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 1 ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "[1]");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 2 ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: 0 ");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclStmt:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedVarDecl: @(");
  REQUIRE(lines_it->find(") x:i32") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedAssignment:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") x") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedAssignment:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") x") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "i32(3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") x") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '+'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") x") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedAssignment:");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") x") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedBinaryOperator: '+'");
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedDeclRefExpr: @(");
  REQUIRE(lines_it->find(") x") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ResolvedNumberLiteral:");
  CONTAINS_NEXT_REQUIRE(lines_it, "u8(1)");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "[0 (exit)]");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  preds: 1 ");
  EXACT_CHECK_NEXT_REQUIRE(lines_it, "  succs: ");
}
