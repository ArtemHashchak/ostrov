class_name SeaCritter
extends Node3D
## Существо сцены моря: тело (модель пака-«кукла» UserSeaActor или силуэт-дублёр SeaProxyMeshes)
## и рулёжка, которой командует сцена (SeaScene). Анимация тела — от скорости и поворота.
## Команды: goto / hold / orbit / flee / follow / wander / drift / crawl_to / surface_at;
## startle — C-старт; ballistic — прыжок из воды по дуге.
## Тик даёт сцена (не _process): дешёвые сцены тикают реже вдали.

enum M { HOLD, GOTO, ORBIT, FLEE, FOLLOW, WANDER, DRIFT, CRAWL, BALLISTIC }

var sp: Dictionary = {}          # запись вида (OceanRoster)
var sea: Object = null           # water_y / floor_at / depth_at
var length := 0.3
var cruise := 0.6
var max_speed := 2.0
var turn_k := 2.4                # рад/с
var accel := 2.5
var bottom := false              # ходит по дну (осьминог, звезда, ёж, скат лёжа)
var mode: M = M.HOLD
var goal := Vector3.ZERO
var face_dir := Vector3.ZERO
var want_speed := 0.0
var orbit_c := Vector3.ZERO
var orbit_r := 3.0
var orbit_dir := 1.0
var follow_node: Node3D = null
var follow_off := Vector3.ZERO
var flee_from := Vector3.ZERO
var drift_v := Vector3.ZERO
var wander_c := Vector3.ZERO
var wander_r := 3.0
var min_above_floor := 0.25
var max_below_surface := 0.3     # не выше воды−… (кроме прыжка)
var speed := 0.0
var vel := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var roll := 0.0
var hidden_k := 0.0              # 0 виден … 1 скрыт (спрятался в коралл — уменьшается)
var octo := {"crawl": 0.0, "threat": 0.0, "grab": 0.0, "jet": 0.0, "flatten": 0.0, "camo": 0.0}

var body: Node3D = null          # UserSeaActor или MeshInstance3D
var actor: UserSeaActor = null
var proxy_mi: MeshInstance3D = null
var proxy_kind := ""
var _turn := 0.0
var _startle := 0.0
var _startle_t := 0.0
var _phase := 0.0
var _rng := RandomNumberGenerator.new()
var _wander_t := 0.0
var _scale := 1.0

static var _proxy_mats: Dictionary = {}

## Создать существо вида sp (OceanRoster.species) в точке pos. Возвращает null, если вид
## представлен не моделью (краб/акула/стая/птица — у сцен для них свои помощники).
static func make(p_sp: Dictionary, p_sea: Object, pos: Vector3, seed_i: int) -> SeaCritter:
	var vis := OceanRoster.visual(p_sp)
	var k := String(vis.get("kind", ""))
	if k != "pack" and k != "proxy":
		return null
	var c := SeaCritter.new()
	c._setup(p_sp, vis, p_sea, pos, seed_i)
	return c

func _setup(p_sp: Dictionary, vis: Dictionary, p_sea: Object, pos: Vector3, seed_i: int) -> void:
	sp = p_sp
	sea = p_sea
	name = String(sp.get("id", "critter"))
	_rng.seed = seed_i
	length = float(sp.get("length", 0.3))
	cruise = float(sp.get("speed", 0.6))
	max_speed = maxf(cruise * 4.5, 0.6)
	turn_k = clampf(2.8 / sqrt(maxf(length, 0.05)), 0.5, 7.0)
	accel = clampf(cruise * 3.0, 0.6, 8.0)
	position = pos
	goal = pos
	wander_c = pos
	yaw = _rng.randf() * TAU
	_phase = _rng.randf() * TAU
	var g := String(sp.get("group", ""))
	if String(vis.kind) == "pack":
		var e: Dictionary = vis.entry
		actor = UserSeaActor.new()
		actor.setup(e, sea, Vector3.ZERO, seed_i)
		actor.position = Vector3.ZERO
		actor.pinned = true
		add_child(actor)
		body = actor
		var src := float(vis.get("src_len", e.get("length", length)))
		_scale = float(vis.get("len", length)) / maxf(src, 0.01)
		var st := float(vis.get("stretch", 1.0))
		actor.scale = Vector3(_scale / sqrt(st), _scale / sqrt(st), _scale * st)
		if actor.kind == "octopus":
			bottom = true
			actor.rotation.y = PI   # глаза (+Z модели) — по ходу существа
	else:
		proxy_kind = String(vis.get("proxy", "fish"))
		proxy_mi = MeshInstance3D.new()
		proxy_mi.mesh = SeaProxyMeshes.get_mesh(proxy_kind, vis.get("colors", []))
		proxy_mi.material_override = _proxy_material(proxy_kind)
		proxy_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(proxy_mi)
		body = proxy_mi
		var aabb := proxy_mi.mesh.get_aabb() if proxy_mi.mesh else AABB(Vector3.ZERO, Vector3.ONE)
		var long := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		_scale = length / maxf(long, 0.01)
		proxy_mi.scale = Vector3.ONE * _scale
		if proxy_kind in ["star", "urchin", "shrimp"] or g == "echinoderm":
			bottom = true
	if g == "ray":
		min_above_floor = 0.15
	if bottom:
		min_above_floor = 0.0
	if g == "mammal" or g == "turtle":
		max_below_surface = 0.15

