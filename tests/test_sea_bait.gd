extends TestCase
## SEA+: приманка отвлекает стаю от пловца; верша, брошенная в воду, ставится и ловит
## рыбу из конечного запаса; копьё по стае даёт рыбу; хитбокс акулы ловит луч оружия,
## убитая акула оставляет мясо и зубы; толчки плота; безопасность переправы для ботов.

class Swimmer extends Node3D:
	var health: float = 100.0
	var max_health: float = 100.0
	var in_water: bool = true
	var bites: int = 0
	func _ready() -> void:
		add_to_group(&"characters")
		var inv := Inventory.new()
		inv.name = "Inventory"
		add_child(inv)
	func is_in_water() -> bool:
		return in_water
	func is_dead() -> bool:
		return health <= 0.0
	func apply_damage(amount: float, _source: Node, kind: StringName) -> void:
		if kind == &"bite":
			bites += 1
		health -= amount

class Deck extends Node3D:
	var bumps: int = 0
	func _ready() -> void:
		add_to_group(&"raft_deck")
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(3.0, 0.4, 3.0)
		m.mesh = b
		add_child(m)
	func deck_height() -> float:
		return global_position.y + 0.2
	func bump(_dir: Vector3, _s: float) -> void:
		bumps += 1

func _init() -> void:
	timeout_sec = 1400.0

