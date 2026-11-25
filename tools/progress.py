#!/usr/bin/env python3
"""Measure how far bitten is from running the target Mac app's window, and draw it.

  progress.py measure --mrun build/mrun --app path/App.app --out DIR [--commit SHA]
      run `mrun --check` on the app's main executable, append one row to DIR/history.csv
      (one row per commit) and redraw DIR/progress.svg
  progress.py backfill --out DIR   (all commands take --repo CHECKOUT)
      seed DIR/history.csv from the "... app window ... -> N" lines that every
      merged pull request wrote into docs/LOG.md
  progress.py draw --app path/App.app --check FILE --out DIR
      redraw DIR/progress.svg from a saved `mrun --check` report

The numbers are imports of the target Mac app (its main executable and the
frameworks it bundles): an import counts as done when bitten binds it. That is
a floor, not a schedule: one SwiftUI symbol can be a day's work and one
libSystem symbol a minute's. The roadmap layers in docs/ROADMAP.md are the
other half of the picture and are drawn next to it.

Nothing from the disk image is written out: only counts.
Standard-library Python, like tools/dmgx."""
import csv
import datetime
import os
import re
import subprocess
import sys

# The checkout whose docs and history are read (--repo, default this one).
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NM_CANDIDATES = ["llvm-nm", "llvm-nm-19", "llvm-nm-18", "llvm-nm-17"]

# Area of the work each imported library belongs to, in roadmap order.
AREAS = [
    ("System", "libSystem, libobjc, CoreFoundation, ...",
     ["libSystem", "libobjc", "CoreFoundation", "Security", "IOKit",
      "CoreServices", "SystemConfiguration", "ServiceManagement", "Carbon",
      "libc++", "libz", "libcompression"]),
    ("Swift", "runtime and standard library", ["libswift*"]),
    ("Foundation", "strings, collections, files, run loops", ["Foundation"]),
    ("Graphics", "CoreGraphics, CoreText, Metal, ...",
     ["CoreGraphics", "CoreText", "QuartzCore", "ImageIO", "CoreImage",
      "Metal", "MetalKit", "CoreVideo", "IOSurface"]),
    ("AppKit", "windows, views, events, menus", ["AppKit"]),
    ("SwiftUI", "SwiftUI, Combine, Observation",
     ["SwiftUI", "SwiftUICore", "Combine", "Observation"]),
    ("Other", "Network, CryptoKit, AppIntents, ...", ["*"]),
]
AREA_NAMES = [a[0] for a in AREAS]


def area_of(lib):
    lib = os.path.basename(lib)
    lib = re.sub(r"(\.A|\.B|\.1)?\.dylib$", "", lib)
    if lib.startswith("libswift"):
        lib_key = "libswift*"
    else:
        lib_key = lib
    for name, _, libs in AREAS:
        if lib_key in libs:
            return name
    return "Other"


# ---------------------------------------------------------------- measuring

def find_nm():
    for n in NM_CANDIDATES:
        for d in os.environ.get("PATH", "").split(os.pathsep):
            if os.access(os.path.join(d, n), os.X_OK):
                return n
    sys.exit("progress.py: no llvm-nm on PATH")


def app_images(app):
    """(name, path) of the app's main executable (CFBundleExecutable) and of
    each framework bundled in Contents/Frameworks: the code the app ships."""
    import plistlib
    try:
        with open(os.path.join(app, "Contents", "Info.plist"), "rb") as f:
            exe = plistlib.load(f)["CFBundleExecutable"]
    except (OSError, KeyError, plistlib.InvalidFileException):
        exe = os.path.basename(app).rsplit(".", 1)[0]
    main = os.path.join(app, "Contents", "MacOS", exe)
    if not os.path.exists(main):
        sys.exit("progress.py: no main executable at %s" % main)
    imgs = [(exe, main)]
    fw = os.path.join(app, "Contents", "Frameworks")
    for d in sorted(os.listdir(fw)) if os.path.isdir(fw) else []:
        name = d[:-len(".framework")] if d.endswith(".framework") else None
        if name and os.path.isfile(os.path.join(fw, d, name)):
            imgs.append((name, os.path.realpath(os.path.join(fw, d, name))))
    return imgs


