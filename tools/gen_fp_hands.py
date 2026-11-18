#!/usr/bin/env python3
"""Генератор меша рук от первого лица (правая рука; левая — зеркало в игре).

Рука описана как поле расстояний (SDF): кости-«капсулы» фаланг, пястные кости,
мышечные подушки ладони (тенар/гипотенар), запястье и предплечье, сухожилия и
вены на тыльной стороне, ногти. Всё сливается гладким минимумом (smin), поэтому
поверхность цельная, без стыков. Поверхность извлекается marching cubes,
упрощается (quadric), нормали — градиент SDF. Для каждой вершины считаются веса
костей (по близости к примитивам кости), цвет кожи и запечённое затенение (AO).
Рукав с закатанным краем — отдельная поверхность (лофт по предплечью).

Результат: assets/models/fp_hands/fp_arm.json — кости (глобальные rest-матрицы в
пространстве кисти: запястье в 0, пальцы по -Z, тыл ладони +Y, большой палец -X)
и поверхности (base64 float32/int32). Сборка в Godot — scripts/player/fp_hands.gd.

Запуск: python3 -I tools/gen_fp_hands.py  (нужны numpy, scikit-image, fast-simplification)
"""
import base64
import json
import math
import os
import sys

import numpy as np
from skimage.measure import marching_cubes
import fast_simplification

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "models", "fp_hands", "fp_arm.json")
VOX = 0.0009          # шаг сетки marching cubes, м
TARGET_TRIS = 9000    # треугольников кожи после упрощения

f32 = np.float32


def nrm(v):
    v = np.asarray(v, dtype=np.float64)
    return v / np.linalg.norm(v)


def rot(axis, ang):
    """Матрица поворота вокруг оси (рад)."""
    a = nrm(axis)
    c, s = math.cos(ang), math.sin(ang)
    x, y, z = a
    return np.array([
        [c + x * x * (1 - c), x * y * (1 - c) - z * s, x * z * (1 - c) + y * s],
        [y * x * (1 - c) + z * s, c + y * y * (1 - c), y * z * (1 - c) - x * s],
        [z * x * (1 - c) - y * s, z * y * (1 - c) + x * s, c + z * z * (1 - c)],
    ])


# ----------------------------------------------------------------- SDF-примитивы

def sd_round_cone(p, a, b, r1, r2):
    """Конус со скруглёнными концами (iq). p: (N,3)."""
    a = np.asarray(a, f32)
    b = np.asarray(b, f32)
    ba = b - a
    l2 = float(ba @ ba)
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    pa = p - a
    y = pa @ ba
    z = y - l2
    xv = pa * l2 - np.outer(y, ba)
    x2 = np.einsum("ij,ij->i", xv, xv)
    y2 = y * y * l2
    z2 = z * z * l2
    k = math.copysign(1.0, rr) * rr * rr * x2
    out = (np.sqrt(x2 * a2 * il2) + y * rr) * il2 - r1
    m1 = np.sign(z) * a2 * z2 > k
    m2 = np.sign(y) * a2 * y2 < k
    out = np.where(m1, np.sqrt(x2 + z2) * il2 - r2, out)
    out = np.where(~m1 & m2, np.sqrt(x2 + y2) * il2 - r1, out)
    return out.astype(f32)


def sd_ellipsoid(p, c, r, basis=None):
    """Эллипсоид (приближение iq). basis — столбцы = оси эллипсоида."""
    q = p - np.asarray(c, f32)
    if basis is not None:
        q = q @ np.asarray(basis, f32)
    r = np.asarray(r, f32)
    k0 = np.linalg.norm(q / r, axis=1)
    k1 = np.linalg.norm(q / (r * r), axis=1)
    return (k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)).astype(f32)


def sd_flat_cone(p, a, b, r1, r2, sx, sy, up):
    """Скруглённый конус со сплюснутым сечением: sx — ширина, sy — толщина."""
    a = np.asarray(a, f32)
    z = nrm(np.asarray(a) - np.asarray(b))
    y = nrm(np.asarray(up) - z * float(np.dot(up, z)))
    x = np.cross(y, z)
    B = np.stack([x, y, z], axis=1).astype(f32)
    q = (p - a) @ B
    q = q / np.array([sx, sy, 1.0], f32)
    L = float(np.linalg.norm(np.asarray(b) - a))
    return sd_round_cone(q, (0, 0, 0), (0, 0, -L), r1, r2) * min(sx, sy)


def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * k * 0.25


# ----------------------------------------------------------------- скелет

