#pragma once

#include <llvm/IR/DIBuilder.h>
#include <llvm/IR/DebugInfoMetadata.h>
#include <llvm/IR/IRBuilder.h>

#include <map>
#include <memory>
#include <vector>

#include "ast.h"

namespace saplang {

struct DebugInfo {
  llvm::DICompileUnit *cu;
  std::vector<llvm::DIScope *> lexical_blocks;
  llvm::DIFile *file;
};

struct GeneratedModule {
  std::unique_ptr<llvm::Module> module;
  std::unique_ptr<llvm::DIBuilder> di_builder;
  std::unique_ptr<DebugInfo> debug_info;
};

class Codegen {
public:
  explicit Codegen(std::vector<std::unique_ptr<ResolvedDecl>> resolved_tree, std::string_view source_path);
  explicit Codegen(std::vector<std::unique_ptr<ResolvedModule>> resolved_modules, std::unordered_map<std::string, TypeInfo> type_infos,
                   bool should_gen_dbg = false);
  std::unique_ptr<llvm::Module> generate_ir();
  std::unordered_map<std::string, std::unique_ptr<GeneratedModule>> generate_modules();

private:
  struct CurrentFunction {
    llvm::Function *current_function;
    std::vector<const ResolvedDeferStmt *> deferred_stmts;
    llvm::Value *return_value{nullptr};
    llvm::BasicBlock *return_bb{nullptr};
    bool is_void{false};
    llvm::Type *return_type{nullptr};
  };

  void gen_func_decl(const ResolvedFuncDecl &decl, GeneratedModule &mod);

  void gen_func_body(const ResolvedFuncDecl &decl, GeneratedModule &mod);

  bool gen_struct_decl(const ResolvedStructDecl &decl, GeneratedModule &mod);

  void gen_global_var_decl(const ResolvedVarDecl &decl, GeneratedModule &mod);

  void emit_debug_location(const SourceLocation &loc, GeneratedModule &mod);

  llvm::Constant *gen_global_struct_init(const ResolvedStructLiteralExpr &init, GeneratedModule &mod);

  llvm::Constant *gen_global_array_init(const ResolvedArrayLiteralExpr &init, GeneratedModule &mod);

  llvm::Constant *get_constant_number_value(const ResolvedNumberLiteral &numlit, GeneratedModule &mod);

  llvm::Type *gen_type(const Type &type, GeneratedModule &mod);

  llvm::DIType *gen_debug_type(const Type &type, GeneratedModule &mod);

  llvm::DISubroutineType *gen_debug_function_type(GeneratedModule &mod, const Type &ret_type, const std::vector<std::unique_ptr<ResolvedParamDecl>> &args);

  llvm::AllocaInst *alloc_stack_var(llvm::Function *func, llvm::Type *type, std::string_view id);

  llvm::Value *gen_block(const ResolvedBlock &body, GeneratedModule &mod, bool is_defer_block = false);

  llvm::Value *gen_stmt(const ResolvedStmt &stmt, GeneratedModule &mod);

  llvm::Value *gen_if_stmt(const ResolvedIfStmt &stmt, GeneratedModule &mod);

  llvm::Value *gen_switch_stmt(const ResolvedSwitchStmt &stmt, GeneratedModule &mod);

  llvm::Value *gen_while_stmt(const ResolvedWhileStmt &stmt, GeneratedModule &mod);

  llvm::Value *gen_for_stmt(const ResolvedForStmt &stmt, GeneratedModule &mod);

  llvm::Value *gen_return_stmt(const ResolvedReturnStmt &stmt, GeneratedModule &mod);

  llvm::Value *gen_expr(const ResolvedExpr &expr, GeneratedModule &mod);

  llvm::Value *gen_binary_op(const ResolvedBinaryOperator &op, GeneratedModule &mod);

  llvm::Value *gen_explicit_cast(const ResolvedExplicitCastExpr &cast, GeneratedModule &mod);

  llvm::Value *gen_array_decay(const Type &lhs_type, const ResolvedDeclRefExpr &rhs_dre, GeneratedModule &mod);

  std::pair<llvm::Value *, Type> gen_unary_op(const ResolvedUnaryOperator &op, GeneratedModule &mod);

  std::vector<llvm::Value *> get_index_accesses(const ResolvedExpr &expr, llvm::Value *loaded_ptr, GeneratedModule &mod);

  std::pair<llvm::Value *, Type> gen_dereference(const ResolvedDeclRefExpr &expr, GeneratedModule &mod);

  llvm::Value *gen_comp_op(TokenKind op, const Type &type, llvm::Value *lhs, llvm::Value *rhs);

  void gen_conditional_op(const ResolvedExpr &op, llvm::BasicBlock *true_bb, llvm::BasicBlock *false_bb, GeneratedModule &mod);

  llvm::Value *gen_call_expr(const ResolvedCallExpr &call, GeneratedModule &mod);

  llvm::Value *gen_struct_literal_expr(const ResolvedStructLiteralExpr &struct_lit, GeneratedModule &mod);

  llvm::Value *gen_array_literal_expr(const ResolvedArrayLiteralExpr &array_lit, llvm::Value *p_array_value, GeneratedModule &mod);

  llvm::Value *gen_string_literal_expr(const ResolvedStringLiteralExpr &str_lit, GeneratedModule &mod);

  llvm::Value *gen_struct_literal_expr_assignment(const ResolvedStructLiteralExpr &struct_lit, llvm::Value *var, GeneratedModule &mod);

  llvm::Value *gen_struct_member_access(const ResolvedStructMemberAccess &access, Type &out_type, GeneratedModule &mod);

  llvm::Value *gen_array_element_access(const ResolvedArrayElementAccess &access, Type &out_type, GeneratedModule &mod);

  llvm::Value *gen_decl_stmt(const ResolvedDeclStmt &stmt, GeneratedModule &mod);

  llvm::Value *gen_assignment(const ResolvedAssignment &assignment, GeneratedModule &mod);

  llvm::Function *get_current_function();

  llvm::Value *type_to_bool(const Type &type, llvm::Value *value, std::optional<TokenKind> op = std::nullopt);

  llvm::Value *bool_to_type(const Type &type, llvm::Value *value);

private:
  CurrentFunction m_CurrentFunction;
  std::vector<std::unique_ptr<ResolvedDecl>> m_ResolvedTree{};
  std::vector<std::unique_ptr<ResolvedModule>> m_ResolvedModules{};
  std::unordered_map<std::string, TypeInfo> m_TypeInfos{};
  std::unordered_map<std::string, std::map<const ResolvedDecl *, llvm::Value *>> m_Declarations{};
  std::map<std::string, llvm::Type *> m_CustomTypes{};
  llvm::Instruction *m_AllocationInsertPoint{nullptr};
  llvm::LLVMContext m_Context;
  llvm::IRBuilder<> m_Builder;
  std::unique_ptr<GeneratedModule> m_Module;
  std::unordered_map<std::string, std::unique_ptr<GeneratedModule>> m_Modules;
  bool m_ShouldGenDebug = false;
};
} // namespace saplang
