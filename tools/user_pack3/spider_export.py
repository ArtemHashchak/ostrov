"""Паук-птицеед пользователя (Насекомые/Паук-птицеед/Модель/Паук_птицеед.blend, Blender 5, сжат zstd) → игровой GLB.
Без упрощения: та же сетка (тело 14.4k треуг., 4.1k карточек волосков) и скелет автора (экспорт только
деформирующих костей). Процедурные материалы хитина/брюшка (шум, вороной-бамп, полосы по атрибуту band)
запекаются Cycles в альбедо и нормали 2048 по UV автора; волоски — текстура автора (градиент по UV.y
повторяет шейдер user_spider_fur в Godot).

    python3 tools/user_pack3/spider_export.py ПУТЬ/Паук_птицеед.blend ПАПКА_ВЫВОДА
(нужен модуль bpy ≥ 5: pip install bpy) → ПАПКА/animal_spider_tarantula.glb
"""
import bpy, os, sys
SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=SRC, load_ui=False, use_scripts=False)
sc=bpy.context.scene
sc.render.engine='CYCLES'
sc.cycles.device='CPU'
sc.cycles.samples=4
body=bpy.data.objects['Spider_Body']; fur=bpy.data.objects['Spider_Fur']
# --- bake chitin + abdomen into one atlas (albedo, normal)
RES=2048
alb=bpy.data.images.new("spider_albedo",RES,RES,alpha=False)
nrm=bpy.data.images.new("spider_normal",RES,RES,alpha=False)
nrm.colorspace_settings.name='Non-Color'
bake_mats=[bpy.data.materials['Spider_Chitin'],bpy.data.materials['Spider_Abdomen']]
def set_target(img):
    for m in body.data.materials:
        nt=m.node_tree
        n=nt.nodes.get("BAKE_T") or nt.nodes.new('ShaderNodeTexImage')
        n.name="BAKE_T"; n.image=img
        nt.nodes.active=n
for o in bpy.context.view_layer.objects: o.select_set(False)
body.select_set(True); bpy.context.view_layer.objects.active=body
# rest pose for baking
rig=bpy.data.objects['Spider_Rig']; rig.data.pose_position='REST'
set_target(alb)
sc.render.bake.use_pass_direct=False; sc.render.bake.use_pass_indirect=False; sc.render.bake.use_pass_color=True
sc.render.bake.margin=8
bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'}, margin=8)
alb.filepath_raw=OUT+"/spider_albedo.png"; alb.file_format='PNG'; alb.save()
set_target(nrm)
bpy.ops.object.bake(type='NORMAL', normal_space='TANGENT', margin=8)
nrm.filepath_raw=OUT+"/spider_normal.png"; nrm.file_format='PNG'; nrm.save()
# --- replace chitin/abdomen with baked textures
for m in bake_mats:
    nt=m.node_tree
    for n in list(nt.nodes):
        if n.type not in('BSDF_PRINCIPLED','OUTPUT_MATERIAL'): nt.nodes.remove(n)
    bs=[n for n in nt.nodes if n.type=='BSDF_PRINCIPLED'][0]
    ta=nt.nodes.new('ShaderNodeTexImage'); ta.image=alb
    tn=nt.nodes.new('ShaderNodeTexImage'); tn.image=nrm
    nm=nt.nodes.new('ShaderNodeNormalMap')
    nt.links.new(ta.outputs['Color'],bs.inputs['Base Color'])
    nt.links.new(tn.outputs['Color'],nm.inputs['Color'])
    nt.links.new(nm.outputs['Normal'],bs.inputs['Normal'])
for m in body.data.materials:
    n=m.node_tree.nodes.get("BAKE_T")
    if n: m.node_tree.nodes.remove(n)
# --- fur: image color + alpha (ramp by UV.y is redone in Godot shader)
fm=bpy.data.materials['Spider_Fur']; nt=fm.node_tree
img=[n for n in nt.nodes if n.type=='TEX_IMAGE'][0].image
for n in list(nt.nodes):
    if n.type not in('BSDF_PRINCIPLED','OUTPUT_MATERIAL'): nt.nodes.remove(n)
bs=[n for n in nt.nodes if n.type=='BSDF_PRINCIPLED'][0]
ti=nt.nodes.new('ShaderNodeTexImage'); ti.image=img
nt.links.new(ti.outputs['Color'],bs.inputs['Base Color']); nt.links.new(ti.outputs['Alpha'],bs.inputs['Alpha'])
img.filepath_raw=OUT+"/spider_hair.png"; img.file_format='PNG'
try: img.save()
except Exception as e: print("hair save",e)
# --- export
for o in bpy.data.objects: o.select_set(o.name in('Spider_Body','Spider_Fur','Spider_Rig'))
bpy.ops.export_scene.gltf(filepath=OUT+"/animal_spider_tarantula.glb", export_format='GLB', use_selection=True,
    export_skins=True, export_def_bones=True, export_animations=False, export_apply=False, export_yup=True,
    export_image_format='AUTO', export_materials='EXPORT')
print("DONE")
