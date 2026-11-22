class_name SeaSchool
extends Node3D
## Стая сцены моря: десятки особей одним вызовом отрисовки (MultiMesh), процессор ведёт
## каждую к её «месту в строю» вокруг центра стаи — без попарных проверок (O(N)).
## Режимы: CRUISE (стая идёт к цели), MILL (шар-карусель: «бэйтбол»), SCATTER (взрывное
## расхождение от хищника и сбор обратно), HIDE (каждая — в своё укрытие: ветви коралла,
## трава), LEAP (часть выпрыгивает из воды). Модель — из пака пользователя (подкраска tint).

enum M { CRUISE, MILL, SCATTER, HIDE, HOLD }

var sea: Object = null
var n := 20
var length := 0.16
var speed := 1.2
var mode: M = M.CRUISE
var center := Vector3.ZERO       # центр стаи (движется к goal)
var goal := Vector3.ZERO
var radius := 1.5                # размер строя
var mill_axis_speed := 1.4       # рад/с для карусели
var threat := Vector3.INF        # от кого шарахаются
var threat_r := 0.0
var hide_spots: Array = []       # Vector3 на особь (HIDE)
var hidden_ratio := 0.0          # доля «в укрытии» (для проверок)

var _mm: MultiMesh
var _mi: MultiMeshInstance3D
var _pos: PackedVector3Array
var _vel: PackedVector3Array
var _off: PackedVector3Array     # место в строю (единичная сфера/эллипсоид)
var _ph: PackedFloat32Array
var _air: PackedByteArray        # 1 — в прыжке (баллистика)
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _scatter_t := 0.0
var _len_scale := 1.0

static var _mats: Dictionary = {}

## entry — вид пака (меш с разметкой). tint — «#rrggbb».
func setup(p_sea: Object, entry: Dictionary, tint: String, count: int, p_len: float, c: Vector3, seed_i: int) -> void:
	sea = p_sea
	n = maxi(count, 1)
	length = p_len
	center = c
	goal = c
	_rng.seed = seed_i
	var mesh: Mesh = UserSeaPack.species_mesh(entry) if not entry.is_empty() else null
	if mesh == null:
		mesh = FishSchool.make_fish_mesh(p_len)
	var src_len := float(entry.get("length", p_len)) if not entry.is_empty() else p_len
	_len_scale = p_len / maxf(src_len, 0.01)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = mesh
	_mm.instance_count = n
	_mi = MultiMeshInstance3D.new()
	_mi.multimesh = _mm
	_mi.top_level = true
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.material_override = _material(entry, mesh, tint, src_len)
	add_child(_mi)
	_mi.global_transform = Transform3D.IDENTITY
	_pos.resize(n)
	_vel.resize(n)
	_off.resize(n)
	_ph.resize(n)
	_air.resize(n)
	for i in n:
		var o := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-1, 1))
		_off[i] = o
		_pos[i] = c + o * radius
		_vel[i] = Vector3.ZERO
		_ph[i] = _rng.randf()
		_air[i] = 0
	_push(0.0)

# --- стая из модели автора с запечёнными клипами (VAT) -------------------------------

const VAT_DIR := "res://assets/user_pack/sea_skel/"
## Стаи VAT: id → файлы модели автора (меш с UV2 = номер вершины, текстура смещений, описание клипов).
const VAT := {"sardine": {"mesh": "animal_fish_sardine_vat.glb", "tex": "animal_fish_sardine_vat_offsets.exr",
	"info": "animal_fish_sardine_vat_info.json", "len": 0.186}}
static var _vat_mesh: Dictionary = {}

static func vat_available(id: String) -> bool:
	return VAT.has(id) and ResourceLoader.exists(VAT_DIR + String(VAT[id]["mesh"])) \
		and ResourceLoader.exists(VAT_DIR + String(VAT[id]["tex"]))

