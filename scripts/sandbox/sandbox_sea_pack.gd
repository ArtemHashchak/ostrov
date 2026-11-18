class_name SandboxSeaPack
extends RefCounted
## Полигон, зона «Пак моделей» — морская часть пака пользователя:
##  * на суше: ряд «витрин» — каждая особь плавает на месте тем же шейдером и анимацией, что в море
##    (рыбы — волна по телу и хвост, осьминог/кальмар — щупальца и рывок мантии, кальмар светится);
##    подписи «до → после» треугольников;
##  * стол с ракушками (подбираемые), вешало с сушёной рыбой;
##  * под водой у пирса: группы всех видов с маршрутами (как в живом море) и точка телепорта.

const P := preload("res://scripts/sandbox/sandbox_props.gd")


static func build(zones: SandboxZones, root: Node3D, c: Vector2) -> void:
	var rep := _report()
	var list := UserSeaPack.species_list()
	# --- витрины: ряд вдоль z = c.y − 4
	var x0 := c.x - 14.0
	var z0 := c.y - 4.0
	var step := 4.2
	for i in list.size():
		var d: Dictionary = list[i]
		var x := x0 + i * step
		var g := P.ground(x, z0)
		var L := float(d.get("length", 0.4))
		var big := L > 2.0
		# мелкие рыбы на витрине крупнее (×3), акула — мельче, чтобы ряд читался
		var k_show := 3.0 if L < 0.5 else (1.3 if L < 1.5 else 0.5)
		var h := 1.1
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.1
		cm.bottom_radius = 0.18
		cm.height = h
		post.mesh = cm
		post.material_override = P._post_mat()
		root.add_child(post)
		post.global_position = Vector3(x, g + h * 0.5, z0)
		var top := g + h + 0.15 + L * k_show * 0.5
		var ex := UserSeaPack.exhibit(d)
		if ex:
			root.add_child(ex)
			ex.global_position = Vector3(x, top, z0)
			ex.rotation.y = PI * 0.5   # боком к дорожке
			ex.scale = Vector3.ONE * k_show
		var key := _report_key(String(d.get("mesh", "")))
		var r: Dictionary = rep.get(key, {})
		var orig := int(r.get("orig_tris", r.get("before_tris", 0)))
		var scale_note := "" if is_equal_approx(k_show, 1.0) else ("  (на витрине ×%s)" % str(snappedf(k_show, 0.1)))
		P.label(root, Vector3(x, top + L * k_show * 0.5 + 0.45, z0), "%s\n%s → %s треуг.%s\n%s" % [String(d.get("name", d.get("id"))),
			_n(orig), _n(r.get("after_tris")), scale_note, _anim_text(String(d.get("anim", "fish")))], 22, P.SIGN_COLOR, 30.0)
	zones._point(&"pack_sea_row", "Пак: морская живность (витрины)",
		Vector3(x0 + list.size() * step * 0.5 - step * 0.5, P.ground(c.x, z0 + 7.0) + 1.7, z0 + 7.0),
		Vector3(x0 + list.size() * step * 0.5 - step * 0.5, P.ground(c.x, z0) + 1.5, z0))
	# --- ракушки на столе (подбираются) и сушёная рыба на вешале
	var tx := c.x - 14.0
	var tz := c.y + 13.0
	P.table(root, tx, tz, 2.4, 0.0, 0.9)
	var gt := P.ground(tx, tz)
	for k in 5:
		var pk := ItemPickup.spawn(root, Vector3(tx - 0.9 + k * 0.45, gt + 1.05, tz), [{"id": &"seashell", "n": 1}])
		if pk:
			pk.freeze = true
	var r_sh: Dictionary = rep.get("item_shell_junonia", {})
	P.tag(root, tx, tz + 1.0, "Ракушка (предмет, лежит на пляжах)\n%s → %s треуг. · E — подобрать" % [_n(r_sh.get("before_tris")), _n(r_sh.get("after_tris"))], 1.8, 25.0)
	if ResourceLoader.exists(UserSeaPack.DRIED_FISH):
		var df := (load(UserSeaPack.DRIED_FISH) as PackedScene).instantiate() as Node3D
		root.add_child(df)
		var dx := tx + 4.0
		df.global_position = Vector3(dx, P.ground(dx, tz) + 0.75, tz)
		var r_df: Dictionary = rep.get("item_dried_fish", {})
		P.tag(root, dx, tz + 1.0, "Сушёная рыба на вешале (декор у коптильни)\n%s → %s треуг." % [_n(r_df.get("orig_tris", r_df.get("before_tris"))), _n(r_df.get("after_tris"))], 2.4, 25.0)


