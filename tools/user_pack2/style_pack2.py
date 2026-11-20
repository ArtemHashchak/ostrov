"""Пак №2 через единый визуальный ряд (VISUAL-UNIFY, tools/style/style_unify.py) — только свои задания:
ящерица, крылан (png_models) и текстуры камня (atlas, класс rock). Строки этих моделей в
assets/user_pack/style_report.json заменяются, остальные (в т. ч. морские) остаются как есть.
    python3 tools/user_pack2/style_pack2.py
Шероховатость ящерицы — отдельная серая карта (не ORM), её медиана сводится в диапазон класса здесь же."""
import os, sys, json
import numpy as np
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "style"))
import style_unify as su  # noqa: E402

MINE_PNG = {"lizard", "bat"}
cfg = json.load(open(os.path.join(su.HERE, "style_config.json"), encoding="utf-8"))
rep_path = os.path.join(su.PACK, "style_report.json")
old = json.load(open(rep_path, encoding="utf-8")) if os.path.exists(rep_path) else []
mine_models = {j["mesh"] for j in cfg["png_models"] if j["name"] in MINE_PNG}
mine_atlas = {j["path"] for j in cfg["atlas"] if j["path"].startswith("rocks/")}
report = [r for r in old if r["model"] not in mine_models | mine_atlas]
for j in cfg["png_models"]:
    if j["name"] in MINE_PNG:
        print("png", j["name"])
        su.process_png_model(j, cfg, report)
for j in cfg["atlas"]:
    if j["path"] in mine_atlas:
        print("atlas", j["path"])
        su.process_atlas(j, cfg, report)
# шероховатость ящерицы (серая карта)
rel = "animals/lizard/lizard_roughness.png"
src = su.backup(rel)
r = np.asarray(Image.open(src).convert("L")).astype(np.float32) / 255.0
lo, hi = cfg["classes"]["reptile_skin"]["rough"]
med = float(np.median(r))
r2 = np.clip(r + (float(np.clip(med, lo, hi)) - med), 0.04, 1.0)
Image.fromarray((r2 * 255 + 0.5).astype(np.uint8), "L").save(os.path.join(su.PACK, rel), "PNG", optimize=True)
for e in report:
    if e["model"] == "animals/lizard/lizard_user.glb":
        e["materials"][0].update({"rough_before": round(med, 3), "rough_after": round(float(np.median(r2)), 3)})
su.write_report(report)
print("готово")
