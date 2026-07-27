import Hls from "../../vendor/hls.mjs"

// A listener can land on this page within milliseconds of a Gathering
// going live — before the pipeline has written its first 4s segment (or
// even the manifest itself) to disk, so the very first manifest fetch
// 404s. hls.js hard-codes any HTTP 4xx as unretriable at the loader
// level ("such error cannot be recovered, retrying is useless" — see
// its own loader source), so no retry-policy config can paper over it;
// the load has to be retried from the outside instead. Confirmed hands-on
// (real browser + real pipeline): without this, that ordinary startup
// race turned into a permanent, unrecoverable playback error every time.
const MAX_STARTUP_RETRIES = 10
const RETRY_DELAY_MS = 1_500

// Attaches an HLS manifest to an <audio> element. LiveView owns all
// state (gathering status, listener count) — this hook only wires up
// playback.
//
// Hls.isSupported() is checked FIRST, not `canPlayType(...)` — Chrome's
// `canPlayType("application/vnd.apple.mpegurl")` can return "maybe"
// (a non-empty, truthy string) even though it can't actually play this
// fMP4-fragmented HLS content natively. Confirmed hands-on: trusting
// that truthy check sent Chrome down the native `<audio src=...>` path,
// where it failed every time with a demuxer parse error — hls.js's MSE
// based playback is what actually works there. Native HLS (`src=`
// directly) is only correct as a fallback for browsers where hls.js
// itself doesn't apply, i.e. Safari/iOS.
export const HlsPlayer = {
  mounted() {
    this.retries = 0
    this.src = this.el.dataset.manifest

    if (Hls.isSupported()) {
      this.attach()
    } else if (this.el.canPlayType("application/vnd.apple.mpegurl")) {
      this.el.src = this.src
    }
  },

  attach() {
    this.hls = new Hls({ lowLatencyMode: false })

    this.hls.on(Hls.Events.ERROR, (_event, data) => {
      if (data.fatal && data.type === Hls.ErrorTypes.NETWORK_ERROR && this.retries < MAX_STARTUP_RETRIES) {
        this.retries += 1
        this.hls.destroy()
        this.retryTimer = setTimeout(() => this.attach(), RETRY_DELAY_MS)
      }
    })

    this.hls.loadSource(this.src)
    this.hls.attachMedia(this.el)
  },

  destroyed() {
    clearTimeout(this.retryTimer)
    this.hls?.destroy()
  }
}
