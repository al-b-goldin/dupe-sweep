"""Builds the README art in docs/readme/ from the generated illustrations and the app screenshots.
Run: python3 scripts/make_readme_art.py <folder with hero.png speed.png keep.png undo.png private.png>
"""
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1]
OUT = os.path.join(ROOT, "docs", "readme")
os.makedirs(OUT, exist_ok=True)
SF = "/System/Library/Fonts/SFNS.ttf"

def font(size, weight="Bold"):
    f = ImageFont.truetype(SF, size)
    try: f.set_variation_by_name(weight)
    except Exception: pass
    return f

def rounded(im, r):
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, im.size[0]-1, im.size[1]-1], r, fill=255)
    im = im.convert("RGBA"); a = im.getchannel("A")
    from PIL import ImageChops
    im.putalpha(ImageChops.multiply(a, m)); return im

def shadow(canvas, box, r, blur, alpha, offset=(0, 18)):
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    x0, y0, x1, y1 = box
    ImageDraw.Draw(sh).rounded_rectangle([x0+offset[0], y0+offset[1], x1+offset[0], y1+offset[1]], r, fill=(4, 30, 36, alpha))
    canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(blur)))

# ---------- hero banner ----------
hero = Image.open(os.path.join(SRC, "hero.png")).convert("RGBA")
W, H = hero.size
top = 90; hero = hero.crop((0, top, W, top + 700))
d = ImageDraw.Draw(hero)
icon = Image.open(os.path.join(ROOT, "dist/icon/icon-1024.png")).convert("RGBA").resize((190, 190), Image.LANCZOS)
x = 96
hero.alpha_composite(icon, (x - 22, 120))
d.text((x, 320), "Dupe Sweep", font=font(112, "Bold"), fill="white")
sub = font(38, "Medium")
d.text((x + 4, 455), "Find duplicate files on your Mac.", font=sub, fill=(224, 244, 247))
d.text((x + 4, 503), "Keep the right copy. Get the space back.", font=sub, fill=(224, 244, 247))
px = x + 2; py = 590; pf = font(26, "Semibold")
for label in ["Free", "Open source", "Private", "macOS 14+"]:
    tw = d.textlength(label, font=pf)
    layer = Image.new("RGBA", hero.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle([px, py, px + tw + 40, py + 48], 24, fill=(255, 255, 255, 40), outline=(255, 255, 255, 120), width=2)
    hero.alpha_composite(layer); d = ImageDraw.Draw(hero)
    d.text((px + 20, py + 9), label, font=pf, fill="white")
    px += tw + 56
hero.convert("RGB").save(os.path.join(OUT, "hero.jpg"), quality=90)

# ---------- feature illustrations ----------
for n in ["speed", "keep", "undo", "private"]:
    im = Image.open(os.path.join(SRC, n + ".png")).convert("RGB")
    s = im.size[0]; c = int(s * 0.1)
    im = im.crop((c, c, s - c, s - c)).resize((480, 480), Image.LANCZOS)
    rounded(im, 48).save(os.path.join(OUT, f"feature-{n}.png"))

# ---------- framed screenshots ----------
def window(shot_path, dark):
    shot = Image.open(shot_path).convert("RGBA")
    w, h = shot.size; bar = 36
    bg = (38, 38, 40, 255) if dark else (236, 236, 238, 255)
    win = Image.new("RGBA", (w, h + bar), bg)
    body = (30, 30, 30, 255) if dark else (255, 255, 255, 255)
    ImageDraw.Draw(win).rectangle([0, bar, w, h + bar], fill=body)
    win.alpha_composite(shot, (0, bar))
    dd = ImageDraw.Draw(win)
    for i, col in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
        cx = 22 + i * 22; dd.ellipse([cx - 7, bar//2 - 7, cx + 7, bar//2 + 7], fill=col)
    dd.line([0, bar - 1, w, bar - 1], fill=(0, 0, 0, 60) if not dark else (255, 255, 255, 25))
    return rounded(win, 14)

def backdrop(w, h, dark):
    a, b = ((14, 62, 72), (9, 38, 46)) if dark else ((47, 168, 186), (19, 94, 107))
    g = Image.new("RGBA", (w, h))
    gd = ImageDraw.Draw(g)
    for y in range(h):
        t = y / h
        gd.line([0, y, w, y], fill=tuple(int(a[k] + (b[k] - a[k]) * t) for k in range(3)) + (255,))
    return rounded(g, 28)

def framed(name, out, dark, pad=70):
    win = window(os.path.join(ROOT, "docs/images", name), dark)
    W2, H2 = win.size[0] + pad * 2, win.size[1] + pad * 2
    c = backdrop(W2, H2, dark)
    shadow(c, (pad, pad, pad + win.size[0], pad + win.size[1]), 14, 26, 150)
    c.alpha_composite(win, (pad, pad))
    c.save(os.path.join(OUT, out))

framed("3-results.png", "results-light.png", False)
framed("3-results-dark.png", "results-dark.png", True)
for n in ["1-start", "2-scanning", "4-done"]:
    framed(n + ".png", f"{n}-light.png", False, pad=40)
    framed(n + "-dark.png", f"{n}-dark.png", True, pad=40)
print("ok", sorted(os.listdir(OUT)))
