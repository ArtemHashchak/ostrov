#!/usr/bin/env python3
"""Записи каталога для новых моделей версии 5 (assets/user_pack/flora_v5/flora_v5.json).
Размеры берутся из самих .gltf (рамка по POSITION с учётом переноса узлов).
Запуск: python3 tools/import_v5/flora_v5_entries.py  (затем flora_catalog.py)."""
import json, os, glob
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)
D = "assets/user_pack/flora_v5"
SRC = "KODAK/Остров/MODELS/"
LIC = "готовая модель (скачано пользователем)"

def gsize(f):
    g = json.load(open(f))
    mn = [1e9] * 3; mx = [-1e9] * 3; tris = 0
    for n in g.get("nodes", []):
        if "mesh" not in n:
            continue
        t = n.get("translation", [0, 0, 0]); s = n.get("scale", [1, 1, 1])
        for p in g["meshes"][n["mesh"]]["primitives"]:
            a = g["accessors"][p["attributes"]["POSITION"]]
            mn = [min(x, t[i] + a["min"][i] * s[i]) for i, x in enumerate(mn)]
            mx = [max(x, t[i] + a["max"][i] * s[i]) for i, x in enumerate(mx)]
            if "indices" in p:
                tris += g["accessors"][p["indices"]]["count"] // 3
    return [round(b - a, 2) for a, b in zip(mn, mx)], tris

E = []
def add(id, name, scene, zones, collision, src, tags, lod=None, climate=True, density=1.0, cluster=0.5, shape=None, extra=None, lic=LIC):
    f = os.path.join(D, scene)
    size, tris = gsize(f)
    e = {"id": id, "name": name, "category": extra.pop("category", "plant") if extra else "plant", "scene": "res://" + f,
         "lod": ["res://" + os.path.join(D, lod)] if lod else [], "zones": zones, "size_m": size, "collision": collision,
         "hitbox": (shape or {}).get("type", "capsule"), "density": density, "cluster": cluster, "source": SRC + src,
         "license": lic, "climate_ok": climate, "tags": tags, "tris": [tris] + ([gsize(os.path.join(D, lod))[1]] if lod else [])}
    if shape:
        e["shape"] = shape
    elif collision == "soft":
        e["shape"] = {"type": "capsule", "radius": round(max(min(size[0], size[2]) * 0.3, 0.2), 2), "height": max(size[1], 0.5)}
    elif collision == "solid":
        e["shape"] = {"type": "capsule", "radius": round(max(min(size[0], size[2]) * 0.06, 0.12), 2), "height": round(min(size[1], 3.0), 2)}
    if extra:
        e.update(extra)
    E.append(e)

# --- лианы (сессия моделей, gltf как есть)
LI = {"liana_span_01": ("Лианы: сцена (2 каната, петли, занавесы)", "span"), "liana_span_braid_02": ("Лиана-жгут с овальными листьями", "span"),
      "liana_span_thorn_03": ("Лиана колючая (жгут)", "span"), "liana_span_leafy_04": ("Лиана длинная, листья-сердечки", "span"),
      "liana_hang_curtain_05": ("Занавес из тонких лиан", "hang"), "liana_hang_ivy_06": ("Плеть с плющевыми листьями", "hang"),
      "liana_climb_07": ("Лиана вьющаяся по стволу", "climb"), "liana_climb_thorn_08": ("Лиана колючая вьющаяся", "climb"),
      "liana_kit_09": ("Кит плетей (12 полос по 3 м)", "kit")}
NOTE = {"span": "провис между двумя деревьями: концы каната по X (0 и ширина), крепление ~ у верха рамки",
        "hang": "свисает с ветки: верх модели — точка крепления", "climb": "обвивает ствол: ставить в ось ствола, низ на землю",
        "kit": "набор отдельных плетей для декора"}
for k, (name, kind) in LI.items():
    sz, _ = gsize(f"{D}/lianas/{k}_lod1.gltf")
    add("flora_" + k, name, f"lianas/{k}_lod1.gltf", ["jungle", "lowland_forest", "mangrove"], "soft" if kind == "hang" else "none",
        "Plants/Лианы", ["liana", "liana_" + kind], lod=f"lianas/{k}_lod2.gltf", density=0.3, cluster=0.7, lic="модели пользователя (генератор сессии моделей)",
        shape={"type": "box", "size": [round(sz[0] * 0.8, 2), round(sz[1] * 0.8, 2), max(sz[2], 0.3)], "offset": [0, round(sz[1] * 0.5, 2), 0]} if kind == "hang" else None,
        extra={"attach": kind, "note": NOTE[kind], **({"slow": 0.8} if kind == "hang" else {})})

add("flora_strelitzia", "Стрелиция (райская птица)", "strelitzia/strelitzia.gltf", ["forest_edge", "jungle", "palm_belt", "lowland_forest"], "soft",
    "Plants/Стрелиция (готовая модель)", ["understory", "big_leaf", "flowers"], lod="strelitzia/strelitzia_lod1.gltf", density=0.4, cluster=0.6,
    shape={"type": "capsule", "radius": 0.6, "height": 1.6})
