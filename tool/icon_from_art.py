"""Builds Relay's edge-to-edge Android icon layers from the artwork image.
usage: icon_from_art.py ART.png RES_DIR [preview.png]"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 1080
SCALE = .66
CX, CY = 630, 615  # centre of the bubbles in the artwork


def bg_field(w, h):
    tl, tr, bl, br = [np.array(c, float) for c in ((6, 24, 52), (14, 17, 56), (6, 14, 36), (8, 10, 24))]
    x = np.linspace(0, 1, w)[None, :, None]
    y = np.linspace(0, 1, h)[:, None, None]
    return (tl * (1 - x) * (1 - y) + tr * x * (1 - y) + bl * (1 - x) * y + br * x * y)


def build(art_path):
    src = Image.open(art_path).convert("RGB")
    w, h = src.size
    P = np.asarray(src, float)
    B = bg_field(w, h)
    region = Image.new("L", (w, h), 0)
    ImageDraw.Draw(region).rectangle((190, 245, 1075, 1000), fill=255)
    region = np.asarray(region.filter(ImageFilter.GaussianBlur(28)), float)[..., None] / 255
    dist = np.abs(P - B).max(axis=2, keepdims=True)
    a = np.clip(dist / 70, 0, 1) * region
    F = np.clip((P - (1 - a) * B) / np.maximum(a, 1e-3), 0, 255)
    fg = np.dstack([F, a * 255]).astype(np.uint8)
    # single-colour version: bubbles only, typing dots cut out
    solid = np.clip((dist - 40) / 30, 0, 1) * region
    holes = Image.new("L", (w, h), 0)
    hd = ImageDraw.Draw(holes)
    for dx in (404, 552, 704):
        hd.ellipse((dx - 47, 548 - 47, dx + 47, 548 + 47), fill=255)
    holes = np.asarray(holes.filter(ImageFilter.GaussianBlur(1.2)), float)[..., None] / 255
    mono_a = solid * (1 - holes) * 255
    mono = np.dstack([np.full((h, w, 3), 255), mono_a]).astype(np.uint8)

    def place(arr):
        im = Image.fromarray(arr, "RGBA")
        n = int(w * SCALE)
        im = im.resize((n, n), Image.LANCZOS)
        out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        out.paste(im, (int(540 - CX * SCALE), int(540 - CY * SCALE)), im)
        return out

    bgl = Image.fromarray(bg_field(S, S).astype(np.uint8), "RGB").convert("RGBA")
    return bgl, place(fg), place(mono)


def mask(size):
    m = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(m).ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
    return m.resize((size, size), Image.LANCZOS)


def composite(bg, fg, size, shape="circle"):
    full = Image.alpha_composite(bg, fg)
    c = int(S * 72 / 108)
    o = (S - c) // 2
    full = full.crop((o, o, o + c, o + c)).resize((size, size), Image.LANCZOS)
    if shape == "circle":
        full.putalpha(mask(size))
    return full


if __name__ == "__main__":
    bg, fg, mono = build(sys.argv[1])
    res = sys.argv[2]
    for dens, px, leg in (("mdpi", 108, 48), ("hdpi", 162, 72), ("xhdpi", 216, 96), ("xxhdpi", 324, 144), ("xxxhdpi", 432, 192)):
        base = f"{res}/mipmap-{dens}/ic_launcher"
        bg.resize((px, px), Image.LANCZOS).convert("RGB").save(base + "_background.png")
        fg.resize((px, px), Image.LANCZOS).save(base + "_foreground.png")
        mono.resize((px, px), Image.LANCZOS).save(base + "_monochrome.png")
        composite(bg, fg, leg).save(base + ".png")
    if len(sys.argv) > 3:
        sheet = Image.new("RGB", (3 * 360 + 160, 400), (236, 238, 242))
        for i, shape in enumerate(("circle", "square")):
            im = composite(bg, fg, 360, shape)
            sheet.paste(im, (40 + i * 400, 20), im)
        m = Image.new("RGBA", (S, S), (60, 60, 66, 255))
        mm = Image.alpha_composite(m, mono).crop((180, 180, 900, 900)).resize((360, 360))
        sheet.paste(mm, (40 + 2 * 400, 20))
        sheet.save(sys.argv[3])
