#include "parser_tests.h"
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

	RUN_TEST(test_PrintfTest);
	return UNITY_END();
}
