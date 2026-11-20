"""Камни пользователя (Rocks/Stone0XX.zip: бесшовные PBR-наборы поверхности камня, без сеток) →
assets/user_pack/rocks/tex/<set>_{albedo,normal,orh}.png (1024, общие для всех валунов).
    python3 -I tools/user_pack2/stones_prep.py SRC_DIR OUT_DIR
Архивы неполные: где нет нормали/высоты/шероховатости — восстанавливаем:
  высота  ← AO и высокочастотная яркость диффуза; нормаль ← градиент высоты (OpenGL, как у исходников:
  проверено корреляцией dH/dстрока с G < 0); шероховатость ← 1 − Glossiness.
orh: R — AO, G — шероховатость, B — высота."""
import sys, os, glob
import numpy as np
from PIL import Image, ImageFilter
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
SETS = ["Stone002", "Stone004", "Stone005", "Stone006", "Stone007"]
R = 1024

def find(s, key):
    for res in ("2k", "4k"):
        f = glob.glob(os.path.join(src, s, res, f"{s}_{key}.png"))
        if f:
            return f[0]
    return None

def load(path, mode):
    im = Image.open(path)
    if im.mode.startswith("I"):
        # 16-битные карты (шероховатость/высота): без обрезки до 255
        a = np.asarray(im).astype(np.float32) / 65535.0
        f = Image.fromarray(a, "F").resize((R, R), Image.LANCZOS)
        return f if mode == "F" else Image.fromarray(np.clip(np.asarray(f) * 255 + 0.5, 0, 255).astype(np.uint8), "L")
    return im.convert(mode).resize((R, R), Image.LANCZOS)

def wrap_blur(a, r):
    # бесшовное (периодическое) гауссово размытие через БПФ
    fy = np.fft.fftfreq(a.shape[0])[:, None]
    fx = np.fft.fftfreq(a.shape[1])[None, :]
    g = np.exp(-2.0 * (np.pi * r) ** 2 * (fx * fx + fy * fy))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g)).astype(np.float32)

for s in SETS:
    alb = load(find(s, "Diffuse"), "RGB")
    alb.save(os.path.join(out, f"{s.lower()}_albedo.png"))
    a = np.asarray(alb).astype(np.float32) / 255.0
    lum = a @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    ao_p = find(s, "Ambient Occlusion")
    ao = np.asarray(load(ao_p, "L")).astype(np.float32) / 255.0 if ao_p else np.ones((R, R), np.float32)
    hp = find(s, "Height")
    if hp:
        h = np.asarray(load(hp, "F")).astype(np.float32)
        h = (h - h.min()) / max(1e-6, h.max() - h.min())
        hsrc = "исходник"
    else:
        # AO хорошо повторяет рельеф (впадины тёмные); добавляем мелкую деталь яркости
        hf = lum - wrap_blur(lum, 6.0)
        h = wrap_blur(ao, 1.2) * 0.75 + hf * 1.5 + 0.25
        h = (h - h.min()) / max(1e-6, h.max() - h.min())
        hsrc = "из AO+яркости"
    rp, gp = find(s, "Roughness"), find(s, "Glossiness")
    if rp:
        rough = np.asarray(load(rp, "L")).astype(np.float32) / 255.0
    else:
        rough = 1.0 - np.asarray(load(gp, "L")).astype(np.float32) / 255.0
    # камень под открытым небом (выветренный, в соли и пыли): медиана шероховатости → 0.8, разброс сохраняется
    rough = np.clip(0.8 + (rough - np.median(rough)) * 0.8, 0.45, 1.0)
    np_ = find(s, "Normal")
    if np_:
        nrm = load(np_, "RGB")
        nsrc = "исходник"
    else:
        hh = h * 6.0
        gx = (np.roll(hh, -1, 1) - np.roll(hh, 1, 1)) * 0.5
        gy = (np.roll(hh, -1, 0) - np.roll(hh, 1, 0)) * 0.5
        # OpenGL: G вверх по картинке; строка растёт вниз → G = +dH/dстрока... с минусом как у исходников
        n = np.dstack([-gx, gy, np.ones_like(hh)])
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        nrm = Image.fromarray(np.clip((n * 0.5 + 0.5) * 255 + 0.5, 0, 255).astype(np.uint8), "RGB")
        nsrc = "из высоты"
    nrm.save(os.path.join(out, f"{s.lower()}_normal.png"))
    orh = np.dstack([ao, rough, h])
    Image.fromarray(np.clip(orh * 255 + 0.5, 0, 255).astype(np.uint8), "RGB").save(os.path.join(out, f"{s.lower()}_orh.png"))
    print(s, "lum %.2f" % lum.mean(), "rough %.2f" % rough.mean(), "высота", hsrc, "нормаль", nsrc)
