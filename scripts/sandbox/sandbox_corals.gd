class_name SandboxCorals
extends RefCounted
## Полигон, зона «Пак моделей» — кораллы по референсу пользователя (CoralPack):
##  * на суше: два ряда «витрин» — все виды и варианты на песке, подписи «вид · треугольники LOD0/LOD1»;
##  * под водой: коралловый сад (все виды вперемешку, как на рифе) и точка телепорта.

const P := preload("res://scripts/sandbox/sandbox_props.gd")


static func _all() -> Array:
	var out: Array = []
	for t in CoralPack.TYPES.keys():
		for v in CoralPack.variants(t):
			out.append([t, v])
	return out


static func build(zones: SandboxZones, root: Node3D, c: Vector2) -> void:
	if not CoralPack.available():
		return
	var items := _all()
	var per_row := int(ceil(items.size() / 2.0))
	var step := 3.4
	var x0 := c.x - 10.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in items.size():
		var t: StringName = items[i][0]
		var v: int = items[i][1]
		var row := i / per_row
		var x := x0 + (i % per_row) * step
		var z := c.y + 22.0 + row * 4.4
		var g := P.ground(x, z)
		var m0 := CoralPack.mesh(t, v, 0)
		var mi := MeshInstance3D.new()
		mi.name = "Coral_%s_%d" % [t, v]
		mi.mesh = m0
		mi.material_override = CoralPack.material(t, -1000.0, 0)
		root.add_child(mi)
		var aabb := m0.get_aabb()
		var big := maxf(aabb.size.x, aabb.size.z)
		var k := clampf(2.4 / maxf(big, 0.01), 0.4, 3.0)   # на витрине — примерно одного размера
		mi.scale = Vector3.ONE * k
		mi.global_position = Vector3(x, g + 0.02, z)
		mi.rotation.y = rng.randf() * TAU
		var tr0 := CoralPack.tri_count(m0)
		var tr1 := CoralPack.tri_count(CoralPack.mesh(t, v, 1))
		var name_: String = String(CoralPack.TYPES[t]["name"])
		var top := g + aabb.size.y * k + 0.5
		P.label(root, Vector3(x, top, z), "%s%s\n%d / %d треуг." % [name_, "" if CoralPack.variants(t) == 1 else " · %d" % (v + 1), tr0, tr1], 20, P.SIGN_COLOR, 26.0)
	var mid_x := x0 + (per_row - 1) * step * 0.5
	zones._point(&"pack_corals", "Пак: кораллы (витрины)",
		Vector3(mid_x, P.ground(mid_x, c.y + 36.0) + 5.0, c.y + 36.0), Vector3(mid_x, P.ground(mid_x, c.y + 24.0) + 0.4, c.y + 24.0))


## Коралловый сад под водой: все виды вперемешку на мелководье 2–6 м.
static func build_sea(zones: SandboxZones, root: Node3D) -> void:
	var w := zones.world
	if w == null or not CoralPack.available():
		return
	var I: Dictionary = w.arch.islands[0]
	var cc: Vector2 = I.center
	var spot := Vector2.INF
	for k in 30:
		var dir := Vector2.from_angle(-PI * 0.5 + 1.2 + k * 0.06)
		for st in range(20, 300, 2):
			var q := cc + dir * float(st)
			var gh := P.ground(q.x, q.y)
			if gh < -2.5 and gh > -5.5:
				spot = q
				break
		if spot.x < INF:
			break
	if spot.x == INF:
		return
	var items := _all()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var garden := Node3D.new()
	garden.name = "CoralGarden"
	root.add_child(garden)
	# по виду — один MultiMesh (как на рифе)
	var by_key: Dictionary = {}
	for n in 140:
		var it: Array = items[rng.randi() % items.size()]
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 9.0
		var x := spot.x + cos(a) * r
		var z := spot.y + sin(a) * r
		var g := P.ground(x, z)
		if g > -0.8:
			continue
		var d: Dictionary = CoralPack.TYPES[it[0]]
		var s := rng.randf_range(float(d.smin), float(d.smax))
		var key := "%s|%d" % [it[0], it[1]]
		if not by_key.has(key):
			by_key[key] = []
		(by_key[key] as Array).append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, g - 0.04 * s, z)),
			CoralPack.pick_tint(it[0], rng)])
	for key in by_key.keys():
		var parts: PackedStringArray = (key as String).split("|")
		var t := StringName(parts[0])
		var v := int(parts[1])
		var arr: Array = by_key[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.use_colors = true
		mm.mesh = CoralPack.mesh(t, v, 0)
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i][0])
			mm.set_instance_custom_data(i, arr[i][1])
			mm.set_instance_color(i, Color(1, 1, 1, 1))
		var mi := MultiMeshInstance3D.new()
		mi.name = "Garden_" + String(key).replace("|", "_")
		mi.multimesh = mm
		mi.material_override = CoralPack.material(t, 0.0, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		garden.add_child(mi)
	var gy := P.ground(spot.x, spot.y)
	var back := (spot - cc).normalized()
	zones._point(&"pack_corals_reef", "Пак: кораллы (риф под водой)",
		Vector3(spot.x - back.x * 8.0, minf(gy + 2.6, -1.2), spot.y - back.y * 8.0), Vector3(spot.x, gy + 0.6, spot.y))
	P.label(root, Vector3(spot.x - back.x * 8.0, 2.4, spot.y - back.y * 8.0), "Коралловый сад · нырните", 34, P.SIGN_COLOR, 60.0)
