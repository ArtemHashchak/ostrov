class_name Survival
extends Node3D
## Модуль SURVIVAL: вода (пресная/морская), тара, кипячение, опреснитель, дождевая
## бочка/тент, кокосы, порча еды (свежесть в слоте), копчение, костёр-готовка, огород,
## травы/припарка (яд), мусорный берег (обломки после штормов), рецепты, API ботам.
##
## Подключение: match.gd сам грузит scenes/survival/survival.tscn в слот "Survival".
## Хуки игрока (точечные правки player.gd): on_use_item, on_drink_water, on_consumed.
## Всё время модуля масштабируется Survival.speed (тесты ускоряют рост/порчу).

const TICK := 0.25
const FRESH_TICK := 1.0
const SALT_TIME := 60.0          # сек «солевой жажды» за глоток морской воды
const SALT_DRAIN := 0.35         # доп. жажда/с при солевом эффекте (≈ −21 за минуту)
const NAUSEA_TIME := 40.0
const STALE := 0.35              # свежесть ниже — риск расстройства
const DEBRIS_PER_BEACH := 5
const DEBRIS_MAX_PER_BEACH := 12
const DEBRIS_WEIGHTS := {&"barrel": 2.0, &"crate": 2.5, &"bottles": 2.0, &"net": 1.5, &"scrap": 1.5}
const CRACK_TOOLS := [&"knife", &"axe_crude", &"axe_modern", &"rock", &"stone", &"glass_shard", &"spear"]
const KIT_RADIUS := {&"campfire": 0.7, &"smoker": 0.9, &"still": 0.7, &"rain_barrel": 0.4, &"tarp": 1.1, &"garden": 1.0}

static var _inst: Survival = null
## Множитель времени модуля (1 — реальное время матча).
static var speed := 1.0
## Принудительный дождь 0..1 (тесты, сцены без неба); <0 — брать у мира.
static var rain_override := -1.0

@export var seed: int = 7
@export var spawn_debris := true
@export var spawn_wild := true

var world: Node = null
var _height_src: Node = null
## ch -> {salt: сек, nausea: сек, pdmg: накоплено урона ядом}
var effects: Dictionary = {}
var beaches: Array[Dictionary] = [] # {pos: Vector3, out: Vector3, tan: Vector3, island}
var structures: Node3D
var _acc := 0.0
var _facc := 0.0
var _last_weather: StringName = &""
var _ghost: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var populated := false

signal populated_done

static func instance() -> Survival:
	return _inst if is_instance_valid(_inst) else null

func _enter_tree() -> void:
	_inst = self

func _exit_tree() -> void:
	if _inst == self:
		_inst = null
		SurvivalModels.clear_cache()
		StaticBatch.clear_cache()

func _ready() -> void:
	name = "Survival"
	add_to_group(&"survival")
	_rng.seed = seed
	SurvivalItems.register()
	structures = Node3D.new()
	structures.name = "Structures"
	add_child(structures)
	world = get_tree().get_first_node_in_group(&"world")
	if world == null or not world.has_method(&"height_at"):
		world = null
		_height_src = _find_height_source()
	elif world.get(&"is_ready") == false and world.has_signal(&"world_ready"):
		await world.world_ready
	if not Events.structure_completed.is_connected(_on_structure_completed):
		Events.structure_completed.connect(_on_structure_completed)
	_make_ghost()
	call_deferred(&"populate")

func _find_height_source() -> Node:
	var n: Node = get_parent()
	while n:
		if n.has_method(&"height_at"):
			return n
		n = n.get_parent()
	for c in get_tree().root.get_children():
		if c.has_method(&"height_at"):
			return c
	return get_tree().current_scene

# ======================================================== мир

static func world_node() -> Node:
	var s := instance()
	return s.world if s else null

func h(x: float, z: float) -> float:
	if world:
		return float(world.call(&"height_at", x, z))
	if _height_src and _height_src.has_method(&"height_at"):
		return float(_height_src.call(&"height_at", x, z))
	return 0.0

func wl() -> float:
	if world and world.has_method(&"water_level"):
		return float(world.call(&"water_level"))
	return 0.0

func slope(x: float, z: float) -> float:
	return absf(h(x + 0.7, z) - h(x - 0.7, z)) + absf(h(x, z + 0.7) - h(x, z - 0.7))

func biome(x: float, z: float) -> StringName:
	if world and world.has_method(&"biome_at"):
		return StringName(world.call(&"biome_at", x, z))
	var y := h(x, z)
	if y <= wl() + 0.2:
		return &"water"
	return &"beach" if y < 1.6 else &"jungle"

func islands() -> Array:
	if world and world.has_method(&"islands"):
		return world.call(&"islands")
	var r := 55.0
	if _height_src and _height_src.get(&"ISLAND_R") != null:
		r = float(_height_src.get(&"ISLAND_R"))
	return [{"id": 0, "kind": &"shared", "team": -1, "center": Vector2.ZERO, "radius": r}]

## Сила дождя 0..1.
static func rain() -> float:
	if rain_override >= 0.0:
		return rain_override
	var w := world_node()
	if w and w.has_method(&"rain_factor"):
		return clampf(float(w.call(&"rain_factor")), 0.0, 1.0)
	return 0.0

func weather() -> StringName:
	if world and world.has_method(&"weather"):
		return StringName(world.call(&"weather"))
	return &"storm" if rain_override >= 0.8 else &"clear"