for n in "abc":
    add(f"flora_matteuccia_{n}", f"Папоротник страусник {n.upper()}", f"matteuccia/matteuccia_struthiopteris_{n}001.gltf",
        ["jungle", "lowland_forest", "mangrove", "forest_edge"], "soft", "Plants/Папоротник страусник (Matteuccia, готовая модель)", ["fern", "ground_cover"],
        lod=f"matteuccia/matteuccia_struthiopteris_{n}001_lod1.gltf", climate=False, density=0.8, cluster=0.7)
add("flora_grass_clump_razw", "Трава (кустик, готовая модель)", "grass_clump/grass_clump.gltf", ["dunes", "forest_edge", "palm_belt", "rocks"], "none",
    "Plants/Трава (готовая модель)", ["grass", "ground_cover"], density=3.0, cluster=0.6)
sz, _ = gsize(f"{D}/liana_wall/liana_wall.gltf")
add("flora_liana_wall", "Стена из лиан (без цветов)", "liana_wall/liana_wall.gltf", ["jungle", "rocks", "lowland_forest"], "soft",
    "Plants/Стена из лиан (готовая модель) — Claude используй только модель без цветов в качесвте семпла", ["liana", "wall", "hero"],
    lod="liana_wall/liana_wall_lod1.gltf", climate=False, density=0.1, cluster=0.3,
    shape={"type": "box", "size": [sz[0], sz[1], 0.5], "offset": [0, round(sz[1] / 2, 2), 0]},
    extra={"slow": 0.6, "attach": "wall", "note": "вертикальная занавесь ~5×3,4 м: к скале/стволам/руинам; тяжёлая — редко"})
GZ = {"weed": ["forest_edge", "dunes", "palm_belt"], "wasteland_gravel": ["rocks", "beach"], "wasteland_grass": ["dunes", "rocks", "forest_edge"],
      "wasteland_branches": ["jungle", "lowland_forest", "forest_edge"], "nettle": ["forest_edge", "lowland_forest"], "medium": ["forest_edge", "palm_belt", "dunes"],
      "leaves": ["jungle", "lowland_forest", "forest_edge"], "grass": ["forest_edge", "palm_belt", "dunes", "lowland_forest"], "dandelion": ["forest_edge", "palm_belt"],
      "daisies": ["forest_edge", "palm_belt"], "clump": ["forest_edge", "dunes"], "clover": ["forest_edge", "palm_belt", "lowland_forest"]}
for f in sorted(glob.glob(f"{D}/grassset/*.gltf")):
    if f.endswith("_lod1.gltf"):
        continue
    n = os.path.basename(f)[:-5]
    z = next((v for k, v in GZ.items() if n.startswith(k)), ["forest_edge"])
    deb = any(w in n for w in ("gravel", "branches", "leaves"))
    add("flora_gs_" + n, "Набор трав: " + n.replace("_", " "), f"grassset/{n}.gltf", z, "none", "Plants/Трава (готовая модель 2, огромный PLY 4.9 ГБ)/Grass.blend",
        ["ground_cover", "debris" if deb else "grass"], lod=f"grassset/{n}_lod1.gltf",
        climate=not any(w in n for w in ("nettle", "dandelion", "daisies", "clover")), density=3.0, cluster=0.7)
# --- деревья
for i, n in enumerate(["", "01", "02", "03", "04"]):
    add(f"flora_kingsville_{i + 1}", f"Самшит Kingsville {i + 1} (дерево)", f"kingsville/kingsville_wood{n}.gltf", ["lowland_forest", "forest_edge", "rocks", "jungle"], "solid",
        "Tree/Деревья Kingsville (5 видов, готовые модели)", ["broadleaf", "small_tree"], lod=f"kingsville/kingsville_wood{n}_lod1.gltf", climate=False, density=0.3, cluster=0.4,
        shape={"type": "capsule", "radius": 0.28, "height": 2.2}, extra={"category": "tree"})
for i, n in enumerate(["", "02"]):
    add(f"flora_macrozamia_{i + 1}", f"Пальма макрозамия {i + 1} (саговник)", f"macrozamia/macrozamia_moorei_palm_tall{n}.gltf", ["forest_edge", "rocks", "dunes", "palm_belt"], "solid",
        "Tree/Пальма макрозамия (Macrozamia moorei, готовая модель)", ["palm", "small_palm"], lod=f"macrozamia/macrozamia_moorei_palm_tall{n}_lod1.gltf", climate=False, density=0.3, cluster=0.5,
        shape={"type": "capsule", "radius": 0.22, "height": 2.4}, extra={"category": "tree"})
for i, n in enumerate(["a001", "a002"]):
    add(f"flora_howea_{i + 1}", f"Пальма ховея (кентия) {i + 1}", f"howea/howea_f_{n}.gltf", ["jungle", "forest_edge", "palm_belt", "lowland_forest"], "solid",
        "Tree/Пальма ховея (Howea forsteriana, готовая модель)", ["palm", "small_palm"], lod=f"howea/howea_f_{n}_lod1.gltf", density=0.5, cluster=0.6,
        shape={"type": "capsule", "radius": 0.12, "height": 2.0}, extra={"category": "tree"})

json.dump({"entries": E}, open(f"{D}/flora_v5.json", "w"), ensure_ascii=False, indent=1)
print(len(E))
