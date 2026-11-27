class_name SeaCritter
extends Node3D
## Существо сцены моря: тело (модель со скелетом и клипами автора SeaSkel, модель пака-«кукла»
## UserSeaActor или силуэт-дублёр SeaProxyMeshes) и рулёжка, которой командует сцена (SeaScene). Анимация тела — от скорости и поворота.
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
var floor_clear := -1.0          # зазор центра над дном (у моделей со скелетом — полвысоты тела)
var speed := 0.0
var vel := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var roll := 0.0
var hidden_k := 0.0              # 0 виден … 1 скрыт (спрятался в коралл — уменьшается)
var octo := {"crawl": 0.0, "threat": 0.0, "grab": 0.0, "jet": 0.0, "flatten": 0.0, "camo": 0.0}

var body: Node3D = null          # SeaSkel, UserSeaActor или MeshInstance3D
var actor: UserSeaActor = null
var skel: SeaSkel = null
## Рефлексы модели со скелетом (реакции на игрока, вдохи, вставки) — поверх команд сцены.
var reflexes := true
## Рефлексы, меняющие маршрут (скат удирает, черепаха всплывает дышать). Сцены моря ведут
## существ сами — у них выключено (SeaScene.critter), остаются клипы-реакции.
var reflex_moves := true
var _rx_cd := 0.0
## Держится хвостом (морской конёк): cling_at — точка стебля (мир), куда приходится завиток хвоста.
var clinging := false
var cling_at := Vector3.ZERO
var _rx_t := 0.0                 # таймер вида (вдох черепахи, кормёжка манты, бросок групера…)
var _rx_state := ""
var _act_cd := 0.0
var proxy_mi: MeshInstance3D = null
var proxy_kind := ""
var _turn := 0.0
var _startle := 0.0
var _startle_t := 0.0
var _phase := 0.0
var _rng := RandomNumberGenerator.new()
var _wander_t := 0.0
var _scale := 1.0
var dead := false               # убит (CreatureHitbox): не тикает, тело всплывает
var hitbox: CreatureHitbox = null

static var _proxy_mats: Dictionary = {}

## Создать существо вида sp (OceanRoster.species) в точке pos. Возвращает null, если вид
## представлен не моделью (краб/акула/стая/птица — у сцен для них свои помощники).
static func make(p_sp: Dictionary, p_sea: Object, pos: Vector3, seed_i: int) -> SeaCritter:
	var vis := OceanRoster.visual(p_sp)
	var k := String(vis.get("kind", ""))
	if k != "pack" and k != "proxy" and k != "skel":
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
	if String(vis.kind) == "skel":
		var vs: Array = vis.variants
		var vi := SeaSkel.next_variant if SeaSkel.next_variant >= 0 and SeaSkel.next_variant < vs.size() else _rng.randi() % vs.size()
		SeaSkel.next_variant = -1
		var vid := String(vs[vi])
		var dd := SeaSkel.def(vid)
		# длина вида: у вариантов своя (молодь ангела, жёлтый хирург) — по отношению к основному
		var L := float(vis.get("len", length)) * float(dd["len"]) / float(SeaSkel.def(String(vs[0]))["len"])
		L *= _rng.randf_range(0.9, 1.1)
		length = L
		skel = SeaSkel.create(vid, L, seed_i)
		add_child(skel)
		body = skel
		skel.on_event = _on_skel_event
		bottom = bool(dd.get("ground", false))
		_scale = L / float(dd["len"])
		floor_clear = SeaSkel.bounds(vid).size.y * 0.5 * _scale
		if vid == "moray":
			min_above_floor = 0.0
		_rx_t = _rng.randf_range(20.0, 60.0) if not vid.begins_with("seahorse") else _rng.randf_range(2.0, 6.0)
	elif String(vis.kind) == "pack":
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
	_add_hitbox(g)

