class_name TutorialLauncher
extends RefCounted
## Запуск режима «Обучение»: настоящий матч на домашнем острове Красных
## (те же модули, что и в match.tscn) + TutorialDirector, который ведёт по шагам.
## Сцена scenes/tutorial/tutorial.tscn — наследник match.tscn с узлом Tutorial.

const SCENE := "res://scenes/tutorial/tutorial.tscn"

## Конфиг матча обучения: 4 команды (флаги ставит обучение само), без ботов
## из лобби, без лимита времени. tutorial=true — признак для модулей.
const CONFIG: Dictionary = {
	"mode": "ffa", "teams": 4, "bots_enemy": 0, "bots_ally": 0, "difficulty": "easy",
	"minutes": 0, "map_size": "normal", "seed": 2026, "auto_flags": false, "tutorial": true,
}

static func start(tree: SceneTree) -> void:
	Game.pending_config = CONFIG.duplicate()
	tree.paused = false
	tree.change_scene_to_file(SCENE)

static func is_done() -> bool:
	return Settings.tutorial_done

static func mark_done() -> void:
	Settings.tutorial_done = true
	Settings.save_settings()
