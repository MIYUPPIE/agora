import { Socket } from "phoenix"

// Lets a broadcaster go live straight from this device's mic — no OBS,
// no external encoder. Captures audio with MediaRecorder and streams
// ~1s webm/opus chunks over a Phoenix Channel to
// Agora.Media.BrowserBroadcastBridge, which bridges them into the same
// RTMP ingest OBS would otherwise use (see that module's moduledoc).
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
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    } catch (_err) {
      this.showError("Microphone permission is required to broadcast from this device.")
      return
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

  teardown() {
    if (this.recorder && this.recorder.state !== "inactive") this.recorder.stop()
    this.recorder = null

    if (this.stream) this.stream.getTracks().forEach((track) => track.stop())
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