## Меш стаи VAT с шейдерными материалами по поверхностям (тело, плавники — свои текстуры).
static func vat_mesh(id: String, tint: String) -> Mesh:
	var key := id + tint
	if _vat_mesh.has(key):
		return _vat_mesh[key]
	var v: Dictionary = VAT[id]
	var ps := load(VAT_DIR + String(v["mesh"])) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate()
	var src: Mesh = null
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		src = mi.mesh
		break
	inst.free()
	if src == null:
		return null
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(VAT_DIR + String(v["info"])))
	var rows := 83.0
	var slow := Vector2(0, 21)
	var fast := Vector2(21, 11)
	if info is Dictionary:
		rows = float((info as Dictionary).get("frames_total", rows))
		for c: Dictionary in (info as Dictionary).get("clips", []):
			if String(c.get("name", "")) == "swim":
				slow = Vector2(float(c.row_start), float(c.frames))
			elif String(c.get("name", "")) == "swim_fast":
				fast = Vector2(float(c.row_start), float(c.frames))
	var mesh := src.duplicate() as Mesh
	var tex := load(VAT_DIR + String(v["tex"])) as Texture2D
	for si in mesh.get_surface_count():
		var sm := mesh.surface_get_material(si)
		var m := ShaderMaterial.new()
		m.shader = load("res://scripts/sea/scenes/sea_school_vat.gdshader")
		m.set_shader_parameter(&"vat_tex", tex)
		m.set_shader_parameter(&"vat_h", rows)
		m.set_shader_parameter(&"clip_slow", slow)
		m.set_shader_parameter(&"clip_fast", fast)
		m.set_shader_parameter(&"tint", Color(tint))
		if sm is BaseMaterial3D:
			m.set_shader_parameter(&"albedo_tex", (sm as BaseMaterial3D).albedo_texture)
		m.set_shader_parameter(&"alpha_cut", 0.35 if si > 0 else 0.02)
		mesh.surface_set_material(si, m)
	mesh.set_meta(&"vat", id)
	_vat_mesh[key] = mesh
	return mesh

## Стая VAT: как setup, но модель — из модели автора (клипы плавания листаются в шейдере).
func setup_vat(p_sea: Object, vat_id: String, tint: String, count: int, p_len: float, c: Vector3, seed_i: int) -> void:
	setup(p_sea, {}, tint, count, p_len, c, seed_i)
	var mesh := vat_mesh(vat_id, tint)
	if mesh == null:
		return
	_mm.mesh = mesh
	_mi.material_override = null
	_len_scale = p_len / float(VAT[vat_id]["len"])
	_push(0.0)

## Стая из модели со скелетом (SeaSkel): меш автора в позе покоя, волна по телу — в шейдере стаи
## (как у моделей пака без разметки), у каждой поверхности своя текстура (тело, плавники, глаз).
static func skel_mesh(skel_id: String) -> Mesh:
	var key := "skel:" + skel_id
	if _vat_mesh.has(key):
		return _vat_mesh[key]
	var d := SeaSkel.def(skel_id)
	if d.is_empty():
		return null
	var ps := SeaSkel.scene(String(d["file"]), d)
	if ps == null:
		return null
	var inst := ps.instantiate()
	var src: Mesh = null
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		src = mi.mesh
		break
	inst.free()
	if src == null:
		return null
	var mesh := src.duplicate() as Mesh
	var L := float(d["len"])
	for si in mesh.get_surface_count():
		var sm := mesh.surface_get_material(si)
		var m := ShaderMaterial.new()
		m.shader = load("res://scripts/sea/scenes/sea_school.gdshader")
		var tex: Texture2D = (sm as BaseMaterial3D).albedo_texture if sm is BaseMaterial3D else null
		m.set_shader_parameter(&"use_tex", tex != null)
		if tex:
			m.set_shader_parameter(&"albedo_tex", tex)
		elif sm is BaseMaterial3D:
			m.set_shader_parameter(&"base_color", (sm as BaseMaterial3D).albedo_color)
		m.set_shader_parameter(&"tint", Color.WHITE)
		m.set_shader_parameter(&"body_len", L)
		m.set_shader_parameter(&"has_rig", false)
		m.set_shader_parameter(&"flash", 0.15)
		m.set_shader_parameter(&"alpha_cut", 0.35 if si > 0 else 0.02)
		mesh.surface_set_material(si, m)
	_vat_mesh[key] = mesh
	return mesh

