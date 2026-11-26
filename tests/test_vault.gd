## test-timeout: 400
extends TestCase
## Перелезание (V5): стенка 1,1 м (тонкая) — прыжок у неё = перелезть на ту сторону;
## ящик 0,9 м толщиной 2 м — забраться наверх; стена 1,9 м (выше груди) — не перелезть;
## мягкие растения (группа soft_plant) замедляют.

var p: Player

func _init() -> void:
	timeout_sec = 400.0

func box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	b.add_child(mi)
	scene.add_child(b)
	b.global_position = pos + Vector3.UP * size.y * 0.5
	return b

## Ровная площадка: плоский пол-плита под тестом (чтобы рельеф не мешал).
func floor_at(c: Vector3) -> void:
	box(c + Vector3.DOWN * 0.3, Vector3(30, 0.3, 30))

func place(pos: Vector3, yaw: float) -> void:
	p.global_position = pos + Vector3.UP * 0.05
	p.velocity = Vector3.ZERO
	p.set_look(yaw, 0.0)
	await wait(0.5)

func run() -> void:
	await wait(1.0)
	p = get_tree().get_first_node_in_group(&"player") as Player
	check(p != null, "игрок есть")
	if p == null:
		return
	Engine.max_physics_steps_per_frame = 16
	var c := p.global_position + Vector3(0, 40, 0) # площадка в воздухе — без рельефа и воды
	floor_at(c)
	# yaw=0 → взгляд −Z
	# 1) тонкая стенка 1,1 м
	box(c + Vector3(-6, 0, -2.0), Vector3(3, 1.1, 0.3))
	await place(c + Vector3(-6, 0, 0), 0.0)
	Input.action_press(&"move_forward")
	await wait(0.25)
	await tap(&"jump")
	await wait(0.2)
	var was_vaulting := p.vaulting
	await wait(0.8)
	Input.action_release(&"move_forward")
	await wait(0.3)
	check(was_vaulting, "у стенки 1,1 м прыжок = перелезание")
	check(p.global_position.z < c.z - 2.3 and p.global_position.y < c.y + 0.4, "оказался на той стороне стенки (z=%.2f)" % (p.global_position.z - c.z))
	# 2) толстый ящик 0,9 м — наверх
	box(c + Vector3(0, 0, -3.0), Vector3(3, 0.9, 2.0))
	await place(c + Vector3(0, 0, 0), 0.0)
	Input.action_press(&"move_forward")
	await wait(0.4)
	await tap(&"jump")
	await wait(0.9)
	Input.action_release(&"move_forward")
	await wait(0.3)
	check(p.global_position.y > c.y + 0.8, "на толстый ящик 0,9 м — забрался наверх (y=%.2f)" % (p.global_position.y - c.y))
	# 3) стена 1,9 м — нельзя
	box(c + Vector3(6, 0, -1.6), Vector3(3, 1.9, 0.3))
	await place(c + Vector3(6, 0, 0), 0.0)
	Input.action_press(&"move_forward")
	await wait(0.3)
	await tap(&"jump")
	await wait(0.2)
	var v3 := p.vaulting
	await wait(1.0)
	Input.action_release(&"move_forward")
	check(not v3 and p.global_position.z > c.z - 1.6, "стену 1,9 м не перелезть (выше груди)")
	# 4) мягкий куст замедляет
	await place(c + Vector3(12, 0, 0), 0.0)
	var a := Area3D.new()
	a.add_to_group(&"soft_plant")
	a.set_meta(&"speed_mul", 0.55)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 2.0
	cs.shape = sh
	a.add_child(cs)
	scene.add_child(a)
	a.global_position = c + Vector3(12, 1, 0)
	await wait(0.4)
	check(absf(p._env_speed() - 0.55) < 0.01, "в кусте скорость ×%.2f" % p._env_speed())
	a.queue_free()
	await wait(0.3)
	check(p._env_speed() > 0.99, "вне куста скорость обычная")
