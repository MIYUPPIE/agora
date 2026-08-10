defmodule Agora.Media.AudioEffectsTest do
  use Agora.DataCase, async: true

  import Agora.AccountsFixtures

  alias Agora.Media.Audio.Params
  alias Agora.Media.AudioEffects

  describe "get_params/1" do
    test "returns defaults when the user has no saved preset" do
      user = user_fixture()
      assert AudioEffects.get_params(user.id) == Params.default()
    end
  end

  describe "update_params/3 when the gathering is not live" do
    test "creates a preset on first update, merging onto defaults" do
      user = user_fixture()
      gathering_id = Ecto.UUID.generate()

      assert {:ok, params} =
               AudioEffects.update_params(gathering_id, user.id, %{input_gain_db: 6.0})

      assert params.input_gain_db == 6.0
      assert params.compressor == Params.default().compressor
      assert AudioEffects.get_params(user.id) == params
    end

    test "a second update merges onto the first, not onto defaults" do
      user = user_fixture()
      gathering_id = Ecto.UUID.generate()

      {:ok, _} = AudioEffects.update_params(gathering_id, user.id, %{input_gain_db: 6.0})

      {:ok, params} =
        AudioEffects.update_params(gathering_id, user.id, %{compressor: %{ratio: 8.0}})

      assert params.input_gain_db == 6.0
      assert params.compressor.ratio == 8.0
    end

    test "out-of-range values are clamped before persisting" do
      user = user_fixture()
      gathering_id = Ecto.UUID.generate()

      {:ok, params} =
        AudioEffects.update_params(gathering_id, user.id, %{limiter: %{ceiling_db: 50.0}})

      assert params.limiter.ceiling_db == 0.0
      assert AudioEffects.get_params(user.id).limiter.ceiling_db == 0.0
    end

    test "two users have completely independent presets" do
      alice = user_fixture()
      bob = user_fixture()
      gathering_id = Ecto.UUID.generate()

      {:ok, _} = AudioEffects.update_params(gathering_id, alice.id, %{input_gain_db: 10.0})

      assert AudioEffects.get_params(bob.id) == Params.default()
      assert AudioEffects.get_params(alice.id).input_gain_db == 10.0
    end
  end

  describe "live?/1" do
    test "false when nothing is registered for the gathering" do
      refute AudioEffects.live?(Ecto.UUID.generate())
    end

    test "true once a process registers itself under GatheringRegistry for that id" do
      gathering_id = Ecto.UUID.generate()
      {:ok, _pid} = Agent.start_link(fn -> :ok end, name: via(gathering_id))

      assert AudioEffects.live?(gathering_id)
    end
  end

  describe "update_params/3 when the gathering is live" do
    test "pushes the change to the registered process via Membrane.Pipeline.call/2 semantics" do
      user = user_fixture()
      gathering_id = Ecto.UUID.generate()
      test_pid = self()

      {:ok, _pid} =
        FakePipeline.start_link(gathering_id: gathering_id, test_pid: test_pid)

      assert {:ok, _params} =
               AudioEffects.update_params(gathering_id, user.id, %{input_gain_db: 3.0})

      assert_receive {:got_call, {:update_effect_params, %{input_gain_db: 3.0}}}
    end

    test "still persists the preset even when the gathering is not live" do
      user = user_fixture()
      gathering_id = Ecto.UUID.generate()

      assert {:ok, params} =
               AudioEffects.update_params(gathering_id, user.id, %{input_gain_db: 9.0})

      assert params.input_gain_db == 9.0
    end
  end

  defp via(gathering_id), do: {:via, Registry, {Agora.Media.GatheringRegistry, gathering_id}}
end
