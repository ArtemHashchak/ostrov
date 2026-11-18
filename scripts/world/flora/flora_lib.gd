class_name FloraLib
extends RefCounted
## Процедурные меши и материалы растительности FLORA.
## Деревья описываются словарём параметров (variant) — по нему можно построить
## ствол целиком или любой его участок [h0, h1] (для пня и брёвен после рубки).

const TEX := "res://scenes/world/flora/tex/"
const LOG_LEN := 2.0
const RING_STEP := 0.45 # шаг колец меша ствола (общая сетка по высоте от основания)

static var _mat_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}
static var _variants: Dictionary = {}

# ---------------------------------------------------------------- материалы

static func foliage_material(tex_name: String, tint: Color = Color.WHITE, wind: float = 0.12, alpha_cut: float = 0.42) -> ShaderMaterial:
	var key := "fol_%s_%s_%.2f" % [tex_name, tint.to_html(), wind]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/world/flora/foliage.gdshader") as Shader
	m.set_shader_parameter(&"albedo_tex", load(TEX + tex_name + ".png") as Texture2D)
	m.set_shader_parameter(&"tint", tint)
	m.set_shader_parameter(&"wind_strength", wind)
	m.set_shader_parameter(&"alpha_cut", alpha_cut)
	_mat_cache[key] = m
	return m

static func bark_material(set_name: String) -> StandardMaterial3D:
	if set_name == "bark_light":
		return bark_light_material()
	var key := "bark_" + set_name
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := TerrainMaterial.pbr(set_name, 1.0)
	m.uv1_scale = Vector3.ONE
	_mat_cache[key] = m
	return m

static func end_grain_material() -> StandardMaterial3D:
	if _mat_cache.has("end_grain"):
		return _mat_cache["end_grain"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + "end_grain.png") as Texture2D
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache["end_grain"] = m
	return m

static func notch_material() -> StandardMaterial3D:
	if _mat_cache.has("notch"):
		return _mat_cache["notch"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + "end_grain.png") as Texture2D
	m.albedo_color = Color(0.86, 0.72, 0.52)
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache["notch"] = m
	return m

static func coconut_material() -> StandardMaterial3D:
	if _mat_cache.has("coconut"):
		return _mat_cache["coconut"]
	var m := StandardMaterial3D.new()
	var bark := bark_material("palm_tree_bark")
	m.albedo_texture = bark.albedo_texture
	m.albedo_color = Color(0.62, 0.52, 0.30)
	m.normal_enabled = true
	m.normal_texture = bark.normal_texture
	m.roughness = 0.75
	m.uv1_scale = Vector3(0.6, 0.6, 0.6)
	_mat_cache["coconut"] = m
	return m

static func coconut_mesh() -> Mesh:
	if _mesh_cache.has("coconut"):
		return _mesh_cache["coconut"]
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.27
	sm.radial_segments = 12
	sm.rings = 8
	sm.material = coconut_material()
	_mesh_cache["coconut"] = sm
	return sm

# ---------------------------------------------------------------- варианты деревьев

