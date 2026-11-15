#!/usr/bin/env python3
"""Draw the wysoom panel picture in code: frothy ocean waves on the top and bottom, black sides with small clouds.

Usage (from the repo root):  python3 tools/theme-art/wave_panel.py [--out file.png]
Writes src/resources/themes/wysoom/panel.png (64x64, 16 px nine-slice frame, flat centre). No API call:
the image model could not draw waves that read as waves at this size.
"""
import argparse, math, os, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from generate import OUT, load_palettes, worst_contrast  # noqa: E402

# Quiet colours on black: a bright sky and white foam were too loud next to the text.
SKY = (0, 0, 0)
FOAM, FOAM_SHADE = (214, 232, 244), (112, 158, 192)
WATER = [(38, 104, 150), (24, 76, 124), (14, 52, 96), (9, 36, 72)]  # light to deep
CLOUD, CLOUD_SHADE = (150, 184, 210), (70, 104, 138)
PERIOD, BAND = 32, 16


SEG = 16           # two waves in every 32 px: a big one and a smaller one
PEAK = 0.7         # where the crest sits in a wave, 0 to 1: a slow back, a steep front
AMP = (5.5, 4.0)


def crest(x):
    """Height of the water line in the 16 px band, periodic in 32 px. Each wave rises slowly and drops steeply."""
    seg, u = (x % PERIOD) // SEG, (x % SEG) / SEG
    h = (u / PEAK) ** 1.4 if u < PEAK else 1 - ((u - PEAK) / (1 - PEAK)) ** 0.7
    return 9.5 - AMP[seg] * h


def wave_band():
    img = Image.new("RGB", (PERIOD, BAND)); px = img.load()
    for x in range(PERIOD):
        c = crest(x)
        for y in range(BAND):
            d = y - c
            if d < 0: px[x, y] = SKY
            elif d < 1: px[x, y] = FOAM
            elif d < 2: px[x, y] = FOAM_SHADE
            else: px[x, y] = WATER[min(int((d - 2) / 2.2), len(WATER) - 1)]
    for seg in range(2):  # the lip of each crest curls over the steep front, with spray above it
        p = seg * SEG + int(round(PEAK * SEG))
        c = int(round(crest(p)))
        for dx, dy in [(-3, 1), (-2, 0), (-1, -1), (0, -1), (1, -1), (2, -1), (3, 0), (3, 1), (2, 1)]:
            px[(p + dx) % PERIOD, c + dy] = FOAM
        px[(p + 1) % PERIOD, c] = FOAM_SHADE; px[(p + 2) % PERIOD, c] = FOAM_SHADE
        for dx, dy in [(-1, -3), (1, -3), (4, -2), (-3, -2), (5, 0)]:
            px[(p + dx) % PERIOD, c + dy] = FOAM
    for x in range(PERIOD):  # froth: foam flecks just under the crest line
        c = int(math.ceil(crest(x)))
        if (x * 7 + 3) % 5 in (0, 1): px[x, min(c + 2, BAND - 1)] = FOAM_SHADE
        if (x * 11 + 1) % 6 == 0: px[x, min(c + 3, BAND - 1)] = FOAM
    return img


def cloud_tile():
    """16 wide, 32 tall, tiles vertically; two small puffy clouds."""
    img = Image.new("RGB", (BAND, PERIOD), SKY); px = img.load()
    for cx, cy in [(6, 9), (9, 25)]:
        puffs = [(cx - 2, cy + 1, 1.8), (cx, cy, 2.4), (cx + 2, cy + 1, 2.0), (cx + 1, cy - 2, 1.8)]
        for shade, off in ((CLOUD_SHADE, 1), (CLOUD, 0)):
            for y in range(PERIOD):
                for x in range(BAND):
                    if any((x - px_) ** 2 + (y - off - py_) ** 2 <= r * r for px_, py_, r in puffs): px[x, y] = shade
    return img


def build(pal):
    img = Image.new("RGB", (64, 64), pal["surface"])
    band, clouds = wave_band(), cloud_tile()
    for y in range(BAND):
        for x in range(64):
            v = band.getpixel((x % PERIOD, y))
            img.putpixel((x, y), v); img.putpixel((x, 48 + y), v)
    for y in range(BAND, 64 - BAND):
        for x in range(BAND):
            img.putpixel((x, y), clouds.getpixel((x, (y - BAND) % PERIOD)))
            img.putpixel((63 - x, y), clouds.getpixel((x, (y - BAND) % PERIOD)))
    return img


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--out", help="write here instead of the theme folder")
    a = ap.parse_args()
    pal = load_palettes()["wysoom"]
    img = build(pal)
    path = a.out or os.path.join(OUT, "wysoom", "panel.png")
    img.save(path)
    print(f"wrote {path}, worst text contrast {worst_contrast(img, 'panel', pal):.1f}")


if __name__ == "__main__":
    main()
