import sys
sys.path.insert(0, __import__('os').path.dirname(__file__))
import numpy as np
from PIL import Image, ImageChops, ImageDraw
import make as M

res = sys.argv[1]
S = M.S
# Foreground on its own: render over black and over white, then solve for colour + alpha.
blk = M.design_b(np.zeros((S, S, 3), np.float32))
wht = M.design_b(np.full((S, S, 3), 255, np.float32))
alpha = np.clip(1 - (wht - blk).mean(axis=2) / 255.0, 0, 1)
col = np.where(alpha[..., None] > 1e-3, blk / np.maximum(alpha[..., None], 1e-3), 0)
fg = Image.fromarray(np.dstack([np.clip(col, 0, 255), alpha * 255]).astype(np.uint8), 'RGBA')
bg = Image.fromarray(np.clip(M.design_b_bg(), 0, 255).astype(np.uint8), 'RGB')

# Single-colour silhouette (themed icons + status bar): arrows + bubble, dots cut out.
sil = Image.new('L', (S, S), 0)
for m in M.SHAPES['arcs'] + [M.SHAPES['bubble']]:
    sil = ImageChops.lighter(sil, m)
for d in M.SHAPES['dots']:
    sil = ImageChops.subtract(sil, d)
mono = Image.merge('RGBA', [Image.new('L', (S, S), 255)] * 3 + [sil])

full = Image.alpha_composite(bg.convert('RGBA'), fg)
def circle(size):
    c = int(S * 72 / 108); o = (S - c) // 2
    im = full.crop((o, o, o + c, o + c)).resize((size, size), Image.LANCZOS)
    m = Image.new('L', (size * 4, size * 4), 0); ImageDraw.Draw(m).ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
    im.putalpha(m.resize((size, size), Image.LANCZOS)); return im

for dens, px, leg, st in (('mdpi', 108, 48, 24), ('hdpi', 162, 72, 36), ('xhdpi', 216, 96, 48), ('xxhdpi', 324, 144, 72), ('xxxhdpi', 432, 192, 96)):
    base = f'{res}/mipmap-{dens}/ic_launcher'
    bg.resize((px, px), Image.LANCZOS).save(base + '_background.png')
    fg.resize((px, px), Image.LANCZOS).save(base + '_foreground.png')
    mono.resize((px, px), Image.LANCZOS).save(base + '_monochrome.png')
    circle(leg).save(base + '.png')
    # Status-bar icon: white on transparent, art filling ~84% of the square.
    k = .84
    c = 1180  # the art spans about 1100 px of the 2160 canvas
    o = (S - c) // 2
    stat = mono.crop((o, o, o + c, o + c)).resize((int(st * k), int(st * k)), Image.LANCZOS)
    out = Image.new('RGBA', (st, st), (0, 0, 0, 0)); out.paste(stat, ((st - stat.width) // 2, (st - stat.height) // 2), stat)
    out.save(f'{res}/drawable-{dens}/ic_stat_relay.png')

# Previews for checking
prev = Image.new('RGBA', (1000, 320), (236, 238, 242, 255))
prev.paste(circle(280), (20, 20), circle(280))
m = mono.resize((280, 280), Image.LANCZOS); bgm = Image.new('RGBA', (280, 280), (60, 60, 66, 255)); bgm.alpha_composite(m); prev.paste(bgm, (340, 20))
sb = Image.new('RGBA', (300, 120), (20, 20, 24, 255))
for i, (dens, st) in enumerate((('xxhdpi', 72), ('mdpi', 24))):
    ic = Image.open(f'{res}/drawable-{dens}/ic_stat_relay.png').convert('RGBA')
    sb.alpha_composite(ic, (20 + i * 120, (120 - st) // 2))
prev.paste(sb, (660, 100))
prev.save('applied-preview.png')
print('ok')
