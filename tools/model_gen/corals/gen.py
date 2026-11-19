# Генератор кораллов «Островов», версия 4 (Blender 4.x, headless):
#   blender -b --disable-autoexec --factory-startup --python tools/model_gen/corals/gen.py -- OUT_DIR [--hi]
# Наша собственная процедурная геометрия по референсу docs/CORALS_REF.md (не копия чужих мешей).
#
# Подход v4: каждый вид строится сначала в ВЫСОКОЙ детализации (без бюджета — тысячи веточек,
# щупалец, ворсинок), потом из него выводятся игровые уровни: LOD0 (часть нитей, сплошные части
# упрощены), LOD1 (ещё реже, нити толще), LOD2 (минимум). Высокая детализация (--hi) пишется в
# OUT_DIR/corals_hi.glb — из неё запекаются импосторы (tools/model_gen/corals/bake_impostors.gd).
#
# Тонкие трубки (веточки, ворс, щупальца, полипы, пиннулы) — «нити»: лента из 2 вершин на точку оси,
# в игре разворачивается к камере (scripts/sea/shaders/coral_common.gdshaderinc). Кодирование нити:
#   POSITION — точка оси, NORMAL — направление оси, UV0 = (6 скелет | 7 мягкая, гибкость),
#   UV1(«UV2») = (сторона −1/+1, радиус м), COLOR_0 — цвет.
# Сплошные части (пластины, комья, чаши, стволы): UV0 = (0 скелет | 1 мягкая, гибкость), обычные нормали.
# Ось Z вверх (glTF → Y вверх). Цвет вершин — sRGB (импортёр Godot сам переводит в линейный).
import bpy, bmesh, math, random, sys, os
from mathutils import Vector, noise

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv and not argv[0].startswith("--") else "/tmp/corals_out"
WRITE_HI = "--hi" in argv
os.makedirs(OUT, exist_ok=True)


def hexc(h, a=1.0):
	h = h.lstrip("#")
	return (int(h[0:2], 16) / 255.0, int(h[2:4], 16) / 255.0, int(h[4:6], 16) / 255.0, a)

def grey(v):
	return (v, v, v, 1.0)

def lerp(a, b, t):
	t = max(0.0, min(1.0, t))
	return tuple(a[i] + (b[i] - a[i]) * t for i in range(len(a)))

def mul(c, k):
	return (min(1.0, c[0] * k), min(1.0, c[1] * k), min(1.0, c[2] * k), c[3] if len(c) > 3 else 1.0)

def _perp(d):
	ref = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
	return d.cross(ref).normalized()

def smooth01(x):
	x = max(0.0, min(1.0, x))
	return x * x * (3 - 2 * x)

# ------------------------------------------------------------------ данные

