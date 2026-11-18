#!/usr/bin/env python3
"""Пакетная нормализация моделей пользователя под бюджеты «Островов».

    python3 tools/asset_normalize.py batch.json [--out assets/user_pack] [--keep-tmp]

batch.json — список заданий (поля как в tools/asset_normalize.gd), но src — обычный путь
к файлу на диске (FBX/OBJ/GLB/DAE), а out — папка категории внутри --out:
    [{"name": "animal_shark_great_white", "category": "animal_large",
      "src": "/tmp/models_in/shark/.../GreatWhiteShark_Animated.fbx",
      "dir": "animals", "size": 4.5, "rotate_y": 180,
      "materials": {"Grey": {"albedo": "...", "normal": "...", "orm": "..."}}}, ...]

Что делает:
  1. временный Godot-проект (исходники не попадают в основной проект);
  2. импорт (FBX через встроенный ufbx);
  3. tools/asset_normalize.gd на каждое задание: упрощение до бюджета категории
     (meshoptimizer, кости и UV сохраняются; листочки → ромбы; слияние материалов),
     текстуры ужимаются до лимита категории, масштаб в метрах, пивот, поворот лицом в −Z;
  4. сводная таблица до/после в <out>/REPORT.md и report.json.
Исходные архивы пользователя в репозиторий не кладутся — только результат .glb.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

GODOT = os.environ.get("GODOT", "/tmp/godot47/Godot_v4.7.2-stable_linux.x86_64")
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    batch = json.load(open(args[0], encoding="utf-8"))
    out_root = os.path.join(ROOT, "assets", "user_pack")
    if "--out" in args:
        out_root = os.path.abspath(args[args.index("--out") + 1])
    keep = "--keep-tmp" in args
    tmp = tempfile.mkdtemp(prefix="asset_norm_")
    with open(os.path.join(tmp, "project.godot"), "w") as f:
        f.write('config_version=5\n[application]\nconfig/name="norm"\n'
                '[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    shutil.copy(os.path.join(HERE, "asset_normalize.gd"), tmp)
    jobs = []
    for i, job in enumerate(batch):
        src = os.path.abspath(job["src"])
        sub = os.path.join(tmp, "src", f"{i:03d}")
        os.makedirs(sub, exist_ok=True)
        dst = os.path.join(sub, os.path.basename(src))
        shutil.copy(src, dst)
        spec = dict(job)
        spec["src"] = "res://src/%03d/%s" % (i, os.path.basename(src))
        cat_dir = os.path.join(out_root, job.get("dir", job.get("category", "misc")))
        os.makedirs(cat_dir, exist_ok=True)
        spec["out"] = os.path.join(cat_dir, job["name"] + ".glb")
        spec["report"] = os.path.join(tmp, job["name"] + ".json")
        sp = os.path.join(tmp, job["name"] + ".spec.json")
        json.dump(spec, open(sp, "w", encoding="utf-8"), ensure_ascii=False)
        jobs.append((job, sp, spec))
    subprocess.run([GODOT, "--headless", "--path", tmp, "--import"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3600)
    rows = []
    for job, sp, spec in jobs:
        r = subprocess.run([GODOT, "--headless", "--path", tmp, "-s", "res://asset_normalize.gd", "--", sp],
                           capture_output=True, text=True, timeout=3600)
        if r.returncode != 0 or os.environ.get("NORM_VERBOSE"): print(r.stdout[-3000:], r.stderr[-3000:])
        rep = {}
        if os.path.exists(spec["report"]):
            rep = json.load(open(spec["report"], encoding="utf-8"))
        rep["ok"] = r.returncode == 0
        rows.append(rep)
        print(f'{job["name"]}: {rep.get("before_tris")} → {rep.get("after_tris")} tris, '
              f'{rep.get("after_surfaces")} поверхн., {rep.get("glb_mb")} МБ, ok={rep["ok"]}')
    _write_report(out_root, rows)
    if not keep:
        shutil.rmtree(tmp, ignore_errors=True)
    return 0 if all(r["ok"] for r in rows) else 1


def _write_report(out_root: str, rows: list) -> None:
    path_json = os.path.join(out_root, "report.json")
    old = {}
    if os.path.exists(path_json):
        for r in json.load(open(path_json, encoding="utf-8")):
            old[r.get("name")] = r
    for r in rows:
        old[r.get("name")] = r
    allrows = sorted(old.values(), key=lambda r: (r.get("category", ""), r.get("name", "")))
    json.dump(allrows, open(path_json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    lines = ["# Пак моделей пользователя — отчёт нормализации", "",
             "| Модель | Категория | Треуг. до → после (бюджет) | Поверхн. до → после | Текстуры, МБ VRAM≈ | Кости | Анимации | .glb, МБ |",
             "|---|---|---|---|---|---|---|---|"]
    for r in allrows:
        an = ", ".join(a["name"] for a in r.get("animations", [])) or "—"
        lines.append(f'| {r.get("name")} | {r.get("category")} | {r.get("before_tris")} → {r.get("after_tris")} '
                     f'({r.get("budget_tris")}) | {r.get("before_surfaces")} → {r.get("after_surfaces")} | '
                     f'{r.get("tex_mb_vram_est")} | {r.get("bones")} | {an} | {r.get("glb_mb")} |')
    open(os.path.join(out_root, "REPORT.md"), "w", encoding="utf-8").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    sys.exit(main())
