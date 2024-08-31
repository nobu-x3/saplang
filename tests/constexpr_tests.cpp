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

// TEST_CASE("implicit casts", "[constexpr]") {
//   SECTION("integers") {
//       SECTION("passing") {
//           TEST_SETUP(R"(
// fn void foo_i64(i64 x) {}
// fn void foo_i32(i32 x) {}
// fn void foo_i16(i16 x) {}
// fn void foo_i8(i8 x) {}

// fn i32 main() {
//     foo_i64(-1);
//     foo_i64(1);
//     foo_i64(0);
// }
// )");
//       }
//   }
// }

TEST_CASE("operations", "[constexpr]") {
  SECTION("prefix") {
    TEST_SETUP(R"(
fn void foo_int(i32 x) {}
fn void foo_uint(u32 x) {}
fn void foo_float(f32 x) {}
fn void foo_bool(bool x) {}

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
    REQUIRE(lines[0].find("ResolvedFuncDecl: @(") != std::string::npos);
    REQUIRE(lines[0].find(") foo_int:") != std::string::npos);
    REQUIRE(lines[1].find("ResolvedParamDecl: @(") != std::string::npos);
    REQUIRE(lines[1].find(") x:") != std::string::npos);
    REQUIRE(lines[2].find("ResolvedBlock:") != std::string::npos);
    REQUIRE(lines[3].find("ResolvedFuncDecl: @(") != std::string::npos);
    REQUIRE(lines[3].find(") foo_uint:") != std::string::npos);
    REQUIRE(lines[4].find("ResolvedParamDecl: @(") != std::string::npos);
    REQUIRE(lines[4].find(") x:") != std::string::npos);
    REQUIRE(lines[5].find("ResolvedBlock:") != std::string::npos);
    REQUIRE(lines[6].find("ResolvedFuncDecl: @(") != std::string::npos);
    REQUIRE(lines[6].find(") foo_float:") != std::string::npos);
    REQUIRE(lines[7].find("ResolvedParamDecl: @(") != std::string::npos);
    REQUIRE(lines[7].find(") x:") != std::string::npos);
    REQUIRE(lines[8].find("ResolvedBlock:") != std::string::npos);
    REQUIRE(lines[9].find("ResolvedFuncDecl: @(") != std::string::npos);
    REQUIRE(lines[9].find(") foo_bool:") != std::string::npos);
    REQUIRE(lines[10].find("ResolvedParamDecl: @(") != std::string::npos);
    REQUIRE(lines[10].find(") x:") != std::string::npos);
    REQUIRE(lines[11].find("ResolvedBlock:") != std::string::npos);
    REQUIRE(lines[12].find("ResolvedFuncDecl: @(") != std::string::npos);
    REQUIRE(lines[12].find(") main:") != std::string::npos);
    REQUIRE(lines[13].find("ResolvedParamDecl: @(") != std::string::npos);
    REQUIRE(lines[13].find(") x:") != std::string::npos);
    REQUIRE(lines[14].find("ResolvedBlock:") != std::string::npos);
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
}