## Пресная ли вода в точке (озёра/родники). WORLD: fresh_water_at(pos) -> bool.
func is_fresh_at(p: Vector3) -> bool:
	# v5.2: отравленный родник (событие) — вода не годится (набрать — только прокипятить; пить — яд)
	if SeasonEvents.is_poisoned(p):
		return false
	if world and world.has_method(&"fresh_water_at"):
		return bool(world.call(&"fresh_water_at", p))
	for s in get_tree().get_nodes_in_group(&"sv_fresh"):
		var s3 := s as Node3D
		if s3 and Vector2(s3.global_position.x - p.x, s3.global_position.z - p.z).length() < 2.6:
			return true
	return false

# ======================================================== инвентарь (статика)

static func data(id: StringName) -> Dictionary:
	if id == &"":
		return {}
	var d := Items.get_item(id)
	return d.data if d else {}

static func inv(ch: Node) -> Inventory:
	if ch == null:
		return null
	return ch.get_node_or_null(^"Inventory") as Inventory

static func held(ch: Node) -> StringName:
	if ch == null:
		return &""
	if ch.has_method(&"held_item"):
		return StringName(ch.call(&"held_item"))
	var i := inv(ch)
	return i.selected_id() if i else &""

static func count(ch: Node, id: StringName) -> int:
	var i := inv(ch)
	return i.count(id) if i else 0

static func take(ch: Node, id: StringName, n: int = 1) -> bool:
	var i := inv(ch)
	return i != null and i.remove(id, n)

## Дать предмет; не влезло — выпадает на землю (ItemPickup) у точки at/персонажа.
static func give(ch: Node, id: StringName, n: int, at: Variant = null) -> void:
	if n <= 0 or id == &"":
		return
	var left := n
	var i := inv(ch)
	if i:
		left = i.add(id, n)
	if left > 0:
		var pos: Vector3 = at if at is Vector3 else ((ch as Node3D).global_position + Vector3.UP if ch is Node3D else Vector3.ZERO)
		var s := instance()
		var parent: Node = s.get_parent() if s and s.get_parent() else (ch.get_parent() if ch else null)
		if parent:
			var arr: Array[Dictionary] = [{"id": id, "n": left}]
			ItemPickup.spawn(parent, pos, arr)
	if n - left > 0:
		toast(ch, "+%d %s" % [n - left, Items.item_name(id)])

static func toast(ch: Node, text: String) -> void:
	if ch and ch.is_in_group(&"player"):
		Events.toast.emit(text)

static func sfx(pos: Vector3, path: String) -> void:
	var s := instance()
	if s == null or not ResourceLoader.exists(path) or DisplayServer.get_name() == "headless":
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = load(path) as AudioStream
	p.unit_size = 4.0
	s.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()

# ======================================================== хуки игрока

## ПКМ с предметом. true — Survival обработал (игрок дальше не ест).
func on_use_item(ch: Node, id: StringName) -> bool:
	var dd := data(id)
	if dd.has("kit"):
		place_from_view(ch, StringName(dd.kit), id)
		return true
	if dd.has("big_container"):
		# V5: канистра — у воды набрать, иначе налить в мелкую тару/отпить
		if can_fill_here(ch) and WaterContainers.litres(ch, id) < float(dd.get("container_l", 20.0)) - 0.05:
			var got := WaterContainers.fill_big(ch, id, is_fresh_at(look_water_point(ch)))
			toast(ch, "Набрал %.1f л" % got)
		else:
			toast(ch, WaterContainers.use_big(ch, id))
		return true
	if dd.has("fill_fresh"):
		if not fill_from_view(ch, id):
			toast(ch, "Смотри на воду (или встань в неё) и жми ПКМ/E, чтобы набрать")
		return true
	if id == &"pot":
		toast(ch, "Котелок: у горящего костра E — вскипятить морскую воду")
		return true
	if dd.has("peel"):
		# зелёный кокос: сначала очистить от шелухи (v5.1)
		if not _can_crack(ch) and count(ch, &"machete") <= 0:
			toast(ch, "Нечем очистить кокос — нужен нож, мачете, топор или камень")
			return true
		if take(ch, id, 1):
			give(ch, StringName(dd.peel), 1)
			give(ch, &"coconut_husk", 1)
			toast(ch, "Кокос очищен — шелуха пойдёт на растопку")
		return true
	if id == &"coconut_peeled" and not _can_crack(ch):
		toast(ch, "Нечем расколоть кокос — нужен камень, нож или топор")
		return true
	if dd.has("seed"):
		toast(ch, "Посади на грядке: смотри на грядку и жми E")
		return true
	# свежесть того, что едим (для on_consumed)
	var i := inv(ch)
	if i and dd.has("spoil"):
		var s := i.get_slot(i.selected)
		ch.set_meta(&"sv_use_fr", float(s.get("fr", 1.0)) if not s.is_empty() and s.id == id else 1.0)
	return false

func _can_crack(ch: Node) -> bool:
	for t in CRACK_TOOLS:
		if count(ch, t) > 0:
			return true
	return false

