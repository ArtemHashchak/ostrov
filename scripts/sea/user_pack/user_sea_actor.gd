class_name UserSeaActor
extends Node3D
## Особь из морского пака пользователя ВБЛИЗИ игрока: своё поведение и процедурная
## анимация модели (шейдер user_creature, состояние — instance uniform, материал общий на вид).
## Вдали те же виды рисуются группами MultiMesh (SeaLifeCells, шейдер user_species).
## Тик — от менеджера UserSeaActors (не _process), дальние тикают реже.
##   fish    — курс по кругу/к точкам, изгиб тела в поворотах, частота хвоста от скорости,
##             зависание с трепетом плавников, испуг: C-старт и рывок прочь от пловца;
##   octopus — ползёт по дну, перебирая щупальцами; замирает и скручивает кончики;
##             угроза (щупальца вверх, мигание цвета), хват щупальцами, рывок мантией
##             вперёд со щупальцами пучком и облаком чернил, потом прячется (распластан, под цвет дна);
##   squid   — висит в толще, волна по плавникам, толчки мантией, бегущие огоньки;
##             испуг — вспышка, чернила и рывок.

enum S { CRUISE, HOVER, STARTLE, CRAWL, PAUSE, THREAT, GRAB, JET, HIDE }

var kind := "fish"
var data: Dictionary = {}
var sea: Object = null
## Закреплён (экспонат полигона): менеджер не убирает по дальности.
var pinned := false
var home := Vector3.ZERO
var state: S = S.CRUISE
var speed := 0.0
var yaw := 0.0
var pitch := 0.0
var body_len := 0.3

var _mi: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var _t := 0.0                 # время в состоянии
var _goal := Vector3.ZERO
var _turn_rate := 0.0
var _swim_phase := 0.0
var _fin_phase := 0.0
var _gait := 0.0
var _jet := 0.0
var _jet_pulse := 0.0
var _flatten := 0.0
var _threat := 0.0
var _grab := 0.0
var _camo := 0.0
var _startle := 0.0
var _startle_side := 1.0
var _crawl := 0.0
var _flee_dir := Vector3.FORWARD
var _cool := 0.0
var _seed_u := 0.0              # не пугаться снова сразу

static var _materials: Dictionary = {}
static var _ink_mat: StandardMaterial3D = null

## d — запись вида (sea_species_user_sea.json); mesh — с разметкой (CUSTOM0/1).
func setup(d: Dictionary, p_sea: Object, pos: Vector3, seed_i: int) -> void:
	data = d
	sea = p_sea
	kind = String(d.get("near", _kind_of(d)))
	body_len = float(d.get("length", 0.4))
	home = pos
	position = pos
	_rng.seed = seed_i
	yaw = _rng.randf() * TAU
	_goal = pos
	_mi = MeshInstance3D.new()
	_mi.name = "Body"
	_mi.mesh = UserSeaPack.species_mesh(d)
	_mi.material_override = material_for(d)
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if body_len < 0.6 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_seed_u = _rng.randf()
	if kind == "squid":
		_mi.rotation.y = -PI * 0.5       # у модели кальмара мантия в −X → в −Z
	if kind == "octopus" and _mi.mesh:
		_mi.position.y = -_mi.mesh.get_aabb().position.y   # низ щупалец — на дне
	add_child(_mi)
	match kind:
		"octopus":
			state = S.CRAWL
			_place_on_floor()
		"squid":
			state = S.HOVER
		_:
			state = S.CRUISE
	_pick_goal()

static func _kind_of(d: Dictionary) -> String:
	var id := String(d.get("id", ""))
	if id.begins_with("octopus"):
		return "octopus"
	if id.begins_with("squid"):
		return "squid"
	return "fish"

