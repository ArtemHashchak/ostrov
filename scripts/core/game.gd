extends Node
## Состояние и правила матча: команды, флаги, возрождение, выбывание, победа,
## время, статистика. Модель флага в мире ставит модуль build
## (BuildModule.place_flag), расстановку в начале матча — MatchDirector
## (scripts/game). Владелец правил — GAME/UI.
##
## Конфиг матча (Game.config, задаёт лобби через Game.pending_config):
##   mode: "ffa" | "2x2"         teams: 4 | 2
##   bots_enemy: 0..3            — ботов в каждой команде соперников
##   bots_ally: 0..3             — ботов-союзников в команде игрока
##   difficulty: "easy" | "normal" | "hard"
##   minutes: 60/120/180/240, 0 — «до последнего флага» (без лимита)
##   map_size: "small" | "normal" | "large"   seed: int
##   auto_flags: true — флаги всех команд ставятся у точек старта сразу
##
## Для ботов (scripts/bots): Game.bot_slots() — кого заспавнить;
## Game.register_character(ch, team) после спавна; Game.request_respawn(ch)
## когда бот готов возродиться (true — возродили / можно; false — выбыл).

const TEAM_NAMES: Array[String] = ["Красные", "Синие", "Зелёные", "Жёлтые"]
const TEAM_NAMES_GEN: Array[String] = ["Красных", "Синих", "Зелёных", "Жёлтых"]
const TEAM_COLORS: Array[Color] = [
	Color(0.85, 0.29, 0.24), Color(0.24, 0.48, 0.85), Color(0.30, 0.69, 0.31), Color(0.90, 0.73, 0.23)]
const RESPAWN_TIME := 10.0
const FLAG_MAX_HP := 300.0
const UNDER_ATTACK_SEC := 5.0

const DEFAULT_CONFIG: Dictionary = {
	"mode": "ffa", "teams": 4, "bots_enemy": 1, "bots_ally": 0, "difficulty": "normal",
	"minutes": 180, "map_size": "normal", "seed": 2026, "auto_flags": true,
}

enum State { MENU, PLAYING, ENDED }

class TeamState:
	var id: int
	var flag_alive: bool = true
	var flag_placed: bool = false
	var flag_hp: float = FLAG_MAX_HP
	var flag_pos: Vector3 = Vector3.ZERO
	var members: Array[Node] = []
	var eliminated: bool = false
	var eliminated_at: float = -1.0
	var last_attacked: float = -100.0 # match_time последнего урона по флагу
	var flags_destroyed: int = 0       # чужих флагов уничтожила команда
	var kills: int = 0

var state: State = State.MENU
var match_time: float = 0.0
var match_length: float = 3.0 * 3600.0
var teams: Array[TeamState] = []
var config: Dictionary = {}
## Настройки следующего матча (лобби → сцена матча). Сохраняются для «Ещё раз».
var pending_config: Dictionary = {}
var winner: int = -1
## Статистика по персонажам: instance_id → {name, team, kills, deaths, logs, bridges, flags, out_time, is_player}
var stats: Dictionary = {}

var _carry_prev: Dictionary = {} # instance_id → bool (для счёта брёвен)
var _check_acc := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_reset_teams(4)
	Events.character_died.connect(_on_character_died)
	Events.flag_destroyed.connect(_on_flag_destroyed)
	Events.structure_completed.connect(_on_structure_completed)

func _reset_teams(n: int) -> void:
	teams.clear()
	for i in n:
		var t := TeamState.new()
		t.id = i
		teams.append(t)

## Начать матч. cfg — значения по умолчанию сцены; pending_config (лобби) важнее.
func start_match(cfg: Dictionary = {}) -> void:
	var c: Dictionary = DEFAULT_CONFIG.duplicate()
	c.merge(cfg, true)
	c.merge(pending_config, true)
	if String(c.mode) == "2x2":
		c.teams = 2
	config = c
	match_time = 0.0
	var minutes := float(c.get("minutes", 180))
	match_length = minutes * 60.0 if minutes > 0.0 else INF
	winner = -1
	stats.clear()
	_carry_prev.clear()
	# Игрок мог зарегистрироваться до старта (его _ready раньше) — переносим.
	var keep: Array[Node] = []
	for t in teams:
		for m in t.members:
			if is_instance_valid(m) and m.is_inside_tree():
				keep.append(m)
	_reset_teams(int(c.get("teams", 4)))
	state = State.PLAYING
	for m in keep:
		register_character(m, int(m.get(&"team")) if m.get(&"team") != null else 0)
	Events.match_started.emit(c)

## Выйти в меню: матч больше не идёт.
func end_session() -> void:
	state = State.MENU

func is_playing() -> bool:
	return state == State.PLAYING

func team_count() -> int:
	return teams.size()

## Боты, которых должен создать модуль bots: [{team, difficulty}].
func bot_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var diff := String(config.get("difficulty", "normal"))
	for t in teams.size():
		var n := int(config.get("bots_ally", 0)) if t == 0 else int(config.get("bots_enemy", 1))
		if String(config.get("mode", "ffa")) == "2x2" and t != 0:
			n = int(config.get("bots_enemy", 1))
		for i in n:
			out.append({"team": t, "difficulty": diff, "index": i})
	return out

