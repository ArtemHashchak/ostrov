extends Node
## Следы на песке (автозагрузка SandTracks).
##
## Хранит недавние отпечатки рядом с камерой (до MAX_PRINTS записей). Карта следов RG 2048² на окно
## 24×24 м вокруг камеры (1.2 см на пиксель) рисуется на GPU: SubViewport с 2D-холстом, каждый
## отпечаток — повернутый штамп своего вида (ступня человека с пальцами, раздвоенное копыто кабана,
## когтистая лапа ящерицы/варана/крокодила, ладонь обезьяны, ласт черепахи, борозда хвоста/брюха).
##   R — глубина лунки 0..1 (1 = TRACK_DEPTH в шейдере, 4.5 см), G — валик выдавленного песка.
## Штампы строятся один раз процедурно (маска глубины → валик = размытая маска минус сама маска).
## Новый отпечаток перекрывает старый (как настоящая нога). Шейдер рельефа (terrain_tropic) делает
## по карте параллакс (лунка видна глубокой при взгляде сбоку), нормаль стенок и валика, тёмное
## влажное дно и утоптанное зерно песка пользователя.
## Старое заплывает (сухой песок ~15 мин, в дождь быстрее); ниже линии наката волна стирает отпечаток
## за несколько секунд. Следы оставляют персонажи (группа characters) и крупные звери: у каждого своя
## походка (человек — левая/правая; кабан — рысь диагоналями; ящерицы/варан/крокодил — лапы широко в
## стороны, пальцы развернуты наружу, волнистая борозда хвоста; черепаха — пары ласт + борозда панциря).

const RES := 2048
const SIZE := 24.0                  # м на сторону окна → 1.17 см/пиксель
const STAMP_RES := 128
const MAX_PRINTS := 700
const STRIDE := 0.72                # м между шагами человека
const FOOT_LEN := 0.27
const FADE_PER_S := 1.0 / 900.0     # сухой песок: ~15 минут
const RAIN_PER_S := 1.0 / 120.0
const WASH_PER_S := 1.0 / 3.0       # под накатом — за 3 с
const REDRAW_HZ := 8.0

enum { FOOT, HOOF, CLAW, HAND, FLIPPER, DRAG, FOOT_TOE, FOOT_HEEL, KNEE }

## Походки: шаг (м), штамп, размер штампа (м, сторона квадрата), смещение лап вбок, база (перед—зад),
## разворот пальцев наружу (рад), сила вдавливания, борозда хвоста/брюха (ширина м, 0 — нет).
const GAITS := {
	&"human":   {"stride": 0.72, "type": FOOT,    "size": 0.375, "lat": 0.09, "base": 0.0, "splay": 0.1,  "str": 1.0, "drag": 0.0},
	&"boar":    {"stride": 0.42, "type": HOOF,    "size": 0.13,  "lat": 0.09, "base": 0.62, "splay": 0.0, "str": 0.95, "drag": 0.0},
	&"iguana":  {"stride": 0.2,  "type": CLAW,    "size": 0.17,  "lat": 0.12, "base": 0.3,  "splay": 0.5, "str": 0.55, "drag": 0.05},
	&"monitor": {"stride": 0.3,  "type": CLAW,    "size": 0.25,  "lat": 0.18, "base": 0.5,  "splay": 0.45, "str": 0.75, "drag": 0.08},
	&"croc":    {"stride": 0.55, "type": CLAW,    "size": 0.36,  "lat": 0.36, "base": 1.0,  "splay": 0.4, "str": 1.0, "drag": 0.2},
	&"turtle":  {"stride": 0.32, "type": FLIPPER, "size": 0.36,  "lat": 0.32, "base": 0.0,  "splay": 0.0, "str": 0.85, "drag": 0.5},
	&"monkey":  {"stride": 0.36, "type": HAND,    "size": 0.15,  "lat": 0.1,  "base": 0.35, "splay": 0.2, "str": 0.6, "drag": 0.0},
}

## Приземление на песок: точка (y не задан) и сила — для частиц брызг песка.
signal land_spray(pos: Vector3, strength: float)

