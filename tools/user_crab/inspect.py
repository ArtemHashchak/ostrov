import bpy, sys
bpy.context.preferences.filepaths.use_scripts_auto_execute = False
bpy.ops.wm.open_mainfile(filepath="/tmp/models_in/crab/crab.blend", load_ui=False, use_scripts=False)
dg = bpy.context.evaluated_depsgraph_get()
for o in bpy.data.objects:
    info = f"{o.name:30s} {o.type:9s} parent={o.parent.name if o.parent else '-'} loc={tuple(round(v,3) for v in o.location)} scale={tuple(round(v,3) for v in o.scale)} dims={tuple(round(v,3) for v in o.dimensions)}"
    if o.type=='MESH':
        me=o.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        info+=f" tris={len(me.loop_triangles)} verts={len(me.vertices)} mats={[m.name for m in o.data.materials if m]} mods={[m.type for m in o.modifiers]} vgroups={len(o.vertex_groups)}"
        o.evaluated_get(dg).to_mesh_clear()
    if o.type=='ARMATURE':
        info+=f" bones={len(o.data.bones)}"
    print(info)
print("ACTIONS", [a.name for a in bpy.data.actions])
for img in bpy.data.images:
    print("IMG", img.name, img.size[:], img.filepath, "packed" if img.packed_file else "")
for m in bpy.data.materials:
    print("MAT", m.name, m.use_nodes)
print("SCENE unit", bpy.context.scene.unit_settings.scale_length)
