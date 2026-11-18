extends TestCase
## Бот на домашнем острове: ставит план базы, рубит деревья, пилит ствол на брёвна,
## носит их на плече и укладывает в стену у флага.

var bots: Bots
var bot: Bot
var cam: Camera3D

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
	check(bots != null, "модуль ботов подключён к матчу")
	if bots == null:
		return
	await wait(1.0)
	check(bots.bots.is_empty(), "с bots_enemy=0 ботов нет")
	Bots.speed = 1.5
	bot = bots.spawn_bot(1, &"hard")
	check(bot != null and bot.is_inside_tree(), "бот создан")
	check(bot.is_in_group(&"characters") and bot.is_in_group(&"bots"), "бот в группах characters/bots")
	check(Game.teams[1].flag_placed, "флаг команды бота стоит")
	check(Game.teams[1].members.has(bot), "бот зарегистрирован в команде")
	cam = Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	var player := scene.get(&"player") as Node3D
	if player:
		player.set_physics_process(false)
	get_tree().root.content_scale_factor = 1.0
	get_tree().root.size = Vector2i(640, 360)
	Engine.time_scale = 4.0
	var t0 := Game.match_time
	var shot_i := 0
	var next_log := 0.0
	while Game.match_time - t0 < 900.0:
		await wait(2.0)
		_follow()
		if Game.match_time - t0 >= next_log:
			next_log += 10.0
			print("[bots] t=%d %s | %s | logs=%d felled=%d delivered=%d carry=%d hp=%d" % [int(Game.match_time - t0), bot.brain.status,
				bot.brain.debug(), int(bot.brain.stats.logs), int(bot.brain.stats.felled), int(bot.brain.stats.delivered), bot.logs_carried, int(bot.health)])
		if shot_i == 0 and String(bot.brain.task.get("phase", "")) == "chop":
			shot_i = 1
			await snap("chop")
		if shot_i == 1 and bot.logs_carried > 0:
			shot_i = 2
			await snap("carry")
		if int(bot.brain.stats.delivered) >= 4:
			break
	Engine.time_scale = 1.0
	var bm := BuildModule.instance()
	var bps := bm.blueprints(1)
	check(not bps.is_empty(), "бот поставил чертёж базы (%d)" % bps.size())
	var logs_in := 0
	for b in bps:
		logs_in += b.filled_count(&"log")
	check(int(bot.brain.stats.felled) >= 1, "бот срубил дерево")
	check(int(bot.brain.stats.logs) >= 2, "бот поднял брёвна (%d)" % int(bot.brain.stats.logs))
	check(logs_in >= 4, "в постройке бота есть брёвна (%d)" % logs_in)
	_follow()
	await wait(0.5)
	await snap("base")
	check(bot.alive, "бот жив")

func _follow() -> void:
	if bot == null:
		return
	var p := bot.global_position
	var back := bot.global_basis.z * 5.0 + Vector3(2.0, 2.6, 0.0)
	cam.global_position = p + back
	cam.look_at(p + Vector3.UP * 1.0)

## Под llvmpipe кадр мира очень дорогой: 3D рисуем только для скриншотов.
func _render(on: bool) -> void:
	get_viewport().disable_3d = not on

func snap(n: String) -> void:
	_render(true)
	await wait_frames(3)
	await shot(n)
	_render(false)
