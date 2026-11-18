class_name ItemIcons
extends Node
## Иконки предметов, отрендеренные из 3D-моделей (HeldModels) в отдельном
## SubViewport: реалистично и без готовых картинок. Кэш общий на игру.
## Использование: ItemIcons.request(host, id) → Texture2D (или null, пока рисуется);
## когда готово — сигнал icon_ready(id) у узла-рендерера.

signal icon_ready(id: StringName)

const SIZE := 96
static var cache: Dictionary = {} # id -> Texture2D
static var _inst: ItemIcons = null

var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _queue: Array[StringName] = []
var _busy := false

static func instance(host: Node) -> ItemIcons:
	if _inst and is_instance_valid(_inst):
		return _inst
	_inst = ItemIcons.new()
	_inst.name = "ItemIcons"
	host.get_tree().root.add_child.call_deferred(_inst)
	return _inst

## Иконка предмета; null — ещё рисуется (придёт icon_ready).
static func request(host: Node, id: StringName) -> Texture2D:
	if id == &"":
		return null
	if cache.has(id):
		return cache[id]
	var r := instance(host)
	if not r._queue.has(id):
		r._queue.append(id)
	return null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.72, 0.68)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.6
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 200, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(1.0, 0.9, 0.75)
	_vp.add_child(rim)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(_cam)

func _process(_d: float) -> void:
	if _busy or _queue.is_empty():
		return
	_render_next()

func _render_next() -> void:
	_busy = true
	var id: StringName = _queue.pop_front()
	for c in _pivot.get_children():
		c.queue_free()
	var model := HeldModels.build(id)
	_pivot.add_child(model)
	await get_tree().process_frame
	# Кадрируем по габаритам модели.
	var aabb := _aabb(model, Transform3D.IDENTITY)
	var size := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if size <= 0.0001:
		size = 0.2
	var center := aabb.get_center()
	_pivot.rotation = Vector3(deg_to_rad(-18.0), deg_to_rad(35.0), deg_to_rad(-30.0))
	center = _pivot.transform * center
	_cam.size = size * 1.25
	_cam.position = center + Vector3(0, 0, size * 3.0)
	_cam.look_at(center)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	if img:
		cache[id] = ImageTexture.create_from_image(img)
		icon_ready.emit(id)
	_busy = false

func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is VisualInstance3D:
		var a := t * (n as VisualInstance3D).get_aabb()
		out = a
		first = false
	for c in n.get_children():
		var ca := _aabb(c, t)
		if ca.size != Vector3.ZERO:
			out = ca if first else out.merge(ca)
			first = false
	return out
