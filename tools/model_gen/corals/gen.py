# Генератор кораллов «Островов» (Blender 4.x, headless):
#   blender -b --disable-autoexec --factory-startup --python tools/model_gen/corals/gen.py -- OUT_DIR
# Наша собственная процедурная геометрия по референсу docs/CORALS_REF.md (не копия чужих мешей).
# На выходе OUT_DIR/corals.glb: объекты <type>_v<n>_lod<k>. Ось Z вверх (glTF → Y вверх).
# Каналы вершин:
#   COLOR_0 — запечённый цвет (альбедо × затенение у основания/в глубине, светлые кончики),
#   UV0.x — «тип части» (0 скелет, 1 мягкая ткань), UV0.y — гибкость 0..1 (качание/расталкивание).
import bpy, bmesh, math, random, sys, os
from mathutils import Vector, Matrix, noise

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "/tmp/corals_out"
os.makedirs(OUT, exist_ok=True)

def _lin(c):
	return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

# Цвет пишем в sRGB: импортёр glTF в Godot сам переводит цвет вершин в линейный
# (проверено test_corals: линейные значения давали двойное затемнение).
def hexc(h, a=1.0):
	h = h.lstrip("#")
	return (int(h[0:2], 16) / 255.0, int(h[2:4], 16) / 255.0, int(h[4:6], 16) / 255.0, a)

def grey(v):
	return (v, v, v, 1.0)

def lerp(a, b, t):
	return tuple(a[i] + (b[i] - a[i]) * t for i in range(len(a)))

def mul(c, k):
	return (c[0] * k, c[1] * k, c[2] * k, c[3] if len(c) > 3 else 1.0)

# ------------------------------------------------------------------ построитель меша