class Solid:
	"""Сплошная геометрия: вершины, грани, цвет/UV на вершину."""
	def __init__(self):
		self.v = []; self.f = []; self.vc = []; self.vu = []

	def add_v(self, p, c, uv=(0.0, 0.0)):
		self.v.append(Vector(p)); self.vc.append(c); self.vu.append(uv)
		return len(self.v) - 1

	def face(self, idx):
		self.f.append(tuple(idx))

	def join(self, o):
		off = len(self.v)
		for i, p in enumerate(o.v):
			self.add_v(p, o.vc[i], o.vu[i])
		for f in o.f:
			self.face(tuple(x + off for x in f))

	def tube(self, pts, radii, sides, cols, flex, cap=True, soft=0.0, flat=1.0, tip_k=0.9, ring_noise=0.0, seed=0):
		n = len(pts)
		rings = []
		prev_u = None
		for i in range(n):
			if i == 0:
				ax = (pts[1] - pts[0]).normalized()
			elif i == n - 1:
				ax = (pts[i] - pts[i - 1]).normalized()
			else:
				ax = ((pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()).normalized()
			if prev_u is None:
				u = _perp(ax)
			else:
				u = (prev_u - ax * prev_u.dot(ax)).normalized()
			v = ax.cross(u).normalized()
			prev_u = u
			ring = []
			for s in range(sides):
				a = math.tau * s / sides
				r = radii[i]
				if ring_noise > 0:
					r *= 1.0 + ring_noise * noise.noise(Vector((pts[i].x * 9 + s, pts[i].y * 9 + seed, pts[i].z * 9)))
				ring.append(self.add_v(pts[i] + u * math.cos(a) * r + v * math.sin(a) * r * flat, cols[i], (soft, flex[i])))
			rings.append(ring)
		for i in range(n - 1):
			a, b = rings[i], rings[i + 1]
			for s in range(sides):
				s1 = (s + 1) % sides
				self.face((a[s], a[s1], b[s1], b[s]))
		if cap:
			tipdir = (pts[-1] - pts[-2]).normalized()
			tip = self.add_v(pts[-1] + tipdir * radii[-1] * tip_k, cols[-1], (soft, flex[-1]))
			last = rings[-1]
			for s in range(sides):
				self.face((last[s], last[(s + 1) % sides], tip))


class Strand:
	"""Нить: осевая линия, радиусы, цвета, гибкость; soft — мягкая ткань; imp — важность (0..1)
	для отбора на дальних уровнях (больше — дольше остаётся)."""
	__slots__ = ("pts", "rad", "col", "flex", "soft", "imp")
	def __init__(self, pts, rad, col, flex, soft=False, imp=0.5):
		self.pts = pts; self.rad = rad; self.col = col; self.flex = flex; self.soft = soft; self.imp = imp


class Coral:
	def __init__(self):
		self.solid = Solid()
		self.strands = []

	def strand(self, pts, r0, r1, c0, c1, flex0=0.0, flex1=0.0, soft=False, bulb=0.0, imp=0.5, cmid=None):
		"""Нить по точкам; радиус r0→r1, цвет c0→(cmid)→c1; bulb>0 — скруглённая «булава» на конце."""
		n = len(pts)
		if n < 2:
			return
		rad = [r0 + (r1 - r0) * (i / (n - 1)) for i in range(n)]
		if cmid is None:
			col = [lerp(c0, c1, i / (n - 1)) for i in range(n)]
		else:
			col = [lerp(c0, cmid, (i / (n - 1)) * 2) if i / (n - 1) < 0.5 else lerp(cmid, c1, (i / (n - 1)) * 2 - 1) for i in range(n)]
		flex = [flex0 + (flex1 - flex0) * (i / (n - 1)) for i in range(n)]
		pts = list(pts)
		if bulb > 0:
			d = (pts[-1] - pts[-2]).normalized()
			rb = r1 * bulb
			pts += [pts[-1] + d * rb * 0.9, pts[-1] + d * rb * 1.75]
			rad += [rb, rb * 0.45]
			col += [c1, c1]
			flex += [flex1, flex1]
		else:
			# скруглённый кончик: короткий сегмент с радиусом → 0
			d = (pts[-1] - pts[-2]).normalized()
			pts.append(pts[-1] + d * rad[-1] * 0.8)
			rad.append(rad[-1] * 0.35)
			col.append(col[-1]); flex.append(flex[-1])
		self.strands.append(Strand(pts, rad, col, flex, soft, imp))

# ------------------------------------------------------------------ сборка объекта Blender

def solid_to_object(sol, name):
	me = bpy.data.meshes.new(name)
	me.from_pydata([tuple(p) for p in sol.v], [], sol.f)
	me.update()
	col = me.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
	uvl = me.uv_layers.new(name="UVMap")
	for i, c in enumerate(sol.vc):
		col.data[i].color = c
	for poly in me.polygons:
		for li in poly.loop_indices:
			uvl.data[li].uv = sol.vu[me.loops[li].vertex_index]
	ob = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(ob)
	return ob

def tri_count_solid(sol):
	return sum(len(f) - 2 for f in sol.f)

def decimate_solid(sol, target):
	"""Упростить сплошную часть до target треугольников (collapse), вернуть Solid с нормалями вершин."""
	if not sol.f:
		return sol, []
	ob = solid_to_object(sol, "dec_tmp")
	t = tri_count_solid(sol)
	if t > target:
		m = ob.modifiers.new("dec", 'DECIMATE')
		m.ratio = max(0.01, target / float(t))
		m.use_collapse_triangulate = True
	dg = bpy.context.evaluated_depsgraph_get()
	me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
	bpy.data.objects.remove(ob)
	me.calc_loop_triangles()
	out = Solid()
	ca = me.color_attributes.get("Col")
	uvl = me.uv_layers.get("UVMap")
	vuv = {}
	for poly in me.polygons:
		for li in poly.loop_indices:
			vuv[me.loops[li].vertex_index] = tuple(uvl.data[li].uv) if uvl else (0.0, 0.0)
	norms = []
	for i, v in enumerate(me.vertices):
		c = tuple(ca.data[i].color) if (ca and ca.domain == 'POINT') else (1, 1, 1, 1)
		out.add_v(v.co.copy(), c, vuv.get(i, (0.0, 0.0)))
		norms.append(v.normal.copy())
	for p in me.polygons:
		out.face(tuple(p.vertices))
	bpy.data.meshes.remove(me)
	return out, norms

def strands_subset(strands, keep, rad_k=1.0, seg_step=1, min_imp=0.0):
	"""Отобрать долю keep нитей (по важности + детерминированный шум), радиус ×rad_k,
	на дальних уровнях — каждую seg_step-ю точку оси (кончики сохраняются)."""
	if keep >= 0.999 and seg_step == 1 and rad_k == 1.0:
		return strands
	scored = []
	for i, s in enumerate(strands):
		h = (math.sin(i * 12.9898 + 78.233) * 43758.5453) % 1.0
		scored.append((s.imp * 0.6 + h * 0.4, i))
	scored.sort(reverse=True)
	n = int(round(len(strands) * keep))
	keep_ids = sorted(i for (_, i) in scored[:n] if strands[i].imp >= min_imp)
	out = []
	for i in keep_ids:
		s = strands[i]
		if seg_step > 1 and len(s.pts) > 3:
			idx = list(range(0, len(s.pts) - 2, seg_step)) + [len(s.pts) - 2, len(s.pts) - 1]
			idx = sorted(set(idx))
		else:
			idx = list(range(len(s.pts)))
		out.append(Strand([s.pts[k] for k in idx], [s.rad[k] * rad_k for k in idx], [s.col[k] for k in idx],
			[s.flex[k] for k in idx], s.soft, s.imp))
	return out

def build_object(name, sol, sol_norms, strands):
	"""Финальный меш: сплошная часть (нормали — свои) + нити (нормаль = ось, UV2 = сторона/радиус)."""
	verts = []; faces = []; vcol = []; vuv = []; vuv2 = []; vnrm = []
	for i, p in enumerate(sol.v):
		verts.append(tuple(p)); vcol.append(sol.vc[i]); vuv.append(sol.vu[i]); vuv2.append((0.0, 0.0))
		vnrm.append(tuple(sol_norms[i]) if i < len(sol_norms) else (0.0, 0.0, 1.0))
	for f in sol.f:
		faces.append(f)
	for s in strands:
		n = len(s.pts)
		base = len(verts)
		kind = 7.0 if s.soft else 6.0
		for k in range(n):
			if k == 0:
				ax = s.pts[1] - s.pts[0]
			elif k == n - 1:
				ax = s.pts[k] - s.pts[k - 1]
			else:
				ax = (s.pts[k + 1] - s.pts[k]).normalized() + (s.pts[k] - s.pts[k - 1]).normalized()
			if ax.length < 1e-6:
				ax = Vector((0, 0, 1))
			ax = ax.normalized()
			for side in (-1.0, 1.0):
				verts.append(tuple(s.pts[k])); vcol.append(s.col[k]); vuv.append((kind, s.flex[k]))
				vuv2.append((side, s.rad[k])); vnrm.append(tuple(ax))
		for k in range(n - 1):
			a = base + k * 2
			faces.append((a, a + 1, a + 3, a + 2))
	me = bpy.data.meshes.new(name)
	me.from_pydata(verts, [], faces)
	me.update()
	col = me.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
	for i, c in enumerate(vcol):
		col.data[i].color = c
	uvl = me.uv_layers.new(name="UVMap")
	uv2 = me.uv_layers.new(name="UV2")
	# экспорт glTF переворачивает V (v → 1−v), импорт Godot — нет: пишем 1−v, чтобы в игре было v
	for poly in me.polygons:
		for li in poly.loop_indices:
			vi = me.loops[li].vertex_index
			uvl.data[li].uv = (vuv[vi][0], 1.0 - vuv[vi][1])
			uv2.data[li].uv = (vuv2[vi][0], 1.0 - vuv2[vi][1])
	if hasattr(me, "use_auto_smooth"):
		me.use_auto_smooth = True
	me.normals_split_custom_set_from_vertices(vnrm)
	ob = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(ob)
	return ob, sum(len(f) - 2 for f in faces)

# ------------------------------------------------------------------ сплошные «комья»

def remesh_blob(spheres, voxel, colfn, uvfn=None):
	"""Органический комок: набор (центр, радиус, шум, зерно) → вокс. ремеш → Solid с цветом по функции."""
	bm = bmesh.new()
	for (c, r, nz, sd) in spheres:
		m = bmesh.ops.create_icosphere(bm, subdivisions=3, radius=r)
		for v in m["verts"]:
			d = v.co.normalized()
			k = 1.0 + nz * noise.noise(d * 2.3 + Vector((sd, sd * 0.7, sd * 1.3)))
			v.co = Vector(c) + d * r * k
	me = bpy.data.meshes.new("blob")
	bm.to_mesh(me)
	bm.free()
	ob = bpy.data.objects.new("blob", me)
	bpy.context.scene.collection.objects.link(ob)
	rm = ob.modifiers.new("rm", 'REMESH')
	rm.mode = 'VOXEL'
	rm.voxel_size = voxel
	rm.use_smooth_shade = True
	dg = bpy.context.evaluated_depsgraph_get()
	me2 = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
	bpy.data.objects.remove(ob)
	bpy.data.meshes.remove(me)
	sol = Solid()
	for v in me2.vertices:
		sol.add_v(v.co.copy(), colfn(v.co, v.normal), uvfn(v.co) if uvfn else (0.0, 0.0))
	for p in me2.polygons:
		sol.face(tuple(p.vertices))
	bpy.data.meshes.remove(me2)
	return sol

def clamp_floor(sol, z=0.0):
	for p in sol.v:
		if p.z < z:
			p.z = z

# ------------------------------------------------------------------ «запекание» затенения

def bake_ao(coral, ao_h=0.35, ao_k=0.45, inner_k=0.4):
	"""Дешёвое затенение в цвет: у основания и в глубине массы — темнее (сплошные и нити)."""
	pts = list(coral.solid.v)
	for s in coral.strands:
		pts += s.pts
	if not pts:
		return
	zmin = min(p.z for p in pts); zmax = max(p.z for p in pts)
	cx = sum(p.x for p in pts) / len(pts); cy = sum(p.y for p in pts) / len(pts)
	rmax = max(max(math.hypot(p.x - cx, p.y - cy) for p in pts), 0.01)
	hz = max(zmax - zmin, 0.01)
	def k_of(p):
		h = (p.z - zmin) / hz
		rr = math.hypot(p.x - cx, p.y - cy) / rmax
		occl = (1.0 - min(1.0, h / ao_h)) * 0.6 + (1.0 - rr) * (1.0 - h) * inner_k
		return 1.0 - ao_k * max(0.0, min(1.0, occl))
	for i, p in enumerate(coral.solid.v):
		coral.solid.vc[i] = mul(coral.solid.vc[i], k_of(p))
	for s in coral.strands:
		s.col = [mul(c, k_of(p)) for c, p in zip(s.col, s.pts)]

# ================================================================== ВИДЫ

# ---------------- столовая акропора (preview 38–41): широкие волнистые многолопастные плиты в 1–3 яруса,
# сверху сплошной густой ворс коротких вертикальных веточек, по кромке — светлая «бахрома» наружу.

def gen_table(seed, tiers):
	rnd = random.Random(seed)
	co = Coral()
	sol = co.solid
	top = hexc("#D58E66"); top2 = hexc("#E7A580"); rim = hexc("#F6E2CA"); under = hexc("#9A6458")
	stem_c = hexc("#7A5648")
	sol.tube([Vector((0, 0, 0)), Vector((0.02, 0.0, 0.22)), Vector((0.0, 0.03, 0.38))], [0.13, 0.1, 0.085], 7,
		[mul(stem_c, 0.6), stem_c, stem_c], [0, 0, 0], cap=False)
	plates = []
	for t in range(tiers):
		R = rnd.uniform(1.55, 1.85) * (1.0 - 0.3 * t)
		cx = rnd.uniform(-0.35, 0.35) * t; cy = rnd.uniform(-0.35, 0.35) * t
		z = 0.38 + 0.17 * t + rnd.uniform(-0.03, 0.03)
		lobes = []
		nl = rnd.randint(4, 6)
		for i in range(nl):
			a = math.tau * i / nl + rnd.uniform(-0.45, 0.45)
			d = R * rnd.uniform(0.4, 0.62)
			lobes.append((Vector((math.cos(a) * d, math.sin(a) * d, 0)), R * rnd.uniform(0.36, 0.56)))
		lobes.append((Vector((0, 0, 0)), R * 0.48))
		def edge_r(a, lobes=lobes):
			dvec = Vector((math.cos(a), math.sin(a), 0))
			best = 0.05
			for (c, r) in lobes:
				b = dvec.dot(c)
				disc = b * b - (c.length_squared - r * r)
				if disc > 0:
					best = max(best, b + math.sqrt(disc))
			return best
		ph = rnd.uniform(0, 6.28)
		def surf(a, f, cx=cx, cy=cy, z=z, ph=ph, edge_r=edge_r):
			er = edge_r(a) * f
			# кромка волной вверх, лёгкая чаша, крупная волна по лопастям
			lift = 0.05 * f * f + 0.11 * f ** 4 * (0.5 + 0.5 * math.sin(a * 5 + ph)) + 0.03 * math.sin(a * 2 + ph * 1.3) * f
			return Vector((cx + math.cos(a) * er, cy + math.sin(a) * er, z + lift))
		RS = 72; RR = 9
		ctop = sol.add_v(Vector((cx, cy, z + 0.03)), top, (0, 0))
		cbot = sol.add_v(Vector((cx, cy, z - 0.03)), under, (0, 0))
		rows_t = []; rows_b = []
		for k in range(1, RR + 1):
			f = (k / RR) ** 0.8
			rt = []; rb = []
			for s in range(RS):
				a = math.tau * s / RS
				p = surf(a, f)
				th = 0.04 * (1 - f) + 0.012
				rib = 0.5 + 0.5 * math.sin(a * 60)
				rt.append(sol.add_v(p + Vector((0, 0, th * 0.5)), lerp(top, top2, 0.5 + 0.5 * noise.noise(p * 2.0)), (0, 0)))
				rb.append(sol.add_v(p - Vector((0, 0, th)), mul(under, 0.7 + 0.25 * f + 0.08 * rib), (0, 0)))
			rows_t.append(rt); rows_b.append(rb)
		for s in range(RS):
			s1 = (s + 1) % RS
			sol.face((ctop, rows_t[0][s], rows_t[0][s1]))
			sol.face((cbot, rows_b[0][s1], rows_b[0][s]))
		for k in range(RR - 1):
			for s in range(RS):
				s1 = (s + 1) % RS
				sol.face((rows_t[k][s], rows_t[k + 1][s], rows_t[k + 1][s1], rows_t[k][s1]))
				sol.face((rows_b[k][s1], rows_b[k + 1][s1], rows_b[k + 1][s], rows_b[k][s]))
		for s in range(RS):
			s1 = (s + 1) % RS
			sol.face((rows_t[-1][s], rows_b[-1][s], rows_b[-1][s1], rows_t[-1][s1]))
		plates.append((surf, edge_r, R, t))
	# ворс: веточки по сетке с дрожанием, шаг ~3.2 см, растут вертикально, у кромки — наружу и светлее
	for (surf, edge_r, R, t) in plates:
		step = 0.032
		n = int(math.pi * R * R / (step * step) * 0.62)
		for i in range(n):
			f = math.sqrt(rnd.random())
			a = rnd.random() * math.tau
			p = surf(a, f)
			out = Vector((math.cos(a), math.sin(a), 0))
			edge = smooth01((f - 0.8) / 0.2)
			ln = rnd.uniform(0.028, 0.055) * (1.0 + 0.6 * edge)
			d = (Vector((0, 0, 1)) + out * (0.15 + 1.4 * edge) + Vector((rnd.uniform(-.25, .25), rnd.uniform(-.25, .25), 0))).normalized()
			cbase = lerp(top, top2, rnd.random())
			ctip = lerp(lerp(top2, rim, 0.45), rim, edge)
			mid = p + d * ln * 0.55 + Vector((rnd.uniform(-.004, .004), rnd.uniform(-.004, .004), 0))
			co.strand([p, mid, p + d * ln], 0.0075, 0.0055, cbase, ctip, soft=False, imp=0.35 + 0.5 * edge, bulb=1.25)
	bake_ao(co, 0.45, 0.3)
	return co

# ---------------- кустовая акропора / «оленьи рога» (preview 30–33): широкая низкая подушка-бурелом из тысяч
# ветвящихся веточек (вилки на каждом шаге), розовато-коричневые с бледными шишковатыми кончиками, обломки вокруг.

def gen_staghorn(seed, W=1.45, H=0.62):
	rnd = random.Random(seed)
	co = Coral()
	dark = hexc("#5E3438"); mid = hexc("#8C5560"); tip = hexc("#F2D4CC")
	ph = rnd.uniform(0, 9)
	def env_top(x, y):
		r = math.hypot(x / W, y / (W * 0.85))
		if r >= 1.0:
			return -1.0
		return H * (1.0 - r ** 2.4) ** 0.6 * (0.88 + 0.2 * noise.noise(Vector((x * 1.6 + ph, y * 1.6, 0.0))))
	tips = [0]
	MAXT = 3200
	def grow(p, d, r, depth):
		if tips[0] > MAXT:
			return
		L = rnd.uniform(0.055, 0.085)
		d = (d + Vector((rnd.uniform(-.28, .28), rnd.uniform(-.28, .28), rnd.uniform(-.1, .22)))).normalized()
		q = p + d * L
		zt = env_top(q.x, q.y)
		inside = zt > 0 and q.z < zt
		rr = max(0.0085, r * 0.86)
		near = inside and (zt - q.z) < 0.09
		ctip = lerp(mid, tip, 0.85) if not inside or near else mid
		# сегмент — нить
		last = (not inside) or depth >= 16
		cs = lerp(dark, mid, min(1.0, depth / 6.0))
		ce = tip if last else lerp(cs, ctip, 0.5)
		co.strand([p, q], r, rr, cs, ce, soft=False, imp=0.25 + 0.05 * depth + (0.4 if last else 0.0), bulb=1.35 if last else 0.0)
		# шишечки-кораллиты по бокам (светлые короткие отростки)
		if rnd.random() < 0.35 and depth > 2:
			sd = (_perp(d) * rnd.choice((-1, 1)) + d * 0.5 + Vector((0, 0, 0.3))).normalized()
			b = p + d * L * rnd.uniform(0.3, 0.8)
			co.strand([b, b + sd * rnd.uniform(0.012, 0.022)], rr * 0.75, rr * 0.6, mid, tip, imp=0.15, bulb=1.2)
		if last:
			tips[0] += 1
			return
		out = Vector((q.x, q.y, 0)).normalized() if Vector((q.x, q.y, 0)).length > 1e-3 else Vector((1, 0, 0))
		k = 2 if rnd.random() < 0.55 else 1
		for j in range(k):
			if k == 2:
				ang = rnd.uniform(0.35, 0.75) * (1 if j == 0 else -1)
				side = _perp(d)
				nd = (d * math.cos(ang) + side * math.sin(ang)).normalized()
			else:
				nd = d
			nd = (nd + out * 0.18 + Vector((0, 0, 0.12))).normalized()
			grow(q, nd, rr, depth + 1)
	n_tr = 26
	bases = []
	for k in range(n_tr):
		a = math.tau * k / n_tr + rnd.uniform(-0.2, 0.2)
		r0 = W * math.sqrt(rnd.uniform(0.0, 0.55))
		bases.append((a, r0))
	for (a, r0) in bases:
		base = Vector((math.cos(a) * r0, math.sin(a) * r0, 0.0))
		out = Vector((math.cos(a), math.sin(a), 0.0))
		d = (out * (0.35 + 0.8 * r0 / W) + Vector((0, 0, 1.0))).normalized()
		grow(base, d, 0.022, 0)
	# обломки на песке вокруг
	for i in range(46):
		a = rnd.random() * math.tau
		rr = rnd.uniform(0.95, 1.4) * W
		p = Vector((math.cos(a) * rr, math.sin(a) * rr * 0.85, 0.01))
		dd = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0.15)).normalized()
		L = rnd.uniform(0.05, 0.11)
		q = p + dd * L
		co.strand([p, q], 0.011, 0.009, mid, tip, imp=0.1, bulb=1.25)
		if rnd.random() < 0.6:
			sd = (dd + _perp(dd) * rnd.uniform(-0.8, 0.8) + Vector((0, 0, 0.3))).normalized()
			co.strand([q, q + sd * L * 0.6], 0.009, 0.008, mid, tip, imp=0.1, bulb=1.25)
	bake_ao(co, 0.55, 0.55, 0.5)
	return co

