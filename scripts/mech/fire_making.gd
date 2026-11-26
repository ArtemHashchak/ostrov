class_name FireMaking
## Разжечь огонь (V5): чем — газовая горелка, зажигалка, огниво, линза (стекло/бутылка на
## солнце), лучковое сверло, трение руками. Шанс зависит от влажности (игрок мокрый,
## мир сырой, дождь без укрытия) и трута (шелуха кокоса — лучший, расходуется).
## Мокрые дрова дымят сильнее (meta smoke_amount на костре — для Perception: дым виден).
##   FireMaking.attempt(ch, fire_pos) -> {ok: bool, chance: float, method: StringName, msg: String}

const METHODS := [
	# id предмета, название, базовый шанс, штраф за сырость (0..1)
	[&"gas_torch", "газовой горелкой", 1.0, 0.0],
	[&"lighter", "зажигалкой", 0.97, 0.6],
	[&"flint_steel", "огнивом", 0.85, 0.7],
	[&"lens", "линзой", 0.75, 0.8],
	[&"fire_drill", "лучковым сверлом", 0.6, 0.9],
	[&"hands", "трением", 0.4, 0.95],
]
## Тесты: ≥0 — фиксированный шанс (1 — всегда загорается).
static var force_chance := -1.0

static func wet_level(ch: Node, pos: Vector3) -> float:
	var wet := 0.0
	var body: Variant = ch.get(&"body") if ch else null
	if body is Object and &"wetness" in body:
		wet = float(body.get(&"wetness")) * 0.7
	var w := BuildEnv.world()
	if w and w.has_method(&"wetness"):
		wet = maxf(wet, float(w.call(&"wetness")))
	var rain := Survival.rain()
	if rain > 0.05 and not _sheltered(ch, pos):
		wet = maxf(wet, rain)
	return clampf(wet, 0.0, 1.0)

static func _sheltered(ch: Node, pos: Vector3) -> bool:
	var c3 := ch as Node3D
	if c3 == null or not c3.is_inside_tree():
		return false
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.UP * 7.0)
	if ch is CollisionObject3D:
		q.exclude = [(ch as CollisionObject3D).get_rid()]
	return not c3.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

static func _has(ch: Node, id: StringName) -> bool:
	return Survival.count(ch, id) > 0

static func best_method(ch: Node) -> Array:
	var w := BuildEnv.world()
	var sun := float(w.call(&"sun_elevation")) if w and w.has_method(&"sun_elevation") else 0.5
	for m: Array in METHODS:
		var id: StringName = m[0]
		if id == &"hands":
			return m
		if id == &"lens":
			if (_has(ch, &"glass_shard") or _has(ch, &"bottle_empty")) and rad_to_deg(asin(clampf(sun, -1.0, 1.0))) > DataTables.f("balance", "fire/lens_needs_sun_elev", 20.0):
				return m
			continue
		if _has(ch, id):
			return m
	return METHODS[METHODS.size() - 1]

static func chance(ch: Node, pos: Vector3) -> Dictionary:
	var m := best_method(ch)
	var c: float = m[2]
	var wet := wet_level(ch, pos)
	c *= 1.0 - float(m[3]) * wet
	var husk := _has(ch, &"coconut_husk")
	if husk and m[0] != &"gas_torch":
		c = minf(1.0, c + DataTables.f("balance", "fire/husk_bonus", 0.35) * (1.0 - wet))
	elif wet > DataTables.f("balance", "fire/dry_tinder_needed", 0.35) and m[0] != &"gas_torch":
		c *= 0.5
	return {"chance": clampf(c, 0.0, 1.0), "method": m[0], "name": m[1], "wet": wet, "husk": husk}

static func attempt(ch: Node, pos: Vector3) -> Dictionary:
	var r := chance(ch, pos)
	if force_chance >= 0.0:
		r["chance"] = force_chance
	var ok := randf() < float(r.chance)
	if bool(r.husk) and r.method != &"gas_torch":
		Survival.take(ch, &"coconut_husk", 1)
	r["ok"] = ok
	if ok:
		r["msg"] = "Разжёг %s" % r.name
	else:
		var why := " — всё сырое" if float(r.wet) > 0.5 else ""
		r["msg"] = "Не разгорелось (%s, шанс ~%d%%)%s" % [r.name, roundi(float(r.chance) * 100.0), why]
	r["smoke_amount"] = 0.6 + 0.8 * float(r.wet)
	return r
