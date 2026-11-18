import bpy, numpy as np, pickle, sys
from mathutils import Vector
bpy.ops.wm.open_mainfile(filepath="/tmp/crabwork/crab_A.blend", load_ui=False, use_scripts=False)
arm=bpy.data.objects["CAngrejo"]; me=bpy.data.objects["crab"]
mw=me.matrix_world; awi=arm.matrix_world.inverted()
P=np.array([tuple(mw@v.co) for v in me.data.vertices])
pr=pickle.load(open("/tmp/crabwork/prongs.pkl","rb"))
which=int(sys.argv[-1])
info={}
for S in "RL":
    d=pr[S]; dist=d["dist"]; thr=d["thr"]
    mov=d["c0"] if which==0 else d["c1"]; fix=d["c1"] if which==0 else d["c0"]
    cm=P[mov].mean(0); cf=P[fix].mean(0)
    dmax=max(dist.values())
    movset=set(mov)
    # hinge band: verts with dist in [thr-0.12*dmax, thr] closer to mov centroid side than fix
    band=[i for i,dd in dist.items() if thr-0.12*dmax<=dd<=thr and i not in movset]
    sep=(cm-cf); sep/=np.linalg.norm(sep)
    mid=(cm+cf)/2
    band_m=[i for i in band if (P[i]-mid)@sep>0]
    g=me.vertex_groups.new(name=S+".Finger")
    for vi in mov:
        v=me.data.vertices[vi]
        for gg in list(v.groups): me.vertex_groups[gg.group].remove([vi])
        g.add([vi],1.0,'REPLACE')
    for vi in band_m:
        dd=dist[vi]; t=(dd-(thr-0.12*dmax))/(0.12*dmax)
        v=me.data.vertices[vi]
        for gg in list(v.groups): gg.weight*= (1-t*0.9)
        g.add([vi],t*0.9,'REPLACE')
    base_sel=[i for i in mov if dist[i]<thr+0.06*dmax]
    base=P[base_sel].mean(0)
    tipm=P[[i for i in mov if dist[i]>np.percentile([dist[j] for j in mov],90)]].mean(0)
    tipf=P[[i for i in fix if dist[i]>np.percentile([dist[j] for j in fix],90)]].mean(0)
    info[S]=(base,tipm,tipf)
    print(S,"mov",len(mov),"band",len(band_m),"base",base.round(2),"tip",tipm.round(2),"fixtip",tipf.round(2))
bpy.context.view_layer.objects.active=arm
bpy.ops.object.mode_set(mode='EDIT')
for S,(base,tipm,tipf) in info.items():
    b=arm.data.edit_bones.new(S+".Finger")
    b.head=awi@Vector(base); b.tail=awi@Vector(tipm)
    b.parent=arm.data.edit_bones[S+".Bone.004"]; b.use_connect=False
    b.align_roll(awi.to_3x3()@Vector(tipf-tipm))
    f=arm.data.edit_bones.new(S+".FixTip")
    f.head=awi@Vector(tipf); f.tail=awi@Vector(tipf+ (tipf-base)*0.2)
    f.parent=arm.data.edit_bones[S+".Bone.004"]; f.use_deform=False
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.wm.save_as_mainfile(filepath=f"/tmp/crabwork/crab_B{which}.blend")
