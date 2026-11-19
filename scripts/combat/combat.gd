class_name Combat
extends Node
## Модуль COMBAT: оружие ближнего/дальнего боя, метательное, снаряды с физикой,
## зоны попадания, урон через apply_damage(amount, source, kind), поджог построек.
## Корень сцены scenes/combat/combat.tscn. Вешает CombatController на игроков
## (ЛКМ/ПКМ/R для оружия), регистрирует предметы и рецепты.
##
## API для ботов и модулей (статический, сцена модуля не обязательна):
##   Combat.WEAPONS[id]                       — таблица оружия (type/damage/ammo/…)
##   Combat.fire(shooter, id, origin, dir, opts={}) -> bool   — выстрел/бросок/удар
##   Combat.melee(attacker, id, dir=ZERO) -> Dictionary  — удар ближнего боя (dir — для ботов; пусто = взгляд)
##   Combat.throw_item(thrower, id, origin, dir, power=1.0) -> Node — бросок (копьё/молотов/динамит)
##   Combat.start_reload(shooter, id) -> float       — начать перезарядку (сек, 0 — нечем/не нужно)
##   Combat.is_loaded(shooter, id) / Combat.is_ready(shooter, id) / Combat.has_ammo(shooter, id)
##   Combat.explode(pos, radius, damage, source) — взрыв (динамит)
##   Combat.ignite_area(pos, radius, source, sec) — огненная зона (молотов)
##   Combat.hit_zone(target, pos) -> StringName  — &"head" ×2 / &"body" ×1 / &"legs" ×0.75
##   Combat.best_weapon(ch) -> StringName      — лучшее оружие из инвентаря (для ботов)
##   Combat.aim_dir(origin, target_pos, id)    — направление с упреждением на падение снаряда
##   Современный огнестрел (WeaponDef: pistol_9mm, rifle): Combat.capacity(ch, id),
##   Combat.fire_mode(ch, id) / Combat.cycle_fire_mode(ch, id); fire(opts.spread — разброс в °,
##   opts.muzzle_node — сокет дула для вспышки). Урон с падением по дистанции, трассеры.

signal hit_landed(info: Dictionary)

const ZONE_MULT := {&"head": 2.0, &"body": 1.0, &"legs": 0.75}

