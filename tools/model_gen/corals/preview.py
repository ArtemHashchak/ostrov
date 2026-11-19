# Превью кораллов: blender -b --factory-startup --disable-autoexec --python preview.py -- corals.glb out.png [lod]
import bpy, sys, math, os
from mathutils import Vector
argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]
lod = argv[2] if len(argv) > 2 else "lod0"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
obs = sorted([o for o in bpy.context.scene.objects if o.type == 'MESH' and o.name.endswith(lod)], key=lambda o: o.name)
for o in bpy.context.scene.objects:
	if o.type == 'MESH' and o not in obs:
		o.hide_render = True
cols = 6
sp = 2.6
for i, o in enumerate(obs):
	o.location = Vector(((i % cols) * sp, -(i // cols) * sp, 0))
	o.rotation_euler = (math.radians(90), 0, 0)  # glTF Y-up → обратно Z-up
	dm = max(o.dimensions)
	o.scale = (1.0,) * 3 if dm <= 0 else ((2.0 / dm),) * 3
	mat = bpy.data.materials.new("vc" + o.name)
	mat.use_nodes = True
	nt = mat.node_tree
	bsdf = nt.nodes["Principled BSDF"]
	attr = nt.nodes.new("ShaderNodeVertexColor")
	nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
	bsdf.inputs["Roughness"].default_value = 0.7
	o.data.materials.clear()
	o.data.materials.append(mat)
sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x = 1800
sc.render.resolution_y = 1100
w = bpy.data.worlds.new("w"); sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.08, 0.14, 0.3, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.6
ld = bpy.data.lights.new("sun", 'SUN'); ld.energy = 3.5
lo = bpy.data.objects.new("sun", ld); sc.collection.objects.link(lo)
lo.rotation_euler = (math.radians(40), math.radians(15), math.radians(30))
cd = bpy.data.cameras.new("cam"); cd.lens = 35
co = bpy.data.objects.new("cam", cd); sc.collection.objects.link(co); sc.camera = co
rows = (len(obs) + cols - 1) // cols
cx = (cols - 1) * sp / 2; cy = -(rows - 1) * sp / 2
co.location = Vector((cx, cy - 10.5, 6.0))
co.rotation_euler = (math.radians(62), 0, 0)
# подписи
for i, o in enumerate(obs):
	cu = bpy.data.curves.new("t" + o.name, 'FONT'); cu.body = o.name.replace("_" + lod, ""); cu.size = 0.22
	t = bpy.data.objects.new("t" + o.name, cu); sc.collection.objects.link(t)
	t.location = o.location + Vector((-0.9, -1.1, 0)); t.rotation_euler = (math.radians(58), 0, 0)
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