## Параметры дерева. kind: &"palm" | &"broadleaf". Детерминированы по seed.
static func variant(kind: StringName, idx: int) -> Dictionary:
	var key := "%s_%d" % [kind, idx]
	if _variants.has(key):
		return _variants[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var v := {"kind": kind, "idx": idx}
	if kind == &"palm":
		v["H"] = rng.randf_range(7.5, 12.5)
		v["r0"] = rng.randf_range(0.17, 0.22)
		v["lean"] = rng.randf_range(0.10, 0.32)        # доля высоты, на которую крона уходит вбок
		v["bend"] = rng.randf_range(-0.6, 0.6)         # второй изгиб (S-образность)
		v["fronds"] = rng.randi_range(13, 17)
		v["dead"] = rng.randi_range(2, 5)
		v["frond_len"] = rng.randf_range(3.6, 4.6)
		v["coconuts"] = rng.randi_range(3, 7)
		v["bark"] = "palm_bark"
	elif kind == &"mangrove":
		# мангр: невысокий, ствол на ходульных корнях, плотная округлая крона мелких листьев
		v["H"] = rng.randf_range(3.0, 4.2)
		v["r0"] = rng.randf_range(0.13, 0.17)
		v["lean"] = rng.randf_range(0.02, 0.14)
		v["bend"] = rng.randf_range(-0.5, 0.5)
		v["branches"] = rng.randi_range(5, 7)
		v["crown_r"] = rng.randf_range(2.4, 3.2)
		v["cards"] = rng.randi_range(70, 86)
		v["flat"] = 0.8
		v["bark"] = "bark_brown_02"
		v["tex"] = "mangrove_cluster"
		v["tint"] = Color(0.92, 1.0, 0.88)
		v["roots"] = rng.randi_range(10, 14)
		v["root_h"] = rng.randf_range(1.2, 1.7)
		v["root_r"] = rng.randf_range(1.5, 2.1)
	elif kind == &"banyan":
		# баньян: толстый короткий ствол, огромная плоская крона, воздушные корни до земли
		v["H"] = rng.randf_range(5.0, 6.5)
		v["r0"] = rng.randf_range(0.55, 0.7)
		v["lean"] = rng.randf_range(0.0, 0.04)
		v["bend"] = rng.randf_range(-0.2, 0.2)
		v["branches"] = rng.randi_range(8, 10)
		v["crown_r"] = rng.randf_range(6.0, 7.2)
		v["cards"] = rng.randi_range(150, 175)
		v["flat"] = 0.55
		v["bark"] = "bark_brown_02"
		v["tex"] = "broadleaf_cluster_b"
		v["tint"] = Color(0.82, 0.94, 0.78)
		v["aerial"] = rng.randi_range(28, 36)
		v["bark"] = "bark_light"
		v["buttress"] = rng.randi_range(6, 8)
	else:
		v["H"] = rng.randf_range(5.5, 8.0)              # высота ствола до разветвления
		v["r0"] = rng.randf_range(0.24, 0.32)
		v["lean"] = rng.randf_range(0.0, 0.08)
		v["bend"] = rng.randf_range(-0.4, 0.4)
		v["branches"] = rng.randi_range(5, 7)
		v["crown_r"] = rng.randf_range(3.2, 4.4)
		v["cards"] = rng.randi_range(78, 96)
		v["bark"] = "bark_brown_02"
		v["tex"] = "broadleaf_cluster" if idx % 2 == 0 else "broadleaf_cluster_b"
	v["seed"] = rng.randi()
	_variants[key] = v
	return v

## Точка оси ствола на высоте h (локально: основание в 0, наклон вдоль +X).
static func trunk_point(v: Dictionary, h: float) -> Vector3:
	var H: float = v["H"]
	var t := clampf(h / H, 0.0, 1.05)
	var lean: float = v["lean"]
	var bend: float = v["bend"]
	var x := pow(t, 1.7) * lean * H + sin(t * PI) * bend * 0.35
	var z := sin(t * PI * 1.3) * bend * 0.2
	return Vector3(x, t * H, z)

## Длина оси ствола от основания до высоты h (для непрерывных UV коры).
static func trunk_arc(v: Dictionary, h: float) -> float:
	if h <= 0.0:
		return 0.0
	var n := maxi(1, int(ceil(h / 0.1)))
	var acc := 0.0
	var prev := trunk_point(v, 0.0)
	for i in n:
		var c := trunk_point(v, h * float(i + 1) / float(n))
		acc += c.distance_to(prev)
		prev = c
	return acc

static func trunk_radius(v: Dictionary, h: float) -> float:
	var H: float = v["H"]
	var t := clampf(h / H, 0.0, 1.0)
	var r0: float = v["r0"]
	var r := r0 * (1.0 - 0.38 * t)
	if v["kind"] == &"palm":
		r *= 1.0 + 0.55 * exp(-h * 3.5)        # расширение у корня
		r *= 1.0 + 0.04 * sin(h * 9.0)          # кольца пальмы
	else:
		r *= 1.0 + 0.45 * exp(-h * 2.5)
	return r

## Меш участка ствола [h0, h1]. caps: 0 — без, 1 — низ, 2 — верх, 3 — оба (срез — годичные кольца).
## notch: {h, dir: Vector3 (лок. горизонталь), depth: 0..1 доли радиуса} — зарубка «как в The Forest»:
## V-образный вырез (верхняя грань наклонная, нижняя почти плоская), светлая древесина внутри.
static func trunk_mesh(v: Dictionary, h0: float, h1: float, caps: int = 0, sides: int = 12, offset: Vector3 = Vector3.ZERO, notch: Dictionary = {}) -> ArrayMesh:
	var has_notch := not notch.is_empty()
	var nh: float = notch.get("h", 0.0)
	var ndir: Vector3 = notch.get("dir", Vector3.FORWARD)
	var ndepth: float = notch.get("depth", 0.0)
	var up_band := 0.0
	var lo_band := 0.0
	if has_notch:
		sides = maxi(sides, 24)
		var rn := trunk_radius(v, nh)
		up_band = rn * (0.35 + 1.1 * ndepth)
		lo_band = rn * (0.08 + 0.25 * ndepth)
	# высоты колец: по общей сетке RING_STEP от основания дерева (у соседних кусков ствола,
	# пня и брёвен кольца совпадают — нет «скачков» профиля) + частые в полосе зарубки
	var hs: Array[float] = [h0]
	var k0 := int(floor(h0 / RING_STEP)) + 1
	while float(k0) * RING_STEP < h1 - 0.06:
		if float(k0) * RING_STEP > h0 + 0.06:
			hs.append(float(k0) * RING_STEP)
		k0 += 1
	hs.append(h1)
	if has_notch:
		var a0 := maxf(h0, nh - lo_band - 0.03)
		var a1 := minf(h1, nh + up_band + 0.03)
		var k := 0
		var hh := a0
		while hh <= a1 and k < 40:
			hs.append(hh)
			hh += 0.035
			k += 1
		hs.sort()
		var dedup: Array[float] = []
		for x in hs:
			if dedup.is_empty() or x - dedup[-1] > 0.01:
				dedup.append(x)
		hs = dedup
	var rings := hs.size()
	var pos: Array[Vector3] = []
	var nor: Array[Vector3] = []
	var uv: Array[Vector2] = []
	var cut: Array[float] = []
	# UV коры — от длины оси от основания дерева: у пня, стоящего/лежащего ствола и брёвен
	# текстура продолжается без скачка на стыке
	var v_acc := trunk_arc(v, h0)
	var prev := trunk_point(v, h0) - offset
	for i in rings:
		var h: float = hs[i]
		var c := trunk_point(v, h) - offset
		var c2 := trunk_point(v, minf(h + 0.05, (v["H"] as float) * 1.05)) - offset
		var axis := (c2 - c).normalized()
		if axis.length() < 0.5:
			axis = Vector3.UP
		var side := axis.cross(Vector3.FORWARD).normalized()
		if side.length() < 0.5:
			side = Vector3.RIGHT
		var fwd := side.cross(axis).normalized()
		var r := trunk_radius(v, h)
		if i > 0:
			v_acc += (c - prev).length()
		prev = c
		var prof := 0.0
		if has_notch:
			var dh := h - nh
			prof = 1.0 - dh / up_band if dh >= 0.0 else 1.0 + dh / lo_band
			prof = clampf(prof, 0.0, 1.0)
		for s in sides + 1:
			var a := TAU * float(s) / float(sides)
			var n := (side * cos(a) + fwd * sin(a)).normalized()
			var cut_k := 0.0
			var pp := c + n * r
			if prof > 0.0:
				# плоский срез: всё, что дальше плоскости (r·(1−depth·prof) вдоль dir), срезается на неё
				var plane := r * (1.0 - ndepth * prof)
				var ex := (pp - c).dot(ndir) - plane
				if ex > 0.0:
					pp -= ndir * ex
					cut_k = ex / r
			pos.append(pp)
			nor.append(n)
			uv.append(Vector2(float(s) / float(sides) * 2.0, v_acc / (TAU * (v["r0"] as float)) * 0.9))
			cut.append(cut_k)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood_n := 0
	for i in rings - 1:
		for s in sides:
			var a := i * (sides + 1) + s
			var b := a + sides + 1
			# по часовой стрелке снаружи — лицевая сторона в Godot (иначе ствол «вывернут»:
			# видна внутренняя дальняя стенка, освещённая со спины, — чёрная кора и «дыры» у земли)
			var quad := [a, a + 1, b, a + 1, b + 1, b]
			var in_cut := (cut[a] + cut[b] + cut[a + 1] + cut[b + 1]) > 0.03
			if in_cut:
				for q in quad:
					wood.set_uv(Vector2(pos[q].x + pos[q].z, pos[q].y) * 1.6)
					wood.add_vertex(pos[q])
				wood_n += 1
			else:
				for q in quad:
					st.set_normal(nor[q])
					st.set_color(Color(0.0, 1.0, 1.0))
					st.set_uv(uv[q])
					st.add_vertex(pos[q])
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, bark_material(v["bark"]))
	if caps != 0:
		var cs := SurfaceTool.new()
		cs.begin(Mesh.PRIMITIVE_TRIANGLES)
		if caps & 1:
			_cap(cs, v, h0, -1.0, sides, offset)
		if caps & 2:
			_cap(cs, v, h1, 1.0, sides, offset)
		cs.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, end_grain_material())
	if wood_n > 0:
		wood.generate_normals()
		wood.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, notch_material())
	return mesh

