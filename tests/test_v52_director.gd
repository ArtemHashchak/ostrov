## test-timeout: 600
extends TestCase
## v5.2 (агент L): режиссёр сценок суши (LandDirector/LandScene) и подсказки мира (WorldHints).
## Свой простой «мир» (берег: суша при x<20, море дальше), без генератора — быстро и детерминированно.
## Каждая сценка запускается и прокручивается вручную (шаги _process), проверяется ход сюжета.

class FakeWorld extends Node3D:
	var tide_amplitude := 0.8
	var hour := 12.0
	var storm := 0.0
	var zones = null
	var sky = null
	func _ready() -> void:
		add_to_group(&"world")
	func height_at(x: float, _z: float) -> float:
		return (20.0 - x) * 0.1 if x < 20.0 else -3.0 - (x - 20.0) * 0.05
	func water_level() -> float:
		return 0.0
	func time_of_day() -> float:
		return hour
	func is_night() -> bool:
		return hour >= 20.0 or hour < 5.5
	func storm_intensity() -> float:
		return storm

var w: FakeWorld
var d: LandDirector

func _init() -> void:
	scene_path = "res://tests/empty_stage.tscn"
	timeout_sec = 580.0

func run() -> void:
	await wait_frames(3)
	w = FakeWorld.new()
	scene.add_child(w)
	var far := Node3D.new()        # «игрок» далеко — актёров не отпускаем на волю
	far.add_to_group(&"player")
	scene.add_child(far)
	far.global_position = Vector3(500, 0, 500)
	d = LandDirector.new()
	d.world = w
	d.auto = false
	scene.add_child(d)
	await wait_frames(2)
	_test_catalog()
	_test_candidates()
	_test_scenes()
	_test_hints()
	await wait_frames(2)

func _test_catalog() -> void:
	var ids := LandDirector.scene_ids()
	check(ids.size() >= 15, "сценок в каталоге: %d (нужно ≥ 15)" % ids.size())
	for id: String in ids:
		check(LandDirector.scene_title(id) != id, "у сценки %s есть русское название" % id)

func _test_candidates() -> void:
	w.hour = 12.0
	var day := d.candidates_at(Vector3(15, 0.5, 0))      # пляж днём
	check("gull_crab_drop" in day, "днём на пляже — «чайка роняет краба»")
	check(not ("turtle_nesting" in day), "днём черепаха не выходит откладывать яйца")
	var sea := d.candidates_at(Vector3(40, 0, 0))
	check("gulls_fish" in sea, "в море у берега днём — «чайки над косяком»")
	check(not ("gull_crab_drop" in sea), "на воде нет сухопутных сценок")
	w.hour = 23.0
	var night := d.candidates_at(Vector3(15, 0.5, 0))
	check("turtle_nesting" in night and "hatchlings" in night, "ночью на пляже — черепахи")
	check(not ("gulls_fight" in night), "ночью чайки не дерутся")
	w.storm = 0.9
	d._recent.clear()
	check(d.try_auto() == null, "в шторм сценок нет")
	w.storm = 0.0
	w.hour = 12.0

func _run(id: String, p: Vector3, steps: int, dt: float = 0.1) -> LandScene:
	d._recent.clear()
	var s := d.start(id, p, true)
	check(s != null, "сценка %s запустилась" % id)
	if s == null:
		return null
	check(s.actors.size() > 0, "%s: актёры есть (%d)" % [id, s.actors.size()])
	for i in steps:
		if s.done:
			break
		s._process(dt)
	return s

