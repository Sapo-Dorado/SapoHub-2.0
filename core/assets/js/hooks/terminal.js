import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { WebglAddon } from "@xterm/addon-webgl";
import { CanvasAddon } from "@xterm/addon-canvas";
import { Unicode11Addon } from "@xterm/addon-unicode11";
import { WebLinksAddon } from "@xterm/addon-web-links";

// Catppuccin Mocha — full 16-color ANSI palette, works well with Claude CLI's
// true-color output and readable at every color index (avoids dark-blue-on-dark)
const THEME = {
  background:                "#0D1113",
  foreground:                "#cdd6f4",
  cursor:                    "#f5e0dc",
  cursorAccent:              "#0D1113",
  selectionBackground:       "#45475a",
  selectionForeground:       "#cdd6f4",
  selectionInactiveBackground: "#313244",
  black:                     "#45475a",
  red:                       "#f38ba8",
  green:                     "#a6e3a1",
  yellow:                    "#f9e2af",
  blue:                      "#89b4fa",
  magenta:                   "#f5c2e7",
  cyan:                      "#94e2d5",
  white:                     "#bac2de",
  brightBlack:               "#585b70",
  brightRed:                 "#f38ba8",
  brightGreen:               "#a6e3a1",
  brightYellow:              "#f9e2af",
  brightBlue:                "#89b4fa",
  brightMagenta:             "#f5c2e7",
  brightCyan:                "#94e2d5",
  brightWhite:               "#a6adc8",
};

