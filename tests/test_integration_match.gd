extends TestCase
## Интеграция: настоящий матч в match.tscn с конфигом по умолчанию (4 команды,
## боты-соперники), все модули подключены (включая COMBAT), игроку выдан
## контроллер оружия, боты сами живут ~20 игровых минут (ускорено): добывают,
## строят, никто не падает с ошибками. В конце — ускоренная развязка: флаги
## соперников сломаны, их боты выбывают, матч заканчивается победой игрока.

var _ended := -99
var _errors_before := 0

func _init() -> void:
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 3500.0
	Game.pending_config = {"mode": "ffa", "minutes": 180, "bots_enemy": 1, "bots_ally": 0, "auto_flags": true}

func _match_ready() -> bool:
	for i in 1800:
		if scene and scene.is_inside_tree() and not (scene.get(&"loaded_modules") as Array).is_empty() \
				and Game.is_playing() and get_tree().get_first_node_in_group(&"player") != null:
			return true
		await wait(0.5)
	return false

func _render(on: bool) -> void:
	get_viewport().disable_3d = not on

func snap(n: String) -> void:
	_render(true)
	await wait_frames(3)
	await shot(n)
	_render(false)

func run() -> void:
	Events.match_ended.connect(func(w: int) -> void: _ended = w)
	Engine.max_physics_steps_per_frame = 30
	check(await _match_ready(), "матч загрузился")
	await wait(2.0)
	var mods: Array = scene.get(&"loaded_modules")
	print("[integ] модули: ", mods)
	for m in ["flora", "build", "sea", "fauna", "survival", "combat", "bots", "ui"]:
		var found := false
		for p: String in mods:
			if p.contains("/%s" % m):
				found = true
		check(found, "модуль %s подключён" % m)
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	check(p.get_node_or_null(^"CombatController") != null, "у игрока контроллер оружия")
	await snap("01_start")
	var bots := Bots.instance()
	check(bots != null and bots.bots.size() == 3, "3 бота-соперника (%d)" % (bots.bots.size() if bots else -1))
	p.set_physics_process(false) # игрок стоит у своего флага
	var bm := BuildModule.instance()
	var built0 := get_tree().get_nodes_in_group(&"buildable").size()
	Engine.time_scale = 3.0
	var t0 := Game.match_time
	var next_log := 0.0
	while Game.match_time - t0 < 1200.0:
		await wait(2.0)
		var dt := Game.match_time - t0
		if dt >= next_log:
			next_log += 120.0
			var st: Array[String] = []
			for b in bots.bots:
				st.append("%d:%s hp=%d" % [b.team, b.brain.status, int(b.health)])
			print("[integ] t=%d fps=%d %s" % [int(dt), Engine.get_frames_per_second(), ", ".join(st)])
	Engine.time_scale = 1.0
	await snap("02_after_20min")
	var alive := 0
	for b in bots.bots:
		if is_instance_valid(b) and (b.alive or not b.eliminated):
			alive += 1
	check(alive == 3, "все боты в игре (%d)" % alive)
	var built1 := get_tree().get_nodes_in_group(&"buildable").size()
	var logs := 0
	for k: Variant in Game.stats:
		logs += int((Game.stats[k] as Dictionary).get("logs", 0))
	print("[integ] построек %d → %d, брёвен перенесено %d" % [built0, built1, logs])
	check(built1 > built0 or logs > 0, "боты добывают/строят")
	for t in 4:
		check(Game.teams[t].flag_alive, "флаг команды %d цел" % t)
	# Развязка: ломаем флаги соперников, добиваем ботов → победа игрока.
	for t in [1, 2, 3]:
		Game.damage_flag(t, 99999.0, p)
	await wait(0.5)
	for b in bots.bots:
		if is_instance_valid(b) and b.alive:
			b.apply_damage(9999.0, p, &"melee")
	Engine.time_scale = 3.0
	var t2 := Time.get_ticks_msec()
	while _ended == -99 and Time.get_ticks_msec() - t2 < 120000:
		await wait(1.0)
	Engine.time_scale = 1.0
	check(_ended == 0, "матч окончен победой игрока (%d)" % _ended)
	await snap("03_end")
	check(bm != null, "модуль стройки")