## type: melee | throw | bow | crossbow | gun
## ammo: [{id, n}] — расход на 1 выстрел (лук — стрела выбирается opts.ammo).
## SUPPLY: mag — магазин (патронов на перезарядку), auto — очередь (держать ЛКМ), pellets — дробь,
## proj — снаряд (по умолчанию musket_ball), bomb — бросок с фитилём (как динамит), modern — бездымный порох,
## pistol — поза пистолета.
const WEAPONS := {
	&"spear": {"name": "Копьё", "type": &"throw", "melee": true, "damage": 20.0, "reach": 2.8, "kind": &"melee",
		"throw_damage": 38.0, "speed": 24.0, "gravity": 1.0, "spread": 1.2, "cooldown": 0.9, "range": 30.0},
	&"club": {"name": "Дубина", "type": &"melee", "damage": 18.0, "reach": 2.3, "kind": &"melee", "cooldown": 0.65, "range": 2.3},
	&"axe_crude": {"name": "Каменный топор", "type": &"melee", "damage": 14.0, "reach": 2.2, "kind": &"axe", "cooldown": 0.62, "range": 2.2},
	&"axe_modern": {"name": "Топор", "type": &"melee", "damage": 22.0, "reach": 2.3, "kind": &"axe", "cooldown": 0.62, "range": 2.3},
	&"bow": {"name": "Лук", "type": &"bow", "damage": 34.0, "speed": 58.0, "gravity": 1.0, "spread_hip": 1.6, "spread_ads": 0.5,
		"draw": 0.85, "cooldown": 0.35, "ammo_types": [&"arrow", &"arrow_fire"], "kind": &"bullet", "range": 60.0, "zoom": 12.0},
	&"crossbow": {"name": "Арбалет", "type": &"crossbow", "damage": 52.0, "speed": 85.0, "gravity": 1.0, "spread_hip": 1.4, "spread_ads": 0.25,
		"reload": 3.2, "cooldown": 0.3, "ammo": [{"id": &"bolt", "n": 1}], "kind": &"bullet", "range": 90.0, "zoom": 22.0,
		"recoil": 2.0},
	&"musket": {"name": "Мушкет", "type": &"gun", "damage": 85.0, "speed": 320.0, "gravity": 1.0, "spread_hip": 3.2, "spread_ads": 0.35,
		"reload": 5.5, "cooldown": 0.4, "ammo": [{"id": &"musket_ball", "n": 1}, {"id": &"gunpowder", "n": 1}],
		"kind": &"bullet", "range": 220.0, "zoom": 26.0, "recoil": 7.0, "sound": "musket_shot", "flash": 1.0},
	&"pistol": {"name": "Пистоль", "type": &"gun", "damage": 48.0, "speed": 240.0, "gravity": 1.0, "spread_hip": 4.0, "spread_ads": 1.1,
		"reload": 3.6, "cooldown": 0.35, "ammo": [{"id": &"musket_ball", "n": 1}, {"id": &"gunpowder", "n": 1}],
		"kind": &"bullet", "range": 70.0, "zoom": 12.0, "recoil": 5.0, "sound": "pistol_shot", "flash": 0.6},
	&"molotov": {"name": "Коктейль Молотова", "type": &"throw", "damage": 6.0, "speed": 17.0, "gravity": 1.0, "spread": 1.5,
		"cooldown": 1.0, "kind": &"fire", "radius": 3.4, "burn_sec": 10.0, "range": 25.0},
	&"dynamite": {"name": "Динамит", "type": &"throw", "damage": 140.0, "speed": 15.0, "gravity": 1.0, "spread": 1.5,
		"cooldown": 1.0, "kind": &"explosion", "radius": 6.5, "fuse": 3.2, "range": 22.0},
	# --- SUPPLY: «посылки из внешнего мира» (только из ящиков спонсоров; модели — SupplyModels) ---
	&"rifle": {"name": "Автомат", "type": &"gun", "damage": 24.0, "speed": 420.0, "gravity": 1.0, "spread_hip": 2.6, "spread_ads": 0.7,
		"reload": 3.0, "cooldown": 0.11, "mag": 20, "auto": true, "ammo": [{"id": &"rifle_ammo", "n": 1}],
		"kind": &"bullet", "range": 160.0, "zoom": 20.0, "recoil": 1.3, "sound": "pistol_shot", "flash": 0.45, "modern": true},
	&"shotgun": {"name": "Дробовик", "type": &"gun", "damage": 11.0, "pellets": 8, "speed": 260.0, "gravity": 1.0, "spread_hip": 6.0,
		"spread_ads": 4.2, "reload": 4.2, "cooldown": 0.9, "mag": 4, "ammo": [{"id": &"shotgun_shell", "n": 1}],
		"kind": &"bullet", "range": 28.0, "zoom": 10.0, "recoil": 6.0, "sound": "musket_shot", "flash": 0.6, "modern": true},
	&"flare_gun": {"name": "Ракетница", "type": &"gun", "damage": 14.0, "speed": 62.0, "gravity": 0.55, "spread_hip": 2.0, "spread_ads": 1.0,
		"reload": 2.4, "cooldown": 0.5, "mag": 1, "ammo": [{"id": &"flare", "n": 1}], "proj": &"flare", "kind": &"fire",
		"range": 60.0, "zoom": 8.0, "recoil": 3.0, "sound": "pistol_shot", "flash": 0.4, "modern": true, "pistol": true},
	&"grenade": {"name": "Граната", "type": &"throw", "damage": 120.0, "speed": 16.0, "gravity": 1.0, "spread": 1.2,
		"cooldown": 1.0, "kind": &"explosion", "radius": 6.0, "fuse": 3.5, "range": 25.0, "bomb": true},
	&"machete": {"name": "Мачете", "type": &"melee", "damage": 26.0, "reach": 2.3, "kind": &"melee", "cooldown": 0.5, "range": 2.3},
	# современный пистолет 9 мм — остальные поля из WeaponDef (weapon_def.gd)
	&"pistol_9mm": {"name": "Пистолет", "type": &"gun", "pistol": true, "modern": true},
}

const AMMO := {
	&"arrow": {"damage": 1.0, "fire": false},
	&"arrow_fire": {"damage": 0.85, "fire": true},
	&"bolt": {"damage": 1.0, "fire": false},
	&"musket_ball": {"damage": 1.0, "fire": false},
	&"flare": {"damage": 1.0, "fire": true},
}

## Последние попадания (для тестов/отладки/HUD), не больше 32.
static var last_hits: Array[Dictionary] = []
## Последний выстрел современного оружия (WeaponDef): {shooter, weapon, origin, aim, dir, spread, tracer}.
static var last_shot: Dictionary = {}
static var _state: Dictionary = {} # instance_id -> {loaded:{}, busy_until, reloading}
static var _registered := false

