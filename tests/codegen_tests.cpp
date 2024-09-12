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
  saplang::Sema sema{std::move(parse_result.functions)};                       \
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