var enabled := true
var origin := Vector2.ZERO          # мир (x, z) угла окна
## [x, z, dirx, dirz, side(0 лев./1 прав.), ширина м, сила 0..1, тип, длина м]
var prints: Array = []
var stamps_total := 0
var _stamps: Array[ImageTexture] = []
var _vp: SubViewport
var _canvas: Node2D
var _walkers := {}                  # instance_id -> {last, side, phase}
var _redraw_t := 0.0
var _decay_t := 0.0
var _dirty := false
var _world: Node = null
var _active := false

func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(RES, RES)
	_vp.disable_3d = true
	_vp.transparent_bg = true
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_canvas = Node2D.new()
	_vp.add_child(_canvas)
	add_child(_vp)
	_canvas.draw.connect(_on_draw)
	# параметры sand_tracks_* объявлены в project.godot [shader_globals]
	RenderingServer.global_shader_parameter_set(&"sand_tracks_map", _vp.get_texture())
	_set_rect(false)

func _set_rect(on: bool) -> void:
	RenderingServer.global_shader_parameter_set(&"sand_tracks_rect", Vector4(origin.x, origin.y, SIZE, 1.0 if on else 0.0))

func clear() -> void:
	prints.clear()
	_walkers.clear()
	_dirty = true

## Скорость (м/с), с которой шаг считается бегом: следы глубже и реже.
const RUN_FROM := 4.2
const RUN_STRIDE := 1.35            # м между шагами на бегу (шаг ~0.72 при ходьбе)

## Отпечаток ступни человека: pos — мир, dir — направление шага (x, z), side 0 — левая, 1 — правая.
func stamp_foot(pos: Vector3, dir: Vector2, side: int, strength := 1.0, scale := 1.0) -> void:
	_add(Vector2(pos.x, pos.z), dir, side, strength, 0.375 * scale, FOOT, 0.0)

## Цепочка следов вида (как если бы зверь прошёл от a до b) — для полигона и тестов.
func walk_line(species: StringName, a: Vector3, b: Vector3, scale := 1.0) -> void:
	var g: Dictionary = GAITS.get(species, GAITS[&"human"])
	var d := Vector2(b.x - a.x, b.z - a.z)
	var n := int(d.length() / (float(g.stride) * scale))
	var w := {"last": Vector2(a.x, a.z), "side": 0, "phase": 0.0}
	for i in range(1, n + 1):
		var p := Vector2(a.x, a.z) + d * (float(i) / n)
		_step(g, w, p, p - w.last, scale)
		w.last = p
		w.side = 1 - int(w.side)

## Свежесть ближайшего отпечатка (0..1) в радиусе 0.2 м — для тестов/логики.
func depth_at(x: float, z: float) -> float:
	var best := 0.0
	for p: Array in prints:
		var q := Vector2(x - float(p[0]), z - float(p[1]))
		if q.length_squared() < 0.04:
			best = maxf(best, float(p[6]))
	return best

func _process(dt: float) -> void:
	if not enabled:
		return
	if _world == null or not is_instance_valid(_world):
		_world = get_tree().get_first_node_in_group(&"world")
		_active = false
		if _world == null:
			return
	if not _active:
		var mat = _world.get("terrain_material")
		_active = mat is ShaderMaterial and float((mat as ShaderMaterial).get_shader_parameter(&"use_beach_sand")) > 0.5
		if not _active:
			return
		if _stamps.is_empty():
			_build_stamps()     # ~0.3 с один раз, только на мире с пляжным песком
		clear()
		_recenter(true)
	_recenter(false)
	_track_walkers()
	_decay_t += dt
	if _decay_t >= 0.25:
		_decay(_decay_t)
		_decay_t = 0.0
	_redraw_t += dt
	if _dirty and _redraw_t >= 1.0 / REDRAW_HZ:
		_redraw_t = 0.0
		_dirty = false
		_canvas.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

