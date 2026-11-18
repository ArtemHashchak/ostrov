#!/usr/bin/env python3
"""Запекание зацикленной FFT-волны (Тессендорф) для океана «Островов».

Один раз при разработке: спектр Филлипса -> поле высот/наклонов/якобиана на
периодической плитке L×L м, кадры по зацикленному периоду T (частоты квантованы,
поэтому последний кадр плавно переходит в первый). Результат — атлас кадров
COLS×ROWS по N×N px (RGBA8):
  R, G — наклон dh/dx, dh/dz (0.5 = 0),  B — высота (0.5 = 0),  A — пена (якобиан).
Масштабы пишутся в fft_meta.json и fft_meta.gd (его читает Ocean.gd — экспортируется).

  python3 tools/bake_ocean_fft.py  ->  assets/ocean/fft_atlas.png, fft_meta.json
"""
import json, math, os
import numpy as np
from PIL import Image

N = 128            # разрешение плитки
L = 24.0           # размер плитки, м
FRAMES = 32
COLS, ROWS = 8, 4
T = 8.0            # период цикла, с
WIND = np.array([1.0, 0.35]); WIND /= np.linalg.norm(WIND)
V = 7.5            # ветер, м/с (мелкая зыбь поверх больших волн Герстнера)
A = 4.0e-4
CHOP = 1.1
G = 9.81
rng = np.random.default_rng(1729)

k1 = 2.0 * math.pi * np.fft.fftfreq(N, d=L / N)
kx, kz = np.meshgrid(k1, k1, indexing="xy")
k = np.sqrt(kx ** 2 + kz ** 2)
k_safe = np.where(k == 0, 1.0, k)
Lw = V * V / G
kd = (kx * WIND[0] + kz * WIND[1]) / k_safe
ph = A * np.exp(-1.0 / (k_safe * Lw) ** 2) / k_safe ** 4 * np.abs(kd) ** 2.5
ph *= np.exp(-(k_safe * 0.02) ** 2)          # срез ряби короче ~6 см
ph[kd < 0] *= 0.15                              # встречные волны слабее
ph[k == 0] = 0.0
h0 = (rng.normal(size=(N, N)) + 1j * rng.normal(size=(N, N))) / math.sqrt(2) * np.sqrt(ph / 2)
h0m = np.conj(np.roll(np.flip(h0), 1, axis=(0, 1)))   # h0*(-k)
w0 = 2.0 * math.pi / T
om = np.round(np.sqrt(G * k) / w0) * w0               # квантование -> точный цикл

frames = []
for f in range(FRAMES):
	t = T * f / FRAMES
	ht = h0 * np.exp(1j * om * t) + h0m * np.exp(-1j * om * t)
	h = np.real(np.fft.ifft2(ht)) * N * N
	sx = np.real(np.fft.ifft2(1j * kx * ht)) * N * N
	sz = np.real(np.fft.ifft2(1j * kz * ht)) * N * N
	dx = np.real(np.fft.ifft2(-1j * kx / k_safe * ht)) * N * N
	dz = np.real(np.fft.ifft2(-1j * kz / k_safe * ht)) * N * N
	jxx = 1 + CHOP * np.real(np.fft.ifft2(kx * kx / k_safe * ht)) * N * N
	jzz = 1 + CHOP * np.real(np.fft.ifft2(kz * kz / k_safe * ht)) * N * N
	jxz = CHOP * np.real(np.fft.ifft2(kx * kz / k_safe * ht)) * N * N
	jac = jxx * jzz - jxz * jxz
	frames.append((h, sx, sz, jac))

hmax = max(np.abs(fr[0]).max() for fr in frames)
smax = max(max(np.abs(fr[1]).max(), np.abs(fr[2]).max()) for fr in frames)
atlas = np.zeros((ROWS * N, COLS * N, 4), dtype=np.uint8)
for f, (h, sx, sz, jac) in enumerate(frames):
	r, c = divmod(f, COLS)
	foam = np.clip((1.0 - jac) * 2.2, 0.0, 1.0)
	px = np.stack([sx / smax * 0.5 + 0.5, sz / smax * 0.5 + 0.5, h / hmax * 0.5 + 0.5, foam], axis=-1)
	atlas[r * N:(r + 1) * N, c * N:(c + 1) * N] = np.clip(px * 255.0 + 0.5, 0, 255).astype(np.uint8)

out = os.path.join(os.path.dirname(__file__), "..", "assets", "ocean")
os.makedirs(out, exist_ok=True)
Image.fromarray(atlas, "RGBA").save(os.path.join(out, "fft_atlas.png"), optimize=True)
meta = {"n": N, "tile_m": L, "frames": FRAMES, "cols": COLS, "rows": ROWS, "period_s": T,
		"height_m": float(hmax), "slope": float(smax)}
json.dump(meta, open(os.path.join(out, "fft_meta.json"), "w"), indent=1)
# то же как скрипт-ресурс: попадает в экспорт (JSON без include_filter не экспортируется)
with open(os.path.join(out, "fft_meta.gd"), "w") as f:
	f.write("# Сгенерировано tools/bake_ocean_fft.py — не править руками.\n")
	f.write("extends RefCounted\n\nconst META := " + json.dumps(meta) + "\n")
print(meta)
