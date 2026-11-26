extends CombatTestCase
## Современный огнестрел (WeaponDef): пистолет 9 мм и автомат на стрельбище SandboxRange
## (10/25/50/100 м). Выстрел расходует патрон, магазин и перезарядка (тактическая +1 в
## патроннике / полная), отдача по паттерну возвращается, ADS совмещает ads_anchor с центром
## экрана и снижает разброс, разброс растёт от очереди и движения, урон с падением по
## дистанции (через Combat API — как у ботов), режим огня V, трассеры, гильзы и следы-декали
## ограничены, поверхности (камень/дерево/металл/песок). Скриншоты стрельбища и вида ADS.

var rg: Dictionary
var base := Vector3.ZERO
var fwd := Vector3.FORWARD
var right := Vector3.RIGHT

func _init() -> void:
	timeout_sec = 3000.0

func at(d: float, side: float, h: float = 0.0) -> Vector3:
	var q := base + fwd * d + right * side
	return Vector3(q.x, BuildEnv.height_at(q.x, q.z) + h, q.z)

## Ровная суша и свободная дорожка (луч на высоте 1.3 м не задевает деревья/камни).
func find_lane() -> bool:
	var wl := BuildEnv.water_level()
	var space := p.get_world_3d().direct_space_state
	var best := -1.0
	for r in [0.0, 12.0, 24.0, 36.0, 48.0]:
		for a in 12:
			var c := Vector3(cos(a * 0.9) * r, 0.0, sin(a * 0.9) * r)
			if not BuildEnv.is_land(c.x, c.z):
				continue
			var h0 := BuildEnv.height_at(c.x, c.z)
			if h0 < wl + 0.6:
				continue
			for k in 16:
				var yw := k * TAU / 16.0
				var f := -Vector3(sin(yw), 0.0, cos(yw))
				var ok := true
				for d in [0.0, 5.0, 10.0, 15.0, 20.0]:
					var q: Vector3 = c + f * float(d)
					var h := BuildEnv.height_at(q.x, q.z)
					if h < wl + 0.4 or absf(h - h0) > 1.0:
						ok = false
						break
				if not ok:
					continue
				var score := 0.0
				for side in [-12.0, -6.0, -1.6, 0.9, 3.2]:
					var sv := f.cross(Vector3.UP).normalized() * float(side)
					var o := c + sv + Vector3.UP * (h0 + 1.3)
					var q := PhysicsRayQueryParameters3D.create(o, o + f * 55.0)
					q.exclude = [p.get_rid()]
					var hit := space.intersect_ray(q)
					score += 55.0 if hit.is_empty() else o.distance_to(hit.position)
				if score > best:
					best = score
					base = Vector3(c.x, h0, c.z)
					fwd = f
			if best >= 270.0:
				break
		if best >= 270.0:
			break
	right = fwd.cross(Vector3.UP).normalized()
	print("[gunplay] дорожка: база %s, направление %s, свобода %.0f из 275" % [base, fwd, best])
	return best > 0.0

func hits_on(t: TrainingDummy) -> Array:
	return t.hits

## Ждать нового попадания в манекен; вернуть запись Combat.last_hits (урон, зона).
func wait_hit(t: TrainingDummy, n0: int, sec: float = 1.5) -> Dictionary:
	var tt := 0.0
	while t.hits.size() <= n0 and tt < sec:
		await wait(0.05)
		tt += 0.05
	if t.hits.size() <= n0:
		return {}
	for i in range(Combat.last_hits.size() - 1, -1, -1):
		if Combat.last_hits[i].target == t:
			return Combat.last_hits[i]
	return {}

## Перезарядка началась с длительностью sec: reload_end − t0 ∈ [sec, sec + 0.6] (t0 — до нажатия).
func reload_len_ok(t0: float, sec: float) -> bool:
	var e := float(Combat.state(p).reload_end) - t0
	print("[gunplay] перезарядка: %.2f с (ожидалось %.2f)" % [e, sec])
	return Combat.is_reloading(p) and e >= sec - 0.02 and e <= sec + 0.6

func pitch() -> float:
	return float(p.get(&"_pitch"))

