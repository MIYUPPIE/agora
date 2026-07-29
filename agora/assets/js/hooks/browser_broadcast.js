import { Socket } from "phoenix"
import {
  COMPRESSOR_SETTINGS,
  GATE_DEFAULTS,
  HIGH_PASS_FREQUENCY_HZ,
  HIGH_PASS_Q,
  MAKEUP_GAIN,
} from "../audio/voice_processing.mjs"

// Requested on top of whatever the device/OS already does. echoCancellation
// and autoGainControl matter mainly on laptops without a headset;
// noiseSuppression is the browser's own ML noise suppressor and does most
// of the "denoise" work before the signal ever reaches our Web Audio graph.
const AUDIO_CONSTRAINTS = {
  echoCancellation: true,
  noiseSuppression: true,
  autoGainControl: true,
  channelCount: 1,
  sampleRate: { ideal: 48000 },
}

const NOISE_GATE_WORKLET_URL = "/assets/js/audio/noise_gate_processor.js"

// Lets a broadcaster go live straight from this device's mic — no OBS,
// no external encoder. Captures audio with MediaRecorder and streams
// ~1s webm/opus chunks over a Phoenix Channel to
// Agora.Media.BrowserBroadcastBridge, which bridges them into the same
// RTMP ingest OBS would otherwise use (see that module's moduledoc).
//
// Before it ever hits MediaRecorder, the raw mic stream is run through a
// Web Audio processing chain (see setupAudioPipeline): a high-pass filter
// for rumble/handling noise, the browser's own noise suppression (via
// AUDIO_CONSTRAINTS), a custom noise-gate AudioWorklet that pulls down
// residual hiss/keyboard/fan noise between words, and a compressor +
// makeup gain so loudness stays consistent for listeners. Any stage that
// isn't supported is skipped rather than blocking the broadcast — a raw,
// unprocessed mic feed is always better than no broadcast at all.
export const BrowserBroadcast = {
  mounted() {
    this.gatheringId = this.el.dataset.gatheringId
    this.token = this.el.dataset.token

    this.idleEl = this.el.querySelector('[data-role="idle"]')
    this.liveEl = this.el.querySelector('[data-role="live"]')
    this.unsupportedEl = this.el.querySelector('[data-role="unsupported"]')
    this.errorEl = this.el.querySelector('[data-role="error"]')
    this.startBtn = this.el.querySelector('[data-action="start"]')
    this.stopBtn = this.el.querySelector('[data-action="stop"]')

    this.mimeType = ["audio/webm;codecs=opus", "audio/webm", "audio/ogg;codecs=opus"].find(
      (type) => window.MediaRecorder && MediaRecorder.isTypeSupported(type)
    )

    if (!this.mimeType || !navigator.mediaDevices?.getUserMedia) {
      this.unsupportedEl.classList.remove("hidden")
      this.startBtn.disabled = true
    }

    this.startBtn.addEventListener("click", () => this.start())
    this.stopBtn.addEventListener("click", () => this.stop())
  },

  destroyed() {
    this.teardown()
  },

  async start() {
    this.clearError()

    try {
      this.rawStream = await navigator.mediaDevices.getUserMedia({ audio: AUDIO_CONSTRAINTS })
    } catch (_err) {
      this.showError("Microphone permission is required to broadcast from this device.")
      return
    }

    try {
      this.stream = await this.setupAudioPipeline(this.rawStream)
    } catch (err) {
      console.warn(
        "BrowserBroadcast: voice processing setup failed, broadcasting the raw mic input instead.",
        err
      )
      this.stream = this.rawStream
    }

    this.socket = new Socket("/socket", { params: { token: this.token } })
    this.socket.connect()

    this.channel = this.socket.channel(`broadcast:${this.gatheringId}`, {})
    this.channel.on("broadcast_error", () => {
      this.showError("The broadcast connection dropped. Tap Go Live to try again.")
      this.teardown()
    })

    this.channel
      .join()
      .receive("ok", () => this.goLive())
      .receive("error", () => {
        this.showError("Couldn't start the broadcast. Try again in a moment.")
        this.teardown()
      })
  },

  goLive() {
    this.recorder = new MediaRecorder(this.stream, {
      mimeType: this.mimeType,
      audioBitsPerSecond: 64_000,
    })

    this.recorder.ondataavailable = (event) => {
      if (event.data.size > 0 && this.channel) {
        event.data.arrayBuffer().then((buf) => this.channel.push("chunk", buf))
      }
    }

    // 1s timeslices: small enough that "Stop" feels immediate, large
    // enough to keep the per-chunk overhead (each chunk is its own
    // WebSocket binary frame) sensible at voice bitrates.
    this.recorder.start(1000)

    this.idleEl.classList.add("hidden")
    this.liveEl.classList.remove("hidden")
  },

  stop() {
    this.teardown()
  },

  // Builds: MediaStreamSource -> highpass -> [noise gate worklet] ->
  // compressor -> makeup gain -> MediaStreamDestination. Returns the
  // destination's stream, which is what MediaRecorder actually records.
  // The AudioContext, and every node in the chain, live only in here and
  // in `this.audioContext`/`this.stream` — teardown() closes the context
  // to free them, and separately stops `this.rawStream`'s tracks, since
  // stopping the *destination* stream's tracks does not stop the
  // underlying mic (it would otherwise stay open with the browser's
  // mic-in-use indicator lit).
  async setupAudioPipeline(rawStream) {
    const AudioContextCtor = window.AudioContext || window.webkitAudioContext
    if (!AudioContextCtor) return rawStream

    const audioContext = new AudioContextCtor()
    await audioContext.resume().catch(() => {})

    const source = audioContext.createMediaStreamSource(rawStream)

    const highpass = audioContext.createBiquadFilter()
    highpass.type = "highpass"
    highpass.frequency.value = HIGH_PASS_FREQUENCY_HZ
    highpass.Q.value = HIGH_PASS_Q

    const compressor = audioContext.createDynamicsCompressor()
    compressor.threshold.value = COMPRESSOR_SETTINGS.threshold
    compressor.knee.value = COMPRESSOR_SETTINGS.knee
    compressor.ratio.value = COMPRESSOR_SETTINGS.ratio
    compressor.attack.value = COMPRESSOR_SETTINGS.attack
    compressor.release.value = COMPRESSOR_SETTINGS.release

    const makeupGain = audioContext.createGain()
    makeupGain.gain.value = MAKEUP_GAIN

    const destination = audioContext.createMediaStreamDestination()
    destination.channelCount = 1
    destination.channelCountMode = "explicit"

    let gateNode = null
    try {
      await audioContext.audioWorklet.addModule(NOISE_GATE_WORKLET_URL)
      gateNode = new AudioWorkletNode(audioContext, "noise-gate-processor", {
        numberOfInputs: 1,
        numberOfOutputs: 1,
        channelCount: 1,
        processorOptions: GATE_DEFAULTS,
      })
    } catch (err) {
      console.warn("BrowserBroadcast: noise gate worklet unavailable, skipping it.", err)
    }

    source.connect(highpass)
    let lastNode = highpass
    if (gateNode) {
      highpass.connect(gateNode)
      lastNode = gateNode
    }
    lastNode.connect(compressor)
    compressor.connect(makeupGain)
    makeupGain.connect(destination)

    this.audioContext = audioContext
    return destination.stream
  },

  teardown() {
    if (this.recorder && this.recorder.state !== "inactive") this.recorder.stop()
    this.recorder = null

    if (this.audioContext) this.audioContext.close().catch(() => {})
    this.audioContext = null

    if (this.rawStream) this.rawStream.getTracks().forEach((track) => track.stop())
    this.rawStream = null
    this.stream = null

    if (this.channel) this.channel.leave()
    this.channel = null

    if (this.socket) this.socket.disconnect()
    this.socket = null

    this.idleEl.classList.remove("hidden")
    this.liveEl.classList.add("hidden")
  },

  showError(message) {
    this.errorEl.textContent = message
    this.errorEl.classList.remove("hidden")
  },

  clearError() {
    this.errorEl.textContent = ""
    this.errorEl.classList.add("hidden")
  },
}