# ---------------- щитковидная/пальчиковая акропора (preview 10, 11, 18, 19, 23): купол из плотных коротких
# толстых пальцев (часть с вилкой), кончики светлее; бугорчатые (узор кораллитов в шейдере).

def gen_corymbose(seed, R=0.5):
	rnd = random.Random(seed)
	co = Coral()
	base = grey(0.42); mid = grey(0.78); tip = grey(0.98)
	core = remesh_blob([((0, 0, R * 0.12), R * 0.62, 0.2, seed)], 0.06, lambda p, n: base)
	clamp_floor(core)
	co.solid = core
	ga = math.pi * (3 - math.sqrt(5))
	N = 620
	for i in range(N):
		z = 0.03 + 0.97 * (i + 0.5) / N
		r = math.sqrt(max(0.0, 1 - z * z))
		a = ga * i
		d = Vector((math.cos(a) * r, math.sin(a) * r, z))
		d = (d + Vector((rnd.uniform(-.07, .07), rnd.uniform(-.07, .07), 0))).normalized()
		start = Vector((d.x * R * 0.5, d.y * R * 0.5, R * 0.1 + d.z * R * 0.38))
		L = R * rnd.uniform(0.42, 0.55) * (0.75 + 0.25 * d.z)
		end = start + (d * 0.85 + Vector((0, 0, 0.25))).normalized() * L
		rad = rnd.uniform(0.019, 0.026)
		midp = (start + end) * 0.5 + Vector((rnd.uniform(-.01, .01), rnd.uniform(-.01, .01), 0))
		if rnd.random() < 0.28:
			# вилка у кончика
			co.strand([start, midp], rad * 1.1, rad, base, mid, imp=0.5)
			for j in (-1, 1):
				sd = (d + _perp(d) * 0.45 * j).normalized()
				co.strand([midp, midp + sd * L * 0.5], rad * 0.95, rad * 0.85, mid, tip, imp=0.45, bulb=1.15)
		else:
			co.strand([start, midp, end], rad * 1.1, rad * 0.95, base, tip, cmid=mid, imp=0.6, bulb=1.15)
	bake_ao(co, 0.4, 0.5)
	return co

