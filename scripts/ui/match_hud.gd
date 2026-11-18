class_name MatchHUD
extends CanvasLayer
## Матчевый интерфейс поверх HUD игрока: флаги команд (мигают при атаке),
## таймер, компас, мини-карта (M — большая карта), лента убийств,
## крупные объявления. Создаёт модуль UI (scripts/ui/ui.gd).

const FEED_MAX := 5
const FEED_TIME := 7.0

var player: Node3D = null
var root: Control
var minimap: Minimap
var big_map: Minimap
var _big_holder: Control
var _flags_box: VBoxContainer
var _flag_rows: Array[Dictionary] = []
var _timer: Label
var _compass: Control
var _feed: VBoxContainer
var _banner: Label
var _banner_t := 0.0
var _built_teams := -1

func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.name = "MatchHUDRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	_build_flags()
	_build_top()
	_build_minimap()
	_build_feed()
	_build_banner()
	_build_big_map()
	Events.character_died.connect(_on_died)
	Events.match_started.connect(func(_c: Dictionary) -> void: _rebuild_flags())

func _build_flags() -> void:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override(&"panel", UITheme.box(Color(0, 0, 0, 0.3), 6, Color(0, 0, 0, 0), 0, 8))
	pc.position = Vector2(18, 16)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pc)
	_flags_box = VBoxContainer.new()
	_flags_box.add_theme_constant_override(&"separation", 5)
	_flags_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(_flags_box)
	_rebuild_flags()

func _rebuild_flags() -> void:
	for c in _flags_box.get_children():
		c.queue_free()
	_flag_rows.clear()
	_built_teams = Game.teams.size()
	for t in Game.teams:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(18, 20)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tid := t.id
		icon.draw.connect(func() -> void: _draw_flag_icon(icon, tid))
		row.add_child(icon)
		var nm := UITheme.label(Game.TEAM_NAMES[tid % 4], 13, Game.team_color(tid).lightened(0.25), true)
		nm.custom_minimum_size = Vector2(74, 0)
		nm.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.7))
		nm.add_theme_constant_override(&"outline_size", 4)
		row.add_child(nm)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(80, 5)
		bar.show_percentage = false
		bar.max_value = Game.FLAG_MAX_HP
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.5)
		bg.set_corner_radius_all(2)
		var fg := StyleBoxFlat.new()
		fg.bg_color = Game.team_color(tid)
		fg.set_corner_radius_all(2)
		bar.add_theme_stylebox_override(&"background", bg)
		bar.add_theme_stylebox_override(&"fill", fg)
		row.add_child(bar)
		var info := UITheme.label("", 12, UITheme.TEXT_DIM)
		info.custom_minimum_size = Vector2(96, 0)
		info.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.7))
		info.add_theme_constant_override(&"outline_size", 3)
		row.add_child(info)
		_flags_box.add_child(row)
		_flag_rows.append({"row": row, "icon": icon, "bar": bar, "info": info, "team": tid})

func _draw_flag_icon(c: Control, team: int) -> void:
	if team >= Game.teams.size():
		return
	var t = Game.teams[team]
	var col := Game.team_color(team)
	if t.eliminated:
		col = Color(0.4, 0.4, 0.4)
	c.draw_line(Vector2(4, 19), Vector2(4, 1), Color(0.85, 0.8, 0.7), 2.0)
	if t.flag_alive:
		var blink := Game.is_flag_under_attack(team) and int(Time.get_ticks_msec() / 220) % 2 == 0
		c.draw_colored_polygon(PackedVector2Array([Vector2(5, 1), Vector2(17, 5), Vector2(5, 10)]), Color(1, 1, 1) if blink else col)
	else:
		c.draw_line(Vector2(2, 3), Vector2(16, 17), UITheme.DANGER, 2.5)
		c.draw_line(Vector2(16, 3), Vector2(2, 17), UITheme.DANGER, 2.5)

func _build_top() -> void:
	_compass = Control.new()
	_compass.anchor_left = 0.5
	_compass.anchor_right = 0.5
	_compass.offset_left = -190
	_compass.offset_right = 190
	_compass.offset_top = 10
	_compass.offset_bottom = 36
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass.draw.connect(_draw_compass)
	root.add_child(_compass)
	_timer = UITheme.label("", 15, UITheme.TEXT)
	_timer.anchor_left = 0.5
	_timer.anchor_right = 0.5
	_timer.offset_left = -120
	_timer.offset_right = 120
	_timer.offset_top = 38
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.75))
	_timer.add_theme_constant_override(&"outline_size", 4)
	root.add_child(_timer)

