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
#
# One progress ring: the share of the target app's imports implemented.
# The history stays in history.csv; it is not drawn.

STYLE = """<style>
  text { font-family: system-ui, -apple-system, "Segoe UI", Helvetica, Arial, sans-serif; }
  .bg { fill: #ffffff; } .ink { fill: #1f2328; } .mute { fill: #656d76; }
  .track { stroke: #eaeef2; } .done { stroke: #2da44e; }
  @media (prefers-color-scheme: dark) {
    .bg { fill: #0d1117; } .ink { fill: #e6edf3; } .mute { fill: #8d96a0; }
    .track { stroke: #21262d; } .done { stroke: #3fb950; }
  }
</style>"""


def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;"))


def fmt(n):
    return "{:,}".format(int(n))


def draw(out, totals, missing, history, commit, when):
    import math
    W, H = 480, 240
    total = sum(totals.values())
    left = sum(min(missing[a], totals[a]) for a in AREA_NAMES)
    done = total - left
    frac = done / total if total else 0
    cx, cy, r = 120, 120, 80
    circ = 2 * math.pi * r
    arc = ""
    if done:
        arc = ('<circle cx="%d" cy="%d" r="%d" fill="none" class="done" stroke-width="22"'
               ' stroke-linecap="round" stroke-dasharray="%.1f %.1f"'
               ' transform="rotate(-90 %d %d)"/>' % (cx, cy, r, circ * frac, circ, cx, cy))
    body = [
        '<rect width="%d" height="%d" rx="12" class="bg"/>' % (W, H),
        '<circle cx="%d" cy="%d" r="%d" fill="none" class="track" stroke-width="22"/>' % (cx, cy, r),
        arc,
        '<text x="%d" y="%d" text-anchor="middle" class="ink" font-size="38"'
        ' font-weight="700">%d%%</text>' % (cx, cy + 13, round(frac * 100)),
        '<text x="250" y="105" class="ink" font-size="20" font-weight="600">Mac app support</text>',
        '<text x="250" y="135" class="mute" font-size="15">%s of %s functions</text>'
        % (fmt(done), fmt(total)),
        '<text x="250" y="158" class="mute" font-size="15">implemented</text>',
        '<text x="250" y="190" class="mute" font-size="12">updated %s</text>' % esc(when[:10]),
    ]
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">\n'
           '%s\n%s\n</svg>\n' % (W, H, W, H, STYLE, "\n".join(x for x in body if x)))
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
