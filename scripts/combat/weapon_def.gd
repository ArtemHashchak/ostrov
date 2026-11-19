class_name WeaponDef
extends Resource
## Описание современного огнестрела (пистолет, автомат): магазин, темп и режимы огня,
## урон с падением по дистанции, разброс (бедро/ADS/движение/прыжок/очередь), паттерн
## отдачи и пружина камеры, перезарядка (тактическая — с патроном в патроннике, полная),
## прицеливание (FOV, время), звуки, трассеры, гильзы.
##
## Реестр: WeaponDef.of(id) / WeaponDef.has(id). Базовые поля попадают в Combat.weapon(id)
## (to_weapon()), поэтому Combat API (боты, звери, флаги, манекены) работает как раньше.
## Модель: сокеты-маркеры muzzle (дуло), ejection_port (окно выброса гильз),
## ads_anchor (точка совмещения прицела: при ADS встаёт в центр экрана на ads_distance
## перед камерой). Ищутся WeaponDef.socket(model, &"muzzle") — подходят и старые имена
## (Muzzle, Sight).

const SOCKETS := {
	&"muzzle": ["muzzle", "Muzzle"],
	&"ejection_port": ["ejection_port", "EjectionPort"],
	&"ads_anchor": ["ads_anchor", "AdsAnchor", "Sight"],
	&"mag": ["mag", "Mag"],
	&"forend": ["forend", "Forend"],
}

@export var id: StringName
@export var display_name := ""
@export var ammo_id: StringName = &""
## Патронов в магазине; chamber — ещё один в патроннике при тактической перезарядке (+1).
@export var mag_size := 15
@export var chamber := true
## Темп (выстр./мин) и режимы огня: &"semi", &"auto" (первый — по умолчанию).
@export var rpm := 450.0
@export var fire_modes: Array[StringName] = [&"semi"]
## Урон пули; полный до falloff_start м, линейно падает до falloff_min (доля) к falloff_end.
@export var damage := 22.0
@export var falloff_start := 12.0
@export var falloff_end := 40.0
@export var falloff_min := 0.55
@export var muzzle_velocity := 360.0
@export var gravity := 1.0
@export var max_range := 300.0
## Разброс, градусы (полный конус ≈ 2 сигмы).
@export var spread_hip := 2.4
@export var spread_ads := 0.35
@export var spread_move := 1.6        # на полной скорости бега
@export var spread_jump := 4.0        # в воздухе
@export var spread_crouch_mult := 0.8
@export var spread_per_shot := 0.45   # рост при стрельбе подряд
@export var spread_max := 3.5         # предел роста от очереди
@export var spread_recover := 6.0     # град/с — возврат после выстрелов
## Отдача: паттерн по номеру выстрела в очереди — Vector2(вбок°, вверх°); дальше — последний
## элемент. recoil_random — случайная добавка (°). В прицеле — × recoil_ads_mult.
@export var recoil_pattern: PackedVector2Array = PackedVector2Array([Vector2(0.0, 1.0)])
@export var recoil_random := 0.25
@export var recoil_ads_mult := 0.7
## Возврат прицела после очереди: задержка (с) и скорость (1/с, экспонента).
@export var recoil_recover_delay := 0.1
@export var recoil_recover := 7.0
## Пружина камеры (визуальный «пинок», не смещает прицел): импульс (°), жёсткость, затухание.
@export var camera_kick := 1.2
@export var spring_stiffness := 180.0
@export var spring_damping := 16.0
## Откат оружия в руках (м) и подброс (°) на выстрел.
@export var kick_back := 0.035
@export var kick_rot := 4.0
## Перезарядка, с: тактическая (патрон в патроннике) / полная (затвор на задержке).
@export var reload_tactical := 1.6
@export var reload_full := 2.2
## Прицеливание: на сколько градусов сужается FOV, время перехода, расстояние до ads_anchor.
@export var ads_fov := 12.0
@export var ads_time := 0.18
@export var ads_distance := 0.42
## Поза пистолета (одна рука) или длинноствола.
@export var pistol_pose := true
## Звуки (имена CombatFx.stream), высота тона.
@export var sound_shot := "pistol_shot"
@export var sound_pitch := 1.0
@export var sound_volume := 2.0
@export var sound_dry := "dry_click"
@export var sound_reload := "hit_metal"
@export var sound_mode := "dry_click"
## Каждый N-й выстрел — трассер (0 — никогда).
@export var tracer_every := 0
@export var tracer_color := Color(1.0, 0.55, 0.2)
## Вспышка у дула (размер), дым/газы, гильза (длина, радиус, м).
@export var flash_size := 0.6
@export var smoke := 0.6
@export var casing_len := 0.019
@export var casing_r := 0.0048

