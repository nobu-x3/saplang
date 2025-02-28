#pragma once

#include "utils.h"
#include <optional>
#include <unordered_map>

namespace saplang {
constexpr char single_char_tokens[] = {'\0', '(', ')', '{', '}', ':', ';', ',', '+', '-', '*', '<',
                                       '>',  '!', '.', '&', '[', ']', '"', '~', '^', '|', '%', '\''};

enum class TokenKind : int {
  Unknown = 0,
  Void,
  Bool,
  u8,
  u16,
  u32,
  u64,
  i8,
  i16,
  i32,
  i64,
  f32,
  f64,
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
  BitwiseShiftL,
  BitwiseShiftR,
  Eof,
  Lparent,
  Rparent,
  Lbrace,
  Rbrace,
  Colon,
  Semicolon,
  Comma,
  Plus,
  Minus,
  Asterisk,
  LessThan,
  GreaterThan,
  Exclamation,
  Dot,
  Amp,
  Lbracket,
  Rbracket,
  DoubleQuote,
  Tilda,
  Hat,
  Pipe,
  Percent,
  SingleQuote,
  KwSwitch,
  KwCase,
  KwDefault,
  SINGLE_CHAR_TOKENS_START = Eof,
  SINGLE_CHAR_TOKENS_END = SingleQuote,
};

const std::unordered_map<std::string_view, TokenKind> keywords = {
    {"void", TokenKind::KwVoid},     {"export", TokenKind::KwExport}, {"module", TokenKind::KwModule},   {"defer", TokenKind::KwDefer},
    {"return", TokenKind::KwReturn}, {"fn", TokenKind::KwFn},         {"if", TokenKind::KwIf},           {"else", TokenKind::KwElse},
    {"while", TokenKind::KwWhile},   {"for", TokenKind::KwFor},       {"const", TokenKind::KwConst},     {"var", TokenKind::KwVar},
    {"struct", TokenKind::KwStruct}, {"null", TokenKind::KwNull},     {"enum", TokenKind::KwEnum},       {"extern", TokenKind::KwExtern},
    {"alias", TokenKind::KwAlias},   {"sizeof", TokenKind::KwSizeof}, {"alignof", TokenKind::KwAlignof}, {"import", TokenKind::KwImport},
    {"switch", TokenKind::KwSwitch}, {"case", TokenKind::KwCase},     {"default", TokenKind::KwDefault}, {"i8", TokenKind::i8},
    {"u8", TokenKind::u8},           {"i16", TokenKind::i16},         {"u16", TokenKind::u16},           {"i32", TokenKind::i32},
    {"u32", TokenKind::u32},         {"i64", TokenKind::i64},         {"u64", TokenKind::u64},           {"f32", TokenKind::f32},
    {"f64", TokenKind::f64},         {"bool", TokenKind::Bool}};

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