class Bone:
    def __init__(self, name, parent, origin, fwd, up):
        self.name = name
        self.parent = parent
        z = -nrm(fwd)                      # кость смотрит по -Z
        y = nrm(np.asarray(up) - z * float(np.dot(up, z)))
        x = np.cross(y, z)
        self.basis = np.stack([x, y, z], axis=1)
        self.origin = np.asarray(origin, dtype=np.float64)

    @property
    def fwd(self):
        return -self.basis[:, 2]

    @property
    def up(self):
        return self.basis[:, 1]

    @property
    def side(self):
        return self.basis[:, 0]


bones: list = []
bone_idx: dict = {}


def add_bone(name, parent, origin, fwd, up):
    b = Bone(name, parent, origin, fwd, up)
    bone_idx[name] = len(bones)
    bones.append(b)
    return b


# Примитивы: (sdf-функция от p, группа, кость)
class Prim:
    def __init__(self, fn, bone, group, k=0.0, weight=True):
        self.fn = fn
        self.bone = bone_idx[bone]
        self.group = group
        self.k = k
        self.weight = weight


prims: list = []

FORE_DIR = nrm((0.0, -0.24, 0.97))     # от запястья к локтю
UP = np.array([0.0, 1.0, 0.0])

add_bone("forearm", -1, (0, 0, 0.30) + 0 * FORE_DIR, -FORE_DIR, UP)
bones[0].origin = np.asarray(FORE_DIR * 0.30)
add_bone("hand", 0, (0, 0, 0), (0, 0.03, -1), UP)

# Предплечье: от запястья назад, сечение — сплюснутый эллипс у запястья, круглее у локтя.
ELBOW = FORE_DIR * 0.30
prims.append(Prim(lambda p: sd_flat_cone(p, (0, 0.0, 0.004), FORE_DIR * 0.075, 0.0245, 0.0295, 1.24, 0.82, UP),
                  "forearm", "arm"))
prims.append(Prim(lambda p: sd_flat_cone(p, FORE_DIR * 0.06, ELBOW * 0.62, 0.031, 0.040, 1.14, 0.88, UP),
                  "forearm", "arm", k=0.02))
# Плечелучевая мышца (сверху со стороны большого пальца) и сгибатели снизу.
prims.append(Prim(lambda p: sd_ellipsoid(p, FORE_DIR * 0.17 + np.array([-0.018, 0.016, 0]), (0.02, 0.017, 0.075),
                                         np.stack([(1, 0, 0), nrm(np.cross(FORE_DIR, (1, 0, 0))), FORE_DIR], 1)),
                  "forearm", "arm", k=0.02))
prims.append(Prim(lambda p: sd_ellipsoid(p, FORE_DIR * 0.16 + np.array([0.006, -0.018, 0]), (0.03, 0.016, 0.08),
                                         np.stack([(1, 0, 0), nrm(np.cross(FORE_DIR, (1, 0, 0))), FORE_DIR], 1)),
                  "forearm", "arm", k=0.02))
# Головка локтевой кости — бугорок у запястья со стороны мизинца.
prims.append(Prim(lambda p: sd_ellipsoid(p, (0.026, 0.006, 0.016), (0.008, 0.009, 0.01)), "forearm", "arm", k=0.01))

# Запястье/пясть: блок запястья + 4 пястные кости + подушки ладони.
prims.append(Prim(lambda p: sd_ellipsoid(p, (0.0, 0.0, -0.016), (0.03, 0.0165, 0.024)), "hand", "palm"))
META = {
    "index": ((-0.017, 0.006, -0.026), (-0.0265, 0.0045, -0.088), 0.0088, 0.0102),
    "middle": ((-0.004, 0.007, -0.027), (-0.0065, 0.0063, -0.0925), 0.0088, 0.0104),
    "ring": ((0.009, 0.006, -0.026), (0.0135, 0.0035, -0.0868), 0.0083, 0.0097),
    "pinky": ((0.02, 0.003, -0.023), (0.0315, -0.0012, -0.0772), 0.0078, 0.0088),
}
for nm, (a, b, r1, r2) in META.items():
    prims.append(Prim(lambda p, a=a, b=b, r1=r1, r2=r2: sd_round_cone(p, a, b, r1, r2), "hand", "palm"))
# Подушка ладони, гипотенар (под мизинцем), тенар (у большого пальца), подушка под пястно-фаланговыми.
prims.append(Prim(lambda p: sd_ellipsoid(p, (0.002, -0.0075, -0.058), (0.033, 0.0095, 0.03)), "hand", "palm"))
prims.append(Prim(lambda p: sd_ellipsoid(p, (0.022, -0.008, -0.04), (0.0125, 0.0115, 0.031)), "hand", "palm"))
prims.append(Prim(lambda p: sd_ellipsoid(p, (-0.021, -0.011, -0.033), (0.016, 0.0135, 0.027),
                                         rot((0, 1, 0), 0.5)), "hand", "palm"))
prims.append(Prim(lambda p: sd_round_cone(p, (-0.025, -0.0055, -0.084), (0.029, -0.0085, -0.074), 0.0085, 0.0078),
                  "hand", "palm"))

