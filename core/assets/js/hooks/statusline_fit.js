// The statusline's left side (brand/crumb/live items) truncates with
// `overflow: hidden` when it doesn't fit, but a hard CSS clip cuts an item's
// text off mid-character. This hides whole `[data-statusline-item]` spans
// instead, starting from the most recently added, until what's left fits —
// so you either see a full status item or none of it, never a fragment.
export default {
  mounted() {
    this.fit = () => {
      const items = Array.from(this.el.querySelectorAll("[data-statusline-item]"))
      items.forEach(item => item.style.display = "")

      for (let i = items.length - 1; i >= 0 && this.el.scrollWidth > this.el.clientWidth; i--) {
        items[i].style.display = "none"
      }
    }

    this.fit()
    this.resizeObserver = new ResizeObserver(() => this.fit())
    this.resizeObserver.observe(this.el)
  },

  updated() {
    this.fit()
  },

  destroyed() {
    this.resizeObserver?.disconnect()
  }
}