def import_totals(app):
    """Imports per area of the app and its bundled frameworks (fixed by the binaries)."""
    nm = find_nm()
    totals = dict.fromkeys(AREA_NAMES, 0)
    for _, path in app_images(app):
        out = subprocess.run([nm, "-m", "-u", "--arch=x86_64", path],
                             capture_output=True, text=True, check=True).stdout
        for line in out.splitlines():
            m = re.search(r"\(from (.+)\)$", line)
            if m:
                totals[area_of(m.group(1))] += 1
    return totals


def missing_from_report(text, names):
    missing = dict.fromkeys(AREA_NAMES, 0)
    for line in text.splitlines():
        f = line.split("\t")
        if f[0] == "MISSING" and len(f) >= 4 and f[1] in names:
            missing[area_of(f[2])] += 1
    return missing


def run_check(mrun, app):
    main = app_images(app)[0][1]
    p = subprocess.run([mrun, "--check", main], capture_output=True, text=True,
                       timeout=900)
    if "SUMMARY" not in p.stdout:
        sys.exit("progress.py: mrun --check gave no report:\n" + p.stderr[-2000:])
    return p.stdout


# ------------------------------------------------------------------ history

FIELDS = ["date", "commit", "source", "missing"] + ["missing_" + a for a in AREA_NAMES]


def read_history(path):
    if not os.path.exists(path):
        return []
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def write_history(path, rows):
    rows = sorted(rows, key=lambda r: r["date"])
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, FIELDS, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in FIELDS})


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True,
                          text=True, check=True).stdout


NUM = r"(\d{1,2},\d{3}|\d{3,5})"


def log_number(text):
    """The last 'the target app's window ...' measurement written in a version of LOG.md."""
    last = None
    for m in re.finditer(r"(?:[Tt]he (?:target |Mac )?app(?:'s)?|[Tt]arget app(?:'s)?) window[^\n]*(?:\n(?!- |#)[^\n]*){0,2}", text):
        nums = re.findall(NUM, m.group(0))
        nums = [int(n.replace(",", "")) for n in nums]
        nums = [n for n in nums if 1000 <= n <= 6000]
        if nums:
            last = nums[-1]
    return last


def backfill(out):
    path = os.path.join(out, "history.csv")
    rows = read_history(path)
    seen = {r["commit"] for r in rows}
    for line in git("log", "--first-parent", "--reverse", "--format=%H %cI",
                    "origin/main", "--", "docs/LOG.md").splitlines():
        sha, date = line.split()
        if sha[:12] in seen:
            continue
        try:
            text = git("show", "%s:docs/LOG.md" % sha)
        except subprocess.CalledProcessError:
            continue
        n = log_number(text)
        if n is None:
            continue
        rows.append({"date": date, "commit": sha[:12], "source": "log",
                     "missing": n})
    # Keep one point per value change so the line shows steps, not noise.
    rows.sort(key=lambda r: r["date"])
    kept, prev = [], None
    for r in rows:
        if r["source"] != "log" or r["missing"] != prev:
            kept.append(r)
        prev = r["missing"]
    write_history(path, kept)
    print("history: %d points" % len(kept))


# ------------------------------------------------------------------ roadmap

def roadmap_layers():
    layers = []
    path = os.path.join(ROOT, "docs", "ROADMAP.md")
    for line in open(path):
        m = re.match(r"\|\s*(\d+)\s*\|(.*?)\|(.*?)\|", line)
        if not m:
            continue
        num, name, state = int(m.group(1)), m.group(2), m.group(3).strip().lower()
        name = re.sub(r"[*`]", "", name).strip()
        name = re.split(r"[:(]", name)[0].strip()
        if state.startswith("done"):
            s = "done"
        elif state.startswith("not started"):
            s = "todo"
        else:
            s = "partial"
        layers.append((num, name, s))
    return layers


# --------------------------------------------------------------------- svg

def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;"))


def fmt(n):
    return "{:,}".format(int(n))


