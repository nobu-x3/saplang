#pragma once

#include "utils.h"
#include <optional>
#include <unordered_map>

namespace saplang {
constexpr char single_char_tokens[] = {'\0', '(', ')', '{', '}', ':', ';', ',', '+', '-', '*', '<', '>', '!', '.', '&', '[', ']', '"', '~', '^', '|', '%', '\''};

enum class TokenKind : char {
  Unknown = 0,
  Identifier,
  Integer,
  BinInteger,
  Real,
  BoolConstant,
  KwExport,
  KwExtern,
  KwAlias,
  KwFn,
  KwVoid,
  KwReturn,
  KwIf,
  KwElse,
  KwModule,
  KwDefer,
  KwWhile,
  KwFor,
  KwConst,
  KwStruct,
  KwNull,
  KwVar,
  KwImport,
  KwEnum,
  KwSizeof,
  KwAlignof,
  Slash,
  AmpAmp,
  PipePipe,
  EqualEqual,
  ExclamationEqual,
  GreaterThanOrEqual,
  LessThanOrEqual,
  Equal,
  ColonColon,
  vla,
  BitwiseShiftL = 80,
  BitwiseShiftR,
  Eof = single_char_tokens[0],
  Lparent = single_char_tokens[1],
  Rparent = single_char_tokens[2],
  Lbrace = single_char_tokens[3],
  Rbrace = single_char_tokens[4],
  Colon = single_char_tokens[5],
  Semicolon = single_char_tokens[6],
  Comma = single_char_tokens[7],
  Plus = single_char_tokens[8],
  Minus = single_char_tokens[9],
  Asterisk = single_char_tokens[10],
  LessThan = single_char_tokens[11],
  GreaterThan = single_char_tokens[12],
  Exclamation = single_char_tokens[13],
  Dot = single_char_tokens[14],
  Amp = single_char_tokens[15],
  Lbracket = single_char_tokens[16],
  Rbracket = single_char_tokens[17],
  DoubleQuote = single_char_tokens[18],
  Tilda = single_char_tokens[19],
  Hat = single_char_tokens[20],
  Pipe = single_char_tokens[21],
  Percent = single_char_tokens[22],
  SingleQuote = single_char_tokens[23],
  KwSwitch,
  KwCase,
  KwDefault,
};

const std::unordered_map<std::string_view, TokenKind> keywords = {
    {"void", TokenKind::KwVoid},     {"export", TokenKind::KwExport}, {"module", TokenKind::KwModule},   {"defer", TokenKind::KwDefer},
    {"return", TokenKind::KwReturn}, {"fn", TokenKind::KwFn},         {"if", TokenKind::KwIf},           {"else", TokenKind::KwElse},
    {"while", TokenKind::KwWhile},   {"for", TokenKind::KwFor},       {"const", TokenKind::KwConst},     {"var", TokenKind::KwVar},
    {"struct", TokenKind::KwStruct}, {"null", TokenKind::KwNull},     {"enum", TokenKind::KwEnum},       {"extern", TokenKind::KwExtern},
    {"alias", TokenKind::KwAlias},   {"sizeof", TokenKind::KwSizeof}, {"alignof", TokenKind::KwAlignof}, {"import", TokenKind::KwImport},
    {"switch", TokenKind::KwSwitch}, {"case", TokenKind::KwCase},     {"default", TokenKind::KwDefault}};

struct Token {
  SourceLocation location;
  TokenKind kind;
  std::optional<std::string> value;
};

class Lexer {
public:
  explicit Lexer(const SourceFile &source);
  Token get_next_token();
  Token get_prev_token(const Token &token);
  std::string get_string_literal();
  char get_character_literal();
  inline std::string get_source_file_path() const { return std::string{m_Source->path}; }

private:
  char peek_next_char(size_t count = 0) const;
  char eat_next_char();
  char go_back_char();

private:
  const SourceFile *m_Source;
  size_t m_Idx = 0;
  int m_Line = 1;
  int m_Column = 0;
  bool is_reading_string = false;
};

} // namespace saplang
