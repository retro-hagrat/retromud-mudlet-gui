#!/usr/bin/env python3
"""Generate the pixel-art theme images with Runware (doc/spec/theming.md).

Usage (from the repo root):
  RUNWARE_API_KEY=... python3 tools/theme-art/generate.py [--theme ocean] [--role panel] [--seed 7]
  python3 tools/theme-art/generate.py --dry-run     # print the prompts, no API call
  python3 tools/theme-art/generate.py --selftest    # offline checks of the image cleanup
Optional: RUNWARE_MODEL overrides the model (default runware:100@1, FLUX schnell).
Needs Pillow. Writes src/resources/themes/<theme>/<role>.png and keeps the raw
downloads in tmp/theme-art-raw/ (ignored by git) so a cleanup can be redone.
"""
import argparse, io, json, os, random, re, sys, urllib.request, uuid, warnings
warnings.filterwarnings("ignore", category=DeprecationWarning)  # Pillow getdata, harmless
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "src", "resources", "themes")
RAW = os.path.join(ROOT, "tmp", "theme-art-raw")
COLORS = 16  # palette size after cleanup

STYLE = ("retro pixel art, 8-bit pixel art style, chunky square pixels, classic 1980s video game UI element, flat colors, hard pixel edges, no anti-aliasing, no gradients, "
         "no blur, no text, no letters, no characters, no 3D perspective, limited palette of at most 8 "
         "colors, perfectly symmetrical, centered, plain front view, retro 1980s computer RPG interface style")
NEGATIVE = ("smooth, blurry, anti-aliased, photo, realistic, 3d, perspective, text, letters, watermark, "
            "shadow outside the shape, gradient, noise, jpeg artifacts")

MOTIF = {
    "welstar": "white marble and gold trim, paladin heraldry with shields, swords and laurel wreaths, fluted columns, noble and orderly",
    "crypt": "vampire crypt, black-violet stone and bone white, rich blood crimson red accents and trim, small bats and fangs, stalactite arches, gothic and cold",
    "sosel": "volcano and jungle, black basalt with glowing lava cracks, dinosaur claw and scale patterns, fern leaves, hot and fierce",
    "wysoom": "deep ocean using only cyan, teal and deep blue colors with white sea foam, no pink, no red, no orange, shark fins and rows of shark teeth, polished shells, rolling waves, glowing blue",
    "raji": "sky and djinn, Arabian arches and filigree, drifting clouds and stars, lamp and smoke swirls, gold trim, twilight and magical",
    "perdow": "darkness and carnivorous plants, thorny vines, venus flytrap jaws, pitcher plants with dripping toxic green, crimson flower maws, sinister",
}
# Runware hangs on square sizes above 256 (seen on 2026-11-14), so square roles are generated at 256x256.
# role: (target w, h), (generated w, h: multiples of 64), mirror axes, text colour used on it, prompt
ROLES = {
    "window": ((128, 128), (256, 256), "xy", "text",
        "a seamless tileable texture, 128x128 pixels, subtle repeating pattern of the theme, very low contrast so text stays readable on it"),
    "panel": ((64, 64), (256, 256), "xy", "text",
        "a square picture frame, 64x64 pixels, 16 pixel decorated corners and 16 pixel repeatable straight edges, a plain flat near-black center area with no detail"),
    "statusbar": ((64, 32), (512, 256), "xy", "text",
        "a wide bar, 64x32 pixels, 16 pixel end caps on the left and the right, a plain flat dark center strip, a thin border line on the top and the bottom"),
    "button": ((48, 48), (256, 256), "x", "text",
        "a small square button frame, 48x48 pixels, 12 pixel corners, slightly raised look with a light top edge and a darker bottom edge, plain flat center"),
    "tab": ((48, 48), (256, 256), "x", "textMuted",
        "an inactive tab, 48x32 pixels, 8 pixel corners, muted colors, plain flat center"),
    "tabActive": ((48, 48), (256, 256), "x", "text",
        "an active tab, 48x32 pixels, 8 pixel corners, bright accent color on the top edge, slightly lighter plain flat center"),
}
# Slices (top, right, bottom, left) in art pixels. Must match NINE in src/scripts/theme/logic.lua.
# The window role is a tile at its own size, so it has no slices.
# Role text for one image that needs its own idea. It replaces the role text of ROLES.
ROLE_OVERRIDE = {
    ("raji", "statusbar"): "a wide ornate Arabian brocade ribbon bar, 64x32 pixels, rich repeating gold arabesque "
        "and damask floral pattern in the style of woven brocade silk, deep indigo and violet cloth with gold thread, "
        "the pattern runs along the top band and the bottom band and fills the 16 pixel end caps, "
        "a plain flat dark center strip",
    ("sosel", "button"): "a small square button frame, 48x48 pixels, the TOP QUARTER of the image is a wide row of three big "
        "erupting volcano cones with bright orange and yellow lava fountains shooting up and glowing lava streams "
        "running down the dark slopes, a red-orange glow in the sky, bold and clearly volcanoes, the BOTTOM QUARTER is "
        "lush green jungle ferns and orange jungle plants, plain flat dark center",
    ("wysoom", "window"): "a seamless tileable ornamental pattern, 128x128 pixels, a dense symmetrical repeating motif of "
        "overlapping wave scales, scallop shells, small shark fins and branching coral, like an ornate carved "
        "tile, deep sea blue and teal with cyan highlights only, no pink, no red, no orange, "
        "every shape clearly drawn, the edges match so it repeats without a visible seam",
}
SLICE = {"window": None, "panel": (16, 16, 16, 16), "statusbar": (8, 16, 8, 16),
         "button": (12, 12, 12, 12), "tab": (12, 12, 12, 12), "tabActive": (12, 12, 12, 12)}