func _ready() -> void:
	add_to_group(&"combat_module")
	Combat.register_items()
	_ensure_actions()
	for p in get_tree().get_nodes_in_group(&"player"):
		_attach(p)
	Events.character_spawned.connect(_on_spawned)

static func instance() -> Combat:
	var t := Engine.get_main_loop() as SceneTree
	return t.get_first_node_in_group(&"combat_module") as Combat if t else null

func _ensure_actions() -> void:
	if not InputMap.has_action(&"reload"):
		InputMap.add_action(&"reload")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_R
		InputMap.action_add_event(&"reload", ev)
	if not InputMap.has_action(&"fire_mode"):
		InputMap.add_action(&"fire_mode")
		var ev2 := InputEventKey.new()
		ev2.physical_keycode = KEY_V
		InputMap.action_add_event(&"fire_mode", ev2)

func _on_spawned(ch: Node) -> void:
	if ch.is_in_group(&"player"):
		_attach(ch)

func _attach(p: Node) -> void:
	if p.get_node_or_null(^"CombatController") == null:
		var c := CombatController.new()
		c.name = "CombatController"
		p.add_child(c)

# ======================= предметы и рецепты =======================

static func register_items() -> void:
	if _registered:
		return
	_registered = true
	CombatItems.register()

# ======================= API =======================

static func weapon(id: StringName) -> Dictionary:
	if WeaponDef.has(id):
		return WeaponDef.merged(id, WEAPONS.get(id, {}))
	return WEAPONS.get(id, {})

## Ёмкость оружия при перезарядке (у WeaponDef — магазин +1 в патроннике при тактической).
static func capacity(ch: Object, id: StringName) -> int:
	var d := WeaponDef.of(id)
	if d:
		return d.capacity(rounds(ch, id))
	return int(weapon(id).get("mag", 1))

## Режим огня (&"auto"/&"semi") современного оружия; у остального — по полю auto.
static func fire_mode(ch: Object, id: StringName) -> StringName:
	var d := WeaponDef.of(id)
	if d == null:
		return &"auto" if weapon(id).get("auto", false) else &"semi"
	var m: StringName = (state(ch).get("modes", {}) as Dictionary).get(id, d.fire_modes[0])
	return m

## Следующий режим огня (V). Возвращает новый режим.
static func cycle_fire_mode(ch: Object, id: StringName) -> StringName:
	var d := WeaponDef.of(id)
	if d == null or d.fire_modes.size() < 2:
		return fire_mode(ch, id)
	var st := state(ch)
	if not st.has("modes"):
		st["modes"] = {}
	var i := d.fire_modes.find(fire_mode(ch, id))
	var m: StringName = d.fire_modes[(i + 1) % d.fire_modes.size()]
	st.modes[id] = m
	return m

static func is_weapon(id: StringName) -> bool:
	return WEAPONS.has(id)

static func is_ranged(id: StringName) -> bool:
	var w := weapon(id)
	return not w.is_empty() and w.type != &"melee"

## Игровое время (учитывает паузу, time_scale и просадки FPS). Без модуля в сцене — по кадрам физики.
static var _clock := 0.0
static var _has_clock := false

static func _now() -> float:
	if _has_clock:
		return _clock
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)

func _physics_process(delta: float) -> void:
	if not _has_clock:
		_clock = _now()
		_has_clock = true
	_clock += delta

func _exit_tree() -> void:
	_has_clock = false
	last_hits.clear()
	last_shot = {}
	_state.clear()
	CombatFx.clear_caches()
	CombatModels.clear_caches()
	GunFx.clear_caches()
	WeaponDef.clear_caches()

static func state(ch: Object) -> Dictionary:
	var k := ch.get_instance_id() if ch else 0
	if not _state.has(k):
		_state[k] = {"loaded": {}, "busy_until": 0.0, "reloading": &"", "reload_end": 0.0}
	return _state[k]

static func is_loaded(ch: Object, id: StringName) -> bool:
	var w := weapon(id)
	if w.is_empty():
		return false
	if not w.type in [&"gun", &"crossbow"]:
		return true
	var st := state(ch)
	return rounds(ch, id) > 0 and not (st.reloading == id and _now() < float(st.reload_end))

## Патронов в оружии (магазин; у однозарядных — 0/1).
static func rounds(ch: Object, id: StringName) -> int:
	var v: Variant = state(ch).loaded.get(id, false)
	if v is bool:
		return 1 if v else 0
	return int(v)

