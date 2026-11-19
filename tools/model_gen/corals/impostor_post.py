# Постобработка атласов импосторов: «растекание» цвета в прозрачные области (без тёмной каймы на
# мипмапах), уменьшение 2× с суперсэмплингом, запись в assets + мета в GDScript (экспортируется сама).
#   python3 tools/model_gen/corals/impostor_post.py /tmp/c4/imp assets/corals/impostors
import sys, os, json
import numpy as np
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
meta = json.load(open(os.path.join(src, "meta.json")))


def dilate(rgb, a, passes=24):
	"""Заполнить RGB прозрачных пикселей средним соседей с покрытием (итеративно)."""
	rgb = rgb.copy(); filled = a > 0.02
	for _ in range(passes):
		if filled.all():
			break
		acc = np.zeros_like(rgb); cnt = np.zeros(filled.shape, np.float32)
		for dy in (-1, 0, 1):
			for dx in (-1, 0, 1):
				if dx == 0 and dy == 0:
					continue
				sh_f = np.roll(np.roll(filled, dy, 0), dx, 1)
				sh_c = np.roll(np.roll(rgb, dy, 0), dx, 1)
				acc += sh_c * sh_f[..., None]
				cnt += sh_f
		new = (~filled) & (cnt > 0)
		rgb[new] = acc[new] / cnt[new][:, None]
		filled = filled | new
	return rgb


for key, m in meta.items():
	for kind in ("albedo", "normal"):
		im = np.asarray(Image.open(os.path.join(src, "%s_%s.png" % (key, kind))).convert("RGBA")).astype(np.float32) / 255.0
		rgb, a = im[..., :3], im[..., 3]
		if kind == "normal":
			# альфа нормали = альфа альбедо (покрытие одинаковое)
			alb = np.asarray(Image.open(os.path.join(src, "%s_albedo.png" % key)).convert("RGBA")).astype(np.float32) / 255.0
			a = alb[..., 3]
		rgb = dilate(rgb, a)
		h, w = a.shape
		# уменьшение 2×: цвет — среднее, альфа — среднее (покрытие)
		rgb2 = rgb.reshape(h // 2, 2, w // 2, 2, 3).mean(axis=(1, 3))
		a2 = a.reshape(h // 2, 2, w // 2, 2).mean(axis=(1, 3))
		out = np.concatenate([rgb2, a2[..., None]], axis=2)
		Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(dst, "%s_%s.png" % (key, kind)))
	print("ok", key)

with open(os.path.join(dst, "impostor_meta.gd"), "w") as f:
	f.write("class_name CoralImpostorMeta\nextends RefCounted\n## Сгенерировано tools/model_gen/corals/impostor_post.py — не править руками.\n")
	f.write("## Импосторы кораллов: центр и радиус ограничивающей сферы (координаты модели), кадров N×N.\n\n")
	f.write("const DATA := {\n")
	for key, m in meta.items():
		c = m["center"]
		f.write('\t"%s": {"center": Vector3(%.4f, %.4f, %.4f), "radius": %.4f, "frames": %d},\n' % (key, c[0], c[1], c[2], m["radius"], m["frames"]))
	f.write("}\n")
print("meta", len(meta))
