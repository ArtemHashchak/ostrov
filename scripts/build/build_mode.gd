class_name BuildMode
extends Node
## Режим стройки игрока (дочерний узел Player): B — список чертежей,
## 1..9/колесо — выбор, ЛКМ — взять/поставить, R — повернуть, ПКМ/B — отмена.

enum State { NONE, MENU, PLACING }

var state: State = State.NONE
var entries: Array[StringName] = []
var sel: int = 0
var current: StringName = &""
var yaw_off: float = 0.0
var ghost: Node3D = null
var valid: bool = false
var reason: String = ""
var place_xform: Transform3D = Transform3D.IDENTITY
var place_anchor: Dictionary = {}
var place_ctx: Dictionary = {}

var _layer: CanvasLayer
var _panel: PanelContainer
var _list: VBoxContainer
var _hint: Label
var _player: Node3D

func _ready() -> void:
	_player = get_parent() as Node3D
	_build_ui()

func player_team() -> int:
	return int(_player.get(&"team")) if _player and _player.get(&"team") != null else 0

# ======================= UI =======================

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.1, 0.07, 0.86)
	sb.border_color = Color(0.55, 0.42, 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	_panel.add_theme_stylebox_override(&"panel", sb)
	_panel.position = Vector2(30, 110)
	_layer.add_child(_panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 3)
	_panel.add_child(_list)
	_panel.visible = false
	_hint = Label.new()
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -400
	_hint.offset_right = 400
	_hint.offset_top = -150
	_hint.offset_bottom = -110
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override(&"font_size", 18)
	_hint.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override(&"outline_size", 5)
	_hint.visible = false
	_layer.add_child(_hint)

func _refresh_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "Чертежи  (1-9 / колесо, ЛКМ — выбрать, B — закрыть)"
	title.add_theme_color_override(&"font_color", Color(0.95, 0.85, 0.6))
	_list.add_child(title)
	for i in entries.size():
		var id := entries[i]
		var l := Label.new()
		var nm := "Флаг команды" if id == &"flag" else BuildDefs.name_of(id)
		var cost := "1 флаг из инвентаря" if id == &"flag" else BuildDefs.cost_text(id)
		l.text = "%s %d. %s  —  %s" % ["▶" if i == sel else "  ", i + 1, nm, cost]
		l.add_theme_color_override(&"font_color", Color(1, 0.9, 0.55) if i == sel else Color(0.85, 0.82, 0.75))
		_list.add_child(l)

func _set_hint(t: String) -> void:
	_hint.text = t
	_hint.visible = t != ""

# ======================= состояние =======================

func open_menu() -> void:
	entries.clear()
	var t := player_team()
	if not _flag_placed(t):
		entries.append(&"flag")
	entries.append_array(BuildDefs.ORDER)
	sel = clampi(sel, 0, entries.size() - 1)
	state = State.MENU
	_refresh_list()
	_panel.visible = true

func close() -> void:
	state = State.NONE
	_panel.visible = false
	_set_hint("")
	_free_ghost()

func start_place(id: StringName) -> void:
	_panel.visible = false
	_free_ghost()
	current = id
	state = State.PLACING
	if id == &"flag":
		ghost = TeamFlag.new().setup(player_team(), true)
	else:
		ghost = Blueprint.new().setup(id, player_team(), {}, true)
	ghost.name = "BuildGhost"
	_ghost_key = ""
	var root := _player.get_parent() if _player.get_parent() else get_tree().current_scene
	root.add_child(ghost)

func _free_ghost() -> void:
	if ghost and is_instance_valid(ghost):
		ghost.queue_free()
	ghost = null

static func _flag_placed(team: int) -> bool:
	if team < 0 or team >= Game.teams.size():
		return true
	return Game.teams[team].flag_placed

# ======================= ввод =======================

func _unhandled_input(event: InputEvent) -> void:
	var mod := BuildModule.instance()
	if _player == null or bool(_player.get(&"ui_open")):
		return
	if event.is_action_pressed(&"build_menu") and (mod == null or mod.menu_hotkey_enabled):
		if state == State.NONE:
			open_menu()
		else:
			close()
		_eat()
		return
	if state == State.NONE:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_scroll(-1)
				_eat()
			MOUSE_BUTTON_WHEEL_DOWN:
				_scroll(1)
				_eat()
			MOUSE_BUTTON_LEFT:
				confirm()
				_eat()
			MOUSE_BUTTON_RIGHT:
				close()
				_eat()
		return
	if event.is_action_pressed(&"attack"):
		confirm()
		_eat()
	elif event.is_action_pressed(&"aim") or event.is_action_pressed(&"pause"):
		close()
		_eat()
	elif event.is_action_pressed(&"build_rotate"):
		yaw_off += PI / 4.0
		_eat()
	elif state == State.MENU:
		for i in mini(9, entries.size()):
			if event.is_action_pressed(StringName("hotbar_%d" % (i + 1))):
				sel = i
				_refresh_list()
				_eat()
				break

func _eat() -> void:
	get_viewport().set_input_as_handled()

func _scroll(d: int) -> void:
	if state == State.MENU:
		sel = posmod(sel + d, entries.size())
		_refresh_list()
	else:
		yaw_off += d * PI / 8.0

## ЛКМ: в меню — взять чертёж; при постановке — поставить.
func confirm() -> void:
	if state == State.MENU:
		if entries.is_empty():
			return
		start_place(entries[sel])
	elif state == State.PLACING:
		_update_ghost()
		if not valid:
			BuildEnv.toast(reason if reason != "" else "Здесь нельзя")
			return
		var mod := BuildModule.instance()
		if mod == null:
			return
		if current == &"flag":
			var inv := BuildEnv.inventory(_player)
			if inv and inv.has_method(&"count") and int(inv.call(&"count", &"flag")) > 0:
				inv.call(&"remove", &"flag", 1)
			mod.place_flag(player_team(), place_xform.origin, place_xform.basis.get_euler().y)
			BuildEnv.toast("Флаг поставлен — защищай его!")
			close()
			return
		mod.place_blueprint(current, place_xform, player_team(), place_anchor, place_ctx)
		# мост/стены удобно ставить подряд — режим остаётся
		_update_ghost()

# ======================= призрак =======================

func _process(_delta: float) -> void:
	if state == State.PLACING:
		_update_ghost()

func _cam() -> Camera3D:
	var c: Variant = _player.get(&"camera")
	return c as Camera3D if c else _player.get_viewport().get_camera_3d()

func _update_ghost() -> void:
	if ghost == null or not is_instance_valid(ghost) or not ghost.is_inside_tree():
		return
	var mod := BuildModule.instance()
	var cam := _cam()
	if mod == null or cam == null:
		return
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var yaw := atan2(-dir.x, -dir.z) + yaw_off  # постройка «смотрит» лицом к игроку по -Z
	valid = false
	reason = ""
	place_anchor = {}
	if current == &"flag":
		var hit := _ray(from, dir, 7.0)
		var p: Vector3 = hit.get("position", from + dir * 4.0)
		if hit.is_empty() and dir.y < -0.05:
			var tw := (BuildEnv.water_level() - from.y) / dir.y
			if tw > 0.0 and tw < 12.0:
				p = from + dir * tw
				hit = {"position": p}
		place_xform = Transform3D(Basis(Vector3.UP, yaw), p)
		if hit.is_empty():
			reason = "Смотри на землю"
		elif _flag_placed(player_team()):
			reason = "Флаг уже стоит"
		elif BuildEnv.height_at(p.x, p.z) < BuildEnv.water_level() + 0.2:
			reason = "Флаг — только на суше"
		elif not BuildEnv.on_own_island(player_team(), p):
			reason = "Флаг ставится только на своём острове"
		else:
			valid = true
	elif BuildDefs.kind_of(current) == &"raft":
		_place_raft(mod, from, dir, yaw)
	else:
		_place_structure(mod, from, dir, yaw)
	ghost.global_transform = place_xform
	if ghost is Blueprint:
		(ghost as Blueprint).set_preview_valid(valid)
	elif ghost.has_method(&"set_preview_valid"):
		ghost.call(&"set_preview_valid", valid)
	var nm := "Флаг" if current == &"flag" else BuildDefs.name_of(current)
	_set_hint("%s — %s   [ЛКМ поставить · R повернуть · ПКМ отмена]" % [nm, "можно" if valid else reason])

var _ghost_key: String = ""
func _ghost_rebuild(c: Dictionary, key: String) -> void:
	if key == _ghost_key or not (ghost is Blueprint):
		return
	_ghost_key = key
	(ghost as Blueprint).rebuild(c)

func _ray(from: Vector3, dir: Vector3, dist: float) -> Dictionary:
	var space := _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * dist)
	q.collide_with_areas = false
	var ex: Array[RID] = []
	if _player is CollisionObject3D:
		ex.append((_player as CollisionObject3D).get_rid())
	if ghost is CollisionObject3D:
		ex.append((ghost as CollisionObject3D).get_rid())
	q.exclude = ex
	return space.intersect_ray(q)