## После Player.consume(id): тара, соль, кокос, гниль, лечение яда.
func on_consumed(ch: Node, id: StringName) -> void:
	var dd := data(id)
	if dd.has("returns"):
		give(ch, StringName(dd.returns), 1)
	match StringName(dd.get("sv", &"")):
		&"salt_water":
			apply_salt(ch)
		&"coconut":
			give(ch, &"coconut_shell", 1)
		&"rotten":
			apply_nausea(ch, 2.0)
			_damage(ch, 6.0, &"food")
			toast(ch, "Гниль! Тошнит…")
		&"cure":
			cure_poison(ch)
	if dd.has("spoil") and ch.has_meta(&"sv_use_fr"):
		var fr := float(ch.get_meta(&"sv_use_fr"))
		ch.remove_meta(&"sv_use_fr")
		if fr < STALE and _rng.randf() < (STALE - fr) / STALE * 0.8 + 0.2:
			apply_nausea(ch, 1.0)
			_damage(ch, 3.0, &"food")
			toast(ch, "Еда начала портиться — живот крутит")

## Игрок пьёт из моря/водоёма (E). true — Survival обработал.
func on_drink_water(ch: Node) -> bool:
	var p := look_water_point(ch)
	var h_id := held(ch)
	# v5.2: тест-полоска и отравленный родник (SeasonEvents)
	if h_id == &"water_test_kit":
		if SeasonEvents.is_poisoned(p):
			toast(ch, "Полоска почернела: вода ОТРАВЛЕНА")
		else:
			toast(ch, "Полоска чистая: яда в воде нет")
		return true
	if SeasonEvents.is_poisoned(p):
		if data(h_id).has("fill_fresh"):
			toast(ch, "Вода пахнет тухлым — набирать не стал")
			return true
		var se := SeasonEvents.instance()
		var ev := se.get_active(&"poison_spring") if se else null
		if ev:
			ev.call(&"poison", ch)
		return true
	var fresh := is_fresh_at(p)
	if data(h_id).has("fill_fresh"):
		fill_at(ch, h_id, fresh)
		return true
	if fresh:
		return false # обычный глоток игрока (+25)
	drink_salt(ch)
	return true

## Точка воды, на которую смотрит/в которой стоит персонаж.
func look_water_point(ch: Node) -> Vector3:
	var c3 := ch as Node3D
	if c3 == null:
		return Vector3.ZERO
	if ch.has_method(&"is_in_water") and bool(ch.call(&"is_in_water")):
		return c3.global_position
	var cam: Variant = ch.get(&"camera")
	if cam is Camera3D and ch.has_method(&"get_look_dir"):
		var eye := (cam as Camera3D).global_position
		var dir: Vector3 = ch.call(&"get_look_dir")
		var w := wl()
		if dir.y < -0.05 and eye.y > w:
			return eye + dir * ((w - eye.y) / dir.y)
	return c3.global_position

## Можно ли набрать воду там, куда смотрит персонаж.
func can_fill_here(ch: Node) -> bool:
	if ch.has_method(&"can_drink_here"):
		return bool(ch.call(&"can_drink_here"))
	if ch.has_method(&"is_in_water") and bool(ch.call(&"is_in_water")):
		return true
	var c3 := ch as Node3D
	return c3 != null and h(c3.global_position.x, c3.global_position.z) < wl() + 0.3

func fill_from_view(ch: Node, id: StringName) -> bool:
	if not can_fill_here(ch):
		return false
	fill_at(ch, id, is_fresh_at(look_water_point(ch)))
	return true

## Наполнить всю тару вида id (пресной/морской).
func fill_at(ch: Node, id: StringName, fresh: bool) -> int:
	var dd := data(id)
	var to := StringName(dd.get("fill_fresh" if fresh else "fill_salt", &""))
	var n := count(ch, id)
	if to == &"" or n <= 0 or not take(ch, id, n):
		return 0
	give(ch, to, n)
	var hands: Variant = ch.get(&"hands")
	if hands is Object and (hands as Object).has_method(&"play_use"):
		(hands as Object).call(&"play_use")
	sfx((ch as Node3D).global_position, "res://assets/sounds/sfx-kit/props-splash.wav")
	toast(ch, ("Набрал пресной воды ×%d" if fresh else "Набрал морской воды ×%d — вскипяти перед питьём") % n)
	return n

func drink_salt(ch: Node) -> void:
	var t: Variant = ch.get(&"thirst")
	if t != null:
		ch.set(&"thirst", minf(100.0, float(t) + 6.0))
	var hands: Variant = ch.get(&"hands")
	if hands is Object and (hands as Object).has_method(&"play_use"):
		(hands as Object).call(&"play_use")
	apply_salt(ch)
	toast(ch, "Морская вода! Солёная — жажда станет только сильнее")

# ======================================================== эффекты

func _fx(ch: Node) -> Dictionary:
	if not effects.has(ch):
		effects[ch] = {"salt": 0.0, "nausea": 0.0, "pdmg": 0.0, "ndmg": 0.0}
	return effects[ch]

func apply_salt(ch: Node) -> void:
	var e := _fx(ch)
	e.salt = minf(SALT_TIME * 3.0, float(e.salt) + SALT_TIME)
	_damage(ch, 3.0, &"salt")

func apply_nausea(ch: Node, mul: float = 1.0) -> void:
	var e := _fx(ch)
	e.nausea = minf(NAUSEA_TIME * 3.0, float(e.nausea) + NAUSEA_TIME * mul)

## Яд (CONTRACT_G2: у персонажа poison — урон/с, poison_time — сек). Тикает SURVIVAL.
static func get_poison(ch: Node) -> Vector2:
	if ch == null:
		return Vector2.ZERO
	var p: Variant = ch.get(&"poison")
	var t: Variant = ch.get(&"poison_time")
	if p != null and t != null:
		return Vector2(float(p), float(t))
	return Vector2(float(ch.get_meta(&"poison", 0.0)), float(ch.get_meta(&"poison_time", 0.0)))

