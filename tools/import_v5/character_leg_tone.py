#!/usr/bin/env python3
"""Тон кожи ног персонажа под торс (игровая копия текстуры, извлечённая Godot при импорте GLB).
Запуск после каждого нового character_male.glb (повторный импорт может перезаписать извлечённую текстуру):
    blender -b -P - <<<'...'  — UV ног пишет /tmp/leg_uv.json (см. ниже LEG_UV_BLENDER), затем
    python3 tools/import_v5/character_leg_tone.py
Маска — UV-треугольники полигонов ниже 0,86 м (в позе покоя), только тёплые пиксели кожи (шорты не трогаем);
уровни: лёгкий контраст ×1.08 вокруг среднего ног и подгонка среднего к 0,92 × тон торса (ноги чаще на солнце)."""
import json, numpy as np
from PIL import Image, ImageDraw, ImageFilter
LEG_UV_BLENDER = """
import bpy, json
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath="assets/user_pack/characters/character_male.glb")
o=next(o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('Body'))
me=o.data; uv=me.uv_layers.active.data; mw=o.matrix_world
json.dump([[[uv[li].uv[0], uv[li].uv[1]] for li in p.loop_indices] for p in me.polygons if (mw@p.center).z<0.86], open('/tmp/leg_uv.json','w'))
"""
F = "assets/user_pack/characters/character_male_FuseModel_Body_Diffuse-FuseModel_Body_Opacity.png"
im = Image.open(F).convert('RGBA'); W, H = im.size
mask = Image.new('L', (W, H), 0); d = ImageDraw.Draw(mask)
for poly in json.load(open('/tmp/leg_uv.json')):
    d.polygon([(u * W, (1 - v) * H) for u, v in poly], fill=255)
mask = mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(3))
a = np.asarray(im).astype(float); m = np.asarray(mask).astype(float)[..., None] / 255
rgb = a[..., :3]
skin = ((rgb[..., 0] > rgb[..., 2] + 15) & (rgb[..., 0] > 60))[..., None].astype(float)
k = m * skin
tm = rgb[(skin[..., 0] > 0) & (m[..., 0] < 0.05)].mean(0); lm = rgb[k[..., 0] > 0.5].mean(0)
gain = tm * 0.92 / lm
a[..., :3] = rgb * (1 - k) + np.clip(((rgb - lm) * 1.08 + lm) * gain, 0, 255) * k
Image.fromarray(a.astype(np.uint8), 'RGBA').save(F)
print("торс", tm.round(1), "ноги было", lm.round(1), "стало", a[..., :3][k[..., 0] > 0.5].mean(0).round(1))