static func _proxy_material(kind: String) -> ShaderMaterial:
	if _proxy_mats.has(kind):
		return _proxy_mats[kind]
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/sea/scenes/sea_proxy.gdshader")
	var mode: int = {"fish": 0, "eel": 1, "ray": 2, "jelly": 3, "turtle": 4, "star": 7, "urchin": 7, "seahorse": 0, "shrimp": 8}.get(kind, 5)
	m.set_shader_parameter(&"mode", mode)
	m.set_shader_parameter(&"rough", 0.35 if kind in ["eel", "ray", "jelly"] else 0.65)
	_proxy_mats[kind] = m
	return m

static func clear_cache() -> void:
	_proxy_mats.clear()

# --- окружение -----------------------------------------------------------------

func water_y() -> float:
	return float(sea.call(&"water_y")) if sea else 0.0

func floor_y(x: float, z: float) -> float:
	return float(sea.call(&"floor_at", x, z)) if sea else -5.0

func forward() -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))

# --- команды -------------------------------------------------------------------

func goto(p: Vector3, spd: float = -1.0) -> void:
	mode = M.GOTO
	goal = p
	want_speed = cruise if spd < 0.0 else spd

func hold(p: Vector3, face: Vector3 = Vector3.ZERO) -> void:
	mode = M.HOLD
	goal = p
	face_dir = face
	want_speed = 0.0

func orbit(c: Vector3, r: float, dir: float = 1.0, spd: float = -1.0) -> void:
	mode = M.ORBIT
	orbit_c = c
	orbit_r = r
	orbit_dir = dir
	want_speed = cruise if spd < 0.0 else spd

func flee(from: Vector3, mult: float = 3.0) -> void:
	mode = M.FLEE
	flee_from = from
	want_speed = cruise * mult
	startle(from)

func follow(n: Node3D, off: Vector3, spd_mult: float = 1.6) -> void:
	mode = M.FOLLOW
	follow_node = n
	follow_off = off
	want_speed = cruise * spd_mult

func wander(c: Vector3, r: float, spd: float = -1.0) -> void:
	mode = M.WANDER
	wander_c = c
	wander_r = r
	want_speed = cruise if spd < 0.0 else spd
	_wander_t = 0.0
	_pick_wander()

func drift(v: Vector3) -> void:
	mode = M.DRIFT
	drift_v = v

## Прыжок из воды по дуге (дельфин, мальки, кит): скорость v.
func leap(v: Vector3) -> void:
	mode = M.BALLISTIC
	vel = v

## C-старт: рывок с изгибом тела прочь от точки.
func startle(from: Vector3) -> void:
	var away := global_position - from
	away.y = 0.0
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	_startle = -signf(right.dot(away) + 0.001)
	_startle_t = 0.35

func _pick_wander() -> void:
	for i in 6:
		var a := _rng.randf() * TAU
		var p := wander_c + Vector3(cos(a), _rng.randf_range(-0.4, 0.4), sin(a)) * _rng.randf_range(wander_r * 0.3, wander_r)
		if water_y() - floor_y(p.x, p.z) > 0.3:
			goal = p
			return
	goal = wander_c

# --- тик ------------------------------------------------------------------------