def load_palettes():
    """Read the hex colours from the presets, so Lua stays the one source."""
    text = open(os.path.join(ROOT, "src", "scripts", "theme", "presets.lua")).read()
    out, cur = {}, None
    for line in text.splitlines():
        m = re.match(r"^    (\w+) = \{$", line)
        if m: cur = m.group(1); out[cur] = {}; continue
        m = re.match(r"^\s+(\w+) = \{ (\d+), (\d+), (\d+) \},?$", line)
        if m and cur: out[cur][m.group(1)] = tuple(int(m.group(i)) for i in (2, 3, 4))
    return out


def hexc(c): return "#%02X%02X%02X" % c


def prompt(theme, role, pal):
    p = pal[theme]
    colors = (f"Base colors {hexc(p['surface'])} and {hexc(p['surfaceAlt'])}, border {hexc(p['border'])}, "
              f"accent {hexc(p['accent'])}.")
    return f"{STYLE}. THEME {theme}: {colors} {MOTIF[theme]}. ROLE {role}: {ROLE_OVERRIDE.get((theme, role), ROLES[role][4])}."


def lin(c):
    c /= 255
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def lum(c): return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])


def contrast(a, b):
    x, y = sorted((lum(a), lum(b)), reverse=True)
    return (x + 0.05) / (y + 0.05)


# The middle of a frame is where text sits. The model ignores "plain center", so the
# script paints it with a flat colour of the theme. The window tile is blended toward the surface.
# The tabs are built from the button art, so they share its patterned edges (the player liked the
# button bottom best). They are not generated.
DERIVED = ("tab", "tabActive")


def derive_tabs(button, pal):
    """tab = the button; tabActive = the button with the lighter text area and an accent line on top."""
    tab = button.copy()
    active = button.copy(); px = active.load()
    for y in range(12, active.height - 12):
        for x in range(12, active.width - 12): px[x, y] = pal["surface"]
    for y in range(2):
        for x in range(active.width): px[x, y] = pal["accent"]
    return tab, active


FILL = {"panel": "surface", "statusbar": "surfaceAlt", "button": "surfaceAlt", "tab": "surfaceAlt", "tabActive": "surface"}
WINDOW_BLEND = 0.55  # share of the surface colour mixed into the window tile


