extends TestCase
## Животные в мире (тестовый остров): популяция, яд змеи, засада крокодила, воровство обезьяны,
## гнездо черепахи, удар по крабу и дроп, приручение и разведение кабанов, стаи птиц и мышей.

func _init() -> void:
	timeout_sec = 1400.0

var fauna: Fauna
var player: Player
var cam: Camera3D

func _shore_point(dir: Vector2, want_h: float) -> Vector3:
	var d := 20.0
	while d < 90.0:
		var p := dir.normalized() * d
		if Fauna.ground_y_at(fauna, p.x, p.y) < want_h:
			return Vector3(p.x, Fauna.ground_y_at(fauna, p.x, p.y), p.y)
		d += 0.5
	return Vector3.ZERO

func _view(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at)
	cam.current = true

func _put_player(p: Vector3) -> void:
	player.global_position = p + Vector3(0, 0.2, 0)
	player.velocity = Vector3.ZERO

func run() -> void:
	player = scene.get(&"player")
	fauna = (load("res://scenes/fauna/fauna.tscn") as PackedScene).instantiate() as Fauna
	scene.add_child(fauna)
	cam = Camera3D.new()
	scene.add_child(cam)
	await wait(1.5)
	check(fauna.populated, "популяция создана")
	var total := fauna.living_count()
	print("[test] animals total=", total)
	var kinds := {}
	for a in fauna.animals:
		kinds[a.species] = int(kinds.get(a.species, 0)) + 1
	print("[test] species: ", kinds)
	check(total >= 20, "на острове есть животные (%d)" % total)
	check(kinds.size() >= 8, "разные виды (%d)" % kinds.size())
	check(Items.get_item(&"hide") != null and Items.get_item(&"turtle_egg") != null, "предметы фауны зарегистрированы")

	# --- змея: предупреждение и укус с ядом ---
	var home := Vector3(0, Fauna.ground_y_at(fauna, 0, 0), 0)
	_put_player(home)
	await wait(0.2)
	var hp0 := player.health
	var snake := fauna.spawn(&"snake", home + Vector3(1.6, 0, 0), 5.0)
	snake.heading = PI * 0.5 # мордой к игроку (-X)
	_view(home + Vector3(2.0, 1.4, 2.6), home + Vector3(1.4, 0.1, 0))
	await wait(1.0)
	await shot("snake_warn")
	await wait(2.5)
	check(player.health < hp0, "змея укусила (hp %.1f → %.1f)" % [hp0, player.health])
	check(player.poison_time > 0.0, "игрок отравлен (poison_time %.1f)" % player.poison_time)
	var hp1 := player.health
	await wait(2.5)
	check(player.health < hp1, "яд отнимает здоровье (%.1f → %.1f)" % [hp1, player.health])
	snake.apply_damage(100.0, player)
	player.poison_time = 0.0
	player.health = player.max_health

	# --- крокодил в засаде у воды ---
	var shore := _shore_point(Vector2(1, 0.3), 0.35)
	var water := _shore_point(Vector2(1, 0.3), -0.7)
	check(shore != Vector3.ZERO and water != Vector3.ZERO, "найдены берег и мелководье")
	var croc := fauna.spawn(&"croc", water, 10.0)
	croc.heading = atan2(-(shore.x - water.x), -(shore.z - water.z))
	_put_player(shore + (shore - water).normalized() * 6.0)
	_view(water + Vector3(-3.0, 2.2, 5.5), water + Vector3(-1.0, 0.0, 0))
	await wait(2.0)
	check(croc.state == &"ambush", "крокодил в засаде (%s)" % croc.state)
	await shot("croc_ambush")
	var hp2 := player.health
	_put_player(shore)
	await wait(3.5)
	await shot("croc_attack")
	check(player.health < hp2, "крокодил атаковал у воды (hp %.1f → %.1f)" % [hp2, player.health])
	croc.apply_damage(500.0, player)
	player.health = player.max_health
	_put_player(home)

	# --- удар по крабу: смерть и дроп ---
	var crab := fauna.spawn(&"crab", home + Vector3(-2, 0, 1), 3.0)
	await wait(0.3)
	var pick0 := get_tree().get_nodes_in_group(&"pickups").size()
	crab.on_hit(player, {"damage": 12.0, "tool": &"rock"})
	await wait(0.4)
	check(crab.dead, "краб убит ударом")
	check(get_tree().get_nodes_in_group(&"pickups").size() > pick0, "выпал дроп (crab_meat)")

	# --- обезьяна-воровка ---
	var loot_pos := home + Vector3(6, 0.4, 6)
	var loot := ItemPickup.spawn(scene, loot_pos, [{"id": &"coconut", "n": 3}])
	var monkey := fauna.spawn(&"monkey", home + Vector3(12, 0, 12), 30.0)
	_put_player(home + Vector3(-15, 0, -15))
	monkey.set_meta(&"loot", loot)
	monkey.set_meta(&"steal_phase", &"approach")
	monkey.state = &"steal"
	_view(home + Vector3(3.0, 2.5, 13.0), home + Vector3(8, 0.3, 8))
	await wait(1.2)
	await shot("monkey_run")
	await wait(4.0)
	check(not is_instance_valid(loot) or loot.stacks.is_empty(), "обезьяна утащила добычу")
	check(not monkey.stolen.is_empty(), "добыча у обезьяны (%s)" % [monkey.stolen])
	var mp := monkey.global_position
	monkey.apply_damage(100.0, player)
	await wait(0.5)
	var got_back := false
	for p in get_tree().get_nodes_in_group(&"pickups"):
		var pu := p as ItemPickup
		if pu and pu.global_position.distance_to(mp) < 3.0:
			for s in pu.stacks:
				if s.id == &"coconut":
					got_back = true
	check(got_back, "убитая обезьяна роняет украденное")

	# --- черепаха откладывает яйца ---
	var beach := _shore_point(Vector2(-0.4, 1), 0.6)
	fauna.force_nesting = true
	var turtle := fauna.spawn(&"turtle", beach, 10.0)
	_put_player(beach + Vector3(-8, 0, -8))
	_view(beach + Vector3(2.5, 1.6, 2.5), beach)
	await wait(1.5)
	await shot("turtle")
	await wait(7.0)
	var nests := get_tree().get_nodes_in_group(&"turtle_nests")
	check(nests.size() > 0, "черепаха отложила яйца (гнёзд %d)" % nests.size())
	if nests.size() > 0:
		var nest := nests[0] as Node3D
		_view(nest.global_position + Vector3(1.4, 1.2, 1.4), nest.global_position)
		await wait(0.3)
		await shot("nest")
		nest.call(&"interact", player)
		check(player.inventory.count(&"turtle_egg") > 0, "яйца собраны (%d)" % player.inventory.count(&"turtle_egg"))
	fauna.force_nesting = false

	# --- приручение и разведение кабанов ---
	_put_player(home)
	player.inventory.add(&"coconut", 10)
	var b1 := fauna.spawn(&"boar", home + Vector3(2.0, 0, 0.5), 10.0)
	var b2 := fauna.spawn(&"boar", home + Vector3(2.5, 0, -1.0), 10.0)
	await wait(0.3)
	for i in 3:
		b1.on_feed(player, &"coconut")
		b2.on_feed(player, &"coconut")
	check(b1.tamed and b2.tamed, "кабаны приручены кормлением")
	check(b1.owner_node == player, "хозяин — игрок")
	fauna.breed_seconds = 3.0
	fauna.grow_seconds = 20.0
	await wait(9.0)
	var babies := 0
	for a in fauna.animals_near(home, 15.0, &"boar"):
		if a.growth < 0.99 and a.tamed:
			babies += 1
	check(babies >= 1, "родился приручённый поросёнок (%d)" % babies)
	_view(home + Vector3(-1.5, 1.6, 4.5), home + Vector3(1.0, 0.3, 0))
	await wait(0.3)
	await shot("tamed_family")
	# хозяин уходит — питомцы идут следом
	_put_player(home + Vector3(-12, 0, 0))
	await wait(6.0)
	check(b1.global_position.distance_to(player.global_position) < 8.0, "приручённый кабан идёт за хозяином")

	# --- кормление через ПКМ-хук (use_selected) ---
	var ig := fauna.spawn(&"iguana", player.global_position + Vector3(0, 0, -1.4), 5.0)
	ig.heading = 0.0
	player.inventory.add(&"leaf", 5)
	check(ig.on_feed(player, &"leaf"), "игуана берёт лист (on_feed)")

	# --- птицы и летучие мыши ---
	fauna.force_night_birds = true
	var fl_p := fauna.spawn_flock(&"parrot", home + Vector3(0, 0, -10), 7, 20.0)
	var fl_b := fauna.spawn_flock(&"bat", home + Vector3(8, 0, -6), 8, 12.0)
	check(fl_p.size() == 7 and fl_b.size() == 8, "стаи созданы")
	_view(home + Vector3(0, 3.0, 8.0), home + Vector3(0, 9.0, -10.0))
	await wait(3.0)
	await shot("flocks")
	var flying := 0
	for a in fl_p:
		if a.global_position.y > Fauna.ground_y_at(fauna, a.global_position.x, a.global_position.z) + 2.0:
			flying += 1
	check(flying >= 5, "попугаи летают (%d)" % flying)
	# обзор популяции
	var some := fauna.animals_near(home, 60.0)
	print("[test] near home: ", some.size())
	_view(home + Vector3(0, 30, 40), home)
	await wait(0.5)
	await shot("overview")
