extends TestCase
## Лор шоу: записки прошлых сезонов — бутылки у остовов кораблей (SeasonNotes в SUPPLY).
## Игрок подходит, E — читает записку (панель с текстом, счёт), Esc — закрывает.
## Плюс декор шоу (ShowProps): мачты-громкоговорители на Вулкане/общих островах, камеры у берегов.

var p: Player

func _init() -> void:
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 1200.0
	Game.pending_config = {"bots_enemy": 0, "bots_ally": 0, "minutes": 0}

func _match_ready() -> bool:
	for i in 900:
		if scene and scene.is_inside_tree() and not (scene.get(&"loaded_modules") as Array).is_empty() and Game.is_playing():
			return true
		await wait(0.5)
	return false

func look(at: Vector3) -> void:
	var d := at - p.get_eye_position()
	p.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))

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
	check(await _match_ready(), "матч загрузился")
	await wait(1.0)
	var sn := SeasonNotes.instance()
	check(sn != null, "модуль записок есть (SUPPLY)")
	if sn == null:
		return
	var w := get_tree().get_first_node_in_group(&"world")
	var nw := (w.call(&"wrecks") as Array).size() if w else 0
	print("[notes] остовов %d, записок %d" % [nw, sn.notes.size()])
	check(sn.notes.size() >= mini(nw, 4) and sn.notes.size() > 0, "записки разложены у остовов (%d при %d остовах)" % [sn.notes.size(), nw])
	var dry := true
	for n in sn.notes:
		dry = dry and n.global_position.y > BuildEnv.water_level() + 0.3
	check(dry, "все бутылки на суше")
	p = get_tree().get_first_node_in_group(&"player") as Player
	var note := sn.notes[0]
	var np := note.global_position
	# встаём в 1.6 м от бутылки, на суше
	var stand := Vector3.INF
	for k in 12:
		var a := TAU * k / 12.0
		var q := np + Vector3(cos(a), 0, sin(a)) * 1.6
		var h := BuildEnv.height_at(q.x, q.z)
		if h > BuildEnv.water_level() + 0.2:
			stand = Vector3(q.x, h + 0.1, q.z)
			break
	check(stand != Vector3.INF, "есть где встать у записки")
	if stand == Vector3.INF:
		return
	p.global_position = stand
	p.velocity = Vector3.ZERO
	await wait(0.6)
	look(np + Vector3.UP * 0.06)
	await wait(0.4)
	await shot("01_bottle")
	await key(&"interact")
	await wait(0.3)
	check(note.read and sn.is_open(), "записка прочитана, текст на экране")
	await shot("02_note")
	check(sn.read_count() == 1, "счёт записок: 1")
	await key(&"pause")
	await wait(0.3)
	check(not sn.is_open(), "Esc закрывает записку")
	if get_tree().paused:
		get_tree().paused = false
	# декор шоу
	var sp := ShowProps.instance()
	check(sp != null, "декор шоу есть (SUPPLY)")
	if sp == null:
		return
	print("[notes] мачт %d, камер %d" % [sp.masts.size(), sp.cams.size()])
	check(sp.masts.size() >= 4, "мачты-громкоговорители расставлены (%d)" % sp.masts.size())
	check(sp.cams.size() >= 20, "камеры у берегов (%d)" % sp.cams.size())
	var m := sp.masts[0]
	var mp := m.global_position
	var st := Vector3.INF
	for k in 16:
		var a := TAU * k / 16.0
		var q := mp + Vector3(cos(a), 0, sin(a)) * 11.0
		var h := BuildEnv.height_at(q.x, q.z)
		if h > BuildEnv.water_level() + 0.3:
			st = Vector3(q.x, h + 0.1, q.z)
			break
	if st != Vector3.INF:
		p.global_position = st
		p.velocity = Vector3.ZERO
		await wait(0.8)
		look(mp + Vector3.UP * 5.0)
		await wait(0.5)
		await shot("03_mast")
	var c := sp.cams[0]
	var cp := c.global_position
	var cam := Camera3D.new()
	scene.add_child(cam)
	var fwd := -c.global_transform.basis.z
	cam.global_position = cp + fwd * 3.0 + Vector3.UP * 1.9
	cam.look_at(cp + Vector3.UP * 1.6)
	cam.make_current()
	await wait(0.4)
	await shot("04_cam")
	cam.queue_free()
