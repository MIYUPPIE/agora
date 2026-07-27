#!/usr/bin/env bash
# Periodic eval, not a gate test: builds and boots a real MIX_ENV=prod
# release with fake-but-present env vars, the way the Docker image does.
#
# This exists because `mix compile`/`mix test` (both MIX_ENV=dev/test)
# cannot catch prod-release-only failures. The one that prompted this
# script: config/runtime.exs set :media_root at runtime for prod, while
# lib/agora_web/endpoint.ex read that *same* key via Application.compile_env
# to decide whether to mount a dev/test-only Plug.Static. Elixir's release
# boot validates every compile_env-tracked key's runtime value against its
# compile-time value and aborts on mismatch — invisible in dev/test (where
# the key IS set at compile time too), only reproducible by actually
# building and booting a prod release. Confirmed hands-on via `docker run`
# before the fix (split into :media_root + :media_static_root) and after.
#
# Run before shipping any change that touches config/runtime.exs,
# application.ex, or endpoint.ex's compile_env reads.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> mix deps.get + assets.deploy (MIX_ENV=prod)"
MIX_ENV=prod mix deps.get --only prod >/dev/null
MIX_ENV=prod mix assets.deploy >/dev/null

echo "==> Building the release"
MIX_ENV=prod mix release --overwrite --quiet

echo "==> Booting it with the minimum required env vars"
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(mix phx.gen.secret)}"
export DATABASE_URL="${DATABASE_URL:-ecto://user:pass@localhost/db}"
export PHX_HOST="${PHX_HOST:-localhost}"

_build/prod/rel/agora/bin/agora eval '
{:ok, img} = Image.new(4, 4, color: [200, 30, 30])
{:ok, _bin} = Image.write(img, :memory, suffix: ".png")
IO.puts("release boot config OK, libvips OK")
'

echo "==> PASS"
