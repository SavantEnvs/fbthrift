# syntax=docker/dockerfile:1.7
# Commit image for fbthrift: base + pinned deps (folly/fmt in-image under /opt/toolchains) + the
# repo at /mayhem built by mayhem/build.sh.
FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

USER root
RUN [ -z "$SOURCE_DATE_EPOCH" ] || repro-sources-list.sh; \
    apt-get update && apt-get install -yq --no-install-recommends \
      cmake ninja-build git ca-certificates curl pkg-config \
      libboost-context-dev libboost-filesystem-dev libboost-program-options-dev libboost-regex-dev \
      libboost-system-dev libboost-thread-dev libboost-dev \
      libgflags-dev libgoogle-glog-dev libevent-dev libdouble-conversion-dev libssl-dev zlib1g-dev \
      libzstd-dev liblz4-dev libsnappy-dev libbz2-dev liblzma-dev libunwind-dev libdwarf-dev \
      libiberty-dev libsodium-dev libxxhash-dev libfast-float-dev libgtest-dev \
 && rm -rf /var/lib/apt/lists/*

# Dependencies are built once, from pinned sources, into fixed $HOME-independent prefixes; the layer
# only depends on build-deps.sh, so source edits never rebuild it.
COPY mayhem/build-deps.sh /opt/mayhem/build-deps.sh
RUN MAYHEM_JOBS="$MAYHEM_JOBS" bash /opt/mayhem/build-deps.sh sanitized
RUN MAYHEM_JOBS="$MAYHEM_JOBS" bash /opt/mayhem/build-deps.sh plain

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
