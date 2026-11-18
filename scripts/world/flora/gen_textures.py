"""Генератор текстур растительности FLORA (запускать из корня проекта):
  python3 scripts/world/flora/gen_textures.py
Пишет RGBA PNG в scenes/world/flora/tex/. Основа — CC0-листья ambientCG (assets/textures/Leaf00x)."""
import math, random, os
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageChops

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../../.."
OUT = ROOT + "/scenes/world/flora/tex"
TEX = ROOT + "/assets/textures"
os.makedirs(OUT, exist_ok=True)
R = random.Random(42)

def leaf_img(name, half):
    a = Image.open(f"{TEX}/{name}/{name}_albedo.png").convert("RGBA")
    o = Image.open(f"{TEX}/{name}/{name}_opacity.png").convert("L")
    a.putalpha(o)
    w, h = a.size
    box = (0, 0, w // 2, h) if half == 0 else (w // 2, 0, w, h)
    return a.crop(a.crop(box).getbbox() and tuple(x + y for x, y in zip(a.crop(box).getbbox(), (box[0], 0, box[0], 0)))) if False else a.crop(box).crop(a.crop(box).getbbox())

def tint(img, f_rgb, bright=1.0):
    r, g, b, al = img.split()
    r = r.point(lambda v: min(255, int(v * f_rgb[0] * bright)))
    g = g.point(lambda v: min(255, int(v * f_rgb[1] * bright)))
    b = b.point(lambda v: min(255, int(v * f_rgb[2] * bright)))
    return Image.merge("RGBA", (r, g, b, al))

# детальная «фактура» листа для модуляции процедурных листочков
LEAF_DETAIL = Image.open(f"{TEX}/Leaf001/Leaf001_albedo.png").convert("L").resize((256, 256))

def palm_frond(path, base=(58, 104, 38), tip=(104, 128, 52), dead=False, n_side=86):
    W, H = 1024, 256
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cy = H // 2
    for side in (-1, 1):
        for k in range(n_side):
            t = k / (n_side - 1)
            x0 = 40 + t * 950
            L = (40 + 105 * math.sin(math.pi * min(1.0, t * 1.15 + 0.08))) * (0.85 + 0.3 * R.random())
            if t > 0.92: L *= (1.0 - t) / 0.08 * 0.8 + 0.2
            ang = math.radians(32 + 18 * t + R.uniform(-5, 5))
            dx, dy = math.cos(ang) * L, math.sin(ang) * L * side
            wbase = 6.5 * (1.0 - 0.4 * t) + R.uniform(-0.5, 0.8)
            nx, ny = -math.sin(ang) * side, math.cos(ang)
            # изгиб листочка
            pts_a, pts_b = [], []
            steps = 8
            for s in range(steps + 1):
                u = s / steps
                bend = math.sin(u * math.pi) * 4.0
                px = x0 + dx * u + nx * bend * 0.3
                py = cy + dy * u + (bend if side > 0 else -bend) * 0.15
                ww = wbase * (1.0 - u) ** 0.8
                pts_a.append((px - ny * ww * 0.0 + nx * ww * 0.5, py + ww * 0.5))
                pts_b.append((px - nx * ww * 0.5, py - ww * 0.5))
            if dead:
                c = (int(120 + R.uniform(-15, 15)), int(92 + R.uniform(-12, 12)), int(52 + R.uniform(-10, 10)))
            else:
                mix = t * 0.6 + R.uniform(0, 0.4)
                c = tuple(int(base[i] * (1 - mix) + tip[i] * mix + R.uniform(-10, 10)) for i in range(3))
            d.polygon(pts_a + pts_b[::-1], fill=c + (255,))
            # светлая жилка
            d.line([(x0, cy), (x0 + dx * 0.85, cy + dy * 0.85)], fill=tuple(min(255, v + 28) for v in c) + (255,), width=1)
            # рваные кончики у сухих
            if dead and R.random() < 0.4:
                d.line([(x0 + dx * 0.6, cy + dy * 0.6), (x0 + dx, cy + dy)], fill=(0, 0, 0, 0), width=3)
    # черешок / центральная жила
    d.line([(0, cy), (W - 20, cy)], fill=(86, 92, 48, 255) if not dead else (110, 86, 54, 255), width=7)
    d.line([(0, cy - 1), (W - 20, cy - 1)], fill=(120, 126, 70, 255) if not dead else (140, 112, 70, 255), width=2)
    # модуляция фактурой
    det = LEAF_DETAIL.resize((W, H))
    r, g, b, a = img.split()
    det = ImageEnhance.Contrast(det).enhance(0.6)
    r = ImageChops.multiply(r, det.point(lambda v: 150 + v // 3)); g = ImageChops.multiply(g, det.point(lambda v: 150 + v // 3)); b = ImageChops.multiply(b, det.point(lambda v: 150 + v // 3))
    img = Image.merge("RGBA", (r.point(lambda v: min(255, int(v * 1.35))), g.point(lambda v: min(255, int(v * 1.35))), b.point(lambda v: min(255, int(v * 1.35))), a))
    img.save(path)

def leaf_cluster(path, leaf_name, half, count, scale, color, size=512, twig=(78, 62, 40)):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    leaf = leaf_img(leaf_name, half)
    cx, base_y = size // 2, size - 10
    # веточки
    tips = []
    for k in range(7):
        a = math.radians(-90 + R.uniform(-70, 70))
        L = R.uniform(0.45, 0.85) * size * 0.55
        ex, ey = cx + math.cos(a) * L, base_y + math.sin(a) * L
        d.line([(cx, base_y), (ex, ey)], fill=twig + (255,), width=4)
        tips.append((ex, ey, a))
    for k in range(count):
        ex, ey, a = R.choice(tips)
        u = R.uniform(0.3, 1.0)
        px = cx + (ex - cx) * u + R.uniform(-30, 30)
        py = base_y + (ey - base_y) * u + R.uniform(-30, 30)
        s = scale * R.uniform(0.75, 1.15)
        lw = max(8, int(leaf.width * s)); lh = max(8, int(leaf.height * s))
        lf = leaf.resize((lw, lh), Image.LANCZOS)
        rot = math.degrees(a) + 90 + R.uniform(-55, 55)
        lf = lf.rotate(-rot, expand=True, resample=Image.BICUBIC)
        br = R.uniform(0.7, 1.15)
        lf = tint(lf, color, br)
        img.alpha_composite(lf, (int(px - lf.width / 2), int(py - lf.height / 2)))
    img.save(path)

def grass_clump(path, n=46):
    W, H = 512, 512
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for k in range(n):
        x0 = W / 2 + R.uniform(-170, 170)
        Hh = R.uniform(0.45, 0.97) * H
        lean = R.uniform(-90, 90)
        w0 = R.uniform(5, 10)
        g = R.uniform(0, 1)
        c = (int(70 + 70 * g + R.uniform(-10, 10)), int(110 + 40 * g + R.uniform(-10, 10)), int(36 + 20 * g))
        if R.random() < 0.15: c = (150, 140, 80)  # сухие травинки
        pts_l, pts_r = [], []
        for s in range(11):
            u = s / 10
            x = x0 + lean * u * u
            y = H - 2 - Hh * u
            ww = w0 * (1 - u) ** 0.9
            pts_l.append((x - ww / 2, y)); pts_r.append((x + ww / 2, y))
        d.polygon(pts_l + pts_r[::-1], fill=c + (255,))
        d.line([(x0, H - 2), (x0 + lean * 0.5, H - 2 - Hh * 0.7)], fill=tuple(min(255, v + 25) for v in c) + (255,), width=1)
    img.save(path)

def end_grain(path):
    W = 256
    img = Image.new("RGB", (W, W), (150, 112, 70))
    d = ImageDraw.Draw(img)
    c = W / 2
    r = W / 2
    k = 0
    while r > 2:
        col = (int(176 - k % 2 * 18 + R.uniform(-6, 6)), int(134 - k % 2 * 16), int(86 - k % 2 * 12))
        d.ellipse([c - r + R.uniform(-1, 1), c - r, c + r, c + r + R.uniform(-1, 1)], fill=col)
        r -= R.uniform(4, 9); k += 1
    d.ellipse([0, 0, W - 1, W - 1], outline=(70, 50, 32), width=10)
    for i in range(6):
        a = R.uniform(0, math.tau)
        d.line([(c, c), (c + math.cos(a) * W * 0.45, c + math.sin(a) * W * 0.45)], fill=(110, 80, 50), width=1)
    img = img.filter(ImageFilter.GaussianBlur(0.8))
    img.save(path)

palm_frond(f"{OUT}/palm_frond.png")
palm_frond(f"{OUT}/palm_frond_young.png", base=(70, 120, 42), tip=(132, 150, 60))
palm_frond(f"{OUT}/palm_frond_dead.png", dead=True)
leaf_cluster(f"{OUT}/broadleaf_cluster.png", "Leaf001", 0, 70, 0.33, (0.78, 0.92, 0.70))
leaf_cluster(f"{OUT}/broadleaf_cluster_b.png", "Leaf001", 1, 70, 0.30, (0.70, 0.88, 0.62))
leaf_cluster(f"{OUT}/bush_cluster.png", "Leaf003", 0, 34, 0.42, (0.85, 1.0, 0.80))
grass_clump(f"{OUT}/grass_clump.png")
end_grain(f"{OUT}/end_grain.png")
print("ok")
