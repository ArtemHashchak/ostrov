extends Node
## Запуск теста: godot ... res://tests/runner.tscn -- --test=res://tests/test_x.gd
## Несколько тестов в одном процессе (без повторного старта движка):
##   ... -- --tests=res://tests/a.gd,res://tests/b.gd
## Код выхода: 0 — успех, 1 — проваленные проверки, 2 — таймаут/ошибка загрузки.
## OSTROVA_TEST_LOW=1 — облегчённая графика для рендер-тестов (низкий пресет, без теней/тумана).

var _deadline_ms := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var paths: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			paths.append(a.substr(7))
		elif a.begins_with("--tests="):
			for p in a.substr(8).split(",", false):
				paths.append(p.strip_edges())
	if paths.is_empty():
		push_error("runner: не указан --test=")
		get_tree().quit(2)
		return
	if OS.get_environment("OSTROVA_TEST_LOW") == "1":
		_apply_low_graphics()
	_watchdog()
	var worst := 0
	for test_path in paths:
		var code := await _run_one(test_path)
		worst = maxi(worst, code)
	get_tree().quit(worst)

func _run_one(test_path: String) -> int:
	var scr := load(test_path) as Script
	if scr == null:
		push_error("runner: не удалось загрузить " + test_path)
		return 2
	var test := scr.new() as TestCase
	test.test_name = test_path.get_file().get_basename()
	if test.scene_path != "":
		test.scene = (load(test.scene_path) as PackedScene).instantiate()
		get_tree().root.add_child.call_deferred(test.scene)
	add_child(test)
	_deadline_ms = Time.get_ticks_msec() + int(test.timeout_sec * 1000.0)
	await get_tree().process_frame
	await get_tree().process_frame
	await test.run()
	var code := 0 if test.failures.is_empty() else 1
	print("[test] DONE ", test.test_name, " failures=", test.failures.size())
	_deadline_ms = 0
	# Подчистить перед следующим тестом в том же процессе.
	if is_instance_valid(test.scene):
		test.scene.queue_free()
	test.queue_free()
	for n in get_tree().root.get_children():
		if n != self and not _is_autoload(n):
			n.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	# Звуки, ещё играющие к концу теста, остаются в аудиосервере («resources still in
	# use at exit»). В матче их останавливают Flora/Combat при выходе из дерева, а в
	# тестовых сценах без узла Flora (стройка, полигоны) — некому: останавливаем здесь.
	Flora.stop_all_sfx()
	CombatFx.stop_all_sounds()
	# Остановленный звук освобождается не сразу: аудиопоток доигрывает затухание, затем
	# AudioServer.update() на главном потоке удаляет воспроизведение. Без нескольких
	# настоящих кадров с паузой выход успевал раньше — редкий флейк «1 resources still
	# in use at exit» (props-splash.wav в test_sea_model, звуки в test_bots_bridge).
	for i in 8:
		OS.delay_msec(25)
		await get_tree().process_frame
	return code

func _is_autoload(n: Node) -> bool:
	return ProjectSettings.has_setting("autoload/" + n.name)

func _watchdog() -> void:
	while true:
		await get_tree().create_timer(1.0, true, true).timeout
		if _deadline_ms > 0 and Time.get_ticks_msec() > _deadline_ms:
			push_error("runner: таймаут теста")
			get_tree().quit(2)
			return

func _apply_low_graphics() -> void:
	var s := get_node_or_null(^"/root/Settings")
	if s != null and "graphics_quality" in s:
		s.set("graphics_quality", 0)
		if s.has_method("apply_graphics"):
			s.call("apply_graphics")
	var vp := get_viewport()
	vp.positional_shadow_atlas_size = 0
	RenderingServer.directional_shadow_atlas_set_size(512, false)