def cleanup(img, role, pal):
    """Shrink to the exact pixel size, cut the palette, mirror so the corners match,
    then make the text area plain."""
    (w, h), _, axes, _, _ = ROLES[role]
    img = img.convert("RGB")
    # window is built from one quadrant and mirrored, so it tiles without a seam
    qw, qh = (w // 2, h // 2) if role == "window" else (w, h)
    img = img.resize((qw, qh), Image.BOX).quantize(colors=COLORS, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    if "x" in axes:
        half = img.crop((0, 0, (qw + 1) // 2, qh)); img.paste(half.transpose(Image.FLIP_LEFT_RIGHT), (qw - half.width, 0))
        img.paste(half, (0, 0))
    if "y" in axes:
        half = img.crop((0, 0, qw, (qh + 1) // 2)); img.paste(half.transpose(Image.FLIP_TOP_BOTTOM), (0, qh - half.height))
        img.paste(half, (0, 0))
    if role == "window":
        full = Image.new("RGB", (w, h))
        full.paste(img, (0, 0)); full.paste(img.transpose(Image.FLIP_LEFT_RIGHT), (qw, 0))
        full.paste(img.transpose(Image.FLIP_TOP_BOTTOM), (0, qh)); full.paste(img.transpose(Image.ROTATE_180), (qw, qh))
        img = full
    if role == "window":
        sf = pal["surface"]
        img = Image.eval(img, lambda v: v)  # copy
        px = img.load()
        for y in range(img.height):
            for x in range(img.width):
                px[x, y] = tuple(int(px[x, y][i] * (1 - WINDOW_BLEND) + sf[i] * WINDOW_BLEND) for i in range(3))
    else:
        t, r, b, l = SLICE[role]
        px = img.load()
        for y in range(t, img.height - b):
            for x in range(l, img.width - r): px[x, y] = pal[FILL[role]]
        if role == "tabActive":  # bright accent line on the top edge
            for y in range(2):
                for x in range(img.width): px[x, y] = pal["accent"]
    return img


def worst_contrast(img, role, theme_pal):
    """Lowest contrast between the text colour and the pixels where text can sit."""
    s = SLICE[role]
    if s is None: return 99.0  # the window tile never carries text, panels sit on it
    w, h = img.size
    box = (s[3], s[0], w - s[1], h - s[2])
    text = theme_pal[ROLES[role][3]]
    return min(contrast(text, img.getpixel((x, y))) for x in range(box[0], box[2]) for y in range(box[1], box[3]))


def call_runware(tasks, key, tries=3):
    """One request per theme. Runware is sometimes slow or answers without an image URL, so retry."""
    last = None
    for attempt in range(1, tries + 1):
        try:
            req = urllib.request.Request("https://api.runware.ai/v1", json.dumps(tasks).encode(), method="POST",
                headers={"Authorization": "Bearer " + key, "Content-Type": "application/json", "User-Agent": "retromud-gui-art/1"})
            with urllib.request.urlopen(req, timeout=100) as r: body = json.load(r)
            if body.get("errors"): sys.exit("Runware returned errors: " + json.dumps(body["errors"])[:500])
            urls = {d["taskUUID"]: d["imageURL"] for d in body.get("data", []) if d.get("imageURL")}
            if all(t["taskUUID"] in urls for t in tasks): return urls
            last = "answer without an image URL for some tasks"
        except (TimeoutError, urllib.error.URLError, OSError) as e:
            last = repr(e)
        print(f"  runware attempt {attempt}/{tries} failed: {last}", file=sys.stderr)
        for t in tasks: t["taskUUID"] = str(uuid.uuid4())  # a fresh id for the retry
    sys.exit("Runware failed after %d tries: %s" % (tries, last))


def download(url):
    req = urllib.request.Request(url, headers={"User-Agent": "retromud-gui-art/1"})
    with urllib.request.urlopen(req, timeout=120) as r: return r.read()


def selftest():
    rnd = random.Random(1)
    for role, ((w, h), (gw, gh), axes, _, _) in ROLES.items():
        src = Image.new("RGB", (gw, gh))
        src.putdata([(rnd.randrange(256), rnd.randrange(256), rnd.randrange(256)) for _ in range(gw * gh)])
        out = cleanup(src, role, load_palettes()["perdow"])
        assert out.size == (w, h), (role, out.size)
        if role != "window": assert len(set(out.getdata())) <= COLORS + 2, (role, "too many colours")
        if role == "tabActive":  # the top rows are the accent line, so skip them for the x check only
            assert out.getpixel((w // 2, 0)) == load_palettes()["perdow"]["accent"], "accent line"
        if "x" in axes: assert all(out.getpixel((x, y)) == out.getpixel((w - 1 - x, y)) for x in range(w) for y in range(h)), (role, "x symmetry")
        if "y" in axes: assert all(out.getpixel((x, y)) == out.getpixel((x, h - 1 - y)) for x in range(w) for y in range(h)), (role, "y symmetry")
        if role != "window":  # the text area is one flat colour (THEME-020 by construction)
            t, r, b, l = SLICE[role]; fill = load_palettes()["perdow"][FILL[role]]
            assert all(out.getpixel((x, y)) == fill for x in range(l, w - r) for y in range(max(t, 2), h - b)), (role, "plain centre")
        if role == "window":  # edges match, so it tiles
            assert all(out.getpixel((0, y)) == out.getpixel((w - 1, y)) for y in range(h)), "tile seam x"
            assert all(out.getpixel((x, 0)) == out.getpixel((x, h - 1)) for x in range(w)), "tile seam y"
    pal0 = load_palettes()["perdow"]
    btn = cleanup(src, "button", pal0)
    tab, act = derive_tabs(btn, pal0)
    assert tab.size == (48, 48) and act.size == (48, 48) and list(tab.getdata()) == list(btn.getdata()), "tab is the button"
    assert all(act.getpixel((x, 0)) == pal0["accent"] and act.getpixel((x, 1)) == pal0["accent"] for x in range(48)), "accent line"
    assert all(act.getpixel((x, y)) == pal0["surface"] for x in range(12, 36) for y in range(12, 36)), "active text area"
    assert act.getpixel((24, 47)) == btn.getpixel((24, 47)), "the patterned bottom is kept"
    assert abs(contrast((0, 0, 0), (255, 255, 255)) - 21) < 1e-6
    pal = load_palettes()
    assert set(pal) == set(MOTIF) and all("textMuted" in p for p in pal.values()), "palette parse"
    assert all("#" in prompt(t, r, pal) for t in pal for r in ROLES)
    print("selftest ok")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--theme"); ap.add_argument("--role"); ap.add_argument("--seed", type=int)
    ap.add_argument("--dry-run", action="store_true"); ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--from-raw", action="store_true", help="redo the cleanup from tmp/theme-art-raw, no API call")
    ap.add_argument("--derive-tabs", action="store_true", help="build tab.png and tabActive.png from button.png (no API call)")
    ap.add_argument("--motif", help="replace the motif of the theme for this run")
    ap.add_argument("--out", help="write the cleaned images into this folder (as <theme>-<role>.png) instead of src/resources, and keep the raw files out of tmp/theme-art-raw")
    a = ap.parse_args()
    if a.selftest: return selftest()
    pal = load_palettes()
    if a.motif and a.theme: MOTIF[a.theme] = a.motif
    themes = [a.theme] if a.theme else list(MOTIF)
    roles = [a.role] if a.role else [r for r in ROLES if r not in DERIVED]
    for t in themes:
        if t not in pal: sys.exit("unknown theme " + t)
    for r in roles:
        if r not in ROLES: sys.exit("unknown role " + r)
        if r in DERIVED: sys.exit(f"{r} is built from the button: run with --derive-tabs")

    def write_derived(t):
        btn = Image.open(os.path.join(OUT, t, "button.png")).convert("RGB")
        for name, img in zip(DERIVED, derive_tabs(btn, pal[t])):
            img.save(os.path.join(OUT, t, name + ".png"))
            print(f"{t}/{name}: derived from the button, worst text contrast {worst_contrast(img, name, pal[t]):.1f}")
    if a.derive_tabs:
        for t in themes: write_derived(t)
        return
    if a.dry_run:
        for t in themes:
            for r in roles: print(f"[{t}/{r}] {ROLES[r][1]}\n  {prompt(t, r, pal)}\n")
        return
    if a.from_raw:
        for t in themes:
            os.makedirs(os.path.join(OUT, t), exist_ok=True)
            for r in roles:
                img = cleanup(Image.open(os.path.join(RAW, f"{t}-{r}.png")), r, pal[t])
                img.save(os.path.join(OUT, t, r + ".png"))
                c = worst_contrast(img, r, pal[t])
                print(f"{t}/{r}: wrote {img.size[0]}x{img.size[1]}, worst text contrast {c:.1f}" + ("  WARN below 4.5" if c < 4.5 else ""))
            if "button" in roles: write_derived(t)
        return
    key = os.environ.get("RUNWARE_API_KEY") or sys.exit("RUNWARE_API_KEY must be set")
    model = os.environ.get("RUNWARE_MODEL", "runware:100@1")
    os.makedirs(RAW, exist_ok=True)
    for t in themes:
        tasks = [{"taskType": "imageInference", "taskUUID": str(uuid.uuid4()), "positivePrompt": prompt(t, r, pal),
                  "negativePrompt": NEGATIVE, "model": model, "width": ROLES[r][1][0], "height": ROLES[r][1][1],
                  "numberResults": 1, "outputFormat": "PNG", **({"seed": a.seed} if a.seed is not None else {})} for r in roles]
        urls = call_runware(tasks, key)
        os.makedirs(os.path.join(OUT, t), exist_ok=True)
        for r, task in zip(roles, tasks):
            data = download(urls[task["taskUUID"]])
            img = cleanup(Image.open(io.BytesIO(data)), r, pal[t])
            if a.out:
                os.makedirs(a.out, exist_ok=True)
                open(os.path.join(a.out, f"{t}-{r}-raw.png"), "wb").write(data)
                img.save(os.path.join(a.out, f"{t}-{r}.png"))
            else:
                open(os.path.join(RAW, f"{t}-{r}.png"), "wb").write(data)
                img.save(os.path.join(OUT, t, r + ".png"))
            c = worst_contrast(img, r, pal[t])
            print(f"{t}/{r}: wrote {img.size[0]}x{img.size[1]}, worst text contrast {c:.1f}" + ("  WARN below 4.5" if c < 4.5 else ""))
        if "button" in roles and not a.out: write_derived(t)


if __name__ == "__main__":
    main()