func _place_structure(mod: BuildModule, from: Vector3, dir: Vector3, yaw: float) -> void:
	var hit := _ray(from, dir, 9.0)
	var p: Vector3 = hit.get("position", from + dir * 5.0)
	var tag: StringName = StringName(BuildDefs.INFO.get(current, {}).get("snap", &""))
	var s := mod.find_socket(tag, p) if tag != &"" else {}
	place_ctx = {}
	if not s.is_empty():
		place_xform = s.xform
		place_ctx = s.get("ctx", {})
		if current == &"stairs":
			_ghost_rebuild(place_ctx, "stairs_socket")
		if yaw_off != 0.0 and current in [&"wall", &"wall_window", &"wall_door"]:
			# R на сокете: развернуть стену на 180° (окно наружу/внутрь)
			if int(round(yaw_off / (PI / 4.0))) % 2 == 1:
				place_xform.basis = place_xform.basis * Basis(Vector3.UP, PI)
		valid = true
		if current == &"platform":
			_ghost_rebuild(mod.platform_ctx(place_xform), str(place_xform.origin.snapped(Vector3.ONE * 0.1), place_xform.basis.get_euler().y))
		return
	if hit.is_empty():
		place_xform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, BuildEnv.height_at(p.x, p.z), p.z))
		reason = "Смотри на землю"
		return
	var y := p.y
	if current != &"platform":
		y = BuildEnv.height_at(p.x, p.z) if hit.collider is StaticBody3D else p.y
		y = minf(y, p.y)
	place_xform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y, p.z))
	if current == &"platform":
		# настил ровно; сваи до земли
		_ghost_rebuild(mod.platform_ctx(place_xform), str(place_xform.origin.snapped(Vector3.ONE * 0.1), snappedf(place_xform.basis.get_euler().y, 0.05)))
	elif current == &"stairs":
		_ghost_rebuild({}, "stairs_ground")
	reason = mod.check_ground(current, place_xform)
	valid = reason == ""

func _place_raft(mod: BuildModule, from: Vector3, dir: Vector3, yaw: float) -> void:
	var wl := BuildEnv.water_level()
	var p := from + dir * 6.0
	if dir.y < -0.05:
		var t := (wl - from.y) / dir.y
		if t > 0.0 and t < 14.0:
			p = from + dir * t
	var s := mod.raft_socket(p)
	if not s.is_empty():
		place_xform = s.xform
		place_anchor = {"type": &"raft", "parent": s.parent, "offset": s.offset}
		valid = true
		return
	var r := mod.shore_raft(p, yaw)
	place_xform = r.xform
	valid = bool(r.ok)
	reason = String(r.reason)
	if valid:
		place_anchor = {"type": &"shore"}
