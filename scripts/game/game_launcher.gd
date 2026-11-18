class_name GameLauncher
extends RefCounted
## Запуск матча с настройками лобби, «Ещё раз», выход в меню.

const MATCH := "res://scenes/world/match.tscn"
const FALLBACK := "res://scenes/test/test_island.tscn"
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const LOBBY_SAVE := "user://lobby.cfg"

## Сид мира по размеру карты (пока WORLD не умеет менять число островов —
## размер только запоминается в Game.config.map_size и в World.map_size, если есть).
static func seed_for(cfg: Dictionary) -> int:
	return int(cfg.get("seed", 2026))

## Запустить матч: cfg уходит в Game.pending_config, сцена создаётся с нужным сидом.
static func start(tree: SceneTree, cfg: Dictionary) -> void:
	Game.pending_config = cfg.duplicate()
	save_lobby(cfg)
	tree.paused = false
	if not ResourceLoader.exists(MATCH):
		tree.change_scene_to_file(FALLBACK)
		return
	var m := (load(MATCH) as PackedScene).instantiate()
	m.set(&"player_team", 0)
	var minutes := float(cfg.get("minutes", 180))
	m.set(&"match_minutes", minutes if minutes > 0.0 else 0.0)
	var w := m.get_node_or_null(^"World")
	if w:
		if w.get(&"seed_value") != null:
			w.set(&"seed_value", seed_for(cfg))
		if w.get(&"map_size") != null:
			w.set(&"map_size", String(cfg.get("map_size", "normal")))
	tree.change_scene_to_node(m)

## Повторить с теми же настройками.
static func restart(tree: SceneTree) -> void:
	Game.end_session()
	start(tree, Game.pending_config if not Game.pending_config.is_empty() else Game.config)

static func to_menu(tree: SceneTree) -> void:
	Game.end_session()
	tree.paused = false
	tree.change_scene_to_file(MAIN_MENU)

static func save_lobby(cfg: Dictionary) -> void:
	var f := ConfigFile.new()
	for k: String in cfg:
		f.set_value("lobby", k, cfg[k])
	f.save(LOBBY_SAVE)

static func load_lobby() -> Dictionary:
	var out: Dictionary = Game.DEFAULT_CONFIG.duplicate()
	var f := ConfigFile.new()
	if f.load(LOBBY_SAVE) == OK and f.has_section("lobby"):
		for k in f.get_section_keys("lobby"):
			out[k] = f.get_value("lobby", k)
	return out