func _recenter(force: bool) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := Vector2(cam.global_position.x, cam.global_position.z)
	var rel := c - origin
	var m := SIZE * 0.3
	if not force and rel.x > m and rel.y > m and rel.x < SIZE - m and rel.y < SIZE - m:
		return
	# окно — целыми пикселями, чтобы отпечатки не «плыли» при сдвиге
	var px := SIZE / RES
	var o := c - Vector2(SIZE, SIZE) * 0.5
	origin = Vector2(floorf(o.x / px) * px, floorf(o.y / px) * px)
	_set_rect(true)
	# Перерисовать карту В ЭТОМ ЖЕ кадре, что и новый rect: иначе до 1/8 с шейдер видит старую
	# картинку в новом окне — следы «прыгают» вперёд на величину сдвига (баг «тропинка следов
	# впереди бегущего игрока» каждые ~1–3 с на бегу).
	_dirty = false
	_redraw_t = 0.0
	_canvas.queue_redraw()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var keep: Array = []
	for p: Array in prints:
		if absf(float(p[0]) - c.x) < SIZE and absf(float(p[1]) - c.y) < SIZE:
			keep.append(p)
	prints = keep

func _is_sand(p: Vector2) -> bool:
	if not _world.has_method("biome_at"):
		return false
	var b: StringName = _world.biome_at(p.x, p.y)
	if b == &"beach":
		return true
	# кромка прибоя (чуть ниже среднего уровня) — тоже песок, там следы видны лучше всего
	if b == &"water" and _world.has_method("water_level"):
		var h: float = _world.height_at(p.x, p.y)
		return h > float(_world.water_level()) - 0.4 and h < 1.0
	return false

func _track_walkers() -> void:
	var nodes: Array = get_tree().get_nodes_in_group(&"characters")
	for a in get_tree().get_nodes_in_group(&"animals"):
		var sp = a.get("species")
		if sp != null and GAITS.has(StringName(str(sp))):
			nodes.append(a)
	var seen := {}
	for n in nodes:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var id: int = n.get_instance_id()
		seen[id] = true
		var g3: Vector3 = (n as Node3D).global_position
		var p := Vector2(g3.x, g3.z)
		var w: Dictionary = _walkers.get(id, {})
		if w.is_empty():
			_walkers[id] = {"last": p, "side": 0, "phase": 0.0}
			continue
		var d: Vector2 = p - w.last
		if d.length() > 6.0:          # телепорт/респаун
			w.last = p
			continue
		var animal: bool = n.is_in_group(&"animals")
		var key: StringName = StringName(str(n.get("species"))) if animal else &"human"
		var g: Dictionary = GAITS[key]
		var sc := 1.0
		if animal:
			var gr = n.get("growth")
			if gr != null:
				sc = lerpf(0.5, 1.0, clampf((float(gr) - 0.45) / 0.55, 0.0, 1.0))
		var swimming = n.get("swimming")
		var on_sand: bool = swimming != true and _is_sand(p)
		# в воздухе следов нет; отталкивание и приземление — отдельные пары отпечатков
		var grounded := true
		if n.has_method(&"is_on_floor"):
			grounded = bool(n.call(&"is_on_floor"))
		else:
			grounded = g3.y - float(_world.height_at(g3.x, g3.z)) < 1.4   # центр корпуса ~0.9 м над землёй
		var was: bool = w.get("ground", true)
		var vel := Vector3.ZERO
		var vv = n.get("velocity")
		if vv is Vector3:
			vel = vv
		var hv := Vector2(vel.x, vel.z)
		if was and not grounded:
			w["air_t"] = 0.0
			w["air_from"] = p
			if on_sand and not animal:
				_jump_pair(p, hv if hv.length() > 0.3 else d, FOOT_TOE, 1.0)
		elif grounded and not was:
			if on_sand and not animal:
				var air_t := float(w.get("air_t", 0.0))
				var st := clampf(0.75 + air_t * 0.6, 0.75, 1.0)
				_jump_pair(p, hv if hv.length() > 0.3 else d, FOOT_HEEL, st)
				if air_t > 0.9:       # тяжёлое приземление: рука упирается в песок
					_add(p + _right(hv if hv.length() > 0.3 else d) * 0.32 + (hv.normalized() if hv.length() > 0.3 else d.normalized()) * 0.35,
						hv if hv.length() > 0.3 else d, 1, 0.8, 0.2, HAND, 0.0)
			w.last = p
		w["ground"] = grounded
		if not grounded:
			w["air_t"] = float(w.get("air_t", 0.0)) + get_process_delta_time()
			w.last = p
			continue
		# присел на месте — колено (одно, на стороне последнего шага), один раз за присед
		var cr = n.get("crouching")
		if cr == true and not w.get("crouch", false) and on_sand and not animal and hv.length() < 0.6:
			var fw := Vector2(0, -1).rotated(-float((n as Node3D).global_rotation.y))
			_add(p - fw * 0.12 + _right(fw) * (0.12 if int(w.side) == 1 else -0.12), fw, int(w.side), 0.85, 0.16, KNEE, 0.24)
		w["crouch"] = cr == true
		# бег: шаг длиннее (следы реже), вдавливание глубже, носок сильнее
		var stride := float(g.stride) * sc
		var run := 0.0
		if not animal:
			run = clampf((hv.length() - RUN_FROM) / 1.6, 0.0, 1.0)
			stride = lerpf(stride, RUN_STRIDE, run)
		if d.length() < stride:
			continue
		if on_sand:
			if run > 0.5:
				var dir2 := d.normalized()
				var sgn2 := 1.0 if int(w.side) == 1 else -1.0
				_add(p + _right(dir2) * float(g.lat) * sgn2 * 0.8, dir2, int(w.side), 1.0, float(g.size) * sc, FOOT_TOE, 0.0)
			else:
				_step(g, w, p, d, sc)
		w.side = 1 - int(w.side)
		w.last = p
	for id in _walkers.keys():
		if not seen.has(id):
			_walkers.erase(id)

