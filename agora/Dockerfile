# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the builder image
#     E.g.: docker.io/hexpm/elixir:1.17.3-erlang-25.3.2.8-debian-trixie-20260610-slim
#   - https://hub.docker.com/_/debian/tags?name=trixie-20260610-slim - for the runner image
#     E.g.: docker.io/debian:trixie-20260610-slim
#
# Find builder and runner images on Docker Hub or on Hex's Build Server (Bob).
# We recommend using Bob's Web UI to find recent tags:
#
#   - https://bob.hex.pm/docker
#
# We suggest using the same Debian version for both the builder and runner images.
#
# We suggest Debian/Ubuntu instead of Alpine to avoid production compatibility issues
# (such as DNS resolution failures, and dynamically linked NIFs/precompiled binaries).
#
# For finding packages in Debian, search on https://packages.debian.org/.

ARG ELIXIR_VERSION=1.17.3
ARG OTP_VERSION=25.3.2.8
ARG DEBIAN_VERSION=trixie-20260610-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

# Live transcription (see Agora.Media.Audio.WhisperServer's moduledoc).
# Pinned the same way scripts/setup_whisper.sh pins it for local dev.
# WHISPER_LIVE_MODEL is the fast model whisper-server uses for real-time
# captions; WHISPER_FINAL_MODEL is the more accurate one
# Agora.Media.Audio.WhisperCli uses for the one-shot post-broadcast pass
# — see that module's moduledoc for why a bigger model is fine there.
ARG WHISPER_CPP_VERSION=v1.7.6
ARG WHISPER_LIVE_MODEL=base.en
ARG WHISPER_FINAL_MODEL=small.en

# Built in its own stage, independent of the Elixir build below: this
# stage's inputs (a pinned upstream tag + ~600MB of ggml model weights)
# change on a completely different cadence than `mix deps.get`/app code,
# and Docker only re-runs a stage when *its own* inputs change — so an
# ordinary `mix.exs`/`lib/` change never re-triggers this clone-and-compile,
# and BuildKit can run it in parallel with the `builder` stage below.
FROM docker.io/debian:${DEBIAN_VERSION} AS whisper-builder

ARG WHISPER_CPP_VERSION
ARG WHISPER_LIVE_MODEL
ARG WHISPER_FINAL_MODEL

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential cmake git ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch ${WHISPER_CPP_VERSION} \
      https://github.com/ggml-org/whisper.cpp.git /whisper.cpp

WORKDIR /whisper.cpp

# Static build (-DBUILD_SHARED_LIBS=OFF): confirmed hands-on, the default
# shared-lib build's binaries only run from inside their own build tree
# (rpath points at build/ggml/src/*.so) — useless once copied into the
# runner stage below. Static linking needs nothing at runtime beyond
# what's already on any Debian box (libstdc++/libgomp/libc), same deal
# as ffmpeg.
RUN cmake -B build -DCMAKE_BUILD_TYPE=Release -DWHISPER_BUILD_EXAMPLES=ON \
      -DWHISPER_BUILD_SERVER=ON -DBUILD_SHARED_LIBS=OFF \
  && cmake --build build --config Release -j$(nproc) --target whisper-cli whisper-server \
  && mkdir -p /whisper/bin /whisper/models \
  && cp build/bin/whisper-cli build/bin/whisper-server /whisper/bin/ \
  && strip /whisper/bin/whisper-cli /whisper/bin/whisper-server \
  && bash ./models/download-ggml-model.sh ${WHISPER_LIVE_MODEL} \
  && bash ./models/download-ggml-model.sh ${WHISPER_FINAL_MODEL} \
  && cp models/ggml-${WHISPER_LIVE_MODEL}.bin models/ggml-${WHISPER_FINAL_MODEL}.bin /whisper/models/

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

RUN mix assets.setup

COPY priv priv

COPY lib lib

# Compile the release
RUN mix compile

COPY assets assets

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

# ffmpeg is required at runtime, not build time: Agora.Media.build_clip/4
# shells out to it (via System.cmd) to remux recorded HLS segments into
# downloadable clips, ArchiveGathering/ClipBuilder do the same for
# full-Gathering replays, and Agora.Media.Audio.WhisperCli shells out to
# it to convert those replays to WAV before the archival transcription
# pass. whisper-cli/whisper-server themselves are statically linked (see
# the whisper-builder stage above) so nothing further is needed for them.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
     libstdc++6 openssl libncurses6 locales ca-certificates ffmpeg \
  && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/agora ./

# whisper-cli/whisper-server + their ggml model weights — see the
# whisper-builder stage above. config/runtime.exs's WHISPER_*_PATH
# defaults already point here, so no env vars are needed for a stock
# deploy; override them only to swap in different-sized models.
COPY --from=whisper-builder --chown=nobody:root /whisper /app/whisper

# Where live HLS segments and archived recordings land before nginx/CDN
# serves them from disk (see MEDIA_ROOT in config/runtime.exs) — mount a
# host volume here so it survives container restarts and nginx can read it.
RUN mkdir -p /app/media_root && chown nobody /app/media_root
VOLUME ["/app/media_root"]

USER nobody

# Web (Phoenix/HTTP) and RTMP ingest respectively — see section 10 of
# developer.md for the single-box nginx/CDN layout these expect.
EXPOSE 4000 1935

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]