static func _cap(st: SurfaceTool, v: Dictionary, h: float, dir: float, sides: int, offset: Vector3) -> void:
	var c := trunk_point(v, h) - offset
	var c2 := trunk_point(v, h + 0.05) - offset
	var axis := (c2 - c).normalized() * dir
	var side := axis.cross(Vector3.FORWARD).normalized()
	if side.length() < 0.5:
		side = Vector3.RIGHT
	var fwd := side.cross(axis).normalized()
	var r := trunk_radius(v, h)
	for s in sides:
		var a0 := TAU * float(s) / float(sides)
		var a1 := TAU * float(s + 1) / float(sides)
		var p0 := c + (side * cos(a0) + fwd * sin(a0)) * r
		var p1 := c + (side * cos(a1) + fwd * sin(a1)) * r
		for p in [c, p0, p1] if dir > 0.0 else [c, p1, p0]:
			var d: Vector3 = (p as Vector3) - c
			st.set_normal(axis)
			st.set_uv(Vector2(0.5 + d.dot(side) / (2.0 * r) * 0.98, 0.5 + d.dot(fwd) / (2.0 * r) * 0.98))
			st.add_vertex(p)

# ---------------------------------------------------------------- кроны

## Крона в локальных координатах дерева (основание ствола в нуле).
static func crown_mesh(v: Dictionary, lod: int = 0) -> ArrayMesh:
	var key := "crown_%s_%d_%d" % [v["kind"], v["idx"], lod]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var mesh: ArrayMesh
	if v["kind"] == &"palm":
		mesh = _palm_crown(v)
	else:
		mesh = _broadleaf_crown(v, lod)
	_mesh_cache[key] = mesh
	return mesh

static func crown_center(v: Dictionary) -> Vector3:
	if v["kind"] == &"palm":
		return trunk_point(v, v["H"]) + Vector3(0, -0.4, 0)
	return trunk_point(v, v["H"]) + Vector3(0, (v["crown_r"] as float) * 0.55 * float(v.get("flat", 1.0)), 0)

static func _palm_crown(v: Dictionary) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(v["seed"]) + 17
	var top := trunk_point(v, v["H"])
	var alive := SurfaceTool.new(); alive.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dead := SurfaceTool.new(); dead.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = v["fronds"]
	var golden := 2.39996
	for i in n:
		var az := float(i) * golden + rng.randf_range(-0.2, 0.2)
		var el := lerpf(0.75, -0.15, float(i) / float(n)) + rng.randf_range(-0.12, 0.12)
		var L: float = (v["frond_len"] as float) * rng.randf_range(0.82, 1.08) * (0.75 if i < 3 else 1.0)
		_frond(alive, top, az, el, L, rng.randf_range(0.9, 1.6), rng)
	for i in int(v["dead"]):
		var az := rng.randf() * TAU
		_frond(dead, top + Vector3(0, -0.35, 0), az, rng.randf_range(-1.25, -0.85), (v["frond_len"] as float) * 0.75, 0.4, rng)
	# «капуста» на макушке
	var mesh := alive.commit()
	mesh.surface_set_material(0, foliage_material("palm_frond", Color(1, 1, 1), 0.10))
	dead.commit(mesh)
	mesh.surface_set_material(1, foliage_material("palm_frond_dead", Color(1, 1, 1), 0.04))
	return mesh