## Один шаг походки: p — текущее положение (центр корпуса), d — смещение с прошлого шага.
func _step(g: Dictionary, w: Dictionary, p: Vector2, d: Vector2, sc: float) -> void:
	var dir := d.normalized() if d.length_squared() > 1e-8 else Vector2(0, -1)
	var right := Vector2(-dir.y, dir.x)
	var side: int = int(w.side)
	var t: int = int(g.type)
	var size: float = float(g.size) * sc
	var lat: float = float(g.lat) * sc
	var base: float = float(g.base) * sc
	var st: float = float(g.str) * lerpf(0.6, 1.0, sc)
	var spl: float = float(g.splay)
	var sgn := 1.0 if side == 1 else -1.0
	match t:
		FOOT:
			_add(p + right * lat * sgn, dir.rotated(spl * sgn), side, st, size, FOOT, 0.0)
		FLIPPER:
			# черепаха гребёт обоими ластами сразу; ласты развернуты назад-наружу
			for s in [0, 1]:
				var k := 1.0 if s == 1 else -1.0
				_add(p + right * lat * k, dir.rotated(0.8 * k), s, st, size * 0.8, FLIPPER, 0.0)
		_:
			# четвероногие — диагональные пары: передняя одной стороны + задняя другой
			_add(p + dir * base * 0.5 + right * lat * sgn, dir.rotated(spl * sgn), side, st, size, t, 0.0)
			_add(p - dir * base * 0.5 - right * lat * sgn, dir.rotated(-spl * sgn), 1 - side, st, size * 1.12, t, 0.0)
	var dw: float = float(g.drag) * sc
	if dw > 0.0:
		# борозда хвоста/брюха — за корпусом; хвост виляет (фаза идёт с каждым шагом)
		w.phase = float(w.phase) + 1.3
		var sway := sin(float(w.phase)) * lat * 0.45 if t != FLIPPER else 0.0
		var back := base * 0.9 if t != FLIPPER else 0.0
		var mid := p - d * 0.5 - dir * back + right * sway
		_add(mid, dir, 0, st * 0.55, dw, DRAG, d.length() * 1.7 + dw)

func _right(dir: Vector2) -> Vector2:
	var d := dir.normalized() if dir.length_squared() > 1e-8 else Vector2(0, -1)
	return Vector2(-d.y, d.x)

