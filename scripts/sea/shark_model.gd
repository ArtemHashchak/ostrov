class_name SharkModel
extends RefCounted
## Процедурная модель акулы: веретенообразное тело (лофт по сечениям), плавники
## (первый и второй спинной, грудные, брюшные, анальный, хвостовой гетероцеркальный),
## жаберные щели, рот, глаза. Нос смотрит в -Z (как «вперёд» в Godot).
## Цвета вершин для шейдера shark_skin: r — спина/брюхо, g — метки, b — кончик плавника.

const SKIN_SHADER := preload("res://scripts/sea/shaders/shark_skin.gdshader")

const SPECIES := {
	&"reef": {
		"name": "Рифовая акула", "length": 1.9, "girth": 0.082, "snout": 0.7,
		"back": Color(0.42, 0.45, 0.48), "belly": Color(0.88, 0.87, 0.84), "line": 0.42, "soft": 0.16,
		"stripes": 0.0, "tip_dark": 0.85, "dorsal_h": 0.12,
		"hp": 110.0, "bite": 15.0, "speed": 2.6, "burst": 6.5, "turn": 2.1, "sense": 30.0,
	},
	&"tiger": {
		"name": "Тигровая акула", "length": 3.4, "girth": 0.092, "snout": 0.35,
		"back": Color(0.43, 0.41, 0.33), "belly": Color(0.86, 0.84, 0.77), "line": 0.45, "soft": 0.2,
		"stripes": 0.55, "tip_dark": 0.0, "dorsal_h": 0.11,
		"hp": 230.0, "bite": 22.0, "speed": 2.3, "burst": 6.0, "turn": 1.55, "sense": 38.0,
	},
	&"white": {
		"name": "Большая белая акула", "length": 4.6, "girth": 0.104, "snout": 0.85,
		"back": Color(0.31, 0.34, 0.37), "belly": Color(0.94, 0.94, 0.93), "line": 0.47, "soft": 0.05,
		"stripes": 0.0, "tip_dark": 0.15, "dorsal_h": 0.135,
		"hp": 460.0, "bite": 38.0, "speed": 2.2, "burst": 7.2, "turn": 1.15, "sense": 48.0,
	},
}

static var _mesh_cache: Dictionary = {}

## Готовая модель: Node3D с телом (MeshInstance3D "Body", свой ShaderMaterial) и глазами.
static func build(species: StringName, lod: int = 0) -> Node3D:
	var cfg: Dictionary = SPECIES[species]
	var L: float = cfg["length"]
	var root := Node3D.new()
	root.name = "SharkModel"
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _get_mesh(species, lod)
	var mat := ShaderMaterial.new()
	mat.shader = SKIN_SHADER
	mat.set_shader_parameter(&"back_color", cfg["back"])
	mat.set_shader_parameter(&"belly_color", cfg["belly"])
	mat.set_shader_parameter(&"line_height", cfg["line"])
	mat.set_shader_parameter(&"line_softness", cfg["soft"])
	mat.set_shader_parameter(&"stripes", cfg["stripes"])
	mat.set_shader_parameter(&"tip_dark", cfg["tip_dark"])
	mat.set_shader_parameter(&"body_length", L)
	body.material_override = mat
	root.add_child(body)
	# Глаза — маленькие чёрные блестящие сферы.
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.02, 0.02, 0.025)
	eye_mat.roughness = 0.08
	eye_mat.metallic_specular = 0.9
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = L * 0.011
	eye_mesh.height = L * 0.022
	eye_mesh.radial_segments = 10
	eye_mesh.rings = 6
	var et := 0.075
	var ew := _half_width(et, cfg) * 0.86
	var eh := _half_height(et, cfg)
	for s in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		e.mesh = eye_mesh
		e.material_override = eye_mat
		e.position = Vector3(s * ew, _center_y(et, L) + eh * 0.32, _z_of(et, L))
		root.add_child(e)
	return root

