"""Этап 2 летучей мыши: выравнивание позы (крен по главной оси крыльев), скелет и веса, экспорт GLB.
blender -b --disable-autoexec OUT_DIR/_bat_low.blend --python tools/user_pack2/bat_rig.py -- OUT_DIR"""
import bpy, sys, os, json, math, mathutils
import numpy as np
out = sys.argv[sys.argv.index("--") + 1]
o = bpy.data.objects["bat"]
me = o.data
P = np.array([v.co[:] for v in me.vertices])
c = P.mean(0)
Q = P - c
# главная ось = размах крыльев
w, V = np.linalg.eigh(np.cov(Q.T))
span = V[:, np.argmax(w)]
if span[0] < 0: span = -span
# голова смотрит в -Y (вид спереди из исходника): ось тела — проекция -Y на плоскость ⟂ span
fwd = np.array([0.0, -1.0, 0.0]); fwd -= span * fwd.dot(span); fwd /= np.linalg.norm(fwd)
up = np.cross(span, fwd); up /= np.linalg.norm(up)
if up[2] < 0: up = -up; fwd = np.cross(up, span)
# базис: X=span, Y=-fwd (Blender: перед = -Y), Z=up
R = np.stack([span, -fwd, up])   # строки — новые оси
Pn = (Q @ R.T)
# пол: середину тела на 0
for i, v in enumerate(me.vertices):
    v.co = mathutils.Vector(Pn[i])
me.update()
X = Pn[:, 0]; Y = Pn[:, 1]; Z = Pn[:, 2]
half = max(abs(X.min()), X.max())
print("SPAN", round(X.min(),3), round(X.max(),3), "LEN", round(Y.min(),3), round(Y.max(),3), "H", round(Z.min(),3), round(Z.max(),3))
# тело: вершины с |x| < 0.12*half
body = np.abs(X) < 0.12 * half
by = Y[body]; bz = Z[body]
head_y = by.min(); tail_y = by.max(); bzc = float(np.median(bz))
# --- скелет
arm = bpy.data.armatures.new("bat_rig"); rig = bpy.data.objects.new("bat_rig", arm)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
def bone(name, h, t, parent=None):
    b = arm.edit_bones.new(name); b.head = h; b.tail = t
    if parent: b.parent = arm.edit_bones[parent]
    return b
mid_y = float(np.median(by))
bone("root", (0, tail_y * 0.3, bzc), (0, head_y * 0.3, bzc))
bone("head", (0, head_y * 0.45, bzc), (0, head_y * 1.05, bzc), "root")
bone("legs", (0, tail_y * 0.4, bzc), (0, tail_y * 1.0, bzc), "root")
sh = 0.10 * half; el = 0.45 * half
for s, sg in (("L", 1.0), ("R", -1.0)):
    # высоту/продольное положение кости крыла берём медианой вершин в полосе
    def at(x0, x1):
        m = (X * sg > x0) & (X * sg < x1)
        return float(np.median(Y[m])), float(np.median(Z[m]))
    y1, z1 = at(sh * 0.8, sh * 1.4); y2, z2 = at(el * 0.9, el * 1.1); y3, z3 = at(half * 0.85, half * 1.0)
    bone("wing1." + s, (sg * sh, y1, z1), (sg * el, y2, z2), "root")
    bone("wing2." + s, (sg * el, y2, z2), (sg * half, y3, z3), "wing1." + s)
bpy.ops.object.mode_set(mode="OBJECT")
# --- веса (гладкие по |x|)
for g in list(o.vertex_groups): o.vertex_groups.remove(g)
names = ["root", "head", "legs", "wing1.L", "wing2.L", "wing1.R", "wing2.R"]
G = {n: o.vertex_groups.new(name=n) for n in names}
def ss(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a))); return t * t * (3 - 2 * t)
for i in range(len(X)):
    ax = abs(X[i]); s = "L" if X[i] > 0 else "R"
    w2 = ss(el * 0.75, el * 1.2, ax)
    w1 = ss(sh * 0.6, sh * 1.6, ax) * (1 - w2)
    wb = 1 - w1 - w2
    wh = wb * ss(head_y * 0.35, head_y * 0.75, -(-Y[i])) if Y[i] < 0 else 0.0
    wh = wb * ss(-head_y * 0.35, -head_y * 0.75, -Y[i]) if Y[i] < 0 else 0.0
    wl = wb * ss(tail_y * 0.45, tail_y * 0.8, Y[i]) if Y[i] > 0 else 0.0
    wr = wb - wh - wl
    for n, val in (("root", wr), ("head", wh), ("legs", wl), ("wing1." + s, w1), ("wing2." + s, w2)):
        if val > 1e-4: G[n].add([i], val, "REPLACE")
o.parent = rig
mod = o.modifiers.new("arm", "ARMATURE"); mod.object = rig
# Godot: перед модели = -Z; Blender -Y → glTF (+Y up) даёт -Z? экспорт с export_yup: Blender -Y → glTF +Z... разворот делаем в Godot.
bpy.ops.object.select_all(action="DESELECT")
bpy.ops.export_scene.gltf(filepath=os.path.join(out, "bat_user.glb"), export_format="GLB",
    export_animations=False, export_apply=False, export_yup=True, export_skins=True)
json.dump({"half_span": half, "head_y": float(head_y), "tail_y": float(tail_y), "verts": len(X),
           "tris": sum(len(p.vertices) - 2 for p in me.polygons)}, open(os.path.join(out, "_rig.json"), "w"))
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "_bat_rigged.blend"))
print("BAT_RIG_DONE")
