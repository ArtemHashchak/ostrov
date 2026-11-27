extends RefCounted
## Поведение животных v5.2 (агент K) — статические помощники для Animal (animal.gd держит
## автомат состояний, здесь — новые состояния и реакции, чтобы не раздувать animal.gd):
##  • распорядок дня (Routines, assets/data/routines.json): bask — греется на открытом месте,
##    hidden — уходит в укрытие (к дереву) или зарывается (крабы на пляже), rest — реже бродит;
##  • крабы замирают при медленном приближении и их можно поймать (E → «Живой краб»),
##    мелочь гибнет, если на неё наступить, краб утаскивает мелкие предметы с песка;
##  • пальмовый вор ночью тащит кокос к себе и ест его;
##  • восприятие: варан чует кровь и тушу по ветру, змея — дрожь земли от шагов,
##    ящерицы удирают от шагов раньше, чем подойдут вплотную.
## Анимаций новых нет — только движение и состояния (клипы/процедурная походка те же).

const PERCEIVERS: Array[StringName] = [&"monitor", &"snake", &"python", &"iguana", &"salamander"]
const OWN_STATES: Array[StringName] = [&"to_cover", &"rest_hidden", &"bask", &"investigate", &"feed",
	&"carry", &"fetch", &"drag"]
## Кого можно раздавить, наступив (мелочь ростом до ладони).
const SMALL_CRUSH: Array[StringName] = [&"crab", &"hermit_crab", &"salamander", &"centipede", &"scorpion", &"spider"]
const CARRY_MAX_KG := 1.0

# ============================ распорядок дня ============================

## Вызывается в конце Animal._think (после нрава): true — распорядок сам выбрал состояние.
static func apply_routine(a: Animal, _pl: Node3D, _d: float) -> bool:
	if a.tamed or a.scripted or a.cfg.get("fly", false):
		return false
	if not a.state in [&"idle", &"wander"]:
		return false
	match a.routine:
		&"hidden":
			if a.species in [&"crab", &"coconut_crab", &"hermit_crab"] and a._biome() == &"beach":
				a._set_state(&"burrow" if a.species != &"hermit_crab" else &"hide")
				a._warn_t = 30.0
				return true
			a.move_to = cover_near(a)
			a._set_state(&"to_cover")
			return true
		&"bask":
			a._set_state(&"bask")
			return true
	return false

## Укрытие рядом: ствол дерева/куст в 15 м (иначе — дом).
static func cover_near(a: Animal) -> Vector3:
	var p := a._nearest_tree_pos(a.global_position, 15.0, a.home)
	if p == a.home:
		return a.home
	# не вплотную к стволу — у корней, со стороны животного
	var to := a.global_position - p
	to.y = 0.0
	if to.length() > 0.01:
		p += to.normalized() * 0.6
	return p

## Мысли в собственных состояниях (вызывается вместо обычного нрава).
static func think_own(a: Animal, pl: Node3D, d: float) -> void:
	var fr := maxf(float(a.cfg.get("flee_r", 0.0)), float(a.cfg.get("aggro_r", 0.0)))
	match a.state:
		&"bask", &"rest_hidden":
			var want := &"bask" if a.state == &"bask" else &"hidden"
			if a.routine != want:
				a._set_state(&"idle")
				return
			# греющийся замечает раньше, спрятавшийся — позже
			var k := 1.0 if a.state == &"bask" else 0.55
			if pl and d < maxf(fr, 1.5) * k:
				a._set_state(&"idle")   # нрав решит: удрать, предупредить, напасть
				return
			if a.state == &"bask" and a.state_t > a._rng.randf_range(60.0, 120.0):
				a._pick_wander(4.0)   # переползти на соседний солнечный камень
		&"to_cover":
			if a.routine != &"hidden" or (pl and d < maxf(fr, 1.5)):
				a._set_state(&"idle")
		&"investigate":
			if a.state_t > 40.0:
				a._set_state(&"idle")
			elif pl and d < float(a.cfg.get("aggro_r", 0.0)):
				a._set_state(&"idle")
		&"feed":
			if a.state_t > float(a.get_meta(&"feed_s", 30.0)):
				a._set_state(&"idle")
			elif pl and d < maxf(fr, 1.5):
				drop_carried(a)
				a._set_state(&"idle")
		&"fetch", &"carry", &"drag":
			if pl and d < maxf(fr, 1.2):
				# спугнули — бросает ношу и удирает
				drop_carried(a)
				a.target = pl
				a._set_state(&"flee")
			elif a.state_t > 45.0:
				drop_carried(a)
				a._set_state(&"idle")

