#!/usr/bin/env python3
"""Единый визуальный ряд для моделей пака пользователя (разные авторы → один реалистичный стиль).

    python3 tools/style/style_unify.py            # калибровать всё по tools/style/style_config.json
    python3 tools/style/style_unify.py --report   # только замерить и написать отчёт, ничего не меняя

Что делает с каждым материалом (по его классу: кожа акулы, чешуя, панцирь, ракушка, кора, листва…):
  1. маска используемых текселей по UV (поля атласа не влияют на замеры);
  2. альбедо: снимает лишний запечённый свет/AO (низкочастотная яркость → к медиане, сила по классу),
     сводит медианную линейную яркость в диапазон класса (таблицы PBR-альбедо), мягко ограничивает
     пересветы (≤ y_max) и «уголь» (≥ 0.012), приглушает лишнюю насыщенность;
  3. шероховатость/металл: медиана шероховатости в диапазон класса (разброс сохраняется), металл — 0
     у органики; где нет карты — пишет коэффициенты материала;
  4. плотность текселей px/м в игровом масштабе: выше нормы категории — текстура уменьшается, ниже —
     отметка в отчёте;
  5. микродеталь: общий для класса рисунок (чешуйки, бугорки, поры, гребни, волокна) вмешивается в
     карту нормалей с периодом в МЕТРАХ — одинаковая «фактура вблизи» у моделей разных авторов.
Оригиналы один раз копируются в assets/user_pack/_style_orig/ (те же пути) и всегда берутся оттуда —
повторный запуск даёт тот же результат. Полка стиля на полигоне показывает «до/после» по этим копиям.
Отчёт: assets/user_pack/STYLE_REPORT.md и style_report.json.
"""
import io
import json
import os
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
PACK = os.path.join(ROOT, "assets", "user_pack")
ORIG = os.path.join(PACK, "_style_orig")
GODOT = os.environ.get("GODOT", "/tmp/godot47/Godot_v4.7.2-stable_linux.x86_64")
sys.path.insert(0, HERE)
from glb_io import Glb  # noqa: E402

REPORT_ONLY = "--report" in sys.argv
RNG = np.random.default_rng(20261119)


# ------------------------------------------------------------------ цвет
def to_lin(c8):
    a = c8 / 255.0
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def to_srgb8(lin):
    lin = np.clip(lin, 0.0, 1.0)
    a = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1 / 2.4) - 0.055)
    return np.clip(np.round(a * 255.0), 0, 255).astype(np.uint8)


def lum(lin):
    return 0.2126 * lin[..., 0] + 0.7152 * lin[..., 1] + 0.0722 * lin[..., 2]


def sat8(c8):
    mx = c8.max(-1)
    mn = c8.min(-1)
    return np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0.0)


# ------------------------------------------------------------------ UV-маска и плотность
def c2(a, b):
    return a[:, 0] * b[:, 1] - a[:, 1] * b[:, 0]


def uv_mask(uv, idx, w, h):
    if uv is None or len(idx) == 0:
        return np.ones((h, w), bool)
    tri_uv = uv[idx]
    uv_area = np.abs(c2(tri_uv[:, 1] - tri_uv[:, 0], tri_uv[:, 2] - tri_uv[:, 0])).sum() / 2
    if uv_area > 1.15 or uv.min() < -0.05 or uv.max() > 1.05:   # тайлинг — маска = вся текстура
        return np.ones((h, w), bool)
    im = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(im)
    for t in tri_uv:
        d.polygon([(float(p[0] * w), float(p[1] * h)) for p in t], fill=255)
    m = np.asarray(im.filter(ImageFilter.MaxFilter(3))) > 0
    return m if m.mean() > 0.002 else np.ones((h, w), bool)


def texel_density(pos, uv, idx, w, h, scale):
    if uv is None or len(idx) == 0:
        return 0.0
    p = pos[idx] * scale
    area = np.linalg.norm(np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0]), axis=1).sum() / 2
    t = uv[idx]
    uva = np.abs(c2(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])).sum() / 2
    if area <= 0:
        return 0.0
    return float(np.sqrt(uva * w * h / area))


