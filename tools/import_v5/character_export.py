# Blender: персонаж пользователя (Mixamo/Fuse: male.fbx + anim/*.fbx + textures) → игровой GLB с клипами.
# blender -b -P character_export.py -- <male.fbx> <папка anim> <папка textures> <out.glb>
# Клипы: idle, walk, run, jump, death (имена файлов Mixamo → роли ниже). Текстуры Fuse: Diffuse/Normal/Gloss/Opacity → PBR
# (roughness = 1 − gloss), 2K → 1K для экономии (персонажей много — боты).
import bpy, sys, os
a = sys.argv[sys.argv.index("--") + 1:]
src, animdir, texdir, out = a
ROLES = {"Idle": "idle", "Walking": "walk", "Running": "run", "Jumping": "jump", "Falling Back Death": "death"}
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src, automatic_bone_orientation=False)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
arm.name = "Character"
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o.name == "default":   # служебный кубик Fuse
        bpy.data.objects.remove(o, do_unlink=True)
for act in list(bpy.data.actions):
    bpy.data.actions.remove(act)
arm.animation_data_create()
for fn, role in ROLES.items():
    p = os.path.join(animdir, fn + ".fbx")
    if not os.path.exists(p):
        print("NO ANIM", p); continue
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=p, automatic_bone_orientation=False)
    new = [o for o in bpy.data.objects if o not in before]
    act = None
    for o in new:
        if o.type == 'ARMATURE' and o.animation_data and o.animation_data.action:
            act = o.animation_data.action
    if act:
        act.name = role
        act.use_fake_user = True
        # NLA-дорожка на основном скелете — экспортёр glTF выгрузит каждую как клип
        tr = arm.animation_data.nla_tracks.new(); tr.name = role
        st = tr.strips.new(role, int(act.frame_range[0]), act)
        st.name = role
        tr.mute = True
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    print("ANIM", role, act.frame_range[:] if act else None)
# материал
m = bpy.data.materials.get("Bodymat")
m.use_nodes = True; nt = m.node_tree
for n in list(nt.nodes):
    if n.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL"): nt.nodes.remove(n)
b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
def tex(fn, nc):
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(os.path.join(texdir, fn))
    if nc: t.image.colorspace_settings.name = "Non-Color"
    t.image.scale(1024, 1024)
    return t
nt.links.new(tex("FuseModel_Body_Diffuse.png", False).outputs[0], b.inputs["Base Color"])
inv = nt.nodes.new("ShaderNodeInvert"); nt.links.new(tex("FuseModel_Body_Gloss.png", True).outputs[0], inv.inputs["Color"])
nt.links.new(inv.outputs[0], b.inputs["Roughness"])
nm = nt.nodes.new("ShaderNodeNormalMap"); nt.links.new(tex("FuseModel_Body_Normal.png", True).outputs[0], nm.inputs["Color"])
nt.links.new(nm.outputs[0], b.inputs["Normal"])
nt.links.new(tex("FuseModel_Body_Opacity.png", True).outputs[0], b.inputs["Alpha"])
m.blend_method = 'CLIP'
b.inputs["Metallic"].default_value = 0.0
arm.animation_data.action = None
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animations=True, export_animation_mode='NLA_TRACKS',
    export_yup=True, export_force_sampling=True, export_frame_range=False)
print("EXPORTED", out, os.path.getsize(out))
