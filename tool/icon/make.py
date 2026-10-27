import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops
S = 2160  # 108dp * 20 (supersampled)
C = S // 2

def L(mode='L'): return Image.new(mode, (S, S), 0)
K = 1.0
def t(*v):
    # scale coordinates toward the centre so the art sits inside the launcher's safe zone
    if len(v) == 1 and isinstance(v[0], (list, tuple)):
        return type(v[0])(t(*p) if isinstance(p, (list, tuple)) else C + (p - C) * K for p in v[0])
    return tuple(C + (x - C) * K for x in v)
def arr(m): return np.asarray(m, dtype=np.float32) / 255.0

def lin_grad(c1, c2, angle=90):
    y, x = np.mgrid[0:S, 0:S].astype(np.float32) / S
    a = np.deg2rad(angle)
    t = (x * np.cos(a) + y * np.sin(a)); t = (t - t.min()) / (t.max() - t.min())
    c1, c2 = np.array(c1, np.float32), np.array(c2, np.float32)
    return c1 + (c2 - c1) * t[..., None]

def rad_grad(c_in, c_out, cx, cy, r):
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    t = np.clip(np.hypot(x - cx, y - cy) / r, 0, 1)[..., None]
    return np.array(c_in, np.float32) + (np.array(c_out, np.float32) - np.array(c_in, np.float32)) * t

def comp(base, rgb, alpha):
    """base: HxWx3 float 0-255; rgb HxWx3 or tuple; alpha HxW 0-1"""
    rgb = np.broadcast_to(np.array(rgb, np.float32), base.shape) if not isinstance(rgb, np.ndarray) else rgb
    a = alpha[..., None]
    return base * (1 - a) + rgb * a

def blur(m, r): return m.filter(ImageFilter.GaussianBlur(r))

def bubble_mask(box, r, tail):
    m = L(); d = ImageDraw.Draw(m)
    d.rounded_rectangle(box, r, fill=255); d.polygon(tail, fill=255)
    return blur(m, 2)

def glossy(base, mask, top, bottom, angle=90, shadow=True, gloss=.55, rim=True):
    a = arr(mask)
    if shadow:
        sh = arr(blur(ImageChops.offset(mask, 0, 40), 60)) * .55
        base = comp(base, (0, 0, 0), sh)
    base = comp(base, lin_grad(top, bottom, angle), a)
    # soft inner shading at the bottom edge
    inner = 1 - arr(blur(ImageChops.offset(mask, 0, -30), 40))
    base = comp(base, (0, 0, 0), np.clip(inner * a, 0, 1) * .35)
    # glossy top highlight: mask shifted down & clipped, faded top->bottom
    ys, xs = np.nonzero(a > .5)
    y0, y1 = ys.min(), ys.max()
    y = np.arange(S, dtype=np.float32)[:, None]
    fade = np.clip(1 - (y - y0) / ((y1 - y0) * .55), 0, 1) ** 1.6
    hl = arr(blur(mask.resize((S, S)).transform((S, S), Image.AFFINE, (1.06, 0, -C * .06, 0, 1.06, -40)), 10)) * a
    base = comp(base, (255, 255, 255), hl * fade * gloss)
    if rim:
        edge = np.clip(a - arr(blur(mask, 6)) * 0 - arr(mask.filter(ImageFilter.MinFilter(9))), 0, 1)
        base = comp(base, (255, 255, 255), edge * .35)
    return base

def bg_layer(top, bottom, glow=None):
    b = lin_grad(top, bottom, 100)
    if glow:
        col, cx, cy, r, k = glow
        g = np.clip(1 - np.hypot(*np.mgrid[0:S, 0:S] - np.array([cy, cx])[:, None, None]) / r, 0, 1) ** 2
        b = comp(b, col, g * k)
    return b