## Хитбокс (пули, острога, стрелы, удар): урон, испуг, смерть, добыча — CreatureHitbox.
func _add_hitbox(g: String) -> void:
	var meat := &"meat_raw" if g in ["mammal", "turtle"] else &"fish_raw"
	var n := clampi(int(ceil(length * 3.0)), 1, 8)
	var hp := clampf(length * 40.0, 6.0, 240.0)
	hitbox = CreatureHitbox.attach(self, {"hp": hp, "drops": [{"id": meat, "n": n}] if length >= 0.12 else [],
		"solid": length >= 1.8})

func die() -> void:
	if dead:
		return
	dead = true
	if skel and skel.has_role("death"):
		skel.pose("death")
	var ws := water_y()
	var tw := create_tween()
	tw.set_parallel(true)
	if not (skel and skel.has_role("death")):
		tw.tween_property(self, ^"rotation:z", rotation.z + PI, 2.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, ^"position:y", position.y + maxf(0.0, ws - 0.2 - global_position.y), maxf(4.0, (ws - global_position.y) * 1.5))
	tw.set_parallel(false)
	tw.tween_interval(CreatureHitbox.CORPSE_TIME)
	tw.tween_callback(queue_free)

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

## Держаться хвостом за стебель/ветку: завиток хвоста (кость tail_grip) — в точке p, морда — по face.
## Тело стоит торчком (без тангажа/крена), качается клипом grip; действия (кормёжка, взгляд) — не отпуская.
func cling(p: Vector3, face: Vector3 = Vector3.ZERO) -> void:
	mode = M.HOLD
	clinging = true
	cling_at = p
	face_dir = face
	want_speed = 0.0
	if skel:
		skel.rest_pose = "grip"

## Отпустить стебель (и снять позу «держится»).
func release() -> void:
	clinging = false
	if skel:
		skel.rest_pose = ""
		skel.pose("")

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
	if skel:
		skel.act("jump")

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
		if water_y() - floor_y(p.x, p.z) > 0.3 and (_bounds != 1 or SeaBounds.water_ok(sea, p.x, p.z, SeaBounds.need_depth(length))):
			goal = p
			return
	goal = wander_c

# --- тик ------------------------------------------------------------------------

func tick(dt: float) -> void:
	if dt <= 0.0 or dead:
		if dead and skel:
			skel.drive(dt, 0.0, cruise, 0.0, true)
		return
	var p := global_position
	var desired := Vector3.ZERO
	var spd := want_speed
	if clinging and mode == M.HOLD:
		_tick_cling(dt)
		return
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

func _tick_cling(dt: float) -> void:
	if face_dir.length() > 0.01:
		var dy := atan2(-face_dir.x, -face_dir.z)
		yaw += clampf(wrapf(dy - yaw, -PI, PI), -turn_k * 0.6 * dt, turn_k * 0.6 * dt)
	pitch = lerpf(pitch, 0.0, clampf(dt * 4.0, 0.0, 1.0))
	roll = lerpf(roll, 0.0, clampf(dt * 4.0, 0.0, 1.0))
	rotation = Vector3(pitch, yaw, roll)
	speed = 0.0
	_turn = 0.0
	var off := Vector3.ZERO
	if skel:
		var g: Variant = skel.bone_point("tail_grip")
		if g != null:
			off = (g as Vector3) * skel.scale
	var want := cling_at - Basis.from_euler(rotation) * off
	global_position = global_position.lerp(want, clampf(dt * 10.0, 0.0, 1.0)) if global_position.distance_to(want) < 0.5 else want
	_anim(dt)

## Границы моря (SeaBounds) включены: -1 — ещё не решено (по месту появления: в бассейне
## полигона/вольере, где нет моря, — выключены).
var _bounds := -1

