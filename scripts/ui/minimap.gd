class_name Minimap
extends Control
## Карта архипелага сверху: рельеф (снимается с world.height_at в фоне),
## игрок-стрелка, союзники, флаги (чужие — после того как их увидел),
## мосты-плоты. Режим mini — окно вокруг игрока; full — весь архипелаг (M).

const RES := 256
const MINI_SPAN := 420.0 # метров по ширине мини-карты
const DISCOVER_DIST := 170.0

var full := false
var player: Node3D = null

var _tex: ImageTexture = null
var _img: Image = null
var _bounds := Rect2()
var _islands: Array[Dictionary] = []
var _task := -1
var _discovered: Dictionary = {} # team → true
var _bridges: PackedVector3Array = PackedVector3Array()
var _bridge_t := 0.0
var _world: Node = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func _world_node() -> Node:
	if _world == null or not is_instance_valid(_world):
		_world = get_tree().get_first_node_in_group(&"world")
	return _world

func _start_bake() -> void:
	var w := _world_node()
	if w == null or not w.has_method(&"islands"):
		return
	_islands.clear()
	var r := Rect2()
	var first := true
	for I: Dictionary in w.call(&"islands"):
		_islands.append(I)
		var c: Vector2 = I.center
		var rad := float(I.radius) + 40.0
		var ir := Rect2(c - Vector2(rad, rad), Vector2(rad, rad) * 2.0)
		r = ir if first else r.merge(ir)
		first = false
	if first:
		return
	var side := maxf(r.size.x, r.size.y) + 80.0
	_bounds = Rect2(r.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
	_img = Image.create(RES, RES, false, Image.FORMAT_RGBA8)
	_task = WorkerThreadPool.add_task(_bake.bind(w), false, "minimap")

func _bake(w: Node) -> void:
	var wl := 0.0
	var step := _bounds.size.x / float(RES)
	for py in RES:
		for px in RES:
			var x := _bounds.position.x + (px + 0.5) * step
			var z := _bounds.position.y + (py + 0.5) * step
			var h := float(w.call(&"height_at", x, z))
			_img.set_pixel(px, py, color_for(h - wl))

static func color_for(h: float) -> Color:
	if h < -6.0:
		return Color(0.05, 0.17, 0.27, 0.92)
	if h < -1.5:
		return Color(0.07, 0.29, 0.38, 0.92).lerp(Color(0.05, 0.17, 0.27, 0.92), clampf((-h - 1.5) / 4.5, 0.0, 1.0))
	if h < 0.0:
		return Color(0.2, 0.5, 0.5, 0.95)
	if h < 1.6:
		return Color(0.82, 0.76, 0.56)
	if h < 22.0:
		return Color(0.27, 0.45, 0.2).lerp(Color(0.2, 0.33, 0.16), clampf(h / 22.0, 0.0, 1.0))
	return Color(0.45, 0.43, 0.4).lerp(Color(0.7, 0.68, 0.64), clampf((h - 22.0) / 40.0, 0.0, 1.0))

func is_baked() -> bool:
	return _tex != null

func _process(delta: float) -> void:
	if _task < 0 and _tex == null and _img == null:
		_start_bake()
	elif _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_tex = ImageTexture.create_from_image(_img)
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(&"player") as Node3D
	if player and is_instance_valid(player):
		var pteam := int(player.get(&"team")) if player.get(&"team") != null else 0
		for t in Game.teams:
			if t.flag_placed and not _discovered.has(t.id):
				if t.id == pteam or player.global_position.distance_to(t.flag_pos) < DISCOVER_DIST:
					_discovered[t.id] = true
	_bridge_t -= delta
	if _bridge_t <= 0.0:
		_bridge_t = 1.0
		_collect_bridges()
	if is_visible_in_tree():
		queue_redraw()

func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

func discover(team: int) -> void:
	_discovered[team] = true

func is_discovered(team: int) -> bool:
	return _discovered.has(team)

func _collect_bridges() -> void:
	_bridges.clear()
	for n in get_tree().get_nodes_in_group(&"buildable"):
		if n is Node3D and n.get(&"def_id") != null:
			var id := StringName(n.get(&"def_id"))
			if id == &"raft" or String(id).contains("bridge"):
				_bridges.append((n as Node3D).global_position)

## Видимая область мира (x,z) для текущего режима.
func view_rect() -> Rect2:
	if full or player == null or not is_instance_valid(player):
		return _bounds if _bounds.size.x > 0.0 else Rect2(-600, -600, 1200, 1200)
	var p := Vector2(player.global_position.x, player.global_position.z)
	var span := Vector2(MINI_SPAN, MINI_SPAN * size.y / maxf(1.0, size.x))
	return Rect2(p - span * 0.5, span)

func world_to_map(x: float, z: float, vr: Rect2) -> Vector2:
	return Vector2((x - vr.position.x) / vr.size.x * size.x, (z - vr.position.y) / vr.size.y * size.y)

func _draw() -> void:
	var vr := view_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.13, 0.2, 0.9))
	if _tex and _bounds.size.x > 0.0:
		# Участок текстуры, попадающий в окно.
		var tx := (vr.position - _bounds.position) / _bounds.size * float(RES)
		var ts := vr.size / _bounds.size * float(RES)
		draw_texture_rect_region(_tex, Rect2(Vector2.ZERO, size), Rect2(tx, ts))
	else:
		for I in _islands:
			var c: Vector2 = I.center
			draw_circle(world_to_map(c.x, c.y, vr), float(I.radius) / vr.size.x * size.x, Color(0.3, 0.45, 0.22))
	var f := UITheme.font(true)
	# Названия островов на большой карте.
	if full:
		for I in _islands:
			var c: Vector2 = I.center
			var nm := String(I.get("name", ""))
			if nm != "":
				var mp := world_to_map(c.x, c.y, vr)
				var tcol := Color(1, 0.97, 0.9, 0.85)
				var it := int(I.get("team", -1))
				if it >= 0 and it < Game.teams.size():
					tcol = Game.team_color(it).lightened(0.35)
				draw_string_outline(f, mp + Vector2(-90, 4), nm, HORIZONTAL_ALIGNMENT_CENTER, 180, 11, 3, Color(0, 0, 0, 0.7))
				draw_string(f, mp + Vector2(-90, 4), nm, HORIZONTAL_ALIGNMENT_CENTER, 180, 11, tcol)
	# Мосты.
	for b in _bridges:
		draw_rect(Rect2(world_to_map(b.x, b.z, vr) - Vector2(2, 2), Vector2(4, 4)), Color(0.55, 0.38, 0.2))
	# Метки модулей (SUPPLY: ящики спонсоров, ожидаемый сброс) — узлы группы map_markers.
	for mn in get_tree().get_nodes_in_group(&"map_markers"):
		if mn.has_method(&"map_markers"):
			for mk: Dictionary in mn.call(&"map_markers", player):
				_draw_marker(mk, vr, f)
	# Союзники.
	var pteam := int(player.get(&"team")) if player and is_instance_valid(player) and player.get(&"team") != null else 0
	if pteam >= 0 and pteam < Game.teams.size():
		for m in Game.teams[pteam].members:
			if m != player and m is Node3D and Game.is_alive(m):
				var mp := world_to_map((m as Node3D).global_position.x, (m as Node3D).global_position.z, vr)
				draw_circle(mp, 3.5, Game.team_color(pteam).lightened(0.3))
	# Флаги.
	for t in Game.teams:
		if not t.flag_placed or not _discovered.has(t.id):
			continue
		var mp := world_to_map(t.flag_pos.x, t.flag_pos.z, vr)
		var col := Game.team_color(t.id)
		if not Rect2(Vector2(-8, -8), size + Vector2(16, 16)).has_point(mp):
			continue
		draw_line(mp + Vector2(-3, 7), mp + Vector2(-3, -9), Color(0.15, 0.1, 0.05), 2.0)
		if t.flag_alive:
			var blink := Game.is_flag_under_attack(t.id) and int(Time.get_ticks_msec() / 250) % 2 == 0
			draw_colored_polygon(PackedVector2Array([mp + Vector2(-2, -9), mp + Vector2(8, -6), mp + Vector2(-2, -3)]), Color.WHITE if blink else col)
		else:
			draw_line(mp + Vector2(-6, -6), mp + Vector2(6, 6), UITheme.DANGER, 2.0)
			draw_line(mp + Vector2(6, -6), mp + Vector2(-6, 6), UITheme.DANGER, 2.0)
	# Игрок — стрелка по взгляду.
	if player and is_instance_valid(player):
		var mp := world_to_map(player.global_position.x, player.global_position.z, vr)
		var d := Vector3(0, 0, -1)
		if player.has_method(&"get_look_dir"):
			d = player.call(&"get_look_dir") as Vector3
		var dir := Vector2(d.x, d.z).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2(0, -1)
		var side := Vector2(-dir.y, dir.x)
		var pts := PackedVector2Array([mp + dir * 8.0, mp - dir * 5.0 + side * 5.0, mp - dir * 2.0, mp - dir * 5.0 - side * 5.0])
		draw_colored_polygon(pts, Color(1, 0.97, 0.88))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.7), 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), UITheme.LINE, false, 1.0)
	# Север.
	draw_string_outline(f, Vector2(size.x * 0.5 - 6, 14), "С", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.7))
	draw_string(f, Vector2(size.x * 0.5 - 6, 14), "С", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.ACCENT)

