import bpy, numpy as np, os
from mathutils import Vector, Matrix
bpy.ops.wm.open_mainfile(filepath="/tmp/crabwork/crab_B0.blend", load_ui=False, use_scripts=False)
arm=bpy.data.objects["CAngrejo"]; me=bpy.data.objects["crab"]
# --- textures: save packed images to files
os.makedirs("/tmp/crabwork/tex",exist_ok=True)
for img in bpy.data.images:
    if img.name.startswith("crab_") and img.packed_file:
        key=img.name.split("_")[1]
        pf=img.packed_files[0] if len(img.packed_files) else img.packed_file
        d=getattr(pf,"data",None)
        if d is None: d=img.packed_file.data
        open(f"/tmp/crabwork/tex/{key}.png","wb").write(d)
        print("TEX",key,len(d))
me.data.materials.clear()
mat=bpy.data.materials.new("crab_shell"); me.data.materials.append(mat)
# --- decimate
bpy.context.view_layer.objects.active=me
me.data.calc_loop_triangles(); print("tris before",len(me.data.loop_triangles))
dec=me.modifiers.new("Dec",'DECIMATE'); dec.decimate_type='COLLAPSE'; dec.ratio=0.215
dec.use_symmetry=True; dec.symmetry_axis='X'
bpy.ops.object.modifier_move_to_index(modifier="Dec",index=0)
bpy.ops.object.modifier_apply(modifier="Dec")
me.data.calc_loop_triangles(); print("tris after",len(me.data.loop_triangles))
# remove other uv map, unused groups
uv=me.data.uv_layers
for l in list(uv):
    if l.name!="automap": uv.remove(l)
# --- scale: carapace width target 0.30 m
gi=me.vertex_groups["Bone"].index
mw=me.matrix_world
body=[mw@v.co for v in me.data.vertices if any(g.group==gi and g.weight>0.9 for g in v.groups)]
xs=[p.x for p in body]; width=max(xs)-min(xs)
allp=[mw@v.co for v in me.data.vertices]
k=0.30/width
print("carapace width",round(width,3),"scale",round(k,4))
# apply transforms: armature + mesh
for o in bpy.context.scene.objects: o.select_set(False)
arm.select_set(True); me.select_set(True); bpy.context.view_layer.objects.active=arm
arm.scale=arm.scale*k; arm.location=arm.location*k
bpy.context.view_layer.update()
bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
bpy.context.view_layer.update()
mw=me.matrix_world
allp=[mw@v.co for v in me.data.vertices]
zmin=min(p.z for p in allp)
# feet: tip of last leg bones
tips=[arm.matrix_world@arm.data.bones[n].tail_local for n in ("R.Bone.009","R.Bone.013","R.Bone.017")]
print("zmin",round(zmin,4),"foot tips z",[round(t.z,4) for t in tips])
ground=min(t.z for t in tips)
arm.location.z-=ground
bpy.context.view_layer.update()
bpy.ops.object.transform_apply(location=True,rotation=False,scale=False)
bpy.context.view_layer.update()
mw=me.matrix_world; allp=[mw@v.co for v in me.data.vertices]
for ax,i in (("x",0),("y",1),("z",2)):
    print("range",ax,round(min(p[i] for p in allp),3),round(max(p[i] for p in allp),3))
print("arm matrix",arm.matrix_world,"mesh matrix",me.matrix_world)
bpy.ops.wm.save_as_mainfile(filepath="/tmp/crabwork/crab_C.blend")
bpy.ops.export_scene.gltf(filepath="/tmp/crabwork/crab_user.glb",export_format='GLB',use_selection=False,
    export_skins=True,export_animations=False,export_yup=True,export_apply=False,export_materials='PLACEHOLDER',
    export_def_bones=False)
print("GLB",os.path.getsize("/tmp/crabwork/crab_user.glb"))