static func set_poison(ch: Node, dps: float, time: float) -> void:
	if ch == null:
		return
	if ch.get(&"poison") != null and ch.get(&"poison_time") != null:
		ch.set(&"poison", dps)
		ch.set(&"poison_time", time)
	else:
		ch.set_meta(&"poison", dps)
		ch.set_meta(&"poison_time", time)

func apply_poison(ch: Node, dps: float, time: float) -> void:
	var cur := get_poison(ch)
	set_poison(ch, maxf(cur.x, dps), maxf(cur.y, time))
	_fx(ch)
	toast(ch, "Отравление! Нужна припарка из трав")

func cure_poison(ch: Node) -> void:
	var had := get_poison(ch).y > 0.0
	set_poison(ch, 0.0, 0.0)
	if effects.has(ch):
		effects[ch].nausea = 0.0
	toast(ch, "Яд выведен" if had else "Полегчало")

func effects_of(ch: Node) -> Dictionary:
	var e: Dictionary = effects.get(ch, {})
	var p := get_poison(ch)
	return {"salt": float(e.get("salt", 0.0)), "nausea": float(e.get("nausea", 0.0)), "poison": p.x, "poison_time": p.y}

func _damage(ch: Node, amount: float, k: StringName) -> void:
	if ch and ch.has_method(&"apply_damage"):
		ch.call(&"apply_damage", amount, null, k)

## FAUNA может взять тик яда на себя: метод ticks_poison() -> true у узла группы fauna.
func _fauna_ticks_poison() -> bool:
	var f := get_tree().get_first_node_in_group(&"fauna")
	return f != null and f.has_method(&"ticks_poison") and bool(f.call(&"ticks_poison"))

func _tick_effects(dt: float) -> void:
	var fauna_poison := _fauna_ticks_poison()
	for ch in get_tree().get_nodes_in_group(&"characters"):
		if ch.has_method(&"is_dead") and bool(ch.call(&"is_dead")):
			effects.erase(ch)
			continue
		var p := Vector2.ZERO if fauna_poison else get_poison(ch)
		if not effects.has(ch) and p.y <= 0.0:
			continue
		var e := _fx(ch)
		if float(e.salt) > 0.0:
			e.salt = maxf(0.0, float(e.salt) - dt)
			var t: Variant = ch.get(&"thirst")
			if t != null:
				ch.set(&"thirst", maxf(0.0, float(t) - SALT_DRAIN * dt))
		if float(e.nausea) > 0.0:
			e.nausea = maxf(0.0, float(e.nausea) - dt)
			var hu: Variant = ch.get(&"hunger")
			if hu != null:
				ch.set(&"hunger", maxf(0.0, float(hu) - 0.12 * dt))
			e.ndmg = float(e.ndmg) + dt * 0.15
		if p.y > 0.0:
			var step := minf(dt, p.y)
			e.pdmg = float(e.pdmg) + p.x * step
			set_poison(ch, p.x if p.y - step > 0.0 else 0.0, maxf(0.0, p.y - step))
		var total := float(e.pdmg) + float(e.ndmg)
		if total >= 1.0:
			var whole := floorf(total)
			_damage(ch, whole, &"poison")
			var share := float(e.pdmg) / total if total > 0.0 else 0.0
			e.pdmg = float(e.pdmg) - whole * share
			e.ndmg = float(e.ndmg) - whole * (1.0 - share)
		if float(e.salt) <= 0.0 and float(e.nausea) <= 0.0 and get_poison(ch).y <= 0.0 and total < 1.0:
			effects.erase(ch)

# ======================================================== порча еды

## Свежесть еды хранится в слоте инвентаря: "fr" (1 — свежая, 0 — сгнила),
## "frn" — сколько штук было при прошлом тике (новые штуки освежают среднее).
## Inventory не правится: ключи живут в словаре слота (move/swap их переносят,
## слияние стеков берёт свежесть целевого стека, выброс/подбор — сбрасывает).
func _tick_fresh(dt: float) -> void:
	for ch in get_tree().get_nodes_in_group(&"characters"):
		var i := inv(ch)
		if i:
			spoil_inventory(i, dt, ch)
	for n in get_tree().get_nodes_in_group(&"sv_storage"):
		var i2 := n.get_node_or_null(^"Inventory") as Inventory
		if i2:
			spoil_inventory(i2, dt, null)

func spoil_inventory(i: Inventory, dt: float, owner: Node) -> void:
	for k in mini(Inventory.SIZE, i.slots.size()):
		var s := i.slots[k]
		if s.is_empty():
			continue
		var minutes := float(data(StringName(s.id)).get("spoil", 0.0))
		if minutes <= 0.0:
			if s.has("fr"):
				s.erase("fr")
				s.erase("frn")
			continue
		var n := int(s.n)
		if not s.has("fr"):
			s["fr"] = 1.0
			s["frn"] = n
		elif n > int(s.frn):
			s["fr"] = (float(s.fr) * int(s.frn) + float(n - int(s.frn))) / float(n)
			s["frn"] = n
		elif n < int(s.frn):
			s["frn"] = n
		s["fr"] = float(s.fr) - dt / (minutes * 60.0)
		if float(s.fr) <= 0.0:
			var nm := Items.item_name(StringName(s.id))
			i.set_slot(k, {"id": &"rotten_food", "n": n})
			toast(owner, "Испортилось: %s" % nm)

