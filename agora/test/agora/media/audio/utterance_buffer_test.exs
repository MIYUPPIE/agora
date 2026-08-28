defmodule Agora.Media.Audio.UtteranceBufferTest do
  use ExUnit.Case, async: true

  alias Agora.Media.Audio.UtteranceBuffer

  @sample_rate 48_000

  defp silence_ms(ms), do: <<0::size(trunc(ms / 1000 * @sample_rate) * 2 * 16)>>

  defp tone_ms(ms, amplitude \\ 0.3, freq \\ 440.0) do
    n = trunc(ms / 1000 * @sample_rate)

    for i <- 0..(n - 1), into: <<>> do
      sample = amplitude * :math.sin(2 * :math.pi() * freq * i / @sample_rate)
      int16 = trunc(sample * 32_767)
      <<int16::signed-little-16, int16::signed-little-16>>
    end
  end

  describe "push/2 — silence handling" do
    test "leading silence before any speech is dropped entirely, buffer stays empty" do
      buffer = UtteranceBuffer.new(@sample_rate)
      {buffer, flush} = UtteranceBuffer.push(buffer, silence_ms(2000))

      assert flush == nil
      assert buffer.audio == <<>>
      assert buffer.total_ms == 0
    end

    test "an empty chunk is a no-op" do
      buffer = UtteranceBuffer.new(@sample_rate)
      assert {^buffer, nil} = UtteranceBuffer.push(buffer, <<>>)
    end
  end

  describe "push/2 — normal utterance flush on trailing silence" do
    test "flushes once speech is followed by enough trailing silence" do
      buffer = UtteranceBuffer.new(@sample_rate, silence_hangover_ms: 500, min_utterance_ms: 300)

      {buffer, nil} = UtteranceBuffer.push(buffer, tone_ms(800))
      assert buffer.has_speech?

      {buffer, flush} = UtteranceBuffer.push(buffer, silence_ms(500))

      assert %{audio: audio, duration_ms: duration_ms} = flush
      assert byte_size(audio) == byte_size(tone_ms(800)) + byte_size(silence_ms(500))
      assert_in_delta duration_ms, 1300, 1.0

      # state resets after flush
      assert buffer.audio == <<>>
      assert buffer.total_ms == 0
      assert buffer.has_speech? == false
    end

    test "a brief mid-utterance pause shorter than the hangover does not flush" do
      buffer = UtteranceBuffer.new(@sample_rate, silence_hangover_ms: 500, min_utterance_ms: 300)

      {buffer, nil} = UtteranceBuffer.push(buffer, tone_ms(400))
      {buffer, nil} = UtteranceBuffer.push(buffer, silence_ms(200))
      {buffer, nil} = UtteranceBuffer.push(buffer, tone_ms(400))

      assert buffer.audio != <<>>
      assert buffer.silence_run_ms == 0
    end

    test "silence_run_ms resets to zero as soon as speech resumes" do
      buffer = UtteranceBuffer.new(@sample_rate, silence_hangover_ms: 1000, min_utterance_ms: 100)

      {buffer, nil} = UtteranceBuffer.push(buffer, tone_ms(200))
      {buffer, nil} = UtteranceBuffer.push(buffer, silence_ms(400))
      assert_in_delta buffer.silence_run_ms, 400, 1.0

      {buffer, nil} = UtteranceBuffer.push(buffer, tone_ms(100))
      assert buffer.silence_run_ms == 0
    end
  end

  describe "push/2 — too-short blips are discarded, not flushed" do
    test "a short blip followed by hangover-length silence resets without emitting a flush" do
      buffer = UtteranceBuffer.new(@sample_rate, silence_hangover_ms: 300, min_utterance_ms: 1000)

      {buffer, nil} = UtteranceBuffer.push(buffer, tone_ms(100))
      {buffer, flush} = UtteranceBuffer.push(buffer, silence_ms(300))

      assert flush == nil
      assert buffer.audio == <<>>
      assert buffer.has_speech? == false
    end
  end

  describe "push/2 — max_utterance_ms safety cap" do
    test "flushes once total buffered duration hits the cap, even with no silence at all" do
      buffer =
        UtteranceBuffer.new(@sample_rate,
          max_utterance_ms: 1000,
          silence_hangover_ms: 100_000,
          min_utterance_ms: 100_000
        )

      {buffer, nil} = UtteranceBuffer.push(buffer, tone_ms(600))
      {buffer, flush} = UtteranceBuffer.push(buffer, tone_ms(500))

      assert %{duration_ms: duration_ms} = flush
      assert duration_ms >= 1000
      assert buffer.audio == <<>>
    end
  end

  describe "push/2 — continuous streaming across many small chunks" do
    test "accumulates correctly across many small pushes the way real Membrane buffers would arrive" do
      buffer = UtteranceBuffer.new(@sample_rate, silence_hangover_ms: 500, min_utterance_ms: 200)

      # 20ms chunks are a realistic Membrane buffer size.
      chunks = for _ <- 1..40, do: tone_ms(20)

      {buffer, flushes} =
        Enum.reduce(chunks, {buffer, []}, fn chunk, {buf, acc} ->
          case UtteranceBuffer.push(buf, chunk) do
            {buf, nil} -> {buf, acc}
            {buf, flush} -> {buf, [flush | acc]}
          end
        end)

      assert flushes == []
      assert_in_delta buffer.total_ms, 800, 1.0

      {_buffer, flush} = UtteranceBuffer.push(buffer, silence_ms(500))
      assert %{duration_ms: duration_ms} = flush
      assert_in_delta duration_ms, 1300, 1.0
    end
  end
end
