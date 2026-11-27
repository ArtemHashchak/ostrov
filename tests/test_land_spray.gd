extends TestCase
## v5.1 (агент H): приземление после прыжка — вместо следов на 0,5 с появлялся «квадрат»
## (частицы выброса песка были квадами 1×1 м). Проверка: песчинки мелкие, отпечатки прыжка
## попадают в карту сразу (перерисовка в том же такте).

func _init() -> void:
	scene_path = "res://tests/empty_stage.tscn"

class FakeWorld extends Node3D:
	func height_at(_x: float, _z: float) -> float:
		return 0.0

func run() -> void:
	var fw := FakeWorld.new()
	scene.add_child(fw)
	var st: Node = SandTracks
	st.set(&"_world", fw)
	var n0: int = (st.get(&"prints") as Array).size()
	st.set(&"_redraw_t", 0.0)
	st.call(&"_jump_pair", Vector2(0, 0), Vector2(0, -1), 7, 1.0)   # FOOT_HEEL — приземление
	var n1: int = (st.get(&"prints") as Array).size()
	check(n1 == n0 + 2, "приземление — пара отпечатков сразу (%d → %d)" % [n0, n1])
	check(float(st.get(&"_redraw_t")) >= 1.0 / 8.0 - 1e-4, "карта следов перерисуется в ближайшем кадре")
	var parts: Array = []
	for c in fw.get_children():
		if c is CPUParticles3D:
			parts.append(c)
	check(parts.size() >= 1, "выброс песка создан")
	for p: CPUParticles3D in parts:
		var q := p.mesh as QuadMesh
		check(q != null and q.size.x <= 0.05 and q.size.y <= 0.05, "песчинка мелкая (%.3f м), без квадрата" % (q.size.x if q else -1.0))
		check(p.scale_amount_max * (q.size.x if q else 1.0) <= 0.08, "даже с масштабом частица меньше 8 см")
	st.set(&"_world", null)
