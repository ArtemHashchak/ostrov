extends Node
## FaunaExt (v5.2, агент K) — живые мелочи мира вокруг игрока; дочерний узел Fauna.
##  • ветер срывает кокосы с пальм (сильнее ветер — чаще; падающий кокос бьёт — flora_pickup.gd);
##  • на бегу можно споткнуться о лежащий кокос (Player.stumble);
##  • морские ежи на рифе: наступил босиком — укол и хромота (Player.limp), обувь — «Сандалии»;
##  • чайки воруют еду: с земли (ItemPickup с едой у пляжа) и из рук, если долго стоять с ней;
##  • приручённый попугай кричит, когда рядом чужой (бот/игрок другой команды).
## Всё — только около игрока (дёшево: медленный тик 1 с, быстрый 0.1 с).

var fauna: Node = null
var debug_wind: float = -1.0          # тесты: принудительная скорость ветра (м/с)
var _slow_t := 0.0
var _fast_t := 0.0
var _rng := RandomNumberGenerator.new()
var _still_t := 0.0                    # сколько игрок стоит с едой в руке
var _urchin_cd := 0.0
var _alarm_seen: Dictionary = {}       # id чужого → время последнего крика
var stats := {"wind_drops": 0, "stumbles": 0, "urchin_stings": 0, "gull_thefts": 0, "parrot_alarms": 0}

const URCHIN_DMG := 6.0
const URCHIN_LIMP_S := 90.0
const GULL_GROUND_R := 45.0
const GULL_HAND_STILL_S := 25.0

func _ready() -> void:
	_rng.seed = 7351
	process_physics_priority = 10

func _physics_process(dt: float) -> void:
	_fast_t += dt
	_slow_t += dt
	_urchin_cd = maxf(0.0, _urchin_cd - dt)
	if _fast_t >= 0.1:
		_fast(_fast_t)
		_fast_t = 0.0
	if _slow_t >= 1.0:
		_slow(_slow_t)
		_slow_t = 0.0

func _player() -> Node3D:
	return get_tree().get_first_node_in_group(&"player") as Node3D

func _world() -> Node:
	return Fauna._world_of(self) if Fauna.instance() else null

func wind_speed() -> float:
	if debug_wind >= 0.0:
		return debug_wind
	var w := _world()
	return float(w.call(&"wind_speed")) if w and w.has_method(&"wind_speed") else 0.0

# ============================== быстрый тик ==============================

func _fast(dt: float) -> void:
	var pl := _player()
	if pl == null or not is_instance_valid(pl):
		return
	_check_stumble(pl)
	_check_urchins(pl)
	_track_still(pl, dt)

func _check_stumble(pl: Node3D) -> void:
	if not pl.has_method(&"stumble") or not (pl is CharacterBody3D):
		return
	var cb := pl as CharacterBody3D
	if not cb.is_on_floor():
		return
	var hs := Vector2(cb.velocity.x, cb.velocity.z).length()
	if hs < 2.2:
		return
	var now := Time.get_ticks_msec() * 0.001
	var fwd := Vector3(cb.velocity.x, 0.0, cb.velocity.z).normalized()
	for n in get_tree().get_nodes_in_group(&"flora_pickups"):
		var fp := n as Node3D
		if fp == null or StringName(fp.get(&"item_id")) != &"coconut" or fp.has_meta(&"carried_by"):
			continue
		var dp := fp.global_position - pl.global_position
		if absf(dp.y) > 0.5 or Vector2(dp.x, dp.z).length() > 0.32:
			continue
		if float(fp.get_meta(&"stepped_t", -10.0)) > now - 1.5:
			continue
		fp.set_meta(&"stepped_t", now)
		var sprint := bool(pl.get(&"sprinting"))
		if _rng.randf() < (0.5 if sprint else 0.2):
			pl.call(&"stumble")
			stats.stumbles += 1
		# кокос из-под ноги откатывается вперёд
		if fp is RigidBody3D and (fp as RigidBody3D).freeze:
			var to := fp.global_position + fwd * 0.35
			var w := _world()
			if w and w.has_method(&"height_at"):
				to.y = float(w.call(&"height_at", to.x, to.z)) + 0.12
			fp.global_position = to

