import bpy, bmesh, math
from mathutils import Vector
import numpy as np
bpy.ops.wm.open_mainfile(filepath="/tmp/models_in/crab/crab.blend", load_ui=False, use_scripts=False)
for o in list(bpy.data.objects):
    if o.name not in ("crab","CAngrejo"): bpy.data.objects.remove(o)
arm=bpy.data.objects["CAngrejo"]; me=bpy.data.objects["crab"]
for pb in arm.pose.bones:
    pb.rotation_quaternion=(1,0,0,0); pb.location=(0,0,0); pb.scale=(1,1,1)
for m in list(me.modifiers):
    if m.type!='ARMATURE': me.modifiers.remove(m)
# remove stray bone
bpy.context.view_layer.objects.active=arm
bpy.ops.object.mode_set(mode='EDIT')
eb=arm.data.edit_bones
if "Bone.006" in eb: eb.remove(eb["Bone.006"])
bpy.ops.object.mode_set(mode='OBJECT')
if "Bone.006" in me.vertex_groups: me.vertex_groups.remove(me.vertex_groups["Bone.006"])
mw=me.matrix_world; aw=arm.matrix_world
P=np.array([tuple(mw@v.co) for v in me.data.vertices])
gidx={g.name:g.index for g in me.vertex_groups}
def weights(name):
    gi=gidx[name]; w=np.zeros(len(P))
    for v in me.data.vertices:
        for g in v.groups:
            if g.group==gi: w[v.index]=g.weight
    return w
result={}
for S in ("R","L"):
    b=arm.data.bones[S+".Bone.004"]
    h=np.array(aw@b.head_local); t=np.array(aw@b.tail_local)
    u=(t-h); L=np.linalg.norm(u); u/=L
    w=weights(S+".Bone.004")
    idx=np.where(w>0.5)[0]
    d=P[idx]-h; s=d@u/L; perp=d-np.outer(d@u,u)
    print(S,"n",len(idx),"s range",s.min().round(2),s.max().round(2), "L",round(L,3))
    hi=idx[s>np.percentile(s,45)]
    dh=P[hi]-h; ph=dh-np.outer(dh@u,u)
    # 2-means via PCA split
    c=ph.mean(0); X=ph-c
    _,_,vt=np.linalg.svd(X,full_matrices=False); dirv=vt[0]
    proj=X@dirv
    for _ in range(20):
        a=ph[proj<0].mean(0); bb=ph[proj>=0].mean(0)
        dirv=(bb-a); dirv/=np.linalg.norm(dirv); mid=(a+bb)/2
        proj=(ph-mid)@dirv
    n0=(proj<0).sum(); n1=(proj>=0).sum()
    print(S,"clusters",n0,n1,"sep",np.linalg.norm(a-bb).round(3),"dir",dirv.round(2))
    result[S]=(h,u,L,dirv,mid,idx,s,perp)
np.save("/tmp/crabwork/P.npy",P)
import pickle; pickle.dump({k:[np.asarray(x) if not isinstance(x,float) else x for x in v] for k,v in result.items()},open("/tmp/crabwork/claw.pkl","wb"))
bpy.ops.wm.save_as_mainfile(filepath="/tmp/crabwork/crab_A.blend")