func _build_minimap() -> void:
	minimap = Minimap.new()
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.offset_left = -214
	minimap.offset_right = -16
	minimap.offset_top = 16
	minimap.offset_bottom = 214
	root.add_child(minimap)

func _build_feed() -> void:
	_feed = VBoxContainer.new()
	_feed.anchor_left = 1.0
	_feed.anchor_right = 1.0
	_feed.offset_left = -420
	_feed.offset_right = -16
	_feed.offset_top = 224
	_feed.add_theme_constant_override(&"separation", 3)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)

func _build_banner() -> void:
	_banner = UITheme.title("", 30)
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.24
	_banner.anchor_bottom = 0.24
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	_banner.add_theme_constant_override(&"outline_size", 6)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	root.add_child(_banner)

func _build_big_map() -> void:
	_big_holder = Control.new()
	_big_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_big_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big_holder.visible = false
	root.add_child(_big_holder)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big_holder.add_child(dim)
	big_map = Minimap.new()
	big_map.full = true
	big_map.anchor_left = 0.5
	big_map.anchor_right = 0.5
	big_map.anchor_top = 0.5
	big_map.anchor_bottom = 0.5
	big_map.offset_left = -300
	big_map.offset_right = 300
	big_map.offset_top = -305
	big_map.offset_bottom = 295
	_big_holder.add_child(big_map)
	var hint := UITheme.label("Карта · %s — закрыть" % UITheme.key_name(&"map"), 13, UITheme.TEXT_DIM)
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 0.5
	hint.anchor_bottom = 0.5
	hint.offset_left = -292
	hint.offset_top = 272
	_big_holder.add_child(hint)

func is_big_map_open() -> bool:
	return _big_holder.visible

func toggle_big_map() -> void:
	_big_holder.visible = not _big_holder.visible

# ------------------------------------------------------------------ обновление

func _process(delta: float) -> void:
	var __pt := PerfStats.begin()
	_perf_process(delta)
	PerfStats.end(&"ui", __pt)

func _perf_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(&"player") as Node3D
		minimap.player = player
		big_map.player = player
	if _built_teams != Game.teams.size():
		_rebuild_flags()
	var paused := get_tree().paused
	root.visible = not paused or _big_holder.visible
	# Большая карта видит то же, что открыла мини-карта.
	for t in Game.teams:
		if minimap.is_discovered(t.id):
			big_map.discover(t.id)
	for r in _flag_rows:
		var t = Game.teams[int(r.team)] if int(r.team) < Game.teams.size() else null
		if t == null:
			continue
		(r.bar as ProgressBar).value = t.flag_hp if t.flag_alive else 0.0
		var alive := Game.alive_members(t.id)
		var info := r.info as Label
		if t.eliminated:
			info.text = "выбыли"
		elif not t.flag_alive:
			info.text = "без флага · %d" % alive
		elif Game.is_flag_under_attack(t.id):
			info.text = "АТАКА! · %d" % alive
		else:
			info.text = "в игре · %d" % alive
		info.add_theme_color_override(&"font_color", UITheme.DANGER if Game.is_flag_under_attack(t.id) or (not t.flag_alive and not t.eliminated) else UITheme.TEXT_DIM)
		(r.row as Control).modulate.a = 0.45 if t.eliminated else 1.0
		(r.icon as Control).queue_redraw()
	if Game.has_time_limit():
		_timer.text = fmt_time(Game.time_left())
		_timer.add_theme_color_override(&"font_color", UITheme.DANGER if Game.time_left() < 300.0 else UITheme.TEXT)
	else:
		_timer.text = fmt_time(Game.match_time) + " · до последнего флага"
	_compass.queue_redraw()
	_banner_t = maxf(0.0, _banner_t - delta)
	_banner.modulate.a = clampf(_banner_t, 0.0, 1.0)
	for l in _feed.get_children():
		var ttl := float(l.get_meta(&"ttl", FEED_TIME)) - delta
		l.set_meta(&"ttl", ttl)
		(l as Control).modulate.a = clampf(ttl, 0.0, 1.0)
		if ttl <= 0.0:
			l.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"map") and not get_tree().paused:
		toggle_big_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"pause") and _big_holder.visible:
		_big_holder.visible = false
		get_viewport().set_input_as_handled()

