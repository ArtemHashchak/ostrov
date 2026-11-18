"""Разметка вершин моделей морского пака пользователя для процедурной анимации вблизи.

Вход: JSON вершин/индексов (дамп из Godot: tools/folder_anim/dump_mesh.gd).
Выход: JSON на вершину: c0 = (номер щупальца, t вдоль щупальца 0..1, 0, «тело» 0/1),
c1 = (направление основания щупальца xyz, расстояние от центра до основания).
Режимы:
  octopus — щупальца отделяются шаром вокруг «узла» под мантией; t — геодезическое
            расстояние по рёбрам меша от края шара (свернутые щупальца размечаются верно);
  squid   — ось тела по X (мантия −X, щупальца +X); номер щупальца — сектор вокруг оси;
  fish    — c0 = (t вдоль тела 0 голова..1 хвост, вес грудного плавника, сторона, вес хвост. плавника).
Запуск: python3 -I seg_rig.py <mode> <in.json> <out.json>
"""
import json, sys, heapq
import numpy as np

mode, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(src))
v = np.array(d["v"], float)
idx = np.array(d["i"]).reshape(-1, 3) if d["i"] else np.arange(len(v)).reshape(-1, 3)

# сварка совпадающих вершин (UV-швы, «суп» треугольников)
key = {}
w = np.zeros(len(v), int)
for k, p in enumerate(np.round(v, 4)):
    w[k] = key.setdefault(tuple(p), len(key))
N = len(key)
P = np.zeros((N, 3))
for k in range(len(v)):
    P[w[k]] = v[k]
nb = [set() for _ in range(N)]
for a, b, c in w[idx]:
    for x, y in ((a, b), (b, c), (c, a)):
        if x != y:
            nb[x].add(y); nb[y].add(x)


def comps(mask):
    lab = -np.ones(N, int); L = 0
    for s in np.where(mask)[0]:
        if lab[s] >= 0:
            continue
        st = [s]; lab[s] = L
        while st:
            x = st.pop()
            for y in nb[x]:
                if mask[y] and lab[y] < 0:
                    lab[y] = L; st.append(y)
        L += 1
    return lab, L


def dijkstra(sources, mask):
    g = np.full(N, np.inf)
    h = []
    for s in sources:
        g[s] = 0.0; h.append((0.0, s))
    heapq.heapify(h)
    while h:
        gg, x = heapq.heappop(h)
        if gg > g[x]:
            continue
        for y in nb[x]:
            if not mask[y]:
                continue
            ng = gg + np.linalg.norm(P[x] - P[y])
            if ng < g[y]:
                g[y] = ng; heapq.heappush(h, (ng, y))
    return g


c0 = np.zeros((N, 4)); c1 = np.zeros((N, 4))
c0[:, 3] = 1.0
report = {}