## Лист пальмы: полоса с V-изгибом вдоль поникающей дуги (треугольники без индексов).
static func _frond(st: SurfaceTool, top: Vector3, az: float, el: float, L: float, droop: float, rng: RandomNumberGenerator) -> void:
	var dir := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el)).normalized()
	var right := dir.cross(Vector3.UP).normalized()
	if right.length() < 0.3:
		right = Vector3.RIGHT
	var segs := 10
	var width := L * 0.33
	var twist := rng.randf_range(-0.25, 0.25)
	var pts: Array[Vector3] = []
	for k in segs + 1:
		var u := float(k) / float(segs)
		pts.append(top + dir * L * u + Vector3.DOWN * droop * L * 0.35 * u * u)
	var rows: Array = [] # [ [pos, normal, uv, sway] x3 ]
	for k in segs + 1:
		var u := float(k) / float(segs)
		var p: Vector3 = pts[k]
		var tang: Vector3 = (pts[mini(k + 1, segs)] - pts[maxi(k - 1, 0)]).normalized()
		var r := tang.cross(Vector3.UP).normalized()
		if r.length() < 0.3:
			r = right
		r = r.rotated(tang, twist * u)
		var up := r.cross(tang).normalized()
		if up.y < 0.0:
			up = -up
			r = -r
		var w := width * (0.35 + 0.65 * sin(clampf(u * 1.05, 0.0, 1.0) * PI * 0.92 + 0.12)) * 0.5
		var fold := w * 0.32
		var sway := clampf(u * 1.2, 0.0, 1.0)
		var nrm := (up * 0.6 + (p - top).normalized() * 0.4).normalized()
		var row: Array = []
		for side in [-1.0, 0.0, 1.0]:
			var q: Vector3 = p + r * w * float(side) + up * (fold if side == 0.0 else 0.0)
			row.append([q, nrm, Vector2(u * 0.96 + 0.02, 0.5 - float(side) * 0.5), sway])
		rows.append(row)
	for k in segs:
		for c in 2:
			var quad: Array = [rows[k][c], rows[k + 1][c], rows[k + 1][c + 1], rows[k][c + 1]]
			for idx in [0, 1, 2, 0, 2, 3]:
				var vv: Array = quad[idx]
				st.set_color(Color(vv[3], 1, 1))
				st.set_normal(vv[1])
				st.set_uv(vv[2])
				st.add_vertex(vv[0])

## Лиственная крона (broadleaf / mangrove / banyan): скелет из ветвей, грозди карточек
## на концах побегов + внутренняя тёмная «набивка», чтобы крона не просвечивала насквозь.
## lod 1 — дальний: в 4 раза меньше карточек вдвое крупнее, без веток.
static func _broadleaf_crown(v: Dictionary, lod: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(v["seed"]) + 31
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := crown_center(v)
	var R: float = v["crown_r"]
	var flat: float = v.get("flat", 1.0)
	var top := trunk_point(v, v["H"])
	var r0: float = v["r0"]
	var tint: Color = v.get("tint", Color(0.95, 1.0, 0.92))
	var limbs: Array = [] # [a, b, ra, rb]
	var twigs: Array[Vector3] = []
	var nb := int(v["branches"])
	for b in nb:
		var az := TAU * float(b) / float(nb) + rng.randf_range(-0.35, 0.35)
		var fork := top + Vector3(0, -rng.randf_range(0.3, 1.4) * minf(1.0, flat * 1.4), 0)
		var tip := center + Vector3(cos(az) * R * 0.62, rng.randf_range(-0.15, 0.45) * R * 0.6 * flat, sin(az) * R * 0.62)
		limbs.append([fork, tip, r0 * 0.5, r0 * 0.2])
		for k in 3:
			var az2 := az + rng.randf_range(-0.9, 0.9)
			var tw := tip + Vector3(cos(az2) * R * 0.32, rng.randf_range(0.05, 0.45) * R * 0.5 * flat, sin(az2) * R * 0.32)
			limbs.append([tip, tw, r0 * 0.2, r0 * 0.07])
			twigs.append(tw)
	twigs.append(center + Vector3(0, R * 0.5 * flat, 0))
	twigs.append(center + Vector3(rng.randf_range(-0.4, 0.4), R * 0.25 * flat, rng.randf_range(-0.4, 0.4)))
	var lod_k := 4 if lod > 0 else 1
	var per := maxi(3 if lod > 0 else 8, int(float(v["cards"]) * 3.2 / float(twigs.size()) / float(lod_k)))
	var size_k := 1.9 if lod > 0 else 1.0
	var crad := R * 0.27
	for tw in twigs:
		for k in per:
			var p: Vector3 = tw + Vector3(rng.randf_range(-1, 1) * crad, rng.randf_range(-0.55, 0.7) * crad * flat, rng.randf_range(-1, 1) * crad)
			var out := (p - center + Vector3(0, R * 0.25 * flat, 0)).normalized()
			out = (out + Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.2, 0.4), rng.randf_range(-0.4, 0.4))).normalized()
			_card(st, p, out, rng.randf_range(1.2, 1.9) * size_k, rng.randf() * TAU, center, 0.7)
	# внутренняя набивка: крупные карточки по эллипсоиду 0.35–0.7 R, затенённые
	var nfill := int(float(v["cards"]) * 0.55 / float(lod_k))
	for k in nfill:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1.0), rng.randf_range(-1, 1)).normalized()
		var p := center + Vector3(d.x * R, d.y * R * flat * 0.8, d.z * R) * rng.randf_range(0.3, 0.68)
		# затенение внутренней листвы — в COLOR.g (тот же материал → один draw call)
		_card(st, p, d, rng.randf_range(1.8, 2.6) * (1.4 if lod > 0 else 1.0), rng.randf() * TAU, center, 0.4, 0.6)
	var mesh := st.commit()
	mesh.surface_set_material(0, foliage_material(v["tex"], tint, 0.07))
	if lod == 0:
		var bst := SurfaceTool.new(); bst.begin(Mesh.PRIMITIVE_TRIANGLES)
		for l in limbs:
			_tube(bst, l[0], l[1], l[2], l[3], 6)
		bst.generate_tangents()
		bst.commit(mesh)
		mesh.surface_set_material(1, bark_material(v["bark"]))
	return mesh