static var _defs: Dictionary = {}
static var _wcache: Dictionary = {}

static func has(wid: StringName) -> bool:
	_ensure()
	return _defs.has(wid)

static func of(wid: StringName) -> WeaponDef:
	_ensure()
	return _defs.get(wid) as WeaponDef

static func all() -> Array:
	_ensure()
	return _defs.values()

static func register(d: WeaponDef) -> void:
	_ensure()
	_defs[d.id] = d
	_wcache.erase(d.id)

## Сброс реестра (Combat._exit_tree — иначе ресурсы-описания «утекают» при закрытии игры).
static func clear_caches() -> void:
	_defs.clear()
	_wcache.clear()

static func _ensure() -> void:
	if not _defs.is_empty():
		return
	for d: WeaponDef in [_pistol_9mm(), _rifle()]:
		_defs[d.id] = d

## Поля для Combat.weapon(id) — поверх записи Combat.WEAPONS.
func to_weapon() -> Dictionary:
	return {
		"name": display_name, "type": &"gun", "damage": damage, "speed": muzzle_velocity, "gravity": gravity,
		"spread_hip": spread_hip, "spread_ads": spread_ads, "reload": reload_full, "cooldown": cooldown(),
		"mag": mag_size, "auto": fire_modes.has(&"auto"), "ammo": [{"id": ammo_id, "n": 1}], "kind": &"bullet",
		"range": falloff_end * 1.5, "zoom": ads_fov, "recoil": camera_kick, "sound": sound_shot, "flash": flash_size,
		"modern": true, "pistol": pistol_pose, "proj": &"bullet", "def": true,
	}

static func merged(wid: StringName, base: Dictionary) -> Dictionary:
	if _wcache.has(wid):
		return _wcache[wid]
	var d := of(wid)
	var w := base.duplicate()
	if d:
		w.merge(d.to_weapon(), true)
		for k: String in ["name"]:
			if base.has(k):
				w[k] = base[k]
	_wcache[wid] = w
	return w

func cooldown() -> float:
	return 60.0 / maxf(rpm, 1.0)

## Множитель урона на дистанции (м).
func falloff_at(dist: float) -> float:
	if dist <= falloff_start:
		return 1.0
	if dist >= falloff_end:
		return falloff_min
	return lerpf(1.0, falloff_min, (dist - falloff_start) / maxf(falloff_end - falloff_start, 0.01))

func damage_at(dist: float) -> float:
	return damage * falloff_at(dist)

## Отдача выстрела №i в очереди: Vector2(вбок°, вверх°).
func recoil_at(i: int) -> Vector2:
	if recoil_pattern.is_empty():
		return Vector2(0.0, 1.0)
	return recoil_pattern[clampi(i, 0, recoil_pattern.size() - 1)]

## Ёмкость при перезарядке: магазин (+1 в патроннике, если перезаряжаемся не «в ноль»).
func capacity(rounds_now: int) -> int:
	return mag_size + (1 if chamber and rounds_now > 0 else 0)

## Узел-сокет модели (muzzle / ejection_port / ads_anchor / mag / forend).
static func socket(model: Node, socket_name: StringName) -> Node3D:
	if model == null:
		return null
	for nm: String in SOCKETS.get(socket_name, [String(socket_name)]):
		var n := model.find_child(nm, true, false) as Node3D
		if n:
			return n
	return null

# ======================= оружие =======================