func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	var p := global_position
	var desired := Vector3.ZERO
	var spd := want_speed
	match mode:
		M.HOLD:
			var to := goal - p
			desired = to
			spd = clampf(to.length() * 1.2, 0.0, cruise)
		M.GOTO:
			var to := goal - p
			desired = to
			spd = want_speed * clampf(to.length() / maxf(length * 2.0, 0.3), 0.15, 1.0)
		M.ORBIT:
			var rel := p - orbit_c
			rel.y = 0.0
			var d := rel.length()
			var tang := Vector3(-rel.z, 0.0, rel.x).normalized() * orbit_dir if d > 0.01 else forward()
			var radial := -rel.normalized() * clampf((d - orbit_r) * 0.6, -1.0, 1.0) if d > 0.01 else Vector3.ZERO
			desired = tang + radial
			desired.y = (orbit_c.y - p.y) * 0.5
		M.FLEE:
			desired = p - flee_from
			desired.y = clampf(desired.y, -0.3, 0.3)
		M.FOLLOW:
			if is_instance_valid(follow_node):
				desired = (follow_node.global_position + follow_off) - p
				spd = want_speed * clampf(desired.length() / 1.5, 0.0, 1.4)
		M.WANDER:
			desired = goal - p
			_wander_t += dt
			if desired.length() < maxf(length * 2.0, 0.4) or _wander_t > 12.0:
				_wander_t = 0.0
				_pick_wander()
		M.DRIFT:
			p += drift_v * dt
			global_position = _clamp(p)
			speed = drift_v.length()
			_anim(dt)
			return
		M.BALLISTIC:
			vel.y -= 9.8 * dt
			p += vel * dt
			var wy := water_y()
			pitch = atan2(vel.y, Vector2(vel.x, vel.z).length())
			yaw = atan2(-vel.x, -vel.z)
			global_position = p
			speed = vel.length()
			if vel.y < 0.0 and p.y < wy - length * 0.3:
				mode = M.GOTO
				goal = p + Vector3(vel.x, -1.0, vel.z).normalized() * 3.0
				want_speed = cruise
				if sea and sea.has_method(&"splash"):
					sea.call(&"splash", Vector3(p.x, wy, p.z), clampf(length, 0.4, 4.0))
			rotation = Vector3(pitch, yaw, 0.0)
			_anim(dt)
			return
	# рулёжка: курс плавно к желаемому, скорость — к желаемой
	var hor := Vector3(desired.x, 0.0, desired.z)
	var prev_yaw := yaw
	if hor.length() > 0.02 and spd > 0.01:
		var dy := atan2(-hor.x, -hor.z)
		var diff := wrapf(dy - yaw, -PI, PI)
		var k := turn_k * (3.5 if _startle_t > 0.0 else 1.0)
		yaw += clampf(diff, -k * dt, k * dt)
	elif mode == M.HOLD and face_dir.length() > 0.01:
		var dy := atan2(-face_dir.x, -face_dir.z)
		yaw += clampf(wrapf(dy - yaw, -PI, PI), -turn_k * 0.4 * dt, turn_k * 0.4 * dt)
	var burst := 1.0
	if _startle_t > 0.0:
		_startle_t -= dt
		burst = 3.5
	speed = move_toward(speed, minf(spd * burst, max_speed * 1.5), dt * accel * (4.0 if burst > 1.0 else 1.0))
	_turn = lerpf(_turn, clampf(wrapf(yaw - prev_yaw, -PI, PI) / maxf(dt, 1e-3) / maxf(turn_k, 0.1), -1.0, 1.0), clampf(dt * 6.0, 0.0, 1.0))
	var vy := 0.0
	if not bottom:
		vy = clampf(desired.y, -1.0, 1.0) * clampf(speed + 0.2, 0.2, 1.5)
	pitch = lerpf(pitch, clampf(vy * 0.5, -0.5, 0.5), clampf(dt * 2.0, 0.0, 1.0))
	vel = Vector3(-sin(yaw), 0.0, -cos(yaw)) * speed + Vector3(0.0, vy, 0.0)
	p += vel * dt
	global_position = _clamp(p)
	var g := String(sp.get("group", ""))
	roll = lerpf(roll, -_turn * (0.35 if g in ["ray", "mammal", "shark"] else 0.1), clampf(dt * 3.0, 0.0, 1.0))
	rotation = Vector3(pitch if not bottom else 0.0, yaw, roll if not bottom else 0.0)
	_anim(dt)

func _clamp(p: Vector3) -> Vector3:
	var fl := floor_y(p.x, p.z)
	var wy := water_y()
	if bottom:
		p.y = lerpf(p.y, fl + 0.01, 0.35)
	else:
		p.y = clampf(p.y, fl + min_above_floor + length * 0.15, wy - max_below_surface)
	return p

func _anim(dt: float) -> void:
	var st := 0.0
	if _startle_t > 0.0:
		st = sin((0.35 - _startle_t) / 0.35 * PI) * _startle
	if actor:
		if actor.kind == "octopus":
			# ползёт глазами вперёд; в реактивном рывке — мантией вперёд
			actor.rotation.y = lerp_angle(actor.rotation.y, 0.0 if float(octo.jet) > 0.5 else PI, clampf(dt * 5.0, 0.0, 1.0))
			actor.puppet_octo(dt, speed, octo.crawl, octo.threat, octo.grab, octo.jet, octo.flatten, octo.camo)
		else:
			actor.puppet_fish(dt, speed / maxf(_scale, 0.01), cruise / maxf(_scale, 0.01), _turn, st, mode == M.HOLD and speed < cruise * 0.3)
	elif proxy_mi:
		var rel := speed / maxf(cruise, 0.05)
		var hz := (0.8 + 0.9 * rel) / sqrt(maxf(length, 0.05))
		if proxy_kind == "ray" or proxy_kind == "turtle":
			hz = (0.35 + 0.25 * rel) / sqrt(maxf(length * 0.5, 0.2))
		elif proxy_kind == "jelly":
			hz = 0.5 + 0.4 * rel
		_phase += dt * TAU * clampf(hz, 0.1, 9.0)
		var amp := clampf(0.04 + rel * 0.03, 0.03, 0.14)
		if proxy_kind == "ray":
			amp = clampf(0.05 + rel * 0.04, 0.04, 0.16)
		proxy_mi.set_instance_shader_parameter(&"anim", Vector4(_phase, amp, _turn + st * 2.0, 0.0))
	# спрятался — уменьшается (уходит в коралл/нору)
	if body:
		body.visible = hidden_k < 0.98