## Карточка листвы (квад) с нормалями «наружу» от центра кроны — мягкий объёмный свет.
static func _card(st: SurfaceTool, p: Vector3, out: Vector3, size: float, roll: float, center: Vector3, sway: float, shade: float = 1.0) -> void:
	var t1 := out.cross(Vector3.UP)
	if t1.length() < 0.2:
		t1 = out.cross(Vector3.RIGHT)
	t1 = t1.normalized().rotated(out, roll)
	var t2 := out.cross(t1).normalized()
	var h := size * 0.5
	var corners := [p - t1 * h - t2 * h, p + t1 * h - t2 * h, p + t1 * h + t2 * h, p - t1 * h + t2 * h]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for idx in [0, 1, 2, 0, 2, 3]:
		var q: Vector3 = corners[idx]
		st.set_color(Color(sway * (0.6 + 0.4 * float(idx >= 2)), shade, 1))
		st.set_normal(((q - center).normalized() * 0.7 + out * 0.3).normalized())
		st.set_uv(uvs[idx])
		st.add_vertex(q)

static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, sides: int) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP).normalized()
	if side.length() < 0.3:
		side = Vector3.RIGHT
	var fwd := side.cross(axis).normalized()
	var L := a.distance_to(b)
	for s in sides:
		var a0 := TAU * float(s) / float(sides)
		var a1 := TAU * float(s + 1) / float(sides)
		var n0 := side * cos(a0) + fwd * sin(a0)
		var n1 := side * cos(a1) + fwd * sin(a1)
		var quad := [[a + n0 * r0, n0, Vector2(float(s) / sides, 0)], [b + n0 * r1, n0, Vector2(float(s) / sides, L)],
			[b + n1 * r1, n1, Vector2(float(s + 1) / sides, L)], [a + n1 * r0, n1, Vector2(float(s + 1) / sides, 0)]]
		for idx in [0, 2, 1, 0, 3, 2]: # по часовой снаружи (лицевая в Godot)
			st.set_color(Color(0, 1, 1))
			st.set_normal(quad[idx][1])
			st.set_uv(quad[idx][2])
			st.add_vertex(quad[idx][0])

# ---------------------------------------------------------------- кусты, трава

static func bush_mesh(idx: int) -> ArrayMesh:
	var key := "bush_%d" % idx
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + idx
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var R := rng.randf_range(0.7, 1.2)
	var center := Vector3(0, R * 0.55, 0)
	for k in 16:
		var a := rng.randf() * TAU
		var el := rng.randf_range(-0.1, 1.2)
		var out := Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el)).normalized()
		var p := center + out * R * rng.randf_range(0.3, 0.7)
		p.y = maxf(p.y, 0.35)
		_card(st, p, out, rng.randf_range(0.9, 1.4), rng.randf() * TAU, center, 0.5)
	var mesh := st.commit()
	mesh.surface_set_material(0, foliage_material("bush_cluster" if idx % 2 == 0 else "broadleaf_cluster", Color(0.76, 0.86, 0.72), 0.05))
	_mesh_cache[key] = mesh
	return mesh

static func grass_mesh() -> ArrayMesh:
	if _mesh_cache.has("grass"):
		return _mesh_cache["grass"]
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := PI * float(k) / 3.0
		var t := Vector3(cos(a), 0, sin(a)) * 0.45
		var h := 0.62
		var corners := [-t, t, t + Vector3(0, h, 0), -t + Vector3(0, h, 0)]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			var q: Vector3 = corners[idx]
			st.set_color(Color(q.y / h, 1, 1))
			st.set_normal(Vector3.UP.lerp(Vector3(cos(a + PI / 2), 0, sin(a + PI / 2)), 0.25).normalized())
			st.set_uv(uvs[idx])
			st.add_vertex(q)
	var mesh := st.commit()
	mesh.surface_set_material(0, foliage_material("grass_clump", Color(0.9, 0.95, 0.85), 0.10, 0.5))
	_mesh_cache["grass"] = mesh
	return mesh

## Первый меш из сцены (glb) — для MultiMesh.
static func first_mesh(scene_path: String) -> Mesh:
	if _mesh_cache.has(scene_path):
		return _mesh_cache[scene_path]
	if not ResourceLoader.exists(scene_path):
		return null
	var inst := (load(scene_path) as PackedScene).instantiate()
	var found: Mesh = null
	var stack: Array[Node] = [inst]
	while not stack.is_empty() and found == null:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			found = (n as MeshInstance3D).mesh
		for c in n.get_children():
			stack.append(c)
	inst.free()
	_mesh_cache[scene_path] = found
	return found

# ---------------------------------------------------------------- G2: корни, сборные меши, LOD