static func fmt_time(sec: float) -> String:
	var s := int(sec)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]

## Крупное объявление по центру сверху.
func announce(text: String, color: Color = UITheme.TEXT) -> void:
	_banner.text = text
	_banner.add_theme_color_override(&"font_color", color)
	_banner_t = 3.6

func _on_died(ch: Node, killer: Node) -> void:
	if ch == null or not ch.is_in_group(&"characters"):
		return
	var k := Game.character_of(killer)
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	line.custom_minimum_size = Vector2(400, 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_font_size_override(&"normal_font_size", 14)
	line.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	line.add_theme_constant_override(&"outline_size", 4)
	var victim := _who(ch)
	var reason := _reason(StringName(ch.get(&"last_damage_kind")) if ch.get(&"last_damage_kind") != null else &"")
	if k and k != ch:
		line.text = "[right]%s  [color=#d9c49a]✕[/color]  %s[/right]" % [_who(k), victim]
	else:
		line.text = "[right]%s [color=#bbb]— %s[/color][/right]" % [victim, reason]
	line.set_meta(&"ttl", FEED_TIME)
	_feed.add_child(line)
	while _feed.get_child_count() > FEED_MAX:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()

func _who(ch: Node) -> String:
	var team := int(ch.get(&"team")) if ch.get(&"team") != null else -1
	var col := Game.team_color(team).lightened(0.25) if team >= 0 else UITheme.TEXT
	return "[color=#%s]%s[/color]" % [col.to_html(false), Game.display_name(ch)]

static func _reason(kind: StringName) -> String:
	match kind:
		&"drown": return "утонул"
		&"fall": return "разбился"
		&"starve": return "истощение"
		&"bite": return "растерзан"
		&"fire": return "сгорел"
		&"food", &"poison": return "отравление"
		&"explosion": return "взрыв"
		_: return "погиб"

func _draw_compass() -> void:
	var c := _compass
	var w := c.size.x
	var h := c.size.y
	c.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.28))
	if player == null or not is_instance_valid(player):
		return
	var d := Vector3(0, 0, -1)
	if player.has_method(&"get_look_dir"):
		d = player.call(&"get_look_dir") as Vector3
	# Курс: 0 — север (−Z), по часовой.
	var heading := rad_to_deg(atan2(d.x, -d.z))
	var f := UITheme.font(true)
	var half_fov := 90.0
	for deg in range(0, 360, 15):
		var rel := wrapf(float(deg) - heading, -180.0, 180.0)
		if absf(rel) > half_fov:
			continue
		var x := w * 0.5 + rel / half_fov * w * 0.5
		var label := ""
		match deg:
			0: label = "С"
			90: label = "В"
			180: label = "Ю"
			270: label = "З"
			45: label = "СВ"
			135: label = "ЮВ"
			225: label = "ЮЗ"
			315: label = "СЗ"
		if label != "":
			var big := label.length() == 1
			c.draw_string(f, Vector2(x - (7 if big else 10), h - 7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15 if big else 11,
				UITheme.ACCENT if label == "С" else Color(1, 0.97, 0.9, 0.9 if big else 0.6))
		else:
			c.draw_line(Vector2(x, h - 8), Vector2(x, h - 3), Color(1, 1, 1, 0.45), 1.0)
	# Свой флаг на компасе.
	var pteam := int(player.get(&"team")) if player.get(&"team") != null else 0
	if pteam < Game.teams.size() and Game.teams[pteam].flag_placed and Game.teams[pteam].flag_alive:
		var fp := Game.teams[pteam].flag_pos - player.global_position
		var fdeg := rad_to_deg(atan2(fp.x, -fp.z))
		var rel := clampf(wrapf(fdeg - heading, -180.0, 180.0), -half_fov, half_fov)
		var x := w * 0.5 + rel / half_fov * w * 0.5
		c.draw_colored_polygon(PackedVector2Array([Vector2(x - 5, 0), Vector2(x + 5, 0), Vector2(x, 7)]), Game.team_color(pteam))
	c.draw_line(Vector2(w * 0.5, 0), Vector2(w * 0.5, h), Color(1, 1, 1, 0.8), 1.0)
