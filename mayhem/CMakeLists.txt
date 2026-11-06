# Wrapper project: builds fbthrift from the repo root (RPC stack off) and the fuzz harnesses against
# it, so the fuzzed code gets the same sanitizer/SanCov flags as the harnesses.
cmake_minimum_required(VERSION 3.24)
project(fbthrift_mayhem LANGUAGES C CXX)

set(THRIFT_RPC OFF CACHE BOOL "" FORCE)
set(THRIFT_TESTS OFF CACHE BOOL "" FORCE)
set(THRIFT_BENCHMARKS OFF CACHE BOOL "" FORCE)
set(THRIFT_PY_DEPRECATED OFF CACHE BOOL "" FORCE)
add_subdirectory(${FBTHRIFT_ROOT} ${CMAKE_BINARY_DIR}/fbthrift EXCLUDE_FROM_ALL)

set(FUZZ_ENGINE "" CACHE STRING "link flags for the fuzz engine")
set(STANDALONE_MAIN "" CACHE FILEPATH "run-once driver (C source) for the -standalone reproducers")

function(add_harness name)
  foreach(variant IN ITEMS fuzz standalone)
    if(variant STREQUAL fuzz)
      set(tgt ${name})
      set(extra "")
    else()
      set(tgt ${name}-standalone)
      set(extra ${STANDALONE_MAIN})
    endif()
    add_executable(${tgt} EXCLUDE_FROM_ALL ${CMAKE_CURRENT_SOURCE_DIR}/harness/${name}.cc
                   ${LSAN_OFF_SRC} ${extra})
    target_compile_features(${tgt} PRIVATE cxx_std_20)
    target_include_directories(${tgt} PRIVATE ${FBTHRIFT_ROOT} ${CMAKE_BINARY_DIR}/fbthrift)
    target_link_libraries(${tgt} PRIVATE ${ARGN})
    if(variant STREQUAL fuzz)
      separate_arguments(_engine NATIVE_COMMAND "${FUZZ_ENGINE}")
      target_link_libraries(${tgt} PRIVATE ${_engine})
    endif()
  endforeach()
endfunction()

add_harness(thrift_parse thrift_frontend thrift_generators thrift_generator_util thrift_ast)
add_harness(rpc_metadata thrift_rpc_metadata thrift_protocol)
add_harness(protocol_object thrift_metadata thrift_protocol)
