#include <cassert>

#include "parser.h"

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
std::unique_ptr<Stmt> Parser::parse_stmt() {
  if (m_NextToken.kind == TokenKind::KwReturn)
    return parse_return_stmt();
  auto expr = parse_expr();
  if (!expr)
    return nullptr;
  if (m_NextToken.kind != TokenKind::Semicolon) {
    return report(m_NextToken.location,
                  "expected ';' at the end of a statement.");
  }
  eat_next_token();
  return expr;
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

// <primaryExpression>
// ::= <numberLiteral>
// | <declRefExpr>
// | <callExpr>
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
    if (m_NextToken.kind != TokenKind::Identifier) {
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

std::unique_ptr<Expr> Parser::parse_expr() { return parse_primary_expr(); }

// <paramDecl>
// ::= <type> <identifier>
std::unique_ptr<ParamDecl> Parser::parse_param_decl() {
  SourceLocation location = m_NextToken.location;
  auto type = parse_type();
  if (!type)
    return nullptr;
  if (!m_NextToken.value) {
    return report(location, "expected identifier.");
  }
  std::string id = *m_NextToken.value;
  eat_next_token(); // eat identifier
  return std::make_unique<ParamDecl>(location, std::move(id), std::move(*type));
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
    } else if (*m_NextToken.value == "f8") {
      eat_next_token();
      return Type::builtin_f8();
    } else if (*m_NextToken.value == "f16") {
      eat_next_token();
      return Type::builtin_f16();
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
// ::= <funcDecl>* EOF
FuncParsingResult Parser::parse_source_file() {
  std::vector<std::unique_ptr<FunctionDecl>> functions;
  bool is_complete_ast = true;
  while (m_NextToken.kind != TokenKind::Eof) {
    if (m_NextToken.kind != TokenKind::KwFn) {
      report(m_NextToken.location,
             "only function definitions are allowed in global scope.");
      is_complete_ast = false;
      sync_on(TokenKind::KwFn);
      continue;
    }
    auto fn = parse_function_decl();
    if (!fn) {
      is_complete_ast = false;
      sync_on(TokenKind::KwFn);
      continue;
    }
    functions.emplace_back(std::move(fn));
  }
  assert(m_NextToken.kind == TokenKind::Eof);
  return {is_complete_ast, std::move(functions)};
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
