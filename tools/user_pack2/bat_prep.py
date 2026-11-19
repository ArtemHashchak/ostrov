"""Летучая мышь пользователя (Птицы/Flying+Bat_FBX.zip, «Flying Bat.fbx», ~385k треуг., без скелета)
→ assets/user_pack/animals/bat/bat_user.glb
blender -b --disable-autoexec --python tools/user_pack2/bat_prep.py -- "Flying Bat.fbx" OUT_DIR
Части сливаются, сетка упрощается до бюджета (Decimate collapse), текстура 1024.
Скелет строится по геометрии: тело, голова, по 2 кости крыла (плечо/кисть) с каждой стороны,
ноги-хвост; веса — гладкие по размаху крыла (надёжнее «тепловых» на скан-сетке)."""
import bpy, sys, os, json, mathutils, math
a = sys.argv[sys.argv.index("--") + 1:]
src, out = a[0], a[1]
os.makedirs(out, exist_ok=True)
TARGET = int(os.environ.get("BAT_TRIS", "3000"))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
for o in bpy.data.objects:
    o.select_set(o in meshes)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
o = bpy.context.view_layer.objects.active
o.name = "bat"
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
# сварка дублей по швам частей
bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.remove_doubles(threshold=0.0005); bpy.ops.object.mode_set(mode="OBJECT")
before = sum(len(p.vertices) - 2 for p in o.data.polygons)
dm = o.modifiers.new("dec", "DECIMATE"); dm.decimate_type = "COLLAPSE"; dm.ratio = TARGET / before
dm.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier="dec")
after = sum(len(p.vertices) - 2 for p in o.data.polygons)
# оставить один UV-слой
while len(o.data.uv_layers) > 1:
    o.data.uv_layers.remove(o.data.uv_layers[-1])
bpy.ops.object.shade_smooth()
# геометрия: оси
vs = [o.matrix_world @ v.co for v in o.data.vertices]
mn = mathutils.Vector([min(v[i] for v in vs) for i in range(3)])
mx = mathutils.Vector([max(v[i] for v in vs) for i in range(3)])
ext = mx - mn
print("EXT", tuple(round(e, 3) for e in ext), "MIN", tuple(round(e,3) for e in mn), "MAX", tuple(round(e,3) for e in mx))
# текстура
for img in bpy.data.images:
    if img.size[0] > 1024:
        img.scale(1024, 1024)
    nm = "bat_" + os.path.splitext(img.name)[0] + ".png"
    p = os.path.join(out, nm)
    img.filepath_raw = p; img.file_format = "PNG"; img.save()
    if img.packed_file:
        img.unpack(method="REMOVE")
    img.filepath = p
json.dump({"before": before, "after": after, "ext": list(ext), "min": list(mn), "max": list(mx)}, open(os.path.join(out, "_geo.json"), "w"))
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "_bat_low.blend"))
print("BAT_STAGE1", before, after)