# ------------------------------------------------------------------ сглаживание по маске
def masked_blur(x, m, sigma):
    """Гаусс по маске: blur(x*m)/blur(m) — поля атласа не тянут цвет к чёрному."""
    from scipy.ndimage import gaussian_filter
    r = max(1.0, sigma)
    def g(a):
        return gaussian_filter(a.astype(np.float32), r, mode="wrap")
    num = g(x * m)
    den = g(m.astype(np.float32))
    return num / np.maximum(den, 1e-4)


# ------------------------------------------------------------------ альбедо
def calibrate_albedo(img: Image.Image, mask, cls):
    rgba = np.asarray(img.convert("RGBA")).astype(np.float64)
    rgb8 = rgba[..., :3]
    alpha = rgba[..., 3]
    m = mask & (alpha > 128)
    if m.sum() < 16:
        m = alpha > 128
    lin = to_lin(rgb8)
    Y = lum(lin)
    st = {"y_med_before": float(np.median(Y[m])), "y_p95_before": float(np.percentile(Y[m], 95)),
          "sat_before": float(np.median(sat8(rgb8)[m]))}
    h, w = Y.shape
    # 1) запечённый свет: стандартное отклонение log-яркости на низких частотах
    logY = np.log(np.maximum(Y, 1e-4))
    lo = masked_blur(logY, m, max(w, h) / 24.0)
    st["baked_before"] = float(np.std(lo[m]))
    k = float(cls.get("delight", 0.0))
    if k > 0:
        dev = lo - np.median(lo[m])
        f = np.exp(np.clip(-k * dev, np.log(0.6), np.log(1.6)))
        lin = lin * f[..., None]
        Y = lum(lin)
        logY = np.log(np.maximum(Y, 1e-4))
        lo2 = masked_blur(logY, m, max(w, h) / 24.0)
        st["baked_after"] = float(np.std(lo2[m]))
    else:
        st["baked_after"] = st["baked_before"]
    # 2) медиана яркости в диапазон класса
    y_lo, y_hi = cls["y"]
    med = float(np.median(Y[m]))
    tgt = float(np.clip(med, y_lo, y_hi))
    if med > 1e-4 and abs(tgt - med) > 1e-4:
        lin = lin * (tgt / med)
        Y = lum(lin)
    # 3) мягкий потолок и «уголь»
    y_max = float(cls.get("y_max", 0.8))
    knee = 0.8 * y_max
    over = Y > knee
    if over.any():
        ny = knee + (y_max - knee) * np.tanh((Y - knee) / (y_max - knee))
        f = np.where(over, ny / np.maximum(Y, 1e-6), 1.0)
        lin = lin * f[..., None]
        Y = lum(lin)
    floor_ = 0.012
    low = Y < floor_
    if low.any():
        lin = np.where(low[..., None], lin + (floor_ - Y)[..., None] * 0.9, lin)
        Y = lum(lin)
    # 4) насыщенность (по sRGB-метрике, правка в линейном пространстве с сохранением яркости)
    s_now = float(np.median(sat8(to_srgb8(lin).astype(np.float64))[m]))
    s_max = float(cls.get("sat_max", 1.0))
    if s_now > s_max:
        s = s_max / s_now
        lin = Y[..., None] + (lin - Y[..., None]) * s
    out8 = to_srgb8(lin)
    st["y_med_after"] = float(np.median(lum(to_lin(out8.astype(np.float64)))[m]))
    st["y_p95_after"] = float(np.percentile(lum(to_lin(out8.astype(np.float64)))[m], 95))
    st["sat_after"] = float(np.median(sat8(out8.astype(np.float64))[m]))
    res = np.dstack([out8, rgba[..., 3].astype(np.uint8)])
    return Image.fromarray(res, "RGBA" if img.mode == "RGBA" else "RGBA").convert(img.mode if img.mode in ("RGB", "RGBA") else "RGBA"), st


def calibrate_color(rgb_lin, cls):
    """Коэффициент цвета материала без текстуры (листва пальмы, кокосы)."""
    lin = np.array(rgb_lin[:3], np.float64).reshape(1, 1, 3)
    Y = float(lum(lin)[0, 0])
    tgt = float(np.clip(Y, *cls["y"]))
    if Y > 1e-4:
        lin = lin * (tgt / Y)
    s8 = to_srgb8(lin).astype(np.float64)
    s_now = float(sat8(s8)[0, 0])
    if s_now > cls.get("sat_max", 1.0):
        Yn = float(lum(lin)[0, 0])
        lin = Yn + (lin - Yn) * (cls["sat_max"] / s_now)
    return [float(v) for v in lin.reshape(3)], {"y_before": Y, "y_after": float(lum(lin)[0, 0]),
                                                 "sat_before": s_now, "sat_after": float(sat8(to_srgb8(lin).astype(np.float64))[0, 0])}


