defmodule AgoraWeb.AgoraComponentsTest do
  use ExUnit.Case, async: true

  alias AgoraWeb.AgoraComponents

  describe "format_duration/1" do
    test "formats whole minutes" do
      assert AgoraComponents.format_duration(60_000) == "1:00"
    end

    test "pads seconds under 10" do
      assert AgoraComponents.format_duration(65_000) == "1:05"
    end

    test "handles durations under a minute" do
      assert AgoraComponents.format_duration(3_000) == "0:03"
    end

    test "handles multi-digit minutes" do
      assert AgoraComponents.format_duration(754_000) == "12:34"
    end
  end
end