func setup_skel(p_sea: Object, skel_id: String, count: int, p_len: float, c: Vector3, seed_i: int) -> void:
	setup(p_sea, {}, "#ffffff", count, p_len, c, seed_i)
	var mesh := skel_mesh(skel_id)
	if mesh == null:
		return
	_mm.mesh = mesh
	_mi.material_override = null
	_len_scale = p_len / float(SeaSkel.def(skel_id)["len"])
	_push(0.0)

static func _material(entry: Dictionary, mesh: Mesh, tint: String, src_len: float) -> ShaderMaterial:
	var key := String(entry.get("id", "none")) + tint
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/sea/scenes/sea_school.gdshader")
	var tex: Texture2D = null
	if mesh and mesh.get_surface_count() > 0 and mesh.surface_get_material(0) is BaseMaterial3D:
		tex = (mesh.surface_get_material(0) as BaseMaterial3D).albedo_texture
	m.set_shader_parameter(&"use_tex", tex != null)
	if tex:
		m.set_shader_parameter(&"albedo_tex", tex)
	m.set_shader_parameter(&"tint", Color(tint))
	m.set_shader_parameter(&"body_len", src_len)
	m.set_shader_parameter(&"has_rig", mesh != null and mesh.has_meta(&"rig"))
	m.set_shader_parameter(&"flash", 0.6)
	_mats[key] = m
	return m

static func clear_cache() -> void:
	_mats.clear()
	_vat_mesh.clear()

func _water() -> float:
	return float(sea.call(&"water_y")) if sea else 0.0

func _floor(x: float, z: float) -> float:
	return float(sea.call(&"floor_at", x, z)) if sea else -6.0

# --- команды ----------------------------------------------------------------------

func cruise_to(p: Vector3, spd: float = -1.0) -> void:
	mode = M.CRUISE
	goal = p
	if spd > 0.0:
		speed = spd

func mill(c: Vector3, r: float) -> void:
	mode = M.MILL
	goal = c
	radius = r

func hold_at(c: Vector3) -> void:
	mode = M.HOLD
	goal = c

## Взрывное расхождение от точки (атака хищника), потом сбор.
func scatter(from: Vector3, r: float = 4.0, t: float = 1.6) -> void:
	threat = from
	threat_r = r
	_scatter_t = t
	if mode != M.MILL:
		mode = M.SCATTER

## Каждая особь — в ближайшее укрытие из списка (ветви коралла, трава).
func hide_in(spots: Array) -> void:
	if spots.is_empty():
		return
	mode = M.HIDE
	hide_spots.resize(n)
	for i in n:
		hide_spots[i] = spots[i % spots.size()] + Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf_range(0.05, 0.35), _rng.randf_range(-0.25, 0.25))

func emerge(c: Vector3) -> void:
	mode = M.CRUISE
	goal = c

## k особей у поверхности выпрыгивают из воды.
func leap(k: int, away_from: Vector3) -> void:
	var wy := _water()
	var done := 0
	for i in n:
		if done >= k:
			break
		if _air[i] == 1 or _pos[i].y < wy - 1.5:
			continue
		var d := _pos[i] - away_from
		d.y = 0.0
		d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
		_vel[i] = d * _rng.randf_range(1.0, 2.2) + Vector3(0.0, _rng.randf_range(2.2, 3.4), 0.0)
		_pos[i].y = wy
		_air[i] = 1
		done += 1

# --- тик --------------------------------------------------------------------------

