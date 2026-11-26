extends Node
## След на воде (v5, агент D; автозагрузка WaterWakes): бурун у носа и расходящийся след за плотом,
## рябь кругами вокруг пловца, всплески. Устроено как SandTracks: карта RG 512² на окно 64×64 м вокруг
## камеры рисуется на GPU (SubViewport + 2D-холст), океан (ocean.gdshader) читает её глобально:
##   R — пена/взбитая вода (бурун, след, всплеск), G — рябь (кольца от пловца и капель).
## Источники: персонажи в воде (group characters, swimming == true), плоты (group raft_deck),
## всё, что в группе water_movers (лодки, крупные звери у поверхности). API для разовых всплесков:
## WaterWakes.splash(pos, strength).

const RES := 512
const SIZE := 64.0
const LIFE := 7.0               # с — сколько живёт точка следа
const MAX_PTS := 900
const DROP_DT := 0.08           # с между точками следа одного источника
const REDRAW_HZ := 20.0

var enabled := true
var origin := Vector2.ZERO
## точки: [x, z, возраст, сила, ширина, вид(0 след/1 кольцо/2 бурун), dirx, dirz]
var pts: Array = []
var _vp: SubViewport
var _canvas: Node2D
var _blob: ImageTexture
var _ring: ImageTexture
var _src := {}                  # instance_id -> {last: Vector3, t: float, ring_t: float}
var _redraw_t := 0.0
var _world: Node = null

func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(RES, RES)
	_vp.disable_3d = true
	_vp.transparent_bg = true
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_canvas = Node2D.new()
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # следы складываются (пересечения ярче)
	_canvas.material = cm
	_vp.add_child(_canvas)
	add_child(_vp)
	_canvas.draw.connect(_on_draw)
	_build_textures()
	RenderingServer.global_shader_parameter_set(&"wake_map", _vp.get_texture())
	_set_rect(false)

func _set_rect(on: bool) -> void:
	RenderingServer.global_shader_parameter_set(&"wake_rect", Vector4(origin.x, origin.y, SIZE, 1.0 if on else 0.0))

## Разовый всплеск (падение в воду, выстрел по воде, прыжок рыбы): пена + кольцо.
func splash(pos: Vector3, strength := 1.0) -> void:
	_add(Vector2(pos.x, pos.z), clampf(strength, 0.1, 2.0), 0.6 + 0.5 * strength, 2, Vector2.ZERO)
	_add(Vector2(pos.x, pos.z), clampf(strength, 0.1, 2.0), 0.4, 1, Vector2.ZERO)

func clear() -> void:
	pts.clear()
	_src.clear()

func _add(p: Vector2, s: float, width: float, kind: int, dir: Vector2) -> void:
	pts.append([p.x, p.y, 0.0, s, width, kind, dir.x, dir.y])
	if pts.size() > MAX_PTS:
		pts.remove_at(0)

func _process(dt: float) -> void:
	if not enabled:
		return
	if _world == null or not is_instance_valid(_world):
		_world = get_tree().get_first_node_in_group(&"world")
		if _world == null:
			_set_rect(false)
			return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_recenter(Vector2(cam.global_position.x, cam.global_position.z))
	_track(dt)
	var keep: Array = []
	for p: Array in pts:
		p[2] = float(p[2]) + dt
		if float(p[2]) < LIFE:
			keep.append(p)
	pts = keep
	_redraw_t += dt
	if _redraw_t >= 1.0 / REDRAW_HZ and not pts.is_empty():
		_redraw_t = 0.0
		_canvas.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

func _recenter(c: Vector2) -> void:
	var rel := c - origin
	var m := SIZE * 0.3
	if rel.x > m and rel.y > m and rel.x < SIZE - m and rel.y < SIZE - m:
		return
	var px := SIZE / RES
	var o := c - Vector2(SIZE, SIZE) * 0.5
	origin = Vector2(floorf(o.x / px) * px, floorf(o.y / px) * px)
	_set_rect(true)
	# как в SandTracks: перерисовка в том же кадре, что и новый прямоугольник
	_redraw_t = 0.0
	_canvas.queue_redraw()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

func _water_y() -> float:
	return float(_world.water_level()) if _world.has_method(&"water_level") else 0.0

