// LiveView JS hooks contributed by this module (composed into core's
// bundle by nix). Keep hooks framework-free.

// A plain `<a download>` gives the browser no progress hook, and on mobile
// there's no visible sign anything is happening until the file lands —
// so fetch it ourselves with a streamed read and render our own bar from
// the bytes actually received, then hand the assembled blob off as a
// normal save.
const DownloadProgress = {
  mounted() {
    this.el.addEventListener("click", (e) => this.download(e));
  },

  async download(e) {
    e.preventDefault();
    if (this.busy) return;
    this.busy = true;

    const url = this.el.getAttribute("href");
    const filename =
      this.el.getAttribute("download") ||
      decodeURIComponent(url.split("/").pop().split("?")[0]);
    const original = this.el.innerHTML;

    this.el.innerHTML =
      '<span class="inline-flex items-center gap-1.5 whitespace-nowrap">' +
      '<span class="w-12 h-1 rounded-full bg-[#0D1113] border border-[#242D31] overflow-hidden inline-block">' +
      '<span class="dlp-fill block h-full bg-[#7FB069]" style="width:0%"></span>' +
      "</span>" +
      '<span class="dlp-pct tabular-nums">0%</span>' +
      "</span>";
    const fill = this.el.querySelector(".dlp-fill");
    const pct = this.el.querySelector(".dlp-pct");

    try {
      const res = await fetch(url);
      if (!res.ok || !res.body) throw new Error(`HTTP ${res.status}`);

      const total = parseInt(res.headers.get("Content-Length") || "0", 10);
      const reader = res.body.getReader();
      const chunks = [];
      let loaded = 0;

      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        chunks.push(value);
        loaded += value.length;
        if (total) {
          const p = Math.min(100, Math.round((loaded / total) * 100));
          fill.style.width = `${p}%`;
          pct.textContent = `${p}%`;
        }
      }

      const blob = new Blob(chunks, {
        type: res.headers.get("Content-Type") || "application/octet-stream",
      });
      const objectUrl = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = objectUrl;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      a.remove();
      // Revoking immediately can race with the browser's own (async,
      // especially on mobile Safari) read of the blob for the actual save —
      // the download can silently never complete for a large file. Give it
      // real headroom rather than revoking on the next tick.
      setTimeout(() => URL.revokeObjectURL(objectUrl), 30_000);
    } catch (err) {
      // Progress tracking failed (e.g. no Content-Length, network hiccup) —
      // still get the file to the user via a normal navigation-based download.
      console.error("[download-progress] falling back to plain navigation:", err);
      window.location.href = url;
    } finally {
      this.el.innerHTML = original;
      this.busy = false;
    }
  },
};

export default { DownloadProgress };
