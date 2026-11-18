class_name MatchUI
extends Node
## Модуль UI матча (слот «UI» в match.tscn): ход матча (MatchDirector),
## матчевый HUD (флаги, таймер, компас, мини-карта, лента), экран итога.
## HUD игрока (полоски, хотбар, панели) создаёт сам игрок — scripts/ui/hud.gd.

var director: MatchDirector
var hud: MatchHUD
var end_screen: EndScreen
var _end_layer: CanvasLayer

func _ready() -> void:
	add_to_group(&"match_ui")
	director = MatchDirector.new()
	director.name = "MatchDirector"
	add_child(director)
	hud = MatchHUD.new()
	hud.name = "MatchHUD"
	add_child(hud)
	_end_layer = CanvasLayer.new()
	_end_layer.layer = 20
	_end_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_end_layer)
	end_screen = EndScreen.new()
	_end_layer.add_child(end_screen)
	director.notice.connect(hud.announce)
	Events.match_ended.connect(_on_match_ended)
	Events.team_eliminated.connect(_on_team_eliminated)

static func instance() -> MatchUI:
	var t := Engine.get_main_loop() as SceneTree
	return t.get_first_node_in_group(&"match_ui") as MatchUI if t else null

func _player_team() -> int:
	var p := get_tree().get_first_node_in_group(&"player")
	return int(p.get(&"team")) if p and p.get(&"team") != null else 0

func _on_team_eliminated(team: int) -> void:
	if team == _player_team() and Game.is_playing():
		# Дать посмотреть, как всё случилось, затем — итог (матч идёт дальше).
		await get_tree().create_timer(2.5).timeout
		if Game.is_playing() and is_inside_tree():
			end_screen.show_result(-1, false)

func _on_match_ended(win: int) -> void:
	await get_tree().create_timer(2.0, true).timeout
	if not is_inside_tree():
		return
	get_tree().paused = true
	end_screen.show_result(win, true)