func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	_t += dt
	_scatter_t = maxf(_scatter_t - dt, 0.0)
	if mode == M.SCATTER and _scatter_t <= 0.0:
		mode = M.CRUISE
	# центр стаи плывёт к цели
	var to := goal - center
	var cs := speed if mode == M.CRUISE else speed * 0.4
	if to.length() > 0.05:
		center += to.normalized() * minf(to.length(), cs * dt)
	var wy := _water()
	var hidden := 0
	var rot := Basis(Vector3.UP, _t * mill_axis_speed)
	for i in n:
		var p := _pos[i]
		var v := _vel[i]
		if _air[i] == 1:
			v.y -= 9.8 * dt
			p += v * dt
			if p.y < wy - 0.15 and v.y < 0.0:
				_air[i] = 0
				v = Vector3(v.x, -0.5, v.z) * 0.5
			_pos[i] = p
			_vel[i] = v
			continue
		var target := center + _off[i] * radius
		match mode:
			M.MILL:
				# карусель: место в строю вращается вокруг вертикали, шар плотный
				target = goal + rot * (_off[i] * radius)
			M.HIDE:
				target = hide_spots[i] if i < hide_spots.size() else center
			M.HOLD:
				target = goal + _off[i] * radius * 0.6
		var want := target - p
		var max_v := speed * (1.6 if mode != M.HIDE else 1.2)
		var desired := want.limit_length(1.0) * max_v
		# шарахаться от угрозы (быстро)
		if threat != Vector3.INF and _scatter_t > 0.0:
			var a := p - threat
			var ad := a.length()
			if ad < threat_r:
				desired += a.normalized() * speed * 5.0 * (1.0 - ad / threat_r)
		var k := 3.0 if _scatter_t <= 0.0 else 9.0
		v = v.lerp(desired, clampf(dt * k, 0.0, 1.0))
		p += v * dt
		var fl := _floor(p.x, p.z)
		p.y = clampf(p.y, fl + length * 0.4, wy - 0.12)
		if mode == M.HIDE and want.length() < 0.35:
			hidden += 1
		_pos[i] = p
		_vel[i] = v
	hidden_ratio = float(hidden) / float(n)
	_push(dt)

func _push(dt: float) -> void:
	for i in n:
		var v := _vel[i]
		var hv := Vector3(v.x, 0.0, v.z)
		var b := Basis.IDENTITY
		var sp := v.length()
		if sp > 0.02:
			var f := v.normalized()
			b = Basis.looking_at(f, Vector3.UP if absf(f.y) < 0.95 else Vector3.FORWARD)
		var s := _len_scale
		_mm.set_instance_transform(i, Transform3D(b.scaled(Vector3.ONE * s), _pos[i]))
		var rel := sp / maxf(speed * 0.5, 0.05)
		_ph[i] = fposmod(_ph[i] + dt * (1.0 + 1.4 * rel) / sqrt(maxf(length, 0.04)), 1.0)
		var turn := clampf(hv.normalized().cross(Vector3.FORWARD).y * 0.0, -1.0, 1.0)
		var amp := clampf(0.04 + rel * 0.03, 0.03, 0.14)
		if _scatter_t > 0.0:
			turn = clampf(sin(float(i) * 1.7) * _scatter_t, -1.0, 1.0)
		_mm.set_instance_custom_data(i, Color(_ph[i], amp, turn, 0.0))
	var ext := radius * 4.0 + 10.0
	_mi.custom_aabb = AABB(center - Vector3(ext, ext, ext), Vector3(ext, ext, ext) * 2.0)

## Средняя точка особей (для проверок и камер).
func mean_pos() -> Vector3:
	var s := Vector3.ZERO
	for i in n:
		s += _pos[i]
	return s / float(maxi(n, 1))

## Средний разброс от центра (для проверок «стая разошлась»).
func spread() -> float:
	var m := mean_pos()
	var s := 0.0
	for i in n:
		s += _pos[i].distance_to(m)
	return s / float(maxi(n, 1))

func airborne() -> int:
	var c := 0
	for i in n:
		c += _air[i]
	return c
