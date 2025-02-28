import io;
import ctype;

export enum TokenType {
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
  KwSwitch,
  KwCase,
  KwDefault,
  EOF
}

export struct SourceLocation {
    u64 index;
    u64 row;
    u64 col;
}

export struct Token {
    TokenType type;
    u8[64] text;
}

export struct Scanner {
    const u8* input;
    u64 index;

}

export fn Token next_token(Scanner* scanner) {
    while(scanner.input[scanner.index] && isspace(scanner.input[scanner.index])){
        scanner.input = scanner.input + 1;
    }
    if(scanner.input[scanner.index] == '\0') {
        return .{.type = TokenType::EOF};
    }
    if(strncmp(&scanner.input[scanner.index], "i32", 3) && !isalnum(scanner.input[scanner.index + 3])) {
        scanner.input = scanner.input + 3;
        var Token tok = .{TokenType::i32};
        strcpy(tok.text, "i32");
        return tok;
    }
}