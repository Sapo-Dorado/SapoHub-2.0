// Draggable floating assistant button, fixed bottom-right on every page
// (mounted from root.html.heex, outside any single LiveView's DOM, so a
// click navigates with a plain location change rather than a LiveView
// JS command). Position persists across reloads via localStorage — same
// interaction model as SapoHub v1's floating-assistant hook, restyled
// for v2's palette.
export default {
  mounted() {
    const el = this.el
    const STORAGE_KEY = "sapohub-floating-assistant-pos"

    const saved = localStorage.getItem(STORAGE_KEY)
    if (saved) {
      try {
        const { right, bottom } = JSON.parse(saved)
        el.style.right = right + "px"
        el.style.bottom = bottom + "px"
      } catch (_) {}
    }

    let startX, startY, startRight, startBottom
    let dragged = false

    const onMove = (clientX, clientY) => {
      const dx = clientX - startX
      const dy = clientY - startY
      if (Math.abs(dx) > 4 || Math.abs(dy) > 4) dragged = true
      if (!dragged) return

      el.style.cursor = "grabbing"
      el.style.right = Math.max(0, startRight - dx) + "px"
      el.style.bottom = Math.max(0, startBottom - dy) + "px"
    }

    const onUp = () => {
      document.removeEventListener("mousemove", onMouseMove)
      document.removeEventListener("mouseup", onMouseUp)
      document.removeEventListener("touchmove", onTouchMove)
      document.removeEventListener("touchend", onTouchEnd)
      el.style.cursor = "grab"

      if (!dragged) {
        window.location.href = "/assistant"
      } else {
        const right = parseFloat(el.style.right) || 24
        const bottom = parseFloat(el.style.bottom) || 24
        localStorage.setItem(STORAGE_KEY, JSON.stringify({ right, bottom }))
      }
      dragged = false
    }

    const onMouseMove = (e) => onMove(e.clientX, e.clientY)
    const onMouseUp = () => onUp()
    const onTouchMove = (e) => { e.preventDefault(); onMove(e.touches[0].clientX, e.touches[0].clientY) }
    const onTouchEnd = () => onUp()

    el.addEventListener("mousedown", (e) => {
      e.preventDefault()
      dragged = false
      startX = e.clientX
      startY = e.clientY
      startRight = parseFloat(el.style.right) || 24
      startBottom = parseFloat(el.style.bottom) || 24
      document.addEventListener("mousemove", onMouseMove)
      document.addEventListener("mouseup", onMouseUp)
    })

    el.addEventListener("touchstart", (e) => {
      dragged = false
      startX = e.touches[0].clientX
      startY = e.touches[0].clientY
      startRight = parseFloat(el.style.right) || 24
      startBottom = parseFloat(el.style.bottom) || 24
      document.addEventListener("touchmove", onTouchMove, { passive: false })
      document.addEventListener("touchend", onTouchEnd)
    })
  }
}
