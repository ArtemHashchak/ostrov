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
		self.vu2 = []    # uv2 (координаты в плитке атласа у карточек)
		self.cards = None   # отдельный MB с карточками (не упрощается, на LOD1 — половина, на LOD2 — нет)

	def add_v(self, p, c, uv, uv2=(0.0, 0.0)):
		self.v.append(Vector(p))
		self.vc.append(c)
		self.vu.append(uv)
		self.vu2.append(uv2)
		return len(self.v) - 1

	def card(self, p, up, side, tile, c0, c1, flex0=0.0, flex1=0.0, cross=True, u0=0.0, u1=1.0):
		"""Карточка атласа: квад от p вдоль up (высота=|up|), ширина=|side|; cross — ещё квад поперёк.
		UV.x = 4 + плитка (0 бахрома, 1 перо, 2 полипы, 3 щетина), UV.y — гибкость, UV2 — 0..1 в плитке."""
		if self.cards is None:
			self.cards = MB()
		cm = self.cards
		sides = [side]
		if cross:
			sides.append(up.normalized().cross(side).normalized() * side.length)
		for sd in sides:
			a = cm.add_v(p - sd * 0.5, c0, (4.0 + tile, flex0), (u0, 1.0))
			b = cm.add_v(p + sd * 0.5, c0, (4.0 + tile, flex0), (u1, 1.0))
			c = cm.add_v(p + sd * 0.5 + up, c1, (4.0 + tile, flex1), (u1, 0.0))
			d = cm.add_v(p - sd * 0.5 + up, c1, (4.0 + tile, flex1), (u0, 0.0))
			cm.face((a, b, c, d))
		return cm

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
		uv2 = me.uv_layers.new(name="UV2")
		for poly in me.polygons:
			for li in poly.loop_indices:
				vi = me.loops[li].vertex_index
				col.data[li].color = self.vc[vi]
				uvl.data[li].uv = self.vu[vi]
				uv2.data[li].uv = self.vu2[vi] if vi < len(self.vu2) else (0.0, 0.0)
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

def _join(dst, src):
	off = len(dst.v)
	for i, p in enumerate(src.v):
		dst.add_v(p, src.vc[i], src.vu[i], src.vu2[i] if i < len(src.vu2) else (0, 0))
	for f in src.f:
		dst.face(tuple(x + off for x in f))

def _perp(d):
	ref = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
	return d.cross(ref).normalized()

# ------------------------------------------------------------------ столовая акропора (v2)

