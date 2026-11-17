extends Node
## Состояние матча: команды, флаги, возрождение. Логику флага в мире (модель,
## постановка) делает модуль build; здесь — только правила и учёт.

const TEAM_NAMES: Array[String] = ["Красные", "Синие", "Зелёные", "Жёлтые"]
const TEAM_COLORS: Array[Color] = [
	Color(0.85, 0.29, 0.24), Color(0.24, 0.48, 0.85), Color(0.30, 0.69, 0.31), Color(0.90, 0.73, 0.23)]
const RESPAWN_TIME := 5.0
const FLAG_MAX_HP := 300.0

enum State { MENU, PLAYING, ENDED }

class TeamState:
	var id: int
	var flag_alive: bool = true
	var flag_placed: bool = false
	var flag_hp: float = FLAG_MAX_HP
	var flag_pos: Vector3 = Vector3.ZERO
	var members: Array[Node] = []
	var eliminated: bool = false

var state: State = State.MENU
var match_time: float = 0.0
var match_length: float = 3.0 * 3600.0
var teams: Array[TeamState] = []
var config: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_reset_teams(4)

func _reset_teams(n: int) -> void:
	teams.clear()
	for i in n:
		var t := TeamState.new()
		t.id = i
		teams.append(t)

func start_match(cfg: Dictionary = {}) -> void:
	config = cfg
	match_time = 0.0
	match_length = float(cfg.get("minutes", 180)) * 60.0
	_reset_teams(int(cfg.get("teams", 4)))
	state = State.PLAYING
	Events.match_started.emit(cfg)

func register_member(team: int, ch: Node) -> void:
	if team >= 0 and team < teams.size() and not teams[team].members.has(ch):
		teams[team].members.append(ch)

func _process(delta: float) -> void:
	if state == State.PLAYING:
		match_time += delta

## Флаг поставлен (вызывает build-модуль).
func set_flag_placed(team: int, pos: Vector3) -> void:
	var t := teams[team]
	t.flag_placed = true
	t.flag_pos = pos
	Events.flag_placed.emit(team, pos)

func damage_flag(team: int, amount: float, by: Node = null) -> void:
	var t := teams[team]
	if not t.flag_alive:
		return
	t.flag_hp = maxf(0.0, t.flag_hp - amount)
	Events.flag_damaged.emit(team, t.flag_hp, FLAG_MAX_HP)
	if t.flag_hp <= 0.0:
		t.flag_alive = false
		Events.flag_destroyed.emit(team, by)

## Можно ли возродиться персонажу команды.
func can_respawn(team: int) -> bool:
	return team >= 0 and team < teams.size() and teams[team].flag_alive

func team_color(team: int) -> Color:
	return TEAM_COLORS[team % TEAM_COLORS.size()]
