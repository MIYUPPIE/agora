const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = plugin(function(api) {
  let matchComponents = api && api.matchComponents
  let theme = api && api.theme
  if (!matchComponents || !theme) return

  let iconsDir = path.join(__dirname, "../../deps/heroicons/optimized")
  if (!fs.existsSync(iconsDir)) return

  let values = {}
  let icons = [
    ["", "/24/outline"],
    ["-solid", "/24/solid"],
    ["-mini", "/20/solid"],
    ["-micro", "/16/solid"]
  ]
  icons.forEach(([suffix, dir]) => {
    let fullDir = path.join(iconsDir, dir)
    if (fs.existsSync(fullDir)) {
      fs.readdirSync(fullDir).forEach(file => {
        let name = path.basename(file, ".svg") + suffix
        values[name] = path.join(fullDir, file)
      })
    }
  })
  matchComponents({
    "hero": (fullPath) => {
      if (typeof fullPath !== "string" || !fs.existsSync(fullPath)) return {}
      let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
      content = encodeURIComponent(content)
      return {
        [`--hero-icon`]: `url('data:image/svg+xml;utf8,${content}')`,
        "-webkit-mask": `var(--hero-icon)`,
        "mask": `var(--hero-icon)`,
        "mask-repeat": "no-repeat",
        "background-color": "currentColor",
        "vertical-align": "middle",
        "display": "inline-block"
      }
    }
  }, {values})
})