def gen_table(seed, tiers):
	"""Широкий многолопастной волнистый стол: контур — объединение 3–5 кругов-лопастей,
	светлая кромка, густой ворс (оболочки + карточки щетины по кромке и сверху)."""
	rnd = random.Random(seed)
	mb = MB()
	top = hexc("#D99A78"); top2 = hexc("#E8B090"); rim = hexc("#F8E8D2"); under = hexc("#A87060")
	stem_c = hexc("#806050")
	mb.tube([Vector((0, 0, 0)), Vector((0.02, 0.0, 0.25)), Vector((0.0, 0.03, 0.4))], [0.14, 0.1, 0.09], 6,
		[mul(stem_c, 0.6), stem_c, stem_c], [0, 0, 0], cap=False)
	for t in range(tiers):
		R = rnd.uniform(1.05, 1.25) * (1.0 - 0.3 * t)
		cx = rnd.uniform(-0.3, 0.3) * t; cy = rnd.uniform(-0.3, 0.3) * t
		z = 0.4 + 0.2 * t + rnd.uniform(-0.03, 0.04)
		lobes = []
		nl = rnd.randint(3, 5)
		for i in range(nl):
			a = math.tau * i / nl + rnd.uniform(-0.4, 0.4)
			d = R * rnd.uniform(0.35, 0.55)
			lobes.append((Vector((math.cos(a) * d, math.sin(a) * d, 0)), R * rnd.uniform(0.45, 0.62)))
		lobes.append((Vector((0, 0, 0)), R * 0.5))
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
		RS = 40; RR = 5
		def ring_pt(a, f, cx=cx, cy=cy, z=z, ph=ph, edge_r=edge_r):
			er = edge_r(a) * f
			lift = 0.06 * f * f + 0.09 * f ** 4 * (0.5 + 0.5 * math.sin(a * 6 + ph))   # кромка волной вверх
			return Vector((cx + math.cos(a) * er, cy + math.sin(a) * er, z + lift))
		ctop = mb.add_v(Vector((cx, cy, z + 0.035)), top, (0, 0))
		cbot = mb.add_v(Vector((cx, cy, z - 0.035)), under, (0, 0))
		rows_t = []; rows_b = []
		for k in range(1, RR + 1):
			f = (k / RR) ** 0.75
			rt = []; rb = []
			for s in range(RS):
				a = math.tau * s / RS
				p = ring_pt(a, f)
				patch = 0.5 + 0.5 * noise.noise(p * 2.0 + Vector((seed, 0, 0)))
				ct = lerp(lerp(top, top2, patch), rim, max(0.0, (f - 0.86) / 0.14))
				th = 0.045 * (1 - f) + 0.012
				rt.append(mb.add_v(p + Vector((0, 0, th * 0.5)), ct, (0, 0)))
				rb.append(mb.add_v(p - Vector((0, 0, th)), mul(under, 0.8 + 0.2 * f), (0, 0)))
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
		# ворс-оболочки (шейдер оставляет точки-кончики)
		for layer, dz in ((1, 0.03), (2, 0.06)):
			cs = mb.add_v(Vector((cx, cy, z + 0.035 + dz)), lerp(top2, rim, 0.3 * layer), (2.0 + 0.6 * layer, 0))
			rows_s = []
			for k in range(RR):
				rs = []
				for s in range(RS):
					p = mb.v[rows_t[k][s]] + Vector((0, 0, dz))
					f = (k + 1) / RR
					rs.append(mb.add_v(p, lerp(lerp(top2, rim, 0.25 * layer), rim, max(0.0, (f - 0.8) / 0.2)), (2.0 + 0.6 * layer, 0)))
				rows_s.append(rs)
			for s in range(RS):
				mb.face((cs, rows_s[0][s], rows_s[0][(s + 1) % RS]))
			for k in range(RR - 1):
				for s in range(RS):
					s1 = (s + 1) % RS
					mb.face((rows_s[k][s], rows_s[k + 1][s], rows_s[k + 1][s1], rows_s[k][s1]))
		# щетина по кромке: карточки наружу-вверх, светлые
		for s in range(0, RS * 3):
			a = math.tau * (s + rnd.random()) / (RS * 3)
			p = ring_pt(a, 0.985)
			out = Vector((math.cos(a), math.sin(a), 0))
			up = (out * 0.8 + Vector((0, 0, 1))).normalized() * rnd.uniform(0.07, 0.1)
			mb.card(p, up, _perp(out) * 0.0 + Vector((-math.sin(a), math.cos(a), 0)) * 0.16, 3, top2, rim, cross=False)
		# щетина пятнами сверху
		for i in range(int(95 * R)):
			f = math.sqrt(rnd.random()) * 0.9
			a = rnd.random() * math.tau
			p = ring_pt(a, f) + Vector((0, 0, 0.02))
			mb.card(p, Vector((0, 0, rnd.uniform(0.05, 0.08))), Vector((math.cos(a * 3), math.sin(a * 3), 0)) * 0.14, 3, top, lerp(top2, rim, 0.5))
	bake_shade(mb, 0.5, 0.3)
	return mb

def branch_tree(mb, rnd, base, dirv, length, rad, depth, maxd, cols, tip_col, sides, fork_n=(2, 3), spread=0.55, up=0.35, flatten=1.0, segs=3, taper=0.72, tip_cards=0, seg_cards=0, card_col=None):
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
	mb.tube(pts, radii, sides, colsl, [0] * (segs + 1), cap=is_tip, flat=flatten, tip_k=0.7)
	cc = card_col or cols[1]
	if seg_cards and depth >= 1:
		for k in range(seg_cards):
			t = rnd.uniform(0.2, 1.0)
			p = pts[0] + (pts[-1] - pts[0]) * t
			sd = _perp(d) * rad * 6.0
			mb.card(p - d * rad * 2.0, d * length * 0.9, sd, 3, cc, tip_col, cross=True)
	if is_tip and tip_cards:
		for k in range(tip_cards):
			nd = (d + Vector((rnd.uniform(-.5, .5), rnd.uniform(-.5, .5), rnd.uniform(0, .5)))).normalized()
			mb.card(pts[-1] - nd * rad, nd * length * rnd.uniform(0.6, 0.9), _perp(nd) * length * 0.8, 3, cc, tip_col, cross=True)
	if not is_tip:
		k = rnd.randint(*fork_n)
		for j in range(k):
			nd = (d + Vector((rnd.uniform(-spread, spread), rnd.uniform(-spread, spread), rnd.uniform(-0.1, spread * 0.6) + up))).normalized()
			branch_tree(mb, rnd, pts[-1], nd, length * rnd.uniform(0.7, 0.9), r1, depth + 1, maxd, cols, tip_col, sides, fork_n, spread, up, flatten, segs, taper, tip_cards, seg_cards, card_col)

