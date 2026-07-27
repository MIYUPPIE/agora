# Agora — Build Blueprint

**The gathering place.** An audio-first social platform: live streaming
(Gatherings) + a social feed of audio and image posts, built on Phoenix
and LiveView. Listeners can record and download any Gathering live.

This document takes a developer from an empty machine to a deployed MVP.
Work the phases in order — each ends in something you can run and see.

---

## 0. Domain language

Agora has its own vocabulary. Use it everywhere — schema, modules, UI —
so the code reads like the product.

| Agora term    | Means                                             |
|---------------|---------------------------------------------------|
| Gathering     | A live audio stream (Mixlr-style broadcast)       |
| Tiding        | A short text announcement/status post             |
| Post          | A feed item: audio, image set, or tiding          |
| Cling         | To follow someone                                 |
| Clinger       | A follower (someone who clings to you)            |
| Clings        | People you follow (your outgoing clings)          |
| Torch         | A reaction ("pass the flame / signal boost")      |
| Heart         | The like reaction                                 |
| Recording     | A listener-captured clip of a Gathering           |

---

## 1. Architecture at a glance

```
                        ┌──────────────────────────────┐
 Broadcaster (OBS /     │        Phoenix app           │
 mobile encoder)  ──────┼─▶ RTMP ingest (Membrane)     │
                        │      │                        │
                        │      ▼                        │
                        │   Membrane pipeline           │
                        │   (AAC → HLS segments)        │
                        │      │                        │
                        │      ▼                        │
                        │   SegmentStorage ─▶ disk      │
                        │      │        └─▶ Postgres     │
                        │      │        └─▶ PubSub       │
 Listener (browser) ◀───┼── LiveView + hls.js hook      │
                        │      ▲                        │
                        │   Presence (listener count)   │
                        │   PubSub  (feed, reactions)   │
                        │   Oban    (clips, archive)    │
                        └──────────────┬───────────────┘
                                       ▼
                        R2 / S3 + CDN (segments, media,
                                       recordings)
```

**Key principle:** the Phoenix server never streams audio *to* listeners.
It produces HLS segments (static files) that a CDN serves. Server cost
scales with **broadcasters**, not listeners — so thousands can listen on
a small box.

**Stack**

- Phoenix + LiveView (all UI and real-time)
- Membrane Framework (RTMP ingest → HLS)
- PostgreSQL (Ecto)
- Oban (background jobs: clip building, archiving, notifications)
- Cloudflare R2 (or any S3) + CDN
- Tailwind (ships with Phoenix) for the dark/red theme
- hls.js + small LiveView hooks for the audio player and waveform

---

## 2. Prerequisites

```bash
# Elixir/Erlang — use asdf or your OS package
elixir --version          # 1.17+ on OTP 27
mix local.hex --force
mix archive.install hex phx_new

# System deps
sudo apt install -y postgresql ffmpeg build-essential

# ffmpeg is REQUIRED at runtime for clip building.
ffmpeg -version
```

---

## 3. Phase 1 — Project skeleton + accounts

**Goal:** a running app you can log into. Nothing streams yet.

```bash
mix phx.new agora --live
cd agora
# configure DB in config/dev.exs, then:
mix ecto.create
```

Add auth (the generator gives you a full, secure auth system):

```bash
mix phx.gen.auth Accounts User users
mix deps.get
mix ecto.migrate
```

Add remaining deps to `mix.exs`:

```elixir
{:membrane_core, "~> 1.1"},
{:membrane_rtmp_plugin, "~> 0.27"},
{:membrane_http_adaptive_stream_plugin, "~> 0.18"},
{:membrane_aac_plugin, "~> 0.19"},
{:oban, "~> 2.18"},
{:ex_aws, "~> 2.5"},
{:ex_aws_s3, "~> 2.5"},
{:hackney, "~> 1.20"},
{:sweet_xml, "~> 0.7"},
{:image, "~> 0.54"}          # image resizing for posts/avatars
```

```bash
mix deps.get
```

**Done when:** you can sign up, log in, log out, and see the styled login
screen matching your first mockup (dark background, red inputs, Agora
logo).

