# Agora media core — wiring it together

## mix.exs deps

```elixir
{:membrane_core, "~> 1.1"},
{:membrane_rtmp_plugin, "~> 0.27"},
{:membrane_http_adaptive_stream_plugin, "~> 0.18"},
{:membrane_aac_plugin, "~> 0.19"},
{:oban, "~> 2.18"},
{:ex_aws, "~> 2.5"},
{:ex_aws_s3, "~> 2.5"},
{:hackney, "~> 1.20"},
{:sweet_xml, "~> 0.7"}
```

FFmpeg must be on the host: `apt install ffmpeg`.

> Membrane plugin options occasionally rename between minor versions.
> If a child spec fails to build, check the plugin's HexDocs for your
> pinned version — the pipeline shape stays the same.

## application.ex children (order matters)

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

## config

```elixir
config :agora,
  media_root: "/var/agora/media",          # local disk for live segments
  recordings_bucket: "agora-recordings",   # R2 bucket
  cdn_base_url: "https://cdn.agora.example"

config :agora, Oban,
  repo: Agora.Repo,
  queues: [media: 5, default: 10]

config :ex_aws,
  access_key_id: {:system, "R2_ACCESS_KEY_ID"},
  secret_access_key: {:system, "R2_SECRET_ACCESS_KEY"},
  s3: [
    scheme: "https://",
    host: "<account_id>.r2.cloudflarestorage.com",
    region: "auto"
  ]
```

## migrations

```elixir
create table(:gathering_segments) do
  add :gathering_id, references(:gatherings, on_delete: :delete_all), null: false
  add :sequence, :integer, null: false
  add :filename, :string, null: false
  add :byte_size, :integer
  add :duration_ms, :integer
  timestamps(updated_at: false)
end

create unique_index(:gathering_segments, [:gathering_id, :sequence])

create table(:recordings) do
  add :user_id, references(:users, on_delete: :delete_all), null: false
  add :gathering_id, references(:gatherings, on_delete: :delete_all), null: false
  add :start_seq, :integer, null: false
  add :end_seq, :integer
  add :status, :string, null: false, default: "recording"
  add :download_url, :string
  add :byte_size, :bigint
  timestamps()
end

create index(:recordings, [:user_id, :gathering_id])
```

## Serving live segments

Point the CDN at `/media/gatherings/:id/index.m3u8`. In dev, a plain
`Plug.Static` on `media_root` works:

```elixir
plug Plug.Static, at: "/media", from: {:agora, :media_root_runtime}
```

In prod put nginx or the CDN directly on the directory — segments are
immutable files, cache them hard (`Cache-Control: max-age=31536000` for
`.m4s`, `no-cache` for `.m3u8`).

## Test flow

1. Create a Gathering in IEx → note its stream_key
2. `ffmpeg -re -i test.mp3 -c:a aac -b:a 64k -f flv rtmp://localhost:1935/live/<stream_key>`
3. Open the GatheringLive page → audio plays, listener count = 1
4. Tap Record, wait 20s, tap Stop → download link arrives via PubSub
