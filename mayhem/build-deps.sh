#!/usr/bin/env bash
# Builds fbthrift's C++ dependencies from pinned sources into a fixed in-image prefix, so
# mayhem/build.sh (re-run offline by the PATCH tier) never needs the network.
#   build-deps.sh sanitized   -> /opt/toolchains/deps       (ASan+UBSan+SanCov: linked into fuzz targets)
#   build-deps.sh plain       -> /opt/toolchains/deps-plain (no sanitizers: linked into the test oracle)
# Also (sanitized only) vendors fizz/wangle/mvfst sources for FetchContent at /opt/toolchains/deps-src.
set -euo pipefail
MODE="$1"
: "${MAYHEM_JOBS:=$(nproc)}"
[ -n "$MAYHEM_JOBS" ] || MAYHEM_JOBS=$(nproc)

FMT_URL=https://github.com/fmtlib/fmt/archive/refs/tags/12.1.0.tar.gz
FMT_SHA=ea7de4299689e12b6dddd392f9896f08fb0777ac7168897a244a6d6085043fea
FOLLY_REV=872b8e9255b0e6c823e5c97dcabe3152117b52df
MVFST_REV=176f9dce7b6684017ebb58007d72ba62440fa871
WANGLE_REV=f39fe35931454b4723dd2d983aba208d605a1ae7
FIZZ_REV=f05a12cc6d765d71bc6fce7f9cc0d8e7471cec32

case "$MODE" in
  sanitized)
    PREFIX=/opt/toolchains/deps
    FLAGS="-O1 ${SANITIZER_FLAGS:-} -fsanitize=fuzzer-no-link ${DEBUG_FLAGS:--g -gdwarf-3}" ;;
  plain)
    PREFIX=/opt/toolchains/deps-plain
    FLAGS="-O1" ;;
  *) echo "usage: $0 sanitized|plain" >&2; exit 2 ;;
esac

W=/tmp/deps-$MODE
rm -rf "$W"; mkdir -p "$W" "$PREFIX"
fetch_git() { # name url rev dest
  mkdir -p "$4"; git -C "$4" init -q
  git -C "$4" fetch -q --depth 1 "$2" "$3"
  git -C "$4" checkout -q FETCH_HEAD
}

common=(-G Ninja -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ "-DCMAKE_C_FLAGS=$FLAGS"
        "-DCMAKE_CXX_FLAGS=$FLAGS" -DCMAKE_BUILD_TYPE= -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=OFF "-DCMAKE_INSTALL_PREFIX=$PREFIX" "-DCMAKE_PREFIX_PATH=$PREFIX")

curl -fsSL "$FMT_URL" -o "$W/fmt.tgz"
echo "$FMT_SHA  $W/fmt.tgz" | sha256sum -c -
mkdir -p "$W/fmt" && tar -xzf "$W/fmt.tgz" -C "$W/fmt" --strip-components=1
cmake -S "$W/fmt" -B "$W/fmt-b" "${common[@]}" -DFMT_TEST=OFF -DFMT_DOC=OFF
cmake --build "$W/fmt-b" -j"$MAYHEM_JOBS" && cmake --install "$W/fmt-b"

fetch_git folly https://github.com/facebook/folly.git "$FOLLY_REV" "$W/folly"
cmake -S "$W/folly" -B "$W/folly-b" "${common[@]}" -DBUILD_TESTS=OFF -DBUILD_BENCHMARKS=OFF
cmake --build "$W/folly-b" -j"$MAYHEM_JOBS" && cmake --install "$W/folly-b"

if [ "$MODE" = sanitized ]; then
  S=/opt/toolchains/deps-src; mkdir -p "$S"
  fetch_git fizz   https://github.com/facebookincubator/fizz.git "$FIZZ_REV"   "$S/fizz"
  fetch_git wangle https://github.com/facebook/wangle.git          "$WANGLE_REV" "$S/wangle"
  fetch_git mvfst  https://github.com/facebook/mvfst.git           "$MVFST_REV"  "$S/mvfst"
fi
rm -rf "$W"
