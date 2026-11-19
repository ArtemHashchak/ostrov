"""Ящерица пользователя (Ящерицы/lizard_model.blend) → assets/user_pack/animals/lizard/lizard_user.glb
blender -b --disable-autoexec lizard_model.blend --python tools/user_pack2/lizard_prep.py -- OUT_DIR
Сабсёрф снимается, тело упрощается (Decimate collapse, веса сохраняются), текстуры 1024,
экспорт только деформирующих костей, без анимаций (анимация процедурная в Godot)."""
import bpy, sys, os, json
out = sys.argv[sys.argv.index("--") + 1]
os.makedirs(out, exist_ok=True)
TARGET = {"lizard_base": 4200, "lizard_spikes": 700, "eye_left": 160, "eye_right": 160}
rig = bpy.data.objects["lizard_rig"]
# убрать лишнее
for o in list(bpy.data.objects):
    if o != rig and o.parent != rig:
        bpy.data.objects.remove(o, do_unlink=True)
rep = {}
for name, tgt in TARGET.items():
    o = bpy.data.objects[name]
    for m in list(o.modifiers):
        if m.type == "SUBSURF":
            o.modifiers.remove(m)
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    if tris > tgt:
        bpy.context.view_layer.objects.active = o
        dm = o.modifiers.new("dec", "DECIMATE")
        dm.decimate_type = "COLLAPSE"
        dm.ratio = tgt / tris
        dm.use_collapse_triangulate = True
        # decimate должен идти до armature
        while o.modifiers.find("dec") > 0:
            bpy.ops.object.modifier_move_up(modifier="dec")
        bpy.ops.object.modifier_apply(modifier="dec")
    rep[name] = [tris, sum(len(p.vertices) - 2 for p in o.data.polygons)]
# текстуры: распаковать, уменьшить до 1024, записать рядом
for img in bpy.data.images:
    if img.size[0] == 0:
        continue
    if img.packed_file:
        img.unpack(method="USE_ORIGINAL") if False else None
    w, h = img.size
    if w > 1024:
        img.scale(1024, 1024)
    base = os.path.splitext(os.path.basename(img.name))[0].replace(".png", "")
    p = os.path.join(out, "lizard_" + base + ".png")
    img.filepath_raw = p
    img.file_format = "PNG"
    img.save()
    if img.packed_file:
        img.unpack(method="REMOVE")
    img.filepath = p
# кости: координаты ключевых
bones = {}
for b in rig.data.bones:
    if b.use_deform:
        bones[b.name] = [list(rig.matrix_world @ b.head_local), list(rig.matrix_world @ b.tail_local), b.parent.name if b.parent else None]
json.dump({"tris": rep, "bones": bones}, open(os.path.join(out, "_prep_report.json"), "w"), indent=1)
bpy.ops.export_scene.gltf(filepath=os.path.join(out, "lizard_user.glb"), export_format="GLB",
    export_def_bones=True, export_animations=False, export_apply=True, export_yup=True,
    export_image_format="AUTO", export_skins=True)
print("PREP_DONE", rep, "deform bones", len(bones))
