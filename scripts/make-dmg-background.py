#!/usr/bin/env python3
"""Render the DMG Finder-window background (dmg/background.png and dmg/background@2x.png).

The window is WIDTH x HEIGHT points (see scripts/build-dmg.sh, which positions the app icon and the
Applications link on either side of the arrow drawn here). Dark ASCII field (same look as the share card
and launch video) with a white arrow; a darker pocket behind the icons keeps them legible.
"""
import math
import os
import random
from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 660, 400
ARROW_Y = 180          # vertical centre of the icons (build-dmg.sh uses the same value)
ARROW_LEN, HEAD, STROKE = 72, 18, 3
BG = (13, 13, 13)
CW, CH = 9, 14         # glyph cell (points)
RAMP = ". . . : : - = + * # % @ 8 0 B M".split()
OUT = os.path.join(os.path.dirname(__file__), "..", "dmg")
FONT = "/System/Library/Fonts/Menlo.ttc"
LABEL_FONT = "/System/Library/Fonts/SFNS.ttf"


def value_noise(cols, rows, seed, cell=6):
    """Smooth 0..1 noise: random lattice, bicubic-upsampled."""
    rnd = random.Random(seed)
    gw, gh = cols // cell + 2, rows // cell + 2
    lat = Image.new("F", (gw, gh))
    lat.putdata([rnd.random() for _ in range(gw * gh)])
    return lat.resize((cols, rows), Image.BICUBIC)


def render(scale):
    img = Image.new("RGB", (WIDTH * scale, HEIGHT * scale), BG)
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, int(10 * scale), index=1)  # Menlo Bold
    cols, rows = WIDTH // CW + 1, HEIGHT // CH + 1
    n1, n2 = value_noise(cols, rows, 7), value_noise(cols, rows, 11, cell=3)
    jitter = random.Random(3)
    for r in range(rows):
        for c in range(cols):
            n = 0.65 * n1.getpixel((c, r)) + 0.35 * n2.getpixel((c, r))
            n = max(0.0, min(1.0, (n - 0.5) * 1.6 + 0.5))
            dens = n * 0.5 if n < 0.5 else 0.25 + (n - 0.5) * 1.5
            if jitter.random() > min(1.0, dens) * 0.9 + 0.05:
                continue
            ch = RAMP[min(len(RAMP) - 1, int(n * len(RAMP)))]
            x, y = c * CW, r * CH
            # darker pocket around the icon row so the app icon / folder read clearly
            dx, dy = (x - WIDTH / 2) / (WIDTH / 2), (y - ARROW_Y) / 150
            pocket = max(0.0, 1 - math.sqrt(dx * dx + dy * dy))
            a = (0.18 + 0.55 * n) * (1 - 0.75 * pocket)
            v = int(13 + a * 215)
            d.text((x * scale, y * scale), ch, font=font, fill=(v, v, v))
    cx, cy = WIDTH / 2, ARROW_Y
    x0, x1 = (cx - ARROW_LEN / 2) * scale, (cx + ARROW_LEN / 2) * scale
    y, w = cy * scale, STROKE * scale
    for pts in ([(x0, y), (x1, y)], [(x1 - HEAD * scale, y - HEAD * scale), (x1, y)], [(x1 - HEAD * scale, y + HEAD * scale), (x1, y)]):
        d.line(pts, fill="white", width=w)
    d.ellipse([x1 - w / 2, y - w / 2, x1 + w / 2, y + w / 2], fill="white")
    # Finder draws icon labels in black regardless of the background, which is unreadable here; paint white
    # labels at the same spots (positions mirror APP_X / APPS_X / ICON in scripts/build-dmg.sh).
    label = ImageFont.truetype(LABEL_FONT, int(12 * scale))
    for text, lx in (("New Media Writer", 165), ("Applications", 495)):
        tw = d.textlength(text, font=label)
        d.text((lx * scale - tw / 2, (ARROW_Y + 64 + 7) * scale), text, font=label, fill="white")
    return img


os.makedirs(OUT, exist_ok=True)
render(1).save(os.path.join(OUT, "background.png"))
render(2).save(os.path.join(OUT, "background@2x.png"))
print(f"wrote dmg/background.png ({WIDTH}x{HEIGHT}) and dmg/background@2x.png")