## Пара ступней рядом (отталкивание — носки глубже; приземление — пятки глубже + выброс песка).
func _jump_pair(p: Vector2, dir: Vector2, type: int, strength: float) -> void:
	var d := dir.normalized() if dir.length_squared() > 1e-8 else Vector2(0, -1)
	var r := _right(d)
	for side in [0, 1]:
		var k := 1.0 if side == 1 else -1.0
		_add(p + r * 0.12 * k, d.rotated(0.08 * k), side, strength, 0.375, type, 0.0)
	if type == FOOT_HEEL:
		land_spray.emit(Vector3(p.x, 0.0, p.y), strength)
		_spray(p, d, strength)

## Выброс песка из-под ног при приземлении: короткий веер песчинок вперёд-вбок (CPU, ~30 частиц).
func _spray(p: Vector2, dir: Vector2, strength: float) -> void:
	if _world == null:
		return
	var y := float(_world.height_at(p.x, p.y))
	var e := CPUParticles3D.new()
	e.one_shot = true
	e.explosiveness = 0.92
	e.amount = int(18 + 18 * strength)
	e.lifetime = 0.7
	e.local_coords = false
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.12
	e.direction = Vector3(dir.x, 1.4, dir.y).normalized()
	e.spread = 55.0
	e.initial_velocity_min = 0.6 * strength
	e.initial_velocity_max = 1.9 * strength
	e.gravity = Vector3(0, -9.8, 0)
	e.scale_amount_min = 0.006
	e.scale_amount_max = 0.016
	var m := QuadMesh.new()
	m.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = Color(0.78, 0.7, 0.55)
	m.material = mat
	e.mesh = m
	var c := Gradient.new()
	c.set_color(0, Color(1, 1, 1, 1))
	c.set_color(1, Color(1, 1, 1, 0))
	e.color_ramp = c
	_world.add_child(e)
	e.global_position = Vector3(p.x, y + 0.05, p.y)
	e.emitting = true
	e.finished.connect(e.queue_free)

func _add(p: Vector2, dir: Vector2, side: int, strength: float, size: float, type: int, length: float) -> void:
	if dir.length_squared() < 1e-6:
		dir = Vector2(0, -1)
	dir = dir.normalized()
	prints.append([p.x, p.y, dir.x, dir.y, side, size, clampf(strength, 0.0, 1.0), type, length if length > 0.0 else size])
	if prints.size() > MAX_PRINTS:
		prints.remove_at(0)
	stamps_total += 1
	_dirty = true

func _decay(dt: float) -> void:
	if _world == null or prints.is_empty():
		return
	var wl: float = _world.water_level() if _world.has_method("water_level") else 0.0
	var rain := 0.0
	if _world.has_method("rain_factor"):
		rain = float(_world.rain_factor())
	var dry := (FADE_PER_S + RAIN_PER_S * rain) * dt
	var keep: Array = []
	for p: Array in prints:
		var x := float(p[0])
		var z := float(p[1])
		var h: float = _world.height_at(x, z)
		var run_up := wl + 0.3
		if _world.has_method("wave_height"):
			run_up = maxf(run_up, float(_world.wave_height(x, z)) + 0.2)
		var s := float(p[6]) - (WASH_PER_S * dt if h < run_up else dry)
		if s > 0.01:
			p[6] = s
			keep.append(p)
	prints = keep
	_dirty = true