func _track(dt: float) -> void:
	var nodes: Array = []
	for n in get_tree().get_nodes_in_group(&"characters"):
		if n.get("swimming") == true:
			nodes.append([n, 0.45, false])
	for n in get_tree().get_nodes_in_group(&"raft_deck"):
		nodes.append([n, 1.4, true])
	for n in get_tree().get_nodes_in_group(&"water_movers"):
		nodes.append([n, float(n.get_meta(&"wake_width", 1.0)), true])
	var seen := {}
	var wl := _water_y()
	for e in nodes:
		var n: Node3D = e[0] as Node3D
		if n == null or not is_instance_valid(n):
			continue
		var id := n.get_instance_id()
		seen[id] = true
		var g := n.global_position
		var st: Dictionary = _src.get(id, {})
		if st.is_empty():
			_src[id] = {"last": g, "t": 0.0, "ring_t": 0.0}
			continue
		st.t = float(st.t) + dt
		st.ring_t = float(st.ring_t) + dt
		if absf(g.y - wl) > 2.5:
			st.last = g
			continue
		var d := Vector2(g.x - st.last.x, g.z - st.last.z)
		var w: float = float(e[1])
		if float(st.t) >= DROP_DT:
			var sp := d.length() / maxf(float(st.t), 1e-3)
			st.t = 0.0
			st.last = g
			if sp > 0.25:
				var dir := d.normalized()
				var k := clampf(sp / 3.0, 0.2, 1.3)
				# след за кормой (расходится со временем) и бурун у носа
				_add(Vector2(g.x, g.z) - dir * w * 0.5, k, w, 0, dir)
				if bool(e[2]) and sp > 0.8:
					_add(Vector2(g.x, g.z) + dir * w * 0.55, k * 0.8, w * 0.7, 2, dir)
		# пловец даже стоя на месте даёт кольца ряби (руки/ноги работают)
		if not bool(e[2]) and float(st.ring_t) > 0.55:
			st.ring_t = 0.0
			_add(Vector2(g.x, g.z), 0.7, 0.35, 1, Vector2.ZERO)
	for id in _src.keys():
		if not seen.has(id):
			_src.erase(id)

func _on_draw() -> void:
	var px := SIZE / RES
	for p: Array in pts:
		var c := Vector2((float(p[0]) - origin.x) / px, (float(p[1]) - origin.y) / px)
		if c.x < -40 or c.y < -40 or c.x > RES + 40 or c.y > RES + 40:
			continue
		var age := float(p[2])
		var life_k := 1.0 - age / LIFE
		var s := float(p[3])
		var kind := int(p[5])
		match kind:
			1:
				# кольцо: растёт ~0.9 м/с, гаснет за 2.5 с
				var r := (float(p[4]) + age * 0.9) / px
				var a := clampf(1.0 - age / 2.5, 0.0, 1.0) * s
				if a > 0.01:
					_canvas.draw_texture_rect(_ring, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(0, a, 0, 1))
			_:
				# пена: след расходится (ширина растёт), бурун/всплеск — короче и ярче
				var grow := 1.0 + age * (0.55 if kind == 0 else 1.4)
				var r2 := float(p[4]) * grow / px
				var a2 := s * life_k * life_k * (1.0 if kind == 0 else clampf(1.0 - age / 1.6, 0.0, 1.0))
				if a2 > 0.01:
					_canvas.draw_texture_rect(_blob, Rect2(c - Vector2(r2, r2), Vector2(r2, r2) * 2.0), false, Color(a2, a2 * 0.3, 0, 1))

func _build_textures() -> void:
	var n := 64
	var b := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var r := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var q := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var d := q.length()
			var blob := clampf(1.0 - d, 0.0, 1.0)
			blob = blob * blob * (3.0 - 2.0 * blob)
			b.set_pixel(x, y, Color(1, 1, 1, blob))
			var ring := clampf(1.0 - absf(d - 0.85) / 0.12, 0.0, 1.0)
			r.set_pixel(x, y, Color(1, 1, 1, ring * ring))
	_blob = ImageTexture.create_from_image(b)
	_ring = ImageTexture.create_from_image(r)