func _test_scenes() -> void:
	var beach := Vector3(14, 0.6, 0)
	var forest := Vector3(0, 2.0, 0)
	# 1. чайка поднимает краба, роняет — краб разбивается
	var s := _run("gull_crab_drop", beach, 300)
	if s:
		var crab: Animal = s.data.crab
		check(is_instance_valid(crab) and crab.dead, "краб упал с высоты и разбился")
		check(int(s.data.phase) >= 2, "чайка села клевать (фаза %d)" % int(s.data.phase))
		s.cleanup()
	# 2. черепашата — уходят в море, краб ловит одного
	s = _run("hatchlings", beach, 700)
	if s:
		var alive := 0
		var dead := 0
		for b: Animal in s.data.babies:
			if is_instance_valid(b):
				if b.dead:
					dead += 1
				else:
					alive += 1
		check(alive < 11, "черепашата добрались до воды (на суше осталось %d из 11)" % alive)
		check(dead >= 1, "краб поймал детёныша (%d)" % dead)
		s.cleanup()
	# 3. варан у туши
	s = _run("monitor_carcass", forest, 300)
	if s:
		var mon: Animal = s.data.mon
		var body: Animal = s.data.body
		check(body.dead, "туша лежит")
		# без Fauna (тестовый мир) звери ходят по «уровню 0» неровно — допуск шире
		check(mon.global_position.distance_to(body.global_position) < 3.6, "варан подошёл к туше (%.1f м)" % mon.global_position.distance_to(body.global_position))
		s.cleanup()
		check(body in d.leftovers, "туша остаётся в мире после сценки (для падальщиков)")
	# 4. ход крабов
	s = _run("crab_march", Vector3(8, 1.2, 0), 500)
	if s:
		var reached := 0
		for c: Variant in s.data.crabs:
			if not is_instance_valid(c) or (c as Animal).is_queued_for_deletion():
				reached += 1
		check(reached >= 10, "крабы дошли до моря: %d из 34" % reached)
		s.cleanup()
	# 5. летучие мыши: стая поднимается и делится на три
	s = _run("bat_emergence", forest, 200)
	if s:
		check(s.data.split, "стая летучих мышей разделилась")
		var hi := 0.0
		for a: Animal in s.actors:
			if is_instance_valid(a):
				hi = maxf(hi, a.global_position.y)
		check(hi > 10.0, "мыши поднялись над землёй (%.1f м)" % hi)
		s.cleanup()
	# 6. чайки дерутся, одна уносит рыбу
	s = _run("gulls_fight", beach, 250)
	if s:
		check(int(s.data.thief) >= 0, "одна чайка утащила рыбу")
		s.cleanup()
	# 7–11, 13–16: просто идут без ошибок
	for id in ["iguanas_bask", "parrots_flock", "boar_family", "hermit_shell", "snake_hunt", "monitor_shore", "crabs_low_tide"]:
		s = _run(id, forest if id in ["parrots_flock", "boar_family", "snake_hunt"] else beach, 450)
		if s:
			var moved := false
			for a: Animal in s.actors:
				if is_instance_valid(a) and (a.speed > 0.01 or a.state != &"idle" or a.dead):
					moved = true
			check(moved or id == "iguanas_bask" or (id == "snake_hunt" and s.data.struck), "%s: актёры живут" % id)
			if id == "snake_hunt":
				check(s.data.struck, "змея схватила саламандру")
			s.cleanup()
	for id in ["gulls_fish", "air_chase"]:
		s = _run(id, Vector3(40, 0, 0), 200)
		if s:
			check(s.props.size() > 0, "%s: всплески/рыба есть" % id)
			s.cleanup()
	# 12. черепаха выходит, копает, оставляет гнездо — к нему следы
	s = _run("turtle_nesting", Vector3(12, 0.8, 0), 2200)
	if s:
		var nests := get_tree().get_nodes_in_group(&"turtle_nests")
		check(nests.size() >= 1, "черепаха оставила гнездо")
		s.cleanup()

