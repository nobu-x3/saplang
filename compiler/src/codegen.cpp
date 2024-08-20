#include "codegen.h"

#include <llvm/IR/Function.h>
#include <llvm/IR/Module.h>

namespace saplang {

Codegen::Codegen(std::vector<std::unique_ptr<ResolvedFuncDecl>> resolved_tree,
                 std::string_view source_path)
    : m_ResolvedTree{std::move(resolved_tree)}, m_Builder{m_Context},
      m_Module{std::make_unique<llvm::Module>("<tu>", m_Context)} {
  m_Module->setSourceFileName(source_path);
  m_Module->setTargetTriple("x86-64");
}

std::unique_ptr<llvm::Module> Codegen::generate_ir() {
  for (auto &&func : m_ResolvedTree) {
    gen_func_decl(*func);
  }

  for (auto &&func : m_ResolvedTree) {
    gen_func_body(*func);
  }

  return std::move(m_Module);
}

void Codegen::gen_func_decl(const ResolvedFuncDecl &decl) {
  llvm::Type *return_type = gen_type(decl.type);
  std::vector<llvm::Type *> param_types{};
  for (auto &&param : decl.params) {
    param_types.emplace_back(gen_type(param->type));
  }
  auto *type = llvm::FunctionType::get(return_type, param_types, false);
  llvm::Function::Create(type, llvm::Function::ExternalLinkage, decl.id,
                         *m_Module);
}

void Codegen::gen_func_body(const ResolvedFuncDecl &decl) {
  auto *function = m_Module->getFunction(decl.id);
  auto *entry_bb = llvm::BasicBlock::Create(m_Context, "entry", function);
  m_Builder.SetInsertPoint(entry_bb);
  llvm::Value *undef = llvm::UndefValue::get(m_Builder.getInt32Ty());
  m_AllocationInsertPoint = new llvm::BitCastInst(
      undef, undef->getType(), "alloca.placeholder", entry_bb);
  auto *return_type = gen_type(decl.type);
  bool is_void = decl.type.kind == Type::Kind::Void;
  if (!is_void) {
    m_RetVal = alloc_stack_var(function, return_type, "retval");
  }
  m_RetBB = llvm::BasicBlock::Create(m_Context, "return");
  int idx = 0;
  for (auto &&arg : function->args()) {
    const auto *param_decl = decl.params[idx].get();
    auto *type = gen_type(decl.params[idx]->type);
    arg.setName(param_decl->id);
    llvm::Value *var = alloc_stack_var(function, type, param_decl->id);
    m_Builder.CreateStore(&arg, var);
    m_Declarations[param_decl] = var;
    ++idx;
  }
  gen_block(*decl.body);
  if (m_RetBB->hasNPredecessorsOrMore(1)) {
    m_Builder.CreateBr(m_RetBB);
    m_RetBB->insertInto(function);
    m_Builder.SetInsertPoint(m_RetBB);
  }
  m_AllocationInsertPoint->eraseFromParent();
  m_AllocationInsertPoint = nullptr;
  if (is_void) {
    m_Builder.CreateRetVoid();
    return;
  }
  m_Builder.CreateRet(m_Builder.CreateLoad(return_type, m_RetVal));
}

llvm::Type *Codegen::gen_type(Type type) {
  switch (type.kind) {
  case Type::Kind::i8:
  case Type::Kind::u8:
    return m_Builder.getInt8Ty();
    break;
  case Type::Kind::i16:
  case Type::Kind::u16:
    return m_Builder.getInt16Ty();
    break;
  case Type::Kind::i32:
  case Type::Kind::u32:
    return m_Builder.getInt32Ty();
    break;
  case Type::Kind::i64:
  case Type::Kind::u64:
    return m_Builder.getInt64Ty();
    break;
  case Type::Kind::f32:
    return m_Builder.getFloatTy();
  case Type::Kind::f64:
    return m_Builder.getDoubleTy();
  case Type::Kind::Bool:
    return m_Builder.getInt1Ty();
  case Type::Kind::Void:
    return m_Builder.getVoidTy();
  case Type::Kind::Pointer:
    return m_Builder.getPtrTy();
  }
}

llvm::AllocaInst *Codegen::alloc_stack_var(llvm::Function *func,
                                           llvm::Type *type,
                                           std::string_view id) {
  llvm::IRBuilder<> tmp_builder{m_Context};
  tmp_builder.SetInsertPoint(m_AllocationInsertPoint);
  return tmp_builder.CreateAlloca(type, nullptr, id);
}

void Codegen::gen_block(const ResolvedBlock &body) {
  for (auto &&stmt : body.statements) {
    gen_stmt(*stmt);
    // @TODO: defer statements
    // After a return statement we clear the insertion point, so that
    // no other instructions are inserted into the current block and break.
    // The break ensures that no other instruction is generated that will be
    // inserted regardless of there is no insertion point and crash (e.g.:
    // CreateStore, CreateLoad).
    if (dynamic_cast<const ResolvedReturnStmt *>(stmt.get())) {
      m_Builder.ClearInsertionPoint();
      break;
    }
  }
}

llvm::Value *Codegen::gen_stmt(const ResolvedStmt &stmt) {
  if (auto *expr = dynamic_cast<const ResolvedExpr *>(&stmt)) {
    return gen_expr(*expr);
  }
  if (auto *return_stmt = dynamic_cast<const ResolvedReturnStmt *>(&stmt)) {
    return gen_return_stmt(*return_stmt);
  }
  llvm_unreachable("unknown statememt.");
  return nullptr;
}

llvm::Value *Codegen::gen_return_stmt(const ResolvedReturnStmt &stmt) {
  if (stmt.expr)
    m_Builder.CreateStore(gen_expr(*stmt.expr), m_RetVal);
  assert(m_RetBB && "function with return stmt doesn't have a return block");
  return m_Builder.CreateBr(m_RetBB);
}

llvm::Value *Codegen::gen_expr(const ResolvedExpr &expr) {
  if (auto *number = dynamic_cast<const ResolvedNumberLiteral *>(&expr)) {
    auto *type = gen_type(number->type);
    switch (number->type.kind) {
    case Type::Kind::f32:
      return llvm::ConstantFP::get(type, number->value.f32);
    case Type::Kind::f64:
      return llvm::ConstantFP::get(type, number->value.f64);
    case Type::Kind::i8:
      return llvm::ConstantInt::get(type, number->value.i8);
    case Type::Kind::u8:
      return llvm::ConstantInt::get(type, number->value.u8);
    case Type::Kind::i16:
      return llvm::ConstantInt::get(type, number->value.i16);
    case Type::Kind::u16:
      return llvm::ConstantInt::get(type, number->value.u16);
    case Type::Kind::i32:
      return llvm::ConstantInt::get(type, number->value.i32);
    case Type::Kind::u32:
      return llvm::ConstantInt::get(type, number->value.u32);
    case Type::Kind::i64:
      return llvm::ConstantInt::get(type, number->value.i64);
    case Type::Kind::u64:
      return llvm::ConstantInt::get(type, number->value.u64);
    case Type::Kind::Bool:
      return llvm::ConstantInt::get(type, number->value.b8);
    }
  }
  if (auto *dre = dynamic_cast<const ResolvedDeclRefExpr *>(&expr)) {
    auto *type = gen_type(dre->type);
    return m_Builder.CreateLoad(type, m_Declarations[dre->decl]);
  }
  if (auto *call = dynamic_cast<const ResolvedCallExpr *>(&expr)) {
    return gen_call_expr(*call);
  }
  llvm_unreachable("unknown expression");
  return nullptr;
}

llvm::Value *Codegen::gen_call_expr(const ResolvedCallExpr &call) {
  llvm::Function *callee = m_Module->getFunction(call.func_decl->id);
  std::vector<llvm::Value *> args{};
  for (auto &&arg : call.args) {
    args.emplace_back(gen_expr(*arg));
  }
  return m_Builder.CreateCall(callee, args);
}

} // namespace saplang