static func _get_mesh(species: StringName, lod: int) -> ArrayMesh:
	var key := "%s_%d" % [species, lod]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m := _make_mesh(SPECIES[species], lod)
	_mesh_cache[key] = m
	return m

# ---------------- профиль тела ----------------
static func _z_of(t: float, L: float) -> float:
	return -L * 0.5 + t * L * 0.9  # тело занимает 90% длины, остальное — хвост

static func _shape(t: float, cfg: Dictionary) -> float:
	var snout: float = cfg["snout"]
	if t < 0.3:
		var u := t / 0.3
		return maxf(pow(sin(u * PI * 0.5), lerpf(0.7, 1.05, snout)), 0.03)
	var v := (t - 0.3) / 0.7
	return maxf(pow(cos(v * PI * 0.5), 1.15), 0.06)

static func _half_width(t: float, cfg: Dictionary) -> float:
	var L: float = cfg["length"]
	return L * float(cfg["girth"]) * _shape(t, cfg) * lerpf(1.08, 0.86, clampf(t * 1.6, 0.0, 1.0))

static func _half_height(t: float, cfg: Dictionary) -> float:
	var L: float = cfg["length"]
	var flat_snout := lerpf(0.8, 1.0, smoothstep(0.0, 0.25, t))
	return L * float(cfg["girth"]) * _shape(t, cfg) * 1.0 * flat_snout

static func _center_y(t: float, L: float) -> float:
	return L * 0.012 * sin(t * PI) + L * 0.01 * pow(1.0 - t, 6.0)

static func _top_y(t: float, cfg: Dictionary) -> float:
	return _center_y(t, cfg["length"]) + _half_height(t, cfg)

static func _bottom_y(t: float, cfg: Dictionary) -> float:
	return _center_y(t, cfg["length"]) - _half_height(t, cfg) * 0.86

