class_name Supply
extends Node3D
## Модуль SUPPLY — «посылки из внешнего мира». Лор: игра — реалити-шоу, богатые
## зрители-спонсоры иногда сбрасывают ящики с современными вещами.
## Расписание (игровое время матча): первый сброс через 8–12 мин, дальше каждые
## 10–20 мин; к концу матча чаще (до ×0.55) и ценнее (легендарных до 40%).
## Сброс: самолёт пролетает над общим/центральным островом (или у его берега),
## ящик падает на парашюте, дым цвета редкости, объявление всем, метка на мини-карте
## (группа map_markers → map_markers(viewer)). Рация в инвентаре показывает следующий
## сброс заранее. Игрокам вешается SupplyController (горелка, пила, бинокль, фонарь…).
##
## API: Supply.instance(), crates(), available_crates(), crate_near(pos, r),
##   next_drop {time, pos, tier, island}, drop_now(pos=null, tier=-1, plane=true) -> SupplyCrate|SupplyPlane,
##   schedule_in(sec), filter_damage(ch, amount, kind) (бронежилет; зовут Player/Bot.apply_damage).

signal drop_announced(info: Dictionary)
signal crate_landed(crate: SupplyCrate)
signal crate_opened(crate: SupplyCrate, by: Node)

const FIRST_MIN := 480.0
const FIRST_MAX := 720.0
const GAP_MIN := 600.0
const GAP_MAX := 1200.0
const ALTITUDE := 150.0
const RADIO_LEAD := 150.0   # за сколько секунд рация «слышит» следующий сброс

## Множитель расписания для тестов (1 — как в матче).
static var schedule_scale := 1.0

var next_drop: Dictionary = {}
var drops := 0
var plane_lead := 900.0
var wind := Vector3(0.6, 0.0, 0.25)
var _rng := RandomNumberGenerator.new()
var _radio_warned := -1

static func instance() -> Supply:
	var t := Engine.get_main_loop() as SceneTree
	return t.get_first_node_in_group(&"supply") as Supply if t else null

func _ready() -> void:
	name = "Supply"
	add_to_group(&"supply")
	add_to_group(&"map_markers")
	_rng.randomize()
	var a := _rng.randf() * TAU
	wind = Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(0.3, 0.9)
	SupplyItems.register()
	for p in get_tree().get_nodes_in_group(&"player"):
		_attach(p)
	Events.character_spawned.connect(_on_spawned)
	Events.match_started.connect(_on_match_started)
	get_tree().node_added.connect(_on_node_added)

func _exit_tree() -> void:
	SupplyModels.clear_caches()
	SupplyFx.clear_caches()

func _on_spawned(ch: Node) -> void:
	if ch.is_in_group(&"player"):
		_attach(ch)

func _attach(p: Node) -> void:
	if p is Player and p.get_node_or_null(^"SupplyController") == null:
		var c := SupplyController.new()
		c.name = "SupplyController"
		p.add_child(c)

func _on_match_started(_cfg: Dictionary) -> void:
	next_drop = {}
	drops = 0

# ------------------------------------------------------------ расписание

func _len() -> float:
	return Game.match_length if Game.has_time_limit() and Game.match_length > 60.0 else 10800.0

func progress_at(t: float) -> float:
	return clampf(t / _len(), 0.0, 1.0)

func schedule_in(sec: float, tier: int = -1) -> void:
	var t := Game.match_time + sec
	var spot := pick_spot()
	next_drop = {"time": t, "pos": spot.pos, "island": spot.island, "tier": tier if tier >= 0 else _pick_tier(progress_at(t), drops == 0)}
	_radio_warned = -1

func _schedule() -> void:
	var dt: float
	if drops == 0:
		dt = _rng.randf_range(FIRST_MIN, FIRST_MAX)
	else:
		dt = _rng.randf_range(GAP_MIN, GAP_MAX) * lerpf(1.0, 0.55, progress_at(Game.match_time))
	schedule_in(dt * schedule_scale)

func _pick_tier(prog: float, first: bool) -> int:
	var leg := 0.0 if first else 0.05 + 0.35 * prog
	var rare := 0.3 + 0.15 * prog
	var r := _rng.randf()
	if r < leg:
		return 2
	if r < leg + rare:
		return 1
	return 0

func _process(_delta: float) -> void:
	if not Game.is_playing():
		return
	if next_drop.is_empty():
		_schedule()
		return
	var left := float(next_drop.time) - Game.match_time
	if left <= RADIO_LEAD and _radio_warned != drops:
		_radio_warned = drops
		for p in get_tree().get_nodes_in_group(&"player"):
			if BuildEnv.inv_count(p, &"radio") > 0:
				Events.toast.emit("Рация: «…борт на подходе, точка сброса — %s». Метка на карте" % _where(next_drop, p as Node3D))
	if left <= 0.0:
		var info := next_drop
		next_drop = {}
		drops += 1
		launch(info)
		_schedule()

