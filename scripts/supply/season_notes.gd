class_name SeasonNotes
extends Node3D
## Лор шоу: «записки прошлых сезонов» (docs/LORE.md) — бутылки с записками на берегу
## у каждого остова корабля (World.wrecks()). E — прочитать: текст во весь экран
## (закрыть — E/Esc или через READ_SEC), счёт «Записки: N из M». Коллекционные: без
## пользы в бою, раскрывают тайну «свободы» победителей.
##
## API: SeasonNotes.instance(), notes (Array[SeasonNote]), read_count(), open_note(i), close_note()

const READ_SEC := 25.0

const TEXTS: Array[String] = [
	"Сезон 3, день 9. Нас осталось двое. Флаг держится. Ведущий по ночам зачитывает ставки — на нас ставят всё меньше. Если кто-то это найдёт: не пейте из ручья у скал, он солёный после прилива.",
	"Сезон 5. Мы победили. Сказали ждать катер у центрального острова. Ждём четвёртый день. Дроны больше не прилетают. Ящики тоже.",
	"Кто бы ты ни был — мосты жгут ночью. Сторожи свой мост, а не флаг. Флаг они найдут и так. — Р.",
	"Сезон 7, «Синие». Контракт, пункт 14.2: «Призом распоряжается фонд в интересах победителя». Я прочитала его только здесь. Поздно.",
	"Акулы идут на кровь и на шум. Если упал в воду — не бей руками. Я видел, как они ходят за плотами кругами. Их кормят с вертолёта, каждый вечер в одно и то же время.",
	"Сезон 8. Победителей увезли. Через месяц один из них снова был на острове — в другой команде, под другим именем. Он нас не узнал. Или сделал вид.",
	"Камера на третьей пальме от бухты не работает с позапрошлого сезона. Там можно говорить. Там мы и договорились. Жаль, что не все сдержали слово.",
]

var notes: Array[SeasonNote] = []
var _layer: CanvasLayer
var _panel: PanelContainer
var _label: RichTextLabel
var _open_t := 0.0
var _open_i := -1

static func instance() -> SeasonNotes:
	var t := Engine.get_main_loop() as SceneTree
	return t.get_first_node_in_group(&"season_notes") as SeasonNotes if t else null

func _ready() -> void:
	name = "SeasonNotes"
	add_to_group(&"season_notes")
	_build_ui()
	_place.call_deferred()

## Бутылки у остовов: ближайшая к остову суша (пляж), не в воде.
func _place() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var w := get_tree().get_first_node_in_group(&"world")
	if w == null or not w.has_method(&"wrecks"):
		return
	var wl := BuildEnv.water_level()
	var i := 0
	for wr: Dictionary in w.call(&"wrecks"):
		if i >= TEXTS.size():
			break
		var c: Vector3 = wr.pos
		var spot := Vector3.INF
		for r: float in [12.0, 16.0, 20.0, 25.0, 31.0, 38.0]:
			for k in 16:
				var a := TAU * k / 16.0 + r
				var x := c.x + cos(a) * r
				var z := c.z + sin(a) * r
				var h := BuildEnv.height_at(x, z)
				if h > wl + 0.35 and h < wl + 3.0 and _clear(space, Vector3(x, h, z)):
					spot = Vector3(x, h, z)
					break
			if spot != Vector3.INF:
				break
		if spot == Vector3.INF:
			continue
		add_note(spot, i, float(wr.get("yaw", 0.0)))
		i += 1

## Сверху ничего нет (остов, камень, дерево): луч сверху упирается в сам рельеф.
static func _clear(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	if space == null:
		return true
	for off: Vector3 in [Vector3.ZERO, Vector3(0.8, 0, 0), Vector3(-0.8, 0, 0), Vector3(0, 0, 0.8), Vector3(0, 0, -0.8)]:
		var q := PhysicsRayQueryParameters3D.create(p + off + Vector3.UP * 30.0, p + off + Vector3.DOWN * 1.0)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit.position as Vector3).y > BuildEnv.height_at(p.x + off.x, p.z + off.z) + 0.25:
			return false
	return true

func add_note(at: Vector3, text_i: int, yaw: float = 0.0) -> SeasonNote:
	var n := SeasonNote.new()
	n.index = text_i
	n.name = "Note%d" % text_i
	add_child(n)
	n.global_position = at + Vector3.UP * 0.05
	n.rotation.y = yaw
	notes.append(n)
	return n

