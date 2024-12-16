#pragma once

#include <llvm/IR/IRBuilder.h>

#include <map>
#include <memory>
#include <vector>

#include "ast.h"

namespace saplang {
class Codegen {
public:
  explicit Codegen(std::vector<std::unique_ptr<ResolvedDecl>> resolved_tree, std::string_view source_path);
  explicit Codegen(std::vector<std::unique_ptr<ResolvedModule>> resolved_modules, std::string_view source_path);
  std::unique_ptr<llvm::Module> generate_ir();
  std::vector<std::unique_ptr<llvm::Module>> generate_modules();

private:
  struct CurrentFunction {
    llvm::Function *current_function;
    std::vector<const ResolvedDeferStmt *> deferred_stmts;
    llvm::Value *return_value{nullptr};
    llvm::BasicBlock *return_bb{nullptr};
    bool is_void{false};
    llvm::Type *return_type{nullptr};
  };

  void gen_func_decl(const ResolvedFuncDecl &decl, llvm::Module &mod);

  void gen_func_body(const ResolvedFuncDecl &decl, llvm::Module &mod);

  void gen_struct_decl(const ResolvedStructDecl &decl, llvm::Module &mod);

  void gen_global_var_decl(const ResolvedVarDecl &decl, llvm::Module &mod);

  llvm::Constant *gen_global_struct_init(const ResolvedStructLiteralExpr &init, llvm::Module& mod);

  llvm::Constant *gen_global_array_init(const ResolvedArrayLiteralExpr &init, llvm::Module& mod);

  llvm::Constant *get_constant_number_value(const ResolvedNumberLiteral &numlit);

  llvm::Type *gen_type(const Type &type);

  llvm::AllocaInst *alloc_stack_var(llvm::Function *func, llvm::Type *type, std::string_view id);

  void gen_block(const ResolvedBlock &body, llvm::Module& mod);

  llvm::Value *gen_stmt(const ResolvedStmt &stmt, llvm::Module &mod);

  llvm::Value *gen_if_stmt(const ResolvedIfStmt &stmt, llvm::Module& mod);

  llvm::Value *gen_while_stmt(const ResolvedWhileStmt &stmt, llvm::Module& mod);

  llvm::Value *gen_for_stmt(const ResolvedForStmt &stmt, llvm::Module& mod);

  llvm::Value *gen_return_stmt(const ResolvedReturnStmt &stmt, llvm::Module& mod);

  llvm::Value *gen_expr(const ResolvedExpr &expr, llvm::Module &mod);

  llvm::Value *gen_binary_op(const ResolvedBinaryOperator &op, llvm::Module& mod);

  llvm::Value *gen_explicit_cast(const ResolvedExplicitCastExpr &cast, llvm::Module& mod);

  llvm::Value *gen_array_decay(const Type &lhs_type, const ResolvedDeclRefExpr &rhs_dre);

  std::pair<llvm::Value *, Type> gen_unary_op(const ResolvedUnaryOperator &op, llvm::Module& mod);

  std::vector<llvm::Value *> get_index_accesses(const ResolvedExpr &expr, llvm::Value *loaded_ptr, llvm::Module& mod);

  std::pair<llvm::Value *, Type> gen_dereference(const ResolvedDeclRefExpr &expr);

  llvm::Value *gen_comp_op(TokenKind op, Type::Kind kind, llvm::Value *lhs, llvm::Value *rhs);

  void gen_conditional_op(const ResolvedExpr &op, llvm::BasicBlock *true_bb, llvm::BasicBlock *false_bb, llvm::Module& mod);

  llvm::Value *gen_call_expr(const ResolvedCallExpr &call, llvm::Module &mod);

  llvm::Value *gen_struct_literal_expr(const ResolvedStructLiteralExpr &struct_lit, llvm::Module& mod);

  llvm::Value *gen_array_literal_expr(const ResolvedArrayLiteralExpr &array_lit, llvm::Value *p_array_value, llvm::Module& mod);

  llvm::Value *gen_string_literal_expr(const ResolvedStringLiteralExpr &str_lit, llvm::Module& mod);

  llvm::Value *gen_struct_literal_expr_assignment(const ResolvedStructLiteralExpr &struct_lit, llvm::Value *var, llvm::Module &mod);

  llvm::Value *gen_struct_member_access(const ResolvedStructMemberAccess &access, Type &out_type, llvm::Module& mod);

  llvm::Value *gen_array_element_access(const ResolvedArrayElementAccess &access, Type &out_type, llvm::Module& mod);

  llvm::Value *gen_decl_stmt(const ResolvedDeclStmt &stmt, llvm::Module& mod);

  llvm::Value *gen_assignment(const ResolvedAssignment &assignment, llvm::Module &mod);

  llvm::Function *get_current_function();

  llvm::Value *type_to_bool(Type::Kind kind, llvm::Value *value);

  llvm::Value *bool_to_type(Type::Kind kind, llvm::Value *value);

private:
  CurrentFunction m_CurrentFunction;
  std::vector<std::unique_ptr<ResolvedDecl>> m_ResolvedTree{};
  std::vector<std::unique_ptr<ResolvedModule>> m_ResolvedModules{};
  std::map<const ResolvedDecl *, llvm::Value *> m_Declarations{};
  std::map<std::string, llvm::Type *> m_CustomTypes{};
  llvm::Instruction *m_AllocationInsertPoint{nullptr};
  llvm::LLVMContext m_Context;
  llvm::IRBuilder<> m_Builder;
  std::unique_ptr<llvm::Module> m_Module;
  std::unordered_map<std::string, std::unique_ptr<llvm::Module>> m_Modules;
};
} // namespace saplang
