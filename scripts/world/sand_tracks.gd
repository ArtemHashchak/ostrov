extends Node
## Следы на песке (автозагрузка SandTracks).
## Хранит только недавние отпечатки рядом с камерой (до MAX_PRINTS записей: место, направление шага,
## левая/правая, размер, «свежесть»). Раз в 1/REDRAW_HZ с карта 1024×1024 на окно 32×32 м вокруг
## камеры (3 см на пиксель) перерисовывается из этих записей: R — глубина отпечатка 0..1.
## Шейдер рельефа (terrain_tropic) по ней продавливает песок (нормаль по краю отпечатка, тень в лунке)
## и подмешивает утоптанный песок пользователя (Грунт/Песок → assets/textures/sand_trampled).
## Старое выцветает (сухой песок ~15 мин, в дождь быстрее), ниже линии наката волна размывает
## отпечаток за несколько секунд. Свои следы оставляют персонажи (группа characters) и крупные звери.

const RES := 1024
const SIZE := 32.0                  # м на сторону окна → 3.1 см/пиксель
const MAX_PRINTS := 360
const STRIDE := 0.72                # м между шагами человека
const FOOT_LEN := 0.27
const FOOT_W := 0.105
const FADE_PER_S := 1.0 / 900.0     # сухой песок: ~15 минут
const RAIN_PER_S := 1.0 / 120.0
const WASH_PER_S := 1.0 / 3.0       # под накатом — за 3 с
const REDRAW_HZ := 8.0
const ANIMAL_SPECIES := [&"boar", &"croc", &"turtle", &"monitor", &"iguana", &"monkey"]

var enabled := true
var origin := Vector2.ZERO          # мир (x, z) угла окна
var prints: Array = []              # [x, z, dirx, dirz, side, scale, strength(0..1)]
var stamps_total := 0
var _img: Image
var _tex: ImageTexture
var _walkers := {}                  # instance_id -> {last: Vector2, side: int}
var _redraw_t := 0.0
var _decay_t := 0.0
var _dirty := false
var _world: Node = null
var _active := false

func _ready() -> void:
	_img = Image.create(RES, RES, false, Image.FORMAT_R8)
	_tex = ImageTexture.create_from_image(_img)
	# параметры sand_tracks_* объявлены в project.godot [shader_globals]
	RenderingServer.global_shader_parameter_set(&"sand_tracks_map", _tex)
	_set_rect(false)

func _set_rect(on: bool) -> void:
	RenderingServer.global_shader_parameter_set(&"sand_tracks_rect", Vector4(origin.x, origin.y, SIZE, 1.0 if on else 0.0))

func clear() -> void:
	prints.clear()
	_walkers.clear()
	_dirty = true

## Отпечаток вручную: pos — мир, dir — направление шага (x, z), side 0 — левая, 1 — правая.
func stamp_foot(pos: Vector3, dir: Vector2, side: int, strength := 1.0, scale := 1.0) -> void:
	_add(Vector2(pos.x, pos.z), dir, side, strength, scale)

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
		_redraw()

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
	_dirty = true
	# дальние записи больше не нужны
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
		if sp != null and ANIMAL_SPECIES.has(StringName(str(sp))):
			nodes.append(a)
	var seen := {}
	for n in nodes:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var id: int = n.get_instance_id()
		seen[id] = true
		var g: Vector3 = (n as Node3D).global_position
		var p := Vector2(g.x, g.z)
		var w: Dictionary = _walkers.get(id, {})
		if w.is_empty():
			_walkers[id] = {"last": p, "side": 0}
			continue
		var d: Vector2 = p - w.last
		if d.length() > 6.0:          # телепорт/респаун
			w.last = p
			continue
		var animal: bool = n.is_in_group(&"animals")
		var stride := 0.45 if animal else STRIDE
		if d.length() < stride:
			continue
		var air := g.y - float(_world.height_at(g.x, g.z))
		var swimming = n.get("swimming")
		if air < 1.4 and swimming != true and _is_sand(p):
			var dir := d.normalized()
			if animal:
				# четыре лапы: пара отпечатков на шаг, мельче
				_add(p, dir, w.side, 0.8, 0.75)
				_add(p - dir * 0.35, dir, 1 - w.side, 0.7, 0.75)
			else:
				_add(p, dir, w.side, 1.0, 1.0)
		w.side = 1 - w.side
		w.last = p
	for id in _walkers.keys():
		if not seen.has(id):
			_walkers.erase(id)

func _add(p: Vector2, dir: Vector2, side: int, strength: float, scale: float) -> void:
	if dir.length_squared() < 1e-6:
		dir = Vector2(0, -1)
	dir = dir.normalized()
	prints.append([p.x, p.y, dir.x, dir.y, side, scale, clampf(strength, 0.0, 1.0)])
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

func _redraw() -> void:
	_img.fill(Color(0, 0, 0))
	var px := SIZE / RES
	for p: Array in prints:
		_draw(Vector2(float(p[0]), float(p[1])), Vector2(float(p[2]), float(p[3])), int(p[4]), float(p[5]), float(p[6]), px)
	_tex.update(_img)

## Отпечаток ступни: носок шире пятки, глубже в пятке и под подушечками; валик по краю
## получается в шейдере — нормаль берётся из градиента карты.
func _draw(p: Vector2, dir: Vector2, side: int, scale: float, strength: float, px: float) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var c := p + perp * (0.1 * scale) * (1.0 if side == 0 else -1.0)
	var L := FOOT_LEN * scale
	var W := FOOT_W * scale
	var cx := (c.x - origin.x) / px
	var cy := (c.y - origin.y) / px
	var rp := int(ceil(L * 0.6 / px)) + 1
	var x0 := maxi(0, int(cx) - rp)
	var x1 := mini(RES - 1, int(cx) + rp)
	var y0 := maxi(0, int(cy) - rp)
	var y1 := mini(RES - 1, int(cy) + rp)
	if x0 > x1 or y0 > y1:
		return
	for yy in range(y0, y1 + 1):
		for xx in range(x0, x1 + 1):
			var q := Vector2((xx + 0.5) * px + origin.x, (yy + 0.5) * px + origin.y) - c
			var u := q.dot(dir) / (L * 0.5)          # −1 пятка … +1 носок
			if absf(u) >= 1.0:
				continue
			var widen := 0.78 + 0.32 * clampf(u + 0.2, -1.0, 1.0)
			var v := q.dot(perp) / (W * 0.5 * widen)
			var e := u * u + v * v
			if e >= 1.0:
				continue
			# профиль: плоское дно, мягкий край; пятка и подушечки глубже
			var depth := smoothstep(1.0, 0.55, e) * (0.75 + 0.25 * (exp(-pow((u + 0.62) * 3.2, 2.0)) + exp(-pow((u - 0.5) * 3.5, 2.0))))
			var val := clampf(depth * strength, 0.0, 1.0)
			if val > _img.get_pixel(xx, yy).r:
				_img.set_pixel(xx, yy, Color(val, 0, 0))