## Можно ли сейчас перезарядиться (магазин не полон, есть патроны, не заняты).
static func can_reload(ch: Object, id: StringName) -> bool:
	var w := weapon(id)
	if w.is_empty() or not w.type in [&"gun", &"crossbow"]:
		return false
	var st := state(ch)
	return rounds(ch, id) < capacity(ch, id) and not is_reloading(ch) and _now() >= float(st.busy_until) and has_ammo(ch, id)

static func is_ready(ch: Object, id: StringName) -> bool:
	return _now() >= float(state(ch).busy_until)

static func is_reloading(ch: Object) -> bool:
	var st := state(ch)
	return st.reloading != &"" and _now() < float(st.reload_end)

## Сколько выстрелов есть в запасе (без учёта заряженного). -1 — без инвентаря (боты без инвентаря — бесконечно).
static func ammo_count(ch: Object, id: StringName, ammo_id: StringName = &"") -> int:
	var w := weapon(id)
	var inv := _inv(ch)
	if inv == null:
		return -1
	match w.get("type", &""):
		&"bow":
			if ammo_id != &"":
				return int(inv.call(&"count", ammo_id))
			var n := 0
			for a: StringName in w.ammo_types:
				n += int(inv.call(&"count", a))
			return n
		&"gun", &"crossbow":
			var m := 1 << 30
			for a: Dictionary in w.ammo:
				m = mini(m, int(inv.call(&"count", a.id)) / int(a.n))
			return m
		&"throw":
			return int(inv.call(&"count", id))
	return -1

static func has_ammo(ch: Object, id: StringName, ammo_id: StringName = &"") -> bool:
	var c := ammo_count(ch, id, ammo_id)
	return c != 0

static func _inv(ch: Object) -> Object:
	if ch == null:
		return null
	var inv: Variant = ch.get(&"inventory")
	if inv is Object and (inv as Object).has_method(&"count"):
		return inv as Object
	return null

static func _take(ch: Object, id: StringName, n: int) -> bool:
	var inv := _inv(ch)
	if inv == null:
		return true
	if int(inv.call(&"count", id)) < n:
		return false
	inv.call(&"remove", id, n)
	return true

## Перезарядка (мушкет/пистоль/арбалет): тратит порох+пулю (или болт) из инвентаря.
## Возвращает время перезарядки, 0 — нечем или уже заряжено.
static func start_reload(ch: Object, id: StringName) -> float:
	var w := weapon(id)
	if w.is_empty() or not w.type in [&"gun", &"crossbow"]:
		return 0.0
	var st := state(ch)
	var have := rounds(ch, id)
	var cap := capacity(ch, id)
	if have >= cap or is_reloading(ch) or _now() < float(st.busy_until):
		return 0.0
	if not has_ammo(ch, id):
		return 0.0
	var n := 1
	if w.has("mag"):
		var avail := ammo_count(ch, id)
		n = cap - have if avail < 0 else mini(cap - have, avail)
	for a: Dictionary in w.ammo:
		_take(ch, a.id, int(a.n) * n)
	var t := float(w.reload)
	var d := WeaponDef.of(id)
	if d:
		# тактическая (патрон в патроннике) — быстрее полной (затвор на задержке)
		t = d.reload_tactical if have > 0 else d.reload_full
	st.reload_full = have <= 0
	st.loaded[id] = (have + n) if w.has("mag") else true
	st.reload_n = n
	st.reloading = id
	st.reload_end = _now() + t
	st.busy_until = _now() + t
	return t

## Отменить перезарядку (сменили оружие): заряд не теряется только если успели.
static func cancel_reload(ch: Object) -> void:
	var st := state(ch)
	if st.reloading != &"" and _now() < float(st.reload_end):
		var id: StringName = st.reloading
		var n := int(st.get("reload_n", 1))
		if weapon(id).has("mag"):
			st.loaded[id] = maxi(0, rounds(ch, id) - n)
		else:
			st.loaded[id] = false
		# порох и пуля (патроны) возвращаются
		var inv := _inv(ch)
		if inv:
			for a: Dictionary in weapon(id).ammo:
				inv.call(&"add", a.id, int(a.n) * n)
		st.busy_until = _now()
	st.reloading = &""