const TerminalHook = {
  mounted() {
    // data-session-id is a generic identifier — works for project UUIDs or "dashboard"
    const sessionId = this.el.dataset.sessionId;

    this.term = new Terminal({
      cursorBlink: true,
      fontSize: 14,
      fontFamily: '"JetBrains Mono", "Fira Code", "Cascadia Code", monospace',
      theme: THEME,
      scrollback: 5000,
      allowProposedApi: true,
      // Render box-drawing characters as pixel-perfect vectors, not font glyphs
      customGlyphs: true,
      // Prevent ambiguous-width glyphs (Claude spinners, symbols) from bleeding into adjacent cells
      rescaleOverlappingGlyphs: true,
      // Disable smooth scroll animation — reduces CPU during heavy output bursts
      smoothScrollDuration: 0,
      fastScrollSensitivity: 5,
    });

    // Unicode 11 — correct cell-width for CJK, emoji, and box-drawing characters
    const unicode11 = new Unicode11Addon();
    this.term.loadAddon(unicode11);
    this.term.unicode.activeVersion = "11";

    // Clickable URLs in output
    this.term.loadAddon(new WebLinksAddon());

    this.fitAddon = new FitAddon();
    this.term.loadAddon(this.fitAddon);
    this.term.open(this.el);

    // WebGL renderer (GPU-accelerated) with Canvas 2D fallback
    this._contextLost = false;
    try {
      const webgl = new WebglAddon();
      // If the GPU context is lost (sleep, tab switching), clean up gracefully
      // and flag so the visibilitychange handler knows to request a full replay.
      webgl.onContextLoss(() => {
        this._contextLost = true;
        webgl.dispose();
        try { this.term.loadAddon(new CanvasAddon()); } catch (_) {}
      });
      this.term.loadAddon(webgl);
    } catch (_) {
      try { this.term.loadAddon(new CanvasAddon()); } catch (_) {}
    }

    // Guard flag — async callbacks check this before touching the terminal so
    // they don't throw on a disposed instance if the hook is destroyed before
    // fonts have finished loading (e.g. user navigates away immediately).
    this._alive = true;

    // Mobile control buttons — keyed by session-id so multiple terminals on one
    // page don't conflict
    this.ctrlMode = false;
    const escBtn   = document.getElementById(`esc-btn-${sessionId}`);
    const ctrlBtn  = document.getElementById(`ctrl-btn-${sessionId}`);
    const tabBtn   = document.getElementById(`tab-btn-${sessionId}`);
    const upBtn    = document.getElementById(`up-btn-${sessionId}`);
    const downBtn  = document.getElementById(`down-btn-${sessionId}`);
    const textBtn  = document.getElementById(`text-btn-${sessionId}`);
    const pasteBtn = document.getElementById(`paste-btn-${sessionId}`);

    if (escBtn) {
      escBtn.addEventListener("click", () => {
        this.pushEvent("terminal_input", { data: "\x1b", session_id: sessionId });
        this.term.focus();
      });
    }

    if (ctrlBtn) {
      ctrlBtn.addEventListener("click", () => {
        // CTRL mode stays latched until tapped again — intentional, lets users
        // send multiple ctrl-chords (e.g. ctrl-a then ctrl-k) without re-tapping
        this.ctrlMode = !this.ctrlMode;
        ctrlBtn.style.backgroundColor = this.ctrlMode ? "rgb(59 130 246 / 0.3)" : "";
        ctrlBtn.style.borderColor     = this.ctrlMode ? "rgb(96 165 250)" : "";
        ctrlBtn.style.color           = this.ctrlMode ? "rgb(147 197 253)" : "";
        this.term.focus();
      });
    }

    if (tabBtn) {
      tabBtn.addEventListener("click", () => {
        this.pushEvent("terminal_input", { data: "\t", session_id: sessionId });
        this.term.focus();
      });
    }

    if (upBtn) {
      upBtn.addEventListener("click", () => {
        this.pushEvent("terminal_input", { data: "\x1b[A", session_id: sessionId });
        this.term.focus();
      });
    }

    if (downBtn) {
      downBtn.addEventListener("click", () => {
        this.pushEvent("terminal_input", { data: "\x1b[B", session_id: sessionId });
        this.term.focus();
      });
    }

    if (textBtn) {
      textBtn.addEventListener("click", () => {
        // xterm.js renders to canvas/WebGL — native touch text selection is impossible.
        // Work around this by extracting the buffer as plain text and showing it in a
        // modal overlay where the browser's normal long-press → select → copy menu works.
        const buf   = this.term.buffer.active;
        const end   = buf.viewportY + this.term.rows;
        const start = Math.max(0, end - 200);
        const lines = [];
        for (let r = start; r < end; r++) {
          const line = buf.getLine(r);
          if (line) lines.push(line.translateToString(true));
        }
        // Strip trailing blank lines.
        while (lines.length && !lines[lines.length - 1].trim()) lines.pop();
        const text = lines.join("\n");

        const overlay = document.createElement("div");
        overlay.style.cssText = [
          "position:fixed", "inset:0", "z-index:9999",
          "background:rgba(0,0,0,0.85)",
          "display:flex", "flex-direction:column",
          "padding:1rem", "gap:0.75rem",
        ].join(";");

        const header = document.createElement("div");
        header.style.cssText = "display:flex;justify-content:space-between;align-items:center;flex-shrink:0";

        const label = document.createElement("span");
        label.textContent = "Terminal output — select to copy";
        label.style.cssText = "font-family:monospace;font-size:0.75rem;color:#a6adc8;letter-spacing:0.05em;text-transform:uppercase";

        const closeBtn = document.createElement("button");
        closeBtn.textContent = "✕ Close";
        closeBtn.style.cssText = [
          "font-family:monospace", "font-size:0.875rem",
          "color:#cdd6f4", "background:transparent",
          "border:1px solid #45475a", "padding:0.25rem 0.75rem",
          "cursor:pointer",
        ].join(";");
        closeBtn.addEventListener("click", () => overlay.remove());

        header.appendChild(label);
        header.appendChild(closeBtn);

        const pre = document.createElement("pre");
        pre.textContent = text || "(no output)";
        pre.style.cssText = [
          "flex:1", "overflow-y:auto", "overflow-x:auto",
          "white-space:pre-wrap", "word-break:break-all",
          "font-family:\"JetBrains Mono\",\"Fira Code\",monospace",
          "font-size:0.8rem", "line-height:1.5",
          "color:#cdd6f4", "background:#0D1113",
          "border:1px solid #313244", "padding:0.75rem",
          "margin:0",
          "-webkit-user-select:text", "user-select:text",
        ].join(";");

        overlay.appendChild(header);
        overlay.appendChild(pre);
        document.body.appendChild(overlay);
      });
    }

    if (pasteBtn) {
      pasteBtn.addEventListener("click", () => {
        navigator.clipboard.readText().then((text) => {
          if (text) {
            this.pushEvent("terminal_input", { data: text, session_id: sessionId });
          }
          this.term.focus();
        }).catch(() => { this.term.focus(); });
      });
    }

    // Forward keystrokes to the LiveView (and on to the PTY)
    this.term.onData((data) => {
      if (this.ctrlMode && data.length === 1) {
        this.pushEvent("terminal_input", { data: String.fromCharCode(data.charCodeAt(0) & 0x1f), session_id: sessionId });
      } else {
        this.pushEvent("terminal_input", { data, session_id: sessionId });
      }
    });

    // Clear the terminal before a session replay so repeated replays
    // (mount, reconnect, tab return) don't stack duplicate output.
    this.handleEvent(`terminal_clear:${sessionId}`, () => {
      this.term.reset();
    });

    // Receive PTY output chunks (base64-encoded binary from Elixir)
    this.handleEvent(`terminal_output:${sessionId}`, ({ data }) => {
      const bytes = Uint8Array.from(atob(data), (c) => c.charCodeAt(0));
      this.term.write(new TextDecoder().decode(bytes));
    });

    this.handleEvent(`session_exit:${sessionId}`, ({ code }) => {
      this.term.write(`\r\n\x1b[33m[Session ended with exit code ${code}]\x1b[0m\r\n`);
    });

    // Refit and replay when this tab is activated (switched to from another tab).
    this.handleEvent(`activate_terminal:${sessionId}`, () => {
      if (!this._alive || !this._ready) return;
      try { this.fitAddon.fit(); } catch (_) {}
      this.pushEvent("terminal_resize", {
        cols: this.term.cols || 220,
        rows: this.term.rows || 30,
        session_id: sessionId,
      });
      this.pushEvent("replay_session", { session_id: sessionId });
    });

    // Whether the initial fit (fonts.ready + rAF) has run yet.
    // The ResizeObserver skips until this is true so only one terminal_resize
    // fires on setup — a mid-session resize causes Claude to redraw its status
    // line with stale cursor offsets, producing visual glitches.
    this._ready = false;

    // Keep PTY dimensions in sync with the container on user-driven resizes
    // (window resize, sidebar toggle, etc.).  Skipped until _ready so the
    // initial setup is the sole source of the first terminal_resize.
    this.resizeObserver = new ResizeObserver(() => {
      if (!this._alive || !this._ready) return;
      // Skip when hidden (display:none → offsetParent is null, width is 0).
      // Fitting a hidden element computes ~1 col and would squish PTY output.
      // The activate_terminal handler re-fits with correct dims when switching back.
      if (this.el.offsetParent === null || this.el.getBoundingClientRect().width === 0) return;
      this.fitAddon.fit();
      this.pushEvent("terminal_resize", {
        cols: this.term.cols,
        rows: this.term.rows,
        session_id: sessionId,
      });
    });
    this.resizeObserver.observe(this.el);

    // Send initial size and replay any buffered output for reconnecting clients.
    // fonts.ready ensures character cell dimensions are measured with the real
    // font before we fit.  requestAnimationFrame defers one frame so the browser
    // has committed layout — without it, fonts.ready resolves immediately during
    // live navigation (fonts are cached) but the element may not yet have been
    // laid out, causing fitAddon.fit() to compute 0 cols/rows.
    document.fonts.ready.then(() => {
      if (!this._alive) return;
      console.debug("[terminal] fonts.ready fired");
      requestAnimationFrame(() => {
        if (!this._alive) return;
        this._ready = true;
        // fit() can throw if the element has 0 dimensions (e.g. the terminal
        // div was just injected by a connected-mount diff and layout hasn't
        // committed yet).  Catch so the pushEvents always fire — we fall back
        // to the terminal's current cols/rows (default 80×24 from term.open).
        try {
          this.fitAddon.fit();
        } catch (e) {
          console.warn("[terminal] fitAddon.fit() threw:", e);
        }
        const cols = this.term.cols || 220;
        const rows = this.term.rows || 30;
        console.debug(`[terminal] setup → cols=${cols} rows=${rows} el-width=${this.el.getBoundingClientRect().width}`);
        this.pushEvent("terminal_resize", { cols, rows, session_id: sessionId });
        this.pushEvent("replay_session", { session_id: sessionId });
      });
    });

    // Re-fit and re-render when the user returns to this tab.
    // Always replay the session buffer on return: the WebSocket may have
    // reconnected while the tab was hidden (in which case reconnected() already
    // fired, but a second replay is harmless), or the GPU context may have been
    // lost and the Canvas fallback renderer needs the buffer refilled.
    this._onVisible = () => {
      if (document.visibilityState !== "visible" || !this._alive || !this._ready) return;
      try { this.fitAddon.fit(); } catch (_) {}
      this.pushEvent("terminal_resize", {
        cols: this.term.cols || 220,
        rows: this.term.rows || 30,
        session_id: sessionId,
      });
      this._contextLost = false;
      this.pushEvent("replay_session", { session_id: sessionId });
    };
    document.addEventListener("visibilitychange", this._onVisible);
  },

  // Called by LiveView when the WebSocket reconnects after a network drop
  // (e.g. the tab was backgrounded long enough for the server to time it out).
  // Re-fit and replay the full buffer so the terminal catches up.
  reconnected() {
    if (!this._alive) return;
    const sessionId = this.el.dataset.sessionId;
    console.debug("[terminal] LiveView reconnected — replaying session");
    try { this.fitAddon.fit(); } catch (_) {}
    this.pushEvent("terminal_resize", {
      cols: this.term.cols || 220,
      rows: this.term.rows || 30,
      session_id: sessionId,
    });
    this.pushEvent("replay_session", { session_id: sessionId });
  },

  destroyed() {
    this._alive = false;
    document.removeEventListener("visibilitychange", this._onVisible);
    if (this.resizeObserver) this.resizeObserver.disconnect();
    try { if (this.term) this.term.dispose(); } catch (_) {}
  },
};

export default TerminalHook;