## Свежесть стека в слоте (1 — свежий; -1 — не портится).
static func freshness(ch: Node, slot: int) -> float:
	var i := inv(ch)
	if i == null:
		return -1.0
	var s := i.get_slot(slot)
	if s.is_empty() or float(data(StringName(s.id)).get("spoil", 0.0)) <= 0.0:
		return -1.0
	var fr := float(s.get("fr", 1.0))
	var n := int(s.n)
	var fn := int(s.get("frn", n))
	if n > fn and fn >= 0:
		fr = (fr * fn + float(n - fn)) / float(n) # подложенные свежие куски — сразу
	return clampf(fr, 0.0, 1.0)

# ======================================================== тик

func _process(delta: float) -> void:
	var __pt := PerfStats.begin()
	_perf_process(delta)
	PerfStats.end(&"survival", __pt)

func _perf_process(delta: float) -> void:
	var dt := delta * speed
	_acc += dt
	_facc += dt
	if _acc >= TICK * speed:
		var step := _acc
		_acc = 0.0
		for st in get_tree().get_nodes_in_group(&"sv_station"):
			(st as SvStation).tick(step)
		_tick_effects(step)
		_watch_weather()
	if _facc >= FRESH_TICK * speed:
		var fstep := _facc
		_facc = 0.0
		_tick_fresh(fstep)
	_update_ghost()

func _watch_weather() -> void:
	var w := weather()
	if _last_weather == &"storm" and w != &"storm":
		after_storm()
	_last_weather = w

# ======================================================== постройки

## Поставить постройку SURVIVAL перед персонажем (ПКМ с набором в руке).
func place_from_view(ch: Node, kit: StringName, item_id: StringName) -> Node:
	var t := _placement(ch, kit)
	if not bool(t.ok):
		toast(ch, String(t.reason))
		return null
	if not take(ch, item_id, 1):
		return null
	return place_structure(null, kit, t.pos, float(t.yaw))

