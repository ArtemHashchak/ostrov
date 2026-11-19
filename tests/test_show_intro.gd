extends TestCase
## Кат-сцена «В эфире» (ShowIntro, SUPPLY): в начале матча камера-дрон облетает архипелаг
## и снижается к игроку (~9 с), плашки команд; игрок заморожен, после — снова управляет.
## Пропуск Пробелом.

var p: Player

func _init() -> void:
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 1200.0
	Game.pending_config = {"bots_enemy": 0, "bots_ally": 0, "minutes": 0, "intro": true}

func key(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await wait(0.15)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await wait(0.2)

func run() -> void:
	var si: ShowIntro = null
	for i in 900:
		si = ShowIntro.instance()
		if si and si.playing:
			break
		await wait(0.25)
	check(si != null and si.playing, "кат-сцена началась вместе с матчем")
	if si == null or not si.playing:
		return
	p = get_tree().get_first_node_in_group(&"player") as Player
	var cam := get_viewport().get_camera_3d()
	check(cam != null and cam.name == &"IntroCam", "камера кат-сцены активна")
	check(not p.is_physics_processing(), "игрок заморожен на время кат-сцены")
	var hud_shown := false
	for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if c is MatchHUD and (c as CanvasLayer).visible:
			hud_shown = true
	check(not hud_shown, "HUD спрятан на время кат-сцены")
	var h0 := cam.global_position.y
	await wait(1.2)
	await shot("01_start")
	await wait(2.5)
	await shot("02_orbit")
	await wait(2.8)
	await shot("03_descent")
	var t := 0.0
	while si.playing and t < 8.0:
		await wait(0.25)
		t += 0.25
	check(not si.playing, "кат-сцена закончилась сама")
	check(get_viewport().get_camera_3d() == p.camera, "вернулась камера игрока")
	check(p.is_physics_processing(), "игрок снова управляется")
	var hud_back := false
	for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if c is MatchHUD and (c as CanvasLayer).visible:
			hud_back = true
	check(hud_back, "HUD вернулся")
	check(h0 > 60.0, "пролёт начинался высоко (%.0f м)" % h0)
	await wait(0.3)
	await shot("04_after")
	# пропуск
	si.play()
	await wait(1.0)
	check(si.playing, "повтор кат-сцены")
	await key(&"jump")
	await wait(0.2)
	check(not si.playing and get_viewport().get_camera_3d() == p.camera, "Пробел пропускает кат-сцену")
