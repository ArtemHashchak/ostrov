extends TestCase
## SUPPLY — посылки спонсоров: ускоренный сброс по расписанию (самолёт → ящик на
## парашюте), приземление и дым, метка на карте, вскрытие удержанием E (и прерывание
## уроном), выдача лута, газовая горелка (кипячение морской воды в котелке), автомат
## (магазин, перезарядка, очередь, расход патронов), ракетница, бронежилет, ласты,
## ящик на воде. Скриншоты: падающий ящик с парашютом, открытый ящик, автомат в руках.

var p: Player
var sup: Supply
var combat: Combat

func _init() -> void:
	timeout_sec = 1400.0

func aim_at(target: Vector3) -> void:
	var d := target - p.get_eye_position()
	p.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))

func put(id: StringName, n: int, slot: int) -> void:
	p.inventory.set_slot(slot, {"id": id, "n": n})

func select(id: StringName) -> void:
	for i in Inventory.HOTBAR:
		if p.inventory.get_slot(i).get("id", &"") == id:
			p.inventory.select(i)
			return

func ground(x: float, z: float) -> Vector3:
	return Vector3(x, BuildEnv.height_at(x, z), z)

## Нажать E и держать (событие доходит до _unhandled_input игрока → interact).
func hold_interact(sec: float) -> void:
	var ev := InputEventAction.new()
	ev.action = &"interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await wait(sec)
	var up := InputEventAction.new()
	up.action = &"interact"
	up.pressed = false
	Input.parse_input_event(up)
	await wait_frames(2)

## Открытое место на суше (без деревьев/камней в радиусе r над землёй) — для съёмки.
func clear_spot(r: float) -> Vector3:
	var space := (scene as Node3D).get_world_3d().direct_space_state
	var sh := SphereShape3D.new()
	sh.radius = r
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	for ring: float in [36.0, 30.0, 40.0, 26.0, 44.0]:
		for k in 24:
			var a := TAU * k / 24.0
			var g := ground(cos(a) * ring, sin(a) * ring)
			if g.y < BuildEnv.water_level() + 0.8:
				continue
			q.transform = Transform3D(Basis(), g + Vector3.UP * (r + 0.6))
			if space.intersect_shape(q, 1).is_empty():
				return g
	return ground(36.0, 0.0)

func wait_until(cond: Callable, max_sec: float, step: float = 0.25) -> bool:
	var t := 0.0
	while t < max_sec:
		if cond.call():
			return true
		await wait(step)
		t += step
	return bool(cond.call())