func _clamp(p: Vector3) -> Vector3:
	# v5.1: не на берег и не в отрезанную низину — всё тело в море нужной глубины (SeaBounds)
	if _bounds < 0:
		_bounds = 1 if sea and SeaBounds.water_ok(sea, global_position.x, global_position.z, 0.3) else 0
	if _bounds == 1 and not SeaBounds.body_ok(sea, p, forward(), maxf(length, 0.1)):
		var here := global_position
		if SeaBounds.water_ok(sea, here.x, here.z, SeaBounds.need_depth(length) * 0.6):
			p.x = here.x
			p.z = here.z
		yaw = wrapf(yaw + 0.35, -PI, PI)
		if mode == M.WANDER:
			_pick_wander()
	var fl := floor_y(p.x, p.z)
	var wy := water_y()
	if bottom:
		p.y = lerpf(p.y, fl + 0.01, 0.35)
	else:
		p.y = clampf(p.y, fl + min_above_floor + (floor_clear if floor_clear >= 0.0 else length * 0.15), wy - max_below_surface)
	return p

func _anim(dt: float) -> void:
	var st := 0.0
	if _startle_t > 0.0:
		st = sin((0.35 - _startle_t) / 0.35 * PI) * _startle
	if skel:
		if st != 0.0 and not skel.busy() and skel.has_role("startle"):
			skel.act("startle")
		skel.drive(dt, speed, cruise, _turn, mode == M.HOLD and speed < cruise * 0.3)
		if reflexes:
			_reflex(dt)
	elif actor:
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

# --- модели со скелетом: команды и рефлексы ----------------------------------------

## Разовое действие модели (роль клипа SeaSkel: bite, gulp, snap, ink, roll, breathe, jump, flip…).
func act(role: String) -> float:
	return skel.act(role) if skel else 0.0

## Поза (bury, threat, curl, death; "" — снять).
func pose(role: String) -> void:
	if skel:
		skel.pose(role)

func _player_pos() -> Variant:
	var pl := get_tree().get_first_node_in_group(&"player") as Node3D if is_inside_tree() else null
	if pl == null:
		var cam := get_viewport().get_camera_3d() if get_viewport() else null
		return cam.global_position if cam else null
	return pl.global_position