PALM_K = 0.012

# Пальцы: длины фаланг, радиусы, разведение (рад) и сгиб в покое (град: пястно-фаланговый, средний, дистальный).
FINGERS = {
    #        длины фаланг              радиусы (основание→кончик)        разведение  сгиб
    "index": ((0.041, 0.0245, 0.0195), (0.0094, 0.0086, 0.0078, 0.0071), -0.10, (12, 16, 8)),
    "middle": ((0.0455, 0.0285, 0.0205), (0.0097, 0.0089, 0.008, 0.0073), -0.01, (12, 17, 8)),
    "ring": ((0.0425, 0.027, 0.0195), (0.009, 0.0083, 0.0076, 0.0069), 0.09, (13, 18, 9)),
    "pinky": ((0.0335, 0.0195, 0.0178), (0.008, 0.0073, 0.0066, 0.006), 0.2, (15, 20, 10)),
}

nail_prims = []


def build_finger(nm, base, lens, radii, spread, flex, parent="hand", up0=UP, fwd0=(0, 0, -1), thumb=False):
    fwd = rot(up0, -spread) @ nrm(fwd0)
    up = nrm(np.asarray(up0) - fwd * float(np.dot(up0, fwd)))
    pos = np.asarray(base, dtype=np.float64)
    par = parent
    names = []
    for i, L in enumerate(lens):
        side = np.cross(up, -fwd)            # ось сгиба (X кости)
        R = rot(side, -math.radians(flex[i]))
        fwd = R @ fwd
        up = R @ up
        bn = f"{nm}{i + 1}"
        add_bone(bn, bone_idx[par] if isinstance(par, str) else par, pos, fwd, up)
        names.append(bn)
        a = pos.copy()
        b = pos + fwd * L
        r1, r2 = radii[i], radii[i + 1]
        last = i == len(lens) - 1
        if last:
            # Кончик пальца: подушечка снизу полнее, ноготь сверху.
            prims.append(Prim(lambda p, a=a, b=b - fwd * r2 * 0.55, r1=r1, r2=r2: sd_round_cone(p, a, b, r1, r2),
                              bn, "finger"))
            pad_c = a + fwd * L * 0.55 - up * r2 * 0.28
            Bp = np.stack([np.cross(up, -fwd), up, -fwd], 1)
            prims.append(Prim(lambda p, c=pad_c, r=(r2 * 1.05, r2 * 0.85, L * 0.4), B=Bp: sd_ellipsoid(p, c, r, B),
                              bn, "finger", k=0.004))
            nc = a + fwd * L * 0.56 + up * r2 * 0.66
            nr = (r2 * 0.80, 0.0019, L * 0.37)
            nail_prims.append(len(prims))
            prims.append(Prim(lambda p, c=nc, r=nr, B=Bp: sd_ellipsoid(p, c, r, B), bn, "nail", k=0.0014))
        else:
            prims.append(Prim(lambda p, a=a, b=b, r1=r1, r2=r2: sd_round_cone(p, a, b, r1, r2), bn, "finger"))
            # Костяшка межфалангового сустава (тыл) и складка снизу.
            kc = b + up * r2 * 0.36
            prims.append(Prim(lambda p, c=kc, r=r2 * 0.66: sd_ellipsoid(p, c, (r * 1.05, r, r)), bn, "finger",
                              k=0.004))
        pos = b
        par = bn
    return names


for nm, (lens, radii, spread, flex) in FINGERS.items():
    base = META[nm][1]
    # Пальцы начинаются у головки пястной кости (чуть вперёд и ниже — сустав внутри).
    build_finger(nm, np.asarray(base) + np.array([0, -0.0015, -0.002]), lens, radii, spread, flex)

# Большой палец: пястная кость от основания ладони, ноготь смотрит наружу-вверх.
T_BASE = np.array([-0.019, -0.0075, -0.012])
T_DIR = nrm((-0.62, -0.30, -0.72))
T_UP = nrm((-0.55, 0.8, -0.1))
thumb_names = build_finger("thumb", T_BASE, (0.044, 0.032, 0.0285), (0.0128, 0.0112, 0.0101, 0.0083), 0.0,
                           (0, 10, 14), up0=T_UP, fwd0=T_DIR, thumb=True)
# Мышца между большим и указательным (тыл) — даёт перепонку.
prims.append(Prim(lambda p: sd_round_cone(p, (-0.02, 0.0, -0.03), (-0.04, -0.006, -0.05), 0.0085, 0.0062),
                  "hand", "palm"))

# ------------------------------------------------------------ сборка поля

GROUP_ORDER = ["arm", "palm", "finger", "nail"]


