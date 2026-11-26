## test-timeout: 600
extends TestCase
## Механики V5 (агент F), часть 2: мокрость и температура (BodyState), износ оружия от соли
## (АК бессмертен, 9 мм — ломается), отсыревший порох, вода в таре (расплёскивание на бегу,
## морская вода в открытую тару при плавании, канистра: набрать/налить), розжиг (сырость
## снижает шанс, шелуха помогает), жажда мутит экран.

var p: Player

func _init() -> void:
	timeout_sec = 600.0

func slot(id: StringName) -> Dictionary:
	return GearWear._slot_of(p, id)

func run() -> void:
	await wait(1.0)
	p = get_tree().get_first_node_in_group(&"player") as Player
	check(p != null and p.body != null, "у игрока есть BodyState")
	if p == null or p.body == null:
		return
	SupplyItems.register()
	Survival.instance() # модуль может отсутствовать в тестовой сцене — предметы регистрируем сами
	SurvivalItems.register()
	FaunaItems.register()
	var b := p.body
	# ---- мокрость ----
	b.wetness = 0.0
	p.swimming = true
	b._update_wetness(0.5)
	p.swimming = false
	check(b.wetness > 0.9, "плавание — промок (%.2f)" % b.wetness)
	b.force = {"sun_elevation": 0.9, "wind_speed": 6.0, "rain_intensity": 0.0, "shade": false, "fire": 0.0}
	var w0 := b.wetness
	for i in 60:
		b._update_wetness(1.0)
	check(b.wetness < w0 - 0.2, "на солнце и ветру сохнет за минуту: %.2f → %.2f" % [w0, b.wetness])
	# ---- температура ----
	b.wetness = 1.0
	b.force = {"sun_elevation": -0.5, "wind_speed": 8.0, "rain_intensity": 0.5, "shade": false, "shelter": false, "fire": 0.0}
	var cold := b._target()
	check(cold < -0.7, "ночь, ветер, дождь, мокрый — очень холодно (%.2f, %s)" % [cold, str(b.causes)])
	b.force["fire"] = 1.0
	var warm := b._target()
	check(warm > cold + 0.6, "у костра теплее (%.2f)" % warm)
	b.wetness = 0.0
	b.force = {"sun_elevation": 0.95, "wind_speed": 1.0, "rain_intensity": 0.0, "shade": false, "fire": 0.0}
	var noon := b._target()
	b.force["shade"] = true
	var shade := b._target()
	check(noon > 0.5 and shade < noon - 0.3, "полдень на солнце жарко (%.2f), в тени прохладнее (%.2f)" % [noon, shade])
	b.temp = 0.9
	b._apply(0.1)
	check(p.thirst_mul > 1.5, "жара — жажда быстрее ×%.1f" % p.thirst_mul)
	b.temp = -0.9
	b._apply(0.1)
	check(p.stamina_regen_mul < 0.8, "холод — силы восстанавливаются медленнее ×%.2f" % p.stamina_regen_mul)
	b.temp = 0.0
	b._apply(0.1)
	b.wetness = 0.0
	b.force = {"sun_elevation": -0.5, "wind_speed": 3.0, "rain_intensity": 0.0, "shade": false, "fire": 0.0}
	var bare := b._target()
	p.inventory.add(&"hide", 1)
	var dressed := b._target()
	check(dressed > bare + 0.1, "одежда (шкура, clothing.warmth) греет: %.2f → %.2f" % [bare, dressed])
	# ---- износ оружия ----
	p.inventory.add(&"rifle", 1)
	p.inventory.add(&"pistol_9mm", 1)
	p.inventory.add(&"rifle_ammo", 30)
	p.swimming = true
	for i in 40:
		GearWear.tick(p, GearWear.DAY_S / 10.0) # 4 «суток» в море
	p.swimming = false
	check(GearWear.condition(p, &"rifle") >= GearWear.IMMORTAL_FLOOR - 0.001 and float(slot(&"rifle").get("rust", 0.0)) > 0.5,
		"АК после 4 суток в море: состояние %.2f (ржавчина снаружи %.2f)" % [GearWear.condition(p, &"rifle"), float(slot(&"rifle").get("rust", 0.0))])
	check(GearWear.condition(p, &"pistol_9mm") < 0.1, "9 мм после 4 суток в море: %.2f" % GearWear.condition(p, &"pistol_9mm"))
	check(GearWear.fire_check(p, &"pistol_9mm") == &"broken", "9 мм сломан — не стреляет")
	check(float(slot(&"rifle_ammo").get("wet", 0.0)) > 0.9, "патроны намокли")
	var misf := 0
	for i in 200:
		if GearWear.fire_check(p, &"rifle", &"rifle_ammo") == &"misfire":
			misf += 1
	check(misf > 60, "мокрые патроны — осечки (%d из 200)" % misf)
	# ---- вода в таре ----
	p.inventory.add(&"shell_water", 3)
	p.sprinting = true
	var t := 0
	while Survival.count(p, &"shell_water") == 3 and t < 400:
		WaterContainers.tick(p, 0.5)
		t += 1
	p.sprinting = false
	check(Survival.count(p, &"shell_water") < 3 and Survival.count(p, &"coconut_shell") >= 1, "на бегу из плошки расплескалось (%d с)" % int(t * 0.5))
	p.swimming = true
	WaterContainers.tick(p, 0.1)
	p.swimming = false
	check(Survival.count(p, &"shell_water") == 0 and Survival.count(p, &"shell_salt") >= 1, "в море открытая плошка залилась солёной")
	p.inventory.remove(&"coconut_shell", Survival.count(p, &"coconut_shell"))
	p.inventory.remove(&"shell_salt", Survival.count(p, &"shell_salt"))
	p.inventory.add(&"canister", 1)
	p.inventory.add(&"bamboo_cup", 1)
	check(WaterContainers.fill_big(p, &"canister", true) > 19.0, "канистра набрана (20 л)")
	var msg := WaterContainers.use_big(p, &"canister")
	check(Survival.count(p, &"bamboo_cup_water") == 1 and absf(WaterContainers.litres(p, &"canister") - 19.2) < 0.01, "налил 0,8 л в колено бамбука: %s" % msg)
	# ---- розжиг ----
	b.wetness = 0.0
	var w := BuildEnv.world()
	var dry := FireMaking.chance(p, p.global_position)
	b.wetness = 1.0
	var wetc := FireMaking.chance(p, p.global_position)
	check(float(wetc.chance) < float(dry.chance) * 0.6, "мокрым разжечь труднее: %.2f → %.2f (%s)" % [dry.chance, wetc.chance, dry.method])
	p.inventory.add(&"coconut_husk", 2)
	b.wetness = 0.0
	var husk := FireMaking.chance(p, p.global_position)
	check(float(husk.chance) > float(dry.chance), "шелуха кокоса помогает: %.2f" % husk.chance)
	p.inventory.add(&"lighter", 1)
	check(FireMaking.chance(p, p.global_position).method == &"lighter", "зажигалка — лучший способ после горелки")
	# ---- жажда ----
	p.thirst = 5.0
	check(b.thirst_blur() > 0.4, "жажда — экран мутнеет (%.2f)" % b.thirst_blur())
	p.thirst = 80.0
	check(b.thirst_blur() == 0.0, "напился — чётко")