## Общий материал вида (instance uniform — состояние каждой особи).
static func material_for(d: Dictionary) -> ShaderMaterial:
	var id := String(d.get("id", ""))
	if _materials.has(id):
		return _materials[id]
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/sea/user_pack/user_creature.gdshader")
	var k := String(d.get("near", _kind_of(d)))
	m.set_shader_parameter(&"mode", {"fish": 0, "octopus": 1, "squid": 2}.get(k, 0))
	m.set_shader_parameter(&"body_len", float(d.get("length", 0.4)))
	var mesh := UserSeaPack.species_mesh(d)
	var tex: Texture2D = null
	if mesh and mesh.get_surface_count() > 0 and mesh.surface_get_material(0) is BaseMaterial3D:
		tex = (mesh.surface_get_material(0) as BaseMaterial3D).albedo_texture
	var extra: Dictionary = d.get("params", {})
	var use_tex: bool = tex != null and bool(extra.get("use_tex", true))
	m.set_shader_parameter(&"use_tex", use_tex)
	if tex:
		m.set_shader_parameter(&"albedo_tex", tex)
	if extra.has("color_a"):
		var bc := Color(String(extra["color_a"]))
		if k == "squid":
			bc = bc * Color(0.72, 0.62, 0.86)   # вблизи — насыщеннее, свечение не «выбеливает»
		m.set_shader_parameter(&"base_color", bc)
	if extra.has("glow"):
		m.set_shader_parameter(&"glow", float(extra["glow"]) * 0.8)
	if extra.has("glow_color"):
		m.set_shader_parameter(&"glow_color", Color(String(extra["glow_color"])))
	if extra.has("tint"):
		m.set_shader_parameter(&"tint", Color(String(extra["tint"])))
	if mesh and mesh.has_meta(&"rig"):
		var rig: Dictionary = mesh.get_meta(&"rig")
		if rig.has("hub"):
			var h: Array = rig["hub"]
			m.set_shader_parameter(&"hub", Vector3(float(h[0]), float(h[1]), float(h[2])))
		if rig.has("R"):
			m.set_shader_parameter(&"arm_base", float(rig["R"]))
		if rig.has("arm_len"):
			var s := 0.0
			for x: Variant in rig["arm_len"]:
				s += float(x)
			m.set_shader_parameter(&"arm_len", s / maxf((rig["arm_len"] as Array).size(), 1))
		elif rig.has("x_max"):
			m.set_shader_parameter(&"arm_len", float(rig["x_max"]) - float(rig["x_split"]))
	_materials[id] = m
	return m

static func clear_cache() -> void:
	_materials.clear()
	_ink_mat = null

# --- окружение -------------------------------------------------------------

func _water() -> float:
	return float(sea.call(&"water_y")) if sea else 0.0

func _floor(x: float, z: float) -> float:
	return float(sea.call(&"floor_at", x, z)) if sea else -6.0

func _depth(x: float, z: float) -> float:
	return float(sea.call(&"depth_at", x, z)) if sea else 6.0

func _place_on_floor() -> void:
	position.y = _floor(position.x, position.z) + 0.02

func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

func _pick_goal() -> void:
	var r: float = clampf(float(data.get("roam", 6.0)), 2.0, 14.0)
	for i in 8:
		var a := _rng.randf() * TAU
		var g := home + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(r * 0.3, r)
		var dep := _depth(g.x, g.z)
		if dep > (0.6 if kind == "octopus" else 1.2):
			var fl := _floor(g.x, g.z)
			if kind == "octopus":
				g.y = fl
			else:
				var dr: Array = data.get("depth", [1.0, 30.0])
				var wy := _water()
				g.y = clampf(wy - _rng.randf_range(float(dr[0]) * 0.6, minf(float(dr[1]), dep) * 0.8), fl + body_len, wy - 0.4)
			_goal = g
			return
	_goal = home

## Ближайший пловец/камера (от кого пугаться).
func _threat_source(viewer: Vector3, player: Node3D) -> Vector3:
	if player and player.has_method(&"is_in_water") and bool(player.call(&"is_in_water")):
		return player.global_position + Vector3(0.0, 0.6, 0.0)
	return viewer

# --- тик -------------------------------------------------------------------