func run() -> void:
	await wait(0.5)
	var sea := Sea.new()
	sea.life_enabled = false
	scene.add_child(sea)
	await wait(0.5)
	check(Items.get_item(&"shark_meat") != null and Items.get_item(&"fish_trap") != null, "предметы моря зарегистрированы")
	check(Items.recipes.has(&"r_fish_trap"), "рецепт верши")

	# --- приманка ---
	var sw := Swimmer.new()
	scene.add_child(sw)
	sw.global_position = Vector3(74.0, -0.35, 6.0)
	sw.health = 100000.0   # бессмертный — считаем укусы
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	cam.global_position = sw.global_position + Vector3(-9, 4, 8)
	cam.look_at(sw.global_position)
	var t := 0.0
	while sw.bites < 2 and t < 60.0:
		await wait(0.5)
		t += 0.5
	check(sw.bites >= 2, "стая атакует пловца (%d укусов за %.0f с)" % [sw.bites, t])
	var before := sw.bites
	await wait(10.0)
	var rate_before := float(sw.bites - before) / 10.0
	# бросаем мясо в воду в 25 м — как игрок клавишей G (ItemPickup падает в воду)
	var bait_pos := sw.global_position + Vector3(0, 0, 25)
	for k in 36:
		var a := TAU * k / 36.0
		var cand := sw.global_position + Vector3(cos(a), 0, sin(a)) * 25.0
		if sea.depth_at(cand.x, cand.z) > 3.0:
			bait_pos = cand
			break
	var bait_arr: Array[Dictionary] = [{"id": &"meat_raw", "n": 3}, {"id": &"fish_raw", "n": 2}]
	var pk := ItemPickup.spawn(scene, Vector3(bait_pos.x, -0.6, bait_pos.z), bait_arr)
	await wait(1.0)
	check(not is_instance_valid(pk) or pk.is_queued_for_deletion(), "приманка ушла в воду и стала приманкой")
	var lured := 0
	for s in sea.sharks:
		if s.bait_t > 0.0:
			lured += 1
	check(lured >= 1, "акул отвлеклось на приманку: %d" % lured)
	var b0 := sw.bites
	await wait(10.0)
	var rate_after := float(sw.bites - b0) / 10.0
	check(rate_after < rate_before or rate_after == 0.0, "укусов в секунду до приманки %.2f, после %.2f" % [rate_before, rate_after])
	var near_bait := sea.sharks_near(bait_pos, 12.0).size()
	check(near_bait >= 1, "у приманки кормятся акулы: %d" % near_bait)
	cam.global_position = bait_pos + Vector3(-8, 3, 6)
	cam.look_at(bait_pos + Vector3(0, -1, 0))
	await shot("bait")
	sw.queue_free()

	# --- толчки плота ---
	var deck := Deck.new()
	scene.add_child(deck)
	deck.global_position = Vector3(bait_pos.x, 0.0, bait_pos.z)
	t = 0.0
	while deck.bumps == 0 and t < 30.0:
		await wait(0.5)
		t += 0.5
	check(deck.bumps > 0, "акулы толкают низкий плот (%d за %.0f с), но не ломают" % [deck.bumps, t])
	deck.queue_free()

	# --- верша ---
	SeaTrap.speed = 40.0
	var trap_spot := Vector3(60.0, -1.0, -20.0)
	for k in 12:
		if sea.depth_at(trap_spot.x, trap_spot.z) > 1.5 and sea.depth_at(trap_spot.x, trap_spot.z) < 4.5:
			break
		trap_spot.x += 3.0
	var stock0 := sea.fish_stock_at(trap_spot)
	var trap_arr: Array[Dictionary] = [{"id": &"fish_trap", "n": 1}]
	ItemPickup.spawn(scene, trap_spot + Vector3(0, -0.3, 0), trap_arr)
	await wait(1.0)
	check(sea.traps.size() == 1, "верша встала на дно (глубина %.1f м)" % sea.depth_at(trap_spot.x, trap_spot.z))
	if sea.traps.size() == 1:
		var tr: SeaTrap = sea.traps[0]
		await wait(SeaTrap.CATCH_SEC / SeaTrap.speed * 3.5)
		check(tr.held >= 2, "в верше рыба: %d" % tr.held)
		check(sea.fish_stock_at(trap_spot) == stock0 - tr.held, "запас рыбы убыл: %d → %d" % [stock0, sea.fish_stock_at(trap_spot)])
		var fisher := Swimmer.new()
		scene.add_child(fisher)
		var held := tr.held
		tr.interact(fisher)
		var inv: Inventory = fisher.get_node(^"Inventory")
		check(inv.count(&"fish_raw") == held, "улов в инвентаре: %d" % inv.count(&"fish_raw"))
		cam.global_position = tr.global_position + Vector3(-2.2, 0.9, 1.8)
		cam.look_at(tr.global_position + Vector3(0, 0.3, 0))
		await wait(0.2)
		await shot("trap")
		tr.interact(fisher)
		await wait(0.1)
		check(inv.count(&"fish_trap") == 1 and sea.traps.is_empty(), "пустую вершу забрали обратно")
		fisher.queue_free()
	SeaTrap.speed = 1.0

	# --- конечный запас: выловить всё ---
	var key_pos := trap_spot
	var total := 0
	for i in 400:
		var g := sea.take_fish(key_pos, 1)
		if g == 0:
			break
		total += g
	check(sea.fish_stock_at(key_pos) == 0 and sea.take_fish(key_pos, 1) == 0, "рыба кончается навсегда (выловлено ещё %d)" % total)

	# --- копьё по стае (в другом месте, где рыба есть) ---
	var school: FishSchool = null
	for f in sea.schools:
		if sea.fish_stock_at(f.center) > 5:
			school = f
			break
	check(school != null, "есть стая в водах с рыбой")
	if school:
		var spear := Swimmer.new()
		scene.add_child(spear)
		spear.global_position = school.center + Vector3(1.5, 0, 0)
		var got := 0
		for i in 12:
			school.apply_damage(20.0, spear, &"melee")
		var inv2: Inventory = spear.get_node(^"Inventory")
		got = inv2.count(&"fish_raw")
		check(got >= 3, "копьём по стае: %d рыб из 12 ударов" % got)
		spear.queue_free()

	# --- хитбокс акулы и добыча ---
	var shark: Shark = null
	for s in sea.sharks:
		if not s.is_dead():
			shark = s
			break
	await wait_frames(3)
	var space := shark.get_world_3d().direct_space_state
	var from := shark.global_position + Vector3(0, 3.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, shark.global_position + Vector3(0, -2.0, 0))
	var hit: Dictionary = space.intersect_ray(q)
	var tgt: Node = null
	if not hit.is_empty():
		tgt = Combat._find_with(hit.collider as Node, &"apply_damage")
	check(tgt == shark, "луч оружия попадает в акулу (%s)" % [hit.get("collider")])
	var pickups_before := get_tree().get_nodes_in_group(&"pickups").size()
	shark.apply_damage(5000.0, null, &"explosion")
	await wait(0.3)
	var found_meat := false
	for p in get_tree().get_nodes_in_group(&"pickups"):
		for st in p.stacks:
			if st.id == &"shark_meat":
				found_meat = true
	check(found_meat and get_tree().get_nodes_in_group(&"pickups").size() > pickups_before, "с туши выпали мясо и зубы")

	# --- переправа для ботов ---
	var a := Vector3(40, 0, 0)
	var b := Vector3(140, 0, 30)
	var s1 := sea.safe_crossing_score(a, b)
	var s2 := sea.safe_crossing_score(Vector3(0, 0, 0), Vector3(5, 0, 5))
	check(s1 >= 0.0 and s1 <= 1.0 and s2 >= s1, "safe_crossing_score: открытая вода %.2f, суша %.2f" % [s1, s2])
	sea.queue_free()
	await wait(0.3)