---

## 4. Phase 2 — Profiles, Clings, and the social graph

**Goal:** the profile hub from mockup 2 — avatar, name, tagline, stats
(Posts / Gatherings / Clingers / Clings), and the ability to cling to
someone.

### Schema

```
profiles
  user_id (FK, unique)   display_name   tagline   avatar_url   bio

clings                              -- the follow graph
  clinger_id (FK users)  -- the follower
  clinged_id (FK users)  -- the followed
  unique index (clinger_id, clinged_id)
  check: clinger_id <> clinged_id   -- can't cling to yourself
```

Counts are two indexed queries, never stored columns (they drift):

```elixir
def clinger_count(user_id),  # people who follow me
  do: Repo.aggregate(from(c in Cling, where: c.clinged_id == ^user_id), :count)

def cling_count(user_id),    # people I follow
  do: Repo.aggregate(from(c in Cling, where: c.clinger_id == ^user_id), :count)
```

### The profile hub LiveView

Build `AgoraWeb.ProfileLive` matching mockup 2:

- Red header band: avatar, display name, tagline, settings gear, menu.
- Action row: **Start Gathering · Upload Image · Tidings · Join Gathering**.
- Stats row: Posts · Gatherings · Clingers · Clings.
- Feed of the user's posts below (Phase 3).

Use function components for reuse:

```elixir
# lib/agora_web/components/agora_components.ex
attr :count, :integer, required: true
attr :label, :string, required: true
def stat(assigns) do
  ~H"""
  <div class="text-center">
    <div class="text-3xl font-bold text-white">{@count}</div>
    <div class="text-sm text-neutral-400">{@label}</div>
  </div>
  """
end
```

**Done when:** you can view anyone's profile, see live-correct stats, and
tap a Cling/Uncling button that updates the Clinger count in real time
(broadcast the change over PubSub topic `user:<id>:stats`).

---

## 5. Phase 3 — Posts and the feed

**Goal:** the scrolling feed of audio posts, image posts, and tidings
(mockups 2 and 3), with Heart and Torch reactions.

### Schema

```
posts
  user_id (FK)   kind (enum: :audio, :image_set, :tiding)
  title          body (text, for tidings)   duration_ms (audio)
  waveform (jsonb, peak array for audio)     inserted_at

post_media                       -- images and audio files
  post_id (FK)   kind (:image, :audio)   url   position   byte_size

reactions
  user_id (FK)   post_id (FK)   kind (enum: :heart, :torch)
  unique index (user_id, post_id, kind)

comments
  user_id (FK)   post_id (FK)   body   inserted_at
```

### Upload flow

Use LiveView's built-in uploads (`allow_upload`) for **Upload Image** and
audio posts. Consume to a temp file, resize/normalize, push to R2, store
the URL:

```elixir
socket = allow_upload(socket, :media,
  accept: ~w(.jpg .jpeg .png .m4a .mp3),
  max_entries: 5,
  max_file_size: 25_000_000)
```

On consume: images → resize to a few widths with the `image` lib;
audio → run `ffprobe` for duration and generate a waveform peak array
(store as jsonb) in an Oban job so the upload feels instant.

### The feed LiveView

- Subscribe to `feed:<user_id>` (posts from people you cling to).
- New post from someone you cling to → PubSub → prepend to the stream.
- Reactions update counters live (`handle_info`).
- Render audio posts with the waveform (a hook draws the peak array to a
  canvas) + a play button; image posts as a gallery; tidings as text.

Use **LiveView streams** for the feed so long lists don't bloat memory:

```elixir
socket = stream(socket, :posts, load_feed(user))
# on new post:
{:noreply, stream_insert(socket, :posts, new_post, at: 0)}
```

**Done when:** the feed renders all three post types, reactions tick up
live across browsers, and a new post appears in a Clinger's feed without
refresh.

---

## 6. Phase 4 — Live Gatherings (the media core)

**Goal:** Start a Gathering, broadcast audio, listeners hear it live with
a listener count. This is the riskiest phase — prototype it in isolation
first.