func register_member(team: int, ch: Node) -> void:
	register_character(ch, team)

## Зарегистрировать персонажа (игрок, бот) в команде и в статистике.
func register_character(ch: Node, team: int) -> void:
	if ch == null or team < 0 or team >= teams.size():
		return
	for t in teams:
		if t.id != team:
			t.members.erase(ch)
	if not teams[team].members.has(ch):
		teams[team].members.append(ch)
	var id := ch.get_instance_id()
	if not stats.has(id):
		stats[id] = {"name": display_name(ch), "team": team, "kills": 0, "deaths": 0, "logs": 0,
			"bridges": 0, "flags": 0, "out_time": -1.0, "is_player": ch.is_in_group(&"player")}
	else:
		stats[id].team = team

static func display_name(ch: Node) -> String:
	if ch == null:
		return "?"
	var dn: Variant = ch.get(&"display_name")
	if dn is String and dn != "":
		return dn
	if ch.is_in_group(&"player"):
		return "Ты"
	return String(ch.name)

func _process(delta: float) -> void:
	var __pt := PerfStats.begin()
	_perf_process(delta)
	PerfStats.end(&"game", __pt)

func _perf_process(delta: float) -> void:
	if state != State.PLAYING:
		return
	match_time += delta
	_track_logs()
	_check_acc += delta
	if _check_acc >= 0.5:
		_check_acc = 0.0
		check_eliminations()
	if state == State.PLAYING and match_time >= match_length:
		end_match(leading_team())

func time_left() -> float:
	return maxf(0.0, match_length - match_time)

func has_time_limit() -> bool:
	return match_length < INF

# ---------------------------------------------------------------- флаг

## Флаг поставлен (вызывает build-модуль).
func set_flag_placed(team: int, pos: Vector3) -> void:
	if team < 0 or team >= teams.size():
		return
	var t := teams[team]
	t.flag_placed = true
	t.flag_pos = pos
	Events.flag_placed.emit(team, pos)

func damage_flag(team: int, amount: float, by: Node = null) -> void:
	if team < 0 or team >= teams.size():
		return
	var t := teams[team]
	if not t.flag_alive:
		return
	# Свой флаг своей команде не ломается.
	var att := character_of(by)
	if att and att.get(&"team") != null and int(att.get(&"team")) == team:
		return
	t.flag_hp = maxf(0.0, t.flag_hp - amount)
	t.last_attacked = match_time
	Events.flag_damaged.emit(team, t.flag_hp, FLAG_MAX_HP)
	if t.flag_hp <= 0.0:
		t.flag_alive = false
		Events.flag_destroyed.emit(team, by)

func is_flag_under_attack(team: int) -> bool:
	return team >= 0 and team < teams.size() and teams[team].flag_alive \
		and match_time - teams[team].last_attacked < UNDER_ATTACK_SEC

## Можно ли возродиться персонажу команды.
func can_respawn(team: int) -> bool:
	return team >= 0 and team < teams.size() and teams[team].flag_alive \
		and not teams[team].eliminated and state != State.ENDED

## Точка возрождения команды: у флага, иначе у старта.
func respawn_position(team: int) -> Vector3:
	if team >= 0 and team < teams.size() and teams[team].flag_placed:
		var a := randf() * TAU
		return teams[team].flag_pos + Vector3(cos(a) * 2.2, 0.3, sin(a) * 2.2)
	var w := get_tree().get_first_node_in_group(&"world")
	if w and w.has_method(&"spawn_point"):
		return w.call(&"spawn_point", team) as Vector3
	return Vector3.ZERO

## Бот (или иной персонаж) просит возрождения. true — возрождён (у персонажа
## вызван respawn() либо он перенесён к флагу), false — команда без флага.
func request_respawn(ch: Node) -> bool:
	if ch == null or ch.get(&"team") == null:
		return false
	var team := int(ch.get(&"team"))
	if not can_respawn(team):
		return false
	if ch.has_method(&"respawn"):
		ch.call(&"respawn")
	elif ch is Node3D:
		(ch as Node3D).global_position = respawn_position(team)
		Events.character_spawned.emit(ch)
	return true

func team_color(team: int) -> Color:
	return TEAM_COLORS[posmod(team, TEAM_COLORS.size())]

# ---------------------------------------------------------------- выбывание и победа

## ch без типа: в составе команды может остаться уже освобождённый узел (бот удалён
## в конце сцены) — типизированный параметр на нём даёт ошибку скрипта.
static func is_alive(ch) -> bool:
	if ch == null or not is_instance_valid(ch) or not (ch is Node) or not ch.is_inside_tree():
		return false
	if ch.has_method(&"is_dead"):
		return not bool(ch.call(&"is_dead"))
	var a: Variant = ch.get(&"alive")
	return a == null or bool(a)

func alive_members(team: int) -> int:
	var n := 0
	for m in teams[team].members:
		if is_alive(m):
			n += 1
	return n

