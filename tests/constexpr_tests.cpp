#include "test_utils.h"

std::string common = R"(
fn void foo_int(i32 x) {}
fn void foo_uint(u32 x) {}
fn void foo_float(f32 x) {}
fn void foo_bool(bool x) {}
)";

#define COMMON_REQUIRES                                                        \
  REQUIRE(lines[0].find("ResolvedFuncDecl: @(") != std::string::npos);         \
  REQUIRE(lines[0].find(") foo_int:") != std::string::npos);                   \
  REQUIRE(lines[1].find("ResolvedParamDecl: @(") != std::string::npos);        \
  REQUIRE(lines[1].find(") x:") != std::string::npos);                         \
  REQUIRE(lines[2].find("ResolvedBlock:") != std::string::npos);               \
  REQUIRE(lines[3].find("ResolvedFuncDecl: @(") != std::string::npos);         \
  REQUIRE(lines[3].find(") foo_uint:") != std::string::npos);                  \
  REQUIRE(lines[4].find("ResolvedParamDecl: @(") != std::string::npos);        \
  REQUIRE(lines[4].find(") x:") != std::string::npos);                         \
  REQUIRE(lines[5].find("ResolvedBlock:") != std::string::npos);               \
  REQUIRE(lines[6].find("ResolvedFuncDecl: @(") != std::string::npos);         \
  REQUIRE(lines[6].find(") foo_float:") != std::string::npos);                 \
  REQUIRE(lines[7].find("ResolvedParamDecl: @(") != std::string::npos);        \
  REQUIRE(lines[7].find(") x:") != std::string::npos);                         \
  REQUIRE(lines[8].find("ResolvedBlock:") != std::string::npos);               \
  REQUIRE(lines[9].find("ResolvedFuncDecl: @(") != std::string::npos);         \
  REQUIRE(lines[9].find(") foo_bool:") != std::string::npos);                  \
  REQUIRE(lines[10].find("ResolvedParamDecl: @(") != std::string::npos);       \
  REQUIRE(lines[10].find(") x:") != std::string::npos);                        \
  REQUIRE(lines[11].find("ResolvedBlock:") != std::string::npos);              \
  REQUIRE(lines[12].find("ResolvedFuncDecl: @(") != std::string::npos);        \
  REQUIRE(lines[12].find(") main:") != std::string::npos);                     \
  REQUIRE(lines[13].find("ResolvedParamDecl: @(") != std::string::npos);       \
  REQUIRE(lines[13].find(") x:") != std::string::npos);                        \
  REQUIRE(lines[14].find("ResolvedBlock:") != std::string::npos);

#define TEST_SETUP(file_contents)                                              \
  saplang::clear_error_stream();                                               \
  std::stringstream buffer{file_contents};                                     \
  std::stringstream output_buffer{};                                           \
  saplang::SourceFile src_file{"constexpr_tests", buffer.str()};               \
  saplang::Lexer lexer{src_file};                                              \
  saplang::Parser parser(&lexer);                                              \
  auto parse_result = parser.parse_source_file();                              \
  saplang::Sema sema{std::move(parse_result.functions)};                       \
  auto resolved_ast = sema.resolve_ast();                                      \
  for (auto &&fn : resolved_ast) {                                             \
    fn->dump_to_stream(output_buffer);                                         \
  }                                                                            \
  const auto &error_stream = saplang::get_error_stream();                      \
  const std::string output_string = output_buffer.str();                       \
  auto lines = break_by_line(output_string);                                   \
  auto lines_it = lines.begin() + 15;

TEST_CASE("args", "[constexpr]") {
  TEST_SETUP(R"(
fn void foo(i32 x) {}

fn void bar(i32 x) {
    foo(x);
}

fn i32 main() {
    bar(322);
}
)");
  REQUIRE(error_stream.str() == "");
  REQUIRE(lines.size() == 13);
  lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedFuncDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedParamDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBlock:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedFuncDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") bar:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedParamDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBlock:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedFuncDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") main:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBlock:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") bar:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(322)") != std::string::npos);
}