## Движение в собственных состояниях (из Animal._act).
static func act_own(a: Animal, dt: float) -> void:
	var walk := float(a.cfg["walk"])
	match a.state:
		&"to_cover":
			a._steer(a.move_to, walk, dt)
			if a._flat_dist(a.move_to) < 0.8 or a.state_t > 25.0:
				a._set_state(&"rest_hidden")
		&"investigate":
			a._steer(a.move_to, float(a.cfg["run"]) * 0.45, dt)
			if a._flat_dist(a.move_to) < 1.4:
				a.set_meta(&"feed_s", a._rng.randf_range(20.0, 40.0))
				a._set_state(&"feed")
		&"fetch":
			var tv: Variant = a.get_meta(&"carry_target") if a.has_meta(&"carry_target") else null
			if tv == null or not is_instance_valid(tv) or not (tv as Node3D).is_inside_tree():
				a._set_state(&"idle")
				return
			var t := tv as Node3D
			if t.has_meta(&"carried_by") and t.get_meta(&"carried_by") != a:
				a._set_state(&"idle")
				return
			a._steer(t.global_position, walk * 1.2, dt)
			if a._flat_dist(t.global_position) < 0.45 + (0.15 if a.species == &"coconut_crab" else 0.0):
				_pick_up(a, t)
		&"carry", &"drag":
			if a.carry_node == null or not is_instance_valid(a.carry_node):
				a.carry_node = null
				a._set_state(&"idle")
				return
			var sp := walk * (0.6 if a.state == &"carry" else 0.45)
			a._steer(a.move_to, sp, dt)
			_hold_carried(a)
			if a._flat_dist(a.move_to) < 0.6:
				drop_carried(a)
				if a.species == &"coconut_crab":
					a.set_meta(&"feed_s", a._rng.randf_range(40.0, 90.0))
					a._set_state(&"feed")   # ест кокос у себя
				else:
					a._set_state(&"idle")

# ============================ ноша: краб, пальмовый вор ============================

## Краб на пляже иногда утаскивает мелкий предмет (≤1 кг) на 5–8 м — к воде/норе.
static func try_crab_carry(a: Animal) -> bool:
	if a.routine == &"hidden" or a._biome() != &"beach" or a._rng.randf() > 0.25:
		return false
	var best: Node3D = null
	var bd := 6.0
	for n in a.get_tree().get_nodes_in_group(&"pickups"):
		var p := n as ItemPickup
		if p == null or not p.is_inside_tree() or p.has_meta(&"carried_by"):
			continue
		if _stacks_kg(p) > CARRY_MAX_KG:
			continue
		var dd := a._flat_dist(p.global_position)
		if dd < bd:
			bd = dd
			best = p
	if best == null:
		return false
	a.set_meta(&"carry_target", best)
	a._set_state(&"fetch")
	return true

static func _stacks_kg(p: ItemPickup) -> float:
	var kg := 0.0
	for s: Dictionary in p.stacks:
		var d := Items.get_item(s.id)
		kg += (d.weight if d else 0.3) * int(s.n)
	return kg

## Пальмовый вор: ночью (распорядок active) ищет лежащий кокос в 18 м и тащит к себе.
static func think_coconut_crab(a: Animal, pl: Node3D, d: float) -> bool:
	if a.tamed or a.routine != &"active" or not a.state in [&"idle", &"wander"]:
		return false
	if pl and d < float(a.cfg["flee_r"]) * 1.5:
		return false
	if a.state_t < 1.5:
		return false
	var best: Node3D = null
	var bd := 18.0
	for n in a.get_tree().get_nodes_in_group(&"flora_pickups"):
		var fp := n as Node3D
		if fp == null or not fp.is_inside_tree() or fp.has_meta(&"carried_by"):
			continue
		if StringName(fp.get(&"item_id")) != &"coconut" or int(fp.get(&"mode")) != 3:   # FloraPickup.REST
			continue
		var dd := a._flat_dist(fp.global_position)
		if dd < bd:
			bd = dd
			best = fp
	if best == null:
		return false
	a.set_meta(&"carry_target", best)
	a._set_state(&"fetch")
	return true

