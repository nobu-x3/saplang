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
  llvm_unreachable("unexpected type.");
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
  if (auto *expr = dynamic_cast<const ResolvedExpr *>(&stmt))
    return gen_expr(*expr);
  if (auto *ifstmt = dynamic_cast<const ResolvedIfStmt *>(&stmt))
    return gen_if_stmt(*ifstmt);
  if (auto *whilestmt = dynamic_cast<const ResolvedWhileStmt *>(&stmt))
    return gen_while_stmt(*whilestmt);
  if (auto *return_stmt = dynamic_cast<const ResolvedReturnStmt *>(&stmt))
    return gen_return_stmt(*return_stmt);
  if (auto *decl_stmt = dynamic_cast<const ResolvedDeclStmt *>(&stmt))
    return gen_decl_stmt(*decl_stmt);
  if (auto *assignment = dynamic_cast<const ResolvedAssignment *>(&stmt))
    return gen_assignment(*assignment);
  if (auto *for_stmt = dynamic_cast<const ResolvedForStmt *>(&stmt))
    return gen_for_stmt(*for_stmt);
  llvm_unreachable("unknown statememt.");
  return nullptr;
}

llvm::Value *Codegen::gen_if_stmt(const ResolvedIfStmt &stmt) {
  llvm::Function *function = get_current_function();
  auto *true_bb = llvm::BasicBlock::Create(m_Context, "if.true");
  auto *exit_bb = llvm::BasicBlock::Create(m_Context, "if.exit");
  auto *else_bb = exit_bb;
  if (stmt.false_block) {
    else_bb = llvm::BasicBlock::Create(m_Context, "if.false");
  }
  llvm::Value *cond = gen_expr(*stmt.condition);
  m_Builder.CreateCondBr(type_to_bool(stmt.condition->type.kind, cond), true_bb,
                         else_bb);
  true_bb->insertInto(function);
  m_Builder.SetInsertPoint(true_bb);
  gen_block(*stmt.true_block);
  m_Builder.CreateBr(exit_bb);
  if (stmt.false_block) {
    else_bb->insertInto(function);
    m_Builder.SetInsertPoint(else_bb);
    gen_block(*stmt.false_block);
    m_Builder.CreateBr(exit_bb);
  }
  exit_bb->insertInto(function);
  m_Builder.SetInsertPoint(exit_bb);
  return nullptr;
}

llvm::Value *Codegen::gen_while_stmt(const ResolvedWhileStmt &stmt) {
  llvm::Function *function = get_current_function();
  llvm::BasicBlock *header =
      llvm::BasicBlock::Create(m_Context, "while.cond", function);
  llvm::BasicBlock *body =
      llvm::BasicBlock::Create(m_Context, "while.body", function);
  llvm::BasicBlock *exit =
      llvm::BasicBlock::Create(m_Context, "while.exit", function);
  m_Builder.CreateBr(header);
  m_Builder.SetInsertPoint(header);
  llvm::Value *condition = gen_expr(*stmt.condition);
  m_Builder.CreateCondBr(type_to_bool(stmt.condition->type.kind, condition),
                         body, exit);
  m_Builder.SetInsertPoint(body);
  gen_block(*stmt.body);
  m_Builder.CreateBr(header);
  m_Builder.SetInsertPoint(exit);
  return nullptr;
}

llvm::Value *Codegen::gen_for_stmt(const ResolvedForStmt &stmt) {
  llvm::Function *function = get_current_function();
  llvm::BasicBlock *counter_decl =
      llvm::BasicBlock::Create(m_Context, "for.counter_decl", function);
  llvm::BasicBlock *header =
      llvm::BasicBlock::Create(m_Context, "for.condition", function);
  llvm::BasicBlock *body =
      llvm::BasicBlock::Create(m_Context, "for.body", function);
  llvm::BasicBlock *counter_op =
      llvm::BasicBlock::Create(m_Context, "for.counter_op", function);
  llvm::BasicBlock *exit =
      llvm::BasicBlock::Create(m_Context, "for.exit", function);
  m_Builder.CreateBr(counter_decl);
  m_Builder.SetInsertPoint(counter_decl);
  llvm::Value *var_decl = gen_decl_stmt(*stmt.counter_variable);
  m_Builder.CreateBr(header);
  m_Builder.SetInsertPoint(header);
  llvm::Value *condition = gen_expr(*stmt.condition);
  m_Builder.CreateCondBr(type_to_bool(stmt.condition->type.kind, condition),
                         body, exit);
  m_Builder.SetInsertPoint(body);
  gen_block(*stmt.body);
  m_Builder.CreateBr(counter_op);
  m_Builder.SetInsertPoint(counter_op);
  llvm::Value *counter_incr = gen_stmt(*stmt.increment_expr);
  m_Builder.CreateBr(header);
  m_Builder.SetInsertPoint(exit);
  return nullptr;
}

