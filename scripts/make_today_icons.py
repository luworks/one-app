"""Render the "Today" icon concepts into a directory (default: cwd) as 1024px PNGs.

Usage: python3 scripts/make_today_icons.py [OUT_DIR] [CONCEPT ...]
Concepts: dots, sunrise, nowbar. Needs Pillow only.
"""
import os
import sys
from PIL import Image, ImageDraw

S, SS = 1024, 4            # final size, supersampling factor
TOP, BOTTOM = (44, 44, 46), (22, 22, 24)
INK = (245, 245, 242)
DIM = (92, 92, 96)
ACCENT = (232, 116, 59)


def base():
    im = Image.new("RGB", (S * SS, S * SS))
    d = ImageDraw.Draw(im)
    for y in range(S * SS):
        t = y / (S * SS - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM))
        d.line([(0, y), (S * SS, y)], fill=c)
    return im, d


def u(v):
    return round(v * SS)


def dots():
    """5x5 grid converging on one orange dot: dots grow and brighten toward today."""
    im, d = base()
    cols, rows, step = 5, 5, 150
    x0 = (S - step * (cols - 1)) / 2
    y0 = (S - step * (rows - 1)) / 2
    for i in range(rows):
        for j in range(cols):
            cx, cy = x0 + j * step, y0 + i * step
            ring = max(abs(i - 2), abs(j - 2))      # 0 centre, 1 inner ring, 2 outer ring
            if ring == 0:
                rr, col = 88, ACCENT
            else:
                rr = {1: 52, 2: 28}[ring]
                t = {1: 0.8, 2: 0.15}[ring]
                col = tuple(round(a + (b - a) * t) for a, b in zip(DIM, INK))
            d.ellipse((u(cx - rr), u(cy - rr), u(cx + rr), u(cy + rr)), fill=col)
    return im


def sunrise():
    """Orange sun on an off-white horizon: a new day starting."""
    im, d = base()
    r, cx, hy = 250, 512, 600
    d.pieslice((u(cx - r), u(hy - r), u(cx + r), u(hy + r)), 180, 360, fill=ACCENT)
    d.rounded_rectangle((u(170), u(hy + 40), u(854), u(hy + 40 + 56)), u(28), fill=INK)
    d.rounded_rectangle((u(300), u(hy + 40 + 56 + 44), u(724), u(hy + 40 + 56 + 44 + 56)), u(28), fill=DIM)
    return im


def nowbar():
    """The day as a bar with an orange 'now' marker across it."""
    im, d = base()
    w, h = 250, 640
    x0, y0 = (S - w) / 2, (S - h) / 2
    d.rounded_rectangle((u(x0), u(y0), u(x0 + w), u(y0 + h)), u(w / 2), fill=INK)
    my = y0 + h * 0.58
    d.rounded_rectangle((u(x0 - 70), u(my - 30), u(x0 + w + 70), u(my + 30)), u(30), fill=ACCENT)
    return im


CONCEPTS = {"dots": dots, "sunrise": sunrise, "nowbar": nowbar}

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    names = sys.argv[2:] or list(CONCEPTS)
    os.makedirs(out, exist_ok=True)
    for n in names:
        CONCEPTS[n]().resize((S, S), Image.LANCZOS).save(os.path.join(out, f"today-{n}.png"), optimize=True)