static func _pick_up(a: Animal, t: Node3D) -> void:
	a.carry_node = t
	t.set_meta(&"carried_by", a)
	if t is RigidBody3D:
		var rb := t as RigidBody3D
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.freeze = true
		rb.linear_velocity = Vector3.ZERO
	# куда нести: краб — к воде/норе, пальмовый вор — домой (к своему дереву)
	if a.species == &"coconut_crab":
		a.move_to = a.home if a._flat_dist(a.home) > 3.0 else a._nearest_tree_pos(a.global_position, 20.0, a.home)
		a._set_state(&"drag")
	else:
		var away := Vector3(a._rng.randf_range(-1, 1), 0.0, a._rng.randf_range(-1, 1)).normalized()
		var dest := a.global_position + away * a._rng.randf_range(5.0, 8.0)
		var w := a._towards_water(a.global_position)
		if a._rng.randf() < 0.6 and w != a.global_position:
			dest = a.global_position + (w - a.global_position).normalized() * a._rng.randf_range(5.0, 8.0)
		var g := Fauna.ground_y_at(a, dest.x, dest.z)
		if g < Fauna.water_y(a) + 0.05:
			dest = a.global_position + away * 4.0   # не в воду — у кромки
		a.move_to = dest
		a._set_state(&"carry")
	a._sound(a.cfg.get("sound", &"crab_click"), -2.0)

## Предмет держится у клешней (краб) или волочится сбоку (пальмовый вор).
static func _hold_carried(a: Animal) -> void:
	var n := a.carry_node
	var fwd := Vector3(-sin(a.heading), 0.0, -cos(a.heading))
	var off := 0.22 if a.species != &"coconut_crab" else 0.42
	var p := a.global_position + fwd * off
	var g := Fauna.ground_y_at(a, p.x, p.z)
	p.y = g + (0.07 if a.species != &"coconut_crab" else 0.12)
	n.global_position = p
	if a.species == &"coconut_crab":
		n.rotate_object_local(Vector3.RIGHT, 0.02)   # кокос перекатывается при волочении

## Бросить ношу на землю (спугнули/донёс/погиб).
static func drop_carried(a: Animal) -> void:
	var n := a.carry_node
	a.carry_node = null
	if a.has_meta(&"carry_target"):
		a.remove_meta(&"carry_target")
	if n == null or not is_instance_valid(n):
		return
	if n.has_meta(&"carried_by"):
		n.remove_meta(&"carried_by")
	var p := n.global_position
	var g := Fauna.ground_y_at(a, p.x, p.z)
	if n is FloraPickup:
		n.global_position = Vector3(p.x, g + 0.12, p.z)
		(n as FloraPickup).freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		(n as FloraPickup).freeze = true
	elif n is RigidBody3D:
		n.global_position = Vector3(p.x, g + 0.1, p.z)
		(n as RigidBody3D).freeze = false

# ============================ поймать, раздавить ============================

static func can_catch(a: Animal, by: Node) -> bool:
	if a.dead or a.tamed or not a.cfg.get("catch", false) or not (by is Node3D):
		return false
	if by.get(&"inventory") == null:
		return false
	if (by as Node3D).global_position.distance_to(a.global_position) > 1.8:
		return false
	if a.state in [&"freeze", &"burrow", &"rest_hidden", &"feed", &"drag"]:
		return true
	return a.state in [&"idle", &"bask"] and a._is_crouching(by)

static func catch_by(a: Animal, by: Node) -> void:
	var inv: Inventory = by.get(&"inventory")
	var n := 3 if a.species == &"coconut_crab" else 1
	var left := inv.add(&"crab_live", n) if inv else n
	if left >= n:
		Events.toast.emit("Некуда положить")
		return
	a._sound(a.cfg.get("sound", &"crab_click"), 2.0)
	if by.is_in_group(&"player"):
		Events.toast.emit("Пойман: %s" % a.display_name().to_lower())
	drop_carried(a)
	a.dead = true   # из учёта живых — сразу (туши нет: краб в мешке)
	a.queue_free()

## Наступили на мелочь (краб, сколопендра, скорпион, паук, саламандра): гибнет с хрустом.
## Зарывшийся в песок краб — цел. Только у камеры (lod 0).
static func check_crush(a: Animal) -> void:
	if a.carry_node != null and not a.state in [&"carry", &"drag", &"fetch"]:
		drop_carried(a)
	if not a.species in SMALL_CRUSH or a._crush_cd > 0.0 or a.state in [&"burrow", &"climb", &"on_tree", &"jump"]:
		return
	a._crush_cd = 0.12
	var box: Vector3 = a.cfg["box"]
	var r := 0.18 + maxf(box.x, box.z) * 0.35 * a.growth
	for c in a.get_tree().get_nodes_in_group(&"characters"):
		var ch := c as CharacterBody3D
		if ch == null or not a._alive(ch):
			continue
		var dp := ch.global_position - a.global_position
		if absf(dp.y) > 0.35 or Vector2(dp.x, dp.z).length() > r:
			continue
		if not ch.is_on_floor():
			continue
		var hs := Vector2(ch.velocity.x, ch.velocity.z).length()
		if hs < 0.6:
			continue
		a._sound(&"crunch", 2.0)
		var wn := a.get_tree().root.get_node_or_null(^"Wounds")
		if wn and wn.has_method(&"_drip_spot"):
			wn.call(&"_drip_spot", a.global_position + Vector3.UP * 0.05, 0.7)
		a.set_meta(&"crushed", true)
		a.die(ch)
		return