## dt — шаг; viewer — камера; player — игрок (может быть null); near — подробная анимация.
func tick(dt: float, viewer: Vector3, player: Node3D, near: bool) -> void:
	_t += dt
	_cool = maxf(_cool - dt, 0.0)
	var src := _threat_source(viewer, player)
	var dsrc := global_position.distance_to(src)
	match kind:
		"octopus":
			_tick_octopus(dt, src, dsrc)
		"squid":
			_tick_squid(dt, src, dsrc)
		_:
			_tick_fish(dt, src, dsrc)
	rotation = Vector3(pitch, yaw, 0.0)
	if near:
		_push_uniforms()

func _steer_to(dir: Vector3, want_speed: float, dt: float, turn_k: float, accel: float) -> void:
	dir.y = 0.0
	if dir.length() > 0.001:
		var dy := atan2(-dir.x, -dir.z)
		var diff := wrapf(dy - yaw, -PI, PI)
		var step := clampf(diff, -turn_k * dt, turn_k * dt)
		yaw += step
		_turn_rate = lerpf(_turn_rate, step / maxf(dt, 1e-3) / turn_k, clampf(dt * 6.0, 0.0, 1.0))
	speed = move_toward(speed, want_speed, dt * accel)

## Не выходить из воды и не зарываться в дно.
func _clamp_water(p: Vector3, margin: float) -> Vector3:
	var fl := _floor(p.x, p.z)
	p.y = clampf(p.y, fl + margin, _water() - 0.25)
	if _depth(p.x, p.z) < 0.5:
		p.x = position.x
		p.z = position.z
		yaw += PI * 0.6
	return p

func _tick_fish(dt: float, src: Vector3, dsrc: float) -> void:
	var L := body_len
	var cruise := float(data.get("speed", 0.6))
	var want := 0.0
	var dir := forward()
	match state:
		S.CRUISE:
			dir = _goal - global_position
			want = cruise
			if dir.length() < L * 3.0 or _t > 12.0:
				if _rng.randf() < 0.35:
					state = S.HOVER
					_t = 0.0
				_pick_goal()
		S.HOVER:
			# зависла: еле шевелит хвостом, трепещет плавниками, медленно разворачивается
			want = cruise * 0.06
			dir = forward().rotated(Vector3.UP, sin(_t * 0.4) * 0.6)
			if _t > _rng.randf_range(3.0, 7.0):
				state = S.CRUISE
				_t = 0.0
		S.STARTLE:
			dir = _flee_dir
			want = cruise * (4.5 if _t < 0.6 else 2.2)
			if _t > 1.6:
				state = S.CRUISE
				_t = 0.0
				_cool = 2.5
				_pick_goal()
	# испуг: пловец ближе ~2.5 м
	if state != S.STARTLE and _cool <= 0.0 and dsrc < 1.6 + L * 4.0:
		var away := global_position - src
		away.y = 0.0
		_flee_dir = away.normalized() if away.length() > 0.01 else forward()
		# в какую сторону загибаться: к направлению бегства
		var right := forward().cross(Vector3.UP)
		_startle_side = -signf(right.dot(_flee_dir) + 0.001)
		state = S.STARTLE
		_t = 0.0
	var turn_k := 2.2 if state != S.STARTLE else 9.0
	_steer_to(dir, want, dt, turn_k, 2.5 if state != S.STARTLE else 14.0)
	var p := position + forward() * speed * dt
	var dy := _goal.y - p.y if state == S.CRUISE else 0.0
	p.y += clampf(dy, -0.4, 0.4) * dt
	pitch = lerpf(pitch, clampf(dy * 0.6, -0.4, 0.4), dt * 2.0)
	position = _clamp_water(p, L * 0.6)
	# анимация: частота хвоста растёт со скоростью, размах — тоже
	var rel := speed / maxf(cruise, 0.05)
	var hz := (0.9 + 0.9 * rel) / sqrt(maxf(L, 0.05))
	_swim_phase += dt * TAU * clampf(hz, 0.4, 9.0)
	_fin_phase += dt * TAU * (2.6 if state == S.HOVER else 1.2)
	var st := 0.0
	if state == S.STARTLE and _t < 0.35:
		st = sin(_t / 0.35 * PI) * _startle_side
	_startle = lerpf(_startle, st, clampf(dt * 18.0, 0.0, 1.0))

