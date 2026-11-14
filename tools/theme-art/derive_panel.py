#!/usr/bin/env python3
"""Build a theme's panel frame from its status bar art, with no API call.

  python3 tools/theme-art/derive_panel.py raji

The top band of the status bar repeats every 32 px. It becomes the top edge of the panel, is rotated
for the left edge, and is mirrored for the right and bottom edges. The end cap of the status bar is the
corner. The status bar itself is not changed. Needs Pillow. Writes src/resources/themes/<theme>/panel.png.
"""
import os, re, sys
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))


def palette(theme):
    cur, out = None, {}
    for line in open(os.path.join(ROOT, "src", "scripts", "theme", "presets.lua")):
        m = re.match(r"^    (\w+) = \{$", line)
        if m: cur = m.group(1); out[cur] = {}; continue
        m = re.match(r"^\s+(\w+) = \{ (\d+), (\d+), (\d+) \},?$", line)
        if m and cur: out[cur][m.group(1)] = tuple(int(m.group(i)) for i in (2, 3, 4))
    return out[theme]


def derive(sb, surface, alt):
    def swap(im, a, b):  # the flat text colour of the bar becomes the flat colour of the panel
        im = im.copy(); px = im.load()
        for y in range(im.height):
            for x in range(im.width):
                if px[x, y] == a: px[x, y] = b
        return im
    corner = swap(sb.crop((0, 0, 16, 16)), alt, surface)
    top = swap(sb.crop((16, 0, 48, 16)), alt, surface)
    tp, cp = top.load(), corner.load()
    for y in range(8, 16):               # under the 8 px band the top edge is the flat panel colour
        for x in range(32): tp[x, y] = surface
        for x in range(8, 16): cp[x, y] = surface
    left = top.transpose(Image.ROTATE_90)  # 16 wide, 32 tall, band on the left
    out = Image.new("RGB", (64, 64), surface)
    out.paste(corner, (0, 0)); out.paste(corner.transpose(Image.FLIP_LEFT_RIGHT), (48, 0))
    out.paste(corner.transpose(Image.FLIP_TOP_BOTTOM), (0, 48)); out.paste(corner.transpose(Image.ROTATE_180), (48, 48))
    out.paste(top, (16, 0)); out.paste(top.transpose(Image.FLIP_TOP_BOTTOM), (16, 48))
    out.paste(left, (0, 16)); out.paste(left.transpose(Image.FLIP_LEFT_RIGHT), (48, 16))
    return out


def main():
    if len(sys.argv) != 2: sys.exit(__doc__)
    theme = sys.argv[1]
    p = palette(theme)
    sb = Image.open(os.path.join(ROOT, "src", "resources", "themes", theme, "statusbar.png")).convert("RGB")
    assert sb.size == (64, 32), sb.size
    out = derive(sb, p["surface"], p["surfaceAlt"])
    path = os.path.join(ROOT, "src", "resources", "themes", theme, "panel.png")
    out.save(path)
    print("wrote", path, out.size)


if __name__ == "__main__":
    main()
