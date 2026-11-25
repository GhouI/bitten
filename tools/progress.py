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
import math
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
#
# The chart is one card, shown through <img> in the README, so it is plain
# SVG: no script, no web fonts, light and dark from one <style> block.
# Three pictures, top to bottom, all drawn in the same three columns
# (labels, picture, values). The first and the last are stacks and read
# from the bottom up, the way the system is built:
#
#   areas    every import as one block, a row per area. A row's height is
#            how many imports the area has and its filled part is how many
#            are implemented, so filled area against the whole block is the
#            headline percentage
#   history  imports implemented over time, the axis zoomed to the range
#   roadmap  the layers as a stack, first layer at the bottom, the app on top
#
#   type     four sizes, two weights (TYPE); nothing else is used
#   spacing  multiples of 4, PAD at the card edge and around section rules
#   colour   one blue means "implemented" everywhere, a lighter step of the
#            same blue is work still open. Text never wears the blue.

W = 880                  # drawn width: GitHub's README column
PAD = 32                 # card edge, and the air above and below a rule
COL_L, COL_R = 108, 164  # label column and value column either side of a picture
GAP = 4                  # between rows of a picture
FONT = 'system-ui, -apple-system, "Segoe UI", Helvetica, Arial, sans-serif'

# class: (font-size, font-weight)
T_HERO, T_TITLE, T_BODY, T_SMALL = 56, 20, 14, 12
TYPE = {
    "hero":  (T_HERO, 600),
    "title": (T_TITLE, 600),
    "head":  (T_BODY, 600),
    "body":  (T_BODY, 400),
    "small": (T_SMALL, 400),
}

# role: (light, dark). Neutrals sit on GitHub's own page colours; the blues
# are steps of one ramp, checked for contrast against each surface.
COLORS = {
    "surface": ("#ffffff", "#0d1117"),
    "border":  ("#d1d9e0", "#3d444d"),
    "ink":     ("#1f2328", "#f0f6fc"),   # primary text
    "sec":     ("#59636e", "#9198a1"),   # secondary text
    "rule":    ("#e6eaef", "#262c36"),   # section rules and gridlines
    "axis":    ("#c2cad3", "#3d444d"),   # tick marks, outline of an unstarted layer
    "accent":  ("#2370cd", "#338ced"),   # implemented, done
    "track":   ("#84b9f3", "#0f4a96"),   # not yet implemented, in progress
}


def build_style():
    def rules(i):
        c = {k: v[i] for k, v in COLORS.items()}
        return [
            ".card { fill: %(surface)s; stroke: %(border)s; }" % c,
            ".ink { fill: %(ink)s; }" % c,
            ".sec { fill: %(sec)s; }" % c,
            ".rule { stroke: %(rule)s; }" % c,
            ".axis { stroke: %(axis)s; }" % c,
            ".fill { fill: %(accent)s; }" % c,
            ".track { fill: %(track)s; }" % c,
            ".notch { stroke: %(surface)s; stroke-opacity: 0.45; }" % c,
            ".line { stroke: %(accent)s; fill: none; }" % c,
            ".on { fill: %(surface)s; }" % c,
            ".dot { fill: %(accent)s; stroke: %(surface)s; }" % c,
            ".open { fill: %(surface)s; stroke: %(axis)s; }" % c,
            ".goal { fill: %(surface)s; stroke: %(ink)s; }" % c,
        ]
    out = ["<style>", "  text { font-family: %s; }" % FONT]
    for name, (size, weight) in TYPE.items():
        out.append("  .%s { font-size: %dpx; font-weight: %d; }" % (name, size, weight))
    out.append("  .hero { letter-spacing: -1.5px; }")
    out.append("  .num { font-variant-numeric: tabular-nums; }")
    out += ["  " + r for r in rules(0)]
    out.append("  @media (prefers-color-scheme: dark) {")
    out += ["    " + r for r in rules(1)]
    out += ["  }", "</style>"]
    return "\n".join(out)


STYLE = build_style()


def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;"))


def fmt(n):
    return "{:,}".format(int(n))


