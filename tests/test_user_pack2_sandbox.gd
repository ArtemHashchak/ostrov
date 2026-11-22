extends TestCase
## Пак №2 на полигоне «Пак моделей»: игуана и варан (загоны), стайка крыланов, ряд валунов
## (камень пользователя) рядом с прежними polyhaven. Скриншоты в каждой точке.

var sb: Sandbox

func _init() -> void:
	scene_path = "res://scenes/sandbox/sandbox.tscn"
	timeout_sec = 2600.0

func run() -> void:
	sb = scene as Sandbox
	var t0 := Time.get_ticks_msec()
	while not sb.is_built and Time.get_ticks_msec() - t0 < 1500000:
		await wait(0.5)
	check(sb.is_built, "полигон собран")
	if not sb.is_built:
		return
	var z := sb.zones
	# игуана и варан — модели пака №3 с клипами автора (SandboxLand2), если они в проекте
	var new_liz := UserClipRig.available(&"iguana")
	var ids: Array = [&"pack3_iguana_green", &"pack3_varan_komodo"] if new_liz else [&"pack_iguana", &"pack_monitor"]
	for id in ids + [&"pack_bat", &"pack_rocks"]:
		check(z.points.has(id), "есть точка перемещения: %s" % id)
		if not z.points.has(id):
			continue
		if id == &"pack_bat":
			var f := get_tree().get_first_node_in_group(&"fauna")
			if f:
				f.set(&"force_night_birds", true)
		sb.panel.go(id)
		await wait(2.5)
		await shot(String(id))
	# в загонах — модели пользователя
	var liz := get_tree().root.find_children("UserLizard", "", true, false)
	if new_liz:
		liz = get_tree().root.find_children("iguana_green", "", true, false) + get_tree().root.find_children("varan_komodo", "", true, false)
	check(liz.size() >= 2, "в загонах ящерицы пользователя (%d)" % liz.size())
	var rocks := 0
	for mi in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override
		if m is ShaderMaterial and (m as ShaderMaterial).shader and (m as ShaderMaterial).shader.resource_path.ends_with("user_rock.gdshader"):
			rocks += 1
	check(rocks >= 6, "валуны пака с камнем пользователя (%d)" % rocks)