### Schema

```
gatherings
  user_id (FK)   title   status (enum: :scheduled, :live, :ended)
  stream_key (unique, secret)   started_at   ended_at
  segment_count

gathering_segments
  gathering_id (FK)   sequence (int)   filename
  byte_size   duration_ms
  unique index (gathering_id, sequence)
```

### The pieces (full code in the media-core files already delivered)

1. **`Agora.Media.GatheringPipeline`** — one Membrane pipeline per live
   Gathering: RTMP in → AAC → HLS segments (`persist?: true` so every
   segment survives the whole stream, enabling replay + record).

2. **`Agora.Media.SegmentStorage`** — custom HLS storage: writes each
   segment to disk, inserts a `gathering_segments` row with a sequence
   number, broadcasts the new head sequence on
   `gathering:<id>:segments`.

3. **`Agora.Media.RTMPEndpoint`** — validates the stream key on connect
   and starts a pipeline only for valid keys.

4. **`Agora.Media.GatheringSupervisor` + `GatheringRegistry`** — a
   DynamicSupervisor owning one pipeline per Gathering, addressable by id.

### Start / Join flow

- **Start Gathering** → create a `gatherings` row (status `:scheduled`),
  generate a `stream_key`, show the broadcaster the ingest URL
  (`rtmp://ingest.agora.example/live/<stream_key>`) and a "you're live"
  panel. When the encoder connects, the pipeline flips status to `:live`
  and broadcasts `{:gathering_live, id}` to every Clinger.
- **Join Gathering** → `AgoraWeb.GatheringLive` (delivered): hls.js hook
  plays the manifest, Presence tracks the listener, count updates live.

### Browser broadcasting (optional, phase 4b)

RTMP covers OBS/mixer users (preachers with setups). For "tap to go live
from the phone browser," add `membrane_webrtc_plugin` ingest into the
same pipeline. Ship RTMP first — it's simpler and covers your power users.

**Done when:** `ffmpeg -re -i test.mp3 -c:a aac -b:a 64k -f flv
rtmp://localhost:1935/live/<key>` makes audio play in a browser
GatheringLive page with a correct listener count.

---

## 7. Phase 5 — Record & download (the differentiator)

**Goal:** a listener taps Record during a live Gathering and downloads
the captured audio. Mixlr can't do this — make it native and free.

### How it works (full code in `Agora.Recordings` + `ClipBuilder`)

Recording stores **no audio** — just two integers:

```
Record pressed → start_seq = current head segment
Stop pressed   → end_seq   = current head segment, enqueue ClipBuilder
```

Because segments already exist on disk (Phase 4), the `ClipBuilder` Oban
job just concatenates the range with FFmpeg `-c copy` (remux, no
re-encode → sub-second even for an hour), uploads the `.m4a` to R2, and
pushes the download link to the listener's LiveView over
`user:<id>:recordings`.

Free wins you get from this design:

- **Record from the beginning** (`start_seq = 0`) even if they joined late.
- **Full replay** of every ended Gathering (segments persist).
- **Clip sharing** — "torch this moment" becomes a shareable clip.

**Done when:** during a live stream, Record → wait → Stop yields a working
download link, and a thousand simultaneous recorders cost the server
nothing until they each stop.

### schema

```
recordings
  user_id (FK)   gathering_id (FK)
  start_seq   end_seq   status (:recording|:processing|:ready|:failed)
  download_url   byte_size
```

---

## 8. Phase 6 — Real-time glue (Presence, PubSub, notifications)

These thread through every phase; this phase makes them deliberate.

- **Presence** on `gathering:<id>` → live listener counts and "who's
  here." Already wired in GatheringLive.
- **PubSub topics** (standardize these):
  - `gathering:<id>` — live/ended lifecycle, chat
  - `gathering:<id>:segments` — new segment head (for recording)
  - `feed:<user_id>` — new posts from clings
  - `user:<id>:stats` — clinger/cling count changes
  - `user:<id>:recordings` — recording ready/failed
