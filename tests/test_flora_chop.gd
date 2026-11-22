extends TestCase
## FLORA: рассадка, рубка дерева → падение → пень → распил на брёвна → бревно в руки;
## камень-ресурс, кокосы с пальмы, подбор палок; скриншоты леса и пляжа.

var flora: Flora

func run() -> void:
	timeout_sec = 900.0
	Engine.max_physics_steps_per_frame = 40 # софт-рендер в контейнере ~1 кадр/с
	await wait(0.6)
	var p := get_tree().get_first_node_in_group(&"player") as Player
	check(p != null, "игрок есть")
	if p == null:
		return
	# Убираем заглушки тестовой сцены (деревья-цилиндры, glb-камни/кусты).
	for c in scene.get_children():
		if String(c.name).begins_with("Tree") or c.scene_file_path.contains("polyhaven"):
			c.queue_free()
	flora = Flora.new()
	flora.seed = 5
	scene.add_child(flora)
	await wait(0.5)
	check(flora.populated, "рассадка выполнена: %s" % str(flora.stats))
	check(int(flora.stats.get("palm", 0)) >= 10 and int(flora.stats.get("broadleaf", 0)) >= 8, "деревья: пальм %d, лиственных %d" % [flora.stats.get("palm", 0), flora.stats.get("broadleaf", 0)])
	check(int(flora.stats.get("grass", 0)) > 300, "трава: %d" % flora.stats.get("grass", 0))

	# ---- виды: лес и пляж
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.fov = 70.0
	cam.make_current()
	var hh := func(x: float, z: float) -> float: return float(scene.call(&"height_at", x, z))
	cam.global_position = Vector3(-6, hh.call(-6.0, 4.0) + 1.7, 4)
	cam.look_at(Vector3(18, hh.call(18.0, -10.0) + 3.0, -10))
	await wait(1.2)
	await shot("01_forest")
	# пляж: ищем пальму на краю
	var beach_palm: ChoppableTree = null
	for t in flora.trees_near(Vector3.ZERO, 200.0, &"palm"):
		if Vector2(t.position.x, t.position.z).length() > 36.0:
			beach_palm = t
			break
	if beach_palm:
		var dir := Vector2(beach_palm.position.x, beach_palm.position.z).normalized()
		var at := Vector2(beach_palm.position.x, beach_palm.position.z) + dir * 10.0 + Vector2(-dir.y, dir.x) * 6.0
		cam.global_position = Vector3(at.x, maxf(hh.call(at.x, at.y), 0.0) + 1.6, at.y)
		cam.look_at(beach_palm.global_position + Vector3(0, 5.0, 0))
		await wait(0.8)
		await shot("02_beach")
	cam.global_position = Vector3(0, 30, 75)
	cam.look_at(Vector3(0, 0, 0))
	await wait(0.8)
	await shot("03_aerial")

	# ---- рубка: лиственное дерево рядом с центром
	var tree: ChoppableTree = null
	for t in flora.trees_near(Vector3.ZERO, 40.0, &"broadleaf"):
		if t.global_position.length() > 9.0:
			tree = t
			break
	check(tree != null, "нашлось лиственное дерево для рубки")
	if tree == null:
		return
	# ставим игрока в 1.3 м от ствола, смотрим на ствол
	var tp := tree.global_position
	var from_dir := Vector3(tp.x, 0, tp.z).normalized()
	var stand := tp - from_dir * 1.35
	stand.y = hh.call(stand.x, stand.z) + 0.1
	p.global_position = stand
	p.inventory.add(&"axe_crude", 1)
	for i in Inventory.HOTBAR:
		if p.inventory.get_slot(i).get("id", &"") == &"axe_crude":
			p.inventory.select(i)
	await wait(0.4)
	var eye := p.get_eye_position()
	var aim := tp + Vector3(0, 1.0, 0) - eye
	p.set_look(atan2(-aim.x, -aim.z), atan2(aim.y, Vector2(aim.x, aim.z).length()))
	p.camera.make_current()
	await wait(0.3)
	var h0 := tree.health
	p.swing()
	await wait(0.9)
	check(tree.health < h0, "настоящий удар игрока (топор) ранит дерево: %.0f → %.0f" % [h0, tree.health])
	check(tree.cut_h > 0.2, "зарубка на высоте удара: %.2f м" % tree.cut_h)
	p.swing()
	await wait(0.9)
	await shot("04_notch")
	# удар рукой слабее
	var hb := tree.health
	tree.on_hit(p, {"position": tp + Vector3(0, 1, 0), "normal": -from_dir, "tool": &"hand"})
	var hand_dmg := hb - tree.health
	hb = tree.health
	tree.on_hit(p, {"position": tp + Vector3(0, 1, 0), "normal": -from_dir, "tool": &"axe", "damage": 14.0})
	var axe_dmg := hb - tree.health
	var side_v := Vector3(-from_dir.z, 0, from_dir.x)
	cam.global_position = tp + Vector3(0, tree.cut_h + 0.45, 0) - from_dir * 1.3 + side_v * 0.7
	cam.look_at(tp + Vector3(0, tree.cut_h, 0))
	cam.make_current()
	await wait(0.2)
	await shot("04b_notch_close")
	p.camera.make_current()
	check(axe_dmg > hand_dmg * 4.0, "топор сильнее руки: %.1f vs %.1f" % [axe_dmg, hand_dmg])
	var n := 0
	while not tree.felled and n < 40:
		tree.on_hit(p, {"position": tp + Vector3(0, 1, 0), "normal": -from_dir, "tool": &"axe", "damage": 14.0})
		n += 1
	check(tree.felled and tree.is_stump(), "дерево срублено, остался пень (ударов %d)" % (n + 4))
	var trunk: FallenTrunk = null
	for c in tree.get_parent().get_children():
		if c is FallenTrunk:
			trunk = c
	check(trunk != null, "появился падающий ствол")
	if trunk == null:
		return
	var top0 := trunk.global_transform.basis.y
	await wait(0.9)
	await shot("05_falling")
	var t := 0.0
	while is_instance_valid(trunk) and not trunk.freeze and t < 10.0:
		await wait(0.25)
		t += 0.25
	var tilt := rad_to_deg(trunk.global_transform.basis.y.angle_to(Vector3.UP))
	check(tilt > 55.0, "ствол упал: наклон %.0f°" % tilt)
	var away := trunk.global_position - p.global_position
	check(Vector3(trunk.global_transform.basis.y.x, 0, trunk.global_transform.basis.y.z).dot(Vector3(from_dir.x, 0, from_dir.z)) > 0.3, "упал от игрока")
	check(trunk.freeze, "ствол успокоился за %.1f с" % t)
	check(tree.is_in_group(&"stumps") and is_instance_valid(tree), "пень остаётся")
	var _u := top0 + away
	cam.global_position = tp - from_dir * 5.0 + Vector3(-from_dir.z, 0, from_dir.x) * 4.0 + Vector3(0, 2.6, 0)
	cam.look_at(tp + from_dir * 3.0)
	cam.make_current()
	await wait(0.3)
	await shot("06_fallen")

	# ---- распил на брёвна
	var logs_before := get_tree().get_nodes_in_group(&"log").size()
	var leaves0 := Flora.count_of(p, &"leaf")
	cam.global_position = trunk.crown_global_position() + Vector3(0, 3.5, 0) - from_dir * 7.0 + side_v * 5.0
	cam.look_at(trunk.global_position.lerp(trunk.crown_global_position(), 0.5))
	await wait(0.2)
	await shot("06b_fallen_close")
	var segs0 := trunk.logs_left()
	var k := 0
	while trunk.logs_left() > 0 and k < 60 and is_instance_valid(trunk):
		var hp := trunk.global_transform * Vector3(0, 1.0 + (trunk.logs_left() - 1) * FloraLib.LOG_LEN, 0)
		trunk.on_hit(p, {"position": hp, "normal": Vector3.UP, "tool": &"axe", "damage": 14.0})
		k += 1
	var logs: Array = get_tree().get_nodes_in_group(&"log").filter(func(l: Node) -> bool: return l is FloraLog)
	# у дерева пака (зонтичная крона) ствол до развилки короткий — брёвна дают и толстые ветви кроны
	var pack_tree := tree.variant.has("pack")
	if not pack_tree:
		check(logs.size() >= 2 and segs0 >= 2, "распилено на брёвна: %d (было сегментов %d, ударов %d, всего в группе log %d→%d)" % [logs.size(), segs0, k, logs_before, get_tree().get_nodes_in_group(&"log").size()])
	else:
		check(logs.size() >= 1 and segs0 >= 1, "ствол распилен: %d (сегментов %d)" % [logs.size(), segs0])
	# крона → листья и палки
	var kk := 0
	while is_instance_valid(trunk) and trunk.has_crown() and kk < 30:
		trunk.on_hit(p, {"position": trunk.crown_global_position(), "normal": Vector3.UP, "tool": &"axe", "damage": 14.0})
		kk += 1
	await wait(1.2)
	check(Flora.count_of(p, &"leaf") > leaves0, "крона дала листья: %d" % Flora.count_of(p, &"leaf"))
	if pack_tree:
		logs = get_tree().get_nodes_in_group(&"log").filter(func(l: Node) -> bool: return l is FloraLog)
		check(logs.size() >= 2, "ствол + ветви кроны — брёвна: %d" % logs.size())
	var sticks_on_ground := 0
	for c in flora.get_children() + scene.get_children():
		if c is FloraPickup and c.item_id == &"stick" and c.global_position.distance_to(tp) < 25.0:
			sticks_on_ground += 1
	check(sticks_on_ground >= 1, "крона рассыпалась палками: %d" % sticks_on_ground)
	await shot("07_logs")

	# ---- бревно в руки
	var lg := logs[0] as FloraLog
	lg.interact(p)
	check(p.carrying_log and p.carried_object == lg, "бревно в руках")
	if logs.size() > 1:
		(logs[1] as FloraLog).interact(p)
		check(lg.carried_count() == 2, "взято второе бревно: %d" % lg.carried_count())
	await wait(0.5)
	await shot("08_carry")
	lg.interact(p)
	await wait(1.5)
	check(not p.carrying_log, "брёвна положены")
	check(lg.visible and lg.global_position.distance_to(p.global_position) < 5.0, "бревно лежит рядом: %.1f м" % lg.global_position.distance_to(p.global_position))

	# ---- камень-ресурс
	var rock: ResourceRock = null
	for c in flora.get_children():
		if c is ResourceRock:
			rock = c
			break
	if rock == null:
		rock = ResourceRock.new()
		rock.position = Vector3(3, hh.call(3.0, 3.0), 3)
		flora.add_child(rock)
		await wait(0.1)
	var r0 := Flora.count_of(p, &"rock")
	for i in 4:
		rock.on_hit(p, {"position": rock.global_position + Vector3(0, 0.5, 0), "normal": Vector3.UP, "tool": &"rock"})
	check(Flora.count_of(p, &"rock") > r0, "камень даёт rock: %d" % Flora.count_of(p, &"rock"))

	# ---- пальма: тряска → кокос → подобрать
	var palm: ChoppableTree = null
	for pt in flora.trees_near(Vector3.ZERO, 80.0, &"palm"):
		if pt.coconuts > 0:
			palm = pt
			break
	check(palm != null, "есть пальма с кокосами")
	if palm:
		var c0 := palm.coconuts
		var tries := 0
		while palm.coconuts == c0 and tries < 30:
			palm.interact(p)
			tries += 1
		check(palm.coconuts < c0, "тряска уронила кокос (попыток %d)" % tries)
		await wait(1.5)
		var nut: FloraPickup = null
		for c in palm.get_parent().get_children():
			if c is FloraPickup and c.item_id == &"coconut":
				nut = c
		check(nut != null, "кокос на земле")
		if nut:
			check(nut.get_interact_text(p).to_lower().contains("кокос"), "подсказка: %s" % nut.get_interact_text(p))
			var cc := Flora.count_of(p, &"coconut")
			nut.interact(p)
			check(Flora.count_of(p, &"coconut") == cc + 1, "кокос подобран")
	# ---- палка на земле
	var stick: FloraPickup = null
	for c in flora.get_children():
		if c is FloraPickup and c.item_id == &"stick":
			stick = c
			break
	if stick:
		var s0 := Flora.count_of(p, &"stick")
		stick.interact(p)
		check(Flora.count_of(p, &"stick") == s0 + 1, "палка подобрана")
	print("[test] fps ", Engine.get_frames_per_second())
