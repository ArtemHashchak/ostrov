# Blender: печать состава файла (.blend/.fbx/.obj/.glb): объекты, треугольники, материалы, картинки, скелеты, клипы.
# blender -b -P creatures_inspect.py -- <file>
import bpy, sys, os
f = sys.argv[sys.argv.index("--") + 1]
ext = os.path.splitext(f)[1].lower()
if ext == ".blend":
    bpy.ops.wm.open_mainfile(filepath=f)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if ext == ".fbx": bpy.ops.import_scene.fbx(filepath=f)
    elif ext == ".obj": bpy.ops.wm.obj_import(filepath=f)
    elif ext in (".glb", ".gltf"): bpy.ops.import_scene.gltf(filepath=f)
    elif ext == ".dae": bpy.ops.wm.collada_import(filepath=f)
dg = bpy.context.evaluated_depsgraph_get()
tot = 0
for o in bpy.data.objects:
    tri = 0
    if o.type == 'MESH':
        m = o.evaluated_get(dg).to_mesh()
        m.calc_loop_triangles(); tri = len(m.loop_triangles)
        o.evaluated_get(dg).to_mesh_clear()
        tot += tri
    print("OBJ %-28s %-9s tri=%-7d parent=%s mats=%s dims=%s hide=%s coll=%s" % (o.name[:28], o.type, tri, o.parent.name if o.parent else "-",
        [s.material.name for s in o.material_slots if s.material][:4], tuple(round(x, 3) for x in o.dimensions), o.hide_render,
        [c.name for c in o.users_collection][:2]))
print("TOTAL_TRIS", tot)
for im in bpy.data.images:
    print("IMG", im.name, im.size[:], "packed" if im.packed_file else im.filepath)
for a in bpy.data.actions:
    print("ACT", a.name, a.frame_range[:])