def fib_dome(n, el_min=0.15):
	out = []
	ga = math.pi * (3 - math.sqrt(5))
	for i in range(n):
		z = el_min + (1.0 - el_min) * (i + 0.5) / n
		r = math.sqrt(max(0.0, 1 - z * z))
		a = ga * i
		out.append(Vector((math.cos(a) * r, math.sin(a) * r, z)))
	return out

def gen_staghorn(seed):
	"""Широкий плотный холм из сотен коротких шишковатых веточек (Acropora, preview 30–33).
	Геометрия — короткие конусы-побеги из поверхности холма (3 грани, без ветвления — дёшево),
	объём и «шишки» — крестовые карточки щетины (атлас: веточки с почками) на каждом побеге."""
	rnd = random.Random(seed)
	mb = MB()
	base = hexc("#5E3A40"); mid = hexc("#A06C70"); tip = hexc("#EAC4BC")
	W = rnd.uniform(1.0, 1.15); Hh = 0.75
	for i, d in enumerate(fib_dome(440, 0.05)):
		d = (d + Vector((rnd.uniform(-.2, .2), rnd.uniform(-.2, .2), 0))).normalized()
		bump = 1.0 + 0.18 * noise.noise(d * 2.2 + Vector((seed, 0, 0)))
		hx = Vector((d.x * W * bump, d.y * W * bump, d.z * Hh * bump))
		g = (d + Vector((rnd.uniform(-.7, .7), rnd.uniform(-.7, .7), 0.5))).normalized()
		ln = rnd.uniform(0.13, 0.22)
		mb.tube([hx - g * 0.04, hx + g * ln], [0.022, 0.011], 3, [mul(mid, 0.75), tip], [0, 0], cap=True, tip_k=0.8)
	core = remesh_blob([((0, 0, 0.0), 0.9, 0.2, seed)], 0.3, "core", lambda p, n: base)
	for p in core.v:
		p.x *= W; p.y *= W
		p.z = max(0.0, p.z * Hh * 0.95)
	_join(mb, core)
	for i in range(12):   # обломки по краю
		a = rnd.random() * math.tau
		p = Vector((math.cos(a) * rnd.uniform(1.05, 1.35) * W, math.sin(a) * rnd.uniform(1.05, 1.35) * W, 0.02))
		dd = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0.3)).normalized()
		mb.tube([p, p + dd * 0.12], [0.016, 0.01], 3, [mid, tip], [0, 0], cap=True, tip_k=0.8)
	bake_shade(mb, 0.45, 0.5)
	return mb

def gen_corymbose(seed):
	rnd = random.Random(seed)
	mb = MB()
	base = grey(0.5); mid = grey(0.8); tip = grey(0.98)
	R = 0.5
	for i, d in enumerate(fib_dome(240, 0.04)):
		d = (d + Vector((rnd.uniform(-.06, .06), rnd.uniform(-.06, .06), 0))).normalized()
		start = Vector((d.x * R * 0.45, d.y * R * 0.45, R * 0.15 + d.z * R * 0.35))
		end = Vector((d.x * R, d.y * R, d.z * R * 0.8 + R * 0.08)) * rnd.uniform(0.88, 0.98)
		rad = rnd.uniform(0.022, 0.03)
		mb.tube([start, end], [rad * 1.1, rad], 4, [base, tip], [0, 0], ring_noise=0.15, seed=i, tip_k=0.7)
	core = remesh_blob([((0, 0, R * 0.15), R * 0.6, 0.2, seed)], 0.07, "core", lambda p, n: base)
	for p in core.v:
		p.z = max(p.z, 0.0)
	_join(mb, core)
	bake_shade(mb, 0.45, 0.5)
	return mb

