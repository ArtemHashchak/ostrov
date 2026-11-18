extends CombatTestCase
## Стрельба по манекену: зоны попадания (голова ×2, ноги ×0.75), перезарядка мушкета
## (порох+пуля), арбалет, лук, пистоль, динамит; API для ботов; скриншоты оружия.

var dummy: TrainingDummy

func _init() -> void:
	timeout_sec = 1500.0

func last_dummy_hit() -> Dictionary:
	for i in range(Combat.last_hits.size() - 1, -1, -1):
		var h := Combat.last_hits[i]
		if h.target == dummy:
			return h
	return {}

func fire_at(target: Vector3, wait_sec: float = 0.6) -> Dictionary:
	var n0 := dummy.hits.size()
	aim_at(target)
	await wait_frames(2)
	await tap(&"attack")
	var t := 0.0
	while dummy.hits.size() == n0 and t < wait_sec:
		await wait(0.05)
		t += 0.05
	return last_dummy_hit() if dummy.hits.size() > n0 else {}

func run() -> void:
	if not await setup_combat():
		return
	# ровная суша: ищем место и направление, где 16 м вперёд — земля
	var wl := BuildEnv.water_level()
	var base := Vector3.ZERO
	var yaw := 0.0
	var found := false
	for r in [0.0, 10.0, 20.0, 30.0, 40.0]:
		for a in 16:
			var c := Vector3(cos(a * 0.7) * r, 0.0, sin(a * 0.7) * r)
			for k in 12:
				var yw := k * TAU / 12.0
				var f := -Vector3(sin(yw), 0.0, cos(yw))
				var ok := true
				var h0 := ground(c.x, c.z)
				for d in [0.0, 4.0, 8.0, 12.0, 16.0]:
					var q: Vector3 = c + f * float(d)
					var h := ground(q.x, q.z)
					if h < wl + 0.6 or absf(h - h0) > 1.2:
						ok = false
						break
				if ok and BuildEnv.is_land(c.x, c.z):
					base = c
					yaw = yw
					found = true
					break
			if found:
				break
		if found:
			break
	check(found, "найдено ровное место на суше")
	base.y = ground(base.x, base.z) + 0.2
	teleport(base)
	p.set_look(yaw, 0.0)
	await wait(0.3)
	var fwd := -Vector3(sin(yaw), 0.0, cos(yaw))
	dummy = TrainingDummy.new()
	scene.add_child(dummy)
	var dp := base + fwd * 12.0
	dp.y = ground(dp.x, dp.z) - 0.02
	dummy.global_position = dp
	dummy.look_at(Vector3(base.x, dp.y, base.z), Vector3.UP)
	await wait(0.3)
	var feet := dummy.global_position.y
	var head := dummy.get_eye_position()
	var body := Vector3(dp.x, feet + 1.2, dp.z)
	var legs := Vector3(dp.x, feet + 0.45, dp.z)
	check(Items.get_item(&"musket") != null and Items.recipes.has(&"r_molotov"), "оружие и рецепты зарегистрированы")
	check(Combat.hit_zone(dummy, head) == &"head" and Combat.hit_zone(dummy, legs) == &"legs" and Combat.hit_zone(dummy, body) == &"body", "зоны по высоте")

	# --- мушкет: без пороха не стреляет, перезарядка, выстрел в голову (ПКМ) ---
	await equip(&"musket")
	aim_at(body)
	await wait(0.4)
	await shot("01_musket_hip")
	await tap(&"attack")
	await wait(0.2)
	check(not Combat.is_reloading(p) and not Combat.is_loaded(p, &"musket"), "без пороха и пуль — не заряжается")
	p.inventory.add(&"gunpowder", 6)
	p.inventory.add(&"musket_ball", 6)
	await tap(&"reload")
	await wait(0.3)
	check(Combat.is_reloading(p), "R — перезарядка мушкета")
	check(p.inventory.count(&"gunpowder") == 5 and p.inventory.count(&"musket_ball") == 5, "перезарядка тратит порох и пулю")
	await wait(1.6)
	await shot("02_musket_reload")
	await tap(&"attack")
	check(dummy.hits.is_empty(), "во время перезарядки не стреляет")
	await wait(3.8)
	check(Combat.is_loaded(p, &"musket"), "мушкет заряжен (%.1f с)" % float(Combat.weapon(&"musket").reload))
	Input.action_press(&"aim")
	aim_at(head)
	await wait(0.8)
	check(p.fov_zoom > 15.0, "ПКМ — прицел, FOV сужен на %.0f°" % p.fov_zoom)
	await shot("03_musket_ads")
	var pitch0: float = p.get(&"_pitch")
	var h := await fire_at(head)
	await wait(0.05)
	await shot("04_musket_fire")
	Input.action_release(&"aim")
	check(not h.is_empty() and h.zone == &"head", "мушкет — попадание в голову (%s)" % [h.get("zone", "мимо")])
	check(not h.is_empty() and float(h.damage) > 85.0 * 2.0 * 0.85 and float(h.damage) <= 85.0 * 2.0 + 0.01, "урон в голову ×2 (с потерей скорости пули) = %.0f" % float(h.get("damage", 0.0)))
	check(float(p.get(&"_pitch")) > pitch0 + 0.01, "отдача подбросила ствол")
	check(not Combat.is_loaded(p, &"musket"), "после выстрела мушкет пуст")

	# --- пистоль: ноги ---
	await equip(&"pistol")
	await tap(&"reload")
	await wait(1.2)
	await shot("05_pistol_reload")
	await wait(2.6)
	Input.action_press(&"aim")
	await wait(0.6)
	aim_at(legs)
	await wait(0.2)
	await shot("06_pistol_ads")
	h = await fire_at(legs)
	Input.action_release(&"aim")
	check(not h.is_empty() and h.zone == &"legs" and float(h.damage) > 48.0 * 0.75 * 0.8 and float(h.damage) <= 48.0 * 0.75 + 0.01, "пистоль — ноги ×0.75 (%s, %.1f)" % [h.get("zone", "мимо"), float(h.get("damage", 0.0))])

	# --- арбалет: тело ---
	await equip(&"crossbow")
	p.inventory.add(&"bolt", 3)
	await shot("07_crossbow_empty")
	await tap(&"attack") # пусто — сам начинает взводить
	await wait(1.4)
	await shot("08_crossbow_crank")
	await wait(2.0)
	check(Combat.is_loaded(p, &"crossbow"), "арбалет взведён, болт на ложе")
	aim_at(body)
	await wait(0.3)
	await shot("09_crossbow_loaded")
	h = await fire_at(body + Vector3.UP * 0.01)
	check(not h.is_empty() and h.zone == &"body" and float(h.damage) > 52.0 * 0.8 and float(h.damage) <= 52.01, "арбалет — тело ×1 (%s, %.1f)" % [h.get("zone", "мимо"), float(h.get("damage", 0.0))])
	await wait(0.3)
	var stuck := false
	for c in dummy.get_children():
		if c is Area3D or (c.get_child_count() > 0 and c.get_script() == null and c is Node3D and c.name.begins_with("@")):
			stuck = true
	check(stuck or dummy.get_child_count() > 8, "болт воткнулся в манекен")

	# --- лук: натяжение, полёт с падением ---
	await equip(&"bow")
	p.inventory.add(&"arrow", 5)
	p.inventory.add(&"arrow_fire", 2)
	await wait(0.3)
	await shot("10_bow_idle")
	var aimp := body + Vector3.UP * 0.18
	aim_at(aimp)
	Input.action_press(&"attack")
	await wait(1.1)
	check(ctrl().draw >= 0.99, "лук натянут полностью (%.2f)" % ctrl().draw)
	await shot("11_bow_drawn")
	var n0 := dummy.hits.size()
	Input.action_release(&"attack")
	var t := 0.0
	while dummy.hits.size() == n0 and t < 1.5:
		await wait(0.05)
		t += 0.05
	h = last_dummy_hit()
	check(dummy.hits.size() > n0, "стрела попала в манекен (%s, %.1f)" % [h.get("zone", "-"), float(h.get("damage", 0.0))])
	check(p.inventory.count(&"arrow") == 4, "стрела израсходована")
	await wait(0.3)
	await shot("12_bow_after")
	aim_at(dummy.global_position + Vector3(0.0, 1.0, 0.0))
	await wait(0.5)
	await shot("13_dummy_closeup")

	# --- метательное: вид в руке ---
	await equip(&"molotov")
	p.inventory.add(&"molotov", 1)
	aim_at(dp + fwd * 10.0)
	await wait(0.3)
	await shot("14_molotov_idle")
	Input.action_press(&"attack")
	await wait(0.7)
	await shot("15_molotov_windup")
	Input.action_release(&"attack")
	await wait(0.15)
	await shot("16_molotov_throw")
	await wait(1.6)
	await shot("17_molotov_fire")
	await equip(&"club")
	p.inventory.add(&"club", 0)
	await wait(0.2)
	await shot("18_club")
	await equip(&"spear")
	Input.action_press(&"aim")
	await wait(0.7)
	await shot("19_spear_raise")
	Input.action_release(&"aim")

	# --- динамит по манекену ---
	await equip(&"dynamite")
	await wait(0.2)
	await shot("20_dynamite")
	var before := dummy.total
	var dir := Combat.aim_dir(p.get_eye_position(), dp + Vector3.UP * 0.3, &"dynamite")
	var bomb := Combat.throw_item(p, &"dynamite", p.get_eye_position() + dir * 0.3, dir, 1.0)
	check(bomb is CombatBomb, "динамит брошен (API throw_item)")
	# время физики под нагрузкой отстаёт от таймеров — ждём сам взрыв
	aim_at(dp + Vector3.UP)
	var tb := 0.0
	var last_bp := Vector3.ZERO
	while is_instance_valid(bomb) and tb < 30.0:
		last_bp = (bomb as Node3D).global_position
		await wait(0.1)
		tb += 0.1
	print("[combat] бомба: последняя позиция %s, до манекена %.1f м, %.1f с" % [last_bp, last_bp.distance_to(dp), tb])
	await wait_frames(2)
	await shot("21_explosion")
	await wait(0.3)
	check(dummy.total > before + 20.0, "взрыв ранил манекен (%.0f)" % (dummy.total - before))

	# --- API для ботов (без инвентаря — бесконечные боеприпасы) ---
	var bot := Node3D.new()
	scene.add_child(bot)
	bot.global_position = dp + fwd * -20.0 + Vector3.UP * 1.6
	var origin := bot.global_position
	var fired := Combat.fire(bot, &"musket", origin, Combat.aim_dir(origin, body, &"musket"))
	check(not fired and Combat.is_reloading(bot), "бот: fire без заряда начинает перезарядку")
	await wait(5.7)
	var nb := dummy.hits.size()
	fired = Combat.fire(bot, &"musket", origin, Combat.aim_dir(origin, body, &"musket"), {"ads": true})
	await wait(0.4)
	check(fired and dummy.hits.size() > nb, "бот: выстрел из мушкета попал")
	var b2 := Node3D.new()
	scene.add_child(b2)
	b2.global_position = dp + fwd * -1.5
	b2.look_at(dp + Vector3.UP * 1.2)
	var mh := Combat.melee(b2, &"club")
	check(not mh.is_empty() and not mh.has("miss"), "бот: Combat.melee дубиной попал")
	print("[test] damage log: ", dummy.hits.size(), " попаданий, всего ", dummy.total)
