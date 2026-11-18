import bpy, sys, math
from mathutils import Vector
bpy.ops.wm.open_mainfile(filepath=sys.argv[-3], load_ui=False, use_scripts=False)
sc=bpy.context.scene; sc.render.use_compositing=False; sc.render.use_sequencer=False
arm=bpy.data.objects["CAngrejo"]; me=bpy.data.objects["crab"]
view=sys.argv[-2]; openf=float(sys.argv[-1])
for S in "RL":
    pb=arm.pose.bones[S+".Finger"]; pb.rotation_mode='XYZ'; pb.rotation_euler=(openf,0,0)
cols={"R.Finger":(1,0,0,1),"L.Finger":(1,0,0,1),"R.Bone.004":(0,1,0,1),"L.Bone.004":(0,1,0,1),"R.Bone.003":(0,0.3,1,1),"L.Bone.003":(0,0.3,1,1)}
names={g.index:g.name for g in me.vertex_groups}
ca=me.data.color_attributes.new("c",'FLOAT_COLOR','POINT')
for v in me.data.vertices:
    best=max(v.groups,key=lambda g:g.weight,default=None)
    ca.data[v.index].color=cols.get(names[best.group] if best else "",(0.7,0.7,0.7,1))
mat=bpy.data.materials.new("vc"); mat.use_nodes=True; nt=mat.node_tree
a=nt.nodes.new("ShaderNodeAttribute"); a.attribute_name="c"; nt.links.new(a.outputs["Color"],nt.nodes["Principled BSDF"].inputs["Base Color"])
me.data.materials.clear(); me.data.materials.append(mat)
bpy.context.view_layer.update()
dg=bpy.context.evaluated_depsgraph_get()
b=arm.data.bones["R.Bone.004"]; ctr=arm.matrix_world@((b.head_local+b.tail_local)/2)
if view=="all":
    pts=[me.matrix_world@Vector(c) for c in me.bound_box]; ctr=sum(pts,Vector())/8; size=4.0
else: size=1.2
sun=bpy.data.lights.new("s",'SUN'); sun.energy=4; so=bpy.data.objects.new("s",sun); sc.collection.objects.link(so); so.rotation_euler=(0.6,0.2,0.5)
w=bpy.data.worlds.new("w"); sc.world=w; w.use_nodes=True; w.node_tree.nodes["Background"].inputs[1].default_value=1.0
cam=bpy.data.cameras.new("c"); co=bpy.data.objects.new("c",cam); sc.collection.objects.link(co); sc.camera=co
cam.type='ORTHO'; cam.ortho_scale=size
sc.render.engine='CYCLES'; sc.cycles.samples=6; sc.render.resolution_x=480; sc.render.resolution_y=480
dirs={"top":Vector((0,0,1)),"front":Vector((0,1,0.2)),"out":Vector((-1,0.3,0.2)),"all":Vector((0.5,1,0.8))}
d=dirs["all" if view=="all" else view]
co.location=ctr+d.normalized()*10; co.rotation_euler=(ctr-co.location).to_track_quat('-Z','Y').to_euler()
sc.render.filepath=f"/tmp/crabwork/B_{sys.argv[-3][-7]}_{view}_{openf}.png"
bpy.ops.render.render(write_still=True)