func _placement(ch: Node, kit: StringName) -> Dictionary:
	var c3 := ch as Node3D
	var res := {"ok": false, "reason": "Некуда ставить", "pos": Vector3.ZERO, "yaw": 0.0}
	if c3 == null:
		return res
	var eye := c3.global_position + Vector3.UP * 1.6
	var dir := -c3.global_transform.basis.z
	var cam: Variant = ch.get(&"camera")
	if cam is Camera3D:
		eye = (cam as Camera3D).global_position
	if ch.has_method(&"get_look_dir"):
		dir = ch.call(&"get_look_dir")
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	if flat.length() < 0.1:
		flat = Vector3.FORWARD
	var r := float(KIT_RADIUS.get(kit, 0.8))
	var pos := c3.global_position + flat * (1.4 + r)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * 5.0)
	if c3 is CollisionObject3D:
		q.exclude = [(c3 as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and (hit.position as Vector3).distance_to(c3.global_position) > r + 0.4:
		pos = hit.position
		pos.y = maxf(pos.y, h(pos.x, pos.z))
	else:
		pos.y = h(pos.x, pos.z)
	res.pos = pos
	res.yaw = atan2(-flat.x, -flat.z)
	res.reason = check_place(kit, pos)
	res.ok = res.reason == ""
	return res

## "" — можно ставить; иначе причина.
func check_place(kit: StringName, pos: Vector3) -> String:
	var ground := h(pos.x, pos.z)
	var on_terrain := absf(pos.y - ground) < 0.35
	if on_terrain and ground < wl() + 0.25:
		return "Нельзя ставить в воде"
	if on_terrain and slope(pos.x, pos.z) > 0.9:
		return "Слишком круто"
	if kit == &"garden" and not on_terrain:
		return "Грядку — только на землю"
	var r := float(KIT_RADIUS.get(kit, 0.8))
	for st in get_tree().get_nodes_in_group(&"sv_station"):
		var s3 := st as Node3D
		if s3 and s3.global_position.distance_to(pos) < r + 0.6 and not (st is SvWild) and not (st is SvDebris):
			return "Мешает другая постройка"
	return ""

## Создать постройку SURVIVAL (для ботов и тестов — без проверок и без набора).
## kit: campfire | smoker | still | rain_barrel | tarp | garden
func place_structure(ch: Node, kit: StringName, pos: Vector3, yaw: float = 0.0) -> Node3D:
	var n: SvStation = null
	match kit:
		&"campfire": n = SvFire.new()
		&"smoker": n = SvSmoker.new()
		&"still", &"rain_barrel", &"tarp", &"spring":
			var w := SvWater.new()
			w.kind = kit
			n = w
		&"garden":
			var g := SvGarden.new()
			g.soil_factor = 0.6 if biome(pos.x, pos.z) == &"beach" else 1.0
			n = g
		_:
			return null
	n.kind = kit
	structures.add_child(n)
	n.global_position = pos
	n.rotation.y = yaw
	if ch:
		var dd := {}
		for k in Items.items.keys():
			var it := Items.get_item(k)
			if it and StringName(it.data.get("kit", &"")) == kit:
				dd[k] = true
		for k in dd.keys():
			if take(ch, StringName(k), 1):
				break
	Events.structure_completed.emit(n, StringName("sv_" + String(kit)))
	return n

func _on_structure_completed(node: Node, def_id: StringName) -> void:
	if def_id == &"fire_pit" and node is Node3D and node.get_node_or_null(^"SvFire") == null:
		var f := SvFire.new()
		f.attached = true
		node.add_child(f)

func _attach_existing_pits() -> void:
	for n in get_tree().get_nodes_in_group(&"buildable"):
		if StringName(n.get(&"def_id") if n.get(&"def_id") != null else &"") == &"fire_pit" and bool(n.get(&"complete")):
			_on_structure_completed(n, &"fire_pit")

# ---------- призрак установки ----------

func _make_ghost() -> void:
	_ghost = MeshInstance3D.new()
	_ghost.name = "PlaceGhost"
	var m := CylinderMesh.new()
	m.top_radius = 1.0
	m.bottom_radius = 1.0
	m.height = 0.06
	m.radial_segments = 24
	_ghost.mesh = m
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)

func _update_ghost() -> void:
	var p := get_tree().get_first_node_in_group(&"player")
	if p == null or _ghost == null:
		return
	var kit := StringName(data(held(p)).get("kit", &""))
	if kit == &"":
		_ghost.visible = false
		return
	var t := _placement(p, kit)
	var r := float(KIT_RADIUS.get(kit, 0.8))
	_ghost.visible = true
	_ghost.global_position = (t.pos as Vector3) + Vector3.UP * 0.04
	_ghost.scale = Vector3(r, 1.0, r)
	_ghost.material_override = SurvivalModels.color(Color(0.5, 1.0, 0.55, 0.3) if bool(t.ok) else Color(1.0, 0.35, 0.3, 0.3), 0.6)

# ======================================================== рассадка

func populate() -> void:
	if populated:
		return
	populated = true
	_find_beaches()
	if spawn_debris:
		for b in beaches:
			_spawn_on_beach(b, DEBRIS_PER_BEACH)
	if spawn_wild:
		_spawn_wild()
	if not (world and world.has_method(&"fresh_water_at")):
		_spawn_springs()
	_attach_existing_pits()
	_last_weather = weather()
	populated_done.emit()

## Мусорные берега: world.trash_beaches() (если есть) или по 1–2 на остров.
func _find_beaches() -> void:
	beaches.clear()
	if world and world.has_method(&"trash_beaches"):
		for b in world.call(&"trash_beaches"):
			var p := _beach_point_of(b)
			if p != Vector3.INF:
				beaches.append(_beach_frame(p))
		if not beaches.is_empty():
			return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 13 + 1
	for I in islands():
		var c: Vector2 = I.center
		var R := float(I.radius)
		var nb := 1 if StringName(I.get("kind", &"")) == &"home" else 2
		var base := rng.randf() * TAU
		for k in nb:
			var a := base + TAU * k / nb + rng.randf_range(-0.4, 0.4)
			var p := _shore_point(c, Vector2(cos(a), sin(a)), R)
			if p != Vector3.INF:
				var fr := _beach_frame(p)
				fr.island = I
				beaches.append(fr)

func _beach_point_of(b: Variant) -> Vector3:
	var v: Variant = b
	if b is Dictionary:
		for k in ["position", "pos", "center", "point"]:
			if (b as Dictionary).has(k):
				v = b[k]
				break
	if v is Vector2:
		return Vector3(v.x, h(v.x, v.y), v.y)
	if v is Vector3:
		return v
	return Vector3.INF

## Точка пляжа: идём от центра наружу до кромки воды, отступаем на сушу.
func _shore_point(c: Vector2, d: Vector2, R: float) -> Vector3:
	var w := wl()
	var r := R * 0.25
	var last_land := -1.0
	while r < R * 1.8:
		var p := c + d * r
		var y := h(p.x, p.y)
		if y > w + 0.3:
			last_land = r
		elif last_land > 0.0 and r - last_land > 2.0:
			break
		r += 0.5
	if last_land < 0.0:
		return Vector3.INF
	var p2 := c + d * (last_land - 2.5)
	return Vector3(p2.x, h(p2.x, p2.y), p2.y)

func _beach_frame(p: Vector3) -> Dictionary:
	var best := Vector2.ZERO
	var bd := 1e9
	for I in islands():
		var dd := (Vector2(p.x, p.z) - (I.center as Vector2)).length()
		if dd < bd:
			bd = dd
			best = I.center
	var out := Vector3(p.x - best.x, 0.0, p.z - best.y).normalized()
	if out.length() < 0.1:
		out = Vector3.RIGHT
	return {"pos": p, "out": out, "tan": out.cross(Vector3.UP).normalized(), "island": {}}

func _spawn_on_beach(b: Dictionary, n: int) -> int:
	var have := 0
	for d in get_tree().get_nodes_in_group(&"sv_debris"):
		if (d as Node3D).global_position.distance_to(b.pos) < 12.0:
			have += 1
	var made := 0
	var w := wl()
	var tries := 0
	while made < n and have + made < DEBRIS_MAX_PER_BEACH and tries < n * 12:
		tries += 1
		var along := _rng.randf_range(-11.0, 11.0)
		var p: Vector3 = (b.pos as Vector3) + (b.tan as Vector3) * along
		# по нормали к берегу — до полосы прибоя
		var best := Vector3.INF
		for s in 14:
			var q: Vector3 = p + (b.out as Vector3) * (float(s) * 0.6 - 3.0)
			var y := h(q.x, q.z)
			if y > w + 0.22 and y < w + 1.6 and slope(q.x, q.z) < 0.7:
				best = Vector3(q.x, y, q.z)
		if best == Vector3.INF:
			continue
		var clash := false
		for d in get_tree().get_nodes_in_group(&"sv_station"):
			if (d as Node3D).global_position.distance_to(best) < 1.6:
				clash = true
				break
		if clash:
			continue
		var dbr := SvDebris.new()
		dbr.kind = _pick_debris()
		dbr.seed_v = _rng.randi() % 100000
		structures.add_child(dbr)
		dbr.global_position = best - Vector3(0, 0.05, 0)
		dbr.rotation.y = _rng.randf() * TAU
		made += 1
	return made

func _pick_debris() -> StringName:
	var total := 0.0
	for k in DEBRIS_WEIGHTS.keys():
		total += float(DEBRIS_WEIGHTS[k])
	var r := _rng.randf() * total
	for k in DEBRIS_WEIGHTS.keys():
		r -= float(DEBRIS_WEIGHTS[k])
		if r <= 0.0:
			return k
	return &"crate"

## После шторма море выносит новый мусор.
func after_storm() -> int:
	var made := 0
	for b in beaches:
		made += _spawn_on_beach(b, 4)
	if made > 0:
		Events.toast.emit("Шторм выбросил на берег обломки")
	return made

func _spawn_wild() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7 + 3
	var avoid: Array[Vector3] = []
	if world and world.has_method(&"spawn_point"):
		for t in 4:
			avoid.append(world.call(&"spawn_point", t))
	for I in islands():
		var c: Vector2 = I.center
		var R := float(I.radius)
		var k := clampf(R / 55.0, 0.6, 2.2)
		var want := {&"herb": int(6 * k), &"berry": int(4 * k), &"taro": int(3 * k)}
		for kind in want.keys():
			var made := 0
			var tries := 0
			while made < int(want[kind]) and tries < 80:
				tries += 1
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf()) * R * 0.8
				var x := c.x + cos(a) * r
				var z := c.y + sin(a) * r
				var y := h(x, z)
				if y < wl() + 1.4 or slope(x, z) > 0.8:
					continue
				var b := biome(x, z)
				if b in [&"beach", &"rocky", &"water"]:
					continue
				if kind == &"taro" and y > 6.0:
					continue
				var p := Vector3(x, y, z)
				var bad := false
				for s in avoid:
					if s.distance_to(p) < 8.0:
						bad = true
				if bad:
					continue
				var wp := SvWild.new()
				wp.kind = kind
				structures.add_child(wp)
				wp.global_position = p - Vector3(0, 0.03, 0)
				wp.rotation.y = rng.randf() * TAU
				made += 1

