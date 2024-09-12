#pragma once

#include "ast.h"

#include <set>

namespace saplang {
struct BasicBlock {
  std::set<std::pair<int, bool>> predecessors;
  std::set<std::pair<int, bool>> successors;
  std::vector<const ResolvedStmt *> statements;
};

struct CFG : public IDumpable {
  std::vector<BasicBlock> basic_blocks;
  int entry{-1};
  int exit{-1};

  int insert_new_block();
  int insert_new_block_before(int before, bool reachable);
  void insert_edge(int from, int to, bool reachable);
  void insert_stmt(const ResolvedStmt *stmt, int block);

  DUMP_IMPL
};

class CFGBuilder {
public:
  CFG build(const ResolvedFuncDecl &fn);

private:
  int insert_block(const ResolvedBlock &block, int successor);
  int insert_stmt(const ResolvedStmt &stmt, int block);
  int insert_if_stmt(const ResolvedIfStmt &if_stmt, int exit);
  int insert_while_stmt(const ResolvedWhileStmt &while_stmt, int exit);
  int insert_expr(const ResolvedExpr &expr, int block);
  int insert_return_stmt(const ResolvedReturnStmt &ret, int block);
  int insert_decl_stmt(const ResolvedDeclStmt& stmt, int block);

private:
  CFG m_CFG;
};
} // namespace saplang