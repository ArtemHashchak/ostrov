#!/usr/bin/env python3
"""Грунт-текстуры версии 5 (агент A): бесшовные наборы ≤2K → assets/user_pack/ground/<id>/
(albedo.jpg, normal.jpg, rough.jpg, ao.jpg, height.jpg) + assets/user_pack/ground/ground.json (записи каталога).
Запуск: python3 tools/import_v5/ground_textures.py <папка распакованных исходников> <папка 2k-наборов>"""
import sys, os, json
from PIL import Image, ImageOps, ImageEnhance
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets/user_pack/ground")
SRC = "KODAK/Остров/MODELS/"
A, B = sys.argv[1], sys.argv[2]
def P(*a): return os.path.join(*a)
SETS = [  # id, имя, файлы {albedo,normal,rough|gloss|spec,ao,height}, зоны, теги, источник
 ("sand", "Песок", {"albedo": P(A, "sand/sand/textures/2k/New_Graph_diffuse.png"), "normal": P(A, "sand/sand/textures/2k/New_Graph_normal.png"),
   "spec": P(A, "sand/sand/textures/2k/New_Graph_specular.png"), "ao": P(A, "sand/sand/textures/2k/New_Graph_ambientOcclusion.png"),
   "height": P(A, "sand/sand/textures/2k/New_Graph_height.png")}, ["beach", "dunes", "lagoon"], ["sand"], "Грунт/Песок"),
 ("forest_floor", "Лесная почва", {"albedo": P(B, "forest_floor/Forest_Ground001_Diffuse.png"), "normal": P(B, "forest_floor/Forest_Ground001_Normal.png"),
   "rough": P(B, "forest_floor/Forest_Ground001_Roughness.png"), "ao": P(B, "forest_floor/Forest_Ground001_Ambient Occlusion.png"),
   "height": P(B, "forest_floor/Forest_Ground001_Height.png")}, ["jungle", "lowland_forest"], ["forest_floor"], "Грунт/Лесная почва (Forest_Ground001)"),
 ("mud", "Грязь (мангры)", {"albedo": P(A, "mud/cylinder_mud_Textures/mud_basecolor.png"), "normal": P(A, "mud/cylinder_mud_Textures/mud_normal.png"),
   "rough": P(A, "mud/cylinder_mud_Textures/mud_roughness.png"), "ao": P(A, "mud/cylinder_mud_Textures/mud_Ambient_Occlusion.png"),
   "height": P(A, "mud/cylinder_mud_Textures/mud_height.png")}, ["mangrove"], ["mud", "wet"], "Грунт/Грязь (mud, текстуры)"),
 ("pebbles", "Галька", {"albedo": P(A, "pebbles/PebblesSurface_1/PebblesSurface_1Albedo.jpg"), "normal": P(A, "pebbles/PebblesSurface_1/PebblesSurface_1NormalMap.jpg"),
   "rough": P(A, "pebbles/PebblesSurface_1/PebblesSurface_1Roughness.jpg"), "ao": P(A, "pebbles/PebblesSurface_1/PebblesSurface_1AO.jpg"),
   "height": P(A, "pebbles/PebblesSurface_1/PebblesSurface_1DisplacementMap.jpg")}, ["beach", "rocks"], ["pebbles"], "Грунт/Галька (Pebbles)"),
 ("moss_stone", "Мох на камне", {"albedo": P(B, "moss_stone/Moss_Stone001_Diffuse.png"), "normal": P(B, "moss_stone/Moss_Stone001_Normal.png"),
   "rough": P(B, "moss_stone/Moss_Stone001_Roughness.png"), "ao": P(B, "moss_stone/Moss_Stone001_Ambient Occlusion.png"),
   "height": P(B, "moss_stone/Moss_Stone001_Height.png")}, ["rocks", "jungle"], ["moss", "rock"], "Грунт/Мох на камне (Moss_Stone001)"),
 ("dirt", "Земля", {"albedo": P(B, "dirt/Dirt001_Diffuse.png"), "normal": P(B, "dirt/Dirt001_Normal.png"), "rough": P(B, "dirt/Dirt001_Roughness.png"),
   "ao": P(B, "dirt/Dirt001_Ambient Occlusion.png"), "height": P(B, "dirt/Dirt001_Height.png")}, ["forest_edge", "lowland_forest", "rocks"], ["dirt"], "Грунт/Грязь (Dirt001)"),
 ("dirt_2", "Земля (вариант 2)", {"albedo": P(B, "dirt_b/Dirt001_Diffuse.png"), "normal": P(B, "dirt_b/Dirt001_Normal.png"), "rough": P(B, "dirt_b/Dirt001_Roughness.png"),
   "ao": P(B, "dirt_b/Dirt001_Ambient Occlusion.png"), "height": P(B, "dirt_b/Dirt001_Height.png")}, ["forest_edge", "palm_belt"], ["dirt"], "Грунт/Грязь (Dirt001)/Textures (2).zip"),
]
for i in range(1, 11):
    pre = "grass" if i == 10 else "Grass%03d" % i
    d = P(B, "grass_%03d" % i)
    SETS.append(("grass_%02d" % i, "Трава %d" % i, {"albedo": P(d, pre + "_Diffuse.png"), "normal": P(d, pre + "_Normal.png"), "rough": P(d, pre + "_Roughness.png"),
                 "ao": P(d, pre + "_Ambient Occlusion.png"), "height": P(d, pre + "_Height.png")}, ["forest_edge", "palm_belt", "dunes", "lowland_forest"], ["grass"],
                 "Plants/Разная трава (текстуры)/Textures.zip"))