def field(p, return_parts=False):
    """SDF всей руки. С return_parts — ещё и расстояния до каждого примитива."""
    parts = [pr.fn(p) for pr in prims]
    # Ладонь и предплечье — одним гладким слиянием.
    arm = None
    palm = None
    for pr, d in zip(prims, parts):
        if pr.group == "arm":
            arm = d if arm is None else smin(arm, d, pr.k or 0.02)
        elif pr.group == "palm":
            palm = d if palm is None else smin(palm, d, PALM_K)
    total = smin(palm, arm, 0.022)
    # Пальцы — каждый отдельно (жёсткое слияние фаланг с мягкими суставами), затем к ладони.
    fingers = {}
    for pr, d in zip(prims, parts):
        if pr.group in ("finger", "nail"):
            key = bones[pr.bone].name.rstrip("123")
            cur = fingers.get(key)
            k = pr.k if pr.k > 0 else 0.0045
            fingers[key] = d if cur is None else smin(cur, d, k)
    for key in ["thumb", "index", "middle", "ring", "pinky"]:
        total = smin(total, fingers[key], 0.011 if key == "thumb" else 0.0068)
    if return_parts:
        return total, parts
    return total


# Сухожилия и вены на тыльной стороне: тонкие валики, лежащие на поверхности.

def project_to_surface(pts, n=6):
    pts = np.asarray(pts, f32).copy()
    for _ in range(n):
        d = field(pts)
        g = gradient(pts)
        pts = pts - g * d[:, None]
    return pts


def gradient(p, e=0.0004):
    gx = field(p + [e, 0, 0]) - field(p - [e, 0, 0])
    gy = field(p + [0, e, 0]) - field(p - [0, e, 0])
    gz = field(p + [0, 0, e]) - field(p - [0, 0, e])
    g = np.stack([gx, gy, gz], 1)
    return (g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)).astype(f32)


def add_ridge(points, r0, r1, sink, bone, group="palm", k=0.003):
    """Валик вдоль кривой по поверхности (вена, сухожилие)."""
    pts = np.asarray(points, f32)
    # Сгущаем точки кривой.
    dense = []
    for i in range(len(pts) - 1):
        for t in np.linspace(0, 1, 8, endpoint=False):
            dense.append(pts[i] * (1 - t) + pts[i + 1] * t)
    dense.append(pts[-1])
    dense = np.asarray(dense, f32)
    surf = project_to_surface(dense + np.array([0, 0.02, 0], f32))
    nn = gradient(surf)
    centers = surf - nn * sink
    ridge = []
    m = len(centers)
    for i in range(m - 1):
        t0 = i / (m - 1)
        t1 = (i + 1) / (m - 1)
        ra = r0 + (r1 - r0) * t0
        rb = r0 + (r1 - r0) * t1
        ridge.append((centers[i].copy(), centers[i + 1].copy(), ra, rb))
    return ridge, bone, group, k


ridges = []
# Сухожилия разгибателей: от запястья к костяшкам.
for nm in ["index", "middle", "ring", "pinky"]:
    head = np.asarray(META[nm][1])
    start = np.array([head[0] * 0.35, 0.012, -0.012])
    mid = start * 0.5 + head * 0.5
    ridges.append(add_ridge([start, mid, head + [0, 0, 0.012]], 0.0021, 0.0017, 0.0011, "hand"))
# Вены: на тыле кисти и на предплечье (со стороны большого пальца).
ridges.append(add_ridge([(-0.008, 0.012, 0.02), (-0.011, 0.012, -0.005), (-0.016, 0.01, -0.03), (-0.021, 0.008, -0.05)],
                        0.0014, 0.0011, 0.0008, "hand", k=0.004))
ridges.append(add_ridge([(-0.011, 0.012, -0.015), (0.002, 0.012, -0.04), (0.012, 0.009, -0.058)],
                        0.0011, 0.0009, 0.0006, "hand", k=0.004))
ridges.append(add_ridge([(-0.016, 0.012, 0.04), (-0.022, 0.0, 0.09), (-0.024, -0.01, 0.15)],
                        0.0015, 0.0017, 0.0009, "forearm", k=0.006))

base_field = field


def ridge_prims():
    out = []
    for segs, bone, group, k in ridges:
        for a, b, ra, rb in segs:
            out.append(Prim(lambda p, a=a, b=b, ra=ra, rb=rb: sd_round_cone(p, a, b, ra, rb), bone, "ridge", k=k))
    return out


RIDGES = ridge_prims()


def field_full(p, return_parts=False):
    total, parts = field(p, True)
    for pr in RIDGES:
        d = pr.fn(p)
        total = smin(total, d, pr.k)
        parts.append(d)
    if return_parts:
        return total, parts
    return total


ALL_PRIMS = prims + RIDGES