## Точка сброса: общий/центральный/особый остров (не домашний), чаще в глубине суши,
## иногда — у берега в воде (ящик плавает и дрейфует к суше).
func pick_spot() -> Dictionary:
	var w := BuildEnv.world()
	var wl := BuildEnv.water_level()
	var isl: Array = []
	if w and w.has_method(&"islands"):
		for I: Dictionary in w.call(&"islands"):
			if StringName(I.get("kind", &"")) != &"home" and float(I.get("radius", 0.0)) >= 18.0:
				isl.append(I)
	if isl.is_empty():
		# остров-заглушка (тесты): вокруг начала координат
		for k in 40:
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(8.0, 34.0)
			var q := Vector3(cos(a) * r, 0, sin(a) * r)
			q.y = BuildEnv.height_at(q.x, q.z)
			if q.y > wl + 0.5:
				return {"pos": q, "island": ""}
		return {"pos": Vector3(0, BuildEnv.height_at(0, 0), 0), "island": ""}
	var total := 0.0
	for I: Dictionary in isl:
		total += _isl_weight(I)
	var pick: Dictionary = isl[0]
	var rr := _rng.randf() * total
	for I: Dictionary in isl:
		rr -= _isl_weight(I)
		if rr <= 0.0:
			pick = I
			break
	var c: Vector2 = pick.center
	var R := float(pick.radius)
	var shore := _rng.randf() < 0.22
	for k in 60:
		var a := _rng.randf() * TAU
		var r := R * (_rng.randf_range(1.0, 1.22) if shore else _rng.randf_range(0.12, 0.6))
		var x := c.x + cos(a) * r
		var z := c.y + sin(a) * r
		var h := BuildEnv.height_at(x, z)
		if shore:
			if h < wl - 1.5 and h > wl - 9.0:
				return {"pos": Vector3(x, wl, z), "island": String(pick.get("name", ""))}
			continue
		if h < wl + 0.8:
			continue
		if w.has_method(&"normal_at") and (w.call(&"normal_at", x, z) as Vector3).y < 0.82:
			continue
		return {"pos": Vector3(x, h, z), "island": String(pick.get("name", ""))}
	return {"pos": Vector3(c.x, BuildEnv.height_at(c.x, c.y), c.y), "island": String(pick.get("name", ""))}

func _isl_weight(I: Dictionary) -> float:
	match StringName(I.get("kind", &"")):
		&"center": return 1.6
		&"shared": return 1.3
		&"swamp", &"wreck": return 0.7
	return 1.0

# ------------------------------------------------------------ сброс

## Немедленный сброс (тесты, отладка). plane=false — ящик сразу в воздухе над точкой.
func drop_now(pos: Variant = null, tier: int = -1, plane: bool = true) -> Node:
	var info := pick_spot() if pos == null else {"pos": pos as Vector3, "island": ""}
	info.tier = tier if tier >= 0 else _pick_tier(progress_at(Game.match_time), false)
	drops += 1
	return launch(info, plane)

func launch(info: Dictionary, plane: bool = true) -> Node:
	var target: Vector3 = info.pos
	var tier := int(info.get("tier", 0))
	var wl := BuildEnv.water_level()
	var alt := wl + ALTITUDE
	var ground := maxf(target.y, wl)
	var fall_t := (alt - 3.0 - ground) / SupplyCrate.FALL_SPEED
	var release := target - wind * fall_t
	var crate := SupplyCrate.new()
	crate.name = "SupplyCrate%d" % drops
	crate.tier = tier
	crate.number = drops
	crate.island_name = String(info.get("island", ""))
	crate.wind = wind
	crate.loot = SupplyItems.roll_loot(tier, _rng)
	crate.landed.connect(_on_landed)
	crate.opened.connect(_on_opened)
	var host: Node = get_parent() if get_parent() else self
	print("[supply] сброс №%d (%s) t=%d: %s, остров «%s»" % [drops, SupplyModels.TIER_NAMES[clampi(tier, 0, 2)], int(Game.match_time),
		str(target.snapped(Vector3.ONE)), String(info.get("island", ""))])
	var announce := info.duplicate()
	announce.tier = tier
	if not plane:
		host.add_child(crate)
		crate.global_position = Vector3(release.x, alt - 3.0, release.z)
		_announce(announce)
		return crate
	var pl := SupplyPlane.new()
	pl.drop_point = Vector3(release.x, alt, release.z)
	var a := _rng.randf() * TAU
	pl.heading = Vector3(cos(a), 0.0, sin(a))
	pl.lead = plane_lead
	pl.crate = crate
	pl.crate_parent = host
	pl.released.connect(func(_c: SupplyCrate) -> void: _announce(announce))
	host.add_child(pl)
	return pl

func _announce(info: Dictionary) -> void:
	var tier := int(info.get("tier", 0))
	drop_announced.emit(info)
	var smoke: String = ["зелёный", "фиолетовый", "красный"][clampi(tier, 0, 2)]
	for p in get_tree().get_nodes_in_group(&"player"):
		var txt := "Спонсоры прислали посылку — %s" % _where(info, p as Node3D)
		var md := MatchDirector.instance()
		if md:
			md.notice.emit(txt, SupplyModels.TIER_COLORS[clampi(tier, 0, 2)].lightened(0.25))
		else:
			Events.toast.emit(txt)
		Events.toast.emit("Посылка %s — дым %s" % [SupplyModels.TIER_NAMES[clampi(tier, 0, 2)], smoke])
		break

