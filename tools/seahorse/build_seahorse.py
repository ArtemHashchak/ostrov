# Морской конёк: .blend автора (Blender 5, 3 расцветки) → игровые GLB assets/user_pack/sea_skel/animal_seahorse_<цвет>.glb.
# Меш как есть (без децимации; части слиты в один меш), процедурные материалы плавника/глаз запечены в текстуры,
# добавлены скелет (23 кости, веса по расстоянию до костей) и процедурные клипы (idle_hover, swim, swim_fast, grip,
# grip_eat, grip_look, eat, look, startle, death). Нужен bpy ≥ 5.0 (pip install bpy; системный Blender 4.0 файл не открывает).
# Запуск: cd /tmp && <venv>/bin/python -I build_seahorse.py <blend> <out_dir> [папка_контрольных_силуэтов]
import bpy, sys, math, os
import numpy as np
from mathutils import Matrix, Vector, Quaternion

SRC, OUT = sys.argv[1], sys.argv[2]
CHECK = sys.argv[3] if len(sys.argv) > 3 else ""
COLORS = [("Yellow", 0.0), ("Lilac", 1.5), ("Red", 3.0)]
SCALE = 0.1
FPS = 30

# Точки скелета в координатах автора (X — к рылу, Z — вверх; жёлтый конёк, x-сдвиг 0).
J = {
    "J0": (-0.06, 0.62), "J1": (0.02, 0.88), "J2": (0.05, 1.10), "J3": (0.12, 1.27),
    "J5": (0.55, 1.37), "J6": (0.76, 1.34),
    "T1": (-0.17, 0.48), "T2": (-0.29, 0.36), "T3": (-0.37, 0.25), "T4": (-0.37, 0.13),
    "T5": (-0.30, 0.05), "T6": (-0.21, 0.04), "T7": (-0.16, 0.10), "T8": (-0.19, 0.17), "T9": (-0.26, 0.21),
    "GRIP": (-0.22, 0.14),
}
# имя: (голова, хвост, родитель)
SPINE = [("trunk", "J0", "J1", "root"), ("chest", "J1", "J2", "trunk"), ("neck", "J2", "J3", "chest"),
         ("head", "J3", "J5", "neck"), ("snout", "J5", "J6", "head")]
TAIL = [("tail%d" % (i + 1), a, b, ("root" if i == 0 else "tail%d" % i)) for i, (a, b) in
        enumerate(zip(["J0", "T1", "T2", "T3", "T4", "T5", "T6", "T7", "T8"], ["T1", "T2", "T3", "T4", "T5", "T6", "T7", "T8", "T9"]))]
BODY_BONES = [b[0] for b in SPINE + TAIL]


def lin2srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def M_for(dx):
    return Matrix.Scale(SCALE, 4) @ Matrix.Rotation(math.radians(90), 4, 'Z') @ Matrix.Translation((-dx, 0, 0))


def P(name, dx):
    x, z = J[name]
    return M_for(dx) @ Vector((x + dx, 0.0, z))


def seg_dist(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / max(ab @ ab, 1e-12), 0, 1)
    q = a + np.outer(t, ab)
    return np.linalg.norm(p - q, axis=1), t


def bake_eye(eye_obj, img_name):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 4
    img = bpy.data.images.new(img_name, 256, 256)
    mat = eye_obj.active_material
    nt = mat.node_tree
    tn = nt.nodes.new('ShaderNodeTexImage')
    tn.image = img
    nt.nodes.active = tn
    for o in bpy.data.objects:
        o.select_set(False)
    eye_obj.select_set(True)
    bpy.context.view_layer.objects.active = eye_obj
    bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'}, margin=8)
    img.pack()
    # материал: текстура → Base Color
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    for l in list(bsdf.inputs['Base Color'].links):
        nt.links.remove(l)
    nt.links.new(tn.outputs['Color'], bsdf.inputs['Base Color'])
    for n in list(nt.nodes):
        if n.type in ('TEX_COORD', 'SEPXYZ', 'MAP_RANGE', 'VALTORGB'):
            nt.nodes.remove(n)