class MB:
	"""Накопитель геометрии: вершины, грани, цвет и UV на угол грани."""
	def __init__(self):
		self.v = []      # Vector
		self.f = []      # (idx...)
		self.fc = []     # [(r,g,b,a) на угол]
		self.fu = []     # [(u,v) на угол]
		self.vc = []     # цвет вершины (используется по умолчанию)
		self.vu = []     # uv вершины

	def add_v(self, p, c, uv):
		self.v.append(Vector(p))
		self.vc.append(c)
		self.vu.append(uv)
		return len(self.v) - 1

	def face(self, idx):
		self.f.append(tuple(idx))

	def tube(self, pts, radii, sides, cols, flex, cap=True, ring_noise=0.0, seed=0, flat=1.0, tip_k=0.9):
		"""Труба по ломаной pts (Vector), радиусы и цвета на точку, гибкость на точку."""
		n = len(pts)
		rings = []
		prev_u = None
		for i in range(n):
			if i < n - 1:
				ax = (pts[i + 1] - pts[i]).normalized()
			else:
				ax = (pts[i] - pts[i - 1]).normalized()
			if i > 0 and i < n - 1:
				ax = ((pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()).normalized()
			if prev_u is None:
				ref = Vector((0, 0, 1)) if abs(ax.z) < 0.9 else Vector((1, 0, 0))
				u = ax.cross(ref).normalized()
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
				off = u * math.cos(a) * r + v * math.sin(a) * r * flat
				ring.append(self.add_v(pts[i] + off, cols[i], (0.0, flex[i])))
			rings.append(ring)
		for i in range(n - 1):
			a, b = rings[i], rings[i + 1]
			for s in range(sides):
				s1 = (s + 1) % sides
				self.face((a[s], a[s1], b[s1], b[s]))
		if cap:
			tipdir = (pts[-1] - pts[-2]).normalized()
			tip = self.add_v(pts[-1] + tipdir * radii[-1] * tip_k, cols[-1], (0.0, flex[-1]))
			last = rings[-1]
			for s in range(sides):
				self.face((last[s], last[(s + 1) % sides], tip))
		return rings

	def to_object(self, name):
		me = bpy.data.meshes.new(name)
		me.from_pydata([tuple(p) for p in self.v], [], self.f)
		me.update()
		col = me.color_attributes.new("Col", 'FLOAT_COLOR', 'CORNER')
		uvl = me.uv_layers.new(name="UVMap")
		for poly in me.polygons:
			for li in poly.loop_indices:
				vi = me.loops[li].vertex_index
				col.data[li].color = self.vc[vi]
				uvl.data[li].uv = self.vu[vi]
		ob = bpy.data.objects.new(name, me)
		bpy.context.scene.collection.objects.link(ob)
		return ob

def tri_count(ob):
	return sum(len(p.vertices) - 2 for p in ob.data.polygons)

def shade_smooth(ob):
	ob.data.shade_smooth()

def decimate_to(ob, target_tris):
	"""Упростить (collapse) до target_tris, сохраняя цвет/UV; вернуть новый объект."""
	t = tri_count(ob)
	if t <= target_tris:
		return ob
	m = ob.modifiers.new("dec", 'DECIMATE')
	m.ratio = max(0.02, target_tris / float(t))
	m.use_collapse_triangulate = True
	dg = bpy.context.evaluated_depsgraph_get()
	ev = ob.evaluated_get(dg)
	me = bpy.data.meshes.new_from_object(ev)
	ob.modifiers.clear()
	ob2 = bpy.data.objects.new(ob.name, me)
	bpy.context.scene.collection.objects.link(ob2)
	bpy.data.objects.remove(ob)
	return ob2

def remesh_blob(spheres, voxel, name, colfn, flexfn=None):
	"""Органический комок: набор (центр, радиус, шум) → вокс. ремеш → цвет по функции."""
	bm = bmesh.new()
	for (c, r, nz, sd) in spheres:
		m = bmesh.ops.create_icosphere(bm, subdivisions=3, radius=r)
		for v in m["verts"]:
			d = v.co.normalized()
			k = 1.0 + nz * noise.noise(d * 2.3 + Vector((sd, sd * 0.7, sd * 1.3)))
			v.co = Vector(c) + d * r * k
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	ob = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(ob)
	rm = ob.modifiers.new("rm", 'REMESH')
	rm.mode = 'VOXEL'
	rm.voxel_size = voxel
	rm.use_smooth_shade = True
	dg = bpy.context.evaluated_depsgraph_get()
	me2 = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
	bpy.data.objects.remove(ob)
	mb = MB()
	for v in me2.vertices:
		mb.add_v(v.co, colfn(v.co, v.normal), (0.0, flexfn(v.co) if flexfn else 0.0))
	for p in me2.polygons:
		mb.face(tuple(p.vertices))
	bpy.data.meshes.remove(me2)
	return mb

def bake_shade(mb, ao_h=0.35, ao_k=0.45):
	"""Дешёвое «запекание» затенения в цвет вершин: ниже и глубже внутри — темнее."""
	if not mb.v:
		return
	zmin = min(p.z for p in mb.v)
	zmax = max(p.z for p in mb.v)
	cx = sum(p.x for p in mb.v) / len(mb.v)
	cy = sum(p.y for p in mb.v) / len(mb.v)
	rmax = max(max(math.hypot(p.x - cx, p.y - cy) for p in mb.v), 0.01)
	hz = max(zmax - zmin, 0.01)
	for i, p in enumerate(mb.v):
		h = (p.z - zmin) / hz
		rr = math.hypot(p.x - cx, p.y - cy) / rmax
		occl = (1.0 - min(1.0, h / ao_h)) * 0.6 + (1.0 - rr) * (1.0 - h) * 0.4
		k = 1.0 - ao_k * max(0.0, min(1.0, occl))
		c = mb.vc[i]
		mb.vc[i] = (c[0] * k, c[1] * k, c[2] * k, 1.0)

# ------------------------------------------------------------------ типы

def gen_table(seed, tiers):
	rnd = random.Random(seed)
	mb = MB()
	top = hexc("#D99070"); top2 = hexc("#E8A888"); rim = hexc("#F6E2C8"); under = hexc("#B07868")
	stem_c = hexc("#7A4E40")
	mb.tube([Vector((0, 0, 0)), Vector((0.02, 0.0, 0.25)), Vector((0.0, 0.03, 0.42))], [0.13, 0.09, 0.08], 6,
		[mul(stem_c, 0.6), stem_c, stem_c], [0, 0, 0], cap=False)
	plates = []
	base_r = rnd.uniform(1.0, 1.2)
	for t in range(tiers):
		r = base_r * (1.0 - 0.3 * t) * rnd.uniform(0.9, 1.05)
		plates.append((rnd.uniform(-0.3, 0.3) * t, rnd.uniform(-0.3, 0.3) * t, 0.42 + 0.2 * t + rnd.uniform(-0.03, 0.05), r))
	n_total = {1: 300, 2: 330, 3: 330}[tiers]
	area = sum(p[3] ** 2 for p in plates)
	for (cx, cy, z, r) in plates:
		RS = 30; RR = 4
		phase = rnd.uniform(0, 6.28)
		lob = rnd.randint(4, 6)
		def edge_r(a, r=r, phase=phase, lob=lob):
			return r * (1.0 + 0.12 * math.sin(a * lob + phase) + 0.04 * math.sin(a * (lob * 2 + 1) + phase * 1.7))
		def ring_pt(a, f, cx=cx, cy=cy, z=z, phase=phase, lob=lob, edge_r=edge_r):
			er = edge_r(a) * f
			lift = 0.08 * f * f + 0.07 * f ** 4 * (0.5 + 0.5 * math.sin(a * lob + phase))  # загнутые лепестки
			return Vector((cx + math.cos(a) * er, cy + math.sin(a) * er, z + lift))
		ctop = mb.add_v(Vector((cx, cy, z + 0.03)), top, (0, 0))
		cbot = mb.add_v(Vector((cx, cy, z - 0.03)), under, (0, 0))
		rows_t = []; rows_b = []
		for k in range(1, RR + 1):
			f = (k / RR) ** 0.8
			rt = []; rb = []
			for s in range(RS):
				a = math.tau * s / RS
				p = ring_pt(a, f)
				patch = 0.5 + 0.5 * noise.noise(p * 2.2 + Vector((seed, 0, 0)))
				ct = lerp(lerp(top, top2, patch), rim, max(0.0, (f - 0.82) / 0.18))
				rt.append(mb.add_v(p + Vector((0, 0, 0.025 * (1 - f))), ct, (0, 0)))
				rb.append(mb.add_v(p - Vector((0, 0, 0.04 * (1 - f) + 0.012)), mul(under, 0.8 + 0.2 * f), (0, 0)))
			rows_t.append(rt); rows_b.append(rb)
		for s in range(RS):
			s1 = (s + 1) % RS
			mb.face((ctop, rows_t[0][s], rows_t[0][s1]))
			mb.face((cbot, rows_b[0][s1], rows_b[0][s]))
		for k in range(RR - 1):
			for s in range(RS):
				s1 = (s + 1) % RS
				mb.face((rows_t[k][s], rows_t[k + 1][s], rows_t[k + 1][s1], rows_t[k][s1]))
				mb.face((rows_b[k][s1], rows_b[k + 1][s1], rows_b[k + 1][s], rows_b[k][s]))
		for s in range(RS):
			s1 = (s + 1) % RS
			mb.face((rows_t[-1][s], rows_b[-1][s], rows_b[-1][s1], rows_t[-1][s1]))
		# густой ворс коротких веточек сверху, у кромки — светлые и наклонены наружу
		n_br = int(n_total * r * r / area)
		for i in range(n_br):
			f = math.sqrt(rnd.random()) * 0.98
			if rnd.random() < 0.35:
				f = rnd.uniform(0.85, 0.99)       # кромку гуще
			a = rnd.random() * math.tau
			p = ring_pt(a, f) + Vector((0, 0, 0.015))
			h = rnd.uniform(0.05, 0.09) * (0.8 + 0.4 * f)
			rad = rnd.uniform(0.014, 0.022)
			tipc = lerp(top2, rim, 0.5 + 0.5 * f)
			lean = Vector((math.cos(a), math.sin(a), 0)) * (f ** 2) * 0.9
			b = p + (Vector((0, 0, 1)) + lean).normalized() * h
			mb.tube([p, b], [rad, rad * 0.55], 3, [mul(top, 0.85), tipc], [0, 0])
	bake_shade(mb, 0.5, 0.3)
	return mb

def branch_tree(mb, rnd, base, dirv, length, rad, depth, maxd, cols, tip_col, sides, fork_n=(2, 3), spread=0.55, up=0.35, flatten=1.0, segs=3, taper=0.72):
	pts = [base]
	d = dirv.normalized()
	for i in range(segs):
		d = (d + Vector((rnd.uniform(-0.2, 0.2), rnd.uniform(-0.2, 0.2), up * 0.4))).normalized()
		pts.append(pts[-1] + d * (length / segs))
	r0 = rad; r1 = rad * taper
	radii = [r0 + (r1 - r0) * i / segs for i in range(segs + 1)]
	f = depth / float(max(maxd, 1))
	c0 = lerp(cols[0], cols[1], f)
	c1 = lerp(cols[0], cols[1], min(1.0, f + 1.0 / max(maxd, 1)))
	colsl = [lerp(c0, c1, i / segs) for i in range(segs + 1)]
	is_tip = depth >= maxd
	if is_tip:
		colsl[-1] = tip_col
	mb.tube(pts, radii, sides, colsl, [0] * (segs + 1), cap=is_tip, flat=flatten)
	if not is_tip:
		k = rnd.randint(*fork_n)
		for j in range(k):
			nd = (d + Vector((rnd.uniform(-spread, spread), rnd.uniform(-spread, spread), rnd.uniform(-0.1, spread * 0.6) + up))).normalized()
			branch_tree(mb, rnd, pts[-1], nd, length * rnd.uniform(0.7, 0.9), r1, depth + 1, maxd, cols, tip_col, sides, fork_n, spread, up, flatten, segs, taper)

def fib_dome(n, el_min=0.15):
	"""Равномерные направления по куполу (по Фибоначчи)."""
	out = []
	ga = math.pi * (3 - math.sqrt(5))
	for i in range(n):
		z = el_min + (1.0 - el_min) * (i + 0.5) / n
		r = math.sqrt(max(0.0, 1 - z * z))
		a = ga * i
		out.append(Vector((math.cos(a) * r, math.sin(a) * r, z)))
	return out

def gen_staghorn(seed):
	rnd = random.Random(seed)
	mb = MB()
	base = hexc("#7E4E50"); mid = hexc("#B07272"); tip = hexc("#E6B8B0")
	for d in fib_dome(46, 0.15):
		d = (d + Vector((rnd.uniform(-.12, .12), rnd.uniform(-.12, .12), 0))).normalized()
		d = Vector((d.x * 1.3, d.y * 1.3, d.z)).normalized()       # купол шире, чем выше
		p = Vector((d.x * 0.2, d.y * 0.2, 0.0))
		branch_tree(mb, rnd, p, d, rnd.uniform(0.17, 0.24), 0.034, 0, 2, [base, mid], tip, 4, (2, 2), 0.5, 0.12, segs=1, taper=0.8)
	for i in range(4):   # обломки
		a = rnd.random() * math.tau
		p = Vector((math.cos(a) * rnd.uniform(0.8, 1.0), math.sin(a) * rnd.uniform(0.8, 1.0), 0.02))
		d = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0.1))
		branch_tree(mb, rnd, p, d, 0.1, 0.018, 1, 2, [mid, mid], tip, 3, (1, 2), 0.6, 0.0, segs=1)
	bake_shade(mb, 0.45, 0.5)
	return mb

