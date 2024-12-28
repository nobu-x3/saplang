#include "driver.h"

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

namespace saplang {

std::vector<std::string> split(const std::string &s, char delim) {
  std::vector<std::string> result;
  std::stringstream ss(s);
  std::string item;

  while (getline(ss, item, delim)) {
    result.push_back(item);
  }

  return result;
}

CompilerOptions::CompilerOptions(int argc, const char **argv) {
  for (int idx = 1; idx < argc; ++idx) {
    std::string_view arg = argv[idx];
    if (arg[0] != '-') {
      if (!source.empty()) {
        error("unexpected argument '" + std::string{arg} + ".'\n");
      }
      source = arg;
    } else {
      if (arg == "-h")
        display_help = true;
      else if (arg == "-o")
        output = idx + 1 >= argc ? "" : argv[++idx];
      else if (arg == "-string") {
        input_string = idx + 1 >= argc ? "" : argv[++idx];
        source = "input_string.sl";
      } else if (arg == "-ast-dump")
        ast_dump = true;
      else if (arg == "-res-dump")
        res_dump = true;
      else if (arg == "-cfg-dump")
        cfg_dump = true;
      else if (arg == "-llvm-dump")
        llvm_dump = true;
      else if (arg == "-i")
        import_paths = split(argv[++idx], ';');
      else if (arg == "-L")
        library_paths = split(argv[++idx], ';');
      else if (arg == "-extra")
        extra_flags = split(argv[++idx], ';');
      else if (arg == "-dbg")
        gen_debug = true;
      else if (arg == "-no-cleanup")
        no_cleanup = true;
      else
        error("unexpected argument '" + std::string{arg} + ".'\n");
    }
  }
}

CompilerOptions::CompilerOptions(std::filesystem::path source, std::filesystem::path output) : source(std::move(source)), output(std::move(output)) {}

int Driver::run(std::ostream &output_stream) {
  if (m_Options.display_help) {
    display_help();
    return 0;
  }
  if (m_Options.import_paths.size() == 0) {
    std::filesystem::path src_path{m_Options.source};
    std::filesystem::path abs_src_path{std::filesystem::absolute(src_path)};
    std::filesystem::path parent_path{abs_src_path.parent_path()};
    m_Options.import_paths.push_back(parent_path);
  }
  std::vector<std::unique_ptr<saplang::Module>> modules;
  for (auto &&import_path : m_Options.import_paths) {
    for (const auto &file : std::filesystem::directory_iterator(import_path)) {
      auto filepath = file.path();
      if (filepath.extension() == ".sl") {
        if (filepath.filename() == m_Options.source)
          continue;
        std::stringstream buffer;
        std::string source{filepath};
        std::ifstream file{filepath};
        if (!file) {
          error("failed to open '" + m_Options.source.string() + ".'");
        }
        buffer << file.rdbuf();
        saplang::SourceFile src_file{source, buffer.str()};
        saplang::Lexer lexer{src_file};
        saplang::Parser parser{&lexer, {m_Options.import_paths, true}};
        auto module_parse_result = parser.parse_source_file();
        if (m_Options.ast_dump) {
          std::stringstream ast_stream;
          for (auto &&fn : module_parse_result.module->declarations) {
            fn->dump_to_stream(ast_stream, 0);
          }
          output_stream << ast_stream.str();
          continue;
        }
        if (!module_parse_result.is_complete_ast)
          continue;
        modules.emplace_back(std::move(module_parse_result.module));
      }
    }
  }
  std::set<std::string> libraries;
  for (auto &&module : modules) {
    libraries.merge(module->libraries);
  }
  std::stringstream buffer;
  if (!m_Options.input_string.has_value()) {
    if (m_Options.source.empty())
      error("no source file specified.");
    std::ifstream file{m_Options.source};
    if (!file) {
      error("failed to open '" + m_Options.source.string() + ".'");
    }
    buffer << file.rdbuf();
  } else {
    buffer << *m_Options.input_string;
  }
  std::string source{m_Options.source.string()};
  saplang::SourceFile src_file{source, buffer.str()};
  saplang::Lexer lexer{src_file};
  saplang::Parser parser{&lexer, {m_Options.import_paths, true}};
  auto main_file_parse_result = parser.parse_source_file();
  if (m_Options.ast_dump) {
    std::stringstream ast_stream;
    for (auto &&fn : main_file_parse_result.module->declarations) {
      fn->dump_to_stream(ast_stream, 0);
    }
    output_stream << ast_stream.str();
    return 0;
  }
  if (!main_file_parse_result.is_complete_ast)
    return 1;
  modules.emplace_back(std::move(main_file_parse_result.module));
  saplang::Sema sema{std::move(modules), true};
  auto resolved_modules = sema.resolve_modules(m_Options.res_dump);
  if (m_Options.res_dump) {
    std::stringstream output_stream;
    for (auto &&fn : resolved_modules) {
      fn->dump_to_stream(output_stream, 0);
    }
    output_stream << output_stream.str();
    return 0;
  }
  if (m_Options.cfg_dump) {
    std::stringstream output_stream;
    for (auto &&module : resolved_modules) {
      for (auto &&decl : module->declarations) {
        if (const auto *fn = dynamic_cast<const saplang::ResolvedFuncDecl *>(decl.get())) {
          output_stream << decl->id << ":\n";
          saplang::CFGBuilder().build(*fn).dump_to_stream(output_stream, 1);
          output_stream << output_stream.str();
        }
      }
    }
    return 0;
  }
  if (resolved_modules.empty())
    return 1;
  saplang::Codegen codegen{std::move(resolved_modules), source, sema.move_type_infos(), m_Options.gen_debug};
  auto gened_modules = codegen.generate_modules();
  if (m_Options.gen_debug) {
    for (auto &&[_, mod] : gened_modules) {
      mod->di_builder->finalize();
    }
  }
  if (m_Options.llvm_dump) {
    std::string output_string;
    llvm::raw_string_ostream output_buffer{output_string};
    for (auto &&[name, mod] : gened_modules)
      mod->module->print(output_buffer, nullptr, true, true);
    output_stream << output_string;
    return 0;
  }
  std::stringstream command;
  std::vector<std::string> llvm_ir_paths;
  llvm_ir_paths.reserve(gened_modules.size());
  command << "clang ";
  for (auto &&[name, mod] : gened_modules) {
    std::stringstream path;
    path << "tmp-" << name << ".ll";
    const std::string llvm_ir_path = path.str();
    llvm_ir_paths.push_back(llvm_ir_path);
    std::error_code error_code;
    llvm::raw_fd_ostream f{llvm_ir_path, error_code};
    mod->module->print(f, nullptr);
    command << path.str() << " ";
  }
  if (!m_Options.output.empty())
    command << " -o " << m_Options.output;
  for (auto &&path : m_Options.library_paths) {
    command << " -L" << path;
  }
  for (auto &&lib : libraries) {
    command << " -l" << lib;
  }
  command << " -g -O0";
  /* -ggdb -glldb -gsce -gdbx"; */
  for (auto &&extra_flag : m_Options.extra_flags)
    command << " " << extra_flag;
  int ret = std::system(command.str().c_str());
  if (!m_Options.no_cleanup) {
    for (auto &&llvm_ir_path : llvm_ir_paths)
      std::filesystem::remove(llvm_ir_path);
  }
  return ret;
}

void Driver::display_help() {
  std::cout << "Usage:\n"
            << "compiler [options] <source_file>\n\n"
            << "Options:\n"
            << "\t-h                            display this message.\n"
            << "\t-i \"IMP1;IMP2;...\"          import paths.\n"
            << "\t-L \"PATH1;PATH2\"            library directories.\n"
            << "\t-string <input_string>        use <input_string> instead of "
               "<source_file>.\n"
            << "\t-o <file>                     write executable to <file>.\n"
            << "\t-ast-dump                     print ast.\n"
            << "\t-res-dump                     print resolved syntax tree.\n"
            << "\t-cfg-dump                     print control flow graph.\n"
            << "\t-dbg                          output debug info.\n"
            << "\t-no-cleanup                   do not remove temporary LLVMIR-files after compilation.\n"
            << "\t-llvm-dump                    print the generated llvm module" << std::endl;
}
} // namespace saplang
