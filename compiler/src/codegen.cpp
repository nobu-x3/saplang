#include "codegen.h"
#include "ast.h"
#include "lexer.h"

#include <filesystem>
#include <llvm/BinaryFormat/Dwarf.h>
#include <llvm/IR/BasicBlock.h>
#include <llvm/IR/DIBuilder.h>
#include <llvm/IR/DebugInfoMetadata.h>
#include <llvm/IR/DerivedTypes.h>
#include <llvm/IR/Function.h>
#include <llvm/IR/InstrTypes.h>
#include <llvm/IR/Instructions.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Metadata.h>
#include <llvm/IR/Module.h>
#include <llvm/TargetParser/Host.h>
#include <llvm/TargetParser/Triple.h>
#include <memory>
#include <utility>

namespace saplang {

Codegen::Codegen(std::vector<std::unique_ptr<ResolvedDecl>> resolved_tree, std::string_view source_path)
    : m_ResolvedTree{std::move(resolved_tree)}, m_Builder{m_Context} {
  auto module = std::make_unique<llvm::Module>("<tu>", m_Context);
  m_Module = std::make_unique<GeneratedModule>();
  m_Module->module = std::move(module);
  m_Module->module->setSourceFileName(source_path);
  m_Module->module->setTargetTriple("x86-64");
  if (m_ShouldGenDebug) {
    m_Module->di_builder = std::make_unique<llvm::DIBuilder>(*m_Module->module);
    m_Module->debug_info = std::make_unique<DebugInfo>();
    std::filesystem::path path{source_path};
    m_Module->debug_info->file = m_Module->di_builder->createFile(path.filename().string(), path.parent_path().string());
    m_Module->debug_info->cu = m_Module->di_builder->createCompileUnit(llvm::dwarf::DW_LANG_C, m_Module->debug_info->file, "saplang compiler", false, "", 0);
  }
}

Codegen::Codegen(std::vector<std::unique_ptr<ResolvedModule>> resolved_modules, std::unordered_map<std::string, TypeInfo> type_infos, bool should_gen_dbg)
    : m_ResolvedModules{std::move(resolved_modules)}, m_Builder{m_Context}, m_TypeInfos(std::move(type_infos)), m_ShouldGenDebug(should_gen_dbg) {}

std::unique_ptr<llvm::Module> Codegen::generate_ir() {
  for (auto &&decl : m_ResolvedTree) {
    if (const auto *func = dynamic_cast<const ResolvedFuncDecl *>(decl.get()))
      gen_func_decl(*func, *m_Module);
    else if (const auto *struct_decl = dynamic_cast<const ResolvedStructDecl *>(decl.get()))
      gen_struct_decl(*struct_decl, *m_Module);
    else if (const auto *global_var_decl = dynamic_cast<const ResolvedVarDecl *>(decl.get()))
      gen_global_var_decl(*global_var_decl, *m_Module);
  }
  for (auto &&decl : m_ResolvedTree) {
    if (const auto *func = dynamic_cast<const ResolvedFuncDecl *>(decl.get()))
      gen_func_body(*func, *m_Module);
  }

  return std::move(m_Module->module);
}

std::unordered_map<std::string, std::unique_ptr<GeneratedModule>> Codegen::generate_modules() {
  struct GenStructResult {
    const ResolvedStructDecl *decl;
    bool resolved{false};
  };
  m_Modules.reserve(m_ResolvedModules.size());
  for (auto &&mod : m_ResolvedModules) {
    if (m_Modules.count(mod->name))
      continue;
    std::unique_ptr<llvm::Module> module = std::make_unique<llvm::Module>(mod->name, m_Context);
    module->setSourceFileName(mod->name);
    module->setModuleIdentifier(mod->name);
    module->setTargetTriple("x86-64");
    std::unique_ptr<GeneratedModule> current_module = std::make_unique<GeneratedModule>();
    current_module->module = std::move(module);
    if (m_ShouldGenDebug) {
      current_module->module->addModuleFlag(llvm::Module::Warning, "Debug Info Version", llvm::DEBUG_METADATA_VERSION);
      if (llvm::Triple(llvm::sys::getProcessTriple()).isOSDarwin()) {
        current_module->module->addModuleFlag(llvm::Module::Warning, "Dwarf Version", 2);
      }
      current_module->di_builder = std::make_unique<llvm::DIBuilder>(*current_module->module);
      current_module->debug_info = std::make_unique<DebugInfo>();
      auto abs_path = std::filesystem::absolute(mod->path);
      current_module->debug_info->file = current_module->di_builder->createFile(abs_path.filename().string(), abs_path.parent_path().string());
      current_module->debug_info->cu =
          current_module->di_builder->createCompileUnit(llvm::dwarf::DW_LANG_C, current_module->debug_info->file, "saplang compiler", false, "", 0);
    }
    std::vector<GenStructResult> non_leaf_structs;
    for (auto &&decl : mod->declarations) {
      if (const auto *func = dynamic_cast<const ResolvedFuncDecl *>(decl.get()))
        gen_func_decl(*func, *current_module);
      else if (const auto *struct_decl = dynamic_cast<const ResolvedStructDecl *>(decl.get())) {
        if (!struct_decl->is_leaf) {
          non_leaf_structs.push_back({struct_decl});
          continue;
        }
        gen_struct_decl(*struct_decl, *current_module);
      } else if (const auto *global_var_decl = dynamic_cast<const ResolvedVarDecl *>(decl.get()))
        gen_global_var_decl(*global_var_decl, *current_module);
    }
    bool decl_resolved_last_pass = true;
    while (decl_resolved_last_pass) {
      decl_resolved_last_pass = false;
      for (auto &&struct_decl_res : non_leaf_structs) {
        struct_decl_res.resolved = gen_struct_decl(*struct_decl_res.decl, *current_module);
        decl_resolved_last_pass |= struct_decl_res.resolved;
      }
      for (auto it = non_leaf_structs.begin(); it != non_leaf_structs.end();) {
        if (it->resolved) {
          non_leaf_structs.erase(it);
          --it;
        }
        ++it;
      }
    }
    m_Modules[mod->name] = std::move(current_module);
  }
  for (auto &&mod : m_ResolvedModules) {
    for (auto &&decl : mod->declarations) {
      if (const auto *func = dynamic_cast<const ResolvedFuncDecl *>(decl.get()))
        gen_func_body(*func, *m_Modules[mod->name]);
    }
  }
  return std::move(m_Modules);
}

llvm::DISubroutineType *Codegen::gen_debug_function_type(GeneratedModule &mod, const Type &ret_type,
                                                         const std::vector<std::unique_ptr<ResolvedParamDecl>> &args) {
  if (!m_ShouldGenDebug) {
    return nullptr;
  }
  std::vector<llvm::Metadata *> metadata;
  metadata.reserve(args.size() + 1);
  llvm::DIType *dbg_ret_type = gen_debug_type(ret_type, mod);
  metadata.push_back(dbg_ret_type);
  for (auto &&arg : args) {
    llvm::DIType *dbg_arg_type = gen_debug_type(arg->type, mod);
    metadata.push_back(dbg_arg_type);
  }
  auto &di_builder = mod.di_builder;
  return di_builder->createSubroutineType(di_builder->getOrCreateTypeArray(metadata));
}

void Codegen::gen_func_decl(const ResolvedFuncDecl &decl, GeneratedModule &mod) {
  llvm::Type *return_type = gen_type(decl.type, mod);
  assert(return_type);
  std::vector<llvm::Type *> param_types{};
  for (auto &&param : decl.params) {
    param_types.emplace_back(gen_type(param->type, mod));
  }
  auto *type = llvm::FunctionType::get(return_type, param_types, decl.is_vla);
  const std::string &fn_name = decl.og_name.empty() ? decl.id : decl.og_name;
  llvm::Function *current_function = llvm::Function::Create(type, llvm::Function::ExternalLinkage, fn_name, *mod.module);
  assert(current_function);
  emit_debug_location(decl.location, mod);
  if (m_ShouldGenDebug) {
    std::filesystem::path filepath = std::filesystem::absolute(decl.location.path);
    llvm::DIFile *unit = mod.di_builder->createFile(filepath.filename().string(), filepath.parent_path().string(), std::nullopt, filepath.string());
    llvm::DIScope *fn_context = unit;
    unsigned scope_line = 0;
    auto flags = llvm::DISubprogram::DISPFlags::SPFlagZero;
    auto node_type = llvm::DINode::FlagZero;
    if (decl.body) {
      flags |= llvm::DISubprogram::DISPFlags::SPFlagDefinition;
      node_type = llvm::DINode::FlagPrototyped;
    } else {
      node_type = llvm::DINode::FlagFwdDecl;
    }
    llvm::DISubprogram *subprogram = mod.di_builder->createFunction(fn_context, fn_name, fn_name, unit, decl.location.line,
                                                                    gen_debug_function_type(mod, decl.type, decl.params), scope_line, node_type, flags);
    current_function->setSubprogram(subprogram);
    mod.debug_info->lexical_blocks.push_back(subprogram);
    // unset location for prologue emission
    m_Builder.SetCurrentDebugLocation(llvm::DebugLoc());
  }
  llvm::Value *value = current_function;
  assert(value);
  m_Declarations[mod.module->getName().str()][&decl] = value;
}

void Codegen::gen_global_var_decl(const ResolvedVarDecl &decl, GeneratedModule &mod) {
  llvm::Type *var_type = gen_type(decl.type, mod);
  assert(var_type);
  llvm::Constant *var_init = nullptr;
  if (const auto *numlit = dynamic_cast<const ResolvedNumberLiteral *>(decl.initializer.get())) {
    var_init = get_constant_number_value(*numlit, mod);
  } else if (const auto *struct_init = dynamic_cast<const ResolvedStructLiteralExpr *>(decl.initializer.get())) {
    var_init = gen_global_struct_init(*struct_init, mod);
  } else if (const auto *nullexpr = dynamic_cast<const ResolvedNullExpr *>(decl.initializer.get())) {
    llvm::Type *type = gen_type(nullexpr->type, mod);
    llvm::PointerType *ptr_type = llvm::PointerType::get(type, 0);
    var_init = llvm::ConstantPointerNull::get(ptr_type);
  } else if (const auto *array_lit = dynamic_cast<const ResolvedArrayLiteralExpr *>(decl.initializer.get())) {
    var_init = gen_global_array_init(*array_lit, mod);
  }
  // If var_init == nullptr there's an error in sema
  assert(var_init && "unexpected global variable type");
  llvm::GlobalVariable *global_var = new llvm::GlobalVariable(*mod.module, var_type, decl.is_const, llvm::GlobalVariable::ExternalLinkage, var_init, decl.id);
  m_Declarations[mod.module->getName().str()][&decl] = global_var;
}

void Codegen::emit_debug_location(const SourceLocation &loc, GeneratedModule &mod) {
  if (m_ShouldGenDebug) {
    llvm::DIScope *scope = nullptr;
    if (mod.debug_info->lexical_blocks.empty())
      scope = mod.debug_info->cu;
    else
      scope = mod.debug_info->lexical_blocks.back();
    m_Builder.SetCurrentDebugLocation(llvm::DILocation::get(scope->getContext(), loc.line, loc.col, scope));
  }
}

llvm::Constant *Codegen::gen_global_struct_init(const ResolvedStructLiteralExpr &init, GeneratedModule &mod) {
  llvm::StructType *struct_type = llvm::StructType::getTypeByName(m_Context, init.type.name);
  assert(struct_type);
  if (!struct_type)
    return report(init.location, "could not find struct type with name '" + init.type.name + "'.");
  std::vector<llvm::Constant *> constants{};
  constants.reserve(init.field_initializers.size());
  for (auto &&[name, expr] : init.field_initializers) {
    if (const auto *numlit = dynamic_cast<const ResolvedNumberLiteral *>(expr.get())) {
      constants.emplace_back(get_constant_number_value(*numlit, mod));
    } else if (const auto *struct_lit = dynamic_cast<const ResolvedStructLiteralExpr *>(expr.get())) {
      constants.emplace_back(gen_global_struct_init(*struct_lit, mod));
    } else if (const auto *array_lit = dynamic_cast<const ResolvedArrayLiteralExpr *>(expr.get()))
      constants.emplace_back(gen_global_array_init(*array_lit, mod));
  }
  return llvm::ConstantStruct::get(struct_type, constants);
}

llvm::Constant *Codegen::gen_global_array_init(const ResolvedArrayLiteralExpr &init, GeneratedModule &mod) {
  llvm::ArrayType *type = nullptr;
  if (init.type.array_data) {
    const auto &array_data = *init.type.array_data;
    Type de_arrayed_type = init.type;
    int dimension = de_array_type(de_arrayed_type, 1);
    llvm::Type *underlying_type = gen_type(de_arrayed_type, mod);
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
    if (const auto *numlit = dynamic_cast<const ResolvedNumberLiteral *>(expr.get())) {
      constants.emplace_back(get_constant_number_value(*numlit, mod));
    } else if (const auto *struct_lit = dynamic_cast<const ResolvedStructLiteralExpr *>(expr.get())) {
      constants.emplace_back(gen_global_struct_init(*struct_lit, mod));
    } else if (const auto *array_lit = dynamic_cast<const ResolvedArrayLiteralExpr *>(expr.get()))
      constants.emplace_back(gen_global_array_init(*array_lit, mod));
  }
  return llvm::ConstantArray::get(type, constants);
}

llvm::Constant *Codegen::get_constant_number_value(const ResolvedNumberLiteral &numlit, GeneratedModule &mod) {
  auto *type = gen_type(numlit.type, mod);
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

bool Codegen::gen_struct_decl(const ResolvedStructDecl &decl, GeneratedModule &mod) {
  std::vector<llvm::Type *> member_types{};
  for (auto &&[type, name] : decl.members) {
    auto *gened_type = gen_type(type, mod);
    if (!gened_type)
      return false;
    assert(gened_type);
    member_types.emplace_back(gened_type);
  }
  llvm::ArrayRef<llvm::Type *> array_ref{member_types};
  llvm::StructType *struct_type = llvm::StructType::create(m_Context, array_ref, decl.id);
  assert(struct_type);
  m_CustomTypes[decl.id] = struct_type;
  return true;
}

void Codegen::gen_func_body(const ResolvedFuncDecl &decl, GeneratedModule &mod) {
  if (!decl.body)
    return;
  auto *function = mod.module->getFunction(decl.id);
  assert(function);
  auto *entry_bb = llvm::BasicBlock::Create(m_Context, "entry", function);
  assert(entry_bb);
  m_Builder.SetInsertPoint(entry_bb);
  const std::string &fn_name = decl.og_name.empty() ? decl.id : decl.og_name;
  llvm::DIFile *unit = nullptr;
  llvm::DISubprogram *subprogram = nullptr;
  emit_debug_location(decl.location, mod);
  if (m_ShouldGenDebug) {
    unit = mod.di_builder->createFile(mod.debug_info->cu->getFilename(), mod.debug_info->cu->getDirectory());
    llvm::DIScope *fn_context = unit;
    unsigned scope_line = 0;
    auto flags = llvm::DISubprogram::SPFlagDefinition;
    if (decl.module == mod.module->getName())
      flags |= llvm::DISubprogram::SPFlagLocalToUnit;
    auto node_type = llvm::DINode::FlagPrototyped;
    subprogram = mod.di_builder->createFunction(fn_context, fn_name, llvm::StringRef(), unit, decl.location.line,
                                                gen_debug_function_type(mod, decl.type, decl.params), scope_line, node_type, flags);
    function->setSubprogram(subprogram);
    mod.debug_info->lexical_blocks.push_back(subprogram);
    assert(subprogram);
    function->setSubprogram(subprogram);
    mod.debug_info->lexical_blocks.push_back(subprogram);
    // unset location for prologue emission
    m_Builder.SetCurrentDebugLocation(llvm::DebugLoc());
  }
  llvm::Value *undef = llvm::UndefValue::get(m_Builder.getInt32Ty());
  assert(undef);
  m_AllocationInsertPoint = new llvm::BitCastInst(undef, undef->getType(), "alloca.placeholder", entry_bb);
  assert(m_AllocationInsertPoint);
  m_CurrentFunction.return_type = gen_type(decl.type, mod);
  assert(m_CurrentFunction.return_type);
  m_CurrentFunction.is_void = decl.type.kind == Type::Kind::Void;
  if (!m_CurrentFunction.is_void) {
    m_CurrentFunction.return_value = alloc_stack_var(function, m_CurrentFunction.return_type, "retval");
  }
  m_CurrentFunction.return_bb = llvm::BasicBlock::Create(m_Context, "return");
  assert(m_CurrentFunction.return_bb);
  int idx = 0;
  for (auto &&arg : function->args()) {
    const auto *param_decl = decl.params[idx].get();
    assert(param_decl);
    auto *type = gen_type(decl.params[idx]->type, mod);
    assert(type);
    arg.setName(param_decl->id);
    llvm::Value *var = alloc_stack_var(function, type, param_decl->id);
    assert(var);
    if (m_ShouldGenDebug) {
      llvm::DILocalVariable *dbg_var_info =
          mod.di_builder->createParameterVariable(subprogram, arg.getName(), idx, unit, decl.location.line, gen_debug_type(decl.params[idx]->type, mod));
      auto *call =
          mod.di_builder->insertDeclare(var, dbg_var_info, mod.di_builder->createExpression(),
                                        llvm::DILocation::get(subprogram->getContext(), decl.location.line, 0, subprogram), m_Builder.GetInsertBlock());
      // @NOTE @DEBUG: potentially
      /* call->setDebugLoc(llvm::DILocation::get(subprogram->getContext(), decl.location.line, 0, subprogram)); */
    }
    m_Builder.CreateStore(&arg, var);
    m_Declarations[mod.module->getName().str()][param_decl] = var;
    ++idx;
  }
  gen_block(*decl.body, mod);
  if (m_CurrentFunction.return_bb->hasNPredecessorsOrMore(1)) {
    m_Builder.CreateBr(m_CurrentFunction.return_bb);
    m_CurrentFunction.return_bb->insertInto(function);
    m_Builder.SetInsertPoint(m_CurrentFunction.return_bb);
  }
  m_AllocationInsertPoint->eraseFromParent();
  m_AllocationInsertPoint = nullptr;
  if (m_CurrentFunction.is_void) {
    m_Builder.CreateRetVoid();
    if (m_ShouldGenDebug) {
      mod.debug_info->lexical_blocks.pop_back();
    }
    return;
  }
  if (m_CurrentFunction.deferred_stmts.size() == 0) {
    llvm::Value *load_ret = m_Builder.CreateLoad(m_CurrentFunction.return_type, m_CurrentFunction.return_value);
    assert(load_ret);
    m_Builder.CreateRet(load_ret);
  }
  if (m_ShouldGenDebug) {
    mod.debug_info->lexical_blocks.pop_back();
  }
}

llvm::Type *Codegen::gen_type(const Type &type, GeneratedModule &mod) {
  if (type.array_data) {
    const auto &array_data = *type.array_data;
    Type de_arrayed_type = type;
    int dimension = de_array_type(de_arrayed_type, 1);
    llvm::Type *underlying_type = gen_type(de_arrayed_type, mod);
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

llvm::DIType *get_debug_type_from_llvm_type(const llvm::Type *type, GeneratedModule &mod, std::unordered_map<std::string, TypeInfo> &type_infos) {
  unsigned encoding = 0;
  std::string type_name;
  std::uint64_t size;
  if (type->isIntegerTy(8)) {
    encoding = llvm::dwarf::DW_ATE_unsigned_char;
    type_name = "char";
    size = 8;
  } else if (type->isIntegerTy(1)) {
    encoding = llvm::dwarf::DW_ATE_boolean;
    type_name = "bool";
    size = 1;
  } else if (type->isIntegerTy()) {
    encoding = llvm::dwarf::DW_ATE_signed;
    type_name = "int";
    size = 32;
  } else if (type->isPointerTy() || type->isVoidTy()) {
    encoding = llvm::dwarf::DW_ATE_address;
    type_name = "ptr";
    size = platform_ptr_size();
  } else if (type->isFloatTy() || type->isDoubleTy()) {
    encoding = llvm::dwarf::DW_ATE_float;
    type_name = "float";
    size = 32;
  } else if (type->isStructTy()) {
    std::vector<llvm::Metadata *> metadata;
    std::uint64_t offset = 0;
    const TypeInfo &type_info = type_infos[type->getStructName().str()];
    llvm::DIScope *scope = mod.debug_info->lexical_blocks.size() > 0 ? mod.debug_info->lexical_blocks.back() : mod.debug_info->cu;
    llvm::DIFile *file = mod.debug_info->file;
    for (int i = 0; i < type->getStructNumElements(); ++i) {
      llvm::Type *subtype = type->getStructElementType(i);
      llvm::DIType *di_type = get_debug_type_from_llvm_type(subtype, mod, type_infos);
      metadata.push_back(mod.di_builder->createMemberType(scope, type_info.field_names[i], file, i, type_info.field_sizes[i] * 8, di_type->getAlignInBits(),
                                                          offset, llvm::DINode::FlagZero, di_type));
      offset += type_info.field_sizes[i] * 8;
    }
    return mod.di_builder->createStructType(scope, type->getStructName(), file, 0, type_info.total_size * 8, type_info.alignment * 8, llvm::DINode::FlagZero,
                                            nullptr, mod.di_builder->getOrCreateArray(metadata));
  }
  assert(encoding != 0);
  auto *di_type = mod.di_builder->createBasicType(type_name, size, encoding);
  assert(di_type);
  return di_type;
}

llvm::DIType *Codegen::gen_debug_type(const Type &type, GeneratedModule &mod) {
  if (!m_ShouldGenDebug) {
    return nullptr;
  }
  if (type.array_data) {
    const auto &array_data = *type.array_data;
    Type de_arrayed_type = type;
    std::vector<llvm::Metadata *> metadata;
    metadata.reserve(type.array_data->dimension_count);
    int dimension = 0;
    for (int i = 0; i < type.array_data->dimension_count; ++i) {
      dimension = de_array_type(de_arrayed_type, 1);
      metadata.push_back(mod.di_builder->getOrCreateSubrange(0, dimension));
    }
    llvm::DIType *underlying_type = gen_debug_type(de_arrayed_type, mod);
    assert(underlying_type);
    if (!dimension)
      return underlying_type;
    return mod.di_builder->createArrayType(type.array_data->dimensions.back(), m_TypeInfos[type.name].alignment, underlying_type,
                                           mod.di_builder->getOrCreateArray(metadata));
  }
  if (type.pointer_depth) {
    Type tmp_type = type;
    --tmp_type.pointer_depth;
    llvm::DIType *pointee_type = gen_debug_type(tmp_type, mod);
    return mod.di_builder->createPointerType(pointee_type, platform_ptr_size());
  }
  unsigned encoding = 0;
  switch (type.kind) {
  case Type::Kind::u8:
    encoding = llvm::dwarf::DW_ATE_unsigned_char;
    break;
  case Type::Kind::i8:
    encoding = llvm::dwarf::DW_ATE_signed_char;
    break;
  case Type::Kind::i16:
  case Type::Kind::i32:
  case Type::Kind::i64:
    encoding = llvm::dwarf::DW_ATE_signed;
    break;
  case Type::Kind::u16:
  case Type::Kind::u32:
  case Type::Kind::u64:
    encoding = llvm::dwarf::DW_ATE_unsigned;
    break;
  case Type::Kind::f32:
  case Type::Kind::f64:
    encoding = llvm::dwarf::DW_ATE_float;
    break;
  case Type::Kind::Bool:
    encoding = llvm::dwarf::DW_ATE_boolean;
    break;
  case Type::Kind::Void:
  case Type::Kind::FnPtr:
    encoding = llvm::dwarf::DW_ATE_address;
    break;
  case Type::Kind::Custom: {
    std::vector<llvm::Metadata *> members;
    llvm::Type *struct_type = m_CustomTypes[type.name];
    return get_debug_type_from_llvm_type(struct_type, mod, m_TypeInfos);
  } break;
  }
  assert(encoding != 0);
  auto *di_type = mod.di_builder->createBasicType(type.name, get_type_size(type.kind), encoding);
  assert(di_type);
  return di_type;
}

llvm::AllocaInst *Codegen::alloc_stack_var(llvm::Function *func, llvm::Type *type, std::string_view id) {
  llvm::IRBuilder<> tmp_builder{m_Context};
  tmp_builder.SetInsertPoint(m_AllocationInsertPoint);
  return tmp_builder.CreateAlloca(type, nullptr, id);
}

void Codegen::gen_block(const ResolvedBlock &body, GeneratedModule &mod) {
  const ResolvedReturnStmt *last_ret_stmt = nullptr;
  for (auto &&stmt : body.statements) {
    if (const auto *defer_stmt = dynamic_cast<const ResolvedDeferStmt *>(stmt.get())) {
      m_CurrentFunction.deferred_stmts.push_back(defer_stmt);
    } else {
      gen_stmt(*stmt, mod);
    }
    // @TODO: defer statements
    // After a return statement we clear the insertion point, so that
    // no other instructions are inserted into the current block and break.
    // The break ensures that no other instruction is generated that will be
    // inserted regardless of there is no insertion point and crash (e.g.:
    // CreateStore, CreateLoad).
    if (auto *ret_stmt = dynamic_cast<const ResolvedReturnStmt *>(stmt.get())) {
      last_ret_stmt = ret_stmt;
      m_Builder.ClearInsertionPoint();
      break;
    }
  }
}

llvm::Value *Codegen::gen_stmt(const ResolvedStmt &stmt, GeneratedModule &mod) {
  emit_debug_location(stmt.location, mod);
  if (auto *assignment = dynamic_cast<const ResolvedAssignment *>(&stmt))
    return gen_assignment(*assignment, mod);
  if (auto *expr = dynamic_cast<const ResolvedExpr *>(&stmt)) {
    return gen_expr(*expr, mod);
  }
  if (auto *ifstmt = dynamic_cast<const ResolvedIfStmt *>(&stmt))
    return gen_if_stmt(*ifstmt, mod);
  if (auto *switchstmt = dynamic_cast<const ResolvedSwitchStmt *>(&stmt))
    return gen_switch_stmt(*switchstmt, mod);
  if (auto *whilestmt = dynamic_cast<const ResolvedWhileStmt *>(&stmt))
    return gen_while_stmt(*whilestmt, mod);
  if (auto *return_stmt = dynamic_cast<const ResolvedReturnStmt *>(&stmt))
    return gen_return_stmt(*return_stmt, mod);
  if (auto *decl_stmt = dynamic_cast<const ResolvedDeclStmt *>(&stmt))
    return gen_decl_stmt(*decl_stmt, mod);
  if (auto *for_stmt = dynamic_cast<const ResolvedForStmt *>(&stmt))
    return gen_for_stmt(*for_stmt, mod);
  llvm_unreachable("unknown statememt.");
  return nullptr;
}

llvm::Value *Codegen::gen_if_stmt(const ResolvedIfStmt &stmt, GeneratedModule &mod) {
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
  llvm::Value *cond = gen_expr(*stmt.condition, mod);
  assert(cond);
  // @TODO: this is pretty bad cuz string search
  if (cond->getName().find("to.is_null") == std::string::npos) {
    cond = type_to_bool(stmt.condition->type, cond);
  }
  m_Builder.CreateCondBr(cond, true_bb, else_bb);
  true_bb->insertInto(function);
  m_Builder.SetInsertPoint(true_bb);
  gen_block(*stmt.true_block, mod);
  m_Builder.CreateBr(exit_bb);
  if (stmt.false_block) {
    else_bb->insertInto(function);
    m_Builder.SetInsertPoint(else_bb);
    gen_block(*stmt.false_block, mod);
    m_Builder.CreateBr(exit_bb);
  }
  exit_bb->insertInto(function);
  m_Builder.SetInsertPoint(exit_bb);
  return nullptr;
}

llvm::Value *Codegen::gen_switch_stmt(const ResolvedSwitchStmt &stmt, GeneratedModule &mod) {
  llvm::Function *function = get_current_function();
  assert(function);
  llvm::BasicBlock *default_block = llvm::BasicBlock::Create(m_Context, "sw.default", function);
  assert(default_block);
  llvm::Value *switch_expr = gen_expr(*stmt.eval_expr, mod);
  assert(switch_expr);
  llvm::SwitchInst *switch_inst = m_Builder.CreateSwitch(switch_expr, default_block, stmt.blocks.size());
  std::vector<llvm::BasicBlock *> blocks;
  blocks.reserve(stmt.blocks.size());
  for (auto &&resolved_block : stmt.blocks) {
    llvm::BasicBlock *gened_block = llvm::BasicBlock::Create(m_Context, "sw.bb", function);
    assert(gened_block);
    m_Builder.SetInsertPoint(gened_block);
    gen_block(*resolved_block, mod);
    blocks.push_back(gened_block);
  }
  for (auto &&[expr, ind] : stmt.cases) {
    llvm::Constant *constant = get_constant_number_value(*expr, mod);
    assert(constant);
    llvm::ConstantInt *constant_int = llvm::dyn_cast<llvm::ConstantInt>(constant);
    assert(constant_int);
    switch_inst->addCase(constant_int, blocks[ind]);
  }
  m_Builder.SetInsertPoint(default_block);
  m_Builder.CreateBr(blocks[stmt.default_block_index]);
  // Easier to read LLVM-IR if the rest of the code is the last block of the switch
  llvm::BasicBlock *epilog = llvm::BasicBlock::Create(m_Context, "sw.epilog", function);
  assert(epilog);
  for (auto *block : blocks) {
    m_Builder.SetInsertPoint(block);
    m_Builder.CreateBr(epilog);
  }
  m_Builder.SetInsertPoint(epilog);
  return nullptr;
}

llvm::Value *Codegen::gen_while_stmt(const ResolvedWhileStmt &stmt, GeneratedModule &mod) {
  llvm::Function *function = get_current_function();
  assert(function);
  llvm::BasicBlock *header = llvm::BasicBlock::Create(m_Context, "while.cond", function);
  assert(header);
  llvm::BasicBlock *body = llvm::BasicBlock::Create(m_Context, "while.body", function);
  assert(body);
  llvm::BasicBlock *exit = llvm::BasicBlock::Create(m_Context, "while.exit", function);
  assert(exit);
  m_Builder.CreateBr(header);
  m_Builder.SetInsertPoint(header);
  llvm::Value *condition = gen_expr(*stmt.condition, mod);
  assert(condition);
  if (condition->getName().find("to.is_null") == std::string::npos) {
    condition = type_to_bool(stmt.condition->type, condition);
  }
  m_Builder.CreateCondBr(condition, body, exit);
  m_Builder.SetInsertPoint(body);
  gen_block(*stmt.body, mod);
  m_Builder.CreateBr(header);
  m_Builder.SetInsertPoint(exit);
  return nullptr;
}

llvm::Value *Codegen::gen_for_stmt(const ResolvedForStmt &stmt, GeneratedModule &mod) {
  llvm::Function *function = get_current_function();
  assert(function);
  llvm::BasicBlock *counter_decl = llvm::BasicBlock::Create(m_Context, "for.counter_decl", function);
  assert(counter_decl);
  llvm::BasicBlock *header = llvm::BasicBlock::Create(m_Context, "for.condition", function);
  assert(header);
  llvm::BasicBlock *body = llvm::BasicBlock::Create(m_Context, "for.body", function);
  assert(body);
  llvm::BasicBlock *counter_op = llvm::BasicBlock::Create(m_Context, "for.counter_op", function);
  assert(counter_op);
  llvm::BasicBlock *exit = llvm::BasicBlock::Create(m_Context, "for.exit", function);
  assert(exit);
  m_Builder.CreateBr(counter_decl);
  m_Builder.SetInsertPoint(counter_decl);
  llvm::Value *var_decl = gen_decl_stmt(*stmt.counter_variable, mod);
  m_Builder.CreateBr(header);
  m_Builder.SetInsertPoint(header);
  llvm::Value *condition = gen_expr(*stmt.condition, mod);
  assert(condition);
  if (condition->getName().find("to.is_null") == std::string::npos) {
    condition = type_to_bool(stmt.condition->type, condition);
  }
  m_Builder.CreateCondBr(condition, body, exit);
  m_Builder.SetInsertPoint(body);
  gen_block(*stmt.body, mod);
  m_Builder.CreateBr(counter_op);
  m_Builder.SetInsertPoint(counter_op);
  llvm::Value *counter_incr = gen_stmt(*stmt.increment_expr, mod);
  assert(counter_incr);
  m_Builder.CreateBr(header);
  m_Builder.SetInsertPoint(exit);
  return nullptr;
}

llvm::Value *Codegen::gen_return_stmt(const ResolvedReturnStmt &stmt, GeneratedModule &mod) {
  bool defer_present = false;
  for (auto &&rit = m_CurrentFunction.deferred_stmts.rbegin(); rit != m_CurrentFunction.deferred_stmts.rend(); ++rit) {
    defer_present = true;
    gen_block(*(*rit)->block, mod);
  }
  if (stmt.expr)
    m_Builder.CreateStore(gen_expr(*stmt.expr, mod), m_CurrentFunction.return_value);
  if (!defer_present) {
    assert(m_CurrentFunction.return_bb && "function with return stmt doesn't have a return block");
    return m_Builder.CreateBr(m_CurrentFunction.return_bb);
  }
  if (m_CurrentFunction.is_void) {
    if (m_ShouldGenDebug)
      mod.debug_info->lexical_blocks.pop_back();
    return m_Builder.CreateRetVoid();
  }
  llvm::Value *load_ret = m_Builder.CreateLoad(m_CurrentFunction.return_type, m_CurrentFunction.return_value);
  assert(load_ret);
  if (m_ShouldGenDebug)
    mod.debug_info->lexical_blocks.pop_back();
  return m_Builder.CreateRet(load_ret);
}

enum class SimpleNumType { SINT, UINT, FLOAT };
SimpleNumType get_simple_type(Type::Kind type) {
  if ((type >= Type::Kind::u8 && type <= Type::Kind::u64) || type == Type::Kind::Bool) {
    return SimpleNumType::UINT;
  } else if (type >= Type::Kind::i8 && type <= Type::Kind::i64) {
    return SimpleNumType::SINT;
  } else if (type >= Type::Kind::f32 && type <= Type::Kind::f64) {
    return SimpleNumType::FLOAT;
  }
  llvm_unreachable("unexpected type.");
}

llvm::Instruction::BinaryOps get_math_binop_kind(TokenKind op, Type::Kind type) {
  SimpleNumType simple_type = get_simple_type(type);
  if (op == TokenKind::Plus) {
    if (simple_type == SimpleNumType::SINT || simple_type == SimpleNumType::UINT) {
      return llvm::BinaryOperator::Add;
    } else if (simple_type == SimpleNumType::FLOAT) {
      return llvm::BinaryOperator::FAdd;
    }
  }
  if (op == TokenKind::Minus) {
    if (simple_type == SimpleNumType::SINT || simple_type == SimpleNumType::UINT) {
      return llvm::BinaryOperator::Sub;
    } else if (simple_type == SimpleNumType::FLOAT) {
      return llvm::BinaryOperator::FSub;
    }
  }
  if (op == TokenKind::Asterisk) {
    if (simple_type == SimpleNumType::SINT || simple_type == SimpleNumType::UINT) {
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

llvm::Value *Codegen::gen_expr(const ResolvedExpr &expr, GeneratedModule &mod) {
  if (auto *number = dynamic_cast<const ResolvedNumberLiteral *>(&expr)) {
    return get_constant_number_value(*number, mod);
  }
  if (const auto *dre = dynamic_cast<const ResolvedDeclRefExpr *>(&expr)) {
    llvm::Value *decl = m_Declarations[mod.module->getName().str()][dre->decl];
    assert(decl);
    auto *type = gen_type(dre->type, mod);
    assert(type);
    if (auto *member_access = dynamic_cast<const ResolvedStructMemberAccess *>(dre)) {
      Type member_type = Type::builtin_void(false);
      decl = gen_struct_member_access(*member_access, member_type, mod);
      type = gen_type(member_type, mod);
      assert(type);
    } else if (auto *array_access = dynamic_cast<const ResolvedArrayElementAccess *>(dre)) {
      Type underlying_type = Type::builtin_void(false);
      decl = gen_array_element_access(*array_access, underlying_type, mod);
      assert(decl);
      type = gen_type(underlying_type, mod);
      assert(type);
    }
    return m_Builder.CreateLoad(type, decl);
  }
  if (const auto *call = dynamic_cast<const ResolvedCallExpr *>(&expr))
    return gen_call_expr(*call, mod);
  if (const auto *struct_lit = dynamic_cast<const ResolvedStructLiteralExpr *>(&expr))
    return gen_struct_literal_expr(*struct_lit, mod);
  if (const auto *group = dynamic_cast<const ResolvedGroupingExpr *>(&expr))
    return gen_expr(*group->expr, mod);
  if (const auto *binop = dynamic_cast<const ResolvedBinaryOperator *>(&expr))
    return gen_binary_op(*binop, mod);
  if (const auto *unop = dynamic_cast<const ResolvedUnaryOperator *>(&expr)) {
    auto &&[res, type] = gen_unary_op(*unop, mod);
    return res;
  }
  if (const auto *nullexpr = dynamic_cast<const ResolvedNullExpr *>(&expr)) {
    llvm::Type *type = gen_type(nullexpr->type, mod);
    assert(type);
    llvm::PointerType *ptr_type = llvm::PointerType::get(type, 0);
    assert(ptr_type);
    return llvm::ConstantPointerNull::get(ptr_type);
  }
  if (const auto *cast = dynamic_cast<const ResolvedExplicitCastExpr *>(&expr))
    return gen_explicit_cast(*cast, mod);
  if (const auto *str = dynamic_cast<const ResolvedStringLiteralExpr *>(&expr))
    return gen_string_literal_expr(*str, mod);
  llvm_unreachable("unknown expression");
  return nullptr;
}

llvm::Value *Codegen::gen_struct_literal_expr_assignment(const ResolvedStructLiteralExpr &struct_lit, llvm::Value *var, GeneratedModule &mod) {
  // @TODO: if fully const just memset or memcpy directly to variable
  int index = -1;
  for (auto &&[field_name, expr] : struct_lit.field_initializers) {
    ++index;
    if (!expr)
      continue;
    llvm::Value *gened_expr = nullptr;
    std::vector<llvm::Value *> indices{llvm::ConstantInt::get(m_Context, llvm::APInt(static_cast<unsigned>(platform_ptr_size()), 0)),
                                       llvm::ConstantInt::get(m_Context, llvm::APInt(static_cast<unsigned>(platform_ptr_size()), index))};
    auto *type = gen_type(struct_lit.type, mod);
    assert(type);
    llvm::Value *memptr = m_Builder.CreateInBoundsGEP(type, var, indices);
    assert(memptr);
    if (const auto *struct_lit = dynamic_cast<const ResolvedStructLiteralExpr *>(expr.get())) {
      gened_expr = gen_struct_literal_expr_assignment(*struct_lit, memptr, mod);
    } else if (const auto *unary_op = dynamic_cast<const ResolvedUnaryOperator *>(expr.get()); unary_op && (unary_op->op == TokenKind::Amp)) {
      if (const auto *dre = dynamic_cast<ResolvedDeclRefExpr *>(unary_op->rhs.get())) {
        if (unary_op->op == TokenKind::Amp) {
          llvm::Value *expr = m_Declarations[mod.module->getName().str()][dre->decl];
          assert(expr);
          m_Builder.CreateStore(expr, memptr);
        }
      }
    } else {
      gened_expr = gen_expr(*expr, mod);
    }
    if (gened_expr && memptr && gened_expr != memptr)
      m_Builder.CreateStore(gened_expr, memptr);
  }
  return var;
}

llvm::Value *Codegen::gen_struct_literal_expr(const ResolvedStructLiteralExpr &struct_lit, GeneratedModule &mod) {
  // @TODO: if fully const just memset or memcpy directly to variable
  llvm::Function *current_function = get_current_function();
  assert(current_function);
  llvm::Value *stack_var = alloc_stack_var(current_function, gen_type(struct_lit.type, mod), "");
  assert(stack_var);
  int index = -1;
  for (auto &&[field_name, expr] : struct_lit.field_initializers) {
    ++index;
    if (!expr)
      continue;
    llvm::Value *gened_expr = gen_expr(*expr, mod);
    assert(gened_expr);
    std::vector<llvm::Value *> indices{llvm::ConstantInt::get(m_Context, llvm::APInt(static_cast<unsigned>(platform_ptr_size()), 0)),
                                       llvm::ConstantInt::get(m_Context, llvm::APInt(static_cast<unsigned>(platform_ptr_size()), index))};
    llvm::Value *memptr = m_Builder.CreateInBoundsGEP(gen_type(struct_lit.type, mod), stack_var, indices);
    assert(memptr);
    m_Builder.CreateStore(gened_expr, memptr);
  }
  return stack_var;
}

llvm::Value *Codegen::gen_array_literal_expr(const ResolvedArrayLiteralExpr &array_lit, llvm::Value *p_array_value, GeneratedModule &mod) {
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
    std::vector<llvm::Value *> indices{llvm::ConstantInt::get(m_Context, llvm::APInt(static_cast<unsigned>(platform_array_index_size()), 0)),
                                       llvm::ConstantInt::get(m_Context, llvm::APInt(static_cast<unsigned>(platform_array_index_size()), 0))};
    auto *p_array_type = gen_type(array_lit.type, mod);
    assert(p_array_type);
    llvm::Value *p_array_element = m_Builder.CreateInBoundsGEP(p_array_type, p_array_value, indices, "arrayinit.begin");
    assert(p_array_element);
    if (const auto *inner_array = dynamic_cast<const ResolvedArrayLiteralExpr *>(array_lit.expressions[0].get())) {
      gen_array_literal_expr(*inner_array, p_array_element, mod);
    } else {
      llvm::Value *expr_val = gen_expr(*array_lit.expressions[0], mod);
      assert(expr_val);
      m_Builder.CreateStore(expr_val, p_array_element);
    }
    for (int i = 1; i < array_lit.expressions.size(); ++i) {
      auto &expr = array_lit.expressions[i];
      std::vector<llvm::Value *> indices{llvm::ConstantInt::get(m_Context, llvm::APInt(static_cast<unsigned>(platform_array_index_size()), 1))};
      p_array_element = m_Builder.CreateInBoundsGEP(gen_type(expr->type, mod), p_array_element, indices, "arrayinit.element");
      assert(p_array_element);
      if (const auto *inner_array = dynamic_cast<const ResolvedArrayLiteralExpr *>(array_lit.expressions[i].get())) {
        gen_array_literal_expr(*inner_array, p_array_element, mod);
      } else {
        llvm::Value *expr_val = gen_expr(*expr, mod);
        assert(expr_val);
        m_Builder.CreateStore(expr_val, p_array_element);
      }
    }
  }
  return nullptr;
}

llvm::Value *Codegen::gen_string_literal_expr(const ResolvedStringLiteralExpr &str_lit, GeneratedModule &) {
  std::string reparsed_string;
  for (int i = 0; i < str_lit.val.size(); ++i) {
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

llvm::Value *Codegen::gen_struct_member_access(const ResolvedStructMemberAccess &access, Type &out_type, GeneratedModule &mod) {
  if (!access.inner_member_access)
    return nullptr;
  llvm::Function *current_function = get_current_function();
  assert(current_function);
  llvm::Value *decl = m_Declarations[mod.module->getName().str()][access.decl];
  if (!decl)
    return report(access.location, "unknown declaration '" + access.decl->id + "'.");
  Type access_decl_type = access.decl->type;
  if (access_decl_type.pointer_depth > 0) {
    decl = m_Builder.CreateLoad(gen_type(access_decl_type, mod), decl);
    --access_decl_type.pointer_depth;
  }
  std::vector<llvm::Value *> outer_indices{
      llvm::ConstantInt::get(m_Context, llvm::APInt(static_cast<unsigned>(platform_ptr_size()), 0)),
      llvm::ConstantInt::get(m_Context, llvm::APInt(static_cast<unsigned>(platform_ptr_size()), access.inner_member_access->member_index))};
  llvm::Type *last_gep_type = gen_type(access_decl_type, mod);
  assert(last_gep_type);
  llvm::Value *last_gep = m_Builder.CreateInBoundsGEP(last_gep_type, decl, outer_indices);
  llvm::Value *tmp_gep = last_gep;
  assert(last_gep);
  if (access.params && access.inner_member_access->type.kind == Type::Kind::FnPtr) {
    llvm::Type *function_ret_type = gen_type(access.inner_member_access->type.fn_ptr_signature->first[0], mod);
    assert(function_ret_type);
    bool is_vla = access.inner_member_access->type.fn_ptr_signature->second;
    auto *function_type = llvm::FunctionType::get(function_ret_type, is_vla);
    assert(function_type);
    llvm::Value *loaded_fn = m_Builder.CreateLoad(m_Builder.getPtrTy(), last_gep);
    assert(loaded_fn);
    std::vector<llvm::Value *> args;
    for (auto &&res_arg : *access.params) {
      llvm::Value *arg = gen_expr(*res_arg, mod);
      assert(arg);
      args.push_back(arg);
    }
    last_gep = m_Builder.CreateCall(function_type, loaded_fn, args);
    auto &return_type = access.inner_member_access->type.fn_ptr_signature->first[0];
    // @NOTE: At this point might be worthwile to return after assigning
    // out_type to return_type, but at this point returning nullptr will
    // segfault, and not properly handling it in gen_expr results in an extra
    // load that is unused. I hope LLVM optimizations take care of it but this
    // will need a refactor.
    if (return_type.kind == Type::Kind::Void && return_type.pointer_depth < 1)
      last_gep = tmp_gep;
  }
  out_type = access.inner_member_access->type;
  if (access.inner_member_access->inner_member_access) {
    InnerMemberAccess *current_chain = access.inner_member_access->inner_member_access.get();
    InnerMemberAccess *prev_chain = access.inner_member_access.get();
    while (current_chain) {
      std::vector<llvm::Value *> inner_indices{
          llvm::ConstantInt::get(m_Context, llvm::APInt(static_cast<unsigned>(platform_ptr_size()), 0)),
          llvm::ConstantInt::get(m_Context, llvm::APInt(static_cast<unsigned>(platform_ptr_size()), current_chain->member_index))};
      out_type = current_chain->type;
      Type tmp_type = prev_chain->type;
      if (tmp_type.pointer_depth > 0 && current_chain->type.kind != Type::Kind::FnPtr) {
        last_gep = m_Builder.CreateLoad(gen_type(tmp_type, mod), last_gep);
        --tmp_type.pointer_depth;
      }
      auto *type = gen_type(tmp_type, mod);
      assert(type);
      last_gep = m_Builder.CreateInBoundsGEP(type, last_gep, inner_indices);
      assert(last_gep);
      tmp_gep = last_gep;
      if (current_chain->params && current_chain->type.kind == Type::Kind::FnPtr) {
        out_type = current_chain->type.fn_ptr_signature->first[0];
        Type tmp_type = prev_chain->type.fn_ptr_signature->first[0];
        if (tmp_type.pointer_depth > 0) {
          last_gep = m_Builder.CreateLoad(gen_type(tmp_type, mod), last_gep);
          --tmp_type.pointer_depth;
        }
        llvm::Type *function_ret_type = gen_type(current_chain->type.fn_ptr_signature->first[0], mod);
        assert(function_ret_type);
        bool is_vla = current_chain->type.fn_ptr_signature->second;
        auto *function_type = llvm::FunctionType::get(function_ret_type, is_vla);
        assert(function_type);
        std::vector<llvm::Value *> args;
        for (auto &&res_arg : *current_chain->params) {
          llvm::Value *arg = gen_expr(*res_arg, mod);
          assert(arg);
          args.push_back(arg);
        }
        last_gep = m_Builder.CreateCall(function_type, last_gep, args);
        auto &return_type = current_chain->type.fn_ptr_signature->first[0];
        if (return_type.kind == Type::Kind::Void && return_type.pointer_depth < 1)
          last_gep = tmp_gep;
      }
      assert(last_gep);
      prev_chain = current_chain;
      current_chain = current_chain->inner_member_access.get();
    }
  }
  return last_gep;
}

std::vector<llvm::Value *> Codegen::get_index_accesses(const ResolvedExpr &expr, llvm::Value *loaded_ptr, GeneratedModule &mod) {
  std::vector<llvm::Value *> inner_indices{};
  std::optional<ConstexprResult> constexpr_res = expr.get_constant_value();
  if (constexpr_res) {
    const ConstexprResult &res = *constexpr_res;
    llvm::APInt index{static_cast<unsigned int>(platform_array_index_size()), 0};
    switch (res.kind) {
    case Type::Kind::i8:
      index = {static_cast<unsigned int>(platform_array_index_size()), static_cast<uint64_t>(res.value.i8)};
      break;
    case Type::Kind::u8:
      index = {static_cast<unsigned int>(platform_array_index_size()), res.value.u8};
      break;
    case Type::Kind::i16:
      index = {static_cast<unsigned int>(platform_array_index_size()), static_cast<uint64_t>(res.value.i16)};
      break;
    case Type::Kind::u16:
      index = {static_cast<unsigned int>(platform_array_index_size()), res.value.u16};
      break;
    case Type::Kind::i32:
      index = {static_cast<unsigned int>(platform_array_index_size()), static_cast<uint64_t>(res.value.i32)};
      break;
    case Type::Kind::u32:
      index = {static_cast<unsigned int>(platform_array_index_size()), res.value.u32};
      break;
    case Type::Kind::i64:
      index = {static_cast<unsigned int>(platform_array_index_size()), static_cast<uint64_t>(res.value.i64)};
      break;
    case Type::Kind::u64:
      index = {static_cast<unsigned int>(platform_array_index_size()), res.value.u64};
      break;
    case Type::Kind::Bool:
      index = {static_cast<unsigned int>(platform_array_index_size()), res.value.b8};
      break;
    default:
      break;
    }
    if (loaded_ptr) {
      inner_indices = {llvm::ConstantInt::get(m_Context, index)};
    } else {
      inner_indices = {llvm::ConstantInt::get(m_Context, llvm::APInt(static_cast<unsigned int>(platform_array_index_size()), 0)),
                       llvm::ConstantInt::get(m_Context, index)};
    }
  } else {
    llvm::Value *expr_value = gen_expr(expr, mod);
    if (get_type_size(expr.type.kind) < platform_array_index_size()) { // extent
      expr_value = m_Builder.CreateSExt(expr_value, gen_type(platform_ptr_type(), mod), "idxprom");
    } else if (get_type_size(expr.type.kind) > platform_array_index_size()) { // trunc
      expr_value = m_Builder.CreateTrunc(expr_value, gen_type(platform_ptr_type(), mod), "idxtrunc");
    }
    if (loaded_ptr) {
      inner_indices = {expr_value};
    } else {
      inner_indices = {llvm::ConstantInt::get(m_Context, llvm::APInt(static_cast<unsigned int>(platform_array_index_size()), 0)), expr_value};
    }
  }
  return std::move(inner_indices);
}

llvm::Value *Codegen::gen_array_element_access(const ResolvedArrayElementAccess &access, Type &out_type, GeneratedModule &mod) {
  assert(access.indices.size() >= 1 && "unknown index");
  llvm::Function *current_function = get_current_function();
  assert(current_function);
  llvm::Value *decl = m_Declarations[mod.module->getName().str()][access.decl];
  if (!decl)
    return report(access.location, "unknown declaration '" + access.decl->id + "'.");
  Type decl_type = access.decl->type;
  // Technically should be impossible but just in case sema fails to detect this
  if (!decl_type.array_data && decl_type.pointer_depth < 1)
    return report(access.location, "trying to access element of a non-array non-pointer type.");
  bool is_decay = false;
  if (decl_type.pointer_depth > 0) {
    decl = m_Builder.CreateLoad(gen_type(decl_type, mod), decl);
    --decl_type.pointer_depth;
    is_decay = true;
  }
  auto *last_gep_type = gen_type(decl_type, mod);
  assert(last_gep_type);
  std::vector<llvm::Value *> inner_indices = get_index_accesses(*access.indices[0], is_decay ? decl : nullptr, mod);
  llvm::Value *last_gep = m_Builder.CreateInBoundsGEP(last_gep_type, decl, inner_indices, "arrayidx");
  assert(last_gep);
  // we already decreased pointer depth
  if (!is_decay)
    de_array_type(decl_type, 1);
  out_type = decl_type;
  for (int i = 1; i < access.indices.size(); ++i) {
    if (decl_type.pointer_depth > 0) {
      auto *gened_decl_type = gen_type(decl_type, mod);
      assert(gened_decl_type);
      last_gep = m_Builder.CreateLoad(gened_decl_type, last_gep);
      assert(last_gep);
      --decl_type.pointer_depth;
      is_decay = true;
    }
    std::vector<llvm::Value *> inner_indices = get_index_accesses(*access.indices[i], is_decay ? decl : nullptr, mod);
    last_gep = m_Builder.CreateInBoundsGEP(gen_type(decl_type, mod), last_gep, inner_indices, "arrayidx");
    assert(last_gep);
    if (!is_decay)
      de_array_type(decl_type, 1);
    out_type = decl_type;
  }
  return last_gep;
}

llvm::Value *Codegen::gen_explicit_cast(const ResolvedExplicitCastExpr &cast, GeneratedModule &mod) {
  llvm::Value *var = nullptr;
  ResolvedExplicitCastExpr::CastType prev_cast_type = ResolvedExplicitCastExpr::CastType::Nop;
  const ResolvedDeclRefExpr *decl_ref_expr = dynamic_cast<const ResolvedDeclRefExpr *>(cast.rhs.get());
  if (!decl_ref_expr) {
    if (const ResolvedUnaryOperator *unop = dynamic_cast<const ResolvedUnaryOperator *>(cast.rhs.get())) {
      decl_ref_expr = dynamic_cast<const ResolvedDeclRefExpr *>(unop->rhs.get());
    } else if (const auto *inner_cast = dynamic_cast<const ResolvedExplicitCastExpr *>(cast.rhs.get())) {
      var = gen_explicit_cast(*inner_cast, mod);
      prev_cast_type = inner_cast->cast_type;
    } else {
      var = gen_expr(*cast.rhs, mod);
    }
  }
  var = decl_ref_expr ? m_Declarations[mod.module->getName().str()][decl_ref_expr->decl] : var;
  if (!var)
    return nullptr;
  llvm::Type *type = gen_type(cast.type, mod);
  assert(type);
  llvm::Type *rhs_type = gen_type(cast.rhs->type, mod);
  assert(rhs_type);
  switch (cast.cast_type) {
  case ResolvedExplicitCastExpr::CastType::IntToPtr: {
    if (get_type_size(cast.rhs->type.kind) < platform_array_index_size()) {
      llvm::Value *load = m_Builder.CreateLoad(rhs_type, var);
      auto *gened_platform_ptr_type = gen_type(platform_ptr_type(), mod);
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
    if (prev_cast_type == ResolvedExplicitCastExpr::CastType::Nop && var->getType()->isPtrOrPtrVectorTy()) {
      var = m_Builder.CreateLoad(rhs_type, var);
    }
    assert(var);
    if (is_float(cast.type.kind))
      return m_Builder.CreateFPExt(var, type, "cast_fpext");
    return m_Builder.CreateSExt(var, type, "cast_sext");
  }
  case ResolvedExplicitCastExpr::CastType::Truncate: {
    if (prev_cast_type == ResolvedExplicitCastExpr::CastType::Nop && var->getType()->isPtrOrPtrVectorTy()) {
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

llvm::Value *Codegen::gen_binary_op(const ResolvedBinaryOperator &binop, GeneratedModule &mod) {
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
    gen_conditional_op(*binop.lhs, true_bb, false_bb, mod);
    m_Builder.SetInsertPoint(rhs_bb);
    llvm::Value *rhs = type_to_bool(binop.type, gen_expr(*binop.rhs, mod));
    assert(rhs);
    m_Builder.CreateBr(merge_bb);
    rhs_bb = m_Builder.GetInsertBlock();
    assert(rhs_bb);
    m_Builder.SetInsertPoint(merge_bb);
    llvm::PHINode *phi = m_Builder.CreatePHI(m_Builder.getInt1Ty(), 2);
    assert(phi);
    for (auto it = llvm::pred_begin(merge_bb); it != llvm::pred_end(merge_bb); ++it) {
      if (*it == rhs_bb)
        phi->addIncoming(rhs, rhs_bb);
      else
        phi->addIncoming(m_Builder.getInt1(is_or), *it);
    }
    return bool_to_type(binop.type, phi);
  }
  llvm::Value *lhs = gen_expr(*binop.lhs, mod);
  assert(lhs);
  llvm::Value *rhs = gen_expr(*binop.rhs, mod);
  assert(rhs);
  if (op == TokenKind::LessThan || op == TokenKind::GreaterThan || op == TokenKind::EqualEqual || op == TokenKind::ExclamationEqual ||
      op == TokenKind::GreaterThanOrEqual || op == TokenKind::LessThanOrEqual)
    return bool_to_type(binop.type, gen_comp_op(op, binop.type, lhs, rhs));
  return m_Builder.CreateBinOp(get_math_binop_kind(op, binop.type.kind), lhs, rhs);
}

llvm::Value *gen_lt_expr(llvm::IRBuilder<> *builder, const Type &type, llvm::Value *lhs, llvm::Value *rhs) {
  assert(builder);
  assert(rhs);
  assert(lhs);
  if (type.kind >= Type::Kind::SIGNED_INT_START && type.kind <= Type::Kind::SIGNED_INT_END) {
    return builder->CreateICmpSLT(lhs, rhs);
  }
  if ((type.kind >= Type::Kind::UNSIGNED_INT_START && type.kind <= Type::Kind::UNSIGNED_INT_END) || type.kind == Type::Kind::Bool) {
    return builder->CreateICmpULT(lhs, rhs);
  }
  if ((type.kind == Type::Kind::Custom || type.kind == Type::Kind::FnPtr) && type.pointer_depth) {
    return builder->CreateICmpULT(lhs, rhs);
  }
  if (type.kind >= Type::Kind::FLOATS_START && type.kind <= Type::Kind::FLOATS_END) {
    return builder->CreateFCmpOLT(lhs, rhs);
  }
  llvm_unreachable("unexpected type.");
}

llvm::Value *gen_gt_expr(llvm::IRBuilder<> *builder, const Type &type, llvm::Value *lhs, llvm::Value *rhs) {
  assert(builder);
  assert(rhs);
  assert(lhs);
  if (type.kind >= Type::Kind::SIGNED_INT_START && type.kind <= Type::Kind::SIGNED_INT_END) {
    return builder->CreateICmpSGT(lhs, rhs);
  }
  if ((type.kind >= Type::Kind::UNSIGNED_INT_START && type.kind <= Type::Kind::UNSIGNED_INT_END) || type.kind == Type::Kind::Bool) {
    return builder->CreateICmpUGT(lhs, rhs);
  }
  if ((type.kind == Type::Kind::Custom || type.kind == Type::Kind::FnPtr) && type.pointer_depth) {
    return builder->CreateICmpUGT(lhs, rhs);
  }
  if (type.kind >= Type::Kind::FLOATS_START && type.kind <= Type::Kind::FLOATS_END) {
    return builder->CreateFCmpOGT(lhs, rhs);
  }
  llvm_unreachable("unexpected type.");
}

llvm::Value *gen_eq_expr(llvm::IRBuilder<> *builder, const Type &type, llvm::Value *lhs, llvm::Value *rhs) {
  assert(builder);
  assert(rhs);
  assert(lhs);
  if ((type.kind >= Type::Kind::INTEGERS_START && type.kind <= Type::Kind::INTEGERS_END) || type.kind == Type::Kind::Bool) {
    return builder->CreateICmpEQ(lhs, rhs);
  }
  if ((type.kind == Type::Kind::Custom || type.kind == Type::Kind::FnPtr) && type.pointer_depth) {
    return builder->CreateICmpEQ(lhs, rhs);
  }
  if (type.kind >= Type::Kind::FLOATS_START && type.kind <= Type::Kind::FLOATS_END) {
    return builder->CreateFCmpOEQ(lhs, rhs);
  }
  llvm_unreachable("unexpected type.");
}

llvm::Value *gen_neq_expr(llvm::IRBuilder<> *builder, const Type &type, llvm::Value *lhs, llvm::Value *rhs) {
  assert(builder);
  assert(rhs);
  assert(lhs);
  if ((type.kind >= Type::Kind::INTEGERS_START && type.kind <= Type::Kind::INTEGERS_END) || type.kind == Type::Kind::Bool) {
    return builder->CreateICmpNE(lhs, rhs);
  }
  if ((type.kind == Type::Kind::Custom || type.kind == Type::Kind::FnPtr) && type.pointer_depth) {
    return builder->CreateICmpNE(lhs, rhs);
  }
  if (type.kind >= Type::Kind::FLOATS_START && type.kind <= Type::Kind::FLOATS_END) {
    return builder->CreateFCmpONE(lhs, rhs);
  }
  llvm_unreachable("unexpected type.");
}

llvm::Value *gen_gte_expr(llvm::IRBuilder<> *builder, const Type &type, llvm::Value *lhs, llvm::Value *rhs) {
  assert(builder);
  assert(rhs);
  assert(lhs);
  if (type.kind >= Type::Kind::SIGNED_INT_START && type.kind <= Type::Kind::SIGNED_INT_END) {
    return builder->CreateICmpSGE(lhs, rhs);
  }
  if ((type.kind >= Type::Kind::UNSIGNED_INT_START && type.kind <= Type::Kind::UNSIGNED_INT_END) || type.kind == Type::Kind::Bool) {
    return builder->CreateICmpUGE(lhs, rhs);
  }
  if ((type.kind == Type::Kind::Custom || type.kind == Type::Kind::FnPtr) && type.pointer_depth) {
    return builder->CreateICmpUGE(lhs, rhs);
  }
  if (type.kind >= Type::Kind::FLOATS_START && type.kind <= Type::Kind::FLOATS_END) {
    return builder->CreateFCmpOGE(lhs, rhs);
  }
  llvm_unreachable("unexpected type.");
}

llvm::Value *gen_lte_expr(llvm::IRBuilder<> *builder, const Type &type, llvm::Value *lhs, llvm::Value *rhs) {
  assert(builder);
  assert(rhs);
  assert(lhs);
  if (type.kind >= Type::Kind::SIGNED_INT_START && type.kind <= Type::Kind::SIGNED_INT_END) {
    return builder->CreateICmpSLE(lhs, rhs);
  }
  if ((type.kind >= Type::Kind::UNSIGNED_INT_START && type.kind <= Type::Kind::UNSIGNED_INT_END) || type.kind == Type::Kind::Bool) {
    return builder->CreateICmpULE(lhs, rhs);
  }
  if ((type.kind == Type::Kind::Custom || type.kind == Type::Kind::FnPtr) && type.pointer_depth) {
    return builder->CreateICmpULE(lhs, rhs);
  }
  if (type.kind >= Type::Kind::FLOATS_START && type.kind <= Type::Kind::FLOATS_END) {
    return builder->CreateFCmpOLE(lhs, rhs);
  }
  llvm_unreachable("unexpected type.");
}

llvm::Value *Codegen::gen_comp_op(TokenKind op, const Type &type, llvm::Value *lhs, llvm::Value *rhs) {
  assert(rhs);
  assert(lhs);
  llvm::Value *ret_val;
  switch (op) {
  case TokenKind::LessThan: {
    ret_val = gen_lt_expr(&m_Builder, type, lhs, rhs);
  } break;
  case TokenKind::GreaterThan: {
    ret_val = gen_gt_expr(&m_Builder, type, lhs, rhs);
  } break;
  case TokenKind::EqualEqual: {
    ret_val = gen_eq_expr(&m_Builder, type, lhs, rhs);
  } break;
  case TokenKind::ExclamationEqual: {
    ret_val = gen_neq_expr(&m_Builder, type, lhs, rhs);
  } break;
  case TokenKind::LessThanOrEqual: {
    ret_val = gen_lte_expr(&m_Builder, type, lhs, rhs);
  } break;
  case TokenKind::GreaterThanOrEqual: {
    ret_val = gen_gte_expr(&m_Builder, type, lhs, rhs);
  } break;
  }
  assert(ret_val);
  return bool_to_type(type, ret_val);
}

std::pair<llvm::Value *, Type> Codegen::gen_dereference(const ResolvedDeclRefExpr &expr, GeneratedModule &mod) {
  llvm::Value *decl = m_Declarations[mod.module->getName().str()][expr.decl];
  llvm::Value *ptr = m_Builder.CreateLoad(gen_type(expr.type, mod), decl);
  assert(ptr);
  Type new_internal_type = expr.type;
  --new_internal_type.pointer_depth;
  llvm::Type *dereferenced_type = gen_type(new_internal_type, mod);
  assert(dereferenced_type);
  auto *gened_load = m_Builder.CreateLoad(dereferenced_type, ptr);
  assert(gened_load);
  return std::make_pair(gened_load, new_internal_type);
}

std::pair<llvm::Value *, Type> Codegen::gen_unary_op(const ResolvedUnaryOperator &op, GeneratedModule &mod) {
  if (op.op == TokenKind::Asterisk) {
    if (auto *dre = dynamic_cast<ResolvedDeclRefExpr *>(op.rhs.get())) {
      return gen_dereference(*dre, mod);
    } else if (auto *unop = dynamic_cast<ResolvedUnaryOperator *>(op.rhs.get())) {
      auto &&[rhs, type] = gen_unary_op(*unop, mod);
      assert(rhs);
      --type.pointer_depth;
      llvm::Type *dereferenced_type = gen_type(type, mod);
      assert(dereferenced_type);
      return std::make_pair(m_Builder.CreateLoad(dereferenced_type, rhs), type);
    } else {
      llvm::Value *gened = gen_expr(*op.rhs, mod);
      assert(gened);
      return std::make_pair(gened, op.rhs->type);
    }
  } else if (op.op == TokenKind::Amp) {
    if (auto *dre = dynamic_cast<ResolvedDeclRefExpr *>(op.rhs.get())) {
      ++op.rhs->type.pointer_depth;
      llvm::Value *val = gen_expr(*op.rhs, mod);
      assert(val);
      return std::make_pair(val, op.rhs->type);
    }
  } else {
    llvm::Value *rhs = gen_expr(*op.rhs, mod);
    assert(rhs);
    if (op.op == TokenKind::Exclamation) {
      if (rhs->getType()->isPtrOrPtrVectorTy()) {
        return std::make_pair(m_Builder.CreateIsNull(rhs, "to.is_null"), op.type);
      }
      return std::make_pair(m_Builder.CreateNot(rhs), op.type);
    }
    SimpleNumType type = get_simple_type(op.rhs->type.kind);
    if (op.op == TokenKind::Minus) {
      if (type == SimpleNumType::SINT || type == SimpleNumType::UINT)
        return std::make_pair(m_Builder.CreateNeg(rhs), op.type);
      else if (type == SimpleNumType::FLOAT)
        return std::make_pair(m_Builder.CreateFNeg(rhs), op.type);
    }
    if (op.op == TokenKind::Tilda) {
      return std::make_pair(m_Builder.CreateXor(rhs, llvm::ConstantInt::get(gen_type(op.type, mod), -1), "not"), op.type);
    }
    llvm_unreachable("unknown unary op.");
    return std::make_pair(nullptr, op.type);
  }
  assert(false);
}

void Codegen::gen_conditional_op(const ResolvedExpr &op, llvm::BasicBlock *true_bb, llvm::BasicBlock *false_bb, GeneratedModule &mod) {
  const auto *binop = dynamic_cast<const ResolvedBinaryOperator *>(&op);
  if (binop && binop->op == TokenKind::PipePipe) {
    llvm::BasicBlock *next_bb = llvm::BasicBlock::Create(m_Context, "or.lhs.false", true_bb->getParent());
    gen_conditional_op(*binop->lhs, true_bb, next_bb, mod);
    m_Builder.SetInsertPoint(next_bb);
    gen_conditional_op(*binop->rhs, true_bb, false_bb, mod);
    return;
  }
  if (binop && binop->op == TokenKind::AmpAmp) {
    llvm::BasicBlock *next_bb = llvm::BasicBlock::Create(m_Context, "and.lhs.true", true_bb->getParent());
    assert(next_bb);
    gen_conditional_op(*binop->lhs, next_bb, false_bb, mod);
    m_Builder.SetInsertPoint(next_bb);
    gen_conditional_op(*binop->rhs, true_bb, false_bb, mod);
    return;
  }
  llvm::Value *val = type_to_bool(op.type, gen_expr(op, mod));
  assert(val);
  m_Builder.CreateCondBr(val, true_bb, false_bb);
}

llvm::Value *Codegen::gen_call_expr(const ResolvedCallExpr &call, GeneratedModule &mod) {
  if (mod.module->getName() != call.decl->module) {
    if (!m_Declarations[mod.module->getName().str()].count(call.decl)) {
      auto *resolved_func_decl = dynamic_cast<const ResolvedFuncDecl *>(call.decl);
      assert(resolved_func_decl);
      gen_func_decl(*resolved_func_decl, mod);
    }
  }
  llvm::Function *callee = mod.module->getFunction(call.decl->og_name.empty() ? call.decl->id : call.decl->og_name);
  std::vector<llvm::Value *> args{};
  int param_index = -1;
  for (auto &&arg : call.args) {
    ++param_index;
    if (const auto *unary_op = dynamic_cast<const ResolvedUnaryOperator *>(arg.get()); unary_op && (unary_op->op == TokenKind::Amp)) {
      if (const auto *dre = dynamic_cast<ResolvedDeclRefExpr *>(unary_op->rhs.get())) {
        llvm::Value *expr = m_Declarations[mod.module->getName().str()][dre->decl];
        assert(expr);
        args.emplace_back(expr);
        continue;
      }
    }
    if (const auto *dre = dynamic_cast<ResolvedDeclRefExpr *>(arg.get())) {
      if (const auto *func_decl = dynamic_cast<const ResolvedFuncDecl *>(call.decl)) {
        llvm::Value *decay = gen_array_decay(func_decl->params[param_index]->type, *dre, mod);
        if (decay) {
          args.emplace_back(decay);
          continue;
        }
      }
    }
    args.emplace_back(gen_expr(*arg, mod));
  }
  // we're probably dealing with fn ptr
  if (!callee) {
    callee = static_cast<llvm::Function *>(m_Declarations[mod.module->getName().str()][call.decl]);
    llvm::Type *function_ret_type = gen_type(call.type, mod);
    assert(function_ret_type);
    bool is_fn_ptr = call.type.fn_ptr_signature.has_value();
    bool is_vla = false;
    if (is_fn_ptr)
      is_vla = call.type.fn_ptr_signature->second;
    auto *function_type = llvm::FunctionType::get(function_ret_type, is_vla);
    assert(function_type);
    emit_debug_location(call.location, mod);
    llvm::Value *loaded_fn = m_Builder.CreateLoad(m_Builder.getPtrTy(), callee);
    assert(loaded_fn);
    return m_Builder.CreateCall(function_type, loaded_fn, args, call.decl->og_name.empty() ? call.decl->id : call.decl->og_name);
  }
  emit_debug_location(call.location, mod);
  return m_Builder.CreateCall(callee, args);
}

llvm::Value *Codegen::gen_decl_stmt(const ResolvedDeclStmt &stmt, GeneratedModule &mod) {
  llvm::Function *function = get_current_function();
  assert(function);
  const auto *decl = stmt.var_decl.get();
  assert(decl);
  llvm::Type *type = gen_type(decl->type, mod);
  assert(type);
  llvm::AllocaInst *var = alloc_stack_var(function, type, decl->id);
  assert(var);
  if (const auto &init = decl->initializer) {
    if (const auto *struct_lit = dynamic_cast<const ResolvedStructLiteralExpr *>(init.get())) {
      gen_struct_literal_expr_assignment(*struct_lit, var, mod);
    } else if (const auto *unary_op = dynamic_cast<const ResolvedUnaryOperator *>(init.get()); unary_op && (unary_op->op == TokenKind::Amp)) {
      if (const auto *dre = dynamic_cast<ResolvedDeclRefExpr *>(unary_op->rhs.get())) {
        llvm::Value *expr = m_Declarations[mod.module->getName().str()][dre->decl];
        assert(expr);
        if (unary_op->op == TokenKind::Amp) {
          m_Builder.CreateStore(expr, var);
        }
      }
    } else if (const auto *array_lit = dynamic_cast<ResolvedArrayLiteralExpr *>(init.get())) {
      gen_array_literal_expr(*array_lit, var, mod);
    } else if (const auto *dre = dynamic_cast<const ResolvedDeclRefExpr *>(init.get())) {
      llvm::Value *decay = gen_array_decay(decl->type, *dre, mod);
      m_Builder.CreateStore(decay ? decay : gen_expr(*init, mod), var);
    } else {
      m_Builder.CreateStore(gen_expr(*init, mod), var);
    }
  }
  if (m_ShouldGenDebug) {
    auto *subprogram = mod.debug_info->lexical_blocks.back();
    auto *unit = mod.di_builder->createFile(mod.debug_info->cu->getFilename(), mod.debug_info->cu->getDirectory());
    llvm::DILocalVariable *dbg_var_info = mod.di_builder->createAutoVariable(subprogram, decl->id, unit, decl->location.line, gen_debug_type(decl->type, mod));
    auto *call = mod.di_builder->insertDeclare(var, dbg_var_info, mod.di_builder->createExpression(),
                                               llvm::DILocation::get(subprogram->getContext(), decl->location.line, 0, subprogram), m_Builder.GetInsertBlock());
  }
  m_Declarations[mod.module->getName().str()][decl] = var;
  return nullptr;
}

llvm::Value *Codegen::gen_array_decay(const Type &lhs_type, const ResolvedDeclRefExpr &rhs_dre, GeneratedModule &mod) {
  if (rhs_dre.type.array_data) {
    if (is_same_array_decay(rhs_dre.type, lhs_type)) {
      std::vector<llvm::Value *> indices{llvm::ConstantInt::get(m_Context, llvm::APInt(static_cast<unsigned>(platform_array_index_size()), 0)),
                                         llvm::ConstantInt::get(m_Context, llvm::APInt(static_cast<unsigned>(platform_array_index_size()), 0))};
      llvm::Value *decl = m_Declarations[mod.module->getName().str()][rhs_dre.decl];
      auto *type = gen_type(rhs_dre.type, mod);
      assert(type);
      return m_Builder.CreateInBoundsGEP(type, decl, indices, "arraydecay");
    }
  }
  return nullptr;
}

llvm::Function *Codegen::get_current_function() { return m_Builder.GetInsertBlock()->getParent(); }

llvm::Value *Codegen::type_to_bool(const Type &type, llvm::Value *value, std::optional<TokenKind> op) {
  assert(value);
  if (type.pointer_depth) {
    return m_Builder.CreateIsNotNull(value, "to.is_not_null");
  }
  if (type.kind >= Type::Kind::INTEGERS_START && type.kind <= Type::Kind::INTEGERS_END)
    return m_Builder.CreateICmpNE(value, llvm::ConstantInt::getBool(m_Context, false), "to.bool");
  if (type.kind >= Type::Kind::FLOATS_START && type.kind <= Type::Kind::FLOATS_END)
    return m_Builder.CreateFCmpONE(value, llvm::ConstantFP::get(m_Builder.getDoubleTy(), 0.0), "to.bool");
  if (type.kind == Type::Kind::Bool)
    return value;
  llvm_unreachable("unexpected type cast to bool.");
}

llvm::Value *Codegen::bool_to_type(const Type &type, llvm::Value *value) {
  assert(value);
  if ((type.kind >= Type::Kind::INTEGERS_START && type.kind <= Type::Kind::INTEGERS_END) || type.kind == Type::Kind::Bool)
    return value;
  if ((type.kind == Type::Kind::Custom) && type.pointer_depth)
    return value;
  if (type.kind == Type::Kind::f32)
    return m_Builder.CreateUIToFP(value, m_Builder.getFloatTy(), "to.float");
  if (type.kind == Type::Kind::f64)
    return m_Builder.CreateUIToFP(value, m_Builder.getDoubleTy(), "to.double");
  llvm_unreachable("unexpected type cast from bool.");
}

llvm::Value *Codegen::gen_assignment(const ResolvedAssignment &assignment, GeneratedModule &mod) {
  llvm::Value *decl = m_Declarations[mod.module->getName().str()][assignment.variable->decl];
  Type member_type = Type::builtin_void(false);
  if (const auto *member_access = dynamic_cast<const ResolvedStructMemberAccess *>(assignment.variable.get())) {
    decl = gen_struct_member_access(*member_access, member_type, mod);
    assert(decl);
  } else if (const auto *array_access = dynamic_cast<const ResolvedArrayElementAccess *>(assignment.variable.get())) {
    decl = gen_array_element_access(*array_access, member_type, mod);
  } else {
    Type derefed_type = assignment.variable->type;
    for (int i = 0; i < assignment.lhs_deref_count; ++i) {
      decl = m_Builder.CreateLoad(gen_type(derefed_type, mod), decl);
      --derefed_type.pointer_depth;
    }
  }
  assert(decl);
  llvm::Instruction *instruction = nullptr;
  llvm::Value *expr = nullptr;
  // @TODO: this is super hacky. To refactor pass decl to Codegen::gen_expr and
  // further to Codegen::gen_unary_op
  if (const auto *unop = dynamic_cast<const ResolvedUnaryOperator *>(assignment.expr.get()); unop && unop->op == TokenKind::Amp) {
    if (const auto *dre = dynamic_cast<ResolvedDeclRefExpr *>(unop->rhs.get())) {
      expr = m_Declarations[mod.module->getName().str()][dre->decl];
      assert(expr);
      instruction = m_Builder.CreateStore(expr, decl);
    }
  } else {
    expr = gen_expr(*assignment.expr, mod);
    assert(expr);
    if (const auto *struct_lit = dynamic_cast<const ResolvedStructLiteralExpr *>(assignment.expr.get())) {
      // expr is the stack variable
      llvm::Type *var_type = gen_type(struct_lit->type, mod);
      assert(var_type);
      llvm::Type *decl_type = gen_type(assignment.variable->decl->type, mod);
      assert(decl_type);
      const llvm::DataLayout &data_layout = mod.module->getDataLayout();
      instruction = m_Builder.CreateMemCpy(decl, data_layout.getPrefTypeAlign(decl_type), expr, data_layout.getPrefTypeAlign(var_type),
                                           data_layout.getTypeAllocSize(var_type));
    }
    instruction = instruction ? instruction : m_Builder.CreateStore(expr, decl);
  }
  assert(instruction);
  assert(expr);
  if (m_ShouldGenDebug) {
    // @NOTE: dunno if I need assignment, seems to work without it
    /* auto *subprogram = mod.debug_info->lexical_blocks.back(); */
    /* const auto *location = llvm::DILocation::get(subprogram->getContext(), assignment.location.line, 0, subprogram); */
    /* auto *unit = mod.di_builder->createFile(mod.debug_info->cu->getFilename(), mod.debug_info->cu->getDirectory()); */
    /* llvm::DILocalVariable *debug_var = mod.di_builder->createAutoVariable(subprogram, assignment.variable->decl->id, unit, assignment.location.line, */
    /*                                                                       gen_debug_type(assignment.variable->type, mod)); */
    /* mod.di_builder->insertDbgAssign(instruction, expr, debug_var, mod.di_builder->createExpression(), decl, mod.di_builder->createExpression(), location); */
  }
  return instruction;
}
} // namespace saplang