llvm::Value *Codegen::gen_return_stmt(const ResolvedReturnStmt &stmt) {
  if (stmt.expr)
    m_Builder.CreateStore(gen_expr(*stmt.expr), m_RetVal);
  assert(m_RetBB && "function with return stmt doesn't have a return block");
  return m_Builder.CreateBr(m_RetBB);
}

enum class SimpleNumType { SINT, UINT, FLOAT };
SimpleNumType get_simple_type(Type::Kind type) {
  if ((type >= Type::Kind::u8 && type <= Type::Kind::u64) ||
      type == Type::Kind::Bool) {
    return SimpleNumType::UINT;
  } else if (type >= Type::Kind::i8 && type <= Type::Kind::i64) {
    return SimpleNumType::SINT;
  } else if (type >= Type::Kind::f32 && type <= Type::Kind::f64) {
    return SimpleNumType::FLOAT;
  }
  llvm_unreachable("unexpected type.");
}

llvm::Instruction::BinaryOps get_math_binop_kind(TokenKind op,
                                                 Type::Kind type) {
  SimpleNumType simple_type = get_simple_type(type);
  if (op == TokenKind::Plus) {
    if (simple_type == SimpleNumType::SINT ||
        simple_type == SimpleNumType::UINT) {
      return llvm::BinaryOperator::Add;
    } else if (simple_type == SimpleNumType::FLOAT) {
      return llvm::BinaryOperator::FAdd;
    }
  }
  if (op == TokenKind::Minus) {
    if (simple_type == SimpleNumType::SINT ||
        simple_type == SimpleNumType::UINT) {
      return llvm::BinaryOperator::Sub;
    } else if (simple_type == SimpleNumType::FLOAT) {
      return llvm::BinaryOperator::FSub;
    }
  }
  if (op == TokenKind::Asterisk) {
    if (simple_type == SimpleNumType::SINT ||
        simple_type == SimpleNumType::UINT) {
      return llvm::BinaryOperator::Mul;
    } else if (simple_type == SimpleNumType::FLOAT) {
      return llvm::BinaryOperator::FMul;
    }
  }
  if (op == TokenKind::Slash) {
    if (simple_type == SimpleNumType::UINT) {
      return llvm::BinaryOperator::UDiv;
    } else if (simple_type == SimpleNumType::SINT) {
      return llvm::BinaryOperator::SDiv;
    } else if (simple_type == SimpleNumType::FLOAT) {
      return llvm::BinaryOperator::FDiv;
    }
  }
  llvm_unreachable("unknown expression encountered.");
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
  if (auto *call = dynamic_cast<const ResolvedCallExpr *>(&expr))
    return gen_call_expr(*call);
  if (auto *group = dynamic_cast<const ResolvedGroupingExpr *>(&expr))
    return gen_expr(*group->expr);
  if (auto *binop = dynamic_cast<const ResolvedBinaryOperator *>(&expr))
    return gen_binary_op(*binop);
  if (auto *unop = dynamic_cast<const ResolvedUnaryOperator *>(&expr))
    return gen_unary_op(*unop);
  llvm_unreachable("unknown expression");
  return nullptr;
}