# ---------------- лопастной (preview 26–29): v0 извилистые гребни «цветная капуста», v1 длинные пальцы-гребни,
# v2 шар из коротких толстых шипов (Pocillopora), v3 шишковатые ветвистые пальцы (фиолетовый)

def gen_lobed(seed, long_fingers=False):
	rnd = random.Random(seed)
	R = 0.34
	sph = [((0, 0, R * 0.25), R * 0.7, 0.15, seed)]
	walks = 46 if not long_fingers else 30
	for w in range(walks):
		d = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(0.15, 1.0))).normalized()
		step = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))).normalized()
		for k in range(11):
			step = (step + Vector((rnd.uniform(-.8, .8), rnd.uniform(-.8, .8), rnd.uniform(-.8, .8)))).normalized()
			d = (d + step * 0.15).normalized()
			if d.z < 0.08:
				d.z = 0.08; d = d.normalized()
			h = 1.0 + (0.26 if long_fingers else 0.1) * math.sin(k * 0.9 + w)
			c = (d.x * R * h, d.y * R * h, R * 0.12 + d.z * R * 0.82 * h)
			sph.append((c, rnd.uniform(0.032, 0.046) * (0.85 if long_fingers else 1.0), 0.3, w * 3.1 + k))
	co = Coral()
	co.solid = remesh_blob(sph, 0.011, lambda p, n: grey(0.5 + 0.48 * max(0.0, min(1.0, (p.length / (R * 1.1)) ** 2))))
	clamp_floor(co.solid)
	bake_ao(co, 0.4, 0.4)
	return co

def gen_spiky_ball(seed):
	rnd = random.Random(seed)
	R = 0.27
	co = Coral()
	co.solid = remesh_blob([((0, 0, R * 0.85), R * 0.78, 0.18, seed)], 0.03, lambda p, n: grey(0.6))
	clamp_floor(co.solid)
	ga = math.pi * (3 - math.sqrt(5))
	N = 520
	for i in range(N):
		z = -0.55 + 1.55 * (i + 0.5) / N
		z = min(z, 0.999)
		r = math.sqrt(max(0.0, 1 - z * z))
		a = ga * i
		d = Vector((math.cos(a) * r, math.sin(a) * r, z)).normalized()
		p = Vector((0, 0, R * 0.85)) + d * R * 0.72
		if p.z < 0.03:
			continue
		L = rnd.uniform(0.07, 0.11)
		co.strand([p, p + d * L * 0.6, p + d * L], 0.016, 0.011, grey(0.62), grey(1.0), cmid=grey(0.85), imp=0.6, bulb=1.1)
	bake_ao(co, 0.35, 0.4)
	return co

