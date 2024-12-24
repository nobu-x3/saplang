#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <sstream>
#include <vector>

namespace saplang {

std::vector<std::string> split(const std::string &s, char delim);

struct CompilerOptions {
  std::filesystem::path source;
  std::filesystem::path output;
  std::optional<std::string> input_string{std::nullopt};
  std::vector<std::string> import_paths{};
  std::vector<std::string> library_paths{};
  std::vector<std::string> extra_flags{};
  bool gen_debug{false};
  bool display_help{false};
  bool ast_dump{false};
  bool res_dump{false};
  bool cfg_dump{false};
  bool llvm_dump{false};
  CompilerOptions(int argc, const char **argv);
  CompilerOptions(std::filesystem::path source, std::filesystem::path output);
};

class Driver {
public:
  inline Driver(int argc, const char **argv) : m_Options(argc, argv){}
  inline Driver(const CompilerOptions& options) : m_Options(options){}
  int run(std::ostream& output_stream);
  static void display_help();

private:
  CompilerOptions m_Options;
};
} // namespace saplang