def gen_lobed(seed, long_fingers=False):
	"""«Цветная капуста» (Pocillopora/лопастной, preview 26–29): плотный комок из множества
	коротких толстых изогнутых сплюснутых лопастей с бугристыми концами; основание не видно."""
	rnd = random.Random(seed)
	mb = MB()
	R = 0.34
	n = 150 if not long_fingers else 110
	for i, d in enumerate(fib_dome(n, 0.05)):
		d = (d + Vector((rnd.uniform(-.1, .1), rnd.uniform(-.1, .1), 0))).normalized()
		st = Vector((d.x * R * 0.78, d.y * R * 0.78, R * 0.06 + d.z * R * 0.62))
		ln = rnd.uniform(0.06, 0.09) * (1.5 if long_fingers else 1.0)
		ax = (d + Vector((0, 0, 0.25))).normalized()
		side = _perp(ax)
		bend = side * rnd.uniform(-.7, .7)
		pts = [st - ax * 0.03, st + ax * ln * 0.55 + bend * ln * 0.25, st + ax * ln + bend * ln * 0.5]
		rad = rnd.uniform(0.04, 0.052) * (0.8 if long_fingers else 1.0)
		cols = [grey(0.62), grey(0.86), grey(0.97)]
		mb.tube(pts, [rad * 0.9, rad, rad * 0.82], 5, cols, [0, 0, 0], ring_noise=0.3, seed=i, flat=0.6, tip_k=0.6)
	base = remesh_blob([((0, 0, R * 0.2), R * 0.62, 0.25, seed)], 0.05, "base", lambda p, n: grey(0.62))
	for p in base.v:
		p.z = max(p.z, 0.0)
	_join(mb, base)
	bake_shade(mb, 0.4, 0.4)
	return mb

def gen_foliose(seed, colr):
	"""Розетка-«капуста» Turbinaria (preview 81–85): спираль тонких чашевидных пластин
	с концентрическими полосами и светлой кромкой."""
	rnd = random.Random(seed)
	mb = MB()
	c0 = hexc(colr); c1 = mul(hexc(colr), 0.6); rimc = hexc("#ECE6C8")
	n = rnd.randint(9, 12)
	for t in range(n):
		a0 = t * 2.39996 + rnd.uniform(-.2, .2)
		dist = 0.05 + 0.3 * (t / n) ** 0.7
		cx = math.cos(a0) * dist * 0.5; cy = math.sin(a0) * dist * 0.5
		z = 0.02 + 0.12 * (1 - t / n)
		r = rnd.uniform(0.22, 0.34) * (0.55 + 0.7 * t / n)
		span = rnd.uniform(3.4, 5.2)
		face = a0
		RS, RR = 16, 5
		rows = []
		for k in range(RR + 1):
			f = k / RR
			row = []
			for s in range(RS + 1):
				a = face + span * (s / RS - 0.5)
				rr = r * f
				wav = 0.03 * math.sin((s / RS) * math.pi * 4 + t) * f * f
				p = Vector((cx + math.cos(a) * rr, cy + math.sin(a) * rr, z + 0.07 * f * f + wav))
				band = 0.5 + 0.5 * math.sin(f * 22.0)
				cc = lerp(lerp(c1, c0, f), mul(c0, 0.85), band * 0.4)
				if k == RR:
					cc = rimc
				row.append(mb.add_v(p, cc, (0, 0)))
			rows.append(row)
		for k in range(RR):
			for s in range(RS):
				mb.face((rows[k][s], rows[k][s + 1], rows[k + 1][s + 1], rows[k + 1][s]))
	bake_shade(mb, 0.4, 0.35)
	return mb

def gen_antler(seed, cols):
	"""Открытая ветвистая акропора-«деревце» (preview 59–64): толстый ствол, частые развилки,
	шишковатые веточки (карточки щетины вдоль ветвей)."""
	rnd = random.Random(seed)
	mb = MB()
	base = hexc(cols[0]); tip = hexc(cols[1])
	for k in range(3):
		d = Vector((rnd.uniform(-.5, .5), rnd.uniform(-.5, .5), 1))
		branch_tree(mb, rnd, Vector((rnd.uniform(-.05, .05), rnd.uniform(-.05, .05), 0)), d, 0.24, 0.04, 0, 5,
			[mul(base, 0.7), base], tip, 3, (2, 2), 0.9, 0.08, flatten=0.9, segs=1, taper=0.74, tip_cards=0, card_col=base)
	bake_shade(mb, 0.3, 0.35)
	return mb

