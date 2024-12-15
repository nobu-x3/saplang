#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>

#include "cfg.h"
#include "codegen.h"
#include "lexer.h"
#include "parser.h"
#include "sema.h"
#include "utils.h"

[[noreturn]] void error(std::string_view msg) {
  std::cerr << "error: " << msg << "\n";
  std::exit(1);
}

struct CompilerOptions {
  std::filesystem::path source;
  std::filesystem::path output;
  std::optional<std::string> input_string{std::nullopt};
  std::vector<std::string> import_paths{};
  std::vector<std::string> extra_flags{};
  bool display_help{false};
  bool ast_dump{false};
  bool res_dump{false};
  bool cfg_dump{false};
  bool llvm_dump{false};
};

void display_help() {
  std::cout << "Usage:\n"
            << "compiler [options] <source_file>\n\n"
            << "Options:\n"
            << "\t-h                            display this message.\n"
            << "\t-i \"IMP1;IMP2;...\"          import paths.\n"
            << "\t-string <input_string>        use <input_string> instead of "
               "<source_file>.\n"
            << "\t-o <file>                     write executable to <file>.\n"
            << "\t-ast-dump                     print ast.\n"
            << "\t-res-dump                     print resolved syntax tree.\n"
            << "\t-cfg-dump                     print control flow graph.\n"
            << "\t-llvm-dump                    print the generated llvm module" << std::endl;
}
std::vector<std::string> split(const std::string &s, char delim) {
  std::vector<std::string> result;
  std::stringstream ss(s);
  std::string item;

  while (getline(ss, item, delim)) {
    result.push_back(item);
  }

  return result;
}

CompilerOptions parse_args(int argc, const char **argv) {
  CompilerOptions options{};
  if (argc < 2)
    display_help();
  for (int idx = 1; idx < argc; ++idx) {
    std::string_view arg = argv[idx];
    if (arg[0] != '-') {
      if (!options.source.empty()) {
        error("unexpected argument '" + std::string{arg} + ".'\n");
      }
      options.source = arg;
    } else {
      if (arg == "-h")
        options.display_help = true;
      else if (arg == "-o")
        options.output = idx + 1 >= argc ? "" : argv[++idx];
      else if (arg == "-string") {
        options.input_string = idx + 1 >= argc ? "" : argv[++idx];
        options.source = "input_string.sl";
      } else if (arg == "-ast-dump")
        options.ast_dump = true;
      else if (arg == "-res-dump")
        options.res_dump = true;
      else if (arg == "-cfg-dump")
        options.cfg_dump = true;
      else if (arg == "-llvm-dump")
        options.llvm_dump = true;
      else if (arg == "-i")
        options.import_paths = split(argv[++idx], ';');
      else if (arg == "-extra")
        options.extra_flags = split(argv[++idx], ';');
      else
        error("unexpected argument '" + std::string{arg} + ".'\n");
    }
  }
  return options;
}

int main(int argc, const char **argv) {
  CompilerOptions options = parse_args(argc, argv);
  if (options.display_help) {
    display_help();
    return 0;
  }
  if (options.import_paths.size() == 0) {
    std::filesystem::path src_path{options.source};
    std::filesystem::path abs_src_path{std::filesystem::absolute(src_path)};
    std::filesystem::path parent_path{abs_src_path.parent_path()};
    options.import_paths.push_back(parent_path);
  }
  std::vector<std::unique_ptr<saplang::Module>> modules;
  for (auto &&import_path : options.import_paths) {
    for (const auto &file : std::filesystem::directory_iterator(import_path)) {
      auto filepath = file.path();
      if (filepath.extension() == ".sl") {
        if (filepath.filename() == options.source)
          continue;
        std::stringstream buffer;
        std::string source{filepath};
        std::ifstream file{filepath};
        if (!file) {
          error("failed to open '" + options.source.string() + ".'");
        }
        buffer << file.rdbuf();
        saplang::SourceFile src_file{source, buffer.str()};
        saplang::Lexer lexer{src_file};
        saplang::Parser parser{&lexer, {options.import_paths, true}};
        auto module_parse_result = parser.parse_source_file();
        if (options.ast_dump) {
          std::stringstream ast_stream;
          for (auto &&fn : module_parse_result.module->declarations) {
            fn->dump_to_stream(ast_stream, 0);
          }
          std::cout << ast_stream.str();
          continue;
        }
        if (!module_parse_result.is_complete_ast)
          continue;
        modules.emplace_back(std::move(module_parse_result.module));
      }
    }
  }
  std::stringstream buffer;
  if (!options.input_string.has_value()) {
    if (options.source.empty())
      error("no source file specified.");
    std::ifstream file{options.source};
    if (!file) {
      error("failed to open '" + options.source.string() + ".'");
    }
    buffer << file.rdbuf();
  } else {
    buffer << *options.input_string;
  }
  std::string source{options.source.string()};
  saplang::SourceFile src_file{source, buffer.str()};
  saplang::Lexer lexer{src_file};
  saplang::Parser parser{&lexer, {options.import_paths, true}};
  auto main_file_parse_result = parser.parse_source_file();
  if (options.ast_dump) {
    std::stringstream ast_stream;
    for (auto &&fn : main_file_parse_result.module->declarations) {
      fn->dump_to_stream(ast_stream, 0);
    }
    std::cout << ast_stream.str();
    return 0;
  }
  if (!main_file_parse_result.is_complete_ast)
    return 1;
  modules.emplace_back(std::move(main_file_parse_result.module));
  saplang::Sema sema{std::move(modules), true};
  auto resolved_modules = sema.resolve_modules(options.res_dump);
  if (options.res_dump) {
    std::stringstream output_stream;
    for (auto &&fn : resolved_modules) {
      fn->dump_to_stream(output_stream, 0);
    }
    std::cout << output_stream.str();
    return 0;
  }
  if (options.cfg_dump) {
    std::stringstream output_stream;
    for (auto &&module : resolved_modules) {
      for (auto &&decl : module->declarations) {
        if (const auto *fn = dynamic_cast<const saplang::ResolvedFuncDecl *>(decl.get())) {
          output_stream << decl->id << ":\n";
          saplang::CFGBuilder().build(*fn).dump_to_stream(output_stream, 1);
          std::cout << output_stream.str();
        }
      }
    }
    return 0;
  }
  if (resolved_modules.empty())
    return 1;
  /* saplang::Codegen codegen{std::move(resolved_modules), source}; */
  /* auto llvm_ir = codegen.generate_ir(); */
  /* if (options.llvm_dump) { */
  /*   std::string output_string; */
  /*   llvm::raw_string_ostream output_buffer{output_string}; */
  /*   llvm_ir->print(output_buffer, nullptr, true, true); */
  /*   std::cout << output_string; */
  /*   return 0; */
  /* } */
  /* std::stringstream path; */
  /* path << "tmp-" << std::filesystem::hash_value(options.source) << ".ll"; */
  /* const std::string llvm_ir_path = path.str(); */
  /* std::error_code error_code; */
  /* llvm::raw_fd_ostream f{llvm_ir_path, error_code}; */
  /* llvm_ir->print(f, nullptr); */
  /* std::stringstream command; */
  /* command << "clang " << llvm_ir_path; */
  /* if (!options.output.empty()) */
  /*   command << " -o " << options.output; */
  /* command << " -g -O0 -ggdb -glldb -gsce -gdbx"; */
  /* for (auto &&extra_flag : options.extra_flags) */
  /*   command << extra_flag; */
  /* int ret = std::system(command.str().c_str()); */
  /* // std::filesystem::remove(llvm_ir_path); */
  /* return ret; */
}