## Выстрел/бросок/удар. origin/dir — из глаз стрелка. opts: ads(bool), power(0..1, лук/бросок),
## ammo (лук: &"arrow"/&"arrow_fire"). Для огнестрела/арбалета без заряда — начинает перезарядку и
## возвращает false (боты просто вызывают fire повторно).
static func fire(shooter: Node, weapon_id: StringName, origin: Vector3, dir: Vector3, opts: Dictionary = {}) -> bool:
	var w := weapon(weapon_id)
	if w.is_empty() or shooter == null:
		return false
	register_items()
	var st := state(shooter)
	if _now() < float(st.busy_until):
		return false
	dir = dir.normalized()
	match w.type:
		&"melee":
			melee(shooter, weapon_id, dir)
			return true
		&"throw":
			if bool(opts.get("melee", false)) and w.get("melee", false):
				melee(shooter, weapon_id, dir)
				return true
			return throw_item(shooter, weapon_id, origin, dir, float(opts.get("power", 1.0))) != null
	var power := clampf(float(opts.get("power", 1.0)), 0.15, 1.0)
	var ammo_id: StringName = &""
	match w.type:
		&"bow":
			ammo_id = StringName(opts.get("ammo", &""))
			if ammo_id == &"" or ammo_count(shooter, weapon_id, ammo_id) == 0:
				ammo_id = &""
				for a: StringName in w.ammo_types:
					if ammo_count(shooter, weapon_id, a) != 0:
						ammo_id = a
						break
			if ammo_id == &"":
				CombatFx.sound_at(shooter, "dry_click", origin, -6.0)
				return false
			_take(shooter, ammo_id, 1)
		&"gun", &"crossbow":
			if not is_loaded(shooter, weapon_id):
				if rounds(shooter, weapon_id) <= 0:
					if start_reload(shooter, weapon_id) <= 0.0:
						CombatFx.sound_at(shooter, "dry_click", origin, -6.0)
				return false
			if w.has("mag"):
				st.loaded[weapon_id] = rounds(shooter, weapon_id) - 1
			else:
				st.loaded[weapon_id] = false
			ammo_id = &"bolt" if w.type == &"crossbow" else StringName(w.get("proj", &"musket_ball"))
	var base_t := _now()
	if WeaponDef.has(weapon_id) and float(st.busy_until) > _now() - float(w.cooldown):
		base_t = float(st.busy_until) # непрерывный огонь: ровный темп, не зависящий от FPS
	st.busy_until = base_t + float(w.cooldown)
	var spread := float(w.get("spread_ads" if bool(opts.get("ads", false)) else "spread_hip", 1.0))
	if opts.has("spread"):
		spread = float(opts.spread) # игрок: разброс с учётом движения/очереди/прицела (CombatController)
	if w.type == &"bow":
		spread *= lerpf(2.2, 1.0, power)
	var d := _spread_dir(dir, spread)
	var wd := WeaponDef.of(weapon_id)
	var tracer := false
	if wd:
		var sn: Dictionary = st.get("shot_n", {})
		st["shot_n"] = sn
		sn[weapon_id] = int(sn.get(weapon_id, 0)) + 1
		tracer = wd.tracer_every > 0 and int(sn[weapon_id]) % wd.tracer_every == 0
		last_shot = {"shooter": shooter, "weapon": weapon_id, "origin": origin, "aim": dir, "dir": d, "spread": spread,
			"tracer": tracer, "time": _now()}
	var ad: Dictionary = AMMO.get(ammo_id, {})
	for k in int(w.get("pellets", 1)):
		var pd := d if k == 0 else _spread_dir(dir, spread)
		var pr := CombatProjectile.new()
		pr.shooter = shooter
		pr.weapon_id = weapon_id
		pr.ammo_id = ammo_id
		pr.damage = float(w.damage) * float(ad.get("damage", 1.0)) * (lerpf(0.35, 1.0, power) if w.type == &"bow" else 1.0)
		pr.kind = w.kind
		pr.on_fire = bool(ad.get("fire", false))
		pr.velocity = pd * float(w.speed) * (lerpf(0.45, 1.0, power) if w.type == &"bow" else 1.0)
		pr.gravity_scale = float(w.gravity)
		pr.max_range = float(w.range) * 3.0
		if wd:
			pr.wdef = wd
			pr.tracer = tracer and k == 0
			pr.max_range = wd.max_range
		_root(shooter).add_child(pr)
		pr.global_position = origin
	var mpos: Vector3 = opts.get("muzzle", origin + d * 0.9)
	match w.type:
		&"gun":
			if wd:
				GunFx.shot(shooter, mpos, d, wd, opts.get("muzzle_node") as Node3D)
			elif w.get("modern", false):
				CombatFx.muzzle_modern(shooter, mpos, d, float(w.flash))
			else:
				CombatFx.muzzle(shooter, mpos, d, float(w.flash))
			if not wd:
				CombatFx.sound_at(shooter, String(w.sound), origin, 4.0, 220.0)
				CombatFx.sound_at(shooter, "flint_click", origin, -8.0)
		&"crossbow":
			CombatFx.sound_at(shooter, "crossbow_shot", origin, -2.0)
		&"bow":
			CombatFx.sound_at(shooter, "bow_release", origin, -2.0)
	return true

