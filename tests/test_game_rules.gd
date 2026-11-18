extends TestCase
## Правила матча в Game без мира: конфиг лобби, флаги, выбывание, победа
## последнего, победа по очкам при лимите времени, статистика, bot_slots.

var _elim: Array[int] = []
var _ended := -99

func _init() -> void:
	scene_path = ""
	timeout_sec = 120.0

func _dummy(team: int, nm: String) -> Node3D:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar team := %d\nvar alive := true\nvar display_name := \"%s\"\nvar carrying_log := false\nfunc is_dead() -> bool:\n\treturn not alive\nfunc respawn() -> void:\n\talive = true\n" % [team, nm]
	s.reload()
	var n := Node3D.new()
	n.set_script(s)
	n.add_to_group(&"characters")
	add_child(n)
	return n

func run() -> void:
	Events.team_eliminated.connect(func(t: int) -> void: _elim.append(t))
	Events.match_ended.connect(func(w: int) -> void: _ended = w)
	# --- 2×2 из лобби ---
	Game.pending_config = {"mode": "2x2", "bots_enemy": 2, "bots_ally": 1, "minutes": 0, "difficulty": "hard"}
	Game.start_match({"minutes": 180, "teams": 4})
	check(Game.teams.size() == 2, "2×2 → 2 команды")
	check(not Game.has_time_limit(), "«до последнего флага» — без лимита")
	var slots := Game.bot_slots()
	check(slots.size() == 3, "bot_slots: 1 союзник + 2 соперника (есть %d)" % slots.size())
	check(String(slots[0].difficulty) == "hard", "сложность ботов в слотах")
	# --- FFA, 4 команды ---
	Game.pending_config = {"mode": "ffa", "bots_enemy": 1, "bots_ally": 0, "minutes": 60}
	Game.start_match({"minutes": 180, "teams": 4})
	check(Game.teams.size() == 4 and is_equal_approx(Game.match_length, 3600.0), "FFA: 4 команды, 60 мин")
	var a := _dummy(0, "Игрок")
	var b := _dummy(1, "Бот Б")
	var c := _dummy(2, "Бот В")
	var d := _dummy(3, "Бот Г")
	for n in [a, b, c, d]:
		Game.register_character(n, int(n.get(&"team")))
	for t in 4:
		Game.set_flag_placed(t, Vector3(t * 50.0, 2, 0))
	check(Game.stats.size() == 4, "статистика на 4 персонажей")
	# Свой флаг своя команда не ломает.
	Game.damage_flag(0, 50.0, a)
	check(is_equal_approx(Game.teams[0].flag_hp, Game.FLAG_MAX_HP), "свой флаг не ломается своим")
	# A ломает флаг Б, убивает Б → Б выбывает.
	Game.damage_flag(1, 100.0, a)
	check(Game.is_flag_under_attack(1), "флаг под атакой")
	Game.damage_flag(1, 999.0, a)
	check(not Game.teams[1].flag_alive and not Game.can_respawn(1), "флаг Б уничтожен — нет возрождения")
	check(Game.request_respawn(a), "A с флагом может возродиться")
	check(not Game.request_respawn(b), "Б без флага — нет")
	b.set(&"alive", false)
	Events.character_died.emit(b, a)
	await wait_frames(3)
	check(_elim.has(1), "Б выбыла (флаг + последний погиб)")
	check(int(Game.stats[a.get_instance_id()].kills) == 1 and int(Game.stats[a.get_instance_id()].flags) == 1, "A: 1 убийство, 1 флаг")
	check(int(Game.stats[b.get_instance_id()].deaths) == 1, "Б: 1 смерть")
	# Брёвна: начал нести бревно — +1.
	a.set(&"carrying_log", true)
	await wait_frames(2)
	a.set(&"carrying_log", false)
	await wait_frames(2)
	a.set(&"carrying_log", true)
	await wait_frames(2)
	check(int(Game.stats[a.get_instance_id()].logs) == 2, "брёвна считаются (2)")
	# Время: лимит → лидер по очкам (A — уничтожила флаг).
	Game.match_length = Game.match_time + 0.3
	await wait(0.6)
	check(_ended == 0, "по времени победила команда с очками (0), есть %d" % _ended)
	check(Game.state == Game.State.ENDED, "матч окончен")
	var rows := Game.stats_rows()
	check(rows.size() == 4 and float(rows[0].out_time) > 0.0, "строки статистики")
	# --- последний флаг ---
	_elim.clear()
	_ended = -99
	Game.pending_config = {"mode": "ffa", "minutes": 120}
	Game.start_match({})
	for n in [a, b, c, d]:
		n.set(&"alive", true)
		Game.register_character(n, int(n.get(&"team")))
	for t in 4:
		Game.set_flag_placed(t, Vector3(t * 50.0, 2, 0))
	for t in [1, 2, 0]:
		Game.damage_flag(t, 9999.0, d)
	for n in [b, c, a]:
		n.set(&"alive", false)
		Events.character_died.emit(n, d)
	await wait_frames(4)
	check(_elim.size() == 3, "выбыли три команды (%s)" % str(_elim))
	check(_ended == 3, "победил последний флаг — Жёлтые (есть %d)" % _ended)
	Game.end_session()
