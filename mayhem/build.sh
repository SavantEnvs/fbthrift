#!/usr/bin/env bash
# Builds, in /mayhem: (1) the plain `thrift` compiler used as the test oracle, (2) the sanitized fuzz
# harnesses + their -standalone reproducers. Dependencies (fmt, folly) come from in-image prefixes
# built by mayhem/build-deps.sh, so this script needs no network and is safe to re-run.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

SRC="${SRC:-/mayhem}"
cd "$SRC"
COMMON=(-G Ninja -DCMAKE_BUILD_TYPE=
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=OFF -DTHRIFT_RPC=OFF
        -DTHRIFT_TESTS=OFF -DTHRIFT_BENCHMARKS=OFF -DTHRIFT_PY_DEPRECATED=OFF
        -DFETCHCONTENT_FULLY_DISCONNECTED=ON)

# 1) Oracle: the unsanitized compiler, project-normal flags.
cmake -S . -B mayhem/build-tests "${COMMON[@]}" -DCMAKE_PREFIX_PATH=/opt/toolchains/deps-plain \
  "-DCMAKE_C_FLAGS=-O2 $COVERAGE_FLAGS" "-DCMAKE_CXX_FLAGS=-O2 $COVERAGE_FLAGS"
cmake --build mayhem/build-tests -j"$MAYHEM_JOBS" --target thrift

# 2) Fuzz harnesses over the sanitized + SanCov-instrumented project. Headers are generated with
#    the oracle compiler (same output, and it keeps sanitizer reports out of code generation).
FLAGS="-O1 $SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS"
cmake -S mayhem -B mayhem/build-fuzz "${COMMON[@]}" -DCMAKE_PREFIX_PATH=/opt/toolchains/deps \
  -DFBTHRIFT_ROOT="$SRC" -DTHRIFT_COMPILER="$SRC/mayhem/build-tests/bin/thrift" \
  -DLSAN_OFF_SRC="$SRC/mayhem/lsan_off.cc" -DFUZZ_ENGINE="$LIB_FUZZING_ENGINE" -DSTANDALONE_MAIN="$STANDALONE_FUZZ_MAIN" \
  "-DCMAKE_C_FLAGS=$FLAGS" "-DCMAKE_CXX_FLAGS=$FLAGS"
TARGETS=(thrift_parse rpc_metadata protocol_object)
ALL=()
for t in "${TARGETS[@]}"; do ALL+=("$t" "$t-standalone"); done
cmake --build mayhem/build-fuzz -j"$MAYHEM_JOBS" --target "${ALL[@]}"

for t in "${ALL[@]}"; do cp "mayhem/build-fuzz/bin/$t" "/mayhem/$t" 2>/dev/null || cp "mayhem/build-fuzz/$t" "/mayhem/$t"; done
