import bpy, numpy as np, pickle, heapq
from collections import defaultdict
bpy.ops.wm.open_mainfile(filepath="/tmp/crabwork/crab_A.blend", load_ui=False, use_scripts=False)
me=bpy.data.objects["crab"]; arm=bpy.data.objects["CAngrejo"]
mw=me.matrix_world
P=np.array([tuple(mw@v.co) for v in me.data.vertices])
gidx={g.name:g.index for g in me.vertex_groups}
W=defaultdict(dict)
for v in me.data.vertices:
    for g in v.groups: W[v.index][g.group]=g.weight
adj=defaultdict(list)
for e in me.data.edges:
    a,b=e.vertices; d=float(np.linalg.norm(P[a]-P[b])); adj[a].append((b,d)); adj[b].append((a,d))
out={}
for S in "RL":
    g3=gidx[S+".Bone.003"]; g4=gidx[S+".Bone.004"]
    claw=set(i for i in W if W[i].get(g4,0)+W[i].get(g3,0)>0.5)
    seeds=[i for i in claw if W[i].get(g3,0)>0.9]
    # graph distance from deep palm (.003 core)
    dist={i:0.0 for i in seeds}; pq=[(0.0,i) for i in seeds]
    while pq:
        d,i=heapq.heappop(pq)
        if d>dist.get(i,1e9): continue
        for j,w in adj[i]:
            if j in claw and d+w<dist.get(j,1e9):
                dist[j]=d+w; heapq.heappush(pq,(d+w,j))
    dmax=max(dist.values())
    best=None
    for frac in np.linspace(0.2,0.9,36):
        thr=dmax*frac
        sel=set(i for i,d in dist.items() if d>thr)
        comps=[];seen=set()
        for s0 in sel:
            if s0 in seen: continue
            st=[s0];seen.add(s0);c=[]
            while st:
                i=st.pop();c.append(i)
                for j,_ in adj[i]:
                    if j in sel and j not in seen: seen.add(j);st.append(j)
            comps.append(c)
        comps.sort(key=len,reverse=True)
        big=[c for c in comps if len(c)>15]
        if len(big)>=2:
            best=(frac,thr,big[:2]); break
    frac,thr,(c0,c1)=best
    print(S,"fork at frac",round(frac,2),"dmax",round(dmax,3),"sizes",len(c0),len(c1),
          "cent0",P[c0].mean(0).round(2),"cent1",P[c1].mean(0).round(2))
    out[S]=dict(dist=dist,thr=thr,c0=c0,c1=c1)
pickle.dump(out,open("/tmp/crabwork/prongs.pkl","wb"))
