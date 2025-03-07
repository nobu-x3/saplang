#include "catch2/catch_test_macros.hpp"
#include "test_utils.h"

#define TEST_SETUP(file_contents)                                                                                                                              \
  saplang::clear_error_stream();                                                                                                                               \
  std::stringstream buffer{file_contents};                                                                                                                     \
  std::string output_string;                                                                                                                                   \
  llvm::raw_string_ostream output_buffer{output_string};                                                                                                       \
  saplang::SourceFile src_file{"codegen_test", buffer.str()};                                                                                                  \
  saplang::Lexer lexer{src_file};                                                                                                                              \
  saplang::Parser parser(&lexer, {{}, false});                                                                                                                 \
  auto parse_result = parser.parse_source_file();                                                                                                              \
  saplang::Sema sema{std::move(parse_result.module->declarations)};                                                                                            \
  auto resolved_ast = sema.resolve_ast();                                                                                                                      \
  saplang::Codegen codegen{std::move(resolved_ast), "codegen_tests"};                                                                                          \
  auto generated_code = codegen.generate_ir();                                                                                                                 \
  generated_code->print(output_buffer, nullptr, true, true);                                                                                                   \
  const auto &error_stream = saplang::get_error_stream();

#define TEST_SETUP_MODULE_SINGLE(module_name, file_contents)                                                                                                   \
  saplang::clear_error_stream();                                                                                                                               \
  std::stringstream buffer{file_contents};                                                                                                                     \
  std::stringstream output_buffer{};                                                                                                                           \
  saplang::SourceFile src_file{module_name, buffer.str()};                                                                                                     \
  saplang::Lexer lexer{src_file};                                                                                                                              \
  saplang::Parser parser(&lexer, {{}, false});                                                                                                                 \
  std::vector<std::unique_ptr<saplang::Module>> modules;                                                                                                       \
  auto parse_result = parser.parse_source_file();                                                                                                              \
  modules.emplace_back(std ::move(parse_result.module));                                                                                                       \
  saplang ::Sema sema{std::move(modules)};                                                                                                                     \
  auto resolved_modules = sema.resolve_modules();                                                                                                              \
  const auto &error_stream = saplang::get_error_stream();                                                                                                      \
  saplang ::Codegen codegen{std ::move(resolved_modules), sema.move_type_infos(), false};                                                                      \
  auto gened_modules = codegen.generate_modules();                                                                                                             \
  std ::string output_string;                                                                                                                                  \
  llvm ::raw_string_ostream codegen_output_buffer{output_string};                                                                                              \
  for (auto &&[name, mod] : gened_modules) {                                                                                                                   \
    if (mod && mod->module)                                                                                                                                    \
      mod->module->print(codegen_output_buffer, nullptr, true, true);                                                                                          \
  }                                                                                                                                                            \
  output_buffer << output_string;

TEST_CASE("single return", "[codegen]") {
  SECTION("return stmt 1 fn") {
    TEST_SETUP(R"(fn bool foo() { return true; }
)");
    REQUIRE(output_string ==
            R"(; ModuleID = '<tu>'
source_filename = "codegen_tests"
target triple = "x86-64"

define i1 @foo() {
entry:
  %retval = alloca i1, align 1
  store i1 true, ptr %retval, align 1
  br label %return

return:                                           ; preds = <null operand!>, %entry
  %0 = load i1, ptr %retval, align 1
  ret i1 %0
}
)");
  }
  SECTION("return stmt 2 fns") {
    TEST_SETUP(R"(fn bool foo() { return true; }
fn bool bar() { return true; }
)");
    REQUIRE(output_string ==
            R"(; ModuleID = '<tu>'
source_filename = "codegen_tests"
target triple = "x86-64"

define i1 @foo() {
entry:
  %retval = alloca i1, align 1
  store i1 true, ptr %retval, align 1
  br label %return

return:                                           ; preds = <null operand!>, %entry
  %0 = load i1, ptr %retval, align 1
  ret i1 %0
}

define i1 @bar() {
entry:
  %retval = alloca i1, align 1
  store i1 true, ptr %retval, align 1
  br label %return

return:                                           ; preds = <null operand!>, %entry
  %0 = load i1, ptr %retval, align 1
  ret i1 %0
}
)");
  }
}

TEST_CASE("multiple return", "[codegen]") {
  TEST_SETUP("fn void main() { return; 1; return;}");
  REQUIRE(output_string ==
          R"(; ModuleID = '<tu>'
source_filename = "codegen_tests"
target triple = "x86-64"

define void @main() {
entry:
  br label %return

return:                                           ; preds = <null operand!>, %entry
  ret void
}
)");
}

TEST_CASE("alloca order", "[codegen]") {
  SECTION("Basic setup") {
    TEST_SETUP(R"(
fn void foo(i32 x, bool y, i64 z) {
  x;
  y;
  z;
}
)");
    REQUIRE(output_string == R"(; ModuleID = '<tu>'
source_filename = "codegen_tests"
target triple = "x86-64"

define void @foo(i32 %x, i1 %y, i64 %z) {
entry:
  %x1 = alloca i32, align 4
  %y2 = alloca i1, align 1
  %z3 = alloca i64, align 8
  store i32 %x, ptr %x1, align 4
  store i1 %y, ptr %y2, align 1
  store i64 %z, ptr %z3, align 4
  %0 = load i32, ptr %x1, align 4
  %1 = load i1, ptr %y2, align 1
  %2 = load i64, ptr %z3, align 4
  ret void
}
)");
  }
  SECTION("Setup with call") {
    TEST_SETUP(R"(
fn void foo(i32 x, bool y, i64 z) {
  x;
  y;
  z;
}

fn void main() {
  foo(1, true, 255);
}
)");
    REQUIRE(output_string == R"(; ModuleID = '<tu>'
source_filename = "codegen_tests"
target triple = "x86-64"

define void @foo(i32 %x, i1 %y, i64 %z) {
entry:
  %x1 = alloca i32, align 4
  %y2 = alloca i1, align 1
  %z3 = alloca i64, align 8
  store i32 %x, ptr %x1, align 4
  store i1 %y, ptr %y2, align 1
  store i64 %z, ptr %z3, align 4
  %0 = load i32, ptr %x1, align 4
  %1 = load i1, ptr %y2, align 1
  %2 = load i64, ptr %z3, align 4
  ret void
}

define void @main() {
entry:
  call void @foo(i32 1, i1 true, i64 255)
  ret void
}
)");
    REQUIRE(error_stream.str() == "");
  }
}

