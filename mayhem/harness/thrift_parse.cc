// Fuzzes the Thrift IDL compiler front end: lexer, parser and semantic analysis (all validators).
#include <cstddef>
#include <cstdint>
#include <exception>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include <thrift/compiler/diagnostic.h>
#include <thrift/compiler/parse/parse_ast.h>
#include <thrift/compiler/sema/sema_context.h>
#include <thrift/compiler/source_location.h>

using namespace apache::thrift::compiler;

namespace {
// Includes never resolve to real files: each input is a self-contained, in-memory program.
struct empty_backend : source_manager_backend {
  std::optional<std::vector<char>> read_file(std::string_view) override {
    return std::nullopt;
  }
  bool exists(const std::filesystem::path&) override { return false; }
};
} // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  // add_virtual_file() copies size+1 bytes: the source must be NUL-terminated.
  std::string text(reinterpret_cast<const char*>(data), size);
  source_manager sm(std::make_unique<empty_backend>());
  sm.add_virtual_file("input.thrift", std::string_view(text.c_str(), text.size()));
  auto diags = diagnostics_engine::ignore_all(sm);
  parsing_params params;
  params.allow_missing_includes = true;
  sema_params sparams;
  try {
    parse_ast(sm, diags, "input.thrift", params, &sparams);
  } catch (const std::exception&) {
  }
  return 0;
}