def gen_corymbose(seed):
	rnd = random.Random(seed)
	mb = MB()
	base = grey(0.55); mid = grey(0.82); tip = grey(0.98)
	R = 0.5
	for i, d in enumerate(fib_dome(95, 0.05)):
		d = (d + Vector((rnd.uniform(-.08, .08), rnd.uniform(-.08, .08), 0))).normalized()
		start = Vector((d.x * R * 0.3, d.y * R * 0.3, R * 0.12))
		end = Vector((d.x * R, d.y * R, d.z * R * 0.8 + R * 0.08)) * rnd.uniform(0.82, 0.95)
		mid_p = start + (end - start) * 0.55 + Vector((0, 0, 0.02))
		rad = rnd.uniform(0.04, 0.055)
		mb.tube([start, mid_p, end], [rad * 1.15, rad * 1.05, rad * 0.95], 5, [base, mid, tip], [0, 0, 0], ring_noise=0.15, seed=i, tip_k=0.55)
	core = remesh_blob([((0, 0, R * 0.15), R * 0.5, 0.25, seed)], 0.06, "core", lambda p, n: base)
	off = len(mb.v)
	for i, p in enumerate(core.v):
		p.z = max(p.z, 0.0)
		mb.add_v(p, core.vc[i], core.vu[i])
	for f in core.f:
		mb.face(tuple(x + off for x in f))
	bake_shade(mb, 0.45, 0.5)
	return mb

