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
    return report(m_NextToken.location,
                  "failed to parse function declaration.");
  }
  if (m_NextToken.kind != TokenKind::Identifier || !m_NextToken.value) {
    return report(m_NextToken.location, "expected function identifier.");
  }
  std::string function_identifier = *m_NextToken.value;
  eat_next_token(); // eat '('
  if (m_NextToken.kind != TokenKind::Lparent)
    return report(m_NextToken.location, "expected '('.");
  eat_next_token();
  if (m_NextToken.kind != TokenKind::Rparent)
    return report(m_NextToken.location, "expected ')'.");
  std::unique_ptr<Block> block = parse_block();
  if (!block) {
    return report(m_NextToken.location, "failed to parse function block.");
  }
  return std::make_unique<FunctionDecl>(location, function_identifier,
                                        *return_type, std::move(block));
}

// <block>
// ::= '{' '}'
std::unique_ptr<Block> Parser::parse_block() {
  SourceLocation location = m_NextToken.location;
  eat_next_token(); // eats '{'
  if (m_NextToken.kind != TokenKind::Lbrace)
    return report(m_NextToken.location,
                  "expected '{' at the beginning of a block.");
  eat_next_token(); // eats '}'
  if (m_NextToken.kind != TokenKind::Rbrace)
    return report(m_NextToken.location, "expected '}' at the end of a block.");
  return std::make_unique<Block>(location);
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
    eat_next_token();
  }
  assert(m_NextToken.kind == TokenKind::Eof);
  return {is_complete_ast, std::move(functions)};
}
} // namespace saplang
