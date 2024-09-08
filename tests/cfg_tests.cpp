#include "test_utils.h"

#define TEST_SETUP(file_contents)                                              \
  saplang::clear_error_stream();                                               \
  std::stringstream buffer{file_contents};                                     \
  std::stringstream output_buffer{};                                           \
  saplang::SourceFile src_file{"cfg_test", buffer.str()};                      \
  saplang::Lexer lexer{src_file};                                              \
  saplang::Parser parser(&lexer);                                              \
  auto parse_result = parser.parse_source_file();                              \
  saplang::Sema sema{std::move(parse_result.functions)};                       \
  auto resolved_ast = sema.resolve_ast();                                      \
  for (auto &&fn : resolved_ast) {                                             \
    output_buffer << fn->id << ":\n";                                          \
    saplang::CFGBuilder().build(*fn).dump_to_stream(output_buffer, 1);         \
  }                                                                            \
  std::string output_string = output_buffer.str();                             \
  auto lines = break_by_line(output_string);                                   \
  const auto &error_stream = saplang::get_error_stream();

#define EXACT_CHECK_NEXT_REQUIRE(it, text)                                     \
  NEXT_REQUIRE(it, it->find(text) != std::string::npos);                       \
  REQUIRE(*it == text);

#define CONTAINS_NEXT_REQUIRE(it, text)                                        \
  NEXT_REQUIRE(it, it->find(text) != std::string::npos);

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
  REQUIRE(error_stream.str() ==
          "cfg_test:5:9 warning: unreachable statement.\n");
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