def gen_lobed(seed):
	rnd = random.Random(seed)
	sph = []
	R = 0.36
	# короткие толстые «пальцы-лопасти» (по 3 шара вдоль оси) с просветами между ними
	for i, d in enumerate(fib_dome(26, 0.2)):
		base_p = Vector((d.x * R * 0.55, d.y * R * 0.55, R * 0.25))
		ax = (d + Vector((0, 0, 0.6))).normalized()
		rr = rnd.uniform(0.05, 0.07)
		ln = rnd.uniform(0.12, 0.2)
		for k in range(3):
			sph.append((base_p + ax * ln * k / 2.0, rr * (1.0 - 0.1 * k), 0.35, rnd.random() * 10))
	sph.append((Vector((0, 0, R * 0.2)), R * 0.55, 0.15, 3.3))
	def col(p, n):
		k = 0.72 + 0.3 * max(0.0, n.z) + 0.12 * noise.noise(p * 18.0)
		return grey(min(1.0, k))
	mb = remesh_blob(sph, 0.016, "lobed", col)
	for p in mb.v:
		if p.z < 0:
			p.z = 0.0
	bake_shade(mb, 0.35, 0.45)
	return mb

def gen_foliose(seed, colr):
	rnd = random.Random(seed)
	mb = MB()
	c0 = hexc(colr); c1 = mul(hexc(colr), 0.55)
	for t in range(rnd.randint(5, 7)):
		a0 = rnd.random() * math.tau
		cx = rnd.uniform(-0.15, 0.15); cy = rnd.uniform(-0.15, 0.15)
		z = 0.04 + t * 0.06
		r = rnd.uniform(0.2, 0.34)
		span = rnd.uniform(1.8, 2.8)
		RS, RR = 14, 4
		rows = []
		for k in range(RR + 1):
			f = k / RR
			row = []
			for s in range(RS + 1):
				a = a0 + span * (s / RS - 0.5)
				rr = r * f
				wav = 0.045 * math.sin((s / RS) * math.pi * 3.0 + t) * f * f
				p = Vector((cx + math.cos(a) * rr, cy + math.sin(a) * rr, z + 0.2 * f * f + wav))
				cc = lerp(c1, c0, f)
				if k == RR:
					cc = lerp(c0, hexc("#FFF4DC"), 0.4)
				row.append(mb.add_v(p, cc, (0, 0)))
			rows.append(row)
		for k in range(RR):
			for s in range(RS):
				mb.face((rows[k][s], rows[k][s + 1], rows[k + 1][s + 1], rows[k + 1][s]))
	bake_shade(mb, 0.4, 0.4)
	return mb