## Корни: мангр — ходульные дуги от ствола к земле; баньян — контрфорсы + воздушные корни из кроны.
## Пустой меш для пальмы/лиственного. lod 1 — меньше граней.
static func roots_mesh(v: Dictionary, lod: int = 0) -> ArrayMesh:
	var key := "roots_%s_%d_%d" % [v["kind"], v["idx"], lod]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(v["seed"]) + 77
	var sides := 6 if lod == 0 else 4
	var any := false
	if v.has("roots"):
		var n: int = v["roots"]
		var rh: float = v["root_h"]
		var rr: float = v["root_r"]
		for i in n:
			var az := TAU * float(i) / float(n) + rng.randf_range(-0.25, 0.25)
			var out := Vector3(cos(az), 0, sin(az))
			var a := trunk_point(v, rh * rng.randf_range(0.55, 1.05))
			var b := out * rr * rng.randf_range(0.7, 1.15) + Vector3(0, -0.35, 0)
			var c := a.lerp(b, 0.5) + out * rr * 0.28 + Vector3(0, rh * 0.42, 0)
			_bezier_tube(st, a, c, b, 0.075, 0.045, 6 if lod == 0 else 3, sides)
			if lod == 0 and rng.randf() < 0.55:
				# вторичный корень от середины дуги
				var m := _bez(a, c, b, 0.45)
				var az2 := az + rng.randf_range(-0.6, 0.6)
				var b2 := Vector3(cos(az2), 0, sin(az2)) * rr * rng.randf_range(1.1, 1.5) + Vector3(0, -0.35, 0)
				var c2 := m.lerp(b2, 0.5) + Vector3(0, 0.35, 0)
				_bezier_tube(st, m, c2, b2, 0.045, 0.03, 4, 5)
		any = true
	if v.has("aerial"):
		var R: float = v["crown_r"]
		var H: float = v["H"]
		for i in int(v["buttress"]):
			var az := TAU * float(i) / float(v["buttress"]) + rng.randf_range(-0.2, 0.2)
			var out := Vector3(cos(az), 0, sin(az))
			var a := trunk_point(v, rng.randf_range(0.9, 1.6)) + out * (v["r0"] as float) * 0.6
			var b := out * rng.randf_range(1.5, 2.3) + Vector3(0, -0.25, 0)
			var c := a.lerp(b, 0.5) + Vector3(0, 0.2, 0)
			_bezier_tube(st, a, c, b, 0.24, 0.07, 5 if lod == 0 else 3, sides)
		for i in int(v["aerial"]):
			var az := rng.randf() * TAU
			var d := rng.randf_range(1.4, R * 0.78)
			var top := Vector3(cos(az) * d, H + rng.randf_range(-0.2, 0.9), sin(az) * d)
			var thick := lerpf(0.13, 0.035, clampf((d - 1.4) / (R * 0.78), 0.0, 1.0)) * rng.randf_range(0.7, 1.2)
			var bot := top + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
			bot.y = -0.3 if rng.randf() < 0.7 else rng.randf_range(0.6, 2.5) # часть корней ещё не дорос до земли
			var mid := top.lerp(bot, 0.5) + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
			_bezier_tube(st, top, mid, bot, thick * 0.7, thick, 4 if lod == 0 else 2, sides if thick > 0.06 else 4)
		any = true
	var mesh := ArrayMesh.new()
	if any:
		st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_material(0, bark_light_material() if v.has("aerial") else bark_material(v["bark"]))
	_mesh_cache[key] = mesh
	return mesh