AREA_COLORS = {
    "System": "#6366f1", "Swift": "#f97316", "Foundation": "#0ea5e9",
    "Graphics": "#14b8a6", "AppKit": "#8b5cf6", "SwiftUI": "#ec4899",
    "Other": "#64748b",
}

STYLE = """
<style>
  .card  { fill: #ffffff; stroke: #e5e7eb; }
  .panel { fill: #f8fafc; stroke: #eef2f6; }
  .ink   { fill: #0f172a; }
  .mute  { fill: #64748b; }
  .soft  { fill: #94a3b8; }
  .track { fill: #e9edf3; }
  .grid  { stroke: #e5e7eb; }
  .chip  { fill: #eef2ff; }
  .chipt { fill: #4338ca; }
  .ringtrack { stroke: #e9edf3; }
  .halo  { fill: #ffffff; }
  .done  { fill: #10b981; } .donet { fill: #047857; } .doneb { fill: #d1fae5; }
  .part  { fill: #f59e0b; } .partt { fill: #b45309; } .partb { fill: #fef3c7; }
  .todo  { fill: #cbd5e1; } .todot { fill: #64748b; } .todob { fill: #f1f5f9; }
  @media (prefers-color-scheme: dark) {
    .card  { fill: #0d1117; stroke: #30363d; }
    .panel { fill: #161b22; stroke: #21262d; }
    .ink   { fill: #e6edf3; }
    .mute  { fill: #9198a1; }
    .soft  { fill: #6e7681; }
    .track { fill: #21262d; }
    .grid  { stroke: #21262d; }
    .chip  { fill: #1f2447; }
    .chipt { fill: #a5b4fc; }
    .ringtrack { stroke: #21262d; }
    .halo  { fill: #0d1117; }
    .donet { fill: #34d399; } .doneb { fill: #0b3b2c; }
    .partt { fill: #fbbf24; } .partb { fill: #3d2e0a; }
    .todo  { fill: #484f58; } .todot { fill: #9198a1; } .todob { fill: #21262d; }
  }
  text { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Inter",
         Helvetica, Arial, sans-serif; }
  .num { font-variant-numeric: tabular-nums; }
</style>
"""


