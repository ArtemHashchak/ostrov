"""FLORA G2: текстуры новых растений (запуск из корня проекта):
  python3 scripts/world/flora/gen_textures_g2.py
herb_cluster, taro_leaf, maize_blade, melon_leaf, liana_strip, mangrove_cluster, melon_skin."""
import math, random, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageEnhance

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../../.."
OUT = ROOT + "/scenes/world/flora/tex"
TEX = ROOT + "/assets/textures"
R = random.Random(7)
DET = Image.open(f"{TEX}/Leaf001/Leaf001_albedo.png").convert("L")

def detail(img, k=0.35):
    det = ImageEnhance.Contrast(DET.resize(img.size)).enhance(0.7)
    r, g, b, a = img.split()
    m = det.point(lambda v: int(255 * (1 - k) + v * k))
    r, g, b = (ImageChops.multiply(c, m).point(lambda v: min(255, int(v * 1.25))) for c in (r, g, b))
    return Image.merge("RGBA", (r, g, b, a))

def leaf_poly(d, cx, cy, ang, L, W, col, vein=True, heart=False, lobes=0):
    """Лист: контур вдоль оси ang (радианы), длина L, ширина W."""
    ca, sa = math.cos(ang), math.sin(ang)
    pts_l, pts_r = [], []
    N = 18
    for s in range(N + 1):
        u = s / N
        w = math.sin(math.pi * min(1.0, u * 1.05)) ** 0.8 * W * 0.5
        if heart and u < 0.25:
            w = W * 0.5 * (0.75 + u)
        if lobes:
            w *= 0.82 + 0.18 * abs(math.sin(u * math.pi * lobes))
        x, y = u * L, 0
        pts_l.append((x, w)); pts_r.append((x, -w))
    poly = pts_l + pts_r[::-1]
    if heart:
        poly = [(-L * 0.18, W * 0.28)] + poly + [(-L * 0.18, -W * 0.28)]
    tp = [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in poly]
    d.polygon(tp, fill=col + (255,))
    if vein:
        lc = tuple(min(255, v + 30) for v in col) + (255,)
        d.line([(cx, cy), (cx + L * 0.95 * ca, cy + L * 0.95 * sa)], fill=lc, width=max(1, int(W * 0.04)))
        for k in range(1, 7):
            u = k / 7.5
            for side in (-1, 1):
                bx, by = cx + u * L * ca, cy + u * L * sa
                a2 = ang + side * 0.9
                l2 = W * 0.42 * math.sin(math.pi * min(1, u * 1.05))
                d.line([(bx, by), (bx + l2 * math.cos(a2), by + l2 * math.sin(a2))], fill=lc, width=1)

def herb_cluster(path):
    S = 512
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    stems = []
    for k in range(11):
        x0 = S / 2 + R.uniform(-60, 60)
        h = R.uniform(0.5, 0.92) * S
        lean = R.uniform(-110, 110)
        pts = [(x0 + lean * (u / 10) ** 2, S - 2 - h * u / 10) for u in range(11)]
        d.line(pts, fill=(70, 100, 44, 255), width=4)
        stems.append(pts)
    for pts in stems:
        for i in range(2, 10, 2):
            x, y = pts[i]
            for side in (-1, 1):
                ang = math.radians(-90 + side * R.uniform(35, 75))
                g = R.uniform(0, 1)
                leaf_poly(d, x, y, ang, R.uniform(38, 62), R.uniform(16, 24), (int(64 + 40 * g), int(118 + 30 * g), int(48 + 10 * g)))
    for pts in stems:  # соцветия на макушках
        x, y = pts[-1]
        col = R.choice([(236, 236, 228), (232, 206, 72), (196, 120, 196)])
        for f in range(R.randint(5, 9)):
            fx, fy = x + R.uniform(-16, 16), y + R.uniform(-12, 10)
            r = R.uniform(4, 7)
            d.ellipse([fx - r, fy - r, fx + r, fy + r], fill=col + (255,))
            d.ellipse([fx - 1.5, fy - 1.5, fx + 1.5, fy + 1.5], fill=(240, 200, 60, 255))
    detail(img).save(path)

def taro_leaf(path):
    S = 512
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    # один большой сердцевидный лист «слоновье ухо», черешок крепится у основания (низ текстуры)
    col = (58, 112, 46)
    leaf_poly(d, S / 2, S * 0.70, -math.pi / 2, S * 0.68, S * 0.80, col, vein=False)
    for side in (-1, 1):  # базальные лопасти «сердца»
        cx = S / 2 + side * S * 0.2
        d.ellipse([cx - S * 0.2, S * 0.52, cx + S * 0.2, S * 0.97], fill=col + (255,))
    d.polygon([(S / 2, S * 0.70), (S / 2 - S * 0.07, S), (S / 2 + S * 0.07, S)], fill=(0, 0, 0, 0))
    lc = (96, 150, 76, 255)
    for k in range(9):  # жилки веером от точки крепления черешка
        a = math.radians(-90 + (k - 4) * 22)
        L = S * (0.62 if k == 4 else 0.38)
        d.line([(S / 2, S * 0.70), (S / 2 + math.cos(a) * L, S * 0.70 + math.sin(a) * L)], fill=lc, width=3 if k == 4 else 2)
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    detail(img, 0.08).save(path)

