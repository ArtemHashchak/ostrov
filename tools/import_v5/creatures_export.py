# Blender: модель пользователя → игровой GLB.
# blender -b -P creatures_export.py -- <job.json>
# job: {"src": путь (.blend/.fbx/.obj/.glb), "out": путь .glb, "keep": [имена объектов] (пусто — все MESH/ARMATURE/EMPTY с потомками),
#       "drop": [подстроки имён], "texdir": папка с текстурами (перелинковать отсутствующие картинки по имени файла),
#       "tex_max": 2048, "actions": {"старое": "новое"}, "anim": true, "scale": 1.0, "apply": true,
#       "materials": {"имя материала": {"base": "файл", "normal": "файл", "rough": "файл", "metal": "файл", "alpha": "файл", "ao": "файл"}}}
import bpy, sys, os, json
job = json.load(open(sys.argv[sys.argv.index("--") + 1]))
src = job["src"]; ext = os.path.splitext(src)[1].lower()
if ext == ".blend":
    bpy.ops.wm.open_mainfile(filepath=src)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if ext == ".fbx": bpy.ops.import_scene.fbx(filepath=src, use_anim=job.get("anim", True))
    elif ext == ".obj": bpy.ops.wm.obj_import(filepath=src)
    elif ext in (".glb", ".gltf"): bpy.ops.import_scene.gltf(filepath=src)
    elif ext == ".dae": bpy.ops.wm.collada_import(filepath=src)
# чистка сцены: свет, камеры, служебные
drop = job.get("drop", [])
for o in list(bpy.data.objects):
    if o.type in ("LIGHT", "CAMERA") or any(d.lower() in o.name.lower() for d in drop):
        bpy.data.objects.remove(o, do_unlink=True)
keep = job.get("keep")
if keep:
    keepset = set()
    def add(o):
        keepset.add(o.name)
        for c in o.children: add(c)
    for n in keep:
        if n in bpy.data.objects: add(bpy.data.objects[n])
    for o in list(bpy.data.objects):
        if o.name not in keepset:
            bpy.data.objects.remove(o, do_unlink=True)
# перелинковка картинок
texdir = job.get("texdir")
if texdir:
    files = {}
    for r, _, fs in os.walk(texdir):
        for f in fs: files[f.lower()] = os.path.join(r, f)
    for im in bpy.data.images:
        if im.packed_file or im.source != 'FILE': continue
        b = os.path.basename(bpy.path.abspath(im.filepath)).lower()
        if b in files:
            im.filepath = files[b]; im.reload()
# материалы по описанию (для FBX/OBJ без связей)
def tex_node(nt, path, non_color=False):
    n = nt.nodes.new("ShaderNodeTexImage"); n.image = bpy.data.images.load(path, check_existing=True)
    if non_color: n.image.colorspace_settings.name = "Non-Color"
    return n
for mname, spec in job.get("materials", {}).items():
    mats = [m for m in bpy.data.materials if m.name == mname or mname == "*"]
    for m in mats:
        m.use_nodes = True; nt = m.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
            out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None) or nt.nodes.new("ShaderNodeOutputMaterial")
            nt.links.new(bsdf.outputs[0], out.inputs[0])
        d = spec.get("dir", texdir or "")
        p = lambda k: os.path.join(d, spec[k])
        if "base" in spec:
            t = tex_node(nt, p("base")); nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
            if spec.get("base_alpha"): nt.links.new(t.outputs["Alpha"], bsdf.inputs["Alpha"]); m.blend_method = 'CLIP'
        if "alpha" in spec:
            t = tex_node(nt, p("alpha"), True); nt.links.new(t.outputs["Color"], bsdf.inputs["Alpha"]); m.blend_method = 'CLIP'
        if "rough" in spec:
            t = tex_node(nt, p("rough"), True); nt.links.new(t.outputs["Color"], bsdf.inputs["Roughness"])
        if "gloss" in spec:
            t = tex_node(nt, p("gloss"), True); inv = nt.nodes.new("ShaderNodeInvert")
            nt.links.new(t.outputs["Color"], inv.inputs["Color"]); nt.links.new(inv.outputs["Color"], bsdf.inputs["Roughness"])
        if "metal" in spec:
            t = tex_node(nt, p("metal"), True); nt.links.new(t.outputs["Color"], bsdf.inputs["Metallic"])
        if "normal" in spec:
            t = tex_node(nt, p("normal"), True); nm = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(t.outputs["Color"], nm.inputs["Color"]); nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        for k, v in spec.get("values", {}).items():
            bsdf.inputs[k].default_value = v
# уменьшение текстур
tmax = int(job.get("tex_max", 2048))
for im in bpy.data.images:
    if im.size[0] > tmax or im.size[1] > tmax:
        s = tmax / max(im.size[0], im.size[1])
        try:
            im.scale(max(1, int(im.size[0] * s)), max(1, int(im.size[1] * s)))
        except Exception as e:
            print("scale fail", im.name, e)
# клипы
for a in bpy.data.actions:
    nn = job.get("actions", {}).get(a.name)
    if nn: a.name = nn
    a.use_fake_user = True
if job.get("strip_actions"):
    for a in list(bpy.data.actions):
        if a.name not in job.get("actions", {}).values(): bpy.data.actions.remove(a)
# масштаб корня
sc = float(job.get("scale", 1.0))
if sc != 1.0:
    for o in bpy.data.objects:
        if o.parent is None: o.scale = [x * sc for x in o.scale]
os.makedirs(os.path.dirname(job["out"]), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=job["out"], export_format='GLB', export_animations=job.get("anim", True),
    export_apply=bool(job.get("apply", True)) and not any(o.type == 'ARMATURE' for o in bpy.data.objects),
    export_image_format='AUTO', export_yup=True, use_visible=False)
print("EXPORTED", job["out"], os.path.getsize(job["out"]))
