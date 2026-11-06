#!/usr/bin/env bash
#
# mayhem/test.sh — runs fbthrift's golden-fixture suite through the pre-built plain `thrift` compiler.
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Oracle: upstream's compiler fixtures (thrift/compiler/test/fixtures/*/cmd). Each line
# `<outdir>: <generator[:opts]> src/<file>.thrift` is replayed through the pre-built, unsanitized
# `thrift` compiler exactly as build_fixtures.py does, and the generated tree is diffed against the
# checked-in golden `out/<outdir>/`. A compiler that exits 0 without generating (or generates
# anything different from a golden file) fails every case.
THRIFT="$SRC/mayhem/build-tests/bin/thrift"
FIX="$SRC/thrift/compiler/test/fixtures"
[ -x "$THRIFT" ] || { echo "missing $THRIFT: mayhem/build.sh must build it" >&2; emit_ctrf "fbthrift-fixtures" 0 1 0; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

run_case() { # <fixture> <outdir> <generator> <src>
  local fx="$1" name="$2" gen="$3" src="$4" out args=() sep=:
  out="$WORK/$fx/$name"
  mkdir -p "$out"
  case "$gen" in *cpp2*|*schema*|*mstch_java*|*mstch_python*|*-ast*) ;; *) args+=(-r) ;; esac
  case "$gen" in
    *mstch_cpp*|*mstch_py3*|*mstch_python_capi*)
      case "$gen" in *:*) sep=, ;; esac
      gen="$gen$sep"include_prefix="thrift/compiler/test/fixtures/$fx" ;;
  esac
  (cd "$SRC" && "$THRIFT" -I "$FIX/$fx" -I "$SRC" "${args[@]}" -o "$out" --gen "$gen" \
      "thrift/compiler/test/fixtures/$fx/$src") >"$WORK/$fx.$name.log" 2>&1 || return 1
  # The checked-in goldens omit some generated files (internal `facebook/` trees, empty dirs), so
  # compare golden -> output: a missing or differing golden file fails, extra output files do not.
  local golden="$FIX/$fx/out/$name"
  [ -d "$golden" ] || { golden="$WORK/empty"; mkdir -p "$golden"; }
  local delta
  delta="$(diff -r "$golden" "$out" 2>&1 | grep -v "^Only in $out")"
  printf '%s\n' "$delta" >>"$WORK/$fx.$name.log"
  [ -z "$delta" ]
}

passed=0; failed=0; skipped=0
for cmdfile in "$FIX"/*/cmd; do
  fx="$(basename "$(dirname "$cmdfile")")"
  while read -r name gen src extra; do
    case "$name" in ''|'#'*) continue ;; esac
    name="${name%:}"
    gen="${gen//\\/}"   # shlex-style unescape of \" in generator options
    case "$gen" in thrift2ast-*) skipped=$((skipped+1)); continue ;; esac
    if run_case "$fx" "$name" "$gen" "$src"; then
      passed=$((passed+1))
    else
      failed=$((failed+1)); echo "FAIL $fx/$name" >&2; head -5 "$WORK/$fx.$name.log" >&2
    fi
  done < "$cmdfile"
done
emit_ctrf "fbthrift-fixtures" "$passed" "$failed" "$skipped"