def gen_softcoral(seed, trunk_hex, polyp_hex):
	"""Мягкий коралл Dendronephthya (preview 69–76): светлый полупрозрачный ветвистый ствол,
	на концах — пышные гроздья полипов (карточки атласа «полипы»)."""
	rnd = random.Random(seed)
	mb = MB()
	tc = hexc(trunk_hex); pc = hexc(polyp_hex); pc2 = lerp(pc, hexc("#FFFFFF"), 0.35)
	tips = []
	def grow(p, d, ln, rad, depth):
		q = p + d * ln
		mid = p + d * ln * 0.5 + Vector((rnd.uniform(-.03, .03), rnd.uniform(-.03, .03), 0.02))
		fl = min(0.9, 0.15 + max(depth, 0) * 0.18)
		mb.tube([p, mid, q], [rad, rad * 0.85, rad * 0.7], 5, [tc, tc, lerp(tc, pc, 0.2 * depth)], [fl * 0.6, fl * 0.8, fl], cap=depth >= 3)
		if depth >= 3:
			tips.append((q, d, fl))
			return
		for k in range(3 if depth < 1 else rnd.randint(2, 3)):
			nd = (d + Vector((rnd.uniform(-1.0, 1.0), rnd.uniform(-1.0, 1.0), rnd.uniform(0.0, 0.5)))).normalized()
			grow(q, nd, ln * 0.8, rad * 0.72, depth + 1)
	for k in range(3):
		a = math.tau * k / 3 + rnd.uniform(-.3, .3)
		grow(Vector((math.cos(a) * 0.04, math.sin(a) * 0.04, 0)), Vector((math.cos(a) * 0.5, math.sin(a) * 0.5, 1)).normalized(), 0.2, 0.045, 0)
	for (q, d, fl) in tips:
		for k in range(2):
			nd = (d + Vector((rnd.uniform(-.6, .6), rnd.uniform(-.6, .6), 0.3))).normalized()
			sz = rnd.uniform(0.13, 0.19)
			mb.card(q - nd * sz * 0.35, nd * sz, _perp(nd) * sz, 2, pc, pc2, flex0=fl, flex1=min(1.0, fl + 0.1))
	for i in range(len(mb.vu)):
		if mb.vu[i][1] > 0:
			mb.vu[i] = (1.0, mb.vu[i][1])
	bake_shade(mb, 0.3, 0.3)
	return mb

def gen_tentacles(mb, rnd, center_fn, n, len_rng, rad, col0, col1, sides=4, segs=3, curl=0.4, outward=0.6, flex0=0.15, tipc=None, wiggle=0.0, taper=0.55, tip_k=0.9):
	first = len(mb.v)
	for i in range(n):
		p0, nrm = center_fn(rnd)
		ln = rnd.uniform(*len_rng)
		d = (nrm + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)) * outward).normalized()
		bend = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.6, 0.1))) * curl
		side = _perp(d)
		ph = rnd.uniform(0, 6.28)
		pts = [p0]
		for s in range(1, segs + 1):
			t = s / segs
			w = side * math.sin(t * 5.0 + ph) * wiggle * ln * t
			pts.append(p0 + d * ln * t + bend * ln * t * t + w)
		radii = [rad * (1.0 - taper * (s / segs)) for s in range(segs + 1)]
		cols = [lerp(col0, col1, s / segs) for s in range(segs + 1)]
		if tipc:
			cols[-1] = tipc
		flex = [flex0 + (1.0 - flex0) * (s / segs) for s in range(segs + 1)]
		mb.tube(pts, radii, sides, cols, flex, cap=True, tip_k=tip_k)
	for i in range(first, len(mb.vu)):
		mb.vu[i] = (1.0, mb.vu[i][1])

