#include "parser_tests.h"
#include "sema_tests.h"
#include "threadpool_tests.h"
#include <unity.h>

void setUp(void) {}

void tearDown(void) {}

int main(void) {
	UNITY_BEGIN();
	RUN_TEST(test_VariableDeclaration);
	RUN_TEST(test_ArithmeticExpression);
	RUN_TEST(test_StructDeclaration);
	RUN_TEST(test_FunctionDeclaration);
	RUN_TEST(test_CombinedDeclarations);
	RUN_TEST(test_UnaryExpression_Exclamation);
	RUN_TEST(test_UnaryExpression_Dereference);
	RUN_TEST(test_UnaryExpression_AddressOf);
	RUN_TEST(test_SinglePointer);
	RUN_TEST(test_MultiPointer);
	RUN_TEST(test_CustomTypePointer);
	RUN_TEST(test_ArrayLiterals);
	RUN_TEST(test_ArrayAccessAssignment);
	RUN_TEST(test_FunctionCallsWithLiteralArguments);
	RUN_TEST(test_FunctionCallsWithExprArguments);
	RUN_TEST(test_FunctionCallsNoArguments);
	RUN_TEST(test_MemberAccessSingle_Value);
	RUN_TEST(test_MemberAccessSingle_Pointer);
	RUN_TEST(test_MemberAccessMulti_Pointer);
	RUN_TEST(test_StructLiteral_FullyUnnamed);
	RUN_TEST(test_StructLiteral_FullyNamed);
	RUN_TEST(test_StructLiteral_Mixed);
	RUN_TEST(test_StructLiteral_Nested);
	RUN_TEST(test_EnumDecl_WithReference);
	RUN_TEST(test_EnumDecl_VariableDeclaration);
	RUN_TEST(test_ExternBlocks_FullIO);
	RUN_TEST(test_ExportedDecls);
	RUN_TEST(test_Imports);
	RUN_TEST(test_Namespaces_Functions);
	RUN_TEST(test_IfStatements_NoElse);
	RUN_TEST(test_IfStatements_WithElse);
	RUN_TEST(test_IfStatements_ElseIf);
	RUN_TEST(test_ForLoop_Full);
	RUN_TEST(test_ForLoop_Empty);
	RUN_TEST(test_WhileLoop);
	RUN_TEST(test_DeferStmts);
	RUN_TEST(test_FnPtr_BasicDeclNoParam);
	RUN_TEST(test_FnPtr_BasicDeclWithParams);
	RUN_TEST(test_FnPtr_BasicCall);
	RUN_TEST(test_FnPtr_BasicAssignment);
	RUN_TEST(test_FnPtr_StructFieldAssignment);
	RUN_TEST(test_Binops_AndOrSelf);
	RUN_TEST(test_StringLiteral);
	RUN_TEST(test_CharLiteral);
	RUN_TEST(test_BinaryLiteral);
	RUN_TEST(test_HexadecimalLiteral);
	RUN_TEST(test_ContinueBreak);

	RUN_TEST(test_TypePrinting);
	RUN_TEST(test_UndeclaredVariable);
	RUN_TEST(test_ConstNoInit);
	RUN_TEST(test_AssignmentToConst);
	RUN_TEST(test_AssignmentToRValue);
	RUN_TEST(test_VarialbeRedeclaration);
	RUN_TEST(test_FnRedeclaration);
	RUN_TEST(test_StructRedeclaration);
	RUN_TEST(test_EnumRedeclaration);
	RUN_TEST(test_StructFieldRedeclaration);
	RUN_TEST(test_EnumMemberRedeclaration);
	RUN_TEST(test_ParamRedeclaration);

	RUN_TEST(test_PrintfTest);
	return UNITY_END();
}