def grad_full(p, e=0.0004):
    gx = field_full(p + [e, 0, 0]) - field_full(p - [e, 0, 0])
    gy = field_full(p + [0, e, 0]) - field_full(p - [0, e, 0])
    gz = field_full(p + [0, 0, e]) - field_full(p - [0, 0, e])
    g = np.stack([gx, gy, gz], 1)
    return (g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)).astype(f32)


# ------------------------------------------------------------ извлечение поверхности

SKIN_BACK = 0.175   # докуда тянется кожа предплечья (дальше — под рукавом)


def build_skin():
    lo = np.array([-0.085, -0.075, -0.205])
    hi = np.array([0.06, 0.045, SKIN_BACK * FORE_DIR[2] + 0.02])
    n = np.ceil((hi - lo) / VOX).astype(int) + 1
    print("сетка", n, n.prod() / 1e6, "M")
    vol = np.empty(n, f32)
    xs = lo[0] + np.arange(n[0]) * VOX
    ys = lo[1] + np.arange(n[1]) * VOX
    zs = lo[2] + np.arange(n[2]) * VOX
    # Слоями по X — экономия памяти.
    Y, Z = np.meshgrid(ys, zs, indexing="ij")
    yz = np.stack([Y.ravel(), Z.ravel()], 1).astype(f32)
    for i, x in enumerate(xs):
        p = np.concatenate([np.full((len(yz), 1), x, f32), yz], 1)
        d = field_full(p)
        # Обрезаем предплечье плоскостью за рукавом.
        s = p @ FORE_DIR.astype(f32)
        d = np.maximum(d, s - SKIN_BACK)
        vol[i] = d.reshape(n[1], n[2])
    verts, faces, _, _ = marching_cubes(vol, 0.0, spacing=(VOX, VOX, VOX))
    verts = verts + lo
    print("MC:", len(verts), "вершин", len(faces), "треугольников")
    red = 1.0 - TARGET_TRIS / len(faces)
    v2, f2 = fast_simplification.simplify(verts.astype(np.float32), faces.astype(np.int32), red, agg=6)
    print("после упрощения:", len(v2), len(f2))
    # Досадка вершин на поверхность (упрощение их сдвигает).
    v2 = v2.astype(f32)
    for _ in range(3):
        d = field_full(v2)
        s = v2 @ FORE_DIR.astype(f32)
        g = grad_full(v2)
        inside_cut = s < SKIN_BACK - 0.002
        v2[inside_cut] -= g[inside_cut] * d[inside_cut, None]
    f2 = f2.astype(np.int32)
    # Ориентация: против часовой стрелки снаружи (как у рукава и часов).
    fn = np.cross(v2[f2[:, 1]] - v2[f2[:, 0]], v2[f2[:, 2]] - v2[f2[:, 0]])
    cen = (v2[f2[:, 0]] + v2[f2[:, 1]] + v2[f2[:, 2]]) / 3.0
    if np.mean(np.einsum("ij,ij->i", fn, grad_full(cen.astype(f32)))) < 0:
        f2 = f2[:, ::-1].copy()
    return v2, f2


# ------------------------------------------------------------ атрибуты вершин

def srgb2lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def vnoise(p, scale, seed=0):
    """Гладкий 3D-шум (сумма синусов) для пятнистости кожи."""
    q = p * scale
    v = (np.sin(q[:, 0] * 1.7 + seed) * np.sin(q[:, 1] * 2.3 + seed * 1.3) * np.sin(q[:, 2] * 1.9 + seed * 0.7)
         + 0.5 * np.sin(q[:, 0] * 3.1 + q[:, 2] * 2.2 + seed) * np.sin(q[:, 1] * 3.7 - q[:, 2] * 1.3))
    return v / 1.5


