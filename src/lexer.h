#pragma once

#include "utils.h"
#include <optional>
#include <unordered_map>

namespace saplang {
constexpr char single_char_tokens[] = {'\0', '(', ')', '{', '}', ':', ';'};

enum class TokenKind : char {
  Unknown = -128,
  Identifier,
  KwExport,
  KwFn,
  KwVoid,
  KwReturn,
  KwModule,
  KwDefer,
  // KwI8,
  // KwI16,
  // KwI32,
  // KwI64,
  // KwU8,
  // KwU16,
  // KwU32,
  // KwU64,
  // KwBool,
  Eof = single_char_tokens[0],
  Lparent = single_char_tokens[1],
  Rparent = single_char_tokens[2],
  Lbrace = single_char_tokens[3],
  Rbrace = single_char_tokens[4],
  Colon = single_char_tokens[5],
  Semicolon = single_char_tokens[6],
};

const std::unordered_map<std::string_view, TokenKind> keywords = {
    {"void", TokenKind::KwVoid},     {"export", TokenKind::KwExport},
    {"module", TokenKind::KwModule}, {"defer", TokenKind::KwDefer},
    {"return", TokenKind::KwReturn}, {"fn", TokenKind::KwFn},
    // {"i8", TokenKind::KwI8}, {"i16", TokenKind::}
};

struct Token {
  SourceLocation location;
  TokenKind kind;
  std::optional<std::string> value;
};

class Lexer {
public:
  explicit Lexer(const SourceFile &source);
  Token get_next_token();

private:
  char peek_next_char() const;
  char eat_next_char();

private:
  const SourceFile *m_Source;
  size_t m_Idx = 0;
  int m_Line = 1;
  int m_Column = 0;
};

} // namespace saplang
