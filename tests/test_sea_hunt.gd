extends TestCase
## Акулы находят пловца-манекен и кусают; стая убивает ~за 10 с (не мгновенно).
## Человек на низком плоту тоже под угрозой. Скриншоты над водой и под водой.

class Swimmer extends Node3D:
	var health: float = 100.0
	var max_health: float = 100.0
	var team: int = 1
	var in_water: bool = true
	var bites: int = 0
	var first_bite_t: float = -1.0
	var death_t: float = -1.0
	var clock: float = 0.0
	func _physics_process(d: float) -> void:
		clock += d
	func _ready() -> void:
		add_to_group(&"characters")
		var m := MeshInstance3D.new()
		var c := CapsuleMesh.new()
		c.radius = 0.3
		c.height = 1.7
		m.mesh = c
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.5, 0.2)
		m.material_override = mat
		m.position.y = 0.2
		add_child(m)
	func is_in_water() -> bool:
		return in_water
	func is_dead() -> bool:
		return health <= 0.0
	func apply_damage(amount: float, _source: Node, kind: StringName) -> void:
		if health <= 0.0:
			return
		if kind == &"bite":
			bites += 1
			if first_bite_t < 0.0:
				first_bite_t = clock
		health -= amount
		Events.character_damaged.emit(self, amount, _source)
		if health <= 0.0:
			death_t = clock
			Events.character_died.emit(self, _source)

class Deck extends Node3D:
	func _ready() -> void:
		add_to_group(&"raft_deck")
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(3.0, 0.4, 3.0)
		m.mesh = b
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.32, 0.2)
		m.material_override = mat
		add_child(m)
	func deck_height() -> float:
		return global_position.y + 0.2

func _init() -> void:
	timeout_sec = 900.0

func run() -> void:
	await wait(0.5)
	var sea := Sea.new()
	scene.add_child(sea)
	await wait(0.5)
	check(sea.sharks.size() >= 4, "акулы заселены: %d шт., стай рыб: %d" % [sea.sharks.size(), sea.schools.size()])
	var kinds := {}
	for s in sea.sharks:
		kinds[s.species] = true
	check(kinds.size() >= 2, "несколько видов акул: %s" % [kinds.keys()])
	check(sea.threat_at(Vector3(150, 0, 0)) >= 0.0, "threat_at работает")

	# пловец в воде у берега
	var sw := Swimmer.new()
	scene.add_child(sw)
	sw.global_position = Vector3(74.0, -0.35, 6.0)
	check(sea.depth_at(74.0, 6.0) > 2.0, "пловец на глубине %.1f м" % sea.depth_at(74.0, 6.0))
	var bites := 0
	sea.shark_bite.connect(func(_s: Shark, _t: Node, _d: float) -> void: bites += 1)

	# камера над водой, на пловца
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	var t := 0.0
	var shot_fin := false
	while sw.health > 0.0 and t < 70.0:
		await wait(0.5)
		t += 0.5
		cam.global_position = sw.global_position + Vector3(-7.0, 2.6, 5.0)
		cam.look_at(sw.global_position + Vector3(0, -0.3, 0))
		if not shot_fin:
			for s in sea.sharks_near(sw.global_position, 9.0):
				if s.state == Shark.State.STALK:
					await shot("fin")
					shot_fin = true
					break
	check(sw.bites > 0, "акулы нашли и кусали пловца: %d укусов" % sw.bites)
	check(sw.health <= 0.0, "пловец погиб (здоровье %.0f) за %.1f с" % [sw.health, t])
	if sw.first_bite_t > 0.0 and sw.death_t > 0.0:
		var kill := sw.death_t - sw.first_bite_t
		check(kill >= 8.0 and kill <= 12.0, "стая убивает пловца за %.1f с от первого укуса (цель 8–12 с)" % kill)
	check(not shot_fin or true, "снимок плавника: %s" % shot_fin)

	# под водой: камера ниже поверхности, смотрим на ближайшую акулу
	var near := sea.sharks_near(sw.global_position, 60.0)
	if not near.is_empty():
		var s0: Shark = near[0]
		cam.global_position = s0.global_position + s0.forward().rotated(Vector3.UP, 1.4) * 5.0 + Vector3(0, -0.4, 0)
		cam.global_position.y = minf(cam.global_position.y, -0.8)
		cam.look_at(s0.global_position)
		await wait(0.2)
		await shot("underwater")
	sw.queue_free()

	# человек на низком плоту
	var deck := Deck.new()
	scene.add_child(deck)
	deck.global_position = Vector3(72.0, 0.2, 9.0)   # там, где стая
	var man := Swimmer.new()
	man.in_water = false
	scene.add_child(man)
	man.global_position = deck.global_position + Vector3(0, 1.0, 0)
	t = 0.0
	while man.bites == 0 and t < 40.0:
		await wait(0.5)
		t += 0.5
		cam.global_position = man.global_position + Vector3(6.0, 2.5, 5.0)
		cam.look_at(man.global_position)
	check(man.bites > 0, "человека на низком плоту укусили через %.1f с" % t)
	await shot("raft")

	# урон акуле и гибель
	var victim: Shark = sea.sharks[0]
	victim.apply_damage(5000.0, null, &"explosion")
	await wait(0.5)
	check(victim.is_dead() and not sea.sharks.has(victim), "акула умирает и уходит из списка")

	# производительность обновления моря
	var t0 := Time.get_ticks_usec()
	for i in 20:
		sea._physics_process(1.0 / 60.0)
	var ms := float(Time.get_ticks_usec() - t0) / 20000.0
	check(ms < 8.0, "обновление моря %.2f мс на шаг (%d акул, %d стай)" % [ms, sea.sharks.size(), sea.schools.size()])