llvm::Value *Codegen::gen_binary_op(const ResolvedBinaryOperator &binop) {
  TokenKind op = binop.op;
  if (op == TokenKind::AmpAmp || op == TokenKind::PipePipe) {
    llvm::Function *function = get_current_function();
    bool is_or = op == TokenKind::PipePipe;
    const char *rhs_tag = is_or ? "or.rhs" : "and.rhs";
    const char *merge_tag = is_or ? "or.merge" : "and.merge";
    auto *rhs_bb = llvm::BasicBlock::Create(m_Context, rhs_tag, function);
    auto *merge_bb = llvm::BasicBlock::Create(m_Context, merge_tag, function);
    auto *true_bb = is_or ? merge_bb : rhs_bb;
    auto *false_bb = is_or ? rhs_bb : merge_bb;
    gen_conditional_op(*binop.lhs, true_bb, false_bb);
    m_Builder.SetInsertPoint(rhs_bb);
    llvm::Value *rhs = type_to_bool(binop.type.kind, gen_expr(*binop.rhs));
    m_Builder.CreateBr(merge_bb);
    rhs_bb = m_Builder.GetInsertBlock();
    m_Builder.SetInsertPoint(merge_bb);
    llvm::PHINode *phi = m_Builder.CreatePHI(m_Builder.getInt1Ty(), 2);
    for (auto it = llvm::pred_begin(merge_bb); it != llvm::pred_end(merge_bb);
         ++it) {
      if (*it == rhs_bb)
        phi->addIncoming(rhs, rhs_bb);
      else
        phi->addIncoming(m_Builder.getInt1(is_or), *it);
    }
    return bool_to_type(binop.type.kind, phi);
  }
  llvm::Value *lhs = gen_expr(*binop.lhs);
  llvm::Value *rhs = gen_expr(*binop.rhs);
  if (op == TokenKind::LessThan || op == TokenKind::GreaterThan ||
      op == TokenKind::EqualEqual || op == TokenKind::ExclamationEqual ||
      op == TokenKind::GreaterThanOrEqual || op == TokenKind::LessThanOrEqual)
    return bool_to_type(binop.type.kind,
                        gen_comp_op(op, binop.type.kind, lhs, rhs));
  return m_Builder.CreateBinOp(get_math_binop_kind(op, binop.type.kind), lhs,
                               rhs);
}

llvm::Value *gen_lt_expr(llvm::IRBuilder<> *builder, Type::Kind kind,
                         llvm::Value *lhs, llvm::Value *rhs) {
  if (kind >= Type::Kind::SIGNED_INT_START &&
      kind <= Type::Kind::SIGNED_INT_END) {
    return builder->CreateICmpSLT(lhs, rhs);
  }
  if ((kind >= Type::Kind::UNSIGNED_INT_START &&
       kind <= Type::Kind::UNSIGNED_INT_END) ||
      kind == Type::Kind::Bool) {
    return builder->CreateICmpULT(lhs, rhs);
  }
  if (kind >= Type::Kind::FLOATS_START && kind <= Type::Kind::FLOATS_END) {
    return builder->CreateFCmpOLT(lhs, rhs);
  }
  llvm_unreachable("unexpected type.");
}

llvm::Value *gen_gt_expr(llvm::IRBuilder<> *builder, Type::Kind kind,
                         llvm::Value *lhs, llvm::Value *rhs) {
  if (kind >= Type::Kind::SIGNED_INT_START &&
      kind <= Type::Kind::SIGNED_INT_END) {
    return builder->CreateICmpSGT(lhs, rhs);
  }
  if ((kind >= Type::Kind::UNSIGNED_INT_START &&
       kind <= Type::Kind::UNSIGNED_INT_END) ||
      kind == Type::Kind::Bool) {
    return builder->CreateICmpUGT(lhs, rhs);
  }
  if (kind >= Type::Kind::FLOATS_START && kind <= Type::Kind::FLOATS_END) {
    return builder->CreateFCmpOGT(lhs, rhs);
  }
  llvm_unreachable("unexpected type.");
}

llvm::Value *gen_eq_expr(llvm::IRBuilder<> *builder, Type::Kind kind,
                         llvm::Value *lhs, llvm::Value *rhs) {
  if ((kind >= Type::Kind::INTEGERS_START &&
       kind <= Type::Kind::INTEGERS_END) ||
      kind == Type::Kind::Bool) {
    return builder->CreateICmpEQ(lhs, rhs);
  }
  if (kind >= Type::Kind::FLOATS_START && kind <= Type::Kind::FLOATS_END) {
    return builder->CreateFCmpOEQ(lhs, rhs);
  }
  llvm_unreachable("unexpected type.");
}

