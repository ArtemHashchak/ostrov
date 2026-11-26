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
# Ретаргет: у клипов Mixamo «без кожи» свой скелет с другой позой покоя (и бёдра в других единицах), поэтому
# действия нельзя просто перевесить — кости основного скелета копируют МИРОВОЙ поворот одноимённых костей скелета клипа
# (COPY_ROTATION, мировое пространство), результат запекается в действие (визуальные ключи) и кладётся NLA-дорожкой.
# Перемещение бёдер не копируется (ход делает код игры).
bpy.context.view_layer.objects.active = arm
for fn, role in ROLES.items():
    p = os.path.join(animdir, fn + ".fbx")
    if not os.path.exists(p):
        print("NO ANIM", p); continue
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=p, automatic_bone_orientation=False)
    new = [o for o in bpy.data.objects if o not in before]
    src = next((o for o in new if o.type == 'ARMATURE' and o.animation_data and o.animation_data.action), None)
    if src is None:
        print("NO ACTION", fn); continue
    act = src.animation_data.action
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True); bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    cons = []
    for pb in arm.pose.bones:
        if pb.name in src.pose.bones:
            c = pb.constraints.new('COPY_ROTATION'); c.target = src; c.subtarget = pb.name
            c.target_space = 'WORLD'; c.owner_space = 'WORLD'; cons.append((pb, c))
    arm.animation_data.action = None
    bpy.ops.nla.bake(frame_start=f0, frame_end=f1, only_selected=False, visual_keying=True, clear_constraints=True,
                     use_current_action=False, bake_types={'POSE'})
    baked = arm.animation_data.action
    bpy.ops.object.mode_set(mode='OBJECT')
    baked.name = role; baked.use_fake_user = True
    # без хода бёдер
    for fc in list(baked.fcurves):
        if fc.data_path.endswith('location') and 'Hips' in fc.data_path:
            baked.fcurves.remove(fc)
    arm.animation_data.action = None
    tr = arm.animation_data.nla_tracks.new(); tr.name = role
    st = tr.strips.new(role, f0, baked); st.name = role
    tr.mute = True
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.actions.remove(act)
    print("ANIM", role, (f0, f1))
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