static func _spread_dir(dir: Vector3, deg: float) -> Vector3:
	if deg <= 0.0:
		return dir
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(dir).normalized()
	# нормальное распределение, sigma = deg/2
	var a := randfn(0.0, 0.5) * deg_to_rad(deg)
	var b := randfn(0.0, 0.5) * deg_to_rad(deg)
	return (dir + side * tan(a) + up * tan(b)).normalized()

static func _root(n: Node) -> Node:
	var t := n.get_tree()
	var cs := t.current_scene if t else null
	if cs:
		return cs
	return n.get_parent()

## Удар ближнего боя (для ботов; игрок бьёт своей анимацией). Возвращает hit-словарь.
static func melee(attacker: Node, weapon_id: StringName, dir: Vector3 = Vector3.ZERO) -> Dictionary:
	var w := weapon(weapon_id)
	if w.is_empty():
		w = {"damage": 6.0, "reach": 2.0, "kind": &"melee", "cooldown": 0.5}
	var st := state(attacker)
	if _now() < float(st.busy_until):
		return {}
	st.busy_until = _now() + float(w.get("cooldown", 0.6))
	var a3 := attacker as Node3D
	if a3 == null:
		return {}
	var from := eye_of(a3)
	# бот может передать направление удара явно (иначе — взгляд/−Z узла)
	var look := dir.normalized() if dir.length_squared() > 0.0001 else look_of(a3)
	var to := from + look * float(w.get("reach", 2.2))
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = true
	if attacker is CollisionObject3D:
		q.exclude = [(attacker as CollisionObject3D).get_rid()]
	var hit := a3.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		# узкий «конус» — сфера на конце
		var sp := PhysicsShapeQueryParameters3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.45
		sp.shape = sh
		sp.transform = Transform3D(Basis(), from + look * float(w.get("reach", 2.2)) * 0.75)
		sp.exclude = q.exclude
		var res := a3.get_world_3d().direct_space_state.intersect_shape(sp, 4)
		for r in res:
			if _find_with(r.collider as Node, &"apply_damage"):
				hit = {"collider": r.collider, "position": sp.transform.origin, "normal": -look}
				break
	if hit.is_empty():
		return {"miss": true}
	var tool := PlayerItems.tool_of(weapon_id)
	hit["tool"] = tool
	hit["damage"] = float(w.damage)
	hit["item"] = weapon_id
	deliver(attacker, hit.collider as Node, hit.position, hit.get("normal", Vector3.UP), float(w.damage), StringName(w.kind), weapon_id, true)
	return hit

## Бросок предмета: копьё (возвращается подбором), молотов, динамит, а также любой предмет (камень).
static func throw_item(thrower: Node, id: StringName, origin: Vector3, dir: Vector3, power: float = 1.0) -> Node:
	if thrower == null:
		return null
	register_items()
	var w := weapon(id)
	var st := state(thrower)
	if _now() < float(st.busy_until):
		return null
	if not _take(thrower, id, 1):
		return null
	st.busy_until = _now() + float(w.get("cooldown", 0.8))
	power = clampf(power, 0.2, 1.0)
	var d := _spread_dir(dir.normalized(), float(w.get("spread", 2.0)))
	var speed := float(w.get("speed", 14.0)) * lerpf(0.45, 1.0, power)
	var v := d * speed
	if thrower is CharacterBody3D:
		v += (thrower as CharacterBody3D).velocity * 0.6
	var root := _root(thrower)
	CombatFx.sound_at(thrower, "swoosh", origin, -4.0)
	if id == &"dynamite" or w.get("bomb", false):
		var b := CombatBomb.new()
		b.model_id = id
		b.thrower = thrower
		b.fuse = float(w.fuse)
		b.radius = float(w.radius)
		b.damage = float(w.damage)
		root.add_child(b)
		b.global_position = origin + d * 0.4
		b.linear_velocity = v
		b.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-6, 6))
		return b
	var pr := CombatProjectile.new()
	pr.shooter = thrower
	pr.weapon_id = id
	pr.ammo_id = id
	pr.velocity = v
	pr.gravity_scale = 1.0
	pr.thrown = true
	match id:
		&"molotov":
			pr.damage = float(w.damage)
			pr.kind = &"fire"
			pr.on_fire = true
			pr.spin = true
		&"spear":
			pr.damage = float(w.throw_damage) * lerpf(0.6, 1.0, power)
			pr.kind = &"melee"
		_:
			pr.damage = 4.0 + 4.0 * power
			pr.kind = &"melee"
			pr.spin = true
	root.add_child(pr)
	pr.global_position = origin + d * 0.3
	return pr