# ------------------------------------------------------------------ шероховатость / металл
def calibrate_mr(img: Image.Image, mask, cls):
    a = np.asarray(img.convert("RGB")).astype(np.float64)
    r = a[..., 1] / 255.0
    m = mask
    med = float(np.median(r[m]))
    lo_, hi_ = cls["rough"]
    tgt = float(np.clip(med, lo_, hi_))
    st = {"rough_before": med, "metal_before": float(np.median(a[..., 2][m]) / 255.0)}
    r2 = np.clip(r + (tgt - med), 0.04, 1.0)
    a[..., 1] = np.round(r2 * 255.0)
    if cls.get("metal", 0) != "keep":
        a[..., 2] = 0.0
    st["rough_after"] = float(np.median(r2[m]))
    st["metal_after"] = float(np.median(a[..., 2][m]) / 255.0)
    return Image.fromarray(a.astype(np.uint8), "RGB"), st


# ------------------------------------------------------------------ микродеталь
def _worley(h, w, period, rng):
    """F1, F2 клеточного шума с периодом period (px), бесшовно."""
    ny = max(1, int(round(h / period)))
    nx = max(1, int(round(w / period)))
    pts = rng.random((ny, nx, 2))
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    gy = yy * ny / h
    gx = xx * nx / w
    cy = np.floor(gy).astype(np.int32)
    cx = np.floor(gx).astype(np.int32)
    f1 = np.full((h, w), 9.0, np.float32)
    f2 = np.full((h, w), 9.0, np.float32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            iy = cy + dy
            ix = cx + dx
            p = pts[iy % ny, ix % nx]
            d = np.sqrt((iy + p[..., 0] - gy) ** 2 + (ix + p[..., 1] - gx) ** 2)
            f2 = np.where(d < f1, f1, np.minimum(f2, d))
            f1 = np.minimum(f1, d)
    return f1, f2


def _value(h, w, period, rng, octaves=3):
    out = np.zeros((h, w), np.float32)
    amp = 1.0
    tot = 0.0
    p = period
    for _ in range(octaves):
        ny = max(1, int(round(h / p)))
        nx = max(1, int(round(w / p)))
        g = rng.random((ny, nx)).astype(np.float32)
        im = Image.fromarray(g, "F").resize((w, h), Image.BICUBIC)
        out += np.asarray(im) * amp
        tot += amp
        amp *= 0.5
        p = max(2.0, p / 2.0)
    return out / tot


def detail_height(kind, h, w, period):
    rng = np.random.default_rng(hash(kind) & 0xFFFF)
    if kind == "scales":
        f1, f2 = _worley(h, w, period, rng)
        return np.clip((f2 - f1) * 2.0, 0, 1) ** 0.6
    if kind in ("denticle", "bumps"):
        f1, _ = _worley(h, w, period, rng)
        return 1.0 - np.clip(f1, 0, 1)
    if kind == "pores":
        f1, _ = _worley(h, w, period, rng)
        return np.clip(f1 * 1.4, 0, 1)
    if kind == "ridges":
        yy = np.mgrid[0:h, 0:w][0].astype(np.float32)
        n = _value(h, w, period * 4, rng, 2)
        return 0.5 + 0.5 * np.sin((yy / period + n * 2.0) * 2 * np.pi)
    if kind == "wrinkle":
        n = _value(h, w, period * 2, rng, 4)
        return 1.0 - np.abs(n - 0.5) * 2.0
    if kind == "fibres":
        n = np.asarray(Image.fromarray(_value(h, max(2, w // 8), period, rng, 3), "F").resize((w, h), Image.BICUBIC))
        return n
    return np.zeros((h, w), np.float32)


def blend_detail(nimg: Image.Image, mask, kind, period, amp):
    a = np.asarray(nimg.convert("RGB")).astype(np.float32) / 255.0
    h, w = a.shape[:2]
    hgt = detail_height(kind, h, w, period).astype(np.float32)
    gy, gx = np.gradient(hgt)
    s = amp * period / 2.0
    dx = -gx * s
    dy = -gy * s
    n1 = a * 2.0 - 1.0
    # «whiteout»: сумма наклонов, перемножение z
    nx = n1[..., 0] + dx
    ny = n1[..., 1] + dy
    nz = n1[..., 2]
    ln = np.sqrt(nx * nx + ny * ny + nz * nz) + 1e-6
    out = np.dstack([nx / ln, ny / ln, nz / ln])
    out = np.where(mask[..., None], out, n1)
    return Image.fromarray(np.clip(np.round((out * 0.5 + 0.5) * 255), 0, 255).astype(np.uint8), "RGB")


def flat_normal(w, h):
    return Image.new("RGB", (w, h), (128, 128, 255))


# ------------------------------------------------------------------ утилиты
def png_bytes(img):
    b = io.BytesIO()
    img.save(b, "PNG", optimize=True)
    return b.getvalue()


def backup(rel):
    src = os.path.join(PACK, rel)
    dst = os.path.join(ORIG, rel)
    if not os.path.exists(dst) and os.path.exists(src):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
    return dst


def resize_pow2(img, factor):
    w, h = img.size
    nw = max(256, int(w * factor))
    nh = max(256, int(h * factor))
    if (nw, nh) == (w, h):
        return img
    return img.resize((nw, nh), Image.LANCZOS)


def density_action(dens, rng_):
    lo_, hi_ = rng_
    if dens <= 0:
        return 1.0, "нет UV"
    if dens > hi_ * 1.4:
        f = 1.0
        while dens * f > hi_ * 1.4 and f > 0.25:
            f *= 0.5
        return f, "выше нормы → ×%.2f" % f
    if dens < lo_:
        return 1.0, "НИЖЕ нормы (усилена микродеталь)"
    return 1.0, "в норме"


# ------------------------------------------------------------------ GLB
def process_glb(job, cfg, report):
    rel = job["path"]
    orig = backup(rel)
    g = Glb(orig)
    base = os.path.splitext(os.path.basename(rel))[0]
    out_dir = os.path.dirname(os.path.join(PACK, rel))
    prims = g.primitives()
    main_ext = max((p[1].max(0) - p[1].min(0)).max() for p in prims)
    scale = job["game_size"] / main_ext if main_ext > 0 else 1.0
    rep = {"model": rel, "scale": scale, "materials": []}
    for mi, mat in enumerate(g.json.get("materials", [])):
        mname = mat.get("name", str(mi))
        cname = job["materials"].get(mname, "special_keep")
        cls = cfg["classes"][cname]
        e = {"material": mname, "class": cname}
        if cls.get("keep"):
            e["note"] = "без изменений (глаза/зубы/дёсны)"
            rep["materials"].append(e)
            continue
        pp = [p for p in prims if p[0] == mi]
        pbr = mat.setdefault("pbrMetallicRoughness", {})
        bct = pbr.get("baseColorTexture")
        mrt = pbr.get("metallicRoughnessTexture")
        nt = mat.get("normalTexture")
        dens = 0.0
        mask = None
        if bct is not None:
            ii = g.texture_image(bct["index"])
            img = Image.open(io.BytesIO(g.image_bytes(ii)))
            w, h = img.size
            uv = np.concatenate([p[2] for p in pp if p[2] is not None]) if pp else None
            idx_all = []
            off = 0
            for p in pp:
                idx_all.append(p[3] + off)
                off += len(p[1])
            pos = np.concatenate([p[1] for p in pp]) if pp else np.zeros((0, 3))
            idx = np.concatenate(idx_all) if idx_all else np.zeros((0, 3), np.int64)
            mask = uv_mask(uv, idx, w, h)
            dens = texel_density(pos, uv, idx, w, h, scale)
            fac, dnote = density_action(dens, cfg["density"][job["density"]])
            e["density_px_m"] = round(dens)
            e["density"] = dnote
            new_img, st = calibrate_albedo(img, mask, cls)
            e.update({k: round(v, 4) for k, v in st.items()})
            if fac < 1.0:
                new_img = resize_pow2(new_img, fac)
                e["albedo_size"] = "%dx%d → %dx%d" % (w, h, *new_img.size)
            if not REPORT_ONLY:
                g.set_image_bytes(ii, png_bytes(new_img))
                _write_extracted(out_dir, base, g.json["images"][ii], new_img)
        elif "baseColorFactor" in pbr:
            col, st = calibrate_color(pbr["baseColorFactor"], cls)
            e.update({("color_" + k): round(v, 4) for k, v in st.items()})
            if not REPORT_ONLY:
                pbr["baseColorFactor"] = col + [pbr["baseColorFactor"][3]]
        if mrt is not None:
            ii = g.texture_image(mrt["index"])
            img = Image.open(io.BytesIO(g.image_bytes(ii)))
            mk = mask if mask is not None and mask.shape == (img.size[1], img.size[0]) else np.ones((img.size[1], img.size[0]), bool)
            new_img, st = calibrate_mr(img, mk, cls)
            e.update({k: round(v, 3) for k, v in st.items()})
            pbr["roughnessFactor"] = 1.0
            if cls.get("metal", 0) != "keep":
                pbr["metallicFactor"] = 0.0 if not REPORT_ONLY else pbr.get("metallicFactor", 1.0)
            if not REPORT_ONLY:
                g.set_image_bytes(ii, png_bytes(new_img))
                _write_extracted(out_dir, base, g.json["images"][ii], new_img)
        else:
            rb = float(pbr.get("roughnessFactor", 1.0))
            ra = float(np.clip(rb, *cls["rough"]))
            e["rough_before"] = round(rb, 3)
            e["rough_after"] = round(ra, 3)
            if not REPORT_ONLY:
                pbr["roughnessFactor"] = ra
                if cls.get("metal", 0) != "keep":
                    pbr["metallicFactor"] = 0.0
        det = cls.get("detail")
        if det and nt is not None and dens > 0:
            ii = g.texture_image(nt["index"])
            img = Image.open(io.BytesIO(g.image_bytes(ii)))
            nd = dens * img.size[0] / max(1, (Image.open(io.BytesIO(g.image_bytes(g.texture_image(bct["index"])))).size[0] if bct else img.size[0]))
            period = det["size"] * nd
            amp = det["amp"] * (1.4 if "НИЖЕ" in e.get("density", "") else 1.0)
            if period >= 3.0:
                mk = mask if mask is not None and mask.shape == (img.size[1], img.size[0]) else np.ones((img.size[1], img.size[0]), bool)
                new_img = blend_detail(img, mk, det["kind"], period, amp)
                e["detail"] = "%s, период %.1f px (%.0f мм), сила %.2f" % (det["kind"], period, det["size"] * 1000, amp)
                if not REPORT_ONLY:
                    g.set_image_bytes(ii, png_bytes(new_img))
                    _write_extracted(out_dir, base, g.json["images"][ii], new_img)
            else:
                e["detail"] = "пропущена: черта %.0f мм = %.1f px (< 3 px)" % (det["size"] * 1000, period)
        rep["materials"].append(e)
    if not REPORT_ONLY:
        g.save(os.path.join(PACK, rel))
    report.append(rep)


def _write_extracted(out_dir, base, image_json, img):
    """Godot при импорте GLB выносит картинки в <база>_<имя картинки>.png — держим их в согласии."""
    nm = image_json.get("name")
    if not nm:
        return
    p = os.path.join(out_dir, "%s_%s.png" % (base, nm))
    if os.path.exists(p) or os.path.exists(p + ".import"):
        img.save(p, "PNG", optimize=True)


# ------------------------------------------------------------------ PNG-модели (краб)
def process_png_model(job, cfg, report):
    cls = cfg["classes"][job["class"]]
    g = Glb(os.path.join(PACK, job["mesh"]))
    prims = g.primitives()
    pos = np.concatenate([p[1] for p in prims])
    uv = np.concatenate([p[2] for p in prims])
    idx = []
    off = 0
    for p in prims:
        idx.append(p[3] + off)
        off += len(p[1])
    idx = np.concatenate(idx)
    scale = job["game_size"] / (pos.max(0) - pos.min(0)).max()
    alb_o = backup(job["albedo"])
    img = Image.open(alb_o)
    w, h = img.size
    mask = uv_mask(uv, idx, w, h)
    dens = texel_density(pos, uv, idx, w, h, scale)
    fac, dnote = density_action(dens, cfg["density"][job["density"]])
    e = {"material": job["name"], "class": job["class"], "density_px_m": round(dens), "density": dnote,
         "uv_used": round(float(mask.mean()), 3)}
    new_img, st = calibrate_albedo(img, mask, cls)
    e.update({k: round(v, 4) for k, v in st.items()})
    if not REPORT_ONLY:
        new_img.save(os.path.join(PACK, job["albedo"]), "PNG", optimize=True)
    if job.get("orm"):
        o = Image.open(backup(job["orm"]))
        new_o, st = calibrate_mr(o, mask, cls)
        e.update({k: round(v, 3) for k, v in st.items()})
        if not REPORT_ONLY:
            new_o.save(os.path.join(PACK, job["orm"]), "PNG", optimize=True)
    det = cls.get("detail")
    if det and job.get("normal"):
        n = Image.open(backup(job["normal"]))
        period = det["size"] * dens * n.size[0] / w
        if period >= 3.0:
            new_n = blend_detail(n, mask if mask.shape == (n.size[1], n.size[0]) else np.ones((n.size[1], n.size[0]), bool),
                                 det["kind"], period, det["amp"])
            e["detail"] = "%s, период %.1f px (%.0f мм), сила %.2f" % (det["kind"], period, det["size"] * 1000, det["amp"])
            if not REPORT_ONLY:
                new_n.save(os.path.join(PACK, job["normal"]), "PNG", optimize=True)
        else:
            e["detail"] = "пропущена: %.1f px" % period
    report.append({"model": job["mesh"], "scale": scale, "materials": [e]})


# ------------------------------------------------------------------ морские .res
def godot(*args):
    lock = [] if os.environ.get("STYLE_NO_FLOCK") else ["flock", "/tmp/claude-0/godot.lock"]
    cmd = lock + ["timeout", "900", GODOT, "--headless", "--path", ROOT, "-s",
           "tools/style/sea_res_io.gd", "--"] + list(args)
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-2000:], r.stderr[-2000:])
    return r.returncode


def process_sea(jobs, cfg, report, work):
    orig_dir = os.path.join(work, "sea_orig")
    new_dir = os.path.join(work, "sea_new")
    os.makedirs(new_dir, exist_ok=True)
    # оригиналы .res — в _style_orig; выгрузка — из оригиналов
    jobs = [j for j in jobs if not j.get("skip")]
    for j in jobs:
        backup(j["path"])
    if not all(os.path.exists(os.path.join(orig_dir, os.path.splitext(os.path.basename(j["path"]))[0] + "_mesh.json")) for j in jobs):
        godot("dump", orig_dir, *["res://assets/user_pack/_style_orig/" + j["path"] for j in jobs])
    for j in jobs:
        cls = cfg["classes"][j["class"]]
        name = os.path.splitext(os.path.basename(j["path"]))[0]
        info = json.load(open(os.path.join(orig_dir, name + "_mesh.json")))
        png = os.path.join(orig_dir, name + "_albedo.png")
        e = {"material": name, "class": j["class"]}
        if not os.path.exists(png):
            e["note"] = "нет текстуры (цвет задаёт шейдер вида)"
            report.append({"model": j["path"], "materials": [e]})
            continue
        img = Image.open(png)
        w, h = img.size
        if w < 128 or h < 128:
            e["note"] = "текстура-заглушка %dx%d — цвет задаёт шейдер вида (params color_a/color_b), не трогаем" % (w, h)
            j["_no_inject"] = True
            report.append({"model": j["path"], "materials": [e]})
            continue
        pos = np.array(info["verts"], np.float64)
        uv = np.array(info["uvs"], np.float64) if info["uvs"] else None
        idx = np.array(info["idx"], np.int64)
        idx = idx[: len(idx) // 3 * 3].reshape(-1, 3)
        scale = j["game_size"] / max(1e-6, (pos.max(0) - pos.min(0)).max())
        mask = uv_mask(uv, idx, w, h)
        dens = texel_density(pos, uv, idx, w, h, scale)
        _f, dnote = density_action(dens, cfg["density"][j["density"]])
        e.update({"density_px_m": round(dens), "density": dnote, "uv_used": round(float(mask.mean()), 3)})
        new_img, st = calibrate_albedo(img, mask, cls)
        e.update({k: round(v, 4) for k, v in st.items()})
        e["note"] = "у морских видов шейдер берёт только альбедо: шероховатость/микродеталь задаёт шейдер вида"
        new_img.save(os.path.join(new_dir, name + "_albedo.png"))
        report.append({"model": j["path"], "scale": scale, "materials": [e]})
    if not REPORT_ONLY:
        # кладём калиброванные текстуры в рабочие .res (копируем оригинал и меняем текстуру)
        inj = [j for j in jobs if not j.get("_no_inject")]
        for j in inj:
            shutil.copy2(os.path.join(ORIG, j["path"]), os.path.join(PACK, j["path"]))
        godot("inject", new_dir, *["res://assets/user_pack/" + j["path"] for j in inj])


# ------------------------------------------------------------------ атласы (водоросли)
def process_atlas(job, cfg, report):
    cls = cfg["classes"][job["class"]]
    o = backup(job["path"])
    img = Image.open(o)
    a = np.asarray(img.convert("RGBA"))
    mask = a[..., 3] > 128
    new_img, st = calibrate_albedo(img, mask, cls)
    e = {"material": os.path.basename(job["path"]), "class": job["class"]}
    e.update({k: round(v, 4) for k, v in st.items()})
    if not REPORT_ONLY:
        new_img.save(os.path.join(PACK, job["path"]), "PNG", optimize=True)
    report.append({"model": job["path"], "materials": [e]})


# ------------------------------------------------------------------ отчёт
def write_report(report):
    json.dump(report, open(os.path.join(PACK, "style_report.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    L = ["# Единый визуальный ряд пака — отчёт калибровки", "",
         "Сгенерировано `tools/style/style_unify.py` по `tools/style/style_config.json`. Оригиналы — `assets/user_pack/_style_orig/`.",
         "Y — медианная линейная яркость альбедо по используемым текселям; «запечённый свет» — разброс низкочастотной log-яркости (меньше — ровнее).", "",
         "| Модель / материал | Класс | Плотность px/м | Y до → после | Насыщ. до → после | Запеч. свет до → после | Шерох. до → после | Микродеталь |",
         "|---|---|---|---|---|---|---|---|"]
    for r in report:
        for e in r["materials"]:
            def pair(a, b, fmt="%.3f"):
                if a in e and b in e:
                    return (fmt % e[a]) + " → " + (fmt % e[b])
                return "—"
            yb = pair("y_med_before", "y_med_after") if "y_med_before" in e else pair("color_y_before", "color_y_after")
            sb = pair("sat_before", "sat_after", "%.2f") if "sat_before" in e else pair("color_sat_before", "color_sat_after", "%.2f")
            L.append("| %s · %s | %s | %s | %s | %s | %s | %s | %s |" % (
                os.path.basename(r["model"]), e["material"], e["class"],
                ("%s (%s)" % (e.get("density_px_m"), e.get("density"))) if "density_px_m" in e else "—",
                yb, sb, pair("baked_before", "baked_after"), pair("rough_before", "rough_after", "%.2f"),
                e.get("detail", e.get("note", "—"))))
    open(os.path.join(PACK, "STYLE_REPORT.md"), "w", encoding="utf-8").write("\n".join(L) + "\n")


def main():
    cfg = json.load(open(os.path.join(HERE, "style_config.json"), encoding="utf-8"))
    work = "/tmp/style_work"
    os.makedirs(work, exist_ok=True)
    report = []
    only_sea = "--only-sea" in sys.argv
    if only_sea:  # прежний отчёт без морских строк + новые морские
        old = json.load(open(os.path.join(PACK, "style_report.json"), encoding="utf-8"))
        sea_paths = {j["path"] for j in cfg["sea_res"]}
        report = [r for r in old if r["model"] not in sea_paths]
    for j in ([] if only_sea else cfg["glb"]):
        print("glb", j["path"])
        process_glb(j, cfg, report)
    for j in ([] if only_sea else cfg["png_models"]):
        print("png", j["name"])
        process_png_model(j, cfg, report)
    for j in ([] if only_sea else cfg["atlas"]):
        print("atlas", j["path"])
        process_atlas(j, cfg, report)
    if "--no-sea" not in sys.argv:
        print("sea")
        process_sea(cfg["sea_res"], cfg, report, work)
    write_report(report)
    print("готово:", os.path.join(PACK, "STYLE_REPORT.md"))


if __name__ == "__main__":
    main()