def vertex_attributes(v):
    total, parts = field_full(v, True)
    D = np.stack(parts, 1)                       # (N, P)
    nrmv = grad_full(v)
    # ---- веса костей
    nb = len(bones)
    dmin = D.min(1, keepdims=True)
    sig = 0.0028
    acc = np.zeros((len(v), nb))
    for j, pr in enumerate(ALL_PRIMS):
        if pr.group == "ridge":
            continue
        acc[:, pr.bone] += np.exp(-(D[:, j:j + 1] - dmin)[:, 0] / sig)
    order = np.argsort(-acc, 1)[:, :4]
    w = np.take_along_axis(acc, order, 1)
    w = w / w.sum(1, keepdims=True)
    w[w < 0.02] = 0.0
    w = w / w.sum(1, keepdims=True)
    # ---- область: ноготь, ладонная сторона
    nail_d = D[:, nail_prims].min(1)
    other = np.delete(D, nail_prims, 1).min(1)
    nail = np.clip((other - nail_d) / 0.0007 + 0.5, 0, 1)
    # «тыльность»: нормаль против оси вверх ближайшей кости
    near_bone = order[:, 0]
    ups = np.array([b.up for b in bones])[near_bone]
    dors = np.einsum("ij,ij->i", nrmv, ups)
    # ---- запечённое затенение (AO по SDF)
    ao = np.zeros(len(v))
    for i, dl in enumerate([0.0015, 0.004, 0.008, 0.014]):
        d = field_full(v + nrmv * dl)
        ao += (dl - np.clip(d, 0, dl)) / dl * (0.5 ** i)
    ao = np.clip(1.0 - ao * 0.55, 0.35, 1.0)
    # ---- цвет кожи (загорелая, чуть грязная — неделю на острове)
    back = srgb2lin((0.70, 0.52, 0.42))
    palm = srgb2lin((0.80, 0.62, 0.54))
    redc = srgb2lin((0.74, 0.45, 0.38))
    t = np.clip(dors * 0.8 + 0.5, 0, 1)[:, None]
    col = palm * (1 - t) + back * t
    # покраснение на костяшках и кончиках пальцев
    red = np.zeros(len(v))
    for j, pr in enumerate(ALL_PRIMS):
        if pr.group == "finger":
            bn = bones[pr.bone]
            red = np.maximum(red, np.exp(-D[:, j] / 0.002) * 0.25)
    for nm in ["index", "middle", "ring", "pinky"]:
        head = np.asarray(META[nm][1]) + [0, 0.008, 0]
        red = np.maximum(red, np.exp(-np.sum((v - head) ** 2, 1) / (0.007 ** 2)) * 0.45)
        for i in (2, 3):
            b = bones[bone_idx[f"{nm}{i}"]]
            red = np.maximum(red, np.exp(-np.sum((v - b.origin - b.up * 0.007) ** 2, 1) / (0.0055 ** 2)) * 0.5)
        tip = bones[bone_idx[f"{nm}3"]]
        L = FINGERS[nm][0][2]
        red = np.maximum(red, np.exp(-np.sum((v - tip.origin - tip.fwd * L * 0.85) ** 2, 1) / (0.008 ** 2)) * 0.45)
    col = col * (1 - red[:, None] * 0.45) + redc * red[:, None] * 0.45
    # пятнистость и лёгкая грязь в складках
    spot = vnoise(v, 260.0, 1.0) * 0.06 + vnoise(v, 90.0, 4.0) * 0.05
    col = col * (1.0 + spot[:, None])
    # тыльная сторона предплечья темнее (загар)
    s = v @ FORE_DIR
    tan = np.clip((s - 0.02) / 0.1, 0, 1) * np.clip(dors, 0, 1) * 0.12
    col = col * (1 - tan[:, None])
    # ноготь: розовато-бледный, свободный край светлее
    nailc = srgb2lin((0.80, 0.62, 0.56))
    col = col * (1 - nail[:, None]) + nailc * nail[:, None]
    col = col * ao[:, None]
    # В вершинах — sRGB (Godot сам переводит цвет вершин в линейный).
    col = np.clip(col, 0, 1) ** (1 / 2.2)
    rgba = np.concatenate([col, nail[:, None]], 1).astype(f32)
    return nrmv, order.astype(np.int32), w.astype(f32), rgba, dors.astype(f32)


# ------------------------------------------------------------ рукав

def fore_radius(s, ang):
    """Радиус кожи предплечья по сечению: s — расстояние от запястья, ang — угол."""
    pts = []
    x = np.array([1.0, 0, 0])
    yv = nrm(np.cross(FORE_DIR, x))
    c = FORE_DIR * s
    dirs = np.stack([np.cos(ang), np.sin(ang)], 1)
    d3 = dirs[:, :1] * x + dirs[:, 1:] * yv
    # радиальный поиск поверхности
    r = np.full(len(ang), 0.06)
    lo = np.zeros(len(ang))
    hi = np.full(len(ang), 0.08)
    for _ in range(22):
        mid = (lo + hi) * 0.5
        p = (c + d3 * mid[:, None]).astype(f32)
        d = field_full(p)
        inside = d < 0
        lo = np.where(inside, mid, lo)
        hi = np.where(inside, hi, mid)
    return (lo + hi) * 0.5, d3, c


