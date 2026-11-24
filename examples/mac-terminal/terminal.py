#!/usr/bin/env python3
"""A live view of a Mac app terminal session.

The Mac app's own window is a SwiftUI/AppKit/Metal app, which bitten cannot run yet.
Its engine is the `appcli` server and CLI, a Mach-O program that bitten does run.
This script shows a Mac app terminal by driving that real CLI: the screen comes
from `appcli capture`, keystrokes go in through `appcli send`. Nothing here
reimplements the Mac app; it only gives its terminal somewhere to appear.

  terminal.py            serve the terminal on http://0.0.0.0:7680
  terminal.py --tty      show it in the current terminal (Ctrl-] quits)

Standard library only.
"""
import hashlib
import http.server
import os
import select
import subprocess
import sys
import termios
import threading
import time
import tty

APPCLI = os.environ.get("APPCLI", "appcli")
SESSION = os.environ.get("APP_SESSION", "main")
PORT = int(os.environ.get("PORT", "7680"))
send_lock = threading.Lock()


def appcli(*args, data=None, timeout=20):
    return subprocess.run([APPCLI, *args], input=data, capture_output=True, timeout=timeout)


def ensure_session():
    r = appcli("server", "start")
    if r.returncode != 0 and b"running" not in r.stdout + r.stderr:
        sys.exit("could not start the Mac app server:\n" + (r.stderr or r.stdout).decode(errors="replace"))
    labels = [line.split()[0] for line in appcli("ls").stdout.decode().splitlines()[1:] if line.split()]
    if SESSION not in labels:
        r = appcli("new", SESSION, "--cwd", os.path.expanduser("~"))
        if r.returncode != 0:
            sys.exit("could not create a Mac app session:\n" + r.stderr.decode(errors="replace"))
    version = appcli("version").stdout.decode().splitlines()
    return version[0] if version else "appcli"


def capture(fmt):
    r = appcli("capture", "-s", SESSION, "--format=" + fmt, "--trim")
    return r.stdout if r.returncode == 0 else b""


def send(data):
    if data:
        with send_lock:
            appcli("send", "-s", SESSION, data=data)


PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>the Mac app terminal</title>
<style>
  :root { color-scheme: dark; __PALETTE__ }
  html, body { height: 100%; margin: 0; background: #14161a; color: #d7dae0; }
  body { display: flex; flex-direction: column; font: 14px/1.35 ui-monospace, "SF Mono", Menlo, Consolas, monospace; }
  header { display: flex; gap: 12px; align-items: baseline; padding: 8px 14px; background: #1d2026;
           border-bottom: 1px solid #2c3038; font-family: system-ui, sans-serif; font-size: 13px; }
  header b { color: #f2f3f5; } header span { color: #8b919c; }
  #state { margin-left: auto; }
  #wrap { flex: 1; overflow: auto; padding: 10px 14px; outline: none; }
  #screen { min-height: 100%; }
  #screen > div { font-family: inherit !important; }
  .cursor { display: inline-block; width: .6em; height: 1.1em; vertical-align: text-bottom; background: #d7dae0; opacity: .75; }
</style></head>
<body>
<header><b>the Mac app terminal</b><span>__VERSION__ &middot; macOS binary running on Linux via bitten</span><span id="state">connecting</span></header>
<div id="wrap" tabindex="0"><div id="screen"></div></div>
<script>
const wrap = document.getElementById('wrap'), screenEl = document.getElementById('screen'),
      state = document.getElementById('state');
let tag = '', pending = [], timer = null, busy = false;
async function refresh() {
  if (busy) return; busy = true;
  try {
    const r = await fetch('/screen?have=' + tag);
    if (r.status === 200) {
      const atBottom = wrap.scrollHeight - wrap.scrollTop - wrap.clientHeight < 40;
      tag = r.headers.get('X-Screen-Tag') || '';
      screenEl.innerHTML = await r.text();
      const inner = screenEl.firstElementChild || screenEl;
      const cur = document.createElement('span'); cur.className = 'cursor'; inner.appendChild(cur);
      if (atBottom) wrap.scrollTop = wrap.scrollHeight;
    }
    state.textContent = 'live';
  } catch (e) { state.textContent = 'disconnected'; }
  busy = false;
}
function flush() {
  timer = null;
  const bytes = new Uint8Array(pending); pending = [];
  fetch('/input', {method: 'POST', body: bytes}).then(refresh);
}
function push(str) {
  for (const b of new TextEncoder().encode(str)) pending.push(b);
  if (!timer) timer = setTimeout(flush, 15);
}
const special = {Enter: '\\r', Backspace: '\\x7f', Tab: '\\t', Escape: '\\x1b', ArrowUp: '\\x1b[A',
  ArrowDown: '\\x1b[B', ArrowRight: '\\x1b[C', ArrowLeft: '\\x1b[D', Home: '\\x1b[H', End: '\\x1b[F',
  PageUp: '\\x1b[5~', PageDown: '\\x1b[6~', Delete: '\\x1b[3~'};
document.addEventListener('keydown', e => {
  if (e.metaKey) return;
  let out = null;
  if (special[e.key]) out = special[e.key];
  else if (e.key.length === 1) {
    if (e.ctrlKey) {
      const c = e.key.toUpperCase().charCodeAt(0);
      if (c >= 64 && c <= 95) out = String.fromCharCode(c - 64); else if (e.key === ' ') out = '\\x00';
    } else out = (e.altKey ? '\\x1b' : '') + e.key;
  }
  if (out !== null) { e.preventDefault(); push(out); }
});
document.addEventListener('paste', e => { push(e.clipboardData.getData('text')); e.preventDefault(); });
wrap.focus(); setInterval(refresh, 150); refresh();
</script></body></html>"""

BASE16 = ["#1d1f21", "#cc6666", "#b5bd68", "#f0c674", "#81a2be", "#b294bb", "#8abeb7", "#c5c8c6",
          "#666a70", "#d54e53", "#b9ca4a", "#e7c547", "#7aa6da", "#c397d8", "#70c0b1", "#eaeaea"]


def palette_css():
    colors = list(BASE16)
    steps = [0, 95, 135, 175, 215, 255]
    colors += ["#%02x%02x%02x" % (r, g, b) for r in steps for g in steps for b in steps]
    colors += ["#%02x%02x%02x" % (v, v, v) for v in range(8, 248, 10)]
    return " ".join("--vt-palette-%d: %s;" % (i, c) for i, c in enumerate(colors))


class Handler(http.server.BaseHTTPRequestHandler):
    version_line = "appcli"

    def log_message(self, *args):
        pass

    def reply(self, code, body=b"", ctype="text/plain; charset=utf-8", extra=()):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in extra:
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/" or self.path.startswith("/?"):
            page = PAGE.replace("__PALETTE__", palette_css()).replace("__VERSION__", self.version_line)
            self.reply(200, page.encode(), "text/html; charset=utf-8")
        elif self.path.startswith("/screen"):
            body = capture("html")
            tag = hashlib.sha1(body).hexdigest()[:16]
            if self.path.endswith("have=" + tag):
                self.reply(304)
            else:
                self.reply(200, body, "text/html; charset=utf-8", [("X-Screen-Tag", tag)])
        else:
            self.reply(404, b"not found\n")

    def do_POST(self):
        if self.path != "/input":
            return self.reply(404, b"not found\n")
        # same-origin only: this endpoint types into a shell
        origin = self.headers.get("Origin")
        if origin and origin.split("//", 1)[-1] != self.headers.get("Host", ""):
            return self.reply(403, b"cross-origin input refused\n")
        n = min(int(self.headers.get("Content-Length", "0") or 0), 65536)
        send(self.rfile.read(n))
        self.reply(204)


def serve():
    Handler.version_line = ensure_session()
    srv = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print("the Mac app terminal: http://localhost:%d  (%s)" % (PORT, Handler.version_line), flush=True)
    srv.serve_forever()


def tty_view():
    version = ensure_session()
    if not sys.stdin.isatty():
        sys.exit("--tty needs an interactive terminal (docker run -it)")
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    out = sys.stdout.buffer
    try:
        tty.setraw(fd)
        out.write(b"\x1b[?1049h")
        last = None
        while True:
            ready, _, _ = select.select([fd], [], [], 0.12)
            if ready:
                data = os.read(fd, 4096)
                if not data or b"\x1d" in data:  # Ctrl-]
                    break
                send(data)
            screen = capture("vt")
            if screen != last:
                last = screen
                rows = os.get_terminal_size().lines
                lines = screen.replace(b"\r\n", b"\n").rstrip(b"\n").split(b"\n")[-(rows - 1):]
                title = ("\x1b[7m the Mac app terminal | %s | Ctrl-] quits \x1b[0m" % version).encode()
                out.write(b"\x1b[H" + title + b"\x1b[K\r\n" + b"\x1b[K\r\n".join(lines) + b"\x1b[K\x1b[J")
                out.flush()
    finally:
        out.write(b"\x1b[?1049l")
        out.flush()
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)


if __name__ == "__main__":
    if "--tty" in sys.argv[1:]:
        tty_view()
    else:
        serve()