# ============================ восприятие ============================

static func on_stimulus(a: Animal, st: Dictionary) -> void:
	if a.state in [&"chase", &"attack"]:
		return
	var kind := StringName(st.kind)
	var src: Variant = st.get("source")
	var pos: Vector3 = st.pos
	var dist := a._flat_dist(pos)
	var hidden_k := 0.6 if a.routine == &"hidden" else 1.0
	match a.species:
		&"monitor":
			if kind in [&"blood", &"carrion"]:
				if src == a:
					return
				var r := float(st.radius) * downwind_k(a, pos) * hidden_k
				if dist <= r and a.state != &"feed":
					a.move_to = pos
					a._sound(a.cfg.get("sound", &"lizard"), -2.0)
					a._set_state(&"investigate")
		&"snake", &"python":
			if kind == &"step":
				# дрожь земли: тяжёлые шаги рядом — уползает; крадущегося не замечает
				var s := float(st.strength)
				if s > 0.35 and dist < float(st.radius) * 0.6 * hidden_k and src is Node3D:
					a.target = src as Node3D
					a._set_state(&"flee")
			elif kind == &"shot" and dist < 40.0 and src is Node3D:
				a.target = src as Node3D
				a._set_state(&"flee")
		&"iguana", &"salamander":
			if kind in [&"step", &"shot"] and src is Node3D and dist < float(st.radius) * 0.9 * hidden_k:
				if a.state != &"flee":
					a.target = src as Node3D
					a._set_state(&"flee")

## Множитель радиуса запаха по ветру: зверь с подветренной стороны чует в 2–2.5 раза дальше,
## с наветренной — вдвое хуже. Безветрие — 1.
static func downwind_k(a: Animal, src: Vector3) -> float:
	var w: Node = Fauna._world_of(a)
	if w == null or not w.has_method(&"wind_dir"):
		return 1.0
	var wd: Vector2 = w.call(&"wind_dir")
	var ws := float(w.call(&"wind_speed")) if w.has_method(&"wind_speed") else 3.0
	var to := Vector2(a.global_position.x - src.x, a.global_position.z - src.z)
	if to.length() < 0.5 or wd.length() < 0.01:
		return 1.0
	var k := to.normalized().dot(wd.normalized())   # 1 — точно по ветру от источника
	var wk := clampf(ws / 6.0, 0.0, 1.0)
	return 1.0 + (maxf(k, 0.0) * 1.5 - maxf(-k, 0.0) * 0.5) * wk

## Туша пахнет: раз в несколько секунд — раздражитель «падаль» (варан, падальщики).
static func emit_carrion(a: Animal) -> void:
	var per := a.get_tree().root.get_node_or_null(^"Perception") if a.is_inside_tree() else null
	if per:
		per.call(&"emit", &"carrion", a.global_position, 80.0, 1.0, a)

# ============================ чайка-воровка ============================

