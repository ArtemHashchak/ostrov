## test-timeout: 1500
extends TestCase
## v5.2 (агент K): живой риф в мире v5 — коньки в лугах морской травы (генерация),
## морские ежи записаны и колют босого игрока (хромота), сандалии спасают, коралловые
## рыбы привязаны к своему кораллу, выдох дельфина у поверхности.

var sea: Sea
var life: ReefLife

func _init() -> void:
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 1450.0

func run() -> void:
	await wait(1.0)
	var w := get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.is_ready, "мир готов")
	if w == null:
		return
	w.set_time_of_day(11.5)
	sea = Sea.new()
	sea.auto_populate = false
	scene.add_child(sea)
	sea._find_world()
	sea.populate()
	life = sea.reef_life as ReefLife
	check(life != null, "живой риф построен")
	if life == null:
		return
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	# обойти несколько мест у рифов, пока не найдутся коньки и ежи
	var zones: Array = sea.reef_zones()
	var sh_total := 0
	var urch := 0
	var shelters := 0
	var coral_fish := 0
	var tested := 0
	for z: Dictionary in zones:
		if tested >= 8:
			break
		tested += 1
		var c: Vector2 = z.center
		var spot := Vector3(c.x, 0, c.y)
		life.stream_now(Vector3(spot.x, sea.floor_at(spot.x, spot.z) + 1.4, spot.z))
		cam.global_position = Vector3(spot.x, sea.floor_at(spot.x, spot.z) + 2.0, spot.z)
		sh_total = life.seahorse_count
		urch = 0
		for k in life.urchin_spots:
			urch += (life.urchin_spots[k] as PackedVector3Array).size()
		shelters = 0
		coral_fish = 0
		for s in life.schools:
			if s.mode == 1:
				coral_fish += 1
				if s.shelter != Vector3.INF:
					shelters += 1
		if sh_total > 0 and urch > 0:
			break
	print("[test] коньков %d, ежей %d, рифовых групп %d (с домом-кораллом %d)" % [sh_total, urch, coral_fish, shelters])
	check(sh_total > 0, "в лугах морской травы есть коньки: %d" % sh_total)
	check(urch > 0, "морские ежи записаны: %d" % urch)
	check(shelters > 0 and shelters >= coral_fish / 4, "у рифовых групп есть свой коралл: %d из %d" % [shelters, coral_fish])
	var beds := 0
	for n in life.find_children("Seahorses", "", true, false):
		beds += 1
		for c in n.get(&"critters"):
			check((c as SeaCritter).clinging, "конёк держится за стебель")
			break
	check(beds > 0, "узлы коньков в клетках рифа: %d" % beds)
	# ---------- укол ежа ----------
	var q := Vector3.INF
	for k in life.urchin_spots:
		for u: Vector3 in life.urchin_spots[k]:
			if u.y < BuildEnv.water_level() - 0.4 and (q == Vector3.INF or u.y > q.y):
				q = u   # самый мелкий ёж
	print("[test] ёж на глубине %.1f м" % (BuildEnv.water_level() - q.y if q != Vector3.INF else -1.0))
	var p := get_tree().get_first_node_in_group(&"player") as Player
	if p == null:
		p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
		scene.add_child(p)
	var fauna := Fauna.instance()
	if fauna == null:
		fauna = (load("res://scenes/fauna/fauna.tscn") as PackedScene).instantiate() as Fauna
		fauna.set(&"auto_populate", false)
		scene.add_child(fauna)
		await wait(0.5)
	if urch == 0:
		print("[test] ежей нет — укол пропущен")
		return
	if q == Vector3.INF:
		print("[test] ежа на глубине по пояс нет — укол пропущен")
		return
	life.stream_now(q + Vector3.UP)
	var ext: Node = fauna.ext
	var hp := p.health
	var st0 := int(ext.stats.urchin_stings)
	ext.set(&"_urchin_cd", 0.0)
	for i in 10:
		p.global_position = q
		p.velocity = Vector3.ZERO
		await wait_frames(1)
	check(int(ext.stats.urchin_stings) > st0 and p.limp_t > 0.0, "наступил на ежа: укол и хромота (здоровье %.0f → %.0f)" % [hp, p.health])
	p.limp_t = 0.0
	p.inventory.add(&"sandals", 1)
	ext.set(&"_urchin_cd", 0.0)
	var st1 := int(ext.stats.urchin_stings)
	for i in 10:
		p.global_position = q
		p.velocity = Vector3.ZERO
		await wait_frames(1)
	check(int(ext.stats.urchin_stings) == st1 and p.limp_t == 0.0, "в сандалиях — не колется")
