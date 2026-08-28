// A small "copy" affordance over a read-only value (the OBS RTMP ingest
// URL, currently) that copies the value's own text — read straight from
// its `[data-role="ingest-url"]` element, never duplicated into a data
// attribute — into the clipboard, and flashes a "Copied" confirmation.
// The container carries `phx-update="ignore"` so LiveView re-renders
// elsewhere on the page (chat, effects, transcript) never reset the
// flash mid-animation.
export const CopyToClipboard = {
  mounted() {
    this.valueEl = this.el.querySelector('[data-role="ingest-url"]')
    this.idleEl = this.el.querySelector('[data-role="idle"]')
    this.copiedEl = this.el.querySelector('[data-role="copied"]')
    this.resetTimer = null

    this.el.addEventListener("click", () => this.copy())
  },

  destroyed() {
    clearTimeout(this.resetTimer)
  },

  async copy() {
    const text = this.valueEl?.textContent?.trim()
    if (!text) return

    try {
      await navigator.clipboard.writeText(text)
    } catch (_err) {
      // Clipboard API can refuse (insecure context, denied permission) —
      // the URL is still fully visible and selectable in the <code>
      // block next to this button, so there's nothing further to do.
      return
    }

    this.idleEl.classList.add("hidden")
    this.copiedEl.classList.remove("hidden")

    clearTimeout(this.resetTimer)
    this.resetTimer = setTimeout(() => {
      this.idleEl.classList.remove("hidden")
      this.copiedEl.classList.add("hidden")
    }, 1500)
  },
}