## Родники (если WORLD не даёт fresh_water_at): на общих/центральном островах,
## на домашних — нет (там вода — дождь, кокосы, опреснитель, кипячение).
func _spawn_springs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 5 + 11
	var all := islands()
	for I in all:
		if StringName(I.get("kind", &"")) == &"home" and all.size() > 1:
			continue
		var c: Vector2 = I.center
		var R := float(I.radius)
		var best := Vector3.INF
		var best_s := 1e9
		for t in 120:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * R * 0.55
			var x := c.x + cos(a) * r
			var z := c.y + sin(a) * r
			var y := h(x, z)
			if y < wl() + 1.6 or y > 7.0:
				continue
			var sc := slope(x, z) * 3.0 + absf(y - 2.6) * 0.3
			if sc < best_s:
				best_s = sc
				best = Vector3(x, y, z)
		if best != Vector3.INF:
			var s := place_structure(null, &"spring", best - Vector3(0, 0.05, 0), rng.randf() * TAU)
			s.name = "Spring"

# ======================================================== API ботам

## Источники пресной воды рядом: [{node, pos, kind, portions, dist}] по расстоянию.
## (Море — всегда солёное: бутылку можно набрать и вскипятить, см. fill_container/boil.)
func drink_sources(pos: Vector3, radius: float = 200.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in get_tree().get_nodes_in_group(&"sv_station"):
		if n is SvWater:
			var w := n as SvWater
			var d := w.global_position.distance_to(pos)
			if d <= radius and w.portions() > 0:
				out.append({"node": w, "pos": w.global_position, "kind": w.kind, "portions": w.portions(), "dist": d, "fresh": true})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.dist) < float(b.dist))
	return out

## Еда рядом: дикие растения, созревшие грядки, ящики/бочки с берега, готовое на костре/в коптильне.
## [{node, pos, kind, action: 'pick'|'harvest'|'break'|'take', dist}]
func food_sources(pos: Vector3, radius: float = 200.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in get_tree().get_nodes_in_group(&"sv_station"):
		var s3 := n as Node3D
		var d := s3.global_position.distance_to(pos)
		if d > radius:
			continue
		var act := ""
		if n is SvWild and not (n as SvWild).picked and (n as SvWild).kind != &"herb":
			act = "pick"
		elif n is SvGarden and (n as SvGarden).is_ready():
			act = "harvest"
		elif n is SvDebris and (n as SvDebris).kind == &"crate":
			act = "break"
		elif n is SvFire and not (n as SvFire).grill_ready().is_empty():
			act = "take"
		elif n is SvSmoker and (n as SvSmoker).ready_count() > 0:
			act = "take"
		if act != "":
			out.append({"node": n, "pos": s3.global_position, "kind": (n as SvStation).kind, "action": act, "dist": d})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.dist) < float(b.dist))
	return out

## Лечебные травы рядом (яд).
func herb_sources(pos: Vector3, radius: float = 200.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in get_tree().get_nodes_in_group(&"sv_wild"):
		var w := n as SvWild
		if w.kind == &"herb" and not w.picked and w.global_position.distance_to(pos) <= radius:
			out.append({"node": w, "pos": w.global_position, "dist": w.global_position.distance_to(pos)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.dist) < float(b.dist))
	return out

func debris_near(pos: Vector3, radius: float = 60.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in get_tree().get_nodes_in_group(&"sv_debris"):
		var d := (n as Node3D).global_position.distance_to(pos)
		if d <= radius:
			out.append({"node": n, "pos": (n as Node3D).global_position, "kind": (n as SvDebris).kind, "dist": d})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.dist) < float(b.dist))
	return out

