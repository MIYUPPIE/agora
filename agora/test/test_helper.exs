ExUnit.start(exclude: [:whisper])
Ecto.Adapters.SQL.Sandbox.mode(Agora.Repo, :manual)

# :whisper-tagged tests (test/agora/media/audio/{whisper_cli,whisper_client}_test.exs)
# round-trip through a real whisper.cpp model — several real seconds each,
# and only meaningful once scripts/setup_whisper.sh has been run, so they're
# excluded from the default fast/gate suite every commit pays for. Run them
# explicitly, as a periodic eval:
#
#   mix test --include whisper
