# Blender: предмет пользователя → GLB «в руке» по правилу HeldModels: начало — точка хвата,
# glTF +Y вдоль рукояти (к лезвию/головке), glTF −Z — вперёд (лезвие/кромка/линза).
# blender -b -P held_export.py -- <job.json>
# job: {"src", "out", "along": [x,y,z] — ось исходника, что станет «вверх вдоль рукояти»,
#       "front": [x,y,z] — ось исходника, что станет «вперёд», "grip": [x,y,z] — точка хвата в исходнике (м, после apply),
#       "scale": 1.0, "tex_max": 1024, "drop": [подстроки имён], "keep_coll": "имя коллекции" (оставить только её),
#       "materials": {...} как в creatures_export.py, "texdir": …}
import bpy, sys, os, json
from mathutils import Vector, Matrix
job = json.load(open(sys.argv[sys.argv.index("--") + 1]))
src = job["src"]; ext = os.path.splitext(src)[1].lower()
if ext == ".blend": bpy.ops.wm.open_mainfile(filepath=src)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if ext == ".fbx": bpy.ops.import_scene.fbx(filepath=src)
    elif ext == ".obj": bpy.ops.wm.obj_import(filepath=src)
    elif ext in (".glb", ".gltf"): bpy.ops.import_scene.gltf(filepath=src)
for o in list(bpy.data.objects):
    if o.type in ("LIGHT", "CAMERA") or any(d.lower() in o.name.lower() for d in job.get("drop", [])):
        bpy.data.objects.remove(o, do_unlink=True)
kc = job.get("keep_coll")
if kc:
    for o in list(bpy.data.objects):
        if kc not in [c.name for c in o.users_collection]: bpy.data.objects.remove(o, do_unlink=True)
for o in list(bpy.data.objects):
    if o.type not in ("MESH",): continue
for o in bpy.data.objects:
    o.hide_render = False; o.hide_set(False); o.hide_viewport = False
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
# применить трансформации и отцепить от пустышек
for o in meshes:
    mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
for o in list(bpy.data.objects):
    if o.type == 'EMPTY': bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.select_all(action='DESELECT')
for o in meshes: o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.make_single_user(object=True, obdata=True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# поворот: along → +Z Blender (= +Y glTF), front → +Y Blender (= −Z glTF)
al = Vector(job["along"]).normalized(); fr = Vector(job["front"]).normalized()
fr = (fr - al * fr.dot(al)).normalized(); x = fr.cross(al)
R = Matrix((x, fr, al)).to_4x4()   # строки — новые оси в старых координатах
s = float(job.get("scale", 1.0))
g = Vector(job.get("grip", (0, 0, 0)))
M = Matrix.Scale(s, 4) @ R @ Matrix.Translation(-g)
for o in meshes:
    o.data.transform(M); o.data.update()
if len(meshes) > 1:
    bpy.ops.object.join()
o = bpy.context.view_layer.objects.active; o.name = job.get("name", "Model")
tm = int(job.get("tex_max", 1024))
for im in bpy.data.images:
    if im.size[0] > tm or im.size[1] > tm:
        k = tm / max(im.size[0], im.size[1])
        try: im.scale(max(1, int(im.size[0] * k)), max(1, int(im.size[1] * k)))
        except Exception as e: print("scale fail", im.name, e)
def tex_node(nt, path, nc=False):
    n = nt.nodes.new("ShaderNodeTexImage"); n.image = bpy.data.images.load(path, check_existing=True)
    if nc: n.image.colorspace_settings.name = "Non-Color"
    if max(n.image.size) > tm: n.image.scale(tm, tm)
    return n
for mname, spec in job.get("materials", {}).items():
    for m in [m for m in bpy.data.materials if m.name == mname or mname == "*"]:
        m.use_nodes = True; nt = m.node_tree
        for n in list(nt.nodes):
            if n.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL"): nt.nodes.remove(n)
        b = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None) or nt.nodes.new("ShaderNodeBsdfPrincipled")
        out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None) or nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(b.outputs[0], out.inputs[0])
        d = spec.get("dir", job.get("texdir", ""))
        if "base" in spec: nt.links.new(tex_node(nt, os.path.join(d, spec["base"])).outputs[0], b.inputs["Base Color"])
        if "rough" in spec: nt.links.new(tex_node(nt, os.path.join(d, spec["rough"]), True).outputs[0], b.inputs["Roughness"])
        if "metal" in spec: nt.links.new(tex_node(nt, os.path.join(d, spec["metal"]), True).outputs[0], b.inputs["Metallic"])
        if "normal" in spec:
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(tex_node(nt, os.path.join(d, spec["normal"]), True).outputs[0], nm.inputs["Color"])
            nt.links.new(nm.outputs[0], b.inputs["Normal"])
os.makedirs(os.path.dirname(job["out"]), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=job["out"], export_format='GLB', export_animations=False, export_yup=True)
vs = [v.co for v in o.data.vertices]
print("BOUNDS", [round(min(v[i] for v in vs), 3) for i in range(3)], [round(max(v[i] for v in vs), 3) for i in range(3)])
print("EXPORTED", job["out"], os.path.getsize(job["out"]))