def gen_leather(seed):
	"""Кожистый «Actinia01» (preview 42–45): волнистая чаша-блюдце с рёбрами снаружи,
	по всей верхней поверхности и кромке — густой короткий кремовый мех полипов."""
	rnd = random.Random(seed)
	mb = MB()
	cup0 = hexc("#B88A88"); cup1 = hexc("#EED6CC"); fr0 = hexc("#D8CCA0"); fr1 = hexc("#FAF6E4")
	R = 0.55; H = 0.24
	lob = rnd.randint(3, 4); ph = rnd.uniform(0, 6)
	RS, RR = 40, 6
	def cup_pt(a, f):
		er = R * (1.0 + 0.14 * math.sin(a * lob + ph)) * (0.2 + 0.8 * f)
		z = H * f ** 1.6 + 0.09 * f ** 2 * math.sin(a * lob * 2 + ph)
		return Vector((math.cos(a) * er, math.sin(a) * er, z))
	rows = []
	for k in range(RR + 1):
		f = k / RR
		row = []
		for s in range(RS):
			a = math.tau * s / RS
			p = cup_pt(a, f)
			rib = 0.5 + 0.5 * math.sin(a * 34)
			row.append(mb.add_v(p, lerp(cup0, cup1, f * 0.6 + rib * 0.25), (0, 0)))
		rows.append(row)
	bottom = mb.add_v(Vector((0, 0, 0)), mul(cup0, 0.7), (0, 0))
	for s in range(RS):
		mb.face((bottom, rows[0][(s + 1) % RS], rows[0][s]))
	for k in range(RR):
		for s in range(RS):
			s1 = (s + 1) % RS
			mb.face((rows[k][s], rows[k][s1], rows[k + 1][s1], rows[k + 1][s]))
	ctop = mb.add_v(Vector((0, 0, H * 0.8)), hexc("#C8BC88"), (0, 0))
	for s in range(RS):
		mb.face((ctop, rows[RR][s], rows[RR][(s + 1) % RS]))
	# мех: короткие толстенькие щупальца-полипы (3 грани) по всей верхней поверхности, гуще к кромке
	def where(r):
		a = r.random() * math.tau
		f = 1.0 - r.random() ** 2.2 * 0.85
		p = cup_pt(a, 1.0)
		q = Vector((p.x * f, p.y * f, H * 0.8 + (p.z - H * 0.8) * f))
		n = Vector((math.cos(a) * 0.9 * f, math.sin(a) * 0.9 * f, 1.0)).normalized()
		return q, n
	gen_tentacles(mb, rnd, where, 300, (0.06, 0.11), 0.012, fr0, fr1, sides=3, segs=1, curl=0.25, outward=0.25, taper=0.3, tip_k=1.0)
	bake_shade(mb, 0.35, 0.3)
	return mb

def gen_anemone(seed, colr):
	"""Актиния с длинными щупальцами (preview 46–48, 55–58): высокая плотная шапка волнистых
	щупалец со скруглёнными кончиками. Силуэт — 70 трубок, густота — карточки «бахромы»."""
	rnd = random.Random(seed)
	mb = MB()
	c = hexc(colr); dark = mul(c, 0.7); tipc = lerp(c, hexc("#FFFFFF"), 0.4)
	RS = 16
	center = mb.add_v(Vector((0, 0, 0.07)), dark, (0, 0))
	ring = [mb.add_v(Vector((math.cos(math.tau * s / RS) * 0.42, math.sin(math.tau * s / RS) * 0.26, 0.05)), dark, (0, 0)) for s in range(RS)]
	ring2 = [mb.add_v(Vector((math.cos(math.tau * s / RS) * 0.46, math.sin(math.tau * s / RS) * 0.3, 0.0)), mul(dark, 0.8), (0, 0)) for s in range(RS)]
	for s in range(RS):
		s1 = (s + 1) % RS
		mb.face((center, ring[s], ring[s1]))
		mb.face((ring[s], ring2[s], ring2[s1], ring[s1]))
	def where(r):
		a = r.random() * math.tau
		f = math.sqrt(r.random())
		q = Vector((math.cos(a) * 0.42 * f, math.sin(a) * 0.26 * f, 0.06))
		n = Vector((math.cos(a) * (0.1 + 0.6 * f), math.sin(a) * (0.1 + 0.5 * f), 2.4 - f * 0.9)).normalized()
		return q, n
	gen_tentacles(mb, rnd, where, 125, (0.34, 0.55), 0.026, c, tipc, sides=3, segs=3,
		curl=0.45, outward=0.2, flex0=0.1, wiggle=0.6, taper=0.2, tip_k=1.2)
	bake_shade(mb, 0.3, 0.35)
	return mb

def gen_bubble(seed):
	rnd = random.Random(seed)
	yel = hexc("#E8C030")
	sph = [((0, 0, 0.16), 0.18, 0.15, 1.0)]
	for i in range(6):
		a = math.tau * i / 6 + rnd.uniform(-.3, .3)
		sph.append(((math.cos(a) * 0.13, math.sin(a) * 0.13, rnd.uniform(0.08, 0.18)), rnd.uniform(0.1, 0.13), 0.2, i * 2.0))
	mb = remesh_blob(sph, 0.02, "bubble", lambda p, n: mul(yel, 0.8 + 0.2 * max(0.0, n.z)))
	for p in mb.v:
		if p.z < 0:
			p.z = 0.0
	zmax = max(p.z for p in mb.v)
	def where(r):
		a = r.random() * math.tau
		f = math.sqrt(r.random())
		q = Vector((math.cos(a) * 0.22 * f, math.sin(a) * 0.22 * f, zmax - 0.03 - 0.06 * f * f))
		n = Vector((math.cos(a) * f, math.sin(a) * f, 1.0)).normalized()
		return q, n
	gen_tentacles(mb, rnd, where, 200, (0.08, 0.14), 0.013, hexc("#9A9A92"), hexc("#C4C4BC"), sides=3, segs=2, curl=0.35, outward=0.35, tipc=hexc("#F6F6EE"))
	bake_shade(mb, 0.25, 0.25)
	return mb