## Команда выбывает, когда флага нет и никто не жив.
func check_eliminations() -> void:
	if state != State.PLAYING:
		return
	for t in teams:
		if t.eliminated or t.flag_alive:
			continue
		if alive_members(t.id) == 0:
			t.eliminated = true
			t.eliminated_at = match_time
			for m in t.members:
				if is_instance_valid(m) and stats.has(m.get_instance_id()):
					stats[m.get_instance_id()].out_time = match_time
			Events.team_eliminated.emit(t.id)
	var left: Array[int] = []
	for t in teams:
		if not t.eliminated:
			left.append(t.id)
	if left.size() <= 1 and teams.size() > 1:
		end_match(left[0] if left.size() == 1 else -1)

func team_score(team: int) -> float:
	var t := teams[team]
	if t.eliminated:
		return -1000.0 + t.eliminated_at * 0.001
	return (10.0 if t.flag_alive else 0.0) + t.flags_destroyed * 5.0 + t.kills \
		+ alive_members(team) * 0.5 + t.flag_hp / FLAG_MAX_HP

## Лидер по очкам (для конца по времени); -1 — ничья.
func leading_team() -> int:
	var best := -1
	var best_s := -INF
	var tie := false
	for t in teams:
		var s := team_score(t.id)
		if s > best_s + 0.0001:
			best_s = s
			best = t.id
			tie = false
		elif absf(s - best_s) <= 0.0001:
			tie = true
	return -1 if tie else best

func end_match(win: int) -> void:
	if state != State.PLAYING:
		return
	state = State.ENDED
	winner = win
	for id: int in stats:
		if float(stats[id].out_time) < 0.0:
			stats[id].out_time = match_time
	Events.match_ended.emit(win)

## Строки статистики для экрана конца (по командам, затем по убийствам).
func stats_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: int in stats:
		var r: Dictionary = stats[id].duplicate()
		if float(r.out_time) < 0.0:
			r.out_time = match_time
		rows.append(r)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.team) != int(b.team):
			return int(a.team) < int(b.team)
		return int(a.kills) > int(b.kills))
	return rows

# ---------------------------------------------------------------- статистика

## Персонаж-виновник: сам узел, его стрелок/владелец или предок из группы characters.
func character_of(n: Node) -> Node:
	var cur: Node = n
	for i in 6:
		if cur == null or not is_instance_valid(cur):
			return null
		if cur.is_in_group(&"characters"):
			return cur
		for key: StringName in [&"shooter", &"owner_character", &"thrower", &"attacker", &"source"]:
			var v: Variant = cur.get(key)
			if v is Node and is_instance_valid(v) and (v as Node).is_in_group(&"characters"):
				return v as Node
		cur = cur.get_parent()
	return null

func _stat(ch: Node) -> Dictionary:
	if ch == null:
		return {}
	var id := ch.get_instance_id()
	if not stats.has(id) and ch.get(&"team") != null:
		register_character(ch, int(ch.get(&"team")))
	return stats.get(id, {})

func _on_character_died(ch: Node, killer: Node) -> void:
	if state != State.PLAYING or ch == null or not ch.is_in_group(&"characters"):
		return
	var s := _stat(ch)
	if not s.is_empty():
		s.deaths = int(s.deaths) + 1
	var k := character_of(killer)
	if k and k != ch:
		var ks := _stat(k)
		if not ks.is_empty() and int(ks.team) != int(s.get("team", -1)):
			ks.kills = int(ks.kills) + 1
			var kt := int(ks.team)
			if kt >= 0 and kt < teams.size():
				teams[kt].kills += 1
	check_eliminations.call_deferred()

func _on_flag_destroyed(team: int, by: Node) -> void:
	var k := character_of(by)
	if k:
		var ks := _stat(k)
		if not ks.is_empty():
			ks.flags = int(ks.flags) + 1
			var kt := int(ks.team)
			if kt >= 0 and kt < teams.size() and kt != team:
				teams[kt].flags_destroyed += 1
	check_eliminations.call_deferred()

func _on_structure_completed(node: Node, def_id: StringName) -> void:
	if state != State.PLAYING or not (node is Node3D):
		return
	if def_id != &"raft" and not String(def_id).contains("raft") and not String(def_id).contains("bridge"):
		return
	var team := int(node.get(&"team")) if node.get(&"team") != null else -1
	if team < 0 or team >= teams.size():
		return
	# Строитель — ближайший живой член команды.
	var best: Node = null
	var bd := 20.0
	for m in teams[team].members:
		if is_alive(m) and m is Node3D:
			var d := (m as Node3D).global_position.distance_to((node as Node3D).global_position)
			if d < bd:
				bd = d
				best = m
	if best:
		var s := _stat(best)
		s.bridges = int(s.bridges) + 1

func _track_logs() -> void:
	for t in teams:
		for m in t.members:
			if not is_instance_valid(m):
				continue
			var c: Variant = m.get(&"carrying_log")
			if c == null:
				continue
			var id := m.get_instance_id()
			var now := bool(c)
			if now and not bool(_carry_prev.get(id, false)) and stats.has(id):
				stats[id].logs = int(stats[id].logs) + 1
			_carry_prev[id] = now