def gen_antler(seed, cols):
	rnd = random.Random(seed)
	mb = MB()
	base = hexc(cols[0]); tip = hexc(cols[1])
	for k in range(2):
		d = Vector((rnd.uniform(-.3, .3), rnd.uniform(-.3, .3), 1))
		branch_tree(mb, rnd, Vector((rnd.uniform(-.05, .05), rnd.uniform(-.05, .05), 0)), d, 0.3, 0.05, 0, 4,
			[mul(base, 0.7), base], tip, 5, (2, 2), 0.7, 0.2, flatten=0.85, segs=2, taper=0.75)
	bake_shade(mb, 0.3, 0.35)
	return mb

def gen_softcoral(seed, colr):
	rnd = random.Random(seed)
	mb = MB()
	c = hexc(colr); dark = mul(c, 0.65)
	trunk = [Vector((0, 0, 0)), Vector((0.02, 0, 0.14)), Vector((0, 0.02, 0.28))]
	mb.tube(trunk, [0.08, 0.065, 0.05], 6, [dark, c, c], [0, 0.1, 0.25], cap=False)
	crowns = []
	for i in range(12):
		a = rnd.random() * math.tau
		st = trunk[1 + rnd.randint(0, 1)]
		d = Vector((math.cos(a), math.sin(a), rnd.uniform(0.5, 1.5))).normalized()
		end = st + d * rnd.uniform(0.16, 0.28)
		mid_p = (st + end) * 0.5 + Vector((0, 0, 0.03))
		mb.tube([st, mid_p, end], [0.03, 0.022, 0.016], 4, [c, c, c], [0.2, 0.5, 0.8], cap=True)
		crowns.append([(end + Vector((rnd.uniform(-.07, .07), rnd.uniform(-.07, .07), rnd.uniform(-.03, .07))),
			rnd.uniform(0.032, 0.05), 0.3, rnd.random() * 9) for k in range(rnd.randint(6, 8))])
	# кроны-гроздья — один гладкий комковатый меш (воксельный ремеш), гнутся как мягкие
	allsph = [x for cr in crowns for x in cr]
	light = lerp(c, hexc("#FFFFFF"), 0.25)
	blob = remesh_blob(allsph, 0.018, "crowns", lambda p, n: lerp(c, light, max(0.0, n.z) * 0.6 + 0.2), lambda p: 0.9)
	off = len(mb.v)
	for i, p in enumerate(blob.v):
		mb.add_v(p, blob.vc[i], (1.0, 0.9))
	for f in blob.f:
		mb.face(tuple(x + off for x in f))
	bake_shade(mb, 0.35, 0.35)
	return mb