func read_count() -> int:
	var c := 0
	for n in notes:
		if is_instance_valid(n) and n.read:
			c += 1
	return c

func open_note(i: int) -> void:
	_open_i = i
	_open_t = READ_SEC
	_label.text = "[center][b][color=#6b4a2a]Записка прошлого сезона[/color][/b][/center]\n\n%s\n\n[right][color=#7a6a55]Записки: %d из %d   ·   E / Esc — закрыть[/color][/right]" % [
		TEXTS[i % TEXTS.size()], read_count(), notes.size()]
	_panel.visible = true

func close_note() -> void:
	_open_i = -1
	_panel.visible = false

func is_open() -> bool:
	return _panel.visible

func _process(delta: float) -> void:
	if _open_t > 0.0:
		_open_t -= delta
		if _open_t <= 0.0:
			close_note()

## _input (а не _unhandled_input): Esc должен закрыть записку раньше, чем откроется меню паузы.
func _input(event: InputEvent) -> void:
	if not _panel.visible:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"interact"):
		# E, которым открыли, уже обработан; закрываем только «свежим» нажатием
		if _open_t < READ_SEC - 0.3:
			close_note()
			get_viewport().set_input_as_handled()

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 6
	add_child(_layer)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.86, 0.8, 0.66, 0.96)   # старая бумага
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 20
	sb.content_margin_bottom = 18
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	_panel.add_theme_stylebox_override(&"panel", sb)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -300
	_panel.offset_right = 300
	_panel.offset_top = -150
	_panel.offset_bottom = 150
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_layer.add_child(_panel)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override(&"default_color", Color(0.17, 0.13, 0.09))
	_label.add_theme_font_size_override(&"normal_font_size", 17)
	_label.add_theme_font_size_override(&"bold_font_size", 18)
	_panel.add_child(_label)
	_panel.visible = false


class SeasonNote:
	extends StaticBody3D
	## Бутылка с запиской на песке (коллайдер — для луча взаимодействия игрока).
	var index := 0
	var read := false

	func _ready() -> void:
		add_to_group(&"interactable")
		add_to_group(&"season_note")
		collision_layer = 1
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.35, 0.18, 0.18)
		cs.shape = sh
		cs.position = Vector3(0, 0.07, 0)
		add_child(cs)
		_build()

	func _build() -> void:
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(0.35, 0.55, 0.42, 0.55)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.roughness = 0.08
		glass.metallic_specular = 0.9
		var paper := StandardMaterial3D.new()
		paper.albedo_color = Color(0.86, 0.8, 0.64)
		paper.roughness = 0.9
		var cork := StandardMaterial3D.new()
		cork.albedo_color = Color(0.5, 0.36, 0.22)
		cork.roughness = 0.9
		var body := CylinderMesh.new()
		body.top_radius = 0.045
		body.bottom_radius = 0.048
		body.height = 0.22
		body.radial_segments = 12
		var neck := CylinderMesh.new()
		neck.top_radius = 0.016
		neck.bottom_radius = 0.04
		neck.height = 0.08
		neck.radial_segments = 10
		var plug := CylinderMesh.new()
		plug.top_radius = 0.015
		plug.bottom_radius = 0.015
		plug.height = 0.03
		plug.radial_segments = 8
		var roll := CylinderMesh.new()
		roll.top_radius = 0.025
		roll.bottom_radius = 0.025
		roll.height = 0.18
		roll.radial_segments = 8
		var b := Node3D.new()
		b.name = "Bottle"
		b.rotation = Vector3(0, 0, PI * 0.5)   # лежит на боку
		b.position = Vector3(0, 0.05, 0)
		add_child(b)
		_mi(b, body, glass, Vector3.ZERO)
		_mi(b, neck, glass, Vector3(0, 0.15, 0))
		_mi(b, plug, cork, Vector3(0, 0.2, 0))
		_mi(b, roll, paper, Vector3(0, -0.005, 0))

	func _mi(p: Node3D, m: Mesh, mat: Material, pos: Vector3) -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = mat
		mi.position = pos
		mi.visibility_range_end = 80.0
		p.add_child(mi)

	func get_interact_text(_ch: Node) -> String:
		return "Бутылка с запиской — E: прочитать" if not read else "Записка прошлого сезона — E: перечитать"

	func interact(ch: Node) -> void:
		if not ch.is_in_group(&"player"):
			return
		read = true
		var sn := get_parent() as SeasonNotes
		if sn:
			sn.open_note(index)