def draw(out, totals, missing, history, commit, when):
    import math
    W, P = 880, 28                       # width, outer padding
    total = sum(totals.values())
    left = sum(min(missing[a], totals[a]) for a in AREA_NAMES)
    done = total - left
    frac = done / total if total else 0
    layers = roadmap_layers()
    n_done = sum(1 for l in layers if l[2] == "done")
    n_part = sum(1 for l in layers if l[2] == "partial")
    n_todo = len(layers) - n_done - n_part
    pts = [(datetime.datetime.fromisoformat(r["date"]), int(r["missing"]))
           for r in history if r.get("missing")]

    s = []
    T = s.append

    def text(x, y, body, cls="ink", size=13, weight=400, anchor="start", extra=""):
        if ' class="num"' in extra:
            extra = extra.replace(' class="num"', "")
            cls = (cls + " num").strip()
        T('<text x="%.1f" y="%.1f" class="%s" font-size="%s" font-weight="%d"'
          ' text-anchor="%s"%s>%s</text>' % (x, y, cls, size, weight, anchor, extra, body))

    def panel(x, y, w, h):
        T('<rect x="%d" y="%d" width="%d" height="%d" rx="14" class="panel"/>' % (x, y, w, h))

    # ---- header
    y = 46
    T('<rect x="%d" y="%d" width="10" height="26" rx="3" fill="url(#brand)"/>' % (P, y - 21))
    text(P + 20, y, "bitten", size=22, weight=700)
    text(P + 92, y, "· running a Mac app on Linux", "mute", 15)
    cw = 9 + 7.2 * (len(commit[:7]) + 7)
    T('<rect x="%.1f" y="%d" width="%.1f" height="24" rx="12" class="chip"/>'
      % (W - P - cw, y - 17, cw))
    text(W - P - cw / 2, y - 1, "main @ " + esc(commit[:7]), "chipt", 12, 600, "middle",
         ' font-family="ui-monospace, SFMono-Regular, Menlo, monospace"')
    text(W - P - cw - 12, y - 1, "updated " + esc(when), "mute", 12, anchor="end")

    # ---- hero: ring + numbers + stat tiles
    y = 76
    panel(P, y, W - 2 * P, 156)
    cx, cy, r = P + 86, y + 78, 52
    circ = 2 * math.pi * r
    T('<circle cx="%d" cy="%d" r="%d" fill="none" class="ringtrack" stroke-width="13"/>'
      % (cx, cy, r))
    T('<circle cx="%d" cy="%d" r="%d" fill="none" stroke="url(#ring)" stroke-width="13"'
      ' stroke-linecap="round" stroke-dasharray="%.1f %.1f"'
      ' transform="rotate(-90 %d %d)"/>' % (cx, cy, r, circ * frac, circ, cx, cy))
    text(cx, cy + 9, "%d%%" % round(frac * 100), size=27, weight=750, anchor="middle")
    hx = P + 168
    text(hx, y + 50, "Mac app imports implemented", "mute", 13, 500)
    text(hx, y + 88, '%s <tspan class="soft" font-size="20" font-weight="500">/ %s</tspan>'
         % (fmt(done), fmt(total)), size=34, weight=750, extra=' class="num"')
    text(hx, y + 116, "%s still to go" % fmt(left), "mute", 13.5)

    tiles = [("%d / %d" % (n_done, len(layers)), "layers done", "donet")]
    tiles.append(("%d" % n_part, "layers in progress", "partt"))
    if len(pts) >= 2 and pts[0][1] > pts[-1][1]:
        tiles.append(("−%s" % fmt(pts[0][1] - pts[-1][1]),
                      "since %s" % pts[0][0].strftime("%b %-d"), "ink"))
    tw, th, gap = 118, 58, 10
    tx = W - P - 18 - len(tiles) * tw - (len(tiles) - 1) * gap
    for i, (big, small, cls) in enumerate(tiles):
        x = tx + i * (tw + gap)
        T('<rect x="%d" y="%d" width="%d" height="%d" rx="11" class="card"/>'
          % (x, y + 49, tw, th))
        text(x + 14, y + 76, big, cls, 19, 700, extra=' class="num"')
        text(x + 14, y + 95, small, "mute", 11.5)

    # ---- by area
    y += 156 + 22
    rows = [a for a in AREAS if totals[a[0]]]
    ph = 52 + len(rows) * 38
    panel(P, y, W - 2 * P, ph)
    text(P + 22, y + 32, "By area", size=15, weight=650)
    text(W - P - 22, y + 32, "implemented / imported", "soft", 11.5, anchor="end")
    bx, bw = P + 262, W - 2 * P - 262 - 178
    yy = y + 52
    for name, desc, _ in rows:
        t = totals[name]
        d = t - min(missing[name], t)
        col = AREA_COLORS.get(name, "#64748b")
        T('<circle cx="%d" cy="%d" r="5" fill="%s"/>' % (P + 28, yy + 13, col))
        text(P + 42, yy + 13, esc(name), size=13.5, weight=600, extra=' dominant-baseline="middle"')
        text(P + 42, yy + 29, esc(desc), "soft", 10.5)
        T('<rect x="%d" y="%d" width="%d" height="12" rx="6" class="track"/>'
          % (bx, yy + 7, bw))
        if d:
            T('<rect x="%d" y="%d" width="%.1f" height="12" rx="6" fill="%s"/>'
              % (bx, yy + 7, max(bw * d / t, 12), col))
        text(W - P - 102, yy + 17, "%d%%" % round(100.0 * d / t), size=13.5, weight=700,
             anchor="end", extra=' class="num"')
        text(W - P - 22, yy + 17, "%s/%s" % (fmt(d), fmt(t)), "soft", 11,
             anchor="end", extra=' class="num"')
        yy += 38

    # ---- trend
    y += ph + 22
    ch = 170
    ph = ch + 86
    panel(P, y, W - 2 * P, ph)
    text(P + 22, y + 32, "Imports still missing", size=15, weight=650)
    text(W - P - 22, y + 32, "one step per merged change", "soft", 11.5, anchor="end")
    gx, gy, gw = P + 64, y + 52, W - 2 * P - 64 - 30
    if len(pts) >= 2:
        t0, t1 = pts[0][0], pts[-1][0]
        span = max((t1 - t0).total_seconds(), 1)
        top = max(total, max(v for _, v in pts))
        top = (top + 999) // 1000 * 1000
        for k in range(0, top + 1, 1000):
            ly = gy + ch - ch * k / top
            T('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" class="grid" stroke-width="1"%s/>'
              % (gx, ly, gx + gw, ly, "" if k == 0 else ' stroke-dasharray="3 5"'))
            text(gx - 10, ly + 4, fmt(k), "soft", 10.5, anchor="end", extra=' class="num"')

        def px(t, v):
            return (gx + gw * (t - t0).total_seconds() / span, gy + ch - ch * v / top)
        line = []
        for i, (t, v) in enumerate(pts):
            x_, y_ = px(t, v)
            line.append(("M%.1f %.1f" % (x_, y_)) if not i else ("H%.1f V%.1f" % (x_, y_)))
        line = " ".join(line)
        x0, _ = px(*pts[0])
        xe, ye = px(*pts[-1])
        T('<path d="%s V%.1f H%.1f Z" fill="url(#area)"/>' % (line, gy + ch, x0))
        T('<path d="%s" fill="none" stroke="#6366f1" stroke-width="2.4"'
          ' stroke-linejoin="round"/>' % line)
        T('<circle cx="%.1f" cy="%.1f" r="9" fill="#6366f1" opacity="0.18"/>' % (xe, ye))
        T('<circle cx="%.1f" cy="%.1f" r="4.5" class="halo" stroke="#6366f1"'
          ' stroke-width="2.4"/>' % (xe, ye))
        lbl = fmt(pts[-1][1])
        lw = 12 + 7.6 * len(lbl)
        T('<rect x="%.1f" y="%.1f" width="%.1f" height="22" rx="11" fill="#6366f1"/>'
          % (xe - lw - 12, ye - 32, lw))
        text(xe - 12 - lw / 2, ye - 17, lbl, "", 12, 700, "middle",
             ' fill="#ffffff" style="fill:#fff"')
        text(gx, gy + ch + 22, t0.strftime("%b %-d, %H:%M"), "soft", 11)
        text(gx + gw, gy + ch + 22, t1.strftime("%b %-d, %H:%M"), "soft", 11, anchor="end")
        days = (t1 - t0).total_seconds() / 86400
        gone = pts[0][1] - pts[-1][1]
        if days >= 3 and gone > 0:
            text(gx + gw / 2, gy + ch + 22, "about %s fewer a day" % fmt(gone / days),
                 "mute", 11, anchor="middle")
    else:
        text(gx, gy + 40, "Not enough history yet.", "mute", 12)

    # ---- roadmap
    y += ph + 22
    half = (len(layers) + 1) // 2
    ph = 66 + half * 30 + 8
    panel(P, y, W - 2 * P, ph)
    text(P + 22, y + 32, "Roadmap", size=15, weight=650)
    text(W - P - 22, y + 32, "%d done · %d in progress · %d not started"
         % (n_done, n_part, n_todo), "soft", 11.5, anchor="end")
    # stacked strip of the layers
    sx, sw = P + 22, W - 2 * P - 44
    seg = sw / max(len(layers), 1)
    for i, (_, _, st) in enumerate(layers):
        T('<rect x="%.1f" y="%d" width="%.1f" height="6" rx="3" class="%s"/>'
          % (sx + i * seg + 1, y + 44, seg - 2, {"done": "done", "partial": "part",
                                                  "todo": "todo"}[st]))
    colw = (W - 2 * P - 44) / 2
    for i, (num, name, st) in enumerate(layers):
        col, row = (0, i) if i < half else (1, i - half)
        lx, ly = P + 22 + col * colw, y + 66 + row * 30
        pill = {"done": ("doneb", "donet", "done"),
                "partial": ("partb", "partt", "in progress"),
                "todo": ("todob", "todot", "to do")}[st]
        text(lx, ly + 14, "%2d" % num, "soft", 11.5, 600, extra=' class="num"')
        label = name if len(name) <= 38 else name[:37].rstrip(" ,") + "…"
        text(lx + 24, ly + 14, esc(label), "ink" if st != "todo" else "mute", 12.5,
             500 if st != "todo" else 400)
        pw = 14 + 6.6 * len(pill[2])
        T('<rect x="%.1f" y="%d" width="%.1f" height="19" rx="9.5" class="%s"/>'
          % (lx + colw - pw - 18, ly + 1, pw, pill[0]))
        text(lx + colw - 18 - pw / 2, ly + 14, pill[2], pill[1], 10.5, 650, "middle")

    y += ph + 20
    text(W / 2, y + 4, "Counts are a floor, not a schedule: one SwiftUI symbol can be a"
         " day of work, one libSystem symbol a minute.", "soft", 11, anchor="middle")
    H = y + 26

    defs = ('<defs>'
            '<linearGradient id="brand" x1="0" y1="0" x2="0" y2="1">'
            '<stop offset="0" stop-color="#6366f1"/><stop offset="1" stop-color="#ec4899"/>'
            '</linearGradient>'
            '<linearGradient id="ring" x1="0" y1="0" x2="1" y2="1">'
            '<stop offset="0" stop-color="#10b981"/><stop offset="1" stop-color="#0ea5e9"/>'
            '</linearGradient>'
            '<linearGradient id="area" x1="0" y1="0" x2="0" y2="1">'
            '<stop offset="0" stop-color="#6366f1" stop-opacity="0.28"/>'
            '<stop offset="1" stop-color="#6366f1" stop-opacity="0.02"/>'
            '</linearGradient></defs>')
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">\n'
           '%s%s\n<rect x="0.5" y="0.5" width="%d" height="%d" rx="18" class="card"/>\n%s\n</svg>\n'
           % (W, H, W, H, STYLE, defs, W - 1, H - 1, "\n".join(s)))
    with open(os.path.join(out, "progress.svg"), "w") as f:
        f.write(svg)


