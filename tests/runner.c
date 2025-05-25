#include "codegen_tests.h"
#include "hashmap_tests.h"
#include "parser_tests.h"
#include "sema_tests.h"
#include "threadpool_tests.h"
#include <unity.h>

void setUp(void) {}

void tearDown(void) {}

int main(void) {
	UNITY_BEGIN();

	RUN_TEST(test_hashmap_create_and_destroy);
	RUN_TEST(test_hashmap_put_and_get);
	RUN_TEST(test_hashmap_update_existing_key);
	RUN_TEST(test_hashmap_remove_and_contains);
	RUN_TEST(test_hashmap_remove_missing_key);
	RUN_TEST(test_hashmap_rehash);

	RUN_TEST(test_PrintfTest);

	RUN_TEST(test_VariableDeclaration);
	RUN_TEST(test_ArithmeticExpression);
	RUN_TEST(test_StructDeclaration);
	RUN_TEST(test_UnionDecl);
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
	RUN_TEST(test_ExplicitCast);

	RUN_TEST(test_TypePrinting_sema);
	RUN_TEST(test_UndeclaredVariable_sema);
	RUN_TEST(test_ConstNoInit_sema);
	RUN_TEST(test_AssignmentToConst_sema);
	RUN_TEST(test_AssignmentToRValue_sema);
	RUN_TEST(test_VarialbeRedeclaration_sema);
	RUN_TEST(test_FnRedeclaration_sema);
	RUN_TEST(test_StructRedeclaration_sema);
	RUN_TEST(test_StructLiteralInitMoreInitsThanFields_sema);
	RUN_TEST(test_StructLiteralInitUnknownField_sema);
	RUN_TEST(test_EnumRedeclaration_sema);
	RUN_TEST(test_StructFieldRedeclaration_sema);
	RUN_TEST(test_EnumMemberRedeclaration_sema);
	RUN_TEST(test_ParamRedeclaration_sema);
	RUN_TEST(test_UndeclaredFunction_sema);
	RUN_TEST(test_ArgCountMismatch_sema);
	RUN_TEST(test_ArgTypeMismatch_sema);
	RUN_TEST(test_ParameterNameConflict_sema);
	RUN_TEST(test_FuncCallInitWrongType_sema);
	RUN_TEST(test_FuncCallAssignmentWrongType_sema);
	RUN_TEST(test_ExplicitCastCorrectTypes_ValueToPointer_sema);
	RUN_TEST(test_ExplicitCastCorrectTypes_PointerToValue_sema);
	RUN_TEST(test_ExplicitCastWrongTypes_ReturnType_sema);
	RUN_TEST(test_GlobalVariableInitWithGlobalVar);

	RUN_TEST(test_FunctionDecl_codegen);
	RUN_TEST(test_BuiltinGlobalVarNoInit_codegen);
	RUN_TEST(test_BuiltinGlobalVar_codegen);
	RUN_TEST(test_BuiltinGlobalConst_codegen);
	RUN_TEST(test_StructDecl_codegen);
	RUN_TEST(test_GlobalStructDeclInit_codegen);
	RUN_TEST(test_ConstGlobalStructDeclInit_codegen);
	RUN_TEST(test_LocalVarDeclNoInit_codegen);
	RUN_TEST(test_LocalVarDeclWithInit_codegen);
	RUN_TEST(test_LocalVarDeclWithInitOfIdent_codegen);
	RUN_TEST(test_LocalVarReassignmentToLiteral_codegen);
	RUN_TEST(test_LocalVarReassignmentToLocalVar_codegen);
	RUN_TEST(test_LocalVarReassignmentToGlobalVar_codegen);
	RUN_TEST(test_GlobalVarReassignmentToLiteral_codegen);
	RUN_TEST(test_GlobalVarReassignmentToGlobal_codegen);
	RUN_TEST(test_GlobalVarReassignmentToLocal_codegen);
	RUN_TEST(test_LocalStructLiteralInit_codegen);
	RUN_TEST(test_LocalStructLiteralEmptyInit_codegen);
	RUN_TEST(test_LocalStructLiteralReinitialization_codegen);
	RUN_TEST(test_NestedStructInit_codegen);
	RUN_TEST(test_BasicMemberAccessAssignment_codegen);
	RUN_TEST(test_NestedMemberAccessAssignment_codegen);
	RUN_TEST(test_MemberAccessAssignmentToMemberAccess_codegen);
	RUN_TEST(test_BasicReturn_codegen);
	RUN_TEST(test_ExprIdentReturn_codegen);
	RUN_TEST(test_MemberAccessReturn_codegen);
	RUN_TEST(test_MemberAccessNestedReturn_codegen);
	RUN_TEST(test_UnaryNeg_codegen);
	RUN_TEST(test_UnaryLogicalNot_codegen);
	RUN_TEST(test_UnaryAddressOf_codegen);
	RUN_TEST(test_UnaryDeref_codegen);
	RUN_TEST(test_UnaryBitwiseNot_codegen);
	RUN_TEST(test_Add_codegen);
	RUN_TEST(test_Sub_codegen);
	RUN_TEST(test_Div_codegen);
	RUN_TEST(test_Mul_codegen);
	RUN_TEST(test_Mod_codegen);
	RUN_TEST(test_SelfAdd_codegen);
	RUN_TEST(test_SelfSub_codegen);
	RUN_TEST(test_SelfMul_codegen);
	RUN_TEST(test_SelfDiv_codegen);
	RUN_TEST(test_CharList_codegen);
	RUN_TEST(test_LocalArrayLiteralInit_codegen);
	RUN_TEST(test_LocalArrayLiteralInitWithVar_codegen);
	RUN_TEST(test_LocalArrayLiteralNested_codegen);
	RUN_TEST(test_ArrayElementAccess_codegen);
	RUN_TEST(test_ArrayElementAccessFromVarIndex_codegen);
	RUN_TEST(test_NestedArrayAccess_codegen);
	RUN_TEST(test_VoidFnCallNoParams_codegen);
	RUN_TEST(test_VoidFnCallWithParams_codegen);
	RUN_TEST(test_NonVoidFnCallWithParams_codegen);
	RUN_TEST(test_EnumVar_codegen);
	RUN_TEST(test_EnumValueReturn_codegen);
	RUN_TEST(test_ExternBlockFn_codegen);
	RUN_TEST(test_ExternBlockFnVa_codegen);
	RUN_TEST(test_ForLoopConstComp_codegen);
	RUN_TEST(test_ForLoopVarComp_codegen);
	RUN_TEST(test_WhileLoopBasicComp_codegen);
	RUN_TEST(test_WhileLoopVarComp_codegen);
	RUN_TEST(test_IfStmtBasic_codegen);
	RUN_TEST(test_IfStmtInWhileLoop_codegen);
	RUN_TEST(test_IfElseStmtInWhileLoop_codegen);
	RUN_TEST(test_ExplicitCastIntToIntType);
	RUN_TEST(test_ExplicitCastFloatToFloatType);
	RUN_TEST(test_ExplicitCastFloatToIntType);
	RUN_TEST(test_ExplicitCastPtrToIntType);
	RUN_TEST(test_ExplicitCastPtrToPtr);
	RUN_TEST(test_ExplicitCastPtrToPtrWithAddressOf);
	RUN_TEST(test_WhileLoopContinueBreak_codegen);
	RUN_TEST(test_ForLoopContinueBreak_codegen);

	return UNITY_END();
}