# ---------------- построение ----------------
static func _make_mesh(cfg: Dictionary, lod: int) -> ArrayMesh:
	var L: float = cfg["length"]
	var rings := 34 if lod == 0 else 14
	var segs := 22 if lod == 0 else 10
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# --- тело (лофт) ---
	var base := 0
	for i in rings + 1:
		var t := float(i) / rings
		var z := _z_of(t, L)
		var hw := _half_width(t, cfg)
		var hh := _half_height(t, cfg)
		var cy := _center_y(t, L)
		if i == 0:
			hw = L * 0.004
			hh = L * 0.004
		for j in segs:
			var a := TAU * float(j) / segs - PI * 0.5   # -90° — брюхо
			var sy := sin(a)
			var y := cy + hh * sy * (0.86 if sy < 0.0 else 1.0)
			var x := hw * cos(a)
			# лёгкая «квадратность» брюха как у настоящих акул
			if sy < -0.2:
				x *= 1.04
			var dorsal := clampf(0.5 + 0.5 * sy, 0.0, 1.0)
			st.set_color(Color(dorsal, 1.0, 0.0))
			st.set_uv(Vector2(float(j) / segs, t))
			st.add_vertex(Vector3(x, y, z))
	for i in rings:
		for j in segs:
			var a0 := base + i * segs + j
			var a1 := base + i * segs + (j + 1) % segs
			var b0 := base + (i + 1) * segs + j
			var b1 := base + (i + 1) * segs + (j + 1) % segs
			st.add_index(a0); st.add_index(b0); st.add_index(a1)
			st.add_index(a1); st.add_index(b0); st.add_index(b1)
	var vcount := (rings + 1) * segs
	# --- плавники ---
	var verts := [vcount]
	var dh: float = cfg["dorsal_h"]
	# первый спинной
	var tf := 0.36
	var tb := 0.53
	_fin(st, verts, [
		Vector3(0, _top_y((tf + tb) * 0.5, cfg) - L * 0.01, _z_of((tf + tb) * 0.5, L)),
		Vector3(0, _top_y(tf, cfg) - L * 0.004, _z_of(tf, L)),
		Vector3(0, _top_y(tf, cfg) + L * dh * 0.65, _z_of(tf, L) + L * 0.06),
		Vector3(0, _top_y(tf, cfg) + L * dh, _z_of(tf, L) + L * 0.115),
		Vector3(0, _top_y(tb, cfg) + L * dh * 0.25, _z_of(tb, L) - L * 0.005),
		Vector3(0, _top_y(tb, cfg) - L * 0.004, _z_of(tb, L)),
	], Vector3.RIGHT, L * 0.009, 1.0, [3])
	# второй спинной
	_fin(st, verts, [
		Vector3(0, _top_y(0.79, cfg) - L * 0.003, _z_of(0.79, L)),
		Vector3(0, _top_y(0.76, cfg) - L * 0.002, _z_of(0.76, L)),
		Vector3(0, _top_y(0.77, cfg) + L * 0.035, _z_of(0.785, L)),
		Vector3(0, _top_y(0.82, cfg) - L * 0.002, _z_of(0.82, L)),
	], Vector3.RIGHT, L * 0.004, 1.0, [2])
	# анальный (снизу)
	_fin(st, verts, [
		Vector3(0, _bottom_y(0.8, cfg) + L * 0.003, _z_of(0.8, L)),
		Vector3(0, _bottom_y(0.77, cfg) + L * 0.002, _z_of(0.77, L)),
		Vector3(0, _bottom_y(0.79, cfg) - L * 0.03, _z_of(0.8, L)),
		Vector3(0, _bottom_y(0.83, cfg) + L * 0.002, _z_of(0.83, L)),
	], Vector3.RIGHT, L * 0.004, 0.35, [2])
	for s in [-1.0, 1.0]:
		# грудные — широкие «крылья», вниз-назад
		var tp := 0.24
		var root_y := _center_y(tp, L) - _half_height(tp, cfg) * 0.35
		var rw := _half_width(tp, cfg) * 0.9
		_fin(st, verts, [
			Vector3(s * rw, root_y, _z_of(tp + 0.04, L)),
			Vector3(s * rw, root_y + L * 0.004, _z_of(tp, L)),
			Vector3(s * (rw + L * 0.15), root_y - L * 0.06, _z_of(tp, L) + L * 0.11),
			Vector3(s * (rw + L * 0.19), root_y - L * 0.085, _z_of(tp, L) + L * 0.15),
			Vector3(s * (rw + L * 0.05), root_y - L * 0.02, _z_of(tp + 0.1, L)),
			Vector3(s * rw, root_y, _z_of(tp + 0.1, L)),
		], Vector3(-s * 0.35, 1.0, 0.0).normalized(), L * 0.006, 0.8, [3])
		# брюшные — маленькие
		var tv := 0.63
		var vy := _bottom_y(tv, cfg) + L * 0.006
		var vw := _half_width(tv, cfg) * 0.55
		_fin(st, verts, [
			Vector3(s * vw, vy, _z_of(tv + 0.02, L)),
			Vector3(s * vw, vy, _z_of(tv, L)),
			Vector3(s * (vw + L * 0.04), vy - L * 0.025, _z_of(tv, L) + L * 0.05),
			Vector3(s * vw, vy, _z_of(tv + 0.06, L)),
		], Vector3(-s * 0.5, 1.0, 0.0).normalized(), L * 0.004, 0.4, [2])
	# хвостовой: верхняя лопасть длиннее (гетероцеркальный)
	var tz := _z_of(0.985, L)
	var ty := _center_y(0.985, L)
	_fin(st, verts, [
		Vector3(0, ty, tz - L * 0.02),
		Vector3(0, ty + _half_height(0.96, cfg) * 0.8, _z_of(0.95, L)),
		Vector3(0, ty + L * 0.11, tz + L * 0.035),
		Vector3(0, ty + L * 0.205, tz + L * 0.085),
		Vector3(0, ty + L * 0.13, tz + L * 0.075),
		Vector3(0, ty + L * 0.015, tz + L * 0.04),
		Vector3(0, ty - L * 0.09, tz + L * 0.06),
		Vector3(0, ty - L * 0.12, tz + L * 0.05),
		Vector3(0, ty - _half_height(0.96, cfg) * 0.8, _z_of(0.95, L)),
	], Vector3.RIGHT, L * 0.006, 0.9, [3, 7])
	# --- жаберные щели (5 тёмных полосок с каждой стороны) ---
	for s in [-1.0, 1.0]:
		for k in 5:
			var t := 0.2 + k * 0.022
			var hw := _half_width(t, cfg) * 1.004 + L * 0.0015
			var cy := _center_y(t, L)
			var hh := _half_height(t, cfg)
			var y0 := cy - hh * 0.35
			var y1 := cy + hh * (0.32 - k * 0.02)
			var z := _z_of(t, L)
			var wz := L * 0.0018
			_quad(st, verts,
				Vector3(s * hw, y0, z - wz), Vector3(s * hw, y1, z - wz + L * 0.004),
				Vector3(s * hw, y1, z + wz + L * 0.004), Vector3(s * hw, y0, z + wz),
				Color(0.5, 0.62, 0.0), Vector3(s, 0, 0))
	# --- рот (тёмный серп снизу у носа) ---
	var mt0 := 0.085
	var mt1 := 0.13
	var my := _bottom_y(0.11, cfg) - L * 0.0015
	var mw := _half_width(0.12, cfg) * 0.72
	_quad(st, verts,
		Vector3(-mw, my + L * 0.006, _z_of(mt1, L)), Vector3(-mw * 0.4, my, _z_of(mt0, L)),
		Vector3(mw * 0.4, my, _z_of(mt0, L)), Vector3(mw, my + L * 0.006, _z_of(mt1, L)),
		Color(0.2, 0.3, 0.0), Vector3.DOWN)
	st.generate_normals()
	return st.commit()

