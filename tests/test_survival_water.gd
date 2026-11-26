extends TestCase
## test-class: render
## SURVIVAL — вода: морская вода вредит, набор в бутылку, кипячение в котелке
## на костре, дождевая бочка/тент под дождём, опреснитель, родник; мусорный берег.

var p: Player
var sv: Survival

func _init() -> void:
	timeout_sec = 1300.0

func aim_at(target: Vector3) -> void:
	var d := target - p.get_eye_position()
	p.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))

func put(id: StringName, n: int, slot: int = 0) -> void:
	p.inventory.set_slot(slot, {"id": id, "n": n})
	p.inventory.select(slot)

func ground(x: float, z: float) -> Vector3:
	return Vector3(x, scene.call(&"height_at", x, z), z)

func run() -> void:
	await wait(1.0)
	p = get_tree().get_first_node_in_group(&"player") as Player
	check(p != null, "игрок есть")
	sv = (load("res://scenes/survival/survival.tscn") as PackedScene).instantiate() as Survival
	scene.add_child(sv)
	if not sv.populated:
		await sv.populated_done
	check(Survival.instance() == sv, "Survival.instance()")
	check(Items.get_item(&"water_salt") != null and Items.recipes.has(&"r_pot"), "предметы и рецепты зарегистрированы")
	var nd := get_tree().get_nodes_in_group(&"sv_debris").size()
	var nw := get_tree().get_nodes_in_group(&"sv_wild").size()
	var ns := get_tree().get_nodes_in_group(&"sv_fresh").size()
	check(nd >= 4, "мусор на берегу: %d" % nd)
	check(nw >= 6, "дикие растения: %d" % nw)
	check(ns == 1, "родник на острове-заглушке: %d" % ns)
	check(sv.beaches.size() >= 1, "мусорных берегов: %d" % sv.beaches.size())

	# ---------- морская вода ----------
	var sx := 30.0
	while sx < 70.0 and float(scene.call(&"height_at", sx, 0.0)) > 0.6:
		sx += 0.25
	var wx := sx
	while wx < 80.0 and float(scene.call(&"height_at", wx, 0.0)) > p.water_level() - 0.05:
		wx += 0.25
	var stand := ground(maxf(sx - 1.2, wx - 1.6), 0.0)
	p.global_position = stand + Vector3.UP * 0.1
	p.velocity = Vector3.ZERO
	await wait(0.5)
	aim_at(Vector3(wx + 0.6, p.water_level(), 0.0))
	await wait_frames(3)
	check(p.can_drink_here(), "смотрим на море (x=%.1f)" % sx)
	p.thirst = 50.0
	var hp0 := p.health
	p.drink_water()
	await wait(0.2)
	check(p.thirst < 60.0, "морская вода почти не поит: %.1f" % p.thirst)
	check(p.health < hp0, "морская вода ранит: %.1f→%.1f" % [hp0, p.health])
	check(float(sv.effects_of(p).salt) > 0.0, "солевой эффект")
	var t0 := p.thirst
	await wait(2.0)
	check(p.thirst < t0 - 0.5, "солевая жажда тянет воду быстрее: %.2f→%.2f" % [t0, p.thirst])

	# ---------- бутылки: набрать морской ----------
	put(&"bottle_empty", 3)
	await wait(0.6)
	p.drink_water()
	await wait(0.2)
	check(p.inventory.count(&"water_salt") == 3 and p.inventory.count(&"bottle_empty") == 0, "набрал морской воды ×3")

	# ---------- костёр + котелок ----------
	Survival.speed = 10.0
	FireMaking.force_chance = 1.0 # V5: розжиг случаен (чем/сырость) — здесь проверяем готовку
	var base := ground(sx - 9.0, 3.0)
	var fire := sv.place_structure(null, &"campfire", base) as SvFire
	p.inventory.set_slot(1, {"id": &"stick", "n": 6})
	p.inventory.set_slot(2, {"id": &"pot", "n": 1})
	p.inventory.set_slot(3, {"id": &"fish_raw", "n": 1})
	p.global_position = base + Vector3(0, 0.2, 2.2)
	await wait(0.3)
	aim_at(base + Vector3(0, 0.3, 0))
	await wait_frames(3)
	check(p.call(&"_interact_target") == fire, "луч попадает в костёр")
	fire.interact(p)
	check(fire.lit and fire.is_in_group(&"campfire"), "костёр горит, станция campfire")
	p.inventory.select(0) # в руке морская вода
	fire.interact(p) # рыба жарится (готовка раньше кипячения)
	check(fire.grill.size() == 1, "рыба на решётке")
	fire.interact(p)
	check(not fire.pot.is_empty() and p.inventory.count(&"water_salt") == 0 and p.inventory.count(&"pot") == 0, "котелок с морской водой на огне")
	await wait(1.2)
	await shot("01_campfire_pot")
	await until(func() -> bool: return fire.pot_ready() and not fire.grill_ready().is_empty(), 40.0)
	fire.interact(p) # снять рыбу
	fire.interact(p) # снять котелок
	check(p.inventory.count(&"fish_cooked") == 1, "рыба зажарена")
	check(p.inventory.count(&"water_bottle") == 3 and p.inventory.count(&"pot") == 1, "вскипело: пресная ×3, котелок вернулся")
	p.thirst = 40.0
	p.consume(&"water_bottle")
	p.inventory.remove(&"water_bottle", 1)
	check(p.thirst > 75.0 and p.inventory.count(&"bottle_empty") == 1, "выпил — бутылка пустая вернулась")

	# ---------- дождь: бочка, тент; опреснитель ----------
	var bpos := ground(sx - 12.0, -4.0)
	var barrel := sv.place_structure(null, &"rain_barrel", bpos) as SvWater
	var tarp := sv.place_structure(null, &"tarp", ground(sx - 14.5, -1.0)) as SvWater
	var still := sv.place_structure(null, &"still", ground(sx - 5.0, -5.0)) as SvWater
	Survival.rain_override = 1.0
	Survival.speed = 20.0
	await until(func() -> bool: return barrel.portions() >= 2 and tarp.portions() >= 3, 30.0)
	check(barrel.portions() >= 2, "бочка набрала дождя: %d" % barrel.portions())
	check(tarp.portions() > barrel.portions(), "тент собирает быстрее бочки: %d > %d" % [tarp.portions(), barrel.portions()])
	check(still.portions() == 0, "в дождь опреснитель не работает")
	print("[dbg] still amount=%.3f sun=%.2f ms=%d" % [still.amount, SvWater.sun_factor(), Time.get_ticks_msec()])
	Survival.rain_override = 0.0
	await until(func() -> bool: return still.portions() >= 1, 30.0)
	check(still.portions() >= 1, "опреснитель на солнце дал воду")
	Survival.speed = 1.0
	put(&"bottle_empty", 1, 0)
	var before := barrel.portions()
	var wb0 := p.inventory.count(&"water_bottle")
	barrel.interact(p)
	check(p.inventory.count(&"water_bottle") > wb0 and barrel.portions() == before - (p.inventory.count(&"water_bottle") - wb0), "набрал из бочки: %d→%d, бочка %d→%d" % [wb0, p.inventory.count(&"water_bottle"), before, barrel.portions()])
	p.thirst = 20.0
	p.inventory.select(4)
	tarp.interact(p)
	check(p.thirst > 40.0, "попил из тента")
	# вид: бочка, тент, опреснитель
	p.global_position = ground(sx - 6.0, 3.0) + Vector3.UP * 0.1
	await wait(0.4)
	aim_at(ground(sx - 12.0, -3.0) + Vector3.UP * 0.4)
	await wait(0.8)
	await shot("02_rain_collectors")

	# ---------- родник ----------
	var spring := get_tree().get_first_node_in_group(&"sv_fresh") as SvWater
	p.thirst = 30.0
	spring.interact(p)
	check(p.thirst >= 54.0, "попил из родника")
	put(&"coconut_shell", 2, 0)
	spring.interact(p)
	check(p.inventory.count(&"shell_water") == 2, "набрал родниковой в скорлупки")
	check(sv.drink_sources(p.global_position).size() >= 3, "API: drink_sources")
	p.global_position = spring.global_position + Vector3(0, 0.2, 4.0)
	await wait(0.4)
	aim_at(spring.global_position)
	await wait(0.6)
	await shot("03_spring")

	# ---------- мусорный берег ----------
	var b: Dictionary = sv.beaches[0]
	var bp: Vector3 = b.pos
	p.global_position = bp - (b.out as Vector3) * 5.0 + Vector3.UP * 0.5
	p.global_position.y = float(scene.call(&"height_at", p.global_position.x, p.global_position.z)) + 0.1
	await wait(0.4)
	aim_at(bp)
	await wait(0.8)
	await shot("04_trash_beach")
	var near := sv.debris_near(bp, 20.0)
	check(not near.is_empty(), "API: debris_near")
	var n0 := get_tree().get_nodes_in_group(&"sv_debris").size()
	var made := sv.after_storm()
	await wait_frames(2)
	check(made > 0 and get_tree().get_nodes_in_group(&"sv_debris").size() == n0 + made, "после шторма новый мусор: +%d" % made)
	Survival.speed = 1.0
	Survival.rain_override = -1.0

func until(cond: Callable, sec: float) -> bool:
	var t := 0.0
	while t < sec:
		if cond.call():
			return true
		await wait(0.25)
		t += 0.25
		if int(t * 4.0) % 16 == 0:
			print("[dbg] until t=%.1f fps=%d ms=%d" % [t, Engine.get_frames_per_second(), Time.get_ticks_msec()])
	return bool(cond.call())