if mode == "octopus":
    lab0, _ = comps(np.ones(N, bool))
    M = lab0 == np.bincount(lab0).argmax()
    best = None
    for hy in np.linspace(P[M, 1].min(), P[M, 1].max(), 9):
        for hz in np.linspace(-0.12, 0.12, 9):
            hub = np.array([0.0, hy, hz])
            dist = np.linalg.norm(P - hub, axis=1)
            for R in np.linspace(0.06, 0.25, 14):
                lab, L = comps(M & (dist > R))
                if not L:
                    continue
                cnt = np.bincount(lab[lab >= 0])
                bigm = cnt >= 0.015 * M.sum()
                big = int(bigm.sum())
                sc = (big if 8 <= big <= 9 else 0) * 10 + cnt[bigm].sum() / M.sum()
                if best is None or sc > best[0]:
                    best = (sc, hub, R)
    _, hub, R = best
    dist = np.linalg.norm(P - hub, axis=1)
    lab, L = comps(M & (dist > R))
    cnt = np.bincount(lab[lab >= 0])
    arms = [k for k in range(L) if cnt[k] >= 0.015 * M.sum()]
    # мантия — самая высокая компонента (её центр выше всех), остальное — щупальца
    cy = {k: P[lab == k, 1].mean() for k in arms}
    mantle = max(arms, key=lambda k: cy[k]) if len(arms) > 8 else None
    arms = [k for k in arms if k != mantle]
    info = []
    for k in arms:
        vs = np.where(lab == k)[0]
        inner = set(np.where(~(dist > R) & M)[0])
        border = [x for x in vs if any(y in inner for y in nb[x])]
        if not border:
            border = list(vs[np.argsort(dist[vs])[:4]])
        g = dijkstra(border, lab == k)
        base = P[border].mean(0)
        dirv = base - hub
        dirv[1] *= 0.35  # основание почти горизонтально — сгиб «вверх» к спине
        dirv /= np.linalg.norm(dirv) + 1e-6
        info.append((np.arctan2(dirv[2], dirv[0]), vs, g, base, dirv))
    info.sort(key=lambda a: a[0])
    for j, (ang, vs, g, base, dirv) in enumerate(info):
        gm = g[vs].max()
        c0[vs, 0] = j
        c0[vs, 1] = np.clip(g[vs] / max(gm, 1e-4), 0, 1)
        c0[vs, 3] = 0.0
        c1[vs, 0:3] = dirv
        c1[vs, 3] = np.linalg.norm((base - hub) * [1, 0, 1])
    report = {"hub": hub.tolist(), "R": float(R), "arms": len(info),
              "arm_len": [float(a[2][a[1]].max()) for a in info]}
    c1[c0[:, 3] > 0.5, 0:3] = 0
    # pivot (центр) — в hub: передаём через отчёт, шейдер берёт uniform
elif mode == "squid":
    # ось X: мантия у −X, щупальца у +X
    x = P[:, 0]
    xs = np.percentile(x, 45)
    cyz = P[x < xs][:, 1:3].mean(0)
    xm = x.max()
    arm = x > xs
    t = np.clip((x - xs) / max(xm - xs, 1e-4), 0, 1)
    ang = np.arctan2(P[:, 1] - cyz[0], P[:, 2] - cyz[1])
    sec = np.floor((ang + np.pi) / (2 * np.pi) * 8).astype(int) % 8
    c0[arm, 0] = sec[arm]
    c0[arm, 1] = t[arm]
    c0[arm, 3] = 0.0
    c1[arm, 0:3] = [1.0, 0.0, 0.0]
    c1[arm, 3] = 0.0
    # плавники мантии: дальние от оси точки в задней половине мантии
    rr = np.hypot(P[:, 1] - cyz[0], P[:, 2] - cyz[1])
    man = x <= xs
    fin = man & (rr > np.percentile(rr[man], 85))
    c0[fin, 2] = 1.0
    report = {"x_split": float(xs), "x_max": float(xm), "axis_c": cyz.tolist(), "fin_verts": int(fin.sum())}
    report["hub"] = [float(xs), float(cyz[0]), float(cyz[1])]
elif mode == "fish":
    z = P[:, 2]
    zmin, zmax = z.min(), z.max()
    t = (z - zmin) / max(zmax - zmin, 1e-4)  # 0 голова (−Z) … 1 хвост
    ax = np.abs(P[:, 0])
    fin = np.zeros(N)
    bins = np.linspace(0, 1, 21)
    for b in range(20):
        s = (t >= bins[b]) & (t < bins[b + 1] + 1e-6)
        if s.sum() < 4:
            continue
        med = np.median(ax[s])
        q = np.percentile(ax[s], 95)
        if q > med * 1.6:
            fin[s] = np.clip((ax[s] - med * 1.3) / max(q - med * 1.3, 1e-4), 0, 1)
    pect = fin * ((t > 0.15) & (t < 0.6))
    c0[:, 0] = t
    c0[:, 1] = pect
    c0[:, 2] = np.sign(P[:, 0])
    c0[:, 3] = 0.0
    report = {"pect_verts": int((pect > 0.2).sum())}

out = {"c0": c0[w].tolist(), "c1": c1[w].tolist(), "report": report}
json.dump(out, open(dst, "w"))
print(mode, json.dumps(report))