## Реакции по заданиям автора модели. Вызывается из _anim (тик сцены/менеджера).
func _reflex(dt: float) -> void:
	_act_cd = maxf(_act_cd - dt, 0.0)
	_rx_t -= dt
	_rx_cd -= dt
	if _rx_cd > 0.0:
		return
	_rx_cd = 0.25
	var pp: Variant = _player_pos()
	var dist := INF
	if pp != null:
		dist = global_position.distance_to(pp as Vector3)
	var L := length
	var free := mode == M.WANDER or mode == M.HOLD or mode == M.DRIFT
	match skel.id:
		"moray":
			# в норе: угроза (пасть, глоточные челюсти) при приближении, бросок вплотную, отход в нору
			if dist < L * 0.8 and _act_cd <= 0.0:
				skel.act("lunge")
				_act_cd = 3.0
			elif dist < L * 2.0 and speed < cruise * 0.3:
				if skel.posing() == "" and not skel.busy():
					skel.pose("threat")
			elif skel.posing() != "":
				skel.pose("")
		"stingray":
			if dist < 2.2 and skel.posing() != "" and reflex_moves:
				skel.pose("")
				bottom = false
				flee(pp as Vector3, 3.0)
				_act_cd = 4.0
			elif dist < 1.0 and _act_cd <= 0.0:
				skel.act("strike")
				_act_cd = 3.0
			elif reflex_moves and free and speed < cruise * 0.15 and dist > 4.0 and skel.posing() == "" \
					and global_position.y - floor_y(global_position.x, global_position.z) < 0.6:
				bottom = true
				skel.pose("bury")
			elif mode != M.HOLD and skel.posing() == "" and bottom:
				bottom = false
		"giant_grouper":
			if _rx_t <= 0.0:
				_rx_t = _rng.randf_range(15.0, 40.0)
				skel.act("gulp")
		"barracuda":
			if dist < 1.2 and _act_cd <= 0.0:
				skel.act("bite")
				_act_cd = 2.5
		"manta":
			if _rx_state == "feed":
				if _rx_t <= 0.0:
					_rx_state = ""
					skel.pose("")
					if _rng.randf() < 0.6:
						skel.act("roll")
					_rx_t = _rng.randf_range(20.0, 45.0)
			elif _rx_t <= 0.0 and free:
				_rx_state = "feed"
				_rx_t = _rng.randf_range(6.0, 12.0)
				skel.pose("feed")
		"dolphin":
			if global_position.y > water_y() - L * 0.6 and _act_cd <= 0.0:
				skel.act("breathe")
				_act_cd = _rng.randf_range(8.0, 20.0)
		"squid_red":
			if dist < 2.0 and _act_cd <= 0.0:
				skel.act("ink")
				startle(pp as Vector3)
				_act_cd = 6.0
		"turtle_green", "turtle_hawksbill":
			# вдох у поверхности каждые 30–90 с
			if _rx_state == "up":
				if global_position.y > water_y() - max_below_surface - 0.25 or _rx_t < -25.0:
					_rx_state = ""
					skel.act("breathe")
					_rx_t = _rng.randf_range(30.0, 90.0)
					wander(wander_c, wander_r)
			elif _rx_t <= 0.0 and free and reflex_moves:
				_rx_state = "up"
				var p := global_position
				goto(Vector3(p.x, water_y(), p.z) + forward() * 2.0, cruise)
		"lobster":
			if dist < 0.9 and _act_cd <= 0.0:
				skel.pose("")
				skel.act("flip")
				global_position -= forward() * 0.2 * _scale
				_act_cd = 3.0
			elif dist < 2.0 and skel.posing() == "" and not skel.busy():
				skel.pose("threat")
			elif dist > 2.6 and skel.posing() != "":
				skel.pose("")
		"shrimp_pistol":
			if dist < 0.5 and _act_cd <= 0.0:
				skel.act("flip")
				global_position -= forward() * 0.025 * _scale
				_act_cd = 2.0
		"starfish_orange", "starfish_spiny":
			if dist < 0.6 and skel.posing() == "":
				skel.pose("curl")
			elif dist > 1.2 and skel.posing() != "":
				skel.pose("")
		"seacucumber_spotted", "seacucumber_grey":
			if dist < 0.7 and skel.posing() == "":
				skel.pose("contract")
			elif dist > 1.4 and skel.posing() != "":
				skel.pose("")
		"seahorse_yellow", "seahorse_lilac", "seahorse_red":
			# конёк: держась за стебель — кормится (наклон головы и щелчок рылом) и косится глазами,
			# пловца рядом провожает взглядом; свободный — кормёжка/взгляды вставками, испуг вплотную
			if clinging:
				if not skel.busy():
					if dist < 1.2 and _act_cd <= 0.0:
						skel.act("grip_look")
						_act_cd = 4.0
					elif _rx_t <= 0.0:
						skel.act("grip_eat" if _rng.randf() < 0.6 else "grip_look")
						_rx_t = _rng.randf_range(4.0, 10.0)
			elif dist < 0.6 and _act_cd <= 0.0 and pp != null:
				startle(pp as Vector3)
				_act_cd = 3.0
		_:
			# рифовые рыбы: испуг в 1–2 м (C-изгиб и рывок)
			if dist < clampf(L * 8.0, 1.0, 2.0) and _act_cd <= 0.0 and pp != null:
				startle(pp as Vector3)
				_act_cd = 3.0

## События клипов: щелчок креветки — пузырь кавитации со вспышкой; чернила кальмара — облако.
func _on_skel_event(ev: String, s: SeaSkel) -> void:
	var p := s.global_position + forward() * length * 0.5 if s.is_inside_tree() else global_position
	match ev:
		"snap":
			SeaSkelFx.cavitation(self, p, 0.23)   # кадр 7 из 30 к/с
		"ink":
			SeaSkelFx.ink(self, s.global_position - forward() * length * 0.3, length)
