extends Node3D
## Морские коньки в лугах морской травы (v5.2, агент K): клетка рифа (ReefLife) ставит
## 1–2 пары; конёк держится хвостом за стебель (SeaCritter.cling — клип grip, кормёжка и
## взгляды — из пака tools/seahorse). Тикают только около камеры; клетка уходит — и коньки.

const RANGE := 45.0
var critters: Array[SeaCritter] = []
var _sea: Object = null

func setup(p_sea: Object, spots: Array[Vector3], seed_i: int) -> void:
	_sea = p_sea
	var sp := OceanRoster.species("seahorse")
	if sp.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i
	for s in spots:
		for k in 2:
			var off := Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5))
			var stem := s + off + Vector3.UP * rng.randf_range(0.12, 0.3)   # ниже верхушек травы
			var c := SeaCritter.make(sp, _sea, stem + Vector3.UP * 0.05, seed_i + critters.size() * 31)
			if c == null:
				continue
			add_child(c)
			c.global_position = stem + Vector3.UP * 0.05
			var face := Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1)).normalized()
			c.cling(stem, face)
			critters.append(c)

func _physics_process(dt: float) -> void:
	if critters.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(critters[0].global_position) > RANGE:
		for c in critters:
			c.visible = false
		return
	for c in critters:
		if is_instance_valid(c):
			c.visible = true
			c.tick(dt)