TEST_CASE("Conditionals, binary ops") {
  std::string common = R"(

fn bool truef(i32 x) {
  return true;
}

fn bool falsef(i32 x) {
  return false;
}
)";
  SECTION("false || true && false") {
    TEST_SETUP(common + R"(
fn i32 main() {
  falsef(1) || truef(2) && falsef(3);
  return -2;
}
)");
    REQUIRE(remove_whitespace(output_string) == remove_whitespace(R"(; ModuleID = '<tu>'
  source_filename = "codegen_tests"
  target triple = "x86-64"

define i1 @truef(i32 %x) {
  entry:
    %retval = alloca i1, align 1
    %x1 = alloca i32, align 4
    store i32 %x, ptr %x1, align 4
    store i1 true, ptr %retval, align 1
    br label %return

return:                                           ; preds = <null operand!>,
  %entry
    %0 = load i1, ptr %retval, align 1
    ret i1 %0
  }

define i1 @falsef(i32 %x) {
  entry:
    %retval = alloca i1, align 1
    %x1 = alloca i32, align 4
    store i32 %x, ptr %x1, align 4
    store i1 false, ptr %retval, align 1
    br label %return

return:                                           ; preds = <null operand!>,
  %entry
    %0 = load i1, ptr %retval, align 1
    ret i1 %0
  }

define i32 @main() {
  entry:
    %retval = alloca i32, align 4
    %0 = call i1 @falsef(i32 1)
    br i1 %0, label %or.merge, label %or.rhs

or.rhs:                                           ; preds = %entry
    %1 = call i1 @truef(i32 2)
    br i1 %1, label %and.rhs, label %and.merge

or.merge:                                         ; preds = %and.merge,
  %entry
    %2 = phi i1 [ %4, %and.merge ], [ true, %entry ]
    store i32 -2, ptr %retval, align 4
    br label %return

and.rhs:                                          ; preds = %or.rhs
    %3 = call i1 @falsef(i32 3)
    br label %and.merge

and.merge:                                        ; preds = %and.rhs, %or.
  rhs
    %4 = phi i1 [ %3, %and.rhs ], [ false, %or.rhs ]
    br label %or.merge

return:                                           ; preds = <null operand!>,
  %or.merge
    %5 = load i32, ptr %retval, align 4
    ret i32 %5
  })"));
    REQUIRE(error_stream.str() == "");
  }
  SECTION("false || true || true") {
    TEST_SETUP(common + R"(
fn i32 main() {
  falsef(4) || truef(5) || truef(6);
}
)");
    REQUIRE(remove_whitespace(output_string) == remove_whitespace(R"(; ModuleID = '<tu>'
  source_filename = "codegen_tests"
  target triple = "x86-64"

define i1 @truef(i32 %x) {
  entry:
    %retval = alloca i1, align 1
    %x1 = alloca i32, align 4
    store i32 %x, ptr %x1, align 4
    store i1 true, ptr %retval, align 1
    br label %return

return:                                           ; preds = <null operand!>,
  %entry
    %0 = load i1, ptr %retval, align 1
    ret i1 %0
  }

define i1 @falsef(i32 %x) {
  entry:
    %retval = alloca i1, align 1
    %x1 = alloca i32, align 4
    store i32 %x, ptr %x1, align 4
    store i1 false, ptr %retval, align 1
    br label %return

return:                                           ; preds = <null operand!>,
  %entry
    %0 = load i1, ptr %retval, align 1
    ret i1 %0
  }

define i32 @main() {
  entry:
    %retval = alloca i32, align 4
    %0 = call i1 @falsef(i32 4)
    br i1 %0, label %or.merge, label %or.lhs.false

or.rhs:                                           ; preds = %or.lhs.false
    %1 = call i1 @truef(i32 6)
    br label %or.merge

or.merge:                                         ; preds = %or.rhs, %or.
  lhs.false, %entry
    %2 = phi i1 [ %1, %or.rhs ], [ true, %or.lhs.false ], [ true, %entry ]
    %3 = load i32, ptr %retval, align 4
    ret i32 %3

or.lhs.false:                                     ; preds = %entry
    %4 = call i1 @truef(i32 5)
    br i1 %4, label %or.merge, label %or.rhs

; uselistorder directives
    uselistorder label %or.merge, { 1, 0, 2 }
  }

; uselistorder directives
  uselistorder ptr @truef, { 1, 0 })"));
    REQUIRE(error_stream.str() == "");
  }
  SECTION("false && false && true") {
    TEST_SETUP(common + R"(
fn i32 main() {
  falsef(7) && falsef(8) && truef(9);
}
)");
    REQUIRE(remove_whitespace(output_string) == remove_whitespace(R"(; ModuleID = '<tu>'
  source_filename = "codegen_tests"
  target triple = "x86-64"

define i1 @truef(i32 %x) {
  entry:
    %retval = alloca i1, align 1
    %x1 = alloca i32, align 4
    store i32 %x, ptr %x1, align 4
    store i1 true, ptr %retval, align 1
    br label %return

return:                                           ; preds = <null operand!>,
  %entry
    %0 = load i1, ptr %retval, align 1
    ret i1 %0
  }

define i1 @falsef(i32 %x) {
  entry:
    %retval = alloca i1, align 1
    %x1 = alloca i32, align 4
    store i32 %x, ptr %x1, align 4
    store i1 false, ptr %retval, align 1
    br label %return

return:                                           ; preds = <null operand!>,
  %entry
    %0 = load i1, ptr %retval, align 1
    ret i1 %0
  }

define i32 @main() {
  entry:
    %retval = alloca i32, align 4
    %0 = call i1 @falsef(i32 7)
    br i1 %0, label %and.lhs.true, label %and.merge

and.rhs:                                          ; preds = %and.lhs.true
    %1 = call i1 @truef(i32 9)
    br label %and.merge

and.merge:                                        ; preds = %and.rhs, %and.
  lhs.true, %entry
    %2 = phi i1 [ %1, %and.rhs ], [ false, %and.lhs.true ], [ false, %entry ]
    %3 = load i32, ptr %retval, align 4
    ret i32 %3

and.lhs.true:                                     ; preds = %entry
    %4 = call i1 @falsef(i32 8)
    br i1 %4, label %and.rhs, label %and.merge

; uselistorder directives
    uselistorder label %and.merge, { 1, 0, 2 }
  }
)"));
    REQUIRE(error_stream.str() == "");
  }
  SECTION("true || true || true") {
    TEST_SETUP(common + R"(
fn i32 main() {
  truef(10) || truef(11) || truef(12);
}
)");
    REQUIRE(remove_whitespace(output_string) == remove_whitespace(R"(; ModuleID = '<tu>'
  source_filename = "codegen_tests"
  target triple = "x86-64"

define i1 @truef(i32 %x) {
  entry:
    %retval = alloca i1, align 1
    %x1 = alloca i32, align 4
    store i32 %x, ptr %x1, align 4
    store i1 true, ptr %retval, align 1
    br label %return

return:                                           ; preds = <null operand!>,
  %entry
    %0 = load i1, ptr %retval, align 1
    ret i1 %0
  }

define i1 @falsef(i32 %x) {
  entry:
    %retval = alloca i1, align 1
    %x1 = alloca i32, align 4
    store i32 %x, ptr %x1, align 4
    store i1 false, ptr %retval, align 1
    br label %return

return:                                           ; preds = <null operand!>,
  %entry
    %0 = load i1, ptr %retval, align 1
    ret i1 %0
  }

define i32 @main() {
  entry:
    %retval = alloca i32, align 4
    %0 = call i1 @truef(i32 10)
    br i1 %0, label %or.merge, label %or.lhs.false

or.rhs:                                           ; preds = %or.lhs.false
    %1 = call i1 @truef(i32 12)
    br label %or.merge

or.merge:                                         ; preds = %or.rhs, %or.
  lhs.false, %entry
    %2 = phi i1 [ %1, %or.rhs ], [ true, %or.lhs.false ], [ true, %entry ]
    %3 = load i32, ptr %retval, align 4
    ret i32 %3

or.lhs.false:                                     ; preds = %entry
    %4 = call i1 @truef(i32 11)
    br i1 %4, label %or.merge, label %or.rhs

; uselistorder directives
    uselistorder label %or.merge, { 1, 0, 2 }
  }

; uselistorder directives
  uselistorder ptr @truef, { 1, 0, 2 }
)"));
    REQUIRE(error_stream.str() == "");
  }
  SECTION("false || true && false || true") {
    TEST_SETUP(common + R"(
fn i32 main() {
  falsef(13) || truef(14) && falsef(15) || truef(16);
}
)");
    REQUIRE(remove_whitespace(output_string) == remove_whitespace(R"(; ModuleID = '<tu>'
  source_filename = "codegen_tests"
  target triple = "x86-64"

define i1 @truef(i32 %x) {
  entry:
    %retval = alloca i1, align 1
    %x1 = alloca i32, align 4
    store i32 %x, ptr %x1, align 4
    store i1 true, ptr %retval, align 1
    br label %return

return:                                           ; preds = <null operand!>,
  %entry
    %0 = load i1, ptr %retval, align 1
    ret i1 %0
  }

define i1 @falsef(i32 %x) {
  entry:
    %retval = alloca i1, align 1
    %x1 = alloca i32, align 4
    store i32 %x, ptr %x1, align 4
    store i1 false, ptr %retval, align 1
    br label %return

return:                                           ; preds = <null operand!>,
  %entry
    %0 = load i1, ptr %retval, align 1
    ret i1 %0
  }

define i32 @main() {
  entry:
    %retval = alloca i32, align 4
    %0 = call i1 @falsef(i32 13)
    br i1 %0, label %or.merge, label %or.lhs.false

or.rhs:                                           ; preds = %and.lhs.true,
  %or.lhs.false
    %1 = call i1 @truef(i32 16)
    br label %or.merge

or.merge:                                         ; preds = %or.rhs, %and.
  lhs.true, %entry
    %2 = phi i1 [ %1, %or.rhs ], [ true, %and.lhs.true ], [ true, %entry ]
    %3 = load i32, ptr %retval, align 4
    ret i32 %3

or.lhs.false:                                     ; preds = %entry
    %4 = call i1 @truef(i32 14)
    br i1 %4, label %and.lhs.true, label %or.rhs

and.lhs.true:                                     ; preds = %or.lhs.false
    %5 = call i1 @falsef(i32 15)
    br i1 %5, label %or.merge, label %or.rhs

; uselistorder directives
    uselistorder label %or.merge, { 1, 0, 2 }
  }

; uselistorder directives
  uselistorder ptr @truef, { 1, 0 })"));
    REQUIRE(error_stream.str() == "");
  }
}

TEST_CASE("if statement, binop condition") {
  TEST_SETUP(R"(
fn void foo(i32 x) {
  if x == 1 || x == 2 && x > 3 {
  }
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 3;
  REQUIRE(lines_it->find("define void @foo(i32 %x) {") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("entry:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%x1 = alloca i32, align 4") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("store i32 %x, ptr %x1, align 4") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%0 = load i32, ptr %x1, align 4") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%1 = icmp eq i32 %0, 1") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%to.bool = icmp ne i1 %1, false") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("br i1 %to.bool, label %or.merge, label %or.rhs") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("or.rhs") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %entry") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%2 = load i32, ptr %x1, align 4") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%3 = icmp eq i32 %2, 2") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%to.bool2 = icmp ne i1 %3, false") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("br i1 %to.bool2, label %and.rhs, label %and.merge") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("or.merge") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %and.merge, %entry") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%4 = phi i1 [ %7, %and.merge ], [ true, %entry ]") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("br i1 %4, label %if.true, label %if.exit") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("and.rhs") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %or.rhs") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%5 = load i32, ptr %x1, align 4") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%6 = icmp sgt i32 %5, 3") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%to.bool3 = icmp ne i1 %6, false") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("br label %and.merge") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("and.merge") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %and.rhs, %or.rhs") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%7 = phi i1 [ %to.bool3, %and.rhs ], [ false, %or.rhs ]") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("br label %or.merge") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("if.true") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %or.merge") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("br label %if.exit") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("if.exit") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %if.true, %or.merge") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ret void") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("}") != std::string::npos);
}

TEST_CASE("simple while loop return", "[codegen]") {
  TEST_SETUP(R"(
  fn void foo(bool val) {
    while val {
      return;
    }
  }
  )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 3;
  REQUIRE(lines_it->find("define void @foo(i1 %val) {") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("entry:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%val1 = alloca i1, align 1") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("store i1 %val, ptr %val1, align 1") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("br label %while.cond") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("while.cond:") != std::string::npos);
  REQUIRE(lines_it->find("; preds = <null operand!>, %entry") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%0 = load i1, ptr %val1, align 1") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("br i1 %0, label %while.body, label %while.exit") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("while.body:") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %while.cond") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ret void") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("while.exit:") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %while.cond") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ret void") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("}") != std::string::npos);
}

TEST_CASE("simple while loop", "[codegen]") {
  TEST_SETUP(R"(
  fn void foo(i32 val) {
    while val > 3 {
      bar();
    }
  }

  fn void bar() {}
  )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 3;
  REQUIRE(lines_it->find("define void @foo(i32 %val) {") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("entry:") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%val1 = alloca i32, align 4") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("store i32 %val, ptr %val1, align 4") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("br label %while.cond") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("while.cond:") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %while.body, %entry") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%0 = load i32, ptr %val1, align 4") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%1 = icmp ugt i32 %0, 3") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find(" br i1 %1, label %while.body, label %while.exit") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("while.body:") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %while.cond") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("call void @bar()") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("br label %while.cond") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("while.exit:") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %while.cond") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("ret void") != std::string::npos);
}

TEST_CASE("codegen var decl", "[codegen]") {
  TEST_SETUP(R"(
    fn void foo() {
      var i32 x = 1;
      var i32 y = 2;
      var i32 z = 3;
      var i32 a;
      bar(x);
      bar(y);
      bar(z);
      bar(a);
    }

    fn void bar(i32 num) {}
  )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 5;
  REQUIRE(lines_it->find("%x = alloca i32, align 4") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "%y = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%z = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 1, ptr %x, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 2, ptr %y, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 3, ptr %z, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load i32, ptr %x, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @bar(i32 %0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load i32, ptr %y, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @bar(i32 %1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %z, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @bar(i32 %2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = load i32, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @bar(i32 %3)");
}

