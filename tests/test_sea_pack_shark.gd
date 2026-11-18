extends TestCase
## Живая акула из пака пользователя в море: скелет с анимациями вблизи (swim, bite,
## hurt, die), VAT-меш вдали, процедурная модель как запасной вариант (SharkModel.use_pack).

func _init() -> void:
	scene_path = "res://scenes/world/world_view.tscn"
	timeout_sec = 2400.0

func run() -> void:
	await wait(1.0)
	var w := get_tree().get_first_node_in_group(&"world") as World
	check(w != null and w.is_ready, "мир готов")
	if w == null:
		return
	w.set_time_of_day(12.0)
	w.set_weather(&"clear", true)
	w.set_time_paused(true)
	check(SharkModel.pack_available(), "модель пака есть")
	var sea := Sea.new()
	sea.auto_populate = false
	sea.life_cells_enabled = false
	scene.add_child(sea)
	sea._find_world()
	# глубокое место
	var I: Dictionary = w.islands()[1]
	var c: Vector2 = I.center
	var p := Vector3(c.x + float(I.radius) + 40.0, 0, c.y)
	for i in 36:
		var a := TAU * i / 36.0
		var q := c + Vector2(cos(a), sin(a)) * (float(I.radius) + 40.0)
		if sea.depth_at(q.x, q.y) > 8.0:
			p = Vector3(q.x, 0, q.y)
			break
	var wy := sea.water_y()
	var sh := sea.spawn_shark(&"white", Vector2(p.x, p.z), 6.0, 3) as Shark
	check(sh != null and sh.uses_pack_model(), "белая акула на модели пака")
	sh.global_position = Vector3(p.x, wy - 3.0, p.z)
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	cam.global_position = sh.global_position + Vector3(-7, 0.5, 2)
	cam.look_at(sh.global_position)
	await wait(1.5)
	cam.global_position = sh.global_position + Vector3(-7, 0.5, 2)
	cam.look_at(sh.global_position)
	await wait(0.2)
	var ap: AnimationPlayer = sh._ap
	check(ap != null and sh.current_clip().begins_with("swim") or sh.current_clip().begins_with("turn"), "плывёт: %s" % sh.current_clip())
	check(not sh._far and (sh._model.get_node(^"Skel") as Node3D).visible, "вблизи — скелет")
	await shot("near")
	# боль
	sh.apply_damage(5.0, null, &"melee")
	await get_tree().process_frame
	print("[test] после удара: %s" % sh.current_clip())
	# вдали — VAT
	cam.global_position = sh.global_position + Vector3(-60, 2.0, 10)
	cam.look_at(sh.global_position)
	await wait(0.6)
	check(sh._far and (sh._model.get_node(^"Far") as Node3D).visible and not sh.anim_active(), "вдали — VAT без скелета")
	await shot("far")
	# смерть
	cam.global_position = sh.global_position + Vector3(-7, 0.5, 2)
	await wait(0.3)
	sh.apply_damage(5000.0, null, &"explosion")
	await wait(0.2)
	check(sh.is_dead() and sh.current_clip().ends_with("die"), "гибель: %s" % sh.current_clip())
	await wait(1.5)
	cam.look_at(sh.global_position)
	await shot("dead")
	# запасной вариант
	SharkModel.use_pack = false
	var sh2 := sea.spawn_shark(&"tiger", Vector2(p.x, p.z), 6.0, 4) as Shark
	check(sh2 != null and not sh2.uses_pack_model() and sh2._mat != null, "запасная процедурная модель")
	SharkModel.use_pack = true
