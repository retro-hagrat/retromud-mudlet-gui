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
COLORS = 12  # palette size after cleanup

STYLE = ("8-bit pixel art game UI element, flat colors, hard pixel edges, no anti-aliasing, no gradients, "
         "no blur, no text, no letters, no characters, no 3D perspective, limited palette of at most 8 "
         "colors, perfectly symmetrical, centered, plain front view, retro 1980s computer RPG interface style")
NEGATIVE = ("smooth, blurry, anti-aliased, photo, realistic, 3d, perspective, text, letters, watermark, "
            "shadow outside the shape, gradient, noise, jpeg artifacts")

MOTIF = {
    "dark": "dungeon slate, small indigo rune studs in the corners, calm, cool, low contrast",
    "light": "warm parchment paper, ink border, small corner flourishes, clean and bright",
    "flame": "charred black stone, glowing ember cracks and corner rivets, warm and fiery",
    "ocean": "deep sea, small aquamarine coral and wave details in the corners, cool and calm",
    "forest": "mossy dark wood and leaves, small leaf details in the corners",
}
# role: (target w, h), (generated w, h: multiples of 64), mirror axes, text colour used on it, prompt
ROLES = {
    "window": ((64, 64), (512, 512), "xy", "text",
        "a seamless tileable texture, 64x64 pixels, subtle repeating pattern of the theme, very low contrast so text stays readable on it"),
    "panel": ((32, 32), (512, 512), "xy", "text",
        "a square frame, 32x32 pixels, 8 pixel decorated corners and 8 pixel repeatable straight edges, a plain flat dark center area with no detail"),
    "statusbar": ((32, 16), (512, 256), "xy", "text",
        "a wide bar, 32x16 pixels, 8 pixel end caps on the left and the right, a plain flat center strip, a thin border line on the top and the bottom"),
    "button": ((24, 24), (512, 512), "x", "text",
        "a small square button frame, 24x24 pixels, 6 pixel corners, slightly raised look with a light top edge and a darker bottom edge, plain flat center"),
    "tab": ((24, 16), (384, 256), "x", "textMuted",
        "an inactive tab, 24x16 pixels, 4 pixel corners, muted colors, plain flat center"),
    "tabActive": ((24, 16), (384, 256), "x", "text",
        "an active tab, 24x16 pixels, 4 pixel corners, bright accent color on the top edge, slightly lighter plain flat center"),
}
SLICE = {"window": None, "panel": 8, "statusbar": 4, "button": 6, "tab": 4, "tabActive": 4}


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
    return f"{STYLE}. THEME {theme}: {colors} {MOTIF[theme]}. ROLE {role}: {ROLES[role][4]}."


def lin(c):
    c /= 255
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def lum(c): return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])


def contrast(a, b):
    x, y = sorted((lum(a), lum(b)), reverse=True)
    return (x + 0.05) / (y + 0.05)


def cleanup(img, role):
    """Shrink to the exact pixel size, cut the palette, mirror so the corners match."""
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
    return img


def worst_contrast(img, role, theme_pal):
    """Lowest contrast between the text colour and the pixels where text can sit."""
    s = SLICE[role]
    w, h = img.size
    box = (0, 0, w, h) if s is None else (s, min(s, h // 4), w - s, h - min(s, h // 4))
    text = theme_pal[ROLES[role][3]]
    return min(contrast(text, img.getpixel((x, y))) for x in range(box[0], box[2]) for y in range(box[1], box[3]))


def call_runware(tasks, key):
    req = urllib.request.Request("https://api.runware.ai/v1", json.dumps(tasks).encode(), method="POST",
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json", "User-Agent": "retromud-gui-art/1"})
    with urllib.request.urlopen(req, timeout=180) as r: body = json.load(r)
    if body.get("errors"): sys.exit("Runware returned errors: " + json.dumps(body["errors"])[:500])
    return {d["taskUUID"]: d["imageURL"] for d in body["data"]}


def download(url):
    req = urllib.request.Request(url, headers={"User-Agent": "retromud-gui-art/1"})
    with urllib.request.urlopen(req, timeout=120) as r: return r.read()


def selftest():
    rnd = random.Random(1)
    for role, ((w, h), (gw, gh), axes, _, _) in ROLES.items():
        src = Image.new("RGB", (gw, gh))
        src.putdata([(rnd.randrange(256), rnd.randrange(256), rnd.randrange(256)) for _ in range(gw * gh)])
        out = cleanup(src, role)
        assert out.size == (w, h), (role, out.size)
        assert len(set(out.getdata())) <= COLORS, (role, "too many colours")
        if "x" in axes: assert all(out.getpixel((x, y)) == out.getpixel((w - 1 - x, y)) for x in range(w) for y in range(h)), (role, "x symmetry")
        if "y" in axes: assert all(out.getpixel((x, y)) == out.getpixel((x, h - 1 - y)) for x in range(w) for y in range(h)), (role, "y symmetry")
        if role == "window":  # edges match, so it tiles
            assert all(out.getpixel((0, y)) == out.getpixel((w - 1, y)) for y in range(h)), "tile seam x"
            assert all(out.getpixel((x, 0)) == out.getpixel((x, h - 1)) for x in range(w)), "tile seam y"
    assert abs(contrast((0, 0, 0), (255, 255, 255)) - 21) < 1e-6
    pal = load_palettes()
    assert set(pal) == set(MOTIF) and all("textMuted" in p for p in pal.values()), "palette parse"
    assert all("#" in prompt(t, r, pal) for t in pal for r in ROLES)
    print("selftest ok")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--theme"); ap.add_argument("--role"); ap.add_argument("--seed", type=int)
    ap.add_argument("--dry-run", action="store_true"); ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest: return selftest()
    pal = load_palettes()
    themes = [a.theme] if a.theme else list(MOTIF)
    roles = [a.role] if a.role else list(ROLES)
    for t in themes:
        if t not in pal: sys.exit("unknown theme " + t)
    for r in roles:
        if r not in ROLES: sys.exit("unknown role " + r)
    if a.dry_run:
        for t in themes:
            for r in roles: print(f"[{t}/{r}] {ROLES[r][1]}\n  {prompt(t, r, pal)}\n")
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
            open(os.path.join(RAW, f"{t}-{r}.png"), "wb").write(data)
            img = cleanup(Image.open(io.BytesIO(data)), r)
            img.save(os.path.join(OUT, t, r + ".png"))
            c = worst_contrast(img, r, pal[t])
            print(f"{t}/{r}: wrote {img.size[0]}x{img.size[1]}, worst text contrast {c:.1f}" + ("  WARN below 4.5" if c < 4.5 else ""))


if __name__ == "__main__":
    main()