llvm::Value *gen_neq_expr(llvm::IRBuilder<> *builder, Type::Kind kind,
                          llvm::Value *lhs, llvm::Value *rhs) {
  if ((kind >= Type::Kind::INTEGERS_START &&
       kind <= Type::Kind::INTEGERS_END) ||
      kind == Type::Kind::Bool) {
    return builder->CreateICmpNE(lhs, rhs);
  }
  if (kind >= Type::Kind::FLOATS_START && kind <= Type::Kind::FLOATS_END) {
    return builder->CreateFCmpONE(lhs, rhs);
  }
  llvm_unreachable("unexpected type.");
}

llvm::Value *gen_gte_expr(llvm::IRBuilder<> *builder, Type::Kind kind,
                          llvm::Value *lhs, llvm::Value *rhs) {
  if (kind >= Type::Kind::SIGNED_INT_START &&
      kind <= Type::Kind::SIGNED_INT_END) {
    return builder->CreateICmpSGE(lhs, rhs);
  }
  if ((kind >= Type::Kind::UNSIGNED_INT_START &&
       kind <= Type::Kind::UNSIGNED_INT_END) ||
      kind == Type::Kind::Bool) {
    return builder->CreateICmpUGE(lhs, rhs);
  }
  if (kind >= Type::Kind::FLOATS_START && kind <= Type::Kind::FLOATS_END) {
    return builder->CreateFCmpOGE(lhs, rhs);
  }
  llvm_unreachable("unexpected type.");
}

llvm::Value *gen_lte_expr(llvm::IRBuilder<> *builder, Type::Kind kind,
                          llvm::Value *lhs, llvm::Value *rhs) {
  if (kind >= Type::Kind::SIGNED_INT_START &&
      kind <= Type::Kind::SIGNED_INT_END) {
    return builder->CreateICmpSLE(lhs, rhs);
  }
  if ((kind >= Type::Kind::UNSIGNED_INT_START &&
       kind <= Type::Kind::UNSIGNED_INT_END) ||
      kind == Type::Kind::Bool) {
    return builder->CreateICmpULE(lhs, rhs);
  }
  if (kind >= Type::Kind::FLOATS_START && kind <= Type::Kind::FLOATS_END) {
    return builder->CreateFCmpOLE(lhs, rhs);
  }
  llvm_unreachable("unexpected type.");
}

llvm::Value *Codegen::gen_comp_op(TokenKind op, Type::Kind kind,
                                  llvm::Value *lhs, llvm::Value *rhs) {
  llvm::Value *ret_val;
  switch (op) {
  case TokenKind::LessThan: {
    ret_val = gen_lt_expr(&m_Builder, kind, lhs, rhs);
  } break;
  case TokenKind::GreaterThan: {
    ret_val = gen_gt_expr(&m_Builder, kind, lhs, rhs);
  } break;
  case TokenKind::EqualEqual: {
    ret_val = gen_eq_expr(&m_Builder, kind, lhs, rhs);
  } break;
  case TokenKind::ExclamationEqual: {
    ret_val = gen_neq_expr(&m_Builder, kind, lhs, rhs);
  } break;
  case TokenKind::LessThanOrEqual: {
    ret_val = gen_lte_expr(&m_Builder, kind, lhs, rhs);
  } break;
  case TokenKind::GreaterThanOrEqual: {
    ret_val = gen_gte_expr(&m_Builder, kind, lhs, rhs);
  } break;
  }
  return bool_to_type(kind, ret_val);
}

llvm::Value *Codegen::gen_unary_op(const ResolvedUnaryOperator &op) {
  llvm::Value *rhs = gen_expr(*op.rhs);
  SimpleNumType type = get_simple_type(op.rhs->type.kind);
  if (op.op == TokenKind::Minus) {
    if (type == SimpleNumType::SINT || type == SimpleNumType::UINT)
      return m_Builder.CreateNeg(rhs);
    else if (type == SimpleNumType::FLOAT)
      return m_Builder.CreateFNeg(rhs);
  }
  if (op.op == TokenKind::Exclamation) {
    return m_Builder.CreateNot(rhs);
  }
  llvm_unreachable("unknown unary op.");
  return nullptr;
}

