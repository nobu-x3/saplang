#include "catch2/catch_test_macros.hpp"
#include "test_utils.h"

#define TEST_SETUP(file_contents)                                              \
  saplang::clear_error_stream();                                               \
  std::stringstream buffer{file_contents};                                     \
  std::string output_string;                                                   \
  llvm::raw_string_ostream output_buffer{output_string};                       \
  saplang::SourceFile src_file{"codegen_test", buffer.str()};                  \
  saplang::Lexer lexer{src_file};                                              \
  saplang::Parser parser(&lexer);                                              \
  auto parse_result = parser.parse_source_file();                              \
  saplang::Sema sema{std::move(parse_result.declarations)};                    \
  auto resolved_ast = sema.resolve_ast();                                      \
  saplang::Codegen codegen{std::move(resolved_ast), "codegen_tests"};          \
  auto generated_code = codegen.generate_ir();                                 \
  generated_code->print(output_buffer, nullptr, true, true);                   \
  const auto &error_stream = saplang::get_error_stream();

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
    REQUIRE(remove_whitespace(output_string) ==
            remove_whitespace(R"(; ModuleID = '<tu>'
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
    REQUIRE(remove_whitespace(output_string) ==
            remove_whitespace(R"(; ModuleID = '<tu>'
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
    REQUIRE(remove_whitespace(output_string) ==
            remove_whitespace(R"(; ModuleID = '<tu>'
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
    REQUIRE(remove_whitespace(output_string) ==
            remove_whitespace(R"(; ModuleID = '<tu>'
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
    REQUIRE(remove_whitespace(output_string) ==
            remove_whitespace(R"(; ModuleID = '<tu>'
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
  NEXT_REQUIRE(lines_it, lines_it->find("%x1 = alloca i32, align 4") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("store i32 %x, ptr %x1, align 4") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%0 = load i32, ptr %x1, align 4") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("%1 = icmp eq i32 %0, 1") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%to.bool = icmp ne i1 %1, false") !=
                             std::string::npos);
  NEXT_REQUIRE(
      lines_it,
      lines_it->find("br i1 %to.bool, label %or.merge, label %or.rhs") !=
          std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("or.rhs") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %entry") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%2 = load i32, ptr %x1, align 4") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("%3 = icmp eq i32 %2, 2") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%to.bool2 = icmp ne i1 %3, false") !=
                             std::string::npos);
  NEXT_REQUIRE(
      lines_it,
      lines_it->find("br i1 %to.bool2, label %and.rhs, label %and.merge") !=
          std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("or.merge") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %and.merge, %entry") != std::string::npos);
  NEXT_REQUIRE(
      lines_it,
      lines_it->find("%4 = phi i1 [ %7, %and.merge ], [ true, %entry ]") !=
          std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("br i1 %4, label %if.true, label %if.exit") !=
                   std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("and.rhs") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %or.rhs") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%5 = load i32, ptr %x1, align 4") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("%6 = icmp sgt i32 %5, 3") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%to.bool3 = icmp ne i1 %6, false") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("br label %and.merge") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("and.merge") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %and.rhs, %or.rhs") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find(
                   "%7 = phi i1 [ %to.bool3, %and.rhs ], [ false, %or.rhs ]") !=
                   std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("br label %or.merge") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("if.true") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %or.merge") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("br label %if.exit") != std::string::npos);
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
  NEXT_REQUIRE(lines_it, lines_it->find("%val1 = alloca i1, align 1") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("store i1 %val, ptr %val1, align 1") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("br label %while.cond") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("while.cond:") != std::string::npos);
  REQUIRE(lines_it->find("; preds = <null operand!>, %entry") !=
          std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%0 = load i1, ptr %val1, align 1") !=
                             std::string::npos);
  NEXT_REQUIRE(
      lines_it,
      lines_it->find("br i1 %0, label %while.body, label %while.exit") !=
          std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("while.body:") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %while.cond") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("br label %return") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("while.exit:") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %while.cond") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("br label %return") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("return:") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %while.exit, %while.body") !=
          std::string::npos);
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
  NEXT_REQUIRE(lines_it, lines_it->find("%val1 = alloca i32, align 4") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("store i32 %val, ptr %val1, align 4") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("br label %while.cond") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("while.cond:") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %while.body, %entry") != std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("%0 = load i32, ptr %val1, align 4") !=
                             std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("%1 = icmp ugt i32 %0, 3") != std::string::npos);
  NEXT_REQUIRE(
      lines_it,
      lines_it->find(" br i1 %1, label %while.body, label %while.exit") !=
          std::string::npos);
  NEXT_REQUIRE(lines_it, lines_it->find("while.body:") != std::string::npos);
  REQUIRE(lines_it->find("; preds = %while.cond") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("call void @bar()") != std::string::npos);
  NEXT_REQUIRE(lines_it,
               lines_it->find("br label %while.cond") != std::string::npos);
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
  REQUIRE(lines_it->find("; preds = %for.counter_op, %for.counter_decl") !=
          std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "%0 = load i32, ptr %i, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = icmp ult i32 %0, 10");
  CONTAINS_NEXT_REQUIRE(lines_it, "%to.bool = icmp ne i1 %1, false");
  CONTAINS_NEXT_REQUIRE(lines_it,
                        "br i1 %to.bool, label %for.body, label %for.exit");
  CONTAINS_NEXT_REQUIRE(lines_it, "for.body:");
  REQUIRE(lines_it->find("; preds = %for.condition") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "br label %for.counter_op");
  CONTAINS_NEXT_REQUIRE(lines_it, "for.counter_op:");
  REQUIRE(lines_it->find("; preds = %for.body") != std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %i, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%3 = add i32 %2, i8 1");
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
  REQUIRE(lines_it->find("%TestType = type { i32, float, i8, i32 }") !=
          std::string::npos);
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
  REQUIRE(lines_it->find("%TestType = type { i32, float, i1, i32 }") !=
          std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%t = alloca %TestType, align 8");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%0 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 -1, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%1 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 2.000000e+00, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%2 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %2, align 1");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%3 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 3");
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
  REQUIRE(lines_it->find("%TestType = type { i32, float, i1, i32 }") !=
          std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%t = alloca %TestType, align 8");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%0 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 -1, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%1 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 2.000000e+00, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%2 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %2, align 1");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%3 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 250, ptr %3, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%4 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 0");
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
  REQUIRE(lines_it->find("%TestType = type { i32, float, i1, i32 }") !=
          std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%t = alloca %TestType, align 8");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%0 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 -1, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%1 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 2.000000e+00, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%2 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %2, align 1");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%3 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 250, ptr %3, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%4 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i8 5, ptr %4, align 1");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%5 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i8 15, ptr %5, align 1");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%6 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 3");
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
  REQUIRE(lines_it->find("%TestType = type { i32, float, i1, i32 }") !=
          std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @foo(%TestType %variable) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%variable1 = alloca %TestType, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it,
                        "store %TestType %variable, ptr %variable1, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%0 = getelementptr inbounds %TestType, ptr %variable1, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i8 15, ptr %0, align 1");
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%1 = getelementptr inbounds %TestType, ptr %variable1, i32 0, i32 3");
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
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%1 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 -1, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%2 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 2.000000e+00, ptr %2, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%3 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %3, align 1");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%4 = getelementptr inbounds %TestType, ptr %t, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 250, ptr %4, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%5 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 0, ptr %5, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%6 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 3.000000e+00, ptr %6, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%7 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 false, ptr %7, align 1");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%8 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 3");
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
  REQUIRE(lines_it->find("%TestType2 = type { %TestType }") !=
          std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType = type { i32, float, i1, i32 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%t = alloca %TestType2, align 8");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%0 = getelementptr inbounds %TestType2, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%1 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 -1, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%2 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 2.000000e+00, ptr %2, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%3 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %3, align 1");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%4 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 3");
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
  REQUIRE(lines_it->find("%TestType = type { i32, float, i1, i32 }") !=
          std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType2 = type { %TestType }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @bar(%TestType %variable) {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%variable1 = alloca %TestType, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it,
                        "store %TestType %variable, ptr %variable1, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%0 = getelementptr inbounds %TestType, ptr %variable1, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i8 15, ptr %0, align 1");
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%1 = getelementptr inbounds %TestType, ptr %variable1, i32 0, i32 3");
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
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%0 = getelementptr inbounds %TestType2, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%1 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 -1, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%2 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 2.000000e+00, ptr %2, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%3 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %3, align 1");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%4 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 250, ptr %4, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%5 = getelementptr inbounds %TestType2, ptr %t, i32 0, i32 0");
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
  REQUIRE(lines_it->find("%TestType2 = type { %TestType }") !=
          std::string::npos);
  CONTAINS_NEXT_REQUIRE(lines_it, "%TestType = type { i32, float, i1, i32 }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define i32 @main() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "%retval = alloca i32, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "%t = alloca %TestType2, align 8");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%0 = getelementptr inbounds %TestType2, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%1 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 -1, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%2 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 2.000000e+00, ptr %2, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%3 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %3, align 1");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%4 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 250, ptr %4, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%5 = getelementptr inbounds %TestType2, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%6 = getelementptr inbounds %TestType, ptr %5, i32 0, i32 3");
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
  REQUIRE(lines_it->find("%TestType2 = type { %TestType }") !=
          std::string::npos);
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
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%0 = getelementptr inbounds %TestType2, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%1 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 -1, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%2 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 2.000000e+00, ptr %2, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%3 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %3, align 1");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%4 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 3");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 250, ptr %4, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%5 = getelementptr inbounds %TestType2, ptr %t, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%6 = getelementptr inbounds %TestType, ptr %5, i32 0, i32 3");
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
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%1 = getelementptr inbounds %TestType2, ptr %test1, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%2 = getelementptr inbounds %TestType, ptr %1, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 15, ptr %2, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%3 = getelementptr inbounds %TestType, ptr %1, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 1.600000e+01, ptr %3, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%4 = getelementptr inbounds %TestType, ptr %1, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %4, align 1");
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%5 = getelementptr inbounds %TestType2, ptr %test1, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%6 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 17, ptr %6, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%7 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 1.800000e+01, ptr %7, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%8 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 false, ptr %8, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @llvm.memcpy.p0.p0.i64(ptr align "
                                  "8 %5, ptr align 8 %0, i64 12, i1 false)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
}

TEST_CASE("nested struct type var reassignment from another struct",
          "[codegen]") {
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
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%0 = getelementptr inbounds %TestType2, ptr %test2, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%1 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 17, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%2 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 1.800000e+01, ptr %2, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%3 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 false, ptr %3, align 1");
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%4 = getelementptr inbounds %TestType2, ptr %test1, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%5 = getelementptr inbounds %TestType, ptr %4, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 15, ptr %5, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%6 = getelementptr inbounds %TestType, ptr %4, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 1.600000e+01, ptr %6, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%7 = getelementptr inbounds %TestType, ptr %4, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %7, align 1");
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%8 = getelementptr inbounds %TestType2, ptr %test1, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%9 = getelementptr inbounds %TestType2, ptr %test2, i32 0, i32 0");
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
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "@test1 = global %TestType { i32 15, float 1.600000e+01, i1 true }");
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "@test2 = constant %TestType { i32 17, float 1.800000e+01, i1 false }");
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
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "@test1 = global %TestType { i32 15, float 1.600000e+01, i1 true }");
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "@test2 = constant %TestType { i32 17, float 1.800000e+01, i1 false }");
  CONTAINS_NEXT_REQUIRE(lines_it, "define void @foo() {");
  CONTAINS_NEXT_REQUIRE(lines_it, "entry:");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i8 16, ptr @test1, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("global struct type var access from function last element",
          "[codegen]") {
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
  CONTAINS_NEXT_REQUIRE(lines_it,
                        "store i8 16, ptr getelementptr inbounds (%TestType, "
                        "ptr @test1, i32 0, i32 3), align 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

TEST_CASE("global nested struct type var reassignment from function",
          "[codegen]") {
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
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%1 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 15, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%2 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 1");
  CONTAINS_NEXT_REQUIRE(lines_it, "store float 1.600000e+01, ptr %2, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it, "%3 = getelementptr inbounds %TestType, ptr %0, i32 0, i32 2");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i1 true, ptr %3, align 1");
  CONTAINS_NEXT_REQUIRE(lines_it,
                        "call void @llvm.memcpy.p0.p0.i64(ptr align 8 @test1, "
                        "ptr align 8 %0, i64 12, i1 false)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
}

TEST_CASE(
    "global nested struct type var reassignment from another var from function",
    "[codegen]") {
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

TEST_CASE("builtin type address of operator storing to parameter",
          "[codegen]") {
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
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%0 = getelementptr inbounds %TestStruct, ptr %a, i32 0, i32 0");
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
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%0 = getelementptr inbounds %TestStruct, ptr %a, i32 0, i32 0");
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
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%0 = getelementptr inbounds %TestStruct, ptr %str, i32 0, i32 0");
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
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%0 = getelementptr inbounds %TestStruct, ptr %str, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "store ptr %a, ptr %0, align 8");
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%1 = getelementptr inbounds %TestStruct, ptr %str, i32 0, i32 0");
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

TEST_CASE("builtin type dereference operator storing to parameter",
          "[codegen]") {
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
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%0 = getelementptr inbounds %TestStruct, ptr %a, i32 0, i32 0");
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
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%0 = getelementptr inbounds %TestStruct, ptr %a, i32 0, i32 0");
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
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%0 = getelementptr inbounds %TestStruct, ptr %str, i32 0, i32 0");
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
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%0 = getelementptr inbounds %TestStruct, ptr %str, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%1 = load ptr, ptr %ptr, align 8");
  CONTAINS_NEXT_REQUIRE(lines_it, "%2 = load i32, ptr %1, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "store i32 %2, ptr %0, align 4");
  CONTAINS_NEXT_REQUIRE(
      lines_it,
      "%3 = getelementptr inbounds %TestStruct, ptr %str, i32 0, i32 0");
  CONTAINS_NEXT_REQUIRE(lines_it, "%4 = load i32, ptr %3, align 4");
  CONTAINS_NEXT_REQUIRE(lines_it, "call void @bar(i32 %4)");
  CONTAINS_NEXT_REQUIRE(lines_it, "ret void");
  CONTAINS_NEXT_REQUIRE(lines_it, "}");
}

// @TODO: multidepth pointer
// @TODO: member field inner access == dereference
