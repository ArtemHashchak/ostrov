class_name Bots
extends Node3D
## Корневой узел модуля BOTS (scenes/bots/bots.tscn, слот «Bots» в match.gd).
## На старте матча создаёт ботов по Game.bot_slots() (лобби: сколько ботов в командах,
## сложность). Каждая команда ботов — BotTeam (общий план), каждый бот — Bot + BotBrain.
## Навигация — BotNav (граф островов, мосты, заплывы).
##
## API: Bots.instance(), spawn_bot(team, difficulty, pos?), team_ai(team), bots,
##      nav, set_enabled(on), static speed (множитель скорости работы — для тестов).

## Множитель скорости работы ботов (рубка/сбор). Только для тестов/отладки.
static var speed: float = 1.0

var nav: BotNav = null
var teams: Dictionary = {}        # team -> BotTeam
var bots: Array[Bot] = []
var enabled: bool = true
var _world: Node = null

static func instance() -> Bots:
	var t := Engine.get_main_loop() as SceneTree
	return t.get_first_node_in_group(&"bots_module") as Bots if t else null

func _ready() -> void:
	add_to_group(&"bots_module")
	Events.match_started.connect(_on_match_started)

func _exit_tree() -> void:
	BotModel.clear_cache()
	speed = 1.0

func set_enabled(on: bool) -> void:
	enabled = on
	for b in bots:
		if is_instance_valid(b):
			b.set_physics_process(on)

func _on_match_started(cfg: Dictionary) -> void:
	if not bool(cfg.get("bots", true)):
		return
	# флаги ставит MatchDirector в том же сигнале — ботов создаём после
	_spawn_from_slots.call_deferred()

func _spawn_from_slots() -> void:
	if not is_inside_tree():
		return
	for s: Dictionary in Game.bot_slots():
		spawn_bot(int(s.team), StringName(String(s.get("difficulty", "normal"))))
	if not bots.is_empty():
		print("[bots] создано ботов: ", bots.size())

func world() -> Node:
	if _world == null or not is_instance_valid(_world):
		_world = get_tree().get_first_node_in_group(&"world")
	return _world

func ensure_nav() -> BotNav:
	if nav == null and world():
		nav = BotNav.new()
		nav.setup(world())
		nav.refresh_links(get_tree())
	return nav

func team_ai(team: int) -> BotTeam:
	if not teams.has(team):
		ensure_nav()
		teams[team] = BotTeam.new(team, nav, self)
	return teams[team]

## Создать бота команды team. pos — где появиться (по умолчанию у флага команды).
func spawn_bot(team: int, difficulty: StringName = &"normal", pos: Variant = null) -> Bot:
	if ensure_nav() == null:
		push_warning("[bots] нет мира — боты не созданы")
		return null
	var ta := team_ai(team)
	ta.ensure_flag()
	var b := Bot.new().setup(team, difficulty, ta.bots.size())
	b.nav = nav
	b.team_ai = ta
	b.brain = BotBrain.new(b, ta)
	var p: Vector3 = pos if pos is Vector3 else Game.respawn_position(team)
	add_child(b)
	b.global_position = p + Vector3.UP * 0.2
	ta.bots.append(b)
	bots.append(b)
	# стартовый набор: каменный топор (игрок делает его за минуту)
	b.inventory.add(&"axe_crude", 1)
	if difficulty == &"hard":
		b.inventory.add(&"spear", 1)
	b.hold(&"axe_crude")
	return b

func _physics_process(delta: float) -> void:
	var __pt := PerfStats.begin()
	_perf_physics(delta)
	PerfStats.end(&"bots_nav", __pt)

func _perf_physics(delta: float) -> void:
	if nav and enabled:
		nav.update(delta, get_tree())