def fin_texture(mat, img_name):
    nt = mat.node_tree
    nodes = {n.name: n for n in nt.nodes}
    k = nodes['Math'].inputs[1].default_value
    pw = nodes['Math.003'].inputs[1].default_value
    mix = nodes['Mix']
    A = np.array(mix.inputs['A'].default_value[:3]) if False else np.array([i for i in mix.inputs if i.identifier == 'A_Color'][0].default_value[:3])
    B = np.array([i for i in mix.inputs if i.identifier == 'B_Color'][0].default_value[:3])
    W, H = 1024, 8
    u = (np.arange(W) + 0.5) / W
    f = np.power(np.abs(np.sin(u * k)), pw)
    col = A[None, :] * (1 - f[:, None]) + B[None, :] * f[:, None]
    col = lin2srgb(col)
    px = np.ones((H, W, 4), np.float32)
    px[:, :, :3] = col[None, :, :]
    img = bpy.data.images.new(img_name, W, H)
    img.pixels = px.ravel()
    img.pack()
    tn = nt.nodes.new('ShaderNodeTexImage')
    tn.image = img
    bsdf = nodes['Principled BSDF']
    for l in list(bsdf.inputs['Base Color'].links):
        nt.links.remove(l)
    nt.links.new(tn.outputs['Color'], bsdf.inputs['Base Color'])
    for n in list(nt.nodes):
        if n.type in ('TEX_COORD', 'SEPXYZ', 'MATH', 'MIX'):
            nt.nodes.remove(n)
    print("FIN", mat.name, "k", k, "pow", pw, "A", A, "B", B, "alpha", bsdf.inputs['Alpha'].default_value)