## Направление выстрела по цели с поправкой на падение (для ботов).
static func aim_dir(origin: Vector3, target: Vector3, weapon_id: StringName) -> Vector3:
	var w := weapon(weapon_id)
	var speed := float(w.get("speed", 0.0))
	var d := target - origin
	if speed <= 0.0:
		return d.normalized()
	var g := 9.8 * float(w.get("gravity", 1.0))
	var flat := Vector2(d.x, d.z).length()
	var t := flat / speed
	d.y += 0.5 * g * t * t
	return d.normalized()

## Лучшее оружие из инвентаря (для ботов): дальнобойное с боезапасом, иначе ближнее.
static func best_weapon(ch: Object, prefer_ranged: bool = true) -> StringName:
	var inv := _inv(ch)
	if inv == null:
		return &""
	var order: Array[StringName] = [&"rifle", &"shotgun", &"musket", &"crossbow", &"bow", &"pistol_9mm", &"pistol", &"spear", &"machete", &"axe_modern", &"club", &"axe_crude"] if prefer_ranged \
		else [&"machete", &"axe_modern", &"spear", &"club", &"axe_crude", &"shotgun", &"rifle", &"pistol_9mm", &"musket", &"crossbow", &"pistol", &"bow"]
	for id in order:
		if int(inv.call(&"count", id)) <= 0:
			continue
		var w := weapon(id)
		if w.type in [&"gun", &"crossbow", &"bow"] and not (is_loaded(ch, id) and rounds(ch, id) > 0) and not has_ammo(ch, id):
			continue
		return id
	return &""

# ======================= попадания =======================

static func _find_with(n: Node, method: StringName) -> Node:
	var cur := n
	for i in 7:
		if cur == null:
			return null
		if cur.has_method(method):
			return cur
		cur = cur.get_parent()
	return null

static func eye_of(n: Node3D) -> Vector3:
	if n.has_method(&"get_eye_position"):
		return n.call(&"get_eye_position") as Vector3
	return n.global_position + Vector3.UP * 1.6

static func look_of(n: Node3D) -> Vector3:
	if n.has_method(&"get_look_dir"):
		return (n.call(&"get_look_dir") as Vector3).normalized()
	return -n.global_basis.z

## Зона попадания по высоте точки на теле: голова (выше подбородка) ×2, ноги (ниже паха) ×0.75.
static func hit_zone(target: Node, pos: Vector3) -> StringName:
	if not (target is Node3D):
		return &"body"
	var t3 := target as Node3D
	if target.has_method(&"hit_zone"):
		return target.call(&"hit_zone", pos) as StringName
	if not target.is_in_group(&"characters"):
		# звери: голова — передняя часть туловища
		if target.is_in_group(&"animals") or target.is_in_group(&"sharks"):
			var fwd := -t3.global_basis.z
			var rel := pos - t3.global_position
			return &"head" if rel.dot(fwd) > 0.55 else &"body"
		return &"body"
	var feet := t3.global_position.y
	var eye := eye_of(t3).y
	if pos.y > eye - 0.16:
		return &"head"
	var top := eye + 0.12
	if pos.y < feet + (top - feet) * 0.47:
		return &"legs"
	return &"body"

## Нанести урон цели попадания. Возвращает фактический урон (0 — не по живому/постройке).
static func deliver(source: Node, collider: Node, pos: Vector3, normal: Vector3, dmg: float, kind: StringName,
		weapon_id: StringName, melee_hit: bool = false, on_fire: bool = false) -> float:
	if collider == null:
		return 0.0
	var target := _find_with(collider, &"apply_damage")
	var info := {"target": target, "collider": collider, "position": pos, "normal": normal, "weapon": weapon_id,
		"kind": kind, "zone": &"", "damage": 0.0, "source": source, "time": _now()}
	if target == null:
		var oh := _find_with(collider, &"on_hit")
		if oh and melee_hit:
			oh.call(&"on_hit", source, {"position": pos, "normal": normal, "tool": PlayerItems.tool_of(weapon_id), "damage": dmg, "item": weapon_id})
		_record(info)
		return 0.0
	if target == source:
		return 0.0
	var amount := dmg
	if target.is_in_group(&"buildable"):
		info.zone = &"structure"
		if on_fire and target.has_method(&"ignite"):
			target.call(&"ignite", source)
	else:
		var z := hit_zone(target, pos)
		info.zone = z
		amount *= float(ZONE_MULT.get(z, 1.0))
		if on_fire and target.has_method(&"ignite"):
			target.call(&"ignite", source)
	info.damage = amount
	target.call(&"apply_damage", amount, source, kind)
	_record(info)
	return amount