def gen_knobby_branch(seed):
	"""Шишковатые ветвистые пальцы (preview 26–27 справа): короткие толстые ветви с вилками, в шишках."""
	rnd = random.Random(seed)
	sph = []
	def walk(p, d, r, depth):
		for k in range(4):
			d = (d + Vector((rnd.uniform(-.35, .35), rnd.uniform(-.35, .35), rnd.uniform(0, .25)))).normalized()
			p = p + d * r * 1.1
			sph.append((tuple(p), r * rnd.uniform(0.95, 1.15), 0.35, depth * 7 + k))
		if depth < 3:
			for j in range(2 if rnd.random() < 0.7 else 1):
				nd = (d + _perp(d) * rnd.uniform(-0.9, 0.9) + Vector((0, 0, 0.3))).normalized()
				walk(p, nd, r * 0.88, depth + 1)
	for k in range(6):
		a = math.tau * k / 6 + rnd.uniform(-.3, .3)
		walk(Vector((math.cos(a) * 0.06, math.sin(a) * 0.06, 0.02)), Vector((math.cos(a) * 0.6, math.sin(a) * 0.6, 1)).normalized(), 0.034, 0)
	co = Coral()
	co.solid = remesh_blob(sph, 0.011, lambda p, n: grey(0.5 + 0.45 * smooth01(p.z / 0.45)))
	clamp_floor(co.solid)
	bake_ao(co, 0.35, 0.4)
	return co

# ---------------- листовой (Turbinaria, preview 81–85): спираль-«капуста» тонких чашевидных пластин
# с концентрическими полосами, радиальными бороздками и светлой кромкой

def gen_foliose(seed, colr):
	rnd = random.Random(seed)
	co = Coral()
	sol = co.solid
	c0 = hexc(colr); c1 = mul(hexc(colr), 0.55); rimc = hexc("#EEE8CC")
	n = rnd.randint(15, 19)
	for t in range(n):
		a0 = t * 2.39996 + rnd.uniform(-.2, .2)
		dist = 0.04 + 0.32 * (t / n) ** 0.7
		cx = math.cos(a0) * dist * 0.5; cy = math.sin(a0) * dist * 0.5
		z = 0.02 + 0.14 * (1 - t / n)
		r = rnd.uniform(0.2, 0.32) * (0.5 + 0.75 * t / n)
		span = rnd.uniform(3.2, 5.0)
		face = a0
		tilt = rnd.uniform(0.35, 0.7)
		RS, RR = 22, 7
		rows_t = []; rows_b = []
		for k in range(RR + 1):
			f = k / RR
			rt = []; rb = []
			for s in range(RS + 1):
				a = face + span * (s / RS - 0.5)
				rr = r * f
				wav = 0.025 * math.sin((s / RS) * math.pi * 5 + t) * f * f
				p = Vector((cx + math.cos(a) * rr, cy + math.sin(a) * rr, z + tilt * 0.35 * rr + 0.05 * f * f + wav))
				band = 0.5 + 0.5 * math.sin(f * 30.0)
				groove = 0.5 + 0.5 * math.sin((s / RS) * 46.0)
				cc = lerp(lerp(c1, c0, f), mul(c0, 0.8), band * 0.45 + groove * 0.15)
				if k == RR:
					cc = rimc
				elif k == RR - 1:
					cc = lerp(cc, rimc, 0.4)
				th = 0.007 + 0.006 * (1 - f)
				rt.append(sol.add_v(p + Vector((0, 0, th)), cc, (0, 0)))
				rb.append(sol.add_v(p - Vector((0, 0, th)), mul(cc, 0.75), (0, 0)))
			rows_t.append(rt); rows_b.append(rb)
		for k in range(RR):
			for s in range(RS):
				sol.face((rows_t[k][s], rows_t[k][s + 1], rows_t[k + 1][s + 1], rows_t[k + 1][s]))
				sol.face((rows_b[k][s + 1], rows_b[k][s], rows_b[k + 1][s], rows_b[k + 1][s + 1]))
		for s in range(RS):
			sol.face((rows_t[RR][s], rows_t[RR][s + 1], rows_b[RR][s + 1], rows_b[RR][s]))
		for k in range(RR):
			sol.face((rows_t[k][0], rows_t[k + 1][0], rows_b[k + 1][0], rows_b[k][0]))
			sol.face((rows_t[k + 1][RS], rows_t[k][RS], rows_b[k][RS], rows_b[k + 1][RS]))
	bake_ao(co, 0.4, 0.35)
	return co

# ---------------- акропора-«деревце» (preview 59–64): короткий толстый ствол, широкие частые развилки,
# веточки в шипиках-кораллитах, кончики светлые

def gen_antler(seed, cols):
	rnd = random.Random(seed)
	co = Coral()
	base = hexc(cols[0]); tip = hexc(cols[1]); dark = mul(base, 0.6)
	def grow(p, d, L, r, depth):
		d = (d + Vector((rnd.uniform(-.2, .2), rnd.uniform(-.2, .2), 0.12))).normalized()
		q = p + d * L
		mid = (p + q) * 0.5 + Vector((rnd.uniform(-.01, .01), rnd.uniform(-.01, .01), 0))
		last = depth >= 6
		co.strand([p, mid, q], r, r * 0.8, lerp(dark, base, depth / 6.0), tip if last else lerp(base, tip, depth / 9.0),
			imp=0.3 + 0.1 * depth, bulb=1.2 if last else 0.0)
		# шипики по веточке
		if depth >= 2:
			for k in range(rnd.randint(1, 3)):
				t = rnd.uniform(0.2, 0.9)
				b = p + (q - p) * t
				sd = (_perp(d) * rnd.choice((-1, 1)) + Vector((0, 0, 0.6)) + d * 0.4).normalized()
				co.strand([b, b + sd * rnd.uniform(0.012, 0.022)], r * 0.55, r * 0.45, base, tip, imp=0.1, bulb=1.15)
		if last:
			return
		k = 2 if rnd.random() < 0.85 else 3
		for j in range(k):
			ang = (j - (k - 1) * 0.5) * rnd.uniform(0.6, 0.9)
			side = _perp(d)
			nd = (d * math.cos(ang) + side * math.sin(ang) + Vector((0, 0, 0.25))).normalized()
			grow(q, nd, L * rnd.uniform(0.74, 0.88), r * 0.78, depth + 1)
	for k in range(3):
		d = Vector((rnd.uniform(-.45, .45), rnd.uniform(-.45, .45), 1)).normalized()
		grow(Vector((rnd.uniform(-.04, .04), rnd.uniform(-.04, .04), 0)), d, 0.2, 0.034, 0)
	bake_ao(co, 0.3, 0.35)
	return co

# ---------------- мягкий коралл Dendronephthya (preview 69–76): светлый полупрозрачный ветвистый ствол,
# на концах — пышные «цветная капуста» гроздья тысяч мелких полипов

def gen_softcoral(seed, trunk_hex, polyp_hex):
	rnd = random.Random(seed)
	co = Coral()
	sol = co.solid
	tc = hexc(trunk_hex); pc = hexc(polyp_hex); pc2 = lerp(pc, hexc("#FFFFFF"), 0.4); pcd = mul(pc, 0.7)
	tips = []
	def grow(p, d, ln, rad, depth):
		q = p + d * ln
		mid = p + d * ln * 0.5 + Vector((rnd.uniform(-.03, .03), rnd.uniform(-.03, .03), 0.02))
		fl = min(0.9, 0.15 + max(depth, 0) * 0.17)
		sol.tube([p, mid, q], [rad, rad * 0.86, rad * 0.72], 7, [tc, tc, lerp(tc, pc, 0.15 * depth)], [fl * 0.6, fl * 0.8, fl],
			cap=depth >= 4, soft=1.0)
		if depth >= 4:
			tips.append((q, d, fl))
			return
		for k in range(3 if depth < 1 else rnd.randint(2, 3)):
			nd = (d + Vector((rnd.uniform(-1.0, 1.0), rnd.uniform(-1.0, 1.0), rnd.uniform(0.0, 0.5)))).normalized()
			grow(q, nd, ln * 0.78, rad * 0.72, depth + 1)
	for k in range(3):
		a = math.tau * k / 3 + rnd.uniform(-.3, .3)
		grow(Vector((math.cos(a) * 0.04, math.sin(a) * 0.04, 0)), Vector((math.cos(a) * 0.5, math.sin(a) * 0.5, 1)).normalized(), 0.19, 0.05, 0)
	# гроздья полипов: на каждом кончике «капуста» из мелких комочков-полипов
	for (q, d, fl) in tips:
		nb = rnd.randint(5, 8)
		for b in range(nb):
			bd = (d + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.3, 0.8)))).normalized()
			bc = q + bd * rnd.uniform(0.02, 0.05)
			for k in range(rnd.randint(11, 16)):
				pd = (bd + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * 0.8).normalized()
				p0 = bc + pd * rnd.uniform(0.005, 0.018)
				L = rnd.uniform(0.008, 0.015)
				co.strand([p0, p0 + pd * L], 0.0045, 0.004, pcd, pc2, flex0=fl, flex1=min(1.0, fl + 0.1), soft=True, imp=0.5, bulb=1.5)
	bake_ao(co, 0.3, 0.3)
	return co