def gen_crinoid(seed):
	"""Морская лилия (preview 53, 65–67): густой пучок дугой загнутых рук, по каждой — перистые
	пиннулы (две карточки «перо» крест-накрест вдоль руки)."""
	rnd = random.Random(seed)
	mb = MB()
	c0 = hexc("#9C8410"); c1 = hexc("#E8D838")
	arms = 44
	for i in range(arms):
		a = math.tau * i / arms + rnd.uniform(-.2, .2)
		el = rnd.uniform(1.25, 1.65)
		ln = rnd.uniform(0.45, 0.65)
		bend = rnd.uniform(1.2, 2.2)
		pts = []
		for s in range(8):
			t = s / 7
			ang = el - t * bend
			r = ln * t
			pts.append(Vector((math.cos(a) * r * math.cos(ang) * 1.1, math.sin(a) * r * math.cos(ang) * 1.1, 0.05 + r * math.sin(ang) * 0.9 + 0.14 * t)))
		flex = [0.1 + 0.9 * (s / 7) for s in range(8)]
		mb.tube(pts, [0.011, 0.01, 0.009, 0.008, 0.007, 0.005, 0.004, 0.003], 3, [lerp(c0, c1, s / 7) for s in range(8)], flex)
		for s in range(0, 7):
			p = pts[s]; q = pts[s + 1]
			d = q - p
			if d.length < 1e-4:
				continue
			side = d.normalized().cross(Vector((math.cos(a), math.sin(a), 0))).normalized()
			if side.length < 0.1:
				side = _perp(d.normalized())
			w = 0.09 * (1.0 - 0.08 * s)
			mb.card(p, d * 1.15, side * w, 1, c0, c1, flex[s], flex[s + 1], cross=True)
	for i in range(len(mb.vu)):
		if 0 < mb.vu[i][1] and mb.vu[i][0] < 0.5:
			mb.vu[i] = (1.0, mb.vu[i][1])
	return mb

def gen_mound(seed, colr):
	rnd = random.Random(seed)
	c = hexc(colr)
	sph = []
	for i in range(11):
		a = rnd.random() * math.tau; rr = rnd.uniform(0, 0.28)
		sph.append(((math.cos(a) * rr, math.sin(a) * rr, 0.0), rnd.uniform(0.1, 0.2), 0.45, i * 1.7))
	mb = remesh_blob(sph, 0.03, "mound", lambda p, n: mul(c, 0.7 + 0.35 * max(0.0, n.z) + 0.15 * noise.noise(p * 20.0)))
	for p in mb.v:
		if p.z < 0:
			p.z = 0.0
	return mb

def gen_millepora(seed):
	"""Огненный коралл (preview 77–80): широкие сплюснутые лопасти, расходятся веером в стороны и
	вверх, расширяются к светлым бугристым концам."""
	rnd = random.Random(seed)
	mb = MB()
	c0 = hexc("#9C7438"); c1 = hexc("#D0A860"); tipc = hexc("#F4ECD6")
	for k in range(rnd.randint(5, 7)):
		a = rnd.random() * math.tau
		d = Vector((math.cos(a), math.sin(a), rnd.uniform(0.6, 1.1))).normalized()
		branch_tree(mb, rnd, Vector((rnd.uniform(-.04, .04), rnd.uniform(-.04, .04), 0)), d, 0.17, 0.045, 0, 3,
			[c0, c1], tipc, 6, (2, 2), 0.9, 0.05, flatten=0.3, segs=2, taper=1.08)
	bake_shade(mb, 0.35, 0.35)
	return mb

# ------------------------------------------------------------------ сборка

