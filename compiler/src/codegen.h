#pragma once

#include <llvm/IR/IRBuilder.h>

#include <map>
#include <memory>
#include <vector>

#include "ast.h"

namespace saplang {
class Codegen {
public:
  explicit Codegen(std::vector<std::unique_ptr<ResolvedDecl>> resolved_tree,
                   std::string_view source_path);
  std::unique_ptr<llvm::Module> generate_ir();

private:
  void gen_func_decl(const ResolvedFuncDecl &decl);

  void gen_func_body(const ResolvedFuncDecl &decl);

  void gen_struct_decl(const ResolvedStructDecl &decl);

  void gen_global_var_decl(const ResolvedVarDecl &decl);

  llvm::Constant *gen_global_struct_init(const ResolvedStructLiteralExpr &init);

  llvm::Constant *
  get_constant_number_value(const ResolvedNumberLiteral &numlit);

  llvm::Type *gen_type(Type type);

  llvm::AllocaInst *alloc_stack_var(llvm::Function *func, llvm::Type *type,
                                    std::string_view id);

  void gen_block(const ResolvedBlock &body);

  llvm::Value *gen_stmt(const ResolvedStmt &stmt);

  llvm::Value *gen_if_stmt(const ResolvedIfStmt &stmt);

  llvm::Value *gen_while_stmt(const ResolvedWhileStmt &stmt);

  llvm::Value *gen_for_stmt(const ResolvedForStmt &stmt);

  llvm::Value *gen_return_stmt(const ResolvedReturnStmt &stmt);

  llvm::Value *gen_expr(const ResolvedExpr &expr);

  llvm::Value *gen_binary_op(const ResolvedBinaryOperator &op);

  std::pair<llvm::Value *, Type> gen_unary_op(const ResolvedUnaryOperator &op);

  std::pair<llvm::Value *, Type>
  gen_dereference(const ResolvedDeclRefExpr &expr);

  llvm::Value *gen_comp_op(TokenKind op, Type::Kind kind, llvm::Value *lhs,
                           llvm::Value *rhs);

  void gen_conditional_op(const ResolvedExpr &op, llvm::BasicBlock *true_bb,
                          llvm::BasicBlock *false_bb);

  llvm::Value *gen_call_expr(const ResolvedCallExpr &call);

  llvm::Value *
  gen_struct_literal_expr(const ResolvedStructLiteralExpr &struct_lit);

  llvm::Value *gen_struct_literal_expr_assignment(
      const ResolvedStructLiteralExpr &struct_lit, llvm::Value *var);

  llvm::Value *
  gen_struct_member_access(const ResolvedStructMemberAccess &access,
                           Type &out_type);

  llvm::Value *gen_decl_stmt(const ResolvedDeclStmt &stmt);

  llvm::Value *gen_assignment(const ResolvedAssignment &assignment);

  llvm::Function *get_current_function();

  llvm::Value *type_to_bool(Type::Kind kind, llvm::Value *value);

  llvm::Value *bool_to_type(Type::Kind kind, llvm::Value *value);

private:
  std::vector<std::unique_ptr<ResolvedDecl>> m_ResolvedTree{};
  std::map<const ResolvedDecl *, llvm::Value *> m_Declarations{};
  std::map<std::string, llvm::Type *> m_CustomTypes{};
  llvm::Value *m_RetVal{nullptr};
  llvm::BasicBlock *m_RetBB{nullptr};
  llvm::Instruction *m_AllocationInsertPoint{nullptr};
  llvm::LLVMContext m_Context;
  llvm::IRBuilder<> m_Builder;
  std::unique_ptr<llvm::Module> m_Module;
};
} // namespace saplang