## Пикирование чайки (meta "dive" ставит FaunaExt): к еде на земле или в руке игрока →
## схватить одну штуку → улететь к стае. Убитая чайка роняет украденное (stolen → дроп).
static func tick_gull_dive(a: Animal, dt: float) -> void:
	var d: Dictionary = a.get_meta(&"dive")
	d["t"] = float(d.get("t", 0.0)) + dt
	var tv: Variant = d.get("target")
	var phase: StringName = d.get("phase", &"in")
	if phase == &"in" and (tv == null or not is_instance_valid(tv) or not (tv as Node3D).is_inside_tree() or float(d.t) > 25.0):
		phase = &"out"
		d["phase"] = phase
		d["t"] = 0.0
	var goal: Vector3
	var squab := false
	if phase == &"in":
		var t := tv as Node3D
		goal = t.global_position + Vector3.UP * (1.7 if t.is_in_group(&"player") else 0.25)
		# v5.2 (агент O): драка за рыбу — у добычи чайки 2–5 с кружат, подпрыгивают, клюют
		# друг друга и кричат; потом хватает ближайшая, остальные гонятся за ней
		if bool(d.get("squabble", false)):
			var near := Vector2(a.global_position.x - t.global_position.x, a.global_position.z - t.global_position.z).length()
			if near < 2.6:
				var now := float(d.get("sq", 0.0)) + dt
				d["sq"] = now
				if not d.has("sq_len"):
					d["sq_len"] = randf_range(2.5, 5.0)
				t.set_meta(&"sq_until", true)
				if now < float(d["sq_len"]):
					squab = true
					var ang := float(a.get_instance_id() % 997) * 0.37 + now * 1.6
					var hop := absf(sin(now * 7.0 + float(a.get_instance_id() % 13)))
					goal = t.global_position + Vector3(cos(ang), 0.0, sin(ang)) * 0.85 + Vector3.UP * (0.15 + hop * 0.6)
					if randf() < dt * 0.9:
						a._sound(a.cfg.get("sound", &"gull"), 4.0)
	else:
		var ch: Variant = d.get("chase")
		if ch != null and is_instance_valid(ch) and float(d.t) < 5.0:
			goal = (ch as Node3D).global_position + Vector3(sin(float(d.t) * 3.0), 0.4, cos(float(d.t) * 3.0)) * 1.2
		else:
			d.erase("chase")
			var c: Vector3 = a.flock.get("pos", a.home) if not a.flock.is_empty() else a.home
			goal = c + a.flock_offset + Vector3.UP * 6.0
	var to := goal - a.global_position
	var dist := to.length()
	var sp := float(a.cfg["run"]) * (0.75 if phase == &"in" else 0.9)
	if dist > 0.05:
		var step := minf(sp * dt, dist)
		a.global_position += to / dist * step
		a.heading = lerp_angle(a.heading, atan2(-to.x, -to.z), clampf(dt * 5.0, 0.0, 1.0))
	a.speed = sp
	a.state = &"fly"
	a.rotation.y = a.heading
	var g := Fauna.ground_y_at(a, a.global_position.x, a.global_position.z)
	a.global_position.y = maxf(a.global_position.y, maxf(g, Fauna.water_y(a)) + 0.15)
	a.alt = a.global_position.y - g
	if phase == &"in" and dist < 0.7 and not squab:
		_gull_grab(a, tv as Node3D)
		d["phase"] = &"out"
		d["t"] = 0.0
	elif phase == &"out" and ((dist < 2.0 and d.get("chase") == null) or float(d.t) > (6.0 if d.get("chase") != null else 12.0)):
		a.remove_meta(&"dive")
		return
	a.set_meta(&"dive", d)

static func _gull_grab(a: Animal, t: Node3D) -> void:
	if t.has_meta(&"gull_target"):
		t.remove_meta(&"gull_target")
	var got: StringName = &""
	if t is ItemPickup:
		var pu := t as ItemPickup
		for i in pu.stacks.size():
			var s: Dictionary = pu.stacks[i]
			var it := Items.get_item(s.id)
			if it and it.kind == &"food":
				got = s.id
				s.n = int(s.n) - 1
				if int(s.n) <= 0:
					pu.stacks.remove_at(i)
				break
		if pu.stacks.is_empty():
			pu.queue_free()
	elif t.has_method(&"held_item"):
		var id: StringName = t.call(&"held_item")
		var inv: Variant = t.get(&"inventory")
		var it := Items.get_item(id)
		if it and it.kind == &"food" and inv is Inventory and (inv as Inventory).remove(id, 1):
			got = id
	if got == &"":
		return
	# остальные чайки, дравшиеся за ту же добычу, гонятся за победительницей
	for m in (a.flock.get("members", []) if not a.flock.is_empty() else []):
		if m != a and is_instance_valid(m) and (m as Node).has_meta(&"dive"):
			var od: Dictionary = (m as Node).get_meta(&"dive")
			if od.get("target") == t:
				od["phase"] = &"out"
				od["t"] = 0.0
				od["chase"] = a
				(m as Node).set_meta(&"dive", od)
	var fe0: Node = a.fauna.get(&"ext") if a.fauna else null
	if fe0 and t.has_meta(&"sq_until"):
		var fst: Dictionary = fe0.get(&"stats")
		fst["gull_fights"] = int(fst.get("gull_fights", 0)) + 1
	a.stolen.append({"id": got, "n": 1})
	a._sound(a.cfg.get("sound", &"gull"), 6.0)
	var fe: Node = a.fauna.get(&"ext") if a.fauna else null
	if fe:
		fe.stats.gull_thefts += 1
	if t.is_in_group(&"player"):
		Events.toast.emit("Чайка выхватила из рук: %s!" % Items.item_name(got).to_lower())