def maize_blade(path):
    W, H = 256, 1024
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    for k in range(5):
        x0 = W / 2 + R.uniform(-30, 30)
        lean = R.uniform(-90, 90)
        w0 = R.uniform(20, 30)
        g = R.uniform(0, 1)
        c = (int(78 + 50 * g), int(124 + 30 * g), int(46 + 10 * g))
        pl, pr = [], []
        for s in range(21):
            u = s / 20
            x = x0 + lean * u * u
            y = H - 2 - (H - 20) * u
            ww = w0 * (1 - u) ** 0.6 * (0.7 + 0.3 * math.sin(u * 3))
            pl.append((x - ww / 2, y)); pr.append((x + ww / 2, y))
        d.polygon(pl + pr[::-1], fill=c + (255,))
        d.line([(x0, H - 2), (x0 + lean * 0.6, H * 0.25)], fill=tuple(min(255, v + 35) for v in c) + (255,), width=2)
    detail(img, 0.2).save(path)

def melon_leaf(path):
    S = 512
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    for k in range(9):
        ang = R.uniform(0, math.tau)
        rr = R.uniform(40, 170)
        cx, cy = S / 2 + math.cos(ang) * rr, S / 2 + math.sin(ang) * rr
        g = R.uniform(0, 1)
        leaf_poly(d, cx, cy, ang + R.uniform(-0.5, 0.5), R.uniform(110, 150), R.uniform(95, 125), (int(60 + 36 * g), int(110 + 28 * g), int(42 + 10 * g)), lobes=3)
    # усики-плети
    for k in range(6):
        a = R.uniform(0, math.tau)
        pts = [(S / 2 + math.cos(a + u * 0.15) * u * 24, S / 2 + math.sin(a + u * 0.15) * u * 24) for u in range(11)]
        d.line(pts, fill=(84, 112, 50, 255), width=3)
    detail(img, 0.3).save(path)

def liana_strip(path):
    W, H = 256, 1024
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    pts = [(W / 2 + math.sin(y / 90.0) * 22, y) for y in range(0, H + 1, 16)]
    d.line(pts, fill=(88, 78, 46, 255), width=9)
    d.line(pts, fill=(112, 102, 60, 255), width=3)
    for (x, y) in pts[1:-1]:
        if R.random() < 0.85:
            for side in (-1, 1):
                if R.random() < 0.7:
                    ang = math.radians(90 + side * R.uniform(40, 80))
                    g = R.uniform(0, 1)
                    leaf_poly(d, x, y, ang, R.uniform(46, 76), R.uniform(24, 34), (int(56 + 40 * g), int(104 + 34 * g), int(40 + 12 * g)), heart=R.random() < 0.5)
    detail(img, 0.3).save(path)

def mangrove_cluster(path):
    # мелкие кожистые овальные листья, тёмно-оливковые, плотная гроздь
    S = 512
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    cx, by = S / 2, S - 10
    tips = []
    for k in range(9):
        a = math.radians(-90 + R.uniform(-75, 75))
        L = R.uniform(0.5, 0.9) * S * 0.55
        ex, ey = cx + math.cos(a) * L, by + math.sin(a) * L
        d.line([(cx, by), (ex, ey)], fill=(70, 58, 40, 255), width=4)
        tips.append((ex, ey, a))
    for k in range(120):
        ex, ey, a = R.choice(tips)
        u = R.uniform(0.35, 1.0)
        px, py = cx + (ex - cx) * u + R.uniform(-26, 26), by + (ey - by) * u + R.uniform(-26, 26)
        g = R.uniform(0, 1)
        leaf_poly(d, px, py, a + R.uniform(-1.2, 1.2), R.uniform(42, 60), R.uniform(20, 27), (int(52 + 34 * g), int(86 + 30 * g), int(38 + 8 * g)), vein=True)
    detail(img, 0.3).save(path)

def melon_skin(path):
    W = 256
    img = Image.new("RGB", (W, W), (64, 104, 42)); d = ImageDraw.Draw(img)
    for k in range(10):
        x = k * W / 10
        pts = [(x + math.sin(y / 18.0 + k) * 5, y) for y in range(0, W + 1, 8)]
        d.line(pts, fill=(150, 176, 96), width=7)
    img = img.filter(ImageFilter.GaussianBlur(2.2))
    img.save(path)

herb_cluster(f"{OUT}/herb_cluster.png")
taro_leaf(f"{OUT}/taro_leaf.png")
maize_blade(f"{OUT}/maize_blade.png")
melon_leaf(f"{OUT}/melon_leaf.png")
liana_strip(f"{OUT}/liana_strip.png")
mangrove_cluster(f"{OUT}/mangrove_cluster.png")
melon_skin(f"{OUT}/melon_skin.png")
print("ok")
