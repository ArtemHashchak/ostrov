class_name SeaPush
extends RefCounted
## Расталкивание водорослей пловцами — одна реализация для всех (риф, полигон,
## паки моделей). Шейдер подключает res://shaders/sea_push.gdshaderinc, материал
## регистрируется SeaPush.register(mat); Sea каждый кадр зовёт SeaPush.update()
## с ближайшими к камере пловцами (до 4). Без глобальных юниформ — не нужна запись
## в project.godot, работает в любом рендере.

const MAX := 4
const RADIUS := 1.5       # радиус отгибания вокруг тела, м
static var _mats: Array[WeakRef] = []
static var _last := PackedVector4Array()

static func register(mat: ShaderMaterial) -> void:
	for w in _mats:
		if w.get_ref() == mat:
			return
	_mats.append(weakref(mat))
	if _last.size() == MAX:
		mat.set_shader_parameter(&"push_pos", _last)

## points — мировые позиции пловцов (берутся ближайшие к origin).
static func update(points: Array[Vector3], origin: Vector3) -> void:
	points.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.distance_squared_to(origin) < b.distance_squared_to(origin))
	var arr := PackedVector4Array()
	arr.resize(MAX)
	for i in MAX:
		if i < points.size() and points[i].distance_to(origin) < 60.0:
			var p := points[i]
			arr[i] = Vector4(p.x, p.y, p.z, RADIUS)
		else:
			arr[i] = Vector4(0, 0, 0, 0)
	if arr == _last:
		return
	_last = arr
	var alive: Array[WeakRef] = []
	for w in _mats:
		var m := w.get_ref() as ShaderMaterial
		if m:
			m.set_shader_parameter(&"push_pos", arr)
			alive.append(w)
	_mats = alive

static func clear() -> void:
	_mats.clear()
	_last = PackedVector4Array()
