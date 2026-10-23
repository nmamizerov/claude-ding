#!/usr/bin/env python3
"""Renders assets/demo.gif: Claude works, finishes, and the speaker dings.

    python3 tools/make_demo_gif.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

W, H, S = 720, 320, 2           # draw at 2x, downscale for smooth edges
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"

BG = (18, 18, 22)
WIN = (30, 30, 36)
BAR = (42, 42, 50)
TXT = (220, 220, 228)
DIM = (120, 120, 132)
ORANGE = (217, 119, 87)          # Claude-ish accent
GREEN = (110, 200, 130)
GOLD = (245, 196, 80)

f = ImageFont.truetype(MONO, 17 * S)
fb = ImageFont.truetype(BOLD, 17 * S)
fbig = ImageFont.truetype(BOLD, 26 * S)

SPIN = "·✢✳✶✻✽"


def frame(t):
    """t in seconds; timeline: 0-1.6 working, 1.6 done, 1.7-3.2 ding, hold."""
    im = Image.new("RGB", (W * S, H * S), BG)
    d = ImageDraw.Draw(im)
    x0, y0, x1, y1 = 24 * S, 20 * S, (W - 24) * S, (H - 20) * S
    d.rounded_rectangle((x0, y0, x1, y1), 14 * S, fill=WIN)
    d.rounded_rectangle((x0, y0, x1, y0 + 34 * S), 14 * S, fill=BAR)
    d.rectangle((x0, y0 + 20 * S, x1, y0 + 34 * S), fill=BAR)
    for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        cx, cy = x0 + (22 + i * 20) * S, y0 + 17 * S
        d.ellipse((cx - 6 * S, cy - 6 * S, cx + 6 * S, cy + 6 * S), fill=c)
    d.text(((W // 2 - 50) * S, y0 + 8 * S), "claude", font=f, fill=DIM)

    lx, ly, lh = x0 + 26 * S, y0 + 60 * S, 32 * S
    d.text((lx, ly), ">", font=fb, fill=ORANGE)
    d.text((lx + 22 * S, ly), "refactor the auth module", font=f, fill=TXT)

    if t < 1.6:
        sp = SPIN[int(t * 10) % len(SPIN)]
        dots = "." * (1 + int(t * 3) % 3)
        d.text((lx, ly + lh * 1.5), sp, font=fb, fill=ORANGE)
        d.text((lx + 22 * S, ly + lh * 1.5), f"Working{dots}", font=f, fill=ORANGE)
        d.text((lx + 22 * S, ly + lh * 2.5), f"{int(t * 9)}s · esc to interrupt", font=f, fill=DIM)
    else:
        d.text((lx, ly + lh * 1.5), "●", font=fb, fill=GREEN)
        d.text((lx + 22 * S, ly + lh * 1.5), "Done. Updated 4 files.", font=f, fill=TXT)
        d.text((lx, ly + lh * 2.5), ">", font=fb, fill=ORANGE)
        if int(t * 2) % 2 == 0:
            d.rectangle((lx + 22 * S, ly + lh * 2.5 + 2 * S, lx + 32 * S, ly + lh * 2.5 + 20 * S), fill=TXT)

    # speaker + waves
    if t >= 1.6:
        k = t - 1.6
        pop = 1 + 0.18 * math.exp(-k * 6) * math.sin(k * 30)
        cx, cy = (W - 130) * S, (H // 2 + 10) * S
        u = 1.0 * S * pop
        d.rectangle((cx - 34 * u, cy - 12 * u, cx - 18 * u, cy + 12 * u), fill=GOLD)
        d.polygon([(cx - 18 * u, cy - 12 * u), (cx + 2 * u, cy - 30 * u),
                   (cx + 2 * u, cy + 30 * u), (cx - 18 * u, cy + 12 * u)], fill=GOLD)
        for i in range(3):
            ph = (k * 1.4 - i * 0.22)
            if ph <= 0:
                continue
            ph = ph % 1.0
            r = (22 + ph * 60) * S
            a = max(0.0, 1 - ph)
            col = tuple(int(BG[j] * (1 - a) + GOLD[j] * a) for j in range(3))
            d.arc((cx + 2 * S - r, cy - r, cx + 2 * S + r, cy + r), -45, 45, fill=col, width=int(5 * S))
        if k < 2.6:
            d.text((cx - 40 * S, cy + 46 * S), "ding!", font=fbig, fill=GOLD)
    return im.resize((W, H), Image.LANCZOS)


def main():
    fps, total = 20, 4.6
    frames = [frame(i / fps) for i in range(int(total * fps))]
    sheet = Image.new("RGB", (W, H * 4))
    for i, n in enumerate((5, 40, 50, 60)):
        sheet.paste(frames[n], (0, H * i))
    pal = sheet.quantize(colors=96, method=Image.Quantize.MEDIANCUT)
    frames = [fr.quantize(palette=pal, dither=Image.Dither.NONE) for fr in frames]
    os.makedirs(os.path.join(ROOT, "assets"), exist_ok=True)
    out = os.path.join(ROOT, "assets", "demo.gif")
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=1000 // fps, loop=0, optimize=True)
    print(out, os.path.getsize(out) // 1024, "KB")


if __name__ == "__main__":
    main()