## Пистолет 9 мм (современный, полуавтомат, 15 патронов).
static func _pistol_9mm() -> WeaponDef:
	var d := WeaponDef.new()
	d.id = &"pistol_9mm"
	d.display_name = "Пистолет"
	d.ammo_id = &"ammo_9mm"
	d.mag_size = 15
	d.rpm = 420.0
	d.fire_modes = [&"semi"]
	d.damage = 22.0
	d.falloff_start = 12.0
	d.falloff_end = 45.0
	d.falloff_min = 0.55
	d.muzzle_velocity = 360.0
	d.spread_hip = 2.2
	d.spread_ads = 0.3
	d.spread_move = 1.4
	d.spread_jump = 4.0
	d.spread_per_shot = 0.55
	d.spread_max = 2.6
	d.spread_recover = 5.0
	d.recoil_pattern = PackedVector2Array([Vector2(0.1, 1.6), Vector2(-0.15, 1.7), Vector2(0.2, 1.8)])
	d.recoil_random = 0.35
	d.recoil_ads_mult = 0.75
	d.recoil_recover_delay = 0.08
	d.recoil_recover = 8.0
	d.camera_kick = 1.4
	d.spring_stiffness = 220.0
	d.spring_damping = 18.0
	d.kick_back = 0.03
	d.kick_rot = 9.0
	d.reload_tactical = 1.5
	d.reload_full = 2.0
	d.ads_fov = 10.0
	d.ads_time = 0.15
	d.ads_distance = 0.44
	d.pistol_pose = true
	d.sound_shot = "pistol_shot"
	d.sound_pitch = 1.22
	d.sound_volume = 0.0
	d.tracer_every = 0
	d.flash_size = 0.45
	d.smoke = 0.4
	d.casing_len = 0.019
	d.casing_r = 0.0048
	return d

## Автомат 7,62 (вымышленный, по мотивам АК): авто/одиночный (V), трассер каждый 4-й.
static func _rifle() -> WeaponDef:
	var d := WeaponDef.new()
	d.id = &"rifle"
	d.display_name = "Автомат"
	d.ammo_id = &"rifle_ammo"
	d.mag_size = 20
	d.rpm = 600.0
	d.fire_modes = [&"auto", &"semi"]
	d.damage = 24.0
	d.falloff_start = 50.0
	d.falloff_end = 150.0
	d.falloff_min = 0.7
	d.muzzle_velocity = 715.0
	d.max_range = 600.0
	d.spread_hip = 2.8
	d.spread_ads = 0.22
	d.spread_move = 2.2
	d.spread_jump = 5.0
	d.spread_per_shot = 0.32
	d.spread_max = 3.2
	d.spread_recover = 4.5
	# «семёрка»: первые выстрелы вверх, затем увод влево-вправо
	d.recoil_pattern = PackedVector2Array([Vector2(0.0, 0.9), Vector2(0.05, 1.0), Vector2(0.1, 1.05), Vector2(0.15, 1.0),
		Vector2(-0.2, 0.9), Vector2(-0.35, 0.8), Vector2(-0.45, 0.6), Vector2(-0.3, 0.5), Vector2(0.3, 0.45), Vector2(0.5, 0.4),
		Vector2(0.45, 0.35), Vector2(-0.4, 0.35)])
	d.recoil_random = 0.18
	d.recoil_ads_mult = 0.65
	d.recoil_recover_delay = 0.12
	d.recoil_recover = 6.0
	d.camera_kick = 0.9
	d.spring_stiffness = 260.0
	d.spring_damping = 20.0
	d.kick_back = 0.022
	d.kick_rot = 2.4
	d.reload_tactical = 2.3
	d.reload_full = 3.0
	d.ads_fov = 20.0
	d.ads_time = 0.24
	d.ads_distance = 0.45   # было 0.36: кисть на рукояти вплотную к глазу
	d.pistol_pose = false
	d.sound_shot = "pistol_shot"
	d.sound_pitch = 0.82
	d.sound_volume = 4.0
	d.tracer_every = 4
	d.flash_size = 0.7
	d.smoke = 0.8
	d.casing_len = 0.039
	d.casing_r = 0.0056
	return d