static func _record(info: Dictionary) -> void:
	last_hits.append(info)
	if last_hits.size() > 32:
		last_hits.pop_front()
	var m := instance()
	if m:
		m.hit_landed.emit(info)
	var src: Variant = info.get("source")
	if src is Node and is_instance_valid(src) and (src as Node).has_node(^"CombatController") and info.target != null:
		((src as Node).get_node(^"CombatController") as CombatController).hit_marker(info)

# ======================= огонь и взрывы =======================

## Огненная зона (молотов): поджигает постройки (мосты!), жжёт живых.
static func ignite_area(pos: Vector3, radius: float, source: Node, sec: float = 10.0, parent: Node = null) -> Node3D:
	var t := Engine.get_main_loop() as SceneTree
	if t == null:
		return null
	var fz := CombatFireZone.new()
	fz.radius = radius
	fz.duration = sec
	fz.source = source
	var host: Node = parent if parent else (t.current_scene if t.current_scene else t.root)
	# позиция до add_child: _ready зоны по ней решает «на воде или на суше» (BUILD+ фикс:
	# иначе зона на суше считалась плавающей и опускалась к воде)
	var host3 := host as Node3D
	fz.position = host3.global_transform.affine_inverse() * pos if host3 and host3.is_inside_tree() else pos
	host.add_child(fz)
	fz.global_position = pos
	return fz

## Взрыв: урон с затуханием по расстоянию, импульс телам, постройкам — kind &"explosion".
static func explode(pos: Vector3, radius: float, damage: float, source: Node) -> void:
	var t := Engine.get_main_loop() as SceneTree
	if t == null:
		return
	CombatFx.explosion(pos, radius)
	var seen := {}
	for g: StringName in [&"characters", &"animals", &"sharks", &"buildable", &"player"]:
		for n in t.get_nodes_in_group(g):
			if seen.has(n) or not (n is Node3D) or not n.has_method(&"apply_damage"):
				continue
			seen[n] = true
			var n3 := n as Node3D
			var c := n3.global_position + (Vector3.UP * 0.9 if g != &"buildable" else Vector3.ZERO)
			var dist := c.distance_to(pos)
			if g == &"buildable" and n3.has_method(&"get_aabb_world"):
				pass
			if dist > radius:
				continue
			var k := 1.0 - dist / radius
			var amount := damage * (0.2 + 0.8 * k * k)
			n.call(&"apply_damage", amount, source, &"explosion")
			_record({"target": n, "collider": n, "position": c, "normal": (c - pos).normalized(), "weapon": &"dynamite",
				"kind": &"explosion", "zone": &"blast", "damage": amount, "source": source, "time": _now()})
			if n is CharacterBody3D:
				(n as CharacterBody3D).velocity += ((c - pos).normalized() + Vector3.UP * 0.6) * 9.0 * k
	# физические тела
	var space := (t.current_scene as Node3D).get_world_3d().direct_space_state if t.current_scene is Node3D else null
	if space:
		var sp := PhysicsShapeQueryParameters3D.new()
		var sh := SphereShape3D.new()
		sh.radius = radius
		sp.shape = sh
		sp.transform = Transform3D(Basis(), pos)
		for r in space.intersect_shape(sp, 32):
			var b := r.collider as RigidBody3D
			if b:
				var dv := b.global_position - pos
				var k2 := 1.0 - clampf(dv.length() / radius, 0.0, 1.0)
				b.apply_central_impulse((dv.normalized() + Vector3.UP * 0.5) * b.mass * 12.0 * k2)
	for p in t.get_nodes_in_group(&"player"):
		var cc := (p as Node).get_node_or_null(^"CombatController") as CombatController
		if cc:
			var dd := (p as Node3D).global_position.distance_to(pos)
			cc.shake(clampf(1.6 - dd / 30.0, 0.0, 1.2))