func _tick_octopus(dt: float, src: Vector3, dsrc: float) -> void:
	var cruise := float(data.get("speed", 0.25))
	match state:
		S.CRAWL, S.PAUSE:
			if state == S.CRAWL:
				var dir := _goal - global_position
				dir.y = 0.0
				# ползёт «глазами вперёд»: модель смотрит мантией в −Z, глаза — в +Z
				_steer_to(-dir, cruise, dt, 1.2, 0.6)
				if dir.length() < 0.4 or _t > 14.0:
					state = S.PAUSE
					_t = 0.0
			else:
				speed = move_toward(speed, 0.0, dt * 0.8)
				if _t > _rng.randf_range(2.5, 5.0):
					state = S.CRAWL
					_t = 0.0
					_pick_goal()
			var p := position - forward() * speed * dt   # вперёд глазами = −forward()
			p.y = lerpf(position.y, _floor(p.x, p.z) + 0.02, clampf(dt * 6.0, 0.0, 1.0))
			if _depth(p.x, p.z) > 0.6:
				position = p
			else:
				_pick_goal()
			_crawl = lerpf(_crawl, clampf(speed / maxf(cruise, 0.05), 0.0, 1.0), dt * 3.0)
			_gait += dt * (1.2 + speed * 9.0)
			_threat = move_toward(_threat, 0.0, dt * 0.8)
			_flatten = move_toward(_flatten, 0.0, dt * 0.5)
			_camo = move_toward(_camo, 0.15, dt * 0.3)
			if _cool <= 0.0 and dsrc < 3.2:
				state = S.THREAT
				_t = 0.0
		S.THREAT:
			# поворачивается к пловцу глазами, раздувается, мигает
			speed = move_toward(speed, 0.0, dt * 2.0)
			var to := src - global_position
			_steer_to(-to, 0.0, dt, 2.5, 2.0)
			_threat = move_toward(_threat, 1.0, dt * 2.5)
			_crawl = move_toward(_crawl, 0.0, dt * 3.0)
			_camo = move_toward(_camo, 0.0, dt * 1.5)
			if dsrc < 1.8:
				state = S.GRAB
				_t = 0.0
			elif _t > 1.8:
				_start_jet(src)
			elif dsrc > 5.0:
				state = S.PAUSE
				_t = 0.0
		S.GRAB:
			_grab = move_toward(_grab, 1.0, dt * 3.0)
			if _t > 1.1:
				_start_jet(src)
		S.JET:
			# мантией вперёд: −Z модели по ходу; рывки сжатием мантии
			var pulse := fposmod(_t, 0.9) / 0.9
			_jet_pulse = maxf(1.0 - pulse * 3.0, 0.0)
			var want := 3.2 * (0.5 + _jet_pulse) * clampf(1.6 - _t * 0.5, 0.2, 1.0)
			_steer_to(_flee_dir, want, dt, 4.0, 10.0)
			_jet = move_toward(_jet, 1.0, dt * 6.0)
			_grab = move_toward(_grab, 0.0, dt * 6.0)
			_threat = move_toward(_threat, 0.0, dt * 1.5)
			var p := position + forward() * speed * dt
			var fl := _floor(p.x, p.z)
			p.y = lerpf(position.y, fl + (0.9 if _t < 1.6 else 0.05), dt * 1.5)
			position = _clamp_water(p, 0.02)
			if _t > 2.6:
				state = S.HIDE
				_t = 0.0
				home = global_position
		S.HIDE:
			speed = move_toward(speed, 0.0, dt * 2.0)
			_jet = move_toward(_jet, 0.0, dt * 2.0)
			_jet_pulse = 0.0
			position.y = lerpf(position.y, _floor(position.x, position.z) + 0.01, dt * 3.0)
			_flatten = move_toward(_flatten, 1.0, dt * 1.2)
			_camo = move_toward(_camo, 1.0, dt * 0.8)
			if _t > 7.0 and dsrc > 4.0:
				state = S.PAUSE
				_t = 0.0
				_cool = 4.0
	if state != S.JET:
		_jet = move_toward(_jet, 0.0, dt * 2.0)
		_jet_pulse = move_toward(_jet_pulse, 0.0, dt * 4.0)
	if state != S.GRAB:
		_grab = move_toward(_grab, 0.0, dt * 2.0)
	pitch = 0.0

