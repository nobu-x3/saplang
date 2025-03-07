#include "cfg.h"
#include "ast.h"

#include <llvm/Support/ErrorHandling.h>

namespace saplang {
int CFG::insert_new_block() {
  basic_blocks.emplace_back();
  return basic_blocks.size() - 1;
}

int CFG::insert_new_block_before(int before, bool reachable) {
  int block = insert_new_block();
  insert_edge(block, before, reachable);
  return block;
}

void CFG::insert_edge(int from, int to, bool reachable) {
  basic_blocks[from].successors.emplace(std::make_pair(to, reachable));
  basic_blocks[to].predecessors.emplace(std::make_pair(from, reachable));
}

void CFG::insert_stmt(const ResolvedStmt *stmt, int block) { basic_blocks[block].statements.emplace_back(stmt); }

void CFG::dump_to_stream(std::stringstream &stream, size_t indent_level) const {
  for (int i = basic_blocks.size() - 1; i >= 0; --i) {
    stream << '[' << i;
    if (i == entry)
      stream << " (entry)";
    else if (i == exit)
      stream << " (exit)";
    stream << ']' << '\n';

    stream << "  preds: ";
    for (auto &&[id, reachable] : basic_blocks[i].predecessors)
      stream << id << ((reachable) ? " " : "(U) ");
    stream << '\n';

    stream << "  succs: ";
    for (auto &&[id, reachable] : basic_blocks[i].successors)
      stream << id << ((reachable) ? " " : "(U) ");
    stream << '\n';

    const auto &statements = basic_blocks[i].statements;
    for (auto it = statements.rbegin(); it != statements.rend(); ++it)
      (*it)->dump_to_stream(stream, 1);
    stream << '\n';
  }
}

CFG CFGBuilder::build(const ResolvedFuncDecl &fn) {
  m_CFG = {};
  m_CFG.exit = m_CFG.insert_new_block();
  int body = insert_block(*fn.body, m_CFG.exit);
  m_CFG.entry = m_CFG.insert_new_block_before(body, true);
  return m_CFG;
}

bool is_terminator(const ResolvedStmt &stmt) {
  return dynamic_cast<const ResolvedReturnStmt *>(&stmt) || dynamic_cast<const ResolvedIfStmt *>(&stmt) || dynamic_cast<const ResolvedWhileStmt *>(&stmt);
}
int CFGBuilder::insert_block(const ResolvedBlock &block, int successor) {
  const auto &stmts = block.statements;
  bool should_insert_block = true;
  for (auto it = stmts.rbegin(); it != stmts.rend(); ++it) {
    if (should_insert_block && !is_terminator(**it))
      successor = m_CFG.insert_new_block_before(successor, true);
    should_insert_block = dynamic_cast<const ResolvedWhileStmt *>(it->get()) != nullptr;
    successor = insert_stmt(**it, successor);
  }
  return successor;
}

int CFGBuilder::insert_stmt(const ResolvedStmt &stmt, int block) {
  if (auto *if_stmt = dynamic_cast<const ResolvedIfStmt *>(&stmt))
    return insert_if_stmt(*if_stmt, block);
  if (auto *while_stmt = dynamic_cast<const ResolvedWhileStmt *>(&stmt))
    return insert_while_stmt(*while_stmt, block);
  if (auto *expr = dynamic_cast<const ResolvedExpr *>(&stmt))
    return insert_expr(*expr, block);
  if (auto *switch_stmt = dynamic_cast<const ResolvedSwitchStmt *>(&stmt))
    // @TODO: atm don't do anything
    return m_CFG.basic_blocks.size() - 1;
  if (auto *ret_stmt = dynamic_cast<const ResolvedReturnStmt *>(&stmt))
    return insert_return_stmt(*ret_stmt, block);
  if (auto *decl_stmt = dynamic_cast<const ResolvedDeclStmt *>(&stmt))
    return insert_decl_stmt(*decl_stmt, block);
  if (auto *assignment = dynamic_cast<const ResolvedAssignment *>(&stmt))
    return insert_assignment(*assignment, block);
  if (auto *defer = dynamic_cast<const ResolvedDeferStmt *>(&stmt)) {
    // @TODO: atm don't do anything
    return m_CFG.basic_blocks.size() - 1;
  }
  if (auto *resolved_block = dynamic_cast<const ResolvedBlock *>(&stmt)) {
    return insert_block(*resolved_block, block);
  }
  if (auto *for_stmt = dynamic_cast<const ResolvedForStmt *>(&stmt)) {
    return m_CFG.basic_blocks.size() - 1;
  } else {
    llvm_unreachable("unexpected expression.");
  }
}

int CFGBuilder::insert_if_stmt(const ResolvedIfStmt &if_stmt, int exit) {
  int false_block = exit;
  if (if_stmt.false_block)
    false_block = insert_block(*if_stmt.false_block, exit);
  int true_block = insert_block(*if_stmt.true_block, exit);
  int entry = m_CFG.insert_new_block();
  std::optional<ConstexprResult> val = if_stmt.condition->get_constant_value();
  m_CFG.insert_edge(entry, true_block, val.has_value() && val->kind == Type::Kind::Bool && val->value.b8 != false);
  m_CFG.insert_edge(entry, false_block, !val.has_value() || (val->kind == Type::Kind::Bool && val->value.b8 == false));
  m_CFG.insert_stmt(&if_stmt, entry);
  return insert_expr(*if_stmt.condition, entry);
}

int CFGBuilder::insert_while_stmt(const ResolvedWhileStmt &while_stmt, int exit) {
  int latch = m_CFG.insert_new_block();
  int body = insert_block(*while_stmt.body, latch);
  int header = m_CFG.insert_new_block();
  m_CFG.insert_edge(latch, header, true);
  std::optional<ConstexprResult> val = while_stmt.condition->get_constant_value();
  m_CFG.insert_edge(header, body, val.has_value() && val->kind == Type::Kind::Bool && val->value.b8 != false);
  m_CFG.insert_edge(header, exit, !val.has_value() || (val->kind == Type::Kind::Bool && val->value.b8 != false));
  m_CFG.insert_stmt(&while_stmt, header);
  insert_expr(*while_stmt.condition, header);
  return header;
}

int CFGBuilder::insert_expr(const ResolvedExpr &expr, int block) {
  m_CFG.insert_stmt(&expr, block);
  if (const auto *call_expr = dynamic_cast<const ResolvedCallExpr *>(&expr)) {
    for (auto it = call_expr->args.rbegin(); it != call_expr->args.rend(); ++it)
      insert_expr(**it, block);
    return block;
  }
  if (const auto *group = dynamic_cast<const ResolvedGroupingExpr *>(&expr))
    return insert_expr(*group->expr, block);
  if (const auto *binop = dynamic_cast<const ResolvedBinaryOperator *>(&expr))
    return insert_expr(*binop->rhs, block), insert_expr(*binop->lhs, block);
  if (const auto *unop = dynamic_cast<const ResolvedUnaryOperator *>(&expr))
    return insert_expr(*unop->rhs, block);
  return block;
}

int CFGBuilder::insert_return_stmt(const ResolvedReturnStmt &ret, int block) {
  block = m_CFG.insert_new_block_before(m_CFG.exit, true);
  m_CFG.insert_stmt(&ret, block);
  if (ret.expr)
    return insert_expr(*ret.expr, block);
  return block;
}

int CFGBuilder::insert_decl_stmt(const ResolvedDeclStmt &stmt, int block) {
  m_CFG.insert_stmt(&stmt, block);
  if (const auto &init = stmt.var_decl->initializer)
    return insert_expr(*init, block);
  return block;
}

int CFGBuilder::insert_assignment(const ResolvedAssignment &assignment, int block) {
  m_CFG.insert_stmt(&assignment, block);
  return insert_expr(*assignment.expr, block);
}
} // namespace saplang
