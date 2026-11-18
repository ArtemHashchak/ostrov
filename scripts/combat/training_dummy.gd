class_name TrainingDummy
extends StaticBody3D
## Тренировочный манекен (соломенное чучело на столбе) — для тестов и стрельбища.
## В группе characters: зоны попадания считаются как у персонажа (голова/тело/ноги).

var hits: Array[Dictionary] = [] # {amount, kind, source}
var total := 0.0

func _ready() -> void:
	add_to_group(&"characters")
	add_to_group(&"dummies")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	var straw := HeldModels.pbr("ThatchedRoof001A", Vector3(1.0, 1.0, 1.0), Color(0.95, 0.85, 0.6))
	var sack := CombatModels.mat("cloth")
	var wood := CombatModels.mat("wood")
	CombatModels.rod(self, Vector3(0, -0.2, 0), Vector3(0, 1.95, 0), 0.045, wood, 10)
	# ноги (соломенные снопы), туловище, руки-перекладина, голова-мешок
	for x in [-0.12, 0.12]:
		var lp := PackedVector3Array([Vector3(x, 0.05, 0), Vector3(x, 0.8, 0)])
		CombatModels.mesh(self, CombatModels.loft(lp, [Vector2(0.075, 0.075), Vector2(0.095, 0.095)], Vector3.FORWARD, 12, 1.0), straw)
	var bp := PackedVector3Array([Vector3(0, 0.8, 0), Vector3(0, 1.1, 0), Vector3(0, 1.42, 0), Vector3(0, 1.52, 0)])
	CombatModels.mesh(self, CombatModels.loft(bp, [Vector2(0.2, 0.2), Vector2(0.24, 0.24), Vector2(0.25, 0.25), Vector2(0.12, 0.12)], Vector3.FORWARD, 14, 1.0), straw)
	CombatModels.rod(self, Vector3(-0.6, 1.36, 0), Vector3(0.6, 1.36, 0), 0.035, wood, 8)
	for x in [-0.45, 0.45]:
		var ap := PackedVector3Array([Vector3(x * 0.5, 1.36, 0), Vector3(x, 1.36, 0)])
		CombatModels.mesh(self, CombatModels.loft(ap, [Vector2(0.07, 0.07), Vector2(0.06, 0.06)], Vector3.FORWARD, 10, 1.0), straw)
	HeldModels._sphere(self, 0.15, sack, Vector3(0, 1.67, 0), Vector3(1.0, 1.15, 1.0), 14)
	CombatModels.rod(self, Vector3(-0.1, 1.55, 0), Vector3(0.1, 1.55, 0), 0.012, CombatModels.mat("rope"), 6).rotation_degrees.y = 0.0

func get_eye_position() -> Vector3:
	return global_position + Vector3.UP * 1.66

func apply_damage(amount: float, source: Node = null, kind: StringName = &"melee") -> void:
	hits.append({"amount": amount, "kind": kind, "source": source})
	total += amount
	var tw := create_tween()
	rotation.z = randf_range(-0.04, 0.04)
	tw.tween_property(self, "rotation:z", 0.0, 0.4)
