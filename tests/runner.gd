extends Node
## Запуск теста: godot ... res://tests/runner.tscn -- --test=res://tests/test_x.gd
## Код выхода: 0 — успех, 1 — проваленные проверки, 2 — таймаут/ошибка загрузки.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var test_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			test_path = a.substr(7)
	if test_path == "":
		push_error("runner: не указан --test=")
		get_tree().quit(2)
		return
	var scr := load(test_path) as Script
	if scr == null:
		push_error("runner: не удалось загрузить " + test_path)
		get_tree().quit(2)
		return
	var test := scr.new() as TestCase
	test.test_name = test_path.get_file().get_basename()
	if test.scene_path != "":
		test.scene = (load(test.scene_path) as PackedScene).instantiate()
		get_tree().root.add_child.call_deferred(test.scene)
	add_child(test)
	_guard(test.timeout_sec)
	await get_tree().process_frame
	await get_tree().process_frame
	await test.run()
	var code := 0 if test.failures.is_empty() else 1
	print("[test] DONE ", test.test_name, " failures=", test.failures.size())
	get_tree().quit(code)

func _guard(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout
	push_error("runner: таймаут теста")
	get_tree().quit(2)
