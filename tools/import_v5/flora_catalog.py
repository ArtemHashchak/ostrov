#!/usr/bin/env python3
"""Собирает assets/catalog/flora.json (контракт docs/V5_AGENTS.md п.1).

Источники:
  1) assets/user_pack/flora/flora_pack.json — растения/деревья/кокосы, уже в игре (FloraPack);
  2) assets/user_pack/rocks/rocks_report.json — камни пользователя (UserRocks);
  3) assets/user_pack/flora_v5/flora_v5.json — новые модели версии 5 (пишет tools/import_v5/flora_import.py);
  4) assets/user_pack/ground/ground.json — грунт-текстуры (category "ground").
Метаданные видов (зоны, класс столкновений, источник) — таблица SPECIES ниже.
Запуск: python3 tools/import_v5/flora_catalog.py
"""
import json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
P = lambda *a: os.path.join(ROOT, *a)
SRC = "KODAK/Остров/MODELS/"

# вид → (имя, category, zones, collision, density, cluster, source-папка, climate_ok, tags)
SPECIES = {
    "alocasia_big": ("Алоказия крупная (слоновое ухо)", "plant", ["jungle", "lowland_forest", "mangrove"], "soft", 1.0, 0.6, "Plants/Алоказия крупная (слоновое ухо)", True, ["understory", "big_leaf"]),
    "alocasia_young": ("Алоказия молодая", "plant", ["jungle", "lowland_forest", "forest_edge"], "none", 1.2, 0.6, "Plants/Алоказия молодая (мелкая)", True, ["understory"]),
    "alocasia_var": ("Алоказия пёстрая", "plant", ["jungle", "lowland_forest"], "soft", 0.7, 0.6, "Plants/Алоказия пёстрая (куст с корневищами)", True, ["understory"]),
    "colocasia1": ("Колоказия (таро), набор 1", "plant", ["mangrove", "lowland_forest", "jungle"], "soft", 1.0, 0.7, "Plants/Колоказия (набор 1)", True, ["wet", "big_leaf"]),
    "colocasia2": ("Колоказия (таро), набор 2", "plant", ["mangrove", "lowland_forest", "jungle"], "soft", 1.0, 0.7, "Plants/Колоказия (набор 2)", True, ["wet", "big_leaf"]),
    "monstera": ("Монстера", "plant", ["jungle", "lowland_forest"], "soft", 0.9, 0.5, "Plants/Монстера", True, ["understory", "big_leaf"]),
    "dieffenbachia": ("Диффенбахия", "plant", ["jungle", "lowland_forest"], "soft", 0.8, 0.5, "Plants/Диффенбахия", True, ["understory"]),
    "spathiphyllum": ("Спатифиллум", "plant", ["jungle", "lowland_forest", "mangrove"], "none", 1.0, 0.6, "Plants/Спатифиллум", True, ["understory", "flowers"]),
    "banana": ("Банан", "plant", ["jungle", "forest_edge", "lowland_forest"], "solid", 0.5, 0.7, "Plants/Банан", True, ["small_tree", "food"]),
    "palm_areca": ("Пальма арека", "plant", ["jungle", "forest_edge", "palm_belt"], "solid", 0.6, 0.5, "Plants/Пальма арека (хризалидокарпус)", True, ["small_palm"]),
    "palm_rhapis": ("Рапис (бамбуковая пальма)", "plant", ["jungle", "lowland_forest"], "soft", 0.6, 0.5, "Plants/Рапис (бамбуковая пальма)", True, ["small_palm"]),
    "palm_bush_stemless": ("Пальма кустовая без ствола", "plant", ["palm_belt", "beach", "dunes", "forest_edge"], "soft", 0.8, 0.4, "Plants/Пальма кустовая без ствола", True, ["small_palm"]),
    "palm_short_trunk": ("Пальма низкая с коротким стволом", "plant", ["palm_belt", "beach", "forest_edge"], "solid", 0.5, 0.4, "Plants/Пальма низкая с коротким стволом", True, ["small_palm"]),
    "dracaena_branched": ("Драцена ветвистая", "plant", ["jungle", "rocks", "forest_edge"], "solid", 0.4, 0.3, "Plants/Драцена ветвистая (древовидная)", True, ["small_tree"]),
    "dracaena_fragrans": ("Драцена душистая (молодая)", "plant", ["jungle", "forest_edge", "rocks"], "soft", 0.8, 0.4, "Plants/Драцена душистая (молодая, розетка)", True, []),
    "bamboo_small": ("Бамбук мелкий", "plant", ["jungle", "lowland_forest"], "soft", 0.6, 0.8, "Plants/Бамбук мелкий (кустики)", False, []),
    "sapling_umbrella": ("Саженец зонтичный", "plant", ["jungle", "forest_edge", "lowland_forest"], "soft", 0.8, 0.3, "Plants/Саженец зонтичный с перистыми листьями", True, []),
    "fern_asplenium": ("Асплениум (птичье гнездо)", "plant", ["jungle", "lowland_forest", "rocks"], "none", 1.0, 0.4, "Plants/Асплениум (папоротник «птичье гнездо»)", True, ["fern", "ground_cover"]),
    "fern_nephrolepis": ("Папоротник нефролепис", "plant", ["jungle", "lowland_forest", "mangrove"], "none", 1.2, 0.6, "Plants/Папоротник нефролепис", True, ["fern", "ground_cover"]),
    "fern_low": ("Папоротник низкий", "plant", ["jungle", "lowland_forest", "forest_edge"], "none", 1.6, 0.6, "Plants/Папоротник низкий", True, ["fern", "ground_cover"]),
    "fern_pinnate_small": ("Папоротник перистый мелкий", "plant", ["jungle", "lowland_forest", "forest_edge"], "none", 1.6, 0.6, "Plants/Папоротник перистый мелкий", True, ["fern", "ground_cover"]),
    "fern_nest": ("Папоротник-гнездо", "plant", ["jungle", "lowland_forest"], "none", 1.0, 0.5, "Plants/Папоротники", True, ["fern", "ground_cover"]),
    "fern_sword": ("Папоротник мечевидный", "plant", ["jungle", "mangrove", "lowland_forest"], "none", 1.0, 0.5, "Plants/Папоротники", True, ["fern", "ground_cover"]),
    "grass_curculigo": ("Куркулиго (пальмовая трава)", "plant", ["forest_edge", "dunes", "rocks", "palm_belt"], "none", 1.6, 0.5, "Plants/Куркулиго (пальмовая трава)", True, ["grass", "ground_cover"]),
    "shrub_ixora": ("Иксора (красные цветы)", "plant", ["forest_edge", "palm_belt", "jungle"], "soft", 0.6, 0.5, "Plants/Иксора (красные цветы)", True, ["shrub", "flowers"]),
    "shrub_bluehibiscus": ("Куст с фиолетовыми цветами", "plant", ["forest_edge", "palm_belt"], "soft", 0.6, 0.5, "Plants/Куст с фиолетовыми цветами", True, ["shrub", "flowers"]),
    "shrub_smallleaf": ("Кустарник мелколистный", "plant", ["forest_edge", "rocks", "dunes", "palm_belt"], "soft", 0.9, 0.5, "Plants/Кустарник мелколистный", True, ["shrub"]),
    "orchid_white": ("Орхидеи белые", "plant", ["jungle", "lowland_forest"], "none", 0.4, 0.5, "Plants/Орхидеи белые", True, ["flowers"]),
    "orchid_pink": ("Орхидеи розовые", "plant", ["jungle", "lowland_forest"], "none", 0.4, 0.5, "Plants/Орхидеи розовые", True, ["flowers"]),
    "orchid_white_05_epi": ("Орхидея белая (эпифит на стволе)", "plant", ["jungle"], "none", 0.3, 0.3, "Plants/Орхидеи белые", True, ["epiphyte", "flowers"]),
    "orchid_pink_05_epi": ("Орхидея розовая (эпифит на стволе)", "plant", ["jungle"], "none", 0.3, 0.3, "Plants/Орхидеи розовые", True, ["epiphyte", "flowers"]),
    "palm": ("Пальма кокосовая", "tree", ["palm_belt", "beach", "forest_edge", "dunes"], "solid", 1.0, 0.5, "Tree/Пальма кокосовая", True, ["palm", "fells_seaward"]),
    "mangrove": ("Мангровое дерево", "tree", ["mangrove"], "solid", 1.0, 0.8, "Tree/Мангры (набор)", True, ["wet"]),
    "umbrella": ("Дерево с зонтичной кроной", "tree", ["lowland_forest", "forest_edge", "jungle"], "solid", 0.6, 0.4, "Tree/Дерево с зонтичной кроной", True, ["broadleaf"]),
    "coconut": ("Кокос", "item", ["palm_belt", "beach"], "none", 0.5, 0.8, "Plants/Кокосы", True, ["food", "floats"]),
}