# ---------------- кожистый «Actinia01» (preview 42–45): волнистая лопастная чаша-диск, сверху розово-белая,
# с оранжевым ротовым диском; густой «мех» коротких жёлтых щупалец со скруглёнными кончиками — у края гуще

def gen_leather(seed):
	rnd = random.Random(seed)
	co = Coral()
	sol = co.solid
	cup0 = hexc("#B2827E"); cup1 = hexc("#F2DCD6"); fr0 = hexc("#C8A85C"); fr1 = hexc("#F0DC9A")
	R = 0.55; H = 0.22
	lob = rnd.randint(4, 5); ph = rnd.uniform(0, 6)
	RS, RR = 64, 9
	def cup_r(a):
		return R * (1.0 + 0.16 * math.sin(a * lob + ph) + 0.05 * math.sin(a * lob * 2.3 + ph * 1.7))
	def cup_pt(a, f):
		er = cup_r(a) * (0.2 + 0.8 * f)
		z = H * f ** 1.6 + 0.07 * f ** 2 * math.sin(a * lob * 2 + ph)
		return Vector((math.cos(a) * er, math.sin(a) * er, z))
	def top_pt(a, f):
		# верх диска: от кромки к центру чуть вогнутый
		e = cup_pt(a, 1.0)
		return Vector((e.x * f, e.y * f, H * 0.8 + (e.z - H * 0.8) * f ** 1.4))
	rows = []
	for k in range(RR + 1):
		f = k / RR
		row = []
		for s in range(RS):
			a = math.tau * s / RS
			p = cup_pt(a, f)
			rib = 0.5 + 0.5 * math.sin(a * 40)
			row.append(sol.add_v(p, lerp(cup0, cup1, f * 0.55 + rib * 0.12), (0, 0)))
		rows.append(row)
	bottom = sol.add_v(Vector((0, 0, 0)), mul(cup0, 0.7), (0, 0))
	for s in range(RS):
		sol.face((bottom, rows[0][(s + 1) % RS], rows[0][s]))
	for k in range(RR):
		for s in range(RS):
			s1 = (s + 1) % RS
			sol.face((rows[k][s], rows[k][s1], rows[k + 1][s1], rows[k + 1][s]))
	# верхний диск: розово-белый, ротовой диск в центре оранжевый
	TR = 7
	trows = [rows[RR]]
	for k in range(1, TR):
		f = 1.0 - k / TR
		row = []
		for s in range(RS):
			a = math.tau * s / RS
			c = cup1 if f > 0.2 else lerp(hexc("#E8A050"), cup1, f / 0.2)
			row.append(sol.add_v(top_pt(a, f), c, (0, 0)))
		trows.append(row)
	ctr = sol.add_v(Vector((0, 0, H * 0.8 - 0.01)), hexc("#D88A3A"), (0, 0))
	for k in range(TR - 1):
		for s in range(RS):
			s1 = (s + 1) % RS
			sol.face((trows[k][s], trows[k][s1], trows[k + 1][s1], trows[k + 1][s]))
	for s in range(RS):
		sol.face((trows[-1][s], trows[-1][(s + 1) % RS], ctr))
	# мех: щупальца, плотность растёт к краю, пустое пятно у ротового диска
	N = 1500
	for i in range(N):
		a = rnd.random() * math.tau
		f = 1.0 - rnd.random() ** 1.8 * 0.85
		if f < 0.2:
			continue
		p = top_pt(a, f) if f < 0.995 else cup_pt(a, 1.0)
		out = Vector((math.cos(a), math.sin(a), 0))
		edge = smooth01((f - 0.7) / 0.3)
		d = (Vector((0, 0, 1)) + out * (0.15 + 0.9 * edge) + Vector((rnd.uniform(-.2, .2), rnd.uniform(-.2, .2), 0))).normalized()
		L = rnd.uniform(0.04, 0.065) * (0.75 + 0.5 * edge)
		bend = Vector((rnd.uniform(-.3, .3), rnd.uniform(-.3, .3), -0.1))
		m = p + d * L * 0.5
		e = p + (d + bend * 0.4).normalized() * L
		co.strand([p, m, e], 0.0062, 0.0058, fr0, fr1, flex0=0.2, flex1=1.0, soft=True, imp=0.4 + 0.4 * edge, bulb=1.3)
	bake_ao(co, 0.35, 0.3)
	return co

# ---------------- актиния (preview 46–48, 55–58): из низкого диска во все стороны — сотни длинных тонких
# волнистых щупалец, поднимаются и закручиваются наружу/вниз, кончики с крошечной «булавой»

def gen_anemone(seed, colr):
	rnd = random.Random(seed)
	co = Coral()
	sol = co.solid
	c = hexc(colr); dark = mul(c, 0.62); tipc = lerp(c, hexc("#FFFFFF"), 0.55)
	RX, RY = 0.3, 0.24
	RS = 24
	center = sol.add_v(Vector((0, 0, 0.07)), dark, (1.0, 0.0))
	ring = [sol.add_v(Vector((math.cos(math.tau * s / RS) * RX, math.sin(math.tau * s / RS) * RY, 0.05)), dark, (1.0, 0.0)) for s in range(RS)]
	ring2 = [sol.add_v(Vector((math.cos(math.tau * s / RS) * (RX + .05), math.sin(math.tau * s / RS) * (RY + .05), 0.0)), mul(dark, 0.8), (1.0, 0.0)) for s in range(RS)]
	for s in range(RS):
		s1 = (s + 1) % RS
		sol.face((center, ring[s], ring[s1]))
		sol.face((ring[s], ring2[s], ring2[s1], ring[s1]))
	N = 620
	for i in range(N):
		a = rnd.random() * math.tau
		f = math.sqrt(rnd.random())
		p0 = Vector((math.cos(a) * RX * f, math.sin(a) * RY * f, 0.06 + 0.01 * (1 - f)))
		out = Vector((math.cos(a), math.sin(a), 0))
		side = Vector((-out.y, out.x, 0))
		ln = rnd.uniform(0.26, 0.46) * (1.12 - 0.3 * f)
		th0 = rnd.uniform(0.0, 0.25) + 0.55 * f            # от вертикали
		th1 = th0 + rnd.uniform(0.7, 1.9)                     # закручиваются наружу-вниз
		ph = rnd.uniform(0, 6.28); wig = rnd.uniform(0.18, 0.4)
		segs = 7
		pts = [p0]
		for sgi in range(1, segs + 1):
			t = sgi / segs
			th = th0 + (th1 - th0) * t * t
			dirv = out * math.sin(th) + Vector((0, 0, 1)) * math.cos(th) + side * wig * math.sin(t * 7.0 + ph)
			pts.append(pts[-1] + dirv.normalized() * ln / segs)
		# кончик подкручен колечком
		if rnd.random() < 0.45:
			dd = (pts[-1] - pts[-2]).normalized()
			cv = (dd.cross(Vector((0, 0, 1))).normalized() if abs(dd.z) < 0.95 else side) * 0.5 + Vector((0, 0, -0.5))
			pts.append(pts[-1] + (dd + cv).normalized() * ln / segs * 0.8)
		r = rnd.uniform(0.0068, 0.0088)
		co.strand(pts, r * 1.15, r * 0.85, lerp(c, dark, 0.45), tipc, cmid=c, flex0=0.1, flex1=1.0, soft=True,
			imp=0.3 + 0.4 * (1 - f), bulb=1.45)
	bake_ao(co, 0.3, 0.35, 0.55)
	return co

