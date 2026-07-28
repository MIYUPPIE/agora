// Pairs with the `.tilt` CSS utility (assets/css/app.css): tracks the
// pointer over the element and sets --tilt-rx/--tilt-ry, which the CSS
// turns into a subtle perspective rotation. Only runs on devices that
// actually have a hovering, fine pointer (a real mouse/trackpad) — on
// touch, tilt has no meaningful input to react to, so this stays inert
// and the element just keeps whatever tap/press feedback its own
// classes already provide.
const MAX_DEGREES = 8

export const Tilt = {
  mounted() {
    if (!window.matchMedia("(hover: hover) and (pointer: fine)").matches) return

    this.onMove = (e) => {
      const rect = this.el.getBoundingClientRect()
      const px = (e.clientX - rect.left) / rect.width - 0.5
      const py = (e.clientY - rect.top) / rect.height - 0.5
      this.el.style.setProperty("--tilt-rx", `${(px * MAX_DEGREES).toFixed(2)}deg`)
      this.el.style.setProperty("--tilt-ry", `${(py * -MAX_DEGREES).toFixed(2)}deg`)
    }

    this.onLeave = () => {
      this.el.style.setProperty("--tilt-rx", "0deg")
      this.el.style.setProperty("--tilt-ry", "0deg")
    }

    this.el.addEventListener("mousemove", this.onMove)
    this.el.addEventListener("mouseleave", this.onLeave)
  },

  destroyed() {
    this.el.removeEventListener("mousemove", this.onMove)
    this.el.removeEventListener("mouseleave", this.onLeave)
  }
}
