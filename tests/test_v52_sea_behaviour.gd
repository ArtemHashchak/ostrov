## test-timeout: 600
extends TestCase
## v5.2 (агент K): море.
##  19 рифовые рыбы с «домом»-кораллом: при испуге прячутся в свой коралл, а не разлетаются;
##  20 стая (mode 0) расходится «фонтаном» в стороны от курса хищника; коньки в лугах травы;
##  23 выдох дельфина у поверхности (брызги + звук).

func _init() -> void:
	timeout_sec = 580.0

func _school(sp: StringName, at: Vector3, n: int, rng: RandomNumberGenerator) -> ReefSchool:
	var hs := PackedVector3Array()
	for i in n:
		hs.append(at + Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(-0.3, 0.3), rng.randf_range(-1.5, 1.5)))
	var s := ReefSchool.new()
	s.setup(sp, at, hs, rng, at.y - 3.0)
	scene.add_child(s)
	return s

func run() -> void:
	await wait(1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 52
	ReefLife.level = 0.0
	ReefLife.time = 100.0
	var at := Vector3(0, -4.0, 0)
	# ---------- 19: укрытие в коралле ----------
	var s := _school(&"damsel", at, 12, rng)
	var home := at + Vector3(3.0, -0.5, 0.0)
	s.set_shelter(home)
	var threat := at + Vector3(-3.0, 0.0, 0.0)
	var d0 := 0.0
	for i in s.count():
		d0 += s.fish_pos(i, 100.0).distance_to(home)
	s.scare(threat)
	var d1 := 0.0
	var away := 0.0
	for i in s.count():
		var q := s.fish_pos(i, 102.0)
		d1 += q.distance_to(home)
		away += q.distance_to(threat)
	check(d1 < d0 * 0.6, "испуг: рыбы к своему коралл-дому (среднее %.2f → %.2f м)" % [d0 / s.count(), d1 / s.count()])
	var d2 := 0.0
	for i in s.count():
		d2 += s.fish_pos(i, 125.0).distance_to(home)
	check(d2 > d1 * 1.3, "через ~25 с выплывают обратно (%.2f м)" % (d2 / s.count()))
	check(s.is_scared() and s.mat.get_shader_parameter(&"shelter").w > 0.5, "дом передан в шейдер")
	# ---------- 20: фонтан стаи ----------
	ReefLife.time = 200.0
	var sch := _school(&"sardine", Vector3(30, -5, 0), 40, rng)
	var heading := Vector3(0, 0, -1)
	var pred := sch.current_center() + Vector3(0, 0, 3.0)
	var before: Array[Vector3] = []
	for i in sch.count():
		before.append(sch.fish_pos(i, 200.0))
	sch.scare(pred, -1.0, heading)
	var side_sum := 0.0
	var along_sum := 0.0
	for i in sch.count():
		var dv := sch.fish_pos(i, 201.2) - before[i]
		side_sum += absf(dv.x)
		along_sum += absf(dv.z)
	check(side_sum > along_sum * 1.2, "стая расходится в стороны от курса хищника (вбок %.1f, вдоль %.1f)" % [side_sum, along_sum])
	check(sch.mat.get_shader_parameter(&"scare_dir").w > 0.5, "курс хищника передан в шейдер")
	# ---------- коньки ----------
	var sea := get_tree().get_first_node_in_group(&"sea")
	var sp := OceanRoster.species("seahorse")
	check(not sp.is_empty(), "морской конёк есть в составе океана")
	if sea and not sp.is_empty():
		var bed: Node3D = preload("res://scripts/sea/reef_life/seahorse_bed.gd").new()
		scene.add_child(bed)
		var spots: Array[Vector3] = [Vector3(5, -3.0, 40)]
		bed.call(&"setup", sea, spots, 7)
		var cr: Array = bed.get(&"critters")
		check(cr.size() == 2, "в лугу пара коньков (%d)" % cr.size())
		var clinging := true
		for c: SeaCritter in cr:
			clinging = clinging and c.clinging
		check(clinging, "коньки держатся за стебли")
		bed.queue_free()
		# ---------- 23: выдох дельфина ----------
		var dsp := OceanRoster.species("dolphin")
		if not dsp.is_empty():
			var wy: float = sea.call(&"water_y")
			var dol := SeaCritter.make(dsp, sea, Vector3(0, wy - 0.4, 60), 3)
			if dol:
				scene.add_child(dol)
				dol.global_position = Vector3(0, wy - 0.4, 60)
				var cam := get_viewport().get_camera_3d()
				if cam:
					cam.global_position = Vector3(0, wy + 3, 52)
				var n0 := scene.get_child_count()
				dol._blow()
				await wait_frames(2)
				check(dol.blow_count == 1, "дельфин выдохнул")
				var parts := 0
				for c in get_tree().current_scene.get_children() if get_tree().current_scene else scene.get_children():
					if c is CPUParticles3D:
						parts += 1
				check(parts > 0 or scene.get_child_count() > n0, "фонтанчик брызг над водой")
				dol.queue_free()
		else:
			check(false, "дельфин в составе океана")
	else:
		print("[test] моря в сцене нет — коньки/дельфин пропущены")
