extends TestCase
## Проба: модели SUPPLY крупным планом на берегу (ящик с парашютом, открытый ящик,
## предметы в ряд, дым, самолёт).
func _init() -> void:
	timeout_sec = 400.0

func look(p: Player, at: Vector3) -> void:
	var d := at - p.get_eye_position()
	p.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))

func run() -> void:
	await wait(1.0)
	var p := get_tree().get_first_node_in_group(&"player") as Player
	p.inventory.clear()
	SupplyItems.register()
	var gx := 47.0
	p.global_position = Vector3(gx, BuildEnv.height_at(gx, 0) + 0.1, 0)
	var eye := p.get_eye_position()
	# ящик под куполом на уровне глаз
	var c := SupplyCrate.new()
	c.tier = 1
	c.number = 7
	c.set_physics_process(false)
	scene.add_child(c)
	c.global_position = eye + Vector3(9.0, -3.2, -1.0)
	c.rotation.y = 0.5
	look(p, c.global_position + Vector3.UP * 2.5)
	await wait(1.0)
	await shot("chute")
	# ящик крупно (закрыт), потом открыт
	c.get_node(^"Parachute").visible = false
	c.global_position = Vector3(gx + 2.4, BuildEnv.height_at(gx + 2.4, 0.5), 0.5)
	c.rotation.y = PI * 0.5 + 0.3
	look(p, c.global_position + Vector3.UP * 0.2)
	await wait(0.5)
	await shot("crate")
	(c.get_node(^"Model/Lid") as Node3D).rotation.x = deg_to_rad(105.0)
	(c.get_node(^"Model/Straps") as Node3D).visible = false
	await wait(0.3)
	await shot("crate_open")
	c.queue_free()
	# предметы в ряд
	var ids: Array[StringName] = [&"rifle", &"shotgun", &"flare_gun", &"grenade", &"machete", &"chainsaw", &"gas_torch", &"gas_can",
		&"binoculars", &"flashlight", &"radio", &"fins", &"armor_vest", &"medkit", &"canned_food", &"rifle_ammo", &"shotgun_shell", &"flare", &"fuel_can"]
	var row := Node3D.new()
	scene.add_child(row)
	var base := eye + Vector3(1.3, -0.35, 0.0)
	for i in ids.size():
		var m := HeldModels.build(ids[i])
		row.add_child(m)
		var k := i % 10
		var r := i / 10
		m.global_position = base + Vector3(r * 0.5, -r * 0.25, -1.1 + k * 0.24)
		m.rotation = Vector3(0, PI * 0.5, 0) if ids[i] in [&"rifle", &"shotgun", &"chainsaw", &"machete"] else Vector3(0, -PI * 0.5, 0)
		if ids[i] in [&"rifle", &"shotgun", &"chainsaw"]:
			m.scale = Vector3.ONE * 0.45
	look(p, base + Vector3(0.2, -0.1, 0.0))
	await wait(0.5)
	await shot("items")
	row.queue_free()
	# самолёт
	var pl := Node3D.new()
	scene.add_child(pl)
	SupplyModels.plane(pl)
	pl.global_position = eye + Vector3(40, 12, -10)
	pl.rotation.y = -0.6
	look(p, pl.global_position)
	await wait(0.5)
	await shot("plane")
	pl.queue_free()
	# дым
	var n := Node3D.new()
	scene.add_child(n)
	n.global_position = Vector3(65, BuildEnv.water_level(), 10)
	SupplyFx.smoke_column(n, SupplyModels.TIER_COLORS[0])
	p.global_position = Vector3(30, BuildEnv.height_at(30, 0) + 0.1, 0)
	look(p, n.global_position + Vector3.UP * 14.0)
	await wait(10.0)
	await shot("smoke")