# ---------------------------------------------------------- A: Link bubble
def design_a():
    global K
    K = .74
    base = bg_layer((10, 18, 44), (4, 6, 16), glow=((40, 90, 255), C, C - 120, 900, .45))
    m = bubble_mask(t((560, 560, 1600, 1400)), int(330 * K), [t(700, 1300), t(620, 1640), t(960, 1390)])
    base = glossy(base, m, (250, 252, 255), (196, 210, 232))
    def ring(box, w):
        box = t(box)
        o = L(); d = ImageDraw.Draw(o); d.rounded_rectangle(box, int((box[3] - box[1]) // 2), fill=255)
        i = L(); d2 = ImageDraw.Draw(i)
        d2.rounded_rectangle((box[0] + w, box[1] + w, box[2] - w, box[3] - w), int((box[3] - box[1] - 2 * w) // 2), fill=255)
        return blur(ImageChops.subtract(o, i), 2)
    r1 = ring((700, 800, 1260, 1160), 70)
    r2 = ring((900, 800, 1460, 1160), 70)
    blue = lin_grad((80, 150, 255), (25, 75, 225), 90)
    red = lin_grad((255, 95, 95), (210, 25, 45), 90)
    shadow = lambda r: arr(blur(ImageChops.offset(r, 0, 12), 14)) * .25
    base = comp(base, (0, 0, 0), shadow(r1)); base = comp(base, blue, arr(r1))
    base = comp(base, (0, 0, 0), shadow(r2)); base = comp(base, red, arr(r2))
    # blue passes over red at the bottom crossing -> the links look joined
    cut = L(); ImageDraw.Draw(cut).rectangle(t((1100, 1040, 1300, 1200)), fill=255)
    over = ImageChops.multiply(r1, blur(cut, 4))
    base = comp(base, (0, 0, 0), arr(blur(ImageChops.offset(over, 0, 8), 8)) * .3)
    base = comp(base, blue, arr(over))
    K = 1.0
    return base

# ---------------------------------------------------------- B: Relay loop
SHAPES = {}

def design_b_bg():
    base = bg_layer((14, 14, 22), (0, 0, 0), glow=((255, 40, 60), C - 300, C + 250, 800, .35))
    return comp(base, (40, 90, 255), np.clip(1 - np.hypot(*np.mgrid[0:S, 0:S] - np.array([C - 250, C + 300])[:, None, None]) / 800, 0, 1) ** 2 * .35)

def design_b(base=None):
    base = design_b_bg() if base is None else base
    SHAPES.clear(); SHAPES['arcs'] = []
    def arc(start, end, color_top, color_bot):
        o = L(); d = ImageDraw.Draw(o)
        R, w = 470, 120
        d.pieslice((C - R, C - R, C + R, C + R), start, end, fill=255)
        d.ellipse((C - R + w, C - R + w, C + R - w, C + R - w), fill=0)
        # arrow head at the end angle
        a = np.deg2rad(end); rm = R - w / 2
        tip = (C + np.cos(a + .32) * rm, C + np.sin(a + .32) * rm)
        p1 = (C + np.cos(a) * (R + 70), C + np.sin(a) * (R + 70)); p2 = (C + np.cos(a) * (R - w - 70), C + np.sin(a) * (R - w - 70))
        d.polygon([p1, tip, p2], fill=255)
        return glossy, blur(o, 2), color_top, color_bot
    for start, end, t, b in [(200, 340, (255, 110, 110), (205, 20, 40)), (20, 160, (110, 170, 255), (25, 70, 230))]:
        _, m, t, b = arc(start, end, t, b)
        SHAPES['arcs'].append(m)
        base = glossy(base, m, t, b, gloss=.45)
    # white chat bubble in the middle
    m = bubble_mask((800, 840, 1360, 1250), 170, [(880, 1200), (840, 1380), (1020, 1240)])
    SHAPES['bubble'] = m; SHAPES['dots'] = []
    base = glossy(base, m, (255, 255, 255), (205, 214, 230), gloss=.35)
    for i, x in enumerate((960, 1080, 1200)):
        d = L(); ImageDraw.Draw(d).ellipse((x - 34, 1045 - 34, x + 34, 1045 + 34), fill=255)
        SHAPES['dots'].append(d)
        base = comp(base, [(40, 90, 255), (120, 60, 200), (230, 40, 60)][i], arr(blur(d, 2)))
    return base

# ---------------------------------------------------------- C: Paper plane bubble
def design_c():
    global K
    K = .72
    base = bg_layer((255, 255, 255), (222, 228, 240))
    m = bubble_mask(t((480, 540, 1580, 1440)), int(360 * K), [t(1380, 1330), t(1640, 1660), t(1160, 1420)])
    base = glossy(base, m, (70, 140, 255), (16, 52, 190), gloss=.5)
    trail = L(); d = ImageDraw.Draw(trail)
    for (x0, y0, x1, y1, w) in [(640, 1250, 960, 1090, 44), (700, 1340, 980, 1200, 30)]:
        (x0, y0), (x1, y1) = t(x0, y0), t(x1, y1); w = int(w * K)
        d.line((x0, y0, x1, y1), fill=255, width=w); d.ellipse((x0 - w / 2, y0 - w / 2, x0 + w / 2, y0 + w / 2), fill=255)
    base = comp(base, lin_grad((255, 80, 90), (220, 30, 50), 0), arr(blur(trail, 3)) * .95)
    plane = L(); ImageDraw.Draw(plane).polygon([t(880, 1040), t(1420, 760), t(1200, 1300), t(1080, 1120)], fill=255)
    base = comp(base, (0, 0, 0), arr(blur(ImageChops.offset(plane, 10, 24), 18)) * .35)
    base = comp(base, (255, 255, 255), arr(blur(plane, 2)))
    fold = L(); ImageDraw.Draw(fold).polygon([t(1080, 1120), t(1420, 760), t(1140, 1180)], fill=255)
    base = comp(base, (205, 215, 235), arr(blur(fold, 2)))
    K = 1.0
    return base

def mask(size, shape):
    m = Image.new('L', (size * 4, size * 4), 0); d = ImageDraw.Draw(m)
    if shape == 'circle': d.ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
    else: d.rounded_rectangle((0, 0, size * 4 - 1, size * 4 - 1), int(size * 4 * .26), fill=255)
    return m.resize((size, size), Image.LANCZOS)

def preview(designs, out):
    cell, pad = 360, 40
    sheet = Image.new('RGB', (3 * cell + 4 * pad, 2 * cell + 3 * pad + 70), (236, 238, 242))
    dd = ImageDraw.Draw(sheet)
    f = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 34)
    for i, (k, img) in enumerate(designs):
        im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
        c = int(S * 72 / 108); o = (S - c) // 2
        im = im.crop((o, o, o + c, o + c)).resize((cell, cell), Image.LANCZOS)
        x = pad + i * (cell + pad)
        for j, shape in enumerate(('squircle', 'circle')):
            t = im.copy(); t.putalpha(mask(cell, shape))
            sheet.paste(t, (x, pad + 60 + j * (cell + pad)), t)
        dd.text((x + cell // 2 - 12, pad), k, fill=(20, 20, 24), font=f)
    sheet.save(out)

if __name__ == '__main__':
    preview([('A', design_a()), ('B', design_b()), ('C', design_c())], '/tmp/claude-0/icons3/preview.png')
