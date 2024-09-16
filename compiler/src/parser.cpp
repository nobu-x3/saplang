#include <cassert>
#include <memory>

#include "ast.h"
#include "lexer.h"
#include "parser.h"
#include "utils.h"

namespace saplang {

Parser::Parser(Lexer *lexer)
    : m_Lexer(lexer), m_NextToken(lexer->get_next_token()) {}

// <funcDecl>
// ::= 'fn' <type> <identifier> '(' ')' <block>
std::unique_ptr<FunctionDecl> Parser::parse_function_decl() {
  SourceLocation location = m_NextToken.location;
  if (m_NextToken.kind != TokenKind::KwFn) {
    return report(m_NextToken.location,
                  "function declarations must start with 'fn'");
  }
  eat_next_token();
  auto return_type = parse_type(); // eats the function identifier
  if (!return_type) {
    return nullptr;
  }
  if (m_NextToken.kind != TokenKind::Identifier || !m_NextToken.value) {
    return report(m_NextToken.location, "expected function identifier.");
  }
  std::string function_identifier = *m_NextToken.value;
  eat_next_token(); // eat '('
  if (m_NextToken.kind != TokenKind::Lparent)
    return report(m_NextToken.location, "expected '('.");
  auto param_list = parse_parameter_list();
  if (!param_list)
    return nullptr;
  std::unique_ptr<Block> block = parse_block();
  if (!block) {
    return report(m_NextToken.location, "failed to parse function block.");
  }
  return std::make_unique<FunctionDecl>(location, function_identifier,
                                        *return_type, std::move(*param_list),
                                        std::move(block));
}

// <block>
// ::= '{' <statement>* '}'
std::unique_ptr<Block> Parser::parse_block() {
  SourceLocation location = m_NextToken.location;
  if (m_NextToken.kind != TokenKind::Lbrace)
    return report(m_NextToken.location,
                  "expected '{' at the beginning of a block.");
  eat_next_token(); // eats '{'
  std::vector<std::unique_ptr<Stmt>> statements;
  while (true) {
    if (m_NextToken.kind == TokenKind::Rbrace)
      break;
    if (m_NextToken.kind == TokenKind::Eof ||
        m_NextToken.kind == TokenKind::KwFn) {
      return report(m_NextToken.location,
                    "expected '}' at the end of a block.");
    }
    auto stmt = parse_stmt();
    if (!stmt) {
      synchronize();
      continue;
    }
    statements.emplace_back(std::move(stmt));
  }
  eat_next_token(); // eats '}'
  return std::make_unique<Block>(location, std::move(statements));
}

// <statement>
// ::= <returnStmt>
// | <expr> ';'
// | <ifStatement>
// | <whileStatement>
// | <forStatement>
// | <varDeclStatement>
// | <assignment>
std::unique_ptr<Stmt> Parser::parse_stmt() {
  if (m_NextToken.kind == TokenKind::KwWhile)
    return parse_while_stmt();
  if (m_NextToken.kind == TokenKind::KwFor)
    return parse_for_stmt();
  if (m_NextToken.kind == TokenKind::KwIf)
    return parse_if_stmt();
  if (m_NextToken.kind == TokenKind::KwReturn)
    return parse_return_stmt();
  if (m_NextToken.kind == TokenKind::KwConst ||
      m_NextToken.kind == TokenKind::KwVar)
    return parse_var_decl_stmt();
  auto stmt = parse_assignment_or_expr();
  if (auto *assignment = dynamic_cast<const Assignment *>(stmt.get())) {
    if (m_NextToken.kind != TokenKind::Semicolon)
      return report(m_NextToken.location,
                    "expected ';' at the end of assignment.");
    eat_next_token(); // eat ';'
  }
  if (auto *expr = dynamic_cast<const Expr *>(stmt.get())) {
    if (m_NextToken.kind != TokenKind::Semicolon)
      return report(m_NextToken.location,
                    "expected ';' at the end of expression.");
    eat_next_token(); // eat ';'
  }
  return stmt;
}

// <ifStatement>
//  ::= 'if' <expr> <block> ('else' (<ifStatement> | <block>))?
std::unique_ptr<IfStmt> Parser::parse_if_stmt() {
  SourceLocation location = m_NextToken.location;
  eat_next_token(); // eat 'if'
  std::unique_ptr<Expr> condition = parse_expr();
  if (!condition)
    return nullptr;
  std::unique_ptr<Block> true_block = parse_block();
  if (!true_block)
    return nullptr;
  if (m_NextToken.kind != TokenKind::KwElse)
    return std::make_unique<IfStmt>(location, std::move(condition),
                                    std::move(true_block), nullptr);
  eat_next_token(); // eat 'else'
  std::unique_ptr<Block> false_block;
  if (m_NextToken.kind == TokenKind::KwIf) {
    std::unique_ptr<IfStmt> else_if = parse_if_stmt();
    if (!else_if)
      return nullptr;
    SourceLocation loc = else_if->location;
    std::vector<std::unique_ptr<Stmt>> stmts;
    stmts.emplace_back(std::move(else_if));
    false_block = std::make_unique<Block>(loc, std::move(stmts));
  } else {
    if (m_NextToken.kind != TokenKind::Lbrace)
      return report(location, "expected 'else' block.");
    false_block = parse_block();
  }
  if (!false_block)
    return nullptr;
  return std::make_unique<IfStmt>(location, std::move(condition),
                                  std::move(true_block),
                                  std::move(false_block));
}
// <whileStatement>
//  ::= 'while' <expr> <block>
std::unique_ptr<WhileStmt> Parser::parse_while_stmt() {
  SourceLocation location = m_NextToken.location;
  eat_next_token(); // eat 'while'
  std::unique_ptr<Expr> condition = parse_expr();
  if (!condition)
    return nullptr;
  if (m_NextToken.kind != TokenKind::Lbrace)
    return report(m_NextToken.location, "expected 'while' body.");
  std::unique_ptr<Block> body = parse_block();
  if (!body)
    return nullptr;
  return std::make_unique<WhileStmt>(location, std::move(condition),
                                     std::move(body));
}

// <forStatement>
// ::= 'for' <varDeclStatement> <expr> <assignment> <block>
std::unique_ptr<ForStmt> Parser::parse_for_stmt() {
  SourceLocation loc = m_NextToken.location;
  eat_next_token(); // eat 'for'
  if (m_NextToken.kind == TokenKind::Lparent)
    eat_next_token(); // eat '('
  std::unique_ptr<DeclStmt> var_decl = parse_var_decl_stmt();
  if (!var_decl)
    return nullptr;
  std::unique_ptr<Expr> condition = parse_expr();
  if (!condition)
    return nullptr;
  if (m_NextToken.kind != TokenKind::Semicolon)
    return report(m_NextToken.location, "expected ';' after for condition.");
  eat_next_token(); // eat ';'
  std::unique_ptr<Stmt> increment_expr = parse_assignment_or_expr();
  if (!increment_expr)
    return nullptr;
  if (m_NextToken.kind == TokenKind::Rparent)
    eat_next_token(); // eat ')'
  std::unique_ptr<Block> body = parse_block();
  if (!body)
    return nullptr;
  return std::make_unique<ForStmt>(loc, std::move(var_decl),
                                   std::move(condition),
                                   std::move(increment_expr), std::move(body));
}

// <varDeclStatement>
// ::= ('const' | 'var') <varDecl> ';'
std::unique_ptr<DeclStmt> Parser::parse_var_decl_stmt() {
  SourceLocation loc = m_NextToken.location;
  bool is_const = m_NextToken.kind == TokenKind::KwConst;
  eat_next_token(); // eat 'const' or 'var'
  if (m_NextToken.kind != TokenKind::Identifier)
    return report(m_NextToken.location, "expected identifier.");
  std::unique_ptr<VarDecl> var_decl = parse_var_decl(is_const);
  if (!var_decl)
    return nullptr;
  if (m_NextToken.kind != TokenKind::Semicolon)
    return report(m_NextToken.location,
                  "expected ';' at the end of declaration.");
  eat_next_token(); // eat ';'
  return std::make_unique<DeclStmt>(loc, std::move(var_decl));
}

// <varDecl>
// ::= <type> <identifier> ('=' <expr>)?
std::unique_ptr<VarDecl> Parser::parse_var_decl(bool is_const) {
  SourceLocation loc = m_NextToken.location;
  std::optional<Type> type = parse_type();
  if (!type)
    return report(m_NextToken.location,
                  "expected type before variable identifier.");
  if (m_NextToken.kind != TokenKind::Identifier)
    return report(m_NextToken.location, "expected identifier after type.");
  std::string id = *m_NextToken.value;
  eat_next_token(); // eat id
  if (m_NextToken.kind != TokenKind::Equal) {
    if (is_const)
      return report(loc, "const variable expected to have initializer.");
    return std::make_unique<VarDecl>(loc, id, *type, nullptr, is_const);
  }
  eat_next_token(); // eat '='
  std::unique_ptr<Expr> initializer = parse_expr();
  if (!initializer)
    return nullptr;
  return std::make_unique<VarDecl>(loc, id, *type, std::move(initializer),
                                   is_const);
}

// <structDeclStatement>
// ::= 'struct' <identifier> '{' (<type> <identifier> ';') '}'
std::unique_ptr<StructDecl> Parser::parse_struct_decl() {
  SourceLocation loc = m_NextToken.location;
  eat_next_token(); // eat 'struct'
  if (m_NextToken.kind != TokenKind::Identifier || !m_NextToken.value)
    return report(m_NextToken.location,
                  "struct type declarations must have a name.");
  std::string id = *m_NextToken.value;
  eat_next_token(); // eat identifier
  if (m_NextToken.kind != TokenKind::Lbrace)
    return report(m_NextToken.location,
                  "struct type declarations must have a body.");
  eat_next_token(); // eat '{'
  std::vector<std::pair<Type, std::string>> fields{};
  while (m_NextToken.kind != TokenKind::Rbrace) {
    std::optional<Type> type = parse_type();
    if (!type)
      return nullptr;
    if (m_NextToken.kind != TokenKind::Identifier || !m_NextToken.value)
      return report(m_NextToken.location,
                    "struct member field declarations must have a name.");
    std::string field_name = *m_NextToken.value;
    eat_next_token(); // eat field name
    if (m_NextToken.kind != TokenKind::Semicolon)
      return report(m_NextToken.location,
                    "struct member field declarations must end with ';'.");
    eat_next_token(); // eat ';'
    fields.emplace_back(std::make_pair(*type, field_name));
  }
  eat_next_token(); // eat '}'
  return std::make_unique<StructDecl>(loc, id, std::move(fields));
}

std::unique_ptr<Assignment>
Parser::parse_assignment(std::unique_ptr<Expr> lhs) {
  auto *dre = dynamic_cast<DeclRefExpr *>(lhs.get());
  if (!dre)
    return report(lhs->location, "expected variable on the LHS of assignment.");
  std::ignore = lhs.release();
  return parse_assignment_rhs(std::unique_ptr<DeclRefExpr>(dre));
}

std::unique_ptr<Stmt> Parser::parse_assignment_or_expr() {
  std::unique_ptr<Expr> lhs = parse_prefix_expr();
  if (!lhs)
    return nullptr;
  // Assignment
  if (m_NextToken.kind == TokenKind::Equal) {
    std::unique_ptr<Assignment> assignment = parse_assignment(std::move(lhs));
    if (!assignment)
      return nullptr;
    return assignment;
  }
  std::unique_ptr<Expr> expr = parse_expr_rhs(std::move(lhs), 0);
  if (!expr)
    return nullptr;
  return expr;
}

// <assignment>
// ::= <declRefExpr> '=' <expr>
std::unique_ptr<Assignment>
Parser::parse_assignment_rhs(std::unique_ptr<DeclRefExpr> lhs) {
  SourceLocation loc = m_NextToken.location;
  eat_next_token(); // eat '='
  std::unique_ptr<Expr> rhs = parse_expr();
  if (!rhs)
    return nullptr;
  return std::make_unique<Assignment>(loc, std::move(lhs), std::move(rhs));
}

// <returnStmt>
// ::= 'return' <expr>? ';'
std::unique_ptr<ReturnStmt> Parser::parse_return_stmt() {
  SourceLocation location = m_NextToken.location;
  eat_next_token(); // eat 'return'
  std::unique_ptr<Expr> expr;
  if (m_NextToken.kind != TokenKind::Semicolon) {
    expr = parse_expr();
    if (!expr)
      return nullptr;
  }
  if (m_NextToken.kind != TokenKind::Semicolon) {
    return report(m_NextToken.location,
                  "expected ';' at the end of a statement.");
  }
  eat_next_token(); // eat ';'
  return std::make_unique<ReturnStmt>(location, std::move(expr));
}

// <prefixExpression>
// ::= ('!' | '-')* <primaryExpr>
std::unique_ptr<Expr> Parser::parse_prefix_expr() {
  Token token = m_NextToken;
  if (token.kind != TokenKind::Exclamation && token.kind != TokenKind::Minus)
    return parse_primary_expr();
  eat_next_token(); // eat '!' or '-'
  auto rhs = parse_prefix_expr();
  if (!rhs)
    return nullptr;
  return std::make_unique<UnaryOperator>(token.location, std::move(rhs),
                                         token.kind);
}

// <primaryExpression>
// ::= <numberLiteral>
// | <declRefExpr>
// | <callExpr>
// | '(' <expr> ')'
//
// <numberLiteral>
// ::= <integer>
// | <real>
//
// <declRefExpr>
// ::= <identifier>
//
// <callExpr>
// ::= <declRefExpr> <argList>
std::unique_ptr<Expr> Parser::parse_primary_expr() {
  SourceLocation location = m_NextToken.location;
  // @TODO: distinguish between casting and grouping... or maybe not here, idk
  if (m_NextToken.kind == TokenKind::Lparent) {
    eat_next_token(); // eat '('
    auto expr = parse_expr();
    if (!expr)
      return nullptr;
    if (m_NextToken.kind != TokenKind::Rparent)
      return report(m_NextToken.location, "expected ')'.");
    eat_next_token(); // eat ')'
    return std::make_unique<GroupingExpr>(location, std::move(expr));
  }
  if (m_NextToken.kind == TokenKind::Integer) {
    auto literal = std::make_unique<NumberLiteral>(
        location, NumberLiteral::NumberType::Integer, *m_NextToken.value);
    eat_next_token();
    return literal;
  }
  if (m_NextToken.kind == TokenKind::Real) {
    auto literal = std::make_unique<NumberLiteral>(
        location, NumberLiteral::NumberType::Real, *m_NextToken.value);
    eat_next_token();
    return literal;
  }
  if (m_NextToken.kind == TokenKind::BoolConstant) {
    auto literal = std::make_unique<NumberLiteral>(
        location, NumberLiteral::NumberType::Bool, *m_NextToken.value);
    eat_next_token();
    return literal;
  }
  if (m_NextToken.kind == TokenKind::Identifier) {
    auto declRefExpr =
        std::make_unique<DeclRefExpr>(location, *m_NextToken.value);
    eat_next_token();
    if (m_NextToken.kind != TokenKind::Lparent) {
      return declRefExpr;
    }
    location = m_NextToken.location;
    auto arg_list = parse_argument_list();
    if (!arg_list)
      return nullptr;
    return std::make_unique<CallExpr>(location, std::move(declRefExpr),
                                      std::move(*arg_list));
  }
  return report(location, "expected expression.");
}

// <argList>
// ::= '(' (<expr> (',' <expr>)*)? ')'
std::optional<std::vector<std::unique_ptr<Expr>>>
Parser::parse_argument_list() {
  if (m_NextToken.kind != TokenKind::Lparent) {
    report(m_NextToken.location, "expected '('");
    return std::nullopt;
  }
  eat_next_token(); // eat '('
  std::vector<std::unique_ptr<Expr>> arg_list;
  if (m_NextToken.kind == TokenKind::Rparent) {
    eat_next_token();
    return arg_list;
  }
  while (true) {
    auto expr = parse_expr();
    if (!expr)
      return std::nullopt;
    arg_list.emplace_back(std::move(expr));
    if (m_NextToken.kind != TokenKind::Comma)
      break;
    eat_next_token(); // eat ','
  }
  if (m_NextToken.kind != TokenKind::Rparent) {
    report(m_NextToken.location, "expected ')'.");
    return std::nullopt;
  }
  eat_next_token(); // eat ')'
  return arg_list;
}

// <parameterList>
// ::= '(' (<paramDecl> (',', <paramDecl>)*)? ')'
std::optional<std::vector<std::unique_ptr<ParamDecl>>>
Parser::parse_parameter_list() {
  if (m_NextToken.kind != TokenKind::Lparent) {
    report(m_NextToken.location, "expected '('");
    return std::nullopt;
  }
  eat_next_token(); // eat '('
  std::vector<std::unique_ptr<ParamDecl>> param_decls;
  if (m_NextToken.kind == TokenKind::Rparent) {
    eat_next_token(); // eat ')'
    return param_decls;
  }
  while (true) {
    if (m_NextToken.kind == TokenKind::KwVoid) {
      report(m_NextToken.location, "invalid paramater type 'void'.");
      return std::nullopt;
    }
    if (m_NextToken.kind != TokenKind::Identifier &&
        m_NextToken.kind != TokenKind::KwConst) {
      report(m_NextToken.location, "expected parameter declaration.");
      return std::nullopt;
    }
    auto param_decl = parse_param_decl();
    if (!param_decl)
      return std::nullopt;
    param_decls.emplace_back(std::move(param_decl));
    if (m_NextToken.kind != TokenKind::Comma)
      break;
    eat_next_token(); // eat ','
  }
  if (m_NextToken.kind != TokenKind::Rparent) {
    report(m_NextToken.location, "expected ')'.");
    return std::nullopt;
  }
  eat_next_token(); // eat ')'
  return param_decls;
}

std::unique_ptr<Expr> Parser::parse_expr() {
  auto lhs = parse_prefix_expr();
  if (!lhs)
    return nullptr;
  return parse_expr_rhs(std::move(lhs), 0);
}

int get_tok_precedence(TokenKind tok) {
  switch (tok) {
  case TokenKind::Asterisk:
  case TokenKind::Slash:
    return 6;
  case TokenKind::Plus:
  case TokenKind::Minus:
    return 5;
  case TokenKind::LessThan:
  case TokenKind::LessThanOrEqual:
  case TokenKind::GreaterThan:
  case TokenKind::GreaterThanOrEqual:
    return 4;
  case TokenKind::EqualEqual:
  case TokenKind::ExclamationEqual:
    return 3;
  case TokenKind::AmpAmp:
    return 2;
  case TokenKind::PipePipe:
    return 1;
  default:
    return -1;
  }
}

std::unique_ptr<Expr> Parser::parse_expr_rhs(std::unique_ptr<Expr> lhs,
                                             int precedence) {
  while (true) {
    TokenKind op = m_NextToken.kind;
    int cur_op_prec = get_tok_precedence(op);
    if (cur_op_prec < precedence)
      return lhs;
    eat_next_token();
    auto rhs = parse_prefix_expr();
    if (!rhs)
      return nullptr;
    if (cur_op_prec < get_tok_precedence(m_NextToken.kind)) {
      rhs = parse_expr_rhs(std::move(rhs), cur_op_prec + 1);
      if (!rhs)
        return nullptr;
    }
    lhs = std::make_unique<BinaryOperator>(lhs->location, std::move(lhs),
                                           std::move(rhs), op);
  }
}
// <paramDecl>
// ::= <type> <identifier>
std::unique_ptr<ParamDecl> Parser::parse_param_decl() {
  SourceLocation location = m_NextToken.location;
  bool is_const = false;
  if (m_NextToken.kind == TokenKind::KwConst) {
    is_const = true;
    eat_next_token(); // eat 'const'
  }
  auto type = parse_type();
  if (!type)
    return nullptr;
  if (!m_NextToken.value) {
    return report(location, "expected identifier.");
  }
  std::string id = *m_NextToken.value;
  eat_next_token(); // eat identifier
  return std::make_unique<ParamDecl>(location, std::move(id), std::move(*type),
                                     is_const);
}

// <type>
// ::= 'void'
// |   <identifier>
std::optional<Type> Parser::parse_type() {
  TokenKind kind = m_NextToken.kind;
  if (kind == TokenKind::KwVoid) {
    eat_next_token();
    return Type::builtin_void();
  }
  if (kind == TokenKind::Identifier) {
    assert(m_NextToken.value.has_value());
    if (*m_NextToken.value == "i8") {
      eat_next_token();
      return Type::builtin_i8();
    } else if (*m_NextToken.value == "i16") {
      eat_next_token();
      return Type::builtin_i16();
    } else if (*m_NextToken.value == "i32") {
      eat_next_token();
      return Type::builtin_i32();
    } else if (*m_NextToken.value == "i64") {
      eat_next_token();
      return Type::builtin_i64();
    } else if (*m_NextToken.value == "u8") {
      eat_next_token();
      return Type::builtin_u8();
    } else if (*m_NextToken.value == "u16") {
      eat_next_token();
      return Type::builtin_u16();
    } else if (*m_NextToken.value == "u32") {
      eat_next_token();
      return Type::builtin_u32();
    } else if (*m_NextToken.value == "u64") {
      eat_next_token();
      return Type::builtin_u64();
    } else if (*m_NextToken.value == "f32") {
      eat_next_token();
      return Type::builtin_f32();
    } else if (*m_NextToken.value == "f64") {
      eat_next_token();
      return Type::builtin_f64();
    } else if (*m_NextToken.value == "bool") {
      eat_next_token();
      return Type::builtin_bool();
    }
    Type type = Type::custom(*m_NextToken.value);
    eat_next_token();
    return type;
  }
  report(m_NextToken.location, "expected type specifier.");
  return std::nullopt;
}

// <sourceFile>
// ::= <structDeclStmt>* <funcDecl>* EOF
ParsingResult Parser::parse_source_file() {
  std::vector<std::unique_ptr<Decl>> decls;
  bool is_complete_ast = true;
  const std::vector<TokenKind> sync_kinds{TokenKind::KwFn, TokenKind::KwStruct};
  while (m_NextToken.kind != TokenKind::Eof) {
    if (m_NextToken.kind != TokenKind::KwFn &&
        m_NextToken.kind != TokenKind::KwStruct) {
      report(
          m_NextToken.location,
          "only function and struct declarations are allowed in global scope.");
      is_complete_ast = false;
      sync_on(sync_kinds);
      continue;
    }
    std::unique_ptr<Decl> decl = nullptr;
    if (m_NextToken.kind == TokenKind::KwFn)
      decl = parse_function_decl();
    if (m_NextToken.kind == TokenKind::KwStruct)
      decl = parse_struct_decl();
    if (!decl) {
      is_complete_ast = false;
      sync_on(sync_kinds);
      continue;
    }
    decls.emplace_back(std::move(decl));
  }
  assert(m_NextToken.kind == TokenKind::Eof);
  return {is_complete_ast, std::move(decls)};
}

void Parser::synchronize() {
  m_IsCompleteAst = false;
  int braces = 0;
  while (true) {
    TokenKind kind = m_NextToken.kind;
    if (kind == TokenKind::Lbrace)
      ++braces;
    else if (kind == TokenKind::Rbrace) {
      if (braces == 0)
        break;
      // syncs to next Rbrace
      if (braces == 1) {
        eat_next_token(); // eat '}'
        break;
      }
      --braces;
    } else if (kind == TokenKind::Semicolon && braces == 0) {
      eat_next_token(); // eat ';'
      break;
    } else if (kind == TokenKind::KwFn || kind == TokenKind::Eof)
      break;
    eat_next_token();
  }
}

} // namespace saplang