def build(color, dx):
    bpy.ops.wm.open_mainfile(filepath=SRC, load_ui=False, use_scripts=False)
    pre = "Seahorse_" + color
    objs = [o for o in bpy.data.objects if o.name == pre or o.name.startswith(pre + "_")]
    for o in list(bpy.data.objects):
        if o not in objs:
            bpy.data.objects.remove(o, do_unlink=True)
    body = bpy.data.objects[pre]
    for o in objs:
        if o.modifiers:
            print("MODS", o.name, [m.type for m in o.modifiers])
    # процедурные материалы → текстуры
    eye = bpy.data.objects[pre + "_Eye_L"]
    bake_eye(eye, "Seahorse_Eye_" + color)
    fin_mat = bpy.data.objects[pre + "_DorsalFin"].active_material
    fin_texture(fin_mat, "Seahorse_%s_Fin" % color)
    fin_mat.name = "Seahorse_%s_Fin" % color
    bpy.data.objects[pre + "_Eye_L"].active_material.name = "Seahorse_Eye"
    # части — группы до слияния
    for o in objs:
        part = o.name[len(pre):].lstrip("_") or "Body"
        vg = o.vertex_groups.new(name="part_" + part)
        vg.add(list(range(len(o.data.vertices))), 1.0, 'REPLACE')
        # в мировые координаты
        o.data = o.data.copy()
    for o in objs:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    for o in bpy.data.objects:
        o.select_set(o in objs)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "Seahorse_" + color
    body.data.name = "Seahorse_" + color
    body.data.transform(M_for(dx))
    me = body.data
    nv = len(me.vertices)
    co = np.array([v.co[:] for v in me.vertices])
    parts = {}
    for vg in body.vertex_groups:
        if vg.name.startswith("part_"):
            parts[vg.name[5:]] = vg.index
    vpart = np.full(nv, "", dtype=object)
    for v in me.vertices:
        for g in v.groups:
            for nm, gi in parts.items():
                if g.group == gi and g.weight > 0.5:
                    vpart[v.index] = nm
    for nm in parts:
        body.vertex_groups.remove(body.vertex_groups[ "part_" + nm])
    print("PARTS", {nm: int((vpart == nm).sum()) for nm in parts}, "verts", nv, "polys", len(me.polygons))

    # --- скелет ---
    arm_data = bpy.data.armatures.new("SeahorseRig")
    arm = bpy.data.objects.new("SeahorseRig", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    for o in bpy.data.objects:
        o.select_set(o == arm)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_data.edit_bones
    lat = Vector((1, 0, 0))
    root = eb.new("root")
    root.head = P("J0", dx) * 0.5 + P("J1", dx) * 0.5
    root.tail = root.head + Vector((0, 0, 0.02))
    root.use_deform = False
    for nm, a, b, par in SPINE + TAIL:
        e = eb.new(nm)
        e.head, e.tail = P(a, dx), P(b, dx)
        e.align_roll(lat)
        e.parent = eb[par]
    g = eb.new("tail_grip")
    g.head = P("GRIP", dx)
    g.tail = g.head + Vector((0, 0, 0.01))
    g.parent = eb["tail6"]
    g.use_deform = False

    def part_co(nm):
        return co[vpart == nm]

    body_mask = vpart == "Body"
    # глаза
    eye_bones = {}
    for s in ("L", "R"):
        pc = part_co("Eye_" + s)
        c = Vector(pc.mean(0))
        e = eb.new("eye_" + s)
        e.head = c
        e.tail = c + Vector((0, 0.012, 0))
        e.align_roll(Vector((0, 0, 1)))
        e.parent = eb["head"]
        eye_bones[s] = c
    # грудные плавники: основание — ближе к шее
    a_n, b_n = np.array(eb["neck"].head), np.array(eb["head"].tail)
    for s in ("L", "R"):
        pc = part_co("PectoralFin_" + s)
        d, _ = seg_dist(pc, np.array(eb["chest"].head), np.array(eb["head"].head))
        base = pc[d <= np.quantile(d, 0.3)].mean(0)
        tip = pc[d >= np.quantile(d, 0.7)].mean(0)
        e = eb.new("pect_" + s)
        e.head, e.tail = Vector(base), Vector(tip)
        e.align_roll(Vector((0, 1, 0)))
        e.parent = eb["neck"]
    # спинной плавник: 3 кости вдоль основания
    fc = part_co("DorsalFin")
    axis = np.array(eb["trunk"].tail - eb["tail1"].tail)
    axis /= np.linalg.norm(axis)
    s_par = fc @ axis
    smin, smax = s_par.min(), s_par.max()
    dch = np.min(np.stack([seg_dist(fc, np.array(eb[n].head), np.array(eb[n].tail))[0] for n in ("tail1", "tail2", "trunk", "chest")]), axis=0)
    fin_info = []
    for i in range(3):
        lo, hi = smin + (smax - smin) * i / 3, smin + (smax - smin) * (i + 1) / 3
        sl = (s_par >= lo) & (s_par <= hi)
        ds = dch[sl]
        base = fc[sl][ds <= np.quantile(ds, 0.25)].mean(0)
        tip = fc[sl][ds >= np.quantile(ds, 0.75)].mean(0)
        e = eb.new("dfin%d" % (i + 1))
        e.head, e.tail = Vector(base), Vector(tip)
        e.align_roll(Vector((1, 0, 0)))
        e.parent = eb["trunk"]
        fin_info.append(((lo + hi) / 2))
    bone_seg = {n: (np.array(eb[n].head), np.array(eb[n].tail)) for n in BODY_BONES}
    rest = {b.name: b.matrix.copy() for b in eb}
    bpy.ops.object.mode_set(mode='OBJECT')

    # --- веса ---
    W = {n: np.zeros(nv) for n in [b.name for b in arm_data.bones]}
    D = np.stack([seg_dist(co, *bone_seg[n])[0] for n in BODY_BONES], axis=1)   # nv × nb
    inv = 1.0 / (D ** 4 + 1e-12)
    top = np.argsort(-inv, axis=1)[:, :3]
    wsum = np.zeros(nv)
    tw = np.zeros((nv, 3))
    for k in range(3):
        tw[:, k] = inv[np.arange(nv), top[:, k]]
    tw /= tw.sum(1, keepdims=True)
    tw[tw < 0.02] = 0
    tw /= tw.sum(1, keepdims=True)
    for k in range(3):
        for bi, n in enumerate(BODY_BONES):
            m = top[:, k] == bi
            W[n][m] += tw[m, k]
    # глаза — целиком к кости глаза
    for s in ("L", "R"):
        m = vpart == "Eye_" + s
        for n in BODY_BONES:
            W[n][m] = 0
        W["eye_" + s][m] = 1.0
    # грудные: к основанию — тело
    for s in ("L", "R"):
        m = vpart == "PectoralFin_" + s
        pc = co[m]
        d, _ = seg_dist(pc, np.array(rest["chest"].translation), np.array(rest["head"].translation))
        f = np.clip((d - d.min()) / max(d.max() - d.min(), 1e-6), 0, 1)
        f = f * f * (3 - 2 * f)
        f = np.clip(0.25 + 0.75 * f, 0, 1)
        for n in BODY_BONES:
            W[n][m] *= (1 - f)
        W["pect_" + s][m] = f
    # спинной: по длине основания — плавный переход между костями, к основанию — тело
    m = vpart == "DorsalFin"
    fpos = (co[m] @ axis)
    f = np.clip((dch - np.quantile(dch, 0.02)) / max(np.quantile(dch, 0.98) - np.quantile(dch, 0.02), 1e-6), 0, 1)
    f = f * f * (3 - 2 * f)
    centers = np.array(fin_info)
    wf = np.zeros((m.sum(), 3))
    for i in range(3):
        wf[:, i] = np.clip(1 - np.abs(fpos - centers[i]) / ((smax - smin) / 3), 0, 1)
    wf[fpos <= centers[0], 0] = 1
    wf[fpos >= centers[2], 2] = 1
    wf /= wf.sum(1, keepdims=True)
    for n in BODY_BONES:
        W[n][m] *= (1 - f)
    for i in range(3):
        W["dfin%d" % (i + 1)][m] = wf[:, i] * f
    tot = sum(W.values())
    print("WEIGHT sum min/max", tot.min(), tot.max(), "unweighted", int((tot < 0.5).sum()))
    for n, w in W.items():
        idx = np.nonzero(w > 1e-4)[0]
        if len(idx) == 0:
            continue
        vg = body.vertex_groups.new(name=n)
        for i in idx:
            vg.add([int(i)], float(w[i]), 'REPLACE')
    body.parent = arm
    mod = body.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm

    # --- клипы ---
    make_clips(arm, rest, axis)
    # --- экспорт ---
    os.makedirs(OUT, exist_ok=True)
    fn = os.path.join(OUT, "animal_seahorse_%s.glb" % color.lower())
    for o in bpy.data.objects:
        o.select_set(o in (arm, body))
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    bpy.ops.export_scene.gltf(filepath=fn, export_format='GLB', use_selection=True, export_animations=True,
                              export_animation_mode='ACTIONS', export_yup=True, export_apply=False,
                              export_image_format='AUTO', export_def_bones=False, export_force_sampling=True,
                              export_frame_range=False, export_anim_single_armature=True)
    print("EXPORTED", fn, os.path.getsize(fn))
    if CHECK:
        check_poses(arm, body, color)


# ============================== анимация ==============================

def smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def env(t, a, b, c, d):
    """0 до a, рост к b, держит до c, спад к d."""
    if t < a or t > d:
        return 0.0
    if t < b:
        return smooth((t - a) / max(b - a, 1e-6))
    if t <= c:
        return 1.0
    return 1.0 - smooth((t - c) / max(d - c, 1e-6))


def saccades(t, keys):
    """Ступенчатые взгляды: keys — [(время, угол)], плавный переход 0.12 с; цикл не нужен (последний = первый)."""
    v = keys[0][1]
    for i in range(1, len(keys)):
        t0, a = keys[i]
        v = v + (a - v) * smooth((t - t0) / 0.12) if t >= t0 else v
    return v


LATX, FWDY, UPZ = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))