# --------------------------------------------------------------------- main

def arg(name, default=None):
    if name in sys.argv:
        return sys.argv[sys.argv.index(name) + 1]
    if default is None:
        sys.exit("progress.py: %s is required" % name)
    return default


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("measure", "backfill", "draw"):
        sys.exit(__doc__)
    cmd = sys.argv[1]
    global ROOT
    ROOT = os.path.abspath(arg("--repo", ROOT))
    out = arg("--out")
    os.makedirs(out, exist_ok=True)
    hist_path = os.path.join(out, "history.csv")
    if cmd == "backfill":
        backfill(out)
        return
    app = arg("--app")
    totals = import_totals(app)
    commit = arg("--commit", git("rev-parse", "HEAD").strip())
    if cmd == "measure":
        report = run_check(arg("--mrun", os.path.join(ROOT, "build", "mrun")), app)
    else:
        report = open(arg("--check")).read()
    missing = missing_from_report(report, {n for n, _ in app_images(app)})
    now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
    history = read_history(hist_path)
    if cmd == "measure":
        history = [r for r in history if r["commit"] != commit[:12]]
        row = {"date": now.isoformat(), "commit": commit[:12], "source": "measured",
               "missing": sum(min(missing[a], totals[a]) for a in AREA_NAMES)}
        for a in AREA_NAMES:
            row["missing_" + a] = missing[a]
        history.append(row)
        write_history(hist_path, history)
        history = read_history(hist_path)
    draw(out, totals, missing, history, commit, now.strftime("%Y-%m-%d %H:%M UTC"))
    print("progress: %s missing of %s imports; wrote %s"
          % (fmt(sum(min(missing[a], totals[a]) for a in AREA_NAMES)),
             fmt(sum(totals.values())), os.path.join(out, "progress.svg")))


if __name__ == "__main__":
    main()