## Метка {pos, color, kind: crate|falling|predicted, label}: ящик — квадрат с крестом
## строп, ожидаемый сброс — пульсирующее пунктирное кольцо.
func _draw_marker(mk: Dictionary, vr: Rect2, f: Font) -> void:
	var pos: Vector3 = mk.get("pos", Vector3.ZERO)
	var mp := world_to_map(pos.x, pos.z, vr)
	var col: Color = mk.get("color", Color.WHITE)
	var edge := not Rect2(Vector2(6, 6), size - Vector2(12, 12)).has_point(mp)
	mp = mp.clamp(Vector2(6, 6), size - Vector2(6, 6))
	match StringName(mk.get("kind", &"crate")):
		&"predicted":
			var r := 9.0 + 2.0 * sin(Time.get_ticks_msec() * 0.006)
			for k in 12:
				var a0 := TAU * k / 12.0
				draw_arc(mp, r, a0, a0 + TAU / 24.0, 4, col, 2.0, true)
		_:
			var s := 5.0 if not edge else 4.0
			draw_rect(Rect2(mp - Vector2(s, s), Vector2(s, s) * 2.0), Color(0, 0, 0, 0.75))
			draw_rect(Rect2(mp - Vector2(s, s) + Vector2(1, 1), Vector2(s, s) * 2.0 - Vector2(2, 2)), col)
			if StringName(mk.get("kind", &"")) == &"falling" and int(Time.get_ticks_msec() / 300) % 2 == 0:
				draw_arc(mp, s + 4.0, 0.0, TAU, 16, col, 1.5, true)
	var lb := String(mk.get("label", ""))
	if full and lb != "":
		draw_string_outline(f, mp + Vector2(-60, -10), lb, HORIZONTAL_ALIGNMENT_CENTER, 120, 10, 3, Color(0, 0, 0, 0.7))
		draw_string(f, mp + Vector2(-60, -10), lb, HORIZONTAL_ALIGNMENT_CENTER, 120, 10, col.lightened(0.3))