func _test_hints() -> void:
	var h := WorldHints.new()
	h.world = w
	h.active = false
	scene.add_child(h)
	# 27: гуано → селитра
	check(Items.get_item(&"guano") != null, "предмет «гуано» есть")
	check((Items.recipes as Dictionary).has(&"r_saltpeter_guano"), "рецепт селитры из гуано есть")
	var g := h.add_guano(Vector3(5, 1.5, 3))
	var who := Node3D.new()
	var inv := Inventory.new()
	inv.name = "Inventory"
	who.add_child(inv)
	scene.add_child(who)
	g.interact(who)
	check(inv.count(&"guano") == 2, "соскребли гуано: %d" % inv.count(&"guano"))
	g.interact(who)
	g.interact(who)
	g.interact(who)
	check(inv.count(&"guano") == 6 and g.left == 0, "залежь кончается после 3 раз")
	# 33: луна → прилив
	check(is_equal_approx(WorldHints.moon_tide_factor(1.0), 1.0) and is_equal_approx(WorldHints.moon_tide_factor(0.0), 1.0), "полнолуние/новолуние — полный (сизигийный) прилив")
	check(is_equal_approx(WorldHints.moon_tide_factor(0.5), 0.7), "половина луны — слабый (квадратурный) прилив")
	# 28: падальщики и мухи над тушей
	var body := Animal.create(&"boar", Vector3(2, 1.8, 0), null)
	scene.add_child(body)
	body.cfg = (Animal.SPECIES[&"boar"] as Dictionary).duplicate(true)
	body.cfg["drops"] = []
	body.die(null)
	var rec := h.add_carrion(body)
	check((rec.birds as Array).size() >= 3, "падальщики над тушей: %d" % (rec.birds as Array).size())
	check(is_instance_valid(rec.flies), "мухи над тушей")
	for i in 40:
		h._physics_process(0.1)
	var top := 0.0
	for b: Animal in rec.birds:
		top = maxf(top, b.global_position.y)
	check(top > 15.0, "падальщики кружат высоко — видно издалека (%.0f м)" % top)
	body.queue_free()
	await wait_frames(2)
	h._scan_corpses(Vector3.ZERO)
	var gone := true
	for k in h.carrion.keys():
		if (h.carrion[k] as Dictionary).corpse == null or not is_instance_valid((h.carrion[k] as Dictionary).corpse):
			gone = false
	check(gone, "тушка пропала — падальщики улетели")
	# мухи и муравьи над едой на земле
	var food: Array[Dictionary] = [{"id": &"meat_raw", "n": 1}]
	var pk := ItemPickup.spawn(scene, Vector3(4, 1.6, 2), food)
	h._scan_food(Vector3.ZERO)
	h.pickup_seen[pk.get_instance_id()] = -100.0
	h._scan_food(Vector3.ZERO)
	check(h.flies.has(pk.get_instance_id()), "над брошенным мясом — мухи")
	check(h.ants.has(pk.get_instance_id()), "к брошенной еде — муравьиная дорожка")
	pk.queue_free()
	await wait_frames(2)
	h._scan_food(Vector3.ZERO)
	check(h.flies.is_empty() and h.ants.is_empty(), "еду подобрали — мухи и муравьи пропали")
	# 33: полоса выброса после шторма
	var n := h.spawn_wrack(Vector3(7, 1.3, 0), 30.0)
	check(n > 20, "полоса выброса водорослей у линии высокой воды: %d точек" % n)
	w.storm = 0.9
	h._watch_storm()
	w.storm = 0.0
	var before := int(h.stats.wrack)
	h._watch_storm()
	check(int(h.stats.wrack) > before, "шторм прошёл — на берег выбросило водоросли")
	# 33: перья
	var fe := h.feathers(Vector3(3, 1.7, 1), &"gull")
	check(fe != null and fe.get_child_count() >= 2, "перья после гибели птицы")
	# 33: следы черепахи к гнезду
	var nest := TurtleNest.new()
	scene.add_child(nest)
	nest.global_position = Vector3(10, 1.0, 5)
	var tr := h.turtle_tracks(nest)
	check(tr != null and tr.multimesh.instance_count > 20, "следы черепахи от воды к гнезду: %d отпечатков" % (tr.multimesh.instance_count if tr else 0))
	# 29: дым костра отгоняет комаров
	var fire := Node3D.new()
	fire.add_to_group(&"campfire")
	scene.add_child(fire)
	fire.global_position = Vector3(1, 0, 1)
	check(h._smoke_near(Vector3(3, 0, 2)), "рядом костёр — дым")
	check(not h._smoke_near(Vector3(30, 0, 2)), "далеко от костра — дыма нет")
	# 33: зелёная полоса у источника
	var seep := h.seep(Vector3(-5, 2.5, 0))
	check(seep != null and seep.get_child_count() >= 1, "у источника — сочная зелёная полоса")
