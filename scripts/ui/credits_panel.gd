class_name CreditsPanel
extends PanelContainer
## Экран «Авторы»: титры и лицензии сторонних ресурсов (CC BY 4.0 требует
## указания авторов в игре). Полный список — ASSETS.md.

signal closed

const LINES: Array[Array] = [
	["Игра", "«Острова» — Artem Hashchak, разработка с Claude (Anthropic). Движок Godot Engine (MIT)."],
	["Звуки (CC BY 4.0)", "«Oculus Audio Pack 01» by Oculus VR, LLC — https://developers.meta.com/vr/downloads/package/oculus-audio-pack-1/, лицензия CC BY 4.0. Файлы переименованы, OGG перекодированы из WAV."],
	["Модель ботов (CC BY 4.0)", "«Mannequiny» — GDQuest and contributors (https://www.gdquest.com/), github.com/GDQuest/godot-3d-mannequin, лицензия CC BY 4.0."],
	["Аддоны (MIT)", "Terrain3D и Sky3D — TokisanGames (Cory Petkovsek, Roope Palmroos); MultiMesh Scatter — arcaneenergy; вода — Antz (Godot-Foam-Water) и LesusX (Water-Shader)."],
	["Модели и текстуры (CC0)", "Poly Haven (растения, камни, корабль — James Ray Cock, Nicolò Zubbini, Rico Cilliers; HDRI неба), ambientCG, Khronos glTF Sample Assets, руки — wriks (wrad-arms)."],
	["Звуки (CC0)", "wyzowl/sfx-kit — всплеск, гром, дерево."],
]

func _init() -> void:
	add_theme_stylebox_override(&"panel", UITheme.box(UITheme.PANEL, 8, UITheme.LINE, 1, 24))
	custom_minimum_size = Vector2(720, 0)
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	theme = UITheme.get_theme()
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	add_child(v)
	v.add_child(UITheme.title("Авторы", 28))
	for r in LINES:
		v.add_child(UITheme.label(String(r[0]), 15, UITheme.ACCENT, true))
		var l := UITheme.label(String(r[1]), 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(670, 0)
		v.add_child(l)
	var back := PauseMenu.menu_button("Назад", func() -> void:
		visible = false
		closed.emit())
	v.add_child(back)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		visible = false
		closed.emit()
