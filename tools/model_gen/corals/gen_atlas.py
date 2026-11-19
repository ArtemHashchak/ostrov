# Атлас «карточек» кораллов (2×2 плитки по 512, RGBA): белые узоры с альфой, цвет даёт цвет вершин.
#   0 — бахрома/ворс: частые волнистые нити со скруглёнными светлыми кончиками (актинии, кожистый, столовая)
#   1 — перо: стержень с пиннулами (морская лилия)
#   2 — гроздь полипов: звёздочки-полипы на комке (мягкий коралл Dendronephthya)
#   3 — щетина: короткие шипики (кустовая/открытая акропора, кромки)
# python3 tools/model_gen/corals/gen_atlas.py assets/corals/coral_cards.png
import sys, math, random
from PIL import Image, ImageDraw, ImageFilter

S = 512
SS = 2   # суперсэмплинг

def tile_fringe(rnd):
	im = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	W = S * SS
	n = 42
	for i in range(n):
		x0 = (i + rnd.uniform(0.15, 0.85)) / n * W
		h = rnd.uniform(0.55, 0.97) * W
		w = rnd.uniform(0.016, 0.024) * W
		ph = rnd.uniform(0, 6.28)
		amp = rnd.uniform(0.01, 0.04) * W
		pts = []
		steps = 18
		for k in range(steps + 1):
			t = k / steps
			y = W - t * h
			x = x0 + math.sin(t * 5.0 + ph) * amp * t
			pts.append((x, y))
		for k in range(steps):
			t = k / steps
			g = int(170 + 70 * t)
			d.line([pts[k], pts[k + 1]], fill=(g, g, g, 255), width=int(w * (1.0 - 0.25 * t)))
		tx, ty = pts[-1]
		r = w * 0.75
		d.ellipse([tx - r, ty - r, tx + r, ty + r], fill=(255, 255, 250, 255))
	return im

def tile_feather(rnd):
	im = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	W = S * SS
	cx = W / 2
	# стержень
	d.line([(cx, W), (cx, W * 0.02)], fill=(200, 200, 200, 255), width=int(W * 0.05))
	n = 16
	for i in range(n):
		t = i / n
		y = W * (0.97 - t * 0.93)
		ln = W * 0.38 * (1.0 - 0.65 * t)
		for sg in (-1, 1):
			ex = cx + sg * ln
			ey = y - ln * 0.55
			mx = cx + sg * ln * 0.55
			my = y - ln * 0.15
			d.line([(cx, y), (mx, my), (ex, ey)], fill=(235, 235, 235, 255), width=int(W * 0.03))
			d.ellipse([ex - W * 0.008, ey - W * 0.008, ex + W * 0.008, ey + W * 0.008], fill=(255, 255, 255, 255))
	return im

def tile_polyps(rnd):
	im = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	W = S * SS
	for i in range(140):
		a = rnd.random() * math.tau
		r = math.sqrt(rnd.random()) * W * 0.44
		cx = W / 2 + math.cos(a) * r
		cy = W / 2 + math.sin(a) * r * 0.9
		pr = rnd.uniform(0.02, 0.04) * W
		g = int(rnd.uniform(200, 255))
		for k in range(8):
			b = k / 8 * math.tau + rnd.uniform(-.2, .2)
			ex = cx + math.cos(b) * pr * 1.8
			ey = cy + math.sin(b) * pr * 1.8
			d.line([(cx, cy), (ex, ey)], fill=(g, g, g, 255), width=int(pr * 0.35))
		d.ellipse([cx - pr * 0.6, cy - pr * 0.6, cx + pr * 0.6, cy + pr * 0.6], fill=(int(g * 0.8), int(g * 0.8), int(g * 0.8), 255))
	return im

def tile_bristle(rnd):
	"""Шишковатые веточки акропоры: тонкие сужающиеся побеги с боковыми почками и светлыми
	кончиками; между побегами — прозрачные промежутки (без сплошного основания)."""
	im = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	W = S * SS
	n = 24
	for i in range(n):
		x = (i + rnd.uniform(0.2, 0.8)) / n * W
		h = rnd.uniform(0.45, 0.92) * W
		w = rnd.uniform(0.012, 0.018) * W
		lean = rnd.uniform(-0.18, 0.18) * h
		base = W - rnd.uniform(0, 0.04) * W
		tip = (x + lean, base - h)
		d.polygon([(x - w, base), (x + w, base), (tip[0] + w * 0.35, tip[1]), (tip[0] - w * 0.35, tip[1])], fill=(205, 205, 205, 255))
		# боковые почки-кораллиты
		for k in range(rnd.randint(3, 6)):
			t = rnd.uniform(0.25, 0.9)
			px = x + lean * t; py = base - h * t
			sg = rnd.choice((-1, 1))
			ln = rnd.uniform(0.03, 0.06) * W
			ex = px + sg * ln * 0.8; ey = py - ln * 0.6
			d.line([(px, py), (ex, ey)], fill=(220, 220, 220, 255), width=int(w * 1.1))
			r = w * 0.8
			d.ellipse([ex - r, ey - r, ex + r, ey + r], fill=(245, 242, 235, 255))
		r = w * 1.1
		d.ellipse([tip[0] - r, tip[1] - r, tip[0] + r, tip[1] + r], fill=(252, 250, 244, 255))
	return im

def main():
	out = sys.argv[1] if len(sys.argv) > 1 else "coral_cards.png"
	rnd = random.Random(7)
	atlas = Image.new("RGBA", (S * 2, S * 2), (0, 0, 0, 0))
	for idx, fn in enumerate([tile_fringe, tile_feather, tile_polyps, tile_bristle]):
		t = fn(rnd).resize((S, S), Image.LANCZOS)
		# кромка альфы «выращивается» цветом, чтобы мипы не темнели по краям
		rgb = t.convert("RGB").filter(ImageFilter.MaxFilter(5))
		a = t.getchannel("A")
		t2 = Image.merge("RGBA", (*rgb.split(), a))
		atlas.paste(t2, ((idx % 2) * S, (idx // 2) * S))
	atlas.save(out)

main()
