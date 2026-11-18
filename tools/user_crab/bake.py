import bpy
bpy.ops.wm.open_mainfile(filepath="/tmp/crabwork/crab_A.blend", load_ui=False, use_scripts=False)
sc=bpy.context.scene; sc.render.engine='CYCLES'; sc.cycles.samples=4; sc.cycles.device='CPU'
me=bpy.data.objects["crab"]
for m in list(me.modifiers): me.modifiers.remove(m)   # bake in rest
img=bpy.data.images.new("bake_col",1024,1024)
mat=me.data.materials[0]; nt=mat.node_tree
n=nt.nodes.new("ShaderNodeTexImage"); n.image=img
for x in nt.nodes: x.select=False
n.select=True; nt.nodes.active=n
me.data.uv_layers.active=me.data.uv_layers["automap"]
for o in bpy.context.scene.objects: o.select_set(False)
me.select_set(True); bpy.context.view_layer.objects.active=me
sc.render.bake.use_pass_direct=False; sc.render.bake.use_pass_indirect=False; sc.render.bake.use_pass_color=True
sc.render.bake.margin=8
bpy.ops.object.bake(type='DIFFUSE')
img.filepath_raw="/tmp/crabwork/out/crab_albedo_baked.png"; img.file_format='PNG'; img.save()
print("BAKED")
