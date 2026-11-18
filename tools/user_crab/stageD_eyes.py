"""Краб пака: кости глаз на стебельках (R.Eye / L.Eye) + веса стебельков, экспорт GLB.
Вход: /tmp/crabwork/crab_C.blend (после stageC). Выход: crab_D.blend, crab_user.glb (те же настройки экспорта).
Стебелёк — область меша спереди сверху панциря (|x| 0.012..0.055, z < −0.105, y > 0.235 в координатах
Godot), выращенная по рёбрам от кончиков глаз; вес — от основания (0.35) к кончику (1.0), остаток — кости Bone."""
import bpy, numpy as np, os
from mathutils import Vector
bpy.ops.wm.open_mainfile(filepath="/tmp/crabwork/crab_C.blend", load_ui=False, use_scripts=False)
arm = bpy.data.objects["CAngrejo"]; me = bpy.data.objects["crab"]
mw = me.matrix_world
P = np.array([tuple(mw @ v.co) for v in me.data.vertices])
G = np.stack([P[:, 0], P[:, 2], -P[:, 1]], 1)   # Godot: x, z, -y
nb = [[] for _ in range(len(G))]
for e in me.data.edges:
    a, b = e.vertices
    nb[a].append(b); nb[b].append(a)
region = (np.abs(G[:, 0]) > 0.012) & (np.abs(G[:, 0]) < 0.055) & (G[:, 2] < -0.105) & (G[:, 1] > 0.235)
gi = me.vertex_groups["Bone"].index
out = {}
for sgn, pre in ((-1, "R."), (1, "L.")):
    seeds = np.where(region & (np.sign(G[:, 0]) == sgn) & (G[:, 2] < -0.128) & (G[:, 1] > 0.255))[0]
    sel = set(seeds.tolist()); st = list(sel)
    while st:
        x = st.pop()
        for y in nb[x]:
            if y not in sel and region[y] and np.sign(G[y, 0]) == sgn:
                sel.add(y); st.append(y)
    idx = np.array(sorted(sel))
    tip = G[seeds].mean(0)
    # основание — нижние/задние точки стебелька
    low = idx[np.argsort(G[idx, 1] - (G[idx, 2]) * 0.5)[: max(4, len(idx) // 8)]]
    base = G[low].mean(0)
    print(pre, "verts", len(idx), "base", base.round(3), "tip", tip.round(3))
    out[pre] = (idx, base, tip)
# --- кости
bpy.context.view_layer.objects.active = arm
for o in bpy.context.scene.objects: o.select_set(False)
arm.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.data.edit_bones
inv = arm.matrix_world.inverted()
def bl(g): return inv @ Vector((g[0], -g[2], g[1]))
for pre, (idx, base, tip) in out.items():
    name = pre + "Eye"
    if name in eb: eb.remove(eb[name])
    b = eb.new(name)
    b.head = bl(base); b.tail = bl(tip)
    b.parent = eb["Bone"]
    b.use_deform = True
bpy.ops.object.mode_set(mode='OBJECT')
# --- веса
for pre, (idx, base, tip) in out.items():
    name = pre + "Eye"
    vg = me.vertex_groups.get(name) or me.vertex_groups.new(name=name)
    L = np.linalg.norm(tip - base) + 1e-6
    for i in idx:
        t = np.clip(np.dot(G[i] - base, tip - base) / (L * L), 0.0, 1.0)
        w = float(0.35 + 0.65 * t)
        vg.add([int(i)], w, 'REPLACE')
        # остаток — корневой кости
        v = me.data.vertices[int(i)]
        for g in v.groups:
            if g.group != vg.index:
                g.weight = g.weight * (1.0 - w)
bpy.ops.wm.save_as_mainfile(filepath="/tmp/crabwork/crab_D.blend")
bpy.ops.export_scene.gltf(filepath="/tmp/crabwork/crab_user_eyes.glb", export_format='GLB', use_selection=False,
    export_skins=True, export_animations=False, export_yup=True, export_apply=False, export_materials='PLACEHOLDER',
    export_def_bones=False)
print("GLB", os.path.getsize("/tmp/crabwork/crab_user_eyes.glb"))