func _start_jet(src: Vector3) -> void:
	var away := global_position - src
	away.y = 0.0
	_flee_dir = away.normalized() if away.length() > 0.01 else forward()
	state = S.JET
	_t = 0.0
	_cool = 3.0
	ink(global_position + Vector3(0.0, 0.15, 0.0), body_len)

func _tick_squid(dt: float, src: Vector3, dsrc: float) -> void:
	var cruise := float(data.get("speed", 0.6))
	match state:
		S.HOVER, S.CRUISE:
			# толчки мантией: короткий рывок, потом скольжение
			var cyc := fposmod(_t, 2.6)
			_jet_pulse = maxf(1.0 - cyc / 0.35, 0.0)
			var dir := _goal - global_position
			var want := cruise * (0.25 + _jet_pulse * 1.6)
			_steer_to(dir, want, dt, 1.0, 3.0)
			_jet = lerpf(_jet, 0.25 + _jet_pulse * 0.5, dt * 4.0)
			if dir.length() < 1.0 or _t > 16.0:
				_pick_goal()
				_t = 0.0
			if _cool <= 0.0 and dsrc < 2.6:
				_flee_dir = (global_position - src)
				_flee_dir.y = 0.0
				_flee_dir = _flee_dir.normalized() if _flee_dir.length() > 0.01 else forward()
				state = S.JET
				_t = 0.0
				_cool = 3.0
				ink(global_position, body_len * 0.8)
		S.JET:
			_jet_pulse = maxf(1.0 - fposmod(_t, 0.6) / 0.25, 0.0)
			_steer_to(_flee_dir, cruise * 5.0 * clampf(1.4 - _t * 0.5, 0.3, 1.0), dt, 5.0, 12.0)
			_jet = move_toward(_jet, 1.0, dt * 6.0)
			_threat = move_toward(_threat, 1.0 if _t < 0.8 else 0.0, dt * 4.0)
			if _t > 2.2:
				state = S.HOVER
				_t = 0.0
				home = global_position
				_pick_goal()
	if state != S.JET:
		_threat = move_toward(_threat, 0.0, dt * 2.0)
	var p := position + forward() * speed * dt
	var dy := _goal.y - p.y
	p.y += clampf(dy, -0.3, 0.3) * dt
	position = _clamp_water(p, body_len)
	pitch = lerpf(pitch, clampf(dy * 0.4, -0.3, 0.3), dt)
	_fin_phase += dt * TAU

func _push_uniforms() -> void:
	var mi := _mi
	if kind == "fish":
		var rel := clampf(speed / maxf(float(data.get("speed", 0.6)), 0.05), 0.0, 4.0)
		mi.set_instance_shader_parameter(&"fish_a", Vector4(_swim_phase, clampf(0.035 + rel * 0.03, 0.03, 0.14),
				clampf(_turn_rate, -1.0, 1.0), _startle))
		mi.set_instance_shader_parameter(&"fish_b", Vector4(_fin_phase, 0.55 if state == S.HOVER else 0.25, _seed_u, 0.0))
	else:
		mi.set_instance_shader_parameter(&"octo_a", Vector4(_gait, _crawl, _jet, _jet_pulse))
		mi.set_instance_shader_parameter(&"octo_b", Vector4(_flatten, _threat, _grab, _camo))
		mi.set_instance_shader_parameter(&"fish_b", Vector4(_fin_phase, 0.0, _seed_u, 0.0))

# --- чернила ---------------------------------------------------------------

