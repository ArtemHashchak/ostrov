class_name SandboxMap
extends Control
## Карта «Полигона» сверху: рельеф, зоны с подписями, игрок. Клик — точка мира.

signal clicked(world_xz: Vector2)

const RES := 320

var world: World
var zones: SandboxZones
var player: Node3D
var _tex: ImageTexture
var _bounds := Rect2()

func _init() -> void:
	custom_minimum_size = Vector2(360, 360)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func setup(w: World, z: SandboxZones, p: Node3D) -> void:
	world = w
	zones = z
	player = p
	_bake()

func _bake() -> void:
	var b := world.arch.bounds
	var side := maxf(b.size.x, b.size.y)
	_bounds = Rect2(b.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
	var img := Image.create(RES, RES, false, Image.FORMAT_RGB8)
	for j in RES:
		for i in RES:
			var q := _bounds.position + Vector2((i + 0.5) / RES, (j + 0.5) / RES) * side
			var h := world.height_at(q.x, q.y)
			var c: Color
			if h < -6.0:
				c = Color(0.07, 0.2, 0.32)
			elif h < 0.0:
				c = Color(0.07, 0.2, 0.32).lerp(Color(0.2, 0.52, 0.56), clampf((h + 6.0) / 6.0, 0.0, 1.0))
			elif h < 1.4:
				c = Color(0.85, 0.79, 0.6)
			else:
				c = Color(0.36, 0.5, 0.26).lerp(Color(0.5, 0.48, 0.36), clampf((h - 1.4) / 8.0, 0.0, 1.0))
			if world.lake_level_at(q.x, q.y) > -INF and h < world.lake_level_at(q.x, q.y):
				c = Color(0.25, 0.55, 0.65)
			img.set_pixel(i, j, c)
	_tex = ImageTexture.create_from_image(img)

func _square() -> Rect2:
	var s := minf(size.x, size.y)
	return Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s))

func to_screen(xz: Vector2) -> Vector2:
	var r := _square()
	return r.position + (xz - _bounds.position) / _bounds.size * r.size

func to_world(p: Vector2) -> Vector2:
	var r := _square()
	return _bounds.position + (p - r.position) / r.size * _bounds.size

func _draw() -> void:
	if _tex == null:
		return
	var r := _square()
	draw_texture_rect(_tex, r, false)
	draw_rect(r, UITheme.LINE, false, 1.0)
	var font := UITheme.font(true)
	if zones:
		for id: StringName in zones.order:
			var pt: Dictionary = zones.points[id]
			var p3: Vector3 = pt.pos
			var sp := to_screen(Vector2(p3.x, p3.z))
			draw_circle(sp, 5.0, UITheme.ACCENT)
			draw_circle(sp, 5.0, Color(0, 0, 0, 0.6), false, 1.5)
			draw_string_outline(font, sp + Vector2(8, 5), String(pt.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.8))
			draw_string(font, sp + Vector2(8, 5), String(pt.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT)
	if player and is_instance_valid(player):
		var pp := to_screen(Vector2(player.global_position.x, player.global_position.z))
		var yaw: float = float(player.get(&"_yaw")) if player.get(&"_yaw") != null else 0.0
		var f := Vector2(-sin(yaw), -cos(yaw))
		var rt := Vector2(-f.y, f.x)
		draw_colored_polygon(PackedVector2Array([pp + f * 10.0, pp - f * 6.0 + rt * 6.0, pp - f * 6.0 - rt * 6.0]),
				Color(0.95, 0.3, 0.25))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var p := (event as InputEventMouseButton).position
		if _square().has_point(p):
			clicked.emit(to_world(p))
			accept_event()

func _process(_d: float) -> void:
	if is_visible_in_tree():
		queue_redraw()
