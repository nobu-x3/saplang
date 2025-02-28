#include "lexer.h"

namespace saplang {

bool is_space(char c) { return c == ' ' || c == '\f' || c == '\n' || c == '\r' || c == '\t' || c == '\v'; }

bool is_alpha(char c) { return ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z') || (c == '_'); }

bool is_num(char c) { return ('0' <= c && c <= '9'); }

bool is_alphanum(char c) { return is_alpha(c) || is_num(c); }

bool is_special(char c) {
  for (auto &&character : single_char_tokens) {
    if (c == character)
      return true;
  }
  return false;
}

bool is_keyword(TokenKind kind) {
  return (kind >= TokenKind::KwExport && kind <= TokenKind::KwAlignof) || (kind >= TokenKind::KwSwitch && kind <= TokenKind::KwDefault);
}

Lexer::Lexer(const SourceFile &source) : m_Source(&source) {}

Token Lexer::get_prev_token(const Token &token) {
  while (m_Idx != token.location.id - 1)
    go_back_char();
  return get_next_token();
}

Token Lexer::get_next_token() {
  char curr_char = eat_next_char();
  while (is_space(curr_char))
    curr_char = eat_next_char();
  SourceLocation token_start_location{m_Source->path, m_Line, m_Column, m_Idx};
  if (curr_char == '!' && peek_next_char() == '=') {
    eat_next_char();
    return Token{token_start_location, TokenKind::ExclamationEqual, "!="};
  }
  if (curr_char == '<') {
    if (peek_next_char() == '=') {
      eat_next_char();
      return Token{token_start_location, TokenKind::LessThanOrEqual, "<="};
    } else if (peek_next_char() == '<') {
      eat_next_char();
      return Token{token_start_location, TokenKind::BitwiseShiftL, "<<"};
    }
  }
  if (curr_char == '>') {
    if (peek_next_char() == '=') {
      eat_next_char();
      return Token{token_start_location, TokenKind::GreaterThanOrEqual, ">="};
    } else if (peek_next_char() == '>') {
      eat_next_char();
      return Token{token_start_location, TokenKind::BitwiseShiftR, ">>"};
    }
  }
  if (curr_char == ':' && peek_next_char() == ':') {
    eat_next_char();
    return Token{token_start_location, TokenKind::ColonColon, "::"};
  }
  if (curr_char == '/') {
    if (peek_next_char() != '/')
      return Token{token_start_location, TokenKind::Slash, "/"};
    char c = eat_next_char();
    while (c != '\n' && c != '\0')
      c = eat_next_char();
    return get_next_token();
  }
  if (curr_char == '=') {
    if (peek_next_char() == '=') {
      eat_next_char();
      return Token{token_start_location, TokenKind::EqualEqual, "=="};
    }
    return Token{token_start_location, TokenKind::Equal, "="};
  }
  if (curr_char == '&') {
    if (peek_next_char() == '&') {
      eat_next_char();
      return Token{token_start_location, TokenKind::AmpAmp, "&&"};
    } else {
      return Token{token_start_location, TokenKind::Amp, "&"};
    }
  }
  if (curr_char == '.' && peek_next_char() == '.' && peek_next_char(1) == '.') {
    eat_next_char();
    eat_next_char();
    return Token{token_start_location, TokenKind::vla, "..."};
  }
  if (curr_char == '|' && peek_next_char() == '|') {
    eat_next_char();
    return Token{token_start_location, TokenKind::PipePipe, "||"};
  }
  int index = 0;
  for (auto &&c : single_char_tokens) {
    // TODO: manually write it out to avoid branching for better performance.
    if (c == curr_char) {
      return Token{token_start_location, static_cast<TokenKind>(static_cast<int>(TokenKind::SINGLE_CHAR_TOKENS_START) + index), std::string{c}};
    }
    ++index;
  }
  std::string value{curr_char};
  if (is_alpha(curr_char)) {
    while (is_alphanum(peek_next_char())) {
      value += eat_next_char();
    }
    // TIL unordered_map::count return 1 if found and 0 if not aka C++17
    // .contains
    if (value == "true" || value == "false") {
      return Token{token_start_location, TokenKind::BoolConstant, std::move(value)};
    }
    if (keywords.count(value)) {
      return Token{token_start_location, keywords.at(value), std::move(value)};
    }
    return Token{token_start_location, TokenKind::Identifier, std::move(value)};
  }
  if (is_num(curr_char)) {
    // parsing binary number literals
    if (curr_char == '0' && peek_next_char() == 'b') {
      std::string value;
      eat_next_char();
      while (is_num(peek_next_char())) {
        value += eat_next_char();
      }
      return Token{token_start_location, TokenKind::BinInteger, std::move(value)};
    }
    std::string value{curr_char};
    while (is_num(peek_next_char()))
      value += eat_next_char();
    if (peek_next_char() != '.') {
      return Token{token_start_location, TokenKind::Integer, std::move(value)};
    }
    value += eat_next_char();
    if (!is_num(peek_next_char()))
      return Token{token_start_location, TokenKind::Unknown, std::move(value)};
    while (is_num(peek_next_char()))
      value += eat_next_char();
    return Token{token_start_location, TokenKind::Real, std::move(value)};
  }
  return Token{token_start_location, TokenKind::Unknown, std::move(value)};
}

std::string Lexer::get_string_literal() {
  std::stringstream stream;
  is_reading_string = true;
  char curr_char = eat_next_char();
  while (curr_char != '"') {
    stream << curr_char;
    curr_char = eat_next_char();
  }
  is_reading_string = false;
  return stream.str();
}

char Lexer::get_character_literal() {
  is_reading_string = true;
  char curr_char = eat_next_char(); // should eat single quote
  if (curr_char == '\\') {
    curr_char = eat_next_char();
    switch (curr_char) {
    case 'n':
      return '\n';
    case 't':
      return '\t';
    case 'r':
      return '\r';
    case '\\':
      return '\\';
    case '\'':
      return '\'';
    case '"':
      return '"';
    }
  }
  is_reading_string = false;
  return curr_char;
}

char Lexer::peek_next_char(size_t count) const { return m_Source->buffer[m_Idx + count]; }

char Lexer::eat_next_char() {
  ++m_Column;
  if (m_Source->buffer[m_Idx] == '\n' && !is_reading_string) {
    ++m_Line;
    m_Column = 0;
  }
  return m_Source->buffer[m_Idx++];
}

char Lexer::go_back_char() {
  --m_Column;
  if (m_Column <= 0) {
    --m_Line;
    for (int i = 0; i < m_Line; ++i) {
      int col = 0;
      while (m_Source->buffer[col] != '\n')
        ++col;
      m_Column = col;
    }
  }
  return m_Source->buffer[--m_Idx];
}
} // namespace saplang
