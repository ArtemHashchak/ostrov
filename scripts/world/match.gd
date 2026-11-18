extends Node3D
## Главная сцена матча: мир + точки подключения модулей + игрок.
## Модули подключаются автоматически, если их файлы существуют
## (сцена или скрипт с корневым узлом) — правок этой сцены не требуется.

const MODULES: Array[Dictionary] = [
	{"slot": "Flora", "scenes": ["res://scenes/world/flora/flora.tscn"], "scripts": ["res://scripts/world/flora/flora.gd"]},
	{"slot": "Build", "scenes": ["res://scenes/build/build_module.tscn", "res://scenes/build/build.tscn"], "scripts": ["res://scripts/build/build.gd"]},
	{"slot": "Sea", "scenes": ["res://scenes/sea/sea.tscn"], "scripts": ["res://scripts/sea/sea.gd"]},
	{"slot": "Fauna", "scenes": ["res://scenes/fauna/fauna.tscn"], "scripts": ["res://scripts/fauna/fauna.gd"]},
	{"slot": "Survival", "scenes": ["res://scenes/survival/survival.tscn"], "scripts": ["res://scripts/survival/survival.gd"]},
	{"slot": "Bots", "scenes": ["res://scenes/bots/bots.tscn"], "scripts": ["res://scripts/bots/bots.gd"]},
	{"slot": "UI", "scenes": ["res://scenes/ui/ui.tscn", "res://scenes/ui/hud.tscn"], "scripts": ["res://scripts/ui/ui.gd"]},
]

@export var player_team: int = 0
@export var match_minutes: float = 180.0
@export var spawn_player: bool = true

var world: World
var player: Node3D
var loaded_modules: Array[String] = []

func _ready() -> void:
	world = $World as World
	if not world.is_ready:
		await world.world_ready
	for m in MODULES:
		_attach(m)
	if spawn_player:
		var ps := load("res://scenes/player/player.tscn") as PackedScene
		player = ps.instantiate() as Node3D
		player.set(&"team", player_team)
		player.position = world.spawn_point(player_team)
		add_child(player)
	Game.start_match({"minutes": match_minutes, "teams": 4})
	print("[match] модули: ", loaded_modules)

func _attach(m: Dictionary) -> void:
	var slot := get_node_or_null(String(m.slot))
	if slot == null:
		return
	for p: String in m.scenes:
		if ResourceLoader.exists(p):
			slot.add_child((load(p) as PackedScene).instantiate())
			loaded_modules.append(p)
			return
	for p: String in m.scripts:
		if ResourceLoader.exists(p):
			var scr := load(p) as Script
			var obj: Object = scr.new()
			if obj is Node:
				slot.add_child(obj as Node)
				loaded_modules.append(p)
			return