## «северо-восток, остров «Х», ≈ 340 м» — относительно зрителя.
func _where(info: Dictionary, viewer: Node3D) -> String:
	var pos: Vector3 = info.pos
	var from := viewer.global_position if viewer else Vector3.ZERO
	var d := Vector2(pos.x - from.x, pos.z - from.z)
	var parts: PackedStringArray = []
	if d.length() > 25.0:
		parts.append(compass(d))
	var isl := String(info.get("island", ""))
	if isl != "":
		parts.append("остров «%s»" % isl)
	parts.append("≈ %d м" % int(round(d.length() / 10.0) * 10.0))
	return ", ".join(parts)

## Сторона света по вектору (x, z); север — −Z (как на мини-карте).
static func compass(d: Vector2) -> String:
	const N: Array[String] = ["север", "северо-восток", "восток", "юго-восток", "юг", "юго-запад", "запад", "северо-запад"]
	var ang := atan2(d.x, -d.y) # 0 — север, по часовой
	var i := posmod(int(round(ang / (TAU / 8.0))), 8)
	return N[i]

func _on_landed(c: SupplyCrate) -> void:
	crate_landed.emit(c)

func _on_opened(c: SupplyCrate, by: Node) -> void:
	crate_opened.emit(c, by)
	print("[supply] ящик №%d открыл(а) %s t=%d" % [c.number, Game.display_name(by), int(Game.match_time)])
	if not by.is_in_group(&"player"):
		var p := get_tree().get_first_node_in_group(&"player") as Node3D
		if p and p.global_position.distance_to(c.global_position) < 260.0:
			Events.toast.emit("Посылку забрал(а) %s" % Game.display_name(by))

# ------------------------------------------------------------ запросы

func crates() -> Array[SupplyCrate]:
	var out: Array[SupplyCrate] = []
	for n in get_tree().get_nodes_in_group(&"supply_crates"):
		if n is SupplyCrate and not n.is_queued_for_deletion():
			out.append(n as SupplyCrate)
	return out

func available_crates() -> Array[SupplyCrate]:
	var out: Array[SupplyCrate] = []
	for c in crates():
		if c.is_available():
			out.append(c)
	return out

## Ближайший неоткрытый (приземлившийся) ящик в радиусе r.
func crate_near(pos: Vector3, r: float) -> SupplyCrate:
	var best: SupplyCrate = null
	var bd := r
	for c in available_crates():
		var d := c.global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = c
	return best

## Метки для мини-карты (Minimap рисует узлы группы map_markers).
func map_markers(viewer: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in crates():
		if c.state != SupplyCrate.State.OPENED:
			out.append(c.marker())
	if not next_drop.is_empty() and viewer and BuildEnv.inv_count(viewer, &"radio") > 0:
		var left := float(next_drop.time) - Game.match_time
		if left <= RADIO_LEAD:
			out.append({"pos": next_drop.pos, "color": SupplyModels.TIER_COLORS[clampi(int(next_drop.tier), 0, 2)], "kind": &"predicted",
				"label": "сброс через %d с" % int(maxf(left, 0.0))})
	return out

func radio_text(viewer: Node3D) -> String:
	if next_drop.is_empty():
		return "Рация: в эфире тихо"
	var left := float(next_drop.time) - Game.match_time
	if left > RADIO_LEAD * 2.0:
		return "Рация: «…следующий борт не раньше чем через %d мин…»" % int(ceil(left / 60.0))
	return "Рация: «…сброс через %d с — %s…»" % [int(maxf(left, 0.0)), _where(next_drop, viewer)]

# ------------------------------------------------------------ снаряжение

## Бронежилет в инвентаре: половина урона от пуль/осколков уходит в пластины.
func filter_damage(ch: Node, amount: float, kind: StringName) -> float:
	if not kind in [&"bullet", &"explosion"] or BuildEnv.inv_count(ch, &"armor_vest") <= 0:
		return amount
	var pool := float(ch.get_meta(&"supply_armor", SupplyItems.ARMOR_HP))
	var absorb := minf(amount * 0.5, pool)
	pool -= absorb
	if pool <= 0.5:
		BuildEnv.inv_remove(ch, &"armor_vest", 1)
		ch.remove_meta(&"supply_armor")
		if ch.is_in_group(&"player"):
			Events.toast.emit("Пластины бронежилета разбиты")
	else:
		ch.set_meta(&"supply_armor", pool)
	return amount - absorb

## Сигнальные ракеты: красный свет и дым за снарядом.
func _on_node_added(n: Node) -> void:
	if n is CombatProjectile and (n as CombatProjectile).ammo_id == &"flare":
		var g := SupplyFx.FlareGlow.new()
		g.target = n as Node3D
		(func() -> void:
			var host := get_tree().current_scene if get_tree().current_scene else self
			host.add_child(g)
			if is_instance_valid(g.target):
				g.global_position = g.target.global_position
		).call_deferred()