TEST_CASE("assignment", "[codegen]") {
  TEST_SETUP(R"(
fn void foo(i32 x) {
  var i64 y;
  y = 3;
  y = (x + 4) / 2;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 5;
  REQUIRE(lines_it->find("%x1 = alloca i32, align 4") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "%y = alloca i64, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %x, ptr %x1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i64 3, ptr %y, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load i64, ptr %x1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = add i64 %0, 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = sdiv i64 %1, 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i64 %2, ptr %y, align 4");
}

TEST_CASE("for loop", "[codegen]") {
  TEST_SETUP(R"(
fn void foo() {
  for(var u32 i = 0; i < 10; i = i + 1){}
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 5;
  REQUIRE(lines_it->find("%i = alloca i32, align 4") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %for.counter_decl");
  CONTAINS_NEXT_REQUIRE(lines_it, "for.counter_decl:");
  REQUIRE(lines_it->find("; preds = %entry") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %i, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %for.condition");
  CONTAINS_NEXT_REQUIRE(lines_it, "for.condition:");
  REQUIRE(lines_it->find("; preds = %for.counter_op, %for.counter_decl") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load i32, ptr %i, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = icmp ult i32 %0, 10");
  CONTAINS_NEXT_REQUIRE(lines_it, "%to.bool = icmp ne i1 %1, false");
  CONTAINS_NEXT_REQUIRE(lines_it, "br i1 %to.bool, label %for.body, label %for.exit");
  CONTAINS_NEXT_REQUIRE(lines_it, "for.body:");
  REQUIRE(lines_it->find("; preds = %for.condition") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %for.counter_op");
  CONTAINS_NEXT_REQUIRE(lines_it, "for.counter_op:");
  REQUIRE(lines_it->find("; preds = %for.body") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %i, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = add i32 %2, 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %3, ptr %i, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %for.condition");
  CONTAINS_NEXT_REQUIRE(lines_it, "for.exit:");
  REQUIRE(lines_it->find("; preds = %for.condition") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
}

TEST_CASE("struct type declaration", "[codegen]") {
  TEST_SETUP(R"(
  struct TestType {
    i32 a;
    f32 b;
    i8 c;
    u32 d;
  }
fn void foo() {
  var TestType t;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 3;
  REQUIRE(lines_it->find("%TestType = type { i32, float, i8, i32 }") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%t = alloca %TestType, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("struct literal initialization", "[codegen]") {
  TEST_SETUP(R"(
  struct TestType {
    i32 a;
    f32 b;
    bool c;
    u32 d;
  }
fn void foo() {
  var TestType t = .{.a = -1, .b = 2.0, .c = true, .d = 250};
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 3;
  REQUIRE(lines_it->find("%TestType = type { i32, float, i1, i32 }") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%t = alloca %TestType, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 -1, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 2.000000e+00, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %2, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 250, ptr %3, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("struct member access", "[codegen]") {
  TEST_SETUP(R"(
  struct TestType {
    i32 a;
    f32 b;
    bool c;
    u32 d;
  }
fn i32 foo() {
  var TestType t = .{.a = -1, .b = 2.0, .c = true, .d = 250};
  return t.a;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 3;
  REQUIRE(lines_it->find("%TestType = type { i32, float, i1, i32 }") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%t = alloca %TestType, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 -1, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 2.000000e+00, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %2, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 250, ptr %3, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = load i32, ptr %4, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %5, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%6 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %6");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("struct member assignment", "[codegen]") {
  TEST_SETUP(R"(
  struct TestType {
    i32 a;
    f32 b;
    bool c;
    i32 d;
  }
fn i32 foo() {
  var TestType t = .{.a = -1, .b = 2.0, .c = true, .d = 250};
  t.a = 5;
  t.d = 15;
  return t.d;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 3;
  REQUIRE(lines_it->find("%TestType = type { i32, float, i1, i32 }") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%t = alloca %TestType, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 -1, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 2.000000e+00, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %2, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 250, ptr %3, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 5, ptr %4, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 15, ptr %5, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%6 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "%7 = load i32, ptr %6, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %7, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%8 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %8");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("struct literal in function parameter", "[codegen]") {
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
  const i32 ret1 = foo(.{.a = 0, .b = 3.0, .c = false, .d = 251});
  return foo(t);
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 3;
  REQUIRE(lines_it->find("%TestType = type { i32, float, i1, i32 }") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @foo(%TestType %variable) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%variable1 = alloca %TestType, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store %TestType %variable, ptr %variable1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %TestType, ptr %variable1, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 15, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %TestType, ptr %variable1, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %2, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %3");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @bar() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%t = alloca %TestType, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%ret1 = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = alloca %TestType, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 -1, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 2.000000e+00, ptr %2, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %3, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 250, ptr %4, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %5, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%6 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 3.000000e+00, ptr %6, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%7 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 false, ptr %7, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%8 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 251, ptr %8, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%9 = call i32 @foo(ptr %0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %9, ptr %ret1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%10 = load %TestType, ptr %t, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%11 = call i32 @foo(%TestType %10)");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %11, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%12 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %12");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("struct in struct literal initialization", "[codegen]") {
  TEST_SETUP(R"(
  struct TestType {
    i32 a;
    f32 b;
    bool c;
    u32 d;
  }
struct TestType2 {
  TestType test_type;
}
fn void foo() {
  var TestType2 t = .{.{.a = -1, .b = 2.0, .c = true, .d = 250}};
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 3;
  REQUIRE(lines_it->find("%TestType2 = type { %TestType }") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType = type { i32, float, i1, i32 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%t = alloca %TestType2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %TestType2, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 -1, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 2.000000e+00, ptr %2, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %3, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 250, ptr %4, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("member variable parameter passing", "[codegen]") {
  TEST_SETUP(R"(
  struct TestType {
    i32 a;
    f32 b;
    bool c;
    u32 d;
  }
struct TestType2 {
  TestType test_type;
}
fn i32 bar(TestType variable) {
  variable.d = 15;
  return variable.d;
}
fn i32 foo() {
  var TestType2 t = .{.{.a = -1, .b = 2.0, .c = true, .d = 250}};
  return bar(t.test_type);
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 3;
  REQUIRE(lines_it->find("%TestType = type { i32, float, i1, i32 }") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType2 = type { %TestType }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @bar(%TestType %variable) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%variable1 = alloca %TestType, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store %TestType %variable, ptr %variable1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %TestType, ptr %variable1, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 15, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %TestType, ptr %variable1, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %2, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %3");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%t = alloca %TestType2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %TestType2, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 -1, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 2.000000e+00, ptr %2, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %3, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 250, ptr %4, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = getelementptr inbounds %TestType2, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%6 = load %TestType, ptr %5, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%7 = call i32 @bar(%TestType %6)");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %7, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%8 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %8");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("chain member access", "[codegen]") {
  TEST_SETUP(R"(
struct TestType {
    i32 a;
    f32 b;
    bool c;
    i32 d;
}
struct TestType2 {
  TestType test_type;
}
fn i32 main() {
  var TestType2 t = .{.{.a = -1, .b = 2.0, .c = true, .d = 250}};
  return t.test_type.d;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 3;
  REQUIRE(lines_it->find("%TestType2 = type { %TestType }") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType = type { i32, float, i1, i32 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @main() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%t = alloca %TestType2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %TestType2, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 -1, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 2.000000e+00, ptr %2, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %3, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 250, ptr %4, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = getelementptr inbounds %TestType2, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%6 = getelementptr inbounds %TestType, ptr %5, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "%7 = load i32, ptr %6, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %7, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%8 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %8");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("chain member access in function parameters", "[codegen]") {
  TEST_SETUP(R"(
struct TestType {
    i32 a;
    f32 b;
    bool c;
    i32 d;
}
struct TestType2 {
  TestType test_type;
}
fn i32 foo(i32 d) { return d; }
fn i32 main() {
  var TestType2 t = .{.{.a = -1, .b = 2.0, .c = true, .d = 250}};
  return foo(t.test_type.d);
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 3;
  REQUIRE(lines_it->find("%TestType2 = type { %TestType }") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType = type { i32, float, i1, i32 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @foo(i32 %d) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%d1 = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %d, ptr %d1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load i32, ptr %d1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %0, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %1");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @main() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%t = alloca %TestType2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %TestType2, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 -1, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 2.000000e+00, ptr %2, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %3, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 250, ptr %4, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = getelementptr inbounds %TestType2, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%6 = getelementptr inbounds %TestType, ptr %5, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "%7 = load i32, ptr %6, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%8 = call i32 @foo(i32 %7)");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %8, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%9 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %9");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("nested struct type var reassignment", "[codegen]") {
  TEST_SETUP(R"(
struct TestType {
i32 a;
f32 b;
bool c;
}
struct TestType2 {
TestType test;
}
fn void foo(){
  var TestType2 test1 = .{.{15,16.0,true}};
  test1.test = .{17,18.0,false};
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType2 = type { %TestType }");
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType = type { i32, float, i1 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%test1 = alloca %TestType2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = alloca %TestType, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %TestType2, ptr %test1, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = getelementptr inbounds %TestType, ptr %1, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 15, ptr %2, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = getelementptr inbounds %TestType, ptr %1, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 1.600000e+01, ptr %3, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = getelementptr inbounds %TestType, ptr %1, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %4, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = getelementptr inbounds %TestType2, ptr %test1, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%6 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 17, ptr %6, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%7 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 1.800000e+01, ptr %7, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%8 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 false, ptr %8, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @llvm.memcpy.p0.p0.i64(ptr align "
                                  "8 %5, ptr align 8 %0, i64 12, i1 false)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
}

TEST_CASE("nested struct type var reassignment from another struct", "[codegen]") {
  TEST_SETUP(R"(
struct TestType {
i32 a;
f32 b;
bool c;
}
struct TestType2 {
TestType test;
}
fn void foo(){
  const TestType2 test2 = .{.{17,18.0,false}};
  var TestType2 test1 = .{.{15,16.0,true}};
  test1.test = test2.test;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType2 = type { %TestType }");
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType = type { i32, float, i1 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%test2 = alloca %TestType2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%test1 = alloca %TestType2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %TestType2, ptr %test2, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 17, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 1.800000e+01, ptr %2, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 false, ptr %3, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = getelementptr inbounds %TestType2, ptr %test1, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = getelementptr inbounds %TestType, ptr %4, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 15, ptr %5, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%6 = getelementptr inbounds %TestType, ptr %4, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 1.600000e+01, ptr %6, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%7 = getelementptr inbounds %TestType, ptr %4, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %7, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%8 = getelementptr inbounds %TestType2, ptr %test1, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%9 = getelementptr inbounds %TestType2, ptr %test2, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%10 = load %TestType, ptr %9, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store %TestType %10, ptr %8, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
}

TEST_CASE("global builtin type var", "[codegen]") {
  TEST_SETUP(R"(
var i32 test_i32 = 15;
const i32 test_const_i32 = 18;
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "@test_i32 = global i32 15");
  CONTAINS_NEXT_REQUIRE(lines_it, "@test_const_i32 = constant i32 18");
}

TEST_CASE("global struct type var", "[codegen]") {
  TEST_SETUP(R"(
struct TestType {
i32 a;
f32 b;
bool c;
}
var TestType test1 = .{15, 16.0, true};
const TestType test2 = .{17, 18.0, false};
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType = type { i32, float, i1 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "@test1 = global %TestType { i32 15, float 1.600000e+01, i1 true }");
  CONTAINS_NEXT_REQUIRE(lines_it, "@test2 = constant %TestType { i32 17, float 1.800000e+01, i1 false }");
}

TEST_CASE("global nested struct type var", "[codegen]") {
  TEST_SETUP(R"(
struct TestType {
i32 a;
f32 b;
bool c;
}
struct TestType2 {
TestType test;
}
var TestType2 test1 = .{.{15, 16.0, true}};
const TestType2 test2 = .{.{17, 18.0, false}};
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType2 = type { %TestType }");
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType = type { i32, float, i1 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "@test1 = global %TestType2 { %TestType { "
                                  "i32 15, float 1.600000e+01, i1 true } }");
  CONTAINS_NEXT_REQUIRE(lines_it, "@test2 = constant %TestType2 { %TestType { "
                                  "i32 17, float 1.800000e+01, i1 false } }");
}

TEST_CASE("global builtin type var access from function", "[codegen]") {
  TEST_SETUP(R"(
var i32 test_i32 = 15;
fn void foo(){
  test_i32 = 16;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "@test_i32 = global i32 15");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 16, ptr @test_i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("global struct type var access from function", "[codegen]") {
  TEST_SETUP(R"(
struct TestType {
i32 a;
f32 b;
bool c;
}
var TestType test1 = .{15, 16.0, true};
const TestType test2 = .{17, 18.0, false};
fn void foo(){
  test1.a = 16;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType = type { i32, float, i1 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "@test1 = global %TestType { i32 15, float 1.600000e+01, i1 true }");
  CONTAINS_NEXT_REQUIRE(lines_it, "@test2 = constant %TestType { i32 17, float 1.800000e+01, i1 false }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 16, ptr @test1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("global struct type var access from function last element", "[codegen]") {
  TEST_SETUP(R"(
struct TestType {
i32 a;
f32 b;
bool c;
i32 d;
}
var TestType test1 = .{15, 16.0, true, 0};
const TestType test2 = .{17, 18.0, false, 0};
fn void foo(){
  test1.d = 16;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType = type { i32, float, i1, i32 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "@test1 = global %TestType { i32 15, float "
                                  "1.600000e+01, i1 true, i32 0 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "@test2 = constant %TestType { i32 17, float "
                                  "1.800000e+01, i1 false, i32 0 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 16, ptr getelementptr inbounds (%TestType, "
                                  "ptr @test1, i32 0, i32 3), align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("global nested struct type var reassignment from function", "[codegen]") {
  TEST_SETUP(R"(
struct TestType {
i32 a;
f32 b;
bool c;
}
struct TestType2 {
TestType test;
}
var TestType2 test1 = .{.{15, 16.0, true}};
const TestType2 test2 = .{.{17, 18.0, false}};
fn void foo(){
  test1.test = .{15,16.0,true};
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType2 = type { %TestType }");
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType = type { i32, float, i1 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "@test1 = global %TestType2 { %TestType { "
                                  "i32 15, float 1.600000e+01, i1 true } }");
  CONTAINS_NEXT_REQUIRE(lines_it, "@test2 = constant %TestType2 { %TestType { "
                                  "i32 17, float 1.800000e+01, i1 false } }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = alloca %TestType, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 15, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 1.600000e+01, ptr %2, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %3, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @llvm.memcpy.p0.p0.i64(ptr align 8 @test1, "
                                  "ptr align 8 %0, i64 12, i1 false)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
}

TEST_CASE("global nested struct type var reassignment from another var from function", "[codegen]") {
  TEST_SETUP(R"(
struct TestType {
i32 a;
f32 b;
bool c;
}
struct TestType2 {
TestType test;
}
var TestType2 test1 = .{.{15, 16.0, true}};
const TestType2 test2 = .{.{17, 18.0, false}};
fn void foo(){
  test1.test = test2.test;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_string);
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType2 = type { %TestType }");
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType = type { i32, float, i1 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "@test1 = global %TestType2 { %TestType { "
                                  "i32 15, float 1.600000e+01, i1 true } }");
  CONTAINS_NEXT_REQUIRE(lines_it, "@test2 = constant %TestType2 { %TestType { "
                                  "i32 17, float 1.800000e+01, i1 false } }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load %TestType, ptr @test2, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store %TestType %0, ptr @test1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
}

TEST_CASE("builtin type pointer decl null initialization", "[codegen]") {
  TEST_SETUP(R"(
var i32* test = null;
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "@test = global ptr null");
}

TEST_CASE("struct pointer decl null initialization", "[codegen]") {
  TEST_SETUP(R"(
struct TestStruct { i32 a; }
var TestStruct* test = null;
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "@test = global ptr null");
}

TEST_CASE("struct decl field null initialization", "[codegen]") {
  TEST_SETUP(R"(
struct TestStruct { i32 *a; }
var TestStruct test = .{null};
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestStruct = type { ptr }");
  CONTAINS_NEXT_REQUIRE(lines_it, "@test = global %TestStruct zeroinitializer");
}

TEST_CASE("builtin type address of operator storing", "[codegen]") {
  TEST_SETUP(R"(
fn void foo() {
var i32 a = 0;
var i32* ptr = &a;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%ptr = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %a, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("builtin type address of operator storing to parameter", "[codegen]") {
  TEST_SETUP(R"(
fn void bar(i32* ptr) {}
fn void foo() {
var i32 a = 0;
bar(&a);
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @bar(ptr %ptr) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%ptr1 = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %ptr, ptr %ptr1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @bar(ptr %a)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("custom type address of operator storing", "[codegen]") {
  TEST_SETUP(R"(
struct TestStruct { i32 a; }
fn void foo() {
var TestStruct a = .{0};
var TestStruct* ptr = &a;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestStruct = type { i32 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca %TestStruct, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%ptr = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %TestStruct, ptr %a, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %a, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("custom type address of operator storing to parameter", "[codegen]") {
  TEST_SETUP(R"(
struct TestStruct { i32 a; }
fn void bar(TestStruct* ptr) {}
fn void foo() {
var TestStruct a = .{0};
bar(&a);
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestStruct = type { i32 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @bar(ptr %ptr) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%ptr1 = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %ptr, ptr %ptr1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca %TestStruct, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %TestStruct, ptr %a, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @bar(ptr %a)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("custom type pointer member assignment", "[codegen]") {
  TEST_SETUP(R"(
struct TestStruct { i32* a; }
fn void foo() {
var i32 a = 0;
var TestStruct str = .{&a};
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestStruct = type { ptr }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%str = alloca %TestStruct, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %TestStruct, ptr %str, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %a, ptr %0, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("member field address of function parameter", "[codegen]") {
  TEST_SETUP(R"(
struct TestStruct { i32* a; }
fn void bar(i32* a) {}
fn void foo() {
var i32 a = 0;
var TestStruct str = .{&a};
bar(str.a);
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestStruct = type { ptr }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @bar(ptr %a) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a1 = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %a, ptr %a1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%str = alloca %TestStruct, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %TestStruct, ptr %str, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %a, ptr %0, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %TestStruct, ptr %str, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load ptr, ptr %1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @bar(ptr %2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("derefencing builtin types", "[codegen]") {
  TEST_SETUP(R"(
fn void foo() {
var i32 a = 0;
var i32* ptr = &a;
var i32 b = *ptr;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%ptr = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%b = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %a, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load ptr, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load i32, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %1, ptr %b, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("builtin type dereference operator storing to parameter", "[codegen]") {
  TEST_SETUP(R"(
fn void bar(i32 a) {}
fn void foo() {
var i32 a = 0;
var i32* ptr = &a;
bar(*ptr);
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @bar(i32 %a) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a1 = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %a, ptr %a1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%ptr = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %a, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load ptr, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load i32, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @bar(i32 %1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("custom type dereference operator storing", "[codegen]") {
  TEST_SETUP(R"(
struct TestStruct { i32 a; }
fn void foo() {
var TestStruct a = .{0};
var TestStruct* ptr = &a;
var TestStruct b = *ptr;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestStruct = type { i32 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca %TestStruct, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%ptr = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%b = alloca %TestStruct, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %TestStruct, ptr %a, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, " store ptr %a, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load ptr, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load %TestStruct, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store %TestStruct %2, ptr %b, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("custom type dereference operator storing to parameter", "[codegen]") {
  TEST_SETUP(R"(
 struct TestStruct { i32 a; }
 fn void bar(TestStruct a) {}
 fn void foo() {
 var TestStruct a = .{0};
 var TestStruct* ptr = &a;
 bar(*ptr);
 }
 )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestStruct = type { i32 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @bar(%TestStruct %a) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a1 = alloca %TestStruct, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store %TestStruct %a, ptr %a1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca %TestStruct, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%ptr = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %TestStruct, ptr %a, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %a, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load ptr, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load %TestStruct, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @bar(%TestStruct %2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("custom type pointer member assignment via dereference", "[codegen]") {
  TEST_SETUP(R"(
struct TestStruct { i32 a; }
fn void foo() {
var i32 a = 0;
var i32* ptr = &a;
var TestStruct str = .{*ptr};
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestStruct = type { i32 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%ptr = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%str = alloca %TestStruct, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %a, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %TestStruct, ptr %str, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load ptr, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %2, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("member field dereference function parameter", "[codegen]") {
  TEST_SETUP(R"(
struct TestStruct { i32 a; }
fn void bar(i32 a) {}
fn void foo() {
var i32 a = 0;
var i32 *ptr = &a;
var TestStruct str = .{*ptr};
bar(str.a);
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestStruct = type { i32 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @bar(i32 %a) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a1 = alloca i32, align ");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %a, ptr %a1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%ptr = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%str = alloca %TestStruct, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %a, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %TestStruct, ptr %str, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load ptr, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %2, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = getelementptr inbounds %TestStruct, ptr %str, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = load i32, ptr %3, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @bar(i32 %4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("deref struct copy", "[codegen]") {
  TEST_SETUP(R"(
struct TestStruct { i32 a; }
fn i32 bar(TestStruct* a) {
    const TestStruct deref = *a;
    return deref.a;
}
fn  i32 main() {
    var TestStruct a = .{69};
    return bar(&a);
}
    )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestStruct = type { i32 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @bar(ptr %a) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a1 = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%deref = alloca %TestStruct, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %a, ptr %a1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load ptr, ptr %a1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load %TestStruct, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store %TestStruct %1, ptr %deref, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = getelementptr inbounds %TestStruct, ptr %deref, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = load i32, ptr %2, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %3, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %4");
}

TEST_CASE("pointer member access auto dereference", "[codegen]") {
  TEST_SETUP(R"(
struct TestStruct { i32 a; }
fn i32 bar(TestStruct* a) {
    return a.a;
}
fn  i32 main() {
    var TestStruct a = .{69};
    return bar(&a);
}
    )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestStruct = type { i32 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @bar(ptr %a) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a1 = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %a, ptr %a1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load ptr, ptr %a1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %TestStruct, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %2, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %3");
}

TEST_CASE("multi pointer member access auto dereference", "[codegen]") {
  TEST_SETUP(R"(
struct TestStruct { i32 a; }
struct TestStruct2 { TestStruct* t; }
fn i32 bar(TestStruct2* p) {
    return p.t.a;
}
fn  i32 main() {
    var TestStruct first = .{69};
    var TestStruct2 p = .{&first};
    return bar(&p);
}
    )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestStruct2 = type { ptr }");
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestStruct = type { i32 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @bar(ptr %p) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%p1 = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %p, ptr %p1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load ptr, ptr %p1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %TestStruct2, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load ptr, ptr %1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = getelementptr inbounds %TestStruct, ptr %2, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = load i32, ptr %3, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %4, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %5");
}

TEST_CASE("multidepth pointer", "[codegen]") {
  TEST_SETUP(R"(
fn void main() {
  var i32 a = 69;
  var i32* pa = &a;
  var i32** ppa = &pa;
}
    )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @main() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%pa = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%ppa = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 69, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %a, ptr %pa, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %pa, ptr %ppa, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
}

TEST_CASE("multi dereference", "[codegen]") {
  TEST_SETUP(R"(
fn i32 main() {
  var i32 a = 69;
  var i32* pa = &a;
  var i32 copy_a2 = *pa;
  var i32** ppa = &pa;
  var i32*** pppa = &ppa;
  var i32 copy_a = **ppa;
  return ***pppa;
}
    )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @main() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%pa = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%copy_a2 = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%ppa = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%pppa = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%copy_a = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 69, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %a, ptr %pa, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load ptr, ptr %pa, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load i32, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %1, ptr %copy_a2, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %pa, ptr %ppa, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %ppa, ptr %pppa, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load ptr, ptr %ppa, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = load ptr, ptr %2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = load i32, ptr %3, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %4, ptr %copy_a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = load ptr, ptr %pppa, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%6 = load ptr, ptr %5, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%7 = load ptr, ptr %6, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%8 = load i32, ptr %7, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %8, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%9 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %9");
}

TEST_CASE("Explicit casting", "[codegen]") {
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
  var i8 short_ptrcast = (i8)(i32)t2;
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
  auto lines_it = lines.begin() + 20;
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %t, ptr %t2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%cast_sext = sext i32 %2 to i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i64 %cast_sext, ptr %long, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = load i32, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%cast_trunc = trunc i32 %3 to i8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i8 %cast_trunc, ptr %short, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = load ptr, ptr %t2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%cast_pti = ptrtoint ptr %4 to i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "%cast_trunc1 = trunc i32 %cast_pti to i8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i8 %cast_trunc1, ptr %short_ptrcast, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = load i32, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%cast_sext2 = sext i32 %5 to i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "%cast_itp = inttoptr i64 %cast_sext2 to ptr");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %cast_itp, ptr %t3, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%6 = load ptr, ptr %t3, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%cast_pti3 = ptrtoint ptr %6 to i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %cast_pti3, ptr %ptr_addr, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%7 = load i32, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %7, ptr %nop, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%8 = load i32, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%cast_stf = sitofp i32 %8 to double");
  CONTAINS_NEXT_REQUIRE(lines_it, "store double %cast_stf, ptr %f, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%9 = load double, ptr %f, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%cast_fts = fptosi double %9 to i32");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %cast_fts, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%10 = load i32, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %10, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
}

TEST_CASE("Array declarations no init", "[codegen]") {
  TEST_SETUP(R"(
fn i32 main() {
  var i32[2] array;
  var i32[3][2] array2;
  return 0;
}
    )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 4;
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%array = alloca [2 x i32], align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%array2 = alloca [3 x [2 x i32]], align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
}

TEST_CASE("Array declarations with init", "[codegen]") {
  TEST_SETUP(R"(
fn i32 main() {
  var i32 a = 0;
  var i32[3] int_array = [a, 1, 2];
  var i32[3][2] m_int_array = [[a, 1], [2, 3], [3, 4]];
  return 0;
}
    )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 4;
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%int_array = alloca [3 x i32], align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%m_int_array = alloca [3 x [2 x i32]], align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.begin = getelementptr inbounds "
                                  "[3 x i32], ptr %int_array, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load i32, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %0, ptr %arrayinit.begin, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element = getelementptr inbounds "
                                  "i32, ptr %arrayinit.begin, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 1, ptr %arrayinit.element, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element1 = getelementptr inbounds i32, ptr "
                                  "%arrayinit.element, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 2, ptr %arrayinit.element1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.begin2 = getelementptr inbounds [3 x [2 x "
                                  "i32]], ptr %m_int_array, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.begin3 = getelementptr inbounds [2 x i32], "
                                  "ptr %arrayinit.begin2, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load i32, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %1, ptr %arrayinit.begin3, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element4 = getelementptr "
                                  "inbounds i32, ptr %arrayinit.begin3, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 1, ptr %arrayinit.element4, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element5 = getelementptr inbounds [2 x "
                                  "i32], ptr %arrayinit.begin2, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.begin6 = getelementptr inbounds [2 x i32], "
                                  "ptr %arrayinit.element5, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 2, ptr %arrayinit.begin6, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element7 = getelementptr "
                                  "inbounds i32, ptr %arrayinit.begin6, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 3, ptr %arrayinit.element7, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element8 = getelementptr inbounds [2 x "
                                  "i32], ptr %arrayinit.element5, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.begin9 = getelementptr inbounds [2 x i32], "
                                  "ptr %arrayinit.element8, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 3, ptr %arrayinit.begin9, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element10 = getelementptr "
                                  "inbounds i32, ptr %arrayinit.begin9, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 4, ptr %arrayinit.element10, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
}

TEST_CASE("Array element access", "[codegen]") {
  TEST_SETUP(R"(
fn i32 main() {
  var i32 a = 1;
  var i32[3] int_array = [80, 1, 2];
  var i32[3][2] m_int_array = [[a, 1], [2, 3], [3, 4]];
  var i32 ar0 = int_array[0];
  ar0 = m_int_array[a+1][a];
  return ar0;
}
    )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 4;
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%int_array = alloca [3 x i32], align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%m_int_array = alloca [3 x [2 x i32]], align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%ar0 = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 1, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.begin = getelementptr inbounds "
                                  "[3 x i32], ptr %int_array, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 80, ptr %arrayinit.begin, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element = getelementptr inbounds "
                                  "i32, ptr %arrayinit.begin, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 1, ptr %arrayinit.element, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element1 = getelementptr inbounds i32, ptr "
                                  "%arrayinit.element, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 2, ptr %arrayinit.element1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.begin2 = getelementptr inbounds [3 x [2 x "
                                  "i32]], ptr %m_int_array, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.begin3 = getelementptr inbounds [2 x i32], "
                                  "ptr %arrayinit.begin2, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load i32, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %0, ptr %arrayinit.begin3, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element4 = getelementptr "
                                  "inbounds i32, ptr %arrayinit.begin3, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 1, ptr %arrayinit.element4, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element5 = getelementptr inbounds [2 x "
                                  "i32], ptr %arrayinit.begin2, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.begin6 = getelementptr inbounds [2 x i32], "
                                  "ptr %arrayinit.element5, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 2, ptr %arrayinit.begin6, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element7 = getelementptr "
                                  "inbounds i32, ptr %arrayinit.begin6, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 3, ptr %arrayinit.element7, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element8 = getelementptr inbounds [2 x "
                                  "i32], ptr %arrayinit.element5, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.begin9 = getelementptr inbounds [2 x i32], "
                                  "ptr %arrayinit.element8, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 3, ptr %arrayinit.begin9, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element10 = getelementptr "
                                  "inbounds i32, ptr %arrayinit.begin9, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 4, ptr %arrayinit.element10, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayidx = getelementptr inbounds [3 x "
                                  "i32], ptr %int_array, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load i32, ptr %arrayidx, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %1, ptr %ar0, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = add i32 %2, 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%idxprom = sext i32 %3 to i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayidx11 = getelementptr inbounds [3 x [2 x i32]], "
                                  "ptr %m_int_array, i64 0, i64 %idxprom");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = load i32, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%idxprom12 = sext i32 %4 to i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayidx13 = getelementptr inbounds [2 x i32], ptr "
                                  "%arrayidx11, i64 0, i64 %idxprom12");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = load i32, ptr %arrayidx13, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %5, ptr %ar0, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%6 = load i32, ptr %ar0, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %6, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
}

TEST_CASE("Array pointer decay", "[codegen]") {
  TEST_SETUP(R"(
fn i32 foo(i32* arr) { return arr[0]; }
fn i32 bar(i32* arr) { return *(arr + 0); }
fn i32 fizz(i32* arr, i32 a) { return *(arr + a); }
fn i32 baz(i32** arr) { return arr[2][1]; }
fn i32 main() {
  var i32 a = 80;
  var i32[3] int_array = [a, 1, 2];
  var i32* p_int_array = int_array;
  var i32[3][2] m_int_array = [[a, 1], [2, 3], [3, 4]];
  var i32 b = foo(int_array);
  var i32 c = bar(int_array);
  var i32 d = foo(m_int_array[0]);
  var i32 e = fizz(int_array, 0);
  return e;
}
    )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @foo(ptr %arr) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arr1 = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %arr, ptr %arr1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load ptr, ptr %arr1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayidx = getelementptr inbounds i32, ptr %0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load i32, ptr %arrayidx, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %1, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %2");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @bar(ptr %arr) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arr1 = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %arr, ptr %arr1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load ptr, ptr %arr1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayidx = getelementptr inbounds i32, ptr %0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load i32, ptr %arrayidx, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %1, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %2");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @fizz(ptr %arr, i32 %a) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arr1 = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a2 = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %arr, ptr %arr1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %a, ptr %a2, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load ptr, ptr %arr1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load i32, ptr %a2, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%idxprom = sext i32 %1 to i64");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayidx = getelementptr inbounds i32, ptr %0, i64 %idxprom");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %arrayidx, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %2, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %3");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @baz(ptr %arr) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arr1 = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %arr, ptr %arr1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load ptr, ptr %arr1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayidx = getelementptr inbounds ptr, ptr %0, i64 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load ptr, ptr %arrayidx, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayidx2 = getelementptr inbounds i32, ptr %1, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %arrayidx2, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %2, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %3");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @main() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%int_array = alloca [3 x i32], align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%p_int_array = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%m_int_array = alloca [3 x [2 x i32]], align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%b = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%c = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%d = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%e = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 80, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.begin = getelementptr inbounds "
                                  "[3 x i32], ptr %int_array, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load i32, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %0, ptr %arrayinit.begin, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element = getelementptr inbounds "
                                  "i32, ptr %arrayinit.begin, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 1, ptr %arrayinit.element, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element1 = getelementptr inbounds i32, ptr "
                                  "%arrayinit.element, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 2, ptr %arrayinit.element1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arraydecay = getelementptr inbounds [3 x "
                                  "i32], ptr %int_array, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %arraydecay, ptr %p_int_array, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.begin2 = getelementptr inbounds [3 x [2 x "
                                  "i32]], ptr %m_int_array, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.begin3 = getelementptr inbounds [2 x i32], "
                                  "ptr %arrayinit.begin2, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load i32, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %1, ptr %arrayinit.begin3, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element4 = getelementptr "
                                  "inbounds i32, ptr %arrayinit.begin3, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 1, ptr %arrayinit.element4, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element5 = getelementptr inbounds [2 x "
                                  "i32], ptr %arrayinit.begin2, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.begin6 = getelementptr inbounds [2 x i32], "
                                  "ptr %arrayinit.element5, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 2, ptr %arrayinit.begin6, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element7 = getelementptr "
                                  "inbounds i32, ptr %arrayinit.begin6, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 3, ptr %arrayinit.element7, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element8 = getelementptr inbounds [2 x "
                                  "i32], ptr %arrayinit.element5, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.begin9 = getelementptr inbounds [2 x i32], "
                                  "ptr %arrayinit.element8, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 3, ptr %arrayinit.begin9, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arrayinit.element10 = getelementptr "
                                  "inbounds i32, ptr %arrayinit.begin9, i64 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 4, ptr %arrayinit.element10, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arraydecay11 = getelementptr inbounds [3 x "
                                  "i32], ptr %int_array, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = call i32 @foo(ptr %arraydecay11)");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %2, ptr %b, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arraydecay12 = getelementptr inbounds [3 x "
                                  "i32], ptr %int_array, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = call i32 @bar(ptr %arraydecay12)");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %3, ptr %c, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arraydecay13 = getelementptr inbounds [2 x "
                                  "i32], ptr %m_int_array, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = call i32 @foo(ptr %arraydecay13)");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %4, ptr %d, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%arraydecay14 = getelementptr inbounds [3 x "
                                  "i32], ptr %int_array, i64 0, i64 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = call i32 @fizz(ptr %arraydecay14, i32 0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %5, ptr %e, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%6 = load i32, ptr %e, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %6, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
}

TEST_CASE("Global arrays", "[codegen]") {
  TEST_SETUP(R"(
  var i32[3] arr = [0, 1, 2];
  var i32[3][2] m_int_array = [[0, 1], [2, 3], [3, 4]];
    )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "@arr = global [3 x i32] [i32 0, i32 1, i32 2]");
  CONTAINS_NEXT_REQUIRE(lines_it, "@m_int_array = global [3 x [2 x i32]] [[2 x i32] [i32 0, i32 "
                                  "1], [2 x i32] [i32 2, i32 3], [2 x i32] [i32 3, i32 4]]");
}

// @TODO: array literal function parameters

TEST_CASE("String literals", "[codegen]") {
  TEST_SETUP(R"(
fn i32 main() {
    var u8* string = "hello";
    var u8* string2 = "h.e.l.l.o.";
    var u8* string3 = "";
    return string[0];
}
    )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "@.str = private unnamed_addr constant [6 x i8] c\"hello\00\", align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "@.str.1 = private unnamed_addr constant [11 "
                                  "x i8] c\"h.e.l.l.o.\00\", align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "@.str.2 = private unnamed_addr constant [1 "
                                  "x i8] zeroinitializer, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @main() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%string = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%string2 = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%string3 = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr @.str, ptr %string, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr @.str.1, ptr %string2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr @.str.2, ptr %string3, align 8");
}

TEST_CASE("Enums", "[codegen]") {
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
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @main() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%enum_1 = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%enum_2 = alloca i8, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 5, ptr %enum_1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i8 2, ptr %enum_2, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load i32, ptr %enum_1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %0, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
}

TEST_CASE("Extern function", "[codegen]") {
  TEST_SETUP(R"(
extern {
    fn void* allocate(i32 size) alias malloc;
    fn void print(u8* fmt, ...) alias printf;
}
fn i32 main() {
    var i32* a = allocate(4);
    *a = 68;
    var i32** b = &a;
    **b = 69;
    print("hello %d, %d, %d.\n", 1, 2, 3);
    return *a;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 3;
  CONTAINS_NEXT_REQUIRE(lines_it, "declare ptr @malloc(i32 %0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "declare void @printf(ptr %0, ...)");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @main() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%b = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = call ptr @malloc(i32 4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %0, ptr %a, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load ptr, ptr %a, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 68, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %a, ptr %b, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load ptr, ptr %b, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = load ptr, ptr %2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 69, ptr %3, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str, i8 1, i8 2, i8 3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = load ptr, ptr %a, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = load i32, ptr %4, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %5, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
}

TEST_CASE("Bitwise operators", "[codegen]") {
  TEST_SETUP(R"(
fn i32 main() {
    var i32 a = 1 | 2;
    var i32 a1 = a | 3;
    var i32 b = a & 2;
    var i32 c = a ^ b;
    var i32 d = ~b;
    var i32 e = d % 2;
    var i32 f = 1 << 4;
    var i32 f1 = 1 << f;
    var i32 g = 10 >> 3;
    var i32 g1 = 1 >> g;
    return g;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @main() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a1 = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%b = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%c = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%d = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%e = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%f = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%f1 = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%g = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%g1 = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 3, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load i32, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = or i32 %0, 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %1, ptr %a1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = and i32 %2, 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %3, ptr %b, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = load i32, ptr %a, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = load i32, ptr %b, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%6 = xor i32 %4, %5");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %6, ptr %c, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%7 = load i32, ptr %b, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%not = xor i32 %7, -1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %not, ptr %d, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%8 = load i32, ptr %d, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%9 = srem i32 %8, 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %9, ptr %e, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 16, ptr %f, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%10 = load i32, ptr %f, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%11 = shl i32 1, %10");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %11, ptr %f1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 1, ptr %g, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%12 = load i32, ptr %g, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%13 = ashr i32 1, %12");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %13, ptr %g1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%14 = load i32, ptr %g, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %14, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
}

TEST_CASE("address of assignment as a separate instruction", "[codegen]") {
  TEST_SETUP(R"(
fn void main() {
    var i32 i = 0;
    var i32* p_i;
    p_i = &i;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @main() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%i = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%p_i = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %i, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %i, ptr %p_i, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("Function pointers", "[codegen]") {
  TEST_SETUP(R"(
extern {
    fn void print(const u8*, ...) alias printf;
}
fn void foo(i32 a, f32){
    print("%d \n", a);
}
fn i32 main() {
    var fn* void(i32, f32) p_foo = &foo;
    var fn* void(i32 i, f32 f) p_foo1;
    p_foo1 = &foo;
    p_foo(1, 1.0);
    var Type t = .{&foo, &print};
    var Type t1;
    t1.p_foo = &foo;
    t1.p_bar = &print;
    t.p_foo(1, 1.0);
    t.p_bar("hello");
    return 0;
}
struct Type {
    fn* void(i32, f32) p_foo;
    fn* void(const u8*, ...) p_bar;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%Type = type { ptr, ptr }");
  CONTAINS_NEXT_REQUIRE(lines_it, "@.str = private unnamed_addr constant [5 x i8] c\"%d \0A\00\", align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "@.str.1 = private unnamed_addr constant [6 "
                                  "x i8] c\"hello\00\", align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "declare void @printf(ptr %0, ...)");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo(i32 %a, float %__param_foo1) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%a1 = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%__param_foo12 = alloca float, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %a, ptr %a1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float %__param_foo1, ptr %__param_foo12, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load i32, ptr %a1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str, i32 %0)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @main() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%p_foo = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%p_foo1 = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%t = alloca %Type, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%t1 = alloca %Type, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr @foo, ptr %p_foo, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr @foo, ptr %p_foo1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load ptr, ptr %p_foo, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%p_foo2 = call ptr %0(i32 1, float 1.000000e+00)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %Type, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr @foo, ptr %1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = getelementptr inbounds %Type, ptr %t, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr @printf, ptr %2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = getelementptr inbounds %Type, ptr %t1, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr @foo, ptr %3, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = getelementptr inbounds %Type, ptr %t1, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr @printf, ptr %4, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = getelementptr inbounds %Type, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%6 = load ptr, ptr %5, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void %6(i8 1, float 1.000000e+00)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%7 = load ptr, ptr %5, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%8 = getelementptr inbounds %Type, ptr %t, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%9 = load ptr, ptr %8, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void %9(ptr @.str.1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%10 = load ptr, ptr %8, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
}

TEST_CASE("Function pointer chains", "[codegen]") {
  TEST_SETUP(R"(
fn Type* foo(i32, f32) { var Type t; return &t; }
fn i32 main() {
    var Type t = .{&foo};
    t.p_foo(1, 1.0).p_foo(1, 1.0);
}
struct Type {
    fn* Type*(i32, f32) p_foo;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%Type = type { ptr }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define ptr @foo(i32 %__param_foo0, float %__param_foo1) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%__param_foo01 = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%__param_foo12 = alloca float, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%t = alloca %Type, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %__param_foo0, ptr %__param_foo01, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float %__param_foo1, ptr %__param_foo12, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load ptr, ptr %t, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %0, ptr %retval, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load ptr, ptr %retval, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret ptr %1");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @main() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%t = alloca %Type, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %Type, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr @foo, ptr %0, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %Type, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load ptr, ptr %1, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = call ptr %2(i8 1, float 1.000000e+00)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = getelementptr inbounds ptr, ptr %3, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = load ptr, ptr %4, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%6 = call ptr %5(i8 1, float 1.000000e+00)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%7 = load ptr, ptr %6, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%8 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %8");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("defer stmts", "[codegen]") {
  TEST_SETUP(R"(
extern {
    fn void print(const u8*, ...) alias printf;
    fn void* malloc(u64 size);
    fn void free(void* ptr);
}
fn i32 main() {
  var i32* ptr = malloc(sizeof(i32));
  defer {
    free(ptr);
    print("first defer");
  }
  if(ptr == null){ return 1; }
  var i32* ptr2 = malloc(sizeof(i32));
  defer {
    free(ptr2);
    print("second defer");
  }
  if(ptr2 == null){ return 1; }
  var i32* ptr3 = malloc(sizeof(i32));
  var i32* ptr4 = malloc(sizeof(i32));
  defer {
    free(ptr3);
    free(ptr4);
    print("third defer");
  }
  if(ptr3 == null || ptr4 == null) { return 1; }
  return 0;
}
)");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 14;
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @main() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%ptr = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%ptr2 = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%ptr3 = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%ptr4 = alloca ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = call ptr @malloc(i64 4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %0, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load ptr, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = icmp eq ptr %1, null");
  CONTAINS_NEXT_REQUIRE(lines_it, "%to.is_not_null");
  CONTAINS_NEXT_REQUIRE(lines_it, "br i1 %to.is_not_null, label %if.true, label %if.exit");
  CONTAINS_NEXT_REQUIRE(lines_it, "if.true:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = load ptr, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @free(ptr %3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %4");
  CONTAINS_NEXT_REQUIRE(lines_it, "if.exit:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = call ptr @malloc(i64 4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %5, ptr %ptr2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%6 = load ptr, ptr %ptr2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%7 = icmp eq ptr %6, null");
  CONTAINS_NEXT_REQUIRE(lines_it, "%to.is_not_null1 = icmp ne i1 %7, false");
  CONTAINS_NEXT_REQUIRE(lines_it, "br i1 %to.is_not_null1, label %if.true2, label %if.exit3");
  CONTAINS_NEXT_REQUIRE(lines_it, "if.true2:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%8 = load ptr, ptr %ptr2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @free(ptr %8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str.1)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%9 = load ptr, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @free(ptr %9)");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str.2)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%10 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %10");
  CONTAINS_NEXT_REQUIRE(lines_it, "if.exit3:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%11 = call ptr @malloc(i64 4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %11, ptr %ptr3, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%12 = call ptr @malloc(i64 4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %12, ptr %ptr4, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%13 = load ptr, ptr %ptr3, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%14 = icmp eq ptr %13, null");
  CONTAINS_NEXT_REQUIRE(lines_it, "%to.is_not_null4 = icmp ne i1 %14, false");
  CONTAINS_NEXT_REQUIRE(lines_it, "br i1 %to.is_not_null4, label %or.merge, label %or.rhs");
  CONTAINS_NEXT_REQUIRE(lines_it, "or.rhs:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%15 = load ptr, ptr %ptr4, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%16 = icmp eq ptr %15, null");
  CONTAINS_NEXT_REQUIRE(lines_it, "%to.is_not_null5 = icmp ne i1 %16, false");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %or.merge");
  CONTAINS_NEXT_REQUIRE(lines_it, "or.merge:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%17 = phi i1 [ %to.is_not_null5, %or.rhs ], [ true, %if.exit3 ]");
  CONTAINS_NEXT_REQUIRE(lines_it, "%to.is_not_null6 = icmp ne i1 %17, false");
  CONTAINS_NEXT_REQUIRE(lines_it, "br i1 %to.is_not_null6, label %if.true7, label %if.exit8");
  CONTAINS_NEXT_REQUIRE(lines_it, "if.true7:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%18 = load ptr, ptr %ptr3, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @free(ptr %18)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%19 = load ptr, ptr %ptr4, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @free(ptr %19)");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str.3)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%20 = load ptr, ptr %ptr2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @free(ptr %20)");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str.4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%21 = load ptr, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @free(ptr %21)");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str.5)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%22 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %22");
  CONTAINS_NEXT_REQUIRE(lines_it, "if.exit8:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%23 = load ptr, ptr %ptr3, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @free(ptr %23)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%24 = load ptr, ptr %ptr4, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @free(ptr %24)");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str.6)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%25 = load ptr, ptr %ptr2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @free(ptr %25)");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str.7)");
  CONTAINS_NEXT_REQUIRE(lines_it, "%26 = load ptr, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @free(ptr %26)");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str.8)");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%27 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %27");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("generic structs", "[codegen]") {

  TEST_SETUP_MODULE_SINGLE("codegen", R"(
struct<T> Generic1 {
    T* value;
}
struct<T, K> Generic2 {
    Generic1<T> gen_t;
    Generic1<K> gen_k;
    T val;
}
struct Specific {
    Generic2<i32, f32> generic;
}
fn i32 main() {
    var i32 int = 69;
    var f32 float = 69.0;
    var Specific specific = .{.{.gen_t = .{&int}, .gen_k = .{&float}, .val = int}};
    return specific.generic.val;
}
    )");
  REQUIRE(error_stream.str() == "");
  auto lines = break_by_line(output_buffer.str());
  auto lines_it = lines.begin() + 2;
  CONTAINS_NEXT_REQUIRE(lines_it, "%Specific = type { %__Generic2_i32_f32 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "%__Generic2_i32_f32 = type { %__Generic1_i32, %__Generic1_f32, i32 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "%__Generic1_i32 = type { ptr }");
  CONTAINS_NEXT_REQUIRE(lines_it, "%__Generic1_f32 = type { ptr }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @main() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%int = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%float = alloca float, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%specific = alloca %Specific, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 69, ptr %int, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 6.900000e+01, ptr %float, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = getelementptr inbounds %Specific, ptr %specific, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = getelementptr inbounds %__Generic2_i32_f32, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = getelementptr inbounds %__Generic1_i32, ptr %1, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %int, ptr %2, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = getelementptr inbounds %__Generic2_i32_f32, ptr %0, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = getelementptr inbounds %__Generic1_f32, ptr %3, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %float, ptr %4, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%5 = getelementptr inbounds %__Generic2_i32_f32, ptr %0, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "%6 = load i32, ptr %int, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %6, ptr %5, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%7 = getelementptr inbounds %Specific, ptr %specific, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%8 = getelementptr inbounds %__Generic2_i32_f32, ptr %7, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "%9 = load i32, ptr %8, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %9, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
  CONTAINS_NEXT_REQUIRE(lines_it, "return:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%10 = load i32, ptr %retval, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %10");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("switch stmt", "[codegen]") {
  SECTION("some empty, only default") {
    TEST_SETUP_MODULE_SINGLE("test", R"(
enum TestEnum {
    Zero,
    One,
    Two
}
fn i32 main() {
    var TestEnum test_enum;
    var i32 int = -1;
    switch(test_enum) {
        case TestEnum::Zero:
        case TestEnum::One:
        default: {
            int = (i32)test_enum;
        }
    }
    return int;
}
)");
    REQUIRE(error_stream.str() == "");
    auto lines = break_by_line(output_buffer.str());
    auto lines_it = lines.begin() + 2;
    CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @main() {");
    CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "%test_enum = alloca i32, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "%int = alloca i32, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "store i32 -1, ptr %int, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load i32, ptr %test_enum, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "switch i32 %0, label %sw.default [");
    CONTAINS_NEXT_REQUIRE(lines_it, "i32 0, label %sw.bb");
    CONTAINS_NEXT_REQUIRE(lines_it, "i32 1, label %sw.bb");
    CONTAINS_NEXT_REQUIRE(lines_it, "]");
    CONTAINS_NEXT_REQUIRE(lines_it, "sw.default:");
    CONTAINS_NEXT_REQUIRE(lines_it, "br label %sw.bb");
    CONTAINS_NEXT_REQUIRE(lines_it, "sw.bb:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load i32, ptr %test_enum, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %1, ptr %int, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "br label %sw.epilog");
    CONTAINS_NEXT_REQUIRE(lines_it, "sw.epilog:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %int, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %2, ptr %retval, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
    CONTAINS_NEXT_REQUIRE(lines_it, "return:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%3 = load i32, ptr %retval, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %3");
  }
}

TEST_CASE("implicit nullptr comparisons", "[codegen]") {
  SECTION("is not null") {
    TEST_SETUP_MODULE_SINGLE("test", R"(
fn i32 main() {
    var i32* i = null;
    if(i) {
        return 1;
    }
    return 0;
}
)");
    REQUIRE(error_stream.str() == "");
    auto lines = break_by_line(output_buffer.str());
    auto lines_it = lines.begin() + 2;
    CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @main() {");
    CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "%i = alloca ptr, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "store ptr null, ptr %i, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load ptr, ptr %i, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%to.is_not_null = icmp ne ptr %0, null");
    CONTAINS_NEXT_REQUIRE(lines_it, "br i1 %to.is_not_null, label %if.true, label %if.exit");
    CONTAINS_NEXT_REQUIRE(lines_it, "if.true:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load i32, ptr %retval, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %1");
    CONTAINS_NEXT_REQUIRE(lines_it, "if.exit:");
    CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %retval, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
    CONTAINS_NEXT_REQUIRE(lines_it, "return:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %retval, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %2");
  }
  SECTION("is null") {
    TEST_SETUP_MODULE_SINGLE("test", R"(
fn i32 main() {
    var i32* i = null;
    if(!i) {
        return 1;
    }
    return 0;
}
)");
    REQUIRE(error_stream.str() == "");
    auto lines = break_by_line(output_buffer.str());
    auto lines_it = lines.begin() + 2;
    CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @main() {");
    CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "%i = alloca ptr, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "store ptr null, ptr %i, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load ptr, ptr %i, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%to.is_null = icmp eq ptr %0, null");
    CONTAINS_NEXT_REQUIRE(lines_it, "br i1 %to.is_null, label %if.true, label %if.exit");
    CONTAINS_NEXT_REQUIRE(lines_it, "if.true:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load i32, ptr %retval, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %1");
    CONTAINS_NEXT_REQUIRE(lines_it, "if.exit:");
    CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %retval, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
    CONTAINS_NEXT_REQUIRE(lines_it, "return:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %retval, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %2");
  }
}

TEST_CASE("empty file segfault", "[codegen]") {
  SECTION("empty file") {
    TEST_SETUP_MODULE_SINGLE("test", R"(
)");
    REQUIRE(error_stream.str() == "");
    REQUIRE(output_string == "");
  }
  SECTION("commented out file") {
    TEST_SETUP_MODULE_SINGLE("test", R"(
//fn i32 main() {
//    var i32* i = null;
//    if(!i) {
//        return 1;
//    }
//    return 0;
//}
)");
    REQUIRE(error_stream.str() == "");
    REQUIRE(output_string == "");
  }
}

TEST_CASE("defer statements after early return", "[codegen]") {
  SECTION("basic defers") {
    TEST_SETUP_MODULE_SINGLE("test", R"(
extern {
    export struct FILE {
        i8*   _ptr;
        i32 _cnt;
        i8*   _base;
        i32 _flag;
        i32 _file;
        i32 _charbuf;
        i32 _bufsiz;
        i8*   _tmpfname;
    }
    export fn FILE* fopen(const u8* filename, const u8* mode);
    export fn i32 fclose(FILE* file);
    export fn void printf(const u8*, ...);
    export fn i32 fgetc(FILE* stream);
    export fn i32 fputc(i32 ch, FILE* stream);
}
fn void write() {
    var FILE* file = fopen("tmp.txt", "w");
    const bool opened = file != null;
    printf("opened: %d\n", opened);
    if(!opened) {
        printf("unknown file\n");
        return;
    }
    defer fclose(file);
    fputc(8, file);
}
fn i32 main() {
    write();
    var FILE* file = fopen("tmp.txt", "r");
    if(file == null) {
        printf("unknown file\n");
        return 1;
    }
    defer fclose(file);
    var i8 char = (i8)fgetc(file);
    printf("%d\n", char);
    return 0;
}
)");
    REQUIRE(error_stream.str() == "");
    auto lines = break_by_line(output_buffer.str());
    auto lines_it = lines.begin() + 15;
    CONTAINS_NEXT_REQUIRE(lines_it, "define void @write() {");
    CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
    CONTAINS_NEXT_REQUIRE(lines_it, "file = alloca ptr, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%opened = alloca i1, align 1");
    CONTAINS_NEXT_REQUIRE(lines_it, "%0 = call ptr @fopen(ptr @.str, ptr @.str.1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %0, ptr %file, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load ptr, ptr %file, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%2 = icmp ne ptr %1, null");
    CONTAINS_NEXT_REQUIRE(lines_it, "store i1 %2, ptr %opened, align 1");
    CONTAINS_NEXT_REQUIRE(lines_it, "%3 = load i1, ptr %opened, align 1");
    CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str.2, i1 %3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "%4 = load i1, ptr %opened, align 1");
    CONTAINS_NEXT_REQUIRE(lines_it, "%5 = xor i1 %4, true");
    CONTAINS_NEXT_REQUIRE(lines_it, "br i1 %5, label %if.true, label %if.exit");
    CONTAINS_NEXT_REQUIRE(lines_it, "if.true:");
    CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str.3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
    CONTAINS_NEXT_REQUIRE(lines_it, "if.exit:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%6 = load ptr, ptr %file, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%7 = call i32 @fputc(i32 8, ptr %6)");
    CONTAINS_NEXT_REQUIRE(lines_it, "%8 = load ptr, ptr %file, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%9 = call i32 @fclose(ptr %8)");
    CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
    CONTAINS_NEXT_REQUIRE(lines_it, "}");
    CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @main() {");
    CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "%file = alloca ptr, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%char = alloca i8, align 1");
    CONTAINS_NEXT_REQUIRE(lines_it, "call void @write()");
    CONTAINS_NEXT_REQUIRE(lines_it, "%0 = call ptr @fopen(ptr @.str.4, ptr @.str.5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %0, ptr %file, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load ptr, ptr %file, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%2 = icmp eq ptr %1, null");
    CONTAINS_NEXT_REQUIRE(lines_it, "%to.is_not_null = icmp ne i1 %2, false");
    CONTAINS_NEXT_REQUIRE(lines_it, "br i1 %to.is_not_null, label %if.true, label %if.exit");
    CONTAINS_NEXT_REQUIRE(lines_it, "if.true:");
    CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str.6)");
    CONTAINS_NEXT_REQUIRE(lines_it, "%3 = load i32, ptr %retval, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %3");
    CONTAINS_NEXT_REQUIRE(lines_it, "if.exit:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%4 = load ptr, ptr %file, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%5 = call i32 @fgetc(ptr %4)");
    CONTAINS_NEXT_REQUIRE(lines_it, "%cast_trunc = trunc i32 %5 to i8");
    CONTAINS_NEXT_REQUIRE(lines_it, "store i8 %cast_trunc, ptr %char, align 1");
    CONTAINS_NEXT_REQUIRE(lines_it, "%6 = load i8, ptr %char, align 1");
    CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str.7, i8 %6)");
    CONTAINS_NEXT_REQUIRE(lines_it, "%7 = load ptr, ptr %file, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%8 = call i32 @fclose(ptr %7)");
    CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %retval, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "br label %return");
    CONTAINS_NEXT_REQUIRE(lines_it, "return:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%9 = load i32, ptr %retval, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %9");
  }
  SECTION("in scope blocks") {
    TEST_SETUP_MODULE_SINGLE("test", R"(
extern {
    export struct FILE {
        i8*   _ptr;
        i32 _cnt;
        i8*   _base;
        i32 _flag;
        i32 _file;
        i32 _charbuf;
        i32 _bufsiz;
        i8*   _tmpfname;
    }
    export fn FILE* fopen(const u8* filename, const u8* mode);
    export fn i32 fclose(FILE* file);
    export fn void printf(const u8*, ...);
    export fn i32 fgetc(FILE* stream);
    export fn i32 fputc(i32 ch, FILE* stream);
}
fn i32 main() {
    {
        var FILE* file = fopen("tmp.txt", "w");
        const bool opened = file != null;
        printf("opened: %d\n", opened);
        if(!opened) {
            printf("unknown file\n");
            return 1;
        }
        defer fclose(file);
        fputc(8, file);
    }
    {
        var FILE* file = fopen("tmp.txt", "r");
        if(file == null) {
            printf("unknown file\n");
            return 1;
        }
        defer fclose(file);
        var i8 char = (i8)fgetc(file);
        printf("%d\n", char);
        return 0;
    }
}
)");
    REQUIRE(error_stream.str() == "");
    auto lines = break_by_line(output_buffer.str());
    auto lines_it = lines.begin() + 15;
    CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @main() {");
    CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "%file = alloca ptr, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%opened = alloca i1, align 1");
    CONTAINS_NEXT_REQUIRE(lines_it, "%file2 = alloca ptr, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%char = alloca i8, align 1");
    CONTAINS_NEXT_REQUIRE(lines_it, "br label %scope_block");
    CONTAINS_NEXT_REQUIRE(lines_it, "scope_block:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%0 = call ptr @fopen(ptr @.str, ptr @.str.1)");
    CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %0, ptr %file, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load ptr, ptr %file, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%2 = icmp ne ptr %1, null");
    CONTAINS_NEXT_REQUIRE(lines_it, "store i1 %2, ptr %opened, align 1");
    CONTAINS_NEXT_REQUIRE(lines_it, "%3 = load i1, ptr %opened, align 1");
    CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str.2, i1 %3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "%4 = load i1, ptr %opened, align 1");
    CONTAINS_NEXT_REQUIRE(lines_it, "%5 = xor i1 %4, true");
    CONTAINS_NEXT_REQUIRE(lines_it, "br i1 %5, label %if.true, label %if.exit");
    CONTAINS_NEXT_REQUIRE(lines_it, "if.true:");
    CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str.3)");
    CONTAINS_NEXT_REQUIRE(lines_it, "%6 = load i32, ptr %retval, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %6");
    CONTAINS_NEXT_REQUIRE(lines_it, "if.exit:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%7 = load ptr, ptr %file, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%8 = call i32 @fputc(i32 8, ptr %7)");
    CONTAINS_NEXT_REQUIRE(lines_it, "%9 = load ptr, ptr %file, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%10 = call i32 @fclose(ptr %9)");
    CONTAINS_NEXT_REQUIRE(lines_it, "br label %scope_block1");
    CONTAINS_NEXT_REQUIRE(lines_it, "scope_block1:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%11 = call ptr @fopen(ptr @.str.4, ptr @.str.5)");
    CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %11, ptr %file2, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%12 = load ptr, ptr %file2, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%13 = icmp eq ptr %12, null");
    CONTAINS_NEXT_REQUIRE(lines_it, "%to.is_not_null = icmp ne i1 %13, false");
    CONTAINS_NEXT_REQUIRE(lines_it, "br i1 %to.is_not_null, label %if.true3, label %if.exit4");
    CONTAINS_NEXT_REQUIRE(lines_it, "if.true3:");
    CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str.6)");
    CONTAINS_NEXT_REQUIRE(lines_it, "%14 = load i32, ptr %retval, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %14");
    CONTAINS_NEXT_REQUIRE(lines_it, "if.exit4:");
    CONTAINS_NEXT_REQUIRE(lines_it, "%15 = load ptr, ptr %file2, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%16 = call i32 @fgetc(ptr %15)");
    CONTAINS_NEXT_REQUIRE(lines_it, "%cast_trunc = trunc i32 %16 to i8");
    CONTAINS_NEXT_REQUIRE(lines_it, "store i8 %cast_trunc, ptr %char, align 1");
    CONTAINS_NEXT_REQUIRE(lines_it, "%17 = load i8, ptr %char, align 1");
    CONTAINS_NEXT_REQUIRE(lines_it, "call void (ptr, ...) @printf(ptr @.str.7, i8 %17)");
    CONTAINS_NEXT_REQUIRE(lines_it, "%18 = load ptr, ptr %file2, align 8");
    CONTAINS_NEXT_REQUIRE(lines_it, "%19 = call i32 @fclose(ptr %18)");
    CONTAINS_NEXT_REQUIRE(lines_it, "%20 = load i32, ptr %retval, align 4");
    CONTAINS_NEXT_REQUIRE(lines_it, "ret i32 %20");
  }
}
