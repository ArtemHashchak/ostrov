## test-timeout: 600
extends TestCase
## v5.2 (агент O), мелочи 23.11: чайки дерутся за рыбу на берегу (кружат 2–5 с, хватает одна,
## остальные гонятся); водоросли в приливной полосе сохнут на отливе и намокают в прилив.
## Раки-отшельники ползают (проверка здесь); черепахи всплывают дышать — SeaCritter._reflex (turtle_*: вдох каждые 30–90 с, клип breathe).

var p: Player
var fauna: Fauna

func _init() -> void:
	timeout_sec = 580.0

func run() -> void:
	await wait(1.0)
	p = get_tree().get_first_node_in_group(&"player") as Player
	check(p != null, "игрок есть")
	fauna = (load("res://scenes/fauna/fauna.tscn") as PackedScene).instantiate() as Fauna
	fauna.set(&"auto_populate", false)
	scene.add_child(fauna)
	await wait(1.0)
	var base := p.global_position
	# ---------- чайки и рыба ----------
	var gulls := fauna.spawn_flock(&"gull", base + Vector3(-20, 0, 20), 3, 10.0)
	var fish := ItemPickup.spawn(scene, base + Vector3(-16, 0.3, 18), [{"id": &"fish_raw", "n": 1}])
	await wait(0.3)
	check(fauna.ext.call(&"_is_fish_pickup", fish), "рыба на земле распознана")
	for g in gulls:
		g.set_meta(&"dive", {"target": fish, "phase": &"in", "t": 0.0, "squabble": true})
	var t := 0.0
	var thief: Animal = null
	var circled := 0.0
	while t < 20.0 and thief == null:
		for g in gulls:
			if g.has_meta(&"dive"):
				g.tick(0.05)
		t += 0.05
		if is_instance_valid(fish) and fish.has_meta(&"sq_until"):
			circled += 0.05
		for g in gulls:
			if g.stolen.size() > 0:
				thief = g
		if int(t * 20) % 10 == 0:
			await get_tree().process_frame
	check(thief != null, "одна чайка унесла рыбу (за %.1f с)" % t)
	check(circled >= 1.5, "до этого чайки дрались над рыбой %.1f с" % circled)
	var chasers := 0
	for g in gulls:
		if g != thief and g.has_meta(&"dive") and (g.get_meta(&"dive") as Dictionary).get("chase") == thief:
			chasers += 1
	check(chasers >= 1, "остальные гонятся за воровкой: %d" % chasers)
	# ---------- раки-отшельники ползают (раковина движется), вдали от игрока ----------
	var hp := base + Vector3(30, 0, -30)
	var hermits: Array[Animal] = []
	for k in 3:
		var h := fauna.spawn(&"hermit_crab", hp + Vector3(k * 1.5, 0, 0), 6.0)
		if h:
			hermits.append(h)
	check(hermits.size() == 3, "раки-отшельники появились: %d" % hermits.size())
	var start: Array[Vector3] = []
	for h in hermits:
		start.append(h.global_position)
	await wait(40.0)
	var moved := 0
	for i in hermits.size():
		if is_instance_valid(hermits[i]) and Vector2(hermits[i].global_position.x - start[i].x, hermits[i].global_position.z - start[i].z).length() > 0.3:
			moved += 1
	check(moved >= 1, "раковины ползают сами (сдвинулись %d из %d)" % [moved, hermits.size()])
	# ---------- водоросли сохнут ----------
	var fw := FakeWorld.new()
	scene.add_child(fw)
	var sw := ShoreSeaweed.new()
	sw.world = fw
	scene.add_child(sw)
	sw.set_process(false)
	fw.wl = 0.8   # прилив — всё под водой
	var c: Dictionary = sw.gen_chunk_for_test(Vector2i(0, 0))
	var n := (c.pos as PackedVector3Array).size()
	check(n > 0, "в приливной полосе есть пучки: %d" % n)
	fw.wl = -0.8  # отлив
	for i in 400:
		sw._update(c, fw.wl, 0.5)   # 200 с на воздухе
	var dry_avg := 0.0
	for d in (c.dry as PackedFloat32Array):
		dry_avg += d
	dry_avg /= maxf(n, 1)
	check(dry_avg > 0.9, "на отливе высохли (сухость %.2f)" % dry_avg)
	fw.wl = 0.8
	for i in 20:
		sw._update(c, fw.wl, 0.5)
	var wet_avg := 0.0
	for d in (c.dry as PackedFloat32Array):
		wet_avg += d
	wet_avg /= maxf(n, 1)
	check(wet_avg < 0.1, "в прилив снова мокрые (сухость %.2f)" % wet_avg)

class FakeWorld extends Node:
	var tide_amplitude := 0.8
	var wl := 0.0
	func height_at(x: float, z: float) -> float:
		return 1.0 - x * 0.04   # пологий пляж вдоль X: от +1 до -0.9 м на 48 м
	func water_level() -> float:
		return wl
	func zone_at(_x: float, _z: float) -> StringName:
		return &"beach"