## Под водой у пирса: по группе каждого вида, плавают по маршрутам.
static func build_sea(zones: SandboxZones, root: Node3D) -> void:
	var w := zones.world
	if w == null:
		return
	var I: Dictionary = w.arch.islands[0]
	var cc: Vector2 = I.center
	var dir := Vector2.from_angle(-PI * 0.5 + 0.45)
	var spot := Vector2.INF
	for st in range(30, 300, 2):
		var q := cc + dir * float(st)
		if P.ground(q.x, q.y) < -5.0:
			spot = q
			break
	if spot.x == INF:
		return
	var list := UserSeaPack.species_list()
	var gy := P.ground(spot.x, spot.y)
	for i in list.size():
		var d: Dictionary = list[i]
		var mesh := UserSeaPack.species_mesh(d)
		if mesh == null:
			continue
		var sch: Array = d.get("school", [1, 1])
		var n := clampi(int(sch[1]), 1, 10)
		var big := float(d.get("length", 0.4)) > 2.0
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = n
		var rng := RandomNumberGenerator.new()
		rng.seed = 900 + i
		var spread := float(d.get("length", 0.4)) * 2.5
		for k in n:
			var off := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.5), rng.randf_range(-1, 1)) * spread
			mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, off))
			mm.set_instance_custom_data(k, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
		var mi := MultiMeshInstance3D.new()
		mi.name = "PackSea_" + String(d.get("id"))
		mi.multimesh = mm
		var dd := d.duplicate()
		dd["roam"] = minf(float(d.get("roam", 6.0)), 9.0 if not big else 16.0)
		mi.material_override = UserSeaPack.species_material(dd, false)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ext := float(dd.roam) + spread + 3.0
		mi.custom_aabb = AABB(Vector3(-ext, -4.0, -ext), Vector3(ext * 2.0, 8.0, ext * 2.0))
		root.add_child(mi)
		var a := float(i) / float(maxi(list.size(), 1)) * TAU
		var depth := -gy
		var y := gy + clampf(depth * 0.45, 1.2, 4.0)
		if String(d.get("anim")) == "octopus" and not String(d.id).begins_with("squid"):
			y = gy + 0.9   # осьминог у дна
		mi.global_position = Vector3(spot.x + cos(a) * 4.0, y, spot.y + sin(a) * 4.0)
	zones._point(&"pack_sea", "Пак: морская живность (под водой)",
		Vector3(spot.x - dir.x * 9.0, clampf(gy + 2.2, gy + 1.0, -1.5), spot.y - dir.y * 9.0), Vector3(spot.x, gy + 1.8, spot.y))
	P.label(root, Vector3(spot.x - dir.x * 8.0, 2.4, spot.y - dir.y * 8.0), "Морская живность из пака · нырните", 34, P.SIGN_COLOR, 60.0)


static func _anim_text(a: String) -> String:
	match a:
		"octopus":
			return "щупальца волной, рывок мантии"
		"fish":
			return "волна по телу, хвост"
	return a


static func _report_key(mesh_path: String) -> String:
	return mesh_path.get_file().get_basename()


static func _report() -> Dictionary:
	var out := {}
	var path := "res://assets/user_pack/report.json"
	if not FileAccess.file_exists(path):
		return out
	var arr: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if arr is Array:
		for r: Variant in arr:
			out[String((r as Dictionary).get("name", ""))] = r
	return out


static func _n(v: Variant) -> String:
	if v == null:
		return "?"
	var i := int(v)
	return str(i) if i < 1000 else ("%.1fk" % (i / 1000.0) if i < 1000000 else "%.2fM" % (i / 1000000.0))