def gen_tentacles(mb, rnd, center_fn, n, len_rng, rad, col0, col1, sides=4, segs=3, curl=0.4, outward=0.6, flex0=0.15, tipc=None, wiggle=0.0):
	first = len(mb.v)
	for i in range(n):
		p0, nrm = center_fn(rnd)
		ln = rnd.uniform(*len_rng)
		d = (nrm + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)) * outward).normalized()
		bend = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.6, 0.1))) * curl
		side = d.cross(Vector((0, 0, 1)))
		if side.length < 0.01:
			side = Vector((1, 0, 0))
		side.normalize()
		ph = rnd.uniform(0, 6.28)
		pts = [p0]
		for s in range(1, segs + 1):
			t = s / segs
			w = side * math.sin(t * 5.0 + ph) * wiggle * ln * t
			pts.append(p0 + d * ln * t + bend * ln * t * t + w)
		radii = [rad * (1.0 - 0.55 * (s / segs)) for s in range(segs + 1)]
		cols = [lerp(col0, col1, s / segs) for s in range(segs + 1)]
		if tipc:
			cols[-1] = tipc
		flex = [flex0 + (1.0 - flex0) * (s / segs) for s in range(segs + 1)]
		mb.tube(pts, radii, sides, cols, flex, cap=True)
	for i in range(first, len(mb.vu)):
		mb.vu[i] = (1.0, mb.vu[i][1])

def gen_leather(seed):
	rnd = random.Random(seed)
	mb = MB()
	cup0 = hexc("#B07878"); cup1 = hexc("#E6C2B6"); fr0 = hexc("#C8B868"); fr1 = hexc("#EEE6B8")
	R = 0.45; H = 0.24
	lob = rnd.randint(3, 4); ph = rnd.uniform(0, 6)
	RS, RR = 28, 6
	def cup_pt(a, f):
		er = R * (1.0 + 0.18 * math.sin(a * lob + ph)) * (0.25 + 0.75 * f)
		z = H * f ** 1.6 + 0.06 * f * f * math.sin(a * lob * 2 + ph)
		return Vector((math.cos(a) * er, math.sin(a) * er, z))
	rows = []
	for k in range(RR + 1):
		f = k / RR
		row = []
		for s in range(RS):
			a = math.tau * s / RS
			p = cup_pt(a, f)
			rib = 0.5 + 0.5 * math.sin(a * 26)
			cc = lerp(cup0, cup1, f * 0.75 + rib * 0.2)
			row.append(mb.add_v(p, cc, (0, 0)))
		rows.append(row)
	bottom = mb.add_v(Vector((0, 0, 0)), mul(cup0, 0.7), (0, 0))
	for s in range(RS):
		mb.face((bottom, rows[0][(s + 1) % RS], rows[0][s]))
	for k in range(RR):
		for s in range(RS):
			s1 = (s + 1) % RS
			mb.face((rows[k][s], rows[k][s1], rows[k + 1][s1], rows[k + 1][s]))
	ctop = mb.add_v(Vector((0, 0, H * 0.8)), hexc("#B8A870"), (0, 0))
	for s in range(RS):
		mb.face((ctop, rows[RR][s], rows[RR][(s + 1) % RS]))
	def where(r):
		a = r.random() * math.tau
		f = math.sqrt(r.uniform(0.2, 1.0))
		if r.random() < 0.4:
			f = r.uniform(0.85, 1.0)
		p = cup_pt(a, 1.0)
		q = Vector((p.x * f, p.y * f, H * 0.8 + (p.z - H * 0.8) * f))
		n = Vector((math.cos(a) * 0.7 * f, math.sin(a) * 0.7 * f, 1.0)).normalized()
		return q, n
	gen_tentacles(mb, rnd, where, 330, (0.06, 0.1), 0.016, fr0, fr1, sides=3, segs=1, curl=0.2, outward=0.3)
	bake_shade(mb, 0.35, 0.3)
	return mb