## Морские ежи: ступня у дна рядом с ежом — укол (без обуви), хромота.
func _check_urchins(pl: Node3D) -> void:
	if _urchin_cd > 0.0:
		return
	var rl := ReefLife.instance()
	if rl == null:
		return
	var wl := BuildEnv.water_level()
	var p := pl.global_position
	if p.y > wl - 0.15:
		return   # не в воде
	for q in rl.urchins_near(p, 0.6):
		if absf(p.y - q.y) > 0.4 or Vector2(p.x - q.x, p.z - q.z).length() > 0.42:
			continue
		_urchin_cd = 3.0
		if has_footwear(pl):
			if pl.is_in_group(&"player"):
				Events.toast.emit("Под ногой морской ёж — сандалии спасли")
			return
		if pl.has_method(&"apply_damage"):
			pl.call(&"apply_damage", URCHIN_DMG, self, &"urchin")
		if pl.has_method(&"limp"):
			pl.call(&"limp", URCHIN_LIMP_S)
		stats.urchin_stings += 1
		if pl.is_in_group(&"player"):
			Events.toast.emit("Наступил на морского ежа! Иглы в ступне — хромаете")
		return

static func has_footwear(ch: Node) -> bool:
	var inv: Variant = ch.get(&"inventory")
	if not inv is Inventory:
		return false
	for sl in (inv as Inventory).slots:
		if sl.is_empty():
			continue
		var d := Items.get_item(sl.get("id", &""))
		if d and d.data.get("footwear", false):
			return true
	return false

func _track_still(pl: Node3D, dt: float) -> void:
	var held: StringName = pl.call(&"held_item") if pl.has_method(&"held_item") else &""
	var d := Items.get_item(held) if held != &"" else null
	var moving := pl is CharacterBody3D and Vector2((pl as CharacterBody3D).velocity.x, (pl as CharacterBody3D).velocity.z).length() > 0.25
	if d and d.kind == &"food" and not moving:
		_still_t += dt
	else:
		_still_t = 0.0

# ============================== медленный тик ==============================

func _slow(dt: float) -> void:
	var pl := _player()
	if pl == null or not is_instance_valid(pl):
		return
	_wind_coconuts(pl, dt)
	_gull_thefts(pl)
	_parrot_alarm()

## Ветер срывает кокосы: от ~6.5 м/с, сильнее — чаще (шторм — кокосопад).
func _wind_coconuts(pl: Node3D, dt: float) -> void:
	var ws := wind_speed()
	if ws < 6.5:
		return
	var rate := 0.004 * pow(ws - 6.0, 1.3)   # на один кокос в секунду
	for n in get_tree().get_nodes_in_group(&"choppable"):
		var t := n as Node3D
		# не у всех choppable есть поля kind/coconuts (деревья flora v5, пни) — get даёт null
		if t == null or str(t.get(&"kind")) != "palm" or t.get(&"felled") == true:
			continue
		var cv = t.get(&"coconuts")
		var c := int(cv) if cv != null else 0
		if c <= 0 or t.global_position.distance_to(pl.global_position) > 60.0:
			continue
		if _rng.randf() < rate * c * dt:
			t.call(&"_drop_coconut", null)
			stats.wind_drops += 1

