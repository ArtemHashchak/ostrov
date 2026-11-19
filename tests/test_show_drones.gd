extends TestCase
## Лор шоу: дроны-камеры (ShowDrones, модуль SUPPLY) — дрон ведёт игрока, держится
## сзади-сверху, объектив смотрит на игрока, следует за ним при перемещении.
## Возрождение — «дрон-медик» спускается к точке появления и улетает.

var p: Player

func _init() -> void:
	timeout_sec = 900.0

func look(at: Vector3) -> void:
	var d := at - p.get_eye_position()
	p.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))

func run() -> void:
	await wait(1.0)
	p = get_tree().get_first_node_in_group(&"player") as Player
	check(p != null, "игрок есть")
	if p == null:
		return
	p.inventory.clear()
	var sup := Supply.new()
	scene.add_child(sup)
	await wait(3.0)
	var sd := ShowDrones.instance()
	check(sd != null and sd.drones.size() == ShowDrones.MAX, "дроны созданы (%d)" % (sd.drones.size() if sd else 0))
	if sd == null:
		return
	var d := sd.drone_for(p)
	check(d != null and d.visible, "дрон ведёт игрока")
	if d == null:
		return
	var rel := d.global_position - p.global_position
	print("[drones] дрон %s игрок %s rel %s" % [str(d.global_position), str(p.global_position), str(rel)])
	check(rel.y > 2.5 and Vector2(rel.x, rel.z).length() > 3.0 and rel.length() < 12.0,
		"дрон сзади-сверху на расстоянии (%.1f м, высота %.1f)" % [rel.length(), rel.y])
	var gim := d.get_node(^"Gimbal") as Node3D
	var to := (p.global_position + Vector3.UP * 1.2 - gim.global_position).normalized()
	check(-gim.global_transform.basis.z.dot(to) > 0.95, "объектив смотрит на игрока")
	look(d.global_position)
	await wait(0.5)
	await shot("01_drone")
	# игрок отошёл на 20 м — дрон догоняет
	var p0 := p.global_position
	var np := Vector3(p0.x + 20.0, 0.0, p0.z)
	np.y = BuildEnv.height_at(np.x, np.z) + 0.1
	if np.y < BuildEnv.water_level() + 0.2:
		np = Vector3(p0.x - 20.0, 0.0, p0.z)
		np.y = BuildEnv.height_at(np.x, np.z) + 0.1
	p.global_position = np
	await wait(3.0)
	var rel2 := d.global_position - p.global_position
	check(rel2.length() < 12.0, "дрон догнал игрока (%.1f м)" % rel2.length())
	# крупный план дрона камерой теста
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.global_position = d.global_position + Vector3(1.2, 0.3, 1.2)
	cam.look_at(d.global_position)
	cam.make_current()
	await wait(0.3)
	await shot("02_drone_close")
	p.camera.make_current()
	cam.queue_free()
	# возрождение — дрон-медик
	p.respawn()
	await wait_frames(2)
	check(sd.medic_count == 1, "возрождение вызвало дрона-медика")
	var md := sd.get_node_or_null(^"MedicDrone") as Node3D
	check(md != null, "дрон-медик в сцене")
	await wait(1.15)
	if md and is_instance_valid(md):
		var rp := p.global_position
		look(md.global_position)
		await wait(0.1)
		check(md.global_position.distance_to(rp) < 5.0, "дрон-медик опустился к игроку (%.1f м)" % md.global_position.distance_to(rp))
		await shot("03_medic")
	await wait(3.5)
	check(sd.get_node_or_null(^"MedicDrone") == null, "дрон-медик улетел и удалён")