def gen_anemone(seed, colr):
	rnd = random.Random(seed)
	mb = MB()
	c = hexc(colr); dark = mul(c, 0.7)
	RS = 16
	center = mb.add_v(Vector((0, 0, 0.07)), dark, (0, 0))
	ring = [mb.add_v(Vector((math.cos(math.tau * s / RS) * 0.24, math.sin(math.tau * s / RS) * 0.24, 0.04)), dark, (0, 0)) for s in range(RS)]
	ring2 = [mb.add_v(Vector((math.cos(math.tau * s / RS) * 0.28, math.sin(math.tau * s / RS) * 0.28, 0.0)), mul(dark, 0.8), (0, 0)) for s in range(RS)]
	for s in range(RS):
		s1 = (s + 1) % RS
		mb.face((center, ring[s], ring[s1]))
		mb.face((ring[s], ring2[s], ring2[s1], ring[s1]))
	def where(r):
		a = r.random() * math.tau
		f = math.sqrt(r.random())
		q = Vector((math.cos(a) * 0.24 * f, math.sin(a) * 0.24 * f, 0.06))
		n = Vector((math.cos(a) * (0.2 + 0.9 * f), math.sin(a) * (0.2 + 0.9 * f), 1.4 - f * 0.6)).normalized()
		return q, n
	gen_tentacles(mb, rnd, where, 72, (0.24, 0.38), 0.042, c, lerp(c, hexc("#FFFFFF"), 0.3), sides=4, segs=5,
		curl=0.8, outward=0.3, flex0=0.1, wiggle=0.2)
	bake_shade(mb, 0.3, 0.35)
	return mb

def gen_bubble(seed):
	rnd = random.Random(seed)
	yel = hexc("#E8C030")
	sph = [((0, 0, 0.14), 0.17, 0.2, 1.0)]
	for i in range(6):
		a = math.tau * i / 6 + rnd.uniform(-.3, .3)
		sph.append(((math.cos(a) * 0.12, math.sin(a) * 0.12, rnd.uniform(0.06, 0.16)), rnd.uniform(0.09, 0.12), 0.25, i * 2.0))
	def col(p, n):
		k = 0.8 + 0.2 * max(0.0, n.z)
		return mul(yel, k)
	mb = remesh_blob(sph, 0.02, "bubble", col)
	for p in mb.v:
		if p.z < 0:
			p.z = 0.0
	zmax = max(p.z for p in mb.v)
	def where(r):
		a = r.random() * math.tau
		f = math.sqrt(r.random())
		q = Vector((math.cos(a) * 0.2 * f, math.sin(a) * 0.2 * f, zmax - 0.03 - 0.05 * f * f))
		n = Vector((math.cos(a) * f, math.sin(a) * f, 1.0)).normalized()
		return q, n
	gen_tentacles(mb, rnd, where, 170, (0.07, 0.13), 0.015, hexc("#9A9A92"), hexc("#C4C4BC"), sides=3, segs=2, curl=0.35, outward=0.35, tipc=hexc("#F6F6EE"))
	bake_shade(mb, 0.25, 0.25)
	return mb

def gen_crinoid(seed):
	rnd = random.Random(seed)
	mb = MB()
	c0 = hexc("#A89010"); c1 = hexc("#E4D030")
	arms = 22
	for i in range(arms):
		a = math.tau * i / arms + rnd.uniform(-.15, .15)
		el = rnd.uniform(0.7, 1.35)
		ln = rnd.uniform(0.3, 0.42)
		bend = rnd.uniform(0.8, 1.5)
		pts = []
		for s in range(7):
			t = s / 6
			ang = el - t * bend
			r = ln * t
			pts.append(Vector((math.cos(a) * r * math.cos(ang) * 1.1, math.sin(a) * r * math.cos(ang) * 1.1, 0.05 + r * math.sin(ang) * 0.9 + 0.12 * t)))
		flex = [0.1 + 0.9 * (s / 6) for s in range(7)]
		mb.tube(pts, [0.013, 0.012, 0.011, 0.009, 0.007, 0.005, 0.003], 3, [lerp(c0, c1, s / 6) for s in range(7)], flex)
		for s in range(1, 6):
			p = pts[s]; d = (pts[s + 1] - pts[s]).normalized()
			side = d.cross(Vector((0, 0, 1)))
			if side.length < 0.01:
				side = Vector((1, 0, 0))
			side.normalize()
			for sg in (-1, 1):
				ln_p = 0.05 * (1.0 - 0.12 * s)
				q = p + side * sg * ln_p + d * 0.03 + Vector((0, 0, 0.01))
				i0 = mb.add_v(p, c0, (1.0, flex[s]))
				i1 = mb.add_v(q, c1, (1.0, min(1.0, flex[s] + 0.1)))
				i2 = mb.add_v(p + d * 0.035, c0, (1.0, flex[s]))
				mb.face((i0, i1, i2)); mb.face((i0, i2, i1))
	for i in range(len(mb.vu)):
		if mb.vu[i][1] > 0:
			mb.vu[i] = (1.0, mb.vu[i][1])
	return mb

