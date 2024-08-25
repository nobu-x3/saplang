#pragma once

#include <llvm/IR/IRBuilder.h>

#include <map>
#include <memory>
#include <vector>

#include "ast.h"

namespace saplang {
class Codegen {
public:
  explicit Codegen(std::vector<std::unique_ptr<ResolvedFuncDecl>> resolved_tree,
                   std::string_view source_path);
  std::unique_ptr<llvm::Module> generate_ir();

private:
  void gen_func_decl(const ResolvedFuncDecl &decl);
  void gen_func_body(const ResolvedFuncDecl &decl);
  llvm::Type *gen_type(Type type);
  llvm::AllocaInst *alloc_stack_var(llvm::Function *func, llvm::Type *type,
                                    std::string_view id);
  void gen_block(const ResolvedBlock &body);
  llvm::Value *gen_stmt(const ResolvedStmt &stmt);
  llvm::Value *gen_return_stmt(const ResolvedReturnStmt &stmt);
  llvm::Value *gen_expr(const ResolvedExpr &expr);
  llvm::Value *gen_binary_op(const ResolvedBinaryOperator &op);
  llvm::Value *gen_unary_op(const ResolvedUnaryOperator &op);
  llvm::Value *gen_call_expr(const ResolvedCallExpr &call);

private:
  std::vector<std::unique_ptr<ResolvedFuncDecl>> m_ResolvedTree{};
  std::map<const ResolvedDecl *, llvm::Value *> m_Declarations{};
  llvm::Value *m_RetVal{nullptr};
  llvm::BasicBlock *m_RetBB{nullptr};
  llvm::Instruction *m_AllocationInsertPoint{nullptr};
  llvm::LLVMContext m_Context;
  llvm::IRBuilder<> m_Builder;
  std::unique_ptr<llvm::Module> m_Module;
};
} // namespace saplang