func run() -> void:
	if not await setup_combat():
		return
	SupplyItems.register()
	Engine.max_physics_steps_per_frame = 16
	check(Items.get_item(&"pistol_9mm") != null and Items.get_item(&"ammo_9mm") != null, "предметы «Пистолет» и «Патроны 9 мм» зарегистрированы")
	var pd := WeaponDef.of(&"pistol_9mm")
	var rd := WeaponDef.of(&"rifle")
	check(pd != null and pd.mag_size >= 12 and pd.mag_size <= 15 and pd.ammo_id == &"ammo_9mm", "WeaponDef пистолета: магазин %d, патроны 9 мм" % (pd.mag_size if pd else 0))
	check(rd != null and rd.fire_modes.size() == 3 and rd.tracer_every > 0, "WeaponDef автомата: авто/одиночный/предохранитель, трассеры")
	var cw := Combat.weapon(&"pistol_9mm")
	check(Combat.is_weapon(&"pistol_9mm") and cw.type == &"gun" and int(cw.mag) == pd.mag_size and is_equal_approx(float(cw.cooldown), pd.cooldown()),
		"Combat.weapon(pistol_9mm) собран из WeaponDef")
	check(not Combat.weapon(&"musket").has("def") and int(Combat.weapon(&"rifle").mag) == 20, "старое оружие не тронуто, автомат — магазин 20")
	var in_loot := false
	for e: Array in SupplyItems.LOOT_RARE + SupplyItems.LOOT_LEGENDARY:
		for it: Array in e[0]:
			if it[0] == &"pistol_9mm":
				in_loot = true
	check(in_loot, "пистолет есть в посылках спонсоров")

	check(find_lane(), "найдена дорожка для стрельбища")
	var host := Node3D.new()
	host.name = "Range"
	scene.add_child(host)
	rg = SandboxRange.build(host, base, fwd, func(x: float, z: float) -> float: return BuildEnv.height_at(x, z))
	check(rg.by_dist.has(10) and rg.by_dist.has(25) and rg.by_dist.has(50) and rg.by_dist.has(100), "мишени на 10/25/50/100 м")
	check((rg.dummies as Array).size() == 4 and (rg.plates as Array).size() == 4 and (rg.surfaces as Array).size() == 4, "манекены, гонги, образцы поверхностей")
	teleport(rg.stand)
	aim_at(rg.look)
	await wait(0.6)
	var d10: TrainingDummy = rg.by_dist[10].dummy
	var d50: TrainingDummy = rg.by_dist[50].dummy
	var paper10: Node3D = rg.by_dist[10].paper
	var plate10: SandboxRange.RangePlate = rg.by_dist[10].plate

	# ---------------- пистолет: магазин, перезарядка, выстрел ----------------
	await equip(&"pistol_9mm")
	await wait(0.3)
	await shot("01_range_pistol")
	check(Combat.rounds(p, &"pistol_9mm") == 0, "новый пистолет пуст")
	p.inventory.add(&"ammo_9mm", 40)
	var t0 := Combat._now()
	await tap(&"reload")
	await wait(0.1)
	check(reload_len_ok(t0, pd.reload_full), "R — полная перезарядка (%.1f с)" % pd.reload_full)
	check(Combat.rounds(p, &"pistol_9mm") == pd.mag_size and p.inventory.count(&"ammo_9mm") == 40 - pd.mag_size, "в магазин — %d, в запасе %d" % [Combat.rounds(p, &"pistol_9mm"), p.inventory.count(&"ammo_9mm")])
	await wait(0.6)
	await shot("02_pistol_reload")
	await wait(pd.reload_full)
	check(Combat.is_loaded(p, &"pistol_9mm"), "пистолет заряжен")
	check(ctrl()._mag_label.text == "%d / %d" % [pd.mag_size, 40 - pd.mag_size], "HUD «в магазине / в запасе»: %s" % ctrl()._mag_label.text)
	# прицел: ads_anchor в центре экрана, FOV, разброс
	var body10 := d10.global_position + Vector3.UP * 1.2
	aim_at(body10)
	await wait(0.3)
	var hip_spread := ctrl().spread_now
	Input.action_press(&"aim")
	await wait(0.7)
	var ads_spread := ctrl().spread_now
	check(ctrl().ads > 0.99 and p.fov_zoom > pd.ads_fov * 0.9, "ПКМ — прицел, FOV сужен на %.0f°" % p.fov_zoom)
	check(ads_spread < hip_spread * 0.35, "ADS снижает разброс: %.2f° → %.2f°" % [hip_spread, ads_spread])
	var anc := ctrl().socket(&"ads_anchor")
	var vs := get_viewport().get_visible_rect().size
	var off := (p.camera.unproject_position(anc.global_position) - vs * 0.5).length() if anc else 9999.0
	check(anc != null and not p.camera.is_position_behind(anc.global_position) and off < vs.y * 0.04, "ads_anchor совмещён с центром экрана (%.1f px)" % off)
	await shot("03_pistol_ads")
	var n0 := hits_on(d10).size()
	var r0 := Combat.rounds(p, &"pistol_9mm")
	var c0 := GunFx.casing_count()
	Engine.time_scale = 0.01 # вспышка живёт ~50 мс — замедляем, чтобы попала в кадр
	await tap(&"attack")
	await wait_frames(1)
	await shot("04_pistol_fire")
	Engine.time_scale = 1.0
	check(Combat.rounds(p, &"pistol_9mm") == r0 - 1, "выстрел расходует патрон (%d → %d)" % [r0, Combat.rounds(p, &"pistol_9mm")])
	check(GunFx.casing_count() > c0, "гильза вылетела из окна выброса")
	var h := await wait_hit(d10, n0)
	check(not h.is_empty() and absf(float(h.damage) - pd.damage) < 0.05, "попадание в манекен на 10 м: %.1f (без падения урона)" % float(h.get("damage", 0.0)))
	Input.action_release(&"aim")
	await wait(0.4)
	# тактическая перезарядка: +1 в патроннике
	t0 = Combat._now()
	await tap(&"reload")
	await wait(0.1)
	check(reload_len_ok(t0, pd.reload_tactical), "тактическая перезарядка быстрее (%.1f с)" % pd.reload_tactical)
	check(Combat.rounds(p, &"pistol_9mm") == pd.mag_size + 1, "тактическая: %d+1 в патроннике" % pd.mag_size)
	await wait(pd.reload_tactical + 0.2)
	# опустошить магазин по бумажной мишени (полуавтомат — отдельные нажатия), отдача и её возврат
	aim_at(paper10.global_position)
	await wait(0.3)
	var p0 := pitch()
	var peak := p0
	var shots_left := Combat.rounds(p, &"pistol_9mm")
	for i in shots_left:
		if i % 4 == 0:
			aim_at(paper10.global_position + Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), 0.0))
		await tap(&"attack")
		peak = maxf(peak, pitch())
		await wait(pd.cooldown() + 0.02)
	check(Combat.rounds(p, &"pistol_9mm") == 0, "магазин опустошён")
	var inv_before := p.inventory.count(&"ammo_9mm")
	t0 = Combat._now()
	await tap(&"attack")
	await wait(0.1)
	check(reload_len_ok(t0, pd.reload_full), "пустой — спуск: щелчок и полная перезарядка")
	await wait(pd.reload_full + 0.2)
	var want := mini(pd.mag_size, inv_before)
	check(Combat.rounds(p, &"pistol_9mm") == want and p.inventory.count(&"ammo_9mm") == inv_before - want,
		"после полной — в магазине %d (без патронника), в запасе %d" % [Combat.rounds(p, &"pistol_9mm"), p.inventory.count(&"ammo_9mm")])
	check(GunFx.decal_count() > 0, "следы от пуль на мишени (%d)" % GunFx.decal_count())
	# крупно — бумажная мишень со следами
	var pp := paper10.global_position
	teleport(at(7.0, -1.6, 0.1))
	aim_at(pp)
	await wait(0.5)
	await shot("05_paper_hits")
	teleport(rg.stand)

	# ---------------- автомат: режимы, очередь, отдача, трассеры ----------------
	await equip(&"rifle")
	p.inventory.add(&"rifle_ammo", 60)
	check(Combat.fire_mode(p, &"rifle") == &"auto", "автомат: по умолчанию — очередь")
	await tap(&"fire_mode")
	await wait(0.1)
	check(Combat.fire_mode(p, &"rifle") == &"semi", "V — одиночный")
	await tap(&"fire_mode")
	await wait(0.1)
	check(Combat.fire_mode(p, &"rifle") == &"safe", "V — предохранитель")
	await tap(&"fire_mode")
	await wait(0.1)
	check(Combat.fire_mode(p, &"rifle") == &"auto", "V — снова автоматический")
	await tap(&"reload")
	await wait(rd.reload_full + 0.3)
	check(Combat.rounds(p, &"rifle") == rd.mag_size, "автомат заряжен (%d)" % Combat.rounds(p, &"rifle"))
	var paper25: Node3D = rg.by_dist[25].paper
	aim_at(paper25.global_position)
	await wait(0.5)
	await shot("06_rifle_hip")
	var hip_r := ctrl().spread_now
	# разброс от движения
	Input.action_press(&"move_forward")
	await wait(0.6)
	var move_r := ctrl().spread_now
	Input.action_release(&"move_forward")
	check(move_r > hip_r + 0.5, "разброс растёт в движении: %.2f° → %.2f°" % [hip_r, move_r])
	check(rd != null and Gunplay.new(rd).spread(0.0, 0.0, false, false) > rd.spread_hip + rd.spread_jump * 0.9, "в прыжке разброс больше")
	teleport(rg.stand)
	aim_at(paper25.global_position)
	await wait(0.8)
	hip_r = ctrl().spread_now
	# очередь от бедра: отдача вверх, разброс растёт, трассеры. Под llvmpipe кадр ~0.2–0.3 с —
	# замедляем время, чтобы кадров на очередь было как при обычных 60 FPS.
	Engine.time_scale = 0.25
	p0 = pitch()
	peak = p0
	var rr0 := Combat.rounds(p, &"rifle")
	var tracer_seen := false
	var spread_peak := hip_r
	Input.action_press(&"attack")
	var tb := 0.0
	var took := false
	while tb < 0.7:
		await wait_frames(1)
		tb += get_process_delta_time()
		peak = maxf(peak, pitch())
		spread_peak = maxf(spread_peak, ctrl().spread_now)
		tracer_seen = tracer_seen or bool(Combat.last_shot.get("tracer", false))
		if not took and rr0 - Combat.rounds(p, &"rifle") >= 3:
			took = true
			await shot("07_rifle_burst")
	Input.action_release(&"attack")
	Engine.time_scale = 1.0
	var fired := rr0 - Combat.rounds(p, &"rifle")
	check(fired >= 4, "очередь: %d выстрелов, патроны списаны" % fired)
	check(tracer_seen or fired < rd.tracer_every, "трассер (каждый %d-й)" % rd.tracer_every)
	check(spread_peak > hip_r + 0.5, "разброс растёт при стрельбе очередью: %.2f° → %.2f°" % [hip_r, spread_peak])
	var rise := rad_to_deg(peak - p0)
	check(rise > 1.5, "отдача подбросила прицел на %.1f°" % rise)
	await wait(1.6)
	var back := rad_to_deg(pitch() - p0)
	check(absf(back) < maxf(0.25, rise * 0.1), "отдача вернулась (осталось %.2f° из %.1f°)" % [back, rise])
	check(absf(ctrl().spread_now - hip_r) < 0.2, "разброс восстановился (%.2f°)" % ctrl().spread_now)
	await shot("08_rifle_after_burst")
	# прицел автомата
	var paper100: Node3D = rg.by_dist[100].paper
	aim_at(paper100.global_position)
	Input.action_press(&"aim")
	await wait(0.8)
	var anc2 := ctrl().socket(&"ads_anchor")
	var off2 := (p.camera.unproject_position(anc2.global_position) - vs * 0.5).length() if anc2 else 9999.0
	check(anc2 != null and off2 < vs.y * 0.04, "автомат: ads_anchor в центре (%.1f px)" % off2)
	check(ctrl().spread_now < rd.spread_hip * 0.2, "автомат: в прицеле разброс %.2f°" % ctrl().spread_now)
	await shot("09_rifle_ads_100m")
	Input.action_release(&"aim")
	await wait(0.3)

	# ---------------- урон с падением по дистанции (Combat API, как у ботов) ----------------
	var bot := Node3D.new()
	scene.add_child(bot)
	bot.global_position = at(0.0, 3.2, 1.5)
	var o := bot.global_position
	var fired_bot := Combat.fire(bot, &"pistol_9mm", o, Combat.aim_dir(o, body10, &"pistol_9mm"), {"spread": 0.0})
	check(not fired_bot and Combat.is_reloading(bot), "бот: пустой пистолет — перезарядка")
	await wait(pd.reload_full + 0.3)
	n0 = hits_on(d10).size()
	check(Combat.fire(bot, &"pistol_9mm", o, Combat.aim_dir(o, body10, &"pistol_9mm"), {"spread": 0.0}), "бот: выстрел")
	var h10 := await wait_hit(d10, n0)
	var body50 := d50.global_position + Vector3.UP * 1.2
	# по дорожке манекенов: ближние (10 и 25 м) на время убираем с линии огня
	var d25: TrainingDummy = rg.by_dist[25].dummy
	d10.global_position += Vector3.UP * 60.0
	d25.global_position += Vector3.UP * 60.0
	await wait(0.2)
	var hh50 := {}
	for hgt in [1.5, 3.0, 5.0, 8.0, 12.0]: # холмы острова: стреляем с вышки, если рельеф закрывает
		bot.global_position = at(0.0, 3.2, hgt)
		hh50 = p.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(bot.global_position, body50))
		if hh50.get("collider") == d50:
			break
	print("[gunplay] луч до манекена 50 м с высоты %.1f: %s" % [bot.global_position.y, hh50.get("collider")])
	o = bot.global_position
	await wait(0.3)
	var h50 := {}
	for attempt in 3: # повтор только для диагностики промаха (урон проверяется по попавшей пуле)
		n0 = hits_on(d50).size()
		var nd := GunFx.decal_count()
		var ok50 := Combat.fire(bot, &"pistol_9mm", o, Combat.aim_dir(o, body50, &"pistol_9mm"), {"spread": 0.0})
		h50 = await wait_hit(d50, n0, 3.0)
		if not h50.is_empty():
			break
		var lh: Dictionary = Combat.last_hits[Combat.last_hits.size() - 1] if not Combat.last_hits.is_empty() else {}
		var dec: Node3D = GunFx._decals.back() if GunFx.decal_count() > nd else null
		print("[gunplay] 50 м промах #%d: выстрел=%s, dir=%s, след=%s, посл. попадание: %s" % [attempt, ok50,
			Combat.last_shot.get("dir"), dec.global_position if dec else "-", lh.get("collider")])
		await wait(0.6)
	var dist50 := o.distance_to(body50)
	d10.global_position -= Vector3.UP * 60.0
	d25.global_position -= Vector3.UP * 60.0
	print("[gunplay] урон 10 м: %s, 50 м (%.1f м): %s" % [h10.get("damage", "-"), dist50, h50.get("damage", "-")])
	check(not h10.is_empty() and absf(float(h10.damage) - pd.damage) < 0.05, "10 м — полный урон %.1f" % float(h10.get("damage", 0.0)))
	check(not h50.is_empty() and absf(float(h50.damage) - pd.damage_at(dist50)) < 0.3 and float(h50.damage) < pd.damage * 0.7,
		"50 м — урон упал до %.1f (ожидалось %.1f)" % [float(h50.get("damage", 0.0)), pd.damage_at(dist50)])
	check(is_equal_approx(rd.falloff_at(10.0), 1.0) and rd.falloff_at(200.0) == rd.falloff_min, "автомат: падение урона на дальности")

	# ---------------- поверхности: камень / дерево / металл / песок ----------------
	var kinds := {}
	for b: StaticBody3D in rg.surfaces:
		kinds[GunFx.surface_of(b, b.global_position)] = true
		var dc := GunFx.decal_count()
		var tgt := b.global_position
		bot.global_position = tgt - fwd * 6.0 + Vector3.UP * 0.3
		await wait(0.25)
		Combat.fire(bot, &"pistol_9mm", bot.global_position, (tgt - bot.global_position).normalized(), {"spread": 0.0})
		var tt := 0.0
		while GunFx.decal_count() == dc and tt < 1.0:
			await wait(0.05)
			tt += 0.05
		check(GunFx.decal_count() > dc or GunFx.decal_count() == GunFx.MAX_DECALS, "след на «%s»" % b.get_meta(&"surface"))
	check(kinds.has(&"stone") and kinds.has(&"wood") and kinds.has(&"metal") and kinds.has(&"sand"), "материалы поверхностей: %s" % [kinds.keys()])
	check(GunFx.surface_of(d10, d10.global_position) == &"straw", "манекен — солома (без крови)")
	# гонг (металл): попадание через Combat API
	var ph0 := plate10.hits
	bot.global_position = at(0.0, 0.9, 1.25 + plate10.radius)
	var ptgt := plate10.global_position
	await wait(0.2)
	Combat.fire(bot, &"pistol_9mm", bot.global_position, Combat.aim_dir(bot.global_position, ptgt, &"pistol_9mm"), {"spread": 0.0})
	var tp := 0.0
	while plate10.hits == ph0 and tp < 1.0:
		await wait(0.05)
		tp += 0.05
	check(plate10.hits > ph0, "гонг на 10 м звенит от попадания")
	# вода: брызги без декали (прямой вызов эффекта)
	var dw := GunFx.decal_count()
	GunFx.bullet_impact(p, null, at(5.0, 0.0, 0.0), Vector3.UP, &"water", Vector3.DOWN * 300.0)
	check(GunFx.decal_count() == dw, "вода — брызги без следа")
	# крупно — образцы поверхностей
	var s0: Node3D = rg.surfaces[0]
	var s3: Node3D = rg.surfaces[3]
	var mid := (s0.global_position + s3.global_position) * 0.5
	var stand := mid - fwd * 4.5
	teleport(Vector3(stand.x, BuildEnv.height_at(stand.x, stand.z) + 0.2, stand.z))
	aim_at(mid)
	await wait(0.5)
	await shot("10_surfaces")
	teleport(rg.stand)

	# ---------------- лимиты гильз и следов ----------------
	var cas: RigidBody3D = null
	var y0 := 0.0
	for i in GunFx.MAX_CASINGS + 12:
		var xf := Transform3D(Basis(), p.get_eye_position() + p.camera.global_basis.x * 0.6)
		var c := GunFx.eject_casing(p, xf, p.camera.global_basis.x, Vector3.UP, p.camera.global_basis.z, Vector3.ZERO, rd)
		if i == GunFx.MAX_CASINGS + 11:
			cas = c
			y0 = xf.origin.y
	await wait_frames(2)
	check(GunFx.casing_count() <= GunFx.MAX_CASINGS, "гильз не больше %d (%d)" % [GunFx.MAX_CASINGS, GunFx.casing_count()])
	await wait(1.0)
	check(cas != null and is_instance_valid(cas) and cas.global_position.y < y0 - 0.3, "гильза падает (физика)")
	aim_at(p.global_position + p.camera.global_basis.x * 1.2 * Vector3(1, 0, 1) + fwd * 0.8)
	await wait(0.3)
	await shot("11_casings")
	for i in GunFx.MAX_DECALS + 20:
		GunFx.decal(p, null, at(2.0 + (i % 8) * 0.3, -1.0 + floori(i / 8.0) * 0.3, 0.01), Vector3.UP, &"dirt")
	await wait_frames(2)
	check(GunFx.decal_count() <= GunFx.MAX_DECALS, "следов не больше %d (%d)" % [GunFx.MAX_DECALS, GunFx.decal_count()])
	await wait(GunFx.CASING_LIFE + 1.2)
	check(GunFx.casing_count() == 0, "гильзы исчезают через %.0f с" % GunFx.CASING_LIFE)
	# общий вид стрельбища
	teleport(at(-6.0, -2.0, 0.2) + Vector3.UP * 2.5)
	aim_at(at(40.0, 0.0, 0.0))
	await wait(0.6)
	await shot("12_range_overview")
