import bpy, json
bpy.ops.wm.open_mainfile(filepath="/tmp/crabwork/crab_C.blend", load_ui=False, use_scripts=False)
arm=bpy.data.objects["CAngrejo"]
def g(v): return [round(v.x,5),round(v.z,5),round(-v.y,5)]
d={b.name:{"head":g(arm.matrix_world@b.head_local),"tail":g(arm.matrix_world@b.tail_local)} for b in arm.data.bones}
json.dump(d,open("/tmp/crabwork/out/crab_user_bones.json","w"),indent=1)
print(len(d))