## Холст карты: каждый отпечаток — штамп, повернутый по направлению шага (верх штампа — носок).
func _on_draw() -> void:
	if _stamps.is_empty():
		return
	var px := SIZE / RES
	for p: Array in prints:
		var c := Vector2((float(p[0]) - origin.x) / px, (float(p[1]) - origin.y) / px)
		if c.x < -64 or c.y < -64 or c.x > RES + 64 or c.y > RES + 64:
			continue
		var dx := float(p[2])
		var dz := float(p[3])
		var ang := atan2(dx, -dz)
		var mirror := -1.0 if int(p[4]) == 0 else 1.0
		var wpx := float(p[5]) / px
		var lpx := float(p[8]) / px
		var s := float(p[6])
		_canvas.draw_set_transform(c, ang, Vector2(mirror, 1.0))
		_canvas.draw_texture_rect(_stamps[int(p[7])], Rect2(-wpx * 0.5, -lpx * 0.5, wpx, lpx), false, Color(s, s, 1.0, 1.0))
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ------------------------------------------------------------------ штампы
## Маска глубины штампа в своих координатах: u — вперед (носок) −1..1, v — вбок (+ наружу у правой).
func _shape(t: int, u: float, v: float) -> float:
	match t:
		FOOT:
			var d := _ell(u, v, -0.5, 0.0, 0.22, 0.17) * 1.0                       # пятка — глубже всего
			d = maxf(d, _ell(u, v, -0.08, 0.11, 0.3, 0.085) * 0.55)                 # наружный свод
			d = maxf(d, _ell(u, v, 0.28, -0.01, 0.17, 0.24) * 0.9)                  # подушечка
			d = maxf(d, _ell(u, v, 0.62, -0.15, 0.11, 0.095) * 0.95)                # большой палец
			var toes := [[0.58, 0.0, 0.065], [0.54, 0.1, 0.06], [0.48, 0.18, 0.055], [0.41, 0.245, 0.05]]
			for q in toes:
				d = maxf(d, _ell(u, v, q[0], q[1], q[2], q[2]) * 0.72)
			return d
		HOOF:
			var d := 0.0
			for k in [-1.0, 1.0]:
				# половинка копыта: капля, острием вперед, внутренний край прямой
				var cu := 0.12
				var taper := 1.0 - 0.55 * clampf((u - cu) / 0.5, 0.0, 1.0)
				d = maxf(d, _ell(u, v, cu, 0.15 * k, 0.5, 0.12 * taper) * (0.85 + 0.15 * clampf(-u, 0.0, 1.0)))
				d = maxf(d, _ell(u, v, -0.62, 0.3 * k, 0.08, 0.065) * 0.4)        # прибылые пальцы
			return d
		CLAW:
			var d := _ell(u, v, -0.25, 0.0, 0.22, 0.2) * 0.75                         # ладонь
			# пять пальцев веером; у ящериц четвертый (наружный) самый длинный
			var angs := [-1.0, -0.5, 0.0, 0.45, 0.95]
			var lens := [0.38, 0.55, 0.66, 0.74, 0.5]
			for i in 5:
				var a: float = angs[i]
				var tip := Vector2(-0.25, 0.0) + Vector2(cos(a), sin(a)) * float(lens[i]) * Vector2(1.0, 0.85)
				d = maxf(d, _capsule(u, v, Vector2(-0.2, 0.0), tip, 0.045) * 0.6)
				d = maxf(d, _ell(u, v, tip.x + cos(a) * 0.04, tip.y + sin(a) * 0.04, 0.035, 0.03) * 1.0)  # коготь
			return d
		HAND:
			var d := _ell(u, v, -0.2, 0.0, 0.3, 0.27) * 0.8
			for i in 4:
				var vv := -0.18 + i * 0.12
				d = maxf(d, _capsule(u, v, Vector2(0.05, vv), Vector2(0.45 - absf(vv - 0.0) * 0.4, vv * 1.15), 0.05) * 0.7)
			d = maxf(d, _capsule(u, v, Vector2(-0.25, -0.22), Vector2(0.0, -0.5), 0.055) * 0.7)  # большой
			return d
		FLIPPER:
			# мазок ласта: дуга назад-наружу, глубже у переднего края
			var d := _capsule(u, v, Vector2(0.45, -0.3), Vector2(-0.4, 0.35), 0.16) * (0.55 + 0.45 * clampf(u * 0.8 + 0.5, 0.0, 1.0))
			d = maxf(d, _capsule(u, v, Vector2(0.3, -0.05), Vector2(-0.55, 0.55), 0.08) * 0.5)
			return d
		FOOT_TOE:
			# толчок: носок и пальцы глубоко, пятка едва касается, песок выброшен назад
			var d := _shape(FOOT, u, v)
			var k := smoothstep(-0.7, 0.5, u)
			return d * lerpf(0.25, 1.15, k)
		FOOT_HEEL:
			# приземление: пятка ударяет глубоко, пальцы слабее
			var d := _shape(FOOT, u, v)
			var k := smoothstep(0.6, -0.5, u)
			return d * lerpf(0.4, 1.2, k)
		KNEE:
			# колено + голень: овальная вмятина, след голени назад
			var d := _ell(u, v, 0.45, 0.0, 0.38, 0.62)
			d = maxf(d, _capsule(u, v, Vector2(0.3, 0.0), Vector2(-0.85, 0.0), 0.38) * 0.55)
			return d
		DRAG:
			# борозда: округлый профиль поперек, по длине почти ровная
			var a := clampf(1.0 - absf(v) / 0.7, 0.0, 1.0)
			return (1.0 - (1.0 - a) * (1.0 - a)) * smoothstep(1.0, 0.55, absf(u)) * 0.8
	return 0.0

