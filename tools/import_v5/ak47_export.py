# Blender: АК-47 пользователя (Оружие/Автомат АК-47/Ak47.fbx + textures_AK47.zip) → игровой GLB с подвижными деталями.
# blender -b -P ak47_export.py -- <Ak47.fbx> <папка текстур> <out.glb>
# Контракт docs/V5_AGENTS.md №3: узлы BoltCarrier (затворная рама с рукояткой взведения), Trigger, Selector,
# Magazine + маркеры muzzle, ejection_port, ads_anchor. Ориентация как у процедурного «rifle» (SupplyModels.rifle):
# ствол в −Z (glTF), правая сторона +X, спусковой крючок в (0, 0.017, −0.02) — модель садится в руки на то же место.
# Начала узлов — на осях вращения: спуск — ось пальца, переводчик — ось рычага, магазин — передний зацеп.
import bpy, sys, os
from mathutils import Vector, Matrix
a = sys.argv[sys.argv.index("--") + 1:]
src, texdir, out = a[0], a[1], a[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src)
root_old = bpy.data.objects["Ak47"]
# всё в мировые координаты, без родителя
for o in list(bpy.data.objects):
    if o.type == 'MESH':
        mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
bpy.data.objects.remove(root_old, do_unlink=True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# разворот на 180° вокруг Z (ствол → +Y Blender = −Z glTF) и сдвиг: спуск в (0, 0.02, 0.017) Blender
OFF = Vector((0.0, -0.034, -0.023))
M = Matrix.Translation(OFF) @ Matrix.Rotation(3.14159265, 4, 'Z')
for o in bpy.data.objects:
    o.data.transform(M)
    o.data.update()
def obj(n): return bpy.data.objects[n]
def set_origin(o, p):
    p = Vector(p)
    o.data.transform(Matrix.Translation(-p)); o.location = p
def join(names, into):
    bpy.ops.object.select_all(action='DESELECT')
    for n in names: obj(n).select_set(True)
    bpy.context.view_layer.objects.active = obj(into)
    bpy.ops.object.join()
    return obj(into)
recv = join(["m_gun", "m_magrel"], "m_gun"); recv.name = "Receiver"
mag = join(["m_mag", "m_maglid"], "m_mag"); mag.name = "Magazine"
bolt = obj("m_shelleject"); bolt.name = "BoltCarrier"
trig = obj("m_trigger"); trig.name = "Trigger"
sel = obj("m_fireselect"); sel.name = "Selector"
R = lambda x, y, z: Vector((-x, -y, z)) + OFF   # старые координаты FBX → новые
set_origin(trig, R(0.0, -0.054, 0.054))
set_origin(sel, R(-0.024, -0.02, 0.08))
set_origin(mag, R(0.0, -0.25, 0.08))
set_origin(bolt, R(-0.0275, -0.1665, 0.1025))
root = bpy.data.objects.new("AK47", None); bpy.context.scene.collection.objects.link(root)
for o in (recv, mag, bolt, trig, sel):
    o.parent = root
def marker(name, p):
    e = bpy.data.objects.new(name, None); bpy.context.scene.collection.objects.link(e)
    e.location = Vector(p); e.parent = root; e.empty_display_size = 0.01
marker("muzzle", R(0.0, -0.622, 0.0835))
marker("ejection_port", R(-0.035, -0.1665, 0.1025))
marker("ads_anchor", R(0.0, -0.2, 0.136))
marker("Mag", R(0.0, -0.19, -0.02))
marker("Forend", R(0.0, -0.36, 0.06))
# материал
m = bpy.data.materials.get("T_AK47")
m.use_nodes = True; nt = m.node_tree
for n in list(nt.nodes):
    if n.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL"): nt.nodes.remove(n)
b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
def tex(fn, nc):
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(os.path.join(texdir, fn))
    if nc: t.image.colorspace_settings.name = "Non-Color"
    if t.image.size[0] > 2048: t.image.scale(2048, 2048)
    return t
nt.links.new(tex("ak47_mat_albedo.jpg", False).outputs[0], b.inputs["Base Color"])
nt.links.new(tex("ak47_mat_roughness.jpg", True).outputs[0], b.inputs["Roughness"])
nt.links.new(tex("ak47_mat_metallic.jpg", True).outputs[0], b.inputs["Metallic"])
nm = nt.nodes.new("ShaderNodeNormalMap"); nt.links.new(tex("ak47_mat_normal.jpg", True).outputs[0], nm.inputs["Color"])
nt.links.new(nm.outputs[0], b.inputs["Normal"])
os.makedirs(os.path.dirname(out), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animations=False, export_yup=True)
print("EXPORTED", out, os.path.getsize(out))