- **Go-live notification** (the growth loop): when a Gathering flips
  `:live`, an Oban job fans out "X started a Gathering" to every Clinger
  (in-app via PubSub now; web push / FCM later). **Build this early —
  it's what fills Gatherings.**
- **In-Gathering chat** — a LiveView form + PubSub on `gathering:<id>`;
  no persistence needed for MVP.

---

## 9. Phase 7 — Theme & polish

Match the mockups with Tailwind:

- Background `#1a1a1a` / near-black; accent red `#8b0000`–`#a00`.
- Logo mark (the red triangular "A") as an SVG component.
- Rounded action pills, circular avatar, red circular icon buttons for
  the post-type row.
- Mobile-first layout — your mockups are phones. Design at ~380px width
  first, expand up.

Ship a **PWA manifest** so it installs on phones (icons, standalone
display, theme color). This gets you a mobile app feel without a separate
build. If you later need reliable background audio + native push, add a
Flutter client talking to Phoenix channels — reuse the same backend.

---

## 10. Deployment

**Single box to start** (Hetzner / Fly.io):

- Phoenix + Membrane + Postgres on one node.
- R2 bucket for segments, media, recordings; CDN in front.
- Open port 1935 (RTMP ingest) and 443 (web).

**application.ex children (order matters):**

```elixir
children = [
  Agora.Repo,
  {Phoenix.PubSub, name: Agora.PubSub},
  AgoraWeb.Presence,
  {Oban, Application.fetch_env!(:agora, Oban)},
  Agora.Media.GatheringRegistry,
  Agora.Media.GatheringSupervisor,
  {Membrane.RTMPServer,
   port: 1935,
   handle_new_client: &Agora.Media.RTMPEndpoint.handle_new_client/3},
  AgoraWeb.Endpoint
]
```

**Serving segments:** CDN points at `/media/gatherings/:id/index.m3u8`.
Cache `.m4s` segments hard (`max-age=31536000`), `.m3u8` as `no-cache`.

**Bitrate for your audience:** default **48–64 kbps AAC-HE** for voice
(cheap on Nigerian mobile data), with an optional 128 kbps "music"
quality per Gathering. This one setting affects retention more than any
feature.

**Scaling later:** `libcluster` + route each Gathering pipeline to a node
(Horde/`:global`); Postgres stays central. You will not need Kubernetes.

---

## 11. Build order summary (ship-first path)

1. **Skeleton + auth** — log in, see the themed shell.
2. **Profiles + Clings** — the hub, the social graph, live stats.
3. **Posts + feed** — audio/image/tiding posts, hearts & torches.
4. **Gatherings** — RTMP → HLS → listen live with a count. *(hardest —
   prototype alone first)*
5. **Record & download** — the differentiator.
6. **Real-time glue** — go-live notifications = your growth loop.
7. **Theme + PWA** — match mockups, installable on phones.
8. **Deploy** — one box, R2 + CDN, low default bitrate.

Get Phase 4's test flow (`ffmpeg → RTMP → browser`) working on localhost
before anything else fancy — it de-risks the whole project. Everything
else is standard Phoenix you can move through fast.

---

## 12. Watch-outs (learned the hard way)

- **Membrane plugin options drift between minor versions.** Pin versions;
  when a child spec fails, check the plugin's HexDocs for renamed options.
  The pipeline *shape* stays stable.
- **fMP4 init header name** — `ClipBuilder` finds it by convention;
  verify the exact filename your `SinkBin` version emits.
- **LiveView latency on mobile** — a `phx-click` is a round trip
  (~150–300ms on Nigerian mobile). Use `phx-disable-with` for instant
  button feedback and `Phoenix.LiveView.JS` for local UI (menus, toggles)
  that shouldn't hit the server.
- **Rights on downloads** — record-and-download makes you a distribution
  layer if broadcasters play copyrighted music. Decide your stance early
  (feature you market vs. liability you manage).
- **Cold start is the real risk, not the tech.** Line up your first ~20
  broadcasters (each with an audience) before over-investing in features.
  A narrow first community beats a horizontal platform.
```


logo is ./agora.png