def species_of(i):
    if i.endswith("_epi"):
        return i
    if i.startswith("coconut"):
        return "coconut"
    parts = i.split("_")
    if parts[-1].isdigit():
        parts = parts[:-1]
    return "_".join(parts)

def r3(v):
    return [round(float(x), 2) for x in v]

def pack_entries():
    meta = json.load(open(P("assets/user_pack/flora/flora_pack.json")))
    out = []
    for i in sorted(meta):
        m = meta[i]
        sp = species_of(i)
        name, cat, zones, col, dens, clus, src, ok, tags = SPECIES.get(sp, (i, "plant", ["jungle"], "soft", 1.0, 0.5, "Plants", True, []))
        a = m.get("aabb", [0, 0, 0, 1, 1, 1])
        size = r3(a[3:6])
        e = {"id": "flora_" + i, "name": name + (" " + i.rsplit("_", 1)[-1] if i.rsplit("_", 1)[-1].isdigit() else ""),
             "category": cat, "scene": "flora_pack:" + i, "lod": ["flora_pack:" + i] if m.get("lods", 1) >= 2 else [],
             "zones": zones, "size_m": size, "collision": col, "hitbox": "capsule",
             "density": dens, "cluster": clus, "source": SRC + src, "license": "модели пользователя (пак)",
             "climate_ok": ok, "tags": tags + ["flora_pack"], "pack_id": i}
        if cat == "tree":
            # ствол: капсула по замеру радиуса у земли и высоте до кроны (ось ствола наклонна —
            # C ставит одну капсулу у основания; полные выпуклые оболочки — FloraPack.hulls)
            rad = float((m.get("radius") or [0.25])[0])
            h = float(m.get("crown_y", m.get("H", 3.0)))
            e["shape"] = {"type": "capsule", "radius": round(max(rad, 0.15), 2), "height": round(min(max(h, 1.0), 3.0), 2),
                          "offset": [round(m["axis"][0][0], 2), round(min(max(h, 1.0), 3.0) / 2, 2), round(m["axis"][0][2], 2)] if m.get("axis") else [0, 1.5, 0]}
            e["hulls"] = "FloraPack.hulls"
        elif col == "solid":
            e["shape"] = {"type": "capsule", "radius": round(max(min(size[0], size[2]) * 0.12, 0.08), 2), "height": round(min(size[1], 2.0), 2)}
        elif col == "soft":
            e["shape"] = {"type": "capsule", "radius": round(max(min(size[0], size[2]) * 0.35, 0.2), 2), "height": round(max(size[1], 0.5), 2)}
        if cat == "item":
            e["collision"] = "none"
        out.append(e)
    return out