def build_sleeve():
    NA = 40
    ang = np.linspace(0, 2 * np.pi, NA, endpoint=False)
    S0 = 0.105    # передний край закатанного рукава
    S_END = 0.42
    # профиль: (s, добавка к радиусу)
    prof = [(S0 + 0.006, 0.0006), (S0 + 0.001, 0.0035), (S0, 0.007), (S0 + 0.002, 0.011), (S0 + 0.008, 0.0135),
            (S0 + 0.015, 0.0125), (S0 + 0.02, 0.0108), (S0 + 0.025, 0.0128), (S0 + 0.032, 0.0138),
            (S0 + 0.038, 0.0122), (S0 + 0.042, 0.0098), (S0 + 0.05, 0.0102)]
    s = S0 + 0.06
    while s < S_END:
        prof.append((s, 0.010 + (s - S0) * 0.035))
        s += 0.012
    rows = []
    uvs = []
    vlen = 0.0
    prev = None
    rng = np.random.default_rng(7)
    ph = rng.uniform(0, 6.28, 4)
    for i, (s, add) in enumerate(prof):
        ss = min(s, SKIN_BACK - 0.012)
        r, d3, _ = fore_radius(ss, ang)
        c = FORE_DIR * s
        if s > SKIN_BACK - 0.012:
            r = r + (s - ss) * 0.12
        # складки ткани: продольные и поперечные
        fold = (np.sin(ang * 3 + ph[0] + s * 30) * 0.0016 + np.sin(ang * 7 + ph[1] - s * 55) * 0.0008
                + np.sin(ang * 2 + ph[2] + s * 13) * 0.0012) * (1.0 if i > 2 else 0.3)
        # закатанная часть — валик неровный
        if s < S0 + 0.05 and i > 2:
            fold += np.sin(ang * 5 + ph[3]) * 0.0014
        rr = r + add + fold
        ring = c + d3 * rr[:, None]
        if prev is not None:
            vlen += float(np.mean(np.linalg.norm(ring - prev, axis=1)))
        prev = ring
        rows.append(ring)
        uvs.append(vlen)
    V = []
    UV = []
    for i, ring in enumerate(rows):
        for j in range(NA + 1):
            V.append(ring[j % NA])
            UV.append((j / NA * 3.0, uvs[i] * 9.0))
    V = np.asarray(V, f32)
    UV = np.asarray(UV, f32)
    F = []
    W = NA + 1
    for i in range(len(rows) - 1):
        for j in range(NA):
            a = i * W + j
            b = a + 1
            c = a + W
            d = c + 1
            F += [(a, c, b), (b, c, d)]
    F = np.asarray(F, np.int32)
    # нормали по граням
    N = np.zeros_like(V)
    fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    for k in range(3):
        np.add.at(N, F[:, k], fn)
    # шов UV: усредняем нормали дубликатов
    for i in range(len(rows)):
        a, b = i * W, i * W + NA
        n = N[a] + N[b]
        N[a] = n
        N[b] = n
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
    # наружу?
    cen = (V @ FORE_DIR)[:, None] * FORE_DIR
    if np.mean(np.einsum("ij,ij->i", N, V - cen)) < 0:
        F = F[:, ::-1].copy()
        N = -N
    # цвет: внутренняя сторона закатки и край чуть темнее
    col = np.ones((len(V), 4), f32)
    sv = V @ FORE_DIR
    dark = np.clip(1.0 - (sv - S0) / 0.004, 0, 1) * 0.35
    col[:, :3] *= (1 - dark)[:, None]
    return V, N, UV, F, col


# ------------------------------------------------------------ часы (только на левой руке в игре)

def build_watch():
    NA = 36
    ang = np.linspace(0, 2 * np.pi, NA, endpoint=False)
    S = 0.03
    r, d3, c = fore_radius(S, ang)
    rings = []
    for ds, add in [(-0.009, 0.0004), (-0.0095, 0.0022), (-0.009, 0.0032), (0.009, 0.0032), (0.0095, 0.0022),
                    (0.009, 0.0004)]:
        rr, d3b, cb = fore_radius(S + ds, ang)
        rings.append(cb + d3b * (rr + add)[:, None])
    V = []
    for ring in rings:
        V += list(ring)
    V = np.asarray(V, f32)
    F = []
    for i in range(len(rings) - 1):
        for j in range(NA):
            a = i * NA + j
            b = i * NA + (j + 1) % NA
            cc = a + NA
            d = b + NA
            F += [(a, cc, b), (b, cc, d)]
    F = np.asarray(F, np.int32)
    N = np.zeros_like(V)
    fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    for k in range(3):
        np.add.at(N, F[:, k], fn)
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
    cen = (V @ FORE_DIR)[:, None] * FORE_DIR
    if np.mean(np.einsum("ij,ij->i", N, V - cen)) < 0:
        F = F[:, ::-1].copy()
        N = -N
    # корпус — точка на тыле запястья (для сборки в игре)
    top = np.argmax(d3[:, 1])
    face_pos = c + d3[top] * (r[top] + 0.0036)
    face_up = d3[top]
    return V, N, F, face_pos, face_up


def b64(a, dt):
    return base64.b64encode(np.ascontiguousarray(a, dtype=dt).tobytes()).decode()