def make_clips(arm, rest, fin_axis):
    fin_ax = Vector(fin_axis).normalized()
    neck_ax = (rest["head"].translation - rest["neck"].translation).normalized()
    tails = ["tail%d" % i for i in range(1, 10)]

    def base(t, P, curl=0.0, flutter=(5.0, 25.0), pect=(5.0, 30.0), wave=0.0, eyes=None):
        # хвост: завиток (дистальные кости сильнее)
        for i, n in enumerate(tails):
            k = 0.4 + 0.6 * i / 8
            P.setdefault(n, []).append((LATX, curl * k))
        f, a = flutter
        for i in range(3):
            P.setdefault("dfin%d" % (i + 1), []).append((fin_ax, a * math.sin(2 * math.pi * f * t - i * 1.1)))
        f, a = pect
        P.setdefault("pect_L", []).append((neck_ax, a * math.sin(2 * math.pi * f * t)))
        P.setdefault("pect_R", []).append((neck_ax, -a * math.sin(2 * math.pi * f * t + 0.4)))
        if eyes:
            for s, (yaw, pit) in eyes.items():
                P.setdefault("eye_" + s, []).append((UPZ, yaw))
                P.setdefault("eye_" + s, []).append((FWDY, pit))

    def idle(t, L):
        P = {}
        w = 2 * math.pi * t / L
        base(t, P, curl=4 + 3 * math.sin(w), flutter=(5.0, 24.0), pect=(5.0, 28.0),
             eyes={"L": (saccades(t, [(0, 0), (0.9, 18), (2.0, -8), (3.1, 0)]), saccades(t, [(0, 0), (1.4, 10), (3.3, 0)])),
                   "R": (saccades(t, [(0, 0), (0.5, -14), (1.7, 6), (2.8, 0)]), saccades(t, [(0, 0), (2.2, -9), (3.5, 0)]))})
        P.setdefault("root", []).extend([(FWDY, 3 * math.sin(w)), (LATX, 2 * math.sin(w + 1.0))])
        P.setdefault("neck", []).append((LATX, -3 * math.sin(2 * w)))
        P.setdefault("head", []).append((UPZ, 4 * math.sin(w + 0.5)))
        return P, {"root": Vector((0, 0, 0.0025 * math.sin(w)))}

    def swim(t, L, lean, curl, ff, fa):
        P = {}
        w = 2 * math.pi * t / L
        base(t, P, curl=curl + 3 * math.sin(w), flutter=(ff, fa), pect=(ff, fa + 6),
             eyes={"L": (6, 0), "R": (-6, 0)})
        P.setdefault("root", []).extend([(LATX, lean + 2 * math.sin(w)), (FWDY, 2 * math.sin(w + 0.7))])
        for i, n in enumerate(tails[2:]):
            P.setdefault(n, []).append((UPZ, 4 * math.sin(w - i * 0.6)))
        P.setdefault("head", []).append((LATX, -lean * 0.4))
        return P, {"root": Vector((0, 0, 0.0015 * math.sin(2 * w)))}

    GRIP_CURL = 15.0

    def grip(t, L):
        P = {}
        w = 2 * math.pi * t / L
        sway = 6 * math.sin(w) + 2 * math.sin(3 * w)
        base(t, P, curl=GRIP_CURL, flutter=(4.0, 18.0), pect=(4.0, 24.0),
             eyes={"L": (saccades(t, [(0, 0), (1.1, 22), (2.4, 5), (3.9, -15), (5.2, 0)]), saccades(t, [(0, 0), (2.6, 12), (4.6, 0)])),
                   "R": (saccades(t, [(0, 0), (0.7, -20), (2.9, -4), (4.4, 12), (5.6, 0)]), saccades(t, [(0, 0), (1.8, -10), (5.0, 0)]))})
        P.setdefault("root", []).extend([(LATX, sway), (FWDY, 3 * math.sin(w + 1.3))])
        P["tail2"].append((LATX, -sway * 0.7))
        P["tail3"].append((LATX, -sway * 0.3))
        P.setdefault("neck", []).append((UPZ, 8 * math.sin(w * 2 + 0.3)))
        P.setdefault("head", []).append((LATX, -4 * (0.5 + 0.5 * math.sin(w * 2))))
        return P, {}

    def eat(t, L, gripping):
        P = {}
        # наклон головы к добыче → глаза сходятся → щелчок вверх (pivot feeding) → назад
        tilt = -24 * env(t, 0.05, 0.6, 1.0, 1.05) + 14 * env(t, 1.0, 1.06, 1.12, 1.7) - 0 * t
        conv = env(t, 0.3, 0.55, 1.0, 1.4)
        base(t, P, curl=GRIP_CURL if gripping else 5.0, flutter=(5.0, 22.0), pect=(5.0, 26.0),
             eyes={"L": (22 * conv, -8 * conv), "R": (-22 * conv, 8 * conv)})
        P.setdefault("neck", []).append((LATX, tilt * 0.45))
        P.setdefault("head", []).append((LATX, tilt * 0.55))
        P.setdefault("snout", []).append((LATX, -6 * env(t, 1.0, 1.04, 1.08, 1.3)))
        P.setdefault("root", []).append((LATX, -5 * env(t, 0.1, 0.6, 1.0, 1.6)))
        return P, {}

    def look(t, L, gripping):
        P = {}
        base(t, P, curl=GRIP_CURL if gripping else 5.0, flutter=(5.0, 22.0), pect=(5.0, 26.0),
             eyes={"L": (saccades(t, [(0, 0), (0.2, 35), (0.8, -20), (1.4, 28), (2.0, 0)]),
                         saccades(t, [(0, 0), (0.5, 20), (1.1, -15), (1.8, 0)])),
                   "R": (saccades(t, [(0, 0), (0.35, -30), (0.9, 25), (1.6, -12), (2.1, 0)]),
                         saccades(t, [(0, 0), (0.6, -18), (1.3, 14), (1.9, 0)]))})
        P.setdefault("neck", []).append((UPZ, 10 * math.sin(2 * math.pi * t / L)))
        return P, {}

    def startle(t, L):
        P = {}
        e = env(t, 0.0, 0.08, 0.35, 1.0)
        base(t, P, curl=5 + 12 * e, flutter=(8.0, 40.0 * e + 20), pect=(8.0, 40.0))
        P.setdefault("neck", []).append((LATX, -14 * e))
        P.setdefault("head", []).append((LATX, -8 * e))
        P.setdefault("root", []).append((LATX, 10 * e))
        return P, {"root": Vector((0, -0.006 * e, 0))}

    def death(t, L):
        P = {}
        e = smooth(t / L)
        base(t, P, curl=5 - 18 * e, flutter=(5.0, 22 * (1 - e)), pect=(5.0, 26 * (1 - e)))
        P.setdefault("root", []).append((FWDY, 75 * e))
        P.setdefault("neck", []).append((LATX, -20 * e))
        P.setdefault("head", []).append((LATX, -10 * e))
        return P, {"root": Vector((0, 0, -0.01 * e))}

    clips = [
        ("idle_hover", 4.0, idle),
        ("swim", 2.0, lambda t, L: swim(t, L, -10.0, 6.0, 6.0, 30.0)),
        ("swim_fast", 1.2, lambda t, L: swim(t, L, -22.0, -4.0, 7.5, 36.0)),
        ("grip", 6.0, grip),
        ("eat", 1.8, lambda t, L: eat(t, L, False)),
        ("grip_eat", 1.8, lambda t, L: eat(t, L, True)),
        ("look", 2.2, lambda t, L: look(t, L, False)),
        ("grip_look", 2.2, lambda t, L: look(t, L, True)),
        ("startle", 1.0, startle),
        ("death", 2.0, death),
    ]
    arm.animation_data_create()
    bones = arm.pose.bones
    rq = {n: m.to_quaternion() for n, m in rest.items()}
    for pb in bones:
        pb.rotation_mode = 'QUATERNION'
    for name, L, fn in clips:
        act = bpy.data.actions.new(name)
        arm.animation_data.action = act
        nfr = int(round(L * FPS))
        for fr in range(nfr + 1):
            t = fr / FPS
            rots, locs = fn(t, L)
            for pb in bones:
                q = Quaternion()
                for ax, deg in rots.get(pb.name, []):
                    la = rq[pb.name].inverted() @ ax
                    q = q @ Quaternion(la, math.radians(deg))
                pb.rotation_quaternion = q
                lv = locs.get(pb.name, Vector())
                pb.location = rq[pb.name].inverted() @ lv
                pb.keyframe_insert("rotation_quaternion", frame=fr + 1)
                if pb.name == "root":
                    pb.keyframe_insert("location", frame=fr + 1)
        act.use_fake_user = True
        tr = arm.animation_data.nla_tracks.new()
        tr.name = name
        st = tr.strips.new(name, 1, act)
        tr.mute = True
        print("CLIP", name, nfr + 1, "frames")
    arm.animation_data.action = None


