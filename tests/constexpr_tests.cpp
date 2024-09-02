#include <catch2/catch_test_macros.hpp>

#include <sstream>
#include <string>

#include <codegen.h>
#include <lexer.h>
#include <parser.h>
#include <sema.h>
#include <utils.h>

#include <llvm/Support/raw_ostream.h>

std::vector<std::string> break_by_line(const std::string &input) {
  std::stringstream buffer{input};
  std::vector<std::string> output{};
  output.reserve(32);
  std::string line;
  while (std::getline(buffer, line, '\n')) {
    output.push_back(line);
    line.clear();
  }
  return output;
}

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
  auto lines = break_by_line(output_string);

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
  REQUIRE(lines[0].find("ResolvedFuncDecl: @(") != std::string::npos);
  REQUIRE(lines[0].find(") foo:") != std::string::npos);
  REQUIRE(lines[1].find("ResolvedParamDecl: @(") != std::string::npos);
  REQUIRE(lines[1].find(") x:") != std::string::npos);
  REQUIRE(lines[2].find("ResolvedBlock:") != std::string::npos);
  REQUIRE(lines[3].find("ResolvedFuncDecl: @(") != std::string::npos);
  REQUIRE(lines[3].find(") bar:") != std::string::npos);
  REQUIRE(lines[4].find(") x:") != std::string::npos);
  REQUIRE(lines[5].find("ResolvedBlock:") != std::string::npos);
  REQUIRE(lines[6].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[6].find(") foo:") != std::string::npos);
  REQUIRE(lines[7].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[7].find(") x:") != std::string::npos);
  REQUIRE(lines[8].find("ResolvedFuncDecl: @(") != std::string::npos);
  REQUIRE(lines[8].find(") main:") != std::string::npos);
  REQUIRE(lines[9].find("ResolvedBlock:") != std::string::npos);
  REQUIRE(lines[10].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[10].find(") bar:") != std::string::npos);
  REQUIRE(lines[11].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[12].find("i32(322)") != std::string::npos);
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
  REQUIRE(lines[15].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[15].find("foo_uint") != std::string::npos);
  REQUIRE(lines[16].find("ResolvedUnaryOperator: '-'") != std::string::npos);
  REQUIRE(lines[17].find("i32(-1)") != std::string::npos);
  REQUIRE(lines[18].find("ResolvedNumberLiteral") != std::string::npos);
  REQUIRE(lines[19].find("u32(1)") != std::string::npos);
  REQUIRE(lines[20].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[20].find("foo_uint") != std::string::npos);
  REQUIRE(lines[21].find("ResolvedUnaryOperator: '!'") != std::string::npos);
  REQUIRE(lines[22].find("bool(0)") != std::string::npos);
  REQUIRE(lines[23].find("ResolvedNumberLiteral") != std::string::npos);
  REQUIRE(lines[24].find("u32(1)") != std::string::npos);
  REQUIRE(lines[25].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[25].find("foo_bool") != std::string::npos);
  REQUIRE(lines[26].find("ResolvedUnaryOperator: '!'") != std::string::npos);
  REQUIRE(lines[27].find("bool(0)") != std::string::npos);
  REQUIRE(lines[28].find("ResolvedNumberLiteral") != std::string::npos);
  REQUIRE(lines[29].find("bool(1)") != std::string::npos);
  REQUIRE(lines[30].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[30].find("foo_bool") != std::string::npos);
  REQUIRE(lines[31].find("ResolvedUnaryOperator: '!'") != std::string::npos);
  REQUIRE(lines[32].find("bool(1)") != std::string::npos);
  REQUIRE(lines[33].find("ResolvedNumberLiteral") != std::string::npos);
  REQUIRE(lines[34].find("bool(0)") != std::string::npos);
  REQUIRE(lines[35].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[35].find("foo_bool") != std::string::npos);
  REQUIRE(lines[36].find("ResolvedUnaryOperator: '!'") != std::string::npos);
  REQUIRE(lines[37].find("bool(1)") != std::string::npos);
  REQUIRE(lines[38].find("ResolvedNumberLiteral") != std::string::npos);
  REQUIRE(lines[39].find("bool(0)") != std::string::npos);
  REQUIRE(lines[40].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[40].find("foo_bool") != std::string::npos);
  REQUIRE(lines[41].find("ResolvedUnaryOperator: '!'") != std::string::npos);
  REQUIRE(lines[42].find("bool(0)") != std::string::npos);
  REQUIRE(lines[43].find("ResolvedNumberLiteral") != std::string::npos);
  REQUIRE(lines[44].find("bool(1)") != std::string::npos);
  REQUIRE(lines[45].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[45].find(") foo_int") != std::string::npos);
  REQUIRE(lines[46].find("ResolvedUnaryOperator: '!'") != std::string::npos);
  REQUIRE(lines[47].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[47].find(") x:") != std::string::npos);
  REQUIRE(lines[48].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[48].find(") foo_int") != std::string::npos);
  REQUIRE(lines[49].find("ResolvedUnaryOperator: '-'") != std::string::npos);
  REQUIRE(lines[50].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[50].find(") x:") != std::string::npos);
  REQUIRE(lines[51].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[51].find(") foo_bool") != std::string::npos);
  REQUIRE(lines[52].find("ResolvedUnaryOperator: '!'") != std::string::npos);
  REQUIRE(lines[53].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[53].find(") x:") != std::string::npos);
  REQUIRE(lines[54].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[54].find(") foo_float") != std::string::npos);
  REQUIRE(lines[55].find("ResolvedUnaryOperator: '-'") != std::string::npos);
  REQUIRE(lines[56].find("f32(-1.23)") != std::string::npos);
  REQUIRE(lines[57].find("ResolvedNumberLiteral") != std::string::npos);
  REQUIRE(lines[58].find("f32(1.23)") != std::string::npos);
  REQUIRE(lines[59].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[59].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[60].find("ResolvedUnaryOperator: '!'") != std::string::npos);
  REQUIRE(lines[61].find("bool(0)") != std::string::npos);
  REQUIRE(lines[62].find("ResolvedNumberLiteral") != std::string::npos);
  REQUIRE(lines[63].find("f32(1.23)") != std::string::npos);
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
  REQUIRE(lines[15].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[15].find(") foo_int:") != std::string::npos);
  REQUIRE(lines[16].find("ResolvedBinaryOperator: '*'") != std::string::npos);
  REQUIRE(lines[17].find("i32(15)") != std::string::npos);
  REQUIRE(lines[18].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[19].find("i32(5)") != std::string::npos);
  REQUIRE(lines[20].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[21].find("i32(3)") != std::string::npos);
  REQUIRE(lines[22].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[22].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[23].find("ResolvedBinaryOperator: '*'") != std::string::npos);
  REQUIRE(lines[24].find("bool(1)") != std::string::npos);
  REQUIRE(lines[25].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[26].find("bool(1)") != std::string::npos);
  REQUIRE(lines[27].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[28].find("bool(1)") != std::string::npos);
  REQUIRE(lines[29].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[29].find(") foo_uint:") != std::string::npos);
  REQUIRE(lines[30].find("ResolvedBinaryOperator: '*'") != std::string::npos);
  REQUIRE(lines[31].find("u32(15)") != std::string::npos);
  REQUIRE(lines[32].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[33].find("u32(5)") != std::string::npos);
  REQUIRE(lines[34].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[35].find("u32(3)") != std::string::npos);
  REQUIRE(lines[36].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[36].find(") foo_int:") != std::string::npos);
  REQUIRE(lines[37].find("ResolvedBinaryOperator: '/'") != std::string::npos);
  REQUIRE(lines[38].find("i32(5)") != std::string::npos);
  REQUIRE(lines[39].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[40].find("i32(20)") != std::string::npos);
  REQUIRE(lines[41].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[42].find("i32(4)") != std::string::npos);
  REQUIRE(lines[43].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[43].find(") foo_float:") != std::string::npos);
  REQUIRE(lines[44].find("ResolvedBinaryOperator: '/'") != std::string::npos);
  REQUIRE(lines[45].find("f32(6.66667)") != std::string::npos);
  REQUIRE(lines[46].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[47].find("f32(20)") != std::string::npos);
  REQUIRE(lines[48].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[49].find("f32(3)") != std::string::npos);
  REQUIRE(lines[50].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[50].find(") foo_float:") != std::string::npos);
  REQUIRE(lines[51].find("ResolvedBinaryOperator: '*'") != std::string::npos);
  REQUIRE(lines[52].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[52].find(") x:") != std::string::npos);
  REQUIRE(lines[53].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[54].find("f32(1)") != std::string::npos);
  REQUIRE(lines[55].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[55].find(") foo_float:") != std::string::npos);
  REQUIRE(lines[56].find("ResolvedBinaryOperator: '*'") != std::string::npos);
  REQUIRE(lines[57].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[58].find("f32(1)") != std::string::npos);
  REQUIRE(lines[59].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[59].find(") x:") != std::string::npos);
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
  REQUIRE(lines[15].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[15].find(") foo_int:") != std::string::npos);
  REQUIRE(lines[16].find("ResolvedBinaryOperator: '+'") != std::string::npos);
  REQUIRE(lines[17].find("i32(8)") != std::string::npos);
  REQUIRE(lines[18].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[19].find("i32(5)") != std::string::npos);
  REQUIRE(lines[20].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[21].find("i32(3)") != std::string::npos);
  REQUIRE(lines[22].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[22].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[23].find("ResolvedBinaryOperator: '+'") != std::string::npos);
  REQUIRE(lines[24].find("bool(1)") != std::string::npos);
  REQUIRE(lines[25].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[26].find("bool(1)") != std::string::npos);
  REQUIRE(lines[27].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[28].find("bool(1)") != std::string::npos);
  REQUIRE(lines[29].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[29].find(") foo_uint:") != std::string::npos);
  REQUIRE(lines[30].find("ResolvedBinaryOperator: '-'") != std::string::npos);
  REQUIRE(lines[31].find("u32(2)") != std::string::npos);
  REQUIRE(lines[32].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[33].find("u32(5)") != std::string::npos);
  REQUIRE(lines[34].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[35].find("u32(3)") != std::string::npos);
  REQUIRE(lines[36].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[36].find(") foo_int:") != std::string::npos);
  REQUIRE(lines[37].find("ResolvedBinaryOperator: '-'") != std::string::npos);
  REQUIRE(lines[38].find("i32(16)") != std::string::npos);
  REQUIRE(lines[39].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[40].find("i32(20)") != std::string::npos);
  REQUIRE(lines[41].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[42].find("i32(4)") != std::string::npos);
  REQUIRE(lines[43].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[43].find(") foo_float:") != std::string::npos);
  REQUIRE(lines[44].find("ResolvedBinaryOperator: '+'") != std::string::npos);
  REQUIRE(lines[45].find("f32(23)") != std::string::npos);
  REQUIRE(lines[46].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[47].find("f32(20)") != std::string::npos);
  REQUIRE(lines[48].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[49].find("f32(3)") != std::string::npos);
  REQUIRE(lines[50].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[50].find(") foo_float:") != std::string::npos);
  REQUIRE(lines[51].find("ResolvedBinaryOperator: '-'") != std::string::npos);
  REQUIRE(lines[52].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[52].find(") x:") != std::string::npos);
  REQUIRE(lines[53].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[54].find("f32(1)") != std::string::npos);
  REQUIRE(lines[55].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[55].find(") foo_float:") != std::string::npos);
  REQUIRE(lines[56].find("ResolvedBinaryOperator: '-'") != std::string::npos);
  REQUIRE(lines[57].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[58].find("f32(1)") != std::string::npos);
  REQUIRE(lines[59].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[59].find(") x:") != std::string::npos);
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
  REQUIRE(lines.size() == 107);
  COMMON_REQUIRES
  REQUIRE(lines[15].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[15].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[16].find("ResolvedBinaryOperator: '<'") != std::string::npos);
  REQUIRE(lines[17].find("bool(1)") != std::string::npos);
  REQUIRE(lines[18].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[19].find("u8(2)") != std::string::npos);
  REQUIRE(lines[20].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[21].find("u8(5)") != std::string::npos);
  REQUIRE(lines[22].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[22].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[23].find("ResolvedBinaryOperator: '<'") != std::string::npos);
  REQUIRE(lines[24].find("ResolvedUnaryOperator: '-'") != std::string::npos);
  REQUIRE(lines[25].find("i8(-2)") != std::string::npos);
  REQUIRE(lines[26].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[27].find("u8(2)") != std::string::npos);
  REQUIRE(lines[28].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[29].find("u8(5)") != std::string::npos);
  REQUIRE(lines[30].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[30].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[31].find("ResolvedBinaryOperator: '<'") != std::string::npos);
  REQUIRE(lines[32].find("bool(1)") != std::string::npos);
  REQUIRE(lines[33].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[34].find("f32(2.3)") != std::string::npos);
  REQUIRE(lines[35].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[36].find("f32(5)") != std::string::npos);
  REQUIRE(lines[37].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[37].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[38].find("ResolvedBinaryOperator: '<'") != std::string::npos);
  REQUIRE(lines[39].find("bool(0)") != std::string::npos);
  REQUIRE(lines[40].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[41].find("u8(5)") != std::string::npos);
  REQUIRE(lines[42].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[43].find("u8(2)") != std::string::npos);
  REQUIRE(lines[44].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[44].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[45].find("ResolvedBinaryOperator: '<'") != std::string::npos);
  REQUIRE(lines[46].find("bool(0)") != std::string::npos);
  REQUIRE(lines[47].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[48].find("f32(5)") != std::string::npos);
  REQUIRE(lines[49].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[50].find("f32(2.3)") != std::string::npos);
  REQUIRE(lines[51].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[51].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[52].find("ResolvedBinaryOperator: '<'") != std::string::npos);
  REQUIRE(lines[53].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[54].find("u8(5)") != std::string::npos);
  REQUIRE(lines[55].find("ResolvedUnaryOperator: '-'") != std::string::npos);
  REQUIRE(lines[56].find("i8(-2)") != std::string::npos);
  REQUIRE(lines[57].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[58].find("u8(2)") != std::string::npos);
  REQUIRE(lines[59].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[59].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[60].find("ResolvedBinaryOperator: '<'") != std::string::npos);
  REQUIRE(lines[61].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[61].find(") x:") != std::string::npos);
  REQUIRE(lines[62].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[63].find("u8(2)") != std::string::npos);
  REQUIRE(lines[64].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[64].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[65].find("ResolvedBinaryOperator: '<'") != std::string::npos);
  REQUIRE(lines[66].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[67].find("u8(2)") != std::string::npos);
  REQUIRE(lines[68].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[68].find(") x:") != std::string::npos);
  REQUIRE(lines[69].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[69].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[70].find("ResolvedBinaryOperator: '>'") != std::string::npos);
  REQUIRE(lines[71].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[71].find(") x:") != std::string::npos);
  REQUIRE(lines[72].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[73].find("u8(2)") != std::string::npos);
  REQUIRE(lines[74].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[74].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[75].find("ResolvedBinaryOperator: '>'") != std::string::npos);
  REQUIRE(lines[76].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[77].find("u8(2)") != std::string::npos);
  REQUIRE(lines[78].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[78].find(") x:") != std::string::npos);
  REQUIRE(lines[79].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[79].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[80].find("ResolvedBinaryOperator: '<='") != std::string::npos);
  REQUIRE(lines[81].find("bool(1)") != std::string::npos);
  REQUIRE(lines[82].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[83].find("u8(5)") != std::string::npos);
  REQUIRE(lines[84].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[85].find("u8(5)") != std::string::npos);
  REQUIRE(lines[86].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[86].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[87].find("ResolvedBinaryOperator: '>='") != std::string::npos);
  REQUIRE(lines[88].find("bool(1)") != std::string::npos);
  REQUIRE(lines[89].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[90].find("u8(5)") != std::string::npos);
  REQUIRE(lines[91].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[92].find("u8(5)") != std::string::npos);
  REQUIRE(lines[93].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[93].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[94].find("ResolvedBinaryOperator: '<='") != std::string::npos);
  REQUIRE(lines[95].find("bool(0)") != std::string::npos);
  REQUIRE(lines[96].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[97].find("u8(6)") != std::string::npos);
  REQUIRE(lines[98].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[99].find("u8(5)") != std::string::npos);
  REQUIRE(lines[100].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[100].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[101].find("ResolvedBinaryOperator: '>='") != std::string::npos);
  REQUIRE(lines[102].find("bool(0)") != std::string::npos);
  REQUIRE(lines[103].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[104].find("u8(5)") != std::string::npos);
  REQUIRE(lines[105].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[106].find("u8(6)") != std::string::npos);
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
  REQUIRE(lines[15].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[15].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[16].find("ResolvedBinaryOperator: '=='") != std::string::npos);
  REQUIRE(lines[17].find("bool(1)") != std::string::npos);
  REQUIRE(lines[18].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[19].find("u8(2)") != std::string::npos);
  REQUIRE(lines[20].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[21].find("u8(2)") != std::string::npos);
  REQUIRE(lines[22].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[22].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[23].find("ResolvedBinaryOperator: '=='") != std::string::npos);
  REQUIRE(lines[24].find("bool(0)") != std::string::npos);
  REQUIRE(lines[25].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[26].find("u8(3)") != std::string::npos);
  REQUIRE(lines[27].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[28].find("u8(2)") != std::string::npos);
  REQUIRE(lines[29].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[29].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[30].find("ResolvedBinaryOperator: '=='") != std::string::npos);
  REQUIRE(lines[31].find("bool(0)") != std::string::npos);
  REQUIRE(lines[32].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[33].find("f32(2.3)") != std::string::npos);
  REQUIRE(lines[34].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[35].find("f32(2)") != std::string::npos);
  REQUIRE(lines[36].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[36].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[37].find("ResolvedBinaryOperator: '=='") != std::string::npos);
  REQUIRE(lines[38].find("bool(1)") != std::string::npos);
  REQUIRE(lines[39].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[40].find("f32(2)") != std::string::npos);
  REQUIRE(lines[41].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[42].find("f32(2)") != std::string::npos);
  REQUIRE(lines[43].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[43].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[44].find("ResolvedBinaryOperator: '=='") != std::string::npos);
  REQUIRE(lines[45].find("bool(0)") != std::string::npos);
  REQUIRE(lines[46].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[47].find("f32(2)") != std::string::npos);
  REQUIRE(lines[48].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[49].find("f32(2.3)") != std::string::npos);
  REQUIRE(lines[50].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[50].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[51].find("ResolvedBinaryOperator: '=='") != std::string::npos);
  REQUIRE(lines[52].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[52].find(") x:") != std::string::npos);
  REQUIRE(lines[53].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[54].find("u8(2)") != std::string::npos);
  REQUIRE(lines[55].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[55].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[56].find("ResolvedBinaryOperator: '=='") != std::string::npos);
  REQUIRE(lines[57].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[58].find("u8(2)") != std::string::npos);
  REQUIRE(lines[59].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[59].find(") x:") != std::string::npos);
  REQUIRE(lines[60].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[60].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[61].find("ResolvedBinaryOperator: '!='") != std::string::npos);
  REQUIRE(lines[62].find("bool(0)") != std::string::npos);
  REQUIRE(lines[63].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[64].find("u8(2)") != std::string::npos);
  REQUIRE(lines[65].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[66].find("u8(2)") != std::string::npos);
  REQUIRE(lines[67].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[67].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[68].find("ResolvedBinaryOperator: '!='") != std::string::npos);
  REQUIRE(lines[69].find("bool(1)") != std::string::npos);
  REQUIRE(lines[70].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[71].find("u8(3)") != std::string::npos);
  REQUIRE(lines[72].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[73].find("u8(2)") != std::string::npos);
  REQUIRE(lines[74].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[74].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[75].find("ResolvedBinaryOperator: '!='") != std::string::npos);
  REQUIRE(lines[76].find("bool(1)") != std::string::npos);
  REQUIRE(lines[77].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[78].find("f32(2.3)") != std::string::npos);
  REQUIRE(lines[79].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[80].find("f32(2)") != std::string::npos);
  REQUIRE(lines[81].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[81].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[82].find("ResolvedBinaryOperator: '!='") != std::string::npos);
  REQUIRE(lines[83].find("bool(1)") != std::string::npos);
  REQUIRE(lines[84].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[85].find("f32(2)") != std::string::npos);
  REQUIRE(lines[86].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[87].find("f32(2.3)") != std::string::npos);
  REQUIRE(lines[88].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[88].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[89].find("ResolvedBinaryOperator: '!='") != std::string::npos);
  REQUIRE(lines[90].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[90].find(") x:") != std::string::npos);
  REQUIRE(lines[91].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[92].find("u8(2)") != std::string::npos);
  REQUIRE(lines[93].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[93].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[94].find("ResolvedBinaryOperator: '!='") != std::string::npos);
  REQUIRE(lines[95].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[96].find("u8(2)") != std::string::npos);
  REQUIRE(lines[97].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[97].find(") x:") != std::string::npos);
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
  REQUIRE(lines[15].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[15].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[16].find("ResolvedBinaryOperator: '&&'") != std::string::npos);
  REQUIRE(lines[17].find("bool(1)") != std::string::npos);
  REQUIRE(lines[18].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[19].find("bool(1)") != std::string::npos);
  REQUIRE(lines[20].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[21].find("bool(1)") != std::string::npos);
  REQUIRE(lines[22].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[22].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[23].find("ResolvedBinaryOperator: '&&'") != std::string::npos);
  REQUIRE(lines[24].find("bool(1)") != std::string::npos);
  REQUIRE(lines[25].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[26].find("f32(2)") != std::string::npos);
  REQUIRE(lines[27].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[28].find("f32(3)") != std::string::npos);
  REQUIRE(lines[29].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[29].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[30].find("ResolvedBinaryOperator: '&&'") != std::string::npos);
  REQUIRE(lines[31].find("bool(1)") != std::string::npos);
  REQUIRE(lines[32].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[33].find("f32(2)") != std::string::npos);
  REQUIRE(lines[34].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[35].find("bool(1)") != std::string::npos);
  REQUIRE(lines[36].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[36].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[37].find("ResolvedBinaryOperator: '&&'") != std::string::npos);
  REQUIRE(lines[38].find("bool(0)") != std::string::npos);
  REQUIRE(lines[39].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[40].find("bool(1)") != std::string::npos);
  REQUIRE(lines[41].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[42].find("bool(0)") != std::string::npos);
  REQUIRE(lines[43].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[43].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[44].find("ResolvedBinaryOperator: '&&'") != std::string::npos);
  REQUIRE(lines[45].find("bool(0)") != std::string::npos);
  REQUIRE(lines[46].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[47].find("bool(0)") != std::string::npos);
  REQUIRE(lines[48].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[49].find("bool(0)") != std::string::npos);
  REQUIRE(lines[50].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[50].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[51].find("ResolvedBinaryOperator: '&&'") != std::string::npos);
  REQUIRE(lines[52].find("bool(1)") != std::string::npos);
  REQUIRE(lines[53].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[54].find("bool(1)") != std::string::npos);
  REQUIRE(lines[55].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[56].find("bool(1)") != std::string::npos);
  REQUIRE(lines[57].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[57].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[58].find("ResolvedBinaryOperator: '&&'") != std::string::npos);
  REQUIRE(lines[59].find("bool(0)") != std::string::npos);
  REQUIRE(lines[60].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[61].find("bool(1)") != std::string::npos);
  REQUIRE(lines[62].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[63].find("bool(0)") != std::string::npos);
  REQUIRE(lines[64].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[64].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[65].find("ResolvedBinaryOperator: '&&'") != std::string::npos);
  REQUIRE(lines[66].find("bool(0)") != std::string::npos);
  REQUIRE(lines[67].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[68].find("bool(0)") != std::string::npos);
  REQUIRE(lines[69].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[70].find("bool(0)") != std::string::npos);
  REQUIRE(lines[71].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[71].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[72].find("ResolvedBinaryOperator: '&&'") != std::string::npos);
  REQUIRE(lines[73].find("bool(0)") != std::string::npos);
  REQUIRE(lines[74].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[74].find(") x:") != std::string::npos);
  REQUIRE(lines[75].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[76].find("bool(0)") != std::string::npos);
  REQUIRE(lines[77].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[77].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[78].find("ResolvedBinaryOperator: '&&'") != std::string::npos);
  REQUIRE(lines[79].find("bool(0)") != std::string::npos);
  REQUIRE(lines[80].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[81].find("bool(0)") != std::string::npos);
  REQUIRE(lines[82].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[82].find(") x:") != std::string::npos);
  REQUIRE(lines[83].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[83].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[84].find("ResolvedBinaryOperator: '&&'") != std::string::npos);
  REQUIRE(lines[85].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[86].find("bool(1)") != std::string::npos);
  REQUIRE(lines[87].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[87].find(") x:") != std::string::npos);
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
  REQUIRE(lines[15].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[15].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[16].find("ResolvedBinaryOperator: '||'") != std::string::npos);
  REQUIRE(lines[17].find("bool(1)") != std::string::npos);
  REQUIRE(lines[18].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[19].find("bool(1)") != std::string::npos);
  REQUIRE(lines[20].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[21].find("bool(1)") != std::string::npos);
  REQUIRE(lines[22].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[22].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[23].find("ResolvedBinaryOperator: '||'") != std::string::npos);
  REQUIRE(lines[24].find("bool(1)") != std::string::npos);
  REQUIRE(lines[25].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[26].find("f32(2)") != std::string::npos);
  REQUIRE(lines[27].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[28].find("f32(3)") != std::string::npos);
  REQUIRE(lines[29].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[29].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[30].find("ResolvedBinaryOperator: '||'") != std::string::npos);
  REQUIRE(lines[31].find("bool(1)") != std::string::npos);
  REQUIRE(lines[32].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[33].find("f32(2)") != std::string::npos);
  REQUIRE(lines[34].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[35].find("bool(1)") != std::string::npos);
  REQUIRE(lines[36].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[36].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[37].find("ResolvedBinaryOperator: '||'") != std::string::npos);
  REQUIRE(lines[38].find("bool(1)") != std::string::npos);
  REQUIRE(lines[39].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[40].find("bool(1)") != std::string::npos);
  REQUIRE(lines[41].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[42].find("bool(0)") != std::string::npos);
  REQUIRE(lines[43].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[43].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[44].find("ResolvedBinaryOperator: '||'") != std::string::npos);
  REQUIRE(lines[45].find("bool(0)") != std::string::npos);
  REQUIRE(lines[46].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[47].find("bool(0)") != std::string::npos);
  REQUIRE(lines[48].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[49].find("bool(0)") != std::string::npos);
  REQUIRE(lines[50].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[50].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[51].find("ResolvedBinaryOperator: '||'") != std::string::npos);
  REQUIRE(lines[52].find("bool(1)") != std::string::npos);
  REQUIRE(lines[53].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[54].find("bool(0)") != std::string::npos);
  REQUIRE(lines[55].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[56].find("bool(1)") != std::string::npos);
  REQUIRE(lines[57].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[57].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[58].find("ResolvedBinaryOperator: '||'") != std::string::npos);
  REQUIRE(lines[59].find("bool(1)") != std::string::npos);
  REQUIRE(lines[60].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[61].find("bool(1)") != std::string::npos);
  REQUIRE(lines[62].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[63].find("bool(1)") != std::string::npos);
  REQUIRE(lines[64].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[64].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[65].find("ResolvedBinaryOperator: '||'") != std::string::npos);
  REQUIRE(lines[66].find("bool(1)") != std::string::npos);
  REQUIRE(lines[67].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[68].find("bool(1)") != std::string::npos);
  REQUIRE(lines[69].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[70].find("bool(0)") != std::string::npos);
  REQUIRE(lines[71].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[71].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[72].find("ResolvedBinaryOperator: '||'") != std::string::npos);
  REQUIRE(lines[73].find("bool(1)") != std::string::npos);
  REQUIRE(lines[74].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[75].find("bool(0)") != std::string::npos);
  REQUIRE(lines[76].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[77].find("bool(1)") != std::string::npos);
  REQUIRE(lines[78].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[78].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[79].find("ResolvedBinaryOperator: '||'") != std::string::npos);
  REQUIRE(lines[80].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[80].find(") x:") != std::string::npos);
  REQUIRE(lines[81].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[82].find("bool(0)") != std::string::npos);
  REQUIRE(lines[83].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[83].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[84].find("ResolvedBinaryOperator: '||'") != std::string::npos);
  REQUIRE(lines[85].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[86].find("bool(0)") != std::string::npos);
  REQUIRE(lines[87].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[87].find(") x:") != std::string::npos);
  REQUIRE(lines[88].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[88].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[89].find("ResolvedBinaryOperator: '||'") != std::string::npos);
  REQUIRE(lines[90].find("bool(1)") != std::string::npos);
  REQUIRE(lines[91].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[92].find("bool(1)") != std::string::npos);
  REQUIRE(lines[93].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[93].find(") x:") != std::string::npos);
  REQUIRE(lines[94].find("ResolvedCallExpr: @(") != std::string::npos);
  REQUIRE(lines[94].find(") foo_bool:") != std::string::npos);
  REQUIRE(lines[95].find("ResolvedBinaryOperator: '||'") != std::string::npos);
  REQUIRE(lines[96].find("bool(1)") != std::string::npos);
  REQUIRE(lines[97].find("ResolvedDeclRefExpr: @(") != std::string::npos);
  REQUIRE(lines[97].find(") x:") != std::string::npos);
  REQUIRE(lines[98].find("ResolvedNumberLiteral:") != std::string::npos);
  REQUIRE(lines[99].find("bool(1)") != std::string::npos);

}