TEST_CASE("prefix operations", "[constexpr]") {
  TEST_SETUP(common + R"(
fn i32 main(i32 x) {
    foo_uint(-1);
    foo_uint(!1);
    foo_bool(!1);
    foo_bool(!0);
    foo_bool(!false);
    foo_bool(!true);
    foo_int(!x);
    foo_int(-x);
    foo_bool(!x);
    foo_float(-1.23);
    foo_bool(!1.23);
}
)");
  REQUIRE(error_stream.str() == "");
  REQUIRE(lines.size() == 64);
  COMMON_REQUIRES
  REQUIRE(lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find("foo_uint") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedUnaryOperator: '-'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(-1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u32(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find("foo_uint") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedUnaryOperator: '!'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u32(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find("foo_bool") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedUnaryOperator: '!'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find("foo_bool") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedUnaryOperator: '!'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find("foo_bool") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedUnaryOperator: '!'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find("foo_bool") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedUnaryOperator: '!'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_int") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedUnaryOperator: '!'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_int") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedUnaryOperator: '-'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedUnaryOperator: '!'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_float") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedUnaryOperator: '-'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(-1.23)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(1.23)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedUnaryOperator: '!'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(1.23)") != std::string::npos);
}

TEST_CASE("multiplicative operations", "[constexpr]") {
  TEST_SETUP(common + R"(
fn i32 main(i32 x) {
    foo_int(5 * 3);
    foo_bool(5 * 3);
    foo_uint(5 * 3);
    foo_int(20 / 4);
    foo_float(20 / 3);
    foo_float(x * 1.0);
    foo_float(1.0 * x);
}
)");
  REQUIRE(error_stream.str() == "");
  REQUIRE(lines.size() == 60);
  COMMON_REQUIRES
  REQUIRE(lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_int:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '*'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(15)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '*'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(15)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_uint:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '*'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u32(15)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u32(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u32(3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_int:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '/'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(20)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(4)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_float:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '/'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(6.66667)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(20)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_float:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '*'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_float:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '*'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
}

TEST_CASE("additive operations", "[constexpr]") {
  TEST_SETUP(common + R"(
fn i32 main(i32 x) {
    foo_int(5 + 3);
    foo_bool(5 + 3);
    foo_uint(5 - 3);
    foo_int(20 - 4);
    foo_float(20 + 3);
    foo_float(x - 1.0);
    foo_float(1.0 - x);
}
)");
  REQUIRE(error_stream.str() == "");
  REQUIRE(lines.size() == 60);
  COMMON_REQUIRES
  REQUIRE(lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_int:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '+'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(8)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '+'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(8)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_uint:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '-'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u32(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u32(3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_int:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '-'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(16)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(20)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(4)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_float:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '+'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(23)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(20)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_float:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '-'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_float:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '-'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
}

TEST_CASE("comparison operations", "[constexpr]") {
  TEST_SETUP(common + R"(
fn i32 main(i32 x) {
  foo_bool(2 < 5);
  foo_bool(-2 < 5);
  foo_bool(2.3 < 5);
  foo_bool(5 < 2);
  foo_bool(5 < 2.3);
  foo_bool(5 < -2);
  foo_bool(x < 2);
  foo_bool(2 < x);
  foo_bool(x > 2);
  foo_bool(2 > x);
  foo_bool(5 <= 5);
  foo_bool(5 >= 5);
  foo_bool(6 <= 5);
  foo_bool(5 >= 6);
}
)");
  REQUIRE(error_stream.str() == "");
  REQUIRE(lines.size() == 109);
  COMMON_REQUIRES
  REQUIRE(lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '<'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '<'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedUnaryOperator: '-'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i8(-2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '<'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2.3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '<'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '<'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2.3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '<'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedUnaryOperator: '-'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i8(-2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '<'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '<'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '>'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '>'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '<='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '>='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '<='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(6)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '>='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(5)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(6)") != std::string::npos);
}

TEST_CASE("equality operators", "[constexpr]") {
  TEST_SETUP(common + R"(
fn i32 main(i32 x) {
  foo_bool(2 == 2);
  foo_bool(3 == 2);
  foo_bool(2.3 == 2);
  foo_bool(2.0 == 2);
  foo_bool(2 == 2.3);
  foo_bool(x == 2);
  foo_bool(2 == x);
  foo_bool(2 != 2);
  foo_bool(3 != 2);
  foo_bool(2.3 != 2);
  foo_bool(2 != 2.3);
  foo_bool(x != 2);
  foo_bool(2 != x);
}
)");
  REQUIRE(error_stream.str() == "");
  REQUIRE(lines.size() == 98);
  COMMON_REQUIRES
  REQUIRE(lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '=='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '=='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '=='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2.3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '=='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '=='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2.3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '=='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '=='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '!='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '!='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '!='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2.3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '!='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2.3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '!='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '!='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
}

TEST_CASE("conjunction operators", "[constexpr]") {
  TEST_SETUP(common + R"(
fn i32 main(i32 x) {
  foo_bool(2 && 3);
  foo_bool(2.0 && 3.0);
  foo_bool(2.0 && 3);
  foo_bool(1 && 0);
  foo_bool(0 && 0);
  foo_bool(true && true);
  foo_bool(true && false);
  foo_bool(false && false);
  foo_bool(x && false);
  foo_bool(false && x);
  foo_bool(true && x);
}
)");
  REQUIRE(error_stream.str() == "");
  REQUIRE(lines.size() == 88);
  COMMON_REQUIRES
  REQUIRE(lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '&&'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '&&'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '&&'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '&&'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i8(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i8(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '&&'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i8(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i8(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '&&'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '&&'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '&&'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '&&'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '&&'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '&&'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
}

TEST_CASE("disjunction operators", "[constexpr]") {
  TEST_SETUP(common + R"(
fn i32 main(i32 x) {
  foo_bool(2 || 3);
  foo_bool(2.0 || 3.0);
  foo_bool(2.0 || 3);
  foo_bool(1 || 0);
  foo_bool(0 || 0);
  foo_bool(0 || 1);
  foo_bool(true || true);
  foo_bool(true || false);
  foo_bool(false || true);
  foo_bool(x || false);
  foo_bool(false || x);
  foo_bool(true || x);
  foo_bool(x || true);
}
)");
  REQUIRE(error_stream.str() == "");
  REQUIRE(lines.size() == 100);
  COMMON_REQUIRES
  REQUIRE(lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '||'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("u8(3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '||'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '||'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '||'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i8(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i8(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '||'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i8(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i8(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '||'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i8(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i8(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '||'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '||'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '||'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '||'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '||'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '||'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo_bool:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '||'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("i32(1)") != std::string::npos);
}

TEST_CASE("grouping", "[constexpr]") {
  TEST_SETUP(R"(
fn bool foo() {
  return (10 * (2.1 + 4.0)) && (!(5.3 == 2.1) || 2.1 <= 5);
}
)")
  REQUIRE(error_stream.str() == "");
  REQUIRE(lines.size() == 39);
  lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedFuncDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") foo:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBlock:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedReturnStmt:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '&&'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedGroupingExpr") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(61)") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '*'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(61)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(10)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedGroupingExpr") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(6.1)") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '+'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(6.1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2.1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(4)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedGroupingExpr") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '||'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedUnaryOperator: '!'") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedGroupingExpr") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '=='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(5.3)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2.1)") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '<='") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(2.1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("f32(5)") != std::string::npos);
}

TEST_CASE("special cases", "[constexpr]") {
  SECTION("binary lhs known") {
    TEST_SETUP(R"(
fn i32 binary_lhs_known(i32 x) {
  return (0 && x) + (true || x);
}
)");
    REQUIRE(error_stream.str() == "");
    lines_it = lines.begin();
    REQUIRE(lines_it->find("ResolvedFuncDecl: @(") != std::string::npos);
    REQUIRE(lines_it->find(") binary_lhs_known:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedParamDecl: @(") != std::string::npos);
    REQUIRE(lines_it->find(") x:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedBlock:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedReturnStmt:") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '+'") !=
                               std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedGroupingExpr:") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '&&'") !=
                               std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("i32(0)") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedDeclRefExpr: @(") !=
                               std::string::npos);
    REQUIRE(lines_it->find(") x:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedGroupingExpr:") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '||'") !=
                               std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("i32(1)") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedDeclRefExpr: @(") !=
                               std::string::npos);
    REQUIRE(lines_it->find(") x:") != std::string::npos);
  }
  SECTION("constexpr return") {
    TEST_SETUP("fn i32 ret() { return 1; }");
    REQUIRE(error_stream.str() == "");
    lines_it = lines.begin();
    REQUIRE(lines_it->find("ResolvedFuncDecl: @(") != std::string::npos);
    REQUIRE(lines_it->find(") ret:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedBlock:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedReturnStmt:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("i32(1)") != std::string::npos);
  }
  SECTION("unary non-const") {
    TEST_SETUP("fn i32 unary_non_const(i32 x) { return !x; }");
    REQUIRE(error_stream.str() == "");
    lines_it = lines.begin();
    REQUIRE(lines_it->find("ResolvedFuncDecl: @(") != std::string::npos);
    REQUIRE(lines_it->find(") unary_non_const:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedParamDecl: @(") != std::string::npos);
    REQUIRE(lines_it->find(") x:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedBlock:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedReturnStmt:") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedUnaryOperator: '!'") !=
                               std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedDeclRefExpr: @(") !=
                               std::string::npos);
    REQUIRE(lines_it->find(") x:") != std::string::npos);
  }
  SECTION("lhs known, rhs not") {
    TEST_SETUP("fn bool lhs_known_rhs_not(i32 x) { return true && x; }");
    REQUIRE(error_stream.str() == "");
    lines_it = lines.begin();
    REQUIRE(lines_it->find("ResolvedFuncDecl: @(") != std::string::npos);
    REQUIRE(lines_it->find(") lhs_known_rhs_not:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedParamDecl: @(") != std::string::npos);
    REQUIRE(lines_it->find(") x:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedBlock:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedReturnStmt:") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '&&'") !=
                               std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedDeclRefExpr: @(") !=
                               std::string::npos);
    REQUIRE(lines_it->find(") x:") != std::string::npos);
  }
  SECTION("lhs unknown, rhs false") {
    TEST_SETUP("fn bool lhs_unknown_rhs_false(i32 x) { return x && false; }");
    REQUIRE(error_stream.str() == "");
    lines_it = lines.begin();
    REQUIRE(lines_it->find("ResolvedFuncDecl: @(") != std::string::npos);
    REQUIRE(lines_it->find(") lhs_unknown_rhs_false:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedParamDecl: @(") != std::string::npos);
    REQUIRE(lines_it->find(") x:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedBlock:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedReturnStmt:") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '&&'") !=
                               std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedDeclRefExpr: @(") !=
                               std::string::npos);
    REQUIRE(lines_it->find(") x:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("i32(0)") != std::string::npos);
  }
  SECTION("lhs unknown, rhs true") {
    TEST_SETUP("fn bool lhs_unknown_rhs_false(i32 x) { return x && (0 - 1); }");
    REQUIRE(error_stream.str() == "");
    lines_it = lines.begin();
    REQUIRE(lines_it->find("ResolvedFuncDecl: @(") != std::string::npos);
    REQUIRE(lines_it->find(") lhs_unknown_rhs_false:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedParamDecl: @(") != std::string::npos);
    REQUIRE(lines_it->find(") x:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedBlock:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedReturnStmt:") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '&&'") !=
                               std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedDeclRefExpr: @(") !=
                               std::string::npos);
    REQUIRE(lines_it->find(") x:") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedGroupingExpr:") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("i32(-1)") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '-'") !=
                               std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("i32(-1)") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("i32(0)") != std::string::npos);
    NEXT_REQUIRE(lines_it,
                 lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
    NEXT_REQUIRE(lines_it, lines_it->find("i32(1)") != std::string::npos);
  }
}

TEST_CASE("Constexpr if condition") {
  TEST_SETUP(R"(
fn i32 main(bool x) {
if true {}
else if x {}
else {}

if x || true {}
else if x && false {}
}
)");
  REQUIRE(error_stream.str() == "");
  lines_it = lines.begin();
  REQUIRE(lines_it->find("ResolvedFuncDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") main:") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedParamDecl: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBlock:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedIfStmt") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedIfBlock") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBlock:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedElseBlock") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBlock:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedIfStmt") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedIfBlock") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBlock:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedElseBlock") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBlock:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedIfStmt") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '||'") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(1)") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedIfBlock") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBlock:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedElseBlock") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBlock:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedIfStmt") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBinaryOperator: '&&'") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines_it->find(") x:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedNumberLiteral:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("bool(0)") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedIfBlock") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ResolvedBlock:") != std::string::npos);
}