## Облако чернил: разовые частицы (CPU — работает и в Compatibility), сами исчезают.
func ink(at: Vector3, size: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var p := CPUParticles3D.new()
	p.name = "Ink"
	p.one_shot = true
	p.emitting = false
	p.amount = 26
	p.lifetime = 2.6
	p.explosiveness = 0.85
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = size * 0.25
	p.direction = Vector3(0.0, 0.3, 0.0)
	p.spread = 180.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0.0, 0.05, 0.0)
	p.damping_min = 0.6
	p.damping_max = 1.2
	p.scale_amount_min = size * 0.9
	p.scale_amount_max = size * 2.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 1.6))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.03, 0.03, 0.05, 0.85))
	grad.set_color(1, Color(0.05, 0.06, 0.08, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _ink_material()
	p.mesh = q
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(p.lifetime + 0.5)
	tw.tween_callback(p.queue_free)

static func _ink_material() -> StandardMaterial3D:
	if _ink_mat == null:
		_ink_mat = StandardMaterial3D.new()
		_ink_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ink_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ink_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_ink_mat.vertex_color_use_as_albedo = true
		var g := GradientTexture2D.new()
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.set_color(1, Color(1, 1, 1, 0))
		g.gradient = gr
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		g.width = 64
		g.height = 64
		_ink_mat.albedo_texture = g
		_ink_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _ink_mat

# --- кукла (сцены моря) ------------------------------------------------------
## Сцены моря (SeaCritter) двигают узел сами, особь только анимируется по их скорости.
## Тело создаётся setup(); тикать её менеджеру UserSeaActors не нужно.

## Рыба: скорость (м/с), крейсерская, темп поворота −1..1, C-старт −1..1, зависла ли.
func puppet_fish(dt: float, spd: float, cruise: float, turn: float, startle_amt: float, hover: bool) -> void:
	speed = spd
	var L := body_len
	var rel := spd / maxf(cruise, 0.05)
	var hz := (0.9 + 0.9 * rel) / sqrt(maxf(L, 0.05))
	_swim_phase += dt * TAU * clampf(hz, 0.4, 9.0)
	_fin_phase += dt * TAU * (2.6 if hover else 1.2)
	_turn_rate = lerpf(_turn_rate, clampf(turn, -1.0, 1.0), clampf(dt * 6.0, 0.0, 1.0))
	_startle = lerpf(_startle, startle_amt, clampf(dt * 18.0, 0.0, 1.0))
	state = S.HOVER if hover else S.CRUISE
	_mi.set_instance_shader_parameter(&"fish_a", Vector4(_swim_phase, clampf(0.035 + rel * 0.03, 0.03, 0.14),
			_turn_rate, _startle))
	_mi.set_instance_shader_parameter(&"fish_b", Vector4(_fin_phase, 0.55 if hover else 0.25, _seed_u, 0.0))

## Осьминог: ползёт 0..1 (скорость шагов), угроза, хват, рывок, сжатие мантии, прижат, маскировка.
func puppet_octo(dt: float, spd: float, crawl_k: float, threat: float, grab: float, jet: float, flatten: float, camo: float) -> void:
	speed = spd
	_gait += dt * (1.2 + spd * 9.0)
	_crawl = lerpf(_crawl, crawl_k, clampf(dt * 3.0, 0.0, 1.0))
	_threat = move_toward(_threat, threat, dt * 2.5)
	_grab = move_toward(_grab, grab, dt * 3.0)
	_jet = move_toward(_jet, jet, dt * 6.0)
	_jet_pulse = maxf(1.0 - fposmod(_t, 0.9) / 0.3, 0.0) * jet
	_t += dt
	_flatten = move_toward(_flatten, flatten, dt * 1.2)
	_camo = move_toward(_camo, camo, dt * 0.8)
	_fin_phase += dt * TAU
	_push_uniforms()

## Чернила в точке (для сцен).
func puppet_ink() -> void:
	ink(global_position + Vector3(0.0, 0.15, 0.0), body_len)

## Принудительно (полигон/тест): перейти в состояние.
func force(s: S) -> void:
	state = s
	_t = 0.0
	if s == S.JET or s == S.STARTLE:
		_flee_dir = forward()
		if s == S.JET:
			ink(global_position + Vector3(0.0, 0.15, 0.0), body_len)
