#!/usr/bin/env python3
"""Render the DMG Finder-window background (dmg/background.png and dmg/background@2x.png).

The window is WIDTH x HEIGHT points (see scripts/build-dmg.sh, which positions the app icon and the
Applications link on either side of the arrow drawn here). White, black arrow only.
"""
import os
from PIL import Image, ImageDraw

WIDTH, HEIGHT = 660, 400
ARROW_Y = 180          # vertical centre of the icons (build-dmg.sh uses the same value)
ARROW_LEN, HEAD, STROKE = 72, 18, 3
OUT = os.path.join(os.path.dirname(__file__), "..", "dmg")


def render(scale, supersample=4):
    s = scale * supersample
    img = Image.new("RGB", (WIDTH * s, HEIGHT * s), "white")
    d = ImageDraw.Draw(img)
    cx, cy = WIDTH / 2, ARROW_Y
    x0, x1 = (cx - ARROW_LEN / 2) * s, (cx + ARROW_LEN / 2) * s
    y = cy * s
    w = STROKE * s
    d.line([(x0, y), (x1, y)], fill="black", width=w)
    d.line([(x1 - HEAD * s, y - HEAD * s), (x1, y)], fill="black", width=w)
    d.line([(x1 - HEAD * s, y + HEAD * s), (x1, y)], fill="black", width=w)
    d.ellipse([x1 - w / 2, y - w / 2, x1 + w / 2, y + w / 2], fill="black")
    return img.resize((WIDTH * scale, HEIGHT * scale), Image.LANCZOS)


os.makedirs(OUT, exist_ok=True)
render(1).save(os.path.join(OUT, "background.png"))
render(2).save(os.path.join(OUT, "background@2x.png"))
print(f"wrote dmg/background.png ({WIDTH}x{HEIGHT}) and dmg/background@2x.png")