func _ell(u: float, v: float, cu: float, cv: float, ru: float, rv: float) -> float:
	var e := pow((u - cu) / ru, 2.0) + pow((v - cv) / rv, 2.0)
	return smoothstep(1.0, 0.45, e)

func _capsule(u: float, v: float, a: Vector2, b: Vector2, r: float) -> float:
	var p := Vector2(u, v)
	var ab := b - a
	var h := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	var dist := (p - a - ab * h).length()
	return smoothstep(r, r * 0.35, dist)

func _build_stamps() -> void:
	var n := STAMP_RES
	for t in [FOOT, HOOF, CLAW, HAND, FLIPPER, DRAG, FOOT_TOE, FOOT_HEEL, KNEE]:
		var dimg := Image.create(n, n, false, Image.FORMAT_RF)
		for y in n:
			for x in n:
				# картинка: x — вбок (v), строка 0 — носок (u = +1)
				var v := (x + 0.5) / n * 2.0 - 1.0
				var u := 1.0 - (y + 0.5) / n * 2.0
				dimg.set_pixel(x, y, Color(_shape(t, u, v), 0, 0))
		# валик: выдавленный песок вокруг отпечатка = размытая маска − сама маска
		var blur := dimg.duplicate() as Image
		blur.resize(n / 8, n / 8, Image.INTERPOLATE_BILINEAR)
		blur.resize(n, n, Image.INTERPOLATE_CUBIC)
		var out := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := dimg.get_pixel(x, y).r
				var b := blur.get_pixel(x, y).r
				var rim := clampf(b * 2.2 - d * 2.6, 0.0, 1.0)
				if t == DRAG:
					# борозда кладется внахлест — валик только по бокам, иначе «лесенка» на стыках
					var vv := absf((x + 0.5) / n * 2.0 - 1.0)
					var uu := absf(1.0 - (y + 0.5) / n * 2.0)
					rim = clampf((vv - 0.62) / 0.12, 0.0, 1.0) * clampf((1.0 - vv) / 0.15, 0.0, 1.0) * 0.8 * smoothstep(1.0, 0.7, uu)
				# край штампа — без валика (квадрат не должен читаться)
				var ex := minf(minf(x, n - 1 - x), minf(y, n - 1 - y)) / (n * 0.08)
				rim *= clampf(ex, 0.0, 1.0)
				var a := clampf(maxf(d, rim) * 5.0, 0.0, 1.0)
				if t == DRAG:
					# борозда: профиль поперёк в цвете, спад по длине — в прозрачности (стыки сливаются)
					var vv2 := (x + 0.5) / n * 2.0 - 1.0
					var uu2 := 1.0 - (y + 0.5) / n * 2.0
					var dl := _shape(DRAG, 0.0, vv2)
					a = smoothstep(1.0, 0.45, absf(uu2)) * clampf(maxf(dl, rim) * 5.0, 0.0, 1.0)
					d = dl
				out.set_pixel(x, y, Color(d, rim, 0.0, a))
		_stamps.append(ImageTexture.create_from_image(out))