# ---------------- «Actinia03» (preview 50–54): жёлтое бугристое основание из «шаров», сверху густая шапка-
# «бублик» из сотен коротких серых щупалец с белыми скруглёнными кончиками

def gen_bubble(seed):
	rnd = random.Random(seed)
	yel = hexc("#E6BE2E"); yel2 = hexc("#C8A020")
	sph = [((0, 0, 0.17), 0.18, 0.1, 1.0)]
	for i in range(7):
		a = math.tau * i / 7 + rnd.uniform(-.25, .25)
		sph.append(((math.cos(a) * 0.14, math.sin(a) * 0.14, rnd.uniform(0.09, 0.2)), rnd.uniform(0.1, 0.135), 0.12, i * 2.0))
	co = Coral()
	co.solid = remesh_blob(sph, 0.02, lambda p, n: lerp(yel2, yel, 0.4 + 0.6 * max(0.0, n.z)), lambda p: (1.0, 0.0))
	clamp_floor(co.solid)
	zmax = max(p.z for p in co.solid.v)
	ph = rnd.uniform(0, 6)
	N = 1100
	for i in range(N):
		a = rnd.random() * math.tau
		f = math.sqrt(rnd.random())
		# «бублик»: две лопасти короны, у центра провал
		lobe = 0.8 + 0.2 * math.sin(a * 2 + ph)
		if f < 0.2:
			continue
		rr = 0.26 * f * lobe
		z = zmax - 0.02 - 0.06 * f * f + 0.03 * math.sin(a * 2 + ph)
		p = Vector((math.cos(a) * rr, math.sin(a) * rr, z))
		out = Vector((math.cos(a), math.sin(a), 0))
		d = (Vector((0, 0, 1)) + out * (0.25 + 0.9 * f * f) + Vector((rnd.uniform(-.2, .2), rnd.uniform(-.2, .2), 0))).normalized()
		L = rnd.uniform(0.07, 0.11) * (0.8 + 0.4 * f)
		m = p + d * L * 0.5
		e = p + (d + Vector((rnd.uniform(-.15, .15), rnd.uniform(-.15, .15), -0.05))).normalized() * L
		co.strand([p, m, e], 0.0052, 0.0048, hexc("#7E7E76"), hexc("#B4B4AA"), flex0=0.2, flex1=1.0, soft=True,
			imp=0.5, bulb=1.75)
		co.strands[-1].col[-1] = hexc("#FBFBF5"); co.strands[-1].col[-2] = hexc("#FBFBF5")
	bake_ao(co, 0.25, 0.25)
	return co

# ---------------- морская лилия (preview 53, 65–67): пучок из ~40 рук, загнутых дугой наружу-вниз,
# по всей длине руки — частые перистые пиннулы; кончики закручены

def gen_crinoid(seed, c0h="#9C8410", c1h="#E8D838"):
	rnd = random.Random(seed)
	co = Coral()
	c0 = hexc(c0h); c1 = hexc(c1h)
	arms = 42
	for i in range(arms):
		a = math.tau * i / arms + rnd.uniform(-.2, .2)
		el = rnd.uniform(1.2, 1.6)
		ln = rnd.uniform(0.42, 0.62)
		bend = rnd.uniform(1.4, 2.6)
		pts = []
		M = 14
		for s in range(M):
			t = s / (M - 1)
			ang = el - t * bend - (t ** 4) * 1.5
			r = ln * t
			pts.append(Vector((math.cos(a) * r * math.cos(ang) * 1.05, math.sin(a) * r * math.cos(ang) * 1.05,
				0.05 + r * math.sin(ang) * 0.9 + 0.16 * t)))
		co.strand(pts, 0.0075, 0.0035, c0, c1, flex0=0.1, flex1=1.0, soft=True, imp=0.9)
		# пиннулы: попеременно влево/вправо каждые ~1.3 см, длина убывает к кончику
		total = sum((pts[k + 1] - pts[k]).length for k in range(M - 1))
		npn = int(total / 0.013)
		for j in range(npn):
			t = (j + 0.5) / npn
			fk = t * (M - 1)
			k = min(M - 2, int(fk))
			u = fk - k
			p = pts[k].lerp(pts[k + 1], u)
			d = (pts[k + 1] - pts[k]).normalized()
			side = d.cross(Vector((math.cos(a), math.sin(a), 0))).normalized()
			if side.length < 0.1:
				side = _perp(d)
			sgn = 1 if j % 2 == 0 else -1
			pd = (side * sgn * 0.85 + d * 0.5 + Vector((0, 0, 0.1))).normalized()
			L = 0.032 * (1.0 - 0.6 * t) + 0.006
			fl = 0.1 + 0.9 * t
			co.strand([p, p + pd * L * 0.6, p + (pd + d * 0.25).normalized() * L], 0.0022, 0.0014, lerp(c0, c1, t), c1,
				flex0=fl, flex1=min(1.0, fl + 0.05), soft=True, imp=0.4)
	return co

# ---------------- огненный коралл (preview 77–80): вертикальные толстые лопасти-пластины веером от центра,
# расширяются к бугристой светлой верхней кромке

def gen_millepora(seed):
	rnd = random.Random(seed)
	c0 = hexc("#94703A"); c1 = hexc("#D0A860"); tipc = hexc("#F4ECD6")
	sph = []
	nb = rnd.randint(6, 8)
	for k in range(nb):
		a = rnd.random() * math.tau
		out = Vector((math.cos(a), math.sin(a), 0))
		side = Vector((-out.y, out.x, 0))
		H = rnd.uniform(0.28, 0.5)
		W0 = rnd.uniform(0.06, 0.1)
		W1 = rnd.uniform(0.16, 0.26)
		lean = rnd.uniform(0.15, 0.45)
		curl = rnd.uniform(-0.25, 0.25)
		for iv in range(12):
			v = iv / 11
			w = W0 + (W1 - W0) * v
			cen = out * (0.04 + lean * H * v) + Vector((0, 0, H * v))
			nw = int(2 + w / 0.018)
			for iu in range(nw):
				u = (iu / max(1, nw - 1) - 0.5) * 2
				p = cen + side * u * w * 0.5 + out * (curl * u * u * w)
				top = v > 0.85
				r = 0.022 if not top else rnd.uniform(0.022, 0.03)
				sph.append((tuple(p), r, 0.25, k * 31 + iv * 7 + iu))
	co = Coral()
	zmax = max(s[0][2] for s in sph) + 0.03
	co.solid = remesh_blob(sph, 0.012, lambda p, n: lerp(lerp(c0, c1, smooth01(p.z / zmax * 1.4)), tipc, smooth01((p.z / zmax - 0.78) / 0.22)))
	clamp_floor(co.solid)
	bake_ao(co, 0.35, 0.35)
	return co

# ---------------- корковый холмик: низкие бугристые подушки

