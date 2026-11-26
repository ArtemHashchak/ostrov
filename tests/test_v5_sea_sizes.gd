extends TestCase
## Настоящий размер морских моделей в игре (агент G): существо создаётся так же, как
## в море (SeaSkel.create с длиной из ocean_roster / UserSeaActor с масштабом пака),
## и мерится по костям скелета в текущей позе (скинованные меши) или по мешам.
## Длина должна совпадать с длиной вида из ocean_roster (±20 %).

const SKEL := {"tuna": 1.4, "giant_grouper": 1.7, "dolphin": 2.6, "manta": 3.4}

func _init() -> void:
	scene_path = ""

func run() -> void:
	var root := Node3D.new()
	get_tree().root.add_child(root)
	for id: String in SKEL:
		if not SeaSkel.has(id):
			check(false, "%s: нет в SeaSkel" % id)
			continue
		var L: float = SKEL[id]
		var s := SeaSkel.create(id, L, 3)
		root.add_child(s)
		await wait_frames(4)
		var m := _measure(s)
		print("[size] %s: в игре %.2f м (кости %.2f, меши %.2f), вид %.2f м" % [id, m.x, m.y, m.z, L])
		check(absf(m.x - L) < L * 0.2, "%s: длина в игре %.2f ≈ %.2f м" % [id, m.x, L])
		s.queue_free()
	# паки (не скелет): пиранья 0,3 м, горбатый кит 13 м — как в SeaCritter (масштаб = длина вида / длина пака)
	for pair: Array in [["piranha_user", 0.3], ["whale_humpback_user", 13.0]]:
		var e: Dictionary = OceanRoster.pack_entry(String(pair[0]))
		if e.is_empty():
			check(false, "%s: нет записи пака" % pair[0])
			continue
		var a := UserSeaActor.new()
		a.setup(e, null, Vector3.ZERO, 5)
		a.pinned = true
		root.add_child(a)
		var k := float(pair[1]) / maxf(float(e.get("length", pair[1])), 0.01)
		a.scale = Vector3.ONE * k
		await wait_frames(3)
		var m := _measure(a)
		print("[size] %s: в игре %.2f м (меши), вид %.2f м" % [pair[0], m.z, float(pair[1])])
		check(absf(m.z - float(pair[1])) < float(pair[1]) * 0.2, "%s: длина в игре %.2f ≈ %.2f м" % [pair[0], m.z, float(pair[1])])
		a.queue_free()
	root.queue_free()

## x — итоговая длина (по костям, если есть скелет, иначе по мешам), y — по костям, z — по мешам.
func _measure(n: Node3D) -> Vector3:
	var bone_box := AABB()
	var have_b := false
	for sk: Skeleton3D in n.find_children("*", "Skeleton3D", true, false):
		for b in sk.get_bone_count():
			var p := sk.global_transform * sk.get_bone_global_pose(b).origin
			if not have_b:
				bone_box = AABB(p, Vector3.ZERO)
				have_b = true
			else:
				bone_box = bone_box.expand(p)
	var mesh_box := AABB()
	var have_m := false
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible or mi.mesh == null:
			continue
		var a := mi.global_transform * mi.get_aabb()
		mesh_box = a if not have_m else mesh_box.merge(a)
		have_m = true
	var lb := maxf(maxf(bone_box.size.x, bone_box.size.z), bone_box.size.y) if have_b else 0.0
	var lm := maxf(maxf(mesh_box.size.x, mesh_box.size.z), mesh_box.size.y) if have_m else 0.0
	# кости не доходят до кончика морды и хвостового плавника — запас ~15 %
	var l := lb * 1.15 if have_b else lm
	return Vector3(l, lb, lm)