SPEC = [
	# (тип, вариант, функция, бюджет геометрии LOD0, LOD1, LOD2) — карточки сверх бюджета (≈4 треуг./шт.)
	("table", 0, lambda: gen_table(11, 1), 1600, 800, 300),
	("table", 1, lambda: gen_table(12, 2), 1800, 900, 350),
	("table", 2, lambda: gen_table(13, 3), 2000, 1000, 400),
	("staghorn", 0, lambda: gen_staghorn(21), 4150, 1200, 400),
	("staghorn", 1, lambda: gen_staghorn(22), 4150, 1200, 400),
	("corymbose", 0, lambda: gen_corymbose(31), 2800, 900, 300),
	("corymbose", 1, lambda: gen_corymbose(32), 2800, 900, 300),
	("lobed", 0, lambda: gen_lobed(41), 2900, 900, 300),
	("lobed", 1, lambda: gen_lobed(42, True), 2900, 900, 300),
	("foliose", 0, lambda: gen_foliose(51, "#B8A870"), 2400, 800, 250),
	("foliose", 1, lambda: gen_foliose(52, "#C0A868"), 2400, 800, 250),
	("antler", 0, lambda: gen_antler(61, ["#A88050", "#E8D0A8"]), 1600, 600, 200),
	("antler", 1, lambda: gen_antler(62, ["#9A9A9A", "#E0E0DC"]), 1600, 600, 200),
	("softcoral", 0, lambda: gen_softcoral(71, "#EADCD8", "#E8A030"), 2400, 800, 300),
	("softcoral", 1, lambda: gen_softcoral(72, "#EAD0D0", "#E87898"), 2400, 800, 300),
	("leather", 0, lambda: gen_leather(81), 3000, 900, 300),
	("anemone", 0, lambda: gen_anemone(91, "#F2F0EA"), 3200, 1100, 400),
	("anemone", 1, lambda: gen_anemone(92, "#DCD0B0"), 3200, 1100, 400),
	("bubble", 0, lambda: gen_bubble(101), 2900, 900, 300),
	("crinoid", 0, lambda: gen_crinoid(111), 1400, 600, 250),
	("mound", 0, lambda: gen_mound(121, "#7A5A38"), 700, 250, 100),
	("mound", 1, lambda: gen_mound(122, "#6A6A3A"), 700, 250, 100),
	("millepora", 0, lambda: gen_millepora(131), 2200, 700, 200),
	("millepora", 1, lambda: gen_millepora(132), 2200, 700, 200),
]


def _cards_subset(cm, keep_every):
	"""Каждая keep_every-я карточка (у карточки 1–2 квада по 4 вершины)."""
	out = MB()
	if cm is None or keep_every <= 0:
		return out
	for fi, f in enumerate(cm.f):
		if (fi // 2) % keep_every != 0:
			continue
		ids = []
		for vi in f:
			ids.append(out.add_v(cm.v[vi], cm.vc[vi], cm.vu[vi], cm.vu2[vi]))
		out.face(tuple(ids))
	return out

def main():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	report = []
	only = os.environ.get("CORAL_ONLY", "")
	for (t, vi, fn, b0, b1, b2) in SPEC:
		if only and t not in only.split(","):
			continue
		mb = fn()
		cards = mb.cards
		ob = mb.to_object("%s_v%d_src" % (t, vi))
		src_tris = tri_count(ob)
		row = [t, vi, src_tris]
		for lod, budget, keep in ((0, b0, 1), (1, b1, 2), (2, b2, 0)):
			o = ob.copy(); o.data = ob.data.copy()
			bpy.context.scene.collection.objects.link(o)
			o = decimate_to(o, budget)
			shade_smooth(o)
			sub = _cards_subset(cards, keep)
			if sub.f:
				co = sub.to_object("cards_tmp")
				bpy.ops.object.select_all(action='DESELECT')
				o.select_set(True); co.select_set(True)
				bpy.context.view_layer.objects.active = o
				bpy.ops.object.join()
			o.name = "%s_v%d_lod%d" % (t, vi, lod)
			row.append(tri_count(o))
		bpy.data.objects.remove(ob)
		report.append(row)
		print("CORAL", *row, flush=True)
	bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "corals.glb"), export_format='GLB',
		export_colors=True, export_normals=True, export_texcoords=True, export_apply=False,
		export_materials='NONE', export_yup=True)
	with open(os.path.join(OUT, "report.tsv"), "w") as f:
		f.write("type\tvar\tsrc_tris\tlod0\tlod1\tlod2\n")
		for r in report:
			f.write("\t".join(str(x) for x in r) + "\n")

main()