## Чайки: еда на земле у пляжа — пикируют и уносят; еда в руке у застывшего игрока — тоже.
func _gull_thefts(pl: Node3D) -> void:
	var f: Node = fauna
	if f == null:
		return
	for fl: Dictionary in f.get(&"flocks"):
		if StringName(fl.get("species", &"")) != &"gull" or fl.get("mode", &"fly") == &"perch" and Routines.mode_now(&"gull", self) == &"rest":
			continue
		var home: Vector3 = fl.get("pos", fl.get("home", Vector3.ZERO))
		if Vector2(home.x - pl.global_position.x, home.z - pl.global_position.z).length() > 160.0:
			continue
		if _flock_busy(fl):
			continue
		var tgt: Node3D = null
		if _still_t > GULL_HAND_STILL_S and _near_beach(pl.global_position) \
				and Vector2(home.x - pl.global_position.x, home.z - pl.global_position.z).length() < 80.0:
			tgt = pl
			_still_t = 0.0
		else:
			tgt = _food_on_ground(home)
		if tgt == null:
			continue
		var g := _free_gull(fl)
		if g == null:
			continue
		var sq := _is_fish_pickup(tgt)
		g.set_meta(&"dive", {"target": tgt, "phase": &"in", "t": 0.0, "squabble": sq})
		tgt.set_meta(&"gull_target", true)
		# v5.2 (агент O): рыба на берегу — слетаются 2–3 чайки и дерутся за неё
		if sq:
			for extra in 2:
				var g2 := _free_gull(fl)
				if g2 == null:
					break
				g2.set_meta(&"dive", {"target": tgt, "phase": &"in", "t": randf_range(0.0, 1.2), "squabble": true})

## Подобранная рыба (сырая/приготовленная) на земле — за неё чайки дерутся.
func _is_fish_pickup(t: Node3D) -> bool:
	if not (t is ItemPickup):
		return false
	for st: Dictionary in (t as ItemPickup).stacks:
		if String(st.get("id", "")).contains("fish"):
			return true
	return false

func _flock_busy(fl: Dictionary) -> bool:
	for m in fl.get("members", []):
		if is_instance_valid(m) and (m as Node).has_meta(&"dive"):
			return true
	return false

func _free_gull(fl: Dictionary) -> Animal:
	for m in fl.get("members", []):
		var a := m as Animal
		if a and is_instance_valid(a) and not a.dead and not a.tamed and not a.has_meta(&"dive"):
			return a
	return null

func _near_beach(p: Vector3) -> bool:
	var b := Fauna.biome_of(self, p.x, p.z)
	return b == &"beach" or b == &"water"

func _food_on_ground(home: Vector3) -> Node3D:
	for n in get_tree().get_nodes_in_group(&"pickups"):
		var p := n as ItemPickup
		if p == null or not p.is_inside_tree() or p.has_meta(&"gull_target") or p.has_meta(&"carried_by"):
			continue
		if Vector2(p.global_position.x - home.x, p.global_position.z - home.z).length() > GULL_GROUND_R:
			continue
		if not _near_beach(p.global_position):
			continue
		for s: Dictionary in p.stacks:
			var d := Items.get_item(s.id)
			if d and d.kind == &"food":
				return p
	return null

## Попугай-сторож: приручённый попугай кричит, если в 22 м чужой (не своя команда).
func _parrot_alarm() -> void:
	var now := Time.get_ticks_msec() * 0.001
	for n in get_tree().get_nodes_in_group(&"tamed_animals"):
		var a := n as Animal
		if a == null or a.dead or a.species != &"parrot":
			continue
		for c in get_tree().get_nodes_in_group(&"characters"):
			var ch := c as Node3D
			if ch == null or ch == a.owner_node or not a._alive(ch):
				continue
			var t: Variant = ch.get(&"team")
			if t != null and int(t) == a.team and a.team >= 0:
				continue
			if ch.global_position.distance_to(a.global_position) > 22.0:
				continue
			var key := ch.get_instance_id()
			if now - float(_alarm_seen.get(key, -100.0)) < 20.0:
				continue
			_alarm_seen[key] = now
			a._sound(a.cfg.get("sound", &"parrot"), 8.0)
			a.anim_event(&"alarm")
			stats.parrot_alarms += 1
			if a.owner_node and a.owner_node.is_in_group(&"player"):
				Events.toast.emit("Попугай кричит — рядом чужой!")
			var per := get_tree().root.get_node_or_null(^"Perception")
			if per:
				per.call(&"emit", &"alarm", a.global_position, 60.0, 1.0, a)
			break