def est_width(s, size):
    """Advance width of a string, roughly. There are no font metrics here and
    the reader's system font is unknown, so this errs on the wide side."""
    w = 0.0
    for ch in s:
        if ch in " .,:;'|iljI!":
            w += 0.34
        elif ch in "tfr":
            w += 0.44
        elif ch in "mwMW%@":
            w += 0.98
        elif ch.isupper() or ch.isdigit():
            w += 0.72
        else:
            w += 0.64
    return w * size


def wrap(s, size, width):
    """Break a string at spaces into the fewest lines no wider than `width`,
    then even the lines out so the last one is not a single stray word."""
    def fill(limit):
        lines, cur = [], ""
        for word in s.split():
            trial = (cur + " " + word).strip()
            if cur and est_width(trial, size) > limit:
                lines.append(cur)
                cur = word
            else:
                cur = trial
        return lines + [cur] if cur else lines
    best = fill(width)
    limit = width - size
    while limit > 0 and len(best) > 1:
        tighter = fill(limit)
        if len(tighter) != len(best):
            break
        best, limit = tighter, limit - size
    return best


def nice_step(span, most=5):
    """A 1/2/5 step that crosses `span` in at most `most` intervals."""
    mag = 10 ** math.floor(math.log10(max(span, 1) / most))
    for m in (1, 2, 5, 10):
        if span / (m * mag) <= most:
            return int(m * mag) or 1
    return int(10 * mag)


def time_ticks(t0, t1, most=6):
    """Round clock times between t0 and t1 (UTC) as (time, label, date).
    The date is given where a reader needs it: on the first tick and at
    each midnight; ticks a day or more apart are labelled by date alone."""
    hour, day = 3600, 86400
    span = (t1 - t0).total_seconds()
    for step in (hour, 2 * hour, 3 * hour, 6 * hour, 12 * hour, day, 2 * day,
                 7 * day, 14 * day, 30 * day, 91 * day, 365 * day):
        if span / step <= most:
            break
    epoch = datetime.datetime(1970, 1, 1, tzinfo=datetime.timezone.utc)
    k = math.ceil((t0 - epoch).total_seconds() / step) * step
    ticks = []
    while k <= (t1 - epoch).total_seconds():
        t = epoch + datetime.timedelta(seconds=k)
        date = "%s %d" % (t.strftime("%b"), t.day)
        if step >= day:
            ticks.append((t, date, ""))
        else:
            midnight = not (t.hour or t.minute)
            ticks.append((t, t.strftime("%H:%M"), date if midnight or not ticks else ""))
        k += step
    return ticks


def history_points(history, total):
    """(time in UTC, imports implemented) per history row, oldest first."""
    utc = datetime.timezone.utc
    pts = []
    for r in history:
        if not r.get("missing"):
            continue
        t = datetime.datetime.fromisoformat(r["date"])
        t = t.replace(tzinfo=utc) if t.tzinfo is None else t.astimezone(utc)
        pts.append((t, max(total - int(r["missing"]), 0)))
    pts.sort()
    return pts