## Постройки SURVIVAL рядом (kind: campfire/smoker/still/rain_barrel/tarp/garden/spring или "" — все).
func stations_near(pos: Vector3, kind: StringName = &"", radius: float = 60.0) -> Array[Node]:
	var out: Array[Node] = []
	for n in get_tree().get_nodes_in_group(&"sv_station"):
		if (kind == &"" or (n as SvStation).kind == kind) and (n as Node3D).global_position.distance_to(pos) <= radius:
			out.append(n)
	return out

## Набрать воду: из источника SvWater (пресная) или из моря там, где стоит бот (солёная).
func fill_container(ch: Node, source: Node = null, id: StringName = &"") -> int:
	if id == &"":
		for c in [&"bottle_empty", &"coconut_shell"]:
			if count(ch, c) > 0:
				id = c
				break
	if id == &"":
		return 0
	if source is SvWater:
		return (source as SvWater).fill(ch, id)
	if not can_fill_here(ch):
		return 0
	return fill_at(ch, id, is_fresh_at(look_water_point(ch)))

## Вскипятить морскую воду на костре (нужен котелок в инвентаре).
func boil(ch: Node, fire: Node) -> bool:
	return fire is SvFire and (fire as SvFire).boil(ch)

func cook(ch: Node, fire: Node, id: StringName) -> bool:
	return fire is SvFire and (fire as SvFire).put_on_grill(ch, id)

func light_fire(ch: Node, fire: Node) -> bool:
	return fire is SvFire and (fire as SvFire).light(ch)

func smoke(ch: Node, smoker: Node, id: StringName) -> int:
	return (smoker as SvSmoker).hang(ch, id) if smoker is SvSmoker else 0

func plant(ch: Node, plot: Node, seed_id: StringName) -> bool:
	return plot is SvGarden and (plot as SvGarden).plant(ch, seed_id)

## Полить грядку из тары (по умолчанию — первая пресная).
func water_plot(ch: Node, plot: Node, id: StringName = &"") -> bool:
	if not plot is SvGarden:
		return false
	if id == &"":
		for c in [&"water_bottle", &"shell_water"]:
			if count(ch, c) > 0:
				id = c
				break
	return id != &"" and (plot as SvGarden).water(ch, id)

## Собрать: грядку, дикое растение, готовое с костра/коптильни.
func harvest(ch: Node, node: Node) -> bool:
	if node is SvGarden:
		return not (node as SvGarden).harvest(ch).is_empty()
	if node is SvWild:
		return not (node as SvWild).pick(ch).is_empty()
	if node is SvFire or node is SvSmoker or node is SvWater:
		(node as SvStation).interact(ch)
		return true
	return false

## Один удар по обломку (возвращает true, если разбит).
func break_debris(ch: Node, d: Node, damage: float = 10.0, tool: StringName = &"rock") -> bool:
	if not d is SvDebris or not is_instance_valid(d):
		return false
	(d as SvDebris).on_hit(ch, {"tool": tool, "damage": damage, "position": (d as Node3D).global_position})
	return d.is_queued_for_deletion()

## Забрать/собрать обломок без ударов (бочка, бутылки, сеть).
func salvage_debris(ch: Node, d: Node) -> void:
	if d is SvDebris:
		(d as SvDebris).interact(ch)

## Съесть лучшее из инвентаря (бот). Возвращает id или "".
func eat_best(ch: Node) -> StringName:
	var best := &""
	var score := -1e9
	var i := inv(ch)
	if i == null:
		return &""
	for s in i.slots:
		if s.is_empty():
			continue
		var dd := data(StringName(s.id))
		if not dd.has("hunger") or float(dd.hunger) <= 0.0 or dd.has("cook") or StringName(dd.get("sv", &"")) == &"rotten":
			continue
		var sc := float(dd.hunger) - (20.0 if float(s.get("fr", 1.0)) < STALE else 0.0) + (5.0 if dd.has("spoil") else 0.0)
		if sc > score:
			score = sc
			best = StringName(s.id)
	if best != &"":
		consume_item(ch, best)
	return best

## Попить лучшее из инвентаря (пресное). Возвращает id или "".
func drink_best(ch: Node) -> StringName:
	for id in [&"water_bottle", &"shell_water", &"herbal_tea", &"coconut_peeled", &"melon"]:
		if count(ch, id) > 0 and (id != &"coconut_peeled" or _can_crack(ch)):
			consume_item(ch, id)
			return id
	return &""

## Употребить предмет без анимации (боты): убрать 1 и применить эффект + хук.
func consume_item(ch: Node, id: StringName) -> bool:
	if not take(ch, id, 1):
		return false
	if ch.has_method(&"consume"):
		ch.call(&"consume", id) # Player.consume сам зовёт on_consumed
		if not ch.has_method(&"use_selected"):
			on_consumed(ch, id)
	else:
		var dd := data(id)
		for k in ["hunger", "thirst"]:
			var v: Variant = ch.get(k)
			if v != null:
				ch.set(k, clampf(float(v) + float(dd.get(k, 0.0)), 0.0, 100.0))
		on_consumed(ch, id)
	return true
