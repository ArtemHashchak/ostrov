class_name SupplyPlane
extends Node3D
## Самолёт спонсоров: пролетает над архипелагом по прямой, над точкой сброса
## выпускает ящик с рампы и улетает. Звук мотора — процедурный (SupplyFx.Motor).

signal released(crate: SupplyCrate)

const SPEED := 70.0

var drop_point := Vector3.ZERO   # где выпустить ящик (высота — полёта)
var heading := Vector3.FORWARD    # горизонтальное направление полёта
var lead := 900.0                 # с какого расстояния начинаем
var crate: SupplyCrate            # готовый ящик (ещё не в дереве)
var crate_parent: Node

var _model: Node3D
var _props: Array[Node3D] = []
var _done := false
var _flown := 0.0

func _ready() -> void:
	add_to_group(&"supply_planes")
	_model = Node3D.new()
	add_child(_model)
	SupplyModels.plane(_model)
	HeldModels._no_shadows(_model)
	for n in [&"PropL", &"PropR"]:
		var pr := _model.get_node_or_null(NodePath(String(n))) as Node3D
		if pr:
			_props.append(pr)
	heading = Vector3(heading.x, 0.0, heading.z).normalized()
	global_position = drop_point - heading * lead
	look_at(global_position + heading, Vector3.UP)
	var m := SupplyFx.Motor.new()
	m.kind = &"plane"
	add_child(m)

func _process(delta: float) -> void:
	var step := heading * SPEED * delta
	global_position += step
	_flown += step.length()
	for pr in _props:
		pr.rotate_object_local(Vector3.FORWARD, delta * 40.0)
	# лёгкий крен/тангаж — живее
	_model.rotation = Vector3(sin(_flown * 0.004) * 0.03, 0.0, sin(_flown * 0.003) * 0.05)
	# рампа в 6,4 м за центром самолёта — выпускаем, когда над точкой проходит она
	if not _done and (global_position - drop_point).dot(heading) >= 6.4:
		_done = true
		_release()
	if _flown > lead * 2.0 + 200.0:
		queue_free()

func _release() -> void:
	if crate == null:
		return
	var ramp := _model.find_child("Ramp", true, false) as Node3D
	# точно над точкой сброса (кадр мог «перескочить» её на десятки метров)
	var at := Vector3(drop_point.x, (ramp.global_position.y if ramp else drop_point.y) - 0.5, drop_point.z)
	crate_parent.add_child(crate)
	crate.global_position = at
	released.emit(crate)