def gen_mound(seed, colr):
	rnd = random.Random(seed)
	c = hexc(colr)
	sph = []
	for i in range(16):
		a = rnd.random() * math.tau; rr = rnd.uniform(0, 0.3)
		sph.append(((math.cos(a) * rr, math.sin(a) * rr, 0.0), rnd.uniform(0.08, 0.2), 0.45, i * 1.7))
	co = Coral()
	co.solid = remesh_blob(sph, 0.022, lambda p, n: mul(c, 0.7 + 0.35 * max(0.0, n.z) + 0.15 * noise.noise(p * 20.0)))
	clamp_floor(co.solid)
	return co

# ------------------------------------------------------------------ спецификация видов и уровней

# (тип, вариант, функция, LOD0 (сплошная треуг., доля нитей), LOD1 (…, доля, ×радиус, шаг), LOD2 (…))
SPEC = [
	("table", 0, lambda: gen_table(11, 1), (1600, 0.3), (500, 0.12, 1.6, 1), (200, 0.03, 2.4, 1)),
	("table", 1, lambda: gen_table(12, 2), (2000, 0.26), (650, 0.1, 1.6, 1), (240, 0.025, 2.4, 1)),
	("table", 2, lambda: gen_table(13, 3), (2200, 0.23), (700, 0.09, 1.6, 1), (260, 0.022, 2.4, 1)),
	("staghorn", 0, lambda: gen_staghorn(21), (0, 0.6), (0, 0.22, 1.5, 1), (0, 0.06, 2.4, 1)),
	("staghorn", 1, lambda: gen_staghorn(22, 1.6, 0.68), (0, 0.55), (0, 0.2, 1.5, 1), (0, 0.055, 2.4, 1)),
	("corymbose", 0, lambda: gen_corymbose(31), (900, 0.8), (300, 0.4, 1.25, 2), (120, 0.15, 1.6, 2)),
	("corymbose", 1, lambda: gen_corymbose(32, 0.42), (800, 0.8), (300, 0.4, 1.25, 2), (120, 0.15, 1.6, 2)),
	("lobed", 0, lambda: gen_lobed(41), (3200, 1.0), (1000, 1.0, 1.0, 1), (380, 1.0, 1.0, 1)),
	("lobed", 1, lambda: gen_lobed(42, True), (3200, 1.0), (1000, 1.0, 1.0, 1), (380, 1.0, 1.0, 1)),
	("lobed", 2, lambda: gen_spiky_ball(43), (600, 0.85), (220, 0.4, 1.3, 1), (100, 0.15, 1.8, 1)),
	("lobed", 3, lambda: gen_knobby_branch(44), (3000, 1.0), (950, 1.0, 1.0, 1), (350, 1.0, 1.0, 1)),
	("foliose", 0, lambda: gen_foliose(51, "#B8A870"), (3000, 1.0), (1000, 1.0, 1.0, 1), (320, 1.0, 1.0, 1)),
	("foliose", 1, lambda: gen_foliose(52, "#C0A868"), (3000, 1.0), (1000, 1.0, 1.0, 1), (320, 1.0, 1.0, 1)),
	("antler", 0, lambda: gen_antler(61, ["#A88050", "#EAD4AC"]), (0, 0.75), (0, 0.3, 1.4, 1), (0, 0.1, 2.0, 1)),
	("antler", 1, lambda: gen_antler(62, ["#9A9A9A", "#E2E2DE"]), (0, 0.75), (0, 0.3, 1.4, 1), (0, 0.1, 2.0, 1)),
	("softcoral", 0, lambda: gen_softcoral(71, "#EEE0DC", "#E8A030"), (1600, 0.24), (600, 0.15, 1.6, 1), (240, 0.04, 2.6, 1)),
	("softcoral", 1, lambda: gen_softcoral(72, "#EED4D4", "#E87898"), (1600, 0.24), (600, 0.15, 1.6, 1), (240, 0.04, 2.6, 1)),
	("leather", 0, lambda: gen_leather(81), (1200, 0.55), (450, 0.2, 1.5, 1), (200, 0.06, 2.4, 1)),
	("anemone", 0, lambda: gen_anemone(91, "#F2EEE4"), (300, 0.62), (150, 0.3, 1.3, 2), (60, 0.1, 1.8, 3)),
	("anemone", 1, lambda: gen_anemone(92, "#DCCCA8"), (300, 0.62), (150, 0.3, 1.3, 2), (60, 0.1, 1.8, 3)),
	("bubble", 0, lambda: gen_bubble(101), (1200, 0.55), (450, 0.22, 1.4, 1), (180, 0.07, 2.2, 1)),
	("crinoid", 0, lambda: gen_crinoid(111), (0, 0.42), (0, 0.25, 1.4, 2), (0, 0.08, 1.8, 3)),
	("crinoid", 1, lambda: gen_crinoid(112, "#5E5A50", "#C8C4B4"), (0, 0.42), (0, 0.25, 1.4, 2), (0, 0.08, 1.8, 3)),
	("mound", 0, lambda: gen_mound(121, "#7A5A38"), (800, 1.0), (280, 1.0, 1.0, 1), (110, 1.0, 1.0, 1)),
	("mound", 1, lambda: gen_mound(122, "#6A6A3A"), (800, 1.0), (280, 1.0, 1.0, 1), (110, 1.0, 1.0, 1)),
	("millepora", 0, lambda: gen_millepora(131), (2600, 1.0), (800, 1.0, 1.0, 1), (280, 1.0, 1.0, 1)),
	("millepora", 1, lambda: gen_millepora(132), (2600, 1.0), (800, 1.0, 1.0, 1), (280, 1.0, 1.0, 1)),
]


def strand_tris(strands):
	return sum((len(s.pts) - 1) * 2 for s in strands)


def main():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	report = []
	only = os.environ.get("CORAL_ONLY", "")
	hi_objs = []
	for (t, vi, fn, l0, l1, l2) in SPEC:
		if only and t not in only.split(","):
			continue
		co = fn()
		src_tris = tri_count_solid(co.solid) + strand_tris(co.strands)
		row = [t, vi, src_tris, len(co.strands)]
		if WRITE_HI:
			sol_hi, n_hi = decimate_solid(co.solid, 10 ** 9)
			ob, _ = build_object("%s_v%d_hi" % (t, vi), sol_hi, n_hi, co.strands)
			hi_objs.append(ob)
		for lod, spec in ((0, l0), (1, l1), (2, l2)):
			budget = spec[0]; keep = spec[1]
			rk = spec[2] if len(spec) > 2 else 1.0
			step = spec[3] if len(spec) > 3 else 1
			sol, nrm = decimate_solid(co.solid, budget if budget > 0 else 10 ** 9)
			sub = strands_subset(co.strands, keep, rk, step)
			ob, tris = build_object("%s_v%d_lod%d" % (t, vi, lod), sol, nrm, sub)
			row.append(tris)
		report.append(row)
		print("CORAL", *row, flush=True)
	if WRITE_HI:
		# высокая детализация — отдельно (для запекания импосторов), основной GLB — без неё
		bpy.ops.object.select_all(action='DESELECT')
		for o in hi_objs:
			o.select_set(True)
		bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "corals_hi.glb"), export_format='GLB', use_selection=True,
			export_colors=True, export_normals=True, export_texcoords=True, export_apply=False,
			export_materials='NONE', export_yup=True)
		for o in hi_objs:
			bpy.data.objects.remove(o)
	bpy.ops.object.select_all(action='DESELECT')
	bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "corals.glb"), export_format='GLB',
		export_colors=True, export_normals=True, export_texcoords=True, export_apply=False,
		export_materials='NONE', export_yup=True)
	with open(os.path.join(OUT, "report.tsv"), "w") as f:
		f.write("type\tvar\tsrc_tris\tstrands\tlod0\tlod1\tlod2\n")
		for r in report:
			f.write("\t".join(str(x) for x in r) + "\n")

main()