def check_poses(arm, body, color):
    """Контроль: силуэты (сбоку и спереди) нескольких кадров клипов."""
    sc = bpy.context.scene
    acts = ["idle_hover", "grip", "grip_eat", "swim_fast", "startle", "death"]
    Wd, Hd = 260, 300
    tiles = []
    for an in acts:
        act = bpy.data.actions[an]
        arm.animation_data.action = act
        fr_end = int(act.frame_range[1])
        for fr in (1, max(1, int(fr_end * 0.6))):
            sc.frame_set(fr)
            dg = bpy.context.evaluated_depsgraph_get()
            ev = body.evaluated_get(dg)
            vs = np.array([v.co[:] for v in ev.to_mesh().vertices])
            ev.to_mesh_clear()
            img = np.zeros((Hd, Wd * 2, 3), np.float32)
            for side, (ia, ib) in enumerate(((1, 2), (0, 2))):
                x = vs[:, ia]
                z = vs[:, 2]
                px = ((x + 0.11) / 0.22 * Wd).astype(int) + side * Wd
                pz = ((0.175 - z) / 0.21 * Hd).astype(int)
                ok = (px >= side * Wd) & (px < (side + 1) * Wd) & (pz >= 0) & (pz < Hd)
                img[pz[ok], px[ok]] = (0.9, 0.9, 0.9)
            img[:, Wd - 1] = (0.3, 0.3, 0.8)
            tiles.append(img)
    rows = [np.concatenate(tiles[i:i + 2], axis=1) for i in range(0, len(tiles), 2)]
    full = np.concatenate(rows, axis=0)
    H, W2 = full.shape[:2]
    im = bpy.data.images.new("chk", W2, H)
    px = np.ones((H, W2, 4), np.float32)
    px[:, :, :3] = full[::-1]
    im.pixels = px.ravel()
    im.filepath_raw = os.path.join(CHECK, "check_%s.png" % color)
    im.file_format = 'PNG'
    im.save()
    arm.animation_data.action = None


only = os.environ.get("SH_ONLY", "")
for c, dx in COLORS:
    if only and c != only:
        continue
    build(c, dx)
