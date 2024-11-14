#include "codegen.h"
#include "ast.h"
#include "lexer.h"

#include <llvm-18/llvm/IR/DerivedTypes.h>
#include <llvm-18/llvm/IR/InstrTypes.h>
#include <llvm-18/llvm/IR/LLVMContext.h>
#include <llvm/IR/Function.h>
#include <llvm/IR/Module.h>
#include <utility>

namespace saplang {

Codegen::Codegen(std::vector<std::unique_ptr<ResolvedDecl>> resolved_tree,
                 std::string_view source_path)
    : m_ResolvedTree{std::move(resolved_tree)}, m_Builder{m_Context},
      m_Module{std::make_unique<llvm::Module>("<tu>", m_Context)} {
  m_Module->setSourceFileName(source_path);
  m_Module->setTargetTriple("x86-64");
}

std::unique_ptr<llvm::Module> Codegen::generate_ir() {
  for (auto &&decl : m_ResolvedTree) {
    if (const auto *func = dynamic_cast<const ResolvedFuncDecl *>(decl.get()))
      gen_func_decl(*func);
    else if (const auto *struct_decl =
                 dynamic_cast<const ResolvedStructDecl *>(decl.get()))
      gen_struct_decl(*struct_decl);
    else if (const auto *global_var_decl =
                 dynamic_cast<const ResolvedVarDecl *>(decl.get()))
      gen_global_var_decl(*global_var_decl);
  }

  for (auto &&decl : m_ResolvedTree) {
    if (const auto *func = dynamic_cast<const ResolvedFuncDecl *>(decl.get()))
      gen_func_body(*func);
  }

  return std::move(m_Module);
}

void Codegen::gen_func_decl(const ResolvedFuncDecl &decl) {
  llvm::Type *return_type = gen_type(decl.type);
  assert(return_type);
  std::vector<llvm::Type *> param_types{};
  for (auto &&param : decl.params) {
    param_types.emplace_back(gen_type(param->type));
  }
  auto *type = llvm::FunctionType::get(return_type, param_types, decl.is_vll);
  llvm::Value *value = llvm::Function::Create(
      type, llvm::Function::ExternalLinkage,
      decl.og_name.empty() ? decl.id : decl.og_name, *m_Module);
  assert(value);
  m_Declarations[&decl] = value;
}

void Codegen::gen_global_var_decl(const ResolvedVarDecl &decl) {
  llvm::Type *var_type = gen_type(decl.type);
  assert(var_type);
  llvm::Constant *var_init = nullptr;
  if (const auto *numlit =
          dynamic_cast<const ResolvedNumberLiteral *>(decl.initializer.get())) {
    var_init = get_constant_number_value(*numlit);
  } else if (const auto *struct_init =
                 dynamic_cast<const ResolvedStructLiteralExpr *>(
                     decl.initializer.get())) {
    var_init = gen_global_struct_init(*struct_init);
  } else if (const auto *nullexpr = dynamic_cast<const ResolvedNullExpr *>(
                 decl.initializer.get())) {
    llvm::Type *type = gen_type(nullexpr->type);
    llvm::PointerType *ptr_type = llvm::PointerType::get(type, 0);
    var_init = llvm::ConstantPointerNull::get(ptr_type);
  } else if (const auto *array_lit =
                 dynamic_cast<const ResolvedArrayLiteralExpr *>(
                     decl.initializer.get())) {
    var_init = gen_global_array_init(*array_lit);
  }
  // If var_init == nullptr there's an error in sema
  assert(var_init && "unexpected global variable type");
  llvm::GlobalVariable *global_var = new llvm::GlobalVariable(
      *m_Module, var_type, decl.is_const, llvm::GlobalVariable::ExternalLinkage,
      var_init, decl.id);
  m_Declarations[&decl] = global_var;
}

llvm::Constant *
Codegen::gen_global_struct_init(const ResolvedStructLiteralExpr &init) {
  llvm::StructType *struct_type =
      llvm::StructType::getTypeByName(m_Context, init.type.name);
  assert(struct_type);
  if (!struct_type)
    return report(init.location, "could not find struct type with name '" +
                                     init.type.name + "'.");
  std::vector<llvm::Constant *> constants{};
  constants.reserve(init.field_initializers.size());
  for (auto &&[name, expr] : init.field_initializers) {
    if (const auto *numlit =
            dynamic_cast<const ResolvedNumberLiteral *>(expr.get())) {
      constants.emplace_back(get_constant_number_value(*numlit));
    } else if (const auto *struct_lit =
                   dynamic_cast<const ResolvedStructLiteralExpr *>(
                       expr.get())) {
      constants.emplace_back(gen_global_struct_init(*struct_lit));
    } else if (const auto *array_lit =
                   dynamic_cast<const ResolvedArrayLiteralExpr *>(expr.get()))
      constants.emplace_back(gen_global_array_init(*array_lit));
  }
  return llvm::ConstantStruct::get(struct_type, constants);
}

llvm::Constant *
Codegen::gen_global_array_init(const ResolvedArrayLiteralExpr &init) {
  llvm::ArrayType *type = nullptr;
  if (init.type.array_data) {
    const auto &array_data = *init.type.array_data;
    Type de_arrayed_type = init.type;
    int dimension = de_array_type(de_arrayed_type, 1);
    llvm::Type *underlying_type = gen_type(de_arrayed_type);
    assert(underlying_type);
    if (dimension)
      type = llvm::ArrayType::get(underlying_type, dimension);
  }
  if (!type)
    return report(init.location, "cannot initialize array of this type.");
  if (!type->isArrayTy())
    return report(init.location, "not an array type.");
  std::vector<llvm::Constant *> constants{};
  constants.reserve(init.expressions.size());
  for (auto &&expr : init.expressions) {
    if (const auto *numlit =
            dynamic_cast<const ResolvedNumberLiteral *>(expr.get())) {
      constants.emplace_back(get_constant_number_value(*numlit));
    } else if (const auto *struct_lit =
                   dynamic_cast<const ResolvedStructLiteralExpr *>(
                       expr.get())) {
      constants.emplace_back(gen_global_struct_init(*struct_lit));
    } else if (const auto *array_lit =
                   dynamic_cast<const ResolvedArrayLiteralExpr *>(expr.get()))
      constants.emplace_back(gen_global_array_init(*array_lit));
  }
  return llvm::ConstantArray::get(type, constants);
}

llvm::Constant *
Codegen::get_constant_number_value(const ResolvedNumberLiteral &numlit) {
  auto *type = gen_type(numlit.type);
  assert(type);
  switch (numlit.type.kind) {
  case Type::Kind::f32:
    return llvm::ConstantFP::get(type, numlit.value.f32);
  case Type::Kind::f64:
    return llvm::ConstantFP::get(type, numlit.value.f64);
  case Type::Kind::i8:
    return llvm::ConstantInt::get(type, numlit.value.i8);
  case Type::Kind::u8:
    return llvm::ConstantInt::get(type, numlit.value.u8);
  case Type::Kind::i16:
    return llvm::ConstantInt::get(type, numlit.value.i16);
  case Type::Kind::u16:
    return llvm::ConstantInt::get(type, numlit.value.u16);
  case Type::Kind::i32:
    return llvm::ConstantInt::get(type, numlit.value.i32);
  case Type::Kind::u32:
    return llvm::ConstantInt::get(type, numlit.value.u32);
  case Type::Kind::i64:
    return llvm::ConstantInt::get(type, numlit.value.i64);
  case Type::Kind::u64:
    return llvm::ConstantInt::get(type, numlit.value.u64);
  case Type::Kind::Bool:
    return llvm::ConstantInt::get(type, numlit.value.b8);
  default:
    assert(false);
    return nullptr;
  }
  assert(false);
  return nullptr;
}

void Codegen::gen_struct_decl(const ResolvedStructDecl &decl) {
  std::vector<llvm::Type *> member_types{};
  for (auto &&[type, name] : decl.members) {
    member_types.emplace_back(gen_type(type));
  }
  llvm::ArrayRef<llvm::Type *> array_ref{member_types};
  llvm::StructType *struct_type =
      llvm::StructType::create(m_Context, array_ref, decl.id);
  assert(struct_type);
  m_CustomTypes[decl.id] = struct_type;
}

void Codegen::gen_func_body(const ResolvedFuncDecl &decl) {
  if (!decl.body)
    return;
  auto *function = m_Module->getFunction(decl.id);
  assert(function);
  auto *entry_bb = llvm::BasicBlock::Create(m_Context, "entry", function);
  assert(entry_bb);
  m_Builder.SetInsertPoint(entry_bb);
  llvm::Value *undef = llvm::UndefValue::get(m_Builder.getInt32Ty());
  assert(undef);
  m_AllocationInsertPoint = new llvm::BitCastInst(
      undef, undef->getType(), "alloca.placeholder", entry_bb);
  assert(m_AllocationInsertPoint);
  auto *return_type = gen_type(decl.type);
  assert(return_type);
  bool is_void = decl.type.kind == Type::Kind::Void;
  if (!is_void) {
    m_RetVal = alloc_stack_var(function, return_type, "retval");
  }
  m_RetBB = llvm::BasicBlock::Create(m_Context, "return");
  assert(m_RetBB);
  int idx = 0;
  for (auto &&arg : function->args()) {
    const auto *param_decl = decl.params[idx].get();
    assert(param_decl);
    auto *type = gen_type(decl.params[idx]->type);
    assert(type);
    arg.setName(param_decl->id);
    llvm::Value *var = alloc_stack_var(function, type, param_decl->id);
    assert(var);
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
  llvm::Value *load_ret = m_Builder.CreateLoad(return_type, m_RetVal);
  assert(load_ret);
  m_Builder.CreateRet(load_ret);
}

llvm::Type *Codegen::gen_type(const Type &type) {
  if (type.array_data) {
    const auto &array_data = *type.array_data;
    Type de_arrayed_type = type;
    int dimension = de_array_type(de_arrayed_type, 1);
    llvm::Type *underlying_type = gen_type(de_arrayed_type);
    assert(underlying_type);
    if (!dimension)
      return underlying_type;
    return llvm::ArrayType::get(underlying_type, dimension);
  }
  if (type.pointer_depth)
    return m_Builder.getPtrTy();
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
  case Type::Kind::Custom:
    return m_CustomTypes[type.name];
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
  if (auto *assignment = dynamic_cast<const ResolvedAssignment *>(&stmt))
    return gen_assignment(*assignment);
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
  if (auto *for_stmt = dynamic_cast<const ResolvedForStmt *>(&stmt))
    return gen_for_stmt(*for_stmt);
  llvm_unreachable("unknown statememt.");
  return nullptr;
}

llvm::Value *Codegen::gen_if_stmt(const ResolvedIfStmt &stmt) {
  llvm::Function *function = get_current_function();
  assert(function);
  auto *true_bb = llvm::BasicBlock::Create(m_Context, "if.true");
  assert(true_bb);
  auto *exit_bb = llvm::BasicBlock::Create(m_Context, "if.exit");
  assert(exit_bb);
  auto *else_bb = exit_bb;
  if (stmt.false_block) {
    else_bb = llvm::BasicBlock::Create(m_Context, "if.false");
  }
  llvm::Value *cond = gen_expr(*stmt.condition);
  assert(cond);
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
  assert(function);
  llvm::BasicBlock *header =
      llvm::BasicBlock::Create(m_Context, "while.cond", function);
  assert(header);
  llvm::BasicBlock *body =
      llvm::BasicBlock::Create(m_Context, "while.body", function);
  assert(body);
  llvm::BasicBlock *exit =
      llvm::BasicBlock::Create(m_Context, "while.exit", function);
  assert(exit);
  m_Builder.CreateBr(header);
  m_Builder.SetInsertPoint(header);
  llvm::Value *condition = gen_expr(*stmt.condition);
  assert(condition);
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
  assert(function);
  llvm::BasicBlock *counter_decl =
      llvm::BasicBlock::Create(m_Context, "for.counter_decl", function);
  assert(counter_decl);
  llvm::BasicBlock *header =
      llvm::BasicBlock::Create(m_Context, "for.condition", function);
  assert(header);
  llvm::BasicBlock *body =
      llvm::BasicBlock::Create(m_Context, "for.body", function);
  assert(body);
  llvm::BasicBlock *counter_op =
      llvm::BasicBlock::Create(m_Context, "for.counter_op", function);
  assert(counter_op);
  llvm::BasicBlock *exit =
      llvm::BasicBlock::Create(m_Context, "for.exit", function);
  assert(exit);
  m_Builder.CreateBr(counter_decl);
  m_Builder.SetInsertPoint(counter_decl);
  llvm::Value *var_decl = gen_decl_stmt(*stmt.counter_variable);
  m_Builder.CreateBr(header);
  m_Builder.SetInsertPoint(header);
  llvm::Value *condition = gen_expr(*stmt.condition);
  assert(condition);
  m_Builder.CreateCondBr(type_to_bool(stmt.condition->type.kind, condition),
                         body, exit);
  m_Builder.SetInsertPoint(body);
  gen_block(*stmt.body);
  m_Builder.CreateBr(counter_op);
  m_Builder.SetInsertPoint(counter_op);
  llvm::Value *counter_incr = gen_stmt(*stmt.increment_expr);
  assert(counter_incr);
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
  if (op == TokenKind::BitwiseShiftL) {
    return llvm::BinaryOperator::Shl;
  }
  if (op == TokenKind::BitwiseShiftR) {
    return llvm::BinaryOperator::AShr;
  }
  if (op == TokenKind::Percent) {
    return llvm::BinaryOperator::SRem;
  }
  if (op == TokenKind::Amp) {
    return llvm::BinaryOperator::And;
  }
  if (op == TokenKind::Pipe) {
    return llvm::BinaryOperator::Or;
  }
  if (op == TokenKind::Hat) {
    return llvm::BinaryOperator::Xor;
  }
  llvm_unreachable("unknown expression encountered.");
}

llvm::Value *Codegen::gen_expr(const ResolvedExpr &expr) {
  if (auto *number = dynamic_cast<const ResolvedNumberLiteral *>(&expr)) {
    return get_constant_number_value(*number);
  }
  if (const auto *dre = dynamic_cast<const ResolvedDeclRefExpr *>(&expr)) {
    llvm::Value *decl = m_Declarations[dre->decl];
    assert(decl);
    auto *type = gen_type(dre->type);
    assert(type);
    if (auto *member_access =
            dynamic_cast<const ResolvedStructMemberAccess *>(dre)) {
      Type member_type = Type::builtin_void(false);
      decl = gen_struct_member_access(*member_access, member_type);
      assert(decl);
      type = gen_type(member_type);
      assert(type);
    } else if (auto *array_access =
                   dynamic_cast<const ResolvedArrayElementAccess *>(dre)) {
      Type underlying_type = Type::builtin_void(false);
      decl = gen_array_element_access(*array_access, underlying_type);
      assert(decl);
      type = gen_type(underlying_type);
      assert(type);
    }
    return m_Builder.CreateLoad(type, decl);
  }
  if (const auto *call = dynamic_cast<const ResolvedCallExpr *>(&expr))
    return gen_call_expr(*call);
  if (const auto *struct_lit =
          dynamic_cast<const ResolvedStructLiteralExpr *>(&expr))
    return gen_struct_literal_expr(*struct_lit);
  if (const auto *group = dynamic_cast<const ResolvedGroupingExpr *>(&expr))
    return gen_expr(*group->expr);
  if (const auto *binop = dynamic_cast<const ResolvedBinaryOperator *>(&expr))
    return gen_binary_op(*binop);
  if (const auto *unop = dynamic_cast<const ResolvedUnaryOperator *>(&expr)) {
    auto &&[res, type] = gen_unary_op(*unop);
    return res;
  }
  if (const auto *nullexpr = dynamic_cast<const ResolvedNullExpr *>(&expr)) {
    llvm::Type *type = gen_type(nullexpr->type);
    assert(type);
    llvm::PointerType *ptr_type = llvm::PointerType::get(type, 0);
    assert(ptr_type);
    return llvm::ConstantPointerNull::get(ptr_type);
  }
  if (const auto *cast = dynamic_cast<const ResolvedExplicitCastExpr *>(&expr))
    return gen_explicit_cast(*cast);
  if (const auto *str = dynamic_cast<const ResolvedStringLiteralExpr *>(&expr))
    return gen_string_literal_expr(*str);
  llvm_unreachable("unknown expression");
  return nullptr;
}

llvm::Value *Codegen::gen_struct_literal_expr_assignment(
    const ResolvedStructLiteralExpr &struct_lit, llvm::Value *var) {
  // @TODO: if fully const just memset or memcpy directly to variable
  int index = -1;
  for (auto &&[field_name, expr] : struct_lit.field_initializers) {
    ++index;
    if (!expr)
      continue;
    llvm::Value *gened_expr = nullptr;
    std::vector<llvm::Value *> indices{
        llvm::ConstantInt::get(
            m_Context,
            llvm::APInt(static_cast<unsigned>(platform_ptr_size()), 0)),
        llvm::ConstantInt::get(
            m_Context,
            llvm::APInt(static_cast<unsigned>(platform_ptr_size()), index))};
    auto *type = gen_type(struct_lit.type);
    assert(type);
    llvm::Value *memptr = m_Builder.CreateInBoundsGEP(type, var, indices);
    assert(memptr);
    if (const auto *struct_lit =
            dynamic_cast<const ResolvedStructLiteralExpr *>(expr.get())) {
      gened_expr = gen_struct_literal_expr_assignment(*struct_lit, memptr);
    } else if (const auto *unary_op =
                   dynamic_cast<const ResolvedUnaryOperator *>(expr.get());
               unary_op && (unary_op->op == TokenKind::Amp)) {
      if (const auto *dre =
              dynamic_cast<ResolvedDeclRefExpr *>(unary_op->rhs.get())) {
        if (unary_op->op == TokenKind::Amp) {
          llvm::Value *expr = m_Declarations[dre->decl];
          assert(expr);
          m_Builder.CreateStore(expr, memptr);
        }
      }
    } else {
      gened_expr = gen_expr(*expr);
    }
    if (gened_expr && memptr && gened_expr != memptr)
      m_Builder.CreateStore(gened_expr, memptr);
  }
  return var;
}

llvm::Value *
Codegen::gen_struct_literal_expr(const ResolvedStructLiteralExpr &struct_lit) {
  // @TODO: if fully const just memset or memcpy directly to variable
  llvm::Function *current_function = get_current_function();
  assert(current_function);
  llvm::Value *stack_var =
      alloc_stack_var(current_function, gen_type(struct_lit.type), "");
  assert(stack_var);
  int index = -1;
  for (auto &&[field_name, expr] : struct_lit.field_initializers) {
    ++index;
    if (!expr)
      continue;
    llvm::Value *gened_expr = gen_expr(*expr);
    assert(gened_expr);
    std::vector<llvm::Value *> indices{
        llvm::ConstantInt::get(
            m_Context,
            llvm::APInt(static_cast<unsigned>(platform_ptr_size()), 0)),
        llvm::ConstantInt::get(
            m_Context,
            llvm::APInt(static_cast<unsigned>(platform_ptr_size()), index))};
    llvm::Value *memptr = m_Builder.CreateInBoundsGEP(gen_type(struct_lit.type),
                                                      stack_var, indices);
    assert(memptr);
    m_Builder.CreateStore(gened_expr, memptr);
  }
  return stack_var;
}

llvm::Value *
Codegen::gen_array_literal_expr(const ResolvedArrayLiteralExpr &array_lit,
                                llvm::Value *p_array_value) {
  llvm::Function *current_function = get_current_function();
  assert(current_function);
  // @TODO: memcpy on if all constant
  bool all_constant = true;
  for (auto &expr : array_lit.expressions) {
    if (!expr->get_constant_value()) {
      all_constant = false;
      break;
    }
  }
  if (array_lit.expressions.size() > 0) {
    std::vector<llvm::Value *> indices{
        llvm::ConstantInt::get(
            m_Context,
            llvm::APInt(static_cast<unsigned>(platform_array_index_size()), 0)),
        llvm::ConstantInt::get(
            m_Context,
            llvm::APInt(static_cast<unsigned>(platform_array_index_size()),
                        0))};
    auto *p_array_type = gen_type(array_lit.type);
    assert(p_array_type);
    llvm::Value *p_array_element = m_Builder.CreateInBoundsGEP(
        p_array_type, p_array_value, indices, "arrayinit.begin");
    assert(p_array_element);
    if (const auto *inner_array =
            dynamic_cast<const ResolvedArrayLiteralExpr *>(
                array_lit.expressions[0].get())) {
      gen_array_literal_expr(*inner_array, p_array_element);
    } else {
      llvm::Value *expr_val = gen_expr(*array_lit.expressions[0]);
      assert(expr_val);
      m_Builder.CreateStore(expr_val, p_array_element);
    }
    for (int i = 1; i < array_lit.expressions.size(); ++i) {
      auto &expr = array_lit.expressions[i];
      std::vector<llvm::Value *> indices{llvm::ConstantInt::get(
          m_Context,
          llvm::APInt(static_cast<unsigned>(platform_array_index_size()), 1))};
      p_array_element = m_Builder.CreateInBoundsGEP(
          gen_type(expr->type), p_array_element, indices, "arrayinit.element");
      assert(p_array_element);
      if (const auto *inner_array =
              dynamic_cast<const ResolvedArrayLiteralExpr *>(
                  array_lit.expressions[i].get())) {
        gen_array_literal_expr(*inner_array, p_array_element);
      } else {
        llvm::Value *expr_val = gen_expr(*expr);
        assert(expr_val);
        m_Builder.CreateStore(expr_val, p_array_element);
      }
    }
  }
  return nullptr;
}

llvm::Value *
Codegen::gen_string_literal_expr(const ResolvedStringLiteralExpr &str_lit) {
  std::string reparsed_string;
  for(int i = 0; i < str_lit.val.size(); ++i) {
    if (str_lit.val[i] == '\\') {
      ++i;
      if (str_lit.val[i] == 'n') {
        reparsed_string += '\n';
        ++i;
      }
      continue;
    }
    reparsed_string += str_lit.val[i];
  }
  for (auto it = str_lit.val.begin(); it != str_lit.val.end(); ++it) {
  }
  return m_Builder.CreateGlobalString(reparsed_string, ".str");
}

llvm::Value *
Codegen::gen_struct_member_access(const ResolvedStructMemberAccess &access,
                                  Type &out_type) {
  if (!access.inner_member_access)
    return nullptr;
  llvm::Function *current_function = get_current_function();
  assert(current_function);
  llvm::Value *decl = m_Declarations[access.decl];
  if (!decl)
    return report(access.location,
                  "unknown declaration '" + access.decl->id + "'.");
  Type access_decl_type = access.decl->type;
  if (access_decl_type.pointer_depth > 0) {
    decl = m_Builder.CreateLoad(gen_type(access_decl_type), decl);
    --access_decl_type.pointer_depth;
  }
  std::vector<llvm::Value *> outer_indices{
      llvm::ConstantInt::get(
          m_Context,
          llvm::APInt(static_cast<unsigned>(platform_ptr_size()), 0)),
      llvm::ConstantInt::get(
          m_Context, llvm::APInt(static_cast<unsigned>(platform_ptr_size()),
                                 access.inner_member_access->member_index))};
  llvm::Type *last_gep_type = gen_type(access_decl_type);
  assert(last_gep_type);
  llvm::Value *last_gep =
      m_Builder.CreateInBoundsGEP(last_gep_type, decl, outer_indices);
  assert(last_gep);
  if (access.params &&
      access.inner_member_access->type.kind == Type::Kind::FnPtr) {
    llvm::Type *function_ret_type = gen_type(access.inner_member_access->type);
    assert(function_ret_type);
    bool is_vll = access.inner_member_access->type.fn_ptr_signature->second;
    auto *function_type = llvm::FunctionType::get(function_ret_type, is_vll);
    assert(function_type);
    llvm::Value *loaded_fn =
        m_Builder.CreateLoad(m_Builder.getPtrTy(), last_gep);
    assert(loaded_fn);
    std::vector<llvm::Value *> args;
    for (auto &&res_arg : *access.params) {
      llvm::Value *arg = gen_expr(*res_arg);
      assert(arg);
      args.push_back(arg);
    }
    last_gep = m_Builder.CreateCall(function_type, loaded_fn, args);
  }
  out_type = access.inner_member_access->type;
  if (access.inner_member_access->inner_member_access) {
    InnerMemberAccess *current_chain =
        access.inner_member_access->inner_member_access.get();
    InnerMemberAccess *prev_chain = access.inner_member_access.get();
    while (current_chain) {
      out_type = current_chain->type;
      Type tmp_type = prev_chain->type;
      if (tmp_type.pointer_depth > 0) {
        last_gep = m_Builder.CreateLoad(gen_type(tmp_type), last_gep);
        --tmp_type.pointer_depth;
      }
      std::vector<llvm::Value *> inner_indices{
          llvm::ConstantInt::get(
              m_Context,
              llvm::APInt(static_cast<unsigned>(platform_ptr_size()), 0)),
          llvm::ConstantInt::get(
              m_Context, llvm::APInt(static_cast<unsigned>(platform_ptr_size()),
                                     current_chain->member_index))};
      auto *type = gen_type(tmp_type);
      assert(type);
      last_gep = m_Builder.CreateInBoundsGEP(type, last_gep, inner_indices);
      assert(last_gep);
      prev_chain = current_chain;
      current_chain = current_chain->inner_member_access.get();
    }
  }
  return last_gep;
}

std::vector<llvm::Value *>
Codegen::get_index_accesses(const ResolvedExpr &expr, llvm::Value *loaded_ptr) {
  std::vector<llvm::Value *> inner_indices{};
  std::optional<ConstexprResult> constexpr_res = expr.get_constant_value();
  if (constexpr_res) {
    const ConstexprResult &res = *constexpr_res;
    llvm::APInt index{static_cast<unsigned int>(platform_array_index_size()),
                      0};
    switch (res.kind) {
    case Type::Kind::i8:
      index = {static_cast<unsigned int>(platform_array_index_size()),
               static_cast<uint64_t>(res.value.i8)};
      break;
    case Type::Kind::u8:
      index = {static_cast<unsigned int>(platform_array_index_size()),
               res.value.u8};
      break;
    case Type::Kind::i16:
      index = {static_cast<unsigned int>(platform_array_index_size()),
               static_cast<uint64_t>(res.value.i16)};
      break;
    case Type::Kind::u16:
      index = {static_cast<unsigned int>(platform_array_index_size()),
               res.value.u16};
      break;
    case Type::Kind::i32:
      index = {static_cast<unsigned int>(platform_array_index_size()),
               static_cast<uint64_t>(res.value.i32)};
      break;
    case Type::Kind::u32:
      index = {static_cast<unsigned int>(platform_array_index_size()),
               res.value.u32};
      break;
    case Type::Kind::i64:
      index = {static_cast<unsigned int>(platform_array_index_size()),
               static_cast<uint64_t>(res.value.i64)};
      break;
    case Type::Kind::u64:
      index = {static_cast<unsigned int>(platform_array_index_size()),
               res.value.u64};
      break;
    case Type::Kind::Bool:
      index = {static_cast<unsigned int>(platform_array_index_size()),
               res.value.b8};
      break;
    default:
      break;
    }
    if (loaded_ptr) {
      inner_indices = {llvm::ConstantInt::get(m_Context, index)};
    } else {
      inner_indices = {
          llvm::ConstantInt::get(
              m_Context,
              llvm::APInt(
                  static_cast<unsigned int>(platform_array_index_size()), 0)),
          llvm::ConstantInt::get(m_Context, index)};
    }
  } else {
    llvm::Value *expr_value = gen_expr(expr);
    if (get_type_size(expr.type.kind) < platform_array_index_size()) { // extent
      expr_value = m_Builder.CreateSExt(
          expr_value, gen_type(platform_ptr_type()), "idxprom");
    } else if (get_type_size(expr.type.kind) >
               platform_array_index_size()) { // trunc
      expr_value = m_Builder.CreateTrunc(
          expr_value, gen_type(platform_ptr_type()), "idxtrunc");
    }
    if (loaded_ptr) {
      inner_indices = {expr_value};
    } else {
      inner_indices = {
          llvm::ConstantInt::get(
              m_Context,
              llvm::APInt(
                  static_cast<unsigned int>(platform_array_index_size()), 0)),
          expr_value};
    }
  }
  return std::move(inner_indices);
}

llvm::Value *
Codegen::gen_array_element_access(const ResolvedArrayElementAccess &access,
                                  Type &out_type) {
  assert(access.indices.size() >= 1 && "unknown index");
  llvm::Function *current_function = get_current_function();
  assert(current_function);
  llvm::Value *decl = m_Declarations[access.decl];
  if (!decl)
    return report(access.location,
                  "unknown declaration '" + access.decl->id + "'.");
  Type decl_type = access.decl->type;
  // Technically should be impossible but just in case sema fails to detect this
  if (!decl_type.array_data && decl_type.pointer_depth < 1)
    return report(access.location,
                  "trying to access element of a non-array non-pointer type.");
  bool is_decay = false;
  if (decl_type.pointer_depth > 0) {
    decl = m_Builder.CreateLoad(gen_type(decl_type), decl);
    --decl_type.pointer_depth;
    is_decay = true;
  }
  auto *last_gep_type = gen_type(decl_type);
  assert(last_gep_type);
  std::vector<llvm::Value *> inner_indices =
      get_index_accesses(*access.indices[0], is_decay ? decl : nullptr);
  llvm::Value *last_gep = m_Builder.CreateInBoundsGEP(
      last_gep_type, decl, inner_indices, "arrayidx");
  assert(last_gep);
  // we already decreased pointer depth
  if (!is_decay)
    de_array_type(decl_type, 1);
  out_type = decl_type;
  for (int i = 1; i < access.indices.size(); ++i) {
    if (decl_type.pointer_depth > 0) {
      auto *gened_decl_type = gen_type(decl_type);
      assert(gened_decl_type);
      last_gep = m_Builder.CreateLoad(gened_decl_type, last_gep);
      assert(last_gep);
      --decl_type.pointer_depth;
      is_decay = true;
    }
    std::vector<llvm::Value *> inner_indices =
        get_index_accesses(*access.indices[i], is_decay ? decl : nullptr);
    last_gep = m_Builder.CreateInBoundsGEP(gen_type(decl_type), last_gep,
                                           inner_indices, "arrayidx");
    assert(last_gep);
    if (!is_decay)
      de_array_type(decl_type, 1);
    out_type = decl_type;
  }
  return last_gep;
}

llvm::Value *Codegen::gen_explicit_cast(const ResolvedExplicitCastExpr &cast) {
  llvm::Value *var = nullptr;
  ResolvedExplicitCastExpr::CastType prev_cast_type =
      ResolvedExplicitCastExpr::CastType::Nop;
  const ResolvedDeclRefExpr *decl_ref_expr =
      dynamic_cast<const ResolvedDeclRefExpr *>(cast.rhs.get());
  if (!decl_ref_expr) {
    if (const ResolvedUnaryOperator *unop =
            dynamic_cast<const ResolvedUnaryOperator *>(cast.rhs.get())) {
      decl_ref_expr =
          dynamic_cast<const ResolvedDeclRefExpr *>(unop->rhs.get());
    } else if (const auto *inner_cast =
                   dynamic_cast<const ResolvedExplicitCastExpr *>(
                       cast.rhs.get())) {
      var = gen_explicit_cast(*inner_cast);
      prev_cast_type = inner_cast->cast_type;
    } else {
      var = gen_expr(*cast.rhs);
    }
  }
  var = decl_ref_expr ? m_Declarations[decl_ref_expr->decl] : var;
  if (!var)
    return nullptr;
  llvm::Type *type = gen_type(cast.type);
  assert(type);
  llvm::Type *rhs_type = gen_type(cast.rhs->type);
  assert(rhs_type);
  switch (cast.cast_type) {
  case ResolvedExplicitCastExpr::CastType::IntToPtr: {
    if (get_type_size(cast.rhs->type.kind) < platform_array_index_size()) {
      llvm::Value *load = m_Builder.CreateLoad(rhs_type, var);
      auto *gened_platform_ptr_type = gen_type(platform_ptr_type());
      assert(gened_platform_ptr_type);
      var = m_Builder.CreateSExt(load, gened_platform_ptr_type, "cast_sext");
    }
    assert(var);
    return m_Builder.CreateIntToPtr(var, type, "cast_itp");
  }
  case ResolvedExplicitCastExpr::CastType::PtrToInt: {
    var = m_Builder.CreateLoad(m_Builder.getPtrTy(), var);
    assert(var);
    return m_Builder.CreatePtrToInt(var, type, "cast_pti");
  }
  case ResolvedExplicitCastExpr::CastType::IntToFloat: {
    llvm::Value *load = m_Builder.CreateLoad(rhs_type, var);
    assert(load);
    if (is_signed(decl_ref_expr->type.kind))
      return m_Builder.CreateSIToFP(load, type, "cast_stf");
    return m_Builder.CreateUIToFP(load, type, "cast_utf");
  }
  case ResolvedExplicitCastExpr::CastType::FloatToInt: {
    llvm::Value *load = m_Builder.CreateLoad(rhs_type, var);
    assert(load);
    if (is_signed(cast.type.kind))
      return m_Builder.CreateFPToSI(load, type, "cast_fts");
    return m_Builder.CreateFPToUI(load, type, "cast_ftu");
  }
  case ResolvedExplicitCastExpr::CastType::Ptr:
    return var;
  case ResolvedExplicitCastExpr::CastType::Extend: {
    if (prev_cast_type == ResolvedExplicitCastExpr::CastType::Nop) {
      var = m_Builder.CreateLoad(rhs_type, var);
    }
    assert(var);
    if (is_float(cast.type.kind))
      return m_Builder.CreateFPExt(var, type, "cast_fpext");
    return m_Builder.CreateSExt(var, type, "cast_sext");
  }
  case ResolvedExplicitCastExpr::CastType::Truncate: {
    if (prev_cast_type == ResolvedExplicitCastExpr::CastType::Nop) {
      var = m_Builder.CreateLoad(rhs_type, var);
    }
    assert(var);
    if (is_float(cast.type.kind))
      return m_Builder.CreateFPTrunc(var, type, "cast_fptrunc");
    return m_Builder.CreateTrunc(var, type, "cast_trunc");
  }
  default:
    return m_Builder.CreateLoad(type, var);
  }
}

llvm::Value *Codegen::gen_binary_op(const ResolvedBinaryOperator &binop) {
  TokenKind op = binop.op;
  if (op == TokenKind::AmpAmp || op == TokenKind::PipePipe) {
    llvm::Function *function = get_current_function();
    assert(function);
    bool is_or = op == TokenKind::PipePipe;
    const char *rhs_tag = is_or ? "or.rhs" : "and.rhs";
    const char *merge_tag = is_or ? "or.merge" : "and.merge";
    auto *rhs_bb = llvm::BasicBlock::Create(m_Context, rhs_tag, function);
    assert(rhs_bb);
    auto *merge_bb = llvm::BasicBlock::Create(m_Context, merge_tag, function);
    assert(merge_bb);
    auto *true_bb = is_or ? merge_bb : rhs_bb;
    auto *false_bb = is_or ? rhs_bb : merge_bb;
    gen_conditional_op(*binop.lhs, true_bb, false_bb);
    m_Builder.SetInsertPoint(rhs_bb);
    llvm::Value *rhs = type_to_bool(binop.type.kind, gen_expr(*binop.rhs));
    assert(rhs);
    m_Builder.CreateBr(merge_bb);
    rhs_bb = m_Builder.GetInsertBlock();
    assert(rhs_bb);
    m_Builder.SetInsertPoint(merge_bb);
    llvm::PHINode *phi = m_Builder.CreatePHI(m_Builder.getInt1Ty(), 2);
    assert(phi);
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
  assert(lhs);
  llvm::Value *rhs = gen_expr(*binop.rhs);
  assert(rhs);
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
  assert(builder);
  assert(rhs);
  assert(lhs);
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
  assert(builder);
  assert(rhs);
  assert(lhs);
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
  assert(builder);
  assert(rhs);
  assert(lhs);
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
  assert(builder);
  assert(rhs);
  assert(lhs);
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
  assert(builder);
  assert(rhs);
  assert(lhs);
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
  assert(builder);
  assert(rhs);
  assert(lhs);
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
  assert(rhs);
  assert(lhs);
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
  assert(ret_val);
  return bool_to_type(kind, ret_val);
}

std::pair<llvm::Value *, Type>
Codegen::gen_dereference(const ResolvedDeclRefExpr &expr) {
  llvm::Value *decl = m_Declarations[expr.decl];
  llvm::Value *ptr = m_Builder.CreateLoad(gen_type(expr.type), decl);
  assert(ptr);
  Type new_internal_type = expr.type;
  --new_internal_type.pointer_depth;
  llvm::Type *dereferenced_type = gen_type(new_internal_type);
  assert(dereferenced_type);
  auto *gened_load = m_Builder.CreateLoad(dereferenced_type, ptr);
  assert(gened_load);
  return std::make_pair(gened_load, new_internal_type);
}

std::pair<llvm::Value *, Type>
Codegen::gen_unary_op(const ResolvedUnaryOperator &op) {
  if (op.op == TokenKind::Asterisk) {
    if (auto *dre = dynamic_cast<ResolvedDeclRefExpr *>(op.rhs.get())) {
      return gen_dereference(*dre);
    } else if (auto *unop =
                   dynamic_cast<ResolvedUnaryOperator *>(op.rhs.get())) {
      auto &&[rhs, type] = gen_unary_op(*unop);
      assert(rhs);
      --type.pointer_depth;
      llvm::Type *dereferenced_type = gen_type(type);
      assert(dereferenced_type);
      return std::make_pair(m_Builder.CreateLoad(dereferenced_type, rhs), type);
    } else {
      llvm::Value *gened = gen_expr(*op.rhs);
      assert(gened);
      return std::make_pair(gened, op.rhs->type);
    }
  } else if (op.op == TokenKind::Amp) {
    if (auto *dre = dynamic_cast<ResolvedDeclRefExpr *>(op.rhs.get())) {
    }
  }
  llvm::Value *rhs = gen_expr(*op.rhs);
  assert(rhs);
  SimpleNumType type = get_simple_type(op.rhs->type.kind);
  if (op.op == TokenKind::Minus) {
    if (type == SimpleNumType::SINT || type == SimpleNumType::UINT)
      return std::make_pair(m_Builder.CreateNeg(rhs), op.type);
    else if (type == SimpleNumType::FLOAT)
      return std::make_pair(m_Builder.CreateFNeg(rhs), op.type);
  }
  if (op.op == TokenKind::Exclamation) {
    return std::make_pair(m_Builder.CreateNot(rhs), op.type);
  }
  if (op.op == TokenKind::Tilda) {
    return std::make_pair(
        m_Builder.CreateXor(rhs, llvm::ConstantInt::get(gen_type(op.type), -1),
                            "not"),
        op.type);
  }
  llvm_unreachable("unknown unary op.");
  return std::make_pair(nullptr, op.type);
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
    assert(next_bb);
    gen_conditional_op(*binop->lhs, next_bb, false_bb);
    m_Builder.SetInsertPoint(next_bb);
    gen_conditional_op(*binop->rhs, true_bb, false_bb);
    return;
  }
  llvm::Value *val = type_to_bool(op.type.kind, gen_expr(op));
  assert(val);
  m_Builder.CreateCondBr(val, true_bb, false_bb);
}

llvm::Value *Codegen::gen_call_expr(const ResolvedCallExpr &call) {
  llvm::Function *callee = m_Module->getFunction(
      call.decl->og_name.empty() ? call.decl->id : call.decl->og_name);
  std::vector<llvm::Value *> args{};
  int param_index = -1;
  for (auto &&arg : call.args) {
    ++param_index;
    if (const auto *unary_op =
            dynamic_cast<const ResolvedUnaryOperator *>(arg.get());
        unary_op && (unary_op->op == TokenKind::Amp)) {
      if (const auto *dre =
              dynamic_cast<ResolvedDeclRefExpr *>(unary_op->rhs.get())) {
        llvm::Value *expr = m_Declarations[dre->decl];
        assert(expr);
        args.emplace_back(expr);
        continue;
      }
    }
    if (const auto *dre = dynamic_cast<ResolvedDeclRefExpr *>(arg.get())) {
      if (const auto *func_decl =
              dynamic_cast<const ResolvedFuncDecl *>(call.decl)) {
        llvm::Value *decay =
            gen_array_decay(func_decl->params[param_index]->type, *dre);
        if (decay) {
          args.emplace_back(decay);
          continue;
        }
      }
    }
    args.emplace_back(gen_expr(*arg));
  }
  // we're probably dealing with fn ptr
  if (!callee) {
    callee = static_cast<llvm::Function *>(m_Declarations[call.decl]);
    llvm::Type *function_ret_type = gen_type(call.type);
    assert(function_ret_type);
    bool is_fn_ptr = call.type.fn_ptr_signature.has_value();
    bool is_vll = false;
    if (is_fn_ptr)
      is_vll = call.type.fn_ptr_signature->second;
    auto *function_type = llvm::FunctionType::get(function_ret_type, is_vll);
    assert(function_type);
    llvm::Value *loaded_fn = m_Builder.CreateLoad(m_Builder.getPtrTy(), callee);
    assert(loaded_fn);
    return m_Builder.CreateCall(
        function_type, loaded_fn, args,
        call.decl->og_name.empty() ? call.decl->id : call.decl->og_name);
  }
  return m_Builder.CreateCall(callee, args);
}

llvm::Value *Codegen::gen_decl_stmt(const ResolvedDeclStmt &stmt) {
  llvm::Function *function = get_current_function();
  assert(function);
  const auto *decl = stmt.var_decl.get();
  assert(decl);
  llvm::Type *type = gen_type(decl->type);
  assert(type);
  llvm::AllocaInst *var = alloc_stack_var(function, type, decl->id);
  assert(var);
  if (const auto &init = decl->initializer) {
    if (const auto *struct_lit =
            dynamic_cast<const ResolvedStructLiteralExpr *>(init.get())) {
      gen_struct_literal_expr_assignment(*struct_lit, var);
    } else if (const auto *unary_op =
                   dynamic_cast<const ResolvedUnaryOperator *>(init.get());
               unary_op && (unary_op->op == TokenKind::Amp)) {
      if (const auto *dre =
              dynamic_cast<ResolvedDeclRefExpr *>(unary_op->rhs.get())) {
        llvm::Value *expr = m_Declarations[dre->decl];
        assert(expr);
        if (unary_op->op == TokenKind::Amp) {
          m_Builder.CreateStore(expr, var);
        }
      }
    } else if (const auto *array_lit =
                   dynamic_cast<ResolvedArrayLiteralExpr *>(init.get())) {
      gen_array_literal_expr(*array_lit, var);
    } else if (const auto *dre =
                   dynamic_cast<const ResolvedDeclRefExpr *>(init.get())) {
      llvm::Value *decay = gen_array_decay(decl->type, *dre);
      m_Builder.CreateStore(decay ? decay : gen_expr(*init), var);
    } else {
      m_Builder.CreateStore(gen_expr(*init), var);
    }
  }
  m_Declarations[decl] = var;
  return nullptr;
}

llvm::Value *Codegen::gen_array_decay(const Type &lhs_type,
                                      const ResolvedDeclRefExpr &rhs_dre) {
  if (rhs_dre.type.array_data) {
    if (is_same_array_decay(rhs_dre.type, lhs_type)) {
      std::vector<llvm::Value *> indices{
          llvm::ConstantInt::get(
              m_Context,
              llvm::APInt(static_cast<unsigned>(platform_array_index_size()),
                          0)),
          llvm::ConstantInt::get(
              m_Context,
              llvm::APInt(static_cast<unsigned>(platform_array_index_size()),
                          0))};
      llvm::Value *decl = m_Declarations[rhs_dre.decl];
      auto *type = gen_type(rhs_dre.type);
      assert(type);
      return m_Builder.CreateInBoundsGEP(type, decl, indices, "arraydecay");
    }
  }
  return nullptr;
}

llvm::Function *Codegen::get_current_function() {
  return m_Builder.GetInsertBlock()->getParent();
}

llvm::Value *Codegen::type_to_bool(Type::Kind kind, llvm::Value *value) {
  assert(value);
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
  assert(value);
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
  llvm::Value *decl = m_Declarations[assignment.variable->decl];
  Type member_type = Type::builtin_void(false);
  if (const auto *member_access =
          dynamic_cast<const ResolvedStructMemberAccess *>(
              assignment.variable.get())) {
    decl = gen_struct_member_access(*member_access, member_type);
  } else if (const auto *array_access =
                 dynamic_cast<const ResolvedArrayElementAccess *>(
                     assignment.variable.get())) {
    decl = gen_array_element_access(*array_access, member_type);
  } else {
    Type derefed_type = assignment.variable->type;
    for (int i = 0; i < assignment.lhs_deref_count; ++i) {
      decl = m_Builder.CreateLoad(gen_type(derefed_type), decl);
      --derefed_type.pointer_depth;
    }
  }
  assert(decl);
  // @TODO: this is super hacky. To refactor pass decl to Codegen::gen_expr and
  // further to Codegen::gen_unary_op
  if (const auto *unop =
          dynamic_cast<const ResolvedUnaryOperator *>(assignment.expr.get());
      unop && unop->op == TokenKind::Amp) {
    if (const auto *dre =
            dynamic_cast<ResolvedDeclRefExpr *>(unop->rhs.get())) {
      llvm::Value *expr = m_Declarations[dre->decl];
      assert(expr);
      return m_Builder.CreateStore(expr, decl);
    }
  } else {
    llvm::Value *expr = expr = gen_expr(*assignment.expr);
    assert(expr);
    if (const auto *struct_lit =
            dynamic_cast<const ResolvedStructLiteralExpr *>(
                assignment.expr.get())) {
      // expr is the stack variable
      llvm::Type *var_type = gen_type(struct_lit->type);
      assert(var_type);
      llvm::Type *decl_type = gen_type(assignment.variable->decl->type);
      assert(decl_type);
      const llvm::DataLayout &data_layout = m_Module->getDataLayout();
      return m_Builder.CreateMemCpy(
          decl, data_layout.getPrefTypeAlign(decl_type), expr,
          data_layout.getPrefTypeAlign(var_type),
          data_layout.getTypeAllocSize(var_type));
    }
    return m_Builder.CreateStore(expr, decl);
  }
  assert(false);
}
} // namespace saplang
