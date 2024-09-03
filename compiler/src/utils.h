#pragma once

#include <iostream>
#include <limits>
#include <optional>
#include <sstream>
#include <string>

namespace saplang {

#if defined(BUILD_TESTS)
const std::stringstream &get_error_stream();
void clear_error_stream();
#endif

struct SourceFile {
  std::string_view path;
  std::string buffer;
};

struct SourceLocation {
  std::string_view path;
  int line;
  int col;
};

class IDumpable {
public:
  virtual ~IDumpable() = default;
  virtual void dump_to_stream(std::stringstream &stream,
                              size_t indent = 0) const = 0;
  virtual void dump(size_t indent = 0) const = 0;
};

inline std::string indent(size_t level) { return std::string(level * 2, ' '); }

std::nullptr_t report(SourceLocation location, std::string_view msg,
                      bool is_warning = false);

template <typename Base, typename Ty> class ConstantValueContainer {
public:
  inline void set_constant_value(std::optional<Ty> val) {
    m_ConstantValue = std::move(val);
  }
  inline const std::optional<Ty>& get_constant_value() const {
    return m_ConstantValue;
  }

private:
  ConstantValueContainer() = default;
  friend Base;

private:
  std::optional<Ty> m_ConstantValue{std::nullopt};
};
} // namespace saplang

static double F64_MAX = std::numeric_limits<double>::max();
static double F64_MIN = std::numeric_limits<double>::min();
static float F32_MAX = std::numeric_limits<float>::max();
static float F32_MIN = std::numeric_limits<float>::min();
static long I64_MAX = std::numeric_limits<long>::max();
static long I64_MIN = std::numeric_limits<long>::min();
static int I32_MAX = std::numeric_limits<int>::max();
static int I32_MIN = std::numeric_limits<int>::min();
static short I16_MAX = std::numeric_limits<short>::max();
static short I16_MIN = std::numeric_limits<short>::min();
static signed char I8_MAX = std::numeric_limits<signed char>::max();
static signed char I8_MIN = std::numeric_limits<signed char>::min();
static unsigned long U64_MAX = std::numeric_limits<unsigned long>::max();
static unsigned long U64_MIN = std::numeric_limits<unsigned long>::min();
static unsigned int U32_MAX = std::numeric_limits<unsigned int>::max();
static unsigned int U32_MIN = std::numeric_limits<unsigned int>::min();
static unsigned short U16_MAX = std::numeric_limits<unsigned short>::max();
static unsigned short U16_MIN = std::numeric_limits<unsigned short>::min();
static unsigned char U8_MAX = std::numeric_limits<unsigned char>::max();
static unsigned char U8_MIN = std::numeric_limits<unsigned char>::min();
