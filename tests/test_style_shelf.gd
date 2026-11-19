extends TestCase
## Единый визуальный ряд: калибровка пака (отчёт, диапазоны классов), цветокоррекция StyleGrade,
## «Полка стиля» на полигоне — все модели пака при одном свете, до/после (F7), свет (F8),
## ряд морских видов под водой. Снимки: tests/shots/test_style_shelf_*.png.

var sb: Sandbox

func _init() -> void:
	scene_path = "res://scenes/sandbox/sandbox.tscn"
	timeout_sec = 3500.0

func run() -> void:
	Engine.max_physics_steps_per_frame = 30
	# ---- отчёт калибровки и диапазоны классов
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/style/style_config.json"))
	var rep: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/user_pack/style_report.json"))
	check(rep is Array and (rep as Array).size() >= 8, "отчёт калибровки есть (%d моделей)" % (rep.size() if rep is Array else 0))
	var bad := []
	var n_cal := 0
	if rep is Array:
		for r: Dictionary in rep:
			for m: Dictionary in r.get("materials", []):
				var cls: Dictionary = cfg.classes.get(m.get("class", ""), {})
				if cls.is_empty() or cls.get("keep", false) or not m.has("y_med_after"):
					continue
				n_cal += 1
				var y := float(m.y_med_after)
				var lo := float(cls.y[0]) * 0.85
				var hi := float(cls.y[1]) * 1.15
				if y < lo or y > hi:
					bad.append("%s/%s Y=%.3f" % [r.model, m.material, y])
	check(n_cal >= 8 and bad.is_empty(), "откалиброванные альбедо в диапазонах классов (%d, вне: %s)" % [n_cal, ", ".join(bad)])
	check(DirAccess.dir_exists_absolute("res://assets/user_pack/_style_orig"), "оригиналы сохранены в _style_orig")
	# ---- LUT
	var lut := StyleGrade.lut()
	check(lut != null and lut.get_width() == StyleGrade.SIZE, "LUT цветокоррекции построен (%d³)" % StyleGrade.SIZE)
	var mid := StyleGrade.grade(Color(0.5, 0.5, 0.5))
	var skin := StyleGrade.grade(Color(0.8, 0.55, 0.4))
	check(absf(mid.r - 0.5) < 0.04 and absf(mid.g - 0.5) < 0.04, "LUT мягкий: серый почти не меняется (%.3f %.3f %.3f)" % [mid.r, mid.g, mid.b])
	check(absf(skin.h - Color(0.8, 0.55, 0.4).h) < 0.02, "кожа/песок не уводятся по оттенку")
	# ---- полигон
	sb = scene as Sandbox
	var t0 := Time.get_ticks_msec()
	while not sb.is_built and Time.get_ticks_msec() - t0 < 1500000:
		await wait(0.5)
	check(sb.is_built, "полигон собран за %d с" % int((Time.get_ticks_msec() - t0) / 1000.0))
	if not sb.is_built:
		return
	var shelf := SandboxStyleShelf.instance
	check(shelf != null, "полка стиля построена")
	if shelf == null:
		return
	var na := shelf.after_nodes.filter(func(n): return is_instance_valid(n)).size()
	var nb := shelf.before_nodes.filter(func(n): return is_instance_valid(n)).size()
	check(na >= 10 and nb == na, "на полке %d моделей «после» и %d «до»" % [na, nb])
	check(sb.zones.points.has(&"style") and sb.zones.points.has(&"style_underwater"), "точки «Полка стиля» и «под водой»")
	# ---- снимки: день / пасмурно / закат, после и до
	sb.panel.go(&"style")
	for li in [0, 1, 2]:
		shelf.set_light(li)
		shelf.set_after(true)
		await wait(2.5)
		await shot("%d_%s_after" % [li, ["day", "overcast", "sunset"][li]])
		shelf.set_after(false)
		await wait(1.0)
		await shot("%d_%s_before" % [li, ["day", "overcast", "sunset"][li]])
	shelf.set_after(true)
	await _key(KEY_F7)
	await wait(0.3)
	check(not shelf.showing_after, "F7 — «до»")
	await _key(KEY_F7)
	await wait(0.3)
	check(shelf.showing_after, "F7 ещё раз — «после»")
	await _key(KEY_F8)
	await wait(0.3)
	check(shelf.light_i == 3, "F8 — следующий свет (ночь после заката: %d)" % shelf.light_i)
	shelf.set_light(0)
	# ---- крупно: акула, краб, рыбы
	var c := SandboxZones.ZONES[&"style"].c as Vector2
	sb.cheats.set_fly(true)
	sb.cheats.teleport(Vector3(c.x - 8.0, SandboxProps.ground(c.x - 8.0, c.y + 7.5) + 1.6, c.y + 7.5), Vector3(c.x - 8.0, SandboxProps.ground(c.x - 8.0, c.y + 4.0) + 1.3, c.y + 4.0))
	await wait(2.0)
	await shot("4_close_after")
	shelf.set_after(false)
	await wait(1.0)
	await shot("4_close_before")
	shelf.set_after(true)
	sb.cheats.set_fly(false)
	# ---- под водой
	shelf.set_light(0)
	sb.panel.go(&"style_underwater")
	await wait(3.0)
	await shot("5_underwater_after")
	shelf.set_after(false)
	await wait(1.0)
	await shot("5_underwater_before")
	shelf.set_after(true)
	check(StyleGrade.enabled, "после проверки цветокоррекция включена")

func _key(k: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.keycode = k
	ev.pressed = true
	Input.parse_input_event(ev)
	await wait_frames(2)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await wait_frames(2)