ROCK_META = {
    "boulder_round": ("Валун округлый", ["rocks", "beach", "forest_edge", "jungle"]),
    "boulder_split": ("Валун расколотый", ["rocks", "beach", "jungle"]),
    "rock_angular": ("Камень угловатый", ["rocks", "jungle", "forest_edge"]),
    "rock_slab": ("Плита каменная", ["rocks", "beach"]),
    "rock_karst": ("Карстовый камень", ["rocks", "reef_crest"]),
    "rock_low": ("Камень низкий", ["rocks", "beach", "dunes"]),
}

def rock_entries():
    rep = json.load(open(P("assets/user_pack/rocks/rocks_report.json")))
    out = []
    for i in sorted(rep):
        name, zones = ROCK_META.get(i, (i, ["rocks"]))
        size = r3(rep[i].get("size", [1, 1, 1]))
        out.append({"id": "rock_" + i, "name": name, "category": "rock", "scene": "res://assets/user_pack/rocks/%s.glb" % i,
                    "lod": [], "zones": zones, "size_m": size, "collision": "solid", "hitbox": "box",
                    "shape": {"type": "box", "size": [round(size[0] * 0.85, 2), round(size[1] * 0.9, 2), round(size[2] * 0.85, 2)]},
                    "density": 1.0, "cluster": 0.6, "source": SRC + "Rocks", "license": "модели пользователя",
                    "climate_ok": True, "tags": ["scalable"], "note": "размер — для масштаба 1; UserRocks масштабирует"})
    return out

def extra(path):
    p = P(path)
    if not os.path.exists(p):
        return []
    d = json.load(open(p))
    return d.get("entries", d) if isinstance(d, dict) else d

def main():
    entries = pack_entries() + rock_entries() + extra("assets/user_pack/flora_v5/flora_v5.json") + extra("assets/user_pack/ground/ground.json")
    ids = set()
    for e in entries:
        assert e["id"] not in ids, e["id"]
        ids.add(e["id"])
    os.makedirs(P("assets/catalog"), exist_ok=True)
    json.dump({"version": 1, "owner": "A · Флора", "generated_by": "tools/import_v5/flora_catalog.py", "entries": entries},
              open(P("assets/catalog/flora.json"), "w"), ensure_ascii=False, indent=1)
    from collections import Counter
    print(len(entries), Counter(e["category"] for e in entries))

if __name__ == "__main__":
    main()
