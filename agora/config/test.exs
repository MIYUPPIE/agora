import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :agora, Agora.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "agora_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :agora, AgoraWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "5EJt1wd1qr+lnvBDYKsplopNATnaLtiIBw2BlVRsQiA1FiiCfnX/DRlKx6Q2PKfb",
  server: false

# In test we don't send emails
config :agora, Agora.Mailer, adapter: Swoosh.Adapters.Test

# Post-media uploads write here instead of priv/static/uploads, so test
# runs don't leave real files in the dev static tree.
config :agora, :uploads_local_dir, Path.expand("../tmp/test_uploads", __DIR__)

# Same idea for live-Gathering segments/recordings.
config :agora, :media_root, Path.expand("../tmp/test_media_root", __DIR__)

# Separate compile-time key for the endpoint's /media static mount — see
# the comment on this key in config/dev.exs and in endpoint.ex for why it
# isn't just :media_root.
config :agora, :media_static_root, Path.expand("../tmp/test_media_root", __DIR__)

# Agora.Media.BrowserBroadcastBridge's subprocess: the fast test suite
# doesn't need a real transcode (that's covered by hands-on verification
# against the real dev server instead), just a process that reads stdin
# until closed without needing ffmpeg's actual CLI flags.
config :agora, :browser_broadcast_ffmpeg, "cat"
config :agora, :browser_broadcast_ffmpeg_args, fn _rtmp_url -> [] end

# No real TCP listener on :1935 in tests, and jobs run only when a test
# explicitly asks Oban to (via Oban.Testing), never on a background timer.
config :agora, :start_rtmp_server, false
config :agora, Oban, testing: :manual

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