for k in ["Stone001", "Stone005", "Stone006", "Stone007"]:
    d = P(B, "rock_" + k)
    f = {"albedo": P(d, k + "_Diffuse.png"), "normal": P(d, k + "_Normal.png"), "ao": P(d, k + "_Ambient Occlusion.png"), "height": P(d, k + "_Height.png")}
    if os.path.exists(P(d, k + "_Roughness.png")):
        f["rough"] = P(d, k + "_Roughness.png")
    else:
        f["gloss"] = P(d, k + "_Glossiness.png")
    SETS.append(("rock_" + k[-3:], "Камень " + k[-3:], f, ["rocks", "reef_crest"], ["rock", "cliff"], "Rocks/" + ("Камни StoneNNN (текстуры)" if k in ("Stone005", "Stone006") else k)))

def save(img, path, size, q=90, mode="RGB"):
    img = img.convert(mode)
    if max(img.size) > size:
        img = img.resize((size, size), Image.LANCZOS)
    img.save(path, quality=q, optimize=True)

entries = []
skipped = []
for sid, name, f, zones, tags, src in SETS:
    try:
        for k in ("albedo", "normal"):
            Image.open(f[k]).load()
    except Exception as ex:
        print("ПРОПУСК", sid, ex); skipped.append(sid); continue
    od = P(OUT, sid); os.makedirs(od, exist_ok=True)
    tex = {}
    save(Image.open(f["albedo"]), P(od, "albedo.jpg"), 2048, 90); tex["albedo"] = "albedo.jpg"
    save(Image.open(f["normal"]), P(od, "normal.jpg"), 2048, 93); tex["normal"] = "normal.jpg"
    if "rough" in f:
        r = Image.open(f["rough"]).convert("L")
    elif "gloss" in f:
        r = ImageOps.invert(Image.open(f["gloss"]).convert("L"))
    else:  # specular → шероховатость
        r = ImageOps.invert(Image.open(f["spec"]).convert("L")).point(lambda v: int(80 + v * 0.69))
    save(r, P(od, "rough.jpg"), 1024, 88, "L"); tex["roughness"] = "rough.jpg"
    if os.path.exists(f.get("ao", "")):
        save(Image.open(f["ao"]).convert("L"), P(od, "ao.jpg"), 1024, 88, "L"); tex["ao"] = "ao.jpg"
    if os.path.exists(f.get("height", "")):
        save(Image.open(f["height"]).convert("L"), P(od, "height.jpg"), 1024, 88, "L"); tex["height"] = "height.jpg"
    entries.append({"id": "ground_" + sid, "name": name, "category": "ground", "scene": "", "lod": [], "zones": zones, "size_m": [2.0, 0.0, 2.0],
                    "collision": "none", "hitbox": "box", "density": 1.0, "cluster": 0.0, "source": SRC + src, "license": "текстуры (скачано пользователем)",
                    "climate_ok": True, "tags": tags, "tex": {k: "res://assets/user_pack/ground/%s/%s" % (sid, v) for k, v in tex.items()},
                    "tile_m": 2.0 if "grass" in tags or "sand" in tags else 2.5,
                    "note": "бесшовная, OpenGL-нормаль (+Y); tile_m — рекомендуемый размер повтора, м"})
    print(sid, sorted(tex))
# мокрый песок — из сухого: темнее, глаже (D может делать это и в шейдере по маске мокрости)
od = P(OUT, "sand_wet"); os.makedirs(od, exist_ok=True)
al = Image.open(P(OUT, "sand/albedo.jpg"))
al = ImageEnhance.Brightness(ImageEnhance.Color(al).enhance(1.15)).enhance(0.62)
al.save(P(od, "albedo.jpg"), quality=90, optimize=True)
Image.open(P(OUT, "sand/normal.jpg")).save(P(od, "normal.jpg"), quality=93)
Image.open(P(OUT, "sand/rough.jpg")).point(lambda v: int(v * 0.35)).save(P(od, "rough.jpg"), quality=88)
for k in ("ao", "height"):
    if os.path.exists(P(OUT, "sand/%s.jpg" % k)):
        Image.open(P(OUT, "sand/%s.jpg" % k)).save(P(od, "%s.jpg" % k), quality=88)
e = dict(entries[0]); e.update({"id": "ground_sand_wet", "name": "Песок мокрый", "zones": ["beach", "lagoon"], "tags": ["sand", "wet"],
         "tex": {k: v.replace("/sand/", "/sand_wet/") for k, v in entries[0]["tex"].items()}, "note": "получен из «Песок»: темнее и глаже"})
entries.insert(1, e)
json.dump({"entries": entries}, open(P(OUT, "ground.json"), "w"), ensure_ascii=False, indent=1)
print(len(entries))
