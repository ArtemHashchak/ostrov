extends TestCase
## Бот и посылка спонсоров: ящик падает на домашний остров бота — бот бежит к нему,
## вскрывает (OPEN_TIME) и забирает лут в инвентарь.

var bots: Bots
var bot: Bot

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

func wait_until(cond: Callable, max_sec: float, step: float = 0.25) -> bool:
	var t := 0.0
	while t < max_sec:
		if cond.call():
			return true
		await wait(step)
		t += step
	return bool(cond.call())

func run() -> void:
	check(await _match_ready(), "матч загрузился")
	bots = Bots.instance()
	var sup := Supply.instance()
	check(bots != null and sup != null, "модули ботов и посылок подключены")
	if bots == null or sup == null:
		return
	await wait(1.0)
	bot = bots.spawn_bot(1, &"hard")
	check(bot != null and bot.is_inside_tree(), "бот создан")
	if bot == null:
		return
	var player := scene.get(&"player") as Node3D
	if player:
		player.set_physics_process(false)
		player.global_position = Vector3(0, -500, 0)   # подальше — ящик достаётся боту
	await wait(1.0)
	# точка на суше в ~25 м от бота, на его острове
	var bp := bot.global_position
	var target := Vector3.INF
	for k in 24:
		var a := TAU * k / 24.0
		for r: float in [25.0, 18.0, 12.0, 32.0]:
			var q := bp + Vector3(cos(a), 0, sin(a)) * r
			var h := BuildEnv.height_at(q.x, q.z)
			if h > BuildEnv.water_level() + 0.6 and bot.nav.island_id(Vector3(q.x, h, q.z)) == bot.nav.island_id(bp):
				target = Vector3(q.x, h, q.z)
				break
		if target != Vector3.INF:
			break
	check(target != Vector3.INF, "место для ящика рядом с ботом")
	if target == Vector3.INF:
		return
	var c := sup.drop_now(target, 1, false) as SupplyCrate
	check(c != null, "ящик сброшен")
	if c == null:
		return
	var inv0 := {}
	for s in c.loot:
		inv0[StringName(s.id)] = bot.inv_count(StringName(s.id))
	print("[bots_supply] ящик в %s, бот в %s, лут %s" % [str(target.snapped(Vector3.ONE)), str(bp.snapped(Vector3.ONE)), str(c.loot)])
	check(await wait_until(func() -> bool: return c.state != SupplyCrate.State.FALLING, 90.0), "ящик приземлился")
	Engine.time_scale = 3.0
	var seen_open := false
	var t := 0.0
	while t < 240.0 and c.state != SupplyCrate.State.OPENED:
		await wait(1.0)
		t += 1.0
		if c.opener == bot:
			seen_open = true
		if int(t) % 10 == 0:
			print("[bots_supply] t=%d %s | %s | до ящика %.1f м" % [int(t), bot.brain.status, bot.brain.debug(),
				bot.global_position.distance_to(c.global_position)])
	Engine.time_scale = 1.0
	check(seen_open or c.state == SupplyCrate.State.OPENED, "бот начал вскрывать ящик")
	check(c.state == SupplyCrate.State.OPENED and c.opened_by == bot, "ящик вскрыт ботом")
	var got := 0
	for id: StringName in inv0:
		if bot.inv_count(id) > int(inv0[id]):
			got += 1
	await wait(1.0)
	if got == 0:
		for id: StringName in inv0:
			if bot.inv_count(id) > int(inv0[id]):
				got += 1
	check(got > 0, "лут посылки у бота в инвентаре (%d из %d видов)" % [got, inv0.size()])
