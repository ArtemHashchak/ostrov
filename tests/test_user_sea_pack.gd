extends TestCase
## Морской пак пользователя: виды из assets/user_pack/sea_species_user_sea.json попали в реестр
## (свой шейдер, анимация щупалец/хвоста), меши в бюджете, ракушка — предмет с моделью из пака,
## витрины и подводные группы на полигоне. Скриншоты: витрины, крупно осьминог/кальмар, под водой, ракушки.

var sb: Sandbox

func _init() -> void:
	scene_path = "res://scenes/sandbox/sandbox.tscn"
	timeout_sec = 3500.0

func run() -> void:
	Engine.max_physics_steps_per_frame = 30
	SeaSpecies.reload()
	var budgets := {"small": 1500, "medium": 5000, "large": 12000}
	var ids := ["discus_user", "redfish_user", "spotted_user", "shark_pack8_user", "octopus_user", "squid_user"]
	for id in ids:
		var d := SeaSpecies.get_species(id)
		check(not d.is_empty(), "вид в реестре: %s" % id)
		if d.is_empty():
			continue
		var m := load(String(d.mesh)) as Mesh
		check(m != null, "%s: меш загружается" % id)
		if m:
			var tris := (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			check(m.get_surface_count() == 1, "%s: одна поверхность (атлас)" % id)
			check(tris <= int(budgets[String(d.category)]), "%s: %d треуг. ≤ бюджета %s" % [id, tris, d.category])
		check(ResourceLoader.exists(String(d.shader)), "%s: шейдер пака" % id)
	UserSeaPack.register_items()
	check(Items.get_item(&"seashell") != null, "предмет «Ракушка» зарегистрирован")
	var held := HeldModels.build(&"seashell")
	check(held.find_children("*", "MeshInstance3D", true, false).size() > 0, "ракушка в руке — модель из пака")
	held.free()
	sb = scene as Sandbox
	var t0 := Time.get_ticks_msec()
	while not sb.is_built and Time.get_ticks_msec() - t0 < 1200000:
		await wait(0.5)
	check(sb.is_built, "полигон собран")
	if not sb.is_built:
		return
	var z := sb.zones
	for id in [&"pack_sea_row", &"pack_sea"]:
		check(z.points.has(id), "есть точка перемещения: %s" % id)
	var groups := 0
	for n in get_tree().root.find_children("PackSea_*", "MultiMeshInstance3D", true, false):
		groups += 1
	check(groups == ids.size(), "под водой групп видов пака: %d" % groups)
	sb.panel.go(&"pack_sea_row")
	await wait(3.0)
	await shot("01_row")
	# крупно: осьминог и кальмар (5-я и 6-я витрины)
	var c: Vector2 = SandboxZones.ZONES[&"pack"].c
	var x0 := c.x - 14.0
	var z0 := c.y - 4.0
	for k in [4, 0, 1]:
		var x: float = x0 + float(k) * 4.2
		var g := SandboxProps.ground(x, z0)
		sb.cheats.teleport(Vector3(x, SandboxProps.ground(x, z0 + 3.2) + 0.1, z0 + 3.2), Vector3(x, g + 1.6, z0))
		await wait(1.2)
		await shot("02_exhibit_%d_a" % k)
		await wait(0.7)
		await shot("02_exhibit_%d_b" % k)
	# ракушки и сушёная рыба
	sb.cheats.teleport(Vector3(x0 + 2.0, SandboxProps.ground(x0 + 2.0, c.y + 17.5) + 0.2, c.y + 17.5), Vector3(x0 + 2.0, SandboxProps.ground(x0, c.y + 13.0) + 1.0, c.y + 13.0))
	await wait(1.5)
	await shot("03_shells_driedfish")
	# под водой
	sb.cheats.set_fly(true)
	sb.panel.go(&"pack_sea")
	await wait(3.0)
	await shot("04_underwater_a")
	await wait(2.0)
	await shot("04_underwater_b")
	# живые особи вблизи (UserSeaActor): осьминог на дне, кальмары, рыбы пака
	var live := get_tree().root.find_child("PackSeaLive", true, false) as UserSeaActors
	check(live != null and live.actors.size() >= 8, "живые особи пака у пирса: %d" % (live.actors.size() if live else 0))
	if live:
		for a: UserSeaActor in live.actors:
			if a.kind == "octopus" or a.kind == "squid":
				var p := a.global_position
				sb.cheats.teleport(p + Vector3(1.6, 0.8, 1.6), p + Vector3(0, 0.15, 0))
				await wait(1.5)
				await shot("05_live_%s" % a.kind)
	sb.cheats.set_fly(false)
