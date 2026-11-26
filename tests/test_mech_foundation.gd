## test-timeout: 600
extends TestCase
## Фундамент механик V5: таблицы вне кода (DataTables), материалы и свойства предметов
## (Materials), поверхности под ногами (Surfaces), шина событий шоу (ShowBus), восприятие
## (Perception: первый выстрел на участке пугает стаю птиц на сотни метров, повторный — нет;
## громкие шаги пугают краба; кровь в воде).

var p: Player
var fauna: Fauna

func _init() -> void:
	timeout_sec = 600.0

func run() -> void:
	await wait(1.0)
	p = get_tree().get_first_node_in_group(&"player") as Player
	check(p != null, "игрок есть")
	# ---- таблицы и материалы ----
	check(DataTables.f("balance", "perception/shot_radius") > 300.0, "balance.json читается (shot_radius %.0f)" % DataTables.f("balance", "perception/shot_radius"))
	var mats: Dictionary = DataTables.get_value("materials", "materials", {})
	check(mats.size() >= 30, "materials.json: %d материалов" % mats.size())
	var schema: Dictionary = DataTables.get_value("materials", "schema", {})
	var all_fields := true
	for k in schema.keys():
		for mk in mats.keys():
			if not (mats[mk] as Dictionary).has(k):
				all_fields = false
	check(schema.size() >= 50 and all_fields, "полная схема: %d полей у каждого материала" % schema.size())
	var shell := Materials.item(&"coconut_shell")
	check(absf(float((shell.get("container", {}) as Dictionary).get("cap_l", 0.0)) - 0.3) < 0.01 and bool(shell.buoyant), "половинка кокоса: ёмкость 0,3 л, плавает")
	check(bool(Materials.prop(&"rifle", "weapon_wear", {}).get("immortal", false)) and not bool(Materials.prop(&"pistol_9mm", "weapon_wear", {}).get("immortal", true)), "АК бессмертен к соли, 9 мм — нет")
	check(Materials.mass(&"coconut_husk", 1.0) > Materials.mass(&"coconut_husk", 0.0) * 1.8, "мокрая шелуха тяжелее")
	check(float(Materials.of(&"leaves_dry").walk_loud) > float(Materials.of(&"sand").walk_loud), "сухие листья громче песка")
	# ---- поверхности ----
	var surf := get_node(^"/root/Surfaces")
	var box := StaticBody3D.new()
	box.set_meta(&"surface", &"wood")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2, 0.2, 2)
	cs.shape = bs
	box.add_child(cs)
	scene.add_child(box)
	box.global_position = p.global_position + Vector3(0, 30, 0)
	await wait_frames(3)
	var on_wood: StringName = surf.call(&"at", box.global_position + Vector3(0, 0.1, 0))
	check(on_wood == &"wood", "на деревянном настиле — wood (%s)" % on_wood)
	var ground: StringName = surf.call(&"at", p.global_position + Vector3(3, 0, 3))
	check(ground != &"", "под игроком поверхность: %s, скорость ×%.2f, громкость %.2f" % [ground, surf.call(&"speed_mul_at", p.global_position), surf.call(&"loud_at", p.global_position)])
	box.queue_free()
	# ---- шина шоу ----
	var bus := get_node(^"/root/ShowBus")
	bus.call(&"reset")
	var got: Array = []
	bus.connect(&"show_event", func(ev: Dictionary) -> void: got.append(ev))
	var pts: float = bus.call(&"emit_event", p, &"kill", [&"knife", &"night"])
	check(absf(pts - 40.0 * 2.0 * 1.3) < 0.01 and got.size() == 1, "убийство ножом ночью: %.0f очков, событие разослано" % pts)
	check(absf(float(bus.call(&"points_of", p)) - pts) < 0.01, "очки начислены игроку")
	# ---- восприятие: птицы ----
	fauna = (load("res://scenes/fauna/fauna.tscn") as PackedScene).instantiate() as Fauna
	fauna.set(&"auto_populate", false)
	scene.add_child(fauna)
	await wait(1.0)
	var c := p.global_position + Vector3(60, 0, 0)
	fauna.spawn_flock(&"gull", c, 5, 20.0)
	var fl: Dictionary = fauna.flocks[fauna.flocks.size() - 1]
	await wait(0.3)
	var pc := get_node(^"/root/Perception")
	var st: Dictionary = pc.call(&"shot", p.global_position, p, 1.0)
	check(bool(st.first) and float(st.radius) >= 400.0, "первый выстрел на участке: радиус %.0f м" % float(st.radius))
	var tgt: Vector3 = fl.target
	var fp: Vector3 = fl.pos
	check(fl.mode == &"fly" and Vector2(tgt.x - fp.x, tgt.z - fp.z).length() > 140.0, "стая чаек улетает на %.0f м" % Vector2(tgt.x - fp.x, tgt.z - fp.z).length())
	var st2: Dictionary = pc.call(&"shot", p.global_position + Vector3(5, 0, 0), p, 1.0)
	check(not bool(st2.first) and float(st2.radius) < 200.0, "повторный выстрел там же: радиус %.0f м" % float(st2.radius))
	# ---- восприятие: краб и громкие шаги ----
	var crab_pos := p.global_position + Vector3(0, 0, 9)
	var crab := fauna.spawn(&"crab", crab_pos, 4.0)
	await wait(0.5)
	if crab:
		var s0: StringName = crab.state
		pc.call(&"step", p, crab.global_position + Vector3(0, 0, -9), 1.0, 2.0)
		check(crab.state in [&"burrow", &"flee"], "громкий бег в 9 м — краб прячется/убегает (%s → %s)" % [s0, crab.state])
		crab.call(&"_set_state", &"idle")
		pc.call(&"step", p, crab.global_position + Vector3(0, 0, -9), 0.15, 0.4)
		check(crab.state == &"idle", "тихий шаг вприсядку — краб не замечает")
	else:
		check(false, "краб создан")
	# ---- кровь в воде ----
	var wl := BuildEnv.water_level()
	var bst: Dictionary = pc.call(&"blood", Vector3(p.global_position.x + 200, wl - 2.0, p.global_position.z), 8.0)
	check(float(bst.radius) > 60.0, "кровь в воде: радиус %.0f м" % float(bst.radius))