## Плавник как толстый двусторонний «веер» из первой точки. tips — индексы точек-кончиков.
static func _fin(st: SurfaceTool, verts: Array, pts: Array, n: Vector3, thick: float, dorsal: float, tips: Array) -> void:
	var start: int = verts[0]
	var cnt := pts.size()
	var off := n.normalized() * thick * 0.5
	for side in 2:
		var sgn := 1.0 if side == 0 else -1.0
		for i in cnt:
			var p: Vector3 = pts[i]
			# толщина спадает к кончикам
			var k := 0.15 if tips.has(i) else 1.0
			var b := 1.0 if tips.has(i) else 0.0
			st.set_color(Color(dorsal if side == 0 else dorsal * 0.85, 1.0, b))
			st.set_uv(Vector2(0, 0))
			st.add_vertex(p + off * sgn * k)
	for i in range(1, cnt - 1):
		# сторона A
		st.add_index(start); st.add_index(start + i); st.add_index(start + i + 1)
		# сторона B (обратный порядок)
		st.add_index(start + cnt); st.add_index(start + cnt + i + 1); st.add_index(start + cnt + i)
	# кромка
	for i in cnt:
		var a := start + i
		var b2 := start + (i + 1) % cnt
		st.add_index(a); st.add_index(b2); st.add_index(a + cnt)
		st.add_index(b2); st.add_index(b2 + cnt); st.add_index(a + cnt)
	verts[0] = start + cnt * 2

static func _quad(st: SurfaceTool, verts: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, n: Vector3) -> void:
	var start: int = verts[0]
	# две стороны с отдельными вершинами (чтобы нормали не гасили друг друга)
	for side in 2:
		for p in [a, b, c, d]:
			st.set_color(col)
			st.set_uv(Vector2.ZERO)
			st.add_vertex(p + n * (0.0005 if side == 0 else -0.0005))
	st.add_index(start); st.add_index(start + 1); st.add_index(start + 2)
	st.add_index(start); st.add_index(start + 2); st.add_index(start + 3)
	st.add_index(start + 4); st.add_index(start + 6); st.add_index(start + 5)
	st.add_index(start + 4); st.add_index(start + 7); st.add_index(start + 6)
	verts[0] = start + 8