func run() -> void:
	await wait(1.0)
	p = get_tree().get_first_node_in_group(&"player") as Player
	check(p != null, "игрок есть")
	p.inventory.remove(&"flag", 1) # руки свободны для съёмки
	combat = (load("res://scenes/combat/combat.tscn") as PackedScene).instantiate() as Combat
	scene.add_child(combat)
	sup = Supply.new()
	scene.add_child(sup)
	await wait_frames(3)
	check(Supply.instance() == sup, "Supply.instance()")
	check(p.get_node_or_null(^"SupplyController") != null, "SupplyController прицеплен к игроку")
	for id: StringName in [&"rifle", &"shotgun", &"flare_gun", &"grenade", &"machete", &"chainsaw", &"gas_torch", &"gas_can",
			&"binoculars", &"flashlight", &"radio", &"fins", &"armor_vest", &"medkit", &"canned_food", &"rifle_ammo"]:
		check(Items.get_item(id) != null, "предмет %s зарегистрирован" % id)
	check(Combat.is_weapon(&"rifle") and int(Combat.weapon(&"rifle").mag) == 20, "автомат в Combat.WEAPONS (магазин 20)")
	# лут по редкостям
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var leg_ok := true
	for k in 20:
		var l := SupplyItems.roll_loot(2, rng)
		var has_leg := false
		for s in l:
			if s.id in [&"rifle", &"grenade", &"armor_vest", &"shotgun"]:
				has_leg = true
		leg_ok = leg_ok and has_leg and l.size() >= 3
	check(leg_ok, "легендарный ящик всегда с ценной вещью")
	check(SupplyItems.roll_loot(0, rng).size() >= 2, "обычный ящик не пустой")
	check(Supply.compass(Vector2(10, -10)) == "северо-восток" and Supply.compass(Vector2(0, 5)) == "юг", "стороны света")

	# ---------- расписание: первый сброс назначен на 8–12 мин ----------
	await wait(0.5)
	check(not sup.next_drop.is_empty(), "следующий сброс запланирован")
	var dt0 := float(sup.next_drop.get("time", 0.0)) - Game.match_time
	check(dt0 > 400.0 and dt0 < 730.0, "первый сброс через %.0f с (8–12 мин)" % dt0)

	# ---------- ускоренный сброс: самолёт → ящик ----------
	sup.plane_lead = 260.0
	sup.schedule_in(1.0, 2)
	var target := clear_spot(6.0)
	sup.next_drop.pos = target
	sup.wind = Vector3(0.3, 0, 0.1)
	var out := Vector3(target.x, 0, target.z).normalized()
	var cam_spot := ground(target.x + out.x * 9.0 + out.z * 3.0, target.z + out.z * 9.0 - out.x * 3.0)
	p.global_position = cam_spot + Vector3.UP * 0.1
	p.velocity = Vector3.ZERO
	check(await wait_until(func() -> bool: return get_tree().get_nodes_in_group(&"supply_planes").size() > 0, 5.0), "самолёт вылетел")
	var plane := get_tree().get_nodes_in_group(&"supply_planes")[0] as Node3D
	aim_at(plane.global_position)
	await wait(0.3)
	await shot("00_plane")
	Engine.time_scale = 4.0
	check(await wait_until(func() -> bool: return sup.crates().size() > 0, 10.0), "ящик сброшен")
	var crate := sup.crates()[0]
	check(crate.is_falling() and crate.tier == 2, "ящик падает (легендарный)")
	check(sup.map_markers(p).size() >= 1, "метка ящика на мини-карте")
	await wait_until(func() -> bool: return crate.global_position.y < target.y + 14.0, 40.0, 0.1)
	Engine.time_scale = 1.0
	aim_at(crate.global_position + Vector3.UP * 3.5)
	await wait(0.4)
	await shot("01_falling")
	check(crate.get_node_or_null(^"Parachute") != null, "парашют раскрыт")
	Engine.time_scale = 3.0
	check(await wait_until(func() -> bool: return not crate.is_falling(), 20.0, 0.1), "ящик приземлился")
	Engine.time_scale = 1.0
	var gy := BuildEnv.height_at(crate.global_position.x, crate.global_position.z)
	check(crate.state == SupplyCrate.State.LANDED and absf(crate.global_position.y - gy) < 0.3,
		"стоит на земле (y=%.2f, земля %.2f)" % [crate.global_position.y, gy])
	check(Vector2(crate.global_position.x - target.x, crate.global_position.z - target.z).length() < 3.0, "упал у цели (%.1f м)" % Vector2(crate.global_position.x - target.x, crate.global_position.z - target.z).length())
	check(crate.find_child("SmokeColumn", true, false) != null, "цветной дым")
	await wait(3.0)
	aim_at(crate.global_position + Vector3.UP * 4.0)
	await wait(0.3)
	await shot("02_landed_smoke")

	# ---------- вскрытие: урон прерывает ----------
	crate.loot = [{"id": &"rifle", "n": 1}, {"id": &"rifle_ammo", "n": 30}, {"id": &"gas_torch", "n": 1}, {"id": &"gas_can", "n": 1},
		{"id": &"pot", "n": 1}, {"id": &"flare_gun", "n": 1}, {"id": &"flare", "n": 2}, {"id": &"armor_vest", "n": 1}, {"id": &"fins", "n": 1}]
	var front := crate.global_position + crate.global_basis.z * -1.6
	p.global_position = ground(front.x, front.z) + Vector3.UP * 0.1
	p.velocity = Vector3.ZERO
	await wait(0.4)
	aim_at(crate.global_position + Vector3.UP * 0.3)
	await wait_frames(3)
	check(p._interact_target() == crate, "игрок смотрит на ящик")
	check(String(crate.get_interact_text(p)).contains("удерживай"), "подсказка: %s" % crate.get_interact_text(p))
	var ev := InputEventAction.new()
	ev.action = &"interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await wait(1.2)
	check(crate.opener == p and crate.progress() > 0.2, "вскрытие идёт (%.0f%%)" % (crate.progress() * 100.0))
	p.apply_damage(2.0, null, &"melee")
	await wait_frames(2)
	check(crate.opener == null and crate.is_available(), "урон прервал вскрытие")
	var up := InputEventAction.new()
	up.action = &"interact"
	up.pressed = false
	Input.parse_input_event(up)
	await wait(0.3)
	# ---------- вскрытие до конца ----------
	await hold_interact(3.5)
	check(crate.state == SupplyCrate.State.OPENED, "ящик открыт удержанием E")
	check(p.inventory.count(&"rifle") == 1 and p.inventory.count(&"rifle_ammo") == 30 and p.inventory.count(&"gas_torch") == 1,
		"лут в инвентаре (автомат, патроны 30, горелка)")
	check(sup.map_markers(p).is_empty(), "открытый ящик убран с карты")
	await wait(0.8)
	p.global_position = ground(front.x, front.z) + Vector3.UP * 0.1 + crate.global_basis.x * 0.6
	aim_at(crate.global_position + Vector3.UP * 0.25)
	await wait(0.4)
	await shot("03_opened")

	# ---------- газовая горелка: кипячение морской воды ----------
	var sc := p.get_node(^"SupplyController") as SupplyController
	put(&"water_salt", 3, 8)
	select(&"gas_torch")
	await wait(0.4)
	check(p.held_item() == &"gas_torch", "горелка в руке")
	await tap(&"aim")
	check(not sc.job.is_empty() and sc.job.kind == &"boil", "горелка: кипячение пошло")
	await wait(2.0)
	check(sc.find_child("TorchFlame", true, false) != null or p.hands.find_child("TorchFlame", true, false) != null, "пламя горелки")
	await shot("04_torch")
	await wait(SupplyController.BOIL_TIME - 1.4)
	check(sc.job.is_empty() and p.inventory.count(&"water_salt") == 0 and p.inventory.count(&"water_bottle") >= 3,
		"морская вода вскипела без костра (пресной: %d)" % p.inventory.count(&"water_bottle"))
	check(p.inventory.count(&"gas_can") == 0 and sc.fuel_left(&"gas_can") < SupplyItems.GAS_PER_CAN - 5.0,
		"газ расходуется (осталось %.0f с)" % sc.fuel_left(&"gas_can"))

	# ---------- автомат: перезарядка, очередь, расход патронов ----------
	select(&"rifle")
	await wait(0.5)
	check(Combat.rounds(p, &"rifle") == 0, "магазин пуст")
	await tap(&"reload")
	await wait(0.2)
	check(Combat.is_reloading(p), "перезарядка (R)")
	await wait(float(Combat.weapon(&"rifle").reload) + 0.3)
	check(Combat.rounds(p, &"rifle") == 20 and p.inventory.count(&"rifle_ammo") == 10, "магазин 20, в запасе 10")
	p.global_position = ground(target.x + out.x * 6.0, target.z + out.z * 6.0) + Vector3.UP * 0.1
	await wait(0.3)
	aim_at(p.get_eye_position() + out * 10.0 + Vector3.DOWN * 0.6)
	Input.action_press(&"aim")
	await wait(0.6)
	await shot("05_rifle_ads")
	Input.action_release(&"aim")
	await wait(0.3)
	Input.action_press(&"attack")
	await wait(0.45)
	await shot("05b_rifle_fire")
	await wait(0.15)
	Input.action_release(&"attack")
	await wait(0.3)
	var left := Combat.rounds(p, &"rifle")
	check(left < 18 and left > 5, "очередь: выпущено %d патронов" % (20 - left))
	await tap(&"reload")
	await wait(float(Combat.weapon(&"rifle").reload) + 0.3)
	# GUNPLAY: тактическая перезарядка — магазин 20 + 1 в патроннике (WeaponDef.chamber)
	var want := mini(20 + (1 if left > 0 else 0), left + 10)
	check(Combat.rounds(p, &"rifle") == want and p.inventory.count(&"rifle_ammo") == 10 - (want - left),
		"дозарядка из запаса: %d в магазине, %d в запасе" % [Combat.rounds(p, &"rifle"), p.inventory.count(&"rifle_ammo")])

	# ---------- ракетница ----------
	select(&"flare_gun")
	await wait(0.4)
	await tap(&"reload")
	await wait(float(Combat.weapon(&"flare_gun").reload) + 0.3)
	aim_at(p.get_eye_position() + Vector3(5, 3, -5))
	await tap(&"attack")
	await wait(0.4)
	var glows := get_tree().get_nodes_in_group(&"supply_flares").size()
	check(glows == 1 and p.inventory.count(&"flare") == 1, "сигнальная ракета в воздухе (свет), осталась 1")

	# ---------- бронежилет и ласты ----------
	await wait_frames(2)
	check(is_equal_approx(float(p.get(&"swim_mul")), SupplyController.SWIM_MUL), "ласты ускоряют плавание")
	p.health = 100.0
	p.apply_damage(30.0, null, &"bullet")
	check(absf(p.health - 85.0) < 0.1, "бронежилет: пуля 30 → %.0f урона" % (100.0 - p.health))
	p.health = 100.0
	p.apply_damage(10.0, null, &"melee")
	check(absf(p.health - 90.0) < 0.1, "от удара жилет не спасает")
	p.health = 100.0

	# ---------- ящик в воде: плавает у берега ----------
	var sea := Vector3(78.0, BuildEnv.water_level(), 4.0)
	var c2 := sup.drop_now(sea, 0, false) as SupplyCrate
	check(c2 != null and c2.is_falling(), "второй ящик без самолёта")
	Engine.time_scale = 4.0
	await wait_until(func() -> bool: return not c2.is_falling(), 40.0, 0.1)
	await wait(2.0)
	Engine.time_scale = 1.0
	var ws := BuildEnv.water_surface(c2.global_position.x, c2.global_position.z)
	check(c2.state == SupplyCrate.State.FLOATING and absf(c2.global_position.y - (ws - 0.24)) < 0.4, "ящик плавает (y=%.2f, вода %.2f)" % [c2.global_position.y, ws])
	var shore0 := Vector2(c2.global_position.x, c2.global_position.z).length()
	p.global_position = ground(58.0, 10.0) + Vector3.UP * 0.1
	aim_at(c2.global_position + Vector3.UP * 2.0)
	await wait(2.0)
	await shot("06_floating")
	check(Vector2(c2.global_position.x, c2.global_position.z).length() < shore0, "дрейфует к берегу")
	print("[supply] сбросов: %d" % sup.drops)
