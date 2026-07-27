import Hls from "../../vendor/hls.mjs"

// Attaches an HLS manifest to an <audio> element. LiveView owns all
// state (gathering status, listener count) — this hook only wires up
// playback, using native HLS on Safari/iOS and hls.js everywhere else.
export const HlsPlayer = {
  mounted() {
    const src = this.el.dataset.manifest
    if (this.el.canPlayType("application/vnd.apple.mpegurl")) {
      this.el.src = src
    } else if (Hls.isSupported()) {
      this.hls = new Hls({ lowLatencyMode: false })
      this.hls.loadSource(src)
      this.hls.attachMedia(this.el)
    }
  },
  destroyed() {
    this.hls?.destroy()
  }
}