def main():
    v, f = build_skin()
    n, bi, bw, col, dors = vertex_attributes(v)
    sv, sn, suv, sf, scol = build_sleeve()
    wv, wn, wf, face_pos, face_up = build_watch()
    out = {
        "note": "Сгенерировано tools/gen_fp_hands.py. Пространство кисти: запястье в 0, пальцы -Z, тыл +Y.",
        "bones": [],
        "surfaces": {},
    }
    for b in bones:
        out["bones"].append({
            "name": b.name, "parent": b.parent,
            "basis": [list(map(float, b.basis[:, 0])), list(map(float, b.basis[:, 1])), list(map(float, b.basis[:, 2]))],
            "origin": list(map(float, b.origin)),
        })
    out["surfaces"]["skin"] = {
        "pos": b64(v, "<f4"), "nrm": b64(n, "<f4"), "col": b64(col, "<f4"),
        "uv": b64(np.stack([v[:, 0], v[:, 2]], 1), "<f4"),
        "uv2": b64(np.stack([v[:, 1], dors], 1), "<f4"),
        "bones": b64(bi, "<i4"), "weights": b64(bw, "<f4"), "idx": b64(f, "<i4"),
    }
    out["surfaces"]["sleeve"] = {
        "pos": b64(sv, "<f4"), "nrm": b64(sn, "<f4"), "col": b64(scol, "<f4"), "uv": b64(suv, "<f4"),
        "idx": b64(sf, "<i4"),
    }
    out["surfaces"]["watch"] = {
        "pos": b64(wv, "<f4"), "nrm": b64(wn, "<f4"), "idx": b64(wf, "<i4"),
        "face_pos": list(map(float, face_pos)), "face_up": list(map(float, face_up)),
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as fh:
        json.dump(out, fh, separators=(",", ":"))
    print("записано", OUT, os.path.getsize(OUT) // 1024, "КБ; кожа", len(v), "вершин", len(f), "треуг.; рукав",
          len(sv), "; часы", len(wv))
    if "--preview" in sys.argv:
        preview(v, f, n, col)


def preview(v, f, n, col):
    """Быстрый софт-рендер (ортографика) в PNG для проверки формы."""
    from PIL import Image
    W = 900
    imgs = []
    for view in ("top", "side", "bottom"):
        if view == "top":
            P = np.stack([v[:, 0], -v[:, 2]], 1); depth = v[:, 1]; L = nrm((0.3, 1, 0.4))
        elif view == "side":
            P = np.stack([-v[:, 2], v[:, 1]], 1); depth = -v[:, 0]; L = nrm((-1, 0.6, 0.3))
        else:
            P = np.stack([v[:, 0], v[:, 2]], 1); depth = -v[:, 1]; L = nrm((0.3, -1, 0.4))
        lo = P.min(0) - 0.005
        sc = (W - 20) / max(P.max(0) - lo)
        img = np.zeros((W, W, 3)); zb = np.full((W, W), -1e9)
        Q = (P - lo) * sc
        shade = np.clip(n @ L, 0, 1) * 0.75 + 0.25
        c = np.clip(col[:, :3] * shade[:, None], 0, 1)
        for tri in f:
            pts = Q[tri]
            x0, y0 = np.floor(pts.min(0)).astype(int)
            x1, y1 = np.ceil(pts.max(0)).astype(int)
            if x1 - x0 > 60 or y1 - y0 > 60:
                continue
            xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
            a, b, cc = pts
            den = (b[1] - cc[1]) * (a[0] - cc[0]) + (cc[0] - b[0]) * (a[1] - cc[1])
            if abs(den) < 1e-12:
                continue
            l1 = ((b[1] - cc[1]) * (xs - cc[0]) + (cc[0] - b[0]) * (ys - cc[1])) / den
            l2 = ((cc[1] - a[1]) * (xs - cc[0]) + (a[0] - cc[0]) * (ys - cc[1])) / den
            l3 = 1 - l1 - l2
            m = (l1 >= 0) & (l2 >= 0) & (l3 >= 0) & (xs >= 0) & (ys >= 0) & (xs < W) & (ys < W)
            if not m.any():
                continue
            z = l1 * depth[tri[0]] + l2 * depth[tri[1]] + l3 * depth[tri[2]]
            cl = l1[..., None] * c[tri[0]] + l2[..., None] * c[tri[1]] + l3[..., None] * c[tri[2]]
            xi, yi = xs[m], ys[m]
            zz = z[m]
            upd = zz > zb[W - 1 - yi, xi]
            zb[W - 1 - yi[upd], xi[upd]] = zz[upd]
            img[W - 1 - yi[upd], xi[upd]] = cl[m][upd]
        imgs.append(img)
    out = np.concatenate(imgs, 1)
    Image.fromarray((out * 255).astype(np.uint8)).save(os.path.join(os.path.dirname(OUT), "_preview.png"))


if __name__ == "__main__":
    main()