def draw(out, totals, missing, history, commit, when):
    total = sum(totals.values())
    left = sum(min(missing[a], totals[a]) for a in AREA_NAMES)
    done = total - left
    frac = done / total if total else 0
    layers = roadmap_layers()
    count = {st: sum(1 for l in layers if l[2] == st)
             for st in ("done", "partial", "todo")}
    pts = history_points(history, total)
    x0, x1 = PAD, W - PAD                # the content column

    s = []
    add = s.append

    def text(x, y, body, cls, anchor="start"):
        """One line of text; `cls` is a size from TYPE plus a colour."""
        add('<text x="%.1f" y="%.1f" class="%s"%s>%s</text>'
            % (x, y, cls, "" if anchor == "start" else ' text-anchor="%s"' % anchor,
               body))

    def hline(y, xa=x0, xb=x1, cls="rule"):
        add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" class="%s"/>'
            % (xa, y, xb, y, cls))

    def slab(x, y, w, h, cls, extra=""):
        add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" class="%s"%s/>'
            % (x, y, w, h, min(4, h / 2, w / 2), cls, extra))

    def section(y, title, note=""):
        """Rule, heading and right-hand note; returns where the content starts."""
        hline(y)
        text(x0, y + PAD + 4, esc(title), "head ink")
        if note:
            text(x1, y + PAD + 4, esc(note), "small sec", "end")
        return y + PAD + 4 + 24

    # ---- title
    y = PAD + 12
    text(x0, y, "How close bitten is to running the target Mac app", "head ink")
    text(x1, y, "main @ %s · updated %s" % (esc(commit[:7]), esc(when)),
         "small sec", "end")

    # ---- headline: the one number, and the sentence it stands for
    y += 84
    pct = "%d%%" % round(frac * 100)
    text(x0, y, pct, "hero ink")
    hx = x0 + est_width(pct, T_HERO) + 20
    text(hx, y - 26, "%s of %s imports implemented" % (fmt(done), fmt(total)),
         "title ink")
    more = "%s still to go" % fmt(left)
    if len(pts) >= 2 and pts[-1][1] > pts[0][1]:
        more = "%s of them since %s %d · %s" % (
            fmt(pts[-1][1] - pts[0][1]), pts[0][0].strftime("%b"), pts[0][0].day, more)
    text(hx, y, more, "body sec")

    px0, px1 = x0 + COL_L, x1 - COL_R    # the picture column
    pw = px1 - px0

    def key(y, items, note=""):
        """Swatches and what they mean, above a picture."""
        kx = px0
        for cls, label in items:
            slab(kx + (0.5 if cls == "open" else 0), y - 10.5, 12, 12, cls)
            text(kx + 20, y, esc(label), "small sec")
            kx += 20 + est_width(label, T_SMALL) + 16
        if note:
            text(px1, y, esc(note), "small sec", "end")

    # ---- areas: all the imports as one block, a row per area, the system
    #      at the bottom and the app's own frameworks on top
    rows = [a for a in AREAS if totals[a[0]]]
    if rows:
        y += 48
        key(y, (("fill", "implemented"), ("track", "still to go")),
            "row height = imports in the area")
        y += 16
        # tall enough that the thinnest row still takes a line of text
        ph = min(max(340.0, 16.0 * total / min(totals[a[0]] for a in rows)), 480.0)
        top_y = y
        for name, _, _ in reversed(rows):
            t = totals[name]
            d = t - min(missing[name], t)
            h = ph * t / total
            slab(px0, y, pw, h, "track")
            if d:
                slab(px0, y, max(pw * d / t, 2), h, "fill")
            mid = y + h / 2 + 5
            text(px0 - 12, mid, esc(name), "head ink", "end")
            text(px1 + 56, mid, "%d%%" % round(100.0 * d / t), "head ink num", "end")
            text(x1, mid, "%s of %s" % (fmt(d), fmt(t)), "small sec num", "end")
            y += h + GAP
        y -= GAP
        for k in (0, 25, 50, 75, 100):
            lx = px0 + pw * k / 100
            if 0 < k < 100:
                add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" class="notch"/>'
                    % (lx, top_y, lx, y))
            add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" class="axis"/>'
                % (lx, y + 4, lx, y + 8))
            text(lx, y + 24, "%d%%" % k, "small sec num", "middle")
        y += 28

    # ---- history: imports implemented, stepping up with each merged change
    y = section(y + PAD, "Imports implemented over time",
                "each step is a merged change · times in UTC")
    if len(pts) >= 2:
        gh = 168
        gy = y + 8
        t0, t1 = pts[0][0], pts[-1][0]
        span = max((t1 - t0).total_seconds(), 1)
        lo, hi = min(v for _, v in pts), max(v for _, v in pts)
        step = nice_step(hi - lo, 4)
        base = lo // step * step         # the axis starts here, not at zero
        top = max(hi + 0.08 * (hi - base), base + step)

        def px(t, v):
            return (px0 + pw * (t - t0).total_seconds() / span,
                    gy + gh - gh * (v - base) / (top - base))
        for k in range(base, int(top) + 1, step):
            ly = px(t0, k)[1]
            hline(ly, px0, px1)
            text(px0 - 12, ly + 4, fmt(k), "small sec num", "end")
        dated = False
        for t, label, date in time_ticks(t0, t1):
            lx = px(t, base)[0]
            add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" class="axis"/>'
                % (lx, gy + gh + 4, lx, gy + gh + 8))
            text(lx, gy + gh + 24, label, "small sec num", "middle")
            if date:
                text(lx, gy + gh + 40, date, "small sec", "middle")
                dated = True
        path = []
        for i, (t, v) in enumerate(pts):
            x_, y_ = px(t, v)
            path.append("M%.1f %.1f" % (x_, y_) if not i else "H%.1f V%.1f" % (x_, y_))
        add('<path d="%s" stroke-width="2" stroke-linejoin="round"'
            ' stroke-linecap="round" class="line"/>' % " ".join(path))
        xs, ys = px(*pts[0])
        xe, ye = px(*pts[-1])
        text(xs, ys - 10, fmt(pts[0][1]), "small sec num")
        add('<circle cx="%.1f" cy="%.1f" r="6" stroke-width="2" class="dot"/>' % (xe, ye))
        text(xe + 14, ye + 5, fmt(pts[-1][1]), "head ink num")
        y = gy + gh + (44 if dated else 28)
    else:
        text(x0, y + 12, "Not enough history yet.", "body sec")
        y += 16

    # ---- roadmap: the layers as a stack, built from the bottom up; a layer
    #      is solid once done, tinted while in progress, an outline before
    if layers:
        y = section(y + PAD, "Roadmap",
                    "built from the bottom up: each layer stands on the ones below")
        key(y, (("fill", "%d done" % count["done"]),
                ("track", "%d in progress" % count["partial"]),
                ("open", "%d not started" % count["todo"])))
        y += 16
        slab(px0 + 0.75, y + 0.75, pw - 1.5, 26.5, "goal", ' stroke-width="1.5"')
        text(px0 + 12, y + 19, "The target Mac app", "head ink")
        text(px1 + 12, y + 18, "the goal", "small sec")
        y += 28 + GAP
        look = {"done": ("fill", "body on"), "partial": ("track", "body ink"),
                "todo": ("open", "body sec")}
        for num, name, state in reversed(layers):
            box, ink = look[state]
            lines = wrap(name, T_BODY, pw - 24)
            h = 4 + 20 * len(lines)
            if state == "todo":
                slab(px0 + 0.5, y + 0.5, pw - 1, h - 1, box)
            else:
                slab(px0, y, pw, h, box)
            text(px0 - 12, y + 16, "%d" % num, "small sec num", "end")
            for i, line in enumerate(lines):
                text(px0 + 12, y + 17 + 20 * i, esc(line), ink)
            y += h + GAP
        y -= GAP

    # ---- the caveat
    hline(y + PAD)
    y += PAD + 12
    for line in wrap("Import counts are a floor, not a schedule: one SwiftUI symbol can"
                     " be a day of work, one libSystem symbol a minute.",
                     T_SMALL, x1 - x0):
        y += 16
        text(x0, y, esc(line), "small sec")
    H = int(y + PAD - 4)

    summary = ("%d%% done: bitten implements %s of the %s symbols the target Mac"
               " app imports; %s still to go. %d of %d roadmap layers are done."
               % (round(frac * 100), fmt(done), fmt(total), fmt(left),
                  count["done"], len(layers)))
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d"'
           ' viewBox="0 0 %d %d" role="img" aria-labelledby="t d">\n'
           '<title id="t">How close bitten is to running the target Mac app</title>\n'
           '<desc id="d">%s</desc>\n%s\n'
           '<rect x="0.5" y="0.5" width="%d" height="%d" rx="12" class="card"/>\n'
           '%s\n</svg>\n'
           % (W, H, W, H, esc(summary), STYLE, W - 1, H - 1, "\n".join(s)))
    with open(os.path.join(out, "progress.svg"), "w", encoding="utf-8") as f:
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