## Светлая серо-бурая кора (баньян, воздушные корни).
static func bark_light_material() -> StandardMaterial3D:
	if _mat_cache.has("bark_light"):
		return _mat_cache["bark_light"]
	var m := (TerrainMaterial.pbr("bark_brown_02", 1.0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.albedo_color = Color(1.45, 1.38, 1.25)
	m.uv1_scale = Vector3(1.0, 2.0, 1.0)
	_mat_cache["bark_light"] = m
	return m

static func _bez(a: Vector3, c: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(c, t).lerp(c.lerp(b, t), t)

static func _bezier_tube(st: SurfaceTool, a: Vector3, c: Vector3, b: Vector3, r0: float, r1: float, segs: int, sides: int) -> void:
	for k in segs:
		var t0 := float(k) / float(segs)
		var t1 := float(k + 1) / float(segs)
		_tube(st, _bez(a, c, b, t0), _bez(a, c, b, t1), lerpf(r0, r1, t0), lerpf(r0, r1, t1), sides)

## Меш дерева целиком (ствол + крона + корни [+ кокосы]) для MultiMesh: lod 0 — ближний, 1 — дальний.
## Поверхности с одинаковым материалом сливаются (меньше draw call).
static func tree_mesh(v: Dictionary, lod: int) -> ArrayMesh:
	var key := "tree_%s_%d_%d" % [v["kind"], v["idx"], lod]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var parts: Array = [] # [Mesh, Transform3D]
	parts.append([trunk_mesh(v, 0.0, (v["H"] as float) * (1.0 if v["kind"] == &"palm" else 1.02), 0, 10 if lod == 0 else 5), Transform3D.IDENTITY])
	parts.append([crown_mesh(v, lod), Transform3D.IDENTITY])
	var rm := roots_mesh(v, lod)
	if rm.get_surface_count() > 0:
		parts.append([rm, Transform3D.IDENTITY])
	if v["kind"] == &"palm" and lod == 0:
		var top := trunk_point(v, v["H"])
		var n := int(v.get("coconuts", 0))
		for i in n:
			var a := TAU * float(i) / float(maxi(n, 1))
			parts.append([coconut_mesh(), Transform3D(Basis(), top + Vector3(cos(a) * 0.22, -0.4, sin(a) * 0.22))])
	var mesh := combine(parts)
	_mesh_cache[key] = mesh
	return mesh

## Слить меши по материалам: parts = [[Mesh, Transform3D], ...].
static func combine(parts: Array) -> ArrayMesh:
	var by_mat: Dictionary = {} # Material -> SurfaceTool
	var order: Array = []
	for pr in parts:
		var m: Mesh = pr[0]
		for s in m.get_surface_count():
			var mat: Material = m.surface_get_material(s)
			if mat == null and m is PrimitiveMesh:
				mat = (m as PrimitiveMesh).material
			if not by_mat.has(mat):
				var st := SurfaceTool.new()
				by_mat[mat] = st
				order.append(mat)
			(by_mat[mat] as SurfaceTool).append_from(m, s, pr[1])
	var out := ArrayMesh.new()
	for mat in order:
		(by_mat[mat] as SurfaceTool).commit(out)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out

# ---------------------------------------------------------------- G2: узлы-ресурсы

static func plain_material(key: String, col: Color, rough: float = 0.8, tex: String = "") -> StandardMaterial3D:
	var k := "plain_" + key
	if _mat_cache.has(k):
		return _mat_cache[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if tex != "":
		m.albedo_texture = load(TEX + tex + ".png") as Texture2D
	_mat_cache[k] = m
	return m

static func _sphere(r: float, h: float, seg: int = 8) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = h
	sm.radial_segments = seg
	sm.rings = maxi(4, seg / 2)
	return sm

## Карточки «крест» вокруг вертикали (трава/травы/кукуруза): n плоскостей шириной w, высотой h.
static func _cross(st: SurfaceTool, base: Vector3, w: float, h: float, n: int, yaw: float, tilt: Vector3 = Vector3.ZERO) -> void:
	for k in n:
		var a := yaw + PI * float(k) / float(n)
		var t := Vector3(cos(a), 0, sin(a)) * w * 0.5
		var up := (Vector3.UP + tilt).normalized() * h
		var corners := [base - t, base + t, base + t + up, base - t + up]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		var nrm := Vector3(cos(a + PI / 2), 0.6, sin(a + PI / 2)).normalized()
		for idx in [0, 1, 2, 0, 2, 3]:
			var q: Vector3 = corners[idx]
			st.set_color(Color(clampf((q.y - base.y) / h, 0.0, 1.0), 1, 1))
			st.set_normal(nrm)
			st.set_uv(uvs[idx])
			st.add_vertex(q)

## Меш узла-ресурса. bare = после сбора (ягодный куст без ягод, хлопок без коробочек).
static func resource_mesh(kind: StringName, idx: int, bare: bool = false) -> ArrayMesh:
	var key := "res_%s_%d_%d" % [kind, idx, int(bare)]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s_%d" % [kind, idx])
	var parts: Array = []
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := SurfaceTool.new(); stem.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fol_tex := ""
	var fol_tint := Color(1, 1, 1)
	var stem_mat: Material = plain_material("stem", Color(0.36, 0.48, 0.22), 0.85)
	match kind:
		&"liana":
			# 2–3 плети, свисающие из кроны; верх — на высоте ~idx-зависимой
			fol_tex = "liana_strip"
			var H := 4.6 + float(idx % 3) * 0.9
			for s in 3:
				var off := Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
				var top := Vector3(rng.randf_range(-0.6, 0.6), H + rng.randf_range(-0.4, 0.4), rng.randf_range(-0.6, 0.6))
				var bot := off + Vector3(0, rng.randf_range(0.0, 0.4), 0)
				var mid := top.lerp(bot, 0.55) + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
				_bezier_tube(stem, top, mid, bot, 0.025, 0.02, 6, 4)
				var segs := 5
				for k in segs:
					var a := _bez(top, mid, bot, float(k) / segs)
					var b := _bez(top, mid, bot, float(k + 1) / segs)
					_ribbon(st, b, a, 0.55, rng.randf() * PI, float(k) / segs, float(k + 1) / segs)
			stem_mat = bark_material("bark_brown_02")
		&"herb":
			fol_tex = "herb_cluster"
			_cross(st, Vector3.ZERO, 0.75, 0.75, 3, rng.randf() * PI)
		&"wild_taro":
			fol_tex = "taro_leaf"
			var n := 5 + idx % 3
			for k in n:
				var a := TAU * float(k) / float(n) + rng.randf_range(-0.3, 0.3)
				var out := Vector3(cos(a), 0, sin(a))
				var L := rng.randf_range(0.6, 1.05)
				var tip := out * L * 0.45 + Vector3(0, L, 0)
				_tube(stem, Vector3.ZERO, tip, 0.025, 0.014, 4)
				# лист висит с конца черешка, наклонён наружу и вниз
				var size := rng.randf_range(0.7, 1.0)
				var fwd := (out + Vector3(0, 0.45, 0)).normalized()
				_leaf_plate(st, tip, fwd, size)
		&"wild_maize":
			fol_tex = "maize_blade"
			var n := 3 + idx % 3
			for k in n:
				var base := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
				var h := rng.randf_range(1.6, 2.2)
				var tilt := Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))
				_tube(stem, base, base + (Vector3.UP + tilt).normalized() * h, 0.03, 0.015, 5)
				_cross(st, base, 0.7, h * 1.02, 2, rng.randf() * PI, tilt)
				if not bare:
					var cob := base + (Vector3.UP + tilt).normalized() * h * 0.55 + Vector3(0.06, 0, 0)
					parts.append([_sphere(0.05, 0.3, 8), Transform3D(Basis(Vector3.FORWARD, -0.35), cob), plain_material("cob", Color(0.72, 0.68, 0.36), 0.7)])
					parts.append([_sphere(0.058, 0.26, 6), Transform3D(Basis(Vector3.FORWARD, -0.35), cob + Vector3(0.01, -0.03, 0)), plain_material("husk", Color(0.52, 0.6, 0.3), 0.9)])
		&"wild_melon":
			fol_tex = "melon_leaf"
			for k in 3:
				var p := Vector3(rng.randf_range(-0.5, 0.5), 0.12 + 0.04 * k, rng.randf_range(-0.5, 0.5))
				_card(st, p, Vector3(rng.randf_range(-0.25, 0.25), 1, rng.randf_range(-0.25, 0.25)).normalized(), rng.randf_range(1.1, 1.5), rng.randf() * TAU, p - Vector3(0, 1, 0), 0.25)
			if not bare:
				for k in 1 + idx % 2:
					var p := Vector3(rng.randf_range(-0.4, 0.4), 0.14, rng.randf_range(-0.4, 0.4))
					parts.append([_sphere(0.17, 0.3, 12), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, 1.0, 1.35)), p), plain_material("melon", Color(1, 1, 1), 0.55, "melon_skin")])
		&"berries":
			fol_tex = "bush_cluster"
			fol_tint = Color(0.68, 0.8, 0.62)
			var R := 0.6 + float(idx % 3) * 0.12
			var center := Vector3(0, R * 0.6, 0)
			for k in 14:
				var a := rng.randf() * TAU
				var el := rng.randf_range(-0.1, 1.2)
				var out := Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el)).normalized()
				var p := center + out * R * rng.randf_range(0.3, 0.7)
				p.y = maxf(p.y, 0.3)
				_card(st, p, out, rng.randf_range(0.8, 1.2), rng.randf() * TAU, center, 0.5)
			if not bare:
				var bm := plain_material("berry", Color(0.62, 0.06, 0.12), 0.35)
				var bs := _sphere(0.032, 0.064, 6)
				for k in 34:
					var a := rng.randf() * TAU
					var el := rng.randf_range(-0.1, 1.1)
					var out := Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el))
					var p := center + out * R * rng.randf_range(0.82, 1.0)
					p.y = maxf(p.y, 0.25)
					parts.append([bs, Transform3D(Basis(), p), bm])
		&"cotton":
			fol_tex = "bush_cluster"
			fol_tint = Color(0.86, 0.9, 0.7)
			var bm := plain_material("cotton", Color(0.96, 0.95, 0.9), 1.0)
			var bs := _sphere(0.055, 0.1, 6)
			for k in 4 + idx % 2:
				var base := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
				var top := base + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.9, 1.3), rng.randf_range(-0.3, 0.3))
				_tube(stem, base, top, 0.022, 0.01, 4)
				for j in 4:
					var p := base.lerp(top, rng.randf_range(0.35, 1.0)) + Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
					_card(st, p, Vector3(rng.randf_range(-1, 1), 0.6, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.45, 0.65), rng.randf() * TAU, base + Vector3(0, 0.6, 0), 0.4)
					if not bare:
						parts.append([bs, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, 0.8, 1.1)), p + Vector3(0, 0.08, 0)), bm])
			stem_mat = bark_material("bark_brown_02")
	var mesh := ArrayMesh.new()
	if fol_tex != "":
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, foliage_material(fol_tex, fol_tint, 0.06, 0.45))
	var sarr := stem.commit_to_arrays()
	if sarr.size() > Mesh.ARRAY_VERTEX and sarr[Mesh.ARRAY_VERTEX] is PackedVector3Array and not (sarr[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sarr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, stem_mat)
	if not parts.is_empty():
		var by_mat: Dictionary = {}
		for pr in parts:
			var mat: Material = pr[2]
			if not by_mat.has(mat):
				by_mat[mat] = SurfaceTool.new()
			(by_mat[mat] as SurfaceTool).append_from(pr[0], 0, pr[1])
		for mat in by_mat:
			(by_mat[mat] as SurfaceTool).commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	_mesh_cache[key] = mesh
	return mesh

## Лента-плеть вдоль отрезка a→b (лиана), uv.y от v0 до v1.
static func _ribbon(st: SurfaceTool, a: Vector3, b: Vector3, w: float, roll: float, v0: float, v1: float) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD).normalized().rotated(axis, roll) * w * 0.5
	var nrm := axis.cross(side).normalized()
	for pass_ in 2:
		var sd := side if pass_ == 0 else side.rotated(axis, PI * 0.5)
		var corners := [a - sd, a + sd, b + sd, b - sd]
		var uvs := [Vector2(0, 1.0 - v0), Vector2(1, 1.0 - v0), Vector2(1, 1.0 - v1), Vector2(0, 1.0 - v1)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(0.5 + 0.5 * float(idx >= 2), 1, 1))
			st.set_normal(nrm if pass_ == 0 else nrm.rotated(axis, PI * 0.5))
			st.set_uv(uvs[idx])
			st.add_vertex(corners[idx])

## Лист-пластина (таро): основание в p, «вперёд» fwd, текстура — низ у черешка.
static func _leaf_plate(st: SurfaceTool, p: Vector3, fwd: Vector3, size: float) -> void:
	var side := fwd.cross(Vector3.UP).normalized() * size * 0.5
	var f := fwd * size
	var up := side.cross(fwd).normalized()
	if up.y < 0.0:
		up = -up
	up = (up + Vector3.UP * 0.8).normalized()
	var corners := [p - side - f * 0.15, p + side - f * 0.15, p + side + f * 0.85, p - side + f * 0.85]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(Color(0.3 + 0.7 * float(idx >= 2), 1, 1))
		st.set_normal(up)
		st.set_uv(uvs[idx])
		st.add_vertex(corners[idx])
