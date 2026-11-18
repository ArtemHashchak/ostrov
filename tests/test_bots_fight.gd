extends TestCase
## Бой ботов: защитник (Красные-боты, команда 1) у своего флага и налётчик (команда 2)
## с топором и динамитом. Они дерутся (урон, смерть, возрождение у флага), налётчик
## ломает флаг команды 1; после этого павший защитник больше не возрождается.
## Время ускорено (Engine.time_scale).

var bots: Bots
var cam: Camera3D
var damaged_by_bot := 0
var deaths: Array[Node] = []
var spawns := 0
var deaths_with_flag := 0   # смерти, когда флаг команды павшего ещё стоял

func _init() -> void:
	scene_path = "res://scenes/world/match.tscn"
	timeout_sec = 1480.0
	Game.pending_config = {"bots_enemy": 0, "bots_ally": 0, "minutes": 0}

func _match_ready() -> bool:
	for i in 900:
		if scene and scene.is_inside_tree() and not (scene.get(&"loaded_modules") as Array).is_empty() and Game.is_playing():
			return true
		await wait(0.5)
	return false

func run() -> void:
	check(await _match_ready(), "матч загрузился")
	_render(false)
	bots = Bots.instance()
	if bots == null:
		check(false, "нет модуля ботов")
		return
	var player := scene.get(&"player") as Node3D
	if player:
		player.set_physics_process(false)
	await wait(1.0)
	Events.character_damaged.connect(func(ch: Node, _a: float, src: Node) -> void:
		if ch is Bot and Game.character_of(src) is Bot:
			damaged_by_bot += 1)
	Events.character_died.connect(func(ch: Node, _k: Node) -> void:
		deaths.append(ch)
		var tm: Variant = ch.get(&"team")
		if ch is Bot and tm != null and Game.can_respawn(int(tm)):
			deaths_with_flag += 1)
	Events.character_spawned.connect(func(ch: Node) -> void:
		if ch is Bot:
			spawns += 1)
	var nav := bots.ensure_nav()
	var defender := bots.spawn_bot(1, &"normal")
	var fp := Game.teams[1].flag_pos
	defender.brain.mode = &"build"
	# налётчик — на 18 м от флага защитника, на суше
	var at := fp
	for k in 24:
		var a := TAU * k / 24.0
		var q := fp + Vector3(cos(a), 0, sin(a)) * 18.0
		if nav.land(q.x, q.z):
			at = nav.ground(q)
			break
	var raider := bots.spawn_bot(2, &"hard", at)
	raider.inventory.add(&"axe_modern", 1)
	raider.inventory.add(&"dynamite", 3)
	raider.brain.mode = &"raid"
	raider.brain.raid_team = 1
	Game.teams[1].flag_hp = 200.0
	cam = Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	Engine.time_scale = 2.0
	var t0 := Game.match_time
	var shot_fight := false
	var spawns0 := spawns
	while Game.match_time - t0 < 900.0:
		await wait(1.0)
		_look(raider if raider.alive else defender)
		if not shot_fight and raider.global_position.distance_to(defender.global_position) < 4.0 and raider.alive and defender.alive:
			shot_fight = true
			await snap("fight")
		if int(Game.match_time - t0) % 15 == 0:
			print("[bots] t=%d flag1=%d def[%s hp=%d] raid[%s hp=%d] dmg=%d deaths=%d" % [int(Game.match_time - t0), int(Game.teams[1].flag_hp),
				defender.brain.status, int(defender.health), raider.brain.status, int(raider.health), damaged_by_bot, deaths.size()])
		if not Game.teams[1].flag_alive and (deaths.has(defender) or Game.match_time - t0 > 600.0):
			break
	Engine.time_scale = 1.0
	check(damaged_by_bot > 0, "боты били друг друга (%d попаданий)" % damaged_by_bot)
	check(not deaths.is_empty(), "был убитый (%d)" % deaths.size())
	if deaths_with_flag > 0:
		check(spawns > spawns0, "павший бот возрождался у флага")
	else:
		print("[bots] все смерти — после потери флага, возрождение не ожидается")
	check(not Game.teams[1].flag_alive, "налётчик уничтожил флаг команды 1")
	await snap("after")
	# защитник: убить — флага нет, возрождения нет
	if defender.alive:
		defender.apply_damage(500.0, raider, &"melee")
	Engine.time_scale = 2.0
	await wait(Game.RESPAWN_TIME + 2.0)
	Engine.time_scale = 1.0
	check(not defender.alive and defender.eliminated, "без флага защитник выбыл")

func _look(b: Node3D) -> void:
	var p := b.global_position
	cam.global_position = p + Vector3(5.0, 4.0, 5.0)
	cam.look_at(p + Vector3.UP)

## Под llvmpipe кадр мира очень дорогой: 3D рисуем только для скриншотов.
func _render(on: bool) -> void:
	get_viewport().disable_3d = not on

func snap(n: String) -> void:
	_render(true)
	await wait_frames(3)
	await shot(n)
	_render(false)