def gen_mound(seed, colr):
	rnd = random.Random(seed)
	c = hexc(colr)
	sph = []
	for i in range(11):
		a = rnd.random() * math.tau; rr = rnd.uniform(0, 0.28)
		sph.append(((math.cos(a) * rr, math.sin(a) * rr, 0.0), rnd.uniform(0.1, 0.2), 0.45, i * 1.7))
	def col(p, n):
		k = 0.7 + 0.35 * max(0.0, n.z) + 0.15 * noise.noise(p * 20.0)
		return mul(c, k)
	mb = remesh_blob(sph, 0.03, "mound", col)
	for p in mb.v:
		if p.z < 0:
			p.z = 0.0
	return mb

# ------------------------------------------------------------------ сборка

SPEC = [
	# (тип, вариант, функция, бюджет LOD0, LOD1)
	("table", 0, lambda: gen_table(11, 1), 3400, 900),
	("table", 1, lambda: gen_table(12, 2), 3600, 1000),
	("table", 2, lambda: gen_table(13, 3), 3800, 1100),
	("staghorn", 0, lambda: gen_staghorn(21), 3400, 900),
	("staghorn", 1, lambda: gen_staghorn(22), 3400, 900),
	("corymbose", 0, lambda: gen_corymbose(31), 2600, 700),
	("corymbose", 1, lambda: gen_corymbose(32), 2600, 700),
	("lobed", 0, lambda: gen_lobed(41), 1800, 500),
	("lobed", 1, lambda: gen_lobed(42), 1800, 500),
	("foliose", 0, lambda: gen_foliose(51, "#CDB070"), 900, 300),
	("foliose", 1, lambda: gen_foliose(52, "#D07A40"), 900, 300),
	("antler", 0, lambda: gen_antler(61, ["#B07840", "#E8C08A"]), 1600, 450),
	("antler", 1, lambda: gen_antler(62, ["#C07060", "#F0B0A0"]), 1600, 450),
	("softcoral", 0, lambda: gen_softcoral(71, "#E8D8B0"), 2400, 600),
	("softcoral", 1, lambda: gen_softcoral(72, "#E09A9A"), 2400, 600),
	("leather", 0, lambda: gen_leather(81), 3400, 900),
	("anemone", 0, lambda: gen_anemone(91, "#EEEDE6"), 3200, 900),
	("anemone", 1, lambda: gen_anemone(92, "#D8CCAA"), 3200, 900),
	("bubble", 0, lambda: gen_bubble(101), 2600, 700),
	("crinoid", 0, lambda: gen_crinoid(111), 1600, 600),
	("mound", 0, lambda: gen_mound(121, "#7A5A38"), 700, 250),
	("mound", 1, lambda: gen_mound(122, "#6A6A3A"), 700, 250),
]

def main():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	report = []
	only = os.environ.get("CORAL_ONLY", "")
	for (t, vi, fn, b0, b1) in SPEC:
		if only and t not in only.split(","):
			continue
		mb = fn()
		ob = mb.to_object("%s_v%d_src" % (t, vi))
		src_tris = tri_count(ob)
		bpy.context.view_layer.objects.active = ob
		lod0 = ob.copy(); lod0.data = ob.data.copy(); lod0.name = "%s_v%d_lod0" % (t, vi)
		bpy.context.scene.collection.objects.link(lod0)
		lod0 = decimate_to(lod0, b0)
		lod0.name = "%s_v%d_lod0" % (t, vi)
		lod1 = ob.copy(); lod1.data = ob.data.copy(); lod1.name = "%s_v%d_lod1" % (t, vi)
		bpy.context.scene.collection.objects.link(lod1)
		lod1 = decimate_to(lod1, b1)
		lod1.name = "%s_v%d_lod1" % (t, vi)
		for o in (lod0, lod1):
			shade_smooth(o)
		bpy.data.objects.remove(ob)
		report.append((t, vi, src_tris, tri_count(lod0), tri_count(lod1)))
		print("CORAL", t, vi, src_tris, tri_count(lod0), tri_count(lod1), flush=True)
	bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "corals.glb"), export_format='GLB',
		export_colors=True, export_normals=True, export_texcoords=True, export_apply=False,
		export_materials='NONE', export_yup=True)
	with open(os.path.join(OUT, "report.tsv"), "w") as f:
		f.write("type\tvar\tsrc_tris\tlod0\tlod1\n")
		for r in report:
			f.write("\t".join(str(x) for x in r) + "\n")

main()
