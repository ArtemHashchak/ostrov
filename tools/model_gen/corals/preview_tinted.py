# Превью кораллов С ОТТЕНКОМ экземпляра (как на рифе) на тёмно-синем фоне — для сравнения с референсом.
#   blender -b --factory-startup --disable-autoexec --python preview_tinted.py -- corals.glb OUT_DIR [lod0] [type1,type2]
# На каждый вариант — отдельный кадр 800×520 (косой вид 3/4), имя <тип>_v<n>.png.
import bpy, sys, math, os
from mathutils import Vector
argv = sys.argv[sys.argv.index("--") + 1:]
src, outdir = argv[0], argv[1]
lod = argv[2] if len(argv) > 2 else "lod0"
only = argv[3].split(",") if len(argv) > 3 and argv[3] else []
os.makedirs(outdir, exist_ok=True)
# первый оттенок каждого вида (как TYPES в scripts/sea/corals/coral_pack.gd); варианты берут следующие
TINTS = {
	"corymbose": ["#A6A060", "#B8A870", "#8C8A48"],
	"lobed": ["#C84A4A", "#8A58B8", "#D85A80", "#B8406A"],
}
def hexc(h):
	h = h.lstrip("#"); return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
def srgb2lin(c):
	return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
obs = sorted([o for o in bpy.context.scene.objects if o.type == 'MESH' and o.name.endswith(lod)], key=lambda o: o.name)
if only:
	obs = [o for o in obs if o.name.split("_v")[0] in only]
sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x = 800
sc.render.resolution_y = 520
w = bpy.data.worlds.new("w"); sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.03, 0.06, 0.16, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.7
ld = bpy.data.lights.new("sun", 'SUN'); ld.energy = 3.2
lo = bpy.data.objects.new("sun", ld); sc.collection.objects.link(lo)
lo.rotation_euler = (math.radians(35), math.radians(10), math.radians(-30))
cd = bpy.data.cameras.new("cam"); cd.lens = 50
cam = bpy.data.objects.new("cam", cd); sc.collection.objects.link(cam); sc.camera = cam
for o in bpy.context.scene.objects:
	if o.type == 'MESH':
		o.hide_render = True
for o in obs:
	t = o.name.split("_v")[0]
	vi = int(o.name.split("_v")[1].split("_")[0])
	tint = TINTS.get(t, ["#FFFFFF"])
	tc = srgb2lin(hexc(tint[vi % len(tint)]))
	o.hide_render = False
	o.location = Vector((0, 0, 0))
	o.rotation_euler = (math.radians(90), 0, 0)
	mat = bpy.data.materials.new("vc" + o.name)
	mat.use_nodes = True
	nt = mat.node_tree
	bsdf = nt.nodes["Principled BSDF"]
	attr = nt.nodes.new("ShaderNodeVertexColor")
	mixn = nt.nodes.new("ShaderNodeMix"); mixn.data_type = 'RGBA'; mixn.blend_type = 'MULTIPLY'
	mixn.inputs[0].default_value = 1.0
	nt.links.new(attr.outputs["Color"], mixn.inputs[6])
	mixn.inputs[7].default_value = (tc[0], tc[1], tc[2], 1.0)
	nt.links.new(mixn.outputs[2], bsdf.inputs["Base Color"])
	bsdf.inputs["Roughness"].default_value = 0.75
	o.data.materials.clear(); o.data.materials.append(mat)
	bpy.context.view_layer.update()
	dm = max(o.dimensions)
	bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
	ctr = sum(bb, Vector()) / 8.0
	cam.location = ctr + Vector((0, -dm * 1.9, dm * 1.15))
	d = (ctr - cam.location).normalized()
	cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
	sc.render.filepath = os.path.join(outdir, o.name.replace("_" + lod, "") + ".png")
	bpy.ops.render.render(write_still=True)
	o.hide_render = True
