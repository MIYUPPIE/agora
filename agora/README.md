# Agora

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Live transcription

Every Gathering gets live captions while it's broadcasting, and an
accurate final transcript (downloadable as `.srt`) once it ends — see
`Agora.Media.Audio.WhisperServer`'s moduledoc for the full architecture.
Self-hosted [whisper.cpp](https://github.com/ggml-org/whisper.cpp), not
a hosted API: no external service, no per-minute cost, works offline,
and every broadcaster's connection method (browser mic, OBS/RTMP) gets
captioned the same way since it taps the audio already flowing through
`Agora.Media.GatheringPipeline`, not the browser mic feed directly.

Local dev setup (one-time):

```
scripts/setup_whisper.sh
```

Builds `whisper-cli`/`whisper-server` and downloads the default models
into `priv/whisper/` (gitignored — compiled binaries and model weights,
not source). `config/dev.exs`/`config/test.exs` already point at that
exact location, so no environment variables are needed afterward.
Skipping this step doesn't break anything else — transcription just
stays off (see `Agora.Media.Audio.WhisperServer`'s "self-disabling"
behavior).

The tests that round-trip through a real model (`mix test.whisper`) are
excluded from the default `mix test`/`mix precommit` run — several real
seconds each, and only meaningful once the setup script above has run —
same "periodic eval, not a commit gate" treatment as any other
LLM-quality-dependent test suite.

## Deployment

Single box to start (Hetzner / Fly.io / any VPS with Docker): Phoenix +
Membrane (RTMP ingest -> HLS) + Postgres on one node, nginx in front for
TLS and static media serving, R2 (or any S3-compatible bucket) + a CDN
once you outgrow local disk.

```
cp .env.example .env               # fill in SECRET_KEY_BASE, PHX_HOST, etc.
docker compose build
docker compose up -d db
docker compose run --rm app /app/bin/migrate
docker compose up -d
```

- **`Dockerfile`** — multi-stage release build (generated via
  `mix phx.gen.release --docker`, then customized: `ffmpeg` is installed
  in the runtime stage since `Agora.Media.build_clip/4` shells out to it
  for every recording/replay download; a separate `whisper-builder` stage
  compiles whisper.cpp and downloads its models for live transcription
  (see above); ports `4000` (web) and `1935` (RTMP ingest) are exposed;
  `/app/media_root` is declared as a volume).
- **`docker-compose.yml`** — the three services above, wired together;
  see the file for the exact command sequence.
- **`deploy/nginx.conf.example`** — reverse-proxies everything to Phoenix
  (with the `Upgrade`/`Connection` headers LiveView's websocket needs),
  *except* `/media/`, which it serves directly off the same disk path
  the app writes to (`MEDIA_ROOT`) — that's the point of the shared
  volume: hot listener traffic for live segments and recordings never
  touches the BEAM or Postgres. `.m3u8` playlists are rewritten
  constantly (`no-cache`); `.m4s`/`.mp4`/`.m4a` segments are immutable
  once written (`max-age=31536000`). RTMP (1935) is raw TCP, not HTTP —
  it isn't proxied here; the app container's `1935` port is published
  straight to the host/firewall instead.
- **`.env.example`** — every environment variable the release reads at
  runtime, with what each one is for. Notable ones beyond the standard
  Phoenix set (`SECRET_KEY_BASE`, `DATABASE_URL`, `PHX_HOST`):
  - `MEDIA_ROOT` — disk path for live HLS segments and (R2-less)
    recordings; defaults to `/app/media_root`, matching the Docker
    volume. Must match nginx's `alias` in `nginx.conf.example`.
  - `RTMP_PORT` — defaults to `1935`.
  - `R2_UPLOADS_BUCKET` / `R2_RECORDINGS_BUCKET` / `R2_ACCESS_KEY_ID` /
    `R2_SECRET_ACCESS_KEY` / `R2_ACCOUNT_ID` / `CDN_BASE_URL` — leave
    unset to keep everything on local disk (fine for one box without a
    CDN yet); set them to move post-media uploads and recordings/replays
    to R2 behind a CDN. `R2_RECORDINGS_BUCKET` falls back to
    `R2_UPLOADS_BUCKET` if you only configure one bucket.
  - `WHISPER_CLI_PATH` / `WHISPER_SERVER_PATH` / `WHISPER_LIVE_MODEL_PATH`
    / `WHISPER_FINAL_MODEL_PATH` / `WHISPER_SERVER_PORT` /
    `TRANSCRIPTION_ENABLED` — the Docker image already bundles
    whisper.cpp + default models at the paths these default to (see
    "Live transcription" above and the `whisper-builder` Dockerfile
    stage), so none of these need setting for a stock deploy. Override
    the `_MODEL_PATH` ones to swap in a bigger/smaller model; set
    `TRANSCRIPTION_ENABLED=false` to turn the whole feature off.

**Bitrate.** Default guidance surfaced right on the "Start Gathering"
screen: 48–64 kbps AAC-HE for voice (this is what the broadcaster's own
encoder is configured to, not something Agora transcodes — the pipeline
is a pure RTMP->HLS remux, no re-encode). This one setting affects
listener data cost and retention more than any feature.

**Scaling later.** `libcluster` + routing each Gathering's pipeline to a
node via Horde/`:global`; Postgres stays central. You will not need
Kubernetes for this.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