void Codegen::gen_conditional_op(const ResolvedExpr &op,
                                 llvm::BasicBlock *true_bb,
                                 llvm::BasicBlock *false_bb) {
  const auto *binop = dynamic_cast<const ResolvedBinaryOperator *>(&op);
  if (binop && binop->op == TokenKind::PipePipe) {
    llvm::BasicBlock *next_bb = llvm::BasicBlock::Create(
        m_Context, "or.lhs.false", true_bb->getParent());
    gen_conditional_op(*binop->lhs, true_bb, next_bb);
    m_Builder.SetInsertPoint(next_bb);
    gen_conditional_op(*binop->rhs, true_bb, false_bb);
    return;
  }
  if (binop && binop->op == TokenKind::AmpAmp) {
    llvm::BasicBlock *next_bb = llvm::BasicBlock::Create(
        m_Context, "and.lhs.true", true_bb->getParent());
    gen_conditional_op(*binop->lhs, next_bb, false_bb);
    m_Builder.SetInsertPoint(next_bb);
    gen_conditional_op(*binop->rhs, true_bb, false_bb);
    return;
  }
  llvm::Value *val = type_to_bool(op.type.kind, gen_expr(op));
  m_Builder.CreateCondBr(val, true_bb, false_bb);
}

llvm::Value *Codegen::gen_call_expr(const ResolvedCallExpr &call) {
  llvm::Function *callee = m_Module->getFunction(call.func_decl->id);
  std::vector<llvm::Value *> args{};
  for (auto &&arg : call.args) {
    args.emplace_back(gen_expr(*arg));
  }
  return m_Builder.CreateCall(callee, args);
}

llvm::Value *Codegen::gen_decl_stmt(const ResolvedDeclStmt &stmt) {
  llvm::Function *function = get_current_function();
  const auto *decl = stmt.var_decl.get();
  llvm::Type *type = gen_type(decl->type);
  llvm::AllocaInst *var = alloc_stack_var(function, type, decl->id);
  if (const auto &init = decl->initializer)
    m_Builder.CreateStore(gen_expr(*init), var);
  m_Declarations[decl] = var;
  return nullptr;
}

llvm::Function *Codegen::get_current_function() {
  return m_Builder.GetInsertBlock()->getParent();
}

llvm::Value *Codegen::type_to_bool(Type::Kind kind, llvm::Value *value) {
  if (kind >= Type::Kind::INTEGERS_START && kind <= Type::Kind::INTEGERS_END)
    return m_Builder.CreateICmpNE(
        value, llvm::ConstantInt::getBool(m_Context, false), "to.bool");
  if (kind >= Type::Kind::FLOATS_START && kind <= Type::Kind::FLOATS_END)
    return m_Builder.CreateFCmpONE(
        value, llvm::ConstantFP::get(m_Builder.getDoubleTy(), 0.0), "to.bool");
  if (kind == Type::Kind::Bool)
    return value;
  llvm_unreachable("unexpected type cast to bool.");
}

llvm::Value *Codegen::bool_to_type(Type::Kind kind, llvm::Value *value) {
  if ((kind >= Type::Kind::INTEGERS_START &&
       kind <= Type::Kind::INTEGERS_END) ||
      kind == Type::Kind::Bool)
    return value;
  if (kind == Type::Kind::f32)
    return m_Builder.CreateUIToFP(value, m_Builder.getFloatTy(), "to.float");
  if (kind == Type::Kind::f64)
    return m_Builder.CreateUIToFP(value, m_Builder.getDoubleTy(), "to.double");
  llvm_unreachable("unexpected type cast from bool.");
}

llvm::Value *Codegen::gen_assignment(const ResolvedAssignment &assignment) {
  return m_Builder.CreateStore(gen_expr(*assignment.expr),
                               m_Declarations[assignment.variable->decl]);
}
} // namespace saplang
