#!/usr/bin/env bash
#
# Builds whisper.cpp from source (statically linked, no runtime .so deps
# beyond what's already on any Debian/Ubuntu box running this app — same
# deal as ffmpeg) and downloads the ggml models Agora's live-transcription
# feature needs, into priv/whisper/{bin,models}/ (gitignored — see
# Agora.Media.Audio.Transcription's moduledoc for why these binaries and
# model weights aren't committed to the repo).
#
# Usage: scripts/setup_whisper.sh [live_model] [final_model]
#   live_model  — fast model for real-time captions during a broadcast.
#                 Default: base.en (147MB, good latency/accuracy balance
#                 on CPU). Use tiny.en for lower latency on weak hardware.
#   final_model — accurate model for the one-shot post-broadcast full
#                 transcript. Default: small.en (466MB). Use medium.en or
#                 large-v3-turbo for higher accuracy if you have the disk
#                 space and CPU/GPU budget — that tradeoff is deliberately
#                 not made for you, same call as libfdk-aac in
#                 Agora.Media.Audio.FFmpegPort.
#
# Safe to re-run — skips the clone/build if the binaries already exist,
# and each model download is independently skipped if already present.
set -euo pipefail

LIVE_MODEL="${1:-base.en}"
FINAL_MODEL="${2:-small.en}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WHISPER_DIR="$ROOT_DIR/priv/whisper"
BUILD_DIR="$ROOT_DIR/.whisper_cpp_src"
PINNED_TAG="v1.7.6"

mkdir -p "$WHISPER_DIR/bin" "$WHISPER_DIR/models"

if [ ! -x "$WHISPER_DIR/bin/whisper-cli" ] || [ ! -x "$WHISPER_DIR/bin/whisper-server" ]; then
  echo "==> Cloning whisper.cpp ($PINNED_TAG)..."
  rm -rf "$BUILD_DIR"
  git clone --depth 1 --branch "$PINNED_TAG" https://github.com/ggml-org/whisper.cpp.git "$BUILD_DIR"

  echo "==> Configuring (static build — no runtime .so dependencies)..."
  cmake -B "$BUILD_DIR/build" -S "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_BUILD_EXAMPLES=ON \
    -DWHISPER_BUILD_SERVER=ON \
    -DBUILD_SHARED_LIBS=OFF

  echo "==> Building whisper-cli and whisper-server..."
  cmake --build "$BUILD_DIR/build" --config Release -j"$(nproc)" --target whisper-cli whisper-server

  cp "$BUILD_DIR/build/bin/whisper-cli" "$BUILD_DIR/build/bin/whisper-server" "$WHISPER_DIR/bin/"
  strip "$WHISPER_DIR/bin/whisper-cli" "$WHISPER_DIR/bin/whisper-server"
  rm -rf "$BUILD_DIR"
  echo "==> Built $WHISPER_DIR/bin/whisper-cli and whisper-server"
else
  echo "==> whisper-cli/whisper-server already built, skipping compile"
fi

download_model() {
  local model="$1"
  local dest="$WHISPER_DIR/models/ggml-${model}.bin"
  if [ -f "$dest" ]; then
    echo "==> Model $model already downloaded"
    return
  fi
  echo "==> Downloading ggml model: $model"
  curl -L --fail -o "$dest.tmp" \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${model}.bin"
  mv "$dest.tmp" "$dest"
}

download_model "$LIVE_MODEL"
download_model "$FINAL_MODEL"

cat <<EOF

Done. Add to your .env (see .env.example) or shell profile:

  WHISPER_CLI_PATH=$WHISPER_DIR/bin/whisper-cli
  WHISPER_SERVER_PATH=$WHISPER_DIR/bin/whisper-server
  WHISPER_LIVE_MODEL_PATH=$WHISPER_DIR/models/ggml-${LIVE_MODEL}.bin
  WHISPER_FINAL_MODEL_PATH=$WHISPER_DIR/models/ggml-${FINAL_MODEL}.bin

dev/test already default to these exact paths, so local development needs
no env vars at all — just run this script once.
EOF
