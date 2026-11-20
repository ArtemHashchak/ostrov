"""Снимки мшистой земли (mossy_render.py; нужен pip-модуль openexr) → бесшовные текстуры слоя подлеска в рельефе:
assets/textures/mossy_ground/mossy_ground_{albedo,normal,rhm}.png (1024).
    python3 -I tools/user_pack2/mossy_pack.py RENDER_DIR OUT_DIR REF_ALBEDO
  • бесшовность: тайл смешивается со своей копией, сдвинутой на полпериода, по маске «центр — 1,
    края — 0» (шов копии уходит в центр, где виден оригинал); маска с шумом — без ровного креста;
  • цвет: исходник очень тёмный (лин. альбедо ~0.02 — мох автора рассчитан на подсветку SSS);
    медианная яркость приводится к опаду подлеска (REF_ALBEDO, forest_leaves_02), оттенок сохраняется;
  • высота: мох = 0.55 + 0.45·его рельеф, грязь = её шум; смешение по маске мха; нормаль (OpenGL)
    из высоты с периодическими разностями;
  • rhm: R — шероховатость (мох 0.9, грязь 0.78 ± шум), G — высота, B — маска мха."""
import sys, os
import numpy as np
import cv2
from PIL import Image
src, out, ref = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)
R = 1024

def to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

def to_srgb(l):
    l = np.clip(l, 0, 1)
    return np.where(l <= 0.0031308, l * 12.92, 1.055 * l ** (1 / 2.4) - 0.055)

col = np.asarray(Image.open(os.path.join(src, "mossy_color.png")).convert("RGB")).astype(np.float32) / 255.0
import OpenEXR
dat = np.asarray(OpenEXR.File(os.path.join(src, "mossy_data.exr")).parts[0].channels["RGB"].pixels, np.float32)
n = col.shape[0]
rng = np.random.default_rng(7)

def periodic_mask(n):
    # 1 в центре, 0 у краёв, граница рваная (низкочастотный шум)
    y, x = np.mgrid[0:n, 0:n] / n
    d = np.minimum(np.minimum(x, 1 - x), np.minimum(y, 1 - y))   # 0 у края, 0.5 в центре
    noise = cv2.GaussianBlur(rng.random((n, n)).astype(np.float32), (0, 0), n / 40)
    noise = (noise - noise.mean()) / (noise.std() + 1e-6) * 0.035
    return np.clip((d + noise - 0.06) / 0.14, 0, 1)

M = periodic_mask(n)[..., None]

def seamless(a):
    sh = np.roll(np.roll(a, n // 2, 0), n // 2, 1)
    return a * M + sh * (1 - M)

col = seamless(col)
dat = seamless(dat)
# цвет: медианная линейная яркость → как у опада подлеска
lin = to_lin(col)
L = lin @ np.array([0.2126, 0.7152, 0.0722], np.float32)
ref_lin = to_lin(np.asarray(Image.open(ref).convert("RGB").resize((256, 256))).astype(np.float32) / 255.0)
ref_L = np.median(ref_lin @ np.array([0.2126, 0.7152, 0.0722], np.float32))
k = ref_L / max(np.median(L), 1e-5)
lin = np.clip(lin * k, 0, 0.6)
# грязь автора очень оранжевая: темнее и в бурый (сырая лесная земля); мох — насыщеннее и зеленее.
# маска мха из снимка данных (тот же кадр), до бесшовной склейки уже применена к обоим
mk = np.clip(dat[..., 0], 0, 1)[..., None]
Lk = (lin @ np.array([0.2126, 0.7152, 0.0722], np.float32))[..., None]
dirt = (Lk + (lin - Lk) * 0.6) * np.array([0.82, 0.74, 0.62], np.float32)
moss = np.clip((Lk + (lin - Lk) * 1.35) * np.array([0.85, 1.05, 0.7], np.float32), 0, 1)
lin = dirt * (1 - mk) + moss * mk
print("яркость: медиана %.4f → %.4f (×%.1f)" % (np.median(L), ref_L, k))
alb = (to_srgb(lin) * 255 + 0.5).astype(np.uint8)
Image.fromarray(alb).resize((R, R), Image.LANCZOS).save(os.path.join(out, "mossy_ground_albedo.png"))
mask = np.clip(dat[..., 0], 0, 1)
h_dirt = np.clip(dat[..., 1], 0, 1)
h_moss = np.clip(dat[..., 2], 0, 1)
h = h_dirt * (1 - mask) + (0.55 + 0.45 * h_moss) * mask
h = cv2.resize(h, (R, R), interpolation=cv2.INTER_AREA)
mask_r = cv2.resize(mask, (R, R), interpolation=cv2.INTER_AREA)
# нормаль: периодические разности; 1 тайл ≈ 2.4 м (как на снимке), глубина рельефа ~2 см
tile_m = 2.4
px = tile_m / R
depth = 0.02
gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * depth / (2 * px)
gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * depth / (2 * px)
nn = np.dstack([-gx, gy, np.ones_like(h)])
nn /= np.linalg.norm(nn, axis=2, keepdims=True)
Image.fromarray(((nn * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8)).save(os.path.join(out, "mossy_ground_normal.png"))
noise = cv2.GaussianBlur(rng.random((R, R)).astype(np.float32), (0, 0), 3) - 0.5
rough = np.clip(0.78 * (1 - mask_r) + 0.9 * mask_r + noise * 0.15, 0.5, 1.0)
rhm = np.dstack([rough, h, mask_r])
Image.fromarray((np.clip(rhm, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(out, "mossy_ground_rhm.png"))
print("маска мха: доля %.2f; высота %.2f..%.2f" % (mask_r.mean(), h.min(), h.max()))
