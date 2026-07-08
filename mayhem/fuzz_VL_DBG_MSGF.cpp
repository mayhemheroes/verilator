// Fuzz harness for Verilator's runtime debug-message formatter.
//
// VL_DBG_MSGF (include/verilated.cpp) forwards its (printf-style) format argument to
// Verilator's own _vl_string_vprintf() format parser. We drive that parser with
// fuzzer-controlled bytes as the format string — exercising Verilator's format handling.
//
// Uses no libFuzzer-only headers so the same source links against both the fuzzing
// engine and the standalone (run-once) reproducer driver.
#include <climits>
#include <cstddef>
#include <cstdint>
#include <string>

#include "verilated.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    // NUL-terminated copy so it is a valid C string for the format parser.
    const std::string fmt(reinterpret_cast<const char*>(data), size);
    VL_DBG_MSGF(fmt.c_str());
    return 0;
}
