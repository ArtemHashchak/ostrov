extends TestCase
## FLORA G2: рассадка по биомам на архипелаге, мангры/баньяны, узлы-ресурсы (лианы, травы, дикие
## культуры, ягоды, хлопок, руда/сера), nodes_near/materialize, пробуждение/засыпание деревьев,
## рубка «спящего» дерева через коллизию чанка, невосстанавливаемость; скриншоты и замер.

func _init() -> void:
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 1450.0

var flora: Flora
var cam: Camera3D
var w: Node

func _hh(x: float, z: float) -> float:
	return float(w.call(&"height_at", x, z))

func run() -> void:
	Engine.max_physics_steps_per_frame = 40
	var t_wait := 0.0
	while Flora.instance() == null or not Flora.instance().populated:
		await wait(0.5)
		t_wait += 0.5
		if t_wait > 300.0:
			break
	flora = Flora.instance()
	check(flora != null and flora.populated, "флора рассажена")
	if flora == null:
		return
	w = get_tree().get_first_node_in_group(&"world")
	var st := flora.stats
	print("[test] stats: ", st)
	print("[test] острова: ", w.call(&"islands").map(func(I): return "%s(%s,r%d)" % [I.get("name", I.id), I.kind, int(I.radius)]))
	for k in ["palm", "broadleaf", "mangrove", "banyan", "liana", "herb", "berries", "cotton"]:
		check(int(st.get(k, 0)) > 0, "есть %s: %d" % [k, int(st.get(k, 0))])
	check(int(st.get("wild_taro", 0)) + int(st.get("wild_maize", 0)) + int(st.get("wild_melon", 0)) > 0, "дикие культуры: таро %d, кукуруза %d, дыня %d" % [st.get("wild_taro", 0), st.get("wild_maize", 0), st.get("wild_melon", 0)])
	check(int(st.get("iron_ore", 0)) + int(st.get("sulfur", 0)) > 0, "руда: железо %d, сера %d (редко)" % [st.get("iron_ore", 0), st.get("sulfur", 0)])
	check(int(st.get("iron_ore", 0)) + int(st.get("sulfur", 0)) < int(st.get("rock", 0)), "руды меньше, чем простых валунов")
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	# игрок не должен будить лес во время съёмки — уводим далеко в море
	if p:
		p.set_physics_process(false)
		p.global_position = Vector3(5000, 50, 5000)
	cam = Camera3D.new()
	cam.fov = 68.0
	scene.add_child(cam)
	cam.make_current()

	# ---- API: nodes_near / materialize / harvest
	var actor := Node3D.new()
	actor.name = "TestActor"
	scene.add_child(actor)
	var everything := flora.nodes_near(Vector3.ZERO, 5000.0)
	print("[test] всего узлов: %d, осталось по видам: %s" % [everything.size(), str(flora.remaining())])
	for kind in [&"liana", &"herb", &"berries", &"cotton"]:
		var found := flora.nodes_near(Vector3.ZERO, 5000.0, kind)
		if found.is_empty():
			check(false, "nodes_near(%s) пусто" % kind)
			continue
		var e: Dictionary = found[0]
		var n := flora.materialize(e) as ResourceNode
		check(n != null, "materialize %s → узел" % kind)
		if n == null:
			continue
		var got := n.harvest(actor)
		check(not got.is_empty(), "%s → %s" % [kind, str(got)])
		check(n.harvest(actor).is_empty(), "%s повторно не собирается" % kind)
		await wait_frames(1)
		var again := flora.nodes_near(e.position, 0.5, kind)
		check(again.is_empty(), "%s больше не в nodes_near (невосстанавливаемо)" % kind)
	check(Flora.count_of(actor, &"fiber") > 0 and Flora.count_of(actor, &"liana") > 0, "лиана → liana + fiber")
	check(flora.nodes_near(Vector3.ZERO, 5000.0, &"fiber").size() > 0, "поиск по предмету: fiber → лианы")
	check(flora.nodes_near(Vector3.ZERO, 5000.0, &"seed").size() > 0, "поиск семян: %d источников" % flora.nodes_near(Vector3.ZERO, 5000.0, &"seed").size())
	var crops := flora.nodes_near(Vector3.ZERO, 5000.0, &"crop")
	if not crops.is_empty():
		var cn := flora.materialize(crops[0]) as ResourceNode
		var got := cn.harvest(actor) if cn else {}
		check(got.keys().any(func(k): return String(k).begins_with("seed_")), "%s даёт семена: %s" % [crops[0].kind, str(got)])
	var ores := flora.nodes_near(Vector3.ZERO, 5000.0, &"ore")
	if not ores.is_empty():
		var rock := flora.materialize(ores[0]) as ResourceRock
		check(rock != null and rock.ore != &"", "рудный валун: %s" % ores[0].kind)
		if rock:
			for i in 40:
				rock.on_hit(actor, {"tool": &"pickaxe", "position": rock.global_position + Vector3.UP})
			check(Flora.count_of(actor, rock.ore) >= 3, "добыто %s: %d" % [rock.ore, Flora.count_of(actor, rock.ore)])
			check(rock.depleted and flora.nodes_near(rock.global_position, 0.5, &"ore").is_empty(), "жила выработана навсегда")

	# ---- деревья: рубка «спящего» дерева через коллизию чанка
	var bl := flora.nodes_near(Vector3.ZERO, 5000.0, &"broadleaf")
	var target: Dictionary = {}
	for e in bl:
		if e.node == null:
			target = e
			break
	check(not target.is_empty(), "есть спящее лиственное дерево")
	if not target.is_empty():
		var tp: Vector3 = target.position
		actor.global_position = tp + Vector3(2.0, 1.0, 0)
		var space := (w as Node3D).get_world_3d().direct_space_state
		await wait_frames(2)
		var q := PhysicsRayQueryParameters3D.create(tp + Vector3(3.0, 1.0, 0.0), tp + Vector3(-1.0, 1.0, 0.0))
		var hit := space.intersect_ray(q)
		check(not hit.is_empty() and hit.collider is FloraColliders, "луч попал в коллизию спящего ствола: %s" % str(hit.get("collider")))
		if not hit.is_empty() and hit.collider is FloraColliders:
			for i in 30:
				var h2 := hit.duplicate()
				h2["tool"] = &"axe"
				h2["damage"] = 14.0
				var hc: Node = h2.collider
				hc.call(&"on_hit", actor, h2)
				var tr = target.rec.node
				if tr and (tr as ChoppableTree).felled:
					break
				if tr:
					# дальше бьём уже проснувшееся дерево
					hit = h2
					hit.collider = tr
			var tr2 = target.rec.node
			check(tr2 != null and (tr2 as ChoppableTree).felled, "дерево срублено (проснулось от удара)")
			check(flora.nodes_near(tp, 0.5, &"tree").is_empty(), "срубленное дерево исчезло из nodes_near")
	# ---- пробуждение у персонажа и засыпание
	actor.add_to_group(&"characters")
	var palms := flora.nodes_near(Vector3.ZERO, 5000.0, &"palm")
	var sleeper: Dictionary = {}
	for e in palms:
		if e.node == null:
			sleeper = e
			break
	if not sleeper.is_empty():
		actor.global_position = sleeper.position + Vector3(4, 0, 0)
		flora._tick(false)
		check(sleeper.rec.node != null, "пальма проснулась рядом с персонажем")
		actor.global_position = sleeper.position + Vector3(400, 0, 0)
		sleeper.rec.pt = -100.0
		flora._tick(false)
		await wait_frames(2)
		check(sleeper.rec.node == null, "нетронутая пальма снова уснула (MultiMesh)")
	actor.remove_from_group(&"characters")
	actor.global_position = Vector3(6000, 0, 6000)

	# ---- скриншоты
	await _shot_kind("01_jungle", &"banyan", Vector3(14, 1.7, 9), 3.5, [&"jungle"])
	await _shot_kind("02_jungle_floor", &"broadleaf", Vector3(9, 1.7, -6), 2.0, [&"jungle"])
	await _shot_kind("03_mangrove", &"mangrove", Vector3(9, 1.6, 7), 1.5, [])
	await _shot_kind("04_meadow_crops", &"wild_maize", Vector3(4.5, 1.5, 3.0), 0.6, [&"meadow"])
	await _shot_kind("05_berries_cotton", &"cotton", Vector3(3.5, 1.4, 2.5), 0.5, [])
	await _shot_kind("06_ore", &"ore", Vector3(2.2, 1.3, 1.6), 0.5, [])
	await _shot_kind("07_liana_herb", &"liana", Vector3(4.0, 1.6, 3.0), 2.2, [])
	await _shot_kind("08_beach", &"palm", Vector3(10, 1.7, 8), 5.0, [&"beach"])
	# общий вид + замер кадра
	var isl: Array = w.call(&"islands")
	var c0: Vector2 = isl[0].center
	cam.global_position = Vector3(c0.x + 40, 70, c0.y + 170)
	cam.look_at(Vector3(c0.x, 0, c0.y))
	flora._tick(true)
	await wait(1.5)
	await shot("09_aerial")
	var t0 := Time.get_ticks_usec()
	var frames := 0
	while Time.get_ticks_usec() - t0 < 4000000:
		await get_tree().process_frame
		frames += 1
	var nodes := flora.get_child_count()
	var mmi := 0
	for c in flora.get_children():
		if c is MultiMeshInstance3D:
			mmi += 1
	print("[test] perf: populate %d мс (всего %d), детей Flora %d, MMI %d, спящих чанков %d, кадров за 4 с (llvmpipe): %d, draw calls %d, примитивов %d" % [
		st.get("ms_populate", -1), st.get("ms", -1), nodes, mmi, st.get("tree_chunks", 0), frames,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	# мир v5 (≈3×3 км, суши ×2) — порог больше
	var lim := 9000 if (get_tree().get_first_node_in_group(&"world") as World).gen_version >= 5 else 4000
	check(nodes < lim, "узлов Flora немного: %d (порог %d)" % [nodes, lim])

## Камера у ближайшего узла вида kind (в нужном биоме): offset — откуда смотрим, look_h — высота взгляда.
func _shot_kind(name: String, kind: StringName, offset: Vector3, look_h: float, biomes: Array) -> void:
	var list := flora.nodes_near(Vector3.ZERO, 5000.0, kind)
	var pick: Dictionary = {}
	var best := -1.0
	for e in list.slice(0, 300):
		var pos: Vector3 = e.position
		if not biomes.is_empty() and not biomes.has(w.call(&"biome_at", pos.x, pos.z)):
			continue
		# предпочитаем места, где вокруг много всего (живописнее)
		var score := float(flora.nodes_near(pos, 14.0).size())
		if score > best:
			best = score
			pick = e
	if pick.is_empty():
		print("[test] нет узла для кадра ", name)
		return
	var tp: Vector3 = pick.position
	# камера — на суше: перебираем 8 направлений вокруг цели
	var at := tp + Vector3(offset.x, 0, offset.z)
	var wl := float(w.call(&"water_level")) if w.has_method(&"water_level") else 0.0
	for a in 8:
		var o := Vector3(offset.x, 0, offset.z).rotated(Vector3.UP, a * PI / 4.0)
		if _hh(tp.x + o.x, tp.z + o.z) > wl + 0.35:
			at = tp + o
			break
	var gy := maxf(_hh(at.x, at.z), wl + 0.3)
	cam.global_position = Vector3(at.x, gy + offset.y, at.z)
	cam.look_at(tp + Vector3(0, look_h, 0))
	flora._tick(true)
	await wait(1.2)
	await shot(name)
