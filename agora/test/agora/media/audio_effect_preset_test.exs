defmodule Agora.Media.AudioEffectPresetTest do
  use Agora.DataCase, async: true

  import Agora.AccountsFixtures

  alias Agora.Media.AudioEffectPreset
  alias Agora.Repo

  describe "changeset/2" do
    test "requires user_id and params" do
      changeset = AudioEffectPreset.changeset(%AudioEffectPreset{}, %{})
      refute changeset.valid?
      assert %{user_id: ["can't be blank"], params: ["can't be blank"]} = errors_on(changeset)
    end

    test "valid with a user_id and a params map" do
      user = user_fixture()

      changeset =
        AudioEffectPreset.changeset(%AudioEffectPreset{}, %{
          user_id: user.id,
          params: %{"gain" => 1}
        })

      assert changeset.valid?
    end
  end

  describe "unique_constraint on user_id" do
    test "a second preset for the same user fails to insert" do
      user = user_fixture()

      assert {:ok, _} =
               %AudioEffectPreset{}
               |> AudioEffectPreset.changeset(%{user_id: user.id, params: %{}})
               |> Repo.insert()

      assert {:error, changeset} =
               %AudioEffectPreset{}
               |> AudioEffectPreset.changeset(%{user_id: user.id, params: %{}})
               |> Repo.insert()

      assert %{user_id: ["has already been taken"]} = errors_on(changeset)
    end
  